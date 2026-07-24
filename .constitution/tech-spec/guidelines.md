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
│   │   ├── markdown/        # AST parsing logic
│   │   ├── security/        # OS Keychain root-key integration
│   │   ├── sync/            # Debounced background sync scheduler
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
2. **Dart:**
   - Must pass `dart analyze`.
   - Must be formatted with `dart format`.
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB.
3. **Nix:**
   - Every `*.nix` file must be formatted with `nixfmt` (RFC style). Today that is only `devenv.nix`.
4. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for the hybrid editor rendering (verifying AST nodes render correctly).

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
