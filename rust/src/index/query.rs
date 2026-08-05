//! Discovery and knowledge-graph queries scoped to the active Workspace
//! (WSPC-D009): title-prefix lookup (CAP-FIND-02), the Link completion
//! (CAP-GRAPH-02), backlinks (CAP-GRAPH-05) and the Workspace tree
//! (CAP-GRAPH-01).
//!
//! `search_notes` itself stays in `api::ffi_api` next to `SEARCH_NOTES_SQL`
//! (`architecture/flows/flow-search.md` names that constant as where the
//! caller-supplied `limit` replaces the old hardcoded cap), and
//! `index::scan`'s query-plan test asserts against it by name — moving it
//! here would touch a file this ticket does not scope. Everything else
//! discovery-shaped lives here instead.
//!
//! Every function below takes `workspace_id: &str` explicitly rather than
//! reading `db::connection::active_workspace_id()` itself, matching the
//! rest of the crate's `_impl` convention: the thin `#[frb]` wrapper in
//! `api::ffi_api` resolves the active Workspace and hands it down, so these
//! stay testable against a bare `Connection` with no process-wide state.

use std::collections::HashMap;

use flutter_rust_bridge::frb;
use rusqlite::Connection;

use crate::draft::NoteMetadata;
use crate::error::AppError;

/// One candidate for the in-editor Link completion (CAP-GRAPH-02).
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkCompletion {
    pub note_id: String,
    pub title: String,
    /// The exact text to splice at the cursor: a bundle-absolute Markdown
    /// link, already angle-bracket wrapped and escaped by
    /// `okf::serialize_link`. Built here, in the Core, so the UI never
    /// assembles a link target and cannot produce a non-conformant one — an
    /// ordinary multi-word title produces a path containing a space, and the
    /// unwrapped form of that is not a link at all.
    pub insert_text: String,
}

/// One entry in the Workspace tree (CAP-GRAPH-01). Directories carry their
/// children so the sidebar renders from a single call rather than one call
/// per level.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TreeNode {
    Directory {
        name: String,
        path: String,
        children: Vec<TreeNode>,
    },
    Note {
        id: String,
        title: String,
        path: String,
    },
}

/// Escapes `%`, `_` and the escape character itself in `query`, then appends
/// the wildcard suffix a prefix match needs. Without this a caller's own `%`
/// or `_` would be interpreted as a `LIKE` wildcard rather than matched
/// literally — the same class of footgun `fts5_phrase_query` neutralizes for
/// `MATCH`, applied to `LIKE`'s own two special characters instead.
fn like_prefix_pattern(query: &str) -> String {
    let mut out = String::with_capacity(query.len() + 1);
    for c in query.chars() {
        if matches!(c, '%' | '_' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('%');
    out
}

fn note_metadata_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<NoteMetadata> {
    Ok(NoteMetadata {
        id: row.get(0)?,
        okf_conformant: row.get(1)?,
        path: row.get(2)?,
        title: row.get(3)?,
        last_modified: row.get(4)?,
        snippet: None,
    })
}

/// Title-prefix jump (CAP-FIND-02): every Note in `workspace_id` whose title
/// starts with `query`, ordered alphabetically, capped at `limit`.
///
/// `limit` is bound straight to SQL `LIMIT`, so **`0` returns no rows** rather
/// than every row. Left as SQLite's own semantics rather than clamped or
/// refused: `contracts/ffi_api.rs` introduces `limit` only to replace a
/// hardcoded cap of 50 that "silently truncated with no signal to the caller"
/// and states no lower bound, so a caller asking for zero results is asking a
/// coherent question and gets the literal answer.
pub fn find_notes_by_title_impl(
    conn: &Connection,
    workspace_id: &str,
    query: &str,
    limit: u32,
) -> Result<Vec<NoteMetadata>, AppError> {
    let pattern = like_prefix_pattern(query);
    let mut stmt = conn.prepare(
        "SELECT id, okf_conformant, path, title, last_modified FROM notes \
         WHERE workspace_id = ?1 AND title LIKE ?2 ESCAPE '\\' \
         ORDER BY title LIMIT ?3",
    )?;
    let rows = stmt.query_map(
        rusqlite::params![workspace_id, pattern, limit],
        note_metadata_from_row,
    )?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

/// Candidates for the completion triggered by `[[` (CAP-GRAPH-02). Reuses
/// the same title-prefix match as [`find_notes_by_title_impl`] and adds the
/// ready-to-insert Markdown text: `EDIT-F006`'s STOP forbids the UI from
/// constructing the link target itself, so the wrapping happens here, over
/// the matched Note's own title and concept id, via `okf::serialize_link` —
/// the same function `data-models/okf-bundle.md` names as the sole writer of
/// this form.
///
/// `limit` carries [`find_notes_by_title_impl`]'s semantics unchanged,
/// including `0` returning no candidates.
pub fn link_completions_impl(
    conn: &Connection,
    workspace_id: &str,
    query: &str,
    limit: u32,
) -> Result<Vec<LinkCompletion>, AppError> {
    let candidates = find_notes_by_title_impl(conn, workspace_id, query, limit)?;
    Ok(candidates
        .into_iter()
        .map(|note| LinkCompletion {
            insert_text: crate::okf::serialize_link(&note.title, &note.id),
            note_id: note.id,
            title: note.title,
        })
        .collect())
}

/// Notes linking *to* `note_id` (CAP-GRAPH-05), served by `idx_links_target`.
pub fn backlinks_impl(
    conn: &Connection,
    workspace_id: &str,
    note_id: &str,
) -> Result<Vec<NoteMetadata>, AppError> {
    let mut stmt = conn.prepare(
        "SELECT n.id, n.okf_conformant, n.path, n.title, n.last_modified \
         FROM links l \
         CROSS JOIN notes n ON n.workspace_id = l.workspace_id AND n.id = l.source_id \
         WHERE l.workspace_id = ?1 AND l.target_id = ?2 \
         ORDER BY n.title",
    )?;
    let rows = stmt.query_map(
        rusqlite::params![workspace_id, note_id],
        note_metadata_from_row,
    )?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

/// The bundle-relative parent of `id` (`""` at the bundle root) and the
/// final path segment, shared by both `directories.id` and `notes.id` —
/// both are `/`-separated concept-shaped paths with no leading slash.
fn split_parent(id: &str) -> (String, String) {
    match id.rsplit_once('/') {
        Some((parent, name)) => (parent.to_string(), name.to_string()),
        None => (String::new(), id.to_string()),
    }
}

/// The Directory tree for the sidebar (CAP-GRAPH-01): Directories before
/// Notes at each level, each group sorted case-insensitively by name — the
/// contract only says "sorted by name", and byte order would put `Zebra`
/// before `apple` in a user-facing sidebar, which is not the reading a
/// sighted user expects — with a deterministic tie-break
/// (`directories.path` / `notes.id`) for siblings that share a name. Titles
/// are unique only per `(workspace_id, path)`, not per Directory, so a name
/// alone does not total-order two Notes that happen to share a title; without
/// the tie-break, ties fall back to SQLite's unspecified return order, which
/// can flip after a reindex or `VACUUM` and surfaces as rows swapping in a
/// tree widget's keyed reconciliation.
///
/// Renders from `directories` and `notes` alone, joined in
/// [`build_tree_level`] purely by the parent-path relation [`split_parent`]
/// derives — there is no recursive SQL query here. That makes
/// `incremental::ensure_directories`'s invariant load-bearing: every
/// ancestor directory of an indexed Note must carry its own row, or that
/// Note's whole subtree silently vanishes from the tree with no error,
/// because nothing here walks up from a Note to synthesize a missing parent.
pub fn workspace_tree_impl(
    conn: &Connection,
    workspace_id: &str,
) -> Result<Vec<TreeNode>, AppError> {
    let mut dir_stmt = conn.prepare("SELECT id, path FROM directories WHERE workspace_id = ?1")?;
    let dirs: Vec<(String, String)> = dir_stmt
        .query_map([workspace_id], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;

    let mut note_stmt =
        conn.prepare("SELECT id, path, title FROM notes WHERE workspace_id = ?1")?;
    let notes: Vec<(String, String, String)> = note_stmt
        .query_map([workspace_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut dirs_by_parent: HashMap<String, Vec<(String, String)>> = HashMap::new();
    for (id, path) in dirs {
        let (parent, name) = split_parent(&id);
        dirs_by_parent.entry(parent).or_default().push((name, path));
    }

    let mut notes_by_parent: HashMap<String, Vec<(String, String, String)>> = HashMap::new();
    for (id, path, title) in notes {
        let (parent, _) = split_parent(&id);
        notes_by_parent
            .entry(parent)
            .or_default()
            .push((id, path, title));
    }

    Ok(build_tree_level("", &dirs_by_parent, &notes_by_parent))
}

fn build_tree_level(
    parent: &str,
    dirs_by_parent: &HashMap<String, Vec<(String, String)>>,
    notes_by_parent: &HashMap<String, Vec<(String, String, String)>>,
) -> Vec<TreeNode> {
    let mut out = Vec::new();

    if let Some(dirs) = dirs_by_parent.get(parent) {
        let mut dirs = dirs.clone();
        // Case-insensitive by name, tie-broken by the Directory's own
        // (unique) path: `directories.id`/`.path` is unique per Workspace, so
        // this total-orders even two Directories that happen to share a
        // display name after lowercasing.
        dirs.sort_by(|a, b| {
            a.0.to_lowercase()
                .cmp(&b.0.to_lowercase())
                .then_with(|| a.1.cmp(&b.1))
        });
        for (name, path) in dirs {
            let children = build_tree_level(&path, dirs_by_parent, notes_by_parent);
            out.push(TreeNode::Directory {
                name,
                path,
                children,
            });
        }
    }

    if let Some(notes) = notes_by_parent.get(parent) {
        let mut notes = notes.clone();
        // Case-insensitive by title, tie-broken by concept id. Titles are
        // unique only per `(workspace_id, path)` (`schema.sql`), not per
        // Directory, so two Notes can share a title verbatim — the id is
        // what keeps the order deterministic across calls instead of falling
        // back to SQLite's unspecified order for the tie.
        notes.sort_by(|a, b| {
            a.2.to_lowercase()
                .cmp(&b.2.to_lowercase())
                .then_with(|| a.0.cmp(&b.0))
        });
        for (id, path, title) in notes {
            out.push(TreeNode::Note { id, title, path });
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::super::fixtures::*;
    use super::super::scan::reindex_workspace_impl;
    use super::*;

    /// Gherkin: Notes exist whose titles match a completion query; each
    /// result carries insert text that is a bundle-absolute Markdown link.
    #[test]
    fn link_completions_carry_bundle_absolute_insert_text() {
        let f = fixture();
        f.write(
            "projects/Meeting Notes.md",
            &conformant("Meeting Notes", "Body."),
        );
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let completions = link_completions_impl(&f.conn, &f.workspace_id, "Meeting", 10).unwrap();

        assert_eq!(completions.len(), 1);
        assert_eq!(completions[0].note_id, "projects/Meeting Notes");
        assert_eq!(
            completions[0].insert_text,
            "[Meeting Notes](</projects/Meeting Notes.md>)"
        );
    }

    /// Gherkin: a matching Note whose title contains a space — the ordinary
    /// case, not an edge one — round-trips through a real parse: the
    /// completion's insert text yields a Link whose target is that Note.
    ///
    /// Parsed via [`links_from_source`], which runs the completion text
    /// through the exact same traversal `index::scan` uses in production
    /// (`derive_note`), not a hand-rolled AST walk that could silently drift
    /// from it. The `containing_dir` half of that traversal — derived from
    /// the concept id passed in, here `"somewhere/else/unrelated"`, nowhere
    /// near where `projects/Meeting Notes` actually lives — is deliberately
    /// wrong: `okf::links::classify` only ever consults `containing_dir` for
    /// a *relative* destination, so a link that still resolves correctly
    /// under a wrong one could not have been relative. That is what proves
    /// `insert_text` is the bundle-absolute form and not merely consistent
    /// with root-relative parsing, which a `containing_dir` of `""` cannot
    /// distinguish.
    #[test]
    fn completion_insert_text_parses_back_to_a_link_targeting_the_note() {
        let f = fixture();
        f.write(
            "projects/Meeting Notes.md",
            &conformant("Meeting Notes", "Body."),
        );
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let completions = link_completions_impl(&f.conn, &f.workspace_id, "Meeting", 10).unwrap();
        assert_eq!(completions.len(), 1);

        let source = format!("See {} for details.\n", completions[0].insert_text);
        let links = links_from_source("somewhere/else/unrelated", &source);

        assert_eq!(links, vec!["projects/Meeting Notes".to_string()]);
    }

    /// Gherkin (pinning `okf::links`' escaping — WSPC-D002 — through this
    /// path, which `EDIT-F006` depends on): a title containing `[`, `]` and
    /// `&`, none of which are optional to escape in the text position
    /// (`serialize_link`'s doc comment), still round-trips through
    /// `link_completions` to a Link targeting the right Note.
    #[test]
    fn completion_insert_text_for_a_bracket_and_ampersand_title_round_trips() {
        let f = fixture();
        let title = "Plan [Draft] & Notes";
        f.write(&format!("{title}.md"), &conformant(title, "Body."));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let completions = link_completions_impl(&f.conn, &f.workspace_id, "Plan", 10).unwrap();
        assert_eq!(completions.len(), 1);

        let source = format!("See {} for details.\n", completions[0].insert_text);
        let links = links_from_source("elsewhere/unrelated", &source);

        assert_eq!(links, vec![title.to_string()]);
    }

    /// Parses `source` and returns the target concept id of every Link found
    /// in it, via `index::derive_note` — the same derivation
    /// `index::scan`/`index::incremental` run over every Note on disk — so
    /// this test helper cannot drift from the production Link-extraction
    /// path the way a second, hand-written AST walk could. `concept_id`
    /// supplies the containing directory `derive_note` resolves relative
    /// destinations against (unused here, since every Link under test is the
    /// bundle-absolute form `serialize_link` writes).
    fn links_from_source(concept_id: &str, source: &str) -> Vec<String> {
        let note = crate::index::derive_note(
            concept_id,
            source,
            crate::index::content_hash(source.as_bytes()),
            0,
        );
        note.links.into_iter().map(|link| link.target_id).collect()
    }

    /// Gherkin: three Notes link to a target Note; backlinks for that Note
    /// returns all three source Notes.
    #[test]
    fn backlinks_returns_every_source_note() {
        let f = fixture();
        f.write("target.md", &conformant("Target", "The target."));
        f.write("a.md", &conformant("A", "See [Target](</target.md>)."));
        f.write("b.md", &conformant("B", "Also [Target](</target.md>)."));
        f.write(
            "c.md",
            &conformant("C", "And [Target](</target.md>) again."),
        );
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let results = backlinks_impl(&f.conn, &f.workspace_id, "target").unwrap();

        let ids: std::collections::HashSet<_> = results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(
            ids,
            std::collections::HashSet::from(["a", "b", "c"]),
            "all three source Notes must be returned"
        );
    }

    /// Two Links from the same Note to the same target are one graph edge,
    /// not two (`links` primary key is `(workspace_id, source_id,
    /// target_id)`, and `insert_note_rows` writes it `INSERT OR IGNORE`) —
    /// pinned here against a future refactor that joins `links` without
    /// deduplicating, which would report the same source Note once per Link
    /// instead of once per edge.
    #[test]
    fn a_note_linking_twice_to_the_same_target_yields_one_backlink() {
        let f = fixture();
        f.write("target.md", &conformant("Target", "The target."));
        f.write(
            "a.md",
            &conformant(
                "A",
                "See [Target](</target.md>) and again [Target](</target.md>).",
            ),
        );
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let results = backlinks_impl(&f.conn, &f.workspace_id, "target").unwrap();

        assert_eq!(
            results.len(),
            1,
            "two Links to the same target from one Note is one edge, not two"
        );
        assert_eq!(results[0].id, "a");
    }

    /// A Note with no inbound Links reports no backlinks.
    #[test]
    fn backlinks_is_empty_for_a_note_with_no_inbound_links() {
        let f = fixture();
        f.write("lonely.md", &conformant("Lonely", "Body."));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let results = backlinks_impl(&f.conn, &f.workspace_id, "lonely").unwrap();

        assert!(results.is_empty());
    }

    /// Backlinks must not cross a Workspace boundary: a Note in another
    /// Workspace linking to a same-named target must not appear.
    #[test]
    fn backlinks_does_not_return_a_match_from_another_workspace() {
        let f = fixture();
        f.write("target.md", &conformant("Target", "Body."));
        f.write("a.md", &conformant("A", "[Target](</target.md>)"));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let other_root = f.dir.path().join("bundle-2");
        std::fs::create_dir_all(&other_root).unwrap();
        std::fs::write(other_root.join("target.md"), conformant("Target", "Body.")).unwrap();
        std::fs::write(
            other_root.join("z.md"),
            conformant("Z", "[Target](</target.md>)"),
        )
        .unwrap();
        f.conn
            .execute(
                "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
                 VALUES ('other-ws', 'Other', 'local', NULL, ?1)",
                [other_root.to_string_lossy().to_string()],
            )
            .unwrap();
        reindex_workspace_impl(&f.conn, "other-ws").unwrap();

        let results = backlinks_impl(&f.conn, &f.workspace_id, "target").unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "a");
    }

    /// Gherkin: a Workspace with nested Directories and Notes; the tree
    /// returns nested entries with Directories before Notes at each level.
    #[test]
    fn workspace_tree_nests_directories_before_notes_at_each_level() {
        let f = fixture();
        f.write("Welcome.md", &conformant("Welcome", "Root note."));
        f.write("projects/burlmd.md", &conformant("Burlmd", "A project."));
        f.write("projects/deep/nested.md", &conformant("Nested", "Deep."));
        f.mkdir("empty");
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let tree = workspace_tree_impl(&f.conn, &f.workspace_id).unwrap();

        // Root level: Directories ("empty", "projects") before the Note
        // ("Welcome"), each group sorted by name.
        let root_names: Vec<&str> = tree
            .iter()
            .map(|node| match node {
                TreeNode::Directory { name, .. } => name.as_str(),
                TreeNode::Note { title, .. } => title.as_str(),
            })
            .collect();
        assert_eq!(root_names, vec!["empty", "projects", "Welcome"]);

        let TreeNode::Directory {
            name: empty_name,
            children: empty_children,
            ..
        } = &tree[0]
        else {
            panic!("expected the first entry to be a Directory");
        };
        assert_eq!(empty_name, "empty");
        assert!(empty_children.is_empty());

        let TreeNode::Directory {
            name: projects_name,
            children: projects_children,
            ..
        } = &tree[1]
        else {
            panic!("expected the second entry to be a Directory");
        };
        assert_eq!(projects_name, "projects");

        // "projects" holds a Directory ("deep") and a Note ("burlmd.md"),
        // Directory first.
        assert_eq!(projects_children.len(), 2);
        let TreeNode::Directory {
            name: deep_name,
            children: deep_children,
            ..
        } = &projects_children[0]
        else {
            panic!("expected projects' first child to be a Directory");
        };
        assert_eq!(deep_name, "deep");
        let TreeNode::Note {
            id: deep_note_id, ..
        } = &deep_children[0]
        else {
            panic!("expected a Note beneath deep");
        };
        assert_eq!(deep_note_id, "projects/deep/nested");

        let TreeNode::Note {
            id: burlmd_id,
            path: burlmd_path,
            ..
        } = &projects_children[1]
        else {
            panic!("expected projects' second child to be a Note");
        };
        assert_eq!(burlmd_id, "projects/burlmd");
        assert_eq!(burlmd_path, "projects/burlmd.md");
    }

    /// Case-insensitive ordering is a deliberate reading of the contract's
    /// "sorted by name": byte order would put every capitalized entry ahead
    /// of every lowercase one, which is not what a sighted user expects from
    /// a sidebar.
    #[test]
    fn workspace_tree_orders_siblings_case_insensitively() {
        let f = fixture();
        f.write("Zebra.md", &conformant("Zebra", "Body."));
        f.write("apple.md", &conformant("apple", "Body."));
        f.mkdir("Zoo");
        f.mkdir("aardvark");
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let tree = workspace_tree_impl(&f.conn, &f.workspace_id).unwrap();

        let names: Vec<&str> = tree
            .iter()
            .map(|node| match node {
                TreeNode::Directory { name, .. } => name.as_str(),
                TreeNode::Note { title, .. } => title.as_str(),
            })
            .collect();

        // Directories case-insensitively ("aardvark" before "Zoo"), then
        // Notes case-insensitively ("apple" before "Zebra") — byte order
        // would put both capitalized entries first in their group instead.
        assert_eq!(names, vec!["aardvark", "Zoo", "apple", "Zebra"]);
    }

    /// Titles are unique only per `(workspace_id, path)`, not per Directory,
    /// so two Notes sharing a title must still total-order deterministically
    /// — by concept id — and that order must not depend on which call it is,
    /// unlike SQLite's unspecified order for a tie, which can flip after a
    /// reindex or `VACUUM`.
    #[test]
    fn workspace_tree_breaks_same_title_ties_deterministically_and_stably() {
        let f = fixture();
        f.write("b-note.md", &conformant("Same Title", "Body B."));
        f.write("a-note.md", &conformant("Same Title", "Body A."));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let first = workspace_tree_impl(&f.conn, &f.workspace_id).unwrap();
        let second = workspace_tree_impl(&f.conn, &f.workspace_id).unwrap();

        let ids = |tree: &[TreeNode]| -> Vec<String> {
            tree.iter()
                .map(|node| match node {
                    TreeNode::Note { id, .. } => id.clone(),
                    TreeNode::Directory { path, .. } => path.clone(),
                })
                .collect()
        };

        assert_eq!(
            ids(&first),
            vec!["a-note".to_string(), "b-note".to_string()],
            "tied titles break on concept id, not on SQLite's unspecified row order"
        );
        assert_eq!(
            ids(&first),
            ids(&second),
            "the order must be stable across repeated calls"
        );
    }

    /// Gherkin (find_notes_by_title, exercised through link_completions since
    /// both share the same title-prefix query): a caller-supplied limit caps
    /// the number of results.
    #[test]
    fn find_notes_by_title_respects_the_caller_supplied_limit() {
        let f = fixture();
        f.write("a.md", &conformant("Alpha One", "Body."));
        f.write("b.md", &conformant("Alpha Two", "Body."));
        f.write("c.md", &conformant("Alpha Three", "Body."));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let results = find_notes_by_title_impl(&f.conn, &f.workspace_id, "Alpha", 2).unwrap();

        assert_eq!(results.len(), 2, "the caller's limit, not a hardcoded cap");
    }

    /// A `%` or `_` in the query is matched literally, not as a `LIKE`
    /// wildcard.
    #[test]
    fn title_prefix_query_does_not_treat_percent_as_a_wildcard() {
        let f = fixture();
        f.write("a.md", &conformant("100% Done", "Body."));
        f.write("b.md", &conformant("100 Percent Done", "Body."));
        reindex_workspace_impl(&f.conn, &f.workspace_id).unwrap();

        let results = find_notes_by_title_impl(&f.conn, &f.workspace_id, "100%", 10).unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "100% Done");
    }
}
