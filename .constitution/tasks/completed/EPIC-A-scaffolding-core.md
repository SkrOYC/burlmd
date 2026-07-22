# Epic A: Scaffolding & Core Engine

#### CORE-A001 Initialize FRB Monorepo
- **Type:** Chore
- **Effort:** 3
- **Dependencies:** None
- **Category:** DX
- **Scope (In-Scope Files):**
  - `pubspec.yaml`
  - `rust/Cargo.toml`
  - `flutter_rust_bridge.yaml`
- **Verification Command:** `flutter run -d macos` (or linux) and `cargo test`
- **Expected Success Output:** App builds and runs default FRB template, rust tests pass.
- **STOP Conditions:**
  - STOP if FFI generation fails due to missing system dependencies.
- **Description:** Set up the standard `flutter_rust_bridge` monorepo. Clear out the default counter code and establish the `rust/src/api` directory structure. FRB scaffolds `rust_builder/cargokit/` containing vendored third-party Dart that upstream says to ignore; add `analyzer.exclude` for it in `analysis_options.yaml`, or the `dart analyze` pre-commit hook will gate on code this project does not own. The `dart format` hook is already scoped to `lib/` and `test/` for the same reason.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a fresh clone of the repository
When I run `flutter_rust_bridge_codegen generate`
Then the Dart bindings are successfully generated without errors
And `cargo build` succeeds
```

##### CORE-A001 Deviations & Justifications
- **Touched Files:** `analysis_options.yaml`, `lib/`, `linux/`, `macos/`, `rust_builder/`, `integration_test/`, `test/`, `test_driver/`, `.metadata`, `pubspec.lock`
- **Justification:** Standard Flutter project initialization (`flutter create`) and `flutter_rust_bridge` monorepo integration (`flutter_rust_bridge_codegen integrate`) scaffolded platform build trees, cargokit wrapper package, default main entrypoint, and analysis exclusions required for Dart and Rust build support.


#### CORE-A002 Implement Markdown Parsing Logic
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** CORE-A001
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/markdown/parser.rs`
- **Verification Command:** `cargo test --color=always --package rust --bin rust`
- **Expected Success Output:** All unit tests pass.
- **STOP Conditions:**
  - STOP if `pulldown-cmark` fails to parse nested blocks correctly.
- **Description:** Build the Rust module that uses `pulldown-cmark` to parse raw Markdown text into the custom AST `AstNode` structures defined in the TechSpec.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a raw markdown string with headings and bold text
When the parsing function is called
Then it returns an AstNode tree containing the correct TextRuns
```

##### CORE-A002 Deviations & Justifications
- **Touched Files:** `rust/src/markdown/mod.rs`, `rust/src/lib.rs`, `rust/Cargo.toml`
- **Justification:** Created `rust/src/markdown/mod.rs` to expose `parser`, declared `pub mod markdown;` in `rust/src/lib.rs`, and added `pulldown-cmark` dependency to `rust/Cargo.toml` to support Markdown AST parsing.


#### CORE-A003 Expose AST over FFI
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** CORE-A002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/api/ffi_api.rs`
- **Verification Command:** `flutter_rust_bridge_codegen generate && cargo build`
- **Expected Success Output:** Code generation and compilation succeed.
- **Description:** Expose the AST data structures and the `open_note` synchronous parsing function across the `flutter_rust_bridge` boundary.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the parsed AST structures
When I run FRB codegen
Then the corresponding Dart classes (AstNode, TextRun) are available in `lib/src/rust/`
```

##### CORE-A003 Deviations & Justifications
- **Touched Files:** `pubspec.yaml`, `pubspec.lock`, `lib/src/rust/api/ffi_api.dart`, `lib/src/rust/api/ffi_api.freezed.dart`, `lib/src/rust/frb_generated.dart`, `lib/src/rust/frb_generated.io.dart`, `lib/src/rust/frb_generated.web.dart`, `rust/src/api/mod.rs`, `rust/src/frb_generated.rs`, `rust/src/markdown/mod.rs`, `rust/src/markdown/parser.rs`
- **Justification:** Added `freezed` and `build_runner` dependencies to `pubspec.yaml` required by `flutter_rust_bridge_codegen` for enum AST serialization across FFI, exported `ffi_api` in `rust/src/api/mod.rs`, updated `parser.rs` to import AST types from `ffi_api`, and generated Dart FFI binding files under `lib/src/rust/`.

