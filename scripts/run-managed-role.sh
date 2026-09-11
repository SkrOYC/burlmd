#!/usr/bin/env bash
# Trusted workflow helper. Candidate source is data; this helper always comes
# from the workflow-signer checkout.
set -euo pipefail

role=${1:?role}; source_root=${2:?tested source}; output_root=${3:?output root}
trusted_launcher_input=${BASH_SOURCE[0]}
[[ $source_root == /* && $output_root == /* ]] || { echo 'role roots must be explicit absolute paths' >&2; exit 2; }
[[ ! -L $source_root && ! -L $trusted_launcher_input ]] || { echo 'tested source or trusted launcher input is a symbolic link' >&2; exit 2; }
# Test-only controls must never become an execution path in the trusted role
# helper.  Fixtures model their host through command doubles; a caller that
# supplies a reserved role-fixture variable is rejected before any candidate
# source is read or command is launched.
while IFS= read -r environment_name; do
  case $environment_name in
    BURLMD_ROLE_FIXTURE_*)
      echo "reserved role-fixture environment variable is not accepted: $environment_name" >&2
      exit 2
      ;;
  esac
done < <(compgen -e)
script_root=$(cd "$(dirname "$trusted_launcher_input")/.." && pwd -P)
role_schema=$script_root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json
contract=$script_root/.constitution/tech-spec/contracts/provisional-spikes.toml
[[ -f $role_schema && -f $contract ]] || { echo 'trusted role schema or contract is missing' >&2; exit 2; }
command -v taplo >/dev/null || { echo 'locked taplo is required for contract parsing' >&2; exit 2; }
command -v check-jsonschema >/dev/null || { echo 'locked check-jsonschema is required for manifest validation' >&2; exit 2; }
resolve_trusted_perl() {
  local candidate resolved
  trusted_perl=
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    resolved=$(readlink -f -- "$candidate") || continue
    case $resolved in /nix/store/*) ;; *) continue;; esac
    [[ -f $resolved && -x $resolved && ! -L $resolved ]] || continue
    trusted_perl=$resolved
    break
  done < <(type -a -p perl)
  [[ -n $trusted_perl ]] || return 1
}
resolve_trusted_perl || { echo 'locked Nix-store Perl is required for trusted role helpers' >&2; exit 2; }
readonly trusted_perl
role_schema_version=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$role_schema")
contract_role_schema_version=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.ci_role_evidence_schema_version | jq -er '.')
[[ $role_schema_version == "$contract_role_schema_version" ]] || { echo 'role schema and contract versions disagree' >&2; exit 2; }
ticket=$(jq -er '.ticketIdentity | strings' "${EXPECTED_IDENTITY:?EXPECTED_IDENTITY is required}")
expected_source_sha=$(jq -er '.testedSourceSha | strings | select(test("^[0-9a-f]{40}$"))' "$EXPECTED_IDENTITY")
expected_signer_sha=$(jq -er '.workflowSignerSha | strings | select(test("^[0-9a-f]{40}$"))' "$EXPECTED_IDENTITY")
# The tested checkout is untrusted data, but its revision is an authenticated
# workflow input.  Verify its exact commit before even discovering a test or
# constructing a candidate command.  Disable repository and user config so a
# hostile checkout cannot turn this identity read into an executable hook.
actual_source_sha=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 \
  git -c core.hooksPath=/dev/null -C "$source_root" rev-parse --verify HEAD^{commit}) || {
  echo 'tested source is not a resolvable git checkout' >&2; exit 2;
}
[[ $actual_source_sha == "$expected_source_sha" ]] || {
  echo "tested source HEAD does not match expected identity: $actual_source_sha" >&2; exit 2;
}
actual_signer_sha=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 \
  git -c core.hooksPath=/dev/null -C "$script_root" rev-parse --verify HEAD^{commit}) || {
  echo 'trusted launcher is not a resolvable git checkout' >&2; exit 2;
}
[[ $actual_signer_sha == "$expected_signer_sha" ]] || {
  echo "trusted launcher HEAD does not match workflow signer identity: $actual_signer_sha" >&2; exit 2;
}
canonical_source_root=$(realpath -e -- "$source_root") || { echo 'tested source path is not canonicalizable' >&2; exit 2; }
canonical_trusted_root=$(realpath -e -- "$script_root") || { echo 'trusted launcher root is not canonicalizable' >&2; exit 2; }
canonical_trusted_launcher=$(realpath -e -- "$trusted_launcher_input") || { echo 'trusted launcher path is not canonicalizable' >&2; exit 2; }
[[ $canonical_trusted_launcher == "$canonical_trusted_root/scripts/run-managed-role.sh" ]] || { echo 'trusted launcher path is not the workflow-signer control' >&2; exit 2; }
[[ $source_root == "$canonical_source_root" ]] || { echo 'tested source argument is an aliased or noncanonical path' >&2; exit 2; }
[[ $canonical_source_root != "$canonical_trusted_root" ]] || { echo 'tested source and trusted launcher roots must be distinct' >&2; exit 2; }
source_root=$canonical_source_root
profile_for() { taplo get --file-path "$contract" --output-format json "ci_bootstrap.ticket_evidence_profiles.\"$1\".\"$2\"" | jq -ce .; }
profile_for "$ticket" "$role" >/dev/null || {
  echo 'ticket has no trusted managed evidence profile' >&2; exit 2;
}
if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  [[ -n ${RUNNER_TEMP:-} && $RUNNER_TEMP == /* && ! -L $RUNNER_TEMP ]] || { echo 'BURL-M003 requires an explicit non-linked absolute RUNNER_TEMP' >&2; exit 2; }
  RUNNER_TEMP=$(realpath -e -- "$RUNNER_TEMP") || { echo 'BURL-M003 RUNNER_TEMP is not canonicalizable' >&2; exit 2; }
fi
reference_profile_for() {
  case $1 in
  linux-x86_64) printf '%s' github-ubuntu-22_04-x86_64;;
    macos-26-arm64) printf '%s' github-macos-26-arm64;;
    macos-15-arm64) printf '%s' github-macos-15-arm64;;
    *) return 2;;
  esac
}
# `verification_steps` are anchor-owned TOML, not candidate configuration. A
# platform role runs only its own explicitly labelled step plus unlabelled
# shared checks. BURL-M003 has no Spike entry; its bootstrap checks are recorded
# separately below.
role_steps_for() {
  local requested_ticket=$1 requested_role=$2 role_pattern
  case $requested_role in
    linux-x86_64) role_pattern='^linux';;
  # `macos-default-*` is the current managed macOS profile. `current` and
  # `repeat`, and `previous` remain explicit, non-overlapping evidence roles.
  macos-26-arm64) role_pattern='^macos-(26|current|repeat|default)';;
    macos-15-arm64) role_pattern='^macos-(15|previous)';;
    *) return 2;;
  esac
  [[ $requested_ticket == BURL-M003 ]] && { jq -cn '[]'; return 0; }
  # Non-Spike tickets have profiles and source allowlists, but their candidate
  # gates are not yet a trusted TOML surface. Never reinterpret a missing gate
  # record as a synthetic Spike command list.
  case $requested_ticket in
    BURL-G011|BURL-P002|BURL-O004|BURL-O011|BURL-O012|BURL-O013) return 2 ;;
  esac
  taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -ce --arg id "SPK-$requested_ticket" --arg pattern "$role_pattern" --arg requested_role "$requested_role" '
      [ .[] | select(.id == $id) | .verification_steps[]
        | select((has("run_role") | not) or (.run_role | test($pattern)))
        # The only authenticated-stage prerequisite belongs to the PKG macOS
        # 15 consumer.  Keep it in the declared sequence: filtering it out
        # would allow the following import to observe a stale or substituted
        # inbox.
        | select(
            (has("requires_authenticated_stage_role") | not)
            or ($requested_role == "macos-15-arm64"
                and .requires_authenticated_stage_role == "macos-26-arm64")
          )
      ]'
}

non_spike_gate_guard() {
  local allowlist coordinator_status rotation_required
  case $ticket in
    BURL-G011|BURL-P002|BURL-O011|BURL-O012|BURL-O013)
      # These profiles authenticate complete role bundles, but the accepted
      # contract deliberately supplies no candidate command/gate declaration.
      # A future ticket must add that trusted surface; this bootstrap may not
      # infer it from its scope, profile names, or a candidate checkout.
      allowlist=$(taplo get --file-path "$contract" --output-format json "ci_bootstrap.non_spike_source_write_allowlists.tickets.\"$ticket\"" | jq -ce .) || return 2
      [[ $(jq 'length' <<<"$allowlist") -gt 0 ]] || return 2
      echo "trusted contract declares no candidate execution gates for managed non-Spike $ticket" >&2
      return 2
      ;;
    BURL-O004)
      coordinator_status=$(taplo get --file-path "$contract" --output-format json 'ci_bootstrap.non_spike_coordinators."BURL-O004".coordinator_artifact_status' | jq -er .) || return 2
      rotation_required=$(taplo get --file-path "$contract" --output-format json 'ci_bootstrap.non_spike_coordinators."BURL-O004".trust_anchor_rotation_required' | jq -er .) || return 2
      [[ $coordinator_status == future && $rotation_required == true ]] || return 2
      echo 'BURL-O004 coordinator is future trusted control pending anchor rotation; candidate execution is blocked' >&2
      return 2
      ;;
  esac
  return 0
}
mkdir -p "$output_root/results"
if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  canonical_output_root=$(realpath -e -- "$output_root") || { echo 'BURL-M003 role-output root is not canonicalizable' >&2; exit 2; }
  [[ $output_root == "$canonical_output_root" && -d $output_root && ! -L $output_root ]] || { echo 'BURL-M003 role-output root is linked or aliased' >&2; exit 2; }
  output_root=$canonical_output_root
fi
if [[ $(uname) == Darwin ]]; then
  # Hosted macOS has no Linux-style namespace containment. Keep every authority
  # domain in a disjoint canonical root and treat the authenticated download as
  # immutable input, not a writable candidate directory.
  runtime_root=${BURLMD_ROLE_RUNTIME_ROOT:?macOS role runtime root is required}
  mkdir -p "$runtime_root" "$output_root"
  canonical_source=$(cd "$source_root" && pwd -P)
  canonical_output=$(cd "$output_root" && pwd -P)
  canonical_runtime=$(cd "$runtime_root" && pwd -P)
  canonical_stage=''
  authenticated_stage_consumption=''
  if [[ -n ${BURLMD_AUTHENTICATED_STAGE_ROOT:-} ]]; then
    canonical_stage=$(cd "$BURLMD_AUTHENTICATED_STAGE_ROOT" && pwd -P) || {
      echo 'authenticated input root is unavailable' >&2; exit 1;
    }
  fi
  for root in "$canonical_source" "$canonical_output" "$canonical_runtime" ${canonical_stage:+"$canonical_stage"}; do
    [[ ! -L $root ]] || { echo 'macOS role root is a symbolic link' >&2; exit 1; }
    parent=$root
    while [[ $parent != / ]]; do
      [[ ! -L $parent ]] || { echo 'macOS role root has a symbolic-link ancestor' >&2; exit 1; }
      parent=$(dirname "$parent")
    done
  done
  roots=("$canonical_source" "$canonical_output" "$canonical_runtime")
  [[ -n $canonical_stage ]] && roots+=("$canonical_stage")
  for ((i = 0; i < ${#roots[@]}; i++)); do for ((j = i + 1; j < ${#roots[@]}; j++)); do
    [[ ${roots[i]} != "${roots[j]}" && ${roots[i]} != "${roots[j]}"/* && ${roots[j]} != "${roots[i]}"/* ]] || {
      echo 'macOS source, authenticated input, runtime, and output roots must be disjoint' >&2; exit 1;
    }
  done; done
  if [[ -n $canonical_stage ]]; then
    find "$canonical_stage" -xdev -type l -print -quit | grep -q . && {
      echo 'authenticated macOS input contains a symbolic link' >&2; exit 1;
    }
    find "$canonical_stage" -xdev -type d -exec chmod 555 {} +
    find "$canonical_stage" -xdev -type f -exec chmod 444 {} +
    authenticated_stage_before=$(find "$canonical_stage" -xdev -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
  fi
fi
case $role in
  linux-x86_64) runner=ubuntu-22.04;;
  macos-26-arm64) runner=macos-26;;
  macos-15-arm64) runner=macos-15;;
  *) exit 2;;
esac
class_json=$(profile_for "$ticket" "$role") || { echo "missing $ticket evidence profile for role" >&2; exit 2; }
# The authenticated identity is the request and the anchor-owned TOML profile
# is the authority. Reject either a forged profile or a contract/profile drift
# before a candidate command is launched.
jq -e --arg role "$role" --argjson profile "$class_json" '.requiredEvidenceClasses[$role] == $profile' "$EXPECTED_IDENTITY" >/dev/null || {
  echo 'expected identity evidence profile disagrees with trusted contract' >&2; exit 2;
}
reference_profile=$(reference_profile_for "$role")
documented_environment=$(taplo get --file-path "$contract" --output-format json "reference_profiles.$reference_profile" | jq -ce '{runner_label,os,architecture,os_major,cpu_model_contains,logical_cpu_count,memory_bytes,storage_bytes,logical_viewport_width,logical_viewport_height,logical_viewport_refresh_hz}') || {
  echo "missing documented reference profile for $role" >&2; exit 2;
}
[[ $(jq -r '.runner_label' <<<"$documented_environment") == "$runner" ]] || { echo 'role workflow and reference profile disagree' >&2; exit 2; }
classes=$(jq -r 'join(",")' <<<"$class_json")
viewport_verified=false
viewport_requires_exact_probe=$(jq -r '
  any(.[]; . == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual")
' <<<"$class_json")
[[ $viewport_requires_exact_probe == true || $viewport_requires_exact_probe == false ]] || { echo 'invalid evidence profile viewport classification' >&2; exit 2; }
# Hosted image labels are mutable metadata. Capture the runner-provided image
# metadata and observed host facts separately from the immutable documented
# profile constants.  ImageOS/ImageVersion are required GitHub-hosted facts;
# accepting uname substitutes would turn the manifest into a claim instead.
image_os=${ImageOS:?ImageOS is required from the hosted runner}
image_version=${ImageVersion:?ImageVersion is required from the hosted runner}
if [[ $(uname) == Darwin ]]; then cpu_model=$(sysctl -n machdep.cpu.brand_string); else cpu_model=$(awk -F ': ' '/model name/ {print $2; exit}' /proc/cpuinfo); fi

# Candidate commands receive a deliberately constructed environment.  The
# workflow helper (not a candidate checkout) owns both this launch boundary and
# its scratch configuration.  In particular, do not add an inherited Actions
# variable here: `env -i` is the capability boundary, rather than a blacklist.
candidate_root="$output_root/candidate-environment"
mkdir -p "$candidate_root"/{home,tmp,xdg/{cache,config,data,state},gh,prepared/{home,pub-cache,cargo-home},writable/{dart-tool,build,cargo-target,pub-active-roots,linux-flutter-ephemeral,l10n-generated,rust-builder-cargokit}}
chmod 700 "$candidate_root" "$candidate_root"/{home,tmp,xdg,gh,prepared,writable}

candidate_pid=
candidate_wait_pid=
candidate_session=
candidate_marker_file=
candidate_teardown_lock=
candidate_teardown_lock_fd=
candidate_linux_namespace=false
candidate_diagnostic_fd=
candidate_linux_closure_prepared=false
candidate_linux_base_closure_paths=()
candidate_linux_integration_closure_paths=()
candidate_linux_closure_paths=()
candidate_linux_base_manifest=
candidate_linux_integration_manifest=
candidate_private_store_root=
candidate_private_store_parent=
candidate_linux_env_interpreter=
candidate_linux_openssl_pkgconfig=
candidate_linux_openssl_include=
candidate_linux_openssl_lib=
candidate_linux_mesa_dri=
candidate_linux_mesa_egl=
candidate_linux_ticket_root=
candidate_linux_writable_ticket_root=
m003_runner_temp_root=
m003_log=
m003_authorities=
m003_base_sources=
m003_integration_sources=
m003_base_source_identities=
m003_integration_source_identities=
m003_base_source_sha=
m003_integration_source_sha=
m003_authority_sha=
m003_sway_path=
m003_sway_version=
m003_sway_sha=
m003_sway_identity=
m003_swaymsg_path=
m003_swaymsg_version=
m003_swaymsg_sha=
m003_swaymsg_identity=
m003_flock_path=
m003_flock_version=
m003_flock_sha=
m003_flock_identity=
m003_source_pub_lock_sha=
m003_source_cargo_lock_sha=
m003_source_mountpoints_created=()
m003_base_source_count=0
m003_integration_source_count=0
m003_authority_count=0
declare -A m003_current_path=()
declare -A m003_authority_ids=()
declare -A m003_capacity_devices=()
declare -A m003_capacity_device_path=()
declare -A m003_authority_root=()
declare -A m003_authority_leaf=()
declare -A m003_authority_session=()
declare -A m003_authority_kind=()
declare -A m003_current_frozen_identity=()
declare -A m003_frozen_parent_fd=()
declare -A m003_frozen_parent_identity=()
declare -A m003_frozen_parent_uid=()
declare -A m003_frozen_parent_gid=()
declare -A m003_frozen_parent_mode=()
declare -A m003_frozen_parent_mount_id=()
declare -A m003_frozen_parent_mount_device=()
declare -A m003_frozen_parent_mount_root=()
declare -A m003_frozen_parent_mount_point=()
declare -A m003_standard_stream_identity=()
# Keep this as one Bash value so both the parent verification and the
# candidate environment receive real line-feed separated nix.conf settings.
# A single-quoted string containing "\\n" is not a Nix configuration file.
candidate_private_nix_config=$'experimental-features = nix-command flakes\nsandbox = false\nbuild-users-group =\nsubstituters =\nflake-registry =\naccept-flake-config = false'

# The private rooted store is the predecessor Linux backend.  It remains
# available to non-M003 tickets only; raw-39 M003 sessions use their separate
# read-only host-store views and never reference this state.
private_store_root_is_owned() {
  local root=${1:-} canonical_parent canonical_root
  [[ -n ${candidate_private_store_parent:-} && -n $root ]] || return 1
  canonical_parent=$(realpath -e -- "$candidate_private_store_parent") || return 1
  canonical_root=$(realpath -e -- "$root") || return 1
  [[ $canonical_root == "$canonical_parent"/burlmd-private-nix.[[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]] ]] || return 1
  [[ -d $canonical_root && ! -L $canonical_root && -O $canonical_root ]] || return 1
}

cleanup_private_store() {
  local root=${candidate_private_store_root:-}
  [[ -n $root ]] || return 0
  # Only delete the exact mktemp child this parent created.  -P, -xdev, and
  # -delete unlink directory entries without following a candidate-created
  # symlink or crossing into another filesystem.  Nix store objects are
  # read-only after copy, so repair owner write bits first and keep diagnostics
  # quiet during signal cleanup.
  private_store_root_is_owned "$root" || {
    echo 'refusing to clean an unowned private Nix store root' >&2
    return 1
  }
  chmod u+w -- "$root" 2>/dev/null || true
  find -P "$root" -xdev -depth -exec chmod u+w -- {} + 2>/dev/null || true
  find -P "$root" -xdev -depth -delete 2>/dev/null || true
  [[ ! -e $root ]] || {
    echo 'private Nix store cleanup left its owned root behind' >&2
    return 1
  }
  candidate_private_store_root=
}

# The compositor is trusted role infrastructure, but candidate integration can
# fail at any point after it starts. Keep its cleanup on the role's EXIT path
# alongside the legacy private-store cleanup, and preserve the original role status.
# `stop_linux_private_sway_viewport` is defined later in this script, so guard
# the early-error path before that definition has executed.
cleanup_role_exit() {
  local status=$1
  if declare -F stop_linux_private_sway_viewport >/dev/null; then
    stop_linux_private_sway_viewport || true
  fi
  if [[ $ticket != BURL-M003 ]]; then
    cleanup_private_store || true
  fi
  if declare -F m003_close_authority_fds >/dev/null; then
    if ! m003_close_authority_fds; then (( status != 0 )) || status=1; fi
  fi
  if declare -F m003_cleanup_authenticated_source_mountpoints >/dev/null; then
    if ! m003_cleanup_authenticated_source_mountpoints; then (( status != 0 )) || status=1; fi
  fi
  [[ -z ${candidate_teardown_lock_fd:-} ]] || eval "exec ${candidate_teardown_lock_fd}>&-" || true
  if [[ -n ${candidate_diagnostic_fd:-} ]]; then
    eval "exec ${candidate_diagnostic_fd}>&-" || true
    candidate_diagnostic_fd=
  fi
  return "$status"
}
trap 'role_status=$?; trap - EXIT; cleanup_role_exit "$role_status"; exit $?' EXIT
candidate_macos_cleanup_count=0
candidate_shell=$(command -v bash) || { echo 'bash is required for the candidate launcher' >&2; exit 2; }
candidate_env=(
  "PATH=$PATH"
  "HOME=$candidate_root/home"
  "TMPDIR=$candidate_root/tmp"
  "XDG_CACHE_HOME=$candidate_root/xdg/cache"
  "XDG_CONFIG_HOME=$candidate_root/xdg/config"
  "XDG_DATA_HOME=$candidate_root/xdg/data"
  "XDG_STATE_HOME=$candidate_root/xdg/state"
  "GH_CONFIG_DIR=$candidate_root/gh"
  # Dependency acquisition happens before candidate execution in a separate,
  # credential-free environment. Candidate code can read those exact caches,
  # but it never gets a writable package registry or a host cache.
  "PUB_CACHE=$candidate_root/prepared/pub-cache"
  "CARGO_HOME=$candidate_root/prepared/cargo-home"
  "CARGO_TARGET_DIR=$candidate_root/writable/cargo-target"
  "RUSTUP_HOME=$candidate_root/home/rustup"
  "GIT_CONFIG_NOSYSTEM=1"
  "GIT_CONFIG_GLOBAL=/dev/null"
  "GIT_CONFIG_COUNT=0"
  "GIT_TERMINAL_PROMPT=0"
  "LC_ALL=C.UTF-8"
  "LANG=C.UTF-8"
)

candidate_workspace=
candidate_execution_root=$source_root
candidate_tool_path=

prepare_candidate_tool_path() {
  local tool tool_path resolved sandbox_visible link_target
  local -a selected_tools runtime_tools
  # Build a private tool directory for every role. Linux maps its symlinks to
  # the selected read-only closure view inside Bubblewrap, so candidate PATH never names
  # a broad package bin directory (which would expose undeclared clients).
  mapfile -t selected_tools < <(candidate_profile_tools "$ticket" "$role") || return 2
  # These are the minimal runtime helpers used by the trusted candidate
  # launcher and its declared tools. They are not command authority and are
  # deliberately separate from the ticket/role executable inventory.
  runtime_tools=(bash sh env mkdir rm cp mv ln find grep sed awk sort head tail dirname basename readlink sleep perl tr cat ls cmp)
  if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
    # The trusted generated-binding gate uses these existing closure members
    # through the already-declared candidate-tool-path mount.
    runtime_tools+=(mktemp chmod sha256sum sha1sum tar cc ar rustfmt rg)
  fi
  candidate_tool_path=$candidate_root/tool-path
  mkdir -p "$candidate_tool_path"
  for tool in "${selected_tools[@]}" "${runtime_tools[@]}"; do
    if [[ $tool == perl ]]; then tool_path=$trusted_perl; else tool_path=$(command -v "$tool"); fi
    [[ -n ${tool_path:-} ]] || {
      echo "locked macOS candidate tool is missing: $tool" >&2; return 2;
    }
    resolved=$(readlink -f "$tool_path") || return 2
    link_target=$resolved
    case $resolved in
      /nix/store/*) ;;
      "$source_root"/*)
        # Test-only tools may resolve below the explicit source root. Linux
        # exposes that relative path at /source (the authenticated checkout for
        # M003, the prepared execution copy for legacy tickets); macOS uses its
        # disposable workspace directly.
        sandbox_visible="$candidate_workspace/${resolved#"$source_root/"}"
        [[ -f $sandbox_visible && ! -L $sandbox_visible && -x $sandbox_visible ]] || {
          echo "candidate source tool is absent from the disposable workspace: $tool" >&2
          return 2
        }
        if [[ $role == linux-x86_64 ]]; then
          link_target=/source/${resolved#"$source_root/"}
        else
          link_target=$sandbox_visible
        fi
        ;;
      "$script_root"/*) ;;
      *)
        echo "macOS candidate tool is outside the locked closure: $tool ($resolved)" >&2
        return 2
        ;;
    esac
    [[ -e $candidate_tool_path/$tool ]] || ln -s "$link_target" "$candidate_tool_path/$tool"
  done
  # Flutter's macOS embedding invokes these pinned platform build tools.  They
  # are the complete host exception; do not add a broad system directory.
  if [[ $(uname) == Darwin ]]; then
    # Cargokit and Flutter's generated Xcode build scripts invoke exactly these
    # host-native tools. Keep this list narrow: the candidate still receives no
    # ambient system PATH and no VCS, GitHub, linter, or network client.
    for tool in xcrun xcodebuild clang clang++ ld libtool plutil lipo install_name_tool arch; do
      tool_path=$(command -v "$tool") || {
        echo "required macOS native candidate tool is missing: $tool" >&2
        return 2
      }
      ln -s "$(readlink -f "$tool_path")" "$candidate_tool_path/$tool"
    done
    # Flutter 3.44.3 invokes `open <applicationBundle>` after the macOS VM
    # service attaches to foreground the app. Grant that one fixed executable,
    # not a broad /usr/bin directory or any other launch client.
    [[ -x /usr/bin/open ]] || {
      echo 'required macOS application foreground tool is missing: /usr/bin/open' >&2
      return 2
    }
    ln -s /usr/bin/open "$candidate_tool_path/open"
    # Flutter 3.44.3's Darwin OS utility uses these fixed host helpers while
    # tests start: sw_vers, uname -m, and which before its absolute sysctl
    # fallback. Expose only the exact executables, never a broad /usr/bin PATH
    # entry or a sysctl link.
    for tool in sw_vers uname which; do
      [[ -x /usr/bin/$tool ]] || {
        echo "required macOS Flutter host helper is missing: /usr/bin/$tool" >&2
        return 2
      }
      ln -s "/usr/bin/$tool" "$candidate_tool_path/$tool"
    done
  fi
  [[ -n $trusted_perl && -f $trusted_perl && -x $trusted_perl && ! -L $trusted_perl ]] || {
    echo 'locked trusted Perl interpreter is unavailable' >&2
    return 2
  }
  candidate_env[0]="PATH=$candidate_tool_path"
}

validate_pub_lock_dependencies() {
  local path resolved path_entries workspace_root
  [[ -f $candidate_workspace/pubspec.lock && ! -L $candidate_workspace/pubspec.lock ]] || {
    echo 'candidate pubspec.lock is missing or linked' >&2; return 1;
  }
  # Git Pub sources are deliberately unsupported until their resolution can be
  # bound to an immutable commit in the ticket contract. Rejecting them is
  # safer than treating a branch/tag as a lock. Path sources are permitted only
  # when they remain inside this exact disposable checkout.
  if awk '$1 == "source:" && $2 == "git" { exit 1 }' "$candidate_workspace/pubspec.lock"; then :; else
    echo 'candidate pubspec.lock contains a Git dependency without an accepted immutable policy' >&2
    return 1
  fi
  path_entries=$(awk '
    /^  [^[:space:]][^:]*:$/ { path = "" }
    /^[[:space:]]+path: / { path = $2 }
    /^[[:space:]]+source: path$/ { if (path == "") exit 1; print path }
  ' "$candidate_workspace/pubspec.lock") || {
    echo 'pubspec.lock has an invalid path-source entry' >&2; return 1;
  }
  [[ -n $path_entries ]] || return 0
  workspace_root=$(cd "$candidate_workspace" && pwd -P) || return 1
  while IFS= read -r path; do
    [[ -n $path && $path != /* && $path != *'..'* && $path != *'//' ]] || {
      echo "unsafe path dependency in pubspec.lock: $path" >&2; return 1;
    }
    resolved=$(cd "$candidate_workspace/$path" && pwd -P) || return 1
    [[ ( $resolved == "$workspace_root" || $resolved == "$workspace_root"/* ) && -d $resolved && ! -L $resolved ]] || {
      echo "path dependency escapes disposable checkout: $path" >&2; return 1;
    }
  done <<<"$path_entries"
}

validate_cargo_lock_dependencies() {
  local source
  [[ -f $candidate_workspace/rust/Cargo.lock && ! -L $candidate_workspace/rust/Cargo.lock ]] || {
    echo 'candidate rust/Cargo.lock is missing or linked' >&2; return 1;
  }
  # Cargo records a Git source as URL?rev=<immutable revision>#<resolved
  # commit>. Do not permit a floating ref into the prefetch boundary.
  while IFS= read -r source; do
    [[ $source =~ \?rev=[0-9a-f]{40}.*#[0-9a-f]{40}$ ]] || {
      echo "unlocked Cargo Git dependency: $source" >&2; return 1;
    }
  done < <(awk -F '"' '/^source = "git\+/ { print $2 }' "$candidate_workspace/rust/Cargo.lock")
}

m003_source_tracked_state_is_clean() {
  [[ $ticket == BURL-M003 && $role == linux-x86_64 ]] || return 0
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 \
    git -c core.hooksPath=/dev/null -C "$source_root" \
      diff --no-ext-diff --quiet HEAD -- || return 1
  [[ $(sha256sum "$source_root/pubspec.lock" | awk '{print $1}') == "$m003_source_pub_lock_sha" &&
      $(sha256sum "$source_root/rust/Cargo.lock" | awk '{print $1}') == "$m003_source_cargo_lock_sha" ]]
}

m003_prepare_authenticated_source_mountpoints() {
  local relative path parent canonical_parent
  [[ $ticket == BURL-M003 && $role == linux-x86_64 ]] || return 0
  m003_source_pub_lock_sha=$(sha256sum "$source_root/pubspec.lock" | awk '{print $1}') || return 1
  m003_source_cargo_lock_sha=$(sha256sum "$source_root/rust/Cargo.lock" | awk '{print $1}') || return 1
  m003_source_tracked_state_is_clean || {
    echo 'authenticated tested source has modified tracked bytes before Linux preparation' >&2
    return 1
  }
  m003_source_mountpoints_created=()
  for relative in .dart_tool build linux/flutter/ephemeral; do
    path=$source_root/$relative
    parent=$(dirname -- "$path")
    [[ -d $parent && ! -L $parent ]] || return 1
    canonical_parent=$(realpath -e -- "$parent") || return 1
    [[ $canonical_parent == "$parent" && ( $parent == "$source_root" || $parent == "$source_root"/* ) ]] || return 1
    [[ ! -e $path && ! -L $path ]] || {
      echo "authenticated tested source overlay destination already exists: $relative" >&2
      return 1
    }
    mkdir -- "$path" || return 1
    [[ $(realpath -e -- "$path") == "$path" && -d $path && ! -L $path ]] || return 1
    m003_source_mountpoints_created+=("$path")
  done
  m003_source_tracked_state_is_clean
}

m003_cleanup_authenticated_source_mountpoints() {
  local index path
  [[ ${#m003_source_mountpoints_created[@]} -gt 0 ]] || return 0
  for ((index = ${#m003_source_mountpoints_created[@]} - 1; index >= 0; index--)); do
    path=${m003_source_mountpoints_created[index]}
    [[ $path == "$source_root"/* && -d $path && ! -L $path ]] || return 1
    rmdir -- "$path" || return 1
  done
  m003_source_mountpoints_created=()
  m003_source_tracked_state_is_clean
}

prepare_candidate_dependencies() {
  local pub_lock_before cargo_lock_before cargokit_pub_lock cargokit_pub_lock_before manifest manifest_dir resolved_manifest pub_directory pub_lock spike_root resolved_root dependency_kind dependency_path dependency target link
  local -a candidate_dependency_specs
  candidate_workspace="$candidate_root/workspace"
  # The authenticated checkout's tracked bytes remain immutable candidate
  # input. Work that Flutter/Cargo must generate is directed to this disposable
  # copy and later mounted read-only except for the narrow generated/output
  # roots below.
  cp -a -- "$source_root/." "$candidate_workspace"
  [[ -d $candidate_workspace/.git && ! -L $candidate_workspace/.git ]] || {
    echo 'candidate workspace copy lost Git metadata' >&2; return 1;
  }
  if [[ $ticket == BURL-M003 ]]; then
    validate_pub_lock_dependencies
    validate_cargo_lock_dependencies
    pub_lock_before=$(sha256sum "$candidate_workspace/pubspec.lock" | awk '{print $1}')
    cargo_lock_before=$(sha256sum "$candidate_workspace/rust/Cargo.lock" | awk '{print $1}')
  # `flutter pub get --enforce-lockfile` is available in the installed Flutter
  # 3.44.3/Dart 3.12.2 toolchain (verified from its current --help surface).
  # Its only networked phase has a fresh owned HOME/cache and no inherited
  # GitHub, SSH, registry, or cloud capability. `--no-precompile` prevents a
  # dependency fetch from running package executables.
    (cd "$candidate_workspace" && env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
      XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
      XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
      CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
      GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
      flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace")
    [[ $(sha256sum "$candidate_workspace/pubspec.lock" | awk '{print $1}') == "$pub_lock_before" ]] || {
      echo 'flutter pub get changed the committed lockfile' >&2; return 1;
    }
    # Cargokit invokes a nested Dart package while the Linux CMake build runs.
    # Prefetch its separately locked dependencies here, before the candidate
    # enters its network-less namespace. The native build tool's generated
    # runner has a path dependency on this package, so the root Flutter lock
    # cannot cover these package bytes.
    cargokit_pub_lock="$candidate_workspace/rust_builder/cargokit/build_tool/pubspec.lock"
    [[ -f $cargokit_pub_lock && ! -L $cargokit_pub_lock ]] || {
      echo 'Cargokit build-tool pubspec.lock is missing or linked' >&2; return 1;
    }
    cargokit_pub_lock_before=$(sha256sum "$cargokit_pub_lock" | awk '{print $1}')
    (cd "$candidate_workspace/rust_builder/cargokit/build_tool" && env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
      XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
      XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
      CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
      GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
      dart pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace/rust_builder/cargokit/build_tool")
    [[ $(sha256sum "$cargokit_pub_lock" | awk '{print $1}') == "$cargokit_pub_lock_before" ]] || {
      echo 'Cargokit build-tool dependency prefetch changed the committed lockfile' >&2; return 1;
    }
  # `cargo fetch --locked` resolves no build scripts. It is intentionally
  # separate from the offline candidate commands, which can use only this
  # prepared CARGO_HOME and their isolated target directory.
    env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
    CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
      cargo fetch --locked --manifest-path "$candidate_workspace/rust/Cargo.toml"
    [[ $(sha256sum "$candidate_workspace/rust/Cargo.lock" | awk '{print $1}') == "$cargo_lock_before" ]] || {
      echo 'cargo fetch changed the committed lockfile' >&2; return 1;
    }
  fi
  # A managed Spike declares its candidate inputs through trusted creation and
  # verification commands. Derive each exact Cargo manifest and Pub directory
  # from those fields, resolve it below that Spike's prototype root, and reject
  # missing/ambiguous lockfiles instead of searching the candidate checkout.
  if [[ $ticket != BURL-M003 ]]; then
    mapfile -t candidate_dependency_specs < <(taplo get --file-path "$contract" --output-format json 'spikes[*]' |
      jq -er --arg id "SPK-$ticket" '
        [.[] | select(.id == $id)] as $spikes |
        if (($spikes | length) != 1) then error("missing or ambiguous Spike") else $spikes[0] end |
        .path as $root |
        ([.verification_steps[]? |
            .workdir as $workdir | .command |
            scan("--manifest-path[[:space:]]+([^[:space:]]+)")[0] |
            ["cargo", $root, ($workdir + "/" + .)] | @tsv] +
         [.create_commands[]? |
            .workdir as $workdir | .command as $command |
            if $command | startswith("cargo init") then
              ($command | capture("cargo init(?:[[:space:]]+--[^[:space:]]+)*[[:space:]]+(?<path>[^[:space:]]+)$").path) as $path |
              ["cargo", $root, ($workdir + "/" + $path + "/Cargo.toml")] | @tsv
            elif $command | startswith("flutter create") then
              ($command | capture("flutter create.*[[:space:]](?<path>[^[:space:]]+)$").path) as $path |
              ["pub", $root, ($workdir + "/" + $path)] | @tsv
            else empty end]) | unique | .[]
      ' | LC_ALL=C sort -u)
    (( ${#candidate_dependency_specs[@]} > 0 )) || { echo "Spike has no declared candidate dependencies: $ticket" >&2; return 1; }
    for dependency in "${candidate_dependency_specs[@]}"; do
      IFS=$'\t' read -r dependency_kind spike_root dependency_path <<<"$dependency"
      [[ $dependency_kind == cargo || $dependency_kind == pub ]] || return 1
      [[ -n $spike_root && -n $dependency_path && $spike_root != /* && $dependency_path != /* ]] || return 1
      resolved_root=$(cd "$candidate_workspace/$spike_root" && pwd -P) || return 1
      case $dependency_kind in
        cargo)
          manifest_dir=$(cd "$candidate_workspace/$(dirname "$dependency_path")" && pwd -P) || return 1
          resolved_manifest=$manifest_dir/$(basename "$dependency_path")
          [[ $resolved_manifest == "$resolved_root/"* && -f $resolved_manifest && ! -L $resolved_manifest && -f "$manifest_dir/Cargo.lock" && ! -L "$manifest_dir/Cargo.lock" ]] || {
            echo "declared candidate Cargo manifest or lock is missing/unsafe: $dependency_path" >&2; return 1;
          }
          env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 cargo fetch --locked --manifest-path "$resolved_manifest"
          ;;
        pub)
          pub_directory=$(cd "$candidate_workspace/$dependency_path" && pwd -P) || return 1
          pub_lock=$pub_directory/pubspec.lock
          [[ $pub_directory == "$resolved_root/"* && -f $pub_lock && ! -L $pub_lock ]] || { echo "declared candidate Pub lock is missing/unsafe: $dependency_path" >&2; return 1; }
          pub_lock_before=$(sha256sum "$pub_lock" | awk '{print $1}')
          (cd "$pub_directory" && env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$pub_directory")
          [[ $(sha256sum "$pub_lock" | awk '{print $1}') == "$pub_lock_before" ]] || { echo "candidate Pub fetch changed its lockfile: $dependency_path" >&2; return 1; }
          ;;
      esac
    done
  fi
  # Preparation is complete before a candidate can run.  Linux mounts these
  # exact Pub/Cargo caches read-only below; only explicitly named generated
  # roots are writable.  The disposable execution tree is needed for BURL-M003,
  # whose Flutter/Cargo gates generate project files under otherwise immutable
  # source. Spike commands retain their contract-scoped source write roots.
  if [[ $ticket != BURL-M003 ]]; then
    candidate_execution_root=$candidate_workspace
    prepare_linux_ticket_write_root
    return 0
  fi
  # Preserve package_config generated during the prefetch, but prevent any
  # candidate mutation of the copy's tracked source or Git control directory.
  cp -a -- "$candidate_workspace/.dart_tool/." "$candidate_root/writable/dart-tool/"
  # Linux sees its prepared cache at a private Bubblewrap mount, so preserve
  # the generated package config in an owned overlay and remap only that cache
  # URI prefix. Hosted macOS executes directly from this fresh workspace, where
  # the generated config already names the exact credential-free cache.
  if [[ $role == linux-x86_64 ]]; then
    jq --arg host "file://$candidate_root/prepared/pub-cache" \
      --arg sandbox 'file:///candidate/prepared/pub-cache' '
        def remap:
          if type == "string" and startswith($host)
          then $sandbox + .[($host | length):]
          elif type == "array" then map(remap)
          elif type == "object" then with_entries(.value |= remap)
          else .
          end;
        remap
      ' "$candidate_root/writable/dart-tool/package_config.json" \
      >"$candidate_root/writable/dart-tool/package_config.json.next"
    mv -- "$candidate_root/writable/dart-tool/package_config.json.next" \
      "$candidate_root/writable/dart-tool/package_config.json"
    ! rg -F -- "$candidate_root/prepared/pub-cache" \
      "$candidate_root/writable/dart-tool/package_config.json" || {
      echo 'prepared package config still contains a host cache path' >&2; return 1;
    }
    # Pub's active-root bookkeeping is the only cache location tools must
    # update during the Bubblewrap test execution. Package bytes remain below
    # the read-only cache.
    mkdir -p "$candidate_root/prepared/pub-cache/active_roots"
    rm -rf -- "$candidate_workspace/.dart_tool"
    mkdir -p "$candidate_workspace/.dart_tool" "$candidate_workspace/build" "$candidate_workspace/rust/target"
    m003_prepare_authenticated_source_mountpoints || return 1
  fi
  if [[ $role == linux-x86_64 ]]; then
    # Dependency resolution uses a disposable copy because Flutter generates
    # package/plugin metadata while resolving. The raw-39 namespace must still
    # bind the explicit authenticated checkout as /source; only the declared
    # prepared and writable overlays receive generated bytes from this copy.
    candidate_execution_root=$source_root
    # Flutter's Linux CMake files refer to the generated plugin symlinks under
    # linux/flutter/ephemeral. Preserve that generated tree in the sole
    # writable overlay, then rewrite only absolute source/cache targets for
    # their private Bubblewrap mount points.
    cp -a -- "$candidate_workspace/linux/flutter/ephemeral/." "$candidate_root/writable/linux-flutter-ephemeral/"
    cp -a -- "$candidate_workspace/lib/l10n/generated/." "$candidate_root/writable/l10n-generated/"
    cp -a -- "$candidate_workspace/rust_builder/cargokit/." "$candidate_root/writable/rust-builder-cargokit/"
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || return 1
      case $target in
        "$candidate_workspace"/*) ln -sfn "/source/${target#"$candidate_workspace/"}" "$link";;
        "$candidate_root/prepared/pub-cache"/*) ln -sfn "/candidate/prepared/pub-cache/${target#"$candidate_root/prepared/pub-cache/"}" "$link";;
      esac
    done < <(find "$candidate_root/writable/linux-flutter-ephemeral" -type l -print0)
  else
    # Hosted macOS has no Bubblewrap overlay and therefore executes from the
    # disposable resolution workspace exactly as before.
    candidate_execution_root=$candidate_workspace
  fi
}

prepare_linux_ticket_write_root() {
  local ticket_root writable_roots
  [[ $role == linux-x86_64 && $ticket != BURL-M003 ]] || return 0
  # A Spike's prototype root is the only repository subtree its contract
  # declares writable to candidate code. Validate the trusted TOML relation
  # before copying it into a private overlay; never make the checkout writable
  # merely because an output happens to live beneath it.
  ticket_root=$(taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -er --arg id "SPK-$ticket" '
      [.[] | select(.id == $id)] |
      if length == 1 and (.[0].path | type == "string") then .[0].path else error("missing Spike path") end
    ') || return 1
  [[ $ticket_root != /* && $ticket_root != . && $ticket_root != *'..'* && $ticket_root != *'//' && $ticket_root != */ ]] || return 1
  writable_roots=$(taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -ce --arg id "SPK-$ticket" --arg root "$ticket_root" '
      [.[] | select(.id == $id)] |
      if length == 1 and (.[0].write_allowlist | type == "array") and (.[0].write_allowlist | index($root) != null)
      then .[0].write_allowlist else error("Spike root is absent from write allowlist") end
    ') || return 1
  jq -e 'all(.[]; (type == "string") and (length > 0) and (startswith("/") | not) and (contains("..") | not) and (contains("//") | not))' <<<"$writable_roots" >/dev/null || return 1
  [[ -d $candidate_execution_root/$ticket_root && ! -L $candidate_execution_root/$ticket_root ]] || {
    echo "declared Linux writable root is missing or linked: $ticket_root" >&2; return 1;
  }
  if find "$candidate_execution_root/$ticket_root" -xdev -type l -print -quit | grep -q .; then
    echo "declared Linux writable root contains a symbolic link: $ticket_root" >&2
    return 1
  fi
  candidate_linux_ticket_root=$ticket_root
  candidate_linux_writable_ticket_root=$candidate_root/writable/contract-ticket-root
  rm -rf -- "$candidate_linux_writable_ticket_root"
  cp -a -- "$candidate_execution_root/$ticket_root" "$candidate_linux_writable_ticket_root"
}

prepare_generated_bindings_workspace() {
  local check_root
  [[ $role == linux-x86_64 && $ticket == BURL-M003 ]] || return 0
  check_root="$candidate_root/writable/generated-bindings-check"
  rm -rf -- "$check_root"
  cp -a -- "$candidate_execution_root" "$check_root"
  rm -rf -- "$check_root/.dart_tool"
  mkdir -p "$check_root/.dart_tool"
  cp -a -- "$candidate_root/writable/dart-tool/." "$check_root/.dart_tool/"
  printf '%s' "$check_root"
}

prepare_cargokit_tool_runner() {
  local tool_dir build_tool_dir package_hash
  [[ $role == linux-x86_64 && $ticket == BURL-M003 ]] || return 0
  # Cargokit creates this disposable Dart runner during Ninja's Rust-plugin
  # build. Its upstream script deliberately calls `dart pub get` without
  # --offline, so precompile the exact runner into the only writable build
  # overlay while dependency preparation is still allowed. The runner's hash
  # sentinel makes the later network-less CMake invocation reuse these bytes.
  tool_dir="$candidate_root/writable/build/linux/x64/debug/plugins/rust/cargokit_build/tool"
  build_tool_dir="$candidate_root/writable/rust-builder-cargokit/build_tool"
  [[ -d $build_tool_dir && ! -L $build_tool_dir ]] || return 1
  mkdir -p "$tool_dir/bin"
  printf '%s\n' \
    'name: build_tool_runner' \
    'version: 1.0.0' \
    'publish_to: none' \
    '' \
    'environment:' \
    "  sdk: '>=3.0.0 <4.0.0'" \
    '' \
    'dependencies:' \
    '  build_tool:' \
    "    path: \"$build_tool_dir\"" \
    >"$tool_dir/pubspec.yaml"
  printf '%s\n' \
    "import 'package:build_tool/build_tool.dart' as build_tool;" \
    'void main(List<String> args) {' \
    '  build_tool.runMain(args);' \
    '}' \
    >"$tool_dir/bin/build_tool_runner.dart"
  env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
  XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
  XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
  CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    dart pub get --offline --no-precompile --no-example --directory "$tool_dir"
  env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
  XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
  XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
  CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    dart compile kernel "$tool_dir/bin/build_tool_runner.dart"
  # Cargokit hashes the sandbox-visible path, including `ls -R` directory
  # headings. Map that one generated-overlay prefix before hashing so its
  # reuse sentinel remains valid after the host path becomes /source.
  package_hash=$(LC_ALL=C TZ=UTC ls -lR --full-time --numeric-uid-gid "$build_tool_dir" |
    sed -e "s|$candidate_root/writable/rust-builder-cargokit|/source/rust_builder/cargokit|g" \
        -e "s/ $(stat -c '%u' "$build_tool_dir") $(stat -c '%g' "$build_tool_dir") / 0 0 /g" |
    sha1sum) || return 1
  printf '%s\n' "$package_hash" >"$tool_dir/.package_hash"
}

# Each candidate command runs in a fresh session/process group.  A process that
# calls setsid itself is still discoverable through this unguessable per-launch
# marker, allowing the trusted parent to terminate it before it can outlive the
# candidate command.  The marker is not an authority and no code relies on it
# for security after the fresh-job seal boundary.
candidate_session_pids() {
  # `ps eww` is substantially cheaper than opening every procfs environment on
  # a busy hosted runner, and works on both runner families. Read the marker
  # from a file so the scanner's own argv/environment cannot match it.
  [[ -n $candidate_marker_file && -r $candidate_marker_file ]] || return 0
  ps eww -u "$(id -u)" -o pid=,command= 2>/dev/null |
    awk -v marker_file="$candidate_marker_file" '
      BEGIN { getline marker < marker_file }
      index($0, "BURLMD_CANDIDATE_SESSION=" marker) { print $1 }
    '
}

candidate_group_alive() {
  if [[ $candidate_linux_namespace == true ]]; then
    [[ -n $candidate_wait_pid ]] && kill -0 "$candidate_wait_pid" 2>/dev/null
    return
  fi
  if [[ $candidate_pid =~ ^[1-9][0-9]*$ ]]; then
    kill -0 -- "-$candidate_pid" 2>/dev/null
    return
  fi
  [[ $candidate_wait_pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$candidate_wait_pid" 2>/dev/null
}

candidate_has_survivors() {
  if [[ $candidate_linux_namespace == true ]]; then
    candidate_group_alive
    return
  fi
  candidate_group_alive && return 0
  [[ -n $(candidate_session_pids) ]]
}

record_macos_bounded_cleanup() {
  local had_known_processes=$1 marker_matches=0 remaining=false observations
  [[ $role == linux-x86_64 ]] && return 0
  marker_matches=$(candidate_session_pids | wc -l | tr -d ' ')
  candidate_has_survivors && remaining=true
  # GitHub-hosted macOS does not offer a hostile-code lifecycle boundary. This
  # is deliberately a bounded cleanup observation, not a zero-survivor or
  # containment assertion. A remaining process can at most interfere with the
  # subsequent untrusted handoff in this job; it cannot enter the fresh seal
  # job or obtain its provenance authority.
  candidate_macos_cleanup_count=$((candidate_macos_cleanup_count + 1))
  jq -cn --argjson session "$candidate_macos_cleanup_count" \
    --argjson hadKnownProcesses "$had_known_processes" \
    --argjson markerMatches "$marker_matches" --argjson remaining "$remaining" '
    {mode:"bounded-marker-process-group-cleanup", containmentClaim:false,
     zeroSurvivorClaim:false, session:$session,
     knownCandidateProcessesBeforeCleanup:$hadKnownProcesses,
     markerMatchesAfterCleanup:$markerMatches,
     knownCandidateProcessesRemain:$remaining,
     handoffAuthority:"trusted-wrapper-untrusted-candidate-artifact"}
  ' >>"$output_root/results/macos-bounded-cleanup-observations.ndjson"
  # This is deliberately an aggregate.  A role may execute several candidate
  # commands, so publishing the first cleanup observation would conceal a
  # later survivor or failed cleanup attempt.
  observations="$output_root/results/macos-bounded-cleanup-observations.ndjson"
  jq -s '
    def severity:
      [(if .knownCandidateProcessesRemain then 1 else 0 end),
       (if .knownCandidateProcessesBeforeCleanup then 1 else 0 end),
       .markerMatchesAfterCleanup, .session];
    if length == 0 then error("missing bounded cleanup observations") else
      {mode:"bounded-marker-process-group-cleanup", containmentClaim:false,
       zeroSurvivorClaim:false, sessionCount:length, sessions:.,
       final:.[-1], worst:(sort_by(severity) | .[-1]),
       handoffAuthority:"trusted-wrapper-untrusted-candidate-artifact"}
    end
  ' "$observations" >"$output_root/results/macos-bounded-cleanup.json"
}

confirm_linux_namespace_teardown() {
  [[ $candidate_linux_namespace == true ]] || return 0
  if [[ $ticket != BURL-M003 ]]; then
    [[ -n $candidate_teardown_lock && -f $candidate_teardown_lock ]] || {
      echo 'Linux candidate namespace did not publish its teardown lock' >&2
      return 1
    }
    # The predecessor backend proves its private namespace has ended through
    # Bubblewrap's lock pathname. Raw 39 proves teardown through its original
    # retained descriptor.
    flock -n "$candidate_teardown_lock" true || {
      echo 'Linux candidate namespace teardown lock is still held' >&2
      return 1
    }
    return 0
  fi
  [[ -n $candidate_teardown_lock_fd ]] || {
    echo 'Linux candidate retained teardown descriptor is absent' >&2
    return 1
  }
  # Verify the same open file description that was created before Bubblewrap.
  # Never reopen the candidate-visible pathname: it may have been replaced.
  flock --fcntl --exclusive --timeout 5 --conflict-exit-code 73 "$candidate_teardown_lock_fd" || {
    echo 'Linux candidate namespace teardown OFD lock is still held' >&2
    return 1
  }
}

terminate_candidate_session() {
  local pass pid had_known_processes=false cleanup_status=0
  if [[ $candidate_linux_namespace == true ]]; then
    [[ -n $candidate_pid ]] || return 0
    kill -TERM "$candidate_wait_pid" 2>/dev/null || true
    for ((pass = 0; pass < 100; pass++)); do
      candidate_group_alive || break
      sleep 0.1
    done
    if candidate_group_alive; then
      kill -KILL "$candidate_wait_pid" 2>/dev/null || true
      for ((pass = 0; pass < 50; pass++)); do
        candidate_group_alive || break
        sleep 0.1
      done
    fi
    [[ -z $candidate_wait_pid ]] || wait "$candidate_wait_pid" 2>/dev/null || true
    candidate_group_alive && {
      echo 'Linux candidate wrapper survived bounded TERM/KILL teardown' >&2
      return 1
    }
    confirm_linux_namespace_teardown || return 1
    candidate_pid=
    candidate_wait_pid=
    candidate_session=
    candidate_marker_file=
    candidate_teardown_lock=
    if [[ $ticket == BURL-M003 ]]; then
      eval "exec ${candidate_teardown_lock_fd}>&-" || return 1
      candidate_teardown_lock_fd=
    fi
    candidate_linux_namespace=false
    return 0
  fi
  [[ -n $candidate_pid || -n $candidate_wait_pid || -n $candidate_session || -n $candidate_marker_file ]] || return 0
  candidate_has_survivors && had_known_processes=true
  # TERM gives Flutter and its test device a chance to stop cleanly.  Do not
  # depend on GNU timeout: the bounded polling works on the hosted macOS shell.
  [[ $candidate_pid =~ ^[1-9][0-9]*$ ]] && kill -TERM -- "-$candidate_pid" 2>/dev/null || true
  [[ $candidate_wait_pid =~ ^[1-9][0-9]*$ ]] && kill -TERM "$candidate_wait_pid" 2>/dev/null || true
  for ((pass = 0; pass < 50; pass++)); do
    candidate_has_survivors || break
    sleep 0.1
  done
  if candidate_has_survivors; then
    while IFS= read -r pid; do
      [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -TERM "$pid" 2>/dev/null || true
    done < <(candidate_session_pids)
    for ((pass = 0; pass < 50; pass++)); do
      candidate_has_survivors || break
      sleep 0.1
    done
  fi
  if candidate_has_survivors; then
    [[ $candidate_pid =~ ^[1-9][0-9]*$ ]] && kill -KILL -- "-$candidate_pid" 2>/dev/null || true
    [[ $candidate_wait_pid =~ ^[1-9][0-9]*$ ]] && kill -KILL "$candidate_wait_pid" 2>/dev/null || true
    while IFS= read -r pid; do
      [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -KILL "$pid" 2>/dev/null || true
    done < <(candidate_session_pids)
    for ((pass = 0; pass < 20; pass++)); do
      candidate_has_survivors || break
      sleep 0.1
    done
  fi
  [[ -z $candidate_wait_pid ]] || wait "$candidate_wait_pid" 2>/dev/null || true
  record_macos_bounded_cleanup "$had_known_processes" || cleanup_status=$?
  candidate_pid=
  candidate_wait_pid=
  candidate_session=
  candidate_marker_file=
  return "$cleanup_status"
}

candidate_signal() {
  local signal=$1 status=$2
  trap - INT TERM HUP
  terminate_candidate_session || true
  exit "$status"
}
trap 'candidate_signal INT 130' INT
trap 'candidate_signal TERM 143' TERM
trap 'candidate_signal HUP 129' HUP

close_inherited_candidate_fds() {
  local root fd number
  root=/dev/fd; [[ -d /proc/self/fd ]] && root=/proc/self/fd
  # Bash reads this script through FD 255. Preserve that interpreter FD only;
  # Bash marks it close-on-exec, so it cannot reach the candidate command.
  for fd in "$root"/*; do
    number=${fd##*/}
    [[ $number =~ ^[0-9]+$ ]] || continue
    ((number > 2 && number != 255)) || continue
    eval "exec $number>&-" 2>/dev/null || return 1
  done
}

# This is deliberately an explicit inventory rather than an attempt to parse
# shell from the candidate-controlled checkout.  The contract's commands are
# trusted input, but shell parsing would still be a weaker authority boundary
# (subshells, redirects, and command strings).  Keep the command inventory and
# its ticket/role closure together; the check below fails before launch when a
# declared executable is omitted from the selected profile.
candidate_profile_tools() {
  local requested_ticket=$1 requested_role=$2
  case "$requested_ticket:$requested_role" in
    BURL-M003:linux-x86_64)
      # FRB 2.12.0 invokes `cargo expand` while it generates bindings.  Keep
      # the executable in the ticket-scoped closure so a network-denied
      # candidate cannot fall back to `cargo install cargo-expand`. `ip` is
      # the locked loopback control command used by every M003 Linux launch.
      # Cargokit locates `rustup` in the selected read-only view, so grant
      # the narrow Nix shim rather than an ambient mutable Rust installation.
      # Bubblewrap is parent-only. Sway/swaymsg are mounted only in integration
      # views and are launched by the in-namespace supervisor.
      printf '%s\n' env flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup cmake ninja pkg-config clang openssl jq ip
      ;;
    BURL-M003:macos-26-arm64|BURL-M003:macos-15-arm64)
      # macOS executes its native Flutter/Cargo evidence directly. The Linux
      # compositor/FRB closure is neither needed nor granted there.
      # `cargo metadata` is an explicit BURL-M003 candidate gate. Cargo
      # probes `rustc -vV` even for metadata, so the compiler is part of the
      # minimal macOS execution closure rather than an ambient fallback.
      # Cargokit asks rustup about the native target even though the pinned Nix
      # toolchain already supplies it. Grant the narrow shim, never a mutable
      # rustup home or an ambient Rust installation.
      printf '%s\n' env cargo rustc rustup flutter dart
      ;;
    BURL-O001:linux-x86_64)
      printf '%s\n' env cargo flutter dart cmake ninja pkg-config clang openssl nix nix-store
      ;;
    BURL-O001:macos-26-arm64|BURL-O001:macos-15-arm64)
      printf '%s\n' env cargo flutter dart
      ;;
    BURL-H001:*|BURL-H002:*|BURL-I001:*|BURL-L001:*|BURL-G011:*|BURL-P002:*|BURL-O004:*|BURL-O011:*|BURL-O012:*|BURL-O013:*)
      printf '%s\n' env cargo flutter dart
      ;;
    *) return 2 ;;
  esac
}

candidate_command_executables() {
  # This is intentionally independent of candidate_profile_tools. It names the
  # executable families the trusted candidate phase and raw contract commands
  # require; the selected profile below is the separately reviewed authority
  # grant. A profile omission must therefore fail before a candidate launches.
  local requested_ticket=$1 requested_role=$2
  case "$requested_ticket:$requested_role" in
    BURL-M003:linux-x86_64)
      # FRB 2.12.0 itself invokes cargo-expand during generation.
      # The loopback launcher and Cargokit respectively require `ip` and the
      # locked rustup shim from the selected read-only view.
      printf '%s\n' env flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup cmake ninja pkg-config clang openssl jq ip
      ;;
    BURL-M003:macos-26-arm64|BURL-M003:macos-15-arm64)
      printf '%s\n' cargo flutter dart
      ;;
    BURL-O001:linux-x86_64)
      # Packaging is the sole candidate that receives private offline Nix
      # authority. Its raw steps run cargo and dispatch nix after the trusted
      # result-tool -- wrapper; nix-store is required by that locked client.
      printf '%s\n' cargo nix nix-store
      ;;
    BURL-O001:macos-26-arm64|BURL-O001:macos-15-arm64)
      printf '%s\n' cargo
      ;;
    BURL-H001:*|BURL-H002:*|BURL-I001:*|BURL-L001:*|BURL-G011:*|BURL-P002:*|BURL-O004:*|BURL-O011:*|BURL-O012:*|BURL-O013:*)
      printf '%s\n' cargo flutter dart
      ;;
    *) return 2 ;;
  esac
}

trusted_contract_candidate_heads() {
  # Parse only the trusted TOML command text. Never eval candidate or contract
  # shell. We inspect command heads and the final command after a trusted `--`
  # wrapper, which covers `cargo run … -- execute … -- nix …` without treating
  # arbitrary shell syntax as an authority boundary.
  local command_text segment nested_head head
  role_steps_for "$ticket" "$role" |
    jq -r '.[]?.command // empty' |
    while IFS= read -r command_text; do
      while [[ -n $command_text ]]; do
        segment=${command_text%%;*}
        if [[ $command_text == *';'* ]]; then command_text=${command_text#*;}; else command_text=; fi
        segment=${segment#"${segment%%[![:space:]]*}"}
        head=${segment%%[[:space:]]*}
        case $head in cargo|flutter|dart|nix|nix-store) printf '%s\n' "$head";; esac
        if [[ $segment == *' -- '* ]]; then
          nested_head=${segment##* -- }
          nested_head=${nested_head%%[[:space:]]*}
          case $nested_head in cargo|flutter|dart|nix|nix-store) printf '%s\n' "$nested_head";; esac
        fi
      done
    done
}

validate_candidate_tool_profile() {
  local requested contract_head
  local -a selected=()
  mapfile -t selected < <(candidate_profile_tools "$ticket" "$role") || return 2
  ((${#selected[@]} > 0)) || return 2
  while IFS= read -r requested; do
    [[ " ${selected[*]} " == *" $requested "* ]] || {
      echo "candidate command executable is absent from $ticket/$role closure: $requested" >&2
      return 2
    }
  done < <(candidate_command_executables "$ticket" "$role")
  # The raw command records remain trusted data, but must not silently gain a
  # new candidate executable. Check their direct heads and nested post-`--`
  # heads against both independent expectation and the selected profile.
  while IFS= read -r contract_head; do
    [[ " ${selected[*]} " == *" $contract_head "* ]] || {
      echo "trusted contract executable is absent from $ticket/$role closure: $contract_head" >&2
      return 2
    }
    candidate_command_executables "$ticket" "$role" | rg -Fxq -- "$contract_head" || {
      echo "trusted contract executable is absent from independent $ticket/$role inventory: $contract_head" >&2
      return 2
    }
  done < <(trusted_contract_candidate_heads | LC_ALL=C sort -u)
}

prepare_linux_candidate_private_store() {
  local tool tool_path resolved store_entry closure_root runner_temp_root
  local -a closure_roots required_tools selected_tools
  [[ $role == linux-x86_64 ]] || return 0
  [[ $ticket != BURL-M003 ]] || {
    echo 'BURL-M003 must use the raw-39 read-only closure views' >&2
    return 2
  }
  [[ $candidate_linux_closure_prepared == false ]] || return 0
  command -v nix-store >/dev/null || {
    echo 'locked nix-store is required to materialize Linux candidate closure' >&2
    return 2
  }
  # Resolve this once in the trusted parent, after dependency preparation and
  # before any candidate process exists.  Candidate sessions reuse this exact
  # chroot store; they never invoke devenv, nix copy, or the host daemon.
  mapfile -t selected_tools < <(candidate_profile_tools "$ticket" "$role") || return 2
  required_tools=(bash sh mkdir mktemp chmod install cp mv rm awk sed grep rg sort sha256sum wc find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head "${selected_tools[@]}")
  closure_roots=()
  for tool in "${required_tools[@]}"; do
    # Cargo's development-shell integration can prepend a mutable
    # CARGO_INSTALL_ROOT/bin.  The explicit value is supplied by devenv.nix
    # from pkgs.cargo-expand, so this trusted preflight never selects that
    # ambient installation by PATH precedence.
    if [[ $tool == cargo-expand ]]; then
      tool_path=${BURLMD_CARGO_EXPAND:-}
    else
      tool_path=$(command -v "$tool")
    fi
    [[ -n $tool_path ]] || {
      echo "locked candidate tool is missing: $tool" >&2
      return 2
    }
    resolved=$(readlink -f "$tool_path") || {
      echo "cannot resolve locked candidate tool: $tool" >&2
      return 2
    }
    case $resolved in
      /nix/store/*)
        store_entry=${resolved#/nix/store/}
        # Every executable, including trusted launcher mechanics, is copied
        # into the private rooted store. The candidate receives no host-store
        # source mount after the private /nix bind.
        closure_roots+=("/nix/store/${store_entry%%/*}")
        [[ $tool == env ]] && candidate_linux_env_interpreter=$resolved
        ;;
      "$source_root"/*|"$script_root"/*)
        # Command doubles live only in the role-path unit fixture.  They are
        # never a production source because the workflow PATH is locked Nix.
        ;;
      *)
        echo "candidate tool is outside the locked Nix closure: $tool ($resolved)" >&2
        return 2
        ;;
    esac
  done
  (( ${#closure_roots[@]} > 0 )) || {
    echo 'Linux candidate has no locked closure roots' >&2
    return 2
  }
  mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
  if [[ " ${selected_tools[*]} " == *' openssl '* ]]; then
    candidate_linux_openssl_pkgconfig=$(pkg-config --variable=pcfiledir openssl) || {
      echo 'locked OpenSSL pkg-config metadata is unavailable' >&2
      return 2
    }
    [[ $candidate_linux_openssl_pkgconfig == /nix/store/* && -d $candidate_linux_openssl_pkgconfig ]] || {
      echo "OpenSSL pkg-config path is outside the locked store: $candidate_linux_openssl_pkgconfig" >&2
      return 2
    }
    store_entry=${candidate_linux_openssl_pkgconfig#/nix/store/}
    closure_roots+=("/nix/store/${store_entry%%/*}")
    candidate_linux_openssl_include=$(pkg-config --variable=includedir openssl) || return 2
    candidate_linux_openssl_lib=$(pkg-config --variable=libdir openssl) || return 2
    [[ $candidate_linux_openssl_include == /nix/store/* && -d $candidate_linux_openssl_include && $candidate_linux_openssl_lib == /nix/store/* && -d $candidate_linux_openssl_lib ]] || {
      echo 'OpenSSL include or library path is outside the locked store' >&2
      return 2
    }
    store_entry=${candidate_linux_openssl_include#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
    store_entry=${candidate_linux_openssl_lib#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
  fi
  mapfile -t candidate_linux_closure_paths < <(
    for closure_root in "${closure_roots[@]}"; do nix-store -qR "$closure_root"; done | LC_ALL=C sort -u
  )
  (( ${#candidate_linux_closure_paths[@]} > 0 )) || {
    echo 'Linux candidate runtime closure is empty' >&2
    return 2
  }
  runner_temp_root=$(realpath -e -- "${RUNNER_TEMP:-/tmp}") || {
    echo 'RUNNER_TEMP is not an existing canonical directory' >&2
    return 2
  }
  [[ -d $runner_temp_root && ! -L $runner_temp_root && -O $runner_temp_root ]] || {
    echo 'RUNNER_TEMP must be an owned, non-symbolic-link directory' >&2
    return 2
  }
  candidate_private_store_parent=$runner_temp_root
  candidate_private_store_root=$(mktemp -d "$candidate_private_store_parent/burlmd-private-nix.XXXXXXXX") || return 2
  private_store_root_is_owned "$candidate_private_store_root" || {
    echo 'mktemp did not create an owned private Nix store child' >&2
    return 2
  }
  # A path destination is Nix's documented local/chroot store: copied objects
  # live under <root>/nix/store and its SQLite metadata under
  # <root>/nix/var/nix/db. Copy only the authenticated host closure while the
  # trusted parent still has access to it.
  nix copy --offline --to "$candidate_private_store_root" --no-check-sigs "${candidate_linux_closure_paths[@]}" || return 2
  [[ -f $candidate_private_store_root/nix/var/nix/db/db.sqlite ]] || {
    echo 'private Nix store has no SQLite database' >&2
    return 2
  }
  ! find -P "$candidate_private_store_root/nix" -xdev -type s -print -quit | grep -q . || {
    echo 'private Nix store contains a daemon socket' >&2
    return 2
  }
  NIX_REMOTE=local NIX_PATH= NIX_CONFIG="$candidate_private_nix_config" \
    nix --store "local?root=$candidate_private_store_root" store verify --all --no-trust || return 2
  candidate_linux_closure_prepared=true
}

private_closure_member() {
  local logical_path=$1 physical_path canonical_private_root canonical_physical
  [[ $logical_path == /nix/store/* ]] || return 1
  private_store_root_is_owned "$candidate_private_store_root" || return 1
  canonical_private_root=$(realpath -e -- "$candidate_private_store_root") || return 1
  physical_path="$canonical_private_root/nix/store/${logical_path#/nix/store/}"
  canonical_physical=$(realpath -e -- "$physical_path") || return 1
  [[ $canonical_physical == "$canonical_private_root"/nix/store/* && ! -L $canonical_physical ]] || return 1
  # The private source must map back to exactly the logical path it overlays;
  # a same-named symlink or a host-store path is never an acceptable source.
  [[ "/nix${canonical_physical#"$canonical_private_root/nix"}" == "$logical_path" ]] || return 1
  printf '%s\n' "$canonical_physical"
}

m003_observe_exact_executable() {
  local label=$1 executable=$2 expected_path=$3 expected_version=$4 expected_sha=$5
  shift 5
  local canonical before_identity after_identity stdout_path stderr_path status observed_version observed_sha
  [[ $label == sway || $label == swaymsg || $label == flock ]] || return 1
  [[ $executable == /* && $expected_path == /* && -f $executable && ! -L $executable && -x $executable ]] || return 1
  canonical=$(realpath -e -- "$executable") || return 1
  [[ $canonical == "$expected_path" ]] || return 1
  before_identity=$(stat -Lc '%d:%i' -- "$canonical") || return 1
  observed_sha=$(sha256sum "$canonical" | awk '{print $1}') || return 1
  [[ $observed_sha == "$expected_sha" ]] || return 1
  stdout_path=$m003_runner_temp_root/burlmd-m003/$label-version.stdout
  stderr_path=$m003_runner_temp_root/burlmd-m003/$label-version.stderr
  set +e
  LC_ALL=C "$canonical" "$@" >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e
  [[ $status == 0 && ! -s $stderr_path ]] || return 1
  observed_version=$(<"$stdout_path")
  [[ $observed_version == "$expected_version" && $(wc -c <"$stdout_path" | tr -d ' ') == $((${#expected_version} + 1)) ]] || return 1
  [[ $(realpath -e -- "$executable") == "$expected_path" ]] || return 1
  after_identity=$(stat -Lc '%d:%i' -- "$canonical") || return 1
  [[ $after_identity == "$before_identity" ]] || return 1
  [[ $(sha256sum "$canonical" | awk '{print $1}') == "$observed_sha" ]] || return 1
  case $label in
    sway)
      m003_sway_path=$canonical; m003_sway_version=$observed_version
      m003_sway_sha=$observed_sha; m003_sway_identity=$after_identity
      ;;
    swaymsg)
      m003_swaymsg_path=$canonical; m003_swaymsg_version=$observed_version
      m003_swaymsg_sha=$observed_sha; m003_swaymsg_identity=$after_identity
      ;;
    flock)
      m003_flock_path=$canonical; m003_flock_version=$observed_version
      m003_flock_sha=$observed_sha; m003_flock_identity=$after_identity
      ;;
  esac
  rm -f -- "$stdout_path" "$stderr_path"
}

m003_revalidate_observed_executables() {
  local flock_path
  flock_path=$(readlink -f "$(command -v flock)") || return 1
  m003_observe_exact_executable flock "$flock_path" \
    /nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock \
    'flock from util-linux 2.42' da3e7c9e5f6fe80cf7b32cd0dc8585a15b1ceed617857066dbfdd4de2256ba33 --version || return 1
  m003_observe_exact_executable sway \
    /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway \
    /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway \
    'sway version 1.12' 1f10250bedd99cda8a7ef04a585f66a1dd300bd37557dbd9983535b0a8b5667d --version || return 1
  m003_observe_exact_executable swaymsg \
    /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg \
    /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg \
    'swaymsg version 1.12' cfefe762ed1ed9463eeddad3b1e624f98fe15996bde77953f303a2a110d1270c --version
}

prepare_linux_candidate_closure_views() {
  local tool tool_path resolved store_entry closure_root runner_temp_root manifest_root sway_root swaymsg_root bwrap_root nix_executable nix_store_executable
  local -a closure_roots required_tools selected_tools
  [[ $role == linux-x86_64 ]] || return 0
  [[ $ticket == BURL-M003 ]] || return 0
  [[ $candidate_linux_closure_prepared == false ]] || return 0
  nix_executable=$(command -v nix) || { echo 'locked nix is required to construct Linux candidate closure views' >&2; return 2; }
  nix_store_executable=$(command -v nix-store) || { echo 'locked nix-store is required to construct Linux candidate closure views' >&2; return 2; }
  [[ -x $nix_executable && -x $nix_store_executable && $($nix_executable --version) == 'nix (Nix) 2.35.2' && $($nix_store_executable --version) == 'nix-store (Nix) 2.35.2' ]] || {
    echo 'raw-39 closure views require locked Nix 2.35.2' >&2; return 2;
  }
  # Resolve this once in the trusted parent, after dependency preparation and
  # before any candidate process exists.  The resulting manifests select
  # same-path read-only host-store mounts; no private store, Nix state, or
  # copy is ever exposed to a candidate.
  mapfile -t selected_tools < <(candidate_profile_tools "$ticket" "$role") || return 2
  required_tools=(bash sh mkdir mktemp chmod install cp mv rm cmp awk sed grep rg sort sha256sum wc find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head "${selected_tools[@]}")
  closure_roots=()
  for tool in "${required_tools[@]}"; do
    # Cargo's development-shell integration can prepend a mutable
    # CARGO_INSTALL_ROOT/bin.  The explicit value is supplied by devenv.nix
    # from pkgs.cargo-expand, so this trusted preflight never selects that
    # ambient installation by PATH precedence.
    if [[ $tool == cargo-expand ]]; then
      tool_path=${BURLMD_CARGO_EXPAND:-}
    else
      tool_path=$(command -v "$tool")
    fi
    [[ -n $tool_path ]] || {
      echo "locked candidate tool is missing: $tool" >&2
      return 2
    }
    resolved=$(readlink -f "$tool_path") || {
      echo "cannot resolve locked candidate tool: $tool" >&2
      return 2
    }
    case $resolved in
      /nix/store/*)
        store_entry=${resolved#/nix/store/}
        # Bubblewrap itself remains parent-only. Every other selected root is
        # later mounted same-path and read-only into the selected view.
        closure_roots+=("/nix/store/${store_entry%%/*}")
        [[ $tool == env ]] && candidate_linux_env_interpreter=$resolved
        ;;
      "$source_root"/*|"$script_root"/*)
        # Command doubles live only in the role-path unit fixture.  They are
        # never a production source because the workflow PATH is locked Nix.
        ;;
      *)
        echo "candidate tool is outside the locked Nix closure: $tool ($resolved)" >&2
        return 2
        ;;
    esac
  done
  (( ${#closure_roots[@]} > 0 )) || {
    echo 'Linux candidate has no locked closure roots' >&2
    return 2
  }
  mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
  if [[ " ${selected_tools[*]} " == *' openssl '* ]]; then
  candidate_linux_openssl_pkgconfig=$(pkg-config --variable=pcfiledir openssl) || {
    echo 'locked OpenSSL pkg-config metadata is unavailable' >&2
    return 2
  }
  [[ $candidate_linux_openssl_pkgconfig == /nix/store/* && -d $candidate_linux_openssl_pkgconfig ]] || {
    echo "OpenSSL pkg-config path is outside the locked store: $candidate_linux_openssl_pkgconfig" >&2
    return 2
  }
  store_entry=${candidate_linux_openssl_pkgconfig#/nix/store/}
  closure_roots+=("/nix/store/${store_entry%%/*}")
  candidate_linux_openssl_include=$(pkg-config --variable=includedir openssl) || return 2
  candidate_linux_openssl_lib=$(pkg-config --variable=libdir openssl) || return 2
  [[ $candidate_linux_openssl_include == /nix/store/* && -d $candidate_linux_openssl_include && $candidate_linux_openssl_lib == /nix/store/* && -d $candidate_linux_openssl_lib ]] || {
    echo 'OpenSSL include or library path is outside the locked store' >&2
    return 2
  }
  store_entry=${candidate_linux_openssl_include#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
  store_entry=${candidate_linux_openssl_lib#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
  fi
  if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  candidate_linux_mesa_dri=${BURLMD_MESA_DRI_PATH:?locked Mesa DRI path is required}
  candidate_linux_mesa_egl=${BURLMD_MESA_EGL_VENDOR_PATH:?locked Mesa EGL vendor path is required}
  [[ $candidate_linux_mesa_dri == /nix/store/* && -d $candidate_linux_mesa_dri && $candidate_linux_mesa_egl == /nix/store/* && -f $candidate_linux_mesa_egl ]] || {
    echo 'locked Mesa paths are outside the immutable Nix store' >&2
    return 2
  }
  mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
  mapfile -t candidate_linux_base_closure_paths < <(
    for closure_root in "${closure_roots[@]}"; do "$nix_store_executable" -qR "$closure_root"; done | LC_ALL=C sort -u
  )
  else
    candidate_linux_mesa_dri=
    candidate_linux_mesa_egl=
    mapfile -t candidate_linux_base_closure_paths < <(for closure_root in "${closure_roots[@]}"; do "$nix_store_executable" -qR "$closure_root"; done | LC_ALL=C sort -u)
  fi
  if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
    mapfile -t candidate_linux_base_closure_paths < <(
      { printf '%s\n' "${candidate_linux_base_closure_paths[@]}"; "$nix_store_executable" -qR "${candidate_linux_mesa_dri%/lib/dri}"; "$nix_store_executable" -qR "${candidate_linux_mesa_egl%/share/glvnd/egl_vendor.d/50_mesa.json}"; } | LC_ALL=C sort -u
    )
  fi
  (( ${#candidate_linux_base_closure_paths[@]} > 0 )) || {
    echo 'Linux candidate runtime closure is empty' >&2
    return 2
  }
  runner_temp_root=$(realpath -e -- "${RUNNER_TEMP:-/tmp}") || {
    echo 'RUNNER_TEMP is not an existing canonical directory' >&2
    return 2
  }
  [[ -d $runner_temp_root && ! -L $runner_temp_root && -O $runner_temp_root ]] || {
    echo 'RUNNER_TEMP must be an owned, non-symbolic-link directory' >&2
    return 2
  }
  manifest_root=$runner_temp_root/burlmd-m003
  mkdir -p "$manifest_root" && chmod 700 "$manifest_root" || return 2
  m003_runner_temp_root=$runner_temp_root
  m003_revalidate_observed_executables || {
    echo 'trusted compositor or teardown executable does not match the raw-39 identity' >&2; return 2;
  }
  candidate_linux_base_manifest=$manifest_root/base-session-closure.manifest
  printf '%s\n' "${candidate_linux_base_closure_paths[@]}" >"$candidate_linux_base_manifest"
  sway_root=$m003_sway_path
  swaymsg_root=$m003_swaymsg_path
  # Strip the executable suffix to its store member without relying on a
  # package database inside the candidate namespace.
  sway_root=$(dirname "$(dirname "$sway_root")")
  swaymsg_root=$(dirname "$(dirname "$swaymsg_root")")
  mapfile -t candidate_linux_integration_closure_paths < <({ printf '%s\n' "${candidate_linux_base_closure_paths[@]}"; "$nix_store_executable" -qR "$sway_root"; "$nix_store_executable" -qR "$swaymsg_root"; } | LC_ALL=C sort -u)
  candidate_linux_integration_manifest=$manifest_root/integration-session-closure.manifest
  printf '%s\n' "${candidate_linux_integration_closure_paths[@]}" >"$candidate_linux_integration_manifest"
  # The views are a pinned interface, not a best-effort reduction.  Validate
  # the exact locked inventories before any candidate namespace is created.
  [[ $(wc -l <"$candidate_linux_base_manifest" | tr -d ' ') == 488 && $(wc -c <"$candidate_linux_base_manifest" | tr -d ' ') == 30717 && $(sha256sum "$candidate_linux_base_manifest" | awk '{print $1}') == 127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64 ]] || {
    echo 'base Linux closure view differs from the raw-39 locked manifest' >&2; return 2;
  }
  [[ $(wc -l <"$candidate_linux_integration_manifest" | tr -d ' ') == 547 && $(wc -c <"$candidate_linux_integration_manifest" | tr -d ' ') == 34315 && $(sha256sum "$candidate_linux_integration_manifest" | awk '{print $1}') == 353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896 ]] || {
    echo 'integration Linux closure view differs from the raw-39 locked manifest' >&2; return 2;
  }
  [[ $("$nix_executable" path-info --json "${candidate_linux_base_closure_paths[@]}" | jq -er '[.[] | .narSize] | add') == 6184635112 && $("$nix_executable" path-info --json "${candidate_linux_integration_closure_paths[@]}" | jq -er '[.[] | .narSize] | add') == 6338147240 ]] || {
    echo 'Linux closure views differ from the raw-39 NAR measurements' >&2; return 2;
  }
  bwrap_root=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2
  [[ -x $bwrap_root/bin/bwrap && $("$bwrap_root/bin/bwrap" --version) == 'bubblewrap 0.11.2' && $(sha256sum "$bwrap_root/bin/bwrap" | awk '{print $1}') == c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726 ]] || {
    echo 'trusted Bubblewrap does not match the raw-39 identity' >&2; return 2;
  }
  "$nix_store_executable" -qR "$bwrap_root" | LC_ALL=C sort -u >"$manifest_root/trusted-parent-bubblewrap.manifest"
  [[ $(wc -l <"$manifest_root/trusted-parent-bubblewrap.manifest" | tr -d ' ') == 8 && $(wc -c <"$manifest_root/trusted-parent-bubblewrap.manifest" | tr -d ' ') == 480 && $(sha256sum "$manifest_root/trusted-parent-bubblewrap.manifest" | awk '{print $1}') == 398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd && $("$nix_executable" path-info --json $(<"$manifest_root/trusted-parent-bubblewrap.manifest") | jq -er '[.[] | .narSize] | add') == 40679016 ]] || {
    echo 'trusted Bubblewrap closure differs from the raw-39 inventory' >&2; return 2;
  }
  ! rg -Fq '/nix/var' "$candidate_linux_base_manifest" "$candidate_linux_integration_manifest" || return 2
  candidate_linux_closure_prepared=true
}

run_linux_native_isolation_prerequisite() {
  local probe_shell probe_ip probe_bwrap member probe_nar_bytes probe_bind_bytes nix_executable nix_store_executable
  local -a probe_members=() probe_args=()
  [[ $ticket == BURL-M003 && $role == linux-x86_64 ]] || return 0
  nix_executable=$(command -v nix) || return 2
  nix_store_executable=$(command -v nix-store) || return 2
  [[ -x $nix_executable && -x $nix_store_executable && $($nix_executable --version) == 'nix (Nix) 2.35.2' && $($nix_store_executable --version) == 'nix-store (Nix) 2.35.2' ]] || return 2
  probe_shell=/nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash
  probe_ip=/nix/store/qbsvh4fw7lrmkqk870w4sc21kqylph42-iproute2-7.0.0/bin/ip
  probe_bwrap=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap
  [[ -x $probe_shell && -x $probe_ip && -x $probe_bwrap ]] || return 2
  mapfile -t probe_members < <({ "$nix_store_executable" -qR "${probe_shell%/bin/bash}"; "$nix_store_executable" -qR "${probe_ip%/bin/ip}"; } | LC_ALL=C sort -u)
  [[ ${#probe_members[@]} == 33 ]] || return 2
  [[ $(printf '%s\n' "${probe_members[@]}" | wc -c | tr -d ' ') == 1985 ]] || return 2
  [[ $(printf '%s\n' "${probe_members[@]}" | sha256sum | awk '{print $1}') == 8417a87e4610c15b6237f416532defaaee9c93a06f2b605c6abaeaa8278df8b2 ]] || return 2
  probe_nar_bytes=$("$nix_executable" path-info --json "${probe_members[@]}" | jq -er '[.[] | .narSize] | add') || return 2
  probe_bind_bytes=$(for member in "${probe_members[@]}"; do printf '%s\0%s\0%s\0' --ro-bind "$member" "$member"; done | wc -c | tr -d ' ')
  [[ $probe_nar_bytes == 97009672 && $probe_bind_bytes == 4300 ]] || return 2
  probe_args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --proc /proc --dev /dev --dir /nix --dir /nix/store)
  for member in "${probe_members[@]}"; do probe_args+=(--ro-bind "$member" "$member"); done
  # No sudo/sysctl/AppArmor fallback or restoration path exists: this one
  # native namespace/loopback probe is the fail-closed hosted prerequisite.
  "$probe_bwrap" "${probe_args[@]}" -- "$probe_shell" -c 'set -euo pipefail; "$1" link set dev lo up; line=$("$1" -o link show up dev lo); [[ -n $line && $line == *'"'"'<LOOPBACK,UP,'"'"'* ]]' _ "$probe_ip"
}

# Raw 39 keeps this work in the trusted parent. The
# role log is later parsed by a fresh seal, so all row construction comes from
# the contract and retained parent paths, never from candidate output.
m003_fsync_file() {
  local path=$1
  perl -MIO::Handle -e 'open my $fh, "+<", $ARGV[0] or die "$!\n"; defined($fh->sync) or die "fsync: $!\n";' -- "$path"
}

m003_file_type() {
  [[ -d $1 && ! -L $1 ]] && { printf directory; return; }
  [[ -f $1 && ! -L $1 ]] && { printf regular-file; return; }
  return 1
}

m003_mountinfo_full_identity() {
  local path=$1
  [[ $path == /* && $path != *$'\t'* && $path != *$'\n'* && $path != *$'\r'* && $path != *\\* ]] || return 1
  awk -v target="$path" '
    function decode(value) {
      gsub(/\\040/, " ", value); gsub(/\\011/, "\t", value);
      gsub(/\\012/, "\n", value); gsub(/\\134/, "\\", value); return value
    }
    function covers(mount) {
      return target == mount || (mount == "/" ? substr(target, 1, 1) == "/" : substr(target, 1, length(mount) + 1) == mount "/")
    }
    {
      mount = decode($5); root = decode($4)
      if (covers(mount)) {
        count += 1; ids[count] = $1; parents[count] = $2; devices[count] = $3
        roots[count] = root; mounts[count] = mount
        if (length(mount) > best) best = length(mount)
      }
    }
    END {
      for (i = 1; i <= count; i++) {
        if (length(mounts[i]) != best) continue
        top = 1
        for (j = 1; j <= count; j++) {
          if (length(mounts[j]) == best && parents[j] == ids[i]) { top = 0; break }
        }
        if (top) {
          selected += 1; mount_id = ids[i]; device = devices[i]
          selected_root = roots[i]; selected_mount = mounts[i]
        }
      }
      if (selected == 1) print mount_id "\t" device "\t" selected_root "\t" selected_mount
      else exit 1
    }
  ' /proc/self/mountinfo
}

m003_mountinfo_identity() {
  local mount_id mount_device mount_root mount_point
  IFS=$'\t' read -r mount_id mount_device mount_root mount_point < <(m003_mountinfo_full_identity "$1") || return 1
  [[ $mount_id =~ ^[1-9][0-9]*$ && $mount_device =~ ^[0-9]+:[0-9]+$ && $mount_root == /* && $mount_point == /* ]] || return 1
  printf '%s\t%s\n' "$mount_device" "$mount_root"
}

m003_source_rows() {
  local manifest=$1 class=$2 destination=$3 member file_type dev inode host_mount_device host_mount_root destination_count manifest_count
  [[ -f $manifest && ! -L $manifest ]] || return 1
  : >"$destination" || return 1
  while IFS= read -r member; do
    [[ $member == /nix/store/* && -e $member && ! -L $member ]] || return 1
    file_type=$(m003_file_type "$member") || return 1
    read -r dev inode < <(stat -Lc '%d %i' -- "$member") || return 1
    IFS=$'\t' read -r host_mount_device host_mount_root < <(m003_mountinfo_identity "$member") || return 1
    [[ $host_mount_device =~ ^[0-9]+:[0-9]+$ && $host_mount_root == /* ]] || return 1
    # The parent retains its host provenance.  Inside Bubblewrap, each
    # same-path member bind has a mount root equal to the complete member path.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tro\n' \
      "$member" "$file_type" "$dev" "$inode" "$host_mount_device" "$host_mount_root" \
      "$dev" "$inode" "$host_mount_device" "$member" >>"$destination" || return 1
  done <"$manifest" || return 1
  destination_count=$(wc -l <"$destination" | tr -d ' ') || return 1
  manifest_count=$(wc -l <"$manifest" | tr -d ' ') || return 1
  [[ -s $destination && $destination_count == "$manifest_count" ]]
}

m003_serialize_source_identities() {
  local source_rows=$1 prefix=$2 destination=$3 row_count
  [[ -f $source_rows && ! -L $source_rows && ! -e $destination && ! -L $destination ]] || return 1
  case $prefix in base-source|integration-source) ;; *) return 1;; esac
  if ! awk -v prefix="$prefix" '{printf "%s\t%s\n", prefix, $0}' "$source_rows" >"$destination"; then
    return 1
  fi
  row_count=$(wc -l <"$destination" | tr -d ' ') || return 1
  [[ $row_count =~ ^[1-9][0-9]*$ && $row_count == $(wc -l <"$source_rows" | tr -d ' ') ]]
}

m003_close_authority_fds() {
  local root fd
  for root in "${!m003_frozen_parent_fd[@]}"; do
    fd=${m003_frozen_parent_fd["$root"]}
    [[ -z $fd ]] || eval "exec ${fd}<&-" || return 1
  done
  m003_frozen_parent_fd=()
}

m003_openat2_current_identity() {
  local parent_fd=$1 leaf=$2 expected_path=$3
  [[ $parent_fd =~ ^[0-9]+$ && -n $leaf && $leaf != /* && $expected_path == /* ]] || return 1
  perl -MFcntl=:DEFAULT -e '
    use strict; use warnings;
    my ($parent_fd, $leaf, $expected_path) = @ARGV;
    $parent_fd =~ /\A[0-9]+\z/ or die "invalid parent descriptor\n";
    $leaf =~ /\A[^\x00]+\z/ && $leaf !~ m{\A/|//|(?:\A|/)\.\.?(/|\z)} or die "unsafe authority leaf\n";
    # Linux x86-64 raw-39 platform: openat2(2) is syscall 437. open_how is
    # three little-endian u64 values: flags, mode, and resolve. The resolve
    # mask combines NO_XDEV, NO_MAGICLINKS, NO_SYMLINKS, and BENEATH.
    use constant O_CLOEXEC_LINUX => 02000000;
    my $how = pack(q{Q<Q<Q<}, O_RDONLY | O_CLOEXEC_LINUX | O_NOFOLLOW, 0, 0x0f);
    my $fd = syscall(437, 0 + $parent_fd, $leaf, $how, length($how));
    $fd >= 0 or die "openat2 authority leaf: $!\n";
    open(my $handle, q{<&=}, $fd) or die "fdopen authority leaf: $!\n";
    my $resolved = readlink(q{/proc/self/fd/} . $fd);
    defined($resolved) && $resolved eq $expected_path or die "authority leaf path changed\n";
    my @s = stat($handle); @s or die "fstat authority leaf: $!\n";
    my $kind = (($s[2] & 0170000) == 0040000) ? q{directory}
      : (($s[2] & 0170000) == 0100000) ? q{regular-file} : q{unsupported};
    printf "%s|%s|%s|%s|%s|%04o\n", $kind, @s[0, 1, 4, 5], ($s[2] & 07777);
  ' -- "$parent_fd" "$leaf" "$expected_path"
}

m003_revalidate_frozen_parent() {
  local root=$1 canonical current_identity fd descriptor_identity uid gid mode
  local mount_id mount_device mount_root mount_point
  [[ -n ${m003_frozen_parent_fd["$root"]+x} && -d $root && ! -L $root ]] || return 1
  canonical=$(realpath -e -- "$root") || return 1
  [[ $canonical == "$root" ]] || return 1
  current_identity=$(stat -c '%d:%i' -- "$root") || return 1
  uid=$(stat -c '%u' -- "$root") || return 1
  gid=$(stat -c '%g' -- "$root") || return 1
  mode=$(stat -c '%a' -- "$root") || return 1
  [[ $current_identity == "${m003_frozen_parent_identity["$root"]}" &&
      $uid == "${m003_frozen_parent_uid["$root"]}" &&
      $gid == "${m003_frozen_parent_gid["$root"]}" &&
      $mode == "${m003_frozen_parent_mode["$root"]}" ]] || return 1
  fd=${m003_frozen_parent_fd["$root"]}
  descriptor_identity=$(stat -Lc '%d:%i' -- "/proc/self/fd/$fd") || return 1
  [[ $descriptor_identity == "${m003_frozen_parent_identity["$root"]}" ]] || return 1
  IFS=$'\t' read -r mount_id mount_device mount_root mount_point < <(m003_mountinfo_full_identity "$root") || return 1
  [[ $mount_id == "${m003_frozen_parent_mount_id["$root"]}" &&
      $mount_device == "${m003_frozen_parent_mount_device["$root"]}" &&
      $mount_root == "${m003_frozen_parent_mount_root["$root"]}" &&
      $mount_point == "${m003_frozen_parent_mount_point["$root"]}" ]] || return 1
}

m003_validate_current_authority() {
  local ordinal=$1 session_id=$2 authority_id=$3 key root leaf current identity kind dev inode uid gid mode
  local component component_path mount_id mount_device mount_root mount_point
  local -a m003_leaf_components=()
  key=$ordinal:$authority_id
  [[ -n ${m003_authority_ids["$key"]+x} && ${m003_authority_session["$key"]} == "$session_id" ]] || return 1
  root=${m003_authority_root["$key"]}; leaf=${m003_authority_leaf["$key"]}; current=${m003_current_path["$key"]}
  [[ $current == "$root/$leaf" && $current == "$root"/* ]] || return 1
  m003_revalidate_frozen_parent "$root" || return 1
  identity=$(m003_openat2_current_identity "${m003_frozen_parent_fd["$root"]}" "$leaf" "$current") || return 1
  IFS='|' read -r kind dev inode uid gid mode <<<"$identity"
  [[ $kind == directory || $kind == regular-file ]] || return 1
  [[ $dev == "${m003_frozen_parent_identity["$root"]%%:*}" ]] || return 1
  component_path=$root
  IFS='/' read -r -a m003_leaf_components <<<"$leaf"
  for component in "${m003_leaf_components[@]}"; do
    [[ -n $component && $component != . && $component != .. ]] || return 1
    component_path+=/$component
    IFS=$'\t' read -r mount_id mount_device mount_root mount_point < <(m003_mountinfo_full_identity "$component_path") || return 1
    [[ $mount_id == "${m003_frozen_parent_mount_id["$root"]}" &&
        $mount_device == "${m003_frozen_parent_mount_device["$root"]}" &&
        $mount_root == "${m003_frozen_parent_mount_root["$root"]}" &&
        $mount_point == "${m003_frozen_parent_mount_point["$root"]}" ]] || return 1
  done
  if [[ -n ${m003_current_frozen_identity["$key"]} ]]; then
    [[ $identity == "${m003_current_frozen_identity["$key"]}" ]] || return 1
  else
    [[ $kind == directory && $uid == "${m003_frozen_parent_uid["$root"]}" &&
        $gid == "${m003_frozen_parent_gid["$root"]}" && $mode == 0700 ]] || return 1
  fi
  if [[ $authority_id == xdg-runtime ]]; then
    [[ $kind == directory && $mode == 0700 && -z $(find -P "$current" -mindepth 1 -maxdepth 1 -print -quit) ]] || return 1
  fi
}

m003_validate_ephemeral_lifecycle() {
  local ordinal=$1 other authority_id key path
  for other in {1..7}; do
    for authority_id in closure-staging session-root session-contract-root xdg-runtime; do
      key=$other:$authority_id
      [[ -n ${m003_current_path["$key"]+x} ]] || continue
      path=${m003_current_path["$key"]}
      if (( other == ordinal )); then
        [[ -e $path && ! -L $path ]] || return 1
      else
        [[ ! -e $path && ! -L $path ]] || return 1
      fi
    done
  done
}

m003_uint64_product() {
  perl -MMath::BigInt -e '
    my ($left, $right) = @ARGV;
    $left =~ /\A(?:0|[1-9][0-9]*)\z/ && $right =~ /\A(?:0|[1-9][0-9]*)\z/ or exit 1;
    my $maximum = Math::BigInt->new(q{18446744073709551615});
    my $left_value = Math::BigInt->new($left); my $right_value = Math::BigInt->new($right);
    $left_value <= $maximum && $right_value <= $maximum or exit 1;
    my $value = $left_value->copy()->bmul($right_value);
    $value <= $maximum or exit 1;
    print $value->bstr(), "\n";
  ' -- "$1" "$2"
}

m003_add_authority() {
  local ordinal=$1 session_id=$2 authority_id=$3 kind=$4 root=$5 leaf=$6 type dev inode uid gid mode mount_id mount_device mount_root mount_point
  local canonical key fd current_identity
  [[ $root == /* && $root != *$'\t'* && $root != *$'\n'* && $root != *$'\r'* && $root != *\\* &&
      -n $leaf && $leaf != /* && $leaf != *$'\t'* && $leaf != *$'\n'* && $leaf != *$'\r'* && $leaf != *\\* &&
      $leaf != *//* && $leaf != . && $leaf != .. && $leaf != ../* && $leaf != */../* && $leaf != */.. ]] || return 1
  [[ -d $root && ! -L $root ]] || return 1
  canonical=$(realpath -e -- "$root") || return 1
  [[ $canonical == "$root" ]] || return 1
  type=$(m003_file_type "$root") || return 1
  [[ $type == directory ]] || return 1
  read -r dev inode uid gid mode < <(stat -c '%d %i %u %g %a' -- "$root") || return 1
  IFS=$'\t' read -r mount_id mount_device mount_root mount_point < <(m003_mountinfo_full_identity "$root") || return 1
  [[ $mode =~ ^[0-7]{3,4}$ && $mount_id =~ ^[1-9][0-9]*$ && $mount_device =~ ^[0-9]+:[0-9]+$ && $mount_root == /* && $mount_point == /* ]] || return 1
  if [[ -z ${m003_frozen_parent_fd["$root"]+x} ]]; then
    exec {fd}<"$root" || return 1
    [[ $(stat -Lc '%d:%i' -- "/proc/self/fd/$fd") == "$dev:$inode" ]] || { eval "exec ${fd}<&-"; return 1; }
    m003_frozen_parent_fd["$root"]=$fd
    m003_frozen_parent_identity["$root"]=$dev:$inode
    m003_frozen_parent_uid["$root"]=$uid
    m003_frozen_parent_gid["$root"]=$gid
    m003_frozen_parent_mode["$root"]=$mode
    m003_frozen_parent_mount_id["$root"]=$mount_id
    m003_frozen_parent_mount_device["$root"]=$mount_device
    m003_frozen_parent_mount_root["$root"]=$mount_root
    m003_frozen_parent_mount_point["$root"]=$mount_point
  else
    m003_revalidate_frozen_parent "$root" || return 1
  fi
  fd=${m003_frozen_parent_fd["$root"]}
  key=$ordinal:$authority_id
  [[ -z ${m003_authority_ids["$key"]+x} ]] || return 1
  printf 'capacity-authority\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t0%s\tdirectory\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ordinal" "$session_id" "$authority_id" "$kind" "$root" "$uid" "$gid" "$mode" "$dev" "$inode" "$mount_device" "$mount_root" "$root" "$leaf" >>"$m003_authorities"
  m003_current_path["$key"]="$root/$leaf"
  m003_authority_ids["$key"]=1
  m003_authority_root["$key"]=$root
  m003_authority_leaf["$key"]=$leaf
  m003_authority_session["$key"]=$session_id
  m003_authority_kind["$key"]=$kind
  case $authority_id in
    closure-staging|session-root|session-contract-root|xdg-runtime|closure-store-base)
      [[ ! -e ${m003_current_path["$key"]} && ! -L ${m003_current_path["$key"]} ]] || return 1
      m003_current_frozen_identity["$key"]=
      ;;
    *)
      current_identity=$(m003_openat2_current_identity "$fd" "$leaf" "${m003_current_path["$key"]}") || return 1
      m003_current_frozen_identity["$key"]=$current_identity
      ;;
  esac
  m003_capacity_devices["$dev"]=1
  m003_capacity_device_path["$dev"]=$root
}

m003_plan_authorities() {
  local ordinal session_id session_leaf stage_leaf contract_leaf runtime_leaf
  local script_parent script_leaf source_parent source_leaf
  mkdir -p "$candidate_root/sessions" "$m003_runner_temp_root/burlmd-m003/staging" \
    "$m003_runner_temp_root/burlmd-m003/contracts" "$m003_runner_temp_root/burlmd-m003/xdg-runtime"
  chmod 700 "$candidate_root/sessions" "$m003_runner_temp_root/burlmd-m003/staging" \
    "$m003_runner_temp_root/burlmd-m003/contracts" "$m003_runner_temp_root/burlmd-m003/xdg-runtime"
  m003_authorities=$m003_runner_temp_root/burlmd-m003/capacity-authorities.tsv
  : >"$m003_authorities"
  m003_close_authority_fds || return 1
  m003_current_path=(); m003_authority_ids=(); m003_capacity_devices=(); m003_capacity_device_path=()
  m003_authority_root=(); m003_authority_leaf=(); m003_authority_session=(); m003_authority_kind=()
  m003_current_frozen_identity=()
  m003_frozen_parent_identity=(); m003_frozen_parent_uid=(); m003_frozen_parent_gid=(); m003_frozen_parent_mode=()
  m003_frozen_parent_mount_id=(); m003_frozen_parent_mount_device=(); m003_frozen_parent_mount_root=(); m003_frozen_parent_mount_point=()
  script_parent=$(dirname -- "$script_root"); script_leaf=$(basename -- "$script_root")
  source_parent=$(dirname -- "$source_root"); source_leaf=$(basename -- "$source_root")
  for ordinal in {1..7}; do
    case $ordinal in
      1) session_id=generated-bindings;; 2) session_id=flutter-test;; 3) session_id=dart-analyze;; 4) session_id=cargo-metadata;;
      5) session_id=integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d;;
      6) session_id=integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d;;
      7) session_id=managed-isolation;;
    esac
    session_leaf=$ordinal-$session_id
    stage_leaf=burlmd-m003/staging/$session_leaf
    contract_leaf=burlmd-m003/contracts/$session_leaf
    runtime_leaf=burlmd-m003/xdg-runtime/$session_leaf
    m003_add_authority "$ordinal" "$session_id" closure-staging staging-leaf "$m003_runner_temp_root" "$stage_leaf" || return 1
    m003_add_authority "$ordinal" "$session_id" candidate-home argv-source "$candidate_root" home || return 1
    m003_add_authority "$ordinal" "$session_id" candidate-tmp argv-source "$candidate_root" tmp || return 1
    m003_add_authority "$ordinal" "$session_id" xdg-cache argv-source "$candidate_root/xdg" cache || return 1
    m003_add_authority "$ordinal" "$session_id" xdg-config argv-source "$candidate_root/xdg" config || return 1
    m003_add_authority "$ordinal" "$session_id" xdg-data argv-source "$candidate_root/xdg" data || return 1
    m003_add_authority "$ordinal" "$session_id" xdg-state argv-source "$candidate_root/xdg" state || return 1
    m003_add_authority "$ordinal" "$session_id" gh-config argv-source "$candidate_root" gh || return 1
    m003_add_authority "$ordinal" "$session_id" candidate-tool-path argv-source "$candidate_root" tool-path || return 1
    m003_add_authority "$ordinal" "$session_id" candidate-writable argv-source "$candidate_root" writable || return 1
    m003_add_authority "$ordinal" "$session_id" session-root argv-source "$candidate_root/sessions" "$session_leaf" || return 1
    m003_add_authority "$ordinal" "$session_id" session-contract-root argv-source "$m003_runner_temp_root" "$contract_leaf" || return 1
    if (( ordinal == 5 || ordinal == 6 )); then m003_add_authority "$ordinal" "$session_id" xdg-runtime runtime-leaf "$m003_runner_temp_root" "$runtime_leaf" || return 1; fi
    m003_add_authority "$ordinal" "$session_id" prepared-root argv-source "$candidate_root" prepared || return 1
    m003_add_authority "$ordinal" "$session_id" trusted-control-root argv-source "$script_parent" "$script_leaf" || return 1
    m003_add_authority "$ordinal" "$session_id" tested-source-root argv-source "$source_parent" "$source_leaf" || return 1
    m003_add_authority "$ordinal" "$session_id" dart-tool argv-source "$candidate_root/writable" dart-tool || return 1
    m003_add_authority "$ordinal" "$session_id" flutter-build argv-source "$candidate_root/writable" build || return 1
    m003_add_authority "$ordinal" "$session_id" l10n-generated argv-source "$candidate_root/writable" l10n-generated || return 1
    m003_add_authority "$ordinal" "$session_id" cargokit-root argv-source "$candidate_root/writable" rust-builder-cargokit || return 1
    m003_add_authority "$ordinal" "$session_id" cargokit-launcher argv-source "$candidate_root/writable/rust-builder-cargokit" run_build_tool.sh || return 1
    m003_add_authority "$ordinal" "$session_id" linux-flutter-ephemeral argv-source "$candidate_root/writable" linux-flutter-ephemeral || return 1
    m003_add_authority "$ordinal" "$session_id" pub-active-roots argv-source "$candidate_root/writable" pub-active-roots || return 1
    m003_add_authority "$ordinal" "$session_id" closure-store-base argv-source "$m003_runner_temp_root" "$stage_leaf/nix/store" || return 1
  done
  m003_authority_count=$(wc -l <"$m003_authorities" | tr -d ' ')
  m003_authority_sha=$(sha256sum "$m003_authorities" | awk '{print $1}')
  m003_capacity_root_count=${#m003_capacity_devices[@]}
  (( m003_authority_count > 0 && m003_capacity_root_count > 0 )) || return 1
  [[ $m003_authority_sha =~ ^[0-9a-f]{64}$ ]]
}

m003_prepare_closure_log() {
  [[ $ticket == BURL-M003 && $role == linux-x86_64 && -n $m003_runner_temp_root ]] || return 1
  mkdir -p "$output_root/logs" || return 1
  m003_log=$output_root/logs/burl-m003-linux-closure-view.log
  [[ ! -e $m003_log && ! -L $m003_log ]] || return 1
  m003_plan_authorities || return 1
  m003_base_sources=$m003_runner_temp_root/burlmd-m003/base-sources.tsv
  m003_integration_sources=$m003_runner_temp_root/burlmd-m003/integration-sources.tsv
  m003_base_source_identities=$m003_runner_temp_root/burlmd-m003/base-source-identities.tsv
  m003_integration_source_identities=$m003_runner_temp_root/burlmd-m003/integration-source-identities.tsv
  m003_source_rows "$candidate_linux_base_manifest" base "$m003_base_sources" || return 1
  m003_source_rows "$candidate_linux_integration_manifest" integration "$m003_integration_sources" || return 1
  m003_base_source_count=$(wc -l <"$m003_base_sources" | tr -d ' ')
  m003_integration_source_count=$(wc -l <"$m003_integration_sources" | tr -d ' ')
  [[ $m003_base_source_count == 488 && $m003_integration_source_count == 547 ]] || return 1
  m003_serialize_source_identities "$m003_base_sources" base-source "$m003_base_source_identities" || return 1
  m003_serialize_source_identities "$m003_integration_sources" integration-source "$m003_integration_source_identities" || return 1
  m003_base_source_sha=$(sha256sum "$m003_base_source_identities" | awk '{print $1}') || return 1
  m003_integration_source_sha=$(sha256sum "$m003_integration_source_identities" | awk '{print $1}') || return 1
  [[ $m003_base_source_sha =~ ^[0-9a-f]{64}$ && $m003_integration_source_sha =~ ^[0-9a-f]{64}$ ]] || return 1
  {
    printf '%s\n' \
      'format=burlmd-linux-closure-view-v2' 'raw-contract-version=39' \
      'bubblewrap-path=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap' \
      'bubblewrap-version=bubblewrap 0.11.2' \
      'bubblewrap-sha256=c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726' \
      'bubblewrap-tool-closure-manifest-sha256=398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd' \
      "teardown-lock-verifier-path=$m003_flock_path" \
      "teardown-lock-verifier-version=$m003_flock_version" \
      "teardown-lock-verifier-sha256=$m003_flock_sha" \
      'base-manifest-bytes=30717' 'base-manifest-sha256=127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64' \
      'base-member-count=488' 'base-nar-bytes=6184635112' 'base-bind-bytes=66314' \
      'integration-manifest-bytes=34315' 'integration-manifest-sha256=353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896' \
      'integration-member-count=547' 'integration-nar-bytes=6338147240' 'integration-bind-bytes=74100' \
      "sway-path=$m003_sway_path" "sway-version=$m003_sway_version" \
      "sway-sha256=$m003_sway_sha" \
      "swaymsg-path=$m003_swaymsg_path" "swaymsg-version=$m003_swaymsg_version" \
      "swaymsg-sha256=$m003_swaymsg_sha" \
      'compositor-closure-sha256=d97a41799b1aecc670e31bfd58b339d748498be2bce09d877a0f1a9ed1c6e673' \
      'wayland-socket-basename=wayland-1' 'config-sha256=dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a' \
      "base-source-identity-count=$m003_base_source_count" "base-source-identity-sha256=$m003_base_source_sha" \
      "integration-source-identity-count=$m003_integration_source_count" "integration-source-identity-sha256=$m003_integration_source_sha" \
      "capacity-root-count=$m003_capacity_root_count" "capacity-authority-count=$m003_authority_count" "capacity-authority-sha256=$m003_authority_sha" \
      "capacity-filesystem-count=$m003_capacity_root_count" 'base-session-count=5' 'integration-session-count=2' 'session-count=7'
    cat "$m003_base_source_identities" || return 1
    cat "$m003_integration_source_identities" || return 1
    cat "$m003_authorities" || return 1
  } >"$m003_log" || return 1
  m003_fsync_file "$m003_log" || return 1
}

m003_selected_source_file() {
  case $1 in base) printf '%s' "$m003_base_sources";; integration) printf '%s' "$m003_integration_sources";; *) return 1;; esac
}

m003_expected_preflight_body() {
  local session_class=$1 manifest_sha=$2 source_file=$3 source_count=$4 compositor_state
  [[ $session_class == base ]] && compositor_state=absent || compositor_state=pending-supervisor-start
  {
    printf '%s\n' 'format=burlmd-linux-closure-preflight-v2' "session-class=$session_class" "selected-manifest-sha256=$manifest_sha" "source-identity-count=$source_count"
    cat "$source_file"
    printf '%s\n' 'pid-namespace-private=true' 'network-namespace-private=true' \
      'descriptor=0:candidate-stdin' 'descriptor=1:candidate-stdout' 'descriptor=2:candidate-stderr' \
      'descriptor=3:preflight-record-write' 'descriptor=4:preflight-ack-read' \
      'store-view-exact=true' 'forbidden-paths-absent=true' "compositor-state=$compositor_state"
  }
}

m003_validate_preflight() {
  local fd=$1 expected_body=$2 header byte_count body extra
  IFS= read -r header <&"$fd" || return 1
  [[ $header =~ ^preflight-bytes=([1-9][0-9]*)$ ]] || return 1
  byte_count=${BASH_REMATCH[1]}
  [[ $byte_count == $(printf '%s' "$expected_body" | wc -c | tr -d ' ') ]] || return 1
  IFS= read -r -N "$byte_count" body <&"$fd" || return 1
  [[ $body == "$expected_body" ]] || return 1
  if IFS= read -r -n 1 extra <&"$fd"; then return 1; fi
}

m003_validate_cleanup_frame() {
  local frame=$1 expected_session=$2 line
  [[ -f $frame && ! -L $frame && $(stat -Lc '%a' -- "$frame") == 600 && $(tail -c 1 "$frame" | od -An -t x1) == *0a* ]] || return 1
  mapfile -t m003_cleanup_lines <"$frame"
  (( ${#m003_cleanup_lines[@]} == 7 )) || return 1
  [[ ${m003_cleanup_lines[0]} == "session-id=$expected_session" ]] || return 1
  [[ ${m003_cleanup_lines[1]} =~ ^supervisor-result=(success|candidate-failed|timeout|sway-failed|socket-disrupted|interrupted|cleanup-failed)$ ]] || return 1
  [[ ${m003_cleanup_lines[2]} =~ ^sway-pid=[1-9][0-9]*$ ]] || return 1
  [[ ${m003_cleanup_lines[3]} =~ ^termination-path=[a-z0-9-]+$ ]] || return 1
  [[ ${m003_cleanup_lines[4]} =~ ^wait-status=(0|[1-9][0-9]*)$ && ${m003_cleanup_lines[5]} == sway-reaped=true && ${m003_cleanup_lines[6]} == cleanup-complete=true ]] || return 1
  m003_cleanup_result=${m003_cleanup_lines[1]#supervisor-result=}
  m003_cleanup_wait_status=${m003_cleanup_lines[4]#wait-status=}
}

m003_descriptor_identity() {
  local fd=$1 file_type dev inode target flags
  [[ $fd =~ ^[0-9]+$ && -e /proc/self/fd/$fd ]] || return 1
  IFS='|' read -r file_type dev inode < <(stat -Lc '%F|%d|%i' -- "/proc/self/fd/$fd") || return 1
  target=$(readlink -- "/proc/self/fd/$fd") || return 1
  flags=$(awk '/^flags:/{print $2; exit}' "/proc/self/fdinfo/$fd") || return 1
  [[ -n $file_type && $dev =~ ^[0-9]+$ && $inode =~ ^[0-9]+$ && -n $target && $flags =~ ^0[0-7]+$ ]] || return 1
  printf '%s|%s|%s|%s|%s' "$file_type" "$dev" "$inode" "$target" "$flags"
}

m003_open_standard_streams() {
  local stdin_path=$1 stdout_path=$2 stderr_path=$3
  : >"$stdin_path"; : >"$stdout_path"; : >"$stderr_path" || return 1
  chmod 600 "$stdin_path" "$stdout_path" "$stderr_path" || return 1
  exec {m003_stdin_fd}<"$stdin_path"
  exec {m003_stdout_fd}>"$stdout_path"
  exec {m003_stderr_fd}>"$stderr_path"
  m003_standard_stream_identity[0]=$(m003_descriptor_identity "$m003_stdin_fd") || return 1
  m003_standard_stream_identity[1]=$(m003_descriptor_identity "$m003_stdout_fd") || return 1
  m003_standard_stream_identity[2]=$(m003_descriptor_identity "$m003_stderr_fd") || return 1
}

m003_open_verified_session_directory() {
  local path=$1 expected_identity actual_identity
  [[ -d $path && ! -L $path ]] || return 1
  expected_identity=$(stat -Lc '%d:%i:%u:%g' -- "$path") || return 1
  perl -MFcntl=:DEFAULT -e '
    my ($path, $expected) = @ARGV;
    use constant O_CLOEXEC_LINUX => 02000000;
    sysopen(my $dir, $path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC_LINUX) or die "open session directory: $!\n";
    my @s = stat($dir); join(q{:}, @s[0, 1, 4, 5]) eq $expected or die "session directory identity changed\n";
  ' -- "$path" "$expected_identity" || return 1
  exec {session_fd}<"$path"
  actual_identity=$(stat -Lc '%d:%i:%u:%g' -- "/proc/self/fd/$session_fd") || return 1
  [[ $actual_identity == "$expected_identity" ]]
}

m003_close_standard_streams() {
  local fd
  for fd in "${m003_stdin_fd:-}" "${m003_stdout_fd:-}" "${m003_stderr_fd:-}"; do
    [[ -z $fd ]] || eval "exec ${fd}>&-" || return 1
  done
  m003_stdin_fd= m003_stdout_fd= m003_stderr_fd=
}

m003_write_cleanup_ack() {
  local session_fd=$1
  perl -MFcntl=:DEFAULT -MIO::Handle -e '
    my ($fd) = @ARGV; my $directory = q{/proc/self/fd/} . $fd;
    sysopen(my $dir, $directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) or die "open session: $!\n";
    my $path = q{/proc/self/fd/} . fileno($dir) . q{/cleanup.ack};
    sysopen(my $out, $path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "open cleanup ack: $!\n";
    binmode($out); print {$out} "K\n" or die "write cleanup ack: $!\n"; defined($out->sync) or die "fsync cleanup ack: $!\n";
  ' -- "$session_fd"
}

m003_make_staging_leaf() {
  local ordinal=$1 session_id=$2 manifest=$3 stage_path=$4 member placeholder file_type
  stage_path=${m003_current_path["$ordinal:closure-staging"]}
  [[ ! -e $stage_path && ! -L $stage_path ]] || return 1
  mkdir -p "$stage_path/nix/store" || return 1
  chmod 700 "$stage_path" "$stage_path/nix" "$stage_path/nix/store" || return 1
  # Placeholders establish the declared staging inventory without copying any
  # host-store byte.  Every actual member remains a same-path read-only bind.
  while IFS= read -r member; do
    placeholder=$stage_path/nix/store/${member#/nix/store/}
    [[ ! -e $placeholder && ! -L $placeholder ]] || return 1
    file_type=$(m003_file_type "$member") || return 1
    case $file_type in
      directory) mkdir "$placeholder" || return 1 ;;
      regular-file) : >"$placeholder" || return 1 ;;
      *) return 1 ;;
    esac
  done <"$manifest"
  [[ $(find -P "$stage_path/nix/store" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') == $(wc -l <"$manifest" | tr -d ' ') ]]
}

m003_make_contract_leaf() {
  local ordinal=$1 source_file=$2 leaf=$3 snapshot
  leaf=${m003_current_path["$ordinal:session-contract-root"]}
  [[ ! -e $leaf && ! -L $leaf ]] || return 1
  mkdir "$leaf" || return 1
  chmod 700 "$leaf" || return 1
  snapshot=$leaf/locked-nix-closure.sources
  cp -- "$source_file" "$snapshot" || return 1
  chmod 444 "$snapshot" || return 1
  [[ $(find -P "$leaf" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') == 1 && -f $snapshot && ! -L $snapshot && ! -w $snapshot ]]
}

m003_make_runtime_leaf() {
  local ordinal=$1 leaf
  leaf=${m003_current_path["$ordinal:xdg-runtime"]}
  [[ ! -e $leaf && ! -L $leaf ]] || return 1
  mkdir "$leaf" && chmod 700 "$leaf" || return 1
  [[ -d $leaf && ! -L $leaf && -z $(find -P "$leaf" -mindepth 1 -maxdepth 1 -print -quit) ]]
}

m003_build_candidate_environment() {
  local session_id=$1 class=$2 manifest=$3 members
  local -n destination=$4
  members=$(IFS=:; printf '%s' "${candidate_linux_closure_paths[*]}")
  destination=(
    'PATH=/candidate/tool-path' 'HOME=/candidate/home' 'TMPDIR=/candidate/tmp'
    'XDG_CACHE_HOME=/candidate/xdg/cache' 'XDG_CONFIG_HOME=/candidate/xdg/config'
    'XDG_DATA_HOME=/candidate/xdg/data' 'XDG_STATE_HOME=/candidate/xdg/state'
    'GH_CONFIG_DIR=/candidate/gh' 'PUB_CACHE=/candidate/prepared/pub-cache'
    'CARGO_HOME=/candidate/prepared/cargo-home' 'CARGO_TARGET_DIR=/candidate/writable/cargo-target'
    'RUSTUP_HOME=/candidate/home/rustup' 'GIT_CONFIG_NOSYSTEM=1' 'GIT_CONFIG_GLOBAL=/dev/null'
    'GIT_CONFIG_COUNT=0' 'GIT_TERMINAL_PROMPT=0' 'LC_ALL=C.UTF-8' 'LANG=C.UTF-8'
    'BURLMD_CANDIDATE_LOOPBACK=1' 'NIX_REMOTE=local' 'NIX_PATH=' 'NIX_CONFIG=sandbox = false'
    "BURLMD_CANDIDATE_SESSION=$session_id" 'BURLMD_CANDIDATE_PID_FILE=/candidate/session/pid'
    "BURLMD_LOCKED_NIX_CLOSURE=$members" "PKG_CONFIG_PATH=$candidate_linux_openssl_pkgconfig"
    "LIBCLANG_PATH=${LIBCLANG_PATH:?locked LIBCLANG_PATH is required}" "NIX_CFLAGS_COMPILE=-isystem $candidate_linux_openssl_include"
    "NIX_LDFLAGS_x86_64_unknown_linux_gnu=-L$candidate_linux_openssl_lib" "CFLAGS=-isystem $candidate_linux_openssl_include"
    "LDFLAGS=-L$candidate_linux_openssl_lib" "LIBGL_DRIVERS_PATH=$candidate_linux_mesa_dri"
    "__EGL_VENDOR_LIBRARY_FILENAMES=$candidate_linux_mesa_egl"
  )
  [[ ${#destination[@]} == 33 ]] || return 1
  [[ $class == base || $class == integration ]] || return 1
}

m003_build_argv() {
  local ordinal=$1 session_id=$2 class=$3; shift 3
  local manifest source_id operation destination entry key value
  local -n destination_argv=$1
  local -a environment=()
  shift
  if [[ $class == base ]]; then
    manifest=$candidate_linux_base_manifest; source_id=$m003_base_sources
    candidate_linux_closure_paths=("${candidate_linux_base_closure_paths[@]}")
  else
    manifest=$candidate_linux_integration_manifest; source_id=$m003_integration_sources
    candidate_linux_closure_paths=("${candidate_linux_integration_closure_paths[@]}")
  fi
  m003_build_candidate_environment "$session_id" "$class" "$manifest" environment || return 1
  destination_argv=(/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap
    --unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv)
  for entry in "${environment[@]}"; do key=${entry%%=*}; value=${entry#*=}; destination_argv+=(--setenv "$key" "$value"); done
  destination_argv+=(--lock-file /candidate/session/namespace-teardown.lock
    --proc /proc --dev /dev --tmpfs /tmp --dir /source --dir /candidate --dir /candidate/xdg --dir /candidate/writable
    --dir /candidate/xdg/cache --dir /candidate/xdg/config --dir /candidate/xdg/data --dir /candidate/xdg/state
    --dir /candidate/prepared --dir /contract --dir /trusted --dir /usr --dir /usr/bin)
  local -a dynamic_mounts=(
    'bind:candidate-home:/candidate/home' 'bind:candidate-tmp:/candidate/tmp' 'bind:xdg-cache:/candidate/xdg/cache'
    'bind:xdg-config:/candidate/xdg/config' 'bind:xdg-data:/candidate/xdg/data' 'bind:xdg-state:/candidate/xdg/state'
    'bind:gh-config:/candidate/gh' 'ro-bind:candidate-tool-path:/candidate/tool-path' 'bind:candidate-writable:/candidate/writable'
    'bind:session-root:/candidate/session' 'ro-bind:session-contract-root:/contract' 'ro-bind:prepared-root:/candidate/prepared'
    'ro-bind:trusted-control-root:/trusted' 'ro-bind:tested-source-root:/source' 'bind:dart-tool:/source/.dart_tool'
    'bind:flutter-build:/source/build' 'bind:l10n-generated:/source/lib/l10n/generated' 'ro-bind:cargokit-root:/source/rust_builder/cargokit'
    'bind:cargokit-launcher:/source/rust_builder/cargokit/run_build_tool.sh' 'bind:linux-flutter-ephemeral:/source/linux/flutter/ephemeral'
    'bind:pub-active-roots:/candidate/prepared/pub-cache/active_roots' 'ro-bind:closure-store-base:/nix/store'
  )
  for entry in "${dynamic_mounts[@]}"; do
    IFS=: read -r operation source_id destination <<<"$entry"
    [[ -n ${m003_current_path["$ordinal:$source_id"]+x} ]] || return 1
    destination_argv+=(--"$operation" "${m003_current_path["$ordinal:$source_id"]}" "$destination")
    if [[ $class == integration && $source_id == session-contract-root ]]; then destination_argv+=(--bind "${m003_current_path["$ordinal:xdg-runtime"]}" /candidate/xdg/runtime); fi
  done
  while IFS= read -r entry; do destination_argv+=(--ro-bind "$entry" "$entry"); done <"$manifest"
  destination_argv+=(--symlink /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env /usr/bin/env)
  [[ $class != integration ]] || destination_argv+=(--symlink /nix/store/zh1ijdhb6gng1509b1zrilb6xlzx60j6-bash-5.3p9/bin/bash /bin/sh)
  destination_argv+=(--chdir /source --
    /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash -c 'source "$1"; shift; main "$@"' _ /trusted/scripts/supervise-linux-session.sh
    --session-id "$session_id" --class "$class" --preflight-fd 3 --ack-fd 4 --timeout-seconds 7200 --)
  destination_argv+=("$@")
}

m003_append_session_record() {
  local ordinal=$1 session_id=$2 class=$3 manifest=$4 source_sha=$5 argv_bytes=$6 argv_sha=$7 stage_path=$8 supervisor_result=$9 sway_reaped=${10} cleanup_complete=${11} capacity_rows=${12} lock_identity=${13}
  local lock_dev lock_inode
  [[ $stage_path == "${m003_current_path["$ordinal:closure-staging"]}" ]] || return 1
  [[ $lock_identity =~ ^[1-9][0-9]*:[1-9][0-9]*$ ]] || return 1
  lock_dev=${lock_identity%%:*}; lock_inode=${lock_identity#*:}
  printf 'session\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t0\t0\t%s\t%s\t%s\ttrue\ttrue\t%s\t%s\t%s\t%s\t%s\ttrue\ttrue\n' \
    "$ordinal" "$session_id" "$class" "$manifest" "$source_sha" "$m003_authority_sha" \
    "$(printf '%s\n' "$stage_path" | sha256sum | awk '{print $1}')" "$argv_bytes" "$argv_sha" \
    "$(wc -l < <(if [[ $class == base ]]; then cat "$candidate_linux_base_manifest"; else cat "$candidate_linux_integration_manifest"; fi) | tr -d ' ')" \
    "$(getconf ARG_MAX)" "$m003_preflight_bytes" "$m003_preflight_sha" "$supervisor_result" "$sway_reaped" "$cleanup_complete" \
    "$lock_dev" "$lock_inode" >>"$m003_log"
  [[ -s $capacity_rows ]] || return 1
  cat "$capacity_rows" >>"$m003_log"
  m003_fsync_file "$m003_log"
}

m003_capture_session_capacity_rows() {
  local ordinal=$1 session_id=$2 class=$3 destination=$4 current_id device available capacity_path blocks fragment_size root
  : >"$destination"
  for root in "${!m003_frozen_parent_fd[@]}"; do
    m003_revalidate_frozen_parent "$root" || return 1
  done
  m003_validate_ephemeral_lifecycle "$ordinal" || return 1
  for current_id in closure-staging candidate-home candidate-tmp xdg-cache xdg-config xdg-data xdg-state gh-config candidate-tool-path candidate-writable session-root session-contract-root prepared-root trusted-control-root tested-source-root dart-tool flutter-build l10n-generated cargokit-root cargokit-launcher linux-flutter-ephemeral pub-active-roots closure-store-base; do
    m003_validate_current_authority "$ordinal" "$session_id" "$current_id" || return 1
    device=$(stat -c '%d' -- "${m003_current_path["$ordinal:$current_id"]}") || return 1
    printf 'session-capacity-root\t%s\t%s\t%s\t%s\t%s\n' "$ordinal" "$session_id" "$current_id" "${m003_current_path["$ordinal:$current_id"]}" "$device" >>"$destination"
  done
  if [[ $class == integration ]]; then
    m003_validate_current_authority "$ordinal" "$session_id" xdg-runtime || return 1
    printf 'session-capacity-root\t%s\t%s\txdg-runtime\t%s\t%s\n' "$ordinal" "$session_id" "${m003_current_path["$ordinal:xdg-runtime"]}" "$(stat -c '%d' -- "${m003_current_path["$ordinal:xdg-runtime"]}")" >>"$destination"
  fi
  for device in "${!m003_capacity_devices[@]}"; do
    capacity_path=${m003_capacity_device_path["$device"]}
    m003_revalidate_frozen_parent "$capacity_path" || return 1
    read -r blocks fragment_size < <(LC_ALL=C stat -f -c '%a %S' -- "$capacity_path") || return 1
    available=$(m003_uint64_product "$blocks" "$fragment_size") || return 1
    [[ $available =~ ^(0|[1-9][0-9]*)$ && $available -ge 4000000000 ]] || return 1
    printf 'session-capacity-filesystem\t%s\t%s\t%s\t%s\n' "$ordinal" "$session_id" "$device" "$available" >>"$destination"
  done
}

m003_finish_log() {
  [[ -n $m003_log && -f $m003_log ]] || return 1
  {
    printf 'host-policy\t%s\t%s\t%s\tsuccess\tnot-applied\tnot-applicable\tnot-applicable\tnot-applicable\n' \
      "${ImageVersion:?ImageVersion is required from the hosted runner}" "$(uname -r)" "$(if [[ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns; else printf not-present; fi)"
    printf 'base-manifest-payload:\n'; cat "$candidate_linux_base_manifest"
    printf 'integration-manifest-payload:\n'; cat "$candidate_linux_integration_manifest"
  } >>"$m003_log"
  m003_fsync_file "$m003_log"
}

integration_report_has_successful_tests() {
  local json_log=$1
  [[ -f $json_log && ! -L $json_log ]] || return 1
  jq -se '
    [ .[] | select(.type == "testDone") ] as $tests |
    [ .[] | select(.type == "done") ] as $done |
    ($tests | length) > 0 and
    ($tests | map(select(.hidden == false)) | length) > 0 and
    ($done | length) == 1 and $done[0].success == true and
    all($tests[]; .skipped == false and .result == "success")
  ' "$json_log" >/dev/null
}

write_integration_outcome() {
  local step_id=$1 test_file=$2 status=$3 exit_code=$4 outcome
  outcome="$output_root/results/integration-$step_id.json"
  jq -cn --arg id "$step_id" --arg file "$test_file" --arg status "$status" --argjson exitCode "$exit_code" \
    '{id:$id,file:$file,status:$status,exitCode:$exitCode}' >"$outcome"
}

write_integration_outcomes_aggregate() {
  jq -s --rawfile discovered "$output_root/results/integration-tests.txt" '
    ($discovered | split("\n") | map(select(length > 0)) | sort) as $expected |
    (map(.file) | sort) as $reported |
    if length == 0
      or (([.[].id] | length) != ([.[].id] | unique | length))
      or (([.[].file] | length) != ([.[].file] | unique | length))
      or $reported != $expected
      or any(.[]; .status != "passed")
    then error("missing, duplicate, skipped, partial, or failed integration result")
    else . end
  ' "$output_root"/results/integration-*.json >"$output_root/results/integration-outcomes.json"
}

m003_prepare_linux_integration_report_directory() {
  local results_directory identity
  [[ $ticket == BURL-M003 && $role == linux-x86_64 ]] || return 2
  results_directory=$candidate_root/writable/results
  [[ ! -e $results_directory && ! -L $results_directory ]] || return 1
  mkdir "$results_directory" && chmod 700 "$results_directory" || return 1
  m003_validate_current_authority 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d candidate-writable || return 1
  exec {m003_integration_results_fd}<"$results_directory" || return 1
  identity=$(stat -Lc '%d:%i:%u:%g:%a' -- "/proc/self/fd/$m003_integration_results_fd") || return 1
  [[ $identity =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+:700$ ]] || return 1
  m003_integration_results_directory=$results_directory
  m003_integration_results_identity=$identity
}

m003_validate_linux_integration_report_directory() {
  local ordinal=$1 session_id=$2 results_directory canonical_results canonical_writable identity descriptor_identity
  [[ $ordinal == 5 || $ordinal == 6 ]] || return 1
  [[ -n ${m003_integration_results_directory:-} && -n ${m003_integration_results_identity:-} && ${m003_integration_results_fd:-} =~ ^[0-9]+$ && -d /proc/self/fd/$m003_integration_results_fd ]] || return 1
  m003_validate_current_authority "$ordinal" "$session_id" candidate-writable || return 1
  results_directory=$m003_integration_results_directory
  [[ $results_directory == "$candidate_root/writable/results" && -d $results_directory && ! -L $results_directory ]] || return 1
  identity=$(stat -Lc '%d:%i:%u:%g:%a' -- "$results_directory") || return 1
  descriptor_identity=$(stat -Lc '%d:%i:%u:%g:%a' -- "/proc/self/fd/$m003_integration_results_fd") || return 1
  [[ $descriptor_identity == "$m003_integration_results_identity" && $identity == "$descriptor_identity" ]] || return 1
  canonical_results=$(realpath -e -- "$results_directory") || return 1
  canonical_writable=$(realpath -e -- "$candidate_root/writable") || return 1
  [[ $canonical_writable == "$candidate_root/writable" && $canonical_results == "$canonical_writable/results" ]]
}

m003_consume_linux_integration_report() {
  local ordinal=$1 session_id=$2 test_file=$3 step_id report_name candidate_report canonical_candidate_report
  local output_results canonical_output_results destination outcome status=failed
  [[ $ticket == BURL-M003 && $role == linux-x86_64 ]] || return 2
  step_id=$(printf '%s' "$test_file" | sha256sum | awk '{print $1}')
  [[ $session_id == "integration-$step_id" ]] || return 1
  [[ $(rg -Fxc -- "$test_file" "$output_root/results/integration-tests.txt" || true) == 1 ]] || return 1
  output_results=$output_root/results
  [[ -d $output_root && ! -L $output_root && -d $output_results && ! -L $output_results ]] || return 1
  canonical_output_results=$(realpath -e -- "$output_results") || return 1
  [[ $canonical_output_results == "$output_root/results" ]] || return 1
  destination=$output_results/integration-$step_id.jsonl
  outcome=$output_results/integration-$step_id.json
  [[ ! -e $destination && ! -L $destination && ! -e $outcome && ! -L $outcome ]] || return 1
  report_name=integration-$step_id.jsonl
  if m003_validate_linux_integration_report_directory "$ordinal" "$session_id"; then
    candidate_report=$m003_integration_results_directory/$report_name
    if [[ -f $candidate_report && ! -L $candidate_report ]]; then
      canonical_candidate_report=$(realpath -e -- "$candidate_report") || return 1
      if [[ $canonical_candidate_report == "$m003_integration_results_directory/$report_name" ]] &&
        integration_report_has_successful_tests "$candidate_report" &&
        cp -- "$candidate_report" "$destination" && chmod 600 "$destination"; then
        status=passed
      fi
    fi
  fi
  write_integration_outcome "$step_id" "$test_file" "$status" 0 || return 1
  [[ $status == passed ]]
}

m003_cleanup_ephemeral_session() {
  local ordinal=$1 class=$2 session_fd=$3
  local path runtime
  # The retained original lock descriptor stays acquired while these known
  # leaves are removed.  No candidate-controlled pathname is reopened for the
  # teardown proof itself.
  for path in "${m003_current_path["$ordinal:session-contract-root"]}" "${m003_current_path["$ordinal:closure-staging"]}"; do
    rm -rf -- "$path" || return 1
  done
  if [[ $class == integration ]]; then
    runtime=${m003_current_path["$ordinal:xdg-runtime"]}
    rm -rf -- "$runtime" || return 1
    [[ ! -e $runtime ]] || return 1
  fi
  rm -rf -- "${m003_current_path["$ordinal:session-root"]}" || return 1
  eval "exec ${session_fd}<&-" || return 1
}

# Perl is the per-session parent controller because Bash cannot retain an
# openat-created O_RDWR/O_EXCL/O_NOFOLLOW descriptor across the fork/exec and
# later pass that same open file description to util-linux flock.  This stays
# in this trusted launcher: no helper file, CLI, or candidate-visible control
# protocol is introduced.
m003_perl_session_controller() {
  local session_path=$1 expected_preflight_path=$2 class=$3 stdout_path=$4 stderr_path=$5 stdin_path=$6 output_path=$7 stage_path=$8 contract_path=$9 runtime_path=${10} expected_session_id=${11}; shift 11
  perl -MFcntl=:DEFAULT -MIO::Handle -MErrno=EAGAIN -MFile::Copy=copy -MFile::Path=remove_tree -MPOSIX=dup2,WNOHANG -e '
    use strict; use warnings;
    my ($session, $expected_path, $class, $stdout_path, $stderr_path, $stdin_path, $output_path, $stage, $contract, $runtime, $expected_session, @argv) = @ARGV;
    @argv or die "missing bubblewrap argv\n";
    $expected_session =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/ or die "invalid expected cleanup session ID\n";
    sysopen(my $dir, $session, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) or die "open session authority: $!\n";
    my @dir_stat = stat($dir); my $identity = join(q{:}, @dir_stat[0, 1, 4, 5]);
    my $lock_path = q{/proc/self/fd/} . fileno($dir) . q{/namespace-teardown.lock};
    sysopen(my $lock, $lock_path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "openat original teardown lock: $!\n";
    fcntl($lock, F_SETFD, 0) or die "clear lock cloexec: $!\n";
    my @lock_stat = stat($lock); my $lock_identity = join(q{:}, @lock_stat[0, 1]);
    sysopen(my $stdin,  $stdin_path,  O_RDONLY | O_CREAT | O_NOFOLLOW, 0600) or die "open candidate stdin: $!\n";
    sysopen(my $stdout, $stdout_path, O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600) or die "open candidate stdout: $!\n";
    sysopen(my $stderr, $stderr_path, O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600) or die "open candidate stderr: $!\n";
    my @standard = map { join(q{:}, (stat($_))[0,1]) } ($stdin, $stdout, $stderr);
    open(my $expected_fh, q{<}, $expected_path) or die "open expected preflight: $!\n"; binmode($expected_fh); local $/; my $expected = <$expected_fh>;
    defined($expected) && length($expected) > 0 or die "empty expected preflight\n";
    (-e "$session/cleanup.frame" || -l "$session/cleanup.frame") and die "preexisting cleanup.frame\n";
    (-e "$session/cleanup.ack" || -l "$session/cleanup.ack") and die "preexisting cleanup.ack\n";
    use constant SYS_inotify_add_watch => 254; # Linux x86_64 is the raw-39 platform.
    use constant SYS_inotify_init1 => 294;
    use constant IN_CLOSE_WRITE => 0x00000008;
    use constant IN_MOVED_FROM => 0x00000040;
    use constant IN_MOVED_TO => 0x00000080;
    use constant IN_CREATE => 0x00000100;
    use constant IN_DELETE => 0x00000200;
    use constant O_NONBLOCK_LINUX => 04000;
    use constant O_CLOEXEC_LINUX => 02000000;
    my $inotify_fd = syscall(SYS_inotify_init1, O_NONBLOCK_LINUX | O_CLOEXEC_LINUX);
    $inotify_fd >= 0 or die "open cleanup readiness watch: $!\n";
    open(my $inotify, "<&=$inotify_fd") or die "fdopen cleanup readiness watch: $!\n";
    my $cleanup_watch = syscall(SYS_inotify_add_watch, fileno($inotify), q{/proc/self/fd/} . fileno($dir), IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE);
    $cleanup_watch >= 0 or die "watch cleanup directory: $!\n";
    pipe(my $record_read, my $record_write) or die "preflight pipe: $!\n";
    pipe(my $ack_read, my $ack_write) or die "ack pipe: $!\n";
    my $pid = fork(); defined($pid) or die "fork bubblewrap: $!\n";
    my $controller_complete = 0;
    my $cleanup_frame_closed = 0;
    sub persist_candidate_diagnostics {
      my ($destination, @sources) = @_;
      sysopen(my $out, $destination, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600) or return 0;
      for my $source (@sources) {
        seek($source, 0, 0) or return 0;
        while (1) {
          my $read = sysread($source, my $chunk, 65536);
          return 0 if !defined($read);
          last if $read == 0;
          while (length($chunk)) {
            my $written = syswrite($out, $chunk);
            return 0 if !defined($written) || $written == 0;
            substr($chunk, 0, $written, q{});
          }
        }
      }
      close($out) or return 0;
      return 1;
    }
    END {
      if (!$controller_complete && defined($pid) && $pid > 0 && kill(0, $pid)) {
        kill(q{TERM}, $pid); waitpid($pid, 0);
      }
    }
    $SIG{__DIE__} = sub {
      my $error = shift;
      if (!$controller_complete && $pid > 0) {
        if (kill(0, $pid)) { kill(q{TERM}, $pid); waitpid($pid, 0); }
        persist_candidate_diagnostics($output_path, $stdout, $stderr);
        close($inotify);
        my @failed_lock_stat = stat($lock);
        if (join(q{:}, @failed_lock_stat[0,1]) eq $lock_identity) {
          my $failed_lock_status = system(q{/nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock}, q{--fcntl}, q{--exclusive}, q{--timeout}, q{5}, q{--conflict-exit-code}, q{73}, fileno($lock));
          if ($failed_lock_status == 0) {
            my $ignored_errors;
            remove_tree($contract, $stage, ($class eq q{integration} ? $runtime : ()), $session, {error => \$ignored_errors});
            system(q{/nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock}, q{--fcntl}, q{--unlock}, fileno($lock));
          }
        }
        close($lock); close($dir);
      }
      local $SIG{__DIE__} = q{DEFAULT}; die $error;
    };
    if (!$pid) {
      close($dir); close($lock); close($record_read); close($ack_write);
      dup2(fileno($stdin), 0)  or die "dup stdin: $!\n";
      dup2(fileno($stdout), 1) or die "dup stdout: $!\n";
      dup2(fileno($stderr), 2) or die "dup stderr: $!\n";
      dup2(fileno($record_write), 3) or die "dup record: $!\n";
      dup2(fileno($ack_read), 4) or die "dup ack: $!\n";
      my @child_standard = map { join(q{:}, (stat($_))[0,1]) } (*STDIN, *STDOUT, *STDERR);
      join(q{|}, @child_standard) eq join(q{|}, @standard) or die "candidate stdio identity changed before handshake\n";
      my @fds = glob(q{/proc/self/fd/[0-9]*});
      for my $entry (@fds) { my ($fd) = $entry =~ m{/([0-9]+)$}; next if !defined($fd) || $fd <= 4; POSIX::close($fd); }
      %ENV = ();
      exec { $argv[0] } @argv or die "exec bubblewrap: $!\n";
    }
    close($record_write); close($ack_read); close($stdin);
    # Do not mix buffered readline with sysread on the preflight pipe: a
    # one-write frame can leave its body in the Perl input buffer while sysread
    # observes EOF from the kernel. Read every protocol byte through the same
    # unbuffered path before validating the declared body length and EOF.
    my $header = q{};
    while (length($header) < 128) {
      my $read = sysread($record_read, my $byte, 1);
      if (!defined($read) || $read != 1) {
        my $done = waitpid($pid, WNOHANG);
        for (1 .. 20) {
          last if $done == $pid;
          select undef, undef, undef, 0.05;
          $done = waitpid($pid, WNOHANG);
        }
        my $status = $done == $pid ? $? : q{still-running};
        die "malformed preflight header (candidate-status=$status)\n";
      }
      $header .= $byte;
      last if $byte eq "\n";
    }
    $header =~ /^preflight-bytes=([1-9][0-9]*)\n\z/ or die "malformed preflight header\n";
    my $remaining = $1; my $body = q{};
    while ($remaining > 0) { my $read = sysread($record_read, my $chunk, $remaining); defined($read) && $read > 0 or die "truncated preflight\n"; $body .= $chunk; $remaining -= $read; }
    sysread($record_read, my $trailing, 1) == 0 or die "preflight trailing data\n";
    $body eq $expected or die "preflight body mismatch\n";
    close($record_read) or die "close preflight read: $!\n";
    print {$ack_write} q{G} or die "write preflight ack: $!\n";
    close($ack_write) or die "close preflight ack: $!\n";
    my $acked = $class eq q{base}; my $wait_status; my $cleanup_result = q{};
    while (1) {
      if ($class eq q{integration} && !$acked) {
        while (1) {
          my $event_bytes = sysread($inotify, my $events, 65536);
          last if !defined($event_bytes) && $!{EAGAIN};
          defined($event_bytes) && $event_bytes >= 0 or die "read cleanup readiness watch: $!\n";
          last if $event_bytes == 0;
          my $offset = 0;
          while ($offset < length($events)) {
            length($events) - $offset >= 16 or die "malformed cleanup readiness event\n";
            my ($watch, $mask, $cookie, $name_length) = unpack(q{i L L L}, substr($events, $offset, 16));
            $offset += 16;
            length($events) - $offset >= $name_length or die "truncated cleanup readiness event\n";
            my $name = substr($events, $offset, $name_length); $offset += $name_length;
            $name =~ s/\x00.*\z//;
            next unless $watch == $cleanup_watch && $name eq q{cleanup.frame};
            if ($mask & IN_CLOSE_WRITE) { $cleanup_frame_closed = 1; next; }
            if ($cleanup_frame_closed && ($mask & (IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE))) {
              die "cleanup frame changed after close event\n";
            }
          }
          last if $event_bytes < 65536;
        }
        if ($cleanup_frame_closed) {
          my $frame_path = q{/proc/self/fd/} . fileno($dir) . q{/cleanup.frame};
          my @path_stat = lstat($frame_path);
          @path_stat && -f _ && !-l _ && (($path_stat[2] & 07777) == 0600) or die "unsafe cleanup frame\n";
          sysopen(my $frame, $frame_path, O_RDONLY | O_NOFOLLOW) or die "open cleanup frame: $!\n";
          my @frame_stat = stat($frame);
          @frame_stat && $frame_stat[0] == $path_stat[0] && $frame_stat[1] == $path_stat[1] or die "cleanup frame identity changed\n";
          my $contents = q{};
          my $cleanup_frame_maximum = length($session) + 256;
          while (1) {
            my $read = sysread($frame, my $chunk, 256);
            defined($read) or die "read cleanup frame: $!\n";
            last if $read == 0;
            $contents .= $chunk;
            length($contents) <= $cleanup_frame_maximum or die "oversized cleanup frame\n";
          }
          close($frame) or die "close cleanup frame: $!\n";
          $contents =~ /^session-id=\Q$expected_session\E\nsupervisor-result=(success|candidate-failed|timeout|sway-failed|socket-disrupted|interrupted|cleanup-failed)\nsway-pid=[1-9][0-9]{0,9}\ntermination-path=(candidate-exit|candidate-sigkill|sway-sigkill|signal|early-sway-failure|timeout|sway-failed|socket-disrupted|swaybg-detected)\nwait-status=(0|[1-9][0-9]{0,2})\nsway-reaped=true\ncleanup-complete=true\n\z/ or die "malformed cleanup frame\n";
          my ($reported_result, $reported_termination, $reported_wait) = ($1, $2, $3);
          $reported_wait <= 255 or die "noncanonical cleanup wait status\n";
          if ($reported_result eq q{success}) {
            $reported_wait == 0 && ($reported_termination eq q{candidate-exit} || $reported_termination eq q{sway-sigkill}) or die "invalid successful cleanup frame\n";
          } elsif ($reported_result eq q{candidate-failed}) {
            $reported_wait != 0 or die "invalid failed cleanup frame\n";
          }
          $cleanup_result = $reported_result;
          my $ack_path = q{/proc/self/fd/} . fileno($dir) . q{/cleanup.ack};
          sysopen(my $ack, $ack_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "create cleanup ack: $!\n";
          print {$ack} "K\n" or die "write cleanup ack: $!\n"; defined($ack->sync) or die "fsync cleanup ack: $!\n"; close($ack) or die "close cleanup ack: $!\n";
          $acked = 1;
        }
      }
      my $done = waitpid($pid, WNOHANG); if ($done == $pid) { $wait_status = $?; last; }
      select undef, undef, undef, 0.05;
    }
    ($class eq q{base} || $acked) or die "missing cleanup acknowledgement\n";
    close($inotify) or die "close cleanup readiness watch: $!\n";
    my @after = stat($lock); join(q{:}, @after[0,1]) eq $lock_identity or die "retained lock identity changed\n";
    my $flock = q{/nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock};
    my $flock_status = system($flock, q{--fcntl}, q{--exclusive}, q{--timeout}, q{5}, q{--conflict-exit-code}, q{73}, fileno($lock));
    $flock_status == 0 or die "retained OFD lock was not acquired: $flock_status\n";
    # waitpid status zero is the only normal successful outer Bubblewrap exit.
    # A signal-only status has no shifted exit code but must still reject.
    my $ok = ($wait_status == 0 && ($class eq q{base} || $cleanup_result eq q{success}));
    persist_candidate_diagnostics($output_path, $stdout, $stderr) or die "persist candidate diagnostics\n";
    my $errors;
    remove_tree($contract, $stage, ($class eq q{integration} ? $runtime : ()), $session, {error => \$errors});
    $errors && @$errors and die "ephemeral cleanup failed\n";
    system($flock, q{--fcntl}, q{--unlock}, fileno($lock)) == 0 or die "unlock retained lock: $!\n";
    close($stdout) or die "close candidate stdout: $!\n"; close($stderr) or die "close candidate stderr: $!\n";
    close($lock) or die "close retained lock: $!\n"; close($dir) or die "close session authority: $!\n";
    $controller_complete = 1;
    $ok or die "candidate or supervisor failed\n";
    print "ok\t$lock_identity\n";
  ' -- "$session_path" "$expected_preflight_path" "$class" "$stdout_path" "$stderr_path" "$stdin_path" "$output_path" "$stage_path" "$contract_path" "$runtime_path" "$expected_session_id" "$@"
}

m003_run_session() {
  local ordinal=$1 session_id=$2 class=$3 step_id=$4; shift 4
  local manifest source_file manifest_sha source_sha source_count stage_path session_path contract_path runtime_path stdout_path stderr_path stdin_path
  local preflight_read ack_write expected_preflight bwrap_pid bwrap_status acknowledged=false frame_path session_ok=true failure_status=1
  local argv_path argv_bytes argv_sha controller_result lock_identity capacity_rows expected_preflight_path
  local -a m003_argv=()
  [[ $role == linux-x86_64 && $ticket == BURL-M003 ]] || return 2
  m003_source_tracked_state_is_clean || return 1
  m003_revalidate_observed_executables || return 1
  [[ $(sha256sum /nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap | awk '{print $1}') == c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726 && $(sha256sum "$m003_runner_temp_root/burlmd-m003/trusted-parent-bubblewrap.manifest" | awk '{print $1}') == 398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd ]] || return 1
  if [[ $class == base ]]; then
    manifest=$candidate_linux_base_manifest; source_file=$m003_base_sources; manifest_sha=127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64; source_sha=$m003_base_source_sha; source_count=$m003_base_source_count
    candidate_linux_closure_paths=("${candidate_linux_base_closure_paths[@]}")
  else
    manifest=$candidate_linux_integration_manifest; source_file=$m003_integration_sources; manifest_sha=353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896; source_sha=$m003_integration_source_sha; source_count=$m003_integration_source_count
    candidate_linux_closure_paths=("${candidate_linux_integration_closure_paths[@]}")
  fi
  [[ $(wc -c <"$manifest" | tr -d ' ') == $([[ $class == base ]] && printf 30717 || printf 34315) && $(sha256sum "$manifest" | awk '{print $1}') == "$manifest_sha" ]] || return 1
  if [[ $class == integration ]]; then
    [[ $(stat -Lc '%a' -- "$script_root/scripts/managed-sway.conf") == 644 && $(wc -c <"$script_root/scripts/managed-sway.conf" | tr -d ' ') == 72 && $(sha256sum "$script_root/scripts/managed-sway.conf" | awk '{print $1}') == dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a ]] || return 1
  fi
  stage_path=${m003_current_path["$ordinal:closure-staging"]}; session_path=${m003_current_path["$ordinal:session-root"]}; contract_path=${m003_current_path["$ordinal:session-contract-root"]}
  runtime_path=${m003_current_path["$ordinal:xdg-runtime"]-}
  [[ ! -e $session_path && ! -L $session_path ]] || return 1
  mkdir "$session_path" && chmod 700 "$session_path" || return 1
  m003_open_verified_session_directory "$session_path" || return 1
  read -r lock_dev lock_inode < <(stat -Lc '%d %i' -- "$session_path") || return 1
  m003_make_staging_leaf "$ordinal" "$session_id" "$manifest" "$stage_path" || return 1
  m003_make_contract_leaf "$ordinal" "$source_file" "$contract_path" || return 1
  [[ $class != integration ]] || m003_make_runtime_leaf "$ordinal" || return 1
  stdout_path=$session_path/candidate.stdout; stderr_path=$session_path/candidate.stderr; stdin_path=$session_path/candidate.stdin
  m003_build_argv "$ordinal" "$session_id" "$class" m003_argv "$@" || return 1
  argv_path=$m003_runner_temp_root/burlmd-m003/argv-$ordinal.bin
  printf '%s\0' "${m003_argv[@]}" >"$argv_path"
  argv_bytes=$(wc -c <"$argv_path"); argv_sha=$(sha256sum "$argv_path" | awk '{print $1}')
  (( argv_bytes < $(getconf ARG_MAX) / 2 )) || return 1
  expected_preflight=$(m003_expected_preflight_body "$class" "$manifest_sha" "$source_file" "$source_count")
  expected_preflight+=$'\n'
  expected_preflight_path=$m003_runner_temp_root/burlmd-m003/preflight-$ordinal.expected
  printf '%s' "$expected_preflight" >"$expected_preflight_path"
  m003_preflight_bytes=$(printf '%s' "$expected_preflight" | wc -c | tr -d ' ')
  m003_preflight_sha=$(printf '%s' "$expected_preflight" | sha256sum | awk '{print $1}')
  capacity_rows=$m003_runner_temp_root/burlmd-m003/capacity-$ordinal.tsv
  m003_capture_session_capacity_rows "$ordinal" "$session_id" "$class" "$capacity_rows" || return 1
  controller_result=$(m003_perl_session_controller "$session_path" "$expected_preflight_path" "$class" "$stdout_path" "$stderr_path" "$stdin_path" "$output_root/results/role-step-$step_id.log" "$stage_path" "$contract_path" "$runtime_path" "$session_id" "${m003_argv[@]}") || return 1
  [[ $controller_result =~ ^ok$'\t'([1-9][0-9]*:[1-9][0-9]*)$ ]] || return 1
  lock_identity=${BASH_REMATCH[1]}
  if [[ $class == integration ]]; then
    m003_append_session_record "$ordinal" "$session_id" "$class" "$manifest_sha" "$source_sha" "$argv_bytes" "$argv_sha" "$stage_path" success true true "$capacity_rows" "$lock_identity" || return 1
  else
    m003_append_session_record "$ordinal" "$session_id" "$class" "$manifest_sha" "$source_sha" "$argv_bytes" "$argv_sha" "$stage_path" compositor-not-applicable not-applicable true "$capacity_rows" "$lock_identity" || return 1
  fi
  rm -f -- "$argv_path"
  rm -f -- "$expected_preflight_path"
}

linux_m003_candidate_bwrap() {
  local session_dir=$1 session_destination lock_file lock_destination launcher_pid entry key value arg path_entry closure_path
  local -a path_entries mapped_path
  shift
  [[ $ticket == BURL-M003 ]] || {
    echo 'raw-39 closure-view launcher received a non-M003 ticket' >&2
    return 2
  }
  [[ $(bwrap --version | awk '{print $NF}') == 0.11.2 ]] || {
    echo 'locked Bubblewrap 0.11.2 is required for Linux candidate isolation' >&2
    return 2
  }
  command -v flock >/dev/null || { echo 'locked flock is required for Linux candidate teardown' >&2; return 2; }
  lock_file=$candidate_teardown_lock
  session_destination=/candidate/${session_dir#"$candidate_root/"}
  lock_destination=/candidate/${lock_file#"$candidate_root/"}
  launcher_pid=/candidate/${session_dir#"$candidate_root/"}/pid
  entry='for fd in /proc/self/fd/[0-9]*; do number=${fd##*/}; [[ $number =~ ^[0-9]+$ ]] || continue; ((number > 2 && number != 255)) || continue; eval "exec $number>&-" 2>/dev/null || exit 2; done; ip link set dev lo up || exit 2; ip -o link show up dev lo >/dev/null || exit 2; printf "%s\n" "$$" > "$BURLMD_CANDIDATE_PID_FILE"; "$@"'
  # The role helper and the exact Nix runtime closure are trusted
  # control/toolchain inputs. The candidate source and candidate-owned output
  # roots are the only project mounts. A private Sway socket is added only
  # while its owned Linux integration test is active.
  bwrap_args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --lock-file "$lock_destination")
  for arg in "${candidate_env[@]}"; do
    key=${arg%%=*}; value=${arg#*=}
    if [[ $key == PATH ]]; then
      mapped_path=()
      IFS=: read -r -a path_entries <<<"$value"
      for path_entry in "${path_entries[@]}"; do
        case $path_entry in
          "$source_root"/*) mapped_path+=(/source/${path_entry#"$source_root/"});;
          "$source_root") mapped_path+=(/source);;
          "$script_root"/*) mapped_path+=(/trusted/${path_entry#"$script_root/"});;
          "$script_root") mapped_path+=(/trusted);;
          "$candidate_root"/*) mapped_path+=(/candidate/${path_entry#"$candidate_root/"});;
          "$candidate_root") mapped_path+=(/candidate);;
          *) mapped_path+=("$path_entry");;
        esac
      done
      value=$(IFS=:; printf '%s' "${mapped_path[*]}")
    else
      case $value in
        "$candidate_root"/*) value=/candidate/${value#"$candidate_root/"};;
        "$candidate_root") value=/candidate;;
      esac
    fi
    bwrap_args+=(--setenv "$key" "$value")
  done
  bwrap_args+=(
    --setenv BURLMD_CANDIDATE_LOOPBACK "$([[ $ticket == BURL-M003 ]] && printf 1 || printf 0)"
    --setenv BURLMD_CANDIDATE_SESSION "$candidate_session"
    --setenv BURLMD_CANDIDATE_PID_FILE "$launcher_pid"
  )
  bwrap_args+=(
    --proc /proc --dev /dev --tmpfs /tmp
    --dir /source
    # Do not bind the whole candidate root: it contains the staged execution
    # checkout. Exposing it at /candidate would create a writable alias around
    # the read-only /source mount. Only runtime-owned homes, outputs, and the
    # per-command status directory are writable candidate mounts.
    --dir /candidate --dir /candidate/xdg --dir /candidate/writable
    --dir /candidate/xdg/cache --dir /candidate/xdg/config
    --dir /candidate/xdg/data --dir /candidate/xdg/state
    --bind "$candidate_root/home" /candidate/home
    --bind "$candidate_root/tmp" /candidate/tmp
    --bind "$candidate_root/xdg/cache" /candidate/xdg/cache
    --bind "$candidate_root/xdg/config" /candidate/xdg/config
    --bind "$candidate_root/xdg/data" /candidate/xdg/data
    --bind "$candidate_root/xdg/state" /candidate/xdg/state
    --bind "$candidate_root/gh" /candidate/gh
    --ro-bind "$candidate_tool_path" /candidate/tool-path
    --bind "$candidate_root/writable" /candidate/writable
    --bind "$session_dir" "$session_destination"
    --dir /candidate/prepared
    --ro-bind "$candidate_root/prepared" /candidate/prepared
    --dir /trusted --ro-bind "$script_root" /trusted
  )
  # Every Linux candidate sees its tested source only through this read-only
  # mount. A managed Spike receives one private bind overlay at its exact
  # contract-declared prototype root; no code path binds an entire checkout
  # read-write.
  bwrap_args+=(--ro-bind "$candidate_execution_root" /source)
  if [[ -n $candidate_linux_writable_ticket_root ]]; then
    [[ -n $candidate_linux_ticket_root && -d $candidate_linux_writable_ticket_root && ! -L $candidate_linux_writable_ticket_root ]] || {
      echo 'Linux contract writable overlay is missing or unsafe' >&2; return 2;
    }
    bwrap_args+=(--bind "$candidate_linux_writable_ticket_root" "/source/$candidate_linux_ticket_root")
  fi
  bwrap_args+=(--chdir /source)
  [[ $candidate_linux_closure_prepared == true ]] || {
    echo 'Linux candidate closure views were not prepared by the trusted parent' >&2; return 2;
  }
  if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} ]]; then
    [[ -d $LINUX_VIEWPORT_RUNTIME ]] || { echo 'private Sway runtime mount is absent' >&2; return 1; }
    [[ -n ${LINUX_VIEWPORT_DISPLAY:-} && -S $LINUX_VIEWPORT_RUNTIME/$LINUX_VIEWPORT_DISPLAY ]] || {
      echo 'private Wayland display socket is absent' >&2; return 1;
    }
    bwrap_args+=(--dir /candidate/xdg/runtime --bind "$LINUX_VIEWPORT_RUNTIME" /candidate/xdg/runtime)
  fi
  if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} ]]; then
    candidate_linux_closure_paths=("${candidate_linux_integration_closure_paths[@]}")
  else
    candidate_linux_closure_paths=("${candidate_linux_base_closure_paths[@]}")
  fi
  bwrap_args+=(--dir /nix --dir /nix/store)
  for closure_path in "${candidate_linux_closure_paths[@]}"; do
    [[ $closure_path == /nix/store/* && -e $closure_path && ! -L $closure_path ]] || return 2
    bwrap_args+=(--ro-bind "$closure_path" "$closure_path")
  done
  # Candidate-provided contract commands can use the conventional
  # `#!/usr/bin/env …` shebang, but that interpreter is a specific locked
  # coreutils binary from the declared Nix closure—not a host `/usr` mount.
  # Trusted helpers below are instead invoked through the exact locked Bash.
  [[ -n $candidate_linux_env_interpreter && $candidate_linux_env_interpreter == /nix/store/* ]] || {
    echo 'locked env interpreter is missing from Linux candidate closure' >&2; return 2;
  }
  bwrap_args+=(--dir /usr --dir /usr/bin --symlink "$candidate_linux_env_interpreter" /usr/bin/env)
  if [[ $ticket == BURL-M003 ]]; then
    # The staged tree itself stays read-only. Flutter/Cargo receive only their
    # generated package/config, build, and target roots as writable overlays.
    bwrap_args+=(
      --bind "$candidate_root/writable/dart-tool" /source/.dart_tool
      --bind "$candidate_root/writable/build" /source/build
      --bind "$candidate_root/writable/l10n-generated" /source/lib/l10n/generated
      # The Cargokit copy exists solely to make its path dependency match the
      # precompiled runner's sandbox-visible package configuration.  It is
      # source input to the candidate, not generated output.
      --ro-bind "$candidate_root/writable/rust-builder-cargokit" /source/rust_builder/cargokit
      # CMake marks this launcher executable before invoking it.  Keep that
      # unavoidable mode-bit mutation to this one copied file, not the
      # Cargokit tree or candidate checkout.
      --bind "$candidate_root/writable/rust-builder-cargokit/run_build_tool.sh" /source/rust_builder/cargokit/run_build_tool.sh
      # The Linux desktop toolchain regenerates this Flutter-owned directory.
      # Keep the checkout itself read-only and expose only this dedicated,
      # credential-free overlay rather than widening /source or linux/.
      --bind "$candidate_root/writable/linux-flutter-ephemeral" /source/linux/flutter/ephemeral
      --bind "$candidate_root/writable/pub-active-roots" /candidate/prepared/pub-cache/active_roots
    )
  fi
  bwrap_args+=(--setenv BURLMD_LOCKED_NIX_CLOSURE "$(IFS=:; printf '%s' "${candidate_linux_closure_paths[*]}")")
  if [[ -n $candidate_linux_openssl_pkgconfig ]]; then
    [[ ${LIBCLANG_PATH:-} == /nix/store/* && -d ${LIBCLANG_PATH:-} ]] || {
      echo 'locked LIBCLANG_PATH is required for Linux candidate build tools' >&2; return 2;
    }
    bwrap_args+=(
    --setenv PKG_CONFIG_PATH "$candidate_linux_openssl_pkgconfig"
    --setenv LIBCLANG_PATH "$LIBCLANG_PATH"
    # The cc wrapper receives no ambient devenv flags after env -i. Supply
    # only the immutable OpenSSL include/library locations required by the
    # locked SQLCipher build script, not the host's aggregate flags.
    --setenv NIX_CFLAGS_COMPILE "-isystem $candidate_linux_openssl_include"
    --setenv NIX_LDFLAGS_x86_64_unknown_linux_gnu "-L$candidate_linux_openssl_lib"
    --setenv CFLAGS "-isystem $candidate_linux_openssl_include"
    --setenv LDFLAGS "-L$candidate_linux_openssl_lib"
    --setenv LIBGL_DRIVERS_PATH "$candidate_linux_mesa_dri"
      --setenv __EGL_VENDOR_LIBRARY_FILENAMES "$candidate_linux_mesa_egl"
    )
  fi
  local -a rewritten=()
  for arg in "$@"; do
    if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} && $arg == "XDG_RUNTIME_DIR=$LINUX_VIEWPORT_RUNTIME" ]]; then
      rewritten+=(XDG_RUNTIME_DIR=/candidate/xdg/runtime)
      continue
    fi
    case $arg in
      "$source_root"/*) rewritten+=(/source/${arg#"$source_root/"});;
      "$source_root") rewritten+=(/source);;
      "$script_root"/*) rewritten+=(/trusted/${arg#"$script_root/"});;
      "$script_root") rewritten+=(/trusted);;
      # The disposable candidate checkout lives under candidate_root on the
      # host, but is exposed read-only at /source in Bubblewrap. Match it
      # before the broader runtime-root case so trusted step workdirs enter
      # the mounted checkout rather than an unmounted /candidate/workspace.
      "$candidate_execution_root"/*) rewritten+=(/source/${arg#"$candidate_execution_root/"});;
      "$candidate_execution_root") rewritten+=(/source);;
      "$candidate_root"/*) rewritten+=(/candidate/${arg#"$candidate_root/"});;
      "$candidate_root") rewritten+=(/candidate);;
      *) rewritten+=("$arg");;
    esac
  done
  bwrap "${bwrap_args[@]}" "$candidate_shell" -ceu "$entry" candidate-child "${rewritten[@]}"
}

# Preserve the predecessor private-store namespace verbatim for every Linux
# ticket other than BURL-M003. Raw-39 sessions don't enter this function.
linux_legacy_candidate_bwrap() {
  local session_dir=$1 session_destination lock_file lock_destination launcher_pid entry key value arg path_entry closure_path private_path private_env_interpreter
  local -a path_entries mapped_path
  shift
  [[ $ticket != BURL-M003 ]] || {
    echo 'BURL-M003 must not enter the legacy private-store launcher' >&2
    return 2
  }
  [[ $(bwrap --version | awk '{print $NF}') == 0.11.2 ]] || {
    echo 'locked Bubblewrap 0.11.2 is required for Linux candidate isolation' >&2
    return 2
  }
  command -v flock >/dev/null || { echo 'locked flock is required for Linux candidate teardown' >&2; return 2; }
  lock_file=$candidate_teardown_lock
  session_destination=/candidate/${session_dir#"$candidate_root/"}
  lock_destination=/candidate/${lock_file#"$candidate_root/"}
  launcher_pid=/candidate/${session_dir#"$candidate_root/"}/pid
  entry='for fd in /proc/self/fd/[0-9]*; do number=${fd##*/}; [[ $number =~ ^[0-9]+$ ]] || continue; ((number > 2 && number != 255)) || continue; eval "exec $number>&-" 2>/dev/null || exit 2; done; if [[ ${BURLMD_CANDIDATE_LOOPBACK:-0} == 1 ]]; then ip link set lo up || exit 2; fi; printf "%s\n" "$$" > "$BURLMD_CANDIDATE_PID_FILE"; "$@"'
  # The role helper and the exact Nix runtime closure are trusted
  # control/toolchain inputs. The candidate source and candidate-owned output
  # roots are the only project mounts. A private Sway socket is added only
  # while its owned Linux integration test is active.
  bwrap_args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --lock-file "$lock_destination")
  for arg in "${candidate_env[@]}"; do
    key=${arg%%=*}; value=${arg#*=}
    if [[ $key == PATH ]]; then
      mapped_path=()
      IFS=: read -r -a path_entries <<<"$value"
      for path_entry in "${path_entries[@]}"; do
        case $path_entry in
          "$source_root"/*) mapped_path+=(/source/${path_entry#"$source_root/"});;
          "$source_root") mapped_path+=(/source);;
          "$script_root"/*) mapped_path+=(/trusted/${path_entry#"$script_root/"});;
          "$script_root") mapped_path+=(/trusted);;
          "$candidate_root"/*) mapped_path+=(/candidate/${path_entry#"$candidate_root/"});;
          "$candidate_root") mapped_path+=(/candidate);;
          *) mapped_path+=("$path_entry");;
        esac
      done
      value=$(IFS=:; printf '%s' "${mapped_path[*]}")
    else
      case $value in
        "$candidate_root"/*) value=/candidate/${value#"$candidate_root/"};;
        "$candidate_root") value=/candidate;;
      esac
    fi
    bwrap_args+=(--setenv "$key" "$value")
  done
  bwrap_args+=(
    --setenv BURLMD_CANDIDATE_LOOPBACK "$([[ $ticket == BURL-M003 ]] && printf 1 || printf 0)"
    --setenv BURLMD_CANDIDATE_SESSION "$candidate_session"
    --setenv BURLMD_CANDIDATE_PID_FILE "$launcher_pid"
  )
  bwrap_args+=(
    --proc /proc --dev /dev --tmpfs /tmp
    --dir /source
    # Do not bind the whole candidate root: it contains the staged execution
    # checkout. Exposing it at /candidate would create a writable alias around
    # the read-only /source mount. Only runtime-owned homes, outputs, and the
    # per-command status directory are writable candidate mounts.
    --dir /candidate --dir /candidate/xdg --dir /candidate/writable
    --dir /candidate/xdg/cache --dir /candidate/xdg/config --dir /candidate/xdg/runtime
    --dir /candidate/xdg/data --dir /candidate/xdg/state
    --bind "$candidate_root/home" /candidate/home
    --bind "$candidate_root/tmp" /candidate/tmp
    --bind "$candidate_root/xdg/cache" /candidate/xdg/cache
    --bind "$candidate_root/xdg/config" /candidate/xdg/config
    --bind "$candidate_root/xdg/data" /candidate/xdg/data
    --bind "$candidate_root/xdg/state" /candidate/xdg/state
    --bind "$candidate_root/gh" /candidate/gh
    --ro-bind "$candidate_tool_path" /candidate/tool-path
    --bind "$candidate_root/writable" /candidate/writable
    --bind "$session_dir" "$session_destination"
    --dir /candidate/prepared
    --ro-bind "$candidate_root/prepared" /candidate/prepared
    --dir /trusted --ro-bind "$script_root" /trusted
  )
  # Every Linux candidate sees its tested source only through this read-only
  # mount. A managed Spike receives one private bind overlay at its exact
  # contract-declared prototype root; no code path binds an entire checkout
  # read-write.
  bwrap_args+=(--ro-bind "$candidate_execution_root" /source)
  if [[ -n $candidate_linux_writable_ticket_root ]]; then
    [[ -n $candidate_linux_ticket_root && -d $candidate_linux_writable_ticket_root && ! -L $candidate_linux_writable_ticket_root ]] || {
      echo 'Linux contract writable overlay is missing or unsafe' >&2; return 2;
    }
    bwrap_args+=(--bind "$candidate_linux_writable_ticket_root" "/source/$candidate_linux_ticket_root")
  fi
  bwrap_args+=(--chdir /source)
  [[ $candidate_linux_closure_prepared == true && -n $candidate_private_store_root ]] || {
    echo 'Linux candidate private store was not prepared by the trusted parent' >&2; return 2;
  }
  if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} ]]; then
    [[ -d $LINUX_VIEWPORT_RUNTIME ]] || { echo 'private Sway runtime mount is absent' >&2; return 1; }
    [[ -n ${LINUX_VIEWPORT_DISPLAY:-} && -S $LINUX_VIEWPORT_RUNTIME/$LINUX_VIEWPORT_DISPLAY ]] || {
      echo 'private Wayland display socket is absent' >&2; return 1;
    }
    bwrap_args+=(--ro-bind "$LINUX_VIEWPORT_RUNTIME/$LINUX_VIEWPORT_DISPLAY" "/candidate/xdg/runtime/$LINUX_VIEWPORT_DISPLAY")
  fi
  private_store_root_is_owned "$candidate_private_store_root" || {
    echo 'Linux candidate private store root failed ownership validation' >&2; return 2;
  }
  # The private rooted store remains writable for BURL-O001's new offline
  # output/state paths. Every pre-copied authenticated closure member is then
  # overlaid read-only from that same owned store, never from host /nix/store.
  bwrap_args+=(--bind "$candidate_private_store_root/nix" /nix)
  for closure_path in "${candidate_linux_closure_paths[@]}"; do
    private_path=$(private_closure_member "$closure_path") || {
      echo "invalid private Linux candidate closure member: $closure_path" >&2
      return 2
    }
    bwrap_args+=(--ro-bind "$private_path" "$closure_path")
  done
  # Candidate-provided contract commands can use the conventional
  # `#!/usr/bin/env …` shebang, but that interpreter is a specific locked
  # coreutils binary from the declared Nix closure—not a host `/usr` mount.
  # Trusted helpers below are instead invoked through the exact locked Bash.
  [[ -n $candidate_linux_env_interpreter && $candidate_linux_env_interpreter == /nix/store/* ]] || {
    echo 'locked env interpreter is missing from Linux candidate closure' >&2; return 2;
  }
  private_env_interpreter=$(private_closure_member "$candidate_linux_env_interpreter") || {
    echo 'private env interpreter is absent from the copied Linux closure' >&2; return 2;
  }
  bwrap_args+=(--dir /usr --dir /usr/bin --ro-bind "$private_env_interpreter" /usr/bin/env)
  if [[ $ticket == BURL-M003 ]]; then
    # The staged tree itself stays read-only. Flutter/Cargo receive only their
    # generated package/config, build, and target roots as writable overlays.
    bwrap_args+=(
      --bind "$candidate_root/writable/dart-tool" /source/.dart_tool
      --bind "$candidate_root/writable/build" /source/build
      --bind "$candidate_root/writable/l10n-generated" /source/lib/l10n/generated
      # The Cargokit copy exists solely to make its path dependency match the
      # precompiled runner's sandbox-visible package configuration.  It is
      # source input to the candidate, not generated output.
      --ro-bind "$candidate_root/writable/rust-builder-cargokit" /source/rust_builder/cargokit
      # CMake marks this launcher executable before invoking it.  Keep that
      # unavoidable mode-bit mutation to this one copied file, not the
      # Cargokit tree or candidate checkout.
      --bind "$candidate_root/writable/rust-builder-cargokit/run_build_tool.sh" /source/rust_builder/cargokit/run_build_tool.sh
      # The Linux desktop toolchain regenerates this Flutter-owned directory.
      # Keep the checkout itself read-only and expose only this dedicated,
      # credential-free overlay rather than widening /source or linux/.
      --bind "$candidate_root/writable/linux-flutter-ephemeral" /source/linux/flutter/ephemeral
      --bind "$candidate_root/writable/pub-active-roots" /candidate/prepared/pub-cache/active_roots
    )
  fi
  bwrap_args+=(--setenv BURLMD_LOCKED_NIX_CLOSURE "$(IFS=:; printf '%s' "${candidate_linux_closure_paths[*]}")")
  if [[ -n $candidate_linux_openssl_pkgconfig ]]; then
    [[ ${LIBCLANG_PATH:-} == /nix/store/* && -d ${LIBCLANG_PATH:-} ]] || {
      echo 'locked LIBCLANG_PATH is required for Linux candidate build tools' >&2; return 2;
    }
    bwrap_args+=(
      --setenv PKG_CONFIG_PATH "$candidate_linux_openssl_pkgconfig"
      --setenv LIBCLANG_PATH "$LIBCLANG_PATH"
      # The cc wrapper receives no ambient devenv flags after env -i. Supply
      # only the immutable OpenSSL include/library locations required by the
      # locked SQLCipher build script, not the host's aggregate flags.
      --setenv NIX_CFLAGS_COMPILE "-isystem $candidate_linux_openssl_include"
      --setenv NIX_LDFLAGS "-L$candidate_linux_openssl_lib"
      --setenv CFLAGS "-isystem $candidate_linux_openssl_include"
      --setenv LDFLAGS "-L$candidate_linux_openssl_lib"
      --setenv LIBGL_DRIVERS_PATH "$candidate_linux_mesa_dri"
      --setenv __EGL_VENDOR_LIBRARY_FILENAMES "$candidate_linux_mesa_egl"
    )
  fi
  bwrap_args+=(--setenv NIX_REMOTE local --setenv NIX_PATH '' --setenv NIX_CONFIG "$candidate_private_nix_config")
  local -a rewritten=()
  for arg in "$@"; do
    if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} && $arg == "XDG_RUNTIME_DIR=$LINUX_VIEWPORT_RUNTIME" ]]; then
      rewritten+=(XDG_RUNTIME_DIR=/candidate/xdg/runtime)
      continue
    fi
    case $arg in
      "$source_root"/*) rewritten+=(/source/${arg#"$source_root/"});;
      "$source_root") rewritten+=(/source);;
      "$script_root"/*) rewritten+=(/trusted/${arg#"$script_root/"});;
      "$script_root") rewritten+=(/trusted);;
      # The disposable candidate checkout lives under candidate_root on the
      # host, but is exposed read-only at /source in Bubblewrap. Match it
      # before the broader runtime-root case so trusted step workdirs enter
      # the mounted checkout rather than an unmounted /candidate/workspace.
      "$candidate_execution_root"/*) rewritten+=(/source/${arg#"$candidate_execution_root/"});;
      "$candidate_execution_root") rewritten+=(/source);;
      "$candidate_root"/*) rewritten+=(/candidate/${arg#"$candidate_root/"});;
      "$candidate_root") rewritten+=(/candidate);;
      *) rewritten+=("$arg");;
    esac
  done
  bwrap "${bwrap_args[@]}" "$candidate_shell" -ceu "$entry" candidate-child "${rewritten[@]}"
}

linux_candidate_bwrap() {
  if [[ $ticket == BURL-M003 ]]; then
    linux_m003_candidate_bwrap "$@"
  else
    linux_legacy_candidate_bwrap "$@"
  fi
}

start_candidate_session() {
  local session_dir launcher pass published_pid
  [[ -z $candidate_pid ]] || { echo 'nested candidate session is forbidden' >&2; return 1; }
  if session_dir=$(mktemp -d "$candidate_root/session.XXXXXXXX"); then :; else return $?; fi
  candidate_session="managed-role-${session_dir##*/}"
  candidate_marker_file="$session_dir/marker"
  printf '%s\n' "$candidate_session" >"$candidate_marker_file" || return $?
  # Descriptor 255 is the current Bash interpreter input. It is CLOEXEC; all
  # other inherited descriptors are closed in the launch subshell below. Do
  # not close them in this trusted parent: callers may be capturing a command
  # log on an inherited descriptor while the candidate is being started.
  # The direct fixture inspects the resulting exec child with a non-CLOEXEC FD
  # 10+ canary, because enumerating /proc/self/fd inside this shell creates a
  # scanner descriptor and cannot prove the property being asserted.
  # The trusted parent polls only the wrapper's liveness, then obtains its
  # actual exit result with `wait`. Candidate code receives no status channel:
  # a writable file would let it claim success before its command has ended.
  launcher='printf "%s\n" "$$" > "$BURLMD_CANDIDATE_PID_FILE"; "$@"'
  if [[ $role == linux-x86_64 ]]; then
    candidate_linux_namespace=true
    candidate_teardown_lock="$session_dir/namespace-teardown.lock"
    if [[ $ticket == BURL-M003 ]]; then
      (umask 077; : >"$candidate_teardown_lock") || return $?
      exec {candidate_teardown_lock_fd}<>"$candidate_teardown_lock" || return $?
      [[ -f /proc/$$/fd/$candidate_teardown_lock_fd ]] || return 1
    else
      : >"$candidate_teardown_lock" || return $?
    fi
    (
      # candidate_exec captures startup with errexit temporarily disabled in
      # the parent. Restore it in this child before entering either nested
      # launcher so an implicit fail-closed check cannot continue.
      set -e
      close_inherited_candidate_fds
      linux_candidate_bwrap "$session_dir" "$@"
    ) &
    candidate_wait_pid=$!
    candidate_pid=$candidate_wait_pid
    kill -0 "$candidate_wait_pid" 2>/dev/null || {
      echo 'Linux candidate namespace failed to start' >&2
      return 1
    }
    return 0
  fi
  (
    set -e
    close_inherited_candidate_fds
    # Linux uses Bubblewrap's private PID namespace and --new-session above.
    # Darwin instead uses the pinned Perl POSIX::setsid mechanism explicitly;
    # probing a GNU/Linux `setsid` first would make this branch depend on an
    # unrelated host utility rather than the mechanism it actually uses.
    [[ -x $trusted_perl ]] || {
      echo 'candidate isolation requires the locked Darwin Perl POSIX::setsid helper' >&2
      exit 2
    }
    exec env -i "${candidate_env[@]}" "BURLMD_CANDIDATE_SESSION=$candidate_session" \
      "BURLMD_CANDIDATE_PID_FILE=$session_dir/pid" \
      "$trusted_perl" -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- \
      "$candidate_shell" -ceu "$launcher" candidate-child "$@"
  ) &
  candidate_wait_pid=$!
  for ((pass = 0; pass < 50; pass++)); do
    [[ -s $session_dir/pid ]] && break
    kill -0 "$candidate_wait_pid" 2>/dev/null || break
    sleep 0.1 || return $?
  done
  [[ -s $session_dir/pid ]] || { echo 'candidate session did not publish a leader PID' >&2; return 1; }
  published_pid=$(<"$session_dir/pid") || return $?
  [[ $published_pid =~ ^[1-9][0-9]*$ && $published_pid == "$candidate_wait_pid" ]] || {
    echo 'candidate session published an invalid leader PID' >&2
    return 1
  }
  candidate_pid=$published_pid
}

candidate_exec() {
  local status pass
  candidate_invocation_status=
  candidate_cleanup_status=0
  # Capture startup in this parent shell without placing the multi-check
  # function in an if/!/&&/|| context. Every parent-side startup operation is
  # explicitly checked, and both real launch children restore active errexit
  # before they enter nested launch functions. A partially launched Darwin
  # child remains parent-owned through candidate_wait_pid and is reaped before
  # the original status returns.
  set +e
  start_candidate_session "$@"
  status=$?
  set -e
  if ((status != 0)); then
    candidate_invocation_status=$status
    terminate_candidate_session || candidate_cleanup_status=$?
    return "$candidate_invocation_status"
  fi
  for ((pass = 0; pass < 72000; pass++)); do
    candidate_group_alive || break
    sleep 0.1
  done
  if candidate_group_alive; then
    echo 'candidate session exceeded its bounded wait' >&2
    candidate_invocation_status=1
    terminate_candidate_session || candidate_cleanup_status=$?
    return "$candidate_invocation_status"
  fi
  # This is the only success/failure authority: `candidate_wait_pid` is the
  # trusted wrapper's direct child, so a candidate cannot forge its result.
  set +e
  wait "$candidate_wait_pid"
  status=$?
  set -e
  candidate_invocation_status=$status
  # Always sweep the process group and marker-tagged detached descendants,
  # including after a test or generator failure.
  terminate_candidate_session || candidate_cleanup_status=$?
  # Cleanup failure can't overwrite a nonzero direct-child result. A cleanup
  # failure after a successful child remains a fail-closed invocation failure.
  ((candidate_invocation_status != 0)) && return "$candidate_invocation_status"
  ((candidate_cleanup_status == 0)) || return 1
  return 0
}

# Bash disables errexit throughout a function invoked by `if`, `!`, `&&`, or
# `||`, even when that function executes `set -e`.  Invoke candidate_exec as a
# plain command instead.  Its nonzero return reaches this ERR trap, which saves
# the exact status and disables errexit only after candidate_exec has completed.
# This keeps the direct-child/session mutations in the trusted parent shell.
candidate_exec_status=0
candidate_invocation_status=
candidate_cleanup_status=0
capture_candidate_exec_status() {
  candidate_exec_status=0
  candidate_invocation_status=
  candidate_cleanup_status=0
  trap 'candidate_exec_status=$?; set +e' ERR
  candidate_exec "$@"
  candidate_exec_status=$?
  trap - ERR
  set -e
  [[ $candidate_invocation_status =~ ^(0|[1-9][0-9]{0,2})$ && $candidate_invocation_status -le 255 ]] || {
    candidate_exec_status=1
    return 1
  }
}

validate_candidate_tool_profile
non_spike_gate_guard
run_linux_native_isolation_prerequisite
prepare_candidate_dependencies
prepare_candidate_tool_path
if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  prepare_linux_candidate_closure_views
else
  prepare_linux_candidate_private_store
fi
prepare_cargokit_tool_runner
if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  m003_prepare_closure_log
fi

find "$source_root/integration_test" -type f -name '*_test.dart' -print | sed "s#^$source_root/##" | LC_ALL=C sort >"$output_root/results/integration-tests.txt"
[[ -s $output_root/results/integration-tests.txt ]] || { echo 'no integration tests discovered' >&2; exit 1; }
run_integration_files() {
  local target=$1 runtime=$2 display=$3 test_file result log json_log outcome step_id status
  while IFS= read -r test_file; do
    [[ -n $test_file ]] || continue
    # A path-derived filename collides for e.g. `a_b/test.dart` and
    # `a/b_test.dart`. Bind each outcome to a stable digest of the discovered
    # repository-relative test path instead.
    step_id=$(printf '%s' "$test_file" | sha256sum | awk '{print $1}')
    log="$output_root/results/integration-$step_id.log"
    json_log="$output_root/results/integration-$step_id.jsonl"
    if [[ -n $runtime ]]; then
      capture_candidate_exec_status env XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY="$display" GDK_BACKEND=wayland LIBGL_ALWAYS_SOFTWARE=1 flutter test --no-pub --suppress-analytics "$test_file" -d "$target" -r github --file-reporter="json:$json_log" >"$log" 2>&1
    else
      capture_candidate_exec_status flutter test --no-pub --suppress-analytics "$test_file" -d "$target" -r github --file-reporter="json:$json_log" >"$log" 2>&1
    fi
    result=$candidate_exec_status
    if ((result != 0)); then
      write_integration_outcome "$step_id" "$test_file" failed "$result" || true
      emit_candidate_failure_diagnostic "integration-$step_id" "$candidate_invocation_status"
      write_integration_outcomes_aggregate >/dev/null 2>&1 || true
      return "$result"
    fi
    if integration_report_has_successful_tests "$json_log"; then status=passed; else status=failed; fi
    write_integration_outcome "$step_id" "$test_file" "$status" "$result"
    if [[ $status == failed ]]; then
      # Reporter rejection is a semantic failure after a successful process.
      # Fail closed without inventing a nonzero process status for diagnostics.
      write_integration_outcomes_aggregate >/dev/null 2>&1 || true
      return 1
    fi
  done <"$output_root/results/integration-tests.txt"
  write_integration_outcomes_aggregate
}
record_step() {
  local id=$1 workdir=$2 command=$3 status=$4 log=$5
  jq -cn --arg id "$id" --arg workdir "$workdir" --arg command "$command" --arg status "$status" --arg log "$log" \
    '{id:$id,workdir:$workdir,command:$command,status:$status,log:$log}' >>"$output_root/results/role-steps.ndjson"
}
run_trusted_step() {
  local id=$1 workdir=$2 command=$3 required_stage=${4:-} log status
  [[ $workdir != /* && $workdir != *'..'* && $workdir != *'//' && $workdir != */ ]] || {
    echo "unsafe trusted role step workdir: $workdir" >&2; return 2;
  }
  if [[ -n $required_stage ]]; then
    [[ $ticket == BURL-O001 && $role == macos-15-arm64 && $required_stage == macos-26-arm64 ]] || {
      echo "unauthorized authenticated-stage prerequisite: $required_stage" >&2; return 2;
    }
    prepare_authenticated_pkg_stage || return 1
  elif [[ $ticket == BURL-O001 && $role == macos-15-arm64 && $command == *'handoff import'* ]]; then
    verify_authenticated_pkg_inbox || {
      echo 'BURL-O001 import lacks the immediately preceding verified macOS 26 inbox' >&2; return 1;
    }
  fi
  log="results/role-step-$id.log"
  set +e
  candidate_exec "$candidate_shell" -ceu 'cd -- "$1"; exec "$3" -ceu "$2"' managed-role-step "$candidate_execution_root/$workdir" "$command" "$candidate_shell" >"$output_root/$log" 2>&1
  status=$?
  set -e
  record_step "$id" "$workdir" "$command" "$([[ $status == 0 ]] && printf passed || printf failed)" "$log"
  if [[ -n $required_stage && $status == 0 ]]; then
    record_authenticated_pkg_inbox || return 1
  fi
  return "$status"
}
run_ci_gate() {
  local id=$1 log=$2; shift 2
  capture_candidate_exec_status "$@" >"$output_root/$log" 2>&1
  local status=$candidate_exec_status
  if ((status != 0)); then
    record_step "$id" . "$(printf '%q ' "$@")" failed "$log" || true
    emit_candidate_failure_diagnostic "$id" "$candidate_invocation_status"
    return "$status"
  fi
  record_step "$id" . "$(printf '%q ' "$@")" "$([[ $status == 0 ]] && printf passed || printf failed)" "$log"
}

validate_candidate_failure_diagnostic_contract() {
  local actual_map actual_prefix
  actual_map=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.role_execution.candidate_failure_diagnostic_gate_log_map | jq -ce .) || return 1
  actual_prefix=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.role_execution.candidate_failure_diagnostic_output_prefix | jq -er .) || return 1
  [[ $actual_prefix == 'burlmd-m003-diagnostic: ' ]] || return 1
  [[ $actual_map == '[{"gate_id":"flutter-test","relative_source_log":"results/role-step-flutter-test.log"},{"gate_id":"dart-analyze","relative_source_log":"results/role-step-dart-analyze.log"},{"gate_id":"cargo-metadata","relative_source_log":"results/role-step-cargo-metadata.log"},{"gate_id":"integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d","relative_source_log":"results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.log"},{"gate_id":"integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d","relative_source_log":"results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.log"}]' ]]
}

emit_candidate_failure_diagnostic() {
  local gate_id=$1 original_status=$2 map relative source_root capture
  [[ $ticket == BURL-M003 && $role != linux-x86_64 && $(uname) == Darwin && $original_status -ne 0 ]] || return 0
  [[ -n ${candidate_diagnostic_fd:-} ]] || return 0
  validate_candidate_failure_diagnostic_contract || return 0
  map=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.role_execution.candidate_failure_diagnostic_gate_log_map) || return 0
  relative=$(jq -er --arg gate "$gate_id" '
    [ .[] | select(.gate_id == $gate) | .relative_source_log ] |
    if length == 1 and (.[0] | type == "string") then .[0] else error("unknown diagnostic gate") end
  ' <<<"$map") || return 0
  source_root=$(realpath -e -- "$output_root") || return 0
  [[ $source_root == "$output_root" && -d $source_root && ! -L $source_root ]] || return 0
  [[ $relative == results/* && $relative != *'..'* && $relative != *'//' && $relative != */ ]] || return 0
  # Resolve and recheck the exact mapped parent below the canonical output
  # root. O_NOFOLLOW protects the final component; these checks separately
  # reject a linked or escaping parent before and after the open.
  capture=$(BURLMD_DIAGNOSTIC_GATE=$gate_id BURLMD_DIAGNOSTIC_STATUS=$original_status \
    "$trusted_perl" -MCwd=realpath -MDigest::SHA -MFile::Temp=tempfile -MFcntl=O_RDONLY,O_NONBLOCK,O_NOFOLLOW,SEEK_SET -MMIME::Base64=encode_base64 -MFcntl=:mode -e '
    my ($root, $relative, $snapshot_root) = @ARGV;
    my $results = "$root/results";
    defined(realpath($root)) && realpath($root) eq $root or exit 1;
    defined(realpath($results)) && realpath($results) eq $results or exit 1;
    S_ISDIR((lstat($results))[2]) or exit 1;
    my $source = "$root/$relative";
    sysopen(my $input, $source, O_RDONLY | O_NONBLOCK | O_NOFOLLOW) or exit 1;
    my @stat = stat($input); S_ISREG($stat[2]) or exit 1;
    my @path_stat = lstat($source);
    @path_stat && S_ISREG($path_stat[2]) && $path_stat[0] == $stat[0] && $path_stat[1] == $stat[1] or exit 1;
    defined(realpath($results)) && realpath($results) eq $results or exit 1;
    defined(realpath($source)) && realpath($source) eq $source or exit 1;
    my ($snapshot, $snapshot_path) = tempfile("candidate-failure-diagnostic.XXXXXXXX", DIR => $snapshot_root, UNLINK => 1);
    unlink($snapshot_path) or exit 1;
    binmode($input); binmode($snapshot);
    my @snapshot_stat = stat($snapshot); S_ISREG($snapshot_stat[2]) or exit 1;
    my $size = $stat[7];
    my $offset = $size > 65536 ? $size - 65536 : 0;
    sysseek($input, $offset, SEEK_SET) or exit 1;
    my $remaining = 65536;
    my $retained = 0;
    while ($remaining > 0) {
      my $read = sysread($input, my $bytes, $remaining > 8190 ? 8190 : $remaining);
      defined $read or exit 1;
      last if $read == 0;
      my $written = 0;
      while ($written < $read) {
        my $count = syswrite($snapshot, $bytes, $read - $written, $written);
        defined $count && $count > 0 or exit 1;
        $written += $count;
      }
      $retained += $read;
      $remaining -= $read;
    }
    my @after = stat($input);
    @after && $after[0] == $stat[0] && $after[1] == $stat[1] && $after[7] == $stat[7] && $after[9] == $stat[9] && $after[10] == $stat[10] or exit 1;
    my @final_path_stat = lstat($source);
    @final_path_stat && S_ISREG($final_path_stat[2]) && $final_path_stat[0] == $stat[0] && $final_path_stat[1] == $stat[1] or exit 1;
    defined(realpath($results)) && realpath($results) eq $results or exit 1;
    defined(realpath($source)) && realpath($source) eq $source or exit 1;
    my $expected = $size > 65536 ? 65536 : $size;
    $retained == $expected or exit 1;
    # Hash and encode one bounded pass over the same still-open, unlinked
    # wrapper snapshot. No later operation reopens it by candidate-visible
    # pathname or reads the source log again.
    sysseek($snapshot, 0, SEEK_SET) or exit 1;
    $remaining = $retained;
    my $sha = Digest::SHA->new(256);
    my $encoded = "";
    while ($remaining > 0) {
      my $read = sysread($snapshot, my $bytes, $remaining > 8190 ? 8190 : $remaining);
      defined $read && $read > 0 or exit 1;
      $sha->add($bytes);
      $encoded .= encode_base64($bytes, "");
      $remaining -= $read;
    }
    print "burlmd-m003-diagnostic: gate_id=$ENV{BURLMD_DIAGNOSTIC_GATE}\n";
    print "burlmd-m003-diagnostic: original_exit_status=$ENV{BURLMD_DIAGNOSTIC_STATUS}\n";
    print "burlmd-m003-diagnostic: source_log_bytes=$size\n";
    print "burlmd-m003-diagnostic: retained_tail_bytes=$retained\n";
    print "burlmd-m003-diagnostic: retained_tail_sha256=" . $sha->hexdigest . "\n";
    print "burlmd-m003-diagnostic: base64=$encoded\n";
  ' "$source_root" "$relative" "$runtime_root" 2>/dev/null) || return 0
  printf '%s\n' "$capture" >&"$candidate_diagnostic_fd" || return 0
}

ticket_root_for() {
  local requested_ticket=$1 root
  root=$(taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -er --arg id "SPK-$requested_ticket" '
      [.[] | select(.id == $id) | .path] |
      if (length == 1 and (.[0] | type == "string")) then .[0] else error("missing or ambiguous ticket root") end') || return 1
  [[ $root != /* && $root != *'..'* && $root != *'//' && $root != */ && $root != . ]] || return 1
  printf '%s' "$root"
}

prepare_authenticated_pkg_stage() {
  # BURL-O001's macOS 15 import is the one permitted cross-role input.  The
  # reusable workflow must acquire and authenticate it before this launcher is
  # called, then expose only this owned staging root.  We neither download nor
  # read a candidate-provided location here.
  [[ $ticket == BURL-O001 && $role == macos-15-arm64 ]] || return 0
  local stage_root producer_root destination member source marker members_json provenance nonce binding
  stage_root=${BURLMD_AUTHENTICATED_STAGE_ROOT:?BURL-O001 macOS 15 requires authenticated staging}
  [[ $stage_root == /* && -d $stage_root && $stage_root != "$source_root" && $stage_root != "$source_root"/* ]] || {
    echo 'authenticated staging root is missing, unsafe, or inside tested source' >&2; return 1;
  }
  producer_root=$stage_root/roles/macos-26-arm64
  [[ -d $producer_root && ! -L $producer_root ]] || { echo 'authenticated macOS 26 role stage is absent' >&2; return 1; }
  nonce=$(jq -er '.artifactNonce | select(test("^[0-9a-f]{32}$"))' "$EXPECTED_IDENTITY") || return 1
  # The consumption record is wrapper-only. Ingest and unlink it before any
  # candidate command is assembled; it is not a member of the exposed root and
  # cannot be inherited through candidate_env's env -i boundary.
  binding=${BURLMD_COMPATIBILITY_STAGE_CONSUMPTION:?BURL-O001 requires wrapper compatibility handoff}
  [[ $binding == /* && -f $binding && ! -L $binding && $binding != "$stage_root"/* ]] || { echo 'compatibility handoff is unsafe' >&2; return 1; }
  authenticated_stage_consumption=$(jq -ce . "$binding") || return 1
  rm -f -- "$binding"
  jq -e --arg nonce "$nonce" '
    .producerLineage.stageManifest.artifactNonce == $nonce and
    .producerLineage.stageManifest.producerRole == "macos-26-arm64" and
    .producerLineage.stageManifest.consumerRole == "macos-15-arm64" and
    .consumerBinding.consumerRole == "macos-15-arm64" and
    .consumerBinding.downloadedStageArtifactId == .producerLineage.stageArtifact.artifactId and
    .consumerBinding.credentialsRemoved and .consumerBinding.membersReadOnly
  ' <<<"$authenticated_stage_consumption" >/dev/null || { echo 'compatibility handoff is invalid or substituted' >&2; return 1; }
  [[ $(find "$stage_root" -xdev -type f -print | sed "s#^$stage_root/##" | LC_ALL=C sort) == $'roles/macos-26-arm64/handoff/outbox/macos-current-construction.sha256\nroles/macos-26-arm64/handoff/outbox/macos-current-construction.tar.zst' ]] || { echo 'authenticated stage root exposes non-member bytes' >&2; return 1; }
  destination=$candidate_execution_root/.constitution/prototypes/packaging/managed-evidence-coordinator/roles/macos-26-arm64
  # A previous candidate attempt must never supply the next import's inbox.
  # Recreate the trusted staging destination from the verified-stage bytes.
  rm -rf -- "$destination"
  mkdir -p "$destination/handoff/outbox"
  members_json='[]'
  while IFS= read -r member; do
    [[ $member == handoff/outbox/* && $member != *'..'* && $member != *'//' ]] || return 1
    source=$producer_root/$member
    [[ -f $source && ! -L $source ]] || { echo "authenticated stage member is missing or not regular: $member" >&2; return 1; }
    install -m 0444 "$source" "$destination/$member"
    members_json=$(jq -cn --argjson old "$members_json" --arg name "$member" \
      --arg hash "$(sha256sum "$source" | awk '{print $1}')" --argjson bytes "$(wc -c <"$source")" \
      '$old + [{name:$name,sha256:$hash,bytes:$bytes}]')
  done < <(taplo get --file-path "$contract" --output-format json 'ci_bootstrap.role_prerequisites."BURL-O001-macos-archive".required_members' | jq -er '.[]')
  marker=$output_root/results/authenticated-stage-pkg-macos-26.json
  jq -cn --arg sourceRole macos-26-arm64 --argjson members "$members_json" \
    '{sourceRole:$sourceRole,interface:"authenticated-producer-stage-v1",members:$members}' >"$marker"
}

record_authenticated_pkg_inbox() {
  local marker=$output_root/results/authenticated-stage-pkg-macos-26.json inbox member source staged expected actual
  [[ -f $marker ]] || return 1
  inbox=$candidate_execution_root/.constitution/prototypes/packaging/handoff/current-inbox
  [[ -d $inbox && ! -L $inbox ]] || return 1
  while IFS= read -r member; do
    source=$candidate_execution_root/.constitution/prototypes/packaging/managed-evidence-coordinator/roles/macos-26-arm64/$member
    staged=$inbox/$(basename "$member")
    [[ -f $source && ! -L $source && -f $staged && ! -L $staged ]] || return 1
    expected=$(sha256sum "$source" | awk '{print $1}')
    actual=$(sha256sum "$staged" | awk '{print $1}')
    [[ $actual == "$expected" ]] || { echo "authenticated inbox member was substituted: $member" >&2; return 1; }
  done < <(jq -r '.members[].name' "$marker")
  jq -c '. + {currentInboxCreatedFromVerifiedStage:true}' "$marker" >"$marker.next" && mv -- "$marker.next" "$marker"
}

verify_authenticated_pkg_inbox() {
  local marker
  marker=$output_root/results/authenticated-stage-pkg-macos-26.json
  [[ -f $marker ]] || return 1
  jq -e '.currentInboxCreatedFromVerifiedStage == true' "$marker" >/dev/null || return 1
  record_authenticated_pkg_inbox
}

contract_output_specs() {
  # These are the contract's producer flags only.  In particular, `--artifact`
  # is an input/attachment assertion in several prototype tools, not a blanket
  # export permission.  A candidate cannot turn one of those inputs into an
  # unreviewed bundle member merely by placing a file at the same path.
  jq -r '
    .[] as $step | $step.command |
    scan("--(?:output|stdout|stderr|copy-artifact-to|success-marker|handoff-bundle|handoff-sha256|sha256-output|output-archive|output-dir|append-run)[[:space:]]+([^[:space:]]+)")[0] |
    [$step.workdir, .] | @tsv
  ' "$output_root/results/role-steps.json" | LC_ALL=C sort -u
}

copy_contract_file() {
  local source=$1 path source_dir canonical destination artifact_root
  [[ -f $source && ! -L $source ]] || { echo "declared role artifact missing: $source" >&2; return 1; }
  source_dir=$(cd "$(dirname "$source")" && pwd -P)
  canonical=$source_dir/$(basename "$source")
  artifact_root=${candidate_linux_writable_ticket_root:-$candidate_execution_root/$ticket_root}
  [[ $canonical == "$artifact_root/"* ]] || { echo "declared role artifact escapes ticket root: $path" >&2; return 1; }
  destination=${canonical#"$artifact_root/"}
  [[ $destination != /* && $destination != *'..'* && $destination != *'//' ]] || return 1
  mkdir -p "$output_root/$(dirname "$destination")"
  cp -- "$canonical" "$output_root/$destination"
}

copy_declared_role_artifacts() {
  local path workdir source entry canonical relative
  # The command text comes from the trusted contract. Normalize every declared
  # producer output below the ticket root, including the contract's explicit
  # runs/, logs/, artifacts/, results/, and handoff/ roots. Copy neither a
  # discovered/globbed candidate file nor an arbitrary sibling of an output.
  while IFS=$'\t' read -r workdir path; do
    [[ -n $path && $path != /* && $path != *'//' ]] || return 1
    [[ $workdir != /* && $workdir != *'..'* && $workdir != *'//' && $workdir != */ ]] || return 1
    source=$candidate_execution_root/${workdir#./}/$path
    # Output parents may be created only inside the private overlay, so do not
    # require their read-only source counterpart to exist. `realpath -m`
    # normalizes the trusted command path without dereferencing an output.
    canonical=$(realpath -m -- "$source") || return 1
    if [[ -n $candidate_linux_writable_ticket_root ]]; then
      [[ $canonical == "$candidate_execution_root/$ticket_root/"* ]] || {
        echo "declared role output escapes Linux ticket root: $path" >&2; return 1;
      }
      relative=${canonical#"$candidate_execution_root/$ticket_root/"}
      source=$candidate_linux_writable_ticket_root/$relative
    fi
    if [[ -d $source && ! -L $source ]]; then
      # `--output-dir` is the only directory-valued producer contract. Its
      # regular descendants remain manifest-named exact members; links and
      # special files are rejected rather than silently followed or omitted.
      while IFS= read -r -d '' entry; do
        copy_contract_file "$entry" "$path"
      done < <(find "$source" -xdev -type f -print0 | LC_ALL=C sort -z)
      if find "$source" -xdev \( -type l -o ! -type f -a ! -type d \) -print -quit | grep -q .; then
        echo "declared role output directory contains an unsafe member: $source" >&2
        return 1
      fi
    else
      copy_contract_file "$source" "$path"
    fi
  done < <(contract_output_specs)
}

observe_linux_private_sway_viewport() {
  local runtime socket display sway_socket output_json sway_pid pass
  runtime="$output_root/wayland-runtime"
  mkdir -p "$runtime"; chmod 700 "$runtime"
  XDG_RUNTIME_DIR="$runtime" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 \
    sway --unsupported-gpu >"$output_root/results/sway.log" 2>&1 &
  sway_pid=$!
  # Register immediately after the trusted compositor starts. If socket setup,
  # viewport validation, or a later candidate integration gate exits early,
  # the role-level EXIT cleanup still owns this exact process.
  LINUX_VIEWPORT_SWAY_PID=$sway_pid
  trap 'cleanup_role_exit "$?"' EXIT
  for ((pass = 0; pass < 100; pass++)); do
    for socket in "$runtime"/wayland-*; do
      [[ -S $socket ]] && break 2
    done
    kill -0 "$sway_pid" 2>/dev/null || break
    sleep 0.1
  done
  [[ -n ${socket:-} && -S $socket ]] || {
    kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true
    echo 'private headless Sway did not create a Wayland socket' >&2; return 1
  }
  display=${socket##*/}
  if ! XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY="$display" swaymsg output HEADLESS-1 mode 1920x1080@60Hz >"$output_root/results/role-step-sway-mode.log" 2>&1; then
    kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true
    return 1
  fi
  output_json=$(XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY="$display" swaymsg -t get_outputs -r) || {
    kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true
    return 1
  }
  if ! jq -e '
    length == 1 and .[0].rect.width == 1920 and .[0].rect.height == 1080 and
    (.[] | .current_mode.refresh // 0) == 60000
  ' <<<"$output_json" >"$output_root/results/viewport-linux.json"; then
    kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true
    echo 'private Sway logical viewport differs from the trusted profile' >&2; return 1
  fi
  # BURL-M003's Linux integration suite itself runs against this owned compositor.
  LINUX_VIEWPORT_RUNTIME=$runtime
  LINUX_VIEWPORT_DISPLAY=$display
  viewport_verified=true
}

stop_linux_private_sway_viewport() {
  [[ -n ${LINUX_VIEWPORT_SWAY_PID:-} ]] || return 0
  kill "$LINUX_VIEWPORT_SWAY_PID" 2>/dev/null || true
  wait "$LINUX_VIEWPORT_SWAY_PID" 2>/dev/null || true
  unset LINUX_VIEWPORT_RUNTIME LINUX_VIEWPORT_DISPLAY LINUX_VIEWPORT_SWAY_PID
}

observe_macos_flutter_viewport() {
  # This is intentionally a trusted, disposable Flutter app rather than a
  # candidate test setting a WidgetTester viewport. The launched macOS app
  # reports its real View logical size after the first rendered frame. A hosted
  # GUI image that cannot provide the exact reference viewport rejects the role
  # instead of inheriting `true` from the profile.
  local probe result pid probe_app_pid pass status
  probe="$output_root/trusted-macos-viewport-probe"
  result="$output_root/results/viewport-macos.json"
  rm -rf -- "$probe"
  flutter create --no-pub --platforms=macos --project-name burlmd_viewport_probe "$probe" >"$output_root/results/viewport-macos-create.log" 2>&1 || return 1
  mkdir -p "$probe/lib"
  printf '%s\n' \
    "import 'dart:convert';" \
    "import 'dart:io';" \
    "import 'package:flutter/services.dart';" \
    "import 'package:flutter/widgets.dart';" \
    "const _result = String.fromEnvironment('BURLMD_VIEWPORT_RESULT');" \
    "void main() => runApp(const _Probe());" \
    "class _Probe extends StatefulWidget { const _Probe(); @override State<_Probe> createState() => _ProbeState(); }" \
    "class _ProbeState extends State<_Probe> { static const _platform = MethodChannel('burlmd.viewport.probe'); @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) async { await Future<void>.delayed(const Duration(seconds: 1)); final view = View.of(context); final ratio = view.devicePixelRatio; final size = view.physicalSize; final refresh = await _platform.invokeMethod<num>('refreshHz'); File(_result).writeAsStringSync(jsonEncode({'width': size.width / ratio, 'height': size.height / ratio, 'refreshHz': refresh, 'devicePixelRatio': ratio})); }); } @override Widget build(BuildContext context) => const SizedBox.expand(); }" \
    >"$probe/lib/main.dart"
  printf '%s\n' \
    'import Cocoa' \
    'import FlutterMacOS' \
    'class MainFlutterWindow: NSWindow {' \
    '  override func awakeFromNib() {' \
    '    let controller = FlutterViewController()' \
    '    contentViewController = controller' \
    '    RegisterGeneratedPlugins(registry: controller)' \
    "    let channel = FlutterMethodChannel(name: \"burlmd.viewport.probe\", binaryMessenger: controller.engine.binaryMessenger)" \
    '    channel.setMethodCallHandler { call, result in' \
    '      guard call.method == "refreshHz", let hertz = self.screen?.maximumFramesPerSecond else { result(FlutterMethodNotImplemented); return }' \
    '      result(hertz)' \
    '    }' \
    '    super.awakeFromNib()' \
    '    DispatchQueue.main.async { self.toggleFullScreen(nil) }' \
    '  }' \
    '}' \
    >"$probe/macos/Runner/MainFlutterWindow.swift"
  flutter run -d macos --no-hot --pid-file "$probe/flutter.pid" --dart-define="BURLMD_VIEWPORT_RESULT=$result" >"$output_root/results/viewport-macos-run.log" 2>&1 &
  pid=$!
  for ((pass = 0; pass < 300; pass++)); do
    [[ -s $result ]] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if [[ -s $probe/flutter.pid ]]; then
    probe_app_pid=$(<"$probe/flutter.pid")
    [[ $probe_app_pid =~ ^[1-9][0-9]*$ ]] && kill -TERM "$probe_app_pid" 2>/dev/null || true
  fi
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || status=$?
  rm -rf -- "$probe"
  [[ -s $result ]] || { echo 'trusted macOS Flutter probe did not publish a viewport observation' >&2; return 1; }
  jq -e '
    (.width | type == "number" and . == 1920) and
    (.height | type == "number" and . == 1080) and
    (.refreshHz | type == "number" and . == 60) and
    (.devicePixelRatio | type == "number" and . > 0)
  ' "$result" >/dev/null || { echo 'trusted macOS Flutter logical viewport differs from the reference profile' >&2; return 1; }
  viewport_verified=true
}
candidate_phase() {
  local step_count step id workdir command required_stage
  cd "$candidate_execution_root"
  : >"$output_root/results/role-steps.ndjson"
  if [[ $ticket == BURL-M003 ]]; then
    # BURL-M003's trusted phase is declared by ci_bootstrap.candidate_phase and
    # role_phase rather than a Spike verification_steps array.
    # Keep this order identical to the executable ticket contract.  The
    # generated-byte check must run before Dart/Flutter tests, and the Linux
    # containment assertion remains the final gate after every integration
    # file has produced its own outcome.
    if [[ $role == linux-x86_64 ]]; then
      # The raw-39 ordered session plan is the sole Linux candidate path.  It
      # builds and executes each full Bubblewrap argv once, preserves the
      # parent-side records, and hands both integration sessions to the
      # in-namespace supervisor instead of an external parent Sway process.
      prepare_generated_bindings_workspace >/dev/null
      m003_prepare_linux_integration_report_directory
      m003_run_session 1 generated-bindings base generated-bindings \
        /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash /trusted/scripts/check-generated-bindings.sh --root /candidate/writable/generated-bindings-check
      record_step generated-bindings . 'raw-39 managed base session' passed results/role-step-generated-bindings.log
      m003_run_session 2 flutter-test base flutter-test flutter test --no-pub --suppress-analytics
      record_step flutter-test . 'raw-39 managed base session' passed results/role-step-flutter-test.log
      m003_run_session 3 dart-analyze base dart-analyze dart --suppress-analytics analyze lib test integration_test test_driver
      record_step dart-analyze . 'raw-39 managed base session' passed results/role-step-dart-analyze.log
      m003_run_session 4 cargo-metadata base cargo-metadata cargo metadata --offline --locked --manifest-path rust/Cargo.toml --format-version 1
      record_step cargo-metadata . 'raw-39 managed base session' passed results/role-step-cargo-metadata.log
      m003_run_session 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d integration integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d \
        flutter test --no-pub --suppress-analytics integration_test/production_host_flow_test.dart -d linux -r github --file-reporter=json:/candidate/writable/results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.jsonl
      if m003_consume_linux_integration_report 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d integration_test/production_host_flow_test.dart; then
        record_step integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d . 'raw-39 managed integration session' passed results/role-step-integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.log
      else
        record_step integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d . 'raw-39 managed integration session' failed results/role-step-integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.log
        return 1
      fi
      m003_run_session 6 integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d integration integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d \
        flutter test --no-pub --suppress-analytics integration_test/shell_flow_test.dart -d linux -r github --file-reporter=json:/candidate/writable/results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.jsonl
      if m003_consume_linux_integration_report 6 integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d integration_test/shell_flow_test.dart; then
        record_step integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d . 'raw-39 managed integration session' passed results/role-step-integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.log
      else
        record_step integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d . 'raw-39 managed integration session' failed results/role-step-integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.log
        return 1
      fi
      write_integration_outcomes_aggregate
      m003_run_session 7 managed-isolation base managed-isolation \
        /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash /trusted/scripts/assert-managed-evidence-isolation.sh --contract /trusted/.constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2
      record_step managed-isolation . 'raw-39 managed base session' passed results/role-step-managed-isolation.log
      m003_finish_log
    else
      # Flutter 3.44.3 documents --no-pub and --suppress-analytics on `flutter
      # test`; preparation already enforced the lockfile before network denial.
      run_ci_gate flutter-test results/role-step-flutter-test.log flutter test --no-pub --suppress-analytics
      run_ci_gate dart-analyze results/role-step-dart-analyze.log dart --suppress-analytics analyze lib test integration_test test_driver
      run_ci_gate cargo-metadata results/role-step-cargo-metadata.log cargo metadata --offline --locked --manifest-path rust/Cargo.toml --format-version 1
    fi
  else
    ticket_root=$(ticket_root_for "$ticket") || { echo "missing trusted ticket root for $ticket" >&2; return 1; }
    role_steps_for "$ticket" "$role" >"$output_root/results/role-steps.json"
    step_count=$(jq 'length' "$output_root/results/role-steps.json")
    ((step_count > 0)) || { echo "trusted contract has no verification_steps for $ticket/$role" >&2; return 1; }
    while IFS= read -r step; do
      id=$(jq -r '((.value.run_id // "shared") + "-" + (.key | tostring))' <<<"$step")
      workdir=$(jq -er '.value.workdir | strings' <<<"$step")
      command=$(jq -er '.value.command | strings' <<<"$step")
      required_stage=$(jq -r '.value.requires_authenticated_stage_role // empty' <<<"$step")
      run_trusted_step "$id" "$workdir" "$command" "$required_stage"
    done < <(jq -c 'to_entries[]' "$output_root/results/role-steps.json")
    copy_declared_role_artifacts
  fi
  if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
    # The two raw integration sessions have already run under their own
    # authority-backed runtime leaves.  The parent never starts Sway.
    :
    # The precompiled Cargokit runner is a build-only helper. Remove it before
    # analysis so Dart does not inspect its private path dependency as project
    # source; the immutable Cargokit tree and prepared Pub cache remain intact.
    rm -rf -- "$candidate_root/writable/build/linux/x64/debug/plugins/rust/cargokit_build/tool"
  elif [[ $ticket == BURL-M003 ]]; then
    run_integration_files macos '' ''
  fi
  if [[ $ticket == BURL-M003 ]]; then
    jq -s '.' "$output_root/results/role-steps.ndjson" >"$output_root/results/role-steps.json"
  fi
}
if [[ $ticket == BURL-M003 && $role != linux-x86_64 && $(uname) == Darwin ]]; then
  validate_candidate_failure_diagnostic_contract || {
    echo 'trusted candidate failure diagnostic contract is invalid' >&2
    exit 2
  }
  exec {candidate_diagnostic_fd}>&1
fi
candidate_phase >"$output_root/results/candidate.log" 2>&1
if [[ -n ${candidate_diagnostic_fd:-} ]]; then
  eval "exec ${candidate_diagnostic_fd}>&-"
  candidate_diagnostic_fd=
fi
if [[ $(uname) == Darwin && -n ${canonical_stage:-} ]]; then
  authenticated_stage_after=$(find "$canonical_stage" -xdev -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
  [[ $authenticated_stage_after == "$authenticated_stage_before" ]] || {
    echo 'authenticated macOS input mutated during candidate execution' >&2; exit 1;
  }
fi
if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then
  jq -s '.' "$output_root/results/role-steps.ndjson" >"$output_root/results/role-steps.json"
fi
# BURL-M003's managed profiles are explicitly non-authoritative: it uses its
# private Sway environment for functional integration but does not claim a
# host-display observation. Every viewport-bound Spike must instead own and
# validate an actual platform observation here.
if [[ $ticket == BURL-M003 ]]; then
  viewport_verified=false
elif [[ $viewport_requires_exact_probe == true ]]; then
  case $role in
    linux-x86_64) observe_linux_private_sway_viewport; stop_linux_private_sway_viewport;;
    macos-26-arm64) observe_macos_flutter_viewport;;
    macos-15-arm64) echo 'macOS 15 is functional compatibility-only and cannot establish viewport evidence' >&2; exit 1;;
    *) exit 2;;
  esac
fi

case $(uname -m) in x86_64) observed_arch=x86_64;; arm64|aarch64) observed_arch=aarch64;; *) echo 'unsupported runner architecture' >&2; exit 1;; esac
if [[ $(uname) == Darwin ]]; then
  observed_cpus=$(sysctl -n hw.logicalcpu)
  observed_memory=$(sysctl -n hw.memsize)
  observed_os=macos
  observed_os_major=$(sw_vers -productVersion | awk -F. '$1 ~ /^[0-9]+$/ {print $1; exit}')
  os_release=$(sw_vers | tr '\n' ';' | sed 's/;$//')
  # `diskutil info` accepts a device, not an arbitrary directory beneath a
  # mounted volume. `df -P <path>` deterministically reports the filesystem
  # containing this canonical output root; use its BSD device field as the
  # documented `diskutil info [-plist] device` operand.
  macos_filesystem_device=$(/bin/df -P "$canonical_output" | awk 'NR == 2 { print $1; exit }') || {
    echo 'macOS filesystem mount resolution failed' >&2; exit 1;
  }
  [[ $macos_filesystem_device =~ ^/dev/disk[0-9]+(s[0-9]+)*$ ]] || {
    echo 'macOS filesystem mount resolution returned an invalid device' >&2; exit 1;
  }
  filesystem=$(/usr/sbin/diskutil info -plist "$macos_filesystem_device" | /usr/bin/plutil -extract FilesystemType raw -o - -) || {
    echo 'macOS filesystem observation failed' >&2; exit 1;
  }
else
  observed_cpus=$(getconf _NPROCESSORS_ONLN)
  observed_memory=$(awk '/MemTotal:/ {printf "%.0f", $2 * 1024}' /proc/meminfo)
  observed_os=linux
  observed_os_major=
  os_release=$(tr '\n' ';' </etc/os-release | sed 's/;$//')
  filesystem=$(findmnt -n -o FSTYPE -T "$output_root") || {
    echo 'Linux filesystem observation failed' >&2; exit 1;
  }
fi
[[ -n $filesystem && $filesystem != *$'\n'* && $filesystem != *$'\r'* ]] || {
  echo 'filesystem observation was empty or malformed' >&2; exit 1;
}
observed_storage=$(df -Pk "$output_root" | awk 'NR==2 {printf "%.0f", $4 * 1024}')
documented_arch=$(jq -er '.architecture' <<<"$documented_environment")
documented_os=$(jq -er '.os' <<<"$documented_environment")
documented_os_major=$(jq -r '.os_major // empty' <<<"$documented_environment")
documented_cpu_model_contains=$(jq -r '.cpu_model_contains // empty' <<<"$documented_environment")
documented_cpus=$(jq -er '.logical_cpu_count' <<<"$documented_environment")
documented_memory=$(jq -er '.memory_bytes' <<<"$documented_environment")
documented_storage=$(jq -er '.storage_bytes' <<<"$documented_environment")
[[ $observed_arch == "$documented_arch" ]] || {
  echo "observed architecture $observed_arch does not match documented $documented_arch" >&2; exit 1;
}
[[ $observed_os == "$documented_os" ]] || {
  echo "observed OS $observed_os does not match documented $documented_os" >&2; exit 1;
}
if [[ -n $documented_os_major ]]; then
  [[ $observed_os_major == "$documented_os_major" ]] || {
    echo "observed OS major $observed_os_major does not match documented $documented_os_major" >&2; exit 1;
  }
fi
if [[ -n $documented_cpu_model_contains ]]; then
  [[ $cpu_model == *"$documented_cpu_model_contains"* ]] || {
    echo "observed CPU model does not contain documented $documented_cpu_model_contains" >&2; exit 1;
  }
fi
[[ $observed_cpus =~ ^[1-9][0-9]*$ && $observed_memory =~ ^[1-9][0-9]*$ && $observed_storage =~ ^[1-9][0-9]*$ ]] || {
  echo 'host observation was incomplete' >&2; exit 1;
}
[[ $observed_cpus == "$documented_cpus" ]] || {
  echo "observed logical CPU count $observed_cpus does not match documented $documented_cpus" >&2; exit 1;
}
export ROLE="$role" RUNNER_LABEL="$runner" ARCH="$observed_arch" CPUS="$observed_cpus" MEMORY="$documented_memory" STORAGE="$documented_storage" CLASSES="$classes" OUTPUT_ROOT="$output_root"
if [[ $ticket == BURL-M003 ]]; then
  mapfile -t bundle_members < <(find "$output_root/results" -type f -print | LC_ALL=C sort | sed "s#^$output_root/##")
  if [[ $role == linux-x86_64 ]]; then
    [[ $m003_log == "$output_root/logs/burl-m003-linux-closure-view.log" && -f $m003_log && ! -L $m003_log ]] || {
      echo 'BURL-M003 Linux closure-view log is missing or unsafe' >&2; exit 1;
    }
    bundle_members+=(logs/burl-m003-linux-closure-view.log)
  fi
else
  mapfile -t bundle_members < <(find "$output_root" -type f -print | LC_ALL=C sort |
    sed "s#^$output_root/##" |
    awk '$0 != "ci-role-evidence.json" && $0 != "ci-role-evidence.tar.zst" && $0 !~ /^candidate-environment\// && ($0 !~ /^results\// || $0 == "results/viewport-linux.json" || $0 == "results/viewport-macos.json" || $0 == "results/viewport-macos-run.log" || $0 == "results/macos-bounded-cleanup.json")')
fi
(( ${#bundle_members[@]} > 0 )) || { echo 'role produced no declared bundle artifacts' >&2; exit 1; }
artifacts=$(for relative in "${bundle_members[@]}"; do
  jq -cn --arg name "$relative" --arg hash "$(sha256sum "$output_root/$relative" | awk '{print $1}')" --argjson bytes "$(wc -c <"$output_root/$relative")" '{name:$name,bytes:$bytes,sha256:$hash}'
done | jq -sc .)
gates=$(printf '%s' "$classes" | jq -Rc 'split(",") | reduce .[] as $item ({}; .[$item]=true)')
identity_sha=$(sha256sum "$EXPECTED_IDENTITY" | awk '{print $1}')
compatibility_stage=null
if [[ $ticket == BURL-O001 && $role == macos-15-arm64 ]]; then
  [[ -n ${authenticated_stage_consumption:-} ]] || { echo 'macOS 15 BURL-O001 consumption record is absent' >&2; exit 1; }
  compatibility_stage=$authenticated_stage_consumption
fi
jq -cn --slurpfile identity "$EXPECTED_IDENTITY" --argjson compatibilityStage "$compatibility_stage" --arg digest "$identity_sha" --arg role "$role" --arg runner "$runner" --arg arch "$observed_arch" --arg cpu "$cpu_model" --arg os "$os_release" --arg filesystem "$filesystem" --arg imageOs "$image_os" --arg imageVersion "$image_version" --arg flutter "$(flutter --version | head -1)" --arg dart "$(dart --version 2>&1)" --argjson viewportVerified "$viewport_verified" --argjson observedCpus "$observed_cpus" --argjson documentedMemory "$documented_memory" --argjson documentedStorage "$documented_storage" --argjson observedMemory "$observed_memory" --argjson observedStorage "$observed_storage" --argjson classes "$class_json" --argjson gates "$gates" --argjson artifacts "$artifacts" --argjson version "$role_schema_version" '
  {schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,
   roleEvidence:{role:$role,capturedIdentity:($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:$runner,imageOS:$imageOs,imageVersion:$imageVersion,osRelease:$os,architecture:$arch,cpuModel:$cpu,logicalCpuCount:$observedCpus,documentedMemoryBytes:$documentedMemory,documentedStorageBytes:$documentedStorage,observedMemoryBytes:$observedMemory,observedStorageAvailableBytes:$observedStorage,filesystem:$filesystem},viewport:{width:1920,height:1080,refreshHz:60,verified:$viewportVerified},evidenceClasses:$classes,gates:$gates,toolchain:{flutter:$flutter,dart:$dart},internalArtifacts:$artifacts,compatibilityStage:$compatibilityStage}}' >"$output_root/ci-role-evidence.json"
check-jsonschema --schemafile "$role_schema" "$output_root/ci-role-evidence.json"
(cd "$output_root" && tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -I 'zstd -19 --no-progress' -cf ci-role-evidence.tar.zst ci-role-evidence.json "${bundle_members[@]}")
if [[ $(uname) == Darwin && -n ${canonical_stage:-} ]]; then
  authenticated_stage_after=$(find "$canonical_stage" -xdev -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
  [[ $authenticated_stage_after == "$authenticated_stage_before" ]] || {
    echo 'authenticated macOS input mutated before upload' >&2; exit 1;
  }
fi
