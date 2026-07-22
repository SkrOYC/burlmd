use std::sync::Mutex;

use flutter_rust_bridge::frb;

// AST types are owned by the `markdown` domain module (parsing is what
// produces and shapes them); re-exported here so they cross the FFI
// boundary FRB scans (`rust_input: crate::api`) without `markdown`
// having to depend back on this module for its own output types. `AppError`
// is re-exported the same way, from a shared leaf module, so `db` and
// `security` can report failures without depending upward on `api`.
pub use crate::error::AppError;
pub use crate::markdown::{AstNode, InlineElement, TextRun};

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteMetadata {
    pub id: String,
    pub workspace_id: String,
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    pub snippet: Option<String>,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    pub base_revision: String,
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

    let ast = crate::markdown::parse_markdown(&content);

    let last_modified = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let metadata = NoteMetadata {
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
    *active_note_cache()? = Some(state.clone());
    Ok(state)
}

/// Holds the AST of the note currently open in the editor, kept in memory so
/// `update_block` can apply keystroke-level edits without a disk round trip.
/// Single-slot: this project's UI has exactly one active note at a time.
static ACTIVE_NOTE_CACHE: Mutex<Option<NoteState>> = Mutex::new(None);

fn active_note_cache() -> Result<std::sync::MutexGuard<'static, Option<NoteState>>, AppError> {
    ACTIVE_NOTE_CACHE
        .lock()
        .map_err(|_| AppError::DatabaseError("active note cache poisoned".to_string()))
}

/// Descends `path` into `nodes`, replacing the addressed node with
/// `new_node`. Only `List`/`ListItem`/`Blockquote` hold nested `Vec<AstNode>`
/// and can be descended through; `Suggestion`'s three branches are
/// deliberately not addressable here (that's `resolve_suggestion`'s job).
fn set_node_at_path(
    nodes: &mut [AstNode],
    path: &[usize],
    new_node: AstNode,
) -> Result<(), AppError> {
    let (&idx, rest) = path
        .split_first()
        .ok_or_else(|| AppError::ParseError("empty block_path".to_string()))?;
    let node = nodes
        .get_mut(idx)
        .ok_or_else(|| AppError::ParseError(format!("block_path index {idx} out of range")))?;

    if rest.is_empty() {
        *node = new_node;
        return Ok(());
    }

    match node {
        AstNode::List { items, .. } => set_node_at_path(items, rest, new_node),
        AstNode::ListItem { content, .. } => set_node_at_path(content, rest, new_node),
        AstNode::Blockquote { nodes, .. } => set_node_at_path(nodes, rest, new_node),
        AstNode::Suggestion { .. } => Err(AppError::ParseError(
            "update_block cannot descend into Suggestion nodes; use resolve_suggestion".to_string(),
        )),
        _ => Err(AppError::ParseError(format!(
            "block_path continues past a leaf node at index {idx}"
        ))),
    }
}

/// Applies a keystroke-level edit to the currently open note's in-memory
/// AST and returns the updated `NoteState`. `block_path` is an index path
/// into the AST tree (see `set_node_at_path`); it does not persist the
/// change to disk or the DB — that happens via `save_note`.
#[frb(sync)]
pub fn update_block(
    note_id: String,
    block_path: Vec<usize>,
    new_node: AstNode,
) -> Result<NoteState, AppError> {
    let mut cache = active_note_cache()?;
    let state = cache
        .as_mut()
        .filter(|s| s.metadata.id == note_id)
        .ok_or_else(|| AppError::IoError(format!("no open note with id {note_id}")))?;
    set_node_at_path(&mut state.ast, &block_path, new_node)?;
    Ok(state.clone())
}

/// Full-text search over all indexed notes, ordered by FTS5 relevance
/// (bm25, best match first). `notes_fts` only carries `(title, content)`;
/// `fts_mapping` is the note_id <-> fts_rowid join table maintained
/// alongside it, used here to recover the owning `notes` row per hit.
fn search_notes_impl(
    conn: &rusqlite::Connection,
    query: &str,
) -> Result<Vec<NoteMetadata>, AppError> {
    let mut stmt = conn.prepare(
        "SELECT n.id, n.workspace_id, n.path, n.title, n.last_modified, \
                snippet(notes_fts, 1, '', '', '…', 8) AS snippet \
         FROM notes_fts \
         JOIN fts_mapping ON fts_mapping.fts_rowid = notes_fts.rowid \
         JOIN notes n ON n.id = fts_mapping.note_id \
         WHERE notes_fts MATCH ?1 \
         ORDER BY rank \
         LIMIT 50",
    )?;

    let rows = stmt.query_map([query], |row| {
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
    crate::db::connection::with_connection(|conn| search_notes_impl(conn, &query))
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
fn save_note_impl(
    conn: &rusqlite::Connection,
    note_id: &str,
    expected_base_revision: &str,
    now: i64,
) -> Result<(), AppError> {
    let current: i64 = conn
        .query_row(
            "SELECT last_modified FROM notes WHERE id = ?1",
            [note_id],
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
        "UPDATE notes SET last_modified = ?1 WHERE id = ?2",
        rusqlite::params![now, note_id],
    )?;
    Ok(())
}

#[frb(sync)]
pub fn save_note(note_id: String, expected_base_revision: String) -> Result<(), AppError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    crate::db::connection::with_connection(|conn| {
        save_note_impl(conn, &note_id, &expected_base_revision, now)
    })
}

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::*;

    // `set_node_at_path` is tested directly as a pure function rather than
    // through `update_block`, which reads/writes the process-wide
    // `ACTIVE_NOTE_CACHE` static: exercising that shared mutable state from
    // parallel test threads would make tests interfere with each other,
    // mirroring why `search_notes_impl`/`save_note_impl` below are tested
    // against an isolated connection instead of the DB singleton.
    fn text_paragraph(s: &str) -> AstNode {
        AstNode::Paragraph {
            content: vec![InlineElement::Text(TextRun {
                content: s.to_string(),
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
            })],
        }
    }

    #[test]
    fn set_node_at_path_replaces_a_top_level_node() {
        let mut nodes = vec![text_paragraph("a"), text_paragraph("b")];
        set_node_at_path(&mut nodes, &[1], text_paragraph("replaced")).unwrap();

        assert_eq!(nodes[0], text_paragraph("a"));
        assert_eq!(nodes[1], text_paragraph("replaced"));
    }

    #[test]
    fn set_node_at_path_descends_through_list_and_list_item() {
        let mut nodes = vec![AstNode::List {
            ordered: false,
            items: vec![AstNode::ListItem {
                content: vec![text_paragraph("original")],
                checked: None,
            }],
        }];

        set_node_at_path(&mut nodes, &[0, 0, 0], text_paragraph("edited")).unwrap();

        let AstNode::List { items, .. } = &nodes[0] else {
            panic!("expected a List node");
        };
        let AstNode::ListItem { content, .. } = &items[0] else {
            panic!("expected a ListItem node");
        };
        assert_eq!(content[0], text_paragraph("edited"));
    }

    #[test]
    fn set_node_at_path_descends_through_blockquote() {
        let mut nodes = vec![AstNode::Blockquote {
            nodes: vec![text_paragraph("original")],
        }];

        set_node_at_path(&mut nodes, &[0, 0], text_paragraph("edited")).unwrap();

        let AstNode::Blockquote { nodes: inner, .. } = &nodes[0] else {
            panic!("expected a Blockquote node");
        };
        assert_eq!(inner[0], text_paragraph("edited"));
    }

    #[test]
    fn set_node_at_path_rejects_an_empty_path() {
        let mut nodes = vec![text_paragraph("a")];
        let result = set_node_at_path(&mut nodes, &[], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_an_out_of_range_index() {
        let mut nodes = vec![text_paragraph("a")];
        let result = set_node_at_path(&mut nodes, &[5], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_descending_into_a_leaf_node() {
        let mut nodes = vec![text_paragraph("a")];
        // Paragraph has no nested Vec<AstNode> to descend into.
        let result = set_node_at_path(&mut nodes, &[0, 0], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

    #[test]
    fn set_node_at_path_rejects_descending_into_a_suggestion() {
        let mut nodes = vec![AstNode::Suggestion {
            base_content: None,
            local_content: vec![text_paragraph("local")],
            incoming_content: vec![text_paragraph("incoming")],
        }];
        let result = set_node_at_path(&mut nodes, &[0, 0], text_paragraph("x"));
        assert!(matches!(result, Err(AppError::ParseError(_))));
    }

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

    fn seed_note(conn: &Connection, id: &str, title: &str, content: &str, last_modified: i64) {
        conn.execute(
            "INSERT INTO notes (id, workspace_id, path, title, last_modified) \
             VALUES (?1, 'ws', ?2, ?3, ?4)",
            rusqlite::params![id, format!("{id}.md"), title, last_modified],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO notes_fts (title, content) VALUES (?1, ?2)",
            rusqlite::params![title, content],
        )
        .unwrap();
        let fts_rowid = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO fts_mapping (note_id, fts_rowid) VALUES (?1, ?2)",
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

        let results = search_notes_impl(&conn, "milk").unwrap();

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

        let results = search_notes_impl(&conn, "spaceship").unwrap();

        assert!(results.is_empty());
    }

    #[test]
    fn save_note_updates_last_modified_when_revision_matches() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        save_note_impl(&conn, "note-1", "1000", 2000).unwrap();

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

        let result = save_note_impl(&conn, "note-1", "999", 2000);

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

        let result = save_note_impl(&conn, "does-not-exist", "1000", 2000);

        assert_eq!(
            result,
            Err(AppError::IoError(
                "no note found with id does-not-exist".to_string()
            ))
        );
    }
}
