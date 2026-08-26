-- FORWARD STATUS (TechSpec v1.7.16-provisional): this is the delivered v2
-- derived-index schema. It does not yet model application session state,
-- excluded/repairable paths, Workspace observation, external-change
-- decisions, asset/object state, or typed Git reconciliation. Research Tasks
-- must not extend it. See provisional-forward-models.md; final Stage 3 owns
-- the migration after the AST, path, Git, asset, and packaging evidence lands.
--
-- Physical schema for the SQLite Local Index (ENCRYPTED via SQLCipher).
--
-- This is the second of the Local Repository's two storage forms. The first is
-- the OKF bundle on disk, whose contract is `okf-bundle.md`. Everything here is
-- derived state: the index can be discarded and rebuilt from the bundle at any
-- time, and `reindex_workspace` in `contracts/ffi_api.rs` does exactly that.
-- Nothing in this file is the source of truth for user content.
--
-- Two structural rules follow from OKF's positional identity (ADR-004) and are
-- the reason for most of the key shapes below:
--
--   1. A concept id is unique within a bundle, NOT globally. Two Workspaces may
--      each contain `Welcome.md`. Every table keyed by a concept id is therefore
--      keyed by `(workspace_id, ...)`, never by the id alone.
--   2. Renaming or moving a Note REWRITES its concept id (CAP-LIFE-02/03). Every
--      foreign key referencing a Note therefore carries `ON UPDATE CASCADE`;
--      without it, `PRAGMA foreign_keys = ON` makes a rename of any Note that
--      links out fail outright.

PRAGMA foreign_keys = ON;

-- Schema version 2 adds `notes.title_lookup_key`: a normalized, full-Unicode
-- case-folded title used only for title-prefix lookup. SQLite's stock LIKE and
-- NOCASE handling folds ASCII only, so querying `title` directly would make
-- `über` fail to find a Note titled `Über`. The original title remains the
-- user-visible value and is never rewritten by this derived lookup key.
--
-- Deliberately NOT set here. `db::connection::init_schema` replays this whole
-- batch via `execute_batch` on every open (every statement above and below is
-- idempotent via `CREATE ... IF NOT EXISTS`), so a literal `PRAGMA user_version
-- = 1;` in this file would silently reset a migrated database back to the
-- baseline on every subsequent open -- turning the one value a future
-- migration branches on into a constant. Instead, `init_schema` reads `PRAGMA
-- user_version` first. A version-zero file is classified inside one immediate
-- transaction: a truly empty file (or the recoverable `workspaces`-only DDL
-- prefix) receives v2 atomically; a v1 `notes` shape is migrated and
-- backfilled before v2 is published; and a v2 `notes` shape has any missing
-- idempotent objects completed before that publication. This matters because
-- version 0 can otherwise be a complete v1 file left by a crash between the
-- old schema batch and its separate version write. An index whose
-- `user_version` reads something later than 2 remains untouched by this
-- migration runner.

-- Foreign key enforcement is per CONNECTION and is not stored in the database
-- file: SQLite defaults it OFF, so every connection the application opens must
-- issue the pragma above before it does anything else. This is not defensive.
-- Both cascades below are load-bearing -- `ON UPDATE CASCADE` is what makes a
-- rename possible at all -- and with the pragma off they do not error, they
-- simply do not fire, leaving orphaned `links` and `fts_mapping` rows behind
-- with nothing to signal it. `guidelines.md` states this as a connection-open
-- obligation, and `WSPC-D004` carries a criterion for it: `db::connection`
-- issues this pragma directly on every freshly opened connection (not only
-- when this batch happens to run), because `open_encrypted_db_with_key` is
-- reachable without `init_schema`.

-- A Workspace. Local by default (ADR-005): `provider` is 'local' and
-- `remote_url` is NULL until the user explicitly connects one (CAP-SYNC-01),
-- at which point both are updated in place on the existing row.
CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY,           -- Opaque, locally minted. Not a concept id.
    name TEXT NOT NULL,
    provider TEXT NOT NULL,        -- 'local' (default), 'github', 'gitlab'
    remote_url TEXT,               -- NULL for a Workspace with no Remote
    local_path TEXT NOT NULL       -- Absolute path to the bundle root on disk
);

-- Metadata for a Note (one Markdown file in the bundle).
CREATE TABLE IF NOT EXISTS notes (
    -- The OKF concept id: the bundle-relative path with '.md' removed
    -- (OKF v0.2 SPEC.md section 2). Bundle-relative, '/'-separated, no leading
    -- slash. NOT a UUID -- the previous claim that this column held "a stable
    -- UUID persisted in Markdown YAML frontmatter" was never implemented and
    -- contradicted both the specification and the code; see ADR-004.
    --
    -- Unique per Workspace, not globally: this column alone cannot be the
    -- primary key, because two Workspaces may each hold a `Welcome.md`.
    id TEXT NOT NULL,
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- Same value as `id`, with '.md' retained
    title TEXT NOT NULL,           -- From frontmatter `title`, else derived from filename
    -- NFKC + full default case fold + NFC, derived by `index::title_lookup_key`.
    -- Kept as data rather than a SQLite collation because the bundled
    -- SQLCipher build has no ICU extension and stock LIKE/NOCASE are ASCII-only.
    title_lookup_key TEXT NOT NULL,
    last_modified INTEGER NOT NULL, -- Unix timestamp, for display and ordering only
    -- Content hash of the on-disk file. This is the OCC token `base_revision`
    -- in `contracts/ffi_api.rs` (ADR-007 decision 7), replacing the
    -- `last_modified` comparison that made the open->edit->save path fail by
    -- construction. Also lets an externally modified file be detected on open
    -- without reparsing it (CAP-PORT-03).
    content_hash TEXT NOT NULL,
    -- False when the file has no frontmatter, when its frontmatter does not
    -- parse, OR when it parses but carries no non-empty `type`. All three,
    -- because OKF section 11 states three conformance conditions and the
    -- second is the `type` field -- a block containing only `title:` parses
    -- perfectly and is still non-conformant. Earlier revisions of this comment
    -- listed only the first two cases, which contradicted
    -- `okf-frontmatter.schema.json`, where `type` is both `required` and the
    -- sole entry in `x-conformance-bearing`. The parseable-but-typeless file
    -- is the only case where this check is non-trivial, so it is the one that
    -- must be tested. Such a file is indexed anyway rather than rejected, so
    -- that a Workspace written by another tool still opens (CAP-WS-05,
    -- CAP-PORT-03).
    okf_conformant INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (workspace_id, id),
    UNIQUE(workspace_id, path),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

-- CAP-FIND-02 and CAP-GRAPH-02 both prefix-match this key. `NOCASE` remains
-- useful to SQLite's LIKE planner for the already-folded ASCII subset; every
-- non-ASCII case distinction was removed before storage. The remaining
-- columns make the user-visible sort and the deterministic concept-id
-- tie-break available without a temporary sort for the capped query.
CREATE INDEX IF NOT EXISTS idx_notes_title_lookup
    ON notes(workspace_id, title_lookup_key COLLATE NOCASE, title, id);

-- Lateral connections between Notes, forming the knowledge graph.
-- One row is one edge. Links are stored on disk as standard bundle-absolute
-- Markdown links (ADR-004 decision 5), so the target's concept id is always
-- derivable from the link target -- including when no such Note exists.
CREATE TABLE IF NOT EXISTS links (
    workspace_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    -- The target's concept id, derived from the parsed link destination by
    -- unescaping '\\', '\<', '\>' and '\&' and then stripping the leading '/'
    -- and trailing '.md'. '&' is escaped on the way out because CommonMark
    -- decodes HTML entity references inside a destination, so an unescaped
    -- '&eacute;' in a title would parse back as a different concept id. The destination is angle-bracket wrapped on disk (see
    -- data-models/okf-bundle.md) and the parser strips the brackets, so they
    -- never appear here. NOT NULL: unlike the previous
    -- title-based model, this is always computable. A "ghost link" is a row
    -- whose target_id matches no `notes.id` in the same Workspace -- which OKF
    -- section 6.1 requires consumers to tolerate, and which CAP-GRAPH-04 makes
    -- a feature.
    target_id TEXT NOT NULL,
    target_title TEXT NOT NULL,    -- The link's display text
    -- Keyed on the edge, not on the display text. Two links from the same Note
    -- to the same target with different wording are one graph edge; the second
    -- INSERT OR IGNORE keeps the first row's `target_title`. Accepted: this
    -- table indexes the graph, it does not reproduce the prose.
    --
    -- The rename path needs the same tolerance and cannot get it the same way,
    -- because it is an UPDATE and UPDATE has no OR IGNORE equivalent that keeps
    -- the row. Renaming `Old` to `New` rewrites `target_id` on every inbound
    -- edge, and collides whenever one Note already links to BOTH `Old` and a
    -- ghost `New` -- which is not contrived, it is exactly the CAP-GRAPH-04
    -- workflow of writing forward into an uncreated concept and then creating
    -- it. Reproduced against this file: a bare UPDATE fails with
    -- `UNIQUE constraint failed`, so a P0 rename (CAP-LIFE-02) breaks on a
    -- graph the product itself encourages. The rewrite must therefore be
    -- `UPDATE OR REPLACE`, which drops the duplicate edge and keeps the
    -- renamed link's own `target_title` -- the same "the graph, not the prose"
    -- trade-off already accepted above. See WSPC-D006.
    PRIMARY KEY (workspace_id, source_id, target_id),
    -- ON UPDATE CASCADE is load-bearing, not defensive: renaming a Note
    -- rewrites `notes.id`, and without this a rename of any Note that links
    -- out fails with a foreign key violation.
    FOREIGN KEY (workspace_id, source_id) REFERENCES notes(workspace_id, id)
        ON DELETE CASCADE ON UPDATE CASCADE
    -- Deliberately no foreign key on target_id, to permit ghost links. Inbound
    -- links to a RENAMED Note therefore do not cascade and must be rewritten
    -- explicitly, in the same transaction -- see WSPC-D006 and risk 8.
);

-- Backlink lookups (CAP-GRAPH-05) query by target within a Workspace. Without
-- this index that is a full scan of every edge in the index on every Note open.
CREATE INDEX IF NOT EXISTS idx_links_target ON links(workspace_id, target_id);

-- FTS5 virtual table backing full-text search (CAP-FIND-01, <100ms per
-- `prd/constraints.md`). A standard (non-external-content) FTS table; to avoid
-- an O(N) scan when deleting a Note's row, the Core Engine maintains
-- `fts_mapping` alongside it. FTS5 cannot express a foreign key or a composite
-- primary key, which is precisely why `fts_mapping` carries both on its behalf.
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    title,
    content
);

-- Maps a Note to its FTS5 internal rowid, for O(1) deletion.
--
-- ORDERING OBLIGATION, and the reason this table is dangerous as well as
-- useful: the cascade below destroys the only pointer to the FTS row. Deleting
-- the `notes` row removes the mapping in the same statement, and `notes_fts`
-- is a virtual table with no foreign keys and no `workspace_id`, so the rowid
-- is then unrecoverable and the row is unreachable AND undeletable.
-- Reproduced: after `DELETE FROM notes`, the mapping is gone, the FTS row
-- remains, and its content still matches a `MATCH` query. EVERY path that
-- removes a `notes` row must therefore delete from `notes_fts` via this
-- mapping FIRST, in the same transaction, before touching `notes`. That is
-- `delete_note` and `delete_directory`, and also `reindex_workspace` and the
-- incremental single-Note rewrite -- both of which are worse, because a
-- rebuild strands the WHOLE Workspace's text at once and reindex runs on
-- first open, after a merge, and on recovery. Left unordered the
-- consequence is not merely disk growth: the full text of every deleted Note
-- accumulates permanently in the one file this product encrypts precisely
-- because it aggregates the content of every Note.
CREATE TABLE IF NOT EXISTS fts_mapping (
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    fts_rowid INTEGER NOT NULL,
    PRIMARY KEY (workspace_id, note_id),
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- The primary key above serves DELETION, which is what this table exists for.
-- RETRIEVAL joins the other way: the search query drives from `notes_fts` and
-- joins `ON fts_mapping.fts_rowid = notes_fts.rowid`, and `fts_rowid` is not a
-- prefix of that key. Without this index SQLite builds an AUTOMATIC COVERING
-- INDEX over the whole table on every single search -- it still picks the
-- right drive order, so this is not the catastrophic re-run-MATCH-per-row
-- plan, but it is O(N) transient work per query, repeated and discarded.
-- Measured over 20,000 Notes in one Workspace, in memory: 19.8ms as written,
-- 15.7ms with this index, 4.5ms with this index AND table statistics. Both
-- halves matter, and the second is the less obvious one -- `ANALYZE` is what
-- lets the planner reach `notes` through its own primary key instead of
-- building a second automatic index for that join too. Every path that
-- rebuilds the index must therefore run `ANALYZE` when it finishes.
-- Same reasoning as `idx_links_target` above; against a SQLCipher file on
-- disk rather than an in-memory database the gap is wider.
CREATE INDEX IF NOT EXISTS idx_fts_mapping_rowid ON fts_mapping(fts_rowid);

-- Tier 1 of ADR-008: in-progress Block edits, written on every keystroke so
-- that unwritten work survives an abrupt process kill (CAP-WS-03, and
-- `architecture/resilience.md`'s SQLite Draft Persistence guarantee).
-- Encrypted at rest by virtue of living in this database. A row here is
-- transient: it is cleared once the Note is closed (tier 3).
CREATE TABLE IF NOT EXISTS drafts (
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    raw_markdown TEXT NOT NULL,    -- Full current source text of the Note
    updated_at INTEGER NOT NULL,
    -- The Core's per-Note edit sequence at the moment this row was written,
    -- and the reason tier 2's clear is safe. `SPK-WSPC-D001` §6.2.6: a tier 1
    -- write releases the state lock before its 8-23ms encrypted row write, so
    -- a timer that snapshotted at sequence N, wrote the file, and then
    -- compared an *in-memory* counter still reading N would clear a row the
    -- keystroke is about to write -- and the keystroke would then write row(N)
    -- into a table the timer believed it had emptied. The counter to compare
    -- is the row's, not the buffer's, so the clear is
    -- `DELETE FROM drafts WHERE ... AND edit_seq <= ?`, evaluated atomically
    -- against the row itself. `<=` rather than `=` because a row lagging the
    -- snapshot is also redundant once the newer bytes are on disk.
    edit_seq INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (workspace_id, note_id)
    -- Deliberately no foreign key to notes, for the RENAME case only: a
    -- draft must survive its Note's concept id changing, and adding a FK here
    -- would either block the rename or cascade it, neither of which is what
    -- `WSPC-D006` needs while it re-keys rows explicitly in one transaction.
    --
    -- Note this is NOT because a draft can precede its `notes` row. Under this
    -- design it cannot: `create_note` writes the file with conformant
    -- frontmatter and returns a full `NoteState`, so the row exists before the
    -- first keystroke.
    --
    -- Deletion is the other direction, and having no foreign key means it does
    -- NOT cascade -- reproduced against SQLite with `PRAGMA foreign_keys = ON`:
    -- deleting the `notes` row, or the `workspaces` row above it, leaves this
    -- row behind. `delete_note` and `delete_directory` therefore clear the
    -- affected draft rows explicitly, in the same transaction, exactly as
    -- `WSPC-D006` re-keys them explicitly on rename.
    --
    -- An orphaned draft is nevertheless a state the Core has to REPORT, not one
    -- it can assume away: the schema does not forbid it, so anything that clears
    -- a `notes` row without clearing the draft beside it -- a crash between the
    -- two statements, an external write to the index, a future path that forgets
    -- -- produces one, and the row it produces holds unflushed user work.
    -- `pending_drafts` therefore LEFT JOINs `notes` rather than joining it, and
    -- synthesizes the metadata the missing row would have carried (`path` from
    -- the concept id, `title` from its filename stem, `last_modified` from
    -- `updated_at`, `okf_conformant` false). An orphaned draft is reported and
    -- recoverable; an inner join dropped it silently, which is the one outcome
    -- unflushed work must never have.
);

-- Directories. Only strictly necessary for empty ones -- a Directory holding
-- Notes is implied by their paths -- but stored uniformly so the tree can be
-- rendered from one query (CAP-GRAPH-01) rather than derived per level.
CREATE TABLE IF NOT EXISTS directories (
    id TEXT NOT NULL,              -- Bundle-relative path, matching `path`
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- '/'-separated, no leading slash
    PRIMARY KEY (workspace_id, id),
    UNIQUE(workspace_id, path),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
