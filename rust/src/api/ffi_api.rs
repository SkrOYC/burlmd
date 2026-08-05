use flutter_rust_bridge::frb;

// AST types are owned by the `markdown` domain module (parsing is what
// produces and shapes them); re-exported here so they cross the FFI
// boundary FRB scans (`rust_input: crate::api`) without `markdown`
// having to depend back on this module for its own output types. `AppError`
// is re-exported the same way, from a shared leaf module, so `db` and
// `security` can report failures without depending upward on `api`.
// `NoteMetadata`/`NoteState` are re-exported from `draft`, which also owns
// the active-note cache and `set_node_at_path` — this module's own job is
// just the thin `#[frb]` wrappers below, not the draft-state domain logic.
pub use crate::draft::{NoteMetadata, NoteState};
pub use crate::error::AppError;
pub use crate::markdown::{AstNode, InlineElement, TextRun};
// `WorkspaceInfo` is owned by the `workspace` domain module for the same
// reason the types above are owned by `draft`/`markdown`: `workspace::bootstrap`
// is where the bootstrap logic actually lives (tested directly against an
// injected `Connection`), and this module's own job is the thin `#[frb]`
// wrappers below.
pub use crate::workspace::WorkspaceInfo;
// Same reason again for the persistence tier: `workspace::persist` owns
// ADR-008's machinery and the type it reports through, and the `#[frb]`
// functions below are wrappers over it.
pub use crate::workspace::NoteWriteStatus;
// `LinkCompletion` and `TreeNode` are owned by `index::query` (WSPC-D009),
// the discovery-domain module, for the same reason as every re-export above:
// the logic that fills them lives there, tested directly against an injected
// `Connection`, and this module's own job is the thin `#[frb]` wrappers below.
pub use crate::index::query::{LinkCompletion, TreeNode};

/// Opens the local Workspace, creating and initializing it if absent
/// (ADR-005 decision 1): creates the directory, initializes a Git repository
/// in place, and writes a `workspaces` row with `provider = "local"`. Root
/// key generation and opening the encrypted index both happen as a side
/// effect of `db::connection::connection()` below, on first use in this
/// process — see `security::keyring::get_or_create_root_key`.
///
/// Requires no credential, no provider, and no network — this is the call
/// that makes the Local-First Mandate in `prd/constraints.md` literally true
/// (CAP-WS-01). `path` is `None` to use the default location specified in
/// `guidelines.md`.
///
/// Establishes the active Workspace on success (ADR-005 decision 7,
/// WSPC-D004 review finding #3): every later Note-level call is implicitly
/// scoped to whichever Workspace was most recently opened by this function
/// or [`open_workspace`], via `db::connection::active_workspace_id`.
#[frb]
pub async fn open_or_create_local_workspace(
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    let info = crate::db::connection::with_connection(|conn| {
        crate::workspace::bootstrap::open_or_create_local_workspace_impl(conn, path)
    })?;
    crate::db::connection::set_active_workspace_id(info.id.clone())?;
    Ok(info)
}

/// Opens an existing Workspace directory that this application did not
/// create, including one populated by another tool (CAP-WS-05). Converges on
/// the same post-conditions as [`open_or_create_local_workspace`] — see
/// `workspace::bootstrap`'s module documentation and ADR-005 decision 8,
/// including establishing the active Workspace on success.
#[frb]
pub async fn open_workspace(path: String) -> Result<WorkspaceInfo, AppError> {
    let info = crate::db::connection::with_connection(|conn| {
        crate::workspace::bootstrap::open_workspace_impl(conn, path)
    })?;
    crate::db::connection::set_active_workspace_id(info.id.clone())?;
    Ok(info)
}

/// Full rebuild of `notes`, `notes_fts`, `fts_mapping`, `links` and
/// `directories` for the active Workspace from the bundle on disk. Returns
/// the number of Notes indexed.
///
/// The index is derived state and is always discardable
/// (`data-models/schema.sql`). This closes Epic C deferred item 3:
/// `SyncDeps::default().reindex` in `rust/src/sync/scheduler.rs` is a
/// documented no-op because no re-index function existed anywhere in the
/// crate; one exists now, and wiring the scheduler's hook to it is the only
/// remaining step (deferred there by that ticket's scope, not by this one).
///
/// Per `architecture/risks.md` risk 3 this is **not** the routine path for
/// keeping the index current — `index::incremental::index_note` is. It exists
/// for first open, post-merge reconciliation, and recovery.
#[frb]
pub async fn reindex_workspace() -> Result<u32, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::scan::reindex_workspace_impl(conn, &workspace_id)
    })
}

/// Opens a Note and establishes its editing session.
///
/// Still keyed by filesystem path rather than by concept id — `WSPC-D008`
/// replaces this signature with the contract's `open_note(note_id)`. What it
/// does *within* the active Workspace is already the contract's behaviour: it
/// registers the session ADR-008's tiers operate on, so the working source,
/// the span map and the recorded revision all exist before the first edit, and
/// an unflushed `drafts` row is restored in preference to disk.
///
/// A path outside the active Workspace — or a call before any Workspace has
/// been opened — falls back to reading the file directly. That path registers
/// no session and therefore has no write tier: the Workspace is what supplies
/// the bundle root, the encrypted index the draft row lives in, and the
/// repository tier 3 commits into, and none of the three exists for a file
/// somewhere else on the disk.
#[frb(sync)]
pub fn open_note(path: String) -> Result<NoteState, AppError> {
    if let Some(state) = open_note_in_active_workspace(&path)? {
        return Ok(state);
    }

    let content = std::fs::read_to_string(&path).map_err(|e| AppError::IoError(e.to_string()))?;

    let path_obj = std::path::Path::new(&path);
    let title = path_obj
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string();

    let mut ast = crate::markdown::parse_markdown(&content);
    // `InlineElement::Link.exists` is the one field the parser cannot fill:
    // it is whether `target_id` matches a `notes` row, which only the index
    // knows (WSPC-D003 declares the field, WSPC-D005 resolves it).
    //
    // Two cases leave every Link at the parser's `false`, and they are not the
    // same case. The first is that no Workspace is open at all, so there is no
    // index to ask. The second is that this entry point still takes a
    // filesystem path rather than a concept id (WSPC-D008 reconciles that), so
    // it can be handed a file that is not in the active Workspace's bundle —
    // and a concept id is unique only *within* a bundle, so resolving that
    // file's Links against this index would answer about a different Note that
    // happens to share an id. `Welcome` exists in more or less every bundle.
    // Both cases collapse to `false`, which is also what "no indexed Note
    // matches" means, and the contract already requires the follow path to
    // re-resolve rather than trust the flag.
    if let Ok(workspace_id) = crate::db::connection::active_workspace_id() {
        crate::db::connection::with_connection(|conn| {
            if crate::index::path_is_in_workspace(conn, &workspace_id, path_obj)? {
                crate::index::resolve_link_existence(conn, &workspace_id, &mut ast)?;
            }
            Ok(())
        })?;
    }

    let last_modified = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let metadata = NoteMetadata {
        // Still the filesystem path rather than the OKF concept id
        // `data-models/schema.sql` defines `notes.id` as: this entry point
        // takes a path, and `WSPC-D008` is the ticket that reconciles the two
        // (it replaces this function with the contract's
        // `open_note(note_id)`). What is no longer a placeholder is
        // `base_revision` below.
        id: path.clone(),
        path: path.clone(),
        title,
        last_modified,
        snippet: None,
        // OKF §11's first two conformance conditions, read from the file's own
        // frontmatter rather than assumed: a Workspace this application did
        // not write may hold a Note with none (CAP-WS-05, CAP-PORT-03).
        okf_conformant: crate::okf::read_frontmatter(&content).is_conformant(),
    };

    let state = NoteState {
        ast,
        metadata,
        // The content hash of the bytes on disk (ADR-007 decision 7), which is
        // the OCC token `workspace::persist` compares before every tier 2
        // write — no longer the `"head"` placeholder that could never match
        // anything. It is not an input: no function on this boundary takes it
        // back.
        base_revision: crate::index::content_hash(content.as_bytes()),
        // This path reads the file directly rather than through a session, so
        // no `drafts` row was consulted and nothing was restored. Tier 1
        // recovery arrives with the session-based `open_note` in `WSPC-D008`;
        // `pending_drafts` below already reports the rows.
        restored_from_draft: false,
    };
    *crate::draft::active_note_cache()? = Some(state.clone());
    Ok(state)
}

/// Opens `path` through `workspace::persist` when it names a file inside the
/// active Workspace, or `None` when it does not — including when no Workspace
/// is open at all.
///
/// The concept id is the bundle-relative path with `.md` removed (ADR-004), so
/// it is derived here rather than taken as a parameter; a concept id is unique
/// only within its bundle, which is exactly why this returns `None` rather
/// than guessing for a file outside one.
/// The returned state's `metadata.id` is the **concept id** and its
/// `metadata.path` the bundle-relative path, as the contract specifies — not
/// the absolute filesystem path the fallback branch below still reports. The
/// two branches disagree on that, and deliberately: an id is what every other
/// call in the persistence surface takes, and a file outside any bundle has no
/// concept id to give.
///
/// The state is mirrored into `draft::active_note_cache` as well, because the
/// legacy AST-based `update_block` below reads the note out of that cache and
/// matches on `metadata.id`. Without the mirror, the ordinary Dart sequence —
/// `openNote(path)` then `updateBlock(state.metadata.id, ...)`, which is what
/// `note_providers.dart` does — would fail with "no open note with id". The
/// mirror is a bridge, not a design: the cache and the session are two copies
/// of the same buffer, and `WSPC-D008` removes the first when it replaces
/// `update_block` with the contract's source-text version, which writes through
/// the session and its draft row.
fn open_note_in_active_workspace(path: &str) -> Result<Option<NoteState>, AppError> {
    let Ok(workspace) = crate::workspace::persist::Workspace::active() else {
        return Ok(None);
    };
    let (Ok(root), Ok(absolute)) = (
        std::fs::canonicalize(workspace.root()),
        std::fs::canonicalize(path),
    ) else {
        return Ok(None);
    };
    let Ok(relative) = absolute.strip_prefix(&root) else {
        return Ok(None);
    };
    let note_id = crate::okf::path_to_concept_id(&relative.to_string_lossy());
    let (_, state) = crate::workspace::persist::open_note(&workspace, &note_id)?;
    *crate::draft::active_note_cache()? = Some(state.clone());
    Ok(Some(state))
}

/// Forces ADR-008 tier 2 immediately: writes the Note's working source to its
/// file atomically and returns the new `base_revision`.
///
/// The debounce that normally triggers tier 2 lives in the Core, not the UI —
/// this is the explicit-flush escape hatch used by `close_note`, by application
/// shutdown, and by tests. It takes no revision token: the Core holds one per
/// open Note and replaces it after every successful write, so any token the UI
/// still held would be stale by construction.
#[frb]
pub async fn flush_note(note_id: String) -> Result<String, AppError> {
    open_session(&note_id)?.flush()
}

/// Status of the write tier for one open Note (ADR-008). Never fails: a Note
/// that is not open reports no error and no unwritten edits.
#[frb(sync)]
pub fn note_write_status(note_id: String) -> NoteWriteStatus {
    open_session(&note_id)
        .and_then(|session| session.write_status())
        .unwrap_or_default()
}

/// Discards the buffered edits and re-reads the Note from disk, returning a
/// state with `restored_from_draft = false`.
///
/// This is the other half of `RevisionMismatch` and the only exit from it:
/// `open_note` restores the draft in preference to disk and tier 2 leaves that
/// row in place when it fails, so a reopen would return the buffer that just
/// lost the comparison and fail again on every tick. It **destroys unwritten
/// work by design**, so the UI must confirm first.
#[frb]
pub async fn reload_note(note_id: String) -> Result<NoteState, AppError> {
    open_session(&note_id)?.reload()
}

/// Tier 3: flushes any pending write, makes one Git commit covering this
/// editing session for this Note alone, clears the `drafts` row, and notifies
/// the sync scheduler — which has existed since Epic C with no caller.
///
/// Must also run on application quit and when switching away from a Note, or
/// the session reaches disk but never enters version history.
#[frb]
pub async fn close_note(note_id: String) -> Result<(), AppError> {
    open_session(&note_id)?.close()
}

/// Notes with an unflushed draft from a previous session, for surfacing
/// recovered work on startup (CAP-WS-03).
#[frb]
pub async fn pending_drafts() -> Result<Vec<NoteMetadata>, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::persist::pending_drafts(&workspace)
}

/// The open session for `note_id`, or `NotFound` when the Note is not open.
///
/// Kept private: which Notes are open is Core-side state, and the contract
/// exposes it only through the functions above.
fn open_session(note_id: &str) -> Result<crate::workspace::persist::NoteSession, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::workspace::persist::lookup(&workspace_id, note_id)?
        .ok_or_else(|| AppError::NotFound(format!("no open Note with id {note_id}")))
}

/// Applies a keystroke-level edit to the currently open note's in-memory
/// AST and returns the updated `NoteState`. `block_path` is an index path
/// into the AST tree (see `draft::set_node_at_path`); it does not persist
/// the change to disk or the DB — that happens via `save_note`.
#[frb(sync)]
pub fn update_block(
    note_id: String,
    block_path: Vec<usize>,
    new_node: AstNode,
) -> Result<NoteState, AppError> {
    let mut cache = crate::draft::active_note_cache()?;
    let state = cache
        .as_mut()
        .filter(|s| s.metadata.id == note_id)
        .ok_or_else(|| AppError::IoError(format!("no open note with id {note_id}")))?;
    crate::draft::set_node_at_path(&mut state.ast, &block_path, new_node)?;
    Ok(state.clone())
}

/// FTS5's bare `MATCH` syntax is a full query language (boolean operators,
/// `column:` filters, `-token` exclusion, `"phrase"` grouping, ...), so
/// passing raw user input straight to `MATCH` throws a syntax error on
/// perfectly ordinary searches — a hyphenated word, a colon, unbalanced
/// quotes. Quoting the *whole* query as one phrase would dodge that (FTS5's
/// own escaping rule: double any embedded `"`), but it also silently changes
/// what a "search my notes" box means: a phrase match requires every term to
/// appear adjacent and in that exact order, whereas users expect a multi-word
/// query to match notes containing all the terms, in any order. Quoting each
/// whitespace-split token *separately* instead keeps FTS5's implicit AND
/// across terms (its default when tokens aren't otherwise joined by an
/// operator) while still neutralizing the syntax footguns, since no operator
/// character can survive inside its own quoted token. A query with no tokens
/// at all (empty or whitespace-only input) produces an empty string here;
/// callers should treat that as "no results" rather than pass it to `MATCH`.
fn fts5_phrase_query(query: &str) -> String {
    query
        .split_whitespace()
        .map(|token| format!("\"{}\"", token.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(" ")
}

/// The search query itself, factored out of [`search_notes_impl`] so that
/// `index::scan`'s query-plan test asserts against the statement production
/// actually runs. WSPC-D005 carries a criterion on this plan — it must drive
/// from `notes_fts`, reach `fts_mapping` through `idx_fts_mapping_rowid`, and
/// contain no AUTOMATIC COVERING INDEX step — and a test holding its own copy
/// of the SQL would keep passing after the real query drifted away from it.
///
/// Parameters: `?1` is the FTS5 `MATCH` expression (see
/// [`fts5_phrase_query`]), `?2` the Workspace id.
///
/// Both joins are `CROSS JOIN`, which in SQLite is not a different join —
/// it is the documented way to pin the outer table and stop the planner
/// reordering. It is load-bearing here, and measured: with plain `JOIN`, a
/// Workspace of 10 or 200 Notes plans as `SCAN notes` → `SEARCH fts_mapping`
/// → `SCAN notes_fts VIRTUAL TABLE`, i.e. it re-runs the full-text match once
/// per Note — the catastrophic plan `data-models/schema.sql` distinguishes
/// from the merely-wasteful automatic-covering-index one. It happens to pick
/// the right order at 1000 Notes, which is exactly why WSPC-D005's criterion
/// is stated against the plan rather than a timing: the corpus size at which
/// the timing test runs is the size at which the defect hides. Pinned, the
/// plan is `SCAN notes_fts` → `SEARCH fts_mapping USING idx_fts_mapping_rowid`
/// → `SEARCH n USING sqlite_autoindex_notes_1`, at every corpus size, with and
/// without table statistics, and the `ORDER BY rank` temp b-tree disappears
/// with it because FTS5 already returns rows in rank order.
pub(crate) const SEARCH_NOTES_SQL: &str = "SELECT n.id, n.okf_conformant, n.path, n.title, \
            n.last_modified, snippet(notes_fts, 1, '', '', '…', 8) AS snippet \
     FROM notes_fts \
     CROSS JOIN fts_mapping ON fts_mapping.fts_rowid = notes_fts.rowid \
     CROSS JOIN notes n ON n.workspace_id = fts_mapping.workspace_id \
                        AND n.id = fts_mapping.note_id \
     WHERE notes_fts MATCH ?1 AND fts_mapping.workspace_id = ?2 \
     ORDER BY rank";

/// Full-text search over all indexed notes, ordered by FTS5 relevance
/// (bm25, best match first). `notes_fts` only carries `(title, content)`;
/// `fts_mapping` is the `(workspace_id, note_id)` <-> `fts_rowid` join table
/// maintained alongside it, used here to recover the owning `notes` row per
/// hit.
///
/// Scoped to `workspace_id` (WSPC-D004 review finding #4): `WSPC-D004`
/// brought `notes` and `fts_mapping` onto the composite `(workspace_id, id)`
/// key `data-models/schema.sql` specifies, so joining `fts_mapping` to
/// `notes` on `note_id` alone — and filtering by nothing at all — became a
/// cross-Workspace hazard the moment a second Workspace's rows exist in the
/// same index (ADR-005 decision 7: the index accumulates rows for every
/// Workspace ever opened, CAP-WS-05). It was also, independently, a full
/// scan of `fts_mapping` on every search rather than a lookup through its
/// primary key.
///
/// `SEARCH_NOTES_SQL` deliberately carries no `LIMIT` of its own — this is
/// the fix `WSPC-D009` makes for the hardcoded cap of 50 that used to sit at
/// the end of that constant and silently truncate with no signal to the
/// caller (`architecture/flows/flow-search.md`). The `limit` argument is
/// bound as `?3` on a copy of the statement with `LIMIT ?3` appended, kept
/// out of the shared constant so `index::scan`'s query-plan test — which
/// asserts against `SEARCH_NOTES_SQL` by name and is out of this ticket's
/// scope — keeps exercising the same base query this function actually runs.
fn search_notes_impl(
    conn: &rusqlite::Connection,
    query: &str,
    workspace_id: &str,
    limit: u32,
) -> Result<Vec<NoteMetadata>, AppError> {
    let fts_query = fts5_phrase_query(query);
    if fts_query.is_empty() {
        return Ok(Vec::new());
    }

    let sql = format!("{SEARCH_NOTES_SQL} LIMIT ?3");
    let mut stmt = conn.prepare(&sql)?;

    let rows = stmt.query_map(rusqlite::params![fts_query, workspace_id, limit], |row| {
        Ok(NoteMetadata {
            id: row.get(0)?,
            okf_conformant: row.get(1)?,
            path: row.get(2)?,
            title: row.get(3)?,
            last_modified: row.get(4)?,
            snippet: row.get(5)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

// `async` per the TechSpec FFI contract, even though `guidelines.md`'s Rust
// section otherwise prefers synchronous local-index queries: the body below
// runs to completion synchronously (a blocking mutex lock, then the query)
// with no `.await` inside it, so this doesn't yield to an executor — the
// `async` marker only affects how FRB dispatches the call across the
// boundary, not this function's own execution.
#[frb]
pub async fn search_notes(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        search_notes_impl(conn, &query, &workspace_id, limit)
    })
}

/// Title-prefix jump (CAP-FIND-02).
#[frb]
pub async fn find_notes_by_title(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::find_notes_by_title_impl(conn, &workspace_id, &query, limit)
    })
}

/// Candidates for the completion triggered by `[[` (CAP-GRAPH-02). The
/// trigger is a UI affordance; what gets inserted is `LinkCompletion::insert_text`,
/// built Core-side.
#[frb]
pub async fn link_completions(query: String, limit: u32) -> Result<Vec<LinkCompletion>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::link_completions_impl(conn, &workspace_id, &query, limit)
    })
}

/// Notes linking *to* this one (CAP-GRAPH-05).
#[frb]
pub async fn backlinks(note_id: String) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::backlinks_impl(conn, &workspace_id, &note_id)
    })
}

/// The Directory tree for the sidebar, Directories before Notes, each level
/// sorted by name.
#[frb]
pub async fn workspace_tree() -> Result<Vec<TreeNode>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::workspace_tree_impl(conn, &workspace_id)
    })
}

/// Optimistic-concurrency-controlled save: rejects with `AppError::GitConflict`
/// if `notes.last_modified` has drifted from `expected_base_revision` since the
/// caller last read the note (e.g. a background sync updated it concurrently).
///
/// Serializing the in-memory AST back to Markdown and writing it to the
/// workspace's on-disk file is intentionally out of scope here — no Markdown
/// serializer exists anywhere in this crate yet, and that write path overlaps
/// the Git-aware sync work tracked separately. This function only updates the
/// DB-level revision bookkeeping that write-through will eventually gate on.
///
/// `expected_base_revision` is compared against the DB's own
/// `notes.last_modified` (stringified) — not yet the same token `open_note`
/// currently hands back as `NoteState.base_revision` (a hardcoded
/// placeholder). See the comment on that field for why the two aren't wired
/// together yet.
///
/// Scoped to `workspace_id` (WSPC-D004 review finding #4), matching
/// `search_notes_impl`: `notes` moved onto the composite `(workspace_id, id)`
/// primary key, so `WHERE id = ?` alone was a cross-Workspace hazard on both
/// the read and the write — a `note_id` that happens to collide across two
/// Workspaces (a real possibility, since a concept id is unique only within
/// its own bundle) would read or overwrite the wrong Workspace's row — and
/// independently a full scan of `notes` on every save, since only
/// `(workspace_id, id)` and `(workspace_id, path)` are indexed.
fn save_note_impl(
    conn: &rusqlite::Connection,
    workspace_id: &str,
    note_id: &str,
    expected_base_revision: &str,
    now: i64,
) -> Result<(), AppError> {
    let current: i64 = conn
        .query_row(
            "SELECT last_modified FROM notes WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace_id, note_id],
            |row| row.get(0),
        )
        .map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => {
                AppError::IoError(format!("no note found with id {note_id}"))
            }
            e => AppError::from(e),
        })?;

    if current.to_string() != expected_base_revision {
        return Err(AppError::GitConflict);
    }

    conn.execute(
        "UPDATE notes SET last_modified = ?1 WHERE workspace_id = ?2 AND id = ?3",
        rusqlite::params![now, workspace_id, note_id],
    )?;
    Ok(())
}

#[frb(sync)]
pub fn save_note(note_id: String, expected_base_revision: String) -> Result<(), AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    crate::db::connection::with_connection(|conn| {
        save_note_impl(conn, &workspace_id, &note_id, &expected_base_revision, now)
    })
}

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::*;

    // These exercise `search_notes_impl`/`save_note_impl` directly against an
    // in-memory, unencrypted connection rather than through the `search_notes`/
    // `save_note` FFI wrappers and the process-wide `db::connection::connection()`
    // singleton: the singleton is lazily initialized once per test binary, so
    // routing through it here would make tests order-dependent on which one
    // opens (and fixes the path of) the shared connection first. Encryption
    // itself is already covered by `db::connection`'s own tests; these tests
    // are only responsible for the SQL logic.
    fn seeded_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        crate::db::connection::init_schema(&conn).unwrap();
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES ('ws', 'Test Workspace', 'local', NULL, '/tmp/ws')",
            [],
        )
        .unwrap();
        conn
    }

    // WSPC-D004 brought `db/schema.sql` in line with `data-models/schema.sql`:
    // `notes.content_hash` and `fts_mapping.workspace_id` are both now
    // `NOT NULL`, where the pre-existing fixture below inserted into neither.
    // A throwaway, deterministic-per-call hash stands in for the real
    // content hash `WSPC-D005`'s indexer will compute; nothing in this
    // module's own tests inspects its value.
    fn seed_note(conn: &Connection, id: &str, title: &str, content: &str, last_modified: i64) {
        conn.execute(
            "INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash) \
             VALUES (?1, 'ws', ?2, ?3, ?4, ?5)",
            rusqlite::params![
                id,
                format!("{id}.md"),
                title,
                last_modified,
                format!("hash-{id}")
            ],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO notes_fts (title, content) VALUES (?1, ?2)",
            rusqlite::params![title, content],
        )
        .unwrap();
        let fts_rowid = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO fts_mapping (workspace_id, note_id, fts_rowid) VALUES ('ws', ?1, ?2)",
            rusqlite::params![id, fts_rowid],
        )
        .unwrap();
    }

    #[test]
    fn search_notes_finds_a_match_via_fts5_and_returns_its_metadata() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        seed_note(
            &conn,
            "note-2",
            "Trip Planning",
            "Book flights to Rome",
            2000,
        );

        let results = search_notes_impl(&conn, "milk", "ws", 50).unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "note-1");
        assert_eq!(results[0].title, "Grocery List");
        assert_eq!(results[0].last_modified, 1000);
        assert!(results[0].snippet.as_deref().unwrap().contains("milk"));
    }

    #[test]
    fn search_notes_returns_no_results_for_a_non_matching_query() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        let results = search_notes_impl(&conn, "spaceship", "ws", 50).unwrap();

        assert!(results.is_empty());
    }

    #[test]
    fn search_notes_does_not_choke_on_fts5_syntax_characters_in_ordinary_queries() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        // Each of these is a bare `MATCH` syntax error without phrase-quoting
        // (hyphen is an exclusion operator, `:` introduces a column filter,
        // parens group a boolean expression, and an unmatched `"` is an
        // unterminated string) — none of them should ever surface as an
        // AppError to a user just typing an ordinary search.
        for query in ["note-1", "budget:2024", "hello (world", "\"unbalanced"] {
            search_notes_impl(&conn, query, "ws", 50).unwrap();
        }
    }

    #[test]
    fn search_notes_matches_notes_containing_every_query_term_in_any_order() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        seed_note(
            &conn,
            "note-2",
            "Reordered",
            "bread and milk, in that order",
            2000,
        );
        seed_note(&conn, "note-3", "Missing a term", "Buy milk only", 3000);

        let results = search_notes_impl(&conn, "milk bread", "ws", 50).unwrap();

        // A multi-word query is an implicit AND across per-token quoted
        // phrases (not one exact-phrase match), so word order shouldn't
        // matter — both note-1 and note-2 contain "milk" and "bread"
        // somewhere, note-3 doesn't contain "bread" at all.
        let ids: std::collections::HashSet<_> = results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, std::collections::HashSet::from(["note-1", "note-2"]));
    }

    #[test]
    fn search_notes_returns_nothing_for_an_empty_or_whitespace_only_query() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        assert!(search_notes_impl(&conn, "", "ws", 50).unwrap().is_empty());
        assert!(search_notes_impl(&conn, "   ", "ws", 50)
            .unwrap()
            .is_empty());
    }

    /// Gherkin: given an indexed Workspace, a full-text search run with a
    /// limit returns at most that many results, ranked best match first.
    #[test]
    fn search_notes_returns_at_most_the_caller_supplied_limit() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "One", "shared token alpha", 1000);
        seed_note(&conn, "note-2", "Two", "shared token beta", 2000);
        seed_note(&conn, "note-3", "Three", "shared token gamma", 3000);

        let results = search_notes_impl(&conn, "shared", "ws", 2).unwrap();

        assert_eq!(
            results.len(),
            2,
            "at most the caller's limit, not a hardcoded cap of 50"
        );
    }

    /// Gherkin (ranking half of the same criterion): with a limit smaller
    /// than the number of matches, the surviving result is the best match —
    /// bm25 rewards the Note whose content repeats the query term, so a
    /// limit of 1 must keep it over a Note mentioning the term only once.
    #[test]
    fn search_notes_ranks_the_better_match_first_under_a_tight_limit() {
        let conn = seeded_db();
        seed_note(&conn, "weak", "Weak Match", "distinctiveterm once", 1000);
        seed_note(
            &conn,
            "strong",
            "Strong Match",
            "distinctiveterm distinctiveterm distinctiveterm repeated",
            2000,
        );

        let results = search_notes_impl(&conn, "distinctiveterm", "ws", 1).unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(
            results[0].id, "strong",
            "bm25 ranks the note repeating the term ahead of the one mentioning it once"
        );
    }

    /// WSPC-D004 review finding #4: `notes`/`fts_mapping` moved onto a
    /// composite `(workspace_id, id)` key, so a search unscoped by
    /// `workspace_id` could return — or, worse, silently prefer — a hit from
    /// a Workspace other than the active one the moment two Workspaces'
    /// rows coexist in the index (ADR-005 decision 7). Two Workspaces here
    /// deliberately reuse the same `note_id` ("note-1"), which is exactly
    /// the collision a concept id being unique only within its own bundle
    /// permits.
    #[test]
    fn search_notes_does_not_return_a_match_from_a_different_workspace() {
        let conn = seeded_db();
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES ('other-ws', 'Other Workspace', 'local', NULL, '/tmp/other-ws')",
            [],
        )
        .unwrap();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        conn.execute(
            "INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash) \
             VALUES ('note-1', 'other-ws', 'note-1.md', 'Also Milk', 1000, 'hash-other')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO notes_fts (title, content) VALUES ('Also Milk', 'Buy milk too')",
            [],
        )
        .unwrap();
        let other_fts_rowid = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO fts_mapping (workspace_id, note_id, fts_rowid) \
             VALUES ('other-ws', 'note-1', ?1)",
            [other_fts_rowid],
        )
        .unwrap();

        let results = search_notes_impl(&conn, "milk", "ws", 50).unwrap();

        assert_eq!(
            results.len(),
            1,
            "only the active Workspace's match may be returned"
        );
        // The title is what distinguishes the two rows now that `NoteMetadata`
        // carries no `workspace_id`: both Workspaces hold a `note-1`, which is
        // exactly the collision a concept id being unique only within its own
        // bundle permits.
        assert_eq!(results[0].title, "Grocery List");
    }

    #[test]
    fn save_note_updates_last_modified_when_revision_matches() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        save_note_impl(&conn, "ws", "note-1", "1000", 2000).unwrap();

        let last_modified: i64 = conn
            .query_row(
                "SELECT last_modified FROM notes WHERE id = 'note-1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(last_modified, 2000);
    }

    #[test]
    fn save_note_rejects_a_stale_revision_with_git_conflict() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        let result = save_note_impl(&conn, "ws", "note-1", "999", 2000);

        assert_eq!(result, Err(AppError::GitConflict));
        // The row must be untouched by a rejected save.
        let last_modified: i64 = conn
            .query_row(
                "SELECT last_modified FROM notes WHERE id = 'note-1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(last_modified, 1000);
    }

    #[test]
    fn save_note_reports_a_clear_error_for_an_unknown_note_id() {
        let conn = seeded_db();

        let result = save_note_impl(&conn, "ws", "does-not-exist", "1000", 2000);

        assert_eq!(
            result,
            Err(AppError::IoError(
                "no note found with id does-not-exist".to_string()
            ))
        );
    }
}
