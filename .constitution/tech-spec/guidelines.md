# Project Structure & Guidelines

## Monorepo Layout (Standard FRB Template)
The repository follows the default `flutter_rust_bridge` template structure to minimize custom build script overhead.

```text
/
├── .constitution/       # AI Project Development Framework artifacts
├── .envrc                   # direnv entrypoint; activates the devenv shell
├── devenv.nix               # Developer environment: toolchains, native deps, git hooks
├── devenv.yaml              # devenv inputs (nixpkgs, rust-overlay, git-hooks)
├── devenv.lock              # Pinned input revisions; the reproducibility boundary
├── rust-toolchain.toml      # Rust version pin, read by devenv and by rustup
├── android/             # Flutter Android build files
├── ios/                 # Flutter iOS build files
├── lib/                 # Dart/Flutter UI source code
│   ├── main.dart
│   ├── src/
│   │   ├── components/  # Reusable UI blocks
│   │   ├── providers/   # Riverpod state definitions
│   │   └── rust/        # Auto-generated FRB Dart bindings
├── macos/               # Flutter macOS build files
├── rust/                # Rust Core Engine source code
│   ├── Cargo.toml
│   ├── src/
│   │   ├── api/         # FFI interface exposed to Dart
│   │   ├── db/          # rusqlite database management
│   │   ├── git/         # gix integration
│   │   └── markdown/    # AST parsing logic
├── pubspec.yaml         # Dart dependencies
└── flutter_rust_bridge.yaml # FRB configuration
```

## Toolchain
All commands below assume the `devenv` shell (`devenv shell`, or automatic via
`direnv`). Toolchain versions are pinned there and in `rust-toolchain.toml`; see
`stack.md` for the compatibility policy.

## Coding Standards
1. **Rust:**
   - Must pass `cargo clippy -- -D warnings`.
   - Must be formatted with `cargo fmt`.
   - Avoid async/await unless absolutely necessary (e.g., long-running sync operations on a dedicated thread). Local index queries remain synchronous for maximum performance.
2. **Dart:**
   - Must pass `dart analyze`.
   - Must be formatted with `dart format`.
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB.
3. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for the hybrid editor rendering (verifying AST nodes render correctly).
