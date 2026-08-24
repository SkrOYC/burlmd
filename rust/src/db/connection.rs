use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use rusqlite::{Connection, Transaction, TransactionBehavior};
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
const CURRENT_SCHEMA_VERSION: i64 = 2;

/// Applies `schema.sql` to `conn`. Idempotent — every statement is
/// `CREATE TABLE IF NOT EXISTS` / `CREATE VIRTUAL TABLE IF NOT EXISTS`.
///
/// `schema.sql` deliberately carries no `PRAGMA user_version = ...`
/// statement, because this function replays the whole batch on every open —
/// a literal assignment baked into the batch would silently reset a migrated
/// database's version back to the baseline every time it was reopened.
///
/// Version 2 adds the Unicode title lookup key for the prefix queries that
/// power Find and Link completion. Unlike a fresh index, a v1 index already
/// has a `notes` table, so `CREATE TABLE IF NOT EXISTS` cannot add the new
/// column: it must be migrated and backfilled before the v2 index exists.
///
/// Schema creation and version publication share one immediate SQLite
/// transaction. In particular, `user_version = 0` does not prove that a file
/// is empty: an earlier build could have crashed after creating the complete
/// v1 schema but before writing its version. The version-zero branch therefore
/// recognizes the recoverable v1/v2 shapes rather than replaying v2 DDL into a
/// v1 `notes` table. Any later version remains untouched so a future migration
/// can own it.
pub fn init_schema(conn: &Connection) -> Result<(), AppError> {
    // `schema.sql` contains this too, but a PRAGMA inside the immediate
    // creation/migration transaction cannot change SQLite's per-connection
    // setting. Keep direct in-memory callers correct as well as connections
    // opened through `open_encrypted_db_with_key`.
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;

    let user_version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    match user_version {
        0 => recover_version_zero_schema(conn)?,
        1 => migrate_v1_to_v2(conn)?,
        _ => conn.execute_batch(SCHEMA)?,
    }

    Ok(())
}

/// Recovers a database which still reports version zero. The only
/// deterministically recoverable partial creation state is the schema's first
/// table (`workspaces`) without `notes`; once `notes` exists, its columns
/// distinguish a complete/partial v1 schema from a complete/partial v2 schema.
/// Other version-zero shapes are not ours to guess at and are rejected before
/// this initializer writes to them.
fn recover_version_zero_schema(conn: &Connection) -> Result<(), AppError> {
    let transaction = Transaction::new_unchecked(conn, TransactionBehavior::Immediate)?;
    let table_names = user_table_names(&transaction)?;

    if !table_names.iter().any(|name| name == "notes") {
        if table_names.is_empty() || (table_names.len() == 1 && table_names[0] == "workspaces") {
            apply_current_schema(&transaction)?;
        } else {
            return Err(AppError::DatabaseError(format!(
                "cannot recover version-zero database with no notes table and tables: {}",
                table_names.join(", ")
            )));
        }
    } else {
        let columns = note_column_names(&transaction)?;
        if has_all_columns(&columns, V2_NOTE_COLUMNS) {
            // The previous creation may have stopped after the v2 notes table
            // was committed. Replaying idempotent DDL completes any missing
            // tables/indexes before publishing the version.
            apply_current_schema(&transaction)?;
        } else if has_all_columns(&columns, V1_NOTE_COLUMNS)
            && !columns.iter().any(|column| column == "title_lookup_key")
        {
            migrate_v1_to_v2_in_transaction(&transaction)?;
        } else {
            return Err(AppError::DatabaseError(format!(
                "cannot recover unrecognized version-zero notes schema with columns: {}",
                columns.join(", ")
            )));
        }
    }

    transaction.commit()?;
    Ok(())
}

const V1_NOTE_COLUMNS: &[&str] = &[
    "id",
    "workspace_id",
    "path",
    "title",
    "last_modified",
    "content_hash",
    "okf_conformant",
];
const V2_NOTE_COLUMNS: &[&str] = &[
    "id",
    "workspace_id",
    "path",
    "title",
    "title_lookup_key",
    "last_modified",
    "content_hash",
    "okf_conformant",
];

fn user_table_names(conn: &Connection) -> Result<Vec<String>, AppError> {
    let mut statement = conn.prepare(
        "SELECT name FROM sqlite_master \
         WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )?;
    let rows = statement.query_map([], |row| row.get(0))?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

fn note_column_names(conn: &Connection) -> Result<Vec<String>, AppError> {
    let mut statement = conn.prepare("PRAGMA table_info(notes)")?;
    let rows = statement.query_map([], |row| row.get(1))?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

fn has_all_columns(columns: &[String], required: &[&str]) -> bool {
    required
        .iter()
        .all(|required_column| columns.iter().any(|column| column == required_column))
}

/// Creates any missing v2 objects and publishes the matching version. The
/// caller owns the transaction so DDL, backfill, and version publication are
/// indivisible.
fn apply_current_schema(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch(SCHEMA)?;
    conn.execute_batch(&format!("PRAGMA user_version = {CURRENT_SCHEMA_VERSION};"))?;
    Ok(())
}

/// Adds and fills the v2 normalized, full-Unicode case-folded title lookup
/// key. This is one SQLite transaction: a crash or failure cannot leave a v1
/// index claiming v2 while any row still has no key.
fn migrate_v1_to_v2(conn: &Connection) -> Result<(), AppError> {
    let transaction = Transaction::new_unchecked(conn, TransactionBehavior::Immediate)?;
    migrate_v1_to_v2_in_transaction(&transaction)?;
    transaction.commit()?;
    Ok(())
}

fn migrate_v1_to_v2_in_transaction(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch("ALTER TABLE notes ADD COLUMN title_lookup_key TEXT NOT NULL DEFAULT '';")?;
    // A full v1 file already has these objects, but a crash may have left a
    // prefix of the old DDL behind. Complete the v2 DDL while this transaction
    // is still open; the lookup index is therefore never published without its
    // backing column.
    conn.execute_batch(SCHEMA)?;

    let mut select = conn.prepare("SELECT workspace_id, id, title FROM notes")?;
    let rows = select.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;
    let titles = rows.collect::<Result<Vec<_>, _>>()?;
    drop(select);

    for (workspace_id, note_id, title) in titles {
        conn.execute(
            "UPDATE notes SET title_lookup_key = ?1 WHERE workspace_id = ?2 AND id = ?3",
            rusqlite::params![
                crate::index::title_lookup_key(&title),
                workspace_id,
                note_id
            ],
        )?;
    }

    conn.execute_batch(&format!("PRAGMA user_version = {CURRENT_SCHEMA_VERSION};"))?;
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
///
/// **No `f` may perform file I/O** (`SPK-WSPC-D001` §6.2.7). The mutex taken
/// here is process-wide and is the one a keystroke's own tier 1 draft write
/// waits on, so anything slow inside a closure is latency charged to typing.
/// The rule is enforced rather than merely written down: the scope entered
/// below is what [`assert_no_io_under_the_connection`] reads.
///
/// The guard lives *here*, at the acquisition, rather than only in
/// `workspace::persist::Workspace::with_db`. That is where it started, and the
/// consequence was that it covered exactly the module that already obeyed the
/// rule: every other caller in the crate — `api::ffi_api`'s wrappers,
/// `workspace::bootstrap::converge`, the full reindex — reached the same mutex
/// through this function without ever entering the scope, so a bundle walk
/// under the connection was invisible to the assert that exists to catch it.
pub fn with_connection<T>(
    f: impl FnOnce(&Connection) -> Result<T, AppError>,
) -> Result<T, AppError> {
    let db = connection()?;
    let conn = db
        .lock()
        .map_err(|_| AppError::DatabaseError("db mutex poisoned".to_string()))?;
    let _scope = ConnectionScope::enter();
    f(&conn)
}

// ---------------------------------------------------------------------------
// The rule that no connection closure performs file I/O, enforced
// ---------------------------------------------------------------------------

thread_local! {
    /// Whether this thread is currently holding a connection — the
    /// process-wide one through [`with_connection`], or a test's injected one
    /// through `workspace::persist::Workspace::with_db`.
    static IN_CONNECTION_CLOSURE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// Marks the calling thread as holding the connection for as long as it lives.
///
/// Restores the previous value rather than clearing, so a nested acquisition —
/// which the rule does not forbid — does not report the outer one as finished
/// when the inner one ends.
pub(crate) struct ConnectionScope(bool);

impl ConnectionScope {
    pub(crate) fn enter() -> Self {
        ConnectionScope(IN_CONNECTION_CLOSURE.with(|flag| flag.replace(true)))
    }
}

impl Drop for ConnectionScope {
    fn drop(&mut self) {
        IN_CONNECTION_CLOSURE.with(|flag| flag.set(self.0));
    }
}

pub(crate) fn in_connection_closure() -> bool {
    IN_CONNECTION_CLOSURE.with(std::cell::Cell::get)
}

/// Panics in debug builds when `what` is being done while the connection is
/// held.
///
/// `SPK-WSPC-D001` §6.2.7's three standing review rules are the ones "a tier 2
/// implementation would break first", and the first of them — no file I/O
/// inside a connection closure — is invisible at the call site once the I/O is
/// two functions away. This turns it into a test failure rather than a review
/// finding. Debug only, so a shipped build pays nothing for it.
pub(crate) fn assert_no_io_under_the_connection(what: &str) {
    debug_assert!(
        !in_connection_closure(),
        "{what} ran inside a connection closure: the process-wide connection \
         mutex would be held across file I/O, which is what a keystroke's own \
         tier 1 write then waits on (SPK-WSPC-D001 §6.2.7)"
    );
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
static ACTIVE_WORKSPACE: Mutex<Option<ActiveWorkspace>> = Mutex::new(None);

/// The active Workspace's id, plus its bundle root once something has had to
/// resolve it.
///
/// The root is cached here rather than re-queried because
/// `workspace::persist::Workspace::active` runs on **every** Note-level FFI
/// call — every open, every lifecycle operation, every status poll — and each
/// one was taking the process-wide connection mutex to read one `local_path`
/// that cannot change while a Workspace is open. That is the mutex a
/// keystroke's own tier 1 draft write waits on (`SPK-WSPC-D001` §6.2), so the
/// round trip was contention bought for a constant.
///
/// `local_path` is written once, by `workspace::bootstrap::converge`, and
/// nothing ever updates it for an existing row — so the only event that can
/// invalidate this is the active Workspace *changing*, which is exactly what
/// [`set_active_workspace_id`] clears it on.
struct ActiveWorkspace {
    id: String,
    root: Option<PathBuf>,
}

fn lock_active() -> Result<std::sync::MutexGuard<'static, Option<ActiveWorkspace>>, AppError> {
    ACTIVE_WORKSPACE
        .lock()
        .map_err(|_| AppError::DatabaseError("active workspace lock poisoned".to_string()))
}

/// Records `id` as the active Workspace. Called by
/// `api::ffi_api::open_or_create_local_workspace` and
/// `api::ffi_api::open_workspace` after a successful bootstrap — not by
/// `workspace::bootstrap`'s own `_impl` functions, which are exercised
/// directly against an injected `Connection` in hermetic tests and must
/// never touch this process-wide cell (doing so would leak one test's
/// active Workspace into another's).
///
/// Discards any cached bundle root: a different Workspace has a different one,
/// and re-establishing the *same* id costs one query to refill.
pub(crate) fn set_active_workspace_id(id: String) -> Result<(), AppError> {
    let mut guard = lock_active()?;
    *guard = Some(ActiveWorkspace { id, root: None });
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
    let guard = lock_active()?;
    guard
        .as_ref()
        .map(|active| active.id.clone())
        .ok_or_else(|| AppError::NotFound("no Workspace is open".to_string()))
}

/// The active Workspace's id **and** its bundle root, resolving the root
/// through the index only the first time it is asked for.
///
/// The connection is deliberately acquired with this module's own lock
/// *released*, and the result is stored only if the active Workspace is still
/// the one that was resolved: holding the two at once would introduce a second
/// acquisition order over the process-wide connection mutex, for a cache fill
/// that is happy to be redone.
pub(crate) fn active_workspace() -> Result<(String, PathBuf), AppError> {
    let id = {
        let guard = lock_active()?;
        let active = guard
            .as_ref()
            .ok_or_else(|| AppError::NotFound("no Workspace is open".to_string()))?;
        if let Some(root) = &active.root {
            return Ok((active.id.clone(), root.clone()));
        }
        active.id.clone()
    };

    let root = with_connection(|conn| crate::index::workspace_root(conn, &id))?;

    let mut guard = lock_active()?;
    if let Some(active) = guard.as_mut() {
        if active.id == id {
            active.root = Some(root.clone());
        }
    }
    Ok((id, root))
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
    fn schema_sets_the_current_user_version_for_future_migrations_to_branch_on() {
        let (_dir, conn) = open_test_db();
        init_schema(&conn).unwrap();

        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_SCHEMA_VERSION);
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

    /// A version beyond this binary's known migration must be left exactly as
    /// it is when `init_schema` replays the batch again, rather than being
    /// reset to the current baseline.
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

    #[test]
    fn schema_migrates_v1_title_rows_to_the_unicode_lookup_key() {
        let (_dir, conn) = open_test_db();
        // Deliberately model the v1 `notes` table directly: v1 lacks the
        // lookup-key column, so replaying the v2 schema cannot add it.
        conn.execute_batch(
            "CREATE TABLE notes (
                 id TEXT NOT NULL,
                 workspace_id TEXT NOT NULL,
                 path TEXT NOT NULL,
                 title TEXT NOT NULL,
                 last_modified INTEGER NOT NULL,
                 content_hash TEXT NOT NULL,
                 okf_conformant INTEGER NOT NULL DEFAULT 1,
                 PRIMARY KEY (workspace_id, id)
             );
             INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash)
                 VALUES ('uber', 'ws', 'uber.md', 'Über', 0, 'hash');
             PRAGMA user_version = 1;",
        )
        .unwrap();

        init_schema(&conn).unwrap();

        let key: String = conn
            .query_row(
                "SELECT title_lookup_key FROM notes WHERE workspace_id = 'ws' AND id = 'uber'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(key, crate::index::title_lookup_key("Über"));
        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_SCHEMA_VERSION);
    }

    #[test]
    fn version_zero_full_v1_schema_recovers_notes_links_and_unicode_title_lookup() {
        let (dir, conn) = open_test_db();
        // Build every v1 object from the current physical contract by removing
        // precisely the two v2 DDL additions. `user_version` intentionally
        // remains SQLite's default 0, modeling a process killed after the old
        // non-transactional DDL succeeded but before version publication.
        let v1_schema = SCHEMA
            .replacen("    title_lookup_key TEXT NOT NULL,\n", "", 1)
            .replacen(
                "CREATE INDEX IF NOT EXISTS idx_notes_title_lookup\n    ON notes(workspace_id, title_lookup_key COLLATE NOCASE, title, id);\n\n",
                "",
                1,
            );
        assert!(
            !v1_schema.contains("title_lookup_key TEXT NOT NULL"),
            "the fixture must model the v1 notes shape"
        );
        assert!(
            !v1_schema.contains("CREATE INDEX IF NOT EXISTS idx_notes_title_lookup"),
            "the fixture must model the v1 index set"
        );
        conn.execute_batch(&v1_schema).unwrap();
        conn.execute_batch(
            "INSERT INTO workspaces (id, name, provider, local_path)
                 VALUES ('ws', 'Workspace', 'local', '/workspace');
             INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash)
                 VALUES
                    ('uber', 'ws', 'uber.md', 'Über', 0, 'hash-uber'),
                    ('target', 'ws', 'target.md', 'Target', 0, 'hash-target');
             INSERT INTO links (workspace_id, source_id, target_id, target_title)
                 VALUES ('ws', 'uber', 'target', 'Target');",
        )
        .unwrap();

        init_schema(&conn).unwrap();

        let lookup_key: String = conn
            .query_row(
                "SELECT title_lookup_key FROM notes WHERE workspace_id = 'ws' AND id = 'uber'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lookup_key, crate::index::title_lookup_key("Über"));
        let link: (String, String) = conn
            .query_row(
                "SELECT target_id, target_title FROM links \
                 WHERE workspace_id = 'ws' AND source_id = 'uber'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(link, ("target".to_string(), "Target".to_string()));
        assert_eq!(
            crate::index::query::find_notes_by_title_impl(&conn, "ws", "über", 10)
                .unwrap()
                .into_iter()
                .map(|note| note.id)
                .collect::<Vec<_>>(),
            vec!["uber"]
        );
        let index_exists: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master \
                 WHERE type = 'index' AND name = 'idx_notes_title_lookup'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(index_exists, 1);

        // Recovery is complete and reopening/re-initializing cannot alter the
        // published version or duplicate either the schema or graph data.
        drop(conn);
        let reopened =
            open_encrypted_db_with_key(&dir.path().join("index.sqlite3"), &[0x24u8; 32]).unwrap();
        init_schema(&reopened).unwrap();
        let version: i64 = reopened
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_SCHEMA_VERSION);
        let links: i64 = reopened
            .query_row("SELECT count(*) FROM links", [], |row| row.get(0))
            .unwrap();
        assert_eq!(links, 1);
    }

    #[test]
    fn version_zero_workspaces_only_partial_schema_is_completed_transactionally() {
        let (_dir, conn) = open_test_db();
        conn.execute_batch(
            "CREATE TABLE workspaces (
                 id TEXT PRIMARY KEY,
                 name TEXT NOT NULL,
                 provider TEXT NOT NULL,
                 remote_url TEXT,
                 local_path TEXT NOT NULL
             );",
        )
        .unwrap();

        init_schema(&conn).unwrap();
        init_schema(&conn).unwrap();

        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_SCHEMA_VERSION);
        let notes_exists: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(notes_exists, 1);
    }

    #[test]
    fn fresh_schema_failure_rolls_back_schema_and_version_publication_together() {
        let (_dir, conn) = open_test_db();
        conn.authorizer(Some(
            |context: rusqlite::hooks::AuthContext<'_>| match context.action {
                rusqlite::hooks::AuthAction::CreateTable {
                    table_name: "notes",
                } => rusqlite::hooks::Authorization::Deny,
                _ => rusqlite::hooks::Authorization::Allow,
            },
        ))
        .unwrap();

        let error = init_schema(&conn).expect_err("injected CREATE TABLE failure must surface");
        assert!(matches!(error, AppError::DatabaseError(_)));
        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, 0);
        let created_tables: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master \
                 WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(created_tables, 0, "the failed fresh schema must roll back");

        conn.authorizer(None::<fn(rusqlite::hooks::AuthContext<'_>) -> _>)
            .unwrap();
        init_schema(&conn).unwrap();
        let committed_version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(committed_version, CURRENT_SCHEMA_VERSION);
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

    /// `SPK-WSPC-D001` §6.2.7's first standing rule, enforced at the
    /// acquisition every caller in the crate actually goes through.
    ///
    /// The regression this pins: the guard was entered only by
    /// `workspace::persist::Workspace::with_db`, so it covered exactly the one
    /// module that already obeyed the rule. `api::ffi_api`'s wrappers,
    /// `workspace::bootstrap::converge` and the full reindex all reached this
    /// same process-wide mutex through [`with_connection`] without entering the
    /// scope — and `converge` held it across a repository init, a recursive
    /// scratch sweep and a read-and-parse of every Note in the bundle, entirely
    /// invisibly to the assert whose whole purpose is to catch that.
    ///
    /// `catch_unwind` rather than `#[should_panic]`: the locks this test needs
    /// are held for its whole body, and unwinding out of it would poison them
    /// for every other test in the binary that takes them with `unwrap`.
    #[cfg(debug_assertions)]
    #[test]
    fn file_io_inside_a_with_connection_closure_is_a_hard_error() {
        let _env_lock = ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let db_dir = tempfile::tempdir().unwrap();
        let _db_path = EnvVarGuard::set(
            "BURLMD_DB_PATH",
            db_dir.path().join("index.sqlite3").as_os_str(),
        );

        let previous_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            with_connection(|_conn| {
                assert_no_io_under_the_connection("a probe standing in for a bundle walk");
                Ok(())
            })
        }));
        std::panic::set_hook(previous_hook);

        let payload = outcome.expect_err(
            "the guard must fire for file I/O performed inside a with_connection closure",
        );
        let message = payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&str>().map(|s| (*s).to_string()))
            .unwrap_or_default();
        assert!(
            message.contains("ran inside a connection closure"),
            "expected the connection-scope guard, got {message:?}"
        );
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
