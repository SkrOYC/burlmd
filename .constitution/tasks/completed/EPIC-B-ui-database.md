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

##### UIDB-B006 Deviations & Justifications
- **Touched Files:** `test/components/editor_test.dart` (new)
- **Justification:** The ticket's own Verification Command is `flutter test`, which requires a test to exist; `test/` mirrors `lib/src/components/` for its one widget test, matching the project's existing `test/widget_test.dart` convention.

#### UIDB-B007 Editor FFI Streaming Connection
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** UIDB-B006
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `rust/src/api/ffi_api.rs`
- **Verification Command:** `cargo build && flutter test`
- **Description:** Wire the Editor widget to send block updates (keystrokes) to the `update_block` FFI function, and re-render the AST returned by the Core Engine.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the active Editor
When the user types a character
Then the FFI function is called and the UI updates within 16ms
```

##### UIDB-B007 Deviations & Justifications
- **Touched Files:** `rust/src/frb_generated.rs`, `lib/src/rust/api/ffi_api.dart`, `lib/src/rust/frb_generated.dart`, `lib/src/rust/frb_generated.io.dart`, `lib/src/rust/frb_generated.web.dart`, `lib/src/providers/note_providers.dart`, `lib/src/providers/rust_api_provider.dart`, `test/components/editor_test.dart`
- **Justification:** `rust/src/frb_generated.rs` and `lib/src/rust/**` are `flutter_rust_bridge_codegen generate` output for `update_block`'s new FFI surface, following the same pattern recorded for `UIDB-B004`. `note_providers.dart`/`rust_api_provider.dart` (both already-owned by `UIDB-B005`) are the natural home for the `updateBlock` call the Editor needs — adding it there rather than duplicating FFI-calling logic inside `editor.dart` keeps the "UI stays stateless regarding content" boundary intact. `test/components/editor_test.dart` required updating because `Editor`'s public constructor changed (it now reads `activeNoteProvider` instead of taking `ast` directly, per this ticket's declared scope covering `editor.dart`), which is the same "test needs updating because production API changed" situation the `UIDB-B005` review flagged in advance for this exact milestone.

**Judgment call — the 16ms Gherkin.** A literal stopwatch assertion isn't meaningful under `flutter test`'s fake clock (it doesn't measure real GPU frame timing). The test instead asserts the *shape* of synchronicity: typing triggers exactly one `tester.pump()` before the provider state reflects the edit, with no `await`/`Future` anywhere in the Dart-side call chain (`TextField.onChanged` → `NoteController.updateBlock` → `RustApi.updateBlock`), consistent with the Rust side being `#[frb(sync)]` rather than `async`. This proves no extra async hop sits between keystroke and re-render, which is the actual latency risk the Gherkin is guarding against, without asserting a specific millisecond figure that a widget test can't honestly measure.

**Scope narrowing — single-run paragraph editing only.** Only `Paragraph` blocks are editable in this ticket; other block types stay read-only via `renderBlock`. Editing also collapses a paragraph to a single plain-text run on every keystroke (via `TextField`, which — unlike the `TextSpan` tree `renderBlock` uses for read-only rendering — can only apply one uniform style, not per-character rich formatting). To avoid regressing `UIDB-B006`'s own bold-rendering acceptance criterion for the *pre-edit* render, the field's style is derived from the paragraph's first run, so a simple single-style paragraph (e.g. an all-bold paragraph) still displays correctly the moment the Editor first shows it. That styling does not survive the first keystroke: `onChanged` always rebuilds the paragraph as a plain (`bold: false` etc.) run, so a bold paragraph visibly de-styles as soon as it's edited — this is a real, known consequence of collapsing to single-run editing, not merely a display nuance. Full rich multi-run inline editing (splitting a styled run mid-string while preserving neighboring formatting, links, and cursor position) is materially larger than this ticket's scope and is left as a follow-up.

**Post-closeout fix — multi-run paragraphs were silently made editable too, flattening their styling.** The original implementation above gated editability on "is this an `AstNode_Paragraph`" alone, not on run count. A *multi*-run paragraph (e.g. plain text followed by a bold word) matched that same `TextField` branch, and `_paragraphStyle` only ever reads the *first* run — so the field displayed the entire paragraph in one uniform style, silently dropping every other run's bold/italic/code/strikethrough distinction, even before any edit. This is a genuine regression against `UIDB-B006`'s own Gherkin ("a bold TextRun renders as bold text"), invisible to the whole test suite because every existing test's paragraphs (via the `_paragraphOf` helper) happened to be single-run. It was only caught by actually running the app (`flutter run -d linux`) and inspecting a real screenshot — the first time any ticket's verification had done so; see `tech-spec/guidelines.md`'s new "Running the real app" section for the companion discovery that `flutter run` itself didn't work at all until `rust/target/release/` was populated with `cargo build --release`, since no prior ticket's Verification Command ever launched the compiled app. Fixed by gating the `TextField` branch on a new `_isSingleTextRun` guard (exactly one run, and that run must be `InlineElement_Text`, not a `Link`); multi-run and Link-containing paragraphs now correctly stay read-only via `renderBlock`, preserving full per-run fidelity. This incidentally also closes the previously-recorded "`_plainText` drops Link display text" gap for the editable path, since a paragraph containing a `Link` can no longer reach the `TextField` branch at all. Covered by a new widget test (`a multi-run paragraph stays read-only and keeps each run's distinct styling`).

**Fixed during review — stale content in a reused field.** `_EditableBlock`'s `TextEditingController` was originally seeded once in `initState` and never reconciled afterward. Since Flutter reuses the `State` for the block at a given list index across rebuilds, if `activeNoteProvider` ever swapped in a different note (or a future `insert_block`/`delete_block` reindexed positions), an already-mounted field would keep showing the *previous* note's stale text — and typing into it would stream that edit to the wrong note's block. Not reachable in the app today (no note-switching UI exists, and `Editor` isn't mounted), but it broke the "driven entirely by `activeNoteProvider`" contract the widget was explicitly refactored around, so it was fixed rather than deferred: `didUpdateWidget` now resyncs the controller's text, but only when the incoming node's plain text actually differs from what the field currently shows. On this field's own keystroke round-trip the echoed-back node already matches, so the guard leaves the cursor alone; it only fires on a genuinely external change. Covered by a new widget test (`swapping to a different note resyncs an untouched, reused field`).
