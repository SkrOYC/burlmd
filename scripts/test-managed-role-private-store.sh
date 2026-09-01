#!/usr/bin/env bash
# Reduced real-store probe for the Linux candidate boundary.  It deliberately
# copies the candidate and trusted launcher closures into one private rooted
# store. Every copied closure member is overlaid read-only from that owned store
# while new private database/output paths remain writable.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-private-store.XXXXXXXX")
private_root=$scratch/burlmd-private-nix.probe0001
cleanup() {
  [[ -d $scratch && $scratch == "${TMPDIR:-/tmp}"/burlmd-private-store.* ]] || return 1
  find -P "$scratch" -xdev -depth -exec chmod u+w -- {} + 2>/dev/null || true
  find -P "$scratch" -xdev -depth -delete 2>/dev/null || true
  [[ ! -e $scratch ]]
}
trap cleanup EXIT INT TERM HUP
mkdir -p "$private_root"

env_bin=$(readlink -f "$(command -v env)")
nix_bin=$(readlink -f "$(command -v nix)")
nix_store_bin=$(readlink -f "$(command -v nix-store)")
bash_bin=$(readlink -f "$(command -v bash)")
for path in "$env_bin" "$nix_bin" "$nix_store_bin" "$bash_bin"; do [[ $path == /nix/store/* ]]; done
entry=${env_bin#/nix/store/}; env_root=/nix/store/${entry%%/*}
entry=${nix_bin#/nix/store/}; nix_root=/nix/store/${entry%%/*}
entry=${nix_store_bin#/nix/store/}; nix_store_root=/nix/store/${entry%%/*}
entry=${bash_bin#/nix/store/}; bash_root=/nix/store/${entry%%/*}
mapfile -t candidate_paths < <(for path in "$env_root" "$nix_root" "$nix_store_root" "$bash_root"; do nix-store -qR "$path"; done | LC_ALL=C sort -u)
nix copy --offline --to "$private_root" --no-check-sigs "${candidate_paths[@]}"
[[ -f $private_root/nix/var/nix/db/db.sqlite ]]
! find -P "$private_root/nix" -xdev -type s -print -quit | grep -q .

host_canary=$scratch/host-store-canary
printf host-canary >"$host_canary"
bwrap_args=(--unshare-all --unshare-net --die-with-parent --new-session --clearenv --setenv PATH "$(dirname "$env_bin"):$(dirname "$nix_bin"):$(dirname "$nix_store_bin"):$(dirname "$bash_bin")" --setenv HOME /tmp --setenv TMPDIR /tmp --setenv NIX_REMOTE local --setenv NIX_PATH '' --setenv NIX_CONFIG $'experimental-features = nix-command\nsandbox = false\nbuild-users-group =\nsubstituters =\nflake-registry =\naccept-flake-config = false' --proc /proc --dev /dev --tmpfs /tmp --bind "$private_root/nix" /nix)
for logical_path in "${candidate_paths[@]}"; do
  private_path=$(realpath -e -- "$private_root/nix/store/${logical_path#/nix/store/}")
  [[ $private_path == "$private_root"/nix/store/* && ! -L $private_path && "/nix${private_path#"$private_root/nix"}" == "$logical_path" ]] || exit 1
  bwrap_args+=(--ro-bind "$private_path" "$logical_path")
done
"$(command -v bwrap)" "${bwrap_args[@]}" "$bash_bin" -ceu '
  test -f /nix/var/nix/db/db.sqlite
  test ! -S /nix/var/nix/daemon-socket/socket
  nix path-info "$1" >/dev/null
  ! NIX_REMOTE=daemon nix path-info "$1" >/dev/null 2>&1
  test ! -w "$1"
  printf candidate-only > /nix/var/nix/candidate-store-write
  test ! -e "$2"
' private-store "${candidate_paths[0]}" /host-canary
[[ $(<"$private_root/nix/var/nix/candidate-store-write") == candidate-only ]]
[[ $(<"$host_canary") == host-canary ]]

# A missing or altered database must fail closed before a private store is
# mounted.  Work on disposable copies so the successful probe remains intact.
for mode in missing corrupt; do
  copy=$scratch/$mode
  cp -a "$private_root" "$copy"
  if [[ $mode == missing ]]; then rm -f -- "$copy/nix/var/nix/db/db.sqlite"; else printf corrupt >"$copy/nix/var/nix/db/db.sqlite"; fi
  if NIX_REMOTE=local NIX_PATH= nix --store "local?root=$copy" store verify --all --no-trust >/dev/null 2>&1; then
    echo "private store verification accepted $mode SQLite database" >&2
    exit 1
  fi
done

printf 'managed role reduced private-store probe passed\n'
