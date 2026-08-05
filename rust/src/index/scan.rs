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

/// One whole bundle, read off disk and derived into index rows, with **no
/// connection held**.
///
/// This is the first half of the two-phase rebuild — see [`scan_bundle`] for
/// why the rebuild has two halves at all. It is a plain value precisely so that
/// the expensive half can be handed across the connection boundary rather than
/// performed on the far side of it.
pub struct ScannedBundle {
    /// Bundle-relative directory paths, excluding the root.
    pub directories: Vec<String>,
    /// Every Note that still existed when it was read, already derived.
    pub notes: Vec<super::IndexedNote>,
}

/// **Phase one**: walks the bundle, reads every Note, and derives every row —
/// all of it O(bundle) file I/O and parsing, and **none of it under the
/// connection**.
///
/// The split exists because the previous shape put exactly this work inside a
/// `with_connection` closure: a full rebuild reads and parses every file in the
/// Workspace, and it ran holding the process-wide connection mutex — the one a
/// keystroke's own tier 1 draft write waits on. `SPK-WSPC-D001` §6.2.7 forbids
/// it in as many words ("no closure passed to `with_connection` may perform
/// file I/O"), and this is the largest violation of it the crate had: a
/// thousand-Note bundle held the mutex for the whole walk, on every Workspace
/// open and on every `reindex_workspace` call.
///
/// The shape mirrors `workspace::persist::NoteSession::index_written_source`,
/// which made the same split one Note at a time for the same reason.
///
/// A Note that vanishes between the walk and the read is skipped rather than
/// raised: it no longer exists, so there is nothing to index and no reason to
/// fail a whole rebuild over it.
pub fn scan_bundle(root: &Path) -> Result<ScannedBundle, AppError> {
    crate::db::connection::assert_no_io_under_the_connection("a full bundle scan");

    let scan = walk_bundle(root)?;
    let mut notes = Vec::with_capacity(scan.notes.len());
    for concept_id in &scan.notes {
        if let Some(note) = read_note(root, concept_id)? {
            notes.push(note);
        }
    }
    Ok(ScannedBundle {
        directories: scan.directories,
        notes,
    })
}

/// **Phase two**: replaces `workspace_id`'s `notes`, `notes_fts`,
/// `fts_mapping`, `links` and `directories` rows with what [`scan_bundle`]
/// derived, and returns the number of Notes indexed.
///
/// SQL only — no file is opened, stat-ed or parsed here, which is the whole
/// point of the split. The rebuild is one transaction, so a failure part-way
/// through leaves the previous index intact rather than a half-cleared one.
/// `ANALYZE` runs once it commits — see [`analyze`].
pub fn write_scanned_bundle(
    conn: &Connection,
    workspace_id: &str,
    scanned: &ScannedBundle,
) -> Result<u32, AppError> {
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
            for dir in &scanned.directories {
                stmt.execute(rusqlite::params![dir, workspace_id])?;
            }
        }

        let mut indexed: u32 = 0;
        for note in &scanned.notes {
            insert_note_rows(tx, workspace_id, note)?;
            indexed += 1;
        }
        Ok(indexed)
    })?;

    analyze(conn)?;
    Ok(indexed)
}

/// Both phases, resolving the bundle root through the index first.
///
/// **Not the production path.** Every caller that reaches the process-wide
/// connection — `workspace::bootstrap::converge` and
/// `api::ffi_api::reindex_workspace` — calls [`scan_bundle`] and
/// [`write_scanned_bundle`] separately, so that the walk happens with no
/// connection held. This convenience exists for hermetic tests, which own their
/// injected `Connection` outright and contend with nothing; calling it while a
/// connection *is* held trips [`scan_bundle`]'s own debug assert, which is what
/// keeps that distinction from eroding.
pub fn reindex_workspace_impl(conn: &Connection, workspace_id: &str) -> Result<u32, AppError> {
    let root = workspace_root(conn, workspace_id)?;
    let scanned = scan_bundle(&root)?;
    write_scanned_bundle(conn, workspace_id, &scanned)
}

/// One Note's file, read but not yet interpreted.
///
/// The split exists for the incremental path: everything needed to decide
/// whether a Note's rows are still current is here, and none of the parsing
/// is. Deriving first and comparing afterwards made the common case — an
/// unchanged file, on a path that runs after every write — pay a full parse,
/// span map and link walk to conclude that nothing had changed.
#[derive(Debug, Clone)]
pub struct RawNote {
    pub bytes: Vec<u8>,
    /// SHA-256 of `bytes`, hex-encoded. Both `notes.content_hash` and the OCC
    /// token (ADR-007 decision 7).
    pub content_hash: String,
    pub last_modified: i64,
}

impl RawNote {
    /// Decodes and derives every index row this Note contributes.
    ///
    /// Lossy rather than `read_to_string`: a bundle burlmd did not write may
    /// hold a file that is not valid UTF-8, and CAP-PORT-03 asks for that to
    /// be tolerated rather than to abort the scan. The hash is taken over the
    /// raw bytes, so it matches what a writer computes over the bytes it just
    /// wrote.
    #[must_use]
    pub fn derive(&self, concept_id: &str) -> super::IndexedNote {
        let source = String::from_utf8_lossy(&self.bytes).into_owned();
        derive_note(
            concept_id,
            &source,
            self.content_hash.clone(),
            self.last_modified,
        )
    }
}

/// Reads one Note's bytes and hashes them, or `None` when the file is gone.
pub fn read_note_bytes(root: &Path, concept_id: &str) -> Result<Option<RawNote>, AppError> {
    crate::db::connection::assert_no_io_under_the_connection("reading a Note for indexing");

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

    let content_hash = super::content_hash(&bytes);
    Ok(Some(RawNote {
        bytes,
        content_hash,
        last_modified,
    }))
}

/// Reads one Note off disk and derives its rows, or `None` when the file is
/// gone. The rebuild's per-file step: it always derives, because a rebuild
/// has already discarded the rows it would have compared against.
pub fn read_note(root: &Path, concept_id: &str) -> Result<Option<super::IndexedNote>, AppError> {
    Ok(read_note_bytes(root, concept_id)?.map(|raw| raw.derive(concept_id)))
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
    crate::db::connection::assert_no_io_under_the_connection("walking the bundle");

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
        // The kind comes from `workspace::classify_entry` rather than from a
        // local `is_symlink()`/`is_dir()` pair, so that this walk and the two
        // others over a bundle cannot drift apart on what a link is. What this
        // walk does with one is unchanged and is its own decision: a link is
        // skipped outright, neither indexed as a Note nor descended into, which
        // is also what keeps this walk acyclic.
        let kind = crate::workspace::classify_entry(&file_type);
        if kind == crate::workspace::BundleEntry::Symlink {
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

        if kind == crate::workspace::BundleEntry::Directory {
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

    /// A rebuild clears and rewrites one Workspace's rows. It must not reach
    /// another's — the index accumulates rows for every Workspace ever opened
    /// (ADR-005 decision 7), and the deletes here are the one place a missing
    /// `workspace_id` predicate would strand a *different* bundle's entire
    /// full text rather than merely losing a row.
    #[test]
    fn rebuilding_one_workspace_leaves_anothers_rows_and_text_intact() {
        let f = fixture();
        f.write("a.md", &conformant("A", "first workspace prose"));

        let other_root = f.dir.path().join("bundle-2");
        std::fs::create_dir_all(&other_root).unwrap();
        std::fs::write(
            other_root.join("a.md"),
            conformant("A", "antidisestablishmentarianism elsewhere"),
        )
        .unwrap();
        f.conn
            .execute(
                "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
                 VALUES ('ws-2', 'Second', 'local', NULL, ?1)",
                [other_root.to_string_lossy().to_string()],
            )
            .unwrap();
        reindex_workspace_impl(&f.conn, "ws-2").unwrap();
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        // Rebuild the first Workspace again, now that both are populated.
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        assert_eq!(
            f.raw_fts_matches("antidisestablishmentarianism"),
            1,
            "the other Workspace's text must survive a rebuild of this one"
        );
        assert_eq!(
            f.count("SELECT count(*) FROM notes WHERE workspace_id = 'ws-2'"),
            1
        );
        assert_eq!(
            f.count("SELECT count(*) FROM notes_fts"),
            f.count("SELECT count(*) FROM fts_mapping"),
            "every notes_fts row must still be reachable through the mapping"
        );
        assert_eq!(f.count("SELECT count(*) FROM notes_fts"), 2);
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
        assert!(
            plan.iter()
                .any(|step| step.contains("SEARCH n USING INDEX sqlite_autoindex_notes_1")),
            "notes must be reached through its own (workspace_id, id) primary key — the half \
             ANALYZE is responsible for, got: {plan:#?}"
        );
        assert!(
            !plan
                .iter()
                .any(|step| step.contains("USE TEMP B-TREE FOR ORDER BY")),
            "FTS5 already returns rows in rank order; a sort here means the plan lost that, \
             got: {plan:#?}"
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
