# Stage 3: Technical Implementation Changelog

## v1.0.1
Phase 0 (tooling readiness). Amendments driven by empirically verifying the stack inside the new `devenv` shell rather than by design changes.
- Replaced `fvm` with a `nixpkgs` pin (`flutterPackages.v3_44`) as the Flutter SDK pinning mechanism. `fvm` fetches unpatched SDK binaries that cannot execute on NixOS and sidesteps the Nix store.
- Recorded `devenv` + `devenv.lock` as the reproducibility boundary for the whole toolchain.
- Pinned the Rust toolchain to `1.97.1` and documented `1.94` as a hard floor: `libsqlite3-sys >= 0.38`, reached through `rusqlite`'s `bundled-sqlcipher` build, requires the stabilised `cfg_select!` macro.
- Corrected the `rusqlite` feature set: `bundled-sqlcipher` alone (it implies `bundled`). The `fts5` feature no longer exists in `rusqlite` 0.40 — FTS5 ships enabled in the bundled amalgamation. Confirmed by an FTS5 `MATCH` query against a keyed SQLCipher 4.14.0 connection.
- Updated the `guidelines.md` monorepo layout to include the phase 0 root files (`devenv.nix`, `devenv.yaml`, `devenv.lock`, `rust-toolchain.toml`, `.envrc`), and recorded that the documented commands assume the devenv shell.
- Noted that `keyring` 4.x reaches the Secret Service through `zbus` in pure Rust, so no `libsecret`/`libdbus` native dependency is required on Linux.
- Corrected the SQLCipher encryption claim. It was documented as AES-256-GCM; SQLCipher 4.x is in fact AES-256-CBC with per-page HMAC-SHA512 authentication (Encrypt-then-MAC) and PBKDF2-HMAC-SHA512 key derivation, confirmed against `PRAGMA cipher_settings`. This is not an AEAD, and the distinction matters for EPIC-C's tamper-resistance reasoning. The same wording was corrected in the `UIDB-B002` acceptance criterion.
- Pinned the Android SDK through devenv's `android` module and enabled `allowUnfree`. Flutter was otherwise discovering an SDK by scanning the contributor's home directory — no `ANDROID_HOME` was set and no `adb` was on `PATH`, so the toolchain was ambient host state outside the Nix store. Mobile stays out of product scope; only the toolchain is now governed by `devenv.lock`.
- Recorded the FRB version triple: the Nix-pinned `flutter_rust_bridge_codegen` must stay in lockstep with the `flutter_rust_bridge` Rust crate and Dart package, which resolve from crates.io and pub.dev.

## v1.0.0
- Selected `flutter_rust_bridge` (v2) for FFI, `rusqlite` for local index, and `gix` for Git operations.
- Defined standard FRB monorepo layout.
- Established `riverpod` for Flutter state management.
- Defined physical SQLite `schema.sql` utilizing `FTS5` for sub-100ms full-text search.
- Formalized the raw FFI API contract (`ffi_api.rs`) detailing the AST node structure and synchronous boundary interactions.
- Expanded AST definition in `ffi_api.rs` to cover real-world Markdown semantics (TextRuns, Images, Links).
- Added `ADR-003-local-encryption.md` establishing at-rest encryption via `sqlcipher` and `aes-gcm`.
- Updated `schema.sql` to include multi-workspace support.
- Updated `stack.md` to specify `flutter_secure_storage` and `keyring` for handling cryptographic material safely at the OS level.
