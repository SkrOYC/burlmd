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
- **Justification:** Introducing the `security` module requires a `mod.rs` to declare its child (`keyring`) and a `pub mod security;` wire-in at the crate root (`lib.rs`), the same shape as `CORE-A001`'s recorded deviations for `rust/src/api`. `Cargo.toml`/`Cargo.lock` changed because the `keyring`, `getrandom`, and `zeroize` crates were added via `cargo add` per project tooling policy — `zeroize` wraps the generated root key (and, from `UIDB-B002` onward, its hex encoding and the assembled `PRAGMA` string) so key material is wiped from memory on drop rather than lingering in a dropped-but-unzeroed allocation. (This crate was missed from this justification when first added and only recorded here during PR #4's round-3 review.)

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

**Post-PR-review fixes (round 1) — dual-axis review on PR #4.** An independent Standards + Spec review pass surfaced one real architectural defect and several worthwhile-but-non-blocking cleanups, all fixed on the same PR before the next round:
- **Circular dependency (P1, Standards):** `db::connection` and `security::keyring` both imported `AppError` from `api::ffi_api`, an upward dependency on the FFI-facing layer that `architecture/containers.md` explicitly says the Local Repository and Secure Storage containers shouldn't have. Fixed by moving `AppError`'s definition into a new leaf module, `rust/src/error.rs`, that `api`, `db`, and `security` all depend on inward; `api::ffi_api` re-exports it (`pub use crate::error::AppError;`) using the same pattern already established for the `markdown` AST types, so the FFI surface FRB scans is unchanged. Regenerated FRB bindings accordingly (`AppError` now has its own generated `lib/src/rust/error.dart`).
- **Related doc correction:** while fixing the above, noticed `containers.md` also claimed the Local Repository "Depends on: None (Self-contained)," which was never true once SQLCipher needs the root key — `db::connection::open_encrypted_db` has always called into `security::keyring`. Corrected to "Depends on: Secure Storage."
- **Duplicated code (P2, Standards):** `renderInline`'s `InlineElement_Link` and `InlineElement_ExternalLink` arms were byte-identical; extracted into a shared `_renderLinkSpan` helper. Similarly, `search_notes`/`save_note`'s repeated "acquire the DB singleton, lock it, map a poisoned-lock error" preamble is now a `db::connection::with_connection` helper.
- **Unclear error on unknown note id (P2, Spec):** `save_note` on a note absent from `notes` (no row exists — `open_note` never inserts one) surfaced a raw `AppError::DatabaseError` from `rusqlite::Error::QueryReturnedNoRows`. Now maps that specific case to `AppError::IoError("no note found with id ...")`, matching `update_block`'s existing classification for the same kind of cache-miss. Covered by a new test.
- **Documented, not fixed (Investigate, both axes converged on this independently):** `open_note`'s `NoteState.base_revision` ("head", a placeholder) and `save_note`'s `expected_base_revision` (compared against stringified `notes.last_modified`) are not the same OCC token yet — `open_note` never touches the `notes` table at all. Feeding one into the other today would always mismatch. Left as-is rather than inventing the open→edit→save wiring this ticket never scoped; added explicit comments at both ends so this doesn't read as an oversight when that wiring ticket lands.
- **Documented, not fixed (general feedback, Spec):** `search_notes`'s `#[frb] async` marker is faithful to the TechSpec contract but stands in tension with `guidelines.md`'s "avoid async, local queries stay synchronous" rule; added a comment explaining the body runs synchronously to completion regardless (the `async` only affects FRB's dispatch, not this function's own execution). `guidelines.md` now also carries an explicit carve-out for this case, so it stops being re-flagged every round.

**Post-PR-review fixes (round 2, dual-axis review on PR #4).** The clean-high-priority-round counter reset to zero after round 1's P1 fix, per the loop's own rule, so a second dual-axis pass ran. No P0/P1 surfaced this time; the following P2s were real and fixed:
- **FTS5 `MATCH` syntax errors on ordinary search input (P2, Spec):** `search_notes_impl` bound the raw user query straight into `WHERE notes_fts MATCH ?1`. FTS5's bare `MATCH` grammar treats hyphens as exclusion, colons as column filters, parens as boolean grouping, and unmatched quotes as syntax errors — so everyday queries like `note-1`, `budget:2024`, `hello (world`, or `"unbalanced` all threw, empirically confirmed by the reviewer. Fixed by wrapping the whole query in a `fts5_phrase_query` helper (quoted-phrase escaping, FTS5's own recommended mitigation for exactly this), so the entire input is always treated as one literal phrase — a plain "search my notes" box doesn't need FTS5's query-language power. Covered by new tests for the exact inputs that used to break, plus one proving multi-word phrase semantics.
- **`ListView` building every block eagerly (P2, Spec; general feedback, Standards, independently):** `Editor` used `ListView(children: [...])`, constructing every `_EditableBlock` (including off-screen ones) on every `activeNoteProvider` rebuild — i.e. every keystroke, since `update_block` returns the full AST. Both axes tied this to `architecture/risks.md` #1/#3's frame-budget and large-note-latency concerns. Switched to `ListView.builder` so only visible blocks build.
- **Divergent Change in `ffi_api.rs` (P2, Standards):** the module mixed three unrelated concerns (filesystem open+parse, the in-memory draft cache/`set_node_at_path` editing engine, and DB-backed queries) that will keep growing along independent seams as `insert_block`/`delete_block`/`resolve_suggestion` land. Extracted the draft-state domain (`NoteMetadata`, `NoteState`, the active-note cache, `set_node_at_path`, and their tests) into a new `rust/src/draft.rs` leaf module — matching `containers.md`'s framing of "manages the active draft state" as distinct from the FFI bridge itself. `api::ffi_api` now re-exports these types and calls into `draft`'s functions, keeping its own `#[frb]` functions as thin wrappers. Regenerated FRB bindings (new `lib/src/rust/draft.dart`); updated app code (`note_providers.dart`, `rust_api_provider.dart`, `editor_test.dart`) to import types from their new home.
- **Silent, undocumented `LIMIT 50` on search (P2, Spec):** `search_notes` capped results with no pagination and no signal to the caller of truncation, contradicting `prd/capabilities.md`'s unqualified "search across all Notes" and the FFI contract's unbounded `Vec` return. Full pagination is out of scope for a search feature with no UI yet; documented the cap explicitly instead, in both the contract (`tech-spec/contracts/ffi_api.rs`) and the real implementation, as a call-out to revisit once a search UI actually needs more than 50 results.
- **Documented, not fixed (Investigate, Spec):** a second, distinct facet of the open→save wiring gap beyond `base_revision`: `open_note` sets `metadata.id` to the filesystem path, but `data-models/schema.sql` defines `notes.id` as a stable UUID, and `save_note` looks up rows by `notes.id`. Predates this PR (carried from Epic A), newly visible now that `save_note` exists to key off it. Added an explicit comment alongside the existing `base_revision` one rather than inventing the note-creation/UUID-assignment flow this epic never scoped.
- **Doc-consistency nits (general feedback, both axes):** added `draft.rs`/`error.rs` to `guidelines.md`'s monorepo layout diagram (was still describing the pre-round-1 module list).

**Post-PR-review fixes (round 3, dual-axis review on PR #4).** Round 2 produced no P0/P1, incrementing the clean-high-priority-round counter to one, so a confirming third pass ran per the loop's own rule. It surfaced no P0/P1 either, but caught a real self-inflicted regression from round 2's own fix:
- **Round 2's phrase-quoting fix broke multi-word search (P1-equivalent correctness bug, Spec):** wrapping the *entire* query in one quoted phrase (round 2's fix for FTS5 syntax errors) turned every multi-word search into an exact-adjacent-phrase match — `"budget report"` no longer matched a note containing "report on this month's budget," contradicting `prd/capabilities.md`'s "search across all Notes" and the implicit-AND-across-terms behavior users expect from a search box. `fts5_phrase_query` now quotes each whitespace-split token individually (still escaping embedded quotes) and joins them with a space, which FTS5 parses as an implicit AND of exact-token matches — preserving round 2's original goal (no syntax errors from hyphens/colons/parens/unmatched quotes in ordinary input) while restoring "any order, all terms present" matching. The round-2 test that had encoded the wrong phrase-only semantics (`search_notes_treats_a_multi_word_query_as_an_exact_phrase`) was replaced with `search_notes_matches_notes_containing_every_query_term_in_any_order`; the syntax-error-input regression test was kept as-is since per-token quoting still passes it.
- **Zeroization gap in the SQLCipher key-hex path (P2, Standards):** `open_encrypted_db_with_key` built the hex-encoded key via `key.iter().map(|b| format!("{b:02x}")).collect::<String>()` before wrapping the *result* in `Zeroizing`. Each intermediate `format!` call allocates its own short-lived, un-zeroized `String` that is dropped (not wiped) long before the final `collect()` — key-derived bytes could linger in freed heap memory. Fixed by writing hex digits directly into a single pre-sized `Zeroizing<String>` via `std::fmt::Write`, so there is exactly one key-hex allocation and it was zeroizing-wrapped from the start; the assembled `PRAGMA key = "x'...'"` string was already `Zeroizing`-wrapped from round-1-era code and is unchanged. Verified by existing tests continuing to pass (no behavior change, only allocation discipline).
- **`_EditableBlock` mixed two responsibilities (P2, Standards):** the widget both decided *whether* a paragraph was safely single-style-editable and *how* to render it if so, making the guard and the editing logic harder to reason about independently and to extend when multi-run editing eventually lands. Split into a top-level `_buildBlock`/`_isSingleTextRun` dispatcher (decides eligibility) and a narrower `_EditableParagraph`/`_EditableParagraphState` (takes the already-validated single-run `content` directly, not the whole `AstNode`, so its `build` no longer needs an internal type-narrowing switch). Behavior is unchanged; covered by the existing widget tests, which continued to pass without modification.
- **Missing `PRAGMA user_version` baseline (P2, Standards):** `schema.sql`'s own header comment claims it "Uses `PRAGMA user_version` to track migration state," but no statement ever set it, so every fresh database silently sat at SQLite's default (0) — indistinguishable from "no schema applied yet," which is exactly the ambiguity a future migration runner would need to resolve. Added `PRAGMA user_version = 1;` right after `PRAGMA foreign_keys = ON;` in both `tech-spec/data-models/schema.sql` and `rust/src/db/schema.sql` (kept byte-identical, verified via `diff`), with a comment noting the first real migration should branch on this value rather than treat an unset baseline as version 0. Covered by a new test asserting the pragma reads back as `1`.
- **`zeroize` dependency undocumented in this ticket's Justification (P2, Standards):** `UIDB-B001`'s Deviations & Justifications section (above) never mentioned that `keyring`, `getrandom`, and `zeroize` were all added via `cargo add` for that ticket — only the first two were recorded. Backfilled the missing crate into that Justification text now that round 3's own fix (previous bullet) depends on `zeroize` semantics being understood by a future reader.
- **Documented, not fixed (Investigate, Spec):** `architecture/resilience.md`'s "SQLite Draft Persistence" bullet describes synchronous per-keystroke persistence to the `drafts` table with restore-on-boot, but no code reads or writes that table — `update_block` only ever mutates the in-memory `ACTIVE_NOTE_CACHE`. `drafts` exists in the schema (created by `UIDB-B003`) but was never wired up by any Epic B ticket. Rather than implicitly building crash-recovery persistence as a side effect of a review comment, added an explicit "Current implementation status (Epic B)" note to `resilience.md` documenting the gap and pointing at the write-on-every-`update_block`-plus-restore-on-boot ticket this still needs.
- **Documented, not fixed (general feedback, Standards):** `devenv.nix`'s `grim`/`wtype` additions (from the earlier visual-verification retrofit) are development-machine tooling with no runtime dependency from the shipped app; noted as intentionally out of this ticket's production-code scope rather than something to relocate.
