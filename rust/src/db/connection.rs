use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use rusqlite::Connection;
use zeroize::Zeroizing;

use crate::error::AppError;
use crate::security::keyring::get_or_create_root_key;

impl From<rusqlite::Error> for AppError {
    fn from(e: rusqlite::Error) -> Self {
        AppError::DatabaseError(e.to_string())
    }
}

/// Opens (creating if absent) the SQLCipher-encrypted local index at `path`
/// and unlocks it with the root key from the OS Keychain.
pub fn open_encrypted_db(path: &Path) -> Result<Connection, AppError> {
    let key = get_or_create_root_key()?;
    open_encrypted_db_with_key(path, &*key)
}

/// Opens (creating if absent) the SQLCipher-encrypted local index at `path`
/// and unlocks it with the supplied raw 256-bit `key`. Split out from
/// [`open_encrypted_db`] so callers (namely tests) can inject a throwaway
/// key instead of going through the OS Keychain. `pub(crate)` rather than
/// private so `workspace::bootstrap`'s tests can open a real, on-disk
/// SQLCipher file without going through the process-wide singleton or the
/// OS Keychain — the same reason `db::connection`'s own tests use it.
///
/// `PRAGMA key` must be the first statement executed on a freshly opened
/// connection, before any schema access — SQLCipher defers key validation
/// until the first real page read, so this function forces one immediately
/// to surface a bad/missing key here rather than on the caller's first
/// query. The key is applied in its raw-hex form (`x'<64 hex chars>'`),
/// which sets the 32 encryption key bytes directly with no KDF applied —
/// appropriate because the key is already full-entropy CSPRNG output, not a
/// low-entropy human passphrase that would benefit from SQLCipher's
/// passphrase-mode PBKDF2 derivation.
///
/// Immediately after the key pragma — before the unlock probe touches
/// `sqlite_master` and before any statement that touches a user table —
/// this also issues the two other connection-time obligations
/// `guidelines.md` states: `PRAGMA foreign_keys = ON` (SQLite defaults it
/// off and does not persist it in the file, so every connection must set it
/// itself; every `ON UPDATE CASCADE` in `schema.sql` is inert without it),
/// and `journal_mode = WAL` / `synchronous = NORMAL` per
/// `SPK-WSPC-D001.md` §7: worth roughly 2.3-3.3x on a tier-1 draft write
/// around 100KiB by removing the rollback journal's double write and two of
/// three per-commit `fsync` calls — a real but size-dependent win, not a fix
/// for tier 1's own cost, which is worth little at 1MiB and remains
/// `WSPC-D007`'s problem to carry. `schema.sql` also states `PRAGMA
/// foreign_keys = ON` as its first statement, but that alone is not
/// sufficient: `init_schema` does not run on every path that reaches a
/// connection (this function is reachable without it), so the pragma is
/// issued here too, unconditionally.
pub(crate) fn open_encrypted_db_with_key(path: &Path, key: &[u8]) -> Result<Connection, AppError> {
    let conn = Connection::open(path)?;

    // Written directly into a pre-sized `Zeroizing<String>` via `write!`
    // rather than `key.iter().map(|b| format!(...)).collect::<String>()`:
    // the latter allocates a transient, un-zeroized `String` per key byte
    // (plus `collect`'s own growing-buffer reallocations), each holding
    // key-derived hex and dropped without being wiped. A single pre-sized
    // buffer means there's exactly one hex-key allocation, and it's the one
    // already wrapped in `Zeroizing` below.
    let mut hex_key = Zeroizing::new(String::with_capacity(key.len() * 2));
    for byte in key {
        write!(hex_key, "{byte:02x}").expect("writing to a String cannot fail");
    }
    // PRAGMA statements don't accept bound parameters; `hex_key` is locally
    // generated 64-hex-char data, not attacker-controlled input, so this
    // string interpolation carries no injection risk. Both the hex encoding
    // and the assembled PRAGMA statement are wrapped in `Zeroizing` so the
    // key material is wiped from memory on drop, matching the discipline
    // already applied to it in `security::keyring`.
    let pragma = Zeroizing::new(format!("PRAGMA key = \"x'{}'\";", *hex_key));
    conn.execute_batch(&pragma)?;

    conn.execute_batch(
        "PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;",
    )?;

    conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
        row.get::<_, i64>(0)
    })
    .map_err(|e| AppError::CryptoError(format!("failed to unlock database: {e}")))?;

    Ok(conn)
}

const SCHEMA: &str = include_str!("schema.sql");

/// Applies `schema.sql` to `conn`. Idempotent — every statement is
/// `CREATE TABLE IF NOT EXISTS` / `CREATE VIRTUAL TABLE IF NOT EXISTS`.
///
/// `schema.sql` deliberately carries no `PRAGMA user_version = ...`
/// statement, because this function replays the whole batch on every open —
/// a literal assignment baked into the batch would silently reset a
/// migrated database's version back to the baseline every time it was
/// reopened. Instead, the version is handled here, outside the replayed
/// batch: read first, and written to `1` only when it still reads `0`, i.e.
/// on a freshly created file. A database whose `user_version` already
/// reads something other than `0` — because a future migration has run — is
/// left exactly as it is.
pub fn init_schema(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch(SCHEMA)?;

    let user_version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if user_version == 0 {
        conn.execute_batch("PRAGMA user_version = 1;")?;
    }

    Ok(())
}

/// Opens the encrypted local index at `path` (via the OS Keychain root key)
/// and ensures the schema is applied. The one entry point application code
/// should use to get a ready-to-query connection.
pub fn open_and_initialize(path: &Path) -> Result<Connection, AppError> {
    let conn = open_encrypted_db(path)?;
    init_schema(&conn)?;
    Ok(conn)
}

static DB: OnceLock<Mutex<Connection>> = OnceLock::new();
// Serializes *initialization* only (not per-query access, which goes through
// the `Mutex<Connection>` inside `DB` once it's set). Without this, two
// threads racing to be the first caller of `connection()` could both open
// the same SQLCipher file and run `init_schema` concurrently; SQLite's
// default busy_timeout is 0, so the loser would surface a spurious
// `SQLITE_BUSY` error instead of just losing the (harmless) `DB.set` race.
static INIT_LOCK: Mutex<()> = Mutex::new(());

/// Resolves the base data directory `$XDG_DATA_HOME` falls back to when
/// unset: `~/.local/share` on Linux, `~/Library/Application Support` on
/// macOS (`guidelines.md` "Workspace location"). Shared by this module's
/// default index path and `workspace::bootstrap::default_workspace_dir`,
/// which resolve to siblings under the same `burlmd/` parent — the index is
/// derived state and lives outside the bundle it indexes, not within it.
pub(crate) fn xdg_data_home() -> Result<PathBuf, AppError> {
    if let Ok(dir) = std::env::var("XDG_DATA_HOME") {
        if !dir.is_empty() {
            return Ok(PathBuf::from(dir));
        }
    }
    let home =
        std::env::var("HOME").map_err(|_| AppError::IoError("HOME is not set".to_string()))?;
    let home = PathBuf::from(home);
    if cfg!(target_os = "macos") {
        Ok(home.join("Library").join("Application Support"))
    } else {
        Ok(home.join(".local").join("share"))
    }
}

/// Resolves the default encrypted index path: `$XDG_DATA_HOME/burlmd/index.sqlite3`
/// (with the fallbacks `xdg_data_home` documents), overridable via
/// `BURLMD_DB_PATH` for tests. This replaces the placeholder
/// `$HOME/.burlmd/index.sqlite3` location Epic B carried before any
/// Workspace path existed: that old path is a stale, un-migrated location
/// under a path `guidelines.md` no longer names, and this function never
/// reads or references it — an index file left there by a development build
/// is neither opened, migrated, nor copied (`WSPC-D004`'s STOP condition).
pub(crate) fn default_db_path() -> Result<PathBuf, AppError> {
    if let Ok(p) = std::env::var("BURLMD_DB_PATH") {
        return Ok(PathBuf::from(p));
    }
    let dir = xdg_data_home()?.join("burlmd");
    std::fs::create_dir_all(&dir).map_err(|e| AppError::IoError(e.to_string()))?;
    Ok(dir.join("index.sqlite3"))
}

/// Process-wide encrypted DB connection, lazily opened (and schema-initialized)
/// on first use. `BURLMD_DB_PATH` overrides the default
/// `$XDG_DATA_HOME/burlmd/index.sqlite3` location.
///
/// `OnceLock::get_or_try_init` is unstable on this project's pinned toolchain, so
/// fallible init is done manually via double-checked locking: concurrent callers
/// block on `INIT_LOCK` (rather than racing to open the same file) until the
/// first one finishes, then all observe `DB.get()` returning `Some`.
pub fn connection() -> Result<&'static Mutex<Connection>, AppError> {
    if let Some(db) = DB.get() {
        return Ok(db);
    }

    let _init_guard = INIT_LOCK
        .lock()
        .map_err(|_| AppError::DatabaseError("db init lock poisoned".to_string()))?;

    // Re-check: another thread may have finished initializing while we were
    // waiting for the lock.
    if let Some(db) = DB.get() {
        return Ok(db);
    }

    let conn = open_and_initialize(&default_db_path()?)?;
    let _ = DB.set(Mutex::new(conn));
    Ok(DB.get().expect("DB was just set while holding INIT_LOCK"))
}

/// Acquires the process-wide connection and runs `f` against it, so each
/// FFI function needing the DB doesn't repeat the "get the singleton, lock
/// it, map a poisoned-lock error" preamble.
pub fn with_connection<T>(
    f: impl FnOnce(&Connection) -> Result<T, AppError>,
) -> Result<T, AppError> {
    let db = connection()?;
    let conn = db
        .lock()
        .map_err(|_| AppError::DatabaseError("db mutex poisoned".to_string()))?;
    f(&conn)
}

/// The id of the Workspace established by the most recent successful
/// `open_or_create_local_workspace` or `open_workspace` call in this
/// process (ADR-005 decision 7: "Exactly one Workspace is active at a time,
/// and the Core owns which one" — no function in `contracts/ffi_api.rs`
/// takes a `workspace_id`; every call is implicitly scoped to this one).
/// Deliberately kept next to [`DB`] rather than in `api::ffi_api` or
/// `workspace`: it is process-wide singleton state of exactly the same
/// shape, set once bootstrap succeeds and read by every later Note-level
/// query: `reindex_workspace`, every open session lookup, and the discovery
/// and graph reads `search_notes`/`find_notes_by_title`/`link_completions`/
/// `backlinks`/`workspace_tree` directly; the Note and Directory lifecycle
/// operations indirectly, via `workspace::persist::Workspace::active`
/// (WSPC-D004 review finding #4, extended by WSPC-D005/D006/D009).
static ACTIVE_WORKSPACE: Mutex<Option<String>> = Mutex::new(None);

/// Records `id` as the active Workspace. Called by
/// `api::ffi_api::open_or_create_local_workspace` and
/// `api::ffi_api::open_workspace` after a successful bootstrap — not by
/// `workspace::bootstrap`'s own `_impl` functions, which are exercised
/// directly against an injected `Connection` in hermetic tests and must
/// never touch this process-wide cell (doing so would leak one test's
/// active Workspace into another's).
pub(crate) fn set_active_workspace_id(id: String) -> Result<(), AppError> {
    let mut guard = ACTIVE_WORKSPACE
        .lock()
        .map_err(|_| AppError::DatabaseError("active workspace lock poisoned".to_string()))?;
    *guard = Some(id);
    Ok(())
}

/// Resets [`ACTIVE_WORKSPACE`] to unset. Test-only, and deliberately not the
/// production-path inverse of [`set_active_workspace_id`] — nothing in
/// `contracts/ffi_api.rs` ever un-sets the active Workspace, so this exists
/// solely so a test that set the cell can leave it exactly as it found it,
/// the way `active_workspace_id_reports_the_id_a_bootstrap_call_established`
/// already did inline before `WSPC-D008`'s wrapper-layer tests in
/// `api::ffi_api` needed the same cleanup from a different module, where
/// `ACTIVE_WORKSPACE` itself is not visible. Every caller must hold
/// [`WORKSPACE_TEST_LOCK`] for as long as the reset matters, or a
/// concurrently running test that just set the cell to its own id can have
/// that id cleared out from under it.
#[cfg(test)]
pub(crate) fn clear_active_workspace_id_for_test() {
    let mut guard = ACTIVE_WORKSPACE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *guard = None;
}

/// The active Workspace's id, or `AppError::NotFound` when no
/// `open_or_create_local_workspace`/`open_workspace` call has succeeded yet
/// in this process. Every Note-level FFI function is implicitly scoped to
/// this id (ADR-005 decision 7); see [`set_active_workspace_id`].
pub(crate) fn active_workspace_id() -> Result<String, AppError> {
    let guard = ACTIVE_WORKSPACE
        .lock()
        .map_err(|_| AppError::DatabaseError("active workspace lock poisoned".to_string()))?;
    guard
        .clone()
        .ok_or_else(|| AppError::NotFound("no Workspace is open".to_string()))
}

/// Serializes every test **in this crate** that mutates process-global
/// environment state via `std::env::set_var`/`remove_var` (or, in
/// `workspace::bootstrap`'s relative-path tests, `std::env::set_current_dir`)
/// — not only `HOME`/`XDG_DATA_HOME`/`BURLMD_DB_PATH` here and in
/// `workspace::bootstrap`'s tests, but also `git::operations`'s
/// `GIT_CONFIG_*` env-injection tests. It has to be the *one* lock, not one
/// per module: `std::env::set_var` mutates a single process-wide table, and
/// concurrent `set_var` calls to *different* keys from different threads can
/// still race at the libc level (`setenv` may reallocate the shared
/// `environ` array), so a per-module lock would only prevent same-key races,
/// not this one. WSPC-D004 review finding #5.
///
/// What this lock does **not** claim: it does not serialize against the
/// many tests elsewhere in this crate that spawn a real child process (a
/// `git` CLI invocation via `Command::output()`) without holding it. Making
/// every such test acquire this lock would serialize most of the test
/// binary for no correctness benefit, because none of those tests mutate
/// env vars or depend on inherited ambient ones — every `Command` this crate
/// builds sets the environment variables it cares about explicitly via
/// `Command::env`, never by reading process env at spawn time. This lock's
/// real guarantee is narrower and is the one that matters: no two of *this
/// crate's own* `std::env::set_var`/`remove_var`/`set_current_dir` calls,
/// across every module, are ever in flight at the same time.
#[cfg(test)]
pub(crate) static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Serializes every test **in this crate** that touches [`ACTIVE_WORKSPACE`]
/// or drives the real `#[frb]` wrapper functions in `api::ffi_api` that
/// resolve against it (`workspace::persist::Workspace::active`, and
/// therefore `open_note`/`pending_drafts`) — the same shape of hazard
/// [`ENV_LOCK`] closes for environment variables, for the same reason: the
/// cell is a single process-wide slot, not one per test, so two tests
/// setting it concurrently race on which value the other observes.
///
/// This is a separate lock from `ENV_LOCK` rather than a broadened use of it,
/// because a caller of `api::ffi_api`'s wrapper-layer tests also needs
/// `BURLMD_DB_PATH` held stable for the *first* call to [`connection`] in the
/// process — that first call is also the one and only place those tests
/// touch the real OS Keychain via [`crate::security::keyring`], since
/// [`open_encrypted_db`] has no test-key injection point the way
/// [`open_encrypted_db_with_key`] does. A caller needing both locks takes
/// `ENV_LOCK` first, then this one — the order [`api::ffi_api`]'s
/// wrapper-layer tests use — and no code in this crate acquires them in the
/// opposite order, so that order is not merely a convention but the only one
/// ever exercised.
#[cfg(test)]
pub(crate) static WORKSPACE_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// RAII guard that saves an environment variable's original value on
/// construction and restores it (or removes it, if it was originally unset)
/// on drop — so a test overriding `HOME`/`XDG_DATA_HOME`/`BURLMD_DB_PATH` can
/// never leak a bogus value (e.g. a since-deleted tempdir path) into a later
/// test that doesn't hold [`ENV_LOCK`] at all.
#[cfg(test)]
pub(crate) struct EnvVarGuard {
    key: &'static str,
    original: Option<String>,
}

#[cfg(test)]
impl EnvVarGuard {
    pub(crate) fn set(key: &'static str, value: &std::ffi::OsStr) -> Self {
        let original = std::env::var(key).ok();
        // SAFETY: every caller holds `ENV_LOCK` for the guard's whole
        // lifetime, and every `set_var`/`remove_var` call anywhere in this
        // crate's test suite goes through the same lock (see `ENV_LOCK`'s
        // own doc comment for the precise scope of that guarantee), so this
        // call can never race another mutation of process env from within
        // this crate's own tests.
        unsafe {
            std::env::set_var(key, value);
        }
        Self { key, original }
    }

    pub(crate) fn unset(key: &'static str) -> Self {
        let original = std::env::var(key).ok();
        // SAFETY: see `set` above.
        unsafe {
            std::env::remove_var(key);
        }
        Self { key, original }
    }
}

#[cfg(test)]
impl Drop for EnvVarGuard {
    fn drop(&mut self) {
        // SAFETY: see `set` above; the guard's own construction already
        // established that `ENV_LOCK` is held for this whole scope.
        unsafe {
            match &self.original {
                Some(v) => std::env::set_var(self.key, v),
                None => std::env::remove_var(self.key),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::io::Read;

    use super::*;

    #[test]
    fn database_file_is_encrypted_at_rest_and_unreadable_without_the_key() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("index.sqlite3");
        // A throwaway key, not the real OS Keychain entry — keeps this test
        // hermetic and independent of a live Secret Service being available.
        let key = [0x42u8; 32];

        {
            let conn = open_encrypted_db_with_key(&path, &key).unwrap();
            conn.execute_batch("CREATE TABLE t (x INTEGER);").unwrap();
        } // drop closes the connection, forcing a flush

        // Raw on-disk bytes must not start with SQLite's plaintext magic header.
        let mut buf = [0u8; 16];
        std::fs::File::open(&path)
            .unwrap()
            .read_exact(&mut buf)
            .unwrap();
        assert_ne!(&buf, b"SQLite format 3\0");

        // Re-opening without PRAGMA key must fail to read — the programmatic
        // equivalent of "cannot be opened by standard sqlite3 CLI".
        let unkeyed = Connection::open(&path).unwrap();
        let result = unkeyed.query_row("SELECT count(*) FROM sqlite_master", [], |r| {
            r.get::<_, i64>(0)
        });
        let err = result.expect_err("unkeyed read of an encrypted file must fail");
        assert_eq!(
            err.sqlite_error_code(),
            Some(rusqlite::ErrorCode::NotADatabase),
            "expected SQLITE_NOTADB, got: {err}"
        );
    }

    fn open_test_db() -> (tempfile::TempDir, Connection) {
        let dir = tempfile::tempdir().unwrap();
        let key = [0x24u8; 32]; // throwaway key, keeps the test hermetic
        let conn = open_encrypted_db_with_key(&dir.path().join("index.sqlite3"), &key).unwrap();
        (dir, conn)
    }

    #[test]
    fn schema_creates_notes_and_notes_fts_tables() {
        let (_dir, conn) = open_test_db();
        init_schema(&conn).unwrap();

        let count: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('notes','notes_fts')",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 2); // literal Gherkin assertion

        // Stricter than the literal Gherkin: verify all 7 tables exist.
        let all: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN \
                 ('workspaces','notes','links','notes_fts','fts_mapping','drafts','directories')",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(all, 7);
    }

    #[test]
    fn schema_application_is_idempotent() {
        let (_dir, conn) = open_test_db();
        init_schema(&conn).unwrap();
        init_schema(&conn).unwrap(); // must not error on a second application
    }

    #[test]
    fn schema_sets_a_baseline_user_version_for_future_migrations_to_branch_on() {
        let (_dir, conn) = open_test_db();
        init_schema(&conn).unwrap();

        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, 1);
    }

    /// WSPC-D004: `PRAGMA foreign_keys` must report enabled on any freshly
    /// opened connection, not only one that has also run `init_schema` —
    /// `open_encrypted_db_with_key` is reachable without it (`guidelines.md`).
    #[test]
    fn foreign_keys_pragma_is_enabled_on_any_freshly_opened_connection() {
        let (_dir, conn) = open_test_db();
        // Deliberately no `init_schema` call: the pragma must already be on
        // from `open_encrypted_db_with_key` alone.
        let enabled: i64 = conn
            .query_row("PRAGMA foreign_keys", [], |r| r.get(0))
            .unwrap();
        assert_eq!(enabled, 1, "foreign key enforcement must be on by default");
    }

    /// WSPC-D004 / SPK-WSPC-D001 §7: WAL plus `synchronous = NORMAL` belongs
    /// on every connection, alongside the other connection-time obligations.
    #[test]
    fn journal_mode_is_wal_and_synchronous_is_normal_on_a_freshly_opened_connection() {
        let (_dir, conn) = open_test_db();
        let journal_mode: String = conn
            .query_row("PRAGMA journal_mode", [], |r| r.get(0))
            .unwrap();
        assert_eq!(journal_mode.to_lowercase(), "wal");

        let synchronous: i64 = conn
            .query_row("PRAGMA synchronous", [], |r| r.get(0))
            .unwrap();
        // SQLite reports `synchronous` numerically: 0=OFF, 1=NORMAL, 2=FULL.
        assert_eq!(synchronous, 1, "expected NORMAL (1)");
    }

    /// WSPC-D004: a `user_version` that already reads something other than
    /// `0` — i.e. a database a future migration has already touched — must
    /// be left exactly as it is when `init_schema` replays the batch again,
    /// rather than being reset to the baseline `1`.
    #[test]
    fn schema_batch_replay_leaves_a_nonzero_user_version_untouched() {
        let (_dir, conn) = open_test_db();
        init_schema(&conn).unwrap();
        conn.execute_batch("PRAGMA user_version = 7;").unwrap();

        init_schema(&conn).unwrap(); // replays the batch again

        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, 7, "a non-zero user_version must not be reset");
    }

    /// WSPC-D004 review finding #3: after a bootstrap call succeeds,
    /// [`active_workspace_id`] must report the id of the row that call
    /// established. `set_active_workspace_id` is exercised directly here
    /// (mirroring what `api::ffi_api`'s bootstrap wrappers do on success)
    /// rather than through the real `#[frb]` entry points, which would pull
    /// in the process-wide `DB` singleton and the OS Keychain — the same
    /// reason `workspace::bootstrap`'s own tests inject a `Connection`
    /// instead of going through `connection()`.
    #[test]
    fn active_workspace_id_reports_the_id_a_bootstrap_call_established() {
        // `ACTIVE_WORKSPACE` is process-wide state shared by the whole test
        // binary. `api::ffi_api`'s wrapper-layer tests (`WSPC-D008`) also set
        // it now, through the real `#[frb]` functions, so this held lock is
        // what keeps the assertion below — "no Workspace has been
        // established yet" — from racing whichever of them runs first.
        let _guard = WORKSPACE_TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);

        assert!(
            active_workspace_id().is_err(),
            "no Workspace has been established yet in a process that hasn't called \
             set_active_workspace_id"
        );

        let index_dir = tempfile::tempdir().unwrap();
        let key = [0x55u8; 32];
        let conn =
            open_encrypted_db_with_key(&index_dir.path().join("index.sqlite3"), &key).unwrap();
        init_schema(&conn).unwrap();
        let workspace_dir = tempfile::tempdir().unwrap();
        let info = crate::workspace::bootstrap::open_or_create_local_workspace_impl(
            &conn,
            Some(workspace_dir.path().to_string_lossy().to_string()),
        )
        .unwrap();

        set_active_workspace_id(info.id.clone()).unwrap();

        assert_eq!(active_workspace_id().unwrap(), info.id);

        // Leave it as this test found it (unset) rather than relying on the
        // lock alone to protect a later test that doesn't expect a stale
        // value.
        *ACTIVE_WORKSPACE.lock().unwrap() = None;
    }

    /// WSPC-D004: with `XDG_DATA_HOME` unset, the default index path falls
    /// back through `HOME`, matching `guidelines.md`'s stated fallback
    /// (`~/.local/share/burlmd/index.sqlite3` on this platform).
    #[test]
    fn xdg_data_home_prefers_the_env_var_and_falls_back_to_home() {
        let _guard = ENV_LOCK.lock().unwrap();
        let fake_home = tempfile::tempdir().unwrap();
        let _home = EnvVarGuard::set("HOME", fake_home.path().as_os_str());
        let _no_xdg = EnvVarGuard::unset("XDG_DATA_HOME");
        let _no_override = EnvVarGuard::unset("BURLMD_DB_PATH");

        let resolved = xdg_data_home().unwrap();
        if cfg!(target_os = "macos") {
            assert_eq!(
                resolved,
                fake_home.path().join("Library").join("Application Support")
            );
        } else {
            assert_eq!(resolved, fake_home.path().join(".local").join("share"));
        }

        let explicit_xdg = tempfile::tempdir().unwrap();
        let _with_xdg = EnvVarGuard::set("XDG_DATA_HOME", explicit_xdg.path().as_os_str());
        assert_eq!(xdg_data_home().unwrap(), explicit_xdg.path());
    }

    /// WSPC-D004 STOP condition: an index file at the old
    /// `$HOME/.burlmd/index.sqlite3` placeholder path must be neither
    /// opened, migrated, nor copied. `default_db_path` must resolve
    /// somewhere else entirely, and the legacy file's bytes must be left
    /// completely untouched by resolving it.
    #[test]
    fn default_db_path_never_reads_or_touches_the_legacy_home_burlmd_path() {
        let _guard = ENV_LOCK.lock().unwrap();
        let fake_home = tempfile::tempdir().unwrap();
        let _home = EnvVarGuard::set("HOME", fake_home.path().as_os_str());
        let _no_xdg = EnvVarGuard::unset("XDG_DATA_HOME");
        let _no_override = EnvVarGuard::unset("BURLMD_DB_PATH");

        let legacy_dir = fake_home.path().join(".burlmd");
        std::fs::create_dir_all(&legacy_dir).unwrap();
        let legacy_path = legacy_dir.join("index.sqlite3");
        let legacy_bytes = b"not a real database, must never be touched";
        std::fs::write(&legacy_path, legacy_bytes).unwrap();

        let resolved = default_db_path().unwrap();

        assert_ne!(
            resolved, legacy_path,
            "the resolved index path must not be the legacy $HOME/.burlmd path"
        );
        assert!(
            !resolved.starts_with(&legacy_dir),
            "the resolved index path must not live under the legacy directory either"
        );

        let bytes_after = std::fs::read(&legacy_path).unwrap();
        assert_eq!(
            bytes_after, legacy_bytes,
            "resolving the default path must not read, open, or modify the legacy file"
        );
    }
}
