#!/usr/bin/env bash
# Runs in the pinned devenv shell. This is deliberately a production fixture:
# no candidate-source command doubles are on PATH, and every mounted binary is
# resolved from a real locked Nix store path.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
tools=(
  bash sh env mkdir mktemp chmod install cp mv rm
  awk sed grep rg sort sha256sum wc find tar zstd
  flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc
  git nix nix-store cmake ninja pkg-config clang openssl
  bwrap flock jq taplo check-jsonschema sway swaymsg getconf df ps sleep setsid perl
  readlink uname tr head
)
declare -a roots=() closure_paths=() path_entries=() bwrap_args=()
for tool in "${tools[@]}"; do
  executable=$(readlink -f "$(command -v "$tool")") || exit 1
  [[ $executable == /nix/store/* ]] || {
    echo "production closure tool is not locked: $tool ($executable)" >&2
    exit 1
  }
  entry=${executable#/nix/store/}
  roots+=("/nix/store/${entry%%/*}")
  path_entries+=("$(dirname "$executable")")
done
mapfile -t closure_paths < <(for entry in "${roots[@]}"; do nix-store -qR "$entry"; done | LC_ALL=C sort -u)
mapfile -t path_entries < <(printf '%s\n' "${path_entries[@]}" | LC_ALL=C sort -u)
(( ${#closure_paths[@]} > 0 )) || exit 1
for entry in "${closure_paths[@]}"; do
  [[ $entry == /nix/store/* && -e $entry && ! -L $entry ]] || exit 1
  bwrap_args+=(--ro-bind "$entry" "$entry")
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-role-locked.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/home" "$scratch/tmp" "$scratch/repository"
git -C "$scratch/repository" init -q
git -C "$scratch/repository" config user.email fixture@example.invalid
git -C "$scratch/repository" config user.name fixture
printf 'locked closure fixture\n' >"$scratch/repository/README"
git -C "$scratch/repository" add README
git -C "$scratch/repository" commit -qm 'fixture'
path=$(IFS=:; printf '%s' "${path_entries[*]}")
# The inner command exercises the declared FRB, Rust, Git, and Nix tool
# families from the actual restricted closure. The repository is read-only,
# the writable home/tmp are owned scratch, and no host root/store bind exists.
env -i PATH="$path" HOME="$scratch/home" TMPDIR="$scratch/tmp" \
  "$(command -v bwrap)" --unshare-all --unshare-net --die-with-parent --new-session --clearenv \
  --setenv PATH "$path" --setenv HOME /home --setenv TMPDIR /tmp \
  --proc /proc --dev /dev --tmpfs /tmp --dir /home \
  --ro-bind "$scratch/repository" /source --chdir /source "${bwrap_args[@]}" \
  "$(command -v bash)" -ceu '
    flutter_rust_bridge_codegen --version
    cargo --version
    cargo expand --version
    rustc --version
    git -C /source rev-parse --is-inside-work-tree | grep -Fx true
    nix --version
    nix-store --version
  '

printf 'managed role locked production closure fixture passed\n'
