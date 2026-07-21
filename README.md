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

Once `CORE-A001` adds `rusqlite`, the library the app links is the SQLCipher
**4.14.0** vendored by `bundled-sqlcipher` — not the CLI above. The two float
independently; the CLI is present only for inspecting the encrypted index during
development.

No Android SDK is provisioned — mobile is out of product scope — but discovery
is pinned shut. `ANDROID_HOME` and `ANDROID_SDK_ROOT` point at a deliberately
empty in-repo path, because Flutter otherwise scans well-known home-directory
locations and silently adopts whatever SDK you happen to have installed. That
was the one part of the toolchain `devenv.lock` could not govern. `flutter
doctor` now reports "Unable to locate Android SDK" identically on every machine,
which is the intended state until mobile is unshelved.

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

- `cargo fmt --all -- --check`
- `cargo clippy --all-targets -- -D warnings`
- `dart format --set-exit-if-changed .`
- `dart analyze`
- `nixfmt` on `devenv.nix` — currently the only source file in the repository,
  and so the only hook that can fail today

The language hooks are a no-op until the manifest each one needs
(`rust/Cargo.toml`, `pubspec.yaml`) exists, so they activate on their own as
`CORE-A001` lands — but they fail loudly rather than silently skipping if a
manifest turns up somewhere unexpected. All of them exclude `.constitution/`, so
editing the tech-spec's `ffi_api.rs` contract does not trigger a build gate.

These are the only automated gates. There is no CI, and nothing runs tests.

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
`.constitution/tech-spec/changelog.md`, v1.0.1): the Rust pin must be ≥ 1.95, and
`rusqlite` 0.40 no longer exposes an `fts5` feature.
