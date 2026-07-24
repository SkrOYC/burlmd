# Project Structure & Guidelines

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
│   │   └── screens/         # Full-screen routes (e.g. login.dart)
├── test/                    # Dart widget tests
├── rust/                    # Rust Core Engine source code
│   ├── Cargo.toml
│   ├── tests/               # Rust integration tests
│   ├── src/
│   │   ├── api/             # FFI interface exposed to Dart (thin #[frb] wrappers)
│   │   ├── db/              # rusqlite database management
│   │   ├── draft.rs         # Active-draft-state domain: NoteState/NoteMetadata,
│   │   │                      the open-note cache, block_path-addressed edits
│   │   ├── error.rs         # Shared AppError, so db/security don't depend on api
│   │   ├── git/             # gix integration
│   │   ├── index/           # Bundle -> SQLite indexer: notes, notes_fts,
│   │   │                      fts_mapping, links, directories; full and
│   │   │                      incremental. Owns reindex_workspace.
│   │   ├── markdown/        # AST parsing logic; owns the span map (ADR-007)
│   │   ├── okf/             # OKF v0.2 bundle domain: frontmatter read/validate,
│   │   │                      concept-id <-> path, link target resolution,
│   │   │                      reserved-filename rules
│   │   ├── security/        # OS Keychain root-key integration
│   │   ├── sync/            # Debounced background sync scheduler
│   │   ├── workspace/       # Workspace lifecycle: init/open, note & directory
│   │   │                      CRUD, atomic write, the ADR-008 tiers
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
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB. Ephemeral selection coordinates (`block_path` plus character offset) are UI state, not note content, and are exempt — this is what allows cross-Block selection under ADR-006 without amending `architecture/containers.md`.
   - The rendered and raw presentations of a Block must be typographically identical. Only the text differs (`**bold**` versus bold); font, size, weight, line height, and padding must not, or the Block visibly jumps when it takes focus.
3. **Nix:**
   - Every `*.nix` file must be formatted with `nixfmt` (RFC style). Today that is only `devenv.nix`.
4. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for editor rendering (verifying AST nodes render correctly).
   - **Round-trip property tests are mandatory for the splice path.** For any Note and any Block, splicing that Block's own unmodified source back over its span must produce a byte-identical file. This is the executable form of the Edit Fidelity constraint and is cheap to state as a property over a corpus of fixture Notes, including ones with frontmatter keys the application does not manage.
   - **Every ticket touching UI must launch the real application in its Verification Command.** Not `flutter test` alone. The gap this closes is documented under "Running the real app" below: through Epic B, no ticket's gate ever started the app, and a real regression shipped that six passing widget tests could not see.

## Terminology introduced at this layer

`prd/glossary.md` owns the product vocabulary and deliberately holds no implementation terms. Four terms this specification introduces are load-bearing across the contract, the ADRs and every Epic D ticket, and are defined here because they belong to the physical layer:

| Term | Definition |
| :--- | :--- |
| Concept id | A Note's identity under OKF §2: its bundle-relative path with `.md` removed. Unique within a bundle, **not** globally, which is why ADR-005 decision 7 makes exactly one Workspace active. Stored as `notes.id`. |
| Working source | The single in-memory buffer holding an open Note's full current text — byte-identical to what `drafts.raw_markdown` persists for it. It is what `update_block` substitutes into and what the tier 2 write copies verbatim. |
| Span map | The Core-side map from `block_path` to a byte range in the working source. Never crosses the FFI boundary and never appears on the AST (ADR-007 decision 3). |
| Block path | An index path into a Note's AST, addressing one Block. **Not stable across any reparsing call** — a splice can change a Block's node shape — so callers re-derive it from the returned state rather than retaining it. |

The distinction most worth stating: the **working source** is not the draft row. They hold the same bytes, but the buffer is the live editing state and the row is its crash-durable copy, and tier 2 clears the row while the buffer persists until the Note closes. Conflating them makes "a draft row exists" mean "a Note is open", which is false in both directions.

## Index connection obligations

Every connection opened against the encrypted index must issue `PRAGMA foreign_keys = ON` before any other statement. SQLite defaults it off and does not persist it in the file, so it is a property of the connection rather than of the database. The entire key design in `data-models/schema.sql` depends on it: with the pragma off the `ON UPDATE CASCADE` clauses that make a rename possible do not error, they silently do not fire, and the result is orphaned `links` and `fts_mapping` rows with nothing to signal the loss. Today only `init_schema` reliably runs on the singleton connection, while `open_encrypted_db_with_key` is reachable without it — which is how the tests use it.

`PRAGMA user_version` is the other connection-time concern, in the opposite direction: it must be *read* on open and written only when it reads 0. `init_schema` replays the whole schema batch on every open, so a `user_version` assignment left inside that batch would reset a migrated database to the baseline every time it was opened.

## Workspace location

The default local Workspace (ADR-005 decision 1) resolves to `$XDG_DATA_HOME/burlmd/workspace`, falling back to `~/.local/share/burlmd/workspace` when `XDG_DATA_HOME` is unset, and to `~/Library/Application Support/burlmd/workspace` on macOS.

This is deliberately *not* a visible directory in the user's home. The bundle is a Git repository the application manages, and CAP-WS-05 already provides the path for pointing burlmd at a Workspace the user placed wherever they prefer. Moving this default later is a user-visible migration, so it is recorded here rather than left to the implementation.

The encrypted index does not live inside the bundle. It is derived state (`data-models/schema.sql`), and placing it in the bundle would put an encrypted binary blob inside a Git repository whose entire premise is human-readable plaintext, producing a large opaque diff on every write. It belongs alongside the Workspace, not within it: it resolves to `$XDG_DATA_HOME/burlmd/index.sqlite3` — a *sibling* of the bundle root inside the shared `burlmd/` parent, not a file within the bundle and not an ancestor of it — with the same fallbacks as the Workspace path above, and `BURLMD_DB_PATH` continuing to override it for tests.

This is a change from what the code does today. `rust/src/db/connection.rs` resolves `$HOME/.burlmd/index.sqlite3`, a placeholder written in Epic B before any Workspace path existed and never reconciled with one. `WSPC-D004` moves it. Because that ticket also rewrites the index schema, an index file left at the old path by a development build is not migrated and not read — it is stale derived state under a path this specification no longer names, and the bundle it was derived from can rebuild it.

The *mechanical* rules above — `cargo fmt`, `cargo clippy`, `dart format`,
`dart analyze`, `nixfmt` — are enforced as pre-commit hooks installed on entry
to the devenv shell. All of them exclude `.constitution/`, so editing the spec's
FFI contract does not trigger a build gate. The four *language* hooks
additionally no-op until their manifests exist; `nixfmt` has no manifest to wait
on and runs today.

Once real Rust code exists, `cargo clippy --workspace --all-targets` on every
`.rs` commit will be a multi-minute gate — `bundled-sqlcipher` compiles the
SQLCipher amalgamation from source, and `--all-targets` additionally builds tests
and benches. Consider moving clippy to the `pre-push` stage at that point,
leaving `cargo fmt` on `pre-commit`.

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

For actually looking at rendered output rather than only asserting widget
properties in `flutter test` — screenshot with `grim`, and, when keystroke
simulation is needed, inject text with `wtype` (both provisioned in
`devenv.nix` for this purpose; Wayland-only, not part of the CI/build path).
This caught a real regression during Epic B's closeout that six passing
`flutter test` cases missed entirely: every test's paragraphs happened to be
single-run, so the bug (a multi-run paragraph silently collapsing to one
uniform, unstyled `TextField` once made editable) was invisible to the suite
until an actual rendered screenshot was inspected.
