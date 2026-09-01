#!/usr/bin/env bash
# Native regression coverage for the standalone and injected isolation modes.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
assertion=$root/scripts/assert-managed-evidence-isolation.sh
contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml

# Public standalone command: its parent owns Bubblewrap but the injected child
# must not receive it, credentials, or a descriptor canary.
env -u BURLMD_LOCKED_NIX_CLOSURE "$assertion" --contract "$contract" --sandbox bubblewrap --expected-version 0.11.2

tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-active-isolation.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

real_bwrap=$(command -v bwrap)
real_bash=$(command -v bash)
real_rg=$(command -v rg)
real_awk=$(command -v awk)
real_env=$(command -v env)
real_mkdir=$(command -v mkdir)
for executable in "$real_bwrap" "$real_bash" "$real_rg" "$real_awk" "$real_env" "$real_mkdir"; do
  [[ $(readlink -f "$executable") == /nix/store/* ]] || { echo "fixture needs locked tool: $executable" >&2; exit 1; }
done

# If injected code attempts bwrap or bwrap --version, this shim records it.
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$BURLMD_BWRAP_RECORD"' 'exit 91' >"$tmp/bin/bwrap"
chmod 755 "$tmp/bin/bwrap"

active_roots=()
for executable in "$real_bash" "$real_rg" "$real_awk" "$real_env" "$real_mkdir"; do
  resolved=$(readlink -f "$executable")
  entry=${resolved#/nix/store/}
  active_roots+=("/nix/store/${entry%%/*}")
done
mapfile -t closure < <(for root_path in "${active_roots[@]}"; do nix-store -qR "$root_path"; done | LC_ALL=C sort -u)
closure_value=$(IFS=:; printf '%s' "${closure[*]}")
active_path="$tmp/bin:$(dirname "$(readlink -f "$real_bash")"):$(dirname "$(readlink -f "$real_rg")"):$(dirname "$(readlink -f "$real_awk")"):$(dirname "$(readlink -f "$real_env")"):$(dirname "$(readlink -f "$real_mkdir")")"

run_injected() {
  local extra=$1 expected_status=$2
  local -a args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --setenv PATH "$active_path" --setenv BURLMD_LOCKED_NIX_CLOSURE "$closure_value" --setenv BURLMD_BWRAP_RECORD "$tmp/bwrap-record" --proc /proc --dev /dev --tmpfs /tmp --dir /nix --dir /nix/store --dir /trusted --ro-bind "$root" /trusted --ro-bind "$contract" /contract --chdir /trusted)
  for member in "${closure[@]}"; do args+=(--ro-bind "$member" "$member"); done
  case $extra in
    none) ;;
    credential) args+=(--setenv GH_TOKEN canary) ;;
    bwrap-visible) args+=(--ro-bind "$tmp/bin/bwrap" /nix/store/fake-bwrap/bin/bwrap --setenv PATH "/nix/store/fake-bwrap/bin:$active_path") ;;
    broad) args+=(--ro-bind / /host) ;;
    *) exit 64 ;;
  esac
  set +e
  "$real_bwrap" "${args[@]}" "$real_bash" /trusted/scripts/assert-managed-evidence-isolation.sh --contract /contract --sandbox bubblewrap --expected-version 0.11.2
  status=$?
  set -e
  [[ $status == "$expected_status" ]]
}

run_injected none 0
[[ ! -s $tmp/bwrap-record ]]
run_injected credential 1
run_injected bwrap-visible 1
run_injected broad 1
[[ ! -s $tmp/bwrap-record ]]

printf 'managed active isolation fixture passed\n'
