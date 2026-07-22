# Epic B: UI & Database

#### UIDB-B001 Integrate Keychain Root Key
- **Type:** Security
- **Effort:** 3
- **Dependencies:** CORE-A001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/security/keyring.rs`
- **Verification Command:** `cargo test security::`
- **Description:** Implement Rust `keyring` integration to generate and securely store a 256-bit root AES key in the host OS secure enclave.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a fresh installation
When the app boots
Then a new 256-bit key is generated and stored in the OS Keychain
```

##### UIDB-B001 Deviations & Justifications
- **Touched Files:** `rust/src/security/mod.rs` (new), `rust/src/lib.rs`, `rust/Cargo.toml`, `rust/Cargo.lock`
- **Justification:** Introducing the `security` module requires a `mod.rs` to declare its child (`keyring`) and a `pub mod security;` wire-in at the crate root (`lib.rs`), the same shape as `CORE-A001`'s recorded deviations for `rust/src/api`. `Cargo.toml`/`Cargo.lock` changed because the `keyring` and `getrandom` crates were added via `cargo add` per project tooling policy.

#### UIDB-B002 Encrypt SQLite with SQLCipher
- **Type:** Security
- **Effort:** 5
- **Dependencies:** UIDB-B001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/db/connection.rs`
- **Verification Command:** `cargo test db::`
- **Description:** Configure the `rusqlite` initialization to issue `PRAGMA key` using the root key from `UIDB-B001`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the SQLite initialization
When the database file is written to disk
Then the file is AES-256-CBC encrypted with HMAC-SHA512 page authentication and cannot be opened by standard sqlite3 CLI
```

##### UIDB-B002 Deviations & Justifications
- **Touched Files:** `rust/src/db/mod.rs` (new), `rust/src/lib.rs`, `rust/Cargo.toml`, `rust/Cargo.lock`, `.constitution/tech-spec/stack.md`, `.constitution/tech-spec/changelog.md`
- **Justification:** `db/mod.rs` and the `lib.rs` wire-in are the same unavoidable module-introduction pattern as `UIDB-B001`. `Cargo.toml`/`Cargo.lock` changed via `cargo add rusqlite --features bundled-sqlcipher` and `cargo add tempfile --dev`. `stack.md`/`changelog.md` were corrected because the shipped implementation applies the root key via SQLCipher's raw-key PRAGMA form (`PRAGMA key = "x'<hex>'"`, no KDF) rather than the passphrase/PBKDF2 mechanism the spec previously described — leaving the spec factually wrong about the actual security mechanism was judged worse than this one-bullet out-of-scope correction; confirmed with the user before implementation as the correct approach given the root key is already full-entropy CSPRNG output.

#### UIDB-B003 SQLite Initialization & Schema
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** UIDB-B002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/db/connection.rs`
  - `rust/src/db/schema.sql` (embedded or run on init)
- **Verification Command:** `cargo test db::`
- **Description:** Implement `rusqlite` setup logic to initialize the local encrypted database file, applying the `notes`, `links`, and `notes_fts` tables using the TechSpec schema.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given an empty database path
When the db initialization routine runs
Then the tables `notes` and `notes_fts` are created successfully
```

#### UIDB-B004 Expose SQLite Queries to FFI
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** CORE-A003, UIDB-B003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/api/ffi_api.rs`
- **Verification Command:** `cargo build`
- **Description:** Expose `search_notes` and `save_note` functions across the FRB boundary, wiring them to the `rusqlite` database operations.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the FFI bridge
When Dart calls `search_notes`
Then the Rust core executes an FTS5 query and returns `NoteMetadata`
```

##### UIDB-B004 Deviations & Justifications
- **Touched Files:** `rust/src/db/connection.rs`, `rust/src/frb_generated.rs`, `lib/src/rust/api/ffi_api.dart`, `lib/src/rust/frb_generated.dart`, `lib/src/rust/frb_generated.io.dart`, `lib/src/rust/frb_generated.web.dart`
- **Justification:** `search_notes`/`save_note` need a process-wide DB connection to operate on, so the `OnceLock<Mutex<Connection>>` singleton and its `connection()` accessor were added to `db/connection.rs` (already-owned by UIDB-B002/B003) rather than duplicated inside `ffi_api.rs`. `rust/src/frb_generated.rs` and the `lib/src/rust/**` files are all `flutter_rust_bridge_codegen generate` output (Rust-side dispatch glue and Dart-side bindings respectively), required whenever `ffi_api.rs`'s public FFI surface changes (same pattern recorded for `CORE-A003`, whose own Verification Command was `flutter_rust_bridge_codegen generate && cargo build`); regenerated automatically, not hand-edited.

#### UIDB-B005 Flutter Riverpod Setup
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** CORE-A001
- **Category:** DX
- **Scope (In-Scope Files):**
  - `lib/main.dart`
  - `lib/src/providers/`
- **Verification Command:** `flutter analyze`
- **Description:** Wrap the Flutter app in a `ProviderScope` and set up the foundational Riverpod providers to access the Rust FFI functions globally.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the Flutter app
When it boots
Then the Rust API is injected via a Riverpod Provider
```

##### UIDB-B005 Deviations & Justifications
- **Touched Files:** `pubspec.yaml`, `pubspec.lock`
- **Justification:** `flutter_riverpod` was added via `flutter pub add flutter_riverpod` per project tooling policy, which necessarily updates both the dependency declaration and the lockfile.

#### UIDB-B006 Hybrid Editor Widget (Basic Rendering)
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** UIDB-B004, UIDB-B005
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
- **Verification Command:** `flutter test`
- **Description:** Build the Flutter widget that takes an `AstNode` tree and recursively renders it into Flutter `TextSpan` and structural widgets, effectively visualizing the parsed Markdown without raw asterisks.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given an AST containing a bold TextRun
When the Editor renders the AST
Then a bold Flutter Text widget is painted to the screen
```

#### UIDB-B007 Editor FFI Streaming Connection
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** UIDB-B006
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `rust/src/api/ffi_api.rs`
- **Description:** Wire the Editor widget to send block updates (keystrokes) to the `update_block` FFI function, and re-render the AST returned by the Core Engine.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the active Editor
When the user types a character
Then the FFI function is called and the UI updates within 16ms
```
