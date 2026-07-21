---
version: v1.0.0
---

# Bill of Materials (BOM) & Stack

## Presentation Layer (UI Container)
- **Framework:** Flutter (stable channel)
- **State Management:** `riverpod` (consumes streams from the FFI boundary)

## Core Engine & Local Index
- **Language:** Rust (edition 2021)
- **FFI Bridge:** `flutter_rust_bridge` (v2)
- **Git Implementation:** `gix` (gitoxide)
- **Local Database:** SQLite via `rusqlite` (with `bundled`, `fts5`, and `sqlcipher` features).
- **Markdown Parser:** `pulldown-cmark` (with custom pre-processor for Git conflict markers).

## Security & Cryptography
- **Secure Storage (Rust):** `keyring` - handles direct retrieval of OAuth tokens and AES keys from the OS hardware enclave without passing them through Dart memory.
- **Database Encryption:** `sqlcipher` (bundled with `rusqlite`) - provides transparent AES-256-GCM encryption of the SQLite index file on disk.

## Compatibility & Upgrade Policy
- **Rust Toolchain:** Pinned via `rust-toolchain.toml`.
- **Flutter SDK:** Pinned via `fvm`.
- **Data Schemas:** Handled via `rusqlite` `pragma user_version`.
- **Key Rotation:** The root AES key is randomly generated on first boot and never leaves the device's secure enclave. Key rotation is currently out of scope unless device compromise is suspected.
