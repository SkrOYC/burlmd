#!/usr/bin/env bash
# Trusted workflow helper. Candidate source is data; this helper always comes
# from the workflow-signer checkout.
set -euo pipefail

role=${1:?role}; source_root=${2:?tested source}; output_root=${3:?output root}
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
script_root=$(cd "$(dirname "$0")/.." && pwd -P)
role_schema=$script_root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json
contract=$script_root/.constitution/tech-spec/contracts/provisional-spikes.toml
[[ -f $role_schema && -f $contract ]] || { echo 'trusted role schema or contract is missing' >&2; exit 2; }
command -v taplo >/dev/null || { echo 'locked taplo is required for contract parsing' >&2; exit 2; }
command -v check-jsonschema >/dev/null || { echo 'locked check-jsonschema is required for manifest validation' >&2; exit 2; }
role_schema_version=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$role_schema")
contract_role_schema_version=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.ci_role_evidence_schema_version | jq -er '.')
[[ $role_schema_version == "$contract_role_schema_version" ]] || { echo 'role schema and contract versions disagree' >&2; exit 2; }
ticket=$(jq -er '.ticketIdentity | strings | select(. == "CI-M003" or . == "AST-H001" or . == "PATH-H002" or . == "ASSET-I001" or . == "GIT-L001" or . == "PKG-M001")' "${EXPECTED_IDENTITY:?EXPECTED_IDENTITY is required}")
expected_source_sha=$(jq -er '.testedSourceSha | strings | select(test("^[0-9a-f]{40}$"))' "$EXPECTED_IDENTITY")
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
profile_for() { taplo get --file-path "$contract" --output-format json "ci_bootstrap.ticket_evidence_profiles.\"$1\".\"$2\"" | jq -ce .; }
reference_profile_for() {
  case $1 in
    linux-x86_64) printf '%s' github-ubuntu-24_04-x86_64;;
    macos-26-arm64) printf '%s' github-macos-26-arm64;;
    macos-15-arm64) printf '%s' github-macos-15-arm64;;
    *) return 2;;
  esac
}
# `verification_steps` are anchor-owned TOML, not candidate configuration. A
# platform role runs only its own explicitly labelled step plus unlabelled
# shared checks. CI-M003 has no Spike entry; its bootstrap checks are recorded
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
  [[ $requested_ticket == CI-M003 ]] && { jq -cn '[]'; return 0; }
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
mkdir -p "$output_root/results"
case $role in
  linux-x86_64) runner=ubuntu-24.04;;
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
documented_environment=$(taplo get --file-path "$contract" --output-format json "reference_profiles.$reference_profile" | jq -ce '{runner_label,architecture,logical_cpu_count,memory_bytes,storage_bytes,logical_viewport_width,logical_viewport_height,logical_viewport_refresh_hz}') || {
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
candidate_status_file=
candidate_teardown_lock=
candidate_linux_namespace=false
candidate_linux_closure_prepared=false
candidate_linux_closure_paths=()
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

prepare_candidate_dependencies() {
  local pub_lock_before cargo_lock_before cargokit_pub_lock cargokit_pub_lock_before manifest manifest_dir resolved_manifest pub_directory pub_lock spike_root resolved_root dependency_kind dependency_path dependency target link
  local -a candidate_dependency_specs
  candidate_workspace="$candidate_root/workspace"
  # The authenticated checkout remains immutable candidate input. Work that
  # Flutter/Cargo must generate is directed to this disposable copy and later
  # mounted read-only except for the narrow generated/output roots below.
  cp -a -- "$source_root/." "$candidate_workspace"
  [[ -d $candidate_workspace/.git && ! -L $candidate_workspace/.git ]] || {
    echo 'candidate workspace copy lost Git metadata' >&2; return 1;
  }
  if [[ $ticket == CI-M003 ]]; then
    validate_pub_lock_dependencies
    validate_cargo_lock_dependencies
    pub_lock_before=$(sha256sum "$candidate_workspace/pubspec.lock" | awk '{print $1}')
    cargo_lock_before=$(sha256sum "$candidate_workspace/rust/Cargo.lock" | awk '{print $1}')
  # `flutter pub get --enforce-lockfile` is available in the installed Flutter
  # 3.44.3/Dart 3.12.2 toolchain (verified from its current --help surface).
  # Its only networked phase has a fresh owned HOME/cache and no inherited
  # GitHub, SSH, registry, or cloud capability. `--no-precompile` prevents a
  # dependency fetch from running package executables.
    env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
    XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
    XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
    CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
      flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace"
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
    env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" \
    XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" \
    XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" \
    CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 \
      dart pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace/rust_builder/cargokit/build_tool"
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
  if [[ $ticket != CI-M003 ]]; then
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
          env -i PATH="$PATH" HOME="$candidate_root/prepared/home" TMPDIR="$candidate_root/tmp" XDG_CACHE_HOME="$candidate_root/prepared/home/xdg-cache" XDG_CONFIG_HOME="$candidate_root/prepared/home/xdg-config" XDG_DATA_HOME="$candidate_root/prepared/home/xdg-data" PUB_CACHE="$candidate_root/prepared/pub-cache" CARGO_HOME="$candidate_root/prepared/cargo-home" RUSTUP_HOME="$candidate_root/prepared/home/rustup" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never LC_ALL=C.UTF-8 LANG=C.UTF-8 flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$pub_directory"
          [[ $(sha256sum "$pub_lock" | awk '{print $1}') == "$pub_lock_before" ]] || { echo "candidate Pub fetch changed its lockfile: $dependency_path" >&2; return 1; }
          ;;
      esac
    done
  fi
  # Preparation is complete before a candidate can run.  Linux mounts these
  # exact Pub/Cargo caches read-only below; only explicitly named generated
  # roots are writable.  The disposable execution tree is needed for CI-M003,
  # whose Flutter/Cargo gates generate project files under otherwise immutable
  # source. Spike commands retain their contract-scoped source write roots.
  if [[ $ticket != CI-M003 ]]; then
    candidate_execution_root=$source_root
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
  fi
  candidate_execution_root=$candidate_workspace
  if [[ $role == linux-x86_64 ]]; then
    # Flutter's Linux CMake files refer to the generated plugin symlinks under
    # linux/flutter/ephemeral. Preserve that generated tree in the sole
    # writable overlay, then rewrite only absolute source/cache targets for
    # their private Bubblewrap mount points.
    cp -a -- "$candidate_execution_root/linux/flutter/ephemeral/." "$candidate_root/writable/linux-flutter-ephemeral/"
    cp -a -- "$candidate_execution_root/lib/l10n/generated/." "$candidate_root/writable/l10n-generated/"
    cp -a -- "$candidate_execution_root/rust_builder/cargokit/." "$candidate_root/writable/rust-builder-cargokit/"
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || return 1
      case $target in
        "$candidate_execution_root"/*) ln -sfn "/source/${target#"$candidate_execution_root/"}" "$link";;
        "$candidate_root/prepared/pub-cache"/*) ln -sfn "/candidate/prepared/pub-cache/${target#"$candidate_root/prepared/pub-cache/"}" "$link";;
      esac
    done < <(find "$candidate_root/writable/linux-flutter-ephemeral" -type l -print0)
  fi
}

prepare_generated_bindings_workspace() {
  local check_root
  [[ $role == linux-x86_64 && $ticket == CI-M003 ]] || return 0
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
  [[ $role == linux-x86_64 && $ticket == CI-M003 ]] || return 0
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
  [[ -n $candidate_pid ]] && kill -0 -- "-$candidate_pid" 2>/dev/null
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
  [[ -n $candidate_teardown_lock && -f $candidate_teardown_lock ]] || {
    echo 'Linux candidate namespace did not publish its teardown lock' >&2
    return 1
  }
  # Bubblewrap owns this lock for the full lifetime of its PID namespace. An
  # exclusive acquisition after its host wrapper returns proves its reaper and
  # namespace are gone before any role output can be packaged.
  flock -n "$candidate_teardown_lock" true || {
    echo 'Linux candidate namespace teardown lock is still held' >&2
    return 1
  }
}

terminate_candidate_session() {
  local pass pid had_known_processes=false
  [[ -n $candidate_pid ]] || return 0
  if [[ $candidate_linux_namespace == true ]]; then
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
    candidate_status_file=
    candidate_teardown_lock=
    candidate_linux_namespace=false
    return 0
  fi
  candidate_has_survivors && had_known_processes=true
  # TERM gives Flutter and its test device a chance to stop cleanly.  Do not
  # depend on GNU timeout: the bounded polling works on the hosted macOS shell.
  kill -TERM -- "-$candidate_pid" 2>/dev/null || true
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
    kill -KILL -- "-$candidate_pid" 2>/dev/null || true
    while IFS= read -r pid; do
      [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -KILL "$pid" 2>/dev/null || true
    done < <(candidate_session_pids)
    for ((pass = 0; pass < 20; pass++)); do
      candidate_has_survivors || break
      sleep 0.1
    done
  fi
  [[ -z $candidate_wait_pid ]] || wait "$candidate_wait_pid" 2>/dev/null || true
  record_macos_bounded_cleanup "$had_known_processes"
  candidate_pid=
  candidate_wait_pid=
  candidate_session=
  candidate_marker_file=
  candidate_status_file=
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

linux_candidate_bwrap() {
  local session_dir=$1 session_destination lock_file lock_destination launcher_status launcher_pid entry key value arg path_entry store_entry closure_root closure_path tool tool_path resolved env_interpreter= openssl_pkgconfig= openssl_include= openssl_lib= opengl_driver=
  local -a path_entries mapped_path closure_roots required_tools
  shift
  [[ $(bwrap --version | awk '{print $NF}') == 0.11.2 ]] || {
    echo 'locked Bubblewrap 0.11.2 is required for Linux candidate isolation' >&2
    return 2
  }
  command -v flock >/dev/null || { echo 'locked flock is required for Linux candidate teardown' >&2; return 2; }
  lock_file=$candidate_teardown_lock
  session_destination=/candidate/${session_dir#"$candidate_root/"}
  lock_destination=/candidate/${lock_file#"$candidate_root/"}
  launcher_status=/candidate/${candidate_status_file#"$candidate_root/"}
  launcher_pid=/candidate/${session_dir#"$candidate_root/"}/pid
  entry='for fd in /proc/self/fd/[0-9]*; do number=${fd##*/}; [[ $number =~ ^[0-9]+$ ]] || continue; ((number > 2 && number != 255)) || continue; eval "exec $number>&-" 2>/dev/null || exit 2; done; ip link set lo up || exit 2; printf "%s\n" "$$" > "$BURLMD_CANDIDATE_PID_FILE"; trap '\''printf "143\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 143'\'' TERM; trap '\''printf "130\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 130'\'' INT; trap '\''printf "129\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 129'\'' HUP; set +e; "$@"; status=$?; printf "%s\n" "$status" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit "$status"'
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
    --setenv BURLMD_CANDIDATE_SESSION "$candidate_session"
    --setenv BURLMD_CANDIDATE_PID_FILE "$launcher_pid"
    --setenv BURLMD_CANDIDATE_STATUS_FILE "$launcher_status"
  )
  bwrap_args+=(
    --proc /proc --dev /dev --tmpfs /tmp
    --dir /nix --dir /nix/store
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
    --bind "$candidate_root/writable" /candidate/writable
    --bind "$session_dir" "$session_destination"
    --dir /candidate/prepared
    --ro-bind "$candidate_root/prepared" /candidate/prepared
    --dir /trusted --ro-bind "$script_root" /trusted
  )
  if [[ $candidate_execution_root == "$source_root" ]]; then
    # Pre-CI-M003 Spike commands retain their contract-scoped source output
    # roots. CI-M003 instead uses the staged disposable checkout below.
    bwrap_args+=(--bind "$source_root" /source)
  else
    bwrap_args+=(--ro-bind "$candidate_execution_root" /source)
  fi
  bwrap_args+=(--chdir /source)
  opengl_driver=$(readlink -f /run/opengl-driver) || { echo 'NixOS OpenGL driver root is required for private Linux desktop testing' >&2; return 2; }
  [[ $opengl_driver == /nix/store/* && -d $opengl_driver/lib/dri && -f $opengl_driver/share/glvnd/egl_vendor.d/50_mesa.json ]] || {
    echo 'OpenGL driver root is not a safe Nix store driver closure' >&2; return 2;
  }
  bwrap_args+=(--dir /run --ro-bind "$opengl_driver" /run/opengl-driver)
  if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} ]]; then
    [[ -d $LINUX_VIEWPORT_RUNTIME ]] || { echo 'private Sway runtime mount is absent' >&2; return 1; }
    bwrap_args+=(--dir /sway-runtime --bind "$LINUX_VIEWPORT_RUNTIME" /sway-runtime)
    [[ -n ${LINUX_VIEWPORT_SWAYSOCK:-} && -S $LINUX_VIEWPORT_SWAYSOCK ]] || {
      echo 'private Sway IPC socket is absent' >&2; return 1;
    }
    bwrap_args+=(--setenv SWAYSOCK "/sway-runtime/${LINUX_VIEWPORT_SWAYSOCK##*/}")
  fi
  # A Nix store root is immutable but far broader than the locked role
  # toolchain. Bind only the exact runtime closures of the role's declared
  # tools. Resolve profile symlinks before asking Nix: otherwise a Nix profile
  # path would silently disappear from the private namespace. The resulting
  # list is also passed to the nested isolation assertion, so it never needs a
  # host Nix database or a broad store mount.
  if [[ $candidate_linux_closure_prepared == false ]]; then
    command -v nix-store >/dev/null || { echo 'locked nix-store is required to materialize Linux candidate closure' >&2; return 2; }
    # This is the complete declared Linux candidate command surface: CI-M003's
    # generator/test gates plus every trusted TOML verification step for the
    # five managed Spikes.  Do not substitute host tools or add a broad store
    # bind.  A new command must be added here, reviewed, and reach the manifest
    # through a locked Nix closure before a candidate can execute it.
    required_tools=(
      bash sh env mkdir mktemp chmod install cp mv rm
      awk sed grep rg sort sha256sum wc find tar zstd
      flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup ip
      git nix nix-store cmake ninja pkg-config clang openssl
      bwrap flock jq taplo check-jsonschema
      sway swaymsg getconf df ps sleep setsid perl
      readlink uname tr head ip
    )
    closure_roots=()
    for tool in "${required_tools[@]}"; do
      tool_path=$(command -v "$tool") || { echo "locked candidate tool is missing: $tool" >&2; return 2; }
      resolved=$(readlink -f "$tool_path") || { echo "cannot resolve locked candidate tool: $tool" >&2; return 2; }
      case $resolved in
        /nix/store/*)
          store_entry=${resolved#/nix/store/}
          closure_roots+=("/nix/store/${store_entry%%/*}")
          [[ $tool == env ]] && env_interpreter=$resolved
          ;;
        "$source_root"/*|"$script_root"/*)
          # Unit fixtures can provide command doubles from an explicitly
          # mounted source/trusted path. Production CI never supplies such a
          # PATH: its production-closure fixture below proves every declared
          # command resolves to a locked store entry before role execution.
          ;;
        *)
          echo "candidate tool is outside the locked Nix closure: $tool ($resolved)" >&2
          return 2
          ;;
      esac
    done
    (( ${#closure_roots[@]} > 0 )) || { echo 'Linux candidate has no locked closure roots' >&2; return 2; }
    mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
    # `openssl`'s executable output does not itself carry development headers.
    # Ask the locked pkg-config about exactly its immutable .pc directory and
    # add that output to the candidate closure; no broad inherited PKG_CONFIG
    # path is accepted inside the namespace.
    openssl_pkgconfig=$(pkg-config --variable=pcfiledir openssl) || {
      echo 'locked OpenSSL pkg-config metadata is unavailable' >&2; return 2;
    }
    [[ $openssl_pkgconfig == /nix/store/* && -d $openssl_pkgconfig ]] || {
      echo "OpenSSL pkg-config path is outside the locked store: $openssl_pkgconfig" >&2; return 2;
    }
    store_entry=${openssl_pkgconfig#/nix/store/}
    closure_roots+=("/nix/store/${store_entry%%/*}")
    openssl_include=$(pkg-config --variable=includedir openssl) || return 2
    openssl_lib=$(pkg-config --variable=libdir openssl) || return 2
    [[ $openssl_include == /nix/store/* && -d $openssl_include && $openssl_lib == /nix/store/* && -d $openssl_lib ]] || {
      echo 'OpenSSL include or library path is outside the locked store' >&2; return 2;
    }
    store_entry=${openssl_include#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
    store_entry=${openssl_lib#/nix/store/}; closure_roots+=("/nix/store/${store_entry%%/*}")
    mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
    mapfile -t candidate_linux_closure_paths < <(for closure_root in "${closure_roots[@]}"; do nix-store -qR "$closure_root"; done | LC_ALL=C sort -u)
    mapfile -t candidate_linux_closure_paths < <(
      { printf '%s\n' "${candidate_linux_closure_paths[@]}"; nix-store -qR "$opengl_driver"; } | LC_ALL=C sort -u
    )
    (( ${#candidate_linux_closure_paths[@]} > 0 )) || { echo 'Linux candidate runtime closure is empty' >&2; return 2; }
    candidate_linux_closure_prepared=true
  fi
  for closure_path in "${candidate_linux_closure_paths[@]}"; do
    [[ $closure_path == /nix/store/* && -e $closure_path && ! -L $closure_path ]] || {
      echo "invalid locked Linux candidate closure member: $closure_path" >&2
      return 2
    }
    bwrap_args+=(--ro-bind "$closure_path" "$closure_path")
  done
  # Candidate-provided contract commands can use the conventional
  # `#!/usr/bin/env …` shebang, but that interpreter is a specific locked
  # coreutils binary from the declared Nix closure—not a host `/usr` mount.
  # Trusted helpers below are instead invoked through the exact locked Bash.
  [[ -n $env_interpreter && $env_interpreter == /nix/store/* ]] || {
    echo 'locked env interpreter is missing from Linux candidate closure' >&2; return 2;
  }
  bwrap_args+=(--dir /usr --dir /usr/bin --ro-bind "$env_interpreter" /usr/bin/env)
  if [[ $candidate_execution_root != "$source_root" ]]; then
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
  [[ ${LIBCLANG_PATH:-} == /nix/store/* && -d ${LIBCLANG_PATH:-} ]] || {
    echo 'locked LIBCLANG_PATH is required for Linux candidate build tools' >&2; return 2;
  }
  bwrap_args+=(
    --setenv PKG_CONFIG_PATH "$openssl_pkgconfig"
    --setenv LIBCLANG_PATH "$LIBCLANG_PATH"
    # The cc wrapper receives no ambient devenv flags after env -i. Supply
    # only the immutable OpenSSL include/library locations required by the
    # locked SQLCipher build script, not the host's aggregate flags.
    --setenv NIX_CFLAGS_COMPILE "-isystem $openssl_include"
    --setenv NIX_LDFLAGS "-L$openssl_lib"
    --setenv CFLAGS "-isystem $openssl_include"
    --setenv LDFLAGS "-L$openssl_lib"
    --setenv LIBGL_DRIVERS_PATH /run/opengl-driver/lib/dri
    --setenv __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
  )
  local -a rewritten=()
  for arg in "$@"; do
    if [[ -n ${LINUX_VIEWPORT_RUNTIME:-} && $arg == "XDG_RUNTIME_DIR=$LINUX_VIEWPORT_RUNTIME" ]]; then
      rewritten+=(XDG_RUNTIME_DIR=/sway-runtime)
      continue
    fi
    case $arg in
      "$source_root"/*) rewritten+=(/source/${arg#"$source_root/"});;
      "$source_root") rewritten+=(/source);;
      "$script_root"/*) rewritten+=(/trusted/${arg#"$script_root/"});;
      "$script_root") rewritten+=(/trusted);;
      "$candidate_root"/*) rewritten+=(/candidate/${arg#"$candidate_root/"});;
      "$candidate_root") rewritten+=(/candidate);;
      *) rewritten+=("$arg");;
    esac
  done
  bwrap "${bwrap_args[@]}" "$candidate_shell" -ceu "$entry" candidate-child "${rewritten[@]}"
}

start_candidate_session() {
  local session_dir launcher pass
  [[ -z $candidate_pid ]] || { echo 'nested candidate session is forbidden' >&2; return 1; }
  session_dir=$(mktemp -d "$candidate_root/session.XXXXXXXX")
  candidate_session="managed-role-${session_dir##*/}"
  candidate_marker_file="$session_dir/marker"
  candidate_status_file="$session_dir/status"
  printf '%s\n' "$candidate_session" >"$candidate_marker_file"
  # Descriptor 255 is the current Bash interpreter input. It is CLOEXEC; all
  # other inherited descriptors are closed in the launch subshell below. Do
  # not close them in this trusted parent: callers may be capturing a command
  # log on an inherited descriptor while the candidate is being started.
  # The direct fixture inspects the resulting exec child with a non-CLOEXEC FD
  # 10+ canary, because enumerating /proc/self/fd inside this shell creates a
  # scanner descriptor and cannot prove the property being asserted.
  # Write the command status before the session leader exits. The parent polls
  # that trusted status file rather than blocking in `wait`, so TERM/HUP/INT is
  # handled promptly even while Flutter owns a long-running test process.
  launcher='printf "%s\n" "$$" > "$BURLMD_CANDIDATE_PID_FILE"; trap '\''printf "143\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 143'\'' TERM; trap '\''printf "130\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 130'\'' INT; trap '\''printf "129\n" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit 129'\'' HUP; set +e; "$@"; status=$?; printf "%s\n" "$status" > "$BURLMD_CANDIDATE_STATUS_FILE"; exit "$status"'
  if [[ $role == linux-x86_64 ]]; then
    candidate_linux_namespace=true
    candidate_teardown_lock="$session_dir/namespace-teardown.lock"
    : >"$candidate_teardown_lock"
    (
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
    close_inherited_candidate_fds
    if command -v setsid >/dev/null 2>&1; then
      exec env -i "${candidate_env[@]}" "BURLMD_CANDIDATE_SESSION=$candidate_session" \
        "BURLMD_CANDIDATE_PID_FILE=$session_dir/pid" \
        "BURLMD_CANDIDATE_STATUS_FILE=$candidate_status_file" \
        setsid "$candidate_shell" -ceu "$launcher" candidate-child "$@"
    elif command -v perl >/dev/null 2>&1; then
      # POSIX::setsid ships with the macOS system Perl. The workflow's locked
      # helper closure supplies it explicitly once CI provisioning is finalized.
      exec env -i "${candidate_env[@]}" "BURLMD_CANDIDATE_SESSION=$candidate_session" \
        "BURLMD_CANDIDATE_PID_FILE=$session_dir/pid" \
        "BURLMD_CANDIDATE_STATUS_FILE=$candidate_status_file" \
        perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- \
        "$candidate_shell" -ceu "$launcher" candidate-child "$@"
    fi
    echo 'candidate isolation requires setsid or POSIX::setsid' >&2
    exit 2
  ) &
  candidate_wait_pid=$!
  for ((pass = 0; pass < 50; pass++)); do
    [[ -s $session_dir/pid ]] && break
    kill -0 "$candidate_wait_pid" 2>/dev/null || break
    sleep 0.1
  done
  [[ -s $session_dir/pid ]] || { echo 'candidate session did not publish a leader PID' >&2; return 1; }
  candidate_pid=$(<"$session_dir/pid")
  [[ $candidate_pid =~ ^[1-9][0-9]*$ ]] || { echo 'candidate session published an invalid leader PID' >&2; return 1; }
}

candidate_exec() {
  local status pass
  start_candidate_session "$@"
  for ((pass = 0; pass < 72000; pass++)); do
    [[ -s $candidate_status_file ]] && break
    candidate_has_survivors || { echo 'candidate session ended without a status record' >&2; return 1; }
    sleep 0.1
  done
  [[ -s $candidate_status_file ]] || { echo 'candidate session exceeded its bounded wait' >&2; terminate_candidate_session || true; return 1; }
  status=$(<"$candidate_status_file")
  [[ $status =~ ^[0-9]+$ && $status -le 255 ]] || { echo 'candidate session wrote an invalid status' >&2; terminate_candidate_session || true; return 1; }
  # Always sweep the process group and marker-tagged detached descendants,
  # including after a test or generator failure.
  terminate_candidate_session || return 1
  return "$status"
}

prepare_candidate_dependencies
prepare_cargokit_tool_runner

find "$source_root/integration_test" -type f -name '*_test.dart' -print | sed "s#^$source_root/##" | LC_ALL=C sort >"$output_root/results/integration-tests.txt"
[[ -s $output_root/results/integration-tests.txt ]] || { echo 'no integration tests discovered' >&2; exit 1; }
run_integration_files() {
  local target=$1 runtime=$2 display=$3 failed=0 test_file result log outcome step_id
  while IFS= read -r test_file; do
    [[ -n $test_file ]] || continue
    # A path-derived filename collides for e.g. `a_b/test.dart` and
    # `a/b_test.dart`. Bind each outcome to a stable digest of the discovered
    # repository-relative test path instead.
    step_id=$(printf '%s' "$test_file" | sha256sum | awk '{print $1}')
    log="$output_root/results/integration-$step_id.log"
    set +e
    if [[ -n $runtime ]]; then
      candidate_exec env XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY="$display" flutter test --no-pub --suppress-analytics "$test_file" -d "$target" -r github >"$log" 2>&1
    else
      candidate_exec flutter test --no-pub --suppress-analytics "$test_file" -d "$target" -r github >"$log" 2>&1
    fi
    result=$?
    set -e
    if ((result == 0)) && ! rg -qi 'skipped|pending|no tests' "$log"; then status=passed; else status=failed; failed=1; fi
    outcome="$output_root/results/integration-$step_id.json"
    jq -cn --arg id "$step_id" --arg file "$test_file" --arg status "$status" --argjson exitCode "$result" '{id:$id,file:$file,status:$status,exitCode:$exitCode}' >"$outcome"
  done <"$output_root/results/integration-tests.txt"
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
  ((failed == 0))
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
    [[ $ticket == PKG-M001 && $role == macos-15-arm64 && $required_stage == macos-26-arm64 ]] || {
      echo "unauthorized authenticated-stage prerequisite: $required_stage" >&2; return 2;
    }
    prepare_authenticated_pkg_stage || return 1
  elif [[ $ticket == PKG-M001 && $role == macos-15-arm64 && $command == *'handoff import'* ]]; then
    verify_authenticated_pkg_inbox || {
      echo 'PKG-M001 import lacks the immediately preceding verified macOS 26 inbox' >&2; return 1;
    }
  fi
  log="results/role-step-$id.log"
  set +e
  candidate_exec bash -ceu 'cd -- "$1"; exec bash -ceu "$2"' managed-role-step "$source_root/$workdir" "$command" >"$output_root/$log" 2>&1
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
  set +e
  candidate_exec "$@" >"$output_root/$log" 2>&1
  local status=$?
  set -e
  record_step "$id" . "$(printf '%q ' "$@")" "$([[ $status == 0 ]] && printf passed || printf failed)" "$log"
  return "$status"
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
  # PKG-M001's macOS 15 import is the one permitted cross-role input.  The
  # reusable workflow must acquire and authenticate it before this launcher is
  # called, then expose only this owned staging root.  We neither download nor
  # read a candidate-provided location here.
  [[ $ticket == PKG-M001 && $role == macos-15-arm64 ]] || return 0
  local stage_root producer_root destination member source marker members_json provenance nonce
  stage_root=${BURLMD_AUTHENTICATED_STAGE_ROOT:?PKG-M001 macOS 15 requires authenticated staging}
  [[ $stage_root == /* && -d $stage_root && $stage_root != "$source_root" && $stage_root != "$source_root"/* ]] || {
    echo 'authenticated staging root is missing, unsafe, or inside tested source' >&2; return 1;
  }
  producer_root=$stage_root/roles/macos-26-arm64
  [[ -d $producer_root && ! -L $producer_root ]] || { echo 'authenticated macOS 26 role stage is absent' >&2; return 1; }
  provenance=$stage_root/stage-provenance.json
  nonce=$(jq -er '.artifactNonce | select(test("^[0-9a-f]{32}$"))' "$EXPECTED_IDENTITY") || return 1
  [[ -f $provenance && ! -L $provenance ]] || { echo 'authenticated stage provenance is absent' >&2; return 1; }
  jq -e --arg nonce "$nonce" '
    .schemaVersion == 1 and .interface == "authenticated-producer-stage-v1" and
    .producerRole == "macos-26-arm64" and .artifactNonce == $nonce and
    (.sealingCheckRunId | type == "number" and . > 0) and
    (.roleBundleSha256 | test("^[0-9a-f]{64}$")) and
    (.sealedBundleSha256 | test("^[0-9a-f]{64}$"))
  ' "$provenance" >/dev/null || { echo 'authenticated stage provenance is invalid or substituted' >&2; return 1; }
  destination=$source_root/.constitution/prototypes/packaging/managed-evidence-coordinator/roles/macos-26-arm64
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
  done < <(taplo get --file-path "$contract" --output-format json 'ci_bootstrap.role_prerequisites."PKG-M001-macos-archive".required_members' | jq -er '.[]')
  marker=$output_root/results/authenticated-stage-pkg-macos-26.json
  jq -cn --arg sourceRole macos-26-arm64 --argjson members "$members_json" \
    '{sourceRole:$sourceRole,interface:"authenticated-producer-stage-v1",members:$members}' >"$marker"
}

record_authenticated_pkg_inbox() {
  local marker=$output_root/results/authenticated-stage-pkg-macos-26.json inbox member source staged expected actual
  [[ -f $marker ]] || return 1
  inbox=$source_root/.constitution/prototypes/packaging/handoff/current-inbox
  [[ -d $inbox && ! -L $inbox ]] || return 1
  while IFS= read -r member; do
    source=$source_root/.constitution/prototypes/packaging/managed-evidence-coordinator/roles/macos-26-arm64/$member
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
  local source=$1 path source_dir canonical destination
  [[ -f $source && ! -L $source ]] || { echo "declared role artifact missing: $source" >&2; return 1; }
  source_dir=$(cd "$(dirname "$source")" && pwd -P)
  canonical=$source_dir/$(basename "$source")
  [[ $canonical == "$candidate_execution_root/$ticket_root/"* ]] || { echo "declared role artifact escapes ticket root: $path" >&2; return 1; }
  destination=${canonical#"$candidate_execution_root/$ticket_root/"}
  [[ $destination != /* && $destination != *'..'* && $destination != *'//' ]] || return 1
  mkdir -p "$output_root/$(dirname "$destination")"
  cp -- "$canonical" "$output_root/$destination"
}

copy_declared_role_artifacts() {
  local path workdir source entry
  # The command text comes from the trusted contract. Normalize every declared
  # producer output below the ticket root, including the contract's explicit
  # runs/, logs/, artifacts/, results/, and handoff/ roots. Copy neither a
  # discovered/globbed candidate file nor an arbitrary sibling of an output.
  while IFS=$'\t' read -r workdir path; do
    [[ -n $path && $path != /* && $path != *'//' ]] || return 1
    [[ $workdir != /* && $workdir != *'..'* && $workdir != *'//' && $workdir != */ ]] || return 1
    source=$candidate_execution_root/${workdir#./}/$path
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
  XDG_RUNTIME_DIR="$runtime" WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 \
    sway --unsupported-gpu >"$output_root/results/sway.log" 2>&1 &
  sway_pid=$!
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
  sway_socket="$runtime/sway-ipc.$(id -u).$sway_pid.sock"
  [[ -S $sway_socket ]] || {
    kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true
    echo 'private headless Sway did not create an IPC socket' >&2; return 1
  }
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
  # CI-M003's Linux integration suite itself runs against this owned compositor.
  LINUX_VIEWPORT_RUNTIME=$runtime
  LINUX_VIEWPORT_DISPLAY=$display
  LINUX_VIEWPORT_SWAYSOCK=$sway_socket
  LINUX_VIEWPORT_SWAY_PID=$sway_pid
  viewport_verified=true
}

stop_linux_private_sway_viewport() {
  [[ -n ${LINUX_VIEWPORT_SWAY_PID:-} ]] || return 0
  kill "$LINUX_VIEWPORT_SWAY_PID" 2>/dev/null || true
  wait "$LINUX_VIEWPORT_SWAY_PID" 2>/dev/null || true
  unset LINUX_VIEWPORT_RUNTIME LINUX_VIEWPORT_DISPLAY LINUX_VIEWPORT_SWAYSOCK LINUX_VIEWPORT_SWAY_PID
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
  if [[ $ticket == CI-M003 ]]; then
    # CI-M003's trusted phase is declared by ci_bootstrap.candidate_phase and
    # role_phase rather than a Spike verification_steps array.
    # Keep this order identical to the executable ticket contract.  The
    # generated-byte check must run before Dart/Flutter tests, and the Linux
    # containment assertion remains the final gate after every integration
    # file has produced its own outcome.
    if [[ $role == linux-x86_64 ]]; then
      # Do not execute a trusted helper through its candidate-visible shebang.
      # `candidate_shell` is the exact locked Bash that entered the declared
      # Nix closure; `/trusted` is read-only anchor-owned control code.
      generated_check_root=$(prepare_generated_bindings_workspace)
      run_ci_gate generated-bindings results/role-step-generated-bindings.log "$candidate_shell" "$script_root/scripts/check-generated-bindings.sh" --root "$generated_check_root"
    fi
    # Flutter 3.44.3 documents --no-pub and --suppress-analytics on `flutter
    # test`; preparation already enforced the lockfile before network denial.
    run_ci_gate flutter-test results/role-step-flutter-test.log flutter test --no-pub --suppress-analytics
    # Analyze every authored Dart root explicitly. The build overlay also holds
    # Cargokit's precompiled, disposable runner, which is not project source
    # and intentionally carries a private path dependency for its one build.
    run_ci_gate dart-analyze results/role-step-dart-analyze.log dart --suppress-analytics analyze lib test integration_test test_driver
    # This representative Cargo command runs from the same prepared cache as
    # Flutter and forbids registry access. It proves every CI-M003 role can
    # consume the lock-enforced Cargo fetch without making Cargo itself part of
    # the candidate's dependency-acquisition authority.
    run_ci_gate cargo-metadata results/role-step-cargo-metadata.log cargo metadata --offline --locked --manifest-path rust/Cargo.toml --format-version 1
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
  if [[ $ticket == CI-M003 && $role == linux-x86_64 ]]; then
    observe_linux_private_sway_viewport
    run_integration_files linux "$LINUX_VIEWPORT_RUNTIME" "$LINUX_VIEWPORT_DISPLAY"
    stop_linux_private_sway_viewport
    # The precompiled Cargokit runner is a build-only helper. Remove it before
    # analysis so Dart does not inspect its private path dependency as project
    # source; the immutable Cargokit tree and prepared Pub cache remain intact.
    rm -rf -- "$candidate_root/writable/build/linux/x64/debug/plugins/rust/cargokit_build/tool"
  elif [[ $ticket == CI-M003 ]]; then
    run_integration_files macos '' ''
  fi
  if [[ $ticket == CI-M003 ]]; then
    jq -s '.' "$output_root/results/role-steps.ndjson" >"$output_root/results/role-steps.json"
  fi
}
candidate_phase >"$output_root/results/candidate.log" 2>&1
if [[ $ticket == CI-M003 && $role == linux-x86_64 ]]; then
  isolation_log=results/role-step-managed-isolation.log
  set +e
  "$candidate_shell" "$script_root/scripts/assert-managed-evidence-isolation.sh" --contract "$script_root/.constitution/tech-spec/contracts/provisional-spikes.toml" --sandbox bubblewrap --expected-version 0.11.2 >"$output_root/$isolation_log" 2>&1
  isolation_status=$?
  set -e
  record_step managed-isolation . "$candidate_shell $script_root/scripts/assert-managed-evidence-isolation.sh --contract $script_root/.constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2" "$([[ $isolation_status == 0 ]] && printf passed || printf failed)" "$isolation_log"
  [[ $isolation_status == 0 ]] || exit "$isolation_status"
  jq -s '.' "$output_root/results/role-steps.ndjson" >"$output_root/results/role-steps.json"
fi
# CI-M003's managed profiles are explicitly non-authoritative: it uses its
# private Sway environment for functional integration but does not claim a
# host-display observation. Every viewport-bound Spike must instead own and
# validate an actual platform observation here.
if [[ $ticket == CI-M003 ]]; then
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
  os_release=$(sw_vers | tr '\n' ';' | sed 's/;$//')
else
  observed_cpus=$(getconf _NPROCESSORS_ONLN)
  observed_memory=$(awk '/MemTotal:/ {printf "%.0f", $2 * 1024}' /proc/meminfo)
  os_release=$(tr '\n' ';' </etc/os-release | sed 's/;$//')
fi
observed_storage=$(df -Pk "$output_root" | awk 'NR==2 {printf "%.0f", $4 * 1024}')
documented_arch=$(jq -er '.architecture' <<<"$documented_environment")
documented_cpus=$(jq -er '.logical_cpu_count' <<<"$documented_environment")
documented_memory=$(jq -er '.memory_bytes' <<<"$documented_environment")
documented_storage=$(jq -er '.storage_bytes' <<<"$documented_environment")
[[ $observed_arch == "$documented_arch" ]] || {
  echo "observed architecture $observed_arch does not match documented $documented_arch" >&2; exit 1;
}
[[ $observed_cpus =~ ^[1-9][0-9]*$ && $observed_memory =~ ^[1-9][0-9]*$ && $observed_storage =~ ^[1-9][0-9]*$ ]] || {
  echo 'host observation was incomplete' >&2; exit 1;
}
[[ $observed_cpus == "$documented_cpus" ]] || {
  echo "observed logical CPU count $observed_cpus does not match documented $documented_cpus" >&2; exit 1;
}
export ROLE="$role" RUNNER_LABEL="$runner" ARCH="$observed_arch" CPUS="$observed_cpus" MEMORY="$documented_memory" STORAGE="$documented_storage" CLASSES="$classes" OUTPUT_ROOT="$output_root"
if [[ $ticket == CI-M003 ]]; then
  mapfile -t bundle_members < <(find "$output_root/results" -type f -print | LC_ALL=C sort | sed "s#^$output_root/##")
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
jq -cn --slurpfile identity "$EXPECTED_IDENTITY" --arg digest "$identity_sha" --arg role "$role" --arg runner "$runner" --arg arch "$observed_arch" --arg cpu "$cpu_model" --arg os "$os_release" --arg imageOs "$image_os" --arg imageVersion "$image_version" --arg flutter "$(flutter --version | head -1)" --arg dart "$(dart --version 2>&1)" --argjson viewportVerified "$viewport_verified" --argjson observedCpus "$observed_cpus" --argjson documentedMemory "$documented_memory" --argjson documentedStorage "$documented_storage" --argjson observedMemory "$observed_memory" --argjson observedStorage "$observed_storage" --argjson classes "$class_json" --argjson gates "$gates" --argjson artifacts "$artifacts" --argjson version "$role_schema_version" '
  {schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,
   roleEvidence:{role:$role,capturedIdentity:($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:$runner,imageOS:$imageOs,imageVersion:$imageVersion,osRelease:$os,architecture:$arch,cpuModel:$cpu,logicalCpuCount:$observedCpus,documentedMemoryBytes:$documentedMemory,documentedStorageBytes:$documentedStorage,observedMemoryBytes:$observedMemory,observedStorageAvailableBytes:$observedStorage},viewport:{width:1920,height:1080,refreshHz:60,verified:$viewportVerified},evidenceClasses:$classes,gates:$gates,toolchain:{flutter:$flutter,dart:$dart},internalArtifacts:$artifacts}}' >"$output_root/ci-role-evidence.json"
check-jsonschema --schemafile "$role_schema" "$output_root/ci-role-evidence.json"
(cd "$output_root" && tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -I 'zstd -19 --no-progress' -cf ci-role-evidence.tar.zst ci-role-evidence.json "${bundle_members[@]}")
