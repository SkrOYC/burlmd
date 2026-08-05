//! Projects the OKF bundle on disk into the encrypted index (WSPC-D005).
//!
//! The index is derived state: `data-models/schema.sql` opens by saying it can
//! be discarded and rebuilt from the bundle at any time, and this module is
//! what rebuilds it. Two paths, one row shape:
//!
//! - [`scan`] walks the whole bundle and rebuilds every table for one
//!   Workspace. It runs on first open, after a merge, and on recovery.
//! - [`incremental`] rewrites the rows of a single Note. Per
//!   `architecture/risks.md` risk 3 this is the **routine** path — a full
//!   rescan during ordinary editing is the failure this ticket's STOP
//!   condition names.
//!
//! Both go through the same derivation ([`derive_note`]) and the same writers
//! ([`insert_note_rows`], [`remove_note_rows`]), so a Note's rows do not
//! depend on which path produced them.
//!
//! # Deletion ordering
//!
//! Every removal here goes through [`purge_note_text`] or
//! [`purge_workspace_text`] **before** it touches `notes`. This is the
//! ordering obligation `data-models/schema.sql` states at `fts_mapping`:
//! deleting a `notes` row cascades the mapping away in the same statement,
//! and the mapping is the only pointer to the FTS rowid, so the FTS row is
//! then unreachable *and* undeletable — the full text of the deleted Note
//! stays in the one file this product encrypts precisely because it
//! aggregates every Note's content. There is no accessor here that deletes
//! `notes` without purging the text first; that is why the two are one
//! function rather than two calls a caller could sequence wrongly.
//!
//! # Reading a Note
//!
//! Frontmatter is read through [`crate::okf::frontmatter`] against the span
//! `SpanMap::frontmatter()` records, never off the AST: a frontmatter block
//! produces no `AstNode` at all (`markdown::parser`'s "Regions that are
//! preserved but not addressable"). Going through the span also means the
//! file is parsed once rather than twice — `read_frontmatter` runs its own
//! CommonMark pass to find the block, and at a thousand Notes a second full
//! pass per file is the difference the one-pass design in ADR-007 exists to
//! avoid.

pub mod incremental;
pub mod scan;

use std::collections::HashSet;
use std::path::PathBuf;

use rusqlite::{Connection, OptionalExtension};
use sha2::{Digest, Sha256};

use crate::error::AppError;
use crate::markdown::{parse_note, rendered_text, AstNode, InlineElement};
use crate::okf::frontmatter::Frontmatter;
use crate::okf::read_frontmatter;

/// One Link edge as derived from a Note's parsed inline content: an entry in
/// `links` before it is scoped to a Workspace and a source Note.
///
/// `target_id` is always present, including when it matches no Note —
/// `schema.sql` is explicit that a ghost Link is a row whose `target_id`
/// matches no `notes.id`, not a row that was never written (OKF §6.1,
/// CAP-GRAPH-04).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkEdge {
    pub target_id: String,
    pub target_title: String,
}

/// Everything one Note on disk contributes to the index, derived once and
/// written by [`insert_note_rows`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IndexedNote {
    /// OKF concept id: the bundle-relative path with `.md` removed (§2).
    pub concept_id: String,
    /// The same path with `.md` retained (`notes.path`).
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    pub content_hash: String,
    pub okf_conformant: bool,
    /// What `notes_fts.content` indexes: the Note's *rendered* text, Block by
    /// Block. Not the raw source — searching prose the user never wrote
    /// (fence markers, link destinations, the frontmatter block) produces hits
    /// on text that is not on screen anywhere.
    pub text: String,
    pub links: Vec<LinkEdge>,
}

/// SHA-256, hex-encoded, of a Note's on-disk bytes.
///
/// This is `notes.content_hash`, which ADR-007 decision 7 also makes the OCC
/// token `WSPC-D007` compares before every write. Taken over the raw bytes
/// rather than over a decoded `String` so that the value is well defined for a
/// foreign file that is not valid UTF-8, and so that the hash a writer
/// computes over the bytes it just wrote equals the one a reader computes off
/// disk.
pub fn content_hash(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write as _;
        let _ = write!(out, "{byte:02x}");
    }
    out
}

/// Derives every index row for one Note from its source text.
///
/// `containing_dir` is taken from `concept_id` itself and passed into
/// [`parse_note`], which needs it to resolve the relative link destinations
/// OKF §6.1 permits in a bundle burlmd did not write. Passing the bundle root
/// for every Note instead would silently reclassify a foreign bundle's
/// relative links as links to the wrong concept.
///
/// Never fails on content: a file with no frontmatter, unparseable
/// frontmatter, or frontmatter carrying no non-empty `type` is derived with
/// `okf_conformant = false` rather than rejected (CAP-WS-05, CAP-PORT-03, and
/// this ticket's second STOP condition).
pub fn derive_note(
    concept_id: &str,
    source: &str,
    content_hash: String,
    last_modified: i64,
) -> IndexedNote {
    let containing_dir = concept_id.rsplit_once('/').map_or("", |(dir, _)| dir);
    let parsed = parse_note(source, containing_dir);

    let frontmatter = parsed
        .spans
        .frontmatter()
        .and_then(|span| source.get(span))
        .map_or_else(Frontmatter::default, read_frontmatter);

    let title = frontmatter
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map_or_else(|| file_stem(concept_id).to_string(), str::to_string);

    let text = parsed
        .ast
        .iter()
        .map(rendered_text)
        .collect::<Vec<_>>()
        .join("\n");

    let mut links = Vec::new();
    collect_links(&parsed.ast, &mut links);

    IndexedNote {
        concept_id: concept_id.to_string(),
        path: crate::okf::concept_id_to_path(concept_id),
        title,
        last_modified,
        content_hash,
        okf_conformant: frontmatter.is_conformant(),
        text,
        links,
    }
}

fn file_stem(concept_id: &str) -> &str {
    concept_id
        .rsplit_once('/')
        .map_or(concept_id, |(_, name)| name)
}

fn collect_links(nodes: &[AstNode], out: &mut Vec<LinkEdge>) {
    for node in nodes {
        match node {
            AstNode::Heading { content, .. } | AstNode::Paragraph { content } => {
                collect_inline_links(content, out);
            }
            AstNode::List { items, .. } => collect_links(items, out),
            AstNode::ListItem { content, .. } | AstNode::Blockquote { nodes: content } => {
                collect_links(content, out);
            }
            AstNode::Suggestion {
                base_content,
                local_content,
                incoming_content,
            } => {
                if let Some(base) = base_content {
                    collect_links(base, out);
                }
                collect_links(local_content, out);
                collect_links(incoming_content, out);
            }
            AstNode::CodeBlock { .. } | AstNode::ThematicBreak | AstNode::Image { .. } => {}
        }
    }
}

fn collect_inline_links(content: &[InlineElement], out: &mut Vec<LinkEdge>) {
    for element in content {
        match element {
            InlineElement::Link {
                target_id, content, ..
            } => {
                out.push(LinkEdge {
                    target_id: target_id.clone(),
                    target_title: inline_text(content),
                });
                collect_inline_links(content, out);
            }
            InlineElement::ExternalLink { content, .. } => collect_inline_links(content, out),
            InlineElement::Text(_) => {}
        }
    }
}

/// The rendered text of a run of inline content, via the same `rendered_text`
/// the `BlockRange` contract is defined in terms of rather than a second
/// traversal that could disagree with it.
fn inline_text(content: &[InlineElement]) -> String {
    rendered_text(&AstNode::Paragraph {
        content: content.to_vec(),
    })
}

/// The bundle root recorded for `workspace_id` in `workspaces.local_path`.
///
/// Read from the row rather than taken as a parameter so that no caller can
/// index one Workspace's files under another's id — the index accumulates rows
/// for every Workspace ever opened (ADR-005 decision 7).
pub fn workspace_root(conn: &Connection, workspace_id: &str) -> Result<PathBuf, AppError> {
    conn.query_row(
        "SELECT local_path FROM workspaces WHERE id = ?1",
        [workspace_id],
        |row| row.get::<_, String>(0),
    )
    .optional()?
    .map(PathBuf::from)
    .ok_or_else(|| AppError::NotFound(format!("no Workspace row with id {workspace_id}")))
}

/// Writes every row one Note owns: `notes`, its `notes_fts` row, the
/// `fts_mapping` entry pointing at that row's rowid, and one `links` row per
/// outbound edge.
///
/// Links are `INSERT OR IGNORE`: two Links from the same Note to the same
/// target with different wording are one graph edge, and the first row's
/// `target_title` wins — the trade-off `schema.sql` states at the `links`
/// primary key ("this table indexes the graph, it does not reproduce the
/// prose").
pub fn insert_note_rows(
    conn: &Connection,
    workspace_id: &str,
    note: &IndexedNote,
) -> Result<(), AppError> {
    conn.execute(
        "INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash, \
                            okf_conformant) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            note.concept_id,
            workspace_id,
            note.path,
            note.title,
            note.last_modified,
            note.content_hash,
            note.okf_conformant,
        ],
    )?;

    conn.execute(
        "INSERT INTO notes_fts (title, content) VALUES (?1, ?2)",
        rusqlite::params![note.title, note.text],
    )?;
    let fts_rowid = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO fts_mapping (workspace_id, note_id, fts_rowid) VALUES (?1, ?2, ?3)",
        rusqlite::params![workspace_id, note.concept_id, fts_rowid],
    )?;

    let mut stmt = conn.prepare(
        "INSERT OR IGNORE INTO links (workspace_id, source_id, target_id, target_title) \
         VALUES (?1, ?2, ?3, ?4)",
    )?;
    for link in &note.links {
        stmt.execute(rusqlite::params![
            workspace_id,
            note.concept_id,
            link.target_id,
            link.target_title,
        ])?;
    }
    Ok(())
}

/// Deletes one Note's `notes_fts` row through `fts_mapping`, and nothing else.
///
/// Always called before the `notes` row it belongs to is deleted — see this
/// module's "Deletion ordering" section.
fn purge_note_text(conn: &Connection, workspace_id: &str, note_id: &str) -> Result<(), AppError> {
    conn.execute(
        "DELETE FROM notes_fts WHERE rowid IN \
         (SELECT fts_rowid FROM fts_mapping WHERE workspace_id = ?1 AND note_id = ?2)",
        rusqlite::params![workspace_id, note_id],
    )?;
    Ok(())
}

/// The whole Workspace's `notes_fts` rows, through `fts_mapping`. The rebuild
/// twin of [`purge_note_text`], and the more dangerous of the two: a rebuild
/// that clears `notes` first strands every Note's text at once.
fn purge_workspace_text(conn: &Connection, workspace_id: &str) -> Result<(), AppError> {
    conn.execute(
        "DELETE FROM notes_fts WHERE rowid IN \
         (SELECT fts_rowid FROM fts_mapping WHERE workspace_id = ?1)",
        [workspace_id],
    )?;
    Ok(())
}

/// Removes one Note's rows in the only correct order: full-text row first
/// (through the mapping), then the `notes` row, whose cascade takes the
/// mapping and the Note's outbound `links` with it.
///
/// Inbound Links are deliberately left behind: `links.target_id` carries no
/// foreign key, so an edge pointing at this Note survives as a ghost Link,
/// which is what OKF §6.1 requires and what CAP-GRAPH-04 makes a feature.
pub fn remove_note_rows(
    conn: &Connection,
    workspace_id: &str,
    note_id: &str,
) -> Result<(), AppError> {
    purge_note_text(conn, workspace_id, note_id)?;
    conn.execute(
        "DELETE FROM notes WHERE workspace_id = ?1 AND id = ?2",
        rusqlite::params![workspace_id, note_id],
    )?;
    Ok(())
}

/// Runs `f` inside a transaction, joining the caller's if one is already
/// open.
///
/// Both index paths write several tables that must move together, so both
/// want a transaction. Neither may *insist* on owning one: `WSPC-D006`'s
/// rename has to rewrite the file, this Note's rows and every inbound Link in
/// one atomic operation (`architecture/risks.md` risk 8), which means calling
/// in from inside its own transaction — and `unchecked_transaction` errors
/// rather than nesting. Joining is both what that ticket needs and the
/// stronger guarantee: the index rows commit with the rename or not at all.
fn in_transaction<T>(
    conn: &Connection,
    f: impl FnOnce(&Connection) -> Result<T, AppError>,
) -> Result<T, AppError> {
    if !conn.is_autocommit() {
        return f(conn);
    }
    let tx = conn.unchecked_transaction()?;
    let out = f(&tx)?;
    tx.commit()?;
    Ok(out)
}

/// Refreshes the planner's table statistics.
///
/// Required after every path that rebuilds or updates the index
/// (`schema.sql` at `idx_fts_mapping_rowid`): without it the planner reaches
/// `notes` by building an automatic covering index per query — measured there
/// at 15.7ms versus 4.5ms over 20,000 Notes — which `idx_fts_mapping_rowid`
/// alone does not fix.
pub fn analyze(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch("ANALYZE;")?;
    Ok(())
}

/// True when `note_id` names a Note indexed in `workspace_id`.
pub fn note_exists(conn: &Connection, workspace_id: &str, note_id: &str) -> Result<bool, AppError> {
    let found: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM notes WHERE workspace_id = ?1 AND id = ?2",
            rusqlite::params![workspace_id, note_id],
            |row| row.get(0),
        )
        .optional()?;
    Ok(found.is_some())
}

/// Populates `InlineElement::Link.exists` throughout `nodes` from the index.
///
/// `WSPC-D003` declares the field and leaves it `false`: the parser sits
/// upstream of the index and has nothing to resolve against. This is the only
/// place that answers it, and the answer is exactly "does `target_id` match a
/// `notes` row in this Workspace".
///
/// The flag is advisory and only as fresh as the AST holding it — creating or
/// deleting a Note flips it for every inbound Link in every other Note — so
/// the follow path re-resolves against the index rather than trusting it
/// (`contracts/ffi_api.rs`). What it is for is rendering.
pub fn resolve_link_existence(
    conn: &Connection,
    workspace_id: &str,
    nodes: &mut [AstNode],
) -> Result<(), AppError> {
    let mut targets = HashSet::new();
    collect_link_targets(nodes, &mut targets);
    if targets.is_empty() {
        return Ok(());
    }

    let mut existing = HashSet::new();
    for target in targets {
        if note_exists(conn, workspace_id, &target)? {
            existing.insert(target);
        }
    }
    apply_link_existence(nodes, &existing);
    Ok(())
}

fn collect_link_targets(nodes: &[AstNode], out: &mut HashSet<String>) {
    let mut edges = Vec::new();
    collect_links(nodes, &mut edges);
    out.extend(edges.into_iter().map(|edge| edge.target_id));
}

fn apply_link_existence(nodes: &mut [AstNode], existing: &HashSet<String>) {
    for node in nodes {
        match node {
            AstNode::Heading { content, .. } | AstNode::Paragraph { content } => {
                apply_inline_existence(content, existing);
            }
            AstNode::List { items, .. } => apply_link_existence(items, existing),
            AstNode::ListItem { content, .. } | AstNode::Blockquote { nodes: content } => {
                apply_link_existence(content, existing);
            }
            AstNode::Suggestion {
                base_content,
                local_content,
                incoming_content,
            } => {
                if let Some(base) = base_content {
                    apply_link_existence(base, existing);
                }
                apply_link_existence(local_content, existing);
                apply_link_existence(incoming_content, existing);
            }
            AstNode::CodeBlock { .. } | AstNode::ThematicBreak | AstNode::Image { .. } => {}
        }
    }
}

fn apply_inline_existence(content: &mut [InlineElement], existing: &HashSet<String>) {
    for element in content {
        match element {
            InlineElement::Link {
                target_id,
                exists,
                content,
            } => {
                *exists = existing.contains(target_id);
                apply_inline_existence(content, existing);
            }
            InlineElement::ExternalLink { content, .. } => {
                apply_inline_existence(content, existing);
            }
            InlineElement::Text(_) => {}
        }
    }
}

/// Fixtures shared by this module's own tests and by [`scan`]'s and
/// [`incremental`]'s. Every one of them runs against a real, on-disk
/// SQLCipher file with a throwaway key and a real bundle directory — never
/// the process-wide `db::connection` singleton and never the OS Keychain, so
/// they stay hermetic and order-independent (the pattern
/// `workspace::bootstrap`'s tests established).
#[cfg(test)]
pub(crate) mod fixtures {
    use std::path::{Path, PathBuf};

    use rusqlite::Connection;
    use tempfile::TempDir;

    /// A bundle directory, an encrypted index that is its *sibling* (never
    /// inside it — `guidelines.md`), and a `workspaces` row wiring the two
    /// together.
    pub(crate) struct Fixture {
        pub dir: TempDir,
        pub conn: Connection,
        pub workspace_id: String,
    }

    impl Fixture {
        pub(crate) fn root(&self) -> PathBuf {
            self.dir.path().join("bundle")
        }

        /// Writes `contents` to `rel` inside the bundle, creating parent
        /// directories as needed.
        pub(crate) fn write(&self, rel: &str, contents: &str) {
            let path = self.root().join(rel);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, contents).unwrap();
        }

        pub(crate) fn mkdir(&self, rel: &str) {
            std::fs::create_dir_all(self.root().join(rel)).unwrap();
        }

        pub(crate) fn note_ids(&self) -> Vec<String> {
            let mut stmt = self
                .conn
                .prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
                .unwrap();
            let ids = stmt
                .query_map([&self.workspace_id], |row| row.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            ids
        }

        /// Rows matching a bare FTS5 `MATCH` **without** going through
        /// `fts_mapping`. Deliberately unjoined: a search that joins the
        /// mapping cannot see an orphaned `notes_fts` row, which is precisely
        /// the row a wrong deletion order leaves behind.
        pub(crate) fn raw_fts_matches(&self, query: &str) -> i64 {
            self.conn
                .query_row(
                    "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?1",
                    [query],
                    |row| row.get(0),
                )
                .unwrap()
        }

        pub(crate) fn count(&self, sql: &str) -> i64 {
            self.conn.query_row(sql, [], |row| row.get(0)).unwrap()
        }
    }

    pub(crate) fn fixture() -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("bundle")).unwrap();
        let conn = test_index(dir.path());
        let workspace_id = "ws-1".to_string();
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES (?1, 'Test Workspace', 'local', NULL, ?2)",
            rusqlite::params![
                workspace_id,
                dir.path().join("bundle").to_string_lossy().to_string()
            ],
        )
        .unwrap();
        Fixture {
            dir,
            conn,
            workspace_id,
        }
    }

    fn test_index(dir: &Path) -> Connection {
        let key = [0x5au8; 32]; // throwaway key, not the real Keychain entry
        let conn =
            crate::db::connection::open_encrypted_db_with_key(&dir.join("index.sqlite3"), &key)
                .unwrap();
        crate::db::connection::init_schema(&conn).unwrap();
        conn
    }

    /// A minimal conformant Note: OKF §11 needs a parseable block with a
    /// non-empty `type`.
    pub(crate) fn conformant(title: &str, body: &str) -> String {
        format!("---\ntype: Note\ntitle: {title}\n---\n\n{body}\n")
    }
}

#[cfg(test)]
mod tests {
    use super::fixtures::*;
    use super::*;

    fn derive(concept_id: &str, source: &str) -> IndexedNote {
        derive_note(concept_id, source, content_hash(source.as_bytes()), 42)
    }

    /// The frontmatter block produces no `AstNode`, so it is read through
    /// `okf::frontmatter` against the span the span map records for it.
    #[test]
    fn frontmatter_is_read_through_the_span_map_and_supplies_the_title() {
        let note = derive(
            "projects/burlmd",
            &conformant("Burlmd", "Some prose about it."),
        );

        assert_eq!(note.title, "Burlmd");
        assert!(note.okf_conformant);
        assert_eq!(note.path, "projects/burlmd.md");
        assert_eq!(note.text, "Some prose about it.");
    }

    /// STOP: a file whose frontmatter does not parse must index as
    /// non-conformant, not fail (CAP-WS-05, CAP-PORT-03).
    #[test]
    fn a_file_with_unparseable_frontmatter_indexes_as_non_conformant() {
        let note = derive("foreign", "---\n\ttype: [unclosed\n---\n\nBody text.\n");

        assert!(!note.okf_conformant);
        assert_eq!(note.title, "foreign", "falls back to the filename stem");
        assert_eq!(note.text, "Body text.");
    }

    /// The non-trivial case `schema.sql` singles out: a block containing only
    /// `title:` parses perfectly and is still non-conformant, because OKF §11
    /// conditions on `type`.
    #[test]
    fn frontmatter_that_parses_without_a_type_is_non_conformant() {
        let note = derive("typeless", "---\ntitle: Typeless\n---\n\nBody.\n");

        assert!(!note.okf_conformant);
        assert_eq!(note.title, "Typeless");
    }

    #[test]
    fn a_file_with_no_frontmatter_at_all_is_non_conformant() {
        let note = derive("bare", "# Just a heading\n");

        assert!(!note.okf_conformant);
        assert_eq!(note.title, "bare");
    }

    #[test]
    fn links_are_derived_with_their_target_id_and_display_text() {
        let note = derive(
            "a",
            &conformant("A", "See [Beta](</dir/beta.md>) and [Ghost](</nope.md>)."),
        );

        assert_eq!(
            note.links,
            vec![
                LinkEdge {
                    target_id: "dir/beta".to_string(),
                    target_title: "Beta".to_string(),
                },
                LinkEdge {
                    target_id: "nope".to_string(),
                    target_title: "Ghost".to_string(),
                },
            ]
        );
    }

    /// `parse_note` resolves relative destinations against the Note's own
    /// directory (OKF §6.1), so the indexer has to pass each Note's real
    /// containing directory rather than the bundle root.
    #[test]
    fn a_relative_link_resolves_against_the_notes_own_directory() {
        let note = derive(
            "dir/sub/a",
            &conformant("A", "See [B](b.md) and [C](../c.md)."),
        );

        let targets: Vec<_> = note.links.iter().map(|l| l.target_id.as_str()).collect();
        assert_eq!(targets, vec!["dir/sub/b", "dir/c"]);
    }

    /// Gherkin: `InlineElement::Link.exists` reflects whether the target
    /// concept id matches an indexed Note.
    #[test]
    fn link_existence_is_resolved_against_the_index() {
        let f = fixture();
        let real = derive("real", &conformant("Real", "Body."));
        insert_note_rows(&f.conn, &f.workspace_id, &real).unwrap();

        let mut ast = crate::markdown::parse_markdown(
            "Link to [Real](</real.md>) and to [Ghost](</ghost.md>).\n",
        );
        // The parser leaves the field false for both — that is WSPC-D003's
        // documented state, and the assertion below is only meaningful
        // because of it.
        assert_eq!(link_flags(&ast), vec![false, false]);

        resolve_link_existence(&f.conn, &f.workspace_id, &mut ast).unwrap();

        assert_eq!(link_flags(&ast), vec![true, false]);
    }

    /// A Link nested inside a list item is still a Link; resolution walks the
    /// whole tree rather than only top-level paragraphs.
    #[test]
    fn link_existence_is_resolved_inside_nested_blocks() {
        let f = fixture();
        let real = derive("real", &conformant("Real", "Body."));
        insert_note_rows(&f.conn, &f.workspace_id, &real).unwrap();

        let mut ast = crate::markdown::parse_markdown("- item [Real](</real.md>)\n");
        resolve_link_existence(&f.conn, &f.workspace_id, &mut ast).unwrap();

        assert_eq!(link_flags(&ast), vec![true]);
    }

    /// A concept id is unique within a bundle, not globally: an identically
    /// named Note in another Workspace must not make a ghost Link resolve.
    #[test]
    fn link_existence_does_not_resolve_against_another_workspace() {
        let f = fixture();
        f.conn
            .execute(
                "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
                 VALUES ('other', 'Other', 'local', NULL, '/tmp/other')",
                [],
            )
            .unwrap();
        let real = derive("real", &conformant("Real", "Body."));
        insert_note_rows(&f.conn, "other", &real).unwrap();

        let mut ast = crate::markdown::parse_markdown("[Real](</real.md>)\n");
        resolve_link_existence(&f.conn, &f.workspace_id, &mut ast).unwrap();

        assert_eq!(link_flags(&ast), vec![false]);
    }

    /// The ordering STOP, at its smallest: removing a Note's rows must leave
    /// no `notes_fts` row behind, and the raw (unjoined) `MATCH` is the only
    /// query that can tell.
    #[test]
    fn removing_a_notes_rows_takes_its_full_text_row_with_them() {
        let f = fixture();
        let note = derive(
            "gone",
            &conformant("Gone", "quintessential distinctive text"),
        );
        insert_note_rows(&f.conn, &f.workspace_id, &note).unwrap();
        assert_eq!(f.raw_fts_matches("quintessential"), 1);

        remove_note_rows(&f.conn, &f.workspace_id, "gone").unwrap();

        assert_eq!(
            f.raw_fts_matches("quintessential"),
            0,
            "an orphaned notes_fts row is unreachable AND undeletable once its mapping cascades"
        );
        assert_eq!(f.count("SELECT count(*) FROM fts_mapping"), 0);
        assert_eq!(f.count("SELECT count(*) FROM notes"), 0);
    }

    fn link_flags(nodes: &[AstNode]) -> Vec<bool> {
        let mut out = Vec::new();
        fn walk(nodes: &[AstNode], out: &mut Vec<bool>) {
            for node in nodes {
                match node {
                    AstNode::Heading { content, .. } | AstNode::Paragraph { content } => {
                        inline(content, out);
                    }
                    AstNode::List { items, .. } => walk(items, out),
                    AstNode::ListItem { content, .. } | AstNode::Blockquote { nodes: content } => {
                        walk(content, out);
                    }
                    _ => {}
                }
            }
        }
        fn inline(content: &[InlineElement], out: &mut Vec<bool>) {
            for element in content {
                match element {
                    InlineElement::Link {
                        exists, content, ..
                    } => {
                        out.push(*exists);
                        inline(content, out);
                    }
                    InlineElement::ExternalLink { content, .. } => inline(content, out),
                    InlineElement::Text(_) => {}
                }
            }
        }
        walk(nodes, &mut out);
        out
    }
}
