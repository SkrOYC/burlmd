# burlmd

A local-first, Git-backed note-taking application. Notes live as plain Markdown in a repository you own; the app provides a Live Preview Markdown editor, a lateral knowledge graph over the directory tree, and a planned private GitHub Remote without a central content broker.

A Flutter UI renders state produced by a Rust core engine across a
`flutter_rust_bridge` boundary. The core owns Markdown parsing, the encrypted
SQLite index, Git plumbing via `gix`, and all cryptographic material.

Editing is Live Preview: the Block you are in shows the real Markdown source,
every other Block renders as it will read — no hidden syntax, ever. Notes live
in an Open Knowledge Format bundle that any tool or agent can read directly.

The full product requirements, solution architecture, technical implementation,
and execution specifications live under [`.constitution/`](.constitution/). Start with
[`prd/vision.md`](.constitution/prd/vision.md) and
[`tech-spec/stack.yaml`](.constitution/tech-spec/stack.yaml).

## Status

Epics A through F are complete. The application opens directly into a local
Workspace without a login gate. The shell provides Directory navigation,
full-text search, and recovery for unpersisted edits. The editor provides
Live Preview, cross-Block selection and copy, structural editing, emphasis
shortcuts, Link completion and follow, and atomic multi-Block range edits.

The complete forward backlog is active: ten epics contain 80 tickets and 564 story points. The five `Spike` tickets are research-only and executable within their declared allowlists after their dependencies are satisfied. Contract-scoped production authorization covers `BURL-G001`, `BURL-G002`, `BURL-G003`, `BURL-G004`, `BURL-G005`, `BURL-G007`, `BURL-M015`, and `BURL-M003`. Every other production ticket remains blocked. See [the critical path](.constitution/tasks/critical-path.md) for the authoritative execution rules.

Desktop targets are x86-64 Linux and Apple Silicon macOS. The forward plan covers durable desktop sessions, canonical Workspace authority, Assets and first-class S3-compatible Object Storage, Export and Consolidation, a private GitHub Remote, reconciliation, diagnostics, packaging, and unsigned `0.x` releases. Authoritative Object Store deletion during `0.x`, mobile targets, multiple simultaneous Workspaces, graph visualization, HTML Publishing, a second Remote provider, self-updating binaries, and prerelease signing remain deferred.

## Getting started

The toolchain is provisioned entirely by [devenv](https://devenv.sh) — you do not
install Flutter, Dart or Rust yourself. Package registries are a separate matter:
`pub` and `cargo` still resolve into `~/.pub-cache` and `~/.cargo/registry`
outside the store, pinned by `pubspec.lock` and `Cargo.lock` once those exist.

These are the commands devenv itself documents at
<https://devenv.sh/getting-started/>; follow that page if it has moved on.

```bash
# One-off, if you don't already have them.
sh <(curl -L https://nixos.org/nix/install) --daemon                 # Nix
nix-env --install --attr devenv \
  -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable       # devenv

# Then, from the repository root
devenv shell
```

devenv states no minimum Nix version. The `devenv` CLI is not covered by
`devenv.lock` — see the note below the table.

With [direnv](https://direnv.net) installed, `direnv allow` activates the
environment automatically whenever you `cd` into the repository.

The first entry builds the shell and may take several minutes. Subsequent entries
are near-instant.

Everything below was exercised on Linux only. macOS is *expected* to work — the
Flutter pin advertises both Darwin platforms — but no one has entered this shell
on a Mac, so treat it as unverified. Two known rough edges there: `clang` is in
`packages` unconditionally and would sit alongside the stdenv one, and
`bundled-sqlcipher` links Security/CommonCrypto rather than the `openssl` this
environment supplies. A macOS contributor also needs Xcode and CocoaPods from
outside the Nix store.

## What the environment provides

| Tool | Version | Pinned by |
| --- | --- | --- |
| Flutter (bundles Dart) | 3.44.3 / Dart 3.12.2 | `nixpkgs` via `devenv.nix` |
| Rust | 1.97.1 | [`rust-toolchain.toml`](rust-toolchain.toml) |
| `flutter_rust_bridge_codegen` | 2.12.0 | `nixpkgs` via `devenv.nix` |
| SQLCipher CLI | 4.16.0 | `nixpkgs` via `devenv.nix` |

`BURL-B002` adds `rusqlite` with `bundled-sqlcipher`; the app links the vendored
SQLCipher **4.14.0**, not the CLI above. The two float independently; the CLI is
present only for inspecting the encrypted index during development.

No Android SDK is provisioned — mobile is out of product scope — but discovery
is pinned shut. `ANDROID_HOME` and `ANDROID_SDK_ROOT` point at a deliberately
empty in-repo path, because Flutter otherwise scans well-known home-directory
locations and silently adopts whatever SDK you happen to have installed. That
was the one part of the toolchain `devenv.lock` could not govern. `CHROME_EXECUTABLE`
is pinned shut the same way, for the same reason — the web target is no more in
scope than mobile, and left alone Flutter resolves a browser off the host `PATH`.

So `flutter doctor` deliberately reports **two** failing categories, identically
on every machine, and that is the intended state until those targets are
unshelved:

```text
[✗] Android toolchain - develop for Android devices
    ✗ ANDROID_HOME = <repo>/.sentinels/no-android-sdk
      but Android SDK not found at this location.
[✗] Chrome - develop for the web (Cannot find Chrome executable at
    <repo>/.sentinels/no-chrome)
```

It also carries the native dependencies the stack needs and that are easy to get
wrong: the GTK/GL stack for the Flutter Linux embedder, `libclang` for the
`bindgen` step inside `libsqlite3-sys`, and `openssl` for the SQLCipher build.
No Secret Service library is needed — `keyring` 4.x talks D-Bus in pure Rust via
`zbus`.

Exact versions are locked in `devenv.lock`. To move them forward, run
`devenv update` and re-verify.

One caveat on that boundary: `devenv.lock` pins the inputs, not the `devenv` CLI
that reads it. The CLI is installed from whatever nixpkgs your Nix resolves, and
module compatibility is not guaranteed across CLI majors. This environment is
verified against devenv 2.1.2.

## Quality gates

Entering the shell installs Git pre-commit hooks enforcing the standards in
[`.constitution/tech-spec/guidelines.md`](.constitution/tech-spec/guidelines.md):

- `nixfmt` runs on changed `*.nix` files, excluding `.constitution/`.
- `cargo fmt --all -- --check` checks Rust source changes.
- `cargo clippy --workspace --all-targets -- -D warnings` checks Rust source,
  Cargo manifest, lockfile, and toolchain changes.
- `dart format --output=none --set-exit-if-changed lib test integration_test test_driver`
  checks Dart source changes in the project-owned roots.
- `dart analyze` runs for Dart source or `pubspec.yaml` changes and analyzes the
  root package. The analyzer excludes the vendored `rust_builder/cargokit/`
  sources.

The language hooks are active because the manifests each one needs
(`rust/Cargo.toml`, `pubspec.yaml`) exist. They fail loudly rather than silently
skipping if a manifest turns up somewhere unexpected. All of them exclude
`.constitution/`, so editing the tech-spec's `ffi_api.rs` contract does not
trigger a build gate.

These are the only automated gates. There is no CI, and nothing runs tests.

## Verification performed

The environment was not assumed to work — it was exercised. Inside the shell:

- `flutter doctor` reports `[✓] Linux toolchain` and `[✓] Connected device`
  with a Linux desktop target. The Linux row carries one warning,
  `! Unable to access driver information using 'eglinfo'`, because `mesa-demos`
  is deliberately not in the closure; it does not affect builds.
- `flutter create` followed by `flutter build linux --release` produces a running
  bundle.
- A throwaway Rust crate depending on `rusqlite` (`bundled-sqlcipher`), `gix`,
  `keyring` and `pulldown-cmark` compiles, and its tests execute an FTS5 `MATCH`
  query against a keyed SQLCipher connection.

Two findings from that exercise were reconciled back into the tech-spec (see
`.constitution/tech-spec/changelog.yaml`, v1.0.1): the Rust pin must be ≥ 1.95, and
`rusqlite` 0.40 no longer exposes an `fts5` feature.
