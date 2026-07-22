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
/// key instead of going through the OS Keychain.
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
fn open_encrypted_db_with_key(path: &Path, key: &[u8]) -> Result<Connection, AppError> {
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

    conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
        row.get::<_, i64>(0)
    })
    .map_err(|e| AppError::CryptoError(format!("failed to unlock database: {e}")))?;

    Ok(conn)
}

const SCHEMA: &str = include_str!("schema.sql");

/// Applies `schema.sql` to `conn`. Idempotent — every statement is
/// `CREATE TABLE IF NOT EXISTS` / `CREATE VIRTUAL TABLE IF NOT EXISTS`.
pub fn init_schema(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch(SCHEMA)?;
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

fn default_db_path() -> Result<PathBuf, AppError> {
    if let Ok(p) = std::env::var("BURLMD_DB_PATH") {
        return Ok(PathBuf::from(p));
    }
    let home =
        std::env::var("HOME").map_err(|_| AppError::IoError("HOME is not set".to_string()))?;
    let dir = Path::new(&home).join(".burlmd");
    std::fs::create_dir_all(&dir).map_err(|e| AppError::IoError(e.to_string()))?;
    Ok(dir.join("index.sqlite3"))
}

/// Process-wide encrypted DB connection, lazily opened (and schema-initialized)
/// on first use. `BURLMD_DB_PATH` overrides the default `$HOME/.burlmd/index.sqlite3`
/// location; this is a deliberate placeholder until a workspace-selection ticket
/// makes the path driven by `workspaces.local_path` instead.
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
}
