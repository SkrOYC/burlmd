# Stage 3: Technical Implementation Changelog

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
