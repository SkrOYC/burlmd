#!/usr/bin/env bash
# Contract fixture for the production role runner. It stays parser-free so it
# can run before the locked CI closure is installed; runtime parsing remains
# owned by taplo in run-managed-role.sh.
set -euo pipefail
# `rg -q` intentionally closes a pipeline once it finds a contract entry;
# gawk then exits with SIGPIPE.  This fixture asserts presence, so do not let
# that producer-side success signal mask the assertion under pipefail.
set +o pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
runner=$root/scripts/run-managed-role.sh

while IFS= read -r workflow; do
  awk '
    /cachix\/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24/ { expect = 1; next }
    expect && /^[[:space:]]*with:[[:space:]]*\{enable_kvm: false\}[[:space:]]*$/ { expect = 0; next }
    expect { exit 1 }
    END { if (expect) exit 1 }
  ' "$workflow"
done < <(rg -l 'cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24' "$root/.github/workflows")

# Ticket/role selection is explicit trusted control.  The production launcher
# must not recover the former all-future-tools union, and only packaging may
# select Nix build authority. BURL-M003 receives only its two read-only
# same-path closure views and never Nix state or a copied store.
rg -Fq 'candidate_profile_tools()' "$runner"
rg -Fq 'flutter_rust_bridge_codegen cargo cargo-expand rustc rustup' "$runner"
rg -Fq 'openssl jq ip' "$runner"
! rg -Fq 'openssl bwrap ip' "$runner"
rg -Fq 'candidate_command_executables()' "$runner"
rg -Fq 'trusted_contract_candidate_heads()' "$runner"
rg -Fq 'BURL-O001:linux-x86_64' "$runner"
rg -Fq 'nix nix-store' "$runner"
rg -Fq 'BURL-M003:linux-x86_64' "$runner"
rg -Fq 'BURL-M003:macos-26-arm64|BURL-M003:macos-15-arm64' "$runner"
rg -Fq "printf '%s\\n' env cargo rustc rustup flutter dart" "$runner"
rg -Fq 'pinned Perl POSIX::setsid mechanism explicitly' "$runner"
! sed -n '/start_candidate_session()/,/candidate_exec()/p' "$runner" | rg -Fq 'command -v setsid'
for tool in perl tr cat ls shasum lipo install_name_tool arch; do
  rg -Fq "$tool" "$runner"
done
# Flutter 3.44.3 foregrounds the attached macOS app with `open <app-bundle>`.
# The launcher admits only that fixed executable, never a broad /usr/bin PATH.
rg -Fq '[[ -x /usr/bin/open ]]' "$runner"
rg -Fq 'ln -s /usr/bin/open "$candidate_tool_path/open"' "$runner"
! rg -Fq 'PATH=/usr/bin' "$runner"
rg -Fq 'non_spike_gate_guard()' "$runner"
rg -Fq 'trusted contract declares no candidate execution gates for managed non-Spike $ticket' "$runner"
rg -Fq 'BURL-O004 coordinator is future trusted control pending anchor rotation; candidate execution is blocked' "$runner"
rg -Fq 'BURL-G011|BURL-P002|BURL-O004|BURL-O011|BURL-O012|BURL-O013) return 2 ;;' "$runner"
! rg -Fq 'git nix nix-store cmake ninja pkg-config clang openssl' "$runner"
rg -Fq 'prepare_linux_candidate_closure_views()' "$runner"
rg -Fq 'prepare_linux_candidate_private_store()' "$runner"
rg -Fq 'linux_m003_candidate_bwrap()' "$runner"
rg -Fq 'linux_legacy_candidate_bwrap()' "$runner"
rg -Fq 'linux_candidate_bwrap()' "$runner"
rg -Fq 'run_linux_native_isolation_prerequisite()' "$runner"
awk '/validate_candidate_tool_profile/,/prepare_candidate_dependencies/' "$runner" | rg -Fq 'run_linux_native_isolation_prerequisite'
rg -Fq 'No sudo/sysctl/AppArmor fallback' "$runner"
! rg -Fq -- '--disable-userns' "$runner"

# Regression: raw-38 is a ticket-scoped closure-view/controller path. Its
# M003-only functions must not materialize, mount, or expose the predecessor
# private store even though that backend remains live for later tickets.
m003_view_scope=$(awk '
  /^prepare_linux_candidate_closure_views\(\)/ { active = 1 }
  /^run_linux_native_isolation_prerequisite\(\)/ { active = 0 }
  active { print }
' "$runner")
m003_controller_scope=$(awk '
  /^m003_prepare_closure_log\(\)/ { active = 1 }
  /^linux_m003_candidate_bwrap\(\)/ { active = 0 }
  active { print }
' "$runner")
m003_launcher_scope=$(awk '
  /^linux_m003_candidate_bwrap\(\)/ { active = 1 }
  /^linux_legacy_candidate_bwrap\(\)/ { active = 0 }
  active { print }
' "$runner")
cleanup_scope=$(awk '
  /^cleanup_role_exit\(\)/ { active = 1 }
  /^trap / { active = 0 }
  active { print }
' "$runner")
printf '%s\n' "$m003_view_scope" | rg -Fq '[[ $ticket == BURL-M003 ]] || return 0'
printf '%s\n' "$m003_view_scope" | rg -Fq 'base-session-closure.manifest'
printf '%s\n' "$m003_view_scope" | rg -Fq 'integration-session-closure.manifest'
printf '%s\n' "$m003_view_scope" | rg -Fq 'candidate_linux_base_closure_paths'
printf '%s\n' "$m003_view_scope" | rg -Fq 'candidate_linux_integration_closure_paths'
printf '%s\n' "$m003_launcher_scope" | rg -Fq 'bwrap_args+=(--ro-bind "$closure_path" "$closure_path")'
! printf '%s\n%s\n%s\n' "$m003_view_scope" "$m003_controller_scope" "$m003_launcher_scope" | rg -Fq 'candidate_private_store'
! printf '%s\n%s\n%s\n' "$m003_view_scope" "$m003_controller_scope" "$m003_launcher_scope" | rg -Fq 'nix copy --offline'
printf '%s\n' "$cleanup_scope" | rg -Fq 'if [[ $ticket != BURL-M003 ]]; then'

# Regression: non-M003 Linux tickets keep the predecessor private-store
# backend. They must not select the raw-38 manifests or their exact-488 guard.
legacy_store_scope=$(awk '
  /^prepare_linux_candidate_private_store\(\)/ { active = 1 }
  /^prepare_linux_candidate_closure_views\(\)/ { active = 0 }
  active { print }
' "$runner")
legacy_launcher_scope=$(awk '
  /^linux_legacy_candidate_bwrap\(\)/ { active = 1 }
  /^linux_candidate_bwrap\(\)/ { active = 0 }
  active { print }
' "$runner")
printf '%s\n' "$legacy_store_scope" | rg -Fq '[[ $ticket != BURL-M003 ]] || {'
printf '%s\n' "$legacy_store_scope" | rg -Fq 'nix copy --offline --to "$candidate_private_store_root" --no-check-sigs'
printf '%s\n' "$legacy_store_scope" | rg -Fq 'nix --store "local?root=$candidate_private_store_root" store verify --all --no-trust'
printf '%s\n' "$legacy_launcher_scope" | rg -Fq 'bwrap_args+=(--bind "$candidate_private_store_root/nix" /nix)'
printf '%s\n' "$legacy_launcher_scope" | rg -Fq 'private_closure_member "$closure_path"'
! printf '%s\n%s\n' "$legacy_store_scope" "$legacy_launcher_scope" | rg -Fq 'burlmd-m003'
! printf '%s\n%s\n' "$legacy_store_scope" "$legacy_launcher_scope" | rg -q '== 488|base-session-closure.manifest|integration-session-closure.manifest'

backend_selection_scope=$(awk '
  /^validate_candidate_tool_profile$/ { active = 1 }
  /^prepare_cargokit_tool_runner$/ { if (active) { print; exit } }
  active { print }
' "$runner")
printf '%s\n' "$backend_selection_scope" | rg -Fq 'if [[ $ticket == BURL-M003 && $role == linux-x86_64 ]]; then'
printf '%s\n' "$backend_selection_scope" | rg -Fq 'prepare_linux_candidate_closure_views'
printf '%s\n' "$backend_selection_scope" | rg -Fq 'prepare_linux_candidate_private_store'
backend_dispatch_scope=$(awk '
  /^linux_candidate_bwrap\(\)/ { active = 1 }
  /^start_candidate_session\(\)/ { active = 0 }
  active { print }
' "$runner")
printf '%s\n' "$backend_dispatch_scope" | rg -Fq 'linux_m003_candidate_bwrap "$@"'
printf '%s\n' "$backend_dispatch_scope" | rg -Fq 'linux_legacy_candidate_bwrap "$@"'

# Exercise the extracted ticket guards rather than relying only on source
# presence. The real dispatcher must route M003 to its controller-side view
# launcher and BURL-O001 to the restored private-store launcher. Conversely,
# neither setup function may begin the other backend's work after its guard.
source <(printf '%s\n' "$backend_dispatch_scope")
linux_m003_candidate_bwrap() { selected_backend=m003; }
linux_legacy_candidate_bwrap() { selected_backend=legacy; }
ticket=BURL-M003
selected_backend=
linux_candidate_bwrap
[[ $selected_backend == m003 ]]
ticket=BURL-O001
selected_backend=
linux_candidate_bwrap
[[ $selected_backend == legacy ]]
source <(printf '%s\n' "$m003_view_scope")
source <(printf '%s\n' "$legacy_store_scope")
role=linux-x86_64
ticket=BURL-O001
prepare_linux_candidate_closure_views
ticket=BURL-M003
if prepare_linux_candidate_private_store 2>/dev/null; then
  echo 'BURL-M003 entered the legacy private-store preparation path' >&2
  exit 1
fi
rg -Fq 'candidate command executable is absent from $ticket/$role closure' "$runner"
locked_closure_probe=$root/scripts/test-managed-role-locked-closure.sh
rg -Fq 'base-session-closure.manifest' "$locked_closure_probe"

# The Linux parent, rather than the candidate or an external Sway process,
# owns the complete seven-session raw-38 vector, both handshake pipes, the
# retained original teardown descriptor, and the version-2 closure log.
rg -Fq 'm003_run_session()' "$runner"
rg -Fq 'm003_prepare_closure_log()' "$runner"
rg -Fq 'm003_finish_log()' "$runner"
rg -Fq 'm003_validate_preflight()' "$runner"
rg -Fq 'm003_write_cleanup_ack()' "$runner"
rg -Fq 'm003_perl_session_controller()' "$runner"
rg -Fq 'persist_candidate_diagnostics' "$runner"
rg -Fq 'O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW' "$runner"
rg -Fq '%ENV = ();' "$runner"
rg -Fq 'exec { $argv[0] } @argv' "$runner"
rg -Fq 'preflight-bytes=' "$runner"
rg -Fq 'print {$ack_write} q{G}' "$runner"
rg -Fq 'm003_log=$output_root/logs/burl-m003-linux-closure-view.log' "$runner"
rg -Fq 'burl-m003-linux-closure-view.log' "$runner"
rg -Fq 'integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d' "$runner"
rg -Fq 'integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d' "$runner"
rg -Fq '"teardown-lock-verifier-path=$m003_flock_path"' "$runner"
rg -Fq 'm003_observe_exact_executable()' "$runner"
rg -Fq 'm003_revalidate_observed_executables' "$runner"
rg -Fq '"teardown-lock-verifier-version=$m003_flock_version"' "$runner"
rg -Fq '"sway-version=$m003_sway_version"' "$runner"
rg -Fq '"swaymsg-version=$m003_swaymsg_version"' "$runner"
rg -Fq 'm003_openat2_current_identity()' "$runner"
rg -Fq 'my $fd = syscall(437, 0 + $parent_fd, $leaf, $how, length($how));' "$runner"
rg -Fq 'm003_validate_ephemeral_lifecycle "$ordinal"' "$runner"
rg -Fq "stat -f -c '%a %S'" "$runner"
rg -Fq 'm003_uint64_product "$blocks" "$fragment_size"' "$runner"
rg -Fq 'flock --fcntl --exclusive --timeout 5 --conflict-exit-code 73' "$runner"
! sed -n '/candidate_phase()/,/case \$(uname -m)/p' "$runner" | rg -Fq 'observe_linux_private_sway_viewport'
"$root/scripts/test-linux-session-supervisor.sh"
"$root/scripts/test-managed-evidence-active-isolation.sh"

spike_block() {
  local ticket=$1
  awk -v wanted="SPK-$ticket" '
    BEGIN { active = 0 }
    /^\[\[spikes\]\]$/ { if (active) exit }
    $0 == "id = \"" wanted "\"" { active = 1 }
    active { print }
  ' "$contract"
}

verification_block() {
  spike_block "$1" | awk '
    /^verification_steps = \[$/ { active = 1; next }
    active && /^\]$/ { exit }
    active { print }
  '
}

count_explicit_for() {
  local ticket=$1 expression=$2 count
  count=$(verification_block "$ticket" | rg -c --pcre2 "$expression" || true)
  printf '%s' "${count:-0}"
}

count_shared_for() {
  local ticket=$1 count
  count=$(verification_block "$ticket" | rg -c '^  \{ workdir' || true)
  printf '%s' "${count:-0}"
}

# Every non-CI role receives each unlabeled verification step. Explicit role
# counts remain separate, making the macOS 26-only `macos-default-*` mapping
# and macOS 15 shared cargo-test coverage visible in the fixture.
while IFS=':' read -r ticket shared linux macos26 macos15; do
  [[ $(count_shared_for "$ticket") == "$shared" ]] || exit 1
  [[ $(count_explicit_for "$ticket" 'run_role = "linux') == "$linux" ]] || exit 1
  [[ $(count_explicit_for "$ticket" 'run_role = "macos-(26|current|repeat|default)') == "$macos26" ]] || exit 1
  [[ $(count_explicit_for "$ticket" 'run_role = "macos-(15|previous)') == "$macos15" ]] || exit 1
done <<'EOF'
BURL-H001:1:1:1:0
BURL-H002:1:1:1:0
BURL-I001:1:1:1:0
BURL-L001:1:1:1:0
BURL-O001:0:10:5:4
EOF

# The only authorised cross-role candidate input is packaged through the
# authenticated macOS 26 stage. It is not a candidate source transfer.
rg -Fq 'requires_authenticated_stage_role = "macos-26-arm64"' "$contract"
rg -Fq 'required_members = ["handoff/outbox/macos-current-construction.tar.zst", "handoff/outbox/macos-current-construction.sha256"]' "$contract"
rg -Fq 'BURLMD_AUTHENTICATED_STAGE_ROOT' "$runner"
rg -Fq 'BURLMD_COMPATIBILITY_STAGE_CONSUMPTION' "$runner"
rg -Fq 'authenticated_stage_consumption=$(jq -ce . "$binding")' "$runner"
rg -Fq 'rm -f -- "$binding"' "$runner"
rg -Fq 'authenticated stage root exposes non-member bytes' "$runner"
rg -Fq 'select((has("run_role") | not) or (.run_role | test($pattern)))' "$runner"

# Production manifests bind source identity, trust-owned command outputs, and
# runner observations rather than hard-coded host labels/constants.
rg -Fq 'tested source HEAD does not match expected identity' "$runner"
rg -Fq 'canonical_trusted_launcher == "$canonical_trusted_root/scripts/run-managed-role.sh"' "$runner"
rg -Fq '[[ $canonical_source_root != "$canonical_trusted_root" ]]' "$runner"
! rg -Fq '$canonical_source_root != "$canonical_trusted_root"/*' "$runner"
rg -Fq 'ImageOS is required from the hosted runner' "$runner"
rg -Fq 'ImageVersion is required from the hosted runner' "$runner"
rg -Fq 'os_release=$(tr' "$runner"
rg -Fq 'observed_os_major=$(sw_vers -productVersion' "$runner"
rg -Fq 'observed OS major $observed_os_major does not match documented $documented_os_major' "$runner"
rg -Fq 'observed CPU model does not contain documented $documented_cpu_model_contains' "$runner"
rg -Fq -- '--file-reporter="json:$json_log"' "$runner"
rg -Fq 'select(.type == "testDone")' "$runner"
rg -Fq 'map(select(.hidden == false))' "$runner"
! rg -Fq "rg -qi 'skipped|pending|no tests'" "$runner"
rg -Fq 'm003_prepare_linux_integration_report_directory' "$runner"
rg -Fq 'm003_consume_linux_integration_report 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d integration_test/production_host_flow_test.dart' "$runner"
rg -Fq 'm003_consume_linux_integration_report 6 integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d integration_test/shell_flow_test.dart' "$runner"
rg -Fq 'write_integration_outcomes_aggregate' "$runner"
rg -Fq 'logicalCpuCount:$observedCpus' "$runner"
# BURL-M003 may stage a disposable dependency-resolution checkout, but Linux
# must execute the explicitly authenticated tested-source checkout. Generated
# Flutter/Cargo state is copied only into the already-declared writable and
# prepared overlays; the workspace copy is never promoted to source authority.
rg -Fq 'prepare_candidate_dependencies' "$runner"
rg -Fq '.verification_steps[]?' "$runner"
rg -Fq '.create_commands[]?' "$runner"
rg -Fq 'cargo fetch --locked --manifest-path "$resolved_manifest"' "$runner"
rg -Fq 'flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$pub_directory"' "$runner"
rg -Fq 'flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace"' "$runner"
rg -Fq '(cd "$candidate_workspace" && env -i PATH="$PATH"' "$runner"
rg -Fq 'cargo fetch --locked --manifest-path "$candidate_workspace/rust/Cargo.toml"' "$runner"
rg -Fq 'cargo metadata --offline --locked --manifest-path rust/Cargo.toml --format-version 1' "$runner"
rg -Fq 'if [[ $role == linux-x86_64 ]]; then' "$runner"
rg -Fq 'Hosted macOS executes directly from this fresh workspace' "$runner"
rg -Fq 'prepare_linux_ticket_write_root()' "$runner"
rg -Fq 'candidate_execution_root=$source_root' "$runner"
rg -Fq 'source_parent=$(dirname -- "$source_root"); source_leaf=$(basename -- "$source_root")' "$runner"
rg -Fq 'cp -a -- "$candidate_workspace/linux/flutter/ephemeral/." "$candidate_root/writable/linux-flutter-ephemeral/"' "$runner"
rg -Fq 'runtime_tools+=(mktemp chmod sha256sum sha1sum tar cc ar rustfmt rg)' "$runner"
rg -Fq 'for relative in .dart_tool build linux/flutter/ephemeral; do' "$runner"
rg -Fq 'm003_source_tracked_state_is_clean' "$runner"
rg -Fq 'm003_cleanup_authenticated_source_mountpoints' "$runner"
rg -Fq 'trap '\''role_status=$?; trap - EXIT; cleanup_role_exit "$role_status"; exit $?'\'' EXIT' "$runner"
rg -Fq "'ro-bind:trusted-control-root:/trusted' 'ro-bind:tested-source-root:/source'" "$runner"
rg -Fq 'bwrap_args+=(--bind "$candidate_linux_writable_ticket_root" "/source/$candidate_linux_ticket_root")' "$runner"
rg -Fq '"$candidate_execution_root"/*) rewritten+=(/source/${arg#"$candidate_execution_root/"});;' "$runner"
! rg -Fq 'source_parent=$(dirname -- "$candidate_execution_root")' "$runner"
rg -Fq 'artifact_root=${candidate_linux_writable_ticket_root:-$candidate_execution_root/$ticket_root}' "$runner"
rg -Fq 'scan("--(?:output|stdout|stderr|copy-artifact-to|success-marker|handoff-bundle|handoff-sha256|sha256-output|output-archive|output-dir|append-run)[[:space:]]+([^[:space:]]+)")[0]' "$runner"
rg -Fq 'runs/, logs/, artifacts/, results/, and handoff/' "$runner"
rg -Fq 'observe_linux_private_sway_viewport' "$runner"
rg -Fq 'flutter run -d macos --no-hot --pid-file' "$runner"
rg -Fq 'maximumFramesPerSecond' "$runner"
rg -Fq "BURL-M003's managed profiles are explicitly non-authoritative" "$runner"
rg -Fq 'observed_cpus=$(sysctl -n hw.logicalcpu)' "$runner"
rg -Fq 'macos_filesystem_device=$(/bin/df -P "$canonical_output"' "$runner"
rg -Fq '/usr/sbin/diskutil info -plist "$macos_filesystem_device"' "$runner"
# Linux candidate descendants are contained by Bubblewrap's PID namespace
# reaper. The lock remains the trusted host-side proof that the namespace has
# fully exited before the runner can package role output. Hosted macOS instead
# records bounded marker/process-group cleanup and must make no lifecycle
# containment or zero-survivor assertion.
rg -Fq 'locked Bubblewrap 0.11.2 is required for Linux candidate isolation' "$runner"
rg -Fq -- '--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv' "$runner"
rg -Fq 'ip link set dev lo up || exit 2' "$runner"
rg -Fq '/trusted/scripts/assert-managed-evidence-isolation.sh --contract /trusted/.constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2' "$runner"
! rg -Pq '^[[:space:]]*"\$candidate_shell" "\$script_root/scripts/assert-managed-evidence-isolation\.sh" --contract' "$runner"
rg -Fq -- '--lock-file "$lock_destination"' "$runner"
rg -Fq 'confirm_linux_namespace_teardown' "$runner"
rg -Fq 'flock --fcntl --exclusive --timeout 5 --conflict-exit-code 73' "$runner"
rg -Fq 'actual exit result with `wait`' "$runner"
rg -Fq 'a candidate cannot forge its result' "$runner"
! rg -Fq 'BURLMD_CANDIDATE_STATUS_FILE' "$runner"
rg -Fq '/source/linux/flutter/ephemeral' "$runner"
! rg -Fq -- '--as-pid-1' "$runner"
rg -Fq 'bounded-marker-process-group-cleanup' "$runner"
rg -Fq 'containmentClaim:false' "$runner"
rg -Fq 'zeroSurvivorClaim:false' "$runner"
rg -Fq 'trusted-wrapper-untrusted-candidate-artifact' "$runner"
! rg -Fq 'candidate process survived bounded TERM/KILL teardown' "$runner"

# The PKG macOS 15 prerequisite is selected only for its declared consumer,
# runs in contract order, and records the verified current inbox before import.
rg -Fq '$requested_role == "macos-15-arm64"' "$runner"
rg -Fq 'prepare_authenticated_pkg_stage || return 1' "$runner"
rg -Fq 'currentInboxCreatedFromVerifiedStage:true' "$runner"
rg -Fq 'BURL-O001 import lacks the immediately preceding verified macOS 26 inbox' "$runner"
for ticket in BURL-H001 BURL-H002 BURL-I001 BURL-L001 BURL-O001; do
  spike_block "$ticket" | rg -Fq 'coordinator_manifest = '
  verification_block "$ticket" | rg -Fq -- '--manifest-path '
done

# The seal boundary validates both the manifest-owned byte inventory and the
# contract-derived producer paths. The dedicated fixture exercises each ticket
# plus runs/logs/artifacts/results/handoff and the authenticated PKG handoff.
seal_fixture=$root/scripts/test-seal-validators.sh
rg -Fq 'validate_contract_ticket_bundle BURL-H001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle BURL-H002' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle BURL-I001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle BURL-L001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle BURL-O001' "$seal_fixture"
rg -Fq 'stage-authenticated-role-bundle.sh' "$seal_fixture"

# The aggregate collector's compatibility-stage branch is a production
# contract: this executable corpus builds local artifact/REST/receipt/lineage
# transports and observes every closed BURL-M003 rejection code from the real
# collector implementation.
compatibility_fixture=$root/scripts/test-compatibility-stage-rejections.sh
[[ -x $compatibility_fixture ]]
for code in missing duplicate substituted expired digest-mismatch unattested wrong-signer wrong-run wrong-role wrong-seal stale-producer-receipt noncanonical-lineage lineage-sha-mismatch consumer-unbound unexpected; do
  rg -Fq "compatibility-stage-$code" "$compatibility_fixture"
done
rg -Fq 'valid-burl-o001' "$compatibility_fixture"
rg -Fq 'valid-no-stage-ticket' "$compatibility_fixture"
interface_fixture=$root/scripts/test-compatibility-stage-interface.sh
[[ -x $interface_fixture ]]
rg -Fq 'exactly 26 fields' "$interface_fixture"

# A role with a viewport-bound macOS 26 profile must derive `verified` from a
# trusted Flutter app observation. This host-independent harness supplies the
# macOS system/Flutter boundary and exercises both exact and mismatched values;
# the production launcher still invokes the real hosted macOS APIs.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-role-viewport.XXXXXXXX")
trap '[[ ${BURLMD_KEEP_FIXTURE_TMP:-} == 1 ]] || rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/source/fixture" "$tmp/source/integration_test" "$tmp/bin"
printf 'fixture\n' >"$tmp/source/fixture/input.txt"
printf '[package]\nname = "fixture"\nversion = "0.1.0"\nedition = "2024"\n' >"$tmp/source/fixture/Cargo.toml"
printf '# This file is automatically @generated by Cargo.\nversion = 4\n\n[[package]]\nname = "fixture"\nversion = "0.1.0"\n' >"$tmp/source/fixture/Cargo.lock"
printf '// fixture\n' >"$tmp/source/integration_test/fixture_test.dart"
git -C "$tmp/source" init -q
git -C "$tmp/source" config user.email fixture@example.invalid
git -C "$tmp/source" config user.name fixture
git -C "$tmp/source" add .
git -C "$tmp/source" commit -qm fixture
source_sha=$(git -C "$tmp/source" rev-parse HEAD)
jq -cn --arg sha "$source_sha" --arg nonce 0123456789abcdef0123456789abcdef '
  {ticketIdentity:"BURL-H001",releaseIdentity:"fixture",trustAnchorSha:$sha,testedSourceSha:$sha,workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",baseSha:$sha,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:["fixture/**"],buildIdentity:("a"*64),corpusIdentity:("b"*64),runIdentity:("managed:"+$nonce),artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{},requiredEvidenceClasses:{"linux-x86_64":["common-functional"],"macos-26-arm64":["common-functional","performance","ast-measurement"],"macos-15-arm64":["common-functional"]}}' >"$tmp/expected.json"
cat >"$tmp/bin/taplo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case ${!#} in
  ci_bootstrap.ci_role_evidence_schema_version) printf '15\n' ;;
  'ci_bootstrap.ticket_evidence_profiles."BURL-H001"."macos-26-arm64"') printf '%s\n' '["common-functional","performance","ast-measurement"]' ;;
  reference_profiles.github-macos-26-arm64) printf '%s\n' '{"runner_label":"macos-26","os":"macos","architecture":"aarch64","os_major":26,"cpu_model_contains":"Apple M1","logical_cpu_count":3,"memory_bytes":7000000000,"storage_bytes":14000000000,"logical_viewport_width":1920,"logical_viewport_height":1080,"logical_viewport_refresh_hz":60}' ;;
  'spikes[*]') printf '%s\n' '[{"id":"SPK-BURL-H001","path":"fixture","create_commands":[{"workdir":".","command":"cargo init --bin fixture"}],"verification_steps":[{"run_role":"macos-26-performance","workdir":"fixture","command":"cargo test --locked --manifest-path Cargo.toml --all-targets; mkdir -p runs handoff/outbox && printf run > runs/ast.json && printf handoff > handoff/outbox/ast.tar.zst && printf hash > handoff/outbox/ast.sha256 && true --output runs/ast.json --handoff-bundle handoff/outbox/ast.tar.zst --handoff-sha256 handoff/outbox/ast.sha256"},{"run_role":"macos-26-performance","workdir":"fixture","command":"setsid bash -ceu '\''while :; do sleep 1; done'\'' & true"}]}]' ;;
  *) exit 64 ;;
esac
EOF
cat >"$tmp/bin/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
  --version) printf 'fixture flutter\n' ;;
  create) target=${!#}; mkdir -p "$target/lib" "$target/macos/Runner" ;;
  run)
    for arg in "$@"; do [[ $arg == --dart-define=BURLMD_VIEWPORT_RESULT=* ]] && result=${arg#--dart-define=BURLMD_VIEWPORT_RESULT=}; done
    [[ -n ${result:-} ]] || exit 64
    if [[ $(<"$BURLMD_VIEWPORT_FIXTURE_MODE") == mismatch ]]; then jq -cn '{width:1919,height:1080,refreshHz:60,devicePixelRatio:2}' >"$result"; else jq -cn '{width:1920,height:1080,refreshHz:60,devicePixelRatio:2}' >"$result"; fi
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -m ]] && printf 'arm64\n' || printf 'Darwin\n'
EOF
cat >"$tmp/bin/sysctl" <<'EOF'
#!/usr/bin/env bash
case ${2:-} in hw.logicalcpu) printf '3\n';; hw.memsize) printf '7000000000\n';; machdep.cpu.brand_string) printf '%s\n' "${BURLMD_PROFILE_CPU:-Apple M1 fixture}";; *) exit 64;; esac
EOF
cat >"$tmp/bin/sw_vers" <<'EOF'
#!/usr/bin/env bash
version=${BURLMD_PROFILE_VERSION:-26.0}
if [[ ${1:-} == -productVersion ]]; then printf '%s\n' "$version"; else printf 'ProductName:\tmacOS\nProductVersion:\t%s\n' "$version"; fi
EOF
cat >"$tmp/bin/check-jsonschema" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/cargo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/df" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  -P) [[ $# == 2 && ${2:-} == "${BURLMD_EXPECTED_DF_TARGET:?}" ]] || exit 64
      printf '%s\n' 'Filesystem 512-blocks Used Available Capacity Mounted on' '/dev/disk9s1 1000 100 900 10% /fixture-volume'
      ;;
  -Pk) [[ $# == 2 && ${2:-} == "${BURLMD_EXPECTED_DF_TARGET:?}" ]] || exit 64
       printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' '/dev/disk9s1 500 50 450 10% /fixture-volume'
       ;;
  *) exit 64;;
esac
EOF
cat >"$tmp/bin/diskutil" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == info && ${2:-} == -plist && $# == 3 ]] || exit 64
[[ ${3:-} == /dev/disk9s1 ]] || exit 65
printf '%s\n' '<plist><dict><key>FilesystemType</key><string>fixturefs</string></dict></plist>'
EOF
cat >"$tmp/bin/plutil" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -extract && ${2:-} == FilesystemType && ${3:-} == raw && ${4:-} == -o && ${5:-} == - && ${6:-} == - ]] || exit 64
cat >/dev/null
printf 'fixturefs\n'
EOF
for native_tool in xcrun xcodebuild clang clang++ ld libtool lipo install_name_tool arch open; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/$native_tool"
done
cat >"$tmp/bin/perl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  [[ $1 == -- ]] && { shift; exec "$@"; }
  shift
done
exit 64
EOF
chmod +x "$tmp/bin"/*

# Execute the real launcher rather than pattern-matching its viewport helper.
# Command doubles live in the disposable tested checkout; the launcher gets no
# special fixture flag or production bypass.
cp -a "$tmp/bin" "$tmp/source/fixture-bin"
git -C "$tmp/source" add fixture-bin
git -C "$tmp/source" commit -qm 'fixture tools'
source_sha=$(git -C "$tmp/source" rev-parse HEAD)
signer_sha=$(git -C "$root" rev-parse HEAD)
signer_git_common=$(git -C "$root" rev-parse --git-common-dir)
[[ $signer_git_common == /* && -d $signer_git_common && ! -L $signer_git_common ]] || { echo 'viewport fixture requires the trusted checkout common Git directory' >&2; exit 1; }
jq --arg sha "$source_sha" --arg signer "$signer_sha" '.trustAnchorSha = $sha | .testedSourceSha = $sha | .workflowSignerSha = $signer | .baseSha = $sha' "$tmp/expected.json" >"$tmp/expected.next"
mv "$tmp/expected.next" "$tmp/expected.json"
env_bin=$(readlink -f "$(command -v env)")
sh_bin=$(readlink -f "$(command -v sh)")
[[ $env_bin == /nix/store/* && $sh_bin == /nix/store/* ]] || { echo 'viewport fixture requires locked shell tools' >&2; exit 1; }
run_viewport_fixture() {
  local mode=$1 output=$2 log=$3 version=${4:-26.0} cpu=${5:-Apple M1 fixture}
  printf '%s\n' "$mode" >"$tmp/viewport-mode"
  if env BURLMD_VIEWPORT_FIXTURE_MODE="$tmp/viewport-mode" BURLMD_PROFILE_VERSION="$version" BURLMD_PROFILE_CPU="$cpu" BURLMD_ROLE_RUNTIME_ROOT="$tmp/runtime-$mode" BURLMD_EXPECTED_DF_TARGET="$output" ImageOS=fixture ImageVersion=fixture PATH="$tmp/source/fixture-bin:$(dirname "$(readlink -f "$(command -v zstd)")"):$PATH" EXPECTED_IDENTITY="$tmp/expected.json" \
    bwrap --die-with-parent --tmpfs / --proc /proc --dev /dev --ro-bind /nix /nix --ro-bind /etc /etc \
      --dir /home --dir /home/oscar --dir /home/oscar/GitHub --dir /home/oscar/GitHub/burlmd --ro-bind "$signer_git_common" "$signer_git_common" --ro-bind "$root" "$root" \
      --dir /tmp --bind "$tmp" "$tmp" --dir /bin --ro-bind "$sh_bin" /bin/sh --dir /usr --dir /usr/bin --dir /usr/sbin \
      --ro-bind "$env_bin" /usr/bin/env --ro-bind "$tmp/source/fixture-bin/open" /usr/bin/open --ro-bind "$tmp/source/fixture-bin/df" /bin/df --ro-bind "$tmp/source/fixture-bin/diskutil" /usr/sbin/diskutil --ro-bind "$tmp/source/fixture-bin/plutil" /usr/bin/plutil \
      "$runner" macos-26-arm64 "$tmp/source" "$output" >"$log" 2>&1; then
    return 0
  fi
  return 1
}
if ! run_viewport_fixture exact "$tmp/viewport-exact" "$tmp/viewport-exact.log"; then
  cat "$tmp/viewport-exact.log" >&2
  exit 1
fi
jq -e '.roleEvidence.viewport.verified == true and .roleEvidence.viewport.width == 1920 and .roleEvidence.viewport.height == 1080 and .roleEvidence.viewport.refreshHz == 60' "$tmp/viewport-exact/ci-role-evidence.json" >/dev/null
if run_viewport_fixture mismatch "$tmp/viewport-mismatch" "$tmp/viewport-mismatch.log"; then
  echo 'mismatched macOS Flutter viewport was accepted' >&2
  exit 1
fi
rg -Fq 'trusted macOS Flutter logical viewport differs from the reference profile' "$tmp/viewport-mismatch.log"
if run_viewport_fixture exact "$tmp/host-major-mismatch" "$tmp/host-major-mismatch.log" 25.0; then
  echo 'mismatched macOS major version was accepted' >&2
  exit 1
fi
rg -Fq 'observed OS major 25 does not match documented 26' "$tmp/host-major-mismatch.log"
if run_viewport_fixture exact "$tmp/host-cpu-mismatch" "$tmp/host-cpu-mismatch.log" 26.0 'Apple M2 fixture'; then
  echo 'mismatched macOS CPU model was accepted' >&2
  exit 1
fi
rg -Fq 'observed CPU model does not contain documented Apple M1' "$tmp/host-cpu-mismatch.log"

printf 'managed role production contract fixture passed\n'
