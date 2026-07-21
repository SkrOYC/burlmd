# ADR-003: Comprehensive Local Encryption (At-Rest)

**Status:** Accepted

## Context
While the remote repository (e.g., GitHub) is secured by the provider's infrastructure and the user's OAuth tokens, the local mobile device or laptop is highly vulnerable to theft or unauthorized filesystem access. Since the app claims to respect data sovereignty and privacy, storing plain Markdown files and a plaintext SQLite search index on the local disk is a massive security failure. 

However, full-disk encryption provided by the OS is often insufficient because files are decrypted while the device is unlocked. We need application-level at-rest encryption.

## Decision
1. **SQLite:** We will use `sqlcipher` (bundled via `rusqlite`) to transparently encrypt the entire SQLite index and FTS5 virtual tables using AES-256.
2. **Markdown Files:** The Core Engine will encrypt/decrypt the raw Markdown files using `aes-gcm` before/after Git writes them to the local disk.
3. **Key Management:** The root symmetric key will be generated locally on first boot and stored in the OS-level secure enclave (Keychain on iOS/macOS, Keystore on Android, Credential Manager on Windows) using the Rust `keyring` crate.

## Consequences
- **Positive:** Maximum privacy. A compromised filesystem yields only ciphertext.
- **Negative:** Increased CPU overhead for decrypting files on the fly when reading into the AST, potentially threatening the <16ms UI latency constraint. 
- **Negative:** Backups of the local device might not be restorable if the OS Keychain is not backed up synchronously. To mitigate this, users must rely on the Git remote for cross-device recovery.
