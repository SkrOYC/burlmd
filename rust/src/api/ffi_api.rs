use flutter_rust_bridge::frb;

// AST types are owned by the `markdown` domain module (parsing is what
// produces and shapes them); re-exported here so they cross the FFI
// boundary FRB scans (`rust_input: crate::api`) without `markdown`
// having to depend back on this module for its own output types. `AppError`
// is re-exported the same way, from a shared leaf module, so `db` and
// `security` can report failures without depending upward on `api`.
// `NoteMetadata`/`NoteState` are re-exported from `draft` — this module's own
// job is just the thin `#[frb]` wrappers below, not the draft-state domain
// logic.
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

/// Opens a Note by concept id, restoring an unflushed draft if one exists
/// (ADR-008 tier 1's crash recovery).
///
/// Replaces the previous `open_note(path)` entry point and the
/// `open_note_by_id(note_id)` the pre-v1.1.0 contract also named but never
/// implemented: under ADR-004 a Note's identity is unambiguous, so there is
/// exactly one open-a-Note entry point, and it is this one — a concept id,
/// never a filesystem path and never a `workspace_id` (the active Workspace
/// is always whichever `open_or_create_local_workspace`/`open_workspace` most
/// recently established).
///
/// `workspace::persist::open_note` is what this delegates to, and it already
/// carries the two obligations that mattered here: it rejects a concept id
/// that escapes the Workspace root (a lexical `../` check plus a
/// canonicalized containment check for a path that exists), and it parses
/// with the Note's real bundle-relative containing directory rather than an
/// empty one, so a Link inside a nested Note resolves against its own
/// directory instead of the bundle root.
///
/// `async` per the contract, though the body below runs to completion
/// synchronously with no `.await` — see `search_notes`'s comment on the same
/// point.
#[frb]
pub async fn open_note(note_id: String) -> Result<NoteState, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    let (_, state) = crate::workspace::persist::open_note(&workspace, &note_id)?;
    Ok(state)
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

// ---------------------------------------------------------------------------
// Editing (ADR-006, ADR-007)
//
// `update_block` is the per-keystroke call and the only one that does not
// parse: it substitutes text, adjusts spans arithmetically, writes the draft
// row, and returns nothing. Every other mutator below reparses the working
// source, rebuilds the span map, and returns the whole new state.
// `commit_block` is the one exception in both directions: it reparses but
// writes nothing, because `update_block` already put the text it reparses
// into both the working source and the draft row. See `contracts/ffi_api.rs`'s
// Editing section header for the reasoning in full.
// ---------------------------------------------------------------------------

/// The raw Markdown source of one Block, for populating the editable field
/// when it takes focus (ADR-006 decision 2). Includes the Block's own
/// delimiters and its terminating newline — whatever this hands the UI must
/// come back to `update_block` unmodified in the untouched portion, or the
/// next `commit_block` reparses a working source missing the separator that
/// kept this Block distinct from its neighbor, and the two silently merge.
#[frb(sync)]
pub fn get_block_source(note_id: String, block_path: Vec<usize>) -> Result<String, AppError> {
    open_session(&note_id)?.block_source(&block_path)
}

/// The per-keystroke call (ADR-007 decision 4, ADR-008 tier 1): substitutes
/// `new_source` into the Note's working source over the focused Block's
/// span, adjusts the span map arithmetically, and writes the draft row. Does
/// **not** parse and returns nothing — the reparse belongs to `commit_block`,
/// which is what keeps this call cheap enough to stay off the frame-budget
/// critical path.
#[frb(sync)]
pub fn update_block(
    note_id: String,
    block_path: Vec<usize>,
    new_source: String,
) -> Result<(), AppError> {
    open_session(&note_id)?.update_block(&block_path, &new_source)
}

/// Reparses the Note's working source and rebuilds the span map when the
/// focused Block loses focus (ADR-007 decision 1). Performs no splice —
/// `update_block` already substituted the text this reparses, so splicing it
/// again here would duplicate it (ADR-008 decision 2's failure mode). Writes
/// no draft row either, for the matching reason: `update_block` already wrote
/// whatever this reparses, and tier 2 clears the row on a successful write.
#[frb(sync)]
pub fn commit_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    open_session(&note_id)?.commit_block(&block_path)
}

/// Inserts a new Block at `block_path`, shifting subsequent Blocks down.
#[frb(sync)]
pub fn insert_block(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.insert_block(&block_path, source)
}

#[frb(sync)]
pub fn delete_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    open_session(&note_id)?.delete_block(&block_path)
}

/// Splits a Block at a **source** offset -- pressing Enter mid-Block
/// (CAP-EDIT-03). The focused Block displays raw source under ADR-006, so the
/// caret position the UI reports is already a source offset.
#[frb(sync)]
pub fn split_block(
    note_id: String,
    block_path: Vec<usize>,
    offset: usize,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.split_block(&block_path, offset)
}

/// Merges a Block into its predecessor -- Backspace at offset 0
/// (CAP-EDIT-03). A no-op on the first Block.
#[frb(sync)]
pub fn merge_block_with_previous(
    note_id: String,
    block_path: Vec<usize>,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.merge_block_with_previous(&block_path)
}

/// A selection spanning one or more Blocks, expressed as character offsets
/// into each Block's **rendered** text (ADR-006 decision 3). See
/// `contracts/ffi_api.rs` for the per-`AstNode`-variant definition of
/// "rendered text" these offsets are into.
#[frb]
pub struct BlockRange {
    pub start_path: Vec<usize>,
    pub start_offset: usize,
    pub end_path: Vec<usize>,
    pub end_offset: usize,
}

/// A pure change of ownership. `BlockRange` is `markdown::spans::RenderedRange`'s
/// FFI-boundary twin and the two carry the same four fields for exactly that
/// reason — see that type's own documentation.
impl From<BlockRange> for crate::markdown::RenderedRange {
    fn from(range: BlockRange) -> Self {
        crate::markdown::RenderedRange::new(
            range.start_path,
            range.start_offset,
            range.end_path,
            range.end_offset,
        )
    }
}

/// Markdown for a multi-Block selection (CAP-EDIT-04), executed Core-side
/// because the Core owns both the AST and the source text; reproducing it in
/// Dart would mean a second serializer.
#[frb(sync)]
pub fn copy_range_as_markdown(note_id: String, range: BlockRange) -> Result<String, AppError> {
    open_session(&note_id)?.copy_range_as_markdown(&range.into())
}

#[frb(sync)]
pub fn delete_range(note_id: String, range: BlockRange) -> Result<NoteState, AppError> {
    open_session(&note_id)?.delete_range(&range.into())
}

/// Replaces a multi-Block selection with text -- typing over a selection that
/// crosses Blocks. The caller must re-derive caret position from the
/// returned state rather than reusing anything passed in.
#[frb(sync)]
pub fn replace_range(
    note_id: String,
    range: BlockRange,
    replacement: String,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.replace_range(&range.into(), &replacement)
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

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::*;

    // These exercise `search_notes_impl` directly against an in-memory,
    // unencrypted connection rather than through the `search_notes` FFI
    // wrapper and the process-wide `db::connection::connection()` singleton:
    // the singleton is lazily initialized once per test binary, so routing
    // through it here would make tests order-dependent on which one opens
    // (and fixes the path of) the shared connection first. Encryption itself
    // is already covered by `db::connection`'s own tests; these tests are
    // only responsible for the SQL logic.
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

    // -- WSPC-D008: the editing FFI surface ---------------------------------
    //
    // Every function under test here — `get_block_source`, `update_block`,
    // `commit_block`, `split_block`, `merge_block_with_previous`,
    // `copy_range_as_markdown` — is a thin delegation onto `NoteSession`, so
    // these tests exercise the session directly through the same
    // `Workspace::for_test` seam `workspace::persist`'s own tests use, rather
    // than through the real `#[frb]` wrapper. Going through the wrapper would
    // mean routing through `db::connection::active_workspace_id`, which is
    // process-wide singleton state shared with `db::connection`'s own tests
    // (see that module's `active_workspace_id_reports_the_id_a_bootstrap_call_established`);
    // nothing here should race that. `open_session`'s delegation itself —
    // "call this one-line function with these arguments" — is checked by the
    // compiler at the `#[frb]` boundary: a wrong argument order or a wrong
    // return type does not compile.
    use std::sync::atomic::{AtomicU32, Ordering as AtomicOrdering};
    use std::time::Duration;

    use tempfile::TempDir;

    use crate::workspace::persist::{self, NoteSession, Workspace};

    struct EditingFixture {
        // Held for its `Drop` impl, which removes the temp directory; never
        // read directly.
        #[allow(dead_code)]
        dir: TempDir,
        workspace: std::sync::Arc<Workspace>,
    }

    impl EditingFixture {
        fn root(&self) -> std::path::PathBuf {
            self.dir.path().join("bundle")
        }

        fn write(&self, relative: &str, contents: &str) {
            let path = self.root().join(relative);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, contents).unwrap();
        }

        fn open(&self, note_id: &str) -> NoteSession {
            persist::open_note(&self.workspace, note_id).unwrap().0
        }
    }

    fn editing_fixture() -> EditingFixture {
        static NEXT_WORKSPACE: AtomicU32 = AtomicU32::new(0);

        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("bundle");
        std::fs::create_dir_all(&root).unwrap();
        crate::git::operations::init_repo(&root).unwrap();

        let key = [0x7bu8; 32]; // throwaway, never the real Keychain entry
        let conn = crate::db::connection::open_encrypted_db_with_key(
            &dir.path().join("index.sqlite3"),
            &key,
        )
        .unwrap();
        crate::db::connection::init_schema(&conn).unwrap();

        let workspace_id = format!(
            "ffi-editing-ws-{}",
            NEXT_WORKSPACE.fetch_add(1, AtomicOrdering::SeqCst)
        );
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES (?1, 'Test Workspace', 'local', NULL, ?2)",
            rusqlite::params![workspace_id, root.to_string_lossy()],
        )
        .unwrap();

        // An interval no test here waits out: every scenario fires the tiers
        // (or none at all) explicitly.
        let workspace = Workspace::for_test(conn, workspace_id, root, Duration::from_secs(3600));
        EditingFixture { dir, workspace }
    }

    fn note_source(title: &str, body: &str) -> String {
        format!("---\ntype: Note\ntitle: {title}\n---\n\n{body}\n")
    }

    /// TDD order 1: `get_block_source` returns the raw Block source
    /// *including its terminating newline*, and feeding that text back into
    /// `update_block` unmodified must round-trip through `commit_block`
    /// without the two paragraphs silently merging — the D007 warning that
    /// whatever `get_block_source` hands back must come back verbatim.
    #[test]
    fn block_source_includes_the_terminating_newline_and_round_trips_without_merging() {
        let f = editing_fixture();
        f.write(
            "a.md",
            &note_source("A", "First paragraph.\n\nSecond paragraph."),
        );
        let session = f.open("a");

        let source = session.block_source(&[0]).unwrap();
        assert!(
            source.ends_with('\n'),
            "a Block's own source must include its terminating newline, got {source:?}"
        );
        assert_eq!(source, "First paragraph.\n");

        session.update_block(&[0], &source).unwrap();
        let state = session.commit_block(&[0]).unwrap();

        assert_eq!(
            state.ast.len(),
            2,
            "feeding get_block_source's own text back into update_block \
             verbatim must not merge the two paragraphs into one"
        );
    }

    /// TDD order 2: `update_block` writes the draft row but performs no
    /// parse — the AST held by the session (and the type system: `Result<(),
    /// AppError>` carries none back) is untouched until `commit_block` runs.
    #[test]
    fn update_block_writes_the_draft_row_and_does_not_reparse() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "Original text."));
        let session = f.open("a");
        let before = session.note_state().unwrap();
        assert!(!session.write_status().unwrap().has_unwritten_edits);

        session
            .update_block(&[0], "Rewritten, longer text.\n")
            .unwrap();

        assert!(
            session.write_status().unwrap().has_unwritten_edits,
            "update_block must write the draft row"
        );
        let after = session.note_state().unwrap();
        assert_eq!(
            after.ast, before.ast,
            "update_block must not reparse or rebuild the AST — that is \
             commit_block's job"
        );
        assert_eq!(
            after.base_revision, before.base_revision,
            "update_block must not touch the file on disk"
        );
    }

    /// TDD order 3: `commit_block` reparses the working source `update_block`
    /// already substituted into, and performs no second substitution — the
    /// typed text appears exactly once.
    #[test]
    fn commit_block_reparses_without_a_second_substitution() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "plain text"));
        let session = f.open("a");

        session.update_block(&[0], "- now a list\n").unwrap();
        let state = session.commit_block(&[0]).unwrap();

        assert!(
            matches!(state.ast[0], AstNode::List { .. }),
            "commit_block must reparse: the structural shape change only \
             appears after it, got {:?}",
            state.ast[0]
        );
        let source = session.working_source().unwrap();
        assert_eq!(
            source.matches("now a list").count(),
            1,
            "commit_block must not splice update_block's text in a second time"
        );
    }

    /// TDD order 4 (first half): splitting a Block at an offset produces two
    /// Blocks whose combined text reproduces the original — split introduces
    /// exactly one new separating newline, which is stripped from both sides
    /// before comparing so the check is about content, not formatting.
    #[test]
    fn splitting_a_block_produces_two_blocks_whose_combined_source_equals_the_original() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "helloworld"));
        let session = f.open("a");
        let original = session.block_source(&[0]).unwrap();

        let state = session.split_block(&[0], 5).unwrap();

        assert_eq!(state.ast.len(), 2, "a split must produce two Blocks");
        let first = session.block_source(&[0]).unwrap();
        let second = session.block_source(&[1]).unwrap();
        assert_eq!(
            format!("{first}{second}").replace('\n', ""),
            original.replace('\n', ""),
            "splitting must not lose or duplicate any of the original \
             Block's text"
        );
    }

    /// TDD order 4 (second half): merging the first Block with its
    /// (nonexistent) predecessor is a no-op and returns the unchanged state.
    #[test]
    fn merging_the_first_block_with_its_predecessor_is_a_no_op() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "first\n\nsecond"));
        let session = f.open("a");
        let before = session.note_state().unwrap();

        let after = session.merge_block_with_previous(&[0]).unwrap();

        assert_eq!(
            after, before,
            "there is no predecessor of the first Block, so this must be a \
             no-op returning the unchanged state"
        );
    }

    /// TDD order 5: a selection spanning three Blocks, copied as Markdown,
    /// reproduces the selected content across all three.
    #[test]
    fn copying_a_range_across_three_blocks_reproduces_all_three() {
        let f = editing_fixture();
        f.write(
            "a.md",
            &note_source("A", "first block\n\nsecond block\n\nthird block"),
        );
        let session = f.open("a");
        let state = session.note_state().unwrap();
        assert_eq!(state.ast.len(), 3);

        let end_offset = crate::markdown::rendered_text(&state.ast[2])
            .chars()
            .count();
        let range = crate::markdown::RenderedRange::new(vec![0], 0, vec![2], end_offset);

        let copied = session.copy_range_as_markdown(&range).unwrap();

        assert!(copied.contains("first block"));
        assert!(copied.contains("second block"));
        assert!(copied.contains("third block"));
    }

    /// `BlockRange` (the FFI-boundary type) converts to `RenderedRange` (the
    /// Core-side type `copy_range_as_markdown`/`delete_range`/`replace_range`
    /// actually resolve against) by pure field mapping — no reinterpretation.
    #[test]
    fn block_range_converts_to_rendered_range_by_pure_field_mapping() {
        let range = BlockRange {
            start_path: vec![0],
            start_offset: 3,
            end_path: vec![1, 2],
            end_offset: 9,
        };

        let converted: crate::markdown::RenderedRange = range.into();

        assert_eq!(converted.start_path, vec![0]);
        assert_eq!(converted.start_offset, 3);
        assert_eq!(converted.end_path, vec![1, 2]);
        assert_eq!(converted.end_offset, 9);
    }

    /// TDD order 6 (surface conformance): `open_note` accepts a concept id,
    /// there is exactly one open-a-Note entry point, and no exposed function
    /// takes a `workspace_id` parameter.
    ///
    /// Verified by scanning this file's own source rather than by runtime
    /// reflection: Rust has no introspection over a module's public function
    /// signatures, and `#[frb]` erases to an ordinary `pub fn`/`pub async fn`
    /// the compiler does not tag distinctly. An explicit assertion over the
    /// `#[frb]` surface's own source text is the form `WSPC-D008`'s STOP
    /// condition on this point names as the fallback when a compile-time
    /// check is not practical.
    #[test]
    fn the_ffi_surface_has_one_concept_id_open_entry_point_and_no_function_takes_a_workspace_id() {
        let source = include_str!("ffi_api.rs");

        // Every needle below is assembled from parts rather than written as
        // one literal: this test is itself part of `source` (`include_str!`
        // reads the whole file, this function included), so a literal needle
        // spelling out the pattern it searches for would match its own line
        // too and corrupt the count/contains checks. Splitting each pattern
        // across a `format!` concatenation keeps it out of the file as a
        // contiguous string while still producing the real pattern at
        // runtime.
        let fn_open_note = format!("{}{}", "fn open_", "note(");
        let open_note_signature =
            format!("{}{}{}", "pub async fn open_", "note(note_id", ": String)");
        let workspace_id_param = format!("{}{}", "workspace_id", ": String");

        assert_eq!(
            source.matches(fn_open_note.as_str()).count(),
            1,
            "there must be exactly one open-a-Note entry point"
        );
        assert!(
            source.contains(open_note_signature.as_str()),
            "open_note must take a concept id named note_id, not a path or a \
             workspace_id"
        );
        assert!(
            !source.contains(workspace_id_param.as_str()),
            "no exposed function may take a workspace_id parameter — the \
             active Workspace is always resolved Core-side"
        );
    }
}
