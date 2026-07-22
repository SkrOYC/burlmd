use std::path::Path;

use rusqlite::Connection;

use crate::api::ffi_api::AppError;
use crate::security::keyring::get_or_create_root_key;

impl From<rusqlite::Error> for AppError {
    fn from(e: rusqlite::Error) -> Self {
        AppError::DatabaseError(e.to_string())
    }
}

/// Opens (creating if absent) the SQLCipher-encrypted local index at `path`
/// and unlocks it with the root key from the OS Keychain.
///
/// `PRAGMA key` must be the first statement executed on a freshly opened
/// connection, before any schema access — SQLCipher defers key validation
/// until the first real page read, so this function forces one immediately
/// to surface a bad/missing key here rather than on the caller's first
/// query. The key is applied in its raw-hex form (`x'<64 hex chars>'`),
/// which sets the 32 encryption key bytes directly with no KDF applied —
/// appropriate because the key is already full-entropy CSPRNG output from
/// `get_or_create_root_key`, not a low-entropy human passphrase that would
/// benefit from SQLCipher's passphrase-mode PBKDF2 derivation.
pub fn open_encrypted_db(path: &Path) -> Result<Connection, AppError> {
    let conn = Connection::open(path)?;
    let key = get_or_create_root_key()?;

    let hex_key: String = key.iter().map(|b| format!("{b:02x}")).collect();
    // PRAGMA statements don't accept bound parameters; `hex_key` is locally
    // generated 64-hex-char data, not attacker-controlled input, so this
    // string interpolation carries no injection risk.
    conn.execute_batch(&format!("PRAGMA key = \"x'{hex_key}'\";"))?;

    conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
        row.get::<_, i64>(0)
    })
    .map_err(|e| AppError::CryptoError(format!("failed to unlock database: {e}")))?;

    Ok(conn)
}

#[cfg(test)]
mod tests {
    use std::io::Read;

    use super::*;

    #[test]
    fn database_file_is_encrypted_at_rest_and_unreadable_without_the_key() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("index.sqlite3");

        {
            let conn = open_encrypted_db(&path).unwrap();
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
        assert!(result.is_err());
    }
}
