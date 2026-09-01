#!/usr/bin/env bash
# Fixture-first regression suite for the non-mutating FRB checker.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-frb-fixture.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
fake="$tmp/bin"; mkdir -p "$fake"
cat >"$fake/flutter_rust_bridge_codegen" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then echo 'flutter_rust_bridge_codegen 2.12.0'; exit 0; fi
case ${FRB_FIXTURE_MODE:?} in
  clean) ;;
  stale) printf stale >> rust/src/frb_generated.rs ;;
  add) printf added > lib/src/rust/added.dart ;;
  remove) rm lib/src/rust/frb_generated.dart ;;
  link) ln -s frb_generated.dart lib/src/rust/generated-link.dart ;;
  fifo) mkfifo lib/src/rust/generated-pipe.dart ;;
  fail) printf changed >> rust/src/frb_generated.rs; exit 17 ;;
  interrupt) printf changed >> rust/src/frb_generated.rs; kill -TERM "$PPID" ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$fake/flutter_rust_bridge_codegen"
new_fixture() {
  local root=$1
  mkdir -p "$root/rust/src" "$root/lib/src"
  cp "$repo/rust/src/frb_generated.rs" "$root/rust/src/"
  cp -a "$repo/lib/src/rust" "$root/lib/src/"
}
digest() { (cd "$1" && { printf '%s\0' rust/src/frb_generated.rs; find lib/src/rust -type f -print0; } | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'); }
run_case() {
  local name=$1 expected=$2 root="$tmp/$1" before after outcome
  new_fixture "$root"
  [[ $name == premodified ]] && printf '// premodified\n' >> "$root/lib/src/rust/frb_generated.dart"
  before=$(digest "$root")
  set +e
  PATH="$fake:$PATH" FRB_FIXTURE_MODE="${name/premodified/clean}" "$repo/scripts/check-generated-bindings.sh" --root "$root" >/dev/null 2>&1
  outcome=$?
  set -e
  [[ $outcome == "$expected" ]] || { echo "$name: expected $expected, got $outcome" >&2; exit 1; }
  after=$(digest "$root")
  [[ $before == "$after" ]] || { echo "$name: generated surfaces were not restored" >&2; exit 1; }
}
run_case clean 0
run_case stale 1
run_case add 1
run_case remove 1
run_case premodified 0
run_case fail 17
run_case interrupt 143
run_case link 1
run_case fifo 1

run_invalid_surface_case() {
  local name=$1 root="$tmp/invalid-$1" outcome
  new_fixture "$root"
  case $name in
    rust-link)
      mv "$root/rust/src/frb_generated.rs" "$root/rust/src/real.rs"
      ln -s real.rs "$root/rust/src/frb_generated.rs"
      ;;
    dart-link)
      mv "$root/lib/src/rust" "$root/lib/src/real-rust"
      ln -s real-rust "$root/lib/src/rust"
      ;;
    nested-link)
      ln -s frb_generated.dart "$root/lib/src/rust/preexisting-link.dart"
      ;;
    nested-special)
      mkfifo "$root/lib/src/rust/preexisting-pipe.dart"
      ;;
    non-dart-file)
      printf rejected > "$root/lib/src/rust/not-generated.txt"
      ;;
    missing-root)
      rm -rf -- "$root/lib/src/rust"
      ;;
    *) echo "unknown invalid surface case: $name" >&2; exit 2 ;;
  esac
  set +e
  PATH="$fake:$PATH" FRB_FIXTURE_MODE=clean "$repo/scripts/check-generated-bindings.sh" --root "$root" >/dev/null 2>&1
  outcome=$?
  set -e
  [[ $outcome == 2 ]] || { echo "$name: expected root validation failure 2, got $outcome" >&2; exit 1; }
}
run_invalid_surface_case rust-link
run_invalid_surface_case dart-link
run_invalid_surface_case nested-link
run_invalid_surface_case nested-special
run_invalid_surface_case non-dart-file
run_invalid_surface_case missing-root
