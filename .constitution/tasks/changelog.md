# Stage 4: Tasks Changelog

## v1.2.5
PR #4 dual-axis review, round 4 (confirming pass after round 3's material behavior changes) — loop closed, no fixes needed.
- Both axes returned zero P0/P1, the third consecutive clean high-priority round (after 2 and 3), satisfying the review loop's stop condition. No code changes this round.
- Documented, not fixed: a Feature-Envy P2 (Standards) — `search_notes_impl`/`save_note_impl`/`fts5_phrase_query` still live in `api::ffi_api` rather than `db`, the other half of round 2's Divergent-Change fix; a missing error surface for FFI failures in `note_providers.dart` (P2, Spec, currently unreachable since `Editor` isn't mounted); and an Investigate (Spec) that `search_notes` has no `workspace_id` filter despite `prd/capabilities.md`'s "search... in their Workspace" wording — currently unreachable since only one hardcoded workspace exists and no workspace-selection ticket has landed.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review round 4" note for full detail.

## v1.2.4
PR #4 dual-axis review, round 3 (confirming pass after round 2's clean high-priority result).
- Fixed a real correctness regression introduced by round 2's own fix (Spec axis): quoting the *entire* search query as one phrase turned multi-word search into exact-adjacent-phrase matching, contradicting `prd/capabilities.md`'s "search across all Notes." `fts5_phrase_query` now quotes each whitespace-split token individually and joins with a space, restoring implicit-AND-across-terms matching while still avoiding FTS5 syntax errors on hyphens/colons/parens/unmatched quotes. Replaced the round-2 test that had encoded the wrong phrase-only semantics.
- Fixed a zeroization gap (P2, Standards axis): the SQLCipher key's hex encoding was built via a chain of per-byte `format!` calls (each an un-zeroized, dropped-not-wiped intermediate `String`) before the final result was wrapped in `Zeroizing`. Now writes hex digits directly into one pre-sized `Zeroizing<String>` via `std::fmt::Write`, so there is exactly one key-hex allocation and it was zeroizing-wrapped from the start.
- Fixed a Single-Responsibility P2 (Standards axis): split `_EditableBlock` into a top-level `_buildBlock`/`_isSingleTextRun` eligibility dispatcher and a narrower `_EditableParagraph` that operates on an already-validated single-run `content` list rather than a whole `AstNode`.
- Fixed a spec-honesty P2 (Standards axis): `schema.sql`'s header comment claimed migration tracking via `PRAGMA user_version`, but no statement ever set it. Added `PRAGMA user_version = 1;` to both schema copies, with a comment that the first real migration should branch on this baseline. Added a test asserting the pragma reads back as `1`.
- Backfilled a documentation gap in `UIDB-B001`'s Justification (P2, Standards axis): the `zeroize` crate addition was never recorded alongside `keyring`/`getrandom`.
- Documented (not fixed): `architecture/resilience.md`'s "SQLite Draft Persistence" bullet describes per-keystroke persistence to the `drafts` table with restore-on-boot, but no Epic B ticket ever wired this up — `update_block` only mutates the in-memory cache. Added a "Current implementation status (Epic B)" note flagging this as needing its own future ticket. Also noted `devenv.nix`'s `grim`/`wtype` additions as intentionally outside this ticket's production-code scope.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review fixes (round 3)" note for full detail. Rounds 2 and 3 both produced zero P0/P1 findings, satisfying the review loop's two-consecutive-clean-round stop condition.

## v1.2.3
PR #4 dual-axis review, round 2.
- Fixed a real, exploitable-by-any-ordinary-search P2 (Spec axis): `search_notes_impl` passed raw user input straight into FTS5's `MATCH`, whose query grammar throws syntax errors on hyphens, colons, parens, and unmatched quotes — everyday search terms. Now wraps the query in a quoted-phrase escape (`fts5_phrase_query`) so it's always treated as one literal phrase. Added tests for the exact previously-broken inputs.
- Fixed `Editor`'s `ListView(children: [...])` eagerly building every block (both axes independently flagged this against `architecture/risks.md` #1/#3); switched to `ListView.builder`.
- Fixed a Divergent-Change P2 (Standards axis): extracted the active-note draft-state domain (`NoteMetadata`, `NoteState`, the in-memory cache, `set_node_at_path`) out of `api::ffi_api` into a new `rust/src/draft.rs` leaf module, matching `containers.md`'s framing of draft-state management as distinct from the FFI bridge. Regenerated FRB bindings; updated Dart imports accordingly.
- Documented (not fixed) the search result cap (`LIMIT 50`, no pagination) in both the contract and implementation, and a second facet of the open→save wiring gap (`open_note`'s path-based id vs. `notes.id`'s UUID shape) alongside the existing `base_revision` note.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review fixes (round 2)" note for full detail.

## v1.2.2
PR #4 dual-axis review, round 1.
- Fixed a real architectural defect (P1, Standards axis): `db::connection` and `security::keyring` imported `AppError` from the FFI-facing `api::ffi_api` module, an upward dependency `architecture/containers.md` explicitly rules out for those containers. Moved `AppError` into a new shared leaf module (`rust/src/error.rs`); `api`, `db`, and `security` all depend on it inward now. Also corrected `containers.md`'s Local Repository entry, which claimed "Depends on: None" despite always having called into Secure Storage for the root key.
- Fixed two duplicated-code P2s (Standards axis): `renderInline`'s identical Link/ExternalLink arms, and the repeated DB-singleton-acquire-and-lock preamble in `search_notes`/`save_note` (now a shared `with_connection` helper).
- Fixed an unclear-error P2 (Spec axis): `save_note` on an unknown note id now reports `AppError::IoError` instead of a raw `DatabaseError` surfaced from `rusqlite::Error::QueryReturnedNoRows`.
- Documented (not fixed, no reachable path exists yet) a real latent inconsistency both review axes independently found: `open_note`'s placeholder `base_revision` and `save_note`'s DB-sourced `expected_base_revision` are not the same token yet, since `open_note` never touches the `notes` table. Added explicit comments at both ends instead of inventing the open→edit→save wiring this epic never scoped.
- See `tasks/completed/EPIC-B-ui-database.md`'s new "Post-PR-review fixes (round 1)" note for full detail.

## v1.2.1
Post-closeout correction for Epic B, prompted by a request to actually visually verify the shipped UI rather than rely solely on `flutter test` assertions against fakes.
- Discovered and fixed a real regression in `lib/src/components/editor.dart`: multi-run paragraphs (any paragraph mixing plain text with a bold/italic/code/strikethrough run, or containing a Link) were silently made editable via `TextField` alongside single-run ones, and `_paragraphStyle` only reads the first run — so the field displayed the whole paragraph in one flattened style, dropping every other run's formatting even before any edit. This directly regressed `UIDB-B006`'s own bold-rendering Gherkin and was invisible to all six existing widget tests, since every test paragraph happened to be single-run. Fixed by gating paragraph editability on a new `_isSingleTextRun` check; multi-run and Link-containing paragraphs now correctly stay read-only via `renderBlock`. Added a regression test (`a multi-run paragraph stays read-only and keeps each run's distinct styling`).
- Discovered, separately, that `flutter run -d linux` crashed on startup with no code involved: `flutter_rust_bridge`'s generated Dart loader expects `rust/target/release/librust.so`, but no ticket's Verification Command through Epic A or B ever ran `cargo build --release` or `flutter run` — every gate exercised either the Rust half alone (`cargo build`/`cargo test`) or the Dart half against fakes (`flutter test`), so the actual compiled app had never once been launched. Documented the fix (`cargo build --release` from `rust/`) and the underlying gap in `tech-spec/guidelines.md`'s new "Running the real app" section.
- Added `grim` (screenshot) and `wtype` (keystroke injection) to `devenv.nix` as standing Wayland-only manual-QA tooling, so rendered output can be inspected directly rather than only through widget-test property assertions.
- See `tasks/completed/EPIC-B-ui-database.md`'s `UIDB-B007` section for the full write-up, and `tech-spec/guidelines.md` for the standing workflow note.

## v1.2.0
- Completed **Epic B: UI & Database** (`UIDB-B001`–`UIDB-B007`), total 23 story points: OS Keychain root-key generation, SQLCipher-encrypted SQLite (raw-key PRAGMA, no PBKDF2), schema initialization with FTS5 search, `search_notes`/`save_note`/`update_block` exposed across the FFI boundary, Riverpod provider wiring, and a hybrid Markdown editor widget with live keystroke streaming back to the Rust core.
- Archived `EPIC-B-ui-database.md` to `.constitution/tasks/completed/`. Recomputed the active backlog to 16 story points (Epic C only); `SYNC-C001` and `SYNC-C002`'s dependencies on `UIDB-B004`/`UIDB-B005` are now satisfied, so Epic C is front-of-line.
- Ran the Constitution Freshness & Reconciliation Pass: corrected `architecture/containers.md` and `prd/capabilities.md` to distinguish OS-level (raw Markdown files) from application-level SQLCipher (SQLite index) at-rest encryption, corrected `architecture/flows/flow-edit-note.md` to accurately describe `update_block`'s full-NoteState return and flag the not-yet-implemented Markdown-serialize/commit-to-disk phase, and annotated `architecture/risks.md` risk #6 to record that `save_note`'s OCC currently guards only the database's `last_modified` bookkeeping, not file content. See `architecture/changelog.md` v1.0.1 and `prd/changelog.md` v1.0.1.
- Recorded deferred follow-ups (not blocking, tracked for future tickets): no Markdown serializer/write-through exists yet for `save_note`; the `Editor` widget is fully built and tested but not yet mounted in `main.dart` (no note-open or search UI exists in the running app); paragraph editing collapses to a single plain-text run per keystroke (rich multi-run inline editing, and list/heading/blockquote editing, remain out of scope); inline links are dropped from the AST on the first edit of a paragraph that contains them; `Image.asset` cannot load real note images (placeholder only).

## v1.1.0
- Completed **Epic A: Scaffolding & Core Engine** (`CORE-A001`, `CORE-A002`, `CORE-A003`), total 10 story points.
- Monorepo scaffolded using `flutter_rust_bridge` (v2), Markdown AST parser implemented with `pulldown-cmark`, and AST/FFI API contracts exposed across the FFI boundary to Dart.

## v1.0.1
- Recorded Phase 0 (tooling readiness), executed ahead of `CORE-A001`. It provisions the reproducible `devenv` environment and the pre-commit quality gates; it adds no application code and consumes no story points, so the critical path and totals are unchanged.
- Every file it introduces falls outside the `Scope (In-Scope Files)` of Epics A/B/C by design. `CORE-A001` keeps `Dependencies: None`, but its verification commands are now expected to run inside the devenv shell, per the Toolchain section of `tech-spec/guidelines.md`.
- Added a note to `CORE-A001`: FRB scaffolds vendored third-party Dart under `rust_builder/cargokit/`, which must be excluded via `analyzer.exclude` in `analysis_options.yaml` or the `dart analyze` gate will fail on code the project does not own.
- Corrected the `UIDB-B002` acceptance criterion, which asserted AES-256-GCM. SQLCipher 4.x is AES-256-CBC with HMAC-SHA512 page authentication; see `tech-spec/stack.md` v1.0.1.

## v1.0.0
- Initial formulation of the execution constitution.
- Created active backlog totaling 52 Story Points.
- Sequenced work into Desktop-first phased delivery (Epic A: Scaffolding, Epic B: UI/DB, Epic C: Security/Sync).
- Mapped Build Order diagram and defined critical path.
