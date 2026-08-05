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
//! `flow-workspace-bootstrap.md` names a fourth post-condition alongside
//! those three — "bundle indexed" — and [`converge`] establishes it too, by
//! calling `index::scan::reindex_workspace_impl` once the `workspaces` row
//! exists. `WSPC-D004` deferred that to `WSPC-D005` because no rebuild
//! existed yet; one does, and leaving the call unwired made the
//! post-condition false on every path *and* left `WSPC-D006`'s rename
//! rewriting no Links at all in a bundle that had never been scanned (it
//! seeds its affected set from the `links` table). See [`converge`] for why
//! it runs on the reuse branch as well, and why it is synchronous.
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
/// behind `api::ffi_api::open_or_create_local_workspace`. Unlike
/// [`open_workspace_impl`], this is the one entry point that creates `dir`
/// when it doesn't exist yet.
pub(crate) fn open_or_create_local_workspace_impl(
    conn: &Connection,
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    let dir = match path {
        Some(p) => PathBuf::from(p),
        None => default_workspace_dir()?,
    };
    std::fs::create_dir_all(&dir).map_err(|e| AppError::IoError(e.to_string()))?;
    let canonical = canonicalize_workspace_dir(&dir)?;
    converge(conn, &canonical)
}

/// Opens an existing Workspace directory the application did not create,
/// including one populated by another tool (CAP-WS-05). The domain entry
/// point behind `api::ffi_api::open_workspace`.
///
/// Unlike [`open_or_create_local_workspace_impl`], this does **not** create
/// `dir` — the ticket description is explicit that `open_workspace` "does
/// not create the directory" (only `open_or_create_local_workspace` does),
/// and silently creating an empty directory at a caller-supplied path that
/// doesn't exist (a typo, an unmounted volume, a stale recent-Workspace
/// entry) would shadow the real bundle with a fresh empty one instead of
/// reporting the mistake (WSPC-D004 review finding #1).
pub(crate) fn open_workspace_impl(
    conn: &Connection,
    path: String,
) -> Result<WorkspaceInfo, AppError> {
    let dir = PathBuf::from(&path);
    if !dir.is_dir() {
        return Err(AppError::NotFound(format!(
            "workspace directory does not exist: {path}"
        )));
    }
    let canonical = canonicalize_workspace_dir(&dir)?;
    converge(conn, &canonical)
}

/// Resolves `dir` to its canonical, absolute form (symlinks followed,
/// `.`/`..` and trailing slashes normalized). Both entry points above call
/// this *after* confirming `dir` exists (creating it first, in
/// [`open_or_create_local_workspace_impl`]'s case) and *before* `converge`
/// reads or writes `workspaces.local_path` — that column has no `UNIQUE`
/// constraint, so [`converge`]'s reuse-by-`local_path` lookup is only
/// correct if every caller agrees on one spelling of the same directory.
/// Without this, `/x/ws`, `/x/ws/`, a relative spelling, and a
/// symlink-indirected path would each mint a separate `workspaces` row for
/// what is really one bundle, splitting its index across two id spaces —
/// which ADR-005 decision 7 requires not happen (WSPC-D004 review
/// finding #2).
fn canonicalize_workspace_dir(dir: &Path) -> Result<PathBuf, AppError> {
    std::fs::canonicalize(dir)
        .map_err(|e| AppError::IoError(format!("resolve workspace path {}: {e}", dir.display())))
}

/// The convergent bootstrap logic shared by both entry points
/// (`flow-workspace-bootstrap.md`, ADR-005 decision 8): initializes a Git
/// repository in `dir` or adopts existing history unchanged, and writes (or
/// reuses) the `workspaces` row, then indexes the bundle. `dir` must already
/// exist and be canonicalized — both callers above guarantee this before
/// calling in.
///
/// **No Note under `dir` is written or otherwise modified.** Notes are now
/// *read*, because indexing them is what the fourth post-condition means, but
/// the rebuild derives rows from bytes it never writes back. The side effects
/// on a foreign directory are exactly three, and none of them is content:
/// `.git/`, a `.gitignore` extended with burlmd's own scratch patterns
/// (`git::operations::init_repo`), and the removal of any `.burlmd-trash.*` or
/// `.{name}.tmp` file a previous kill left behind
/// ([`sweep_scratch_files`]) — which are burlmd's, not the bundle's.
fn converge(conn: &Connection, dir: &Path) -> Result<WorkspaceInfo, AppError> {
    crate::git::operations::init_repo(dir)?;
    sweep_scratch_files(dir);

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

    let info = match existing {
        // Reused, not recreated: no second row and — since root key
        // generation happens once per process, in `db::connection`'s own
        // singleton init, entirely upstream of this function — no second
        // key either.
        Some(info) => info,
        None => {
            let id = mint_workspace_id()?;
            let name = workspace_name(dir);
            conn.execute(
                "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
                 VALUES (?1, ?2, 'local', NULL, ?3)",
                rusqlite::params![id, name, local_path],
            )?;
            WorkspaceInfo {
                id,
                name,
                provider: "local".to_string(),
                remote_url: None,
                local_path,
            }
        }
    };

    // The third post-condition: "bundle indexed". Runs after the `workspaces`
    // row exists, because the rebuild resolves the bundle root through it, and
    // on **both** branches — a reused row says nothing about whether the files
    // under it still match the index, since another tool (or another checkout)
    // may have moved underneath it while the application was not running.
    //
    // Not merely a missing post-condition, either. `WSPC-D006`'s rename seeds
    // its affected set from the `links` table, so in a bundle that was never
    // indexed a rename finds no inbound edges and rewrites nothing, leaving
    // every Link in the Workspace pointing at the concept the rename removed —
    // `architecture/risks.md` risk 8, reached by simply never having scanned.
    //
    // Synchronous, deliberately. `flow-workspace-bootstrap.md` describes
    // indexing a large Workspace in the background with the tree filling in as
    // it goes; that is a recorded latent gap and building it here would be a
    // scope this bootstrap does not own. On an empty new bundle — the ordinary
    // first-run path — the rebuild walks nothing and costs one transaction.
    crate::index::scan::reindex_workspace_impl(conn, &info.id)?;

    Ok(info)
}

/// Removes every `.burlmd-trash.*` entry and every `.{name}.tmp` file left
/// anywhere under `dir`.
///
/// **Unconditionally, with no age threshold**, and that is the safe reading
/// rather than the lazy one: both families are created and removed inside a
/// single operation that holds a lock for its whole length, so neither is ever
/// legitimate at the moment a Workspace is being opened. One that is still
/// here got here because a `SIGKILL`, a crash or a power loss stopped the
/// cleanup — `Drop` does not run for any of them — and what it holds is
/// plaintext: a trash entry is the entire content of a Note that was deleted,
/// a temporary file is a Note as it was mid-write. `.gitignore` (written by
/// `git::operations::init_repo`) stops the next whole-worktree commit from
/// publishing them; this is what stops them sitting in the bundle at all.
///
/// The one case an age threshold would narrow is a re-open of the Workspace
/// that is *already* active, racing an idle write inside its own
/// `atomic_write`. It is stated rather than defended against because the
/// outcome is benign in the direction that matters: the sweep removes the
/// temporary file, the write's `rename` then fails, and tier 2 records the
/// error on the session and **keeps the draft row**, which is where the
/// unwritten work lives. Nothing is lost, and the next idle firing writes it.
///
/// Errors are swallowed deliberately. This is housekeeping on a path whose
/// real job is opening a Workspace, and a scratch file that cannot be removed —
/// a read-only directory, a file another process holds — is not a reason to
/// refuse the user their Notes. `.gitignore` is the backstop that makes it
/// merely untidy rather than a disclosure.
///
/// `.git/` is skipped for the same reason `index::scan::walk_bundle` skips it:
/// it is the application's own version history, holds thousands of files, and
/// contains no bundle content.
fn sweep_scratch_files(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name == ".git" {
            continue;
        }
        let path = entry.path();
        let is_dir = entry.file_type().is_ok_and(|t| t.is_dir());
        if super::is_scratch_name(&name) {
            let _ = if is_dir {
                std::fs::remove_dir_all(&path)
            } else {
                std::fs::remove_file(&path)
            };
        } else if is_dir {
            sweep_scratch_files(&path);
        }
    }
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
        // Canonicalized (WSPC-D004 review finding #2), so compared against a
        // canonicalized expectation rather than the raw tempdir path — the
        // two coincide unless a path component is a symlink, which this
        // assertion should not assume either way.
        assert_eq!(
            PathBuf::from(&info.local_path),
            std::fs::canonicalize(&workspace_dir).unwrap()
        );
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

        let canonical_path = std::fs::canonicalize(foreign_dir.path()).unwrap();
        let row_count: i64 = conn
            .query_row(
                "SELECT count(*) FROM workspaces WHERE local_path = ?1",
                [canonical_path.to_string_lossy()],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(row_count, 1);
    }

    /// A `SIGKILL` leaves a `.burlmd-trash.*` entry (the full content of a
    /// deleted Note) or an `.{name}.tmp` (a Note mid-write) sitting untracked
    /// inside the bundle, because no `Drop` runs. `commit_all` snapshots the
    /// whole worktree, so the next commit would publish either as plaintext.
    /// Opening the Workspace sweeps both.
    #[test]
    fn opening_a_workspace_sweeps_scratch_files_a_kill_left_behind() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let dir = tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("projects")).unwrap();
        std::fs::write(dir.path().join("Kept.md"), "---\ntitle: Kept\n---\n").unwrap();
        std::fs::write(
            dir.path().join(".burlmd-trash.Deleted.md.4242.0"),
            "the whole content of a deleted Note\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("projects/.burlmd-trash.Nested.md.4242.1"),
            "and another, one level down\n",
        )
        .unwrap();
        std::fs::create_dir_all(dir.path().join(".burlmd-trash.a directory.4242.2")).unwrap();
        std::fs::write(
            dir.path()
                .join(".burlmd-trash.a directory.4242.2/inside.md"),
            "a whole deleted Directory\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("projects/.burlmd.md.4242.0.tmp"),
            "a Note as it was mid-write\n",
        )
        .unwrap();
        // A dot-file that is not ours must survive.
        std::fs::write(dir.path().join(".editorconfig"), "root = true\n").unwrap();

        open_workspace_impl(&conn, dir.path().to_string_lossy().to_string()).unwrap();

        assert!(!dir.path().join(".burlmd-trash.Deleted.md.4242.0").exists());
        assert!(!dir
            .path()
            .join("projects/.burlmd-trash.Nested.md.4242.1")
            .exists());
        assert!(!dir.path().join(".burlmd-trash.a directory.4242.2").exists());
        assert!(!dir.path().join("projects/.burlmd.md.4242.0.tmp").exists());
        assert!(dir.path().join("Kept.md").is_file(), "a Note must survive");
        assert!(
            dir.path().join(".editorconfig").is_file(),
            "a dot-file that is not burlmd's must survive"
        );
    }

    /// The other half: `.gitignore` is the backstop for a scratch file created
    /// *after* the sweep and killed before its own cleanup. It must be written
    /// when the repository is initialized and extended — not clobbered — when
    /// an existing bundle is adopted.
    #[test]
    fn bootstrap_writes_the_scratch_gitignore_and_appends_to_an_existing_one() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());

        let fresh = tempdir().unwrap();
        open_or_create_local_workspace_impl(
            &conn,
            Some(fresh.path().to_string_lossy().to_string()),
        )
        .unwrap();
        let written = std::fs::read_to_string(fresh.path().join(".gitignore")).unwrap();
        for pattern in crate::workspace::SCRATCH_IGNORE_PATTERNS {
            assert!(
                written.lines().any(|line| line.trim() == pattern),
                "{pattern} missing from a freshly initialized bundle's .gitignore: {written:?}"
            );
        }

        let adopted = tempdir().unwrap();
        std::fs::write(adopted.path().join(".gitignore"), "*.pdf\ndrafts/\n").unwrap();
        open_workspace_impl(&conn, adopted.path().to_string_lossy().to_string()).unwrap();
        let extended = std::fs::read_to_string(adopted.path().join(".gitignore")).unwrap();
        assert!(
            extended.starts_with("*.pdf\ndrafts/\n"),
            "the user's own patterns must survive verbatim, got {extended:?}"
        );
        for pattern in crate::workspace::SCRATCH_IGNORE_PATTERNS {
            assert!(
                extended.lines().any(|line| line.trim() == pattern),
                "{pattern} missing after adoption: {extended:?}"
            );
        }

        // Idempotent: a second open must not append the patterns again.
        open_workspace_impl(&conn, adopted.path().to_string_lossy().to_string()).unwrap();
        let twice = std::fs::read_to_string(adopted.path().join(".gitignore")).unwrap();
        assert_eq!(twice, extended, "a repeat open must change nothing");
    }

    /// `flow-workspace-bootstrap.md`'s fourth post-condition: the bundle is
    /// indexed. Adopting a foreign bundle must populate `notes`, `directories`
    /// and `links` — the tree, search and the graph all read from those, and a
    /// `WSPC-D006` rename seeds its affected set from `links`, so an unindexed
    /// bundle renames a Note and leaves every inbound Link pointing at the
    /// concept the rename removed (`architecture/risks.md` risk 8).
    #[test]
    fn open_workspace_indexes_the_bundle_it_adopts() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let foreign_dir = tempdir().unwrap();
        std::fs::create_dir_all(foreign_dir.path().join("projects")).unwrap();
        std::fs::write(
            foreign_dir.path().join("Welcome.md"),
            "---\ntype: Note\ntitle: Welcome\n---\n\nSee [Burlmd](</projects/burlmd.md>).\n",
        )
        .unwrap();
        std::fs::write(
            foreign_dir.path().join("projects/burlmd.md"),
            "---\ntype: Note\ntitle: Burlmd\n---\n\nA distinctive antidisestablishmentarian body.\n",
        )
        .unwrap();

        let info = open_workspace_impl(&conn, foreign_dir.path().to_string_lossy().to_string())
            .expect("adopting a foreign directory should succeed");

        let note_ids: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([&info.id], |row| row.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows
        };
        assert_eq!(
            note_ids,
            vec!["Welcome".to_string(), "projects/burlmd".to_string()],
            "every Note in an adopted bundle must be indexed"
        );

        let directories: i64 = conn
            .query_row(
                "SELECT count(*) FROM directories WHERE workspace_id = ?1 AND id = 'projects'",
                [&info.id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(directories, 1, "the tree renders from `directories`");

        let (source, target): (String, String) = conn
            .query_row(
                "SELECT source_id, target_id FROM links WHERE workspace_id = ?1",
                [&info.id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(
            (source.as_str(), target.as_str()),
            ("Welcome", "projects/burlmd")
        );

        let searchable: i64 = conn
            .query_row(
                "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?1",
                ["antidisestablishmentarian"],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(searchable, 1, "an adopted bundle must be searchable");
    }

    /// The other entry point converges on the same post-condition, including
    /// on a **reopen**: a reused `workspaces` row says nothing about whether
    /// the files under it still match the index, since another tool may have
    /// changed them while the application was not running.
    #[test]
    fn a_reopen_reindexes_changes_another_tool_made_while_the_app_was_closed() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let path = workspace_dir.path().to_string_lossy().to_string();
        std::fs::write(
            workspace_dir.path().join("First.md"),
            "---\ntype: Note\ntitle: First\n---\n\nBody.\n",
        )
        .unwrap();

        let first = open_or_create_local_workspace_impl(&conn, Some(path.clone())).unwrap();

        // Something else edits the bundle between the two opens.
        std::fs::remove_file(workspace_dir.path().join("First.md")).unwrap();
        std::fs::write(
            workspace_dir.path().join("Second.md"),
            "---\ntype: Note\ntitle: Second\n---\n\nBody.\n",
        )
        .unwrap();

        let second = open_or_create_local_workspace_impl(&conn, Some(path)).unwrap();

        assert_eq!(first.id, second.id);
        let note_ids: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT id FROM notes WHERE workspace_id = ?1 ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([&second.id], |row| row.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows
        };
        assert_eq!(note_ids, vec!["Second".to_string()]);
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

    /// WSPC-D004 review finding #1: `open_workspace` must not create the
    /// directory it's pointed at — a typo, an unmounted volume, or a stale
    /// recent-Workspace entry must be reported rather than silently
    /// producing a fresh empty Workspace that shadows the real bundle.
    #[test]
    fn open_workspace_errors_and_creates_nothing_when_the_directory_is_absent() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let parent = tempdir().unwrap();
        let missing = parent.path().join("does-not-exist");
        assert!(!missing.exists());

        let result = open_workspace_impl(&conn, missing.to_string_lossy().to_string());

        assert!(
            matches!(result, Err(AppError::NotFound(_))),
            "expected NotFound, got {result:?}"
        );
        assert!(
            !missing.exists(),
            "open_workspace must not create the directory it failed to find"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(
            count, 0,
            "no Workspace row may be written for a missing directory"
        );
    }

    /// WSPC-D004 review finding #2: `local_path` has no `UNIQUE` constraint,
    /// so the reuse-on-repeat-open behavior depends entirely on every caller
    /// agreeing on one spelling of the same directory. A trailing slash must
    /// not be enough to mint a second row for the same bundle.
    #[test]
    fn a_trailing_slash_spelling_of_the_same_directory_reuses_the_same_row() {
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_dir = tempdir().unwrap();
        let bare = workspace_dir.path().to_string_lossy().to_string();
        let with_trailing_slash = format!("{bare}/");

        let first = open_or_create_local_workspace_impl(&conn, Some(bare)).unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some(with_trailing_slash)).unwrap();

        assert_eq!(
            first.id, second.id,
            "a trailing-slash spelling of the same directory must reuse the row"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    /// WSPC-D004 review finding #2, the other spelling: a relative path to
    /// the same directory must also reuse the row rather than minting a
    /// second one that splits the bundle's index across two Workspace ids
    /// (ADR-005 decision 7). Mutates the process's current directory, so
    /// this holds `ENV_LOCK` for its whole duration — the same process-wide
    /// mutable state `EnvVarGuard`'s callers serialize on, per
    /// `db::connection::ENV_LOCK`'s doc comment.
    #[test]
    fn a_relative_spelling_of_the_same_directory_reuses_the_same_row() {
        let _guard = ENV_LOCK.lock().unwrap();
        let index_dir = tempdir().unwrap();
        let conn = test_index(index_dir.path());
        let workspace_parent = tempdir().unwrap();
        let workspace_dir = workspace_parent.path().join("ws");
        std::fs::create_dir_all(&workspace_dir).unwrap();

        let original_cwd = std::env::current_dir().unwrap();
        std::env::set_current_dir(workspace_parent.path()).unwrap();
        let first = open_or_create_local_workspace_impl(
            &conn,
            Some(workspace_dir.to_string_lossy().to_string()),
        )
        .unwrap();
        let second = open_or_create_local_workspace_impl(&conn, Some("ws".to_string())).unwrap();
        std::env::set_current_dir(original_cwd).unwrap();

        assert_eq!(
            first.id, second.id,
            "a relative spelling of the same directory must reuse the row"
        );
        let count: i64 = conn
            .query_row("SELECT count(*) FROM workspaces", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
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
