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
/// OKF-conformant frontmatter block, indexes it, and **opens it** — the
/// returned state is the state of an open Note, so the working source, span map
/// and recorded revision are all established before this returns.
///
/// The filename is the title verbatim plus `.md`
/// (`data-models/okf-bundle.md`), because CAP-GRAPH-04's create-on-follow has
/// to invert the derivation. A collision or a reserved filename returns
/// [`AppError::PathUnavailable`] and creates nothing.
pub fn create_note(
    workspace: &Arc<Workspace>,
    directory_path: &str,
    title: &str,
) -> Result<NoteState, AppError> {
    validate_title(title)?;
    let directory = normalize_directory(directory_path)?;
    let new_id = join_id(&directory, title);
    let new_path = workspace.note_path(&new_id)?;
    ensure_path_available(workspace, &new_id, &new_path, None)?;

    let source = conformant_frontmatter(title);
    if let Some(parent) = new_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| AppError::IoError(format!("create {}: {e}", parent.display())))?;
    }
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
        // - Any directory `create_dir_all` had to materialize stays. An empty
        //   directory is not a Note, holds no user content, is invisible to
        //   `walk_bundle`'s Note scan, and Git does not track it; removing it
        //   would mean distinguishing the levels this call created from ones
        //   that already existed, to undo something nothing can observe.
        // - Nothing rolls back if `open_note` below fails *after* the index
        //   transaction committed. That leaves the Note fully created and
        //   correctly indexed but not open, which is a state the user can act
        //   on — the Note is in the tree and opening it is one click — whereas
        //   deleting a Note that was successfully created because the *open*
        //   failed would discard a real result over a recoverable one.
        let _ = std::fs::remove_file(&new_path);
        return Err(error);
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

    let mut journal = FileJournal::default();
    journal.trash(&path)?;

    let removed = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            index::remove_note_rows(tx, workspace.id(), note_id)?;
            clear_draft(tx, workspace.id(), note_id)
        })
    });
    if let Err(error) = removed {
        journal.rollback();
        return Err(error);
    }

    let relative = concept_id_to_path(note_id);
    let display = title.unwrap_or_else(|| file_stem(note_id).to_string());
    let committed = crate::git::operations::commit_paths(
        workspace.root(),
        &format!("Delete {display}\n\n{relative}\n"),
        std::slice::from_ref(&relative),
    );

    // Settled before the commit error is propagated: the file is gone and the
    // index agrees, so the trash entry must go regardless of whether version
    // history recorded it. Leaving it parked would keep the deleted Note's full
    // content sitting untracked inside the bundle.
    journal.commit();
    committed?;
    persist::discard_session(workspace, note_id)?;
    Ok(())
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
    if !old_path.exists() {
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
    if !old_path.exists() {
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
    let absolute = workspace.root().join(&directory);
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

    let old_absolute = workspace.root().join(&directory);
    let new_absolute = workspace.root().join(&new_directory);
    if !old_absolute.is_dir() {
        return Err(AppError::NotFound(format!(
            "no Directory at {directory} in this Workspace"
        )));
    }
    if new_directory != directory && new_absolute.exists() {
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
    let absolute = workspace.root().join(&directory);
    let prefix = format!("{directory}/");
    let removed = workspace.with_db(|conn| note_ids_with_prefix(conn, workspace.id(), &prefix))?;
    if !absolute.exists() && removed.is_empty() {
        return Err(AppError::NotFound(format!(
            "no Directory at {directory} in this Workspace"
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
        journal.rollback();
        return Err(error);
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
    let committed = crate::git::operations::commit_paths(
        workspace.root(),
        &format!("Delete directory {directory}\n"),
        &directory_pathspec,
    );

    journal.commit();
    committed?;
    for note_id in &removed {
        persist::discard_session(workspace, note_id)?;
    }
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
        journal.rollback();
        return Err(error);
    }

    // Derived out here rather than inside the connection closure: deriving
    // reads and parses, and `SPK-WSPC-D001` §6.2.7 forbids file I/O under the
    // process-wide connection mutex a keystroke's own draft write waits on.
    let indexed: Result<Vec<index::IndexedNote>, AppError> = affected
        .iter()
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
        Err(error) => {
            journal.rollback();
            return Err(error);
        }
    };

    let written = workspace.with_db(|conn| {
        in_owned_transaction(conn, |tx| {
            rewrite_index(tx, workspace.id(), plan, &affected, &indexed)
        })
    });
    if let Err(error) = written {
        journal.rollback();
        return Err(error);
    }

    // Once for the whole batch, and outside the transaction that rewrote it —
    // see `write_note_rows_deferring_analyze`. Not fatal on its own: the rows
    // are correct either way and stale statistics cost a worse query plan, not
    // a wrong answer, but there is no reason to swallow the error when the
    // caller can act on it.
    workspace.with_db(index::analyze_bounded)?;

    let mut pathspec: Vec<String> = Vec::new();
    for a in &affected {
        pathspec.push(concept_id_to_path(&a.old_id));
        if a.old_id != a.new_id {
            pathspec.push(concept_id_to_path(&a.new_id));
        }
    }
    // The commit result is held rather than propagated with `?`, so that the
    // journal is settled either way: the bundle and the index are already
    // consistent by this point, and a failure to record that in version history
    // must not also leave a trash entry parked in the bundle.
    let committed =
        crate::git::operations::commit_paths(workspace.root(), &plan.message, &pathspec);
    journal.commit();
    committed?;

    // In-memory and infallible in the sense that matters: nothing after this
    // point can leave the bundle and the index disagreeing.
    for a in &affected {
        persist::carry_session_forward(
            workspace,
            &a.old_id,
            &a.new_id,
            a.new_buffer.clone(),
            a.revision.clone(),
        )?;
    }

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

        let Some(disk) = read_source(&old_path)? else {
            // The index lists this Note as a Link source but its file is gone.
            // Nothing to rewrite, and its rows are rebuilt from the bundle at
            // the next reindex; refusing the rename over someone else's stale
            // row would be the wrong direction of strictness.
            if plan.remap.contains_key(&old_id) {
                return Err(AppError::NotFound(format!(
                    "no file on disk for concept id {old_id}"
                )));
            }
            continue;
        };
        let dir = containing_dir(&old_id).to_string();
        let new_file = rewrite_note_text(&disk, &dir, &plan.remap, new_title)?;

        let buffer = persist::lookup(workspace.id(), &old_id)?
            .map(|session| session.working_source())
            .transpose()?;
        let new_buffer = match buffer {
            Some(source) => rewrite_note_text(&source, &dir, &plan.remap, new_title)?,
            None => None,
        };

        let draft = workspace.with_db(|conn| read_draft_text(conn, workspace.id(), &old_id))?;
        let new_draft = match draft {
            Some(source) => rewrite_note_text(&source, &dir, &plan.remap, new_title)?,
            None => None,
        };

        if new_file.is_none() && new_buffer.is_none() && new_draft.is_none() && old_id == new_id {
            continue;
        }

        let revision = content_hash(new_file.as_deref().unwrap_or(&disk).as_bytes());
        affected.push(Affected {
            old_id,
            new_id,
            old_path,
            new_path,
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

    /// Undoes every step, newest first. Errors are deliberately swallowed:
    /// this runs on a path that is already returning an error, and the caller
    /// has nothing better to do with a second one than the first.
    ///
    /// Takes `&mut self` and drains, rather than consuming, so that
    /// [`FileJournal`]'s `Drop` can be the backstop for a journal neither
    /// committed nor rolled back.
    fn rollback(&mut self) {
        for step in std::mem::take(&mut self.steps).into_iter().rev() {
            match step {
                FileStep::Overwrote { path, previous } => match previous {
                    Some(bytes) => {
                        let _ = persist::atomic_write(&path, &bytes);
                    }
                    None => {
                        let _ = std::fs::remove_file(&path);
                    }
                },
                FileStep::Renamed { from, to } => {
                    let _ = std::fs::rename(&to, &from);
                }
                FileStep::Trashed { original, trash } => {
                    let _ = std::fs::rename(&trash, &original);
                }
            }
        }
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
    if segment == "." || segment == ".." {
        return Err(AppError::PathUnavailable(format!(
            "{segment} does not name a file inside the Workspace"
        )));
    }
    if segment.contains('/') || segment.contains('\\') || segment.contains('\0') {
        return Err(AppError::PathUnavailable(format!(
            "{segment} contains a character no filename can carry, and the derivation is \
             verbatim rather than slugifying (data-models/okf-bundle.md)"
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
fn normalize_directory(path: &str) -> Result<String, AppError> {
    if path.contains('\\') {
        return Err(AppError::PathUnavailable(format!(
            "{path} does not name a Directory inside the Workspace: a Directory path is \
             `/`-separated and a backslash is a character no segment may carry"
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
    Ok(trimmed.to_string())
}

fn ensure_directory_exists(workspace: &Arc<Workspace>, directory: &str) -> Result<(), AppError> {
    if directory.is_empty() {
        return Ok(());
    }
    let absolute = workspace.root().join(directory);
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
fn final_source(affected: &Affected) -> Result<String, AppError> {
    match &affected.new_file {
        Some(source) => Ok(source.clone()),
        None => std::fs::read_to_string(&affected.new_path)
            .map_err(|e| AppError::IoError(format!("read {}: {e}", affected.new_path.display()))),
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

        /// Builds the index from the bundle, the way first open does.
        fn reindex(&self) {
            self.workspace
                .with_db(|conn| {
                    crate::index::scan::reindex_workspace_impl(conn, self.workspace.id())
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
