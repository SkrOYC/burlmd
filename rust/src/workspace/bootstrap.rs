//! Local Workspace bootstrap (ADR-005, `flow-workspace-bootstrap.md`).
//!
//! Implements the domain logic behind `open_or_create_local_workspace` and
//! `open_workspace`, which converge on identical post-conditions per
//! `flow-workspace-bootstrap.md`'s "Three bootstrap paths, one
//! post-condition": the Workspace directory exists, a Git repository is
//! present (initialized if absent, adopted unchanged if present — ADR-005
//! decision 8), and a `workspaces` row exists with `provider = 'local'` and
//! `remote_url = NULL`.
//!
//! Root key generation and opening the encrypted index are the caller's
//! responsibility, via `db::connection` — this module never touches OS
//! Keychain, the network, or authentication state directly. That is not an
//! oversight: `WSPC-D004`'s STOP conditions forbid all three, and
//! `flow-workspace-bootstrap.md` contains no such step.
//!
//! `#[frb]` async wrappers live in `api::ffi_api`, matching the pattern
//! `draft.rs` already establishes for `NoteState`/`NoteMetadata`: this module
//! owns the domain logic and is exercised directly in tests against an
//! injected `Connection`, so hermetic tests never touch the process-wide
//! `db::connection` singleton or the OS Keychain — only a real, on-disk
//! SQLCipher file and a real `gix` repository, both in a tempdir.

use std::path::{Path, PathBuf};

use flutter_rust_bridge::frb;
use rusqlite::{Connection, OptionalExtension};

use crate::error::AppError;

/// A Workspace: the bundle on disk plus its `workspaces` row
/// (`contracts/ffi_api.rs`).
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceInfo {
    pub id: String,
    pub name: String,
    /// `"local"` until the user connects a Remote (CAP-SYNC-01), then the
    /// provider name. Matches `workspaces.provider` in `schema.sql`.
    pub provider: String,
    pub remote_url: Option<String>,
    /// Absolute path to the bundle root on disk.
    pub local_path: String,
}

/// Resolves the default local Workspace directory (`guidelines.md`
/// "Workspace location"): `$XDG_DATA_HOME/burlmd/workspace`, falling back to
/// `~/.local/share/burlmd/workspace` (`~/Library/Application
/// Support/burlmd/workspace` on macOS) when `XDG_DATA_HOME` is unset. A
/// sibling of the default index path resolved by
/// `db::connection::default_db_path`, under the same shared `burlmd/`
/// parent — the index is derived state and lives outside the bundle it
/// indexes, never within it.
pub fn default_workspace_dir() -> Result<PathBuf, AppError> {
    Ok(crate::db::connection::xdg_data_home()?
        .join("burlmd")
        .join("workspace"))
}

/// Opens the local Workspace at `path` (or the default location from
/// [`default_workspace_dir`] when `path` is `None`), creating and
/// initializing it if absent (ADR-005 decision 1). The domain entry point
/// behind `api::ffi_api::open_or_create_local_workspace`.
pub(crate) fn open_or_create_local_workspace_impl(
    conn: &Connection,
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    let dir = match path {
        Some(p) => PathBuf::from(p),
        None => default_workspace_dir()?,
    };
    converge(conn, &dir)
}

/// Opens an existing Workspace directory the application did not create,
/// including one populated by another tool (CAP-WS-05). The domain entry
/// point behind `api::ffi_api::open_workspace`.
pub(crate) fn open_workspace_impl(
    conn: &Connection,
    path: String,
) -> Result<WorkspaceInfo, AppError> {
    converge(conn, Path::new(&path))
}

/// The convergent bootstrap logic shared by both entry points
/// (`flow-workspace-bootstrap.md`, ADR-005 decision 8): creates `dir` if
/// absent, initializes a Git repository in it or adopts existing history
/// unchanged, and writes (or reuses) the `workspaces` row. No Note under
/// `dir` is read, written, or otherwise modified — the only side effect
/// on a foreign directory besides the `workspaces` row is `.git/` itself.
fn converge(conn: &Connection, dir: &Path) -> Result<WorkspaceInfo, AppError> {
    std::fs::create_dir_all(dir).map_err(|e| AppError::IoError(e.to_string()))?;
    crate::git::operations::init_repo(dir)?;

    let local_path = dir.to_string_lossy().to_string();

    let existing = conn
        .query_row(
            "SELECT id, name, provider, remote_url FROM workspaces WHERE local_path = ?1",
            [&local_path],
            |row| {
                Ok(WorkspaceInfo {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    provider: row.get(2)?,
                    remote_url: row.get(3)?,
                    local_path: local_path.clone(),
                })
            },
        )
        .optional()?;

    if let Some(info) = existing {
        // Reused, not recreated: no second row and — since root key
        // generation happens once per process, in `db::connection`'s own
        // singleton init, entirely upstream of this function — no second
        // key either.
        return Ok(info);
    }

    let id = mint_workspace_id()?;
    let name = workspace_name(dir);
    conn.execute(
        "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
         VALUES (?1, ?2, 'local', NULL, ?3)",
        rusqlite::params![id, name, local_path],
    )?;

    Ok(WorkspaceInfo {
        id,
        name,
        provider: "local".to_string(),
        remote_url: None,
        local_path,
    })
}

fn workspace_name(dir: &Path) -> String {
    dir.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("Workspace")
        .to_string()
}

/// Mints an opaque, locally-generated Workspace id — `schema.sql`: "Opaque,
/// locally minted. Not a concept id." A 128-bit CSPRNG value, hex-encoded.
fn mint_workspace_id() -> Result<String, AppError> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes)
        .map_err(|e| AppError::CryptoError(format!("OS CSPRNG failure: {e}")))?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::connection::{init_schema, open_encrypted_db_with_key, EnvVarGuard, ENV_LOCK};
    use tempfile::tempdir;

    /// A real, on-disk SQLCipher connection with the schema applied — never
    /// the process-wide `db::connection` singleton and never the OS
    /// Keychain, so these tests are hermetic and can run in any order.
    fn test_index(dir: &Path) -> Connection {
        let key = [0x77u8; 32]; // throwaway key, not the real Keychain entry
        let conn = open_encrypted_db_with_key(&dir.join("index.sqlite3"), &key).unwrap();
        init_schema(&conn).unwrap();
        conn
    }

    /// Gherkin: Given no Workspace directory exists and no network is
    /// reachable, When the local Workspace is opened, Then the directory is
    /// created, a repository is initialized in it, and a Workspace row is
    /// written with a local provider and no remote URL.
    ///
    /// "No network is reachable" needs no simulation: nothing in this
    /// module, `git::operations::init_repo`, or the query below makes a
    /// network call at all.
    #[test]
    fn open_or_create_creates_dir_repo_and_local_workspace_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_parent = tempdir().unwrap();
        let workspace_dir = workspace_parent.path().join("does-not-exist-yet");
        assert!(!workspace_dir.exists());

        let info = open_or_create_local_workspace_impl(
            &conn,
            Some(workspace_dir.to_string_lossy().to_string()),
        )
        .expect("bootstrap should succeed against an absent directory");

        assert!(workspace_dir.is_dir());
        assert!(workspace_dir.join(".git").is_dir());
        assert_eq!(info.provider, "local");
        assert_eq!(info.remote_url, None);
        assert_eq!(info.local_path, workspace_dir.to_string_lossy());
        assert!(!info.id.is_empty());

        let row: (String, Option<String>) = conn
            .query_row(
                "SELECT provider, remote_url FROM workspaces WHERE id = ?1",
                [&info.id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(row, ("local".to_string(), None));
    }

    /// Gherkin: Given a Workspace that already exists, When the local
    /// Workspace is opened again, Then the existing repository and Workspace
    /// row are reused — same id, same row count.
    #[test]
    fn second_open_reuses_the_existing_repository_and_workspace_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let path = workspace_dir.path().to_string_lossy().to_string();

        let first = open_or_create_local_workspace_impl(&conn, Some(path.clone())).unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some(path)).unwrap();

        assert_eq!(first.id, second.id, "the same Workspace row must be reused");

        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1, "no second row may be written on a repeat open");
    }

    /// Gherkin: Given an existing directory of Markdown files that this
    /// application did not create, When it is opened as a Workspace, Then it
    /// becomes the active Workspace, a Workspace row is written for it, and
    /// no Note in it is modified.
    #[test]
    fn open_workspace_adopts_a_foreign_directory_without_modifying_its_notes() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        let welcome = foreign_dir.path().join("Welcome.md");
        let original_bytes = b"---\ntitle: Welcome\n---\n\nHello.\n";
        std::fs::write(&welcome, original_bytes).unwrap();

        let info = open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string())
            .expect("adopting a foreign directory should succeed");

        assert_eq!(info.provider, "local");
        let stored_bytes = std::fs::read(&welcome).unwrap();
        assert_eq!(
            stored_bytes, original_bytes,
            "no Note in an adopted directory may be modified"
        );

        let row_count: i64 = conn
            .query_row(
                "SELECT count(*) FROM workspaces WHERE local_path = ?1",
                [foreign_dir.path().to_string_lossy()],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(row_count, 1);
    }

    /// Gherkin: Given that directory contains no version history, When it is
    /// opened as a Workspace, Then a repository is initialized in it —
    /// otherwise `close_note`'s tier 3 commit has nothing to commit into
    /// (ADR-005 decision 8).
    #[test]
    fn open_workspace_initializes_a_repository_when_the_directory_has_no_history() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        std::fs::write(foreign_dir.path().join("note.md"), b"content\n").unwrap();
        assert!(!foreign_dir.path().join(".git").exists());

        open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string()).unwrap();

        assert!(foreign_dir.path().join(".git").is_dir());
    }

    /// Gherkin: Given that directory already contains version history, When
    /// it is opened as a Workspace, Then the existing history is adopted
    /// unchanged.
    #[test]
    fn open_workspace_adopts_existing_history_unchanged() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let dir = tempdir().unwrap();
        crate::git::operations::init_repo(dir.path()).unwrap();
        std::fs::write(dir.path().join("note.md"), b"content\n").unwrap();
        let commit = crate::git::operations::commit_all(
            dir.path(),
            "pre-existing history",
            "Someone Else",
            "someone@example.com",
        )
        .unwrap();

        open_workspace_impl(&conn, dir.path().to_string_lossy().to_string()).unwrap();

        let head = std::process::Command::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8_lossy(&head.stdout).trim(),
            commit,
            "pre-existing history must not be disturbed by adoption"
        );
    }

    /// Gherkin: Given any connection opened against the encrypted index,
    /// When `PRAGMA foreign_keys` is queried on it, Then it reports enabled.
    /// Re-asserted here (beyond `db::connection`'s own coverage) against the
    /// exact connection shape this module's tests use, since bootstrap is
    /// the caller `guidelines.md` names as depending on the cascades it
    /// gates.
    #[test]
    fn the_connection_bootstrap_writes_through_has_foreign_keys_enabled() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let enabled: i64 = conn
            .query_row("PRAGMA foreign_keys", [], |r| r.get(0))
            .unwrap();
        assert_eq!(enabled, 1);
    }

    /// WSPC-D004: `open_or_create_local_workspace`'s default path and
    /// `db::connection`'s default index path resolve to siblings under the
    /// same shared `burlmd/` parent — the index lives outside the bundle,
    /// not within it, and not at the legacy `$HOME/.burlmd` location.
    #[test]
    fn default_workspace_dir_and_default_index_path_are_siblings_outside_each_other() {
        let _guard = ENV_LOCK.lock().unwrap();
        let fake_home = tempdir().unwrap();
        let _home = EnvVarGuard::set("HOME", fake_home.path().as_os_str());
        let _no_xdg = EnvVarGuard::unset("XDG_DATA_HOME");
        let _no_override = EnvVarGuard::unset("BURLMD_DB_PATH");

        let workspace_dir = default_workspace_dir().unwrap();
        let index_path = crate::db::connection::default_db_path().unwrap();

        assert_eq!(
            workspace_dir,
            fake_home
                .path()
                .join(".local")
                .join("share")
                .join("burlmd")
                .join("workspace")
        );
        assert_eq!(
            index_path,
            fake_home
                .path()
                .join(".local")
                .join("share")
                .join("burlmd")
                .join("index.sqlite3")
        );
        assert_eq!(
            workspace_dir.parent(),
            index_path.parent(),
            "the Workspace directory and the index must share the same burlmd/ parent"
        );
        assert!(
            !index_path.starts_with(&workspace_dir),
            "the index must not live inside the bundle it indexes"
        );

        let legacy_path = fake_home.path().join(".burlmd").join("index.sqlite3");
        assert_ne!(index_path, legacy_path);
    }
}
