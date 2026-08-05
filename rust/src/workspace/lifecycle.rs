//! Note and Directory lifecycle: create, rename, move and delete
//! (CAP-LIFE-01 .. CAP-LIFE-06).
//!
//! # Why this is one operation and not four
//!
//! OKF identity is positional (ADR-004): a Note's concept id *is* its
//! bundle-relative path with `.md` removed. Renaming or moving a Note
//! therefore changes its identity, and every Link that points at it names a
//! concept that has ceased to exist. `architecture/risks.md` risk 8 states the
//! consequence precisely — a partial rewrite leaves dangling Links that are
//! indistinguishable from deliberate ghost Links, so the graph degrades
//! silently rather than failing loudly.
//!
//! So a rename touches, in one operation that either completes or changes
//! nothing:
//!
//! 1. the renamed Note's **file** (frontmatter `title`, filename) and any
//!    **self-Link** it holds;
//! 2. the **bytes of every source Note** that links to it;
//! 3. its **index rows**, the source Notes' index rows, and every inbound
//!    `links` edge;
//! 4. every affected Note's **`drafts` row**, which carries no foreign key and
//!    so neither cascades nor re-keys itself (`data-models/schema.sql`);
//! 5. every affected Note's **open session** — working source, span map and
//!    recorded revision — through
//!    [`persist::carry_session_forward`](super::persist::carry_session_forward).
//!
//! Risk 8 is explicit that (1)–(3) alone are *necessary and not sufficient*:
//! an open source Note's next idle write copies its buffer verbatim over the
//! rewritten file, and an unflushed draft does the same one session later,
//! because `open_note` parses the draft in preference to disk. Either way the
//! rename is reverted from a direction file-level atomicity cannot see.
//!
//! # How "atomic or fail" is achieved across two stores
//!
//! The bundle and the index are two storage forms and there is no transaction
//! spanning them. The order below is what makes the composite operation
//! recoverable rather than merely usually-correct:
//!
//! - **Everything is planned before anything is written.** Reads, parses,
//!   rewrites and validation all happen first, so the overwhelming majority of
//!   failures (an occupied path, a reserved name, a Link that cannot be
//!   rewritten) occur before a single byte moves.
//! - **The filesystem moves under a journal.** Every write records the bytes
//!   it replaced and every rename records its inverse, so a failure part-way
//!   through the sweep — the case the fourth acceptance criterion names — is
//!   undone before the error is returned.
//! - **The index moves in one transaction**, which is rolled back on error,
//!   and the filesystem journal is unwound behind it.
//! - **The commit is last**, so version history never records a state the
//!   index disagrees with.
//! - **Sessions are carried forward last of all**, because they are in-memory
//!   and cannot fail in a way that leaves the two stores inconsistent.
//!
//! Deletion inverts nothing, so it takes the same shape by a different route:
//! the file is *renamed into a dot-prefixed trash entry inside the bundle*
//! rather than unlinked, which makes "undo the filesystem step" a rename again.
//! The trash entry is removed only once the index transaction has committed.
//! (`index::scan::walk_bundle` skips dot-prefixed entries, so a trash entry
//! that outlives a crash is invisible to the indexer rather than a phantom
//! Note.)

use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use rusqlite::{Connection, OptionalExtension};

use crate::draft::NoteState;
use crate::error::AppError;
use crate::index::{self, content_hash};
use crate::markdown::{parse_note, ParsedNote};
use crate::okf::{concept_id_to_path, is_reserved_title};

use super::links_rewrite::{self, Remap};
use super::persist::{self, Workspace};

/// One Note whose concept id changed as a side effect of an operation on its
/// containing Directory (`contracts/ffi_api.rs`).
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IdRemap {
    pub old_id: String,
    pub new_id: String,
}

/// What a lifecycle operation changed, **beyond the Note it was invoked on**.
///
/// The two lists are disjoint by construction and the caller acts differently
/// on each:
///
/// - `remapped` — Notes whose **concept id** changed. An open one is holding a
///   dead identifier and must re-anchor. Empty for `rename_note` and
///   `move_note`, whose returned `NoteState` already carries the new id; it is
///   `rename_directory` that remaps Notes the caller did not name.
/// - `rewritten` — Notes whose **bytes** changed because an inbound Link in
///   them was rewritten, and whose ids did *not* change. Nothing about them
///   looks wrong, which is the problem: an open one still holds an
///   `InlineElement::Link` carrying the old `target_id`, and following it would
///   run CAP-GRAPH-04's create-on-follow into recreating the concept the rename
///   just removed.
#[frb]
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LifecycleEffects {
    pub remapped: Vec<IdRemap>,
    pub rewritten: Vec<String>,
}

// ---------------------------------------------------------------------------
// Notes
// ---------------------------------------------------------------------------

/// Creates a Note in `directory_path` (empty for the bundle root) with an
/// OKF-conformant frontmatter block, indexes it, **commits it**, and **opens
/// it** — the returned state is the state of an open Note, so the working
/// source, span map and recorded revision are all established before this
/// returns.
///
/// The filename is the title verbatim plus `.md`
/// (`data-models/okf-bundle.md`), because CAP-GRAPH-04's create-on-follow has
/// to invert the derivation. A collision or a reserved filename returns
/// [`AppError::PathUnavailable`] and creates nothing.
///
/// **`directory_path` must already name a Directory**, and an unknown one
/// returns [`AppError::PathUnavailable`] rather than being created. The
/// contract is silent on the question and the two functions that take a
/// Directory disagreed about it: [`move_note`] refuses an unknown
/// destination, while this one used to `create_dir_all` the whole hierarchy.
/// The typo case is what settles it — one mistyped level in `SHEL-E005`'s
/// field silently produced a new Directory and filed the Note out of sight
/// inside it, with nothing to undo and no signal that anything unusual had
/// happened. Creating the Directory first, through [`create_directory`], is
/// the explicit route and the one that leaves the user in control of the
/// tree's shape. An empty `directory_path` is the bundle root and is
/// unaffected.
pub fn create_note(
    workspace: &Arc<Workspace>,
    directory_path: &str,
    title: &str,
) -> Result<NoteState, AppError> {
    validate_title(title)?;
    let directory = normalize_directory(directory_path)?;
    // The same call `move_note` makes, so both entry points onto a Directory
    // answer an unknown one identically — and so both go through the symlink
    // containment check it performs on the way.
    ensure_directory_exists(workspace, &directory)?;
    let new_id = join_id(&directory, title);
    let new_path = workspace.note_path(&new_id)?;
    ensure_path_available(workspace, &new_id, &new_path, None)?;

    let source = conformant_frontmatter(title);
    persist::atomic_write(&new_path, source.as_bytes())?;

    let indexed = index::derive_note(
        &new_id,
        &source,
        content_hash(source.as_bytes()),
        file_mtime(&new_path),
    );
    let written = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            index::incremental::write_note_rows(tx, workspace.id(), &indexed)?;
            record_directories(tx, workspace.id(), &directory)
        })
    });
    if let Err(error) = written {
        // The file is the only thing worth undoing here. Two asymmetries are
        // left standing deliberately, because both are benign and repairing
        // either would cost more than it buys:
        //
        // - An on-disk folder `ensure_directory_exists` had to materialize for
        //   a Directory the index already knew about stays. It is not a level
        //   this call invented — the Directory existed before it ran — and an
        //   empty folder holds no user content, is invisible to
        //   `walk_bundle`'s Note scan, and is not tracked by Git.
        // - Nothing rolls back if `open_note` below fails *after* the index
        //   transaction committed. That leaves the Note fully created and
        //   correctly indexed but not open, which is a state the user can act
        //   on — the Note is in the tree and opening it is one click — whereas
        //   deleting a Note that was successfully created because the *open*
        //   failed would discard a real result over a recoverable one.
        let _ = std::fs::remove_file(&new_path);
        return Err(error);
    }

    // The Note enters version history **here**, not at the first close.
    //
    // Tier 3's gate is `session_edited`, which is false for a Note nobody has
    // typed into — so without this a Note that was created and navigated away
    // from, or one whose idle write landed just before a crash, was a file in
    // the bundle that no commit covered. `delete_note` then made the promise
    // CAP-LIFE-04 states ("recoverable from local version history") without
    // being able to keep it: `commit_paths` removes a path `HEAD` never held,
    // sees an unchanged tree, and commits nothing, so the deleted content
    // existed in no commit anywhere. Its three lifecycle siblings — rename,
    // move and delete — all commit; this one was the exception.
    //
    // No duplicate Create follows: `NoteSession::commit_message` asks
    // `path_in_head`, which now answers yes, so the session's own close commits
    // an Update.
    let relative = concept_id_to_path(&new_id);
    let subject = format!("Create {title}");
    let committed = crate::git::operations::commit_paths(
        workspace.root(),
        &format!("{subject}\n\n{relative}\n"),
        std::slice::from_ref(&relative),
    );
    if let Err(error) = committed {
        // The established stage-failure shape: the file is written and the
        // index agrees, so this is "the operation happened and version history
        // does not record it" rather than "the create failed". Nothing is rolled
        // back for the same reason `delete_note` rolls nothing back at this
        // point — the two stores have already settled.
        return Err(commit_stage_failure(&subject, error, &[]));
    }

    let (_, state) = persist::open_note(workspace, &new_id)?;
    Ok(state)
}

/// Deletes a Note and commits the deletion, so it stays recoverable from local
/// version history (CAP-LIFE-04).
///
/// Two cleanups the `notes` row's own cascade does not perform, both in the
/// same transaction: the `drafts` row, which carries no foreign key at all, and
/// the `notes_fts` row, which must be deleted **before** the `notes` row —
/// deleting `notes` cascades `fts_mapping` away, and that mapping is the only
/// pointer to the FTS rowid, so afterwards the deleted Note's full text stays
/// searchable in the encrypted index, permanently and undeletably
/// (`data-models/schema.sql`). [`index::remove_note_rows`] is what enforces the
/// order.
///
/// Runs under the tier 2 write locks for the same reason a rename does: an idle
/// write already inside its `atomic_write` would otherwise land its temporary
/// file's rename onto the path *after* the deletion moved it aside, resurrecting
/// the file against an index that has already forgotten it.
pub fn delete_note(workspace: &Arc<Workspace>, note_id: &str) -> Result<(), AppError> {
    persist::with_write_locks(workspace, || delete_note_locked(workspace, note_id))
}

fn delete_note_locked(workspace: &Arc<Workspace>, note_id: &str) -> Result<(), AppError> {
    let path = workspace.note_path(note_id)?;
    let title = indexed_title(workspace, note_id)?;
    if !path.exists() && title.is_none() {
        return Err(AppError::NotFound(format!(
            "no Note with concept id {note_id}"
        )));
    }
    // A Note is a file. Nothing stops a bundle from holding a *directory*
    // named `Archive.md` — a foreign tool's, or a user's — and without this
    // the journal's trash-and-discard would remove it and everything beneath
    // it recursively, as a Note deletion, having committed a pathspec that
    // names every file under it as gone. `rename_directory` makes the mirror
    // check for the mirror reason; both report `NotFound`, because what the
    // caller named is not a thing this operation can act on.
    if path.exists() && !path.is_file() {
        return Err(AppError::NotFound(format!(
            "no Note with concept id {note_id}: {} is not a file",
            concept_id_to_path(note_id)
        )));
    }

    let mut journal = FileJournal::default();
    journal.trash(&path)?;

    let removed = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            index::remove_note_rows(tx, workspace.id(), note_id)?;
            clear_draft(tx, workspace.id(), note_id)
        })
    });
    if let Err(error) = removed {
        return Err(rolled_back(&mut journal, error));
    }

    let relative = concept_id_to_path(note_id);
    let display = title.unwrap_or_else(|| file_stem(note_id).to_string());
    let subject = format!("Delete {display}");
    let committed = crate::git::operations::commit_paths(
        workspace.root(),
        &format!("{subject}\n\n{relative}\n"),
        std::slice::from_ref(&relative),
    );

    // Settled before the commit error is propagated: the file is gone and the
    // index agrees, so the trash entry must go regardless of whether version
    // history recorded it. Leaving it parked would keep the deleted Note's full
    // content sitting untracked inside the bundle.
    journal.commit();
    // Retired for the same reason, and *before* the commit error is surfaced.
    // Propagating the commit failure first jumped over this, leaving a session
    // open over a Note that no longer exists in either store — and a session
    // that, closed normally, flushes its buffer and recreates the file the
    // deletion just removed.
    let discarded = persist::discard_session(workspace, note_id);
    if let Err(error) = committed {
        return Err(commit_stage_failure(&subject, error, &[]));
    }
    discarded
}

/// Renames a Note, rewriting its frontmatter `title`, its filename, and every
/// inbound Link that targets it (CAP-LIFE-02).
///
/// Because identity is positional this changes the Note's concept id, and the
/// returned state carries the new one. Returns [`AppError::PathUnavailable`] on
/// exactly the same terms as [`create_note`]: renaming is not a weaker check
/// than creating.
pub fn rename_note(
    workspace: &Arc<Workspace>,
    note_id: &str,
    new_title: &str,
) -> Result<(NoteState, LifecycleEffects), AppError> {
    validate_title(new_title)?;
    let old_path = workspace.note_path(note_id)?;
    if !old_path.is_file() {
        return Err(AppError::NotFound(format!(
            "no file on disk for concept id {note_id}"
        )));
    }
    let new_id = join_id(containing_dir(note_id), new_title);
    let new_path = workspace.note_path(&new_id)?;
    ensure_path_available(workspace, &new_id, &new_path, Some(&old_path))?;

    let mut remap = Remap::new();
    if new_id != note_id {
        remap.insert(note_id.to_string(), new_id.clone());
    }
    let plan = Reidentify {
        remap,
        invoked: Some(note_id.to_string()),
        retitled: Some((note_id.to_string(), new_title.to_string())),
        directory_rename: None,
        message: format!(
            "Rename {} to {new_title}\n\n{}\n",
            file_stem(note_id),
            concept_id_to_path(&new_id)
        ),
    };
    let effects = apply_reidentify(workspace, &plan)?;
    let state = settled_state(workspace, &new_id)?;
    Ok((state, effects))
}

/// Moves a Note to another Directory, rewriting every inbound Link
/// (CAP-LIFE-03). Changes the Note's id, as [`rename_note`] does.
///
/// The moved Note's own frontmatter is untouched — a move changes its location,
/// not its title — but a **self-Link is still rewritten**, because a self-Link
/// is an inbound Link like any other and a move that left it behind would point
/// it at the id the move just vacated.
pub fn move_note(
    workspace: &Arc<Workspace>,
    note_id: &str,
    new_directory_path: &str,
) -> Result<(NoteState, LifecycleEffects), AppError> {
    let old_path = workspace.note_path(note_id)?;
    if !old_path.is_file() {
        return Err(AppError::NotFound(format!(
            "no file on disk for concept id {note_id}"
        )));
    }
    let directory = normalize_directory(new_directory_path)?;
    ensure_directory_exists(workspace, &directory)?;

    let new_id = join_id(&directory, file_stem(note_id));
    let new_path = workspace.note_path(&new_id)?;
    ensure_path_available(workspace, &new_id, &new_path, Some(&old_path))?;

    let mut remap = Remap::new();
    if new_id != note_id {
        remap.insert(note_id.to_string(), new_id.clone());
    }
    let plan = Reidentify {
        remap,
        invoked: Some(note_id.to_string()),
        retitled: None,
        directory_rename: None,
        message: format!(
            "Move {} to {}\n\n{}\n",
            file_stem(note_id),
            if directory.is_empty() {
                "the bundle root"
            } else {
                &directory
            },
            concept_id_to_path(&new_id)
        ),
    };
    let effects = apply_reidentify(workspace, &plan)?;
    let state = settled_state(workspace, &new_id)?;
    Ok((state, effects))
}

// ---------------------------------------------------------------------------
// Directories
// ---------------------------------------------------------------------------

/// Creates a Directory, including intermediate levels (CAP-LIFE-05).
///
/// An empty Directory has no file to represent it, so `directories` is what
/// makes it exist as far as the tree is concerned; the on-disk directory is
/// created too, so a Note can be written into it and so the user sees it in a
/// file manager. Git tracks no empty directory, which is why this makes no
/// commit — the Directory enters version history with the first Note in it.
pub fn create_directory(workspace: &Arc<Workspace>, path: &str) -> Result<(), AppError> {
    let directory = normalize_directory(path)?;
    if directory.is_empty() {
        return Err(AppError::PathUnavailable(
            "the bundle root already exists and cannot be created".to_string(),
        ));
    }
    let absolute = directory_absolute(workspace, &directory)?;
    if absolute.is_file() {
        return Err(AppError::PathUnavailable(format!(
            "{directory} is already a file in this Workspace"
        )));
    }
    std::fs::create_dir_all(&absolute)
        .map_err(|e| AppError::IoError(format!("create {}: {e}", absolute.display())))?;
    workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            record_directories(tx, workspace.id(), &directory)
        })
    })
}

/// Renames a Directory, moving its contents and rewriting inbound Links to
/// every Note beneath it (CAP-LIFE-06).
///
/// Every Note in the subtree is remapped, and the Notes holding rewritten Links
/// are **not confined to that subtree** — anything anywhere in the bundle may
/// link into it, which is why [`LifecycleEffects`] carries both lists.
pub fn rename_directory(
    workspace: &Arc<Workspace>,
    path: &str,
    new_name: &str,
) -> Result<LifecycleEffects, AppError> {
    let directory = normalize_directory(path)?;
    if directory.is_empty() {
        return Err(AppError::PathUnavailable(
            "the bundle root cannot be renamed".to_string(),
        ));
    }
    validate_segment(new_name)?;
    let parent = containing_dir(&directory);
    let new_directory = join_id(parent, new_name);

    let old_absolute = directory_absolute(workspace, &directory)?;
    let new_absolute = directory_absolute(workspace, &new_directory)?;
    if !old_absolute.is_dir() {
        return Err(AppError::NotFound(format!(
            "no Directory at {directory} in this Workspace"
        )));
    }
    // The same escape [`ensure_path_available`] makes for a Note, and for the
    // same reason: `Notes` -> `notes` finds *its own directory* at the
    // destination on a case-insensitive filesystem, which macOS ships by
    // default and `data-models/okf-bundle.md` records under "Case sensitivity
    // follows the filesystem". A bare `exists()` therefore made a case-only
    // rename of a Directory impossible on one of this project's two shipping
    // platforms, while `rename_note` had allowed the Note equivalent all along.
    // Same-file identity — not a case-insensitive string comparison — is what
    // distinguishes it, so a genuine collision with a differently-cased sibling
    // that really is a second directory is still refused.
    if new_directory != directory
        && new_absolute.exists()
        && !is_same_file(&new_absolute, Some(&old_absolute))
    {
        return Err(AppError::PathUnavailable(format!(
            "{new_directory} already exists in this Workspace"
        )));
    }
    if new_directory == directory {
        return Ok(LifecycleEffects::default());
    }

    let prefix = format!("{directory}/");
    let contained =
        workspace.with_db(|conn| note_ids_with_prefix(conn, workspace.id(), &prefix))?;
    let remap: Remap = contained
        .iter()
        .map(|id| {
            let rest = id.strip_prefix(&prefix).unwrap_or(id);
            (id.clone(), format!("{new_directory}/{rest}"))
        })
        .collect();

    let plan = Reidentify {
        remap,
        // A Directory is not a Note, so every Note the rename moved is
        // "beyond" what the caller named and belongs in `remapped`.
        invoked: None,
        retitled: None,
        directory_rename: Some(DirectoryRename {
            old: directory.clone(),
            new: new_directory.clone(),
            old_absolute,
            new_absolute,
        }),
        message: format!("Rename directory {directory} to {new_directory}\n"),
    };
    apply_reidentify(workspace, &plan)
}

/// Deletes a Directory and everything beneath it, in one commit (CAP-LIFE-06),
/// returning the concept ids of every Note removed so a caller holding one open
/// can close it rather than discovering it is gone on next access.
///
/// The contract specifies a **recursive** delete, not an empty-only one — "and
/// everything beneath it" — so this does not refuse a populated Directory. What
/// makes that safe is the commit: every removed Note is recoverable from local
/// version history, exactly as a single [`delete_note`] is.
pub fn delete_directory(workspace: &Arc<Workspace>, path: &str) -> Result<Vec<String>, AppError> {
    persist::with_write_locks(workspace, || delete_directory_locked(workspace, path))
}

fn delete_directory_locked(
    workspace: &Arc<Workspace>,
    path: &str,
) -> Result<Vec<String>, AppError> {
    let directory = normalize_directory(path)?;
    if directory.is_empty() {
        return Err(AppError::PathUnavailable(
            "the bundle root cannot be deleted".to_string(),
        ));
    }
    let absolute = directory_absolute(workspace, &directory)?;
    let prefix = format!("{directory}/");
    let removed = workspace.with_db(|conn| note_ids_with_prefix(conn, workspace.id(), &prefix))?;
    if !absolute.exists() && removed.is_empty() {
        return Err(AppError::NotFound(format!(
            "no Directory at {directory} in this Workspace"
        )));
    }
    // The same guard `rename_directory` already makes, and for a sharper
    // reason. Pointed at a *file*, this trashed it, committed the deletion and
    // returned `Ok([])` — because `removed` is the Notes *under* the prefix and
    // a file has none — leaving the deleted Note's `notes` row and, worse, its
    // `notes_fts` text in the encrypted index with the `fts_mapping` row still
    // pointing at it. That is the stranded-encrypted-text hazard
    // `data-models/schema.sql` names, and it persists for the rest of the
    // session: nothing rebuilds the index until the next open.
    //
    // `exists()` rather than `is_dir()` outright, because a Directory whose
    // on-disk folder has vanished while its `notes` rows survive is a state this
    // call legitimately cleans up.
    if absolute.exists() && !absolute.is_dir() {
        return Err(AppError::NotFound(format!(
            "no Directory at {directory} in this Workspace: it is a file"
        )));
    }

    let mut journal = FileJournal::default();
    if absolute.exists() {
        journal.trash(&absolute)?;
    }

    let cleared = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            for note_id in &removed {
                index::remove_note_rows(tx, workspace.id(), note_id)?;
                clear_draft(tx, workspace.id(), note_id)?;
            }
            tx.execute(
                "DELETE FROM directories WHERE workspace_id = ?1 AND (id = ?2 OR id LIKE ?3 ESCAPE '\\')",
                rusqlite::params![workspace.id(), directory, format!("{}/%", like_escape(&directory))],
            )?;
            Ok(())
        })
    });
    if let Err(error) = cleared {
        return Err(rolled_back(&mut journal, error));
    }

    // The pathspec is the **Directory itself**, not the list of Notes removed.
    //
    // The trash step carried away everything beneath it, and a bundle legitimately
    // holds files that are not Notes: an attachment (CAP-EDIT-06 references
    // images by bundle-absolute path), a foreign tool's `index.md`, anything
    // else an author put there. Committing only the `notes` rows would leave
    // every one of those as a deletion Git knows about but was never told to
    // record — a permanently dirty worktree, and one that the next broad commit
    // or sync resolves at a time nobody chose.
    let directory_pathspec = vec![directory.clone()];
    let subject = format!("Delete directory {directory}");
    let committed = crate::git::operations::commit_paths(
        workspace.root(),
        &format!("{subject}\n"),
        &directory_pathspec,
    );

    journal.commit();
    // Every session is retired before the commit error is surfaced, for the
    // reason `delete_note_locked` gives: the Notes are gone from both stores
    // whether or not version history recorded it, and a session left open over
    // one recreates its file on the next flush. The first failure is held and
    // returned only if the commit itself succeeded — the commit error is the
    // more informative of the two.
    let mut discarded = Ok(());
    for note_id in &removed {
        let outcome = persist::discard_session(workspace, note_id);
        if discarded.is_ok() {
            discarded = outcome;
        }
    }
    if let Err(error) = committed {
        return Err(commit_stage_failure(&subject, error, &[]));
    }
    discarded?;
    Ok(removed)
}

// ---------------------------------------------------------------------------
// The shared re-identification path
// ---------------------------------------------------------------------------

/// One re-identification: which concept ids move, whether the invoked Note is
/// also being retitled, and whether a single directory rename carries the files.
struct Reidentify {
    remap: Remap,
    /// The Note the operation was invoked on, when it was invoked on one.
    /// [`LifecycleEffects`] reports what changed *beyond* it — the caller
    /// already holds its new identity in the returned `NoteState` — so it is
    /// excluded from both lists.
    invoked: Option<String>,
    /// `(note_id, new_title)` when the operation rewrites a frontmatter
    /// `title` — a `rename_note` and nothing else.
    retitled: Option<(String, String)>,
    /// Present when one `rename` moves the whole subtree, rather than one
    /// rename per Note.
    directory_rename: Option<DirectoryRename>,
    message: String,
}

/// A Directory moving as a unit, in both the forms the operation needs it:
/// bundle-relative for the `directories` rows, absolute for the one `rename`.
struct DirectoryRename {
    old: String,
    new: String,
    old_absolute: PathBuf,
    new_absolute: PathBuf,
}

/// One Note the operation touches, planned in full before anything is written.
struct Affected {
    old_id: String,
    new_id: String,
    old_path: PathBuf,
    new_path: PathBuf,
    /// Whether `old_path` held a file when the operation was planned.
    ///
    /// `false` only for a Note that reached the sweep through its **draft row
    /// or its open session** while its file was gone — the population
    /// `persist::open_note`'s recovery branch produces. Everything about such a
    /// candidate is in-memory or in the `drafts` table: nothing is written to
    /// disk for it, nothing is staged for it, and no index row is derived from
    /// it, because there are no bytes to derive one from and inventing an empty
    /// one would blank the Note's title, text and edges (or conjure a row for a
    /// Note the index never had).
    on_disk: bool,
    /// Disk bytes after the operation, when they change.
    new_file: Option<String>,
    /// The working source of the Note's open session after the operation, when
    /// it has one and the rewrite applies to it.
    new_buffer: Option<String>,
    /// `drafts.raw_markdown` after the operation, when a row exists.
    new_draft: Option<String>,
    /// The OCC baseline the session must record afterwards: the hash of the
    /// file as it now is.
    revision: String,
}

/// Runs the whole re-identification under the tier 2 write lock of every open
/// Note in this Workspace.
///
/// A lifecycle rewrite reads a Note's bytes, computes new ones, and writes them
/// back — which is a tier 2 write with a longer read-to-write gap than the idle
/// timer's own. Without the lock, a timer firing inside that gap writes its
/// buffer to disk and this operation then overwrites it from the snapshot it
/// took beforehand, losing the user's work from the file *and* from the buffer
/// in one step. `workspace::persist::with_write_locks` documents the ordering
/// this relies on.
fn apply_reidentify(
    workspace: &Arc<Workspace>,
    plan: &Reidentify,
) -> Result<LifecycleEffects, AppError> {
    persist::with_write_locks(workspace, || apply_reidentify_locked(workspace, plan))
}

fn apply_reidentify_locked(
    workspace: &Arc<Workspace>,
    plan: &Reidentify,
) -> Result<LifecycleEffects, AppError> {
    let affected = plan_affected(workspace, plan)?;

    let mut journal = FileJournal::default();
    if let Err(error) = write_files(&affected, plan, &mut journal) {
        return Err(rolled_back(&mut journal, error));
    }

    // Derived out here rather than inside the connection closure: deriving
    // reads and parses, and `SPK-WSPC-D001` §6.2.7 forbids file I/O under the
    // process-wide connection mutex a keystroke's own draft write waits on.
    // Only the candidates that have a file. One that arrived through its draft
    // row or its session with no file behind it has no bytes to derive rows
    // from — see [`Affected::on_disk`] — and its stale rows are rebuilt from the
    // bundle at the next reindex.
    let indexed: Result<Vec<index::IndexedNote>, AppError> = affected
        .iter()
        .filter(|a| a.on_disk)
        .map(|a| {
            let source = final_source(a)?;
            Ok(index::derive_note(
                &a.new_id,
                &source,
                content_hash(source.as_bytes()),
                file_mtime(&a.new_path),
            ))
        })
        .collect();
    let indexed = match indexed {
        Ok(indexed) => indexed,
        Err(error) => return Err(rolled_back(&mut journal, error)),
    };

    let written = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            rewrite_index(tx, workspace.id(), plan, &affected, &indexed)
        })
    });
    if let Err(error) = written {
        return Err(rolled_back(&mut journal, error));
    }

    // Once for the whole batch, and outside the transaction that rewrote it —
    // see `write_note_rows_deferring_analyze`. Not fatal on its own: the rows
    // are correct either way and stale statistics cost a worse query plan, not
    // a wrong answer.
    //
    // Deliberately **not** propagated with `?`, which corrects what this
    // comment used to claim. The filesystem and the index have both moved by
    // this point, so returning here reported failure for an operation that had
    // already happened *and* jumped over the session reconciliation below,
    // stranding every open Note on a concept id the rename had vacated. It is
    // held instead, and surfaced only if the commit below fails too —
    // [`commit_stage_failure`] explains why that is the whole of the record
    // this crate can keep.
    let best_effort: Vec<String> = workspace
        .with_db(index::analyze_bounded)
        .err()
        .map(|e| format!("refreshing the query planner's statistics: {e:?}"))
        .into_iter()
        .collect();

    let mut pathspec: Vec<String> = Vec::new();
    // A candidate with no file is skipped here too, and this one is not merely
    // pointless: `commit_paths` reads a named path that is absent from disk as a
    // *removal*, so staging the vanished file would record a deletion this
    // operation did not perform, in a commit about a rename.
    for a in affected.iter().filter(|a| a.on_disk) {
        pathspec.push(concept_id_to_path(&a.old_id));
        if a.old_id != a.new_id {
            pathspec.push(concept_id_to_path(&a.new_id));
        }
    }
    // A Directory rename moves the whole directory with one `rename`, so the
    // Notes are not the only thing that moved: a bundle legitimately holds
    // files that are not Notes (an attachment, a foreign tool's `index.md`,
    // anything else an author put there), and every one of them is a rename
    // Git can see but was never told to record. Committing the Note paths alone
    // left the worktree permanently dirty — which is precisely the problem
    // `delete_directory` fixed for itself by committing the Directory rather
    // than the list of Notes.
    //
    // The two ends are named differently, because `commit_paths` reads a
    // directory path as a *removal* — which is exactly what `delete_directory`
    // needs of it. The old location is therefore one entry, and the new one is
    // named a file at a time.
    if let Some(rename) = &plan.directory_rename {
        pathspec.push(rename.old.clone());
        collect_files(workspace.root(), &rename.new_absolute, &mut pathspec);
    }
    // The commit result is held rather than propagated with `?`, so that the
    // journal is settled either way: the bundle and the index are already
    // consistent by this point, and a failure to record that in version history
    // must not also leave a trash entry parked in the bundle.
    let committed =
        crate::git::operations::commit_paths(workspace.root(), &plan.message, &pathspec);
    journal.commit();

    // In-memory and infallible in the sense that matters: nothing after this
    // point can leave the bundle and the index disagreeing.
    //
    // Runs **before** the commit error is surfaced, and that is the fix rather
    // than an ordering nicety. The re-identification has happened in both
    // stores; propagating the commit failure first left every open session
    // keyed to the concept id the operation vacated, so its next idle write was
    // refused with a revision mismatch against a file that no longer exists and
    // the user's buffered work was stranded where nothing could reach it — the
    // reversion `architecture/risks.md` risk 8 describes, reached from the one
    // direction the journal cannot see.
    let mut carried = Ok(());
    for a in &affected {
        let outcome = persist::carry_session_forward(
            workspace,
            &a.old_id,
            &a.new_id,
            a.new_buffer.clone(),
            a.revision.clone(),
        );
        if carried.is_ok() {
            carried = outcome;
        }
    }
    if let Err(error) = committed {
        let subject = plan.message.lines().next().unwrap_or("the operation");
        return Err(commit_stage_failure(subject, error, &best_effort));
    }
    carried?;

    let beyond_the_invoked =
        |a: &&Affected| plan.invoked.as_deref().is_none_or(|id| id != a.old_id);
    Ok(LifecycleEffects {
        remapped: affected
            .iter()
            .filter(|a| a.old_id != a.new_id)
            .filter(beyond_the_invoked)
            .map(|a| IdRemap {
                old_id: a.old_id.clone(),
                new_id: a.new_id.clone(),
            })
            .collect(),
        rewritten: affected
            .iter()
            .filter(|a| a.old_id == a.new_id && a.new_file.is_some())
            .filter(beyond_the_invoked)
            .map(|a| a.new_id.clone())
            .collect(),
    })
}

/// Reads, rewrites and validates every Note the operation touches, **before
/// anything is written**. The overwhelming majority of failure modes — an
/// unreadable file, a Link with no addressable destination — are raised from
/// here, where nothing has moved yet.
fn plan_affected(workspace: &Arc<Workspace>, plan: &Reidentify) -> Result<Vec<Affected>, AppError> {
    let mut candidates: BTreeSet<String> = plan.remap.keys().cloned().collect();
    if let Some((note_id, _)) = &plan.retitled {
        candidates.insert(note_id.clone());
    }
    for old_id in plan.remap.keys() {
        let sources = workspace.with_db(|conn| link_sources(conn, workspace.id(), old_id))?;
        candidates.extend(sources);
    }

    // The `links` table only knows about Links that reached disk **and** were
    // indexed, so driving the sweep from it alone misses two populations, and
    // both of them survive the operation holding a dead concept id:
    //
    // - A Note with an **unflushed draft row**. The draft is persistent state
    //   that outlives the process, `open_note` parses it in preference to disk,
    //   and its next tier 2 write puts those bytes on disk and indexes them —
    //   at which point the ghost edge the rename was supposed to remove is
    //   recreated, and CAP-GRAPH-04's create-on-follow will happily recreate
    //   the concept along with it.
    // - A Note **open with buffered edits**, whose Link may exist only in the
    //   working source. Same ending, one flush sooner.
    //
    // Both are cheap to fold in: `rewrite_note_text` returns `None` for a Note
    // that holds no matching Link and the loop below drops it, so the cost of a
    // false candidate is one read and one scan.
    candidates.extend(workspace.with_db(|conn| draft_note_ids(conn, workspace.id()))?);
    candidates.extend(persist::open_note_ids(workspace.id())?);

    let mut affected = Vec::new();
    for old_id in candidates {
        let new_id = plan
            .remap
            .get(&old_id)
            .cloned()
            .unwrap_or_else(|| old_id.clone());
        let old_path = workspace.note_path(&old_id)?;
        let new_path = workspace.note_path(&new_id)?;
        let new_title = plan
            .retitled
            .as_ref()
            .filter(|(id, _)| *id == old_id)
            .map(|(_, title)| title.as_str());

        let disk = read_source(&old_path)?;
        if disk.is_none() && plan.remap.contains_key(&old_id) {
            // The Note being re-identified has no file to move.
            return Err(AppError::NotFound(format!(
                "no file on disk for concept id {old_id}"
            )));
        }
        let dir = containing_dir(&old_id).to_string();
        let new_file = match &disk {
            Some(source) => rewrite_note_text(source, &dir, &plan.remap, new_title)?,
            None => None,
        };

        let buffer = persist::lookup(workspace.id(), &old_id)?
            .map(|session| session.working_source())
            .transpose()?;
        let held_by_a_session = buffer.is_some();
        let new_buffer = match buffer {
            Some(source) => rewrite_note_text(&source, &dir, &plan.remap, new_title)?,
            None => None,
        };

        let draft = workspace.with_db(|conn| read_draft_text(conn, workspace.id(), &old_id))?;
        let held_by_a_draft = draft.is_some();
        let new_draft = match draft {
            Some(source) => rewrite_note_text(&source, &dir, &plan.remap, new_title)?,
            None => None,
        };

        // A candidate with **no file on disk** is only dropped when nothing
        // else holds it either.
        //
        // The candidate set is deliberately wider than the `links` table (see
        // above), and the two populations it adds — a Note with an unflushed
        // draft row, and a Note open with buffered edits — are exactly the ones
        // that can outlive their own file. `open_note`'s recovery branch opens a
        // Note whose file was deleted underneath it *from the draft row*, so a
        // draft holding the only Link to the renamed concept is routinely a
        // draft with no file behind it. Dropping it here on the strength of the
        // missing file left that Link untouched, and the recovered session's
        // first tier 2 write then put the dead link back on disk and into the
        // index — the rename reverted from the one direction file-level
        // atomicity cannot see (`architecture/risks.md` risk 8), which is the
        // whole reason these two populations are swept at all.
        //
        // A candidate the `links` table alone produced, with no file, no draft
        // and no session, still drops: nothing addressable holds it, and its
        // rows are rebuilt from the bundle at the next reindex. Refusing the
        // rename over someone else's stale row would be the wrong direction of
        // strictness.
        if disk.is_none() && !held_by_a_draft && !held_by_a_session {
            continue;
        }

        if new_file.is_none() && new_buffer.is_none() && new_draft.is_none() && old_id == new_id {
            continue;
        }

        // `""` for a vanished file rather than a read: it is what
        // `persist::open_note` hashes for an absent one (`ABSENT_FILE`), so the
        // baseline this hands to `carry_session_forward` is the baseline the
        // recovering session already holds and its next write still compares
        // equal.
        let revision = content_hash(
            new_file
                .as_deref()
                .or(disk.as_deref())
                .unwrap_or("")
                .as_bytes(),
        );
        affected.push(Affected {
            old_id,
            new_id,
            old_path,
            new_path,
            on_disk: disk.is_some(),
            new_file,
            new_buffer,
            new_draft,
            revision,
        });
    }
    Ok(affected)
}

/// Applies both substitutions a re-identification can make to one Note's text:
/// the frontmatter `title`, and every inbound Link whose target moved.
///
/// Sequential rather than combined, because the title rewrite changes byte
/// lengths and the Link scan must run against the text it will actually be
/// spliced into.
fn rewrite_note_text(
    source: &str,
    containing_dir: &str,
    remap: &Remap,
    new_title: Option<&str>,
) -> Result<Option<String>, AppError> {
    let retitled = new_title.and_then(|title| rewrite_frontmatter_title(source, title));
    let base = retitled.as_deref().unwrap_or(source);
    match links_rewrite::rewrite_link_targets(base, containing_dir, remap)? {
        Some(rewritten) => Ok(Some(rewritten)),
        None => Ok(retitled),
    }
}

fn write_files(
    affected: &[Affected],
    plan: &Reidentify,
    journal: &mut FileJournal,
) -> Result<(), AppError> {
    // Bytes first, at the paths they currently occupy, so a directory rename
    // below carries the rewritten contents rather than racing them.
    for a in affected {
        if let Some(source) = &a.new_file {
            journal.overwrite(&a.old_path, source.as_bytes())?;
        }
    }
    match &plan.directory_rename {
        Some(rename) => journal.rename(&rename.old_absolute, &rename.new_absolute)?,
        None => {
            for a in affected {
                if a.old_path != a.new_path {
                    journal.rename(&a.old_path, &a.new_path)?;
                }
            }
        }
    }
    Ok(())
}

fn rewrite_index(
    tx: &Connection,
    workspace_id: &str,
    plan: &Reidentify,
    affected: &[Affected],
    indexed: &[index::IndexedNote],
) -> Result<(), AppError> {
    // Every inbound edge, whether or not its source Note's bytes were rewritten
    // — a stale row the rewrite found nothing for still has to move.
    //
    // `UPDATE OR REPLACE` rather than a bare `UPDATE`, per the note on the
    // `links` primary key in `data-models/schema.sql`: renaming `Old` to `New`
    // collides whenever one Note already links to *both*, which is exactly
    // CAP-GRAPH-04's write-forward-then-create workflow rather than a contrived
    // case. The duplicate edge is dropped and the renamed Link's own
    // `target_title` kept — a collision to merge, not a conflict to report.
    for (old_id, new_id) in &plan.remap {
        tx.execute(
            "UPDATE OR REPLACE links SET target_id = ?3 \
             WHERE workspace_id = ?1 AND target_id = ?2",
            rusqlite::params![workspace_id, old_id, new_id],
        )?;
    }

    // The `drafts` row carries no foreign key, so it neither cascades nor
    // re-keys itself. It is re-keyed **and rewritten**: `open_note` parses the
    // draft in preference to disk, so a row left holding the pre-rename bytes
    // reverts the rename one session later.
    for a in affected {
        if a.old_id != a.new_id {
            tx.execute(
                "UPDATE OR REPLACE drafts SET note_id = ?3 \
                 WHERE workspace_id = ?1 AND note_id = ?2",
                rusqlite::params![workspace_id, a.old_id, a.new_id],
            )?;
        }
        if let Some(draft) = &a.new_draft {
            tx.execute(
                "UPDATE drafts SET raw_markdown = ?3, updated_at = ?4 \
                 WHERE workspace_id = ?1 AND note_id = ?2",
                rusqlite::params![workspace_id, a.new_id, draft, unix_now()],
            )?;
        }
    }

    // The old rows go first, in `remove_note_rows`' order — `notes_fts` through
    // `fts_mapping`, then `notes` — so no full-text row is stranded behind a
    // cascade that destroyed the only pointer to it.
    for a in affected {
        if a.old_id != a.new_id {
            index::remove_note_rows(tx, workspace_id, &a.old_id)?;
        }
    }
    // Deferring the re-analysis: this loop is a batch, and `analyze_bounded`
    // refreshes statistics about three whole tables rather than about the rows
    // any one Note owns. Running it per Note paid the same bounded scan N times
    // — inside this transaction — for an answer only the last iteration could
    // give. `apply_reidentify_locked` runs it once, after the commit.
    for note in indexed {
        index::incremental::write_note_rows_deferring_analyze(tx, workspace_id, note)?;
    }

    if let Some(rename) = &plan.directory_rename {
        rekey_directories(tx, workspace_id, rename)?;
    }
    Ok(())
}

/// Re-keys the `directories` rows a directory rename moved. `notes` rows carry
/// their own ancestors through `write_note_rows`, but an **empty** Directory
/// inside the renamed subtree has no Note to carry it.
fn rekey_directories(
    tx: &Connection,
    workspace_id: &str,
    rename: &DirectoryRename,
) -> Result<(), AppError> {
    let (old_directory, new_directory) = (rename.old.clone(), rename.new.clone());

    let mut stmt = tx.prepare("SELECT id FROM directories WHERE workspace_id = ?1")?;
    let existing: Vec<String> = stmt
        .query_map([workspace_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    drop(stmt);

    let prefix = format!("{old_directory}/");
    for id in existing {
        let moved = if id == old_directory {
            new_directory.clone()
        } else if let Some(rest) = id.strip_prefix(&prefix) {
            format!("{new_directory}/{rest}")
        } else {
            continue;
        };
        tx.execute(
            "DELETE FROM directories WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace_id, id],
        )?;
        tx.execute(
            "INSERT OR IGNORE INTO directories (id, workspace_id, path) VALUES (?1, ?2, ?1)",
            rusqlite::params![moved, workspace_id],
        )?;
    }
    record_directories(tx, workspace_id, &new_directory)
}

/// The state a caller gets back after a re-identification: the open session's,
/// when the Note is open, and a state derived from the settled file otherwise.
fn settled_state(workspace: &Arc<Workspace>, note_id: &str) -> Result<NoteState, AppError> {
    if let Some(session) = persist::lookup(workspace.id(), note_id)? {
        return session.note_state();
    }
    let path = workspace.note_path(note_id)?;
    let bytes = std::fs::read(&path)
        .map_err(|e| AppError::IoError(format!("read {}: {e}", path.display())))?;
    // Lossy is safe **here and nowhere else in this crate**: these are bytes
    // this process just wrote through `write_files`, so a replacement character
    // cannot appear, and `base_revision` below is hashed from the raw `bytes`
    // rather than from `source`, so even if one did the OCC baseline would still
    // describe the file exactly. Every other constructor of an editable state —
    // `persist::open_note`, `NoteSession::reload` — decodes strictly through
    // `persist::decode_source` instead, because there the bytes are foreign and
    // a silent substitution would be written back over the user's file on the
    // next tier 2 write. Do not copy this line into one of those.
    let source = String::from_utf8_lossy(&bytes).into_owned();
    let ParsedNote { mut ast, spans } = parse_note(&source, containing_dir(note_id));
    workspace.with_db(|conn| index::resolve_link_existence(conn, workspace.id(), &mut ast))?;
    Ok(NoteState {
        ast,
        metadata: metadata_from(note_id, &source, &spans, file_mtime(&path)),
        base_revision: content_hash(&bytes),
        restored_from_draft: false,
    })
}

// ---------------------------------------------------------------------------
// The filesystem journal
// ---------------------------------------------------------------------------

/// Every filesystem step an operation took, in order, each paired with its
/// inverse.
///
/// This is what makes the fourth acceptance criterion — "a rename fails partway
/// through rewriting inbound links, and no file, index row or link has been
/// changed" — a property rather than a hope. [`FileJournal::rollback`] unwinds
/// in reverse; [`FileJournal::commit`] discards the trash entries a deletion
/// parked and keeps everything else.
#[derive(Default)]
struct FileJournal {
    steps: Vec<FileStep>,
}

enum FileStep {
    /// The file at `path` held `previous` before it was overwritten; `None`
    /// when it did not exist.
    Overwrote {
        path: PathBuf,
        previous: Option<Vec<u8>>,
    },
    Renamed {
        from: PathBuf,
        to: PathBuf,
    },
    /// A file or directory renamed out of the way rather than removed, so that
    /// undoing the removal is a rename back rather than a restore from memory.
    Trashed {
        original: PathBuf,
        trash: PathBuf,
    },
}

impl FileJournal {
    fn overwrite(&mut self, path: &Path, bytes: &[u8]) -> Result<(), AppError> {
        let previous = match std::fs::read(path) {
            Ok(bytes) => Some(bytes),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => return Err(AppError::IoError(format!("read {}: {e}", path.display()))),
        };
        persist::atomic_write(path, bytes)?;
        self.steps.push(FileStep::Overwrote {
            path: path.to_path_buf(),
            previous,
        });
        Ok(())
    }

    fn rename(&mut self, from: &Path, to: &Path) -> Result<(), AppError> {
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::IoError(format!("create {}: {e}", parent.display())))?;
        }
        std::fs::rename(from, to).map_err(|e| {
            AppError::IoError(format!(
                "rename {} to {}: {e}",
                from.display(),
                to.display()
            ))
        })?;
        self.steps.push(FileStep::Renamed {
            from: from.to_path_buf(),
            to: to.to_path_buf(),
        });
        Ok(())
    }

    /// Moves `path` aside into a dot-prefixed sibling, which
    /// `index::scan::walk_bundle` skips. The entry is removed by
    /// [`FileJournal::commit`] and restored by [`FileJournal::rollback`].
    fn trash(&mut self, path: &Path) -> Result<(), AppError> {
        static NEXT: AtomicU64 = AtomicU64::new(0);

        if !path.exists() {
            return Ok(());
        }
        let parent = path
            .parent()
            .ok_or_else(|| AppError::IoError(format!("{} has no parent", path.display())))?;
        let name = path
            .file_name()
            .map_or_else(|| "note".to_string(), |n| n.to_string_lossy().into_owned());
        // The prefix is `workspace::TRASH_PREFIX` rather than a literal because
        // two other places have to recognize what this writes: the `.gitignore`
        // `git::operations::init_repo` installs, and the sweep
        // `workspace::bootstrap` runs at open for entries a kill left parked.
        let trash = parent.join(format!(
            "{}{name}.{}.{}",
            super::TRASH_PREFIX,
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::rename(path, &trash)
            .map_err(|e| AppError::IoError(format!("remove {}: {e}", path.display())))?;
        self.steps.push(FileStep::Trashed {
            original: path.to_path_buf(),
            trash,
        });
        Ok(())
    }

    /// Undoes every step, newest first, and **reports what it could not undo**.
    ///
    /// A failing step no longer stops the unwind — the steps are independent,
    /// and abandoning the rest would leave more of the operation standing than
    /// necessary — but it is no longer discarded either. A rollback that cannot
    /// put a file back is the one case where "either completes or changes
    /// nothing" quietly stops being true, and the crate has no logging channel,
    /// so [`rolled_back`] folds this summary into the error the caller is
    /// already receiving. Everything else about a rollback stays best-effort:
    /// this runs on a path that is already returning an error.
    ///
    /// Takes `&mut self` and drains, rather than consuming, so that
    /// [`FileJournal`]'s `Drop` can be the backstop for a journal neither
    /// committed nor rolled back.
    fn rollback(&mut self) -> Option<String> {
        let steps = std::mem::take(&mut self.steps);
        let total = steps.len();
        let mut failures: Vec<String> = Vec::new();

        for step in steps.into_iter().rev() {
            let undone = match step {
                FileStep::Overwrote { path, previous } => match previous {
                    Some(bytes) => persist::atomic_write(&path, &bytes)
                        .map_err(|e| format!("restore {}: {e:?}", path.display())),
                    None => std::fs::remove_file(&path)
                        .map_err(|e| format!("remove {}: {e}", path.display())),
                },
                FileStep::Renamed { from, to } => std::fs::rename(&to, &from)
                    .map_err(|e| format!("move {} back to {}: {e}", to.display(), from.display())),
                FileStep::Trashed { original, trash } => std::fs::rename(&trash, &original)
                    .map_err(|e| format!("restore {}: {e}", original.display())),
            };
            if let Err(failure) = undone {
                failures.push(failure);
            }
        }

        if failures.is_empty() {
            return None;
        }
        Some(format!(
            "{} of {total} filesystem steps could not be undone, the first being: {}",
            failures.len(),
            failures[0]
        ))
    }

    /// Keeps every step and discards the trash entries a deletion parked.
    fn commit(&mut self) {
        for step in std::mem::take(&mut self.steps) {
            Self::discard_trash(&step);
        }
    }

    fn discard_trash(step: &FileStep) {
        let FileStep::Trashed { trash, .. } = step else {
            return;
        };
        if trash.is_dir() {
            let _ = std::fs::remove_dir_all(trash);
        } else {
            let _ = std::fs::remove_file(trash);
        }
    }
}

/// Rolls `journal` back behind an error that is already being returned, and
/// folds any failure of the **rollback itself** into that error's message.
///
/// Every rollback site goes through this rather than calling
/// [`FileJournal::rollback`] directly, because a rollback that does not complete
/// is the single case where this module's headline property — "one operation
/// that either completes or changes nothing" — stops holding, and it used to
/// stop holding silently. There is no logging in this crate, so the error the
/// caller is about to receive is the only channel available; that is a small
/// channel, but the recovery is manual (the previous bytes are in Git) and the
/// user cannot begin it without being told.
fn rolled_back(journal: &mut FileJournal, error: AppError) -> AppError {
    let Some(incomplete) = journal.rollback() else {
        return error;
    };
    restate(error, |detail| {
        format!(
            "{detail} — and undoing it did not fully succeed, so the bundle is part-way \
             through this operation on disk: {incomplete}"
        )
    })
}

/// The error a commit returns **after** the operation it records has already
/// settled.
///
/// By the time `commit_paths` runs, the bundle and the index have both moved
/// and the journal is committed — that ordering is deliberate, and it is what
/// makes the composite operation recoverable. So a failure here does not mean
/// "the operation failed"; it means "the operation happened and version history
/// does not record it", and a caller acts differently on the two. `AppError` has
/// no variant for a stage, so the stage is spelled out in the message.
///
/// `best_effort` carries any non-fatal step that was skipped on the way here
/// (the deferred `ANALYZE`, whose failure is not worth an error of its own).
/// It is attached only when there is already an error to attach it to, which is
/// the whole of the record this crate can keep without a logging framework.
///
/// Shared with [`persist::NoteSession::close`], which is tier 3's own commit and
/// reaches the same state by the same route: the flush has already put the
/// bytes on disk and the rows in the index, so a failure to record that in
/// history is a report to make, not an operation to abandon.
pub(super) fn commit_stage_failure(
    subject: &str,
    error: AppError,
    best_effort: &[String],
) -> AppError {
    let trailer = if best_effort.is_empty() {
        String::new()
    } else {
        format!(
            " (also, best-effort steps did not run: {})",
            best_effort.join("; ")
        )
    };
    restate(error, |detail| {
        format!(
            "{subject}: the operation completed — the bundle and the index have both moved — \
             but the commit recording it in version history failed, so the Workspace is \
             uncommitted: {detail}{trailer}"
        )
    })
}

/// Rewrites the prose inside `error`, keeping its variant so a caller keying on
/// a specific one still sees it.
///
/// [`AppError::RevisionMismatch`] is excluded on purpose: its `String` is a
/// revision the caller parses, not a sentence, and rewriting it would corrupt
/// the reload it exists to drive. The remaining message-less variants are
/// converted to [`AppError::IoError`] with their own name folded into the text,
/// which is the lesser loss: the sentences this function writes are only ever
/// added when the bundle has been left in a state the user has to act on, and
/// that is more urgent than the affordance the original variant would have
/// selected.
fn restate(error: AppError, rewrite: impl FnOnce(&str) -> String) -> AppError {
    match error {
        AppError::RevisionMismatch(revision) => AppError::RevisionMismatch(revision),
        AppError::PathUnavailable(m) => AppError::PathUnavailable(rewrite(&m)),
        AppError::NotFound(m) => AppError::NotFound(rewrite(&m)),
        AppError::DatabaseError(m) => AppError::DatabaseError(rewrite(&m)),
        AppError::CryptoError(m) => AppError::CryptoError(rewrite(&m)),
        AppError::NetworkError(m) => AppError::NetworkError(rewrite(&m)),
        AppError::OAuthError(m) => AppError::OAuthError(rewrite(&m)),
        AppError::IoError(m) => AppError::IoError(rewrite(&m)),
        AppError::ParseError(m) => AppError::ParseError(rewrite(&m)),
        other => AppError::IoError(rewrite(&format!("{other:?}"))),
    }
}

/// The backstop for a journal that is dropped without being committed or rolled
/// back — which is what an error returned *after* the filesystem and the index
/// have both settled produces, the commit step being the one that can do it.
///
/// Only the trash entries are discarded, and that is the whole point: by the
/// time such an error is raised the deletion is real and the index agrees with
/// it, so restoring the file would put the bundle back out of step with the
/// index. What must not survive is a `.burlmd-trash.*` entry parked inside the
/// bundle, holding the full content of a deleted Note as an untracked file that
/// a later broad commit or a sync could publish.
impl Drop for FileJournal {
    fn drop(&mut self) {
        for step in &self.steps {
            Self::discard_trash(step);
        }
    }
}

// ---------------------------------------------------------------------------
// Frontmatter
// ---------------------------------------------------------------------------

/// The block [`create_note`] writes: OKF §11 conformance is a parseable
/// frontmatter block carrying a non-empty `type`, and `title` is what decouples
/// the display name from the identity-bearing filename.
fn conformant_frontmatter(title: &str) -> String {
    format!("---\ntype: Note\ntitle: {}\n---\n\n", yaml_scalar(title))
}

/// Rewrites the `title` value inside a Note's existing frontmatter block,
/// returning `None` when the Note has no block or already carries this title.
///
/// ADR-007 decision 5 makes the block a byte span that is rewritten **only**
/// when `title` changes, so everything outside the one value — key order,
/// spelling, spacing, unmanaged keys — is copied through untouched. A file with
/// no frontmatter at all is left alone rather than given one: `okf-bundle.md`
/// makes bringing a foreign file into conformance an explicit user action, and
/// its title derives from the filename the rename just changed anyway.
fn rewrite_frontmatter_title(source: &str, new_title: &str) -> Option<String> {
    let span = parse_note(source, "").spans.frontmatter()?;
    let block = source.get(span.clone())?;

    let mut lines: Vec<(usize, &str)> = Vec::new();
    let mut offset = span.start;
    for line in block.split_inclusive('\n') {
        lines.push((offset, line.trim_end_matches(['\n', '\r'])));
        offset += line.len();
    }

    let key = lines
        .iter()
        .position(|(_, line)| line.starts_with("title:") || line.trim_end() == "title");

    let replacement = format!("title: {}", yaml_scalar(new_title));
    match key {
        Some(index) => {
            let (start, line) = lines[index];
            let mut end = start + line.len();
            // A block scalar (`title: |`) continues onto the more-indented
            // lines that follow it; they belong to the value being replaced.
            for (next_start, next) in lines.iter().skip(index + 1) {
                if next.starts_with(' ') || next.starts_with('\t') {
                    end = next_start + next.len();
                } else {
                    break;
                }
            }
            if source.get(start..end)? == replacement {
                return None;
            }
            let mut out = source.to_string();
            out.replace_range(start..end, &replacement);
            Some(out)
        }
        None => {
            // No `title` key: add one immediately before the closing delimiter,
            // which is the last line of the block. `title` is a burlmd-managed
            // key (ADR-004 decision 3), so writing it into a block that already
            // exists is not the "create a block that was never there" case the
            // rule above forbids.
            let (closing_start, _) = *lines.last()?;
            let mut out = source.to_string();
            out.replace_range(closing_start..closing_start, &format!("{replacement}\n"));
            Some(out)
        }
    }
}

/// `value` as a YAML scalar that round-trips back through `read_frontmatter` as
/// the same string.
///
/// Plain only for a conservative allowlist; everything else is double-quoted.
/// The allowlist matters because a title is free-form user text under the
/// verbatim derivation rule, and YAML reads a bare `no`, `2024` or `a: b` as a
/// boolean, an integer and a nested mapping respectively.
///
/// Inside the quotes, every character in the `Cc` category is escaped as well
/// as the four that already were. YAML 1.2 §5.7 forbids a raw C0 or C1 control
/// in a double-quoted scalar, and this crate is not the only reader of the
/// bytes it writes: a bundle is a portable artifact under OKF, so a block that
/// only happens to parse is not the bar. Measured against the pinned `saphyr`
/// 0.0.11, a raw `\u{7}` from a terminal paste or a `\u{b}` from a spreadsheet
/// cell round-trips today and only `\u{0}` — already refused upstream by
/// [`validate_segment`] — does not, so this is the spelling being made correct
/// rather than a parse being repaired. `\uXXXX` is chosen over YAML's shorter
/// `\xXX` because it is the one form that covers the whole category, C1
/// controls included.
fn yaml_scalar(value: &str) -> String {
    let plain = value
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic())
        && !value.ends_with(' ')
        && !value.contains(": ")
        && !value.contains(" #")
        && value
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, ' ' | '_' | '-' | '.' | '(' | ')'))
        && !matches!(
            value.to_ascii_lowercase().as_str(),
            "true" | "false" | "yes" | "no" | "on" | "off" | "null"
        );
    if plain {
        return value.to_string();
    }

    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ if c.is_control() => out.push_str(&format!("\\u{:04X}", c as u32)),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// The rule `create_note` and `rename_note` share, per this ticket's second
/// STOP condition: a title that cannot be derived into a filename, or that
/// derives to a reserved one, is refused rather than silently disambiguated.
fn validate_title(title: &str) -> Result<(), AppError> {
    validate_segment(title)?;
    if is_reserved_title(title) {
        return Err(AppError::PathUnavailable(format!(
            "{title} derives to a reserved OKF filename (OKF §3.1 reserves index.md and log.md)"
        )));
    }
    Ok(())
}

/// One path segment — a title or a Directory name — checked against what the
/// verbatim derivation can actually produce.
fn validate_segment(segment: &str) -> Result<(), AppError> {
    if segment.trim().is_empty() {
        return Err(AppError::PathUnavailable(
            "a Note or Directory name cannot be empty".to_string(),
        ));
    }
    // A leading `.` covers `.` and `..` — which name a directory rather than a
    // file inside the Workspace — and every other dot-prefixed name, which is
    // worse than it looks. `index::scan::walk_bundle` skips dot-prefixed
    // entries, deliberately: that is what makes a trash entry or a half-written
    // `.name.pid.n.tmp` invisible to the indexer rather than a phantom Note. So
    // a Note called `.hidden` would be created, indexed and opened, and then
    // silently dropped from the index by the next reindex — which now runs on
    // every Workspace open — leaving the file orphaned on disk and its name
    // permanently taken, since `ensure_path_available` consults the filesystem
    // as well as the index. Refusing is this function's own stance
    // (`data-models/okf-bundle.md`, "Reserved filenames"): a name that cannot
    // be derived correctly is rejected rather than silently disambiguated.
    if segment.starts_with('.') {
        return Err(AppError::PathUnavailable(format!(
            "{segment} derives a dot-prefixed filename, which the indexer skips, so the Note \
             would vanish from the Workspace while its file stayed on disk"
        )));
    }
    if segment.contains('/') || segment.contains('\\') || segment.contains('\0') {
        return Err(AppError::PathUnavailable(format!(
            "{segment} contains a character no filename can carry, and the derivation is \
             verbatim rather than slugifying (data-models/okf-bundle.md)"
        )));
    }
    // A line terminator is legal in a Unix filename and still underivable
    // here, because the filename is not the end of the derivation: every
    // inbound Link to this Note is written by `okf::serialize_link` as an
    // angle-bracket destination, and CommonMark forbids a line ending inside
    // one. `[T](</Two\nLines.md>)` therefore yields no `Link` event at all —
    // no edge in the parser, no row in `links`, no backlink — and
    // `rename_note`'s inbound sweep reports success over link text it left
    // pointing nowhere, which is `architecture/risks.md` risk 8 reached
    // through the create path rather than through a rewrite. Refused rather
    // than escaped, on this function's standing rule: a name that cannot be
    // derived correctly is rejected, never silently disambiguated. A tab is
    // deliberately not in this set — it round-trips through the same
    // destination form unharmed.
    if segment.contains('\n') || segment.contains('\r') {
        return Err(AppError::PathUnavailable(format!(
            "{segment:?} contains a line terminator, which no Link to this Note could \
             carry: the destination form is angle-bracketed and CommonMark forbids a line \
             ending inside one, so every inbound Link would silently stop being a Link"
        )));
    }
    Ok(())
}

/// Both halves of the availability check the contract requires.
///
/// The filesystem is consulted **as well as** the index, and it is the half
/// that is easy to omit: `notes.id` is a case-sensitive `TEXT` key while
/// macOS's default filesystem is not, so `Ideas` and `ideas` are two ids over
/// one file there and an index-only check would report the second as free
/// (`data-models/okf-bundle.md`, "Case sensitivity follows the filesystem").
///
/// `held_by` is the path the operation is moving *from*, when there is one: a
/// rename that only changes case finds its own file at the destination on a
/// case-insensitive filesystem, and that is not a collision.
fn ensure_path_available(
    workspace: &Arc<Workspace>,
    new_id: &str,
    new_path: &Path,
    held_by: Option<&Path>,
) -> Result<(), AppError> {
    if new_path.exists() && !is_same_file(new_path, held_by) {
        return Err(AppError::PathUnavailable(format!(
            "{} is already taken in this Workspace",
            concept_id_to_path(new_id)
        )));
    }
    let taken = workspace.with_db(|conn| index::note_exists(conn, workspace.id(), new_id))?;
    if taken && held_by.is_none_or(|held| held != new_path) {
        return Err(AppError::PathUnavailable(format!(
            "a Note with concept id {new_id} already exists in this Workspace"
        )));
    }
    Ok(())
}

/// Whether `candidate` and `held_by` are the same entry on disk rather than two
/// entries with the same spelling — the test both [`ensure_path_available`] and
/// [`rename_directory`] use to tell a case-only rename apart from a collision on
/// a case-insensitive filesystem.
fn is_same_file(candidate: &Path, held_by: Option<&Path>) -> bool {
    let Some(held) = held_by else {
        return false;
    };
    if held == candidate {
        return true;
    }
    match (
        std::fs::canonicalize(held),
        std::fs::canonicalize(candidate),
    ) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

/// Normalizes a Directory path to the bundle-relative, `/`-separated, no
/// leading slash form `directories.path` stores, rejecting anything that walks
/// out of the bundle.
///
/// A backslash **anywhere** in the input is refused outright, and the order
/// matters: this used to run the containment check first and translate `\` to
/// `/` afterwards, which on Unix is a traversal hole rather than a nicety.
/// `..\..\etc` is a single `Component::Normal` there — one filename that
/// happens to contain backslashes — so it passed the check, and the
/// translation then turned it into `../../etc` for `root().join(..)` to walk
/// out of the bundle with. `create_directory` made directories outside it and
/// `delete_directory` recursively removed one, because the journal is settled
/// before the commit error propagates.
///
/// Rejecting is chosen over translating-then-checking on purpose. It is what
/// [`validate_segment`] already does for a Note or Directory *name*, so the
/// two halves of the same path now agree; and a foreign bundle holding a
/// directory whose name genuinely contains a backslash — legal on every Unix
/// filesystem — cannot be addressed through this API either way, since any
/// translation would rewrite the name into a path. Refusing says so instead of
/// silently addressing a different directory.
///
/// A **dot-prefixed segment** is refused on the same terms, and for the reason
/// [`validate_segment`] gives: `index::scan::walk_bundle` skips those entries,
/// so a Directory under one is invisible to the indexer and the next reindex
/// drops its row, while the on-disk directory — and any Note written into it —
/// stays. It is also what keeps the trash entries and the tier 2 temporary
/// files, both dot-prefixed by construction, from being addressable through
/// this API at all.
fn normalize_directory(path: &str) -> Result<String, AppError> {
    if path.contains('\\') {
        return Err(AppError::PathUnavailable(format!(
            "{path} does not name a Directory inside the Workspace: a Directory path is \
             `/`-separated and a backslash is a character no segment may carry"
        )));
    }
    // Refused here as well as in [`validate_segment`] and
    // [`persist::Workspace::note_path`], for the reason the backslash and the
    // line-terminator rules are duplicated across the same three functions: one
    // rule, three entrances. `validate_segment` already rejected a NUL in a
    // *name*, so `create_note("a\0b")` came back as `PathUnavailable` while
    // `create_directory("a\0b")` walked past this function and into
    // `create_dir_all`, which returned a raw `IoError` about an invalid
    // argument — the same input, two unrelated-looking answers, and the leaked
    // one names an implementation detail instead of the rule it broke.
    if path.contains('\0') {
        return Err(AppError::PathUnavailable(format!(
            "{path:?} contains a NUL, which no path on this system can carry"
        )));
    }
    // Refused here as well as in [`validate_segment`], and for that function's
    // reason: a Directory whose name carries a line terminator puts it into
    // the concept id of every Note beneath it, and so into the
    // angle-bracketed destination of every Link to one — where CommonMark
    // forbids it, silently costing each of those Links its `Link` event, its
    // edge and its backlink. Both halves of a path agree about what a segment
    // may carry, which is the same reason the backslash check above is
    // duplicated between the two.
    if path.contains('\n') || path.contains('\r') {
        return Err(AppError::PathUnavailable(format!(
            "{path:?} contains a line terminator, which no Link to a Note beneath it could \
             carry: the destination form is angle-bracketed and CommonMark forbids a line \
             ending inside one"
        )));
    }
    let trimmed = path.trim_matches('/');
    if trimmed.is_empty() {
        return Ok(String::new());
    }
    let relative = Path::new(trimmed);
    let escapes = relative
        .components()
        .any(|component| !matches!(component, Component::Normal(_)));
    if escapes {
        return Err(AppError::PathUnavailable(format!(
            "{path} does not name a Directory inside the Workspace"
        )));
    }
    if trimmed.split('/').any(|segment| segment.starts_with('.')) {
        return Err(AppError::PathUnavailable(format!(
            "{path} names a dot-prefixed Directory, which the indexer skips, so it would \
             vanish from the Workspace while its contents stayed on disk"
        )));
    }
    Ok(trimmed.to_string())
}

/// The absolute path of a bundle-relative Directory, refusing one that does not
/// resolve to where it names.
///
/// Every operation that turns a Directory path into an absolute one goes
/// through this rather than calling `root().join(..)` itself, because each of
/// them writes, moves or removes at the path it gets back and a symbolic link
/// component redirects all three — `create_directory` materializes a folder
/// outside the bundle, `rename_directory` moves one there, and
/// `delete_directory` recursively removes whatever is really at the other end.
/// [`Workspace::ensure_directory_contained`] carries the reasoning, including
/// why a link back *inside* the bundle is refused too.
fn directory_absolute(workspace: &Arc<Workspace>, directory: &str) -> Result<PathBuf, AppError> {
    workspace
        .ensure_directory_contained(Path::new(directory))
        .map_err(|reason| {
            AppError::PathUnavailable(format!(
                "{directory} does not name a Directory inside the Workspace: {reason}"
            ))
        })?;
    Ok(workspace.root().join(directory))
}

/// Resolves a Directory the caller named, materializing it when the index
/// knows it but no on-disk folder represents it yet.
///
/// The containment check runs **first**, and on the Directory's own components
/// rather than on a file inside it: `is_dir()` follows a symbolic link, so
/// without this a Directory that is really a link was accepted here and every
/// Note moved into it was written wherever the link pointed.
/// [`Workspace::ensure_directory_contained`] documents why a link back inside
/// the bundle is refused too.
fn ensure_directory_exists(workspace: &Arc<Workspace>, directory: &str) -> Result<(), AppError> {
    if directory.is_empty() {
        return Ok(());
    }
    let absolute = directory_absolute(workspace, directory)?;
    if absolute.is_dir() {
        return Ok(());
    }
    let known = workspace.with_db(|conn| {
        conn.query_row(
            "SELECT 1 FROM directories WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace.id(), directory],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(AppError::from)
    })?;
    if known.is_none() {
        return Err(AppError::PathUnavailable(format!(
            "no Directory at {directory} in this Workspace"
        )));
    }
    // Known to the index but never materialized, because an empty Directory has
    // no file to represent it (`contracts/ffi_api.rs`, `create_directory`).
    std::fs::create_dir_all(&absolute)
        .map_err(|e| AppError::IoError(format!("create {}: {e}", absolute.display())))?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

/// Runs `f` in a transaction this function owns, rolling back on error.
///
/// Deliberately not `index::in_transaction`, which *joins* a caller's: the
/// index functions called inside `f` join this one, and the rollback obligation
/// that module documents ("the joining caller owns the rollback") is discharged
/// here.
fn in_owned_transaction<T>(
    conn: &Connection,
    f: impl FnOnce(&Connection) -> Result<T, AppError>,
) -> Result<T, AppError> {
    let tx = conn.unchecked_transaction()?;
    match f(&tx) {
        Ok(value) => {
            tx.commit()?;
            Ok(value)
        }
        Err(error) => {
            // Explicit rather than relying on the drop: a rollback that itself
            // fails must not be silently discarded on a path whose whole
            // guarantee is that nothing changed.
            tx.rollback()?;
            Err(error)
        }
    }
}

fn record_directories(
    conn: &Connection,
    workspace_id: &str,
    directory: &str,
) -> Result<(), AppError> {
    if directory.is_empty() {
        return Ok(());
    }
    let mut stmt = conn.prepare(
        "INSERT OR IGNORE INTO directories (id, workspace_id, path) VALUES (?1, ?2, ?1)",
    )?;
    let mut ancestor = String::new();
    for segment in directory.split('/').filter(|s| !s.is_empty()) {
        if !ancestor.is_empty() {
            ancestor.push('/');
        }
        ancestor.push_str(segment);
        stmt.execute(rusqlite::params![ancestor, workspace_id])?;
    }
    Ok(())
}

fn clear_draft(conn: &Connection, workspace_id: &str, note_id: &str) -> Result<(), AppError> {
    conn.execute(
        "DELETE FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
        rusqlite::params![workspace_id, note_id],
    )?;
    Ok(())
}

fn read_draft_text(
    conn: &Connection,
    workspace_id: &str,
    note_id: &str,
) -> Result<Option<String>, AppError> {
    conn.query_row(
        "SELECT raw_markdown FROM drafts WHERE workspace_id = ?1 AND note_id = ?2",
        rusqlite::params![workspace_id, note_id],
        |row| row.get::<_, String>(0),
    )
    .optional()
    .map_err(AppError::from)
}

/// Every Note carrying an unflushed `drafts` row. See the sweep's candidate
/// seeding in [`plan_affected`] for why the index alone is not enough.
fn draft_note_ids(conn: &Connection, workspace_id: &str) -> Result<Vec<String>, AppError> {
    let mut stmt = conn.prepare("SELECT note_id FROM drafts WHERE workspace_id = ?1")?;
    let rows = stmt.query_map([workspace_id], |row| row.get::<_, String>(0))?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

/// Every Note holding an inbound Link to `target_id`, served by
/// `idx_links_target` — the index `data-models/schema.sql` adds so that this
/// sweep is cheap enough that there is no incentive to skip it (risk 8).
fn link_sources(
    conn: &Connection,
    workspace_id: &str,
    target_id: &str,
) -> Result<Vec<String>, AppError> {
    let mut stmt = conn.prepare(
        "SELECT DISTINCT source_id FROM links WHERE workspace_id = ?1 AND target_id = ?2",
    )?;
    let rows = stmt.query_map(rusqlite::params![workspace_id, target_id], |row| row.get(0))?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

fn note_ids_with_prefix(
    conn: &Connection,
    workspace_id: &str,
    prefix: &str,
) -> Result<Vec<String>, AppError> {
    // Filtered in Rust rather than with `LIKE`: a Directory name is free-form
    // user text and may legitimately contain `%` or `_`, which `LIKE` would
    // read as wildcards.
    let mut stmt = conn.prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")?;
    let rows = stmt.query_map([workspace_id], |row| row.get::<_, String>(0))?;
    Ok(rows
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .filter(|id| id.starts_with(prefix))
        .collect())
}

fn indexed_title(workspace: &Arc<Workspace>, note_id: &str) -> Result<Option<String>, AppError> {
    workspace.with_db(|conn| {
        conn.query_row(
            "SELECT title FROM notes WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace.id(), note_id],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(AppError::from)
    })
}

fn like_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn read_source(path: &Path) -> Result<Option<String>, AppError> {
    match std::fs::read(path) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(source) => Ok(Some(source)),
            Err(_) => Err(AppError::ParseError(format!(
                "{} is not valid UTF-8, so its Links cannot be rewritten without corrupting it",
                path.display()
            ))),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(AppError::IoError(format!("read {}: {e}", path.display()))),
    }
}

/// The bytes on disk for one affected Note once the operation has written them.
///
/// A failed read is an error rather than an empty string: deriving index rows
/// from `""` would silently blank out a Note's title, its full text and its
/// outbound edges while reporting success, which is a worse outcome than the
/// rollback this returns into.
///
/// The one case where a missing file is *not* an error — a candidate that
/// reached the sweep through its draft row or its session with nothing on disk
/// behind it — never reaches here at all: [`Affected::on_disk`] is what filters
/// it out, precisely so this function does not have to choose between the two.
fn final_source(affected: &Affected) -> Result<String, AppError> {
    match &affected.new_file {
        Some(source) => Ok(source.clone()),
        None => std::fs::read_to_string(&affected.new_path)
            .map_err(|e| AppError::IoError(format!("read {}: {e}", affected.new_path.display()))),
    }
}

/// Appends every file beneath `dir` to `out`, bundle-relative, so a Directory
/// rename can name its new location one entry at a time.
///
/// burlmd's own scratch files are skipped, and `.git` with them: both are
/// ignored rather than tracked (`workspace::SCRATCH_IGNORE_PATTERNS`), so
/// staging one is precisely what those patterns exist to prevent. A directory
/// that cannot be read is skipped rather than raised — this runs after the
/// filesystem and the index already agree, and the only cost of missing a file
/// here is the dirty worktree this is closing, not a wrong commit.
fn collect_files(root: &Path, dir: &Path, out: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name == ".git" || super::is_ignored_scratch_name(&name) {
            continue;
        }
        let path = entry.path();
        if path.is_dir() {
            collect_files(root, &path, out);
        } else if let Ok(relative) = path.strip_prefix(root) {
            out.push(relative.to_string_lossy().into_owned());
        }
    }
}

fn containing_dir(concept_id: &str) -> &str {
    concept_id.rsplit_once('/').map_or("", |(dir, _)| dir)
}

fn file_stem(concept_id: &str) -> &str {
    concept_id
        .rsplit_once('/')
        .map_or(concept_id, |(_, name)| name)
}

fn join_id(directory: &str, name: &str) -> String {
    if directory.is_empty() {
        name.to_string()
    } else {
        format!("{directory}/{name}")
    }
}

fn file_mtime(path: &Path) -> i64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0))
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0))
}

fn metadata_from(
    note_id: &str,
    source: &str,
    spans: &crate::markdown::SpanMap,
    last_modified: i64,
) -> crate::draft::NoteMetadata {
    let frontmatter = spans
        .frontmatter()
        .and_then(|span| source.get(span))
        .map_or_else(Default::default, crate::okf::read_frontmatter);
    let title = frontmatter
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map_or_else(|| file_stem(note_id).to_string(), str::to_string);
    crate::draft::NoteMetadata {
        id: note_id.to_string(),
        path: concept_id_to_path(note_id),
        title,
        last_modified,
        snippet: None,
        okf_conformant: frontmatter.is_conformant(),
    }
}

#[cfg(test)]
mod tests {
    use std::process::Command;
    use std::sync::atomic::AtomicU32;
    use std::time::Duration;

    use tempfile::TempDir;

    use super::*;
    use crate::markdown::{AstNode, InlineElement};
    use crate::workspace::persist::NoteSession;

    // -- fixture -------------------------------------------------------------

    struct Fixture {
        dir: TempDir,
        workspace: Arc<Workspace>,
    }

    impl Fixture {
        fn root(&self) -> PathBuf {
            self.dir.path().join("bundle")
        }

        fn write(&self, relative: &str, contents: &str) {
            let path = self.root().join(relative);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, contents).unwrap();
        }

        fn read(&self, relative: &str) -> String {
            std::fs::read_to_string(self.root().join(relative)).unwrap()
        }

        fn exists(&self, relative: &str) -> bool {
            self.root().join(relative).exists()
        }

        /// Builds the index from the bundle, the way first open does — in the
        /// two phases bootstrap uses, with the walk outside the connection.
        fn reindex(&self) {
            let scanned = crate::index::scan::scan_bundle(&self.root()).unwrap();
            self.workspace
                .with_db(|conn| {
                    crate::index::scan::write_scanned_bundle(conn, self.workspace.id(), &scanned)
                })
                .unwrap();
        }

        fn open(&self, note_id: &str) -> NoteSession {
            persist::open_note(&self.workspace, note_id).unwrap().0
        }

        fn note_ids(&self) -> Vec<String> {
            self.query_column("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
        }

        fn directory_ids(&self) -> Vec<String> {
            self.query_column("SELECT id FROM directories WHERE workspace_id = ?1 ORDER BY id")
        }

        /// Every inbound edge's source, for one target.
        fn backlink_sources(&self, target_id: &str) -> Vec<String> {
            self.workspace
                .with_db(|conn| {
                    let mut stmt = conn.prepare(
                        "SELECT source_id FROM links WHERE workspace_id = ?1 AND target_id = ?2 \
                         ORDER BY source_id",
                    )?;
                    let rows = stmt
                        .query_map(rusqlite::params![self.workspace.id(), target_id], |row| {
                            row.get::<_, String>(0)
                        })?
                        .collect::<Result<Vec<_>, _>>()?;
                    Ok(rows)
                })
                .unwrap()
        }

        fn link_targets(&self, source_id: &str) -> Vec<String> {
            self.workspace
                .with_db(|conn| {
                    let mut stmt = conn.prepare(
                        "SELECT target_id FROM links WHERE workspace_id = ?1 AND source_id = ?2 \
                         ORDER BY target_id",
                    )?;
                    let rows = stmt
                        .query_map(rusqlite::params![self.workspace.id(), source_id], |row| {
                            row.get::<_, String>(0)
                        })?
                        .collect::<Result<Vec<_>, _>>()?;
                    Ok(rows)
                })
                .unwrap()
        }

        fn query_column(&self, sql: &str) -> Vec<String> {
            self.workspace
                .with_db(|conn| {
                    let mut stmt = conn.prepare(sql)?;
                    let rows = stmt
                        .query_map([self.workspace.id()], |row| row.get::<_, String>(0))?
                        .collect::<Result<Vec<_>, _>>()?;
                    Ok(rows)
                })
                .unwrap()
        }

        fn count(&self, sql: &str) -> i64 {
            self.workspace
                .with_db(|conn| Ok(conn.query_row(sql, [], |row| row.get::<_, i64>(0))?))
                .unwrap()
        }

        /// Rows matching a bare FTS5 `MATCH` **without** joining `fts_mapping`.
        /// Deliberately unjoined: a search that joins the mapping cannot see an
        /// orphaned `notes_fts` row, which is exactly the row a wrong deletion
        /// order leaves behind.
        fn raw_fts_matches(&self, query: &str) -> i64 {
            self.workspace
                .with_db(|conn| {
                    Ok(conn.query_row(
                        "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?1",
                        [query],
                        |row| row.get::<_, i64>(0),
                    )?)
                })
                .unwrap()
        }

        fn draft_row(&self, note_id: &str) -> Option<String> {
            self.workspace
                .with_db(|conn| read_draft_text(conn, self.workspace.id(), note_id))
                .unwrap()
        }

        fn put_draft(&self, note_id: &str, source: &str) {
            self.workspace
                .with_db(|conn| {
                    conn.execute(
                        "INSERT INTO drafts (workspace_id, note_id, raw_markdown, updated_at, \
                         edit_seq) VALUES (?1, ?2, ?3, ?4, 1)",
                        rusqlite::params![self.workspace.id(), note_id, source, unix_now()],
                    )?;
                    Ok(())
                })
                .unwrap();
        }

        /// Every `.burlmd-trash.*` entry anywhere in the bundle. A deletion
        /// parks one of these and is obliged to remove it: it holds the full
        /// content of a deleted Note as an untracked file, which a later broad
        /// commit or a sync could publish.
        fn trash_entries(&self) -> Vec<String> {
            let mut found = Vec::new();
            walk(&self.root(), &self.root(), &mut found);
            found.sort();
            return found;

            fn walk(root: &Path, dir: &Path, found: &mut Vec<String>) {
                let Ok(entries) = std::fs::read_dir(dir) else {
                    return;
                };
                for entry in entries.flatten() {
                    let path = entry.path();
                    let name = entry.file_name().to_string_lossy().into_owned();
                    if name == ".git" {
                        continue;
                    }
                    if name.starts_with(".burlmd-trash") {
                        found.push(
                            path.strip_prefix(root)
                                .unwrap_or(&path)
                                .to_string_lossy()
                                .into_owned(),
                        );
                    }
                    if path.is_dir() {
                        walk(root, &path, found);
                    }
                }
            }
        }

        /// Makes the next statement against `table` fail, so that a failure
        /// arising *after* the filesystem phase can be driven deterministically
        /// rather than waited for.
        fn inject_index_failure(&self, sql: &str) {
            self.workspace
                .with_db(|conn| {
                    conn.execute_batch(sql)?;
                    Ok(())
                })
                .unwrap();
        }

        fn commit_baseline(&self) {
            crate::git::operations::commit_all(
                &self.root(),
                "baseline",
                "Test",
                "test@example.com",
            )
            .unwrap();
        }

        fn git(&self, args: &[&str]) -> String {
            let output = Command::new("git")
                .args(args)
                .current_dir(self.root())
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .env("GIT_CONFIG_SYSTEM", "/dev/null")
                .output()
                .expect("git CLI available in devenv shell");
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        }
    }

    fn fixture() -> Fixture {
        static NEXT_WORKSPACE: AtomicU32 = AtomicU32::new(0);

        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("bundle");
        std::fs::create_dir_all(&root).unwrap();
        crate::git::operations::init_repo(&root).unwrap();

        let key = [0x5au8; 32]; // throwaway, never the real Keychain entry
        let conn = crate::db::connection::open_encrypted_db_with_key(
            &dir.path().join("index.sqlite3"),
            &key,
        )
        .unwrap();
        crate::db::connection::init_schema(&conn).unwrap();

        // Unique per fixture: the open-note registry is process-wide and the
        // harness runs these in parallel.
        let workspace_id = format!(
            "lifecycle-{}",
            NEXT_WORKSPACE.fetch_add(1, Ordering::SeqCst)
        );
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES (?1, 'Test Workspace', 'local', NULL, ?2)",
            rusqlite::params![workspace_id, root.to_string_lossy()],
        )
        .unwrap();

        // An idle interval no test waits out: every tier is fired explicitly.
        let workspace = Workspace::for_test(conn, workspace_id, root, Duration::from_secs(3600));
        Fixture { dir, workspace }
    }

    /// A conformant Note. Bodies are written with an explicit trailing newline
    /// so that a rewrite that changed line endings would be visible.
    fn note(title: &str, body: &str) -> String {
        format!("---\ntype: Note\ntitle: {title}\n---\n\n{body}\n")
    }

    /// A Link to `concept_id` with `text` as its display text, in the exact
    /// form burlmd writes.
    fn link(text: &str, concept_id: &str) -> String {
        crate::okf::serialize_link(text, concept_id)
    }

    fn link_targets_in(ast: &[AstNode]) -> Vec<(String, bool)> {
        let mut out = Vec::new();
        collect(ast, &mut out);
        return out;

        fn collect(nodes: &[AstNode], out: &mut Vec<(String, bool)>) {
            for node in nodes {
                match node {
                    AstNode::Heading { content, .. } | AstNode::Paragraph { content } => {
                        for element in content {
                            if let InlineElement::Link {
                                target_id, exists, ..
                            } = element
                            {
                                out.push((target_id.clone(), *exists));
                            }
                        }
                    }
                    AstNode::List { items, .. } => collect(items, out),
                    AstNode::ListItem { content, .. } | AstNode::Blockquote { nodes: content } => {
                        collect(content, out);
                    }
                    _ => {}
                }
            }
        }
    }

    // -- creation ------------------------------------------------------------

    /// Gherkin: a Note created in a Directory has a file with a frontmatter
    /// block carrying a non-empty type and that title, and it is indexed.
    #[test]
    fn create_note_writes_a_conformant_block_and_indexes_it() {
        let f = fixture();
        create_directory(&f.workspace, "projects").unwrap();

        let state = create_note(&f.workspace, "projects", "My Great Idea").unwrap();

        assert_eq!(state.metadata.id, "projects/My Great Idea");
        assert_eq!(state.metadata.title, "My Great Idea");
        assert!(state.metadata.okf_conformant);
        let source = f.read("projects/My Great Idea.md");
        assert!(
            source.starts_with("---\ntype: Note\ntitle: My Great Idea\n---\n"),
            "{source:?}"
        );
        assert_eq!(f.note_ids(), vec!["projects/My Great Idea".to_string()]);
        assert_eq!(f.directory_ids(), vec!["projects".to_string()]);
    }

    /// The filename is the title verbatim plus `.md`, with no slugification,
    /// because CAP-GRAPH-04's create-on-follow has to invert the derivation.
    #[test]
    fn the_filename_is_the_title_verbatim() {
        let f = fixture();

        create_note(&f.workspace, "", "Q3 (draft) & notes").unwrap();

        assert!(f.exists("Q3 (draft) & notes.md"));
        // A title YAML would otherwise reinterpret still reads back as itself.
        let state = persist::open_note(&f.workspace, "Q3 (draft) & notes")
            .unwrap()
            .1;
        assert_eq!(state.metadata.title, "Q3 (draft) & notes");
    }

    /// `create_note` returns the state of an **open** Note, so the first
    /// `update_block` substitutes into a buffer that was established.
    #[test]
    fn a_created_note_is_open_for_editing_immediately() {
        let f = fixture();

        create_note(&f.workspace, "", "Fresh").unwrap();

        let session = persist::lookup(f.workspace.id(), "Fresh").unwrap();
        assert!(session.is_some(), "create_note must register a session");
    }

    /// A created Note enters version history at creation, like every other
    /// lifecycle operation.
    ///
    /// The regression this pins: `create_note` made no commit and tier 3's gate
    /// (`session_edited`) stays false for a fresh Note nobody has typed into, so
    /// a Note created and navigated away from — or one whose idle write landed
    /// before a crash — sat in the bundle as an untracked file that no commit
    /// covered. That is the window `architecture/resilience.md` closes for every
    /// other operation here: rename, move and delete all commit.
    #[test]
    fn a_created_note_is_in_version_history_before_anything_is_typed_into_it() {
        let f = fixture();
        f.commit_baseline();

        create_note(&f.workspace, "", "Fresh").unwrap();

        assert_eq!(
            f.git(&["show", "HEAD:Fresh.md"]),
            conformant_frontmatter("Fresh").trim_end(),
            "the created file must be in HEAD's tree"
        );
        assert_eq!(f.git(&["log", "--format=%s", "-1"]), "Create Fresh");
    }

    /// Delete's promise — "recoverable from local version history" — is only
    /// true if the content it deletes was ever committed. Without the create
    /// commit, deleting an untouched fresh Note committed nothing at all
    /// (`commit_paths` returns `None` when the tree is unchanged, and removing a
    /// path `HEAD` never held changes nothing), so the Note's content existed in
    /// no commit anywhere and the deletion was unrecoverable.
    #[test]
    fn deleting_a_never_typed_note_still_leaves_it_recoverable_from_history() {
        let f = fixture();
        f.commit_baseline();
        create_note(&f.workspace, "", "Fresh").unwrap();
        persist::discard_session(&f.workspace, "Fresh").unwrap();

        delete_note(&f.workspace, "Fresh").unwrap();

        assert!(!f.exists("Fresh.md"));
        assert_eq!(f.git(&["log", "--format=%s", "-1"]), "Delete Fresh");
        assert_eq!(
            f.git(&["show", "HEAD~1:Fresh.md"]),
            conformant_frontmatter("Fresh").trim_end(),
            "the deleted content must still be recoverable one commit back"
        );
    }

    /// The create commit does not duplicate itself when the session that
    /// follows it is edited and closed: `commit_message` asks `path_in_head`,
    /// which now answers yes, so tier 3 records an Update rather than a second
    /// Create.
    #[test]
    fn creating_typing_and_closing_records_a_create_and_exactly_one_update() {
        let f = fixture();
        f.commit_baseline();

        create_note(&f.workspace, "", "Fresh").unwrap();
        let session = persist::lookup(f.workspace.id(), "Fresh").unwrap().unwrap();
        session
            .insert_block(&[0], "Typed after creation.".to_string())
            .unwrap();
        session.close().unwrap();

        let subjects = f.git(&["log", "--format=%s"]);
        let subjects: Vec<&str> = subjects.lines().collect();
        assert_eq!(
            subjects,
            vec!["Update Fresh", "Create Fresh", "baseline"],
            "expected exactly one Create and one Update"
        );
        assert!(f.read("Fresh.md").contains("Typed after creation."));
    }

    // -- collisions and reserved names (STOP 2) ------------------------------

    /// Gherkin, both halves of the same rule: a title deriving to an existing
    /// filename, or to a reserved one, reports the path unavailable and changes
    /// nothing — on **create and on rename alike**.
    #[test]
    fn a_title_collision_and_a_reserved_name_are_refused_on_create_and_on_rename() {
        let f = fixture();
        f.write("Taken.md", &note("Taken", "occupied"));
        f.write("Movable.md", &note("Movable", "body"));
        f.reindex();

        assert!(matches!(
            create_note(&f.workspace, "", "Taken"),
            Err(AppError::PathUnavailable(_))
        ));
        assert!(matches!(
            create_note(&f.workspace, "", "index"),
            Err(AppError::PathUnavailable(_))
        ));
        assert!(matches!(
            rename_note(&f.workspace, "Movable", "Taken"),
            Err(AppError::PathUnavailable(_))
        ));
        assert!(matches!(
            rename_note(&f.workspace, "Movable", "log"),
            Err(AppError::PathUnavailable(_))
        ));

        // Nothing created, nothing changed.
        assert_eq!(
            f.note_ids(),
            vec!["Movable".to_string(), "Taken".to_string()]
        );
        assert_eq!(f.read("Taken.md"), note("Taken", "occupied"));
        assert_eq!(f.read("Movable.md"), note("Movable", "body"));
        assert!(!f.exists("index.md"));
        assert!(!f.exists("log.md"));
    }

    /// The filesystem is checked as well as the index. A file the index has
    /// never seen still occupies its path.
    #[test]
    fn availability_is_checked_against_the_filesystem_not_only_the_index() {
        let f = fixture();
        f.write("Unindexed.md", "written by another tool\n");

        let result = create_note(&f.workspace, "", "Unindexed");

        assert!(
            matches!(result, Err(AppError::PathUnavailable(_))),
            "{result:?}"
        );
        assert_eq!(f.read("Unindexed.md"), "written by another tool\n");
    }

    /// A title that cannot be derived into a filename is refused rather than
    /// silently substituted (`data-models/okf-bundle.md`).
    #[test]
    fn an_underivable_title_is_refused() {
        let f = fixture();

        for title in ["", "   ", "a/b", "..", "."] {
            assert!(
                matches!(
                    create_note(&f.workspace, "", title),
                    Err(AppError::PathUnavailable(_))
                ),
                "{title:?} should not be derivable"
            );
        }
    }

    // -- rename: the inbound-link sweep (STOP 1) -----------------------------

    /// The criterion in its mandated shape: the target's title **contains a
    /// space**. With single-word titles the fixture passes vacuously — a bare
    /// destination with no space parses as a Link either way, so there would be
    /// no edge to get wrong.
    #[test]
    fn three_sources_linking_to_a_multi_word_title_all_follow_the_rename() {
        let f = fixture();
        f.write("Meeting Notes.md", &note("Meeting Notes", "the target"));
        for source in ["one", "two", "three"] {
            f.write(
                &format!("{source}.md"),
                &note(
                    source,
                    &format!("see {}", link("Meeting Notes", "Meeting Notes")),
                ),
            );
        }
        f.reindex();
        assert_eq!(
            f.backlink_sources("Meeting Notes"),
            vec!["one".to_string(), "three".to_string(), "two".to_string()],
            "the fixture must actually produce three edges, or this passes vacuously"
        );

        rename_note(&f.workspace, "Meeting Notes", "Standup Notes").unwrap();

        assert_eq!(
            f.backlink_sources("Standup Notes"),
            vec!["one".to_string(), "three".to_string(), "two".to_string()]
        );
        assert!(
            f.backlink_sources("Meeting Notes").is_empty(),
            "an edge is still pointing at the old concept id"
        );
        for source in ["one", "two", "three"] {
            let body = f.read(&format!("{source}.md"));
            assert!(body.contains("</Standup Notes.md>"), "{source}: {body:?}");
            assert!(!body.contains("Meeting Notes.md"), "{source}: {body:?}");
        }
    }

    /// Gherkin: `LifecycleEffects.rewritten` names all three sources. Their own
    /// ids did not change, so the shell has no other way to learn their bytes
    /// moved.
    #[test]
    fn lifecycle_effects_names_every_rewritten_source() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        for source in ["one", "two", "three"] {
            f.write(
                &format!("{source}.md"),
                &note(source, &link("Old Name", "Old Name")),
            );
        }
        f.reindex();

        let (state, effects) = rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        assert_eq!(state.metadata.id, "New Name");
        assert_eq!(
            effects.rewritten,
            vec!["one".to_string(), "three".to_string(), "two".to_string()]
        );
        assert!(
            effects.remapped.is_empty(),
            "`remapped` reports Notes moved *beyond* the one invoked on"
        );
    }

    /// Gherkin: renaming `Old` to `New` where a Note links to **both** succeeds
    /// and the two inbound edges collapse to one, rather than failing on the
    /// `links` primary key. This is the third STOP condition: a collision to
    /// merge, not a conflict to report.
    #[test]
    fn renaming_onto_a_ghost_target_collapses_two_edges_rather_than_failing() {
        let f = fixture();
        f.write("Old.md", &note("Old", "target"));
        f.write(
            "src.md",
            &note(
                "src",
                &format!("{} and {}", link("Old", "Old"), link("New", "New")),
            ),
        );
        f.reindex();
        assert_eq!(
            f.link_targets("src"),
            vec!["New".to_string(), "Old".to_string()],
            "the fixture must start with both edges, or the collision never arises"
        );

        let result = rename_note(&f.workspace, "Old", "New");

        assert!(
            result.is_ok(),
            "the primary key collision must merge: {result:?}"
        );
        assert_eq!(f.link_targets("src"), vec!["New".to_string()]);
        assert_eq!(
            f.count("SELECT count(*) FROM links WHERE source_id = 'src'"),
            1
        );
    }

    /// Gherkin: a Note that links to itself gets both substitutions — its
    /// frontmatter title and its self-Link.
    #[test]
    fn renaming_a_self_linking_note_rewrites_the_title_and_the_self_link() {
        let f = fixture();
        f.write(
            "Me Myself.md",
            &note(
                "Me Myself",
                &format!("a loop back to {}", link("Me Myself", "Me Myself")),
            ),
        );
        f.reindex();

        rename_note(&f.workspace, "Me Myself", "You Yourself").unwrap();

        let source = f.read("You Yourself.md");
        assert!(source.contains("title: You Yourself"), "{source:?}");
        assert!(source.contains("</You Yourself.md>"), "{source:?}");
        assert!(
            !source.contains("Me Myself.md"),
            "a destination still names the old concept id: {source:?}"
        );
        // The Link's *display text* is deliberately untouched: it is the user's
        // own prose, and re-serializing it would double-escape a title an
        // author escaped by hand (`prd/constraints.md`, Edit Fidelity). Only
        // the destination carries identity.
        assert!(
            source.contains("[Me Myself](</You Yourself.md>)"),
            "{source:?}"
        );
        assert_eq!(
            f.link_targets("You Yourself"),
            vec!["You Yourself".to_string()]
        );
        assert!(!f.exists("Me Myself.md"));
    }

    /// Gherkin: the fourth criterion, and the first STOP condition. A rename
    /// that fails part-way through the sweep leaves no file, index row or link
    /// changed.
    ///
    /// The injection is a source Note in a directory the process cannot write
    /// to: planning reads it fine, and the write fails **after** an earlier
    /// source has already been rewritten, which is precisely the partial state
    /// that must not survive.
    #[cfg(unix)]
    #[test]
    fn a_rename_that_fails_partway_leaves_nothing_changed() {
        use std::os::unix::fs::PermissionsExt;

        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("aaa.md", &note("aaa", &link("Old Name", "Old Name")));
        f.write("locked/zzz.md", &note("zzz", &link("Old Name", "Old Name")));
        f.reindex();
        let before_target = f.read("Old Name.md");
        let before_first = f.read("aaa.md");
        let before_locked = f.read("locked/zzz.md");

        let locked = f.root().join("locked");
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o555)).unwrap();
        let result = rename_note(&f.workspace, "Old Name", "New Name");
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o755)).unwrap();

        assert!(
            result.is_err(),
            "the rename must fail rather than half-apply"
        );
        assert!(
            !f.exists("New Name.md"),
            "the target file was renamed anyway"
        );
        assert_eq!(f.read("Old Name.md"), before_target);
        assert_eq!(
            f.read("aaa.md"),
            before_first,
            "the first source was rewritten and never restored — a partial sweep survived"
        );
        assert_eq!(f.read("locked/zzz.md"), before_locked);
        assert_eq!(
            f.note_ids(),
            vec![
                "Old Name".to_string(),
                "aaa".to_string(),
                "locked/zzz".to_string()
            ]
        );
        assert_eq!(
            f.backlink_sources("Old Name"),
            vec!["aaa".to_string(), "locked/zzz".to_string()]
        );
        assert!(f.backlink_sources("New Name").is_empty());
    }

    /// A source Note whose Link cannot be rewritten in place — a reference-style
    /// definition — fails the whole rename rather than being skipped. Skipping
    /// is the silent partial rewrite risk 8 exists to prevent.
    #[test]
    fn an_unrewritable_inbound_link_fails_the_rename() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("ref.md", &note("ref", "see [it][t]\n\n[t]: </Old Name.md>"));
        f.reindex();
        assert_eq!(f.backlink_sources("Old Name"), vec!["ref".to_string()]);

        let result = rename_note(&f.workspace, "Old Name", "New Name");

        assert!(result.is_err(), "{result:?}");
        assert!(f.exists("Old Name.md"));
        assert!(!f.exists("New Name.md"));
    }

    // -- rename: search, drafts and sessions ---------------------------------

    /// Gherkin: `notes_fts` indexes the title, so a rename that updated only
    /// `notes` would leave search answering with the previous one.
    #[test]
    fn a_renamed_note_is_found_by_its_new_title_and_no_longer_by_its_old() {
        let f = fixture();
        f.write(
            "Antidisestablishmentarianism.md",
            &note("Antidisestablishmentarianism", "body"),
        );
        f.reindex();
        assert_eq!(f.raw_fts_matches("Antidisestablishmentarianism"), 1);

        rename_note(
            &f.workspace,
            "Antidisestablishmentarianism",
            "Floccinaucinihilipilification",
        )
        .unwrap();

        assert_eq!(f.raw_fts_matches("Floccinaucinihilipilification"), 1);
        assert_eq!(
            f.raw_fts_matches("Antidisestablishmentarianism"),
            0,
            "the old title still matches, so search answers with a dead concept"
        );
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 1);
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 1);
    }

    /// Gherkin: the one case the missing foreign key exists to permit. The
    /// draft row is re-keyed to the new concept id **and rewritten**, with its
    /// frontmatter `title` carrying the new value — preserving it byte for byte
    /// would make the next write revert the rename.
    #[test]
    fn renaming_a_note_with_an_unflushed_draft_rekeys_and_rewrites_the_row() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "on disk"));
        f.reindex();
        f.put_draft("Old Name", &note("Old Name", "unflushed work in progress"));

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        assert!(
            f.draft_row("Old Name").is_none(),
            "the row was not re-keyed"
        );
        let draft = f
            .draft_row("New Name")
            .expect("the draft must survive the rename");
        assert!(draft.contains("title: New Name"), "{draft:?}");
        assert!(
            draft.contains("unflushed work in progress"),
            "the drafted body must be intact: {draft:?}"
        );
    }

    /// Gherkin: a Note open with buffered edits when it is renamed writes the
    /// new title on the next idle write and is not refused with a revision
    /// mismatch — its working source, span map and recorded revision all move
    /// with the rename.
    #[test]
    fn a_note_open_with_buffered_edits_still_writes_after_a_rename() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "first block"));
        f.reindex();
        let session = f.open("Old Name");
        session.update_block(&[0], "first block, edited\n").unwrap();

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        let moved = persist::lookup(f.workspace.id(), "New Name")
            .unwrap()
            .expect("the session must have followed the rename");
        moved.flush().expect("the idle write must not be refused");
        let written = f.read("New Name.md");
        assert!(written.contains("title: New Name"), "{written:?}");
        assert!(written.contains("first block, edited"), "{written:?}");
        assert!(!f.exists("Old Name.md"));
    }

    /// Gherkin: Note B is open with buffered edits and links to A. A rename
    /// rewrites B's bytes too, so B's buffer, spans and revision must move with
    /// it — otherwise B's next verbatim write reverts the rewrite.
    #[test]
    fn a_source_note_open_with_buffered_edits_writes_and_its_link_resolves() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write(
            "b.md",
            &note(
                "b",
                &format!("intro\n\nsee {}", link("Old Name", "Old Name")),
            ),
        );
        f.reindex();
        let b = f.open("b");
        b.update_block(&[0], "intro, edited\n").unwrap();

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        b.flush().expect("B's next write must not be refused");
        let written = f.read("b.md");
        assert!(written.contains("intro, edited"), "{written:?}");
        assert!(
            written.contains("</New Name.md>"),
            "B's verbatim write reverted the rewrite: {written:?}"
        );
        assert_eq!(f.link_targets("b"), vec!["New Name".to_string()]);
        let resolved = link_targets_in(&b.note_state().unwrap().ast);
        assert_eq!(resolved, vec![("New Name".to_string(), true)]);
    }

    /// Gherkin: B carries an unflushed draft holding a Link to A. `open_note`
    /// parses the draft in preference to disk, so a row left unrewritten
    /// reverts the rename one session later.
    ///
    /// **The Link is in the draft and *not* on disk**, which is the whole point
    /// of the fixture. Putting it in both makes the test pass against a sweep
    /// driven only by the `links` table — B would be a candidate because of its
    /// on-disk Link, and the draft would be rewritten as a side effect of that.
    /// A draft row is persistent state that outlives the process and is parsed
    /// in preference to disk, so it is a Link the index has never seen and the
    /// sweep must find on its own.
    #[test]
    fn a_link_that_exists_only_in_an_unflushed_draft_is_rewritten() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("b.md", &note("b", "nothing on disk points anywhere"));
        f.reindex();
        assert!(
            f.backlink_sources("Old Name").is_empty(),
            "the index must not know about this Link, or the test is vacuous"
        );
        f.put_draft(
            "b",
            &note(
                "b",
                &format!("drafted prose {}", link("Old Name", "Old Name")),
            ),
        );

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        let draft = f.draft_row("b").expect("the draft must survive the rename");
        assert!(
            draft.contains("</New Name.md>"),
            "the draft still holds the old Link, and it is parsed in preference \
             to disk — the rename reverts one session later: {draft:?}"
        );

        let (_, state) = persist::open_note(&f.workspace, "b").unwrap();
        assert!(state.restored_from_draft);
        let restored = persist::lookup(f.workspace.id(), "b")
            .unwrap()
            .unwrap()
            .working_source()
            .unwrap();
        assert!(restored.contains("drafted prose"), "{restored:?}");
        assert!(restored.contains("</New Name.md>"), "{restored:?}");
    }

    /// The same hole one tier earlier: B is open and its buffer holds a Link
    /// that has never reached disk, so the `links` table cannot know about it.
    /// Left unrewritten, B's next tier 2 write puts the dead concept id on disk
    /// *and indexes it* — recreating the ghost edge the rename removed, which
    /// create-on-follow then turns back into the concept.
    #[test]
    fn a_link_that_exists_only_in_an_open_buffer_is_rewritten() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("b.md", &note("b", "placeholder"));
        f.reindex();
        let b = f.open("b");
        b.update_block(&[0], &format!("see {}\n", link("Old Name", "Old Name")))
            .unwrap();
        assert!(
            f.backlink_sources("Old Name").is_empty(),
            "the index must not know about this Link, or the test is vacuous"
        );
        assert!(!f.read("b.md").contains("Old Name.md"));

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        let buffered = b.working_source().unwrap();
        assert!(
            buffered.contains("</New Name.md>"),
            "B's buffer still holds the old Link: {buffered:?}"
        );

        // End to end: the buffer reaching disk must index the *new* edge.
        b.flush().unwrap();
        assert!(f.read("b.md").contains("</New Name.md>"));
        assert_eq!(f.link_targets("b"), vec!["New Name".to_string()]);
        assert!(
            f.backlink_sources("Old Name").is_empty(),
            "B's write resurrected the edge the rename removed"
        );
    }

    /// The same hole again, with the one detail that made the sweep drop the
    /// candidate anyway: **B's file is gone**.
    ///
    /// That is not a contrived fixture, it is the population
    /// `persist::open_note`'s recovery branch exists for — a Note deleted
    /// underneath a live session, whose work survives only in its `drafts` row.
    /// `plan_affected` seeded B from `drafts`, read its (absent) file, and
    /// `continue`d on the strength of the missing bytes, so the Link the row
    /// holds was never rewritten. Recovering that draft and letting it write
    /// then put the dead concept id straight back on disk and into the index —
    /// `architecture/risks.md` risk 8, reached through the exact path the
    /// draft sweep was added to close.
    #[test]
    fn a_link_in_a_draft_whose_file_has_vanished_is_still_rewritten() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("b.md", &note("b", "nothing on disk points anywhere"));
        f.reindex();
        f.put_draft(
            "b",
            &note(
                "b",
                &format!("drafted prose {}", link("Old Name", "Old Name")),
            ),
        );
        // Deleted by something outside this application, after the draft was
        // written: the file is gone, the row is the only copy of the work.
        std::fs::remove_file(f.root().join("b.md")).unwrap();

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        let draft = f.draft_row("b").expect("the draft must survive the rename");
        assert!(
            draft.contains("</New Name.md>"),
            "the draft of a Note whose file has vanished still holds the old Link, and \
             `open_note` recovers exactly that row — the rename reverts on its first \
             write: {draft:?}"
        );

        // End to end, through the recovery branch the fixture is about: the
        // recovered session writes the file back, and what it writes is the
        // rewritten Link rather than the dead one.
        let (session, state) = persist::open_note(&f.workspace, "b").unwrap();
        assert!(state.restored_from_draft);
        session.flush().unwrap();
        assert!(
            f.read("b.md").contains("</New Name.md>"),
            "{:?}",
            f.read("b.md")
        );
        assert_eq!(f.link_targets("b"), vec!["New Name".to_string()]);
        assert!(
            f.backlink_sources("Old Name").is_empty(),
            "the recovered session's write resurrected the edge the rename removed"
        );
    }

    /// The session-buffer half of the same case: B is open over a file that
    /// has since been deleted (`awaiting_recreate`), and the Link the rename
    /// has to follow exists only in its working source.
    #[test]
    fn a_link_in_the_buffer_of_a_session_whose_file_has_vanished_is_still_rewritten() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("b.md", &note("b", "placeholder"));
        f.reindex();
        let b = f.open("b");
        b.update_block(&[0], &format!("see {}\n", link("Old Name", "Old Name")))
            .unwrap();
        std::fs::remove_file(f.root().join("b.md")).unwrap();

        rename_note(&f.workspace, "Old Name", "New Name").unwrap();

        let buffered = b.working_source().unwrap();
        assert!(
            buffered.contains("</New Name.md>"),
            "the buffer of a session over a vanished file still holds the old Link, and its \
             next write recreates the concept the rename removed: {buffered:?}"
        );
    }

    /// The other side of the same branch: a candidate the `links` table alone
    /// produced, with no file, no draft and no session, is still dropped rather
    /// than failing the rename. Its rows are somebody else's stale record and
    /// the next reindex rebuilds them.
    #[test]
    fn a_stale_link_row_with_no_file_draft_or_session_does_not_fail_a_rename() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("b.md", &note("b", &link("Old Name", "Old Name")));
        f.reindex();
        assert_eq!(f.backlink_sources("Old Name"), vec!["b".to_string()]);
        std::fs::remove_file(f.root().join("b.md")).unwrap();

        rename_note(&f.workspace, "Old Name", "New Name").expect("a stale row must not refuse");

        assert!(f.exists("New Name.md"));
        assert!(f.draft_row("b").is_none(), "a draft row was invented");
    }

    // -- move ----------------------------------------------------------------

    /// Gherkin: a moved Note's concept id reflects its new path and every
    /// inbound link resolves.
    #[test]
    fn moving_a_note_changes_its_id_and_every_inbound_link_follows() {
        let f = fixture();
        f.write("Meeting Notes.md", &note("Meeting Notes", "target"));
        f.write(
            "src.md",
            &note("src", &link("Meeting Notes", "Meeting Notes")),
        );
        f.reindex();
        create_directory(&f.workspace, "archive/2026").unwrap();

        let (state, effects) = move_note(&f.workspace, "Meeting Notes", "archive/2026").unwrap();

        assert_eq!(state.metadata.id, "archive/2026/Meeting Notes");
        assert_eq!(state.metadata.path, "archive/2026/Meeting Notes.md");
        assert!(f.exists("archive/2026/Meeting Notes.md"));
        assert!(!f.exists("Meeting Notes.md"));
        assert_eq!(effects.rewritten, vec!["src".to_string()]);
        assert!(
            effects.remapped.is_empty(),
            "`remapped` reports Notes moved *beyond* the one invoked on, whose \
             new id the returned NoteState already carries"
        );
        assert_eq!(
            f.link_targets("src"),
            vec!["archive/2026/Meeting Notes".to_string()]
        );
        assert!(f
            .read("src.md")
            .contains("</archive/2026/Meeting Notes.md>"));
    }

    /// A move leaves the moved Note's frontmatter alone — it changes location,
    /// not title — but a **self-Link is still an inbound Link** and moves with
    /// the concept id.
    #[test]
    fn a_move_rewrites_a_self_link_but_not_the_title() {
        let f = fixture();
        f.write(
            "Loop.md",
            &note("Loop", &format!("back to {}", link("Loop", "Loop"))),
        );
        f.reindex();
        create_directory(&f.workspace, "sub").unwrap();

        move_note(&f.workspace, "Loop", "sub").unwrap();

        let source = f.read("sub/Loop.md");
        assert!(source.contains("title: Loop"), "{source:?}");
        assert!(source.contains("</sub/Loop.md>"), "{source:?}");
        assert_eq!(f.link_targets("sub/Loop"), vec!["sub/Loop".to_string()]);
    }

    #[test]
    fn moving_onto_an_occupied_filename_or_a_missing_directory_is_refused() {
        let f = fixture();
        f.write("a.md", &note("a", "body"));
        f.write("sub/a.md", &note("a", "other"));
        f.reindex();

        assert!(matches!(
            move_note(&f.workspace, "a", "sub"),
            Err(AppError::PathUnavailable(_))
        ));
        assert!(matches!(
            move_note(&f.workspace, "a", "nowhere"),
            Err(AppError::PathUnavailable(_))
        ));
        assert!(f.exists("a.md"));
    }

    // -- deletion ------------------------------------------------------------

    /// Gherkin: the `notes` cascade removes `fts_mapping`, which is the only
    /// pointer to the FTS row, so the FTS row must be deleted **first** or it
    /// becomes permanently unreachable and undeletable — and the deleted Note's
    /// full text stays searchable in the encrypted index indefinitely.
    #[test]
    fn deleting_a_note_leaves_no_reachable_or_orphaned_full_text_row() {
        let f = fixture();
        f.write(
            "Doomed.md",
            &note("Doomed", "antidisestablishmentarianism is distinctive"),
        );
        f.reindex();
        assert_eq!(f.raw_fts_matches("antidisestablishmentarianism"), 1);

        delete_note(&f.workspace, "Doomed").unwrap();

        assert_eq!(
            f.raw_fts_matches("antidisestablishmentarianism"),
            0,
            "the notes_fts row is orphaned and now undeletable"
        );
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 0);
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 0);
        assert!(f.note_ids().is_empty());
        assert!(!f.exists("Doomed.md"));
    }

    /// Gherkin: the `drafts` table has no foreign key, so nothing cascades and
    /// the deletion must clear it explicitly.
    #[test]
    fn deleting_a_note_clears_its_draft_row_explicitly() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "body"));
        f.reindex();
        f.put_draft("Doomed", &note("Doomed", "unflushed"));

        delete_note(&f.workspace, "Doomed").unwrap();

        assert!(f.draft_row("Doomed").is_none());
        assert_eq!(f.count("SELECT count(*) FROM drafts"), 0);
    }

    /// Gherkin: the deletion is committed and the prior content is recoverable
    /// from local version history (CAP-LIFE-04).
    #[test]
    fn deleting_a_note_commits_the_deletion_so_the_prior_content_is_recoverable() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "words worth recovering"));
        f.reindex();
        f.commit_baseline();

        delete_note(&f.workspace, "Doomed").unwrap();

        assert!(!f.exists("Doomed.md"));
        assert_eq!(f.git(&["log", "--format=%s", "-1"]), "Delete Doomed");
        assert!(f
            .git(&["show", "HEAD~1:Doomed.md"])
            .contains("words worth recovering"));
    }

    /// Inbound Links to a deleted Note survive as ghost Links, which OKF §6.1
    /// requires consumers to tolerate and CAP-GRAPH-04 makes a feature.
    #[test]
    fn deleting_a_note_leaves_inbound_links_as_ghosts() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "body"));
        f.write("src.md", &note("src", &link("Doomed", "Doomed")));
        f.reindex();

        delete_note(&f.workspace, "Doomed").unwrap();

        assert_eq!(f.link_targets("src"), vec!["Doomed".to_string()]);
        assert_eq!(f.read("src.md"), note("src", &link("Doomed", "Doomed")));
    }

    /// An open Note that is deleted is retired without a flush: closing it
    /// normally would recreate the file the deletion just removed.
    #[test]
    fn deleting_an_open_note_retires_its_session_without_recreating_the_file() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "body"));
        f.reindex();
        let session = f.open("Doomed");
        session.update_block(&[0], "body, edited\n").unwrap();

        delete_note(&f.workspace, "Doomed").unwrap();

        assert!(persist::lookup(f.workspace.id(), "Doomed")
            .unwrap()
            .is_none());
        assert!(!f.exists("Doomed.md"));
    }

    // -- directories ---------------------------------------------------------

    /// An empty Directory has no file to represent it, so it exists in the
    /// `directories` table — with every intermediate level.
    #[test]
    fn create_directory_records_every_intermediate_level() {
        let f = fixture();

        create_directory(&f.workspace, "a/b/c").unwrap();

        assert_eq!(
            f.directory_ids(),
            vec!["a".to_string(), "a/b".to_string(), "a/b/c".to_string()]
        );
        assert!(f.root().join("a/b/c").is_dir());
    }

    /// A backslash in a Directory path is refused by every operation that takes
    /// one, and nothing is created, renamed or deleted.
    ///
    /// The regression this pins: the containment check ran *before* the `\` to
    /// `/` translation, so on Unix `..\..\etc` was one `Component::Normal`,
    /// passed, and only then became `../../etc` for `root().join(..)` — which
    /// walks out of the bundle. `create_directory` made directories outside it;
    /// `delete_directory` recursively removed one, because its journal is
    /// settled before the commit error propagates.
    #[test]
    fn a_backslash_in_a_directory_path_is_refused_by_every_operation() {
        let f = fixture();
        // A sibling of the bundle, reachable by `..` from inside it. Nothing
        // below may touch it.
        let outside = f.dir.path().join("outside");
        std::fs::create_dir_all(outside.join("nested")).unwrap();
        std::fs::write(outside.join("nested/secret.md"), "not ours\n").unwrap();
        f.write("kept.md", &note("kept", "body"));
        f.reindex();

        // `..\..\outside` traverses out of the bundle once translated;
        // `a\b` is the benign spelling of the same defect. Both are refused.
        for path in ["..\\..\\outside", "..\\..\\outside\\nested", "a\\b"] {
            for result in [
                create_directory(&f.workspace, path),
                rename_directory(&f.workspace, path, "renamed").map(|_| ()),
                delete_directory(&f.workspace, path).map(|_| ()),
                create_note(&f.workspace, path, "New Note").map(|_| ()),
                move_note(&f.workspace, "kept", path).map(|_| ()),
            ] {
                assert!(
                    matches!(result, Err(AppError::PathUnavailable(_))),
                    "{path:?} must be refused, got {result:?}"
                );
            }
        }

        assert!(
            outside.join("nested/secret.md").is_file(),
            "a directory outside the bundle must not be deleted"
        );
        assert!(
            !f.dir.path().join("renamed").exists(),
            "nothing outside the bundle may be renamed"
        );
        let beside: Vec<String> = std::fs::read_dir(f.dir.path())
            .unwrap()
            .filter_map(|e| e.ok().map(|e| e.file_name().to_string_lossy().into_owned()))
            .filter(|name| name != "bundle" && name != "outside")
            .filter(|name| !name.starts_with("index.sqlite3"))
            .collect();
        assert!(
            beside.is_empty(),
            "nothing may be created beside the bundle, found {beside:?}"
        );
        assert_eq!(f.directory_ids(), Vec::<String>::new());
        assert_eq!(f.note_ids(), vec!["kept".to_string()]);
        assert!(f.exists("kept.md"));
        assert!(
            !f.root().join("a").exists(),
            "a refused create must not materialize the leading segment either"
        );
    }

    /// Gherkin (CAP-LIFE-06): renaming a Directory moves its contents, remaps
    /// every Note beneath it, and rewrites inbound Links from Notes that are
    /// **not** in the subtree.
    #[test]
    fn renaming_a_directory_remaps_its_notes_and_rewrites_outside_links() {
        let f = fixture();
        f.write("old dir/One Note.md", &note("One Note", "first"));
        f.write("old dir/Two Note.md", &note("Two Note", "second"));
        f.write(
            "outside.md",
            &note("outside", &link("One Note", "old dir/One Note")),
        );
        f.reindex();

        let effects = rename_directory(&f.workspace, "old dir", "new dir").unwrap();

        assert_eq!(
            f.note_ids(),
            vec![
                "new dir/One Note".to_string(),
                "new dir/Two Note".to_string(),
                "outside".to_string()
            ]
        );
        assert!(f.exists("new dir/One Note.md"));
        assert!(!f.root().join("old dir").exists());
        assert_eq!(
            effects.remapped,
            vec![
                IdRemap {
                    old_id: "old dir/One Note".to_string(),
                    new_id: "new dir/One Note".to_string()
                },
                IdRemap {
                    old_id: "old dir/Two Note".to_string(),
                    new_id: "new dir/Two Note".to_string()
                },
            ]
        );
        assert_eq!(effects.rewritten, vec!["outside".to_string()]);
        assert!(f.read("outside.md").contains("</new dir/One Note.md>"));
        assert_eq!(
            f.link_targets("outside"),
            vec!["new dir/One Note".to_string()]
        );
        assert_eq!(
            f.directory_ids(),
            vec!["new dir".to_string()],
            "the old Directory row must not survive the rename"
        );
    }

    /// A Link *between* two Notes in the renamed subtree moves too: both ends
    /// changed identity in the same operation.
    #[test]
    fn renaming_a_directory_rewrites_links_inside_the_subtree() {
        let f = fixture();
        f.write(
            "old dir/One Note.md",
            &note("One Note", &link("Two Note", "old dir/Two Note")),
        );
        f.write("old dir/Two Note.md", &note("Two Note", "second"));
        f.reindex();

        rename_directory(&f.workspace, "old dir", "new dir").unwrap();

        let source = f.read("new dir/One Note.md");
        assert!(source.contains("</new dir/Two Note.md>"), "{source:?}");
        assert_eq!(
            f.link_targets("new dir/One Note"),
            vec!["new dir/Two Note".to_string()]
        );
    }

    #[test]
    fn renaming_a_directory_onto_an_occupied_name_is_refused() {
        let f = fixture();
        f.write("a/one.md", &note("one", "body"));
        f.write("b/two.md", &note("two", "body"));
        f.reindex();

        let result = rename_directory(&f.workspace, "a", "b");

        assert!(
            matches!(result, Err(AppError::PathUnavailable(_))),
            "{result:?}"
        );
        assert!(f.exists("a/one.md"));
        assert_eq!(f.note_ids(), vec!["a/one".to_string(), "b/two".to_string()]);
    }

    /// `rename_directory`'s occupied-destination check is same-**file**
    /// identity, not path spelling, which is what makes `Notes` -> `notes`
    /// possible at all.
    ///
    /// On a case-insensitive filesystem — macOS's default, and one of this
    /// project's two shipping targets (`data-models/okf-bundle.md`, "Case
    /// sensitivity follows the filesystem") — a case-only rename finds its own
    /// directory sitting at the destination, so the bare `exists()` this used to
    /// make refused it outright. `rename_note` had carried the escape for the
    /// Note equivalent since `ensure_path_available` was written; the Directory
    /// half simply never got it.
    ///
    /// **This is a test of [`is_same_file`] rather than of the rename**, and
    /// deliberately so: the defect only manifests where two spellings name one
    /// directory, ext4 gives every spelling its own inode, and neither a
    /// symbolic link nor a hard link can stand in (a symlinked destination is
    /// refused one step earlier by `directory_absolute`, and POSIX forbids hard
    /// links to directories). So the predicate the escape is built on is pinned
    /// directly: it says yes to one directory reached twice and no to two
    /// directories, which is the whole of what `rename_directory` asks it. The
    /// end-to-end behaviour is covered by
    /// `renaming_a_directory_onto_an_occupied_name_is_refused` above, which must
    /// keep refusing.
    #[test]
    fn the_same_file_escape_accepts_one_directory_and_refuses_two() {
        let f = fixture();
        std::fs::create_dir_all(f.root().join("Notes")).unwrap();
        std::fs::create_dir_all(f.root().join("Other")).unwrap();
        let notes = f.root().join("Notes");
        let other = f.root().join("Other");

        assert!(
            is_same_file(&notes, Some(&notes)),
            "a destination that IS the source directory must not read as occupied"
        );
        // Two spellings, one inode — what a case-only rename produces on a
        // case-insensitive filesystem, reached here through the one indirection
        // ext4 does offer.
        assert!(
            is_same_file(&f.root().join("./Notes"), Some(&notes)),
            "the same directory reached by a second spelling must not read as occupied"
        );
        assert!(
            !is_same_file(&other, Some(&notes)),
            "a genuinely different directory must still read as occupied"
        );
        assert!(
            !is_same_file(&notes, None),
            "with nothing held, every existing destination is a collision"
        );
    }

    /// The contract specifies a **recursive** delete — "and everything beneath
    /// it" — in one commit, returning the concept ids of every Note removed.
    #[test]
    fn deleting_a_directory_removes_everything_beneath_it_in_one_commit() {
        let f = fixture();
        f.write("doomed/One.md", &note("One", "distinctiveuno"));
        f.write("doomed/deep/Two.md", &note("Two", "distinctivedos"));
        f.write("kept.md", &note("kept", "body"));
        f.reindex();
        f.put_draft("doomed/One", &note("One", "unflushed"));
        f.commit_baseline();

        let removed = delete_directory(&f.workspace, "doomed").unwrap();

        assert_eq!(
            removed,
            vec!["doomed/One".to_string(), "doomed/deep/Two".to_string()]
        );
        assert!(!f.root().join("doomed").exists());
        assert_eq!(f.note_ids(), vec!["kept".to_string()]);
        assert!(f.directory_ids().is_empty());
        assert_eq!(f.raw_fts_matches("distinctiveuno"), 0);
        assert_eq!(f.raw_fts_matches("distinctivedos"), 0);
        assert_eq!(f.count("SELECT count(*) FROM drafts"), 0);
        assert_eq!(
            f.git(&["log", "--format=%s", "-1"]),
            "Delete directory doomed"
        );
        assert!(f
            .git(&["show", "HEAD~1:doomed/One.md"])
            .contains("distinctiveuno"));
    }

    // -- journal safety and the rollback arms --------------------------------

    /// The commit is the one step that can fail *after* the bundle and the
    /// index have both settled, and its error is propagated. The trash entry
    /// the deletion parked must not survive that: it holds the deleted Note's
    /// full content as an untracked file inside the bundle, which a later broad
    /// commit or a sync would publish.
    #[test]
    fn a_failed_commit_does_not_leave_a_trash_entry_in_the_bundle() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "words"));
        f.reindex();
        // Breaks `commit_paths` and nothing else: the file and the index move
        // exactly as they otherwise would.
        std::fs::remove_dir_all(f.root().join(".git")).unwrap();

        let result = delete_note(&f.workspace, "Doomed");

        assert!(result.is_err(), "the commit failure must be reported");
        assert!(
            f.trash_entries().is_empty(),
            "a trash entry survived a failed commit: {:?}",
            f.trash_entries()
        );
        assert!(!f.exists("Doomed.md"));
        assert!(f.note_ids().is_empty());
    }

    /// A rollback that cannot finish says so in the error the caller receives.
    ///
    /// This is the one case where "one operation that either completes or
    /// changes nothing" stops holding, and it used to stop holding silently:
    /// every arm of `FileJournal::rollback` discarded its failure with
    /// `let _ =`, so a bundle left part-way through an operation reported
    /// exactly the same error as one that was cleanly unwound. There is no
    /// logging in this crate, so the error is the only channel — and the
    /// recovery is manual, out of Git, which the user cannot begin without
    /// being told.
    ///
    /// The unwind is driven directly rather than through an operation, because
    /// the failure has to be injected *between* the journal's step and its
    /// inverse, which is a window no public entry point exposes.
    #[test]
    fn a_rollback_that_cannot_finish_is_named_in_the_error_it_returns() {
        let f = fixture();
        f.write("One.md", &note("One", "body"));
        let mut journal = FileJournal::default();
        journal
            .rename(&f.root().join("One.md"), &f.root().join("Two.md"))
            .unwrap();
        // The file the inverse rename would move back is gone, so the unwind
        // cannot complete.
        std::fs::remove_file(f.root().join("Two.md")).unwrap();

        let error = rolled_back(
            &mut journal,
            AppError::IoError("the failure that started this".to_string()),
        );

        let AppError::IoError(message) = error else {
            panic!("the original variant must survive: {error:?}");
        };
        assert!(
            message.contains("the failure that started this"),
            "the original failure must still be reported: {message}"
        );
        assert!(
            message.contains("1 of 1"),
            "the message must count what could not be undone: {message}"
        );
        assert!(
            message.contains("part-way"),
            "the message must say the bundle was left mid-operation: {message}"
        );
    }

    /// The ordinary case, unchanged: a rollback that completes adds nothing to
    /// the error, so the common path reads exactly as it did.
    #[test]
    fn a_rollback_that_finishes_leaves_the_error_exactly_as_it_was() {
        let f = fixture();
        f.write("One.md", &note("One", "body"));
        let before = f.read("One.md");
        let mut journal = FileJournal::default();
        journal
            .overwrite(&f.root().join("One.md"), b"clobbered\n")
            .unwrap();
        journal
            .rename(&f.root().join("One.md"), &f.root().join("Two.md"))
            .unwrap();

        let original = AppError::PathUnavailable("nothing to do with the journal".to_string());
        let error = rolled_back(&mut journal, original.clone());

        assert_eq!(error, original, "a clean unwind must not restate the error");
        assert_eq!(f.read("One.md"), before);
        assert!(!f.exists("Two.md"));
    }

    /// A commit that fails does not un-do the operation, so it must not skip
    /// the session reconciliation either.
    ///
    /// By the time `commit_paths` runs, the bundle and the index have both
    /// moved and there is nothing left to roll back — the journal is settled
    /// deliberately, on exactly that reasoning. Propagating the commit error
    /// with `?` at that point jumped over `carry_session_forward`, so the
    /// rename really had happened while the open session stayed keyed to the id
    /// the rename vacated: its next idle write is refused with a revision
    /// mismatch against a file that no longer exists, and the user's buffered
    /// work is stranded in a session nothing can reach.
    ///
    /// The error is still returned — version history genuinely did not record
    /// the rename — but it has to say which stage failed, because "rename
    /// failed" and "the rename happened and was not committed" call for
    /// different things from the caller.
    #[test]
    fn a_failed_commit_still_carries_open_sessions_forward_and_names_the_stage() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "first block"));
        f.reindex();
        let session = f.open("Old Name");
        session.update_block(&[0], "first block, edited\n").unwrap();
        // Breaks `commit_paths` and nothing else.
        std::fs::remove_dir_all(f.root().join(".git")).unwrap();

        let result = rename_note(&f.workspace, "Old Name", "New Name");

        let Err(error) = result else {
            panic!("the commit failure must be reported");
        };
        let message = format!("{error:?}");
        assert!(
            message.contains("commit"),
            "the error must name the commit as the failing stage, got {message}"
        );
        assert!(
            message.contains("succeeded") || message.contains("completed"),
            "the error must say the operation itself completed, got {message}"
        );

        // The rename really happened, so the session has to have followed it.
        assert!(f.exists("New Name.md"));
        assert!(!f.exists("Old Name.md"));
        assert!(
            persist::lookup(f.workspace.id(), "Old Name")
                .unwrap()
                .is_none(),
            "a session was left keyed to the vacated concept id"
        );
        let moved = persist::lookup(f.workspace.id(), "New Name")
            .unwrap()
            .expect("the session must have followed the rename");
        moved
            .flush()
            .expect("the carried-forward session must still be able to write");
        assert!(f.read("New Name.md").contains("first block, edited"));
    }

    /// The deletion arm of the same rule: the Note is gone from the bundle and
    /// from the index whether or not the commit recorded it, so its session
    /// must be retired rather than left open over a file that no longer exists.
    #[test]
    fn a_failed_delete_commit_still_discards_the_open_session() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "body"));
        f.write("doomed dir/Inside.md", &note("Inside", "body"));
        f.reindex();
        let _note_session = f.open("Doomed");
        let _dir_session = f.open("doomed dir/Inside");
        std::fs::remove_dir_all(f.root().join(".git")).unwrap();

        let note_result = delete_note(&f.workspace, "Doomed");
        let dir_result = delete_directory(&f.workspace, "doomed dir").map(|_| ());

        for (what, result) in [("note", &note_result), ("directory", &dir_result)] {
            let Err(error) = result else {
                panic!("{what}: the commit failure must be reported");
            };
            let message = format!("{error:?}");
            assert!(
                message.contains("commit"),
                "{what}: the error must name the commit as the failing stage, got {message}"
            );
        }

        assert!(persist::lookup(f.workspace.id(), "Doomed")
            .unwrap()
            .is_none());
        assert!(persist::lookup(f.workspace.id(), "doomed dir/Inside")
            .unwrap()
            .is_none());
        assert!(!f.exists("Doomed.md"));
        assert!(f.note_ids().is_empty());
    }

    /// The same obligation for a Directory, whose trash entry is a whole
    /// subtree rather than one file.
    #[test]
    fn a_failed_directory_commit_does_not_leave_a_trash_entry_in_the_bundle() {
        let f = fixture();
        f.write("doomed/One.md", &note("One", "words"));
        f.reindex();
        std::fs::remove_dir_all(f.root().join(".git")).unwrap();

        let result = delete_directory(&f.workspace, "doomed");

        assert!(result.is_err());
        assert!(
            f.trash_entries().is_empty(),
            "a trash subtree survived a failed commit: {:?}",
            f.trash_entries()
        );
    }

    /// A bundle legitimately holds files that are not Notes — an attachment, a
    /// foreign tool's `index.md`. `delete_directory` removes the whole subtree,
    /// so a pathspec built from the `notes` table alone would leave every one of
    /// those as a deletion Git knows about but was never told to record: a
    /// permanently dirty worktree, resolved by whatever commits next.
    #[test]
    fn deleting_a_directory_commits_the_non_note_files_it_removed_too() {
        let f = fixture();
        f.write("doomed/One.md", &note("One", "words"));
        f.write("doomed/diagram.png", "not a Note at all\n");
        f.write("doomed/index.md", "a reserved filename, never indexed\n");
        f.reindex();
        f.commit_baseline();
        assert_eq!(f.note_ids(), vec!["doomed/One".to_string()]);

        delete_directory(&f.workspace, "doomed").unwrap();

        assert_eq!(
            f.git(&["status", "--porcelain"]),
            "",
            "the non-Note files under the Directory are deleted on disk but \
             uncommitted, leaving the worktree permanently dirty"
        );
        assert!(f
            .git(&["show", "HEAD~1:doomed/diagram.png"])
            .contains("not a Note at all"));
    }

    /// The mirror of the same rule for a Directory *rename*: the filesystem
    /// step renames the whole directory, so a pathspec built from the affected
    /// Notes alone leaves every non-Note file under it as a rename Git can see
    /// and was never told to record.
    #[test]
    fn renaming_a_directory_commits_the_non_note_files_it_moved_too() {
        let f = fixture();
        f.write("projects/One.md", &note("One", "words"));
        f.write("projects/diagram.png", "an attachment, not a Note\n");
        f.reindex();
        f.commit_baseline();

        rename_directory(&f.workspace, "projects", "work").unwrap();

        assert_eq!(
            f.git(&["status", "--porcelain"]),
            "",
            "the non-Note files under the Directory moved on disk but were not \
             committed, leaving the worktree permanently dirty"
        );
        assert!(f.exists("work/diagram.png"));
        assert!(f
            .git(&["show", "HEAD:work/diagram.png"])
            .contains("an attachment, not a Note"));
    }

    /// `rename_directory` refuses a path whose type it does not handle. Its two
    /// mirrors did not, and each destroys something the caller did not name.
    ///
    /// The regressions this pins:
    ///
    /// - `delete_directory` pointed at a **file** trashed it, committed the
    ///   deletion and returned `Ok([])` — `removed` lists the Notes *under* the
    ///   prefix, and a file has none — leaving the Note's `notes` row and its
    ///   `notes_fts` text stranded in the encrypted index for the rest of the
    ///   session. `data-models/schema.sql` names that hazard specifically.
    /// - `delete_note` pointed at a **directory** named `*.md` — legal, and
    ///   what a foreign tool or a user may well have put there — reached
    ///   `remove_dir_all` through the journal's trash-then-discard and took the
    ///   whole subtree with it.
    #[test]
    fn a_lifecycle_call_refuses_a_path_of_the_wrong_type() {
        let f = fixture();
        f.write("One.md", &note("One", "distinctive searchable words"));
        f.write("Archive.md/inside.md", &note("inside", "nested and kept"));
        f.reindex();
        f.commit_baseline();
        let before = f.note_ids();
        assert_eq!(f.raw_fts_matches("distinctive"), 1);

        let refused = delete_directory(&f.workspace, "One.md");

        assert!(
            matches!(refused, Err(AppError::NotFound(_))),
            "deleting a file as a Directory must be refused, got {refused:?}"
        );
        assert!(f.exists("One.md"), "the file was trashed anyway");
        assert_eq!(f.note_ids(), before, "the index moved");
        assert_eq!(
            f.raw_fts_matches("distinctive"),
            1,
            "the Note's full text was stranded in the encrypted index"
        );

        let refused = delete_note(&f.workspace, "Archive");

        assert!(
            matches!(refused, Err(AppError::NotFound(_))),
            "deleting a directory as a Note must be refused, got {refused:?}"
        );
        assert!(
            f.exists("Archive.md/inside.md"),
            "the directory was removed recursively as if it were a Note"
        );
        assert_eq!(f.note_ids(), before, "the index moved");
        assert!(f.trash_entries().is_empty(), "a trash entry was parked");
        assert_eq!(
            f.git(&["status", "--porcelain"]),
            "",
            "a refused call must leave the worktree exactly as it found it"
        );
        assert_eq!(
            f.git(&["rev-list", "--count", "HEAD"]),
            "1",
            "a refused call recorded a commit"
        );
    }

    /// A name deriving to a dot-prefixed filename is refused rather than
    /// created and then silently dropped.
    ///
    /// `validate_title` permitted a leading `.`, but `index::scan::walk_bundle`
    /// skips dot-prefixed entries — deliberately, so a trash entry or a
    /// half-written `.name.pid.n.tmp` is invisible to the indexer rather than a
    /// phantom Note. A `.hidden` Note was therefore created, indexed and
    /// opened, and then dropped from the index by the next reindex, which now
    /// runs on every Workspace open. The file stayed on disk, orphaned, with
    /// its name permanently taken: `ensure_path_available` consults the
    /// filesystem as well as the index, so the second attempt at the same title
    /// is refused as a collision with a Note nothing can see.
    #[test]
    fn a_leading_dot_in_a_name_is_refused_rather_than_created_and_dropped() {
        let f = fixture();

        let refused = create_note(&f.workspace, "", ".hidden");

        assert!(
            matches!(refused, Err(AppError::PathUnavailable(_))),
            "a dot-prefixed title must be refused, got {refused:?}"
        );
        assert!(!f.exists(".hidden.md"), "the file was created anyway");
        assert!(f.note_ids().is_empty(), "the Note was indexed anyway");

        // The same rule wherever a segment is validated: a rename onto one, a
        // Directory name, and a Directory path.
        f.write("One.md", &note("One", "body"));
        f.reindex();
        for result in [
            rename_note(&f.workspace, "One", ".hidden").map(|_| ()),
            create_directory(&f.workspace, ".hidden"),
            create_note(&f.workspace, ".hidden", "New Note").map(|_| ()),
        ] {
            assert!(
                matches!(result, Err(AppError::PathUnavailable(_))),
                "got {result:?}"
            );
        }
        assert!(
            !f.exists(".hidden"),
            "a refused call materialized a directory"
        );
        assert_eq!(f.note_ids(), vec!["One".to_string()]);
        assert_eq!(f.directory_ids(), Vec::<String>::new());
    }

    /// A name carrying a line terminator derives a filename the Link syntax
    /// cannot address, which is risk 8 arriving through the front door rather
    /// than through a rewrite.
    ///
    /// `okf::serialize_link` writes the destination inside angle brackets, and
    /// CommonMark forbids a line ending inside one — so the text
    /// `[T](</Two\nLines.md>)` yields no `Link` event at all. The parser
    /// produces no edge, the index records no backlink, and `rename_note`
    /// reports success over link text it silently left pointing nowhere. A
    /// tab is deliberately still allowed: it round-trips through the same
    /// destination form.
    #[test]
    fn a_line_terminator_in_a_name_is_refused_and_nothing_is_created() {
        let f = fixture();

        for name in ["Two\nLines", "Carriage\rReturn", "Trailing\n", "\rLeading"] {
            let created = create_note(&f.workspace, "", name).map(|_| ());
            assert!(
                matches!(created, Err(AppError::PathUnavailable(_))),
                "create_note({name:?}) must be refused, got {created:?}"
            );
            let directory = create_directory(&f.workspace, name);
            assert!(
                matches!(directory, Err(AppError::PathUnavailable(_))),
                "create_directory({name:?}) must be refused, got {directory:?}"
            );
            // The same rule wherever a Directory path is normalized rather
            // than a single name validated.
            let nested = create_directory(&f.workspace, &format!("outer/{name}"));
            assert!(
                matches!(nested, Err(AppError::PathUnavailable(_))),
                "create_directory(outer/{name:?}) must be refused, got {nested:?}"
            );
            assert!(!f.exists(&format!("{name}.md")), "the file was created");
            assert!(!f.exists(name), "the directory was created");
        }

        assert!(f.note_ids().is_empty(), "a Note was indexed anyway");
        assert_eq!(f.directory_ids(), Vec::<String>::new());
        assert!(!f.exists("outer"), "an intermediate level was materialized");

        // A tab is not a line terminator and stays derivable, since it
        // round-trips through an angle-bracket destination.
        create_note(&f.workspace, "", "Tab\tstop").unwrap();
        assert!(f.exists("Tab\tstop.md"));
    }

    /// `create_note` and `move_note` name the same thing — a Directory to put
    /// a Note in — and must answer an unknown one the same way. `move_note`
    /// returns `PathUnavailable`; `create_note` used to `create_dir_all` the
    /// whole hierarchy, so one typo in `SHEL-E005`'s field silently created a
    /// Directory and filed the Note out of sight in it. Creating the
    /// Directory first, explicitly, is the route that still works.
    #[test]
    fn create_note_requires_an_existing_directory_rather_than_materializing_one() {
        let f = fixture();
        create_directory(&f.workspace, "projects").unwrap();

        // The explicit route, and the bundle root, both still work.
        create_note(&f.workspace, "projects", "Kept").unwrap();
        create_note(&f.workspace, "", "At the root").unwrap();

        for typo in ["porjects", "projects/deeper", "a/b/c"] {
            let refused = create_note(&f.workspace, typo, "Typo").map(|_| ());
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "create_note({typo:?}, ..) must be refused, got {refused:?}"
            );
            assert!(
                !f.root().join(typo).exists(),
                "{typo:?} was materialized by a refused create"
            );
            assert!(!f.exists(&format!("{typo}/Typo.md")));
        }

        assert_eq!(f.directory_ids(), vec!["projects".to_string()]);
        assert_eq!(
            f.note_ids(),
            vec!["At the root".to_string(), "projects/Kept".to_string()]
        );
    }

    /// A Directory that is really a symlink is refused as a place to create a
    /// Note, whether it points outside the bundle or back inside it.
    ///
    /// The same shape as the dot-prefix defect above, reached by a different
    /// route. `note_path`'s containment check only ran `if absolute.exists()`,
    /// and on the creation path the file does not exist yet, so nothing looked
    /// at the *directory* it was about to be written into. Two endings, both
    /// bad:
    ///
    /// - pointing **outside** the bundle, the write lands wherever the link
    ///   goes — an arbitrary-write primitive out of a concept id the UI
    ///   supplies;
    /// - pointing **inside** it, the write lands in the bundle but under a
    ///   concept id nothing can reach: `index::scan::walk_bundle` skips
    ///   symlinks, so the next reindex drops the row while the file stays and
    ///   `ensure_path_available` keeps the name permanently taken.
    #[cfg(unix)]
    #[test]
    fn a_note_cannot_be_created_through_a_symlinked_directory() {
        let f = fixture();
        let outside = f.dir.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::create_dir_all(f.root().join("Real")).unwrap();
        std::os::unix::fs::symlink(&outside, f.root().join("Escape")).unwrap();
        std::os::unix::fs::symlink(f.root().join("Real"), f.root().join("Detour")).unwrap();
        f.reindex();

        for directory in ["Escape", "Detour"] {
            let refused = create_note(&f.workspace, directory, "Planted");
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "{directory}: a symlinked Directory must be refused, got {refused:?}"
            );
        }

        assert!(
            !outside.join("Planted.md").exists(),
            "a Note was written outside the bundle"
        );
        assert!(
            !f.root().join("Real/Planted.md").exists(),
            "a Note was written under a name the indexer cannot see"
        );
        assert!(f.note_ids().is_empty(), "a Note was indexed anyway");
    }

    /// The same rule applied by the other entry point onto a Directory:
    /// `move_note`, which routes through `ensure_directory_exists` rather than
    /// through `create_note`'s own path check.
    #[cfg(unix)]
    #[test]
    fn a_note_cannot_be_moved_into_a_symlinked_directory() {
        let f = fixture();
        let outside = f.dir.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::create_dir_all(f.root().join("Real")).unwrap();
        std::os::unix::fs::symlink(&outside, f.root().join("Escape")).unwrap();
        std::os::unix::fs::symlink(f.root().join("Real"), f.root().join("Detour")).unwrap();
        f.write("One.md", &note("One", "body"));
        f.reindex();

        for directory in ["Escape", "Detour"] {
            let refused = move_note(&f.workspace, "One", directory);
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "{directory}: a symlinked Directory must be refused, got {refused:?}"
            );
        }

        assert!(f.exists("One.md"), "the Note was moved anyway");
        assert!(!outside.join("One.md").exists());
        assert!(!f.root().join("Real/One.md").exists());
        assert_eq!(f.note_ids(), vec!["One".to_string()]);
    }

    /// The rule the directory tests above pin, applied to the component neither
    /// of them looked at: the **leaf**.
    ///
    /// `Foo.md -> Real.md` planted inside the bundle passed every check
    /// `note_path` made. Its ancestors are ordinary directories, so
    /// `ensure_directory_contained` is satisfied; it resolves inside the
    /// Workspace, so the containment test is satisfied; and the Note opens,
    /// reads and writes through it perfectly well. Then
    /// `index::scan::walk_bundle` skips symbolic links, so the next reindex —
    /// which runs on every Workspace open — drops the row while the file stays
    /// on disk and `ensure_path_available` consults the filesystem, leaving
    /// `Foo` permanently taken by a Note nothing in the application can see.
    /// That is exactly the ending the directory rule prevents, one component
    /// further down.
    #[cfg(unix)]
    #[test]
    fn a_note_that_is_a_symlink_is_refused_at_both_entrances() {
        let f = fixture();
        f.write("Real.md", &note("Real", "the file the link points at"));
        let outside = f.dir.path().join("outside.md");
        std::fs::write(&outside, note("outside", "not in the bundle")).unwrap();
        std::os::unix::fs::symlink(f.root().join("Real.md"), f.root().join("Detour.md")).unwrap();
        std::os::unix::fs::symlink(&outside, f.root().join("Escape.md")).unwrap();
        // A broken link is refused too: `symlink_metadata` sees it as present
        // where `exists()` reports it absent and a create would take the name.
        std::os::unix::fs::symlink(f.root().join("Gone.md"), f.root().join("Dangling.md")).unwrap();
        f.reindex();

        for note_id in ["Detour", "Escape", "Dangling"] {
            let refused = persist::open_note(&f.workspace, note_id).map(|_| ());
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "{note_id}: opening a Note through a symbolic link must be refused, got \
                 {refused:?}"
            );
            let refused = create_note(&f.workspace, "", note_id);
            assert!(
                matches!(refused, Err(AppError::PathUnavailable(_))),
                "{note_id}: creating over a symbolic link must be refused, got {refused:?}"
            );
        }

        assert_eq!(
            std::fs::read_to_string(&outside).unwrap(),
            note("outside", "not in the bundle"),
            "a file outside the bundle was written through the link"
        );
        assert!(f.read("Real.md").contains("the file the link points at"));
        assert!(
            !f.root().join("Gone.md").exists(),
            "the dangling link's target was created through it"
        );
    }

    /// A NUL is refused by all three of this Workspace's path-handling
    /// functions, not two of them.
    ///
    /// `validate_segment` already rejected it in a *name*, so `create_note`
    /// answered `PathUnavailable`. `normalize_directory` did not, so the same
    /// input reached `create_dir_all` through `create_directory` and came back
    /// as a raw `IoError` naming an invalid argument — one rule, two
    /// unrelated-looking answers, and the leaked one describes an
    /// implementation detail rather than what the caller did wrong.
    #[test]
    fn a_nul_in_a_path_is_refused_at_every_entrance() {
        let f = fixture();

        let refused = create_directory(&f.workspace, "a\0b");
        assert!(
            matches!(refused, Err(AppError::PathUnavailable(_))),
            "a Directory path carrying a NUL must be refused, got {refused:?}"
        );

        let refused = create_note(&f.workspace, "", "a\0b");
        assert!(
            matches!(refused, Err(AppError::PathUnavailable(_))),
            "a Note title carrying a NUL must be refused, got {refused:?}"
        );

        // The third entrance: a concept id straight off the UI, which reaches
        // `note_path` without passing through either validator.
        let refused = f.workspace.note_path("a\0b");
        assert!(
            matches!(refused, Err(AppError::PathUnavailable(_))),
            "a concept id carrying a NUL must be refused, got {refused:?}"
        );

        assert!(f.note_ids().is_empty());
        assert!(f.directory_ids().is_empty());
    }

    /// A title carrying a control character round-trips through the frontmatter
    /// block it is written into, and the bytes written for it are the escaped
    /// form YAML 1.2 §5.7 requires rather than a raw control.
    ///
    /// The second half is the point. A raw C0 control inside a double-quoted
    /// scalar is invalid YAML that the pinned `saphyr` 0.0.11 happens to
    /// tolerate — only `\u{0}` is refused, and [`validate_segment`] rejects that
    /// upstream — so this is not a parse being repaired. A bundle is a portable
    /// artifact under OKF and burlmd is not the only reader of what it writes,
    /// which is what makes "only happens to parse here" the wrong bar.
    #[test]
    fn a_title_with_a_control_character_round_trips_as_conformant() {
        let f = fixture();
        f.write("One.md", &note("One", "body"));
        f.reindex();
        // A bell and a start-of-heading: two characters a paste out of a
        // terminal or a spreadsheet cell really does carry. Neither is
        // whitespace, so `metadata_from`'s `trim` is not what is under test.
        let awkward = "Bell\u{7} and start of heading\u{1} inside";

        let (state, _) = rename_note(&f.workspace, "One", awkward).unwrap();

        assert_eq!(state.metadata.title, awkward);
        let written = f.read(&concept_id_to_path(&state.metadata.id));
        assert!(
            state.metadata.okf_conformant,
            "the rewritten frontmatter no longer parses: {written:?}"
        );
        assert!(
            written.contains("title: \"Bell\\u0007 and start of heading\\u0001 inside\""),
            "the control characters were written raw into a double-quoted \
             scalar, which YAML 1.2 §5.7 forbids: {written:?}"
        );
        let reread = crate::okf::read_frontmatter(&written);
        assert!(reread.is_conformant());
        assert_eq!(reread.title.as_deref(), Some(awkward));

        // And on the create path, which writes the block rather than rewriting
        // one value inside it.
        let created = create_note(&f.workspace, "", "Tab\u{1}stop").unwrap();
        assert!(created.metadata.okf_conformant);
        assert_eq!(created.metadata.title, "Tab\u{1}stop");
        assert!(f
            .read("Tab\u{1}stop.md")
            .contains("title: \"Tab\\u0001stop\""));
    }

    /// The `Renamed` and `Overwrote` inverse arms, driven by the one failure
    /// that can occur *after* the files have moved: the index transaction.
    /// Every earlier failure is raised from the planning phase, where nothing
    /// has moved and there is nothing to undo.
    #[test]
    fn an_index_failure_after_the_files_moved_restores_every_one_of_them() {
        let f = fixture();
        f.write("Old Name.md", &note("Old Name", "target"));
        f.write("aaa.md", &note("aaa", &link("Old Name", "Old Name")));
        f.reindex();
        let before_target = f.read("Old Name.md");
        let before_source = f.read("aaa.md");
        f.inject_index_failure(
            "CREATE TRIGGER injected_insert BEFORE INSERT ON notes \
             BEGIN SELECT RAISE(ABORT, 'injected index failure'); END;",
        );

        let result = rename_note(&f.workspace, "Old Name", "New Name");

        assert!(result.is_err(), "{result:?}");
        assert!(!f.exists("New Name.md"), "the rename survived the rollback");
        assert_eq!(
            f.read("Old Name.md"),
            before_target,
            "the renamed file was not restored byte-identically"
        );
        assert_eq!(
            f.read("aaa.md"),
            before_source,
            "the rewritten source was not restored byte-identically"
        );
        assert_eq!(
            f.note_ids(),
            vec!["Old Name".to_string(), "aaa".to_string()]
        );
        assert_eq!(f.backlink_sources("Old Name"), vec!["aaa".to_string()]);
    }

    /// The `Trashed` inverse arm: a deletion whose index transaction fails puts
    /// the file back.
    #[test]
    fn an_index_failure_during_a_deletion_puts_the_file_back() {
        let f = fixture();
        f.write("Doomed.md", &note("Doomed", "words worth keeping"));
        f.reindex();
        let before = f.read("Doomed.md");
        f.inject_index_failure(
            "CREATE TRIGGER injected_delete BEFORE DELETE ON notes \
             BEGIN SELECT RAISE(ABORT, 'injected index failure'); END;",
        );

        let result = delete_note(&f.workspace, "Doomed");

        assert!(result.is_err(), "{result:?}");
        assert_eq!(
            f.read("Doomed.md"),
            before,
            "the deleted file was not restored byte-identically"
        );
        assert!(f.trash_entries().is_empty());
        assert_eq!(f.note_ids(), vec!["Doomed".to_string()]);
    }

    // -- frontmatter rewriting ----------------------------------------------

    /// ADR-007 decision 5: only the `title` value is rewritten. Unmanaged keys
    /// keep their order, spelling and formatting because nothing re-serializes
    /// the block.
    #[test]
    fn only_the_title_value_is_rewritten_in_the_frontmatter() {
        let source = "---\ntype: Note\ntags:   [a, b]\ntitle: Old\nstatus: draft\n---\n\nBody\n";

        let out = rewrite_frontmatter_title(source, "New").unwrap();

        assert_eq!(
            out,
            "---\ntype: Note\ntags:   [a, b]\ntitle: New\nstatus: draft\n---\n\nBody\n"
        );
    }

    /// A block with no `title` key gains one — `title` is burlmd-managed
    /// (ADR-004 decision 3), and this is not the forbidden "create a block that
    /// was never there" case.
    #[test]
    fn a_block_without_a_title_key_gains_one() {
        let source = "---\ntype: Note\n---\n\nBody\n";

        let out = rewrite_frontmatter_title(source, "New").unwrap();

        assert_eq!(out, "---\ntype: Note\ntitle: New\n---\n\nBody\n");
    }

    /// A file with no frontmatter is left exactly as its author wrote it:
    /// bringing a foreign file into conformance is an explicit user action.
    #[test]
    fn a_file_with_no_frontmatter_is_not_given_one() {
        assert!(rewrite_frontmatter_title("# Just a heading\n", "New").is_none());
    }

    /// A rename of a Note with no frontmatter still moves the file and the
    /// index rows; only its bytes stay untouched.
    #[test]
    fn renaming_a_note_with_no_frontmatter_moves_it_without_writing_a_block() {
        let f = fixture();
        f.write("Foreign.md", "# Foreign\n\nWritten elsewhere.\n");
        f.reindex();

        rename_note(&f.workspace, "Foreign", "Adopted").unwrap();

        assert_eq!(f.read("Adopted.md"), "# Foreign\n\nWritten elsewhere.\n");
        assert_eq!(f.note_ids(), vec!["Adopted".to_string()]);
    }

    /// A title YAML would otherwise reinterpret is quoted, so it round-trips as
    /// the string the user typed rather than as a boolean, an integer or a
    /// nested mapping.
    #[test]
    fn a_title_yaml_would_reinterpret_is_quoted() {
        assert_eq!(yaml_scalar("Plain Title"), "Plain Title");
        assert_eq!(yaml_scalar("no"), "\"no\"");
        assert_eq!(yaml_scalar("2026"), "\"2026\"");
        assert_eq!(yaml_scalar("a: b"), "\"a: b\"");
        assert_eq!(yaml_scalar("- dash"), "\"- dash\"");
        assert_eq!(yaml_scalar("say \"hi\""), "\"say \\\"hi\\\"\"");

        for title in ["no", "2026", "a: b", "say \"hi\"", "100% Done"] {
            let source = "---\ntype: Note\ntitle: placeholder\n---\n\nBody\n";
            let out = rewrite_frontmatter_title(source, title).unwrap();
            let block = parse_note(&out, "").spans.frontmatter().unwrap();
            let parsed = crate::okf::read_frontmatter(&out[block]);
            assert_eq!(parsed.title.as_deref(), Some(title), "{out:?}");
        }
    }
}
