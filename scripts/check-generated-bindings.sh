#!/usr/bin/env bash
# Verify FRB output without mutating the checkout. Snapshot completes before
# signals are trapped, and every later exit restores the complete surfaces.
set -euo pipefail

root=.
if [[ ${1:-} == --root ]]; then
  [[ $# == 2 ]] || { echo 'usage: check-generated-bindings.sh [--root CHECKOUT]' >&2; exit 2; }
  root=$2
elif (($#)); then
  echo 'usage: check-generated-bindings.sh [--root CHECKOUT]' >&2
  exit 2
fi
root=$(cd "$root" && pwd -P)
rust_rel=rust/src/frb_generated.rs; dart_rel=lib/src/rust
rust="$root/$rust_rel"; dart="$root/$dart_rel"
[[ -f $rust && ! -L $rust && -d $dart && ! -L $dart ]] || { echo 'generated binding surfaces are missing or linked' >&2; exit 2; }
scratch=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-frb.XXXXXX"); chmod 700 "$scratch"
backup="$scratch/precheck.tar"; before="$scratch/precheck.manifest"

validate_surface() {
  [[ -f $rust && ! -L $rust && -d $dart && ! -L $dart ]] || {
    echo 'generated binding roots must be an owned regular Rust file and directory' >&2
    return 1
  }
  while IFS= read -r -d '' path; do
    [[ $path == "$dart" ]] && continue
    if [[ -L $path || ! -f $path && ! -d $path ]]; then
      echo "unsupported generated-surface file type: $path" >&2
      return 1
    fi
    if [[ -f $path && $path != *.dart ]]; then
      echo "unsupported generated-surface file name: $path" >&2
      return 1
    fi
  done < <(find "$dart" -xdev -print0)
}
manifest() {
  local out=$1
  ( cd "$root"; { printf '%s\0' "$rust_rel"; find "$dart_rel" -xdev -type f -name '*.dart' -print0; } | LC_ALL=C sort -z |
      while IFS= read -r -d '' path; do printf 'f %s %s\n' "$(sha256sum "$path" | awk '{print $1}')" "$path"; done ) >"$out"
}
restore() {
  rm -rf -- "$rust" "$dart"
  mkdir -p "$(dirname "$rust")"
  tar -xf "$backup" -C "$root"
}
finish() {
  local result=$1 restore_result=0
  set +e
  restore || restore_result=1
  validate_surface || restore_result=1
  manifest "$scratch/restored.manifest" || restore_result=1
  cmp -s "$before" "$scratch/restored.manifest" || restore_result=1
  if ((restore_result)); then echo 'generated bindings could not be restored to their precheck state' >&2; result=2; fi
  trap - EXIT HUP INT TERM
  rm -rf -- "$scratch"
  exit "$result"
}

if ! validate_surface; then
  rm -rf -- "$scratch"
  exit 2
fi
tar --sort=name --format=posix -cf "$backup" -C "$root" "$rust_rel" "$dart_rel"
manifest "$before"
[[ -s $backup && -s $before ]] || { rm -rf -- "$scratch"; exit 2; }
trap 'finish "$?"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

generator_version=$(flutter_rust_bridge_codegen --version 2>&1 | awk 'NR==1 { print $NF }')
[[ $generator_version == 2.12.0 ]] || { echo "expected flutter_rust_bridge_codegen 2.12.0, found $generator_version" >&2; exit 2; }
set +e
(cd "$root" && flutter_rust_bridge_codegen generate)
generator_result=$?
set -e
if ((generator_result)); then echo 'flutter_rust_bridge_codegen generation failed; generated bindings were restored' >&2; exit "$generator_result"; fi
validate_surface
manifest "$scratch/generated.manifest"
if ! cmp -s "$before" "$scratch/generated.manifest"; then
  echo 'generated bindings are stale in rust/src/frb_generated.rs or lib/src/rust; regenerate and review the changes' >&2
  exit 1
fi
