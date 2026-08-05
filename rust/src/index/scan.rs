//! Full rebuild of one Workspace's index rows from the bundle on disk.
//!
//! This is `reindex_workspace` in `contracts/ffi_api.rs`, and it is
//! deliberately **not** the routine path: `architecture/risks.md` risk 3
//! requires incremental updates during ordinary editing, and a full rescan
//! there is this ticket's first STOP condition. It exists for first open,
//! post-merge reconciliation, and recovery — each of which is a moment where
//! the index may disagree with the bundle in ways no single write explains.

use std::path::Path;

use rusqlite::Connection;

use crate::error::AppError;

use super::{
    analyze, derive_note, in_transaction, insert_note_rows, purge_workspace_text, workspace_root,
};

/// OKF §3.1 reserves these two filenames (§8 directory listing, §9 update
/// history). `data-models/okf-bundle.md` invariant 1 is the rule applied
/// here: every `.md` file in the bundle *other than* these is a Note. burlmd
/// generates neither (ADR-004 decision 6), but a foreign bundle may contain
/// them, and indexing one as a Note would mint a concept the lifecycle layer
/// then refuses to rename or recreate.
const RESERVED_FILENAMES: [&str; 2] = ["index.md", "log.md"];

/// What one walk of the bundle found.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct BundleScan {
    /// Concept ids, in walk order.
    pub notes: Vec<String>,
    /// Bundle-relative directory paths, excluding the root itself. Recorded
    /// even when a directory holds Notes: `schema.sql` stores them uniformly
    /// so the tree renders from one query, and empty ones would otherwise be
    /// invisible.
    pub directories: Vec<String>,
}

/// Rebuilds `notes`, `notes_fts`, `fts_mapping`, `links` and `directories`
/// for `workspace_id` from its bundle on disk, and returns the number of
/// Notes indexed.
///
/// The whole rebuild is one transaction, so a failure part-way through leaves
/// the previous index intact rather than a half-cleared one. `ANALYZE` runs
/// once it commits — see [`analyze`].
pub fn reindex_workspace_impl(conn: &Connection, workspace_id: &str) -> Result<u32, AppError> {
    let root = workspace_root(conn, workspace_id)?;
    let scan = walk_bundle(&root)?;

    let indexed = in_transaction(conn, |tx| {
        // Ordering obligation (`schema.sql` at `fts_mapping`): the Workspace's
        // full-text rows go first, through the mapping, because deleting
        // `notes` cascades the mapping away and the mapping is the only
        // pointer to the FTS rowid. A rebuild that clears `notes` first
        // strands the whole Workspace's text, permanently, on a path that runs
        // at every open.
        purge_workspace_text(tx, workspace_id)?;
        tx.execute("DELETE FROM notes WHERE workspace_id = ?1", [workspace_id])?;
        tx.execute(
            "DELETE FROM directories WHERE workspace_id = ?1",
            [workspace_id],
        )?;

        {
            let mut stmt = tx.prepare(
                "INSERT OR IGNORE INTO directories (id, workspace_id, path) VALUES (?1, ?2, ?1)",
            )?;
            for dir in &scan.directories {
                stmt.execute(rusqlite::params![dir, workspace_id])?;
            }
        }

        let mut indexed: u32 = 0;
        for concept_id in &scan.notes {
            let Some(note) = read_note(&root, concept_id)? else {
                // The file vanished between the walk and the read. Nothing to
                // index, and no reason to fail the whole rebuild over a Note
                // that no longer exists.
                continue;
            };
            insert_note_rows(tx, workspace_id, &note)?;
            indexed += 1;
        }
        Ok(indexed)
    })?;

    analyze(conn)?;
    Ok(indexed)
}

/// Reads one Note off disk and derives its rows, or `None` when the file is
/// gone.
///
/// Bytes rather than `read_to_string`: a bundle burlmd did not write may hold
/// a file that is not valid UTF-8, and CAP-PORT-03 asks for that to be
/// tolerated rather than to abort the scan. The hash is taken over the raw
/// bytes (so it matches what a writer computes), and the text handed to the
/// parser is a lossy decode of them.
pub fn read_note(root: &Path, concept_id: &str) -> Result<Option<super::IndexedNote>, AppError> {
    let path = root.join(crate::okf::concept_id_to_path(concept_id));
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(AppError::IoError(format!("read {}: {e}", path.display()))),
    };
    let last_modified = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs() as i64);

    let hash = super::content_hash(&bytes);
    let source = String::from_utf8_lossy(&bytes).into_owned();
    Ok(Some(derive_note(concept_id, &source, hash, last_modified)))
}

/// Walks the bundle, collecting concept ids and directory paths.
///
/// Skips, deliberately:
/// - anything whose name starts with `.` — `.git/` above all, which is the
///   application's own version history rather than bundle content, and which
///   holds thousands of files in a Workspace with any history at all;
/// - symbolic links, which is also what keeps this walk acyclic;
/// - `index.md` and `log.md` (see [`RESERVED_FILENAMES`]);
/// - every non-`.md` file. Attachments are not concepts and "are never
///   indexed as Notes" (`data-models/okf-bundle.md`, "Attachments").
pub fn walk_bundle(root: &Path) -> Result<BundleScan, AppError> {
    let mut scan = BundleScan::default();
    walk_dir(root, "", &mut scan)?;
    scan.notes.sort();
    scan.directories.sort();
    Ok(scan)
}

fn walk_dir(dir: &Path, prefix: &str, scan: &mut BundleScan) -> Result<(), AppError> {
    let entries = std::fs::read_dir(dir)
        .map_err(|e| AppError::IoError(format!("read directory {}: {e}", dir.display())))?;

    for entry in entries {
        let entry = entry.map_err(|e| AppError::IoError(e.to_string()))?;
        let file_type = entry
            .file_type()
            .map_err(|e| AppError::IoError(e.to_string()))?;
        if file_type.is_symlink() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let rel = if prefix.is_empty() {
            name.clone()
        } else {
            format!("{prefix}/{name}")
        };

        if file_type.is_dir() {
            scan.directories.push(rel.clone());
            walk_dir(&entry.path(), &rel, scan)?;
        } else if name.ends_with(".md") && !RESERVED_FILENAMES.contains(&name.as_str()) {
            scan.notes.push(crate::okf::path_to_concept_id(&rel));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::fixtures::*;
    use super::*;

    /// Gherkin: every Note in nested Directories has a row keyed by its
    /// concept id, with a content hash and a conformance flag.
    #[test]
    fn every_note_in_nested_directories_gets_a_row_keyed_by_concept_id() {
        let f = fixture();
        f.write("Welcome.md", &conformant("Welcome", "Hello."));
        f.write("projects/burlmd.md", &conformant("Burlmd", "A project."));
        f.write("projects/deep/nested.md", "no frontmatter here\n");

        let count = reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        assert_eq!(count, 3);
        assert_eq!(
            f.note_ids(),
            vec!["Welcome", "projects/burlmd", "projects/deep/nested"]
        );

        let mut stmt = f
            .conn
            .prepare(
                "SELECT id, path, title, content_hash, okf_conformant FROM notes \
                 WHERE workspace_id = ?1 ORDER BY id",
            )
            .unwrap();
        let rows: Vec<(String, String, String, String, bool)> = stmt
            .query_map([&f.workspace_id], |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert_eq!(rows[0].1, "Welcome.md");
        assert_eq!(rows[0].2, "Welcome");
        assert_eq!(rows[0].3.len(), 64, "a hex SHA-256 digest");
        assert!(rows[0].4);
        assert_eq!(rows[1].0, "projects/burlmd");
        assert_eq!(rows[2].0, "projects/deep/nested");
        assert!(
            !rows[2].4,
            "a file with no frontmatter indexes as non-conformant rather than failing"
        );
        assert_ne!(rows[0].3, rows[1].3, "distinct content, distinct hash");
    }

    /// Gherkin: a link to a Note that exists is recorded and resolves.
    #[test]
    fn a_link_to_an_existing_note_is_recorded_and_resolves() {
        let f = fixture();
        f.write(
            "a.md",
            &conformant("A", "See [Beta](</projects/beta.md>) for more."),
        );
        f.write("projects/beta.md", &conformant("Beta", "The target."));

        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let (target_id, target_title): (String, String) = f
            .conn
            .query_row(
                "SELECT target_id, target_title FROM links WHERE workspace_id = ?1 \
                 AND source_id = 'a'",
                [&f.workspace_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(target_id, "projects/beta");
        assert_eq!(target_title, "Beta");
        assert!(super::super::note_exists(&f.conn, &f.workspace_id, &target_id).unwrap());
    }

    /// Gherkin: a link to a Note that does not exist is still recorded, and
    /// is reported as unresolved rather than dropped (OKF §6.1,
    /// CAP-GRAPH-04).
    #[test]
    fn a_ghost_link_is_recorded_and_reported_unresolved() {
        let f = fixture();
        f.write(
            "a.md",
            &conformant("A", "Forward reference to [New Idea](</New Idea.md>)."),
        );

        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let target_id: String = f
            .conn
            .query_row(
                "SELECT target_id FROM links WHERE workspace_id = ?1 AND source_id = 'a'",
                [&f.workspace_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(target_id, "New Idea");
        assert!(
            !super::super::note_exists(&f.conn, &f.workspace_id, &target_id).unwrap(),
            "the edge exists and is unresolved — a ghost Link, not a dropped one"
        );
    }

    /// Gherkin: an empty Directory in the bundle gets a Directory row.
    #[test]
    fn an_empty_directory_gets_a_row() {
        let f = fixture();
        f.mkdir("empty");
        f.mkdir("holds/notes");
        f.write("holds/notes/a.md", &conformant("A", "Body."));

        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let mut stmt = f
            .conn
            .prepare("SELECT id, path FROM directories WHERE workspace_id = ?1 ORDER BY id")
            .unwrap();
        let rows: Vec<(String, String)> = stmt
            .query_map([&f.workspace_id], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            rows,
            vec![
                ("empty".to_string(), "empty".to_string()),
                ("holds".to_string(), "holds".to_string()),
                ("holds/notes".to_string(), "holds/notes".to_string()),
            ]
        );
    }

    /// Gherkin (the FTS-orphan criterion): after a full reindex, a search for
    /// text belonging to no current Note matches nothing. A rebuild that
    /// clears `notes` first strands every FTS row beyond reach, and reindex
    /// runs often enough that the leak is unbounded.
    #[test]
    fn a_rebuild_strands_no_full_text_rows_for_notes_that_are_gone() {
        let f = fixture();
        f.write(
            "doomed.md",
            &conformant("Doomed", "antidisestablishmentarianism is distinctive"),
        );
        f.write("kept.md", &conformant("Kept", "ordinary prose"));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();
        assert_eq!(f.raw_fts_matches("antidisestablishmentarianism"), 1);

        std::fs::remove_file(f.root().join("doomed.md")).unwrap();
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        assert_eq!(
            f.raw_fts_matches("antidisestablishmentarianism"),
            0,
            "text of a Note that no longer exists is still in notes_fts"
        );
        assert_eq!(
            f.count("SELECT count(*) FROM notes_fts"),
            f.count("SELECT count(*) FROM fts_mapping"),
            "every notes_fts row must still be reachable through the mapping"
        );
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 1);
    }

    /// Repeated rebuilds must not accumulate rows either — the same ordering
    /// bug shows up as unbounded growth when nothing was deleted at all.
    #[test]
    fn repeated_rebuilds_do_not_accumulate_rows() {
        let f = fixture();
        f.write("a.md", &conformant("A", "alpha [B](</b.md>)"));
        f.write("b.md", &conformant("B", "beta"));

        for _ in 0..3 {
            assert_eq!(reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap(), 2);
        }

        assert_eq!(f.count("SELECT count(*) FROM notes"), 2);
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 2);
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 2);
        assert_eq!(f.count("SELECT count(*) FROM links"), 1);
        assert_eq!(f.raw_fts_matches("alpha"), 1);
    }

    /// Gherkin: after a full reindex, `ANALYZE` has been run — without it the
    /// planner reaches `notes` by building a second automatic index per query.
    #[test]
    fn a_full_reindex_runs_analyze() {
        let f = fixture();
        f.write("a.md", &conformant("A", "Body."));

        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        assert_eq!(
            f.count("SELECT count(*) FROM sqlite_master WHERE name = 'sqlite_stat1'"),
            1,
            "ANALYZE creates sqlite_stat1"
        );
        assert!(
            f.count("SELECT count(*) FROM sqlite_stat1") > 0,
            "statistics must actually be populated"
        );
    }

    /// Gherkin: the search plan drives from `notes_fts` and reaches
    /// `fts_mapping` through `idx_fts_mapping_rowid`, with no AUTOMATIC
    /// COVERING INDEX step. Asserted on the plan rather than a timing,
    /// because at a thousand Notes the wrong plan is still inside the 100ms
    /// budget and the timing criterion passes with the defect in place.
    ///
    /// 200 Notes deliberately, not the thousand the timing criterion uses:
    /// measured against this schema, an unpinned join order plans correctly at
    /// 1000 Notes and re-runs the `MATCH` once per Note at 200 and at 10. A
    /// plan assertion taken only at the corpus size the timing test uses would
    /// pass for both queries.
    #[test]
    fn the_search_plan_drives_from_notes_fts_through_the_mapping_index() {
        let f = fixture();
        for i in 0..200 {
            f.write(
                &format!("n{i}.md"),
                &conformant(&format!("N{i}"), "shared body text"),
            );
        }
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let plan = query_plan(&f.conn, &f.workspace_id);

        assert!(
            plan.first().is_some_and(|step| step.contains("notes_fts")),
            "the plan must drive from notes_fts, got: {plan:#?}"
        );
        assert!(
            plan.iter()
                .any(|step| step.contains("idx_fts_mapping_rowid")),
            "fts_mapping must be reached through idx_fts_mapping_rowid, got: {plan:#?}"
        );
        assert!(
            !plan
                .iter()
                .any(|step| step.contains("AUTOMATIC COVERING INDEX")),
            "an automatic covering index is O(N) transient work per query, got: {plan:#?}"
        );
    }

    /// Gherkin: an indexed Workspace of at least one thousand Notes answers a
    /// full-text query in under 100ms (`prd/constraints.md`).
    ///
    /// The PRD's budget is asserted literally, in both profiles, because the
    /// margin turned out to be nearly three orders of magnitude: measured
    /// against a real on-disk SQLCipher file, 285µs in a debug build and 160µs
    /// in a release one. A profile-dependent budget would only have been needed if
    /// the two were close, and the debug figure is the slower of the two only
    /// because `cc` compiles the SQLCipher amalgamation at the profile's own
    /// optimization level — none of this work is Rust.
    ///
    /// Treat this as a smoke test for an accidental O(N) plan rather than as
    /// the real guard. The real guard is the plan assertion above: this
    /// criterion passed at 284µs while the query was still re-running the
    /// `MATCH` once per Note, which is what that test caught and this one
    /// could not.
    #[test]
    fn a_full_text_query_over_a_thousand_notes_stays_within_budget() {
        let f = fixture();
        for i in 0..1000 {
            f.write(
                &format!("dir{}/note{i}.md", i % 20),
                &conformant(
                    &format!("Note {i}"),
                    &format!("Body number {i} with shared vocabulary and some filler prose."),
                ),
            );
        }
        f.write(
            "needle.md",
            &conformant("Needle", "quintessential unrepeated token"),
        );
        assert_eq!(
            reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap(),
            1001
        );

        let elapsed = time_search(&f.conn, &f.workspace_id, "quintessential");

        let budget = std::time::Duration::from_millis(100);
        assert!(
            elapsed < budget,
            "full-text query took {elapsed:?}, budget {budget:?}"
        );
    }

    #[test]
    fn the_walk_skips_dot_directories_reserved_filenames_and_attachments() {
        let f = fixture();
        f.write("a.md", &conformant("A", "Body."));
        f.write("index.md", &conformant("Index", "A reserved listing."));
        f.write("dir/log.md", &conformant("Log", "A reserved history."));
        f.write("image.png", "not markdown");
        f.write(".git/objects/deadbeef.md", "internal git state");
        f.mkdir(".hidden");

        let scan = walk_bundle(&f.root()).unwrap();

        assert_eq!(scan.notes, vec!["a".to_string()]);
        assert_eq!(scan.directories, vec!["dir".to_string()]);
    }

    fn query_plan(conn: &Connection, workspace_id: &str) -> Vec<String> {
        let sql = format!(
            "EXPLAIN QUERY PLAN {}",
            crate::api::ffi_api::SEARCH_NOTES_SQL
        );
        let mut stmt = conn.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params!["\"needle\"", workspace_id], |row| {
            row.get::<_, String>(3)
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    fn time_search(conn: &Connection, workspace_id: &str, token: &str) -> std::time::Duration {
        let mut stmt = conn.prepare(crate::api::ffi_api::SEARCH_NOTES_SQL).unwrap();
        let start = std::time::Instant::now();
        let hits: Vec<String> = stmt
            .query_map(
                rusqlite::params![format!("\"{token}\""), workspace_id],
                |row| row.get::<_, String>(0),
            )
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        let elapsed = start.elapsed();
        assert_eq!(hits, vec!["needle".to_string()]);
        elapsed
    }
}
