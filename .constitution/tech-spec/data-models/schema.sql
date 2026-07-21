-- Physical schema for the SQLite Local Index (ENCRYPTED via SQLCipher)
-- Uses PRAGMA user_version to track migration state.

PRAGMA foreign_keys = ON;

-- Represents an authorized Git repository connected via OAuth
CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY,           -- UUID
    remote_url TEXT NOT NULL,      -- Git URL (e.g., https://github.com/user/repo.git)
    provider TEXT NOT NULL,        -- 'github', 'gitlab'
    last_synced INTEGER            -- Unix timestamp
);

-- Represents metadata for a Note (Markdown file on disk)
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,           -- Stable UUID (never derived from file path)
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
    target_id TEXT NOT NULL,
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY (source_id) REFERENCES notes(id) ON DELETE CASCADE,
    FOREIGN KEY (target_id) REFERENCES notes(id) ON DELETE CASCADE
);

-- FTS5 Virtual Table for full-text search across all notes.
-- This is a standard FTS table (not external content) so it can store 
-- the text and generate snippets. The Core Engine must manually 
-- INSERT/DELETE/UPDATE this table when indexing files.
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    note_id UNINDEXED,
    title,
    content
);
