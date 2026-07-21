---
version: v1.0.1
---

# Bill of Materials (BOM) & Stack

## Presentation Layer (UI Container)
- **Framework:** Flutter (stable channel)
- **State Management:** `riverpod` (consumes streams from the FFI boundary)

## Core Engine & Local Index
- **Language:** Rust (edition 2021)
- **FFI Bridge:** `flutter_rust_bridge` (v2)
- **Git Implementation:** `gix` (gitoxide)
- **Local Database:** SQLite via `rusqlite` (with the `bundled-sqlcipher` feature). As of `rusqlite` 0.40 there is no separate `fts5` feature: FTS5 is compiled into the bundled amalgamation by default, and `bundled-sqlcipher` transitively enables `bundled`. Verified in the devenv shell against SQLCipher 4.14.0.
- **Markdown Parser:** `pulldown-cmark` (with custom pre-processor for Git conflict markers).

## Security & Cryptography
- **Secure Storage (Rust):** `keyring` - handles direct retrieval of OAuth tokens and AES keys from the OS hardware enclave without passing them through Dart memory.
- **Database Encryption:** `sqlcipher` (bundled with `rusqlite`) - provides transparent AES-256-GCM encryption of the SQLite index file on disk.

## Compatibility & Upgrade Policy
- **Developer Environment:** The entire toolchain is provisioned by `devenv` (Nix). `devenv.lock` pins `nixpkgs` and `rust-overlay`, making the shell byte-reproducible across machines and CI.
- **Rust Toolchain:** Pinned via `rust-toolchain.toml` (currently `1.97.1`), consumed by devenv through `languages.rust.toolchainFile` and by rustup users directly. `1.94` is a hard floor because `libsqlite3-sys >= 0.38` requires the stabilised `cfg_select!` macro.
- **Flutter SDK:** Pinned via `nixpkgs` (`flutterPackages.v3_44`, currently 3.44.3 / Dart 3.12.2) rather than `fvm`. `fvm` downloads unpatched upstream SDK binaries that do not execute on NixOS and would bypass the Nix store, defeating reproducibility.
- **Data Schemas:** Handled via `rusqlite` `pragma user_version`.
- **Key Rotation:** The root AES key is randomly generated on first boot and never leaves the device's secure enclave. Key rotation is currently out of scope unless device compromise is suspected.
