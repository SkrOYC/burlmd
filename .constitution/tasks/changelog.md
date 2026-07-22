# Stage 4: Tasks Changelog

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
