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

#### UIDB-B002 Encrypt SQLite with SQLCipher
- **Type:** Security
- **Effort:** 5
- **Dependencies:** UIDB-B001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/db/connection.rs`
- **Description:** Configure the `rusqlite` initialization to issue `PRAGMA key` using the root key from `UIDB-B001`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the SQLite initialization
When the database file is written to disk
Then the file is AES-256-GCM encrypted and cannot be opened by standard sqlite3 CLI
```

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
