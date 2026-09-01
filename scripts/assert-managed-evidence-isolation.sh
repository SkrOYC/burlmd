#!/usr/bin/env bash
# Adversarial fixture for the post-download coordinator boundary.
set -euo pipefail
contract= sandbox= expected=
while (($#)); do
  case $1 in
    --contract) contract=$2; shift 2;; --sandbox) sandbox=$2; shift 2;; --expected-version) expected=$2; shift 2;;
    *) echo "usage: $0 --contract FILE --sandbox bubblewrap --expected-version VERSION" >&2; exit 2;;
  esac
done
[[ $sandbox == bubblewrap && -f $contract ]] || exit 2
[[ $(bwrap --version | awk '{print $NF}') == "$expected" ]] || exit 1
script_root=$(cd "$(dirname "$0")/.." && pwd -P)
rg -Fq 'close_nonstdio_fds' "$script_root/scripts/managed-evidence.sh"
rg -Fq 'unshare-net' "$script_root/scripts/managed-evidence.sh"
! rg -Fq -- '--ro-bind / /' "$script_root/scripts/managed-evidence.sh"
rg -Fq 'coordinator-isolation-failed' "$contract"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-isolation.XXXXXX"); chmod 700 "$tmp"
trap 'rm -rf -- "$tmp"' EXIT
mkdir "$tmp/inputs" "$tmp/output" "$tmp/home" "$tmp/config"
printf canary >"$tmp/inputs/readable"
printf credential-canary >"$tmp/home/token"; printf config-canary >"$tmp/config/config"
# Credential/configuration canaries cover every client family that a managed
# coordinator must never inherit.  Their exact values deliberately do not
# appear in the child environment or filesystem.
export GH_TOKEN=github-canary GITHUB_TOKEN=github-token-canary ACTIONS_ID_TOKEN_REQUEST_TOKEN=oidc-canary ACTIONS_ID_TOKEN_REQUEST_URL=https://oidc.invalid \
  SSH_AUTH_SOCK="$tmp/home/ssh.sock" GIT_ASKPASS="$tmp/config/askpass" CARGO_REGISTRIES_CRATES_IO_TOKEN=cargo-canary \
  AWS_ACCESS_KEY_ID=aws-canary AWS_SECRET_ACCESS_KEY=aws-secret-canary GOOGLE_APPLICATION_CREDENTIALS="$tmp/config/gcloud.json" AZURE_CLIENT_SECRET=azure-canary
# Deliberately inherit a non-CLOEXEC descriptor; the probe must not see it.
exec 19<"$tmp/home/token"
shell=$(command -v sh); cat_bin=$(command -v cat); bwrap_bin=$(command -v bwrap)

# The coordinator is intentionally allowed a much smaller command set than a
# candidate role.  The standalone invocation is a trusted top-level gate, so
# it must construct its own store closure instead of inheriting an ambient
# PATH.  Nested invocation receives the candidate launcher's already computed
# closure; it can validate that restricted mount without needing a broad Nix
# database mount inside the outer Bubblewrap namespace.
required_tools=(bash sh env cat mkdir mktemp chmod awk rg sort readlink bwrap)
locked_store_root() {
  local tool=$1 resolved entry
  resolved=$(readlink -f "$(command -v "$tool")") || return 1
  case $resolved in
    /nix/store/*)
      entry=${resolved#/nix/store/}
      printf '/nix/store/%s\n' "${entry%%/*}"
      ;;
    *)
      echo "required isolation tool is not locked in /nix/store: $tool ($resolved)" >&2
      return 1
      ;;
  esac
}
construct_locked_closure() {
  command -v nix-store >/dev/null || {
    echo 'locked nix-store is required to construct the standalone isolation closure' >&2
    return 1
  }
  local tool root
  local -a roots=()
  for tool in "${required_tools[@]}" nix-store; do
    roots+=("$(locked_store_root "$tool")") || return 1
  done
  for root in "${roots[@]}"; do nix-store -qR "$root"; done | LC_ALL=C sort -u
}
validate_injected_closure() {
  local tool executable root path
  # The injected closure is an immutable trusted-launcher input, but reject
  # truncation and broad/host paths before spawning the nested sandbox. Every
  # required executable must resolve below one of the explicitly mounted
  # members; an extra non-store member is never a valid escape hatch.
  for path in "${closure_paths[@]}"; do
    [[ $path == /nix/store/* && -e $path && ! -L $path ]] || {
      echo "invalid locked Nix closure member: $path" >&2; return 1;
    }
  done
  for tool in "${required_tools[@]}"; do
    executable=$(command -v "$tool") || {
      echo "injected closure omits required isolation tool: $tool" >&2; return 1;
    }
    executable=$(readlink -f "$executable") || return 1
    [[ $executable == /nix/store/* ]] || {
      echo "injected closure resolves a required tool outside /nix/store: $tool" >&2; return 1;
    }
    root=${executable#/nix/store/}
    root=/nix/store/${root%%/*}
    # `nix-store -qR` emits dependency paths as well as roots, so every
    # executable used by the nested probe must have its own store entry bound.
    [[ " ${closure_paths[*]} " == *" $root "* ]] || {
      echo "injected closure omits executable store entry for: $tool" >&2; return 1;
    }
  done
}

if [[ -n ${BURLMD_LOCKED_NIX_CLOSURE+x} ]]; then
  IFS=: read -r -a closure_paths <<<"$BURLMD_LOCKED_NIX_CLOSURE"
  (( ${#closure_paths[@]} > 0 )) || { echo 'locked Nix closure is empty' >&2; exit 1; }
  validate_injected_closure
else
  mapfile -t closure_paths < <(construct_locked_closure)
  (( ${#closure_paths[@]} > 0 )) || { echo 'constructed locked Nix closure is empty' >&2; exit 1; }
fi
bwrap_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /inputs --dir /output --chdir / --ro-bind "$tmp/inputs" /inputs --bind "$tmp/output" /output)
for path in "${closure_paths[@]}"; do
  bwrap_args+=(--ro-bind "$path" "$path")
done
# Model the trusted launcher's mandatory descriptor sweep before exec.
exec 19<&-
env -i PATH="$(dirname "$shell"):$(dirname "$cat_bin")" HOME=/home/coordinator XDG_CONFIG_HOME=/tmp/xdg-config XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data GH_CONFIG_DIR=/tmp/gh-config GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  "$bwrap_bin" "${bwrap_args[@]}" "$shell" -ceu '
    test "$(cat /inputs/readable)" = canary
    test ! -w /inputs/readable
    test ! -e /home/coordinator/token
    test ! -e /tmp/xdg-config/config
    test ! -e /proc/self/fd/19
    ! command -v gh; ! command -v git; ! command -v ssh; ! command -v curl; ! command -v wget
    ! command -v aws; ! command -v az; ! command -v gcloud; ! command -v cargo
    ! (exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null
    test -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}${SSH_AUTH_SOCK:-}${CARGO_REGISTRIES_CRATES_IO_TOKEN:-}${AWS_ACCESS_KEY_ID:-}${GOOGLE_APPLICATION_CREDENTIALS:-}${AZURE_CLIENT_SECRET:-}"
    printf schema-valid-result >/output/results.json
    test ! -w /inputs/readable
  '
[[ $(cat "$tmp/output/results.json") == schema-valid-result ]]
# Production must not carry test transport or schema seams into this boundary.
! rg -Fq 'test-collect' scripts/managed-evidence.sh
! rg -Fq 'ME_TEST_' scripts/managed-evidence.sh
