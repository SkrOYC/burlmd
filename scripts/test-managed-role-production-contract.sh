#!/usr/bin/env bash
# Contract fixture for the production role runner. It stays parser-free so it
# can run before the locked CI closure is installed; runtime parsing remains
# owned by taplo in run-managed-role.sh.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
runner=$root/scripts/run-managed-role.sh

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
AST-H001:1:1:1:0
PATH-H002:1:1:1:0
ASSET-I001:1:1:1:0
GIT-L001:1:1:1:0
PKG-M001:0:10:5:4
EOF

# The only authorised cross-role candidate input is packaged through the
# authenticated macOS 26 stage. It is not a candidate source transfer.
rg -Fq 'requires_authenticated_stage_role = "macos-26-arm64"' "$contract"
rg -Fq 'required_members = ["handoff/outbox/macos-current-construction.tar.zst", "handoff/outbox/macos-current-construction.sha256"]' "$contract"
rg -Fq 'BURLMD_AUTHENTICATED_STAGE_ROOT' "$runner"
rg -Fq 'authenticated-producer-stage-v1' "$runner"
rg -Fq 'select((has("run_role") | not) or (.run_role | test($pattern)))' "$runner"

# Production manifests bind source identity, trust-owned command outputs, and
# runner observations rather than hard-coded host labels/constants.
rg -Fq 'tested source HEAD does not match expected identity' "$runner"
rg -Fq 'ImageOS is required from the hosted runner' "$runner"
rg -Fq 'ImageVersion is required from the hosted runner' "$runner"
rg -Fq 'os_release=$(tr' "$runner"
rg -Fq 'logicalCpuCount:$observedCpus' "$runner"
# CI-M003 stages a disposable execution checkout after trusted prefetch.  The
# output collector must therefore bind declared paths to that staged root,
# rather than accidentally reading the authenticated source checkout.
rg -Fq 'prepare_candidate_dependencies' "$runner"
rg -Fq '.verification_steps[]?' "$runner"
rg -Fq '.create_commands[]?' "$runner"
rg -Fq 'cargo fetch --locked --manifest-path "$resolved_manifest"' "$runner"
rg -Fq 'flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$pub_directory"' "$runner"
rg -Fq 'flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$candidate_workspace"' "$runner"
rg -Fq 'cargo fetch --locked --manifest-path "$candidate_workspace/rust/Cargo.toml"' "$runner"
rg -Fq 'cargo metadata --offline --locked --manifest-path rust/Cargo.toml --format-version 1' "$runner"
rg -Fq 'if [[ $role == linux-x86_64 ]]; then' "$runner"
rg -Fq 'Hosted macOS executes directly from this fresh workspace' "$runner"
rg -Fq 'destination=${canonical#"$candidate_execution_root/$ticket_root/"}' "$runner"
rg -Fq 'scan("--(?:output|stdout|stderr|copy-artifact-to|success-marker|handoff-bundle|handoff-sha256|sha256-output|output-archive|output-dir|append-run)[[:space:]]+([^[:space:]]+)")[0]' "$runner"
rg -Fq 'runs/, logs/, artifacts/, results/, and handoff/' "$runner"
rg -Fq 'observe_linux_private_sway_viewport' "$runner"
rg -Fq 'flutter run -d macos --no-hot --pid-file' "$runner"
rg -Fq 'maximumFramesPerSecond' "$runner"
rg -Fq "CI-M003's managed profiles are explicitly non-authoritative" "$runner"
rg -Fq 'observed_cpus=$(sysctl -n hw.logicalcpu)' "$runner"
# Linux candidate descendants are contained by Bubblewrap's PID namespace
# reaper. The lock remains the trusted host-side proof that the namespace has
# fully exited before the runner can package role output. Hosted macOS instead
# records bounded marker/process-group cleanup and must make no lifecycle
# containment or zero-survivor assertion.
rg -Fq 'locked Bubblewrap 0.11.2 is required for Linux candidate isolation' "$runner"
rg -Fq -- '--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv' "$runner"
rg -Fq 'ip link set lo up || exit 2' "$runner"
rg -Fq -- '--lock-file "$lock_destination"' "$runner"
rg -Fq 'confirm_linux_namespace_teardown' "$runner"
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
rg -Fq 'PKG-M001 import lacks the immediately preceding verified macOS 26 inbox' "$runner"
for ticket in AST-H001 PATH-H002 ASSET-I001 GIT-L001 PKG-M001; do
  spike_block "$ticket" | rg -Fq 'coordinator_manifest = '
  verification_block "$ticket" | rg -Fq -- '--manifest-path '
done

# The seal boundary validates both the manifest-owned byte inventory and the
# contract-derived producer paths. The dedicated fixture exercises each ticket
# plus runs/logs/artifacts/results/handoff and the authenticated PKG handoff.
seal_fixture=$root/scripts/test-seal-validators.sh
rg -Fq 'validate_contract_ticket_bundle AST-H001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle PATH-H002' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle ASSET-I001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle GIT-L001' "$seal_fixture"
rg -Fq 'validate_contract_ticket_bundle PKG-M001' "$seal_fixture"
rg -Fq 'stage-authenticated-role-bundle.sh' "$seal_fixture"

# A role with a viewport-bound macOS 26 profile must derive `verified` from a
# trusted Flutter app observation. This host-independent harness supplies the
# macOS system/Flutter boundary and exercises both exact and mismatched values;
# the production launcher still invokes the real hosted macOS APIs.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-role-viewport.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
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
  {ticketIdentity:"AST-H001",releaseIdentity:"fixture",trustAnchorSha:$sha,testedSourceSha:$sha,workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",baseSha:$sha,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:["fixture/**"],buildIdentity:("a"*64),corpusIdentity:("b"*64),runIdentity:("managed:"+$nonce),artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{},requiredEvidenceClasses:{"linux-x86_64":["common-functional"],"macos-26-arm64":["common-functional","performance","ast-measurement"],"macos-15-arm64":["common-functional"]}}' >"$tmp/expected.json"
cat >"$tmp/bin/taplo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case ${!#} in
  ci_bootstrap.ci_role_evidence_schema_version) printf '9\n' ;;
  'ci_bootstrap.ticket_evidence_profiles."AST-H001"."macos-26-arm64"') printf '%s\n' '["common-functional","performance","ast-measurement"]' ;;
  reference_profiles.github-macos-26-arm64) printf '%s\n' '{"runner_label":"macos-26","architecture":"aarch64","logical_cpu_count":3,"memory_bytes":7000000000,"storage_bytes":14000000000,"logical_viewport_width":1920,"logical_viewport_height":1080,"logical_viewport_refresh_hz":60}' ;;
  'spikes[*]') printf '%s\n' '[{"id":"SPK-AST-H001","path":"fixture","create_commands":[{"workdir":".","command":"cargo init --bin fixture"}],"verification_steps":[{"run_role":"macos-26-performance","workdir":"fixture","command":"cargo test --locked --manifest-path Cargo.toml --all-targets; mkdir -p runs handoff/outbox && printf run > runs/ast.json && printf handoff > handoff/outbox/ast.tar.zst && printf hash > handoff/outbox/ast.sha256 && true --output runs/ast.json --handoff-bundle handoff/outbox/ast.tar.zst --handoff-sha256 handoff/outbox/ast.sha256"},{"run_role":"macos-26-performance","workdir":"fixture","command":"setsid bash -ceu '\''while :; do sleep 1; done'\'' & true"}]}]' ;;
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
case ${2:-} in hw.logicalcpu) printf '3\n';; hw.memsize) printf '7000000000\n';; machdep.cpu.brand_string) printf 'Apple M1 fixture\n';; *) exit 64;; esac
EOF
cat >"$tmp/bin/sw_vers" <<'EOF'
#!/usr/bin/env bash
printf 'ProductName:\tmacOS\nProductVersion:\t26.0\n'
EOF
cat >"$tmp/bin/check-jsonschema" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/cargo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/taplo" "$tmp/bin/flutter" "$tmp/bin/uname" "$tmp/bin/sysctl" "$tmp/bin/sw_vers" "$tmp/bin/check-jsonschema" "$tmp/bin/cargo"
run_viewport_fixture() {
  local mode=$1 output=$2
  printf '%s\n' "$mode" >"$tmp/mode"
  ImageOS=fixture ImageVersion=fixture PATH="$tmp/bin:$PATH" BURLMD_VIEWPORT_FIXTURE_MODE="$tmp/mode" EXPECTED_IDENTITY="$tmp/expected.json" \
    "$runner" macos-26-arm64 "$tmp/source" "$output"
}
run_viewport_fixture pass "$tmp/pass"
jq -e '.roleEvidence.viewport == {width:1920,height:1080,refreshHz:60,verified:true}' "$tmp/pass/ci-role-evidence.json" >/dev/null
# The first candidate command exits cleanly. The second detaches a
# marker-tagged process, which bounded cleanup records and terminates. The
# manifest and sealed inner bundle must contain the complete aggregate.
cleanup="$tmp/pass/results/macos-bounded-cleanup.json"
jq -e '
  .mode == "bounded-marker-process-group-cleanup" and
  .containmentClaim == false and .zeroSurvivorClaim == false and
  .sessionCount == 2 and (.sessions | length == 2) and
  .sessions[0].session == 1 and .sessions[1].session == 2 and
  .sessions[0].knownCandidateProcessesRemain == false and
  .sessions[1].knownCandidateProcessesBeforeCleanup == true and
  .sessions[1].knownCandidateProcessesRemain == false and
  .final == .sessions[1] and .worst == .sessions[1]
' "$cleanup" >/dev/null
cleanup_hash=$(sha256sum "$cleanup" | awk '{print $1}')
cleanup_bytes=$(wc -c <"$cleanup")
jq -e --arg hash "$cleanup_hash" --argjson bytes "$cleanup_bytes" '
  any(.roleEvidence.internalArtifacts[];
    .name == "results/macos-bounded-cleanup.json" and .sha256 == $hash and .bytes == $bytes)
' "$tmp/pass/ci-role-evidence.json" >/dev/null
tar -I 'zstd -19 --no-progress' -xOf "$tmp/pass/ci-role-evidence.tar.zst" results/macos-bounded-cleanup.json | cmp -s - "$cleanup"
if run_viewport_fixture mismatch "$tmp/mismatch"; then
  echo 'macOS viewport mismatch was accepted' >&2
  exit 1
fi

printf 'managed role production contract fixture passed\n'
