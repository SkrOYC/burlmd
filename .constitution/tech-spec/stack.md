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
- **Database Encryption:** `sqlcipher` (bundled with `rusqlite`) - provides transparent AES-256-CBC encryption of the SQLite index file on disk, with each page authenticated by HMAC-SHA512 (Encrypt-then-MAC) and the key derived via PBKDF2-HMAC-SHA512. This is not an AEAD construction; threat-model reasoning about tamper resistance must not assume GCM semantics. Per the SQLCipher design document (<https://www.zetetic.net/sqlcipher/design/>): "The encryption algorithm is 256-bit AES in CBC mode", keys are derived with PBKDF2-HMAC-SHA512 at 256,000 iterations, and "every page write includes a Message Authentication Code (HMAC-SHA512) of the ciphertext and the initialization vector at the end of the page". Cross-checked locally by reading `PRAGMA cipher_settings`; the instrument there was the standalone 4.16.0 CLI, while the shipped version is the 4.14.0 vendored by `bundled-sqlcipher`.

## Compatibility & Upgrade Policy
- **Developer Environment:** The entire toolchain is provisioned by `devenv` (Nix). `devenv.lock` pins `nixpkgs`, `rust-overlay` and `git-hooks`, so the toolchain closure resolves identically across machines and CI. Note the boundary stops there: `pub` and `cargo` still resolve package registries outside the store, pinned by `pubspec.lock`/`Cargo.lock` once those exist, and the `devenv` CLI that reads the lock is itself installed outside it.
- **Android SDK:** Not provisioned, and discovery is pinned shut. `ANDROID_HOME` and `ANDROID_SDK_ROOT` point at an in-repo path that deliberately holds no SDK, because Flutter otherwise scans well-known home-directory locations and silently adopts whatever SDK a contributor happens to have installed — the one part of the toolchain `devenv.lock` could not govern. `flutter doctor` now reports "Unable to locate Android SDK" identically on every machine instead of a per-host result. A real pinned SDK belongs here when mobile is unshelved, at versions current at that time; provisioning one now would cost a 14.9 GiB closure on every desktop-only checkout (measured) and would append NDK, build-tools, `libglvnd` and `vulkan-loader` paths to `LD_LIBRARY_PATH`, which the environment deliberately leaves untouched.
- **Rust Toolchain:** Pinned via `rust-toolchain.toml` (currently `1.97.1`), consumed by devenv through `languages.rust.toolchainFile` and by rustup users directly. `1.95` is a hard floor because `libsqlite3-sys >= 0.38` requires `cfg_select!`, which was stabilised in Rust 1.95.0 (rust-lang/rust#149783).
- **Flutter SDK:** Pinned via `nixpkgs` (`flutterPackages.v3_44`, currently 3.44.3 / Dart 3.12.2) rather than `fvm`. `fvm` downloads unpatched upstream SDK binaries that do not execute on NixOS and would bypass the Nix store, defeating reproducibility.
- **FRB Version Triple:** `flutter_rust_bridge_codegen` (pinned by `nixpkgs`, currently 2.12.0) is versioned independently of the `flutter_rust_bridge` Rust crate and Dart package, which resolve from crates.io and pub.dev. Upstream publishes no explicit rule requiring the three to match — the manual and troubleshooting pages were checked and are silent on it — but the codegen emits bindings against a specific runtime API, so skew between them is a live risk rather than a documented constraint. Keep the three aligned and treat a `devenv update` that moves the codegen as requiring the other two to be bumped with it. **To confirm empirically at CORE-A001**, which is the first point at which all three exist.
- **Data Schemas:** Handled via `rusqlite` `pragma user_version`.
- **Key Rotation:** The root AES key is randomly generated on first boot and never leaves the device's secure enclave. Key rotation is currently out of scope unless device compromise is suspected.
