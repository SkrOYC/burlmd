# Project Structure & Guidelines

## Commits
This repository uses [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): summary`, with types `feat`, `fix`, `docs`, `chore`, `refactor`, and
`test`; scope names the area (`docs(prd)`, `fix(editor)`). The history has followed
this shape since Epic A; it is documented here so review can hold work to it rather
than infer it.

## Monorepo Layout (Standard FRB Template)
The repository follows the default `flutter_rust_bridge` template structure to minimize custom build script overhead.

```text
/
├── .agents/                 # Agent skill definitions (Dart/Flutter workflows)
├── .constitution/           # AI Project Development Framework artifacts
├── .envrc                   # direnv entrypoint; activates the devenv shell
├── .gitignore
├── README.md                # Onboarding: how to enter the environment
├── devenv.nix               # Developer environment: toolchains, native deps, git hooks
├── devenv.yaml              # devenv inputs (nixpkgs, rust-overlay, git-hooks)
├── devenv.lock              # Pinned input revisions; the reproducibility boundary
├── rust-toolchain.toml      # Rust version pin, read by devenv and by rustup
├── linux/                   # Flutter Linux build files (in-scope target)
├── macos/                   # Flutter macOS build files (in-scope target)
├── lib/                     # Dart/Flutter UI source code
│   ├── main.dart
│   ├── src/
│   │   ├── components/      # Reusable UI blocks
│   │   ├── providers/       # Riverpod state definitions
│   │   ├── rust/            # Auto-generated FRB Dart bindings
│   │   └── screens/         # Full-screen routes (workspace.dart, login.dart —
│   │                        #   login retained for the deferred connect flow,
│   │                        #   no longer a startup gate since SHEL-E002)
├── scripts/                 # smoke-shot.sh — the manual-QA smoke harness
│                              every UI ticket gates on (SHEL-E001); writes
│                              screenshots to .qa/, which is gitignored
├── test/                    # Dart widget tests
├── rust/                    # Rust Core Engine source code
│   ├── Cargo.toml
│   ├── tests/               # Rust integration tests
│   ├── src/
│   │   ├── api/             # FFI interface exposed to Dart (thin #[frb] wrappers)
│   │   │   ├── auth.rs      # OAuth flow, token storage, session state
│   │   │   ├── ffi_api.rs   # The contract surface
│   │   │   └── simple.rs    # FRB template init hook (outside the contract)
│   │   ├── db/              # rusqlite database management
│   │   ├── draft.rs         # Active-draft-state domain: NoteState/NoteMetadata,
│   │   │                      the open-note cache, block_path-addressed edits
│   │   ├── error.rs         # Shared AppError, so db/security don't depend on api
│   │   ├── git/             # gix integration
│   │   ├── index/           # Bundle -> SQLite indexer: notes, notes_fts,
│   │   │                      fts_mapping, links, directories. `scan` (full
│   │   │                      walk, owns reindex_workspace), `incremental`
│   │   │                      (single-Note reindex, content_hash
│   │   │                      short-circuit), `query` (read paths: search,
│   │   │                      backlinks, tree, title prefix).
│   │   ├── markdown/        # AST parsing logic; owns the span map (ADR-007).
│   │   │                      `parser`/`ast` (parse to Block tree), `spans`
│   │   │                      (span map + its invariants), `splice`
│   │   │                      (span-preserving source edits)
│   │   ├── okf/             # OKF v0.2 bundle domain: `frontmatter` (read and
│   │   │                      validate), `concept_id` (concept-id <-> path,
│   │   │                      reserved-filename rules), `links` (target
│   │   │                      resolution and serialization)
│   │   ├── security/        # OS Keychain root-key integration
│   │   ├── sync/            # Debounced background sync scheduler
│   │   ├── workspace/       # `bootstrap` (init/open, Git repo adoption),
│   │   │                      `lifecycle` (note & directory create/rename/
│   │   │                      move/delete, atomic write), `links_rewrite`
│   │   │                      (inbound-Link source rewriting on rename),
│   │   │                      `persist` (the ADR-008 tiers and their locks)
│   │   └── test_support.rs  # #[cfg(test)]-only fixtures shared across unit test modules
├── pubspec.yaml             # Dart dependencies
└── flutter_rust_bridge.yaml # FRB configuration
```

`android/` and `ios/` are absent by design: mobile targets are deferred per
`tasks/critical-path.md`, and no mobile toolchain is provisioned. `ANDROID_HOME`
is pointed at an in-repo path that deliberately holds no SDK, so Flutter cannot silently
adopt an SDK from the contributor's home directory; see `stack.md`.

## Toolchain
All commands below assume the `devenv` shell (`devenv shell`, or automatic via
`direnv`). Toolchain versions are pinned there and in `rust-toolchain.toml`; see
`stack.md` for the compatibility policy.

## Coding Standards
1. **Rust:**
   - Must pass `cargo clippy -- -D warnings`.
   - Must be formatted with `cargo fmt`.
   - Avoid async/await unless absolutely necessary (e.g., long-running sync operations on a dedicated thread). Local index queries remain synchronous for maximum performance, except where `tech-spec/contracts/ffi_api.rs` itself declares a function `async` (e.g. `search_notes`) — the contract's FFI-boundary signature takes precedence over this preference; the function's own body should still execute synchronously to completion rather than actually yielding to an executor.
   - Source spans are Core-side state, keyed by `block_path`, and must never be added as fields on `AstNode` or otherwise cross the FFI boundary (ADR-007 decision 3). The UI cannot use byte offsets into a file it does not own, and carrying them would inflate every edit round trip against the 16ms budget — `architecture/risks.md` risk 1.
   - No code path may rewrite bytes outside the span of an edited Block. This is the Edit Fidelity constraint in `prd/constraints.md` and it is the reason no AST-to-Markdown serializer exists for the save path; adding one for that path reintroduces exactly the failure the constraint forbids.
2. **Dart:**
   - Must pass `dart analyze`.
   - Must be formatted with `dart format`.
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB. Ephemeral selection coordinates (`block_path` plus Flutter UTF-16 rendered offset) are UI state, not note content, and are exempt — this is what allows cross-Block selection under ADR-006 without amending `architecture/containers.md`.
   - The rendered and raw presentations of a Block must be typographically identical. Only the text differs (`**bold**` versus bold); font, size, weight, line height, and padding must not, or the Block visibly jumps when it takes focus.
   - **Every error returned across the FFI boundary must reach a user-visible surface.** No call site may swallow a Core error. This rule exists because the editor shipped through Epic B with no error path at all — failures crossed the boundary and were discarded, a gap Epic B's review recorded but could not reach until the editor was mounted (`SHEL-E004`, which landed the shell's error surface).
   - **Shell surfaces coordinate through provider seams, not widget ownership.** Note selection flows through the shared selection seam (`selectedNoteIdProvider`) so the tree, editor and lifecycle actions stay coherent without referencing each other; the Directory tree renders from the Core's single whole-tree payload (one call, children nested) and holds only expansion state as ephemeral UI state. Note switching must close the outgoing Note through the Core before opening the next, so its session reaches the commit tier (`SHEL-E004`).
   - **Link-completion grammar is fixed.** A completion is eligible only when a collapsed caret has a last unmatched `[[` on the same line before it; its query is the intervening text. The UI snapshots that exact trigger range and source value, requests no more than 10 Core candidates, and rejects/dismisses the list if a newline, `]]`, focus/selection change, or edit invalidates the snapshot. Core supplies either an existing candidate or a distinguishable prospective ghost when the query is a valid future target. Acceptance replaces the snapshot range with the Core-supplied `LinkCompletion.insert_text`; no Dart code may construct or repair a destination. Follow always re-resolves first, then calls `create_link_target(target_id)` only for a still-missing target.
   - **A cross-Block selection uses one direct `TextInputClient` proxy, not a hidden `TextField`.** Its initial/current proxy value is `TextEditingValue.empty`; after `TextInput.attach`, it calls `setEditingState` with that value before `show`. It owns exactly one `TextInputConnection`, resets the empty platform value after a Core result, and closes before promotion or disposal. `updateEditingValue` handles only ordinary committed text/IME; an `Actions`/`Shortcuts` layer compatible with Flutter 3.44.3 `DefaultTextEditingShortcuts` explicitly handles Delete/Backspace and clipboard copy/cut/paste intents. While `TextEditingValue.composing` is valid and non-collapsed it neither mutates Core nor replaces the platform value. `RangeEditResult` is a present atomic operation, compatible with later undo but not an implementation of deferred CAP-EDIT-08 (ADR-012).
3. **Nix:**
   - Every `*.nix` file must be formatted with `nixfmt` (RFC style). Today that is only `devenv.nix`.
4. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for editor rendering (verifying AST nodes render correctly).
   - **Round-trip property tests are mandatory for the splice path.** For any Note and any Block, splicing that Block's own unmodified source back over its span must produce a byte-identical file. This is the executable form of the Edit Fidelity constraint and is cheap to state as a property over a corpus of fixture Notes, including ones with frontmatter keys the application does not manage.
   - **Every ticket touching UI must launch the real application in its Verification Command.** Not `flutter test` alone. The gap this closes is documented under "Running the real app" below: through Epic B, no ticket's gate ever started the app, and a real regression shipped that six passing widget tests could not see.

5. **Accessibility (standing standard, adopted before Epic E paints widgets):**
   - Keyboard completeness is a hard review bar: every capability reachable by pointer is reachable by keyboard, and focus order follows visual order.
   - Every user-visible widget carries Flutter `Semantics` labels as it is written — not retrofitted. Screen-reader certification is deferred scope (`prd/out-of-scope/screen-reader-certification.md`); semantic structure is not.
6. **Internationalization readiness (standing standard, same timing):**
   - User-facing strings externalize through Flutter `gen-l10n` from the first screen onward; no new hardcoded UI text lands once Epic E begins.
   - No translation effort is scheduled; this standard exists because retrofitting string extraction across painted screens is a sweep nobody enjoys.
   - The current repository has **no** `l10n.yaml`, ARB source, or generated localization output despite that standing rule. `EDIT-F006` must establish `flutter: generate: true`, `l10n.yaml`, and `lib/l10n/app_en.arb` before it adds completion, Link, or create-offer strings. It runs `flutter pub add "flutter_localizations@{sdk: flutter}" intl@0.20.2`, committing `pubspec.lock`; `intl` `0.20.2` is the direct requirement of pinned Flutter 3.44.3 `flutter_localizations`. Its pinned configuration is `arb-dir: lib/l10n`, `output-dir: lib/l10n/generated`, `output-localization-file: app_localizations.dart`, and imports `package:burlmd/l10n/generated/app_localizations.dart`. `flutter gen-l10n --help` confirms synthetic packages cannot be enabled in this SDK and default output is the ARB directory, so the explicit output directory is required. `lib/l10n/generated/**` is repository-owned generated Dart: refresh it with `flutter gen-l10n` and commit it with its ARB/config change; never hand-edit it.

## Persistence lock rules

`rust/src/workspace/persist.rs` uses this acquisition order: lifecycle, tier 2 write, tier 1, state, then connection. A caller can take a suffix of this order, but it must not acquire these locks in reverse order.

- The per-Note tier 1 lock serializes a source mutation through its draft write and serializes lifecycle state installation with that mutation.
- The state lock protects the in-memory snapshot and must not span database or filesystem I/O.
- No closure passed to `with_connection` may perform file I/O.
- No lock that a keystroke can contend for may span an `fsync`.
- Tier 2 writes must use the per-Note tier 2 write lock for the full OCC check, file write, and revision re-record sequence.

## Terminology introduced at this layer

`prd/glossary.md` owns the product vocabulary and deliberately holds no implementation terms. Four terms this specification introduces are load-bearing across the contract, the ADRs and every Epic D ticket, and are defined here because they belong to the physical layer:

| Term | Definition |
| :--- | :--- |
| Concept id | A Note's identity under OKF §2: its bundle-relative path with `.md` removed. Unique within a bundle, **not** globally, which is why ADR-005 decision 7 makes exactly one Workspace active. Stored as `notes.id`. |
| Working source | The single in-memory buffer holding an open Note's full current text — byte-identical to what `drafts.raw_markdown` persists for it. It is what `update_block` substitutes into and what the tier 2 write copies verbatim. |
| Span map | The Core-side map from `block_path` to a byte range in the working source. Never crosses the FFI boundary and never appears on the AST (ADR-007 decision 3). |
| Block path | An index path into a Note's AST, addressing one Block. **Not stable across any reparsing call** — a splice can change a Block's node shape — so callers re-derive it from the returned state rather than retaining it. |

The distinction most worth stating: the **working source** is not the draft row. They hold the same bytes, but the buffer is the live editing state and the row is its crash-durable copy, and tier 2 clears the row while the buffer persists until the Note closes. Conflating them makes "a draft row exists" mean "a Note is open", which is false in both directions.

## Editor-depth verification commands

The active editor-depth tickets quote these commands exactly. `BURLMD_SMOKE_F005`, `BURLMD_SMOKE_F006`, and `BURLMD_SMOKE_F007` are required readiness inputs: the smoke harness must reject a generic Workspace window and capture only after the named staged interaction is ready.

- `flutter test test/components/emphasis_shortcuts_test.dart && BURLMD_SMOKE_F005=1 ./scripts/smoke-shot.sh f005-emphasis && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target && cargo test --lib --manifest-path rust/Cargo.toml create_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml create_link_target && flutter_rust_bridge_codegen generate && flutter gen-l10n && flutter test test/components/link_completion_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F006=1 ./scripts/smoke-shot.sh f006-link-completion && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate && cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_editing_test.dart test/components/text_input_client_test.dart test/components/selection_test.dart && BURLMD_SMOKE_F007=1 ./scripts/smoke-shot.sh f007-range-editing && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`

## Index connection obligations

Every connection opened against the encrypted index must issue `PRAGMA foreign_keys = ON` immediately after the key pragma, and before any statement that touches a table. SQLite defaults it off and does not persist it in the file, so it is a property of the connection rather than of the database.

The ordering is stated that precisely because an earlier revision said *before any other statement*, which is unsatisfiable here: on a SQLCipher connection `rust/src/db/connection.rs` must issue `PRAGMA key` first, then the `SELECT count(*) FROM sqlite_master` unlock probe. An obligation the file it cites cannot meet invites the reader to discount the whole rule. The entire key design in `data-models/schema.sql` depends on it: with the pragma off the `ON UPDATE CASCADE` clauses that make a rename possible do not error, they silently do not fire, and the result is orphaned `links` and `fts_mapping` rows with nothing to signal the loss. Today only `init_schema` reliably runs on the singleton connection, while `open_encrypted_db_with_key` is reachable without it — which is how the tests use it.

`PRAGMA user_version` is the other connection-time concern, in the opposite direction: it must be *read* on open and written only when it reads 0. `init_schema` replays the whole schema batch on every open, so a `user_version` assignment left inside that batch would reset a migrated database to the baseline every time it was opened.

## Workspace location

The default local Workspace (ADR-005 decision 1) resolves to `$XDG_DATA_HOME/burlmd/workspace`, falling back to `~/.local/share/burlmd/workspace` when `XDG_DATA_HOME` is unset, and to `~/Library/Application Support/burlmd/workspace` on macOS.

This is deliberately *not* a visible directory in the user's home. The bundle is a Git repository the application manages, and CAP-WS-05 already provides the path for pointing burlmd at a Workspace the user placed wherever they prefer. Moving this default later is a user-visible migration, so it is recorded here rather than left to the implementation.

The encrypted index does not live inside the bundle. It is derived state (`data-models/schema.sql`), and placing it in the bundle would put an encrypted binary blob inside a Git repository whose entire premise is human-readable plaintext, producing a large opaque diff on every write. It belongs alongside the Workspace, not within it: it resolves to `$XDG_DATA_HOME/burlmd/index.sqlite3` — a *sibling* of the bundle root inside the shared `burlmd/` parent, not a file within the bundle and not an ancestor of it — with the same fallbacks as the Workspace path above, and `BURLMD_DB_PATH` continuing to override it for tests.

`WSPC-D004` moved the code to this path. `rust/src/db/connection.rs` previously resolved `$HOME/.burlmd/index.sqlite3`, a placeholder written in Epic B before any Workspace path existed and never reconciled with one; it now resolves the path above, with a test asserting the legacy location is neither read nor created. Because that ticket also rewrote the index schema, an index file left at the old path by a development build is not migrated and not read — it is stale derived state under a path this specification no longer names, and the bundle it was derived from can rebuild it.

The *mechanical* rules above — `cargo fmt`, `cargo clippy`, `dart format`,
`dart analyze`, `nixfmt` — are enforced as pre-commit hooks installed on entry
to the devenv shell. All of them exclude `.constitution/`, so editing the spec's
FFI contract does not trigger a build gate. The four *language* hooks each guard
on their manifest, but `rust/Cargo.toml` and `pubspec.yaml` both exist as of
Epic A, so all five hooks run on every applicable commit today.

`cargo clippy --workspace --all-targets` on every `.rs` commit is therefore a
live gate now. Against a warm `target/` it costs ~20s (measured at Epic D's
close, on a tree where the dev-profile dependencies were already built). The
multi-minute case is a cold or invalidated `target/` — `bundled-sqlcipher`
compiles the SQLCipher amalgamation from source, and `--all-targets`
additionally builds tests and benches, so a toolchain or feature bump pays for
all of it inside the commit. The standing suggestion is unchanged and still not
acted on: consider moving clippy to the `pre-push` stage, leaving `cargo fmt` on
`pre-commit`.

Nothing enforces the rest, and no CI runs today. The testing standard, the Rust
async-avoidance rule and the Dart widget-statelessness rule are review
obligations, not gated checks.

## Running the real app (manual visual verification)

No ticket's Verification Command through Epic B ever actually launches the
built app (`cargo build`/`cargo test` exercise the Rust half in isolation;
`flutter test` exercises the Dart half against fakes) — so `flutter run`
launching successfully, and the UI actually rendering correctly, had never
once been checked. `flutter run -d linux` in debug mode crashes on startup:
`flutter_rust_bridge`'s generated Dart loader
(`lib/src/rust/frb_generated.dart`, `ioDirectory: 'rust/target/release/'`)
looks for the native library at `rust/target/release/librust.so`, resolved
relative to the process's working directory — a location distinct from the
`bundled-sqlcipher` debug artifact `cargokit` builds into
`build/linux/x64/debug/bundle/lib/librust.so` for the actual app bundle.
Before running the desktop app locally (`flutter run -d linux`, or any manual
visual check), run `cargo build --release` once from `rust/` (and again after
any change to the Rust API surface) so that path exists.

Since `SHEL-E001` the procedure below is also a command: `scripts/smoke-shot.sh <name>` builds the release native library and app bundle, launches, waits for actual rendering, captures `.qa/<name>.png`, and exits non-zero if the application fails to start or render. `BURLMD_SMOKE_SHOT_DIR` may direct a deliberately reviewed evidence capture elsewhere; `SPK-EDIT-F001` is the sole current exception, with its four generated captures kept under `.constitution/evidence/edit-f001/`. Render detection compares raw pixels against a measured desktop noise floor rather than byte-comparing images, because background desktop animation always differs between two captures. Every UI ticket's Verification Command gates on it.

For actually looking at rendered output rather than only asserting widget
properties in `flutter test` — screenshot with `grim`, and, when keystroke
simulation is needed, inject text with `wtype` (both provisioned in
`devenv.nix` for this purpose; Wayland-only, not part of the CI/build path).
This caught a real regression during Epic B's closeout that six passing
`flutter test` cases missed entirely: every test's paragraphs happened to be
single-run, so the bug (a multi-run paragraph silently collapsing to one
uniform, unstyled `TextField` once made editable) was invisible to the suite
until an actual rendered screenshot was inspected.
