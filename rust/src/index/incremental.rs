//! The routine index path: rewriting one Note's rows after one write.
//!
//! `architecture/risks.md` risk 3 is explicit that a full rescan must not be
//! how the index stays current during ordinary editing, and this ticket's
//! first STOP condition restates it. So every write goes through here, and
//! [`scan`](super::scan) is reserved for first open, post-merge
//! reconciliation, and recovery.
//!
//! Nothing in this module reads the directory tree. The only file it touches
//! is the one Note it was asked about, which is what makes "no full rescan"
//! a structural property rather than a promise.

use rusqlite::{Connection, OptionalExtension};

use crate::error::AppError;

use super::{analyze, in_transaction, insert_note_rows, remove_note_rows, workspace_root};

/// Whether [`index_note`] had anything to do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IndexOutcome {
    /// The file on disk hashes to what `notes.content_hash` already records,
    /// so no row was touched. This is the common case on a path that runs
    /// after every write: a tier-2 write that changed nothing, a reopened
    /// Note, a pull that brought no change to this file.
    Unchanged,
    /// The Note's rows were rewritten.
    Updated,
}

/// Brings one Note's index rows in line with the file on disk, and returns
/// whether anything changed.
///
/// Short-circuits on `notes.content_hash`: the same hash ADR-007 decision 7
/// makes the OCC token is also what says the rows are still current, so an
/// unchanged file costs one hash of its bytes and one indexed lookup.
///
/// A rewrite deletes through [`remove_note_rows`] — full-text row first,
/// through `fts_mapping`, then the `notes` row — before inserting the new
/// ones. The single-Note path is subject to the same ordering STOP as the
/// rebuild, and runs far more often.
pub fn index_note(
    conn: &Connection,
    workspace_id: &str,
    concept_id: &str,
) -> Result<IndexOutcome, AppError> {
    let root = workspace_root(conn, workspace_id)?;
    let Some(note) = super::scan::read_note(&root, concept_id)? else {
        return Err(AppError::NotFound(format!(
            "no file on disk for concept id {concept_id}"
        )));
    };

    let stored_hash: Option<String> = conn
        .query_row(
            "SELECT content_hash FROM notes WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace_id, concept_id],
            |row| row.get(0),
        )
        .optional()?;
    if stored_hash.as_deref() == Some(note.content_hash.as_str()) {
        return Ok(IndexOutcome::Unchanged);
    }

    in_transaction(conn, |tx| {
        remove_note_rows(tx, workspace_id, concept_id)?;
        ensure_directories(tx, workspace_id, concept_id)?;
        insert_note_rows(tx, workspace_id, &note)
    })?;

    // Only on a real rewrite: `ANALYZE` re-reads the index's own b-trees, so
    // running it after a no-op would put that cost on every keystroke-adjacent
    // write for statistics that cannot have changed.
    analyze(conn)?;
    Ok(IndexOutcome::Updated)
}

/// Records a `directories` row for every ancestor directory of `concept_id`
/// that has none yet.
///
/// A Note can be the first thing ever written into a Directory (`create_note`
/// into a Directory created in the same session), and the tree renders from
/// `directories` alone — an ancestor missing there is a Note the sidebar
/// cannot reach without a full rebuild.
fn ensure_directories(
    conn: &Connection,
    workspace_id: &str,
    concept_id: &str,
) -> Result<(), AppError> {
    let Some((dir, _)) = concept_id.rsplit_once('/') else {
        return Ok(());
    };
    let mut stmt = conn.prepare(
        "INSERT OR IGNORE INTO directories (id, workspace_id, path) VALUES (?1, ?2, ?1)",
    )?;
    let mut ancestor = String::new();
    for segment in dir.split('/').filter(|s| !s.is_empty()) {
        if !ancestor.is_empty() {
            ancestor.push('/');
        }
        ancestor.push_str(segment);
        stmt.execute(rusqlite::params![ancestor, workspace_id])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::fixtures::*;
    use super::super::scan::reindex_workspace_impl;
    use super::*;

    /// Gherkin: when a single Note has changed on disk, only that Note's rows
    /// are rewritten and no full rescan occurs.
    ///
    /// The sentinel is what makes "no full rescan" observable: it is written
    /// straight into another Note's row, where nothing on disk agrees with
    /// it, so any rescan of the bundle would overwrite it.
    #[test]
    fn only_the_changed_notes_rows_are_rewritten() {
        let f = fixture();
        f.write("a.md", &conformant("A", "original alpha [Old](</old.md>)"));
        f.write("b.md", &conformant("B", "beta body"));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();
        f.conn
            .execute(
                "UPDATE notes SET title = 'SENTINEL' WHERE workspace_id = ?1 AND id = 'b'",
                [&f.workspace_id],
            )
            .unwrap();

        f.write("a.md", &conformant("A", "rewritten alpha [New](</new.md>)"));
        let outcome = index_note(&f.conn, &f.workspace_id, "a").unwrap();

        assert_eq!(outcome, IndexOutcome::Updated);
        let sentinel: String = f
            .conn
            .query_row(
                "SELECT title FROM notes WHERE workspace_id = ?1 AND id = 'b'",
                [&f.workspace_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(
            sentinel, "SENTINEL",
            "b's row was rewritten, so a full rescan ran"
        );
        assert_eq!(f.note_ids(), vec!["a", "b"]);

        // a's own rows did move, in every table it owns.
        assert_eq!(f.raw_fts_matches("rewritten"), 1);
        assert_eq!(f.raw_fts_matches("original"), 0);
        let targets: Vec<String> = {
            let mut stmt = f
                .conn
                .prepare("SELECT target_id FROM links WHERE workspace_id = ?1 AND source_id = 'a'")
                .unwrap();
            let rows = stmt
                .query_map([&f.workspace_id], |row| row.get(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows
        };
        assert_eq!(targets, vec!["new".to_string()]);
    }

    /// The short-circuit that keeps the routine path cheap: an unchanged file
    /// rewrites nothing at all.
    #[test]
    fn an_unchanged_note_is_not_rewritten() {
        let f = fixture();
        f.write("a.md", &conformant("A", "stable body"));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();
        let rowid_before: i64 = f
            .conn
            .query_row(
                "SELECT fts_rowid FROM fts_mapping WHERE workspace_id = ?1 AND note_id = 'a'",
                [&f.workspace_id],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(
            index_note(&f.conn, &f.workspace_id, "a").unwrap(),
            IndexOutcome::Unchanged
        );

        let rowid_after: i64 = f
            .conn
            .query_row(
                "SELECT fts_rowid FROM fts_mapping WHERE workspace_id = ?1 AND note_id = 'a'",
                [&f.workspace_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(rowid_before, rowid_after, "no row was rewritten");
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 1);
    }

    /// The ordering STOP on the incremental path: rewriting one Note must not
    /// strand its previous full-text row.
    #[test]
    fn an_incremental_rewrite_strands_no_full_text_row() {
        let f = fixture();
        f.write(
            "a.md",
            &conformant("A", "antidisestablishmentarianism is distinctive"),
        );
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        f.write("a.md", &conformant("A", "completely different words"));
        index_note(&f.conn, &f.workspace_id, "a").unwrap();

        assert_eq!(
            f.raw_fts_matches("antidisestablishmentarianism"),
            0,
            "the superseded notes_fts row is orphaned and now undeletable"
        );
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 1);
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 1);
    }

    /// Gherkin: `ANALYZE` has been run after an incremental reindex too, not
    /// only after a rebuild.
    #[test]
    fn an_incremental_reindex_runs_analyze() {
        let f = fixture();
        f.write("a.md", &conformant("A", "body"));
        // No full reindex first: `sqlite_stat1` does not exist until some
        // path runs ANALYZE, so its presence afterwards is attributable to
        // this call alone.
        assert_eq!(
            f.count("SELECT count(*) FROM sqlite_master WHERE name = 'sqlite_stat1'"),
            0
        );

        index_note(&f.conn, &f.workspace_id, "a").unwrap();

        assert!(f.count("SELECT count(*) FROM sqlite_stat1") > 0);
    }

    /// A Note written into a Directory the index has never seen brings that
    /// Directory's row with it — the tree renders from `directories` alone.
    #[test]
    fn indexing_a_note_in_a_new_directory_records_its_ancestors() {
        let f = fixture();
        f.write("deep/nested/a.md", &conformant("A", "body"));

        index_note(&f.conn, &f.workspace_id, "deep/nested/a").unwrap();

        let mut stmt = f
            .conn
            .prepare("SELECT id FROM directories WHERE workspace_id = ?1 ORDER BY id")
            .unwrap();
        let dirs: Vec<String> = stmt
            .query_map([&f.workspace_id], |row| row.get(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(dirs, vec!["deep", "deep/nested"]);
    }

    /// `WSPC-D006`'s rename is one atomic operation over the file, the Note's
    /// rows and every inbound Link (`architecture/risks.md` risk 8), so it
    /// calls in from inside a transaction of its own. Joining that transaction
    /// rather than failing on a nested one is what lets the index rows commit
    /// or roll back with the rest of the operation.
    #[test]
    fn indexing_joins_a_transaction_the_caller_already_opened() {
        let f = fixture();
        f.write("a.md", &conformant("A", "body"));

        let tx = f.conn.unchecked_transaction().unwrap();
        index_note(&f.conn, &f.workspace_id, "a").unwrap();
        tx.rollback().unwrap();

        assert_eq!(f.count("SELECT count(*) FROM notes"), 0);
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 0);
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 0);
    }

    #[test]
    fn indexing_a_note_with_no_file_on_disk_reports_not_found() {
        let f = fixture();

        let result = index_note(&f.conn, &f.workspace_id, "missing");

        assert!(matches!(result, Err(AppError::NotFound(_))), "{result:?}");
    }

    /// A foreign file with unparseable frontmatter must index through the
    /// routine path too, not only through the rebuild (CAP-PORT-03).
    #[test]
    fn a_non_conformant_file_indexes_rather_than_failing() {
        let f = fixture();
        f.write("foreign.md", "---\n\ttype: [unclosed\n---\n\nBody.\n");

        assert_eq!(
            index_note(&f.conn, &f.workspace_id, "foreign").unwrap(),
            IndexOutcome::Updated
        );

        let conformant: bool = f
            .conn
            .query_row(
                "SELECT okf_conformant FROM notes WHERE workspace_id = ?1 AND id = 'foreign'",
                [&f.workspace_id],
                |row| row.get(0),
            )
            .unwrap();
        assert!(!conformant);
    }
}
