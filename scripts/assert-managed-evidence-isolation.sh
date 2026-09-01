#!/usr/bin/env bash
# Isolation assertion with two explicit trusted-launcher modes:
#
# * no BURLMD_LOCKED_NIX_CLOSURE: the standalone authoritative command owns
#   one production-shaped Bubblewrap launch;
# * BURLMD_LOCKED_NIX_CLOSURE present: the managed candidate launcher supplied
#   its locked closure, so validate that active namespace without nesting.
#
# The closure input, not a namespace heuristic, selects the mode. This matters
# because a candidate already owns its user namespace and cannot safely create
# a second UID map merely to run this assertion.
set -euo pipefail
contract= sandbox= expected=
standalone_tmp=
while (($#)); do
  case $1 in
    --contract) contract=$2; shift 2;; --sandbox) sandbox=$2; shift 2;; --expected-version) expected=$2; shift 2;;
    *) echo "usage: $0 --contract FILE --sandbox bubblewrap --expected-version VERSION" >&2; exit 2;;
  esac
done
[[ $sandbox == bubblewrap && -f $contract ]] || exit 2
script_root=$(cd "$(dirname "$0")/.." && pwd -P)
rg -Fq 'close_nonstdio_fds' "$script_root/scripts/managed-evidence.sh"
rg -Fq 'unshare-net' "$script_root/scripts/managed-evidence.sh"
! rg -Fq -- '--ro-bind / /' "$script_root/scripts/managed-evidence.sh"
rg -Fq 'coordinator-isolation-failed' "$contract"
# The standalone command owns its Bubblewrap process.  In injected M003 mode,
# Bubblewrap is deliberately parent-only: candidate code must prove that it is
# absent rather than probing it (including with --version).
active_required_tools=(bash sh env cat mkdir chmod awk rg sort readlink)
standalone_required_tools=("${active_required_tools[@]}" mktemp bwrap)
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
  for tool in "${active_required_tools[@]}"; do
    roots+=("$(locked_store_root "$tool")") || return 1
  done
  for root in "${roots[@]}"; do nix-store -qR "$root"; done | LC_ALL=C sort -u
}
validate_injected_closure() {
  local tool executable root path
  # The injected closure is an immutable trusted-launcher input, but reject
  # truncation and broad/host paths. Every required executable must resolve
  # below one of the explicitly mounted members; an extra non-store member is
  # never a valid escape hatch.
  for path in "${closure_paths[@]}"; do
    [[ $path == /nix/store/* && -e $path && ! -L $path ]] || {
      echo "invalid locked Nix closure member: $path" >&2; return 1;
    }
  done
  for tool in "${active_required_tools[@]}"; do
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
    # executable used by this active-boundary assertion has its own bound entry.
    [[ " ${closure_paths[*]} " == *" $root "* ]] || {
      echo "injected closure omits executable store entry for: $tool" >&2; return 1;
    }
  done
}

assert_active_candidate_boundary() {
  local uid_inside uid_outside uid_length gid_inside gid_outside gid_length interface
  local -a interfaces=()
  IFS=: read -r -a closure_paths <<<"$BURLMD_LOCKED_NIX_CLOSURE"
  (( ${#closure_paths[@]} > 0 )) || { echo 'locked Nix closure is empty' >&2; return 1; }
  validate_injected_closure
  ! command -v bwrap || { echo 'candidate exposes parent-only Bubblewrap by name' >&2; return 1; }
  [[ ! -e /nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap ]] || {
    echo 'candidate exposes parent-only Bubblewrap path' >&2; return 1;
  }

  # Validate the active candidate namespace rather than creating a nested one.
  # Production uses --unshare-user --uid 0 --gid 0, whose single-id maps are
  # the observable proof that this process is in the private identity map.
  read -r uid_inside uid_outside uid_length </proc/self/uid_map
  read -r gid_inside gid_outside gid_length </proc/self/gid_map
  [[ $uid_inside == 0 && $gid_inside == 0 && $uid_outside =~ ^[0-9]+$ && $gid_outside =~ ^[0-9]+$ && $uid_length == 1 && $gid_length == 1 ]] || {
    echo 'candidate is not running in the production private user namespace' >&2; return 1;
  }
  while IFS= read -r interface; do interfaces+=("$interface"); done < <(
    awk -F: 'NR > 2 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1 }' /proc/net/dev
  )
  [[ ${interfaces[*]} == lo ]] || {
    echo 'candidate is not running in the production private network namespace' >&2; return 1;
  }
  [[ ! -e /host ]] || { echo 'candidate exposes a broad host bind' >&2; return 1; }
  [[ ! -e /proc/self/fd/19 ]] || { echo 'candidate inherited a descriptor canary' >&2; return 1; }
  ! mkdir "${closure_paths[0]}/.burlmd-write-probe" 2>/dev/null || { echo 'candidate locked closure member is writable' >&2; return 1; }
  [[ ! -w "$script_root/scripts/managed-evidence.sh" ]] || { echo 'trusted coordinator helper is writable' >&2; return 1; }
  ! command -v gh; ! command -v git; ! command -v ssh; ! command -v curl; ! command -v wget
  ! command -v aws; ! command -v az; ! command -v gcloud
  [[ -z ${GH_TOKEN:-}${GITHUB_TOKEN:-}${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}${SSH_AUTH_SOCK:-}${CARGO_REGISTRIES_CRATES_IO_TOKEN:-}${AWS_ACCESS_KEY_ID:-}${GOOGLE_APPLICATION_CREDENTIALS:-}${AZURE_CLIENT_SECRET:-} ]] || {
    echo 'candidate inherited a credential capability' >&2; return 1;
  }
}

run_standalone_assertion() {
  local tmp shell bwrap_bin fixture_path closure_value path
  local -a closure_paths=() path_entries=() bwrap_args=()
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-isolation.XXXXXX"); chmod 700 "$tmp"
  standalone_tmp=$tmp
  trap 'rm -rf -- "$standalone_tmp"' EXIT
  mkdir "$tmp/home" "$tmp/config"
  printf credential-canary >"$tmp/home/token"; printf config-canary >"$tmp/config/config"
  export GH_TOKEN=github-canary GITHUB_TOKEN=github-token-canary ACTIONS_ID_TOKEN_REQUEST_TOKEN=oidc-canary ACTIONS_ID_TOKEN_REQUEST_URL=https://oidc.invalid \
    SSH_AUTH_SOCK="$tmp/home/ssh.sock" GIT_ASKPASS="$tmp/config/askpass" CARGO_REGISTRIES_CRATES_IO_TOKEN=cargo-canary \
    AWS_ACCESS_KEY_ID=aws-canary AWS_SECRET_ACCESS_KEY=aws-secret-canary GOOGLE_APPLICATION_CREDENTIALS="$tmp/config/gcloud.json" AZURE_CLIENT_SECRET=azure-canary
  # Deliberately inherit a non-CLOEXEC descriptor; the managed launch shape
  # must close it before the candidate-side assertion executes.
  exec 19<"$tmp/home/token"
  mapfile -t closure_paths < <(construct_locked_closure)
  (( ${#closure_paths[@]} > 0 )) || { echo 'constructed locked Nix closure is empty' >&2; return 1; }
  for path in "${active_required_tools[@]}"; do
    path_entries+=("$(dirname "$(readlink -f "$(command -v "$path")")")")
  done
  mapfile -t path_entries < <(printf '%s\n' "${path_entries[@]}" | LC_ALL=C sort -u)
  fixture_path=$(IFS=:; printf '%s' "${path_entries[*]}")
  closure_value=$(IFS=:; printf '%s' "${closure_paths[*]}")
  shell=$(command -v bash); bwrap_bin=$(command -v bwrap)
  [[ $($bwrap_bin --version | awk '{print $NF}') == "$expected" ]] || return 1
  # Keep this prefix byte-for-byte aligned with linux_candidate_bwrap's
  # production namespace contract. This standalone branch owns exactly this
  # one Bubblewrap process; its child takes the injected-closure branch above.
  bwrap_args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --setenv PATH "$fixture_path" --setenv BURLMD_LOCKED_NIX_CLOSURE "$closure_value" --proc /proc --dev /dev --tmpfs /tmp --dir /nix --dir /nix/store --dir /trusted --ro-bind "$script_root" /trusted --ro-bind "$contract" /contract --chdir /trusted)
  for path in "${closure_paths[@]}"; do bwrap_args+=(--ro-bind "$path" "$path"); done
  exec 19<&-
  env -i PATH="$fixture_path" \
    "$bwrap_bin" "${bwrap_args[@]}" "$shell" /trusted/scripts/assert-managed-evidence-isolation.sh \
      --contract /contract --sandbox bubblewrap --expected-version "$expected"
}

if [[ -n ${BURLMD_LOCKED_NIX_CLOSURE+x} ]]; then
  assert_active_candidate_boundary
else
  run_standalone_assertion
fi
# Production must not carry test transport or schema seams into this boundary.
! rg -Fq 'test-collect' scripts/managed-evidence.sh
! rg -Fq 'ME_TEST_' scripts/managed-evidence.sh
