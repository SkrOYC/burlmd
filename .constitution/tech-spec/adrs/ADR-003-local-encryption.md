---
id: ADR-0003
status: accepted
date: 2026-07-20
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-003: SQLite Encryption & OS File Protection

**Status:** Accepted

## Context
The external service protects private history in Remote (`BND-20`) by using authorization from Provider (`BND-14`). Provider authorizes and locates the Remote; it doesn't store the history. The local desktop remains vulnerable to theft or unauthorized filesystem access.

We initially considered encrypting local Markdown files with AES-GCM before Git manages them. However, local encryption breaks Git's line-based conflict resolution. A device-bound key also prevents synchronization through standard Git clones.

## Decision
1. **SQLite:** We will use `sqlcipher` (bundled via `rusqlite`) to transparently encrypt the entire SQLite index and FTS5 virtual tables using AES-256. This prevents sandbox escapes from scraping the user's aggregated knowledge graph in bulk.
2. **Markdown Files:** Raw Markdown files will be written to disk in **plaintext**, and this application provides no at-rest protection for them. Whatever protection they have is whatever the host operating system happens to give them — full-disk encryption where the user enabled it, nothing where they did not. Stated as an absence rather than as reliance on a platform feature, because on the primary desktop target FDE is an install-time opt-in the application can neither check nor require, and describing it as something we "rely on" reads as a guarantee. See `prd/constraints.yaml`.
3. **Key Management:** The root symmetric key for the SQLite database will be generated locally on first boot and stored in the OS-level secure enclave (Keychain/Keystore) using the Rust `keyring` crate.

## Consequences
- **Positive:** Git synchronization, cloning, and automatic merge conflict generation (`<<<<<<< HEAD`) work perfectly because the files on disk are standard plaintext Markdown.
- **Positive:** Multi-device synchronization is fully supported out of the box via Git.
- **Negative:** If a sophisticated attacker roots the device while unlocked, they can extract the plaintext Markdown files from the app's document directory. We accept this risk in favor of correct Sync semantics.
