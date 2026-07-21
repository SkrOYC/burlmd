# ADR-003: SQLite Encryption & OS File Protection

**Status:** Accepted

## Context
While the remote repository (e.g., GitHub) is secured by the provider's infrastructure and the user's OAuth tokens, the local mobile device or laptop is highly vulnerable to theft or unauthorized filesystem access. We initially considered encrypting the local Markdown files via AES-GCM before letting Git manage them. However, encrypting files locally fundamentally breaks Git's line-based merge logic for conflict resolution, and locking the encryption key to a single device prevents cross-device syncing via standard Git clones.

## Decision
1. **SQLite:** We will use `sqlcipher` (bundled via `rusqlite`) to transparently encrypt the entire SQLite index and FTS5 virtual tables using AES-256. This prevents sandbox escapes from scraping the user's aggregated knowledge graph in bulk.
2. **Markdown Files:** Raw Markdown files will be written to disk in **plaintext**. We will rely exclusively on the OS-level Full Disk Encryption (FDE) and iOS/Android Data Protection APIs to secure these files at rest.
3. **Key Management:** The root symmetric key for the SQLite database will be generated locally on first boot and stored in the OS-level secure enclave (Keychain/Keystore) using the Rust `keyring` crate.

## Consequences
- **Positive:** Git synchronization, cloning, and automatic merge conflict generation (`<<<<<<< HEAD`) work perfectly because the files on disk are standard plaintext Markdown.
- **Positive:** Multi-device synchronization is fully supported out of the box via Git.
- **Negative:** If a sophisticated attacker roots the device while unlocked, they can extract the plaintext Markdown files from the app's document directory. We accept this risk in favor of correct Sync semantics.
