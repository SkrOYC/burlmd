-- Physical schema for the SQLite Local Index (ENCRYPTED via SQLCipher)
-- Uses PRAGMA user_version to track migration state.

PRAGMA foreign_keys = ON;

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
-- the Core Engine must query `SELECT rowid FROM notes_fts WHERE note_id = ?` 
-- and then `DELETE FROM notes_fts WHERE rowid = ?`.
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    note_id UNINDEXED,
    title,
    content
);

-- Represents in-memory drafts that survive OS process termination (OOM kill)
CREATE TABLE IF NOT EXISTS drafts (
    note_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    raw_markdown TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);

-- Represents explicit directories in the workspace (supports empty directories)
CREATE TABLE IF NOT EXISTS directories (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- Relative path within the Workspace
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
