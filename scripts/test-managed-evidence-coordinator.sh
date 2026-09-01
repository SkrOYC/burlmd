#!/usr/bin/env bash
# Prototype coordinators are independently reviewed work. Until then, this
# verifies their trusted-launcher boundary without emulating a managed run.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
# Exercise the same pre-authentication preparation boundary as a managed Spike
# with a fresh, locked Rust binary. This intentionally derives the compiler
# root independently of Cargo: omitting the cc wrapper from the production
# closure would otherwise look green until rustc reaches its linker step.
preparation_scratch=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-coordinator-prepare.XXXXXXXX")
cleanup_preparation_fixture() {
  rm -rf -- "$preparation_scratch"
}
trap cleanup_preparation_fixture EXIT HUP INT TERM
source_dir=$preparation_scratch/source
target_dir=$preparation_scratch/target
cargo_home=$preparation_scratch/cargo-home
mkdir -p "$target_dir" "$cargo_home"
cargo init --bin --name burlmd_coordinator_preparation "$source_dir" >/dev/null
env -i PATH="$PATH" HOME="$preparation_scratch/home" CARGO_HOME="$cargo_home" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  cargo generate-lockfile --offline --manifest-path "$source_dir/Cargo.toml"
env -i PATH="$PATH" HOME="$preparation_scratch/home" CARGO_HOME="$cargo_home" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  cargo fetch --locked --manifest-path "$source_dir/Cargo.toml"

bash_bin=$(command -v bash)
bwrap_bin=$(command -v bwrap)
cargo_bin=$(command -v cargo)
cc_bin=$(command -v cc)
for tool in "$bash_bin" "$bwrap_bin" "$cargo_bin" "$cc_bin"; do
  resolved=$(readlink -f "$tool")
  [[ $resolved == /nix/store/* ]] || { echo "unlocked coordinator preparation tool: $tool" >&2; exit 1; }
done
[[ $("$bwrap_bin" --version | awk '{print $NF}') == 0.11.2 ]]
mapfile -t preparation_closure < <(nix-store -qR "$bwrap_bin" "$bash_bin" "$cargo_bin" "$cc_bin" | LC_ALL=C sort -u)
preparation_path="$(dirname "$cargo_bin"):$(dirname "$bash_bin"):$(dirname "$cc_bin")"
preparation_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /source --dir /deps --dir /target --ro-bind "$source_dir" /source --ro-bind "$cargo_home" /deps --bind "$target_dir" /target --chdir /source)
for closure in "${preparation_closure[@]}"; do preparation_args+=(--ro-bind "$closure" "$closure"); done
env -i PATH="$preparation_path" HOME=/home/coordinator CARGO_HOME=/deps \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  "$bwrap_bin" "${preparation_args[@]}" "$bash_bin" -ceu '
    test ! -w /source/Cargo.toml
    command -v cc
    cargo build --locked --offline --release --manifest-path /source/Cargo.toml --target-dir /target
  '
[[ -x $target_dir/release/burlmd_coordinator_preparation ]]
rg -Fq 'cc_bin=$(command -v cc)' "$root/scripts/managed-evidence.sh"
rg -Fq '"$bwrap_bin" "$bash_bin" "$(command -v cargo)" "$cc_bin"' "$root/scripts/managed-evidence.sh"
rg -Fq 'build_path="$(dirname "$(command -v cargo)"):$(dirname "$bash_bin"):$(dirname "$cc_bin")"' "$root/scripts/managed-evidence.sh"

# This is the canonical aggregate launcher for managed evidence fixtures.
# Include the real rooted private-store probe so future coordinator/matrix work
# cannot regress to a host store or daemon-backed candidate.
bash "$root/scripts/test-managed-role-private-store.sh"
bash "$root/scripts/test-managed-evidence-client.sh"
bash "$root/scripts/test-managed-evidence-reconciliation.sh"
for ticket in BURL-H001 BURL-H002 BURL-L001 BURL-I001 BURL-O001; do
  rg -Fq "${ticket})" "$root/scripts/managed-evidence.sh"
done
! rg -Fq 'test-collect' "$root/scripts/managed-evidence.sh"
printf 'managed-evidence coordinator boundary tests passed\n'
