#!/usr/bin/env bash
# Verifies that Flutter Rust Bridge output already matches the Rust API.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

before="$(mktemp)"
after="$(mktemp)"
cleanup() {
  rm -f "$before" "$after"
}
trap cleanup EXIT

binding_hashes() {
  sha256sum rust/src/frb_generated.rs
  find lib/src/rust -type f -print0 | sort -z | xargs -0 sha256sum
}

binding_hashes >"$before"
flutter_rust_bridge_codegen generate
binding_hashes >"$after"

if ! cmp -s "$before" "$after"; then
  echo "Generated Flutter Rust Bridge bindings were stale; regenerate and review the changes." >&2
  exit 1
fi
