use keyring::Entry;
use zeroize::Zeroizing;

use crate::api::ffi_api::AppError;

const SERVICE: &str = "com.burlmd.app";
const ACCOUNT: &str = "root_key";

impl From<keyring::Error> for AppError {
    fn from(e: keyring::Error) -> Self {
        AppError::CryptoError(e.to_string())
    }
}

/// Returns the 256-bit root AES key used to encrypt the local SQLite index.
/// On a fresh installation this generates a new CSPRNG key and persists it
/// in the OS Keychain; subsequent calls retrieve the same key. The key is
/// wrapped in `Zeroizing` so every copy of the crown-jewel key material
/// (including intermediate buffers) is wiped from memory when dropped.
pub fn get_or_create_root_key() -> Result<Zeroizing<[u8; 32]>, AppError> {
    get_or_create_root_key_for(SERVICE, ACCOUNT)
}

fn get_or_create_root_key_for(
    service: &str,
    account: &str,
) -> Result<Zeroizing<[u8; 32]>, AppError> {
    let entry = Entry::new(service, account)?;
    match entry.get_secret() {
        Ok(secret) => {
            let secret = Zeroizing::new(secret);
            let bytes: [u8; 32] = secret.as_slice().try_into().map_err(|_| {
                AppError::CryptoError("stored root key is not 32 bytes".to_string())
            })?;
            Ok(Zeroizing::new(bytes))
        }
        Err(keyring::Error::NoEntry) => {
            let key = generate_key()?;
            entry.set_secret(key.as_slice())?;
            Ok(key)
        }
        Err(e) => Err(e.into()),
    }
}

fn generate_key() -> Result<Zeroizing<[u8; 32]>, AppError> {
    let mut key = Zeroizing::new([0u8; 32]);
    getrandom::fill(&mut *key)
        .map_err(|e| AppError::CryptoError(format!("OS CSPRNG failure: {e}")))?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Distinct, clearly-scoped identifiers so this test never touches the
    // real app's shipped Keychain entry, and always cleans up after itself.
    const TEST_SERVICE: &str = "com.burlmd.app.test-security-keyring-b001";
    const TEST_ACCOUNT: &str = "root-key-test";

    #[test]
    fn fresh_installation_generates_and_stores_a_256_bit_key() {
        let entry = Entry::new(TEST_SERVICE, TEST_ACCOUNT).unwrap();
        let _ = entry.delete_credential(); // ensure a clean slate

        let key = get_or_create_root_key_for(TEST_SERVICE, TEST_ACCOUNT).unwrap();
        assert_ne!(*key, [0u8; 32], "generated key must not be all zero bytes");
        assert_eq!(entry.get_secret().unwrap(), key.to_vec());

        // Idempotency: a second call must return the SAME key, not regenerate.
        let key_again = get_or_create_root_key_for(TEST_SERVICE, TEST_ACCOUNT).unwrap();
        assert_eq!(key, key_again);

        entry.delete_credential().unwrap();
    }
}
