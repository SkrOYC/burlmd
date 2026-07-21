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

-- Represents metadata for a Note (Markdown file encrypted on disk)
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,           -- UUID or a normalized file path hash
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

-- FTS5 Virtual Table for full-text search across all notes
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    title,
    content,
    content='notes',    -- External content table
    content_rowid='rowid'
);

-- Triggers to keep FTS5 synchronized with the notes table (for title changes)
-- Note: The Core Engine must manually update the `content` field in `notes_fts` 
-- when the file on disk is decrypted and indexed, as SQLite cannot read the file contents directly.

CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, content) VALUES (new.rowid, new.title, '');
END;

CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, content) VALUES('delete', old.rowid, old.title, '');
END;

CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, content) VALUES('delete', old.rowid, old.title, '');
  INSERT INTO notes_fts(rowid, title, content) VALUES (new.rowid, new.title, '');
END;
