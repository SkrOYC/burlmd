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

-- Baseline schema version. Deliberately still 1: nothing is deployed, no index
-- file exists on any machine, so the v1.1.0 corrections here are edits to the
-- baseline rather than a migration away from it. The first migration written
-- after this project has real users should branch on this value.
--
-- This statement is therefore NOT part of the batch `init_schema` replays on
-- every open. `connection.rs` runs `execute_batch(SCHEMA)` unconditionally, so
-- an unconditional `PRAGMA user_version = 1` would silently reset a migrated
-- database back to the baseline on its next open -- turning the one value a
-- future migration branches on into a constant. The Core reads
-- `PRAGMA user_version` first and sets it only when it reads 0, i.e. on a
-- freshly created file. It is written here because this file is the schema
-- contract and the version belongs with it, not because it is replayable.
PRAGMA user_version = 1;

-- Foreign key enforcement is per CONNECTION and is not stored in the database
-- file: SQLite defaults it OFF, so every connection the application opens must
-- issue the pragma above before it does anything else. This is not defensive.
-- Both cascades below are load-bearing -- `ON UPDATE CASCADE` is what makes a
-- rename possible at all -- and with the pragma off they do not error, they
-- simply do not fire, leaving orphaned `links` and `fts_mapping` rows behind
-- with nothing to signal it. `guidelines.md` states this as a connection-open
-- obligation, and `WSPC-D004` carries a criterion for it, because
-- `open_encrypted_db_with_key` is reachable without `init_schema` today.

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

-- Lateral connections between Notes, forming the knowledge graph.
-- One row is one edge. Links are stored on disk as standard bundle-absolute
-- Markdown links (ADR-004 decision 5), so the target's concept id is always
-- derivable from the link target -- including when no such Note exists.
CREATE TABLE IF NOT EXISTS links (
    workspace_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    -- The target's concept id, derived from the link target by stripping the
    -- leading '/' and trailing '.md'. NOT NULL: unlike the previous
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
    -- `WSPC-D006` re-keys them explicitly on rename. An orphan draft is not a
    -- supported state, but that is a property the Core enforces here, not one
    -- the schema does -- and `pending_drafts`, which returns `NoteMetadata`,
    -- could not represent one anyway.
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
