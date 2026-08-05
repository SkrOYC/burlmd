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

#[frb(sync)]
pub fn open_note(path: String) -> Result<NoteState, AppError> {
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
    // knows (WSPC-D003 declares the field, WSPC-D005 resolves it). Skipped
    // when no Workspace is active — this entry point still takes a filesystem
    // path rather than a concept id (WSPC-D008 reconciles that), so it is
    // reachable with no Workspace open at all, and a Link then keeps the
    // parser's `false`, which is also what "no indexed Note matches" means.
    if let Ok(workspace_id) = crate::db::connection::active_workspace_id() {
        crate::db::connection::with_connection(|conn| {
            crate::index::resolve_link_existence(conn, &workspace_id, &mut ast)
        })?;
    }

    let last_modified = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let metadata = NoteMetadata {
        // A second facet of the "open_note isn't wired to the notes table"
        // gap documented below on `base_revision`: `data-models/schema.sql`
        // defines `notes.id` as a stable UUID, but this is the filesystem
        // path (carried from Epic A's original implementation). Passing
        // this `id` into `save_note`/`update_block` today only works
        // because `update_block` matches against this same in-memory value,
        // never against a DB row — `save_note` keys on `notes.id` for real,
        // so it would need a real UUID once note creation/lookup is wired.
        id: path.clone(),
        workspace_id: "default".to_string(),
        path: path.clone(),
        title,
        last_modified,
        snippet: None,
    };

    let state = NoteState {
        ast,
        metadata,
        // A placeholder token, not yet the same OCC domain `save_note_impl`
        // checks against (`notes.last_modified`, stringified) — `open_note`
        // reads straight from the filesystem and never touches the `notes`
        // table, so there is no DB-backed revision to hand back yet. Passing
        // this value on to `save_note` today would always mismatch and
        // return `GitConflict`. Reconcile when the open->edit->save flow is
        // actually wired (no Markdown serializer/write-through exists yet;
        // see `architecture/risks.md` #6 and `flow-edit-note.md`).
        base_revision: "head".to_string(),
    };
    *crate::draft::active_note_cache()? = Some(state.clone());
    Ok(state)
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
pub(crate) const SEARCH_NOTES_SQL: &str = "SELECT n.id, n.workspace_id, n.path, n.title, \
            n.last_modified, snippet(notes_fts, 1, '', '', '…', 8) AS snippet \
     FROM notes_fts \
     CROSS JOIN fts_mapping ON fts_mapping.fts_rowid = notes_fts.rowid \
     CROSS JOIN notes n ON n.workspace_id = fts_mapping.workspace_id \
                        AND n.id = fts_mapping.note_id \
     WHERE notes_fts MATCH ?1 AND fts_mapping.workspace_id = ?2 \
     ORDER BY rank \
     LIMIT 50";

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
/// Capped at the top 50 matches, with no pagination cursor and no signal to
/// the caller when a query matches more than that (see the matching note on
/// this function in `tech-spec/contracts/ffi_api.rs`) — acceptable for now
/// since no search UI exists yet to expose more, but worth revisiting before
/// one does.
fn search_notes_impl(
    conn: &rusqlite::Connection,
    query: &str,
    workspace_id: &str,
) -> Result<Vec<NoteMetadata>, AppError> {
    let fts_query = fts5_phrase_query(query);
    if fts_query.is_empty() {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(SEARCH_NOTES_SQL)?;

    let rows = stmt.query_map(rusqlite::params![fts_query, workspace_id], |row| {
        Ok(NoteMetadata {
            id: row.get(0)?,
            workspace_id: row.get(1)?,
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
pub async fn search_notes(query: String) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| search_notes_impl(conn, &query, &workspace_id))
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

        let results = search_notes_impl(&conn, "milk", "ws").unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "note-1");
        assert_eq!(results[0].title, "Grocery List");
        assert_eq!(results[0].workspace_id, "ws");
        assert_eq!(results[0].last_modified, 1000);
        assert!(results[0].snippet.as_deref().unwrap().contains("milk"));
    }

    #[test]
    fn search_notes_returns_no_results_for_a_non_matching_query() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        let results = search_notes_impl(&conn, "spaceship", "ws").unwrap();

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
            search_notes_impl(&conn, query, "ws").unwrap();
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

        let results = search_notes_impl(&conn, "milk bread", "ws").unwrap();

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

        assert!(search_notes_impl(&conn, "", "ws").unwrap().is_empty());
        assert!(search_notes_impl(&conn, "   ", "ws").unwrap().is_empty());
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

        let results = search_notes_impl(&conn, "milk", "ws").unwrap();

        assert_eq!(
            results.len(),
            1,
            "only the active Workspace's match may be returned"
        );
        assert_eq!(results[0].workspace_id, "ws");
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
