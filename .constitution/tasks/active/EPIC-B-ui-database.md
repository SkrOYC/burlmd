# Epic B: UI & Database

#### UIDB-B001 SQLite Initialization & Schema
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** CORE-A001
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/db/connection.rs`
  - `rust/src/db/schema.sql` (embedded or run on init)
- **Verification Command:** `cargo test db::`
- **Expected Success Output:** Database initializes in memory for tests.
- **Description:** Implement `rusqlite` setup logic to initialize the local database file, applying the `notes`, `links`, and `notes_fts` tables using the TechSpec schema.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given an empty database path
When the db initialization routine runs
Then the tables `notes` and `notes_fts` are created successfully
```

#### UIDB-B002 Expose SQLite Queries to FFI
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** CORE-A003, UIDB-B001
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

#### UIDB-B003 Flutter Riverpod Setup
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

#### UIDB-B004 Hybrid Editor Widget (Basic Rendering)
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** UIDB-B002, UIDB-B003
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

#### UIDB-B005 Editor FFI Streaming Connection
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** UIDB-B004
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
