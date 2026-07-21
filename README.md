# burlmd

A local-first, Git-backed note-taking application. Notes live as plain Markdown in
a repository you own; the app gives you a Notion-like hybrid editor over them, a
lateral knowledge graph on top of the directory tree, and background sync to a
private GitHub repository over OAuth — with no central content broker in between.

A Flutter UI renders state produced by a Rust core engine across a
`flutter_rust_bridge` boundary. The core owns Markdown parsing, the encrypted
SQLite index, Git plumbing via `gix`, and all cryptographic material.

The full product, architecture, implementation and execution specifications live
under [`.constitution/`](.constitution/). Start with
[`prd/vision.md`](.constitution/prd/vision.md) and
[`tech-spec/stack.md`](.constitution/tech-spec/stack.md).

## Status

Phase 0 — tooling. The developer environment is complete and verified; no
application code exists yet. The first work item is `CORE-A001` in
[`.constitution/tasks/active/EPIC-A-scaffolding-core.md`](.constitution/tasks/active/EPIC-A-scaffolding-core.md),
which scaffolds the `flutter_rust_bridge` monorepo.

The current phase targets **desktop only** (Linux and macOS). Mobile
cross-compilation, graph visualisation and GitLab support are deferred.

## Getting started

The toolchain is provisioned entirely by [devenv](https://devenv.sh) — you do not
install Flutter, Dart or Rust yourself, and nothing is fetched outside the Nix
store.

```bash
# One-off, if you don't already have them
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
nix profile install nixpkgs#devenv

# Then, from the repository root
devenv shell
```

With [direnv](https://direnv.net) installed, `direnv allow` activates the
environment automatically whenever you `cd` into the repository.

The first entry builds the shell and may take several minutes. Subsequent entries
are near-instant.

## What the environment provides

| Tool | Version | Pinned by |
| --- | --- | --- |
| Flutter (bundles Dart) | 3.44.3 / Dart 3.12.2 | `nixpkgs` via `devenv.nix` |
| Rust | 1.97.1 | [`rust-toolchain.toml`](rust-toolchain.toml) |
| `flutter_rust_bridge_codegen` | 2.12.0 | `nixpkgs` via `devenv.nix` |
| SQLCipher | 4.14.0 | vendored by `rusqlite`'s `bundled-sqlcipher` |

It also carries the native dependencies the stack needs and that are easy to get
wrong: the GTK/GL stack for the Flutter Linux embedder, `libclang` for the
`bindgen` step inside `libsqlite3-sys`, `openssl` for the SQLCipher build, and
`libsecret` for the `keyring` crate's Secret Service backend on Linux.

Exact versions are locked in `devenv.lock`. To move them forward, run
`devenv update` and re-verify.

## Quality gates

Entering the shell installs Git pre-commit hooks enforcing the standards in
[`.constitution/tech-spec/guidelines.md`](.constitution/tech-spec/guidelines.md):

- `cargo fmt --all -- --check`
- `cargo clippy --all-targets -- -D warnings`
- `dart format --set-exit-if-changed .`
- `dart analyze`

Each hook is a no-op until the manifest it needs (`rust/Cargo.toml`,
`pubspec.yaml`) exists, so they activate on their own as `CORE-A001` lands.

## Verification performed

The environment was not assumed to work — it was exercised. Inside the shell:

- `flutter doctor` reports a healthy Linux toolchain and an available Linux
  desktop target.
- `flutter create` followed by `flutter build linux --release` produces a running
  bundle.
- A throwaway Rust crate depending on `rusqlite` (`bundled-sqlcipher`), `gix`,
  `keyring` and `pulldown-cmark` compiles, and its tests execute an FTS5 `MATCH`
  query against a keyed SQLCipher connection.

Two findings from that exercise were reconciled back into the tech-spec (see
`.constitution/tech-spec/changelog.md`, v1.0.1): the Rust pin must be ≥ 1.94, and
`rusqlite` 0.40 no longer exposes an `fts5` feature.
