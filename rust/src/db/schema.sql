-- Physical schema for the SQLite Local Index (ENCRYPTED via SQLCipher)
-- Uses PRAGMA user_version to track migration state.

PRAGMA foreign_keys = ON;

-- Baseline schema version. Re-applied on every boot (this file is executed
-- idempotently via `CREATE ... IF NOT EXISTS`), harmless while there is only
-- one version; the first real migration should branch on the value already
-- here rather than starting from an unset (0) baseline.
PRAGMA user_version = 1;

-- Represents an authorized Git repository connected via OAuth
CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY,           -- UUID
    name TEXT NOT NULL,
    provider TEXT NOT NULL,        -- 'github', 'gitlab', 'local'
    remote_url TEXT,               -- The Git remote URL
    local_path TEXT NOT NULL       -- Absolute path where the repo is cloned on disk
);

-- Represents metadata for a Note (Markdown file on disk)
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,           -- Stable UUID (persisted in Markdown YAML frontmatter)
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- The relative path within the Workspace
    title TEXT NOT NULL,
    last_modified INTEGER NOT NULL, -- Unix timestamp
    UNIQUE(workspace_id, path),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

-- Represents lateral connections between Notes
CREATE TABLE IF NOT EXISTS links (
    source_id TEXT NOT NULL,
    target_id TEXT,                -- Nullable for ghost links
    target_title TEXT NOT NULL,    -- The text inside [[Link]]
    PRIMARY KEY (source_id, target_title), -- Core Engine must use INSERT OR IGNORE
    FOREIGN KEY (source_id) REFERENCES notes(id) ON DELETE CASCADE
    -- No foreign key on target_id to allow "ghost links" to uncreated notes
);

-- FTS5 Virtual Table for full-text search across all notes.
-- Note: It is a standard FTS table. To avoid O(N) deletion scans on note_id,
-- the Core Engine must maintain the `fts_mapping` table.
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    title,
    content
);

-- B-Tree index mapping a note's UUID to its FTS5 internal rowid for fast deletion
CREATE TABLE IF NOT EXISTS fts_mapping (
    note_id TEXT PRIMARY KEY,
    fts_rowid INTEGER NOT NULL
);

-- Represents in-memory drafts that survive OS process termination (OOM kill)
CREATE TABLE IF NOT EXISTS drafts (
    note_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    raw_markdown TEXT NOT NULL,
    updated_at INTEGER NOT NULL
    -- No foreign key to notes(id) because new notes start as drafts before saving
);

-- Represents explicit directories in the workspace (supports empty directories)
CREATE TABLE IF NOT EXISTS directories (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- Relative path within the Workspace
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    UNIQUE(workspace_id, path)
);
