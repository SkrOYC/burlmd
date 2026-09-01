#!/usr/bin/env bash
# Tests for the trusted launcher boundary. Synthetic transports never invoke
# the production collector; their observation-only work uses the harness.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
if [[ ${BURLMD_MANAGED_EVIDENCE_CLIENT_LOCKED_SHELL:-} != 1 ]]; then
  exec "$root/scripts/ci-devenv.sh" env BURLMD_MANAGED_EVIDENCE_CLIENT_LOCKED_SHELL=1 "$0" "$@"
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/managed-evidence-client-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

# The production grammar is exactly run|collect. Its reserved fixture prefix
# is rejected before any credential, checkout, or report path is used.
set +e
env ME_TRANSPORT=fixture bash "$root/scripts/managed-evidence.sh" collect >"$tmp/env.out" 2>"$tmp/env.err"
status=$?
set -e
[[ $status == 2 ]]
rg -Fq 'reserved fixture environment' "$tmp/env.err"

# A match near the front of a large environment used to make the old
# `compgen | rg -q` guard fail through SIGPIPE under pipefail. The production
# launcher must still reject the reserved namespace before parsing arguments.
set +e
(
  for fixture_index in $(seq 1 12000); do
    export "ZZ_MANAGED_EVIDENCE_FIXTURE_$fixture_index=fixture"
  done
  export ME_TRANSPORT=fixture
  bash "$root/scripts/managed-evidence.sh" collect
) >"$tmp/large-env.out" 2>"$tmp/large-env.err"
status=$?
set -e
[[ $status == 2 ]]
rg -Fq 'reserved fixture environment' "$tmp/large-env.err"

set +e
bash "$root/scripts/managed-evidence.sh" test-collect >"$tmp/mode.out" 2>"$tmp/mode.err"
status=$?
set -e
[[ $status == 2 ]]
rg -Fq 'usage:' "$tmp/mode.err"

# Local collection is deliberately independent of GitHub's ambient workflow
# environment. Its CLI grammar accepts only the literal fresh attempt, before
# it resolves a checkout, token, or output worktree.
for bad_attempt in 0 2 01 1.0 -1 '+1' '1 '; do
  set +e
  bash "$root/scripts/managed-evidence.sh" collect \
    --ticket BURL-M003 --trust-anchor-sha 0123456789012345678901234567890123456789 \
    --source-ref refs/heads/master --tested-source-sha 0123456789012345678901234567890123456789 \
    --base-sha 0123456789012345678901234567890123456789 \
    --run-identity managed:0123456789abcdef0123456789abcdef --run-id 1 --attempt "$bad_attempt" \
    --output "$tmp/literal-attempt.json" >"$tmp/literal-attempt.out" 2>"$tmp/literal-attempt.err"
  status=$?
  set -e
  [[ $status == 2 ]]
  rg -Fq 'invalid collection identity' "$tmp/literal-attempt.err"
done
! rg -Fq 'GITHUB_RUN_ATTEMPT' "$root/scripts/managed-evidence.sh"

# The harness is intentionally non-authoritative: it can only emit an
# observation below its temporary root and cannot choose a declared report.
bash "$root/scripts/managed-evidence-test-harness.sh" --workspace "$tmp" --contracts "$root/.constitution/tech-spec/contracts"
jq -e '.kind == "managed-evidence-test-observation" and .status == "observed"' "$tmp/observation.json" >/dev/null
! rg -Fq '"accepted"' "$tmp/observation.json"

# The canonical absolute launcher must resolve its own checkout even when the
# caller is outside any Git repository. Use an explicitly attached fixture
# checkout so this rejection remains deterministic when this test's checkout
# is detached.
outside_launcher_root=$tmp/outside-launcher
outside_cwd=$outside_launcher_root/caller
outside_evidence=$outside_launcher_root/evidence
fixture_launcher_root=$outside_launcher_root/attached-launcher
mkdir -p "$outside_cwd" "$outside_evidence"
git -C "$outside_evidence" init --quiet
git clone --quiet "$root" "$fixture_launcher_root"
git -C "$fixture_launcher_root" switch --quiet -c managed-evidence-attached-fixture
outside_head=$(git -C "$fixture_launcher_root" rev-parse HEAD)
set +e
(
  cd "$outside_cwd"
  bash "$fixture_launcher_root/scripts/managed-evidence.sh" collect \
      --ticket BURL-M003 --trust-anchor-sha "$outside_head" --source-ref refs/heads/master \
      --tested-source-sha "$outside_head" --base-sha "$outside_head" \
      --run-identity managed:0123456789abcdef0123456789abcdef --run-id 1 --attempt 1 \
      --output "$outside_evidence/managed-evidence.json"
) >"$tmp/outside-launcher.out" 2>"$tmp/outside-launcher.err"
outside_status=$?
set -e
[[ $outside_status == 2 ]]
rg -Fq 'trust anchor must be clean, detached, and at supplied SHA' "$tmp/outside-launcher.err"

# The output path, not an ambient environment variable, identifies the
# evidence checkout. Reject both an anchor-local report and an arbitrary
# non-repository path before the launcher can inspect any trust state.
git -C "$fixture_launcher_root" switch --quiet --detach "$outside_head"
set +e
(
  cd "$outside_cwd"
  bash "$fixture_launcher_root/scripts/managed-evidence.sh" collect \
      --ticket BURL-M003 --trust-anchor-sha "$outside_head" --source-ref refs/heads/master \
      --tested-source-sha "$outside_head" --base-sha "$outside_head" \
      --run-identity managed:0123456789abcdef0123456789abcdef --run-id 1 --attempt 1 \
      --output "$fixture_launcher_root/managed-evidence.json"
) >"$tmp/anchor-output.out" 2>"$tmp/anchor-output.err"
anchor_output_status=$?
(
  cd "$outside_cwd"
  bash "$fixture_launcher_root/scripts/managed-evidence.sh" collect \
      --ticket BURL-M003 --trust-anchor-sha "$outside_head" --source-ref refs/heads/master \
      --tested-source-sha "$outside_head" --base-sha "$outside_head" \
      --run-identity managed:0123456789abcdef0123456789abcdef --run-id 1 --attempt 1 \
      --output "$outside_launcher_root/not-a-worktree/managed-evidence.json"
) >"$tmp/non-worktree-output.out" 2>"$tmp/non-worktree-output.err"
non_worktree_status=$?
set -e
[[ $anchor_output_status == 2 ]]
rg -Fq 'output must be under the evidence worktree and outside trust anchor' "$tmp/anchor-output.err"
[[ $non_worktree_status == 2 ]]
rg -Fq 'output must be inside an evidence Git worktree' "$tmp/non-worktree-output.err"
for contract_path in CONTRACT ROLE_SCHEMA AGGREGATE_SCHEMA RECEIPT_TRANSPORT_SCHEMA RESULT_SCHEMA; do
  rg -Fq "readonly $contract_path=\$anchor_root/" "$root/scripts/managed-evidence.sh"
done

# Typed role rejection details must survive both the candidate-observation
# command substitution inside receipt_role and a caller-owned receipt channel.
# These are deliberately direct function fixtures: REST/download transports are
# reduced to safe local data while the production receipt branches themselves
# choose and write their codes.
receipt_channel_functions=$tmp/receipt-channel-functions.sh
{
  awk '/^candidate_reject\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^role_reject\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^role_label\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^seal_observation\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^artifact_observation\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^filesystem_manifest_verified\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^receipt_role\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
} >"$receipt_channel_functions"
receipt_fixture_root=$tmp/receipt-channel
mkdir -p "$receipt_fixture_root/launcher"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$receipt_fixture_root/launcher/validate-sealing-receipt.sh"
chmod +x "$receipt_fixture_root/launcher/validate-sealing-receipt.sh"
(
  source "$receipt_channel_functions"
  launcher_dir=$receipt_fixture_root/launcher
  tmp=$receipt_fixture_root
  ticket=BURL-M003
  role=linux-x86_64
  run_identity=managed:0123456789abcdef0123456789abcdef
  run_id=1; attempt=1
  anchor=1111111111111111111111111111111111111111
  tested=$anchor; workflow_signer=$anchor; base=2222222222222222222222222222222222222222
  expected_digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  fixture_hash=$expected_digest
  fixture_wrong_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  inventory=$receipt_fixture_root/inventory.json; jobs=$receipt_fixture_root/jobs.json
  printf '%s\n' '{"artifacts":[]}' >"$inventory"
  expected=$receipt_fixture_root/expected.json
  jq -cn '{requiredRoleGuards:{"linux-x86_64":{runnerLabel:"ubuntu-24.04"},"macos-26-arm64":{runnerLabel:"macos-26"},"macos-15-arm64":{runnerLabel:"macos-15"}}}' >"$expected"
  seal_jobs() {
    case ${fixture_seal:-valid} in
      missing) printf '%s\n' '{"jobs":[]}' ;;
      duplicate) jq -cn '[range(2) | {id:(. + 2),name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"success",check_run_url:("https://api.github.com/check-runs/" + ((. + 2) | tostring))}] | {jobs:.}' ;;
      wrong-label) jq -cn '{jobs:[{id:2,name:"seal",labels:["macos-26"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      self-hosted) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04","self-hosted"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      in-progress) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"in_progress",conclusion:null,check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      failed) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"failure",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      wrong-run) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04"],run_id:99,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      bad-check-locator) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/invalid"}]}' ;;
      bad-job-id) jq -cn '{jobs:[{id:0,name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
      multi-role) jq -cn '{jobs:[{id:2,name:"linux / seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"},{id:12,name:"macos_26 / seal",labels:["macos-26"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/12"},{id:22,name:"macos_15 / seal",labels:["macos-15"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/22"}]}' ;;
      *) jq -cn '{jobs:[{id:2,name:"seal",labels:["ubuntu-24.04"],run_id:1,status:"completed",conclusion:"success",check_run_url:"https://api.github.com/check-runs/2"}]}' ;;
    esac
  }
  seal_jobs >"$jobs"
  workflow_path() { printf .github/workflows/ci-role-linux-x86-64.yml; }
  artifact_by_name() {
    local ignored=$1 name=$2 id digest=$fixture_hash
    case "$name" in
      managed-evidence-expected-*) id=1; [[ $fixture_artifact == expected ]] && digest=$fixture_wrong_hash;;
      managed-evidence-candidate-*) id=2; [[ $fixture_artifact == candidate ]] && digest=$fixture_wrong_hash;;
      managed-evidence-sealed-*) id=3; [[ $fixture_artifact == sealed ]] && digest=$fixture_wrong_hash;;
      managed-evidence-seal-receipt-*) id=4;;
      *) return 1;;
    esac
    jq -cn --argjson id "$id" --arg name "$name" --arg digest "$digest" '{id:$id,name:$name,digest:("sha256:" + $digest)}'
  }
  download_sealing_receipt_zip() {
    local ignored=$1 receipt=$2 bundle=$3 nonce=${run_identity#managed:}
    jq -cn --arg ticket "$ticket" --arg role "$role" --arg nonce "$nonce" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg digest "$expected_digest" --argjson check "${fixture_receipt_check:-2}" '
      def artifact($id; $name): {artifactId:$id,artifactName:$name,uploadActionDigest:("a" * 64),artifactDigest:("sha256:" + ("a" * 64))};
      {schemaVersion:2,ticketIdentity:$ticket,role:$role,workflowRunId:1,runAttempt:1,trustAnchorSha:$anchor,testedSourceSha:$tested,workflowSignerSha:$signer,workflowSignerRef:"refs/heads/master",baseSha:$base,artifactNonce:$nonce,expectedIdentitySha256:$digest,runnerEnvironmentClaim:"github-hosted",sealingCheckRunId:$check,workflowPath:".github/workflows/ci-role-linux-x86-64.yml",expectedArtifact:artifact(1; "managed-evidence-expected-" + $nonce),candidateArtifact:artifact(2; "managed-evidence-candidate-" + $role + "-" + $nonce),sealedArtifact:artifact(3; "managed-evidence-sealed-" + $role + "-" + $nonce),roleBundleSha256:("a" * 64),sealedBundleSha256:("a" * 64),compatibilityStage:null}' >"$receipt"
    case ${fixture_receipt_origin:-valid} in
      wrong-run) jq '.workflowRunId = 99' "$receipt" >"$receipt.next";;
      wrong-attempt) jq '.runAttempt = 99' "$receipt" >"$receipt.next";;
      wrong-runner) jq '.runnerEnvironmentClaim = "self-hosted"' "$receipt" >"$receipt.next";;
      wrong-signer) jq '.workflowSignerSha = ("f" * 40)' "$receipt" >"$receipt.next";;
      wrong-source) jq '.testedSourceSha = ("f" * 40)' "$receipt" >"$receipt.next";;
      wrong-workflow) jq '.workflowPath = ".github/workflows/other.yml"' "$receipt" >"$receipt.next";;
      *) :;;
    esac
    [[ ! -e $receipt.next ]] || mv "$receipt.next" "$receipt"
    : >"$bundle"
  }
  candidate_observation() {
    if [[ -n ${fixture_candidate_code:-} ]]; then candidate_reject "$fixture_candidate_code" "$3"; return 1; fi
    jq -cn '{checkRunId:2}'
  }
  download_one_member_zip() { : >"$3"; }
  safe_sealed_bundle() { : >"$2"; }
  safe_role_bundle() {
    if [[ $fixture_manifest == filesystem ]]; then jq -cn '{roleEvidence:{environment:{filesystem:""},compatibilityStage:null}}' >"$3"
    else jq -cn --argjson stage "$fixture_stage" '{roleEvidence:{environment:{filesystem:"fixture"},compatibilityStage:$stage}}' >"$3"; fi
  }
  sha256_file() { printf 'a%.0s' {1..64}; }
  manifest_shape_valid() { :; }
  verify_attestation() {
    if [[ -n ${fixture_attestation_code:-} && ${fixture_attestation_kind:-} == "$3" ]]; then role_reject "$5" "$fixture_attestation_code"; return 1; fi
    case "$3" in sealed) sealed_attestation_bundle_sha=$(sha256_file "$1");; receipt) receipt_attestation_bundle_sha=$(sha256_file "$1");; esac
  }
  filesystem_role_verified() { :; }
  assert_receipt_code() {
    local name=$1 expected_code=$2 channel ignored
    channel=$receipt_fixture_root/$name.code
    rm -f -- "$channel"
    if ignored=$(receipt_role "$role" "$inventory" "$jobs" "$channel"); then
      echo "$name unexpectedly accepted" >&2; exit 1
    fi
    [[ $(<"$channel") == "$expected_code" ]] || { echo "$name: $(<"$channel")" >&2; exit 1; }
  }
  for fixture_artifact in expected candidate sealed; do
    fixture_candidate_code=; fixture_manifest=valid; fixture_stage=null
    assert_receipt_code "artifact-$fixture_artifact" artifact-digest-mismatch
  done
  fixture_artifact=; fixture_candidate_code=candidate-topology-mismatch; fixture_manifest=valid; fixture_stage=null
  assert_receipt_code candidate-subshell candidate-topology-mismatch
  fixture_artifact=; fixture_candidate_code=; fixture_manifest=filesystem; fixture_stage=null
  assert_receipt_code filesystem filesystem-evidence-mismatch
  ticket=BURL-O001; role=macos-26-arm64; fixture_artifact=; fixture_candidate_code=; fixture_manifest=valid; fixture_stage=null
  assert_receipt_code compatibility-missing compatibility-stage-missing
  ticket=BURL-M003; role=linux-x86_64
  fixture_artifact=; fixture_candidate_code=; fixture_manifest=valid; fixture_stage='{"unexpected":true}'
  assert_receipt_code compatibility compatibility-stage-unexpected
  ticket=BURL-M003; role=linux-x86_64; fixture_artifact=; fixture_candidate_code=; fixture_manifest=valid; fixture_stage=null; fixture_receipt_origin=valid
  fixture_seal=multi-role; seal_jobs >"$jobs"
  for role_and_locator in linux-x86_64:2 macos-26-arm64:12 macos-15-arm64:22; do
    selector_role=${role_and_locator%%:*}; selector_locator=${role_and_locator#*:}
    selector_channel=$receipt_fixture_root/seal-$selector_role.code
    rm -f -- "$selector_channel"
    selector_observation=$(seal_observation "$jobs" "$selector_role" "$selector_channel") || { echo "$selector_role did not select its own seal" >&2; exit 1; }
    [[ $(jq -r '.jobId' <<<"$selector_observation") == "$selector_locator" ]]
    [[ ! -e $selector_channel ]]
  done
  for fixture_seal in missing:sealing-job-missing duplicate:sealing-job-mismatch wrong-label:sealing-job-mismatch self-hosted:sealing-runner-environment-mismatch in-progress:sealing-job-in-progress failed:sealing-job-failed wrong-run:sealing-job-mismatch bad-check-locator:sealing-job-mismatch bad-job-id:sealing-job-mismatch; do
    seal_case=${fixture_seal%%:*}; seal_code=${fixture_seal#*:}; fixture_seal=$seal_case; fixture_receipt_check=2; seal_jobs >"$jobs"
    assert_receipt_code "seal-$seal_case" "$seal_code"
  done
  fixture_seal=valid; fixture_receipt_check=3; seal_jobs >"$jobs"
  assert_receipt_code receipt-locator sealing-job-mismatch
  fixture_receipt_check=2
  for fixture_receipt_origin in wrong-run:sealing-job-mismatch wrong-attempt:sealing-job-mismatch wrong-runner:sealing-runner-environment-mismatch wrong-signer:untrusted-origin wrong-source:untrusted-origin wrong-workflow:untrusted-origin; do
    origin_case=${fixture_receipt_origin%%:*}; origin_code=${fixture_receipt_origin#*:}; fixture_receipt_origin=$origin_case
    assert_receipt_code "receipt-$origin_case" "$origin_code"
  done
  fixture_receipt_origin=valid; fixture_attestation_code=untrusted-origin; fixture_attestation_kind=sealed
  assert_receipt_code sealed-attestation untrusted-origin
  fixture_attestation_code=attestation-unavailable; fixture_attestation_kind=receipt
  assert_receipt_code receipt-attestation attestation-unavailable
)

# `gh attestation verify` fetches attestations through the GitHub API when no
# bundle is supplied. Its documented exit 1 covers both failed verification and
# service errors, while exit 4 is authentication. Exercise the production
# diagnostic classification with an injectable CLI so transport errors preserve
# the previous report and only durable provenance failures select a rejection.
online_attestation_functions=$tmp/online-attestation-functions.sh
{
  awk '/^role_reject\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^attestation_failure_status\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^verify_attestation\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
} >"$online_attestation_functions"
(
  source "$online_attestation_functions"
  API_TRANSIENT=75; API_PERMISSION=76; API_FAILURE=77
  REPOSITORY=SkrOYC/burlmd
  workflow_signer=1111111111111111111111111111111111111111
  workflow_path() { printf .github/workflows/ci-role-linux-x86-64.yml; }
  tmp=$tmp/online-attestation; mkdir -p "$tmp"
  artifact=$tmp/sealed.tar.zst; : >"$artifact"
  GH_BIN=$tmp/fake-gh
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$GH_FIXTURE_STDERR" >&2' 'exit "$GH_FIXTURE_STATUS"' >"$GH_BIN"
  chmod +x "$GH_BIN"
  assert_online_attestation() {
    local name=$1 kind=$2 gh_status=$3 diagnostic=$4 expected_status=$5 expected_code=${6:-} channel status
    channel=$tmp/$name.code; rm -f -- "$channel"
    export GH_FIXTURE_STATUS=$gh_status GH_FIXTURE_STDERR=$diagnostic
    set +e
    verify_attestation "$artifact" linux-x86_64 "$kind" '' "$channel"
    status=$?
    set -e
    [[ $status == "$expected_status" ]] || { echo "$name returned $status, expected $expected_status" >&2; exit 1; }
    if [[ -n $expected_code ]]; then [[ $(<"$channel") == "$expected_code" ]]; else [[ ! -e $channel ]]; fi
  }
  assert_online_attestation sealed-rate-limit sealed 1 'HTTP 429: rate limit exceeded' "$API_TRANSIENT"
  assert_online_attestation receipt-permission receipt 4 'authentication required' "$API_PERMISSION"
  assert_online_attestation sealed-api-failure sealed 1 'HTTP 422: API request failed' "$API_FAILURE"
  assert_online_attestation sealed-cryptographic sealed 1 'failed to verify attestation: signature mismatch' 1 untrusted-origin
  assert_online_attestation receipt-cryptographic receipt 1 'failed to verify attestation: signature mismatch' 1 untrusted-origin
  assert_online_attestation sealed-unavailable sealed 1 'attestations are not supported for this repository' 1 attestation-unavailable
)

# Verify the actual default SLSA v1 predicate created by the pinned
# actions/attest revision.  The predicate's external parameters intentionally
# have no `inputs` member: run identity and nonce are instead authenticated by
# the receipt, manifest, and unique artifact names.
predicate_function="$tmp/attestation-predicate.sh"
awk '/^attestation_predicate_valid\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$predicate_function"
[[ -s $predicate_function ]]
source "$predicate_function"
REPOSITORY=SkrOYC/burlmd
workflow_signer=0123456789abcdef0123456789abcdef01234567
run_id=123456789
attempt=2
workflow_path() { case "$1" in linux-x86_64) printf .github/workflows/ci-role-linux-x86-64.yml;; *) return 1;; esac; }
subject=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
builder="https://github.com/$REPOSITORY/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master"
invocation="https://github.com/$REPOSITORY/actions/runs/$run_id/attempts/$attempt"
fixture=$(jq -cn --arg subject "$subject" --arg signer "$workflow_signer" --arg builder "$builder" --arg invocation "$invocation" '
  [{attestation:{bundle:{mediaType:"application/vnd.dev.sigstore.bundle.v0.3+json"}},verificationResult:{signature:{certificate:{issuer:"https://token.actions.githubusercontent.com",sourceRepositoryURI:"https://github.com/SkrOYC/burlmd",sourceRepositoryDigest:$signer,sourceRepositoryRef:"refs/heads/master",buildSignerURI:$builder,buildSignerDigest:$signer,runnerEnvironment:"github-hosted",runInvocationURI:$invocation}},statement:{subject:[{name:"ci-sealed-role-evidence.tar.zst",digest:{sha256:$subject}}],predicateType:"https://slsa.dev/provenance/v1",predicate:{buildDefinition:{buildType:"https://actions.github.io/buildtypes/workflow/v1",externalParameters:{workflow:{repository:"https://github.com/SkrOYC/burlmd",path:".github/workflows/ci.yml",ref:"refs/heads/master"}},internalParameters:{github:{event_name:"workflow_dispatch",repository_id:"1",repository_owner_id:"2",runner_environment:"github-hosted"}},resolvedDependencies:[{uri:"git+https://github.com/SkrOYC/burlmd@refs/heads/master",digest:{gitCommit:$signer}}]},runDetails:{builder:{id:$builder},metadata:{invocationId:$invocation}}}}}}]')
attestation_predicate_valid "$fixture" "$subject" linux-x86_64
jq -e '.[0].verificationResult.statement.predicate.buildDefinition.externalParameters | has("inputs") | not' <<<"$fixture" >/dev/null
reject_predicate() { if attestation_predicate_valid "$1" "$subject" linux-x86_64; then printf '%s unexpectedly accepted\n' "$2" >&2; exit 1; fi; }
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.runDetails.builder.id = "https://github.com/SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/evil"' <<<"$fixture")" wrong-builder
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.ref = "refs/heads/evil"' <<<"$fixture")" wrong-ref
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runnerEnvironment = "self-hosted"' <<<"$fixture")" wrong-certificate-runner
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.internalParameters.github.runner_environment = "self-hosted"' <<<"$fixture")" wrong-predicate-runner
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.resolvedDependencies[0].digest.gitCommit = "ffffffffffffffffffffffffffffffffffffffff"' <<<"$fixture")" wrong-signer-sha
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runInvocationURI = "https://github.com/SkrOYC/burlmd/actions/runs/999/attempts/2"' <<<"$fixture")" wrong-run
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runInvocationURI = "https://github.com/SkrOYC/burlmd/actions/runs/123456789/attempts/3"' <<<"$fixture")" wrong-attempt
reject_predicate "$(jq '.[0].verificationResult.statement.subject[0].digest.sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' <<<"$fixture")" wrong-subject

# REST API v2026-03-10 always returns the dispatched run details. The request
# body must omit the retired opt-in while the response remains type-checked.
dispatch_function="$tmp/dispatch-run-id.sh"
awk '/^dispatch_run_id\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$dispatch_function"
source "$dispatch_function"
dispatch_fixture=$(jq -cn '{workflow_run_id:123456789,run_url:"https://api.github.com/repos/SkrOYC/burlmd/actions/runs/123456789",html_url:"https://github.com/SkrOYC/burlmd/actions/runs/123456789"}')
[[ $(dispatch_run_id "$dispatch_fixture") == 123456789 ]]
if dispatch_run_id "$(jq 'del(.html_url)' <<<"$dispatch_fixture")"; then
  echo 'dispatch response accepted missing run details' >&2
  exit 1
fi
dispatch_payload=$(jq -cn '{ref:"master",inputs:{expected_identity_base64:"fixture",expected_identity_sha256:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",tested_source_sha:"1111111111111111111111111111111111111111",base_sha:"2222222222222222222222222222222222222222",run_identity:"managed:0123456789abcdef0123456789abcdef",artifact_nonce:"0123456789abcdef0123456789abcdef"}}')
jq -e '((keys | sort) == ["inputs", "ref"]) and (.inputs | type == "object")' <<<"$dispatch_payload" >/dev/null
! rg -Fq 'return_run_details' "$root/scripts/managed-evidence.sh"

# REST run observations are numeric and fresh-dispatch-only.  Check every
# invalid attempt form independently, then retain the same predicate for the
# terminal re-fetch immediately before accepted publication.
fresh_run_function="$tmp/fresh-run.sh"
awk '/^workflow_run_is_fresh_dispatch\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$fresh_run_function"
(
  source "$fresh_run_function"
  workflow_signer=0123456789012345678901234567890123456789
  fresh=$(jq -cn --arg signer "$workflow_signer" '{event:"workflow_dispatch",head_branch:"master",head_sha:$signer,run_attempt:1,path:".github/workflows/ci.yml"}')
  workflow_run_is_fresh_dispatch "$fresh"
  for invalid in \
    "$(jq '.path = ".github/workflows/ci.yml@master"' <<<"$fresh")" \
    "$(jq '.path = ".github/workflows/ci.yml@refs/heads/master"' <<<"$fresh")" \
    "$(jq '.path = ".github/workflows/other.yml"' <<<"$fresh")" \
    "$(jq 'del(.path)' <<<"$fresh")" \
    "$(jq 'del(.run_attempt)' <<<"$fresh")" \
    "$(jq '.run_attempt = "1"' <<<"$fresh")" \
    "$(jq '.run_attempt = 0' <<<"$fresh")" \
    "$(jq '.run_attempt = -1' <<<"$fresh")" \
    "$(jq '.run_attempt = 2' <<<"$fresh")"; do
    if workflow_run_is_fresh_dispatch "$invalid"; then
      echo "accepted invalid REST run_attempt: $invalid" >&2
      exit 1
    fi
  done
)
final_refresh_line=$(rg -n -F 'workflow run final freshness lookup' "$root/scripts/managed-evidence.sh" | cut -d: -f1)
accepted_publication_line=$(rg -n -F 'accepted_report "$roles"' "$root/scripts/managed-evidence.sh" | tail -n1 | cut -d: -f1)
[[ -n $final_refresh_line && -n $accepted_publication_line && $final_refresh_line -lt $accepted_publication_line ]]
sed -n "${final_refresh_line},${accepted_publication_line}p" "$root/scripts/managed-evidence.sh" | rg -Fq "workflow_run_is_fresh_dispatch \"\$final_run_json\" || die 'workflow run attempt drifted before accepted publication'"

# Inventory equality is not a prefix check: ordinary dispatches have exactly
# eleven artifacts, while BURL-O001 alone adds exactly its two authenticated
# producer transport artifacts. The nonce is the sole variable component.
inventory_function="$tmp/reserved-inventory.sh"
awk '/^validate_reserved_inventory\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$inventory_function"
(
  source "$inventory_function"
  run_id=1
  run_identity=managed:0123456789abcdef0123456789abcdef
  nonce=${run_identity#managed:}
  make_inventory() {
    local ticket=$1
    jq -cn --arg ticket "$ticket" --arg nonce "$nonce" '
      ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"] as $roles
      | ["managed-evidence-expected-" + $nonce]
        + [$roles[] | "managed-evidence-candidate-" + . + "-" + $nonce]
        + [$roles[] | "managed-evidence-sealed-" + . + "-" + $nonce]
        + [$roles[] | "managed-evidence-seal-receipt-" + . + "-" + $nonce]
        + ["managed-evidence-receipt-digests-" + $nonce]
        + (if $ticket == "BURL-O001" then ["managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-" + $nonce, "managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-" + $nonce] else [] end)
      | to_entries | {artifacts: map({id:(.key + 1), name:.value, workflow_run:{id:1}})}'
  }
  ticket=BURL-M003
  ordinary=$(make_inventory "$ticket")
  [[ $(jq '.artifacts | length' <<<"$ordinary") == 11 ]]
  inventory="$tmp/ordinary-inventory.json"; printf '%s\n' "$ordinary" >"$inventory"
  validate_reserved_inventory "$inventory"
  jq '.artifacts += [{id:99,name:"managed-evidence-foreign-0123456789abcdef0123456789abcdef",workflow_run:{id:1}}]' "$inventory" >"$inventory.extra"
  ! validate_reserved_inventory "$inventory.extra"
  ticket=BURL-O001
  o001=$(make_inventory "$ticket")
  [[ $(jq '.artifacts | length' <<<"$o001") == 13 ]]
  inventory="$tmp/o001-inventory.json"; printf '%s\n' "$o001" >"$inventory"
  validate_reserved_inventory "$inventory"
  jq 'del(.artifacts[-1])' "$inventory" >"$inventory.missing"
  ! validate_reserved_inventory "$inventory.missing"
)

# Keep a recording fake API inventory in lockstep with every executable
# production call site. Its request vocabulary intentionally has no deletion
# endpoint; the trusted-control fixture separately scans every control file.
api_callsite_count=$(rg -n '^    if response=\$\(api |^  api -L |^  if api -L |^  current=\$\(api |^  dispatch=\$\(api |^if run_json=\$\(api |^if api |^if final_run_json=\$\(api |^  if rest=\$\(api ' "$root/scripts/managed-evidence.sh" | wc -l | tr -d ' ')
recorded_api_calls=()
recording_api() { recorded_api_calls+=("$*"); }
recording_api 'GET /actions/runs/1'
recording_api 'GET /actions/artifacts/1/zip'
recording_api 'GET /actions/artifacts/2/zip'
recording_api 'GET /actions/artifacts/3/zip'
recording_api 'GET /actions/artifacts/4'
recording_api 'GET /actions/artifacts/11'
recording_api 'GET /actions/artifacts/11/zip'
recording_api 'POST /actions/workflows/ci.yml/dispatches'
recording_api 'GET /actions/runs/1'
recording_api 'GET /actions/runs/1/artifacts?per_page=100'
recording_api 'GET /actions/runs/1/jobs?filter=latest&per_page=100'
recording_api 'GET /actions/runs/1'
[[ $api_callsite_count == ${#recorded_api_calls[@]} ]]
! printf '%s\n' "${recorded_api_calls[@]}" | rg -i '(^|[[:space:]])DELETE([[:space:]]|$)'

# Polling retries only transient service observations. A later successful
# observation remains usable evidence; exhausted transport and 403 outcomes
# stay operational and must never be promoted to a rejected report.
wait_functions="$tmp/wait-functions.sh"
{
  cat "$fresh_run_function"
  awk '/^wait_for_run\(\)/,/^}/' "$root/scripts/managed-evidence.sh"
} >"$wait_functions"
(
  source "$wait_functions"
  API_TRANSIENT=75; API_PERMISSION=76; API_FAILURE=77; POLL_TRANSIENT_RETRIES=2
  API_BASE=https://fixture.invalid; REPOSITORY=fixture; run_id=1; attempt=1
  workflow_signer=0123456789012345678901234567890123456789
  poll_counter="$tmp/poll-counter"
  printf '0\n' >"$poll_counter"
  api() {
    polls=$(<"$poll_counter")
    polls=$((polls + 1))
    printf '%s\n' "$polls" >"$poll_counter"
    if ((polls < 3)); then return "$API_TRANSIENT"; fi
    printf '%s\n' '{"event":"workflow_dispatch","head_branch":"master","head_sha":"0123456789012345678901234567890123456789","run_attempt":1,"path":".github/workflows/ci.yml","status":"completed","conclusion":"success"}'
  }
  sleep() { :; }
  wait_for_run
  [[ $(<"$poll_counter") == 3 ]]
  api() { return "$API_TRANSIENT"; }
  set +e; wait_for_run; status=$?; set -e
  [[ $status == "$API_TRANSIENT" ]]
  api() { return "$API_PERMISSION"; }
  set +e; wait_for_run; status=$?; set -e
  [[ $status == "$API_PERMISSION" ]]
)
rg -Fq 'operational_api_failure "$outcome"' "$root/scripts/managed-evidence.sh"
rg -Fq 'run artifact enumeration' "$root/scripts/managed-evidence.sh"
rg -Fq 'role $role evidence acquisition' "$root/scripts/managed-evidence.sh"

# The three receipt downloads are independently addressed immutable artifacts.
# They must return a typed API failure unchanged so the role loop can route it
# operationally rather than inventing a durable evidence rejection.
receipt_role_function="$tmp/receipt-role.sh"
awk '/^receipt_role\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$receipt_role_function"
for download in \
  'download_sealing_receipt_zip "$receipt_artifact" "$receipt_path" "$receipt_bundle_path" || return $?' \
  'download_one_member_zip "$candidate_artifact" ci-role-evidence.tar.zst "$candidate_path" || return $?' \
  'download_one_member_zip "$sealed_artifact" ci-sealed-role-evidence.tar.zst "$sealed_path" || return $?'; do
  rg -Fq "$download" "$receipt_role_function"
done

# Operational routing must leave a prior durable report untouched. The real
# collector invokes this route for every propagated 75/76/77 status, including
# compatibility and per-role acquisition, before any rejected-report writer.
operational_functions="$tmp/operational-functions.sh"
awk '/^operational_api_failure\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$operational_functions"
(
  source "$operational_functions"
  API_TRANSIENT=75; API_PERMISSION=76; API_FAILURE=77
  prior_report="$tmp/prior-operational-report.json"
  printf 'prior durable report\n' >"$prior_report"
  die() { return 2; }
  for injected in "$API_TRANSIENT" "$API_PERMISSION" "$API_FAILURE"; do
    set +e
    operational_api_failure "$injected" 'injected operational acquisition'
    status=$?
    set -e
    [[ $status == 2 ]]
    cmp -s <(printf 'prior durable report\n') "$prior_report"
  done
)
rg -Fq "operational_api_failure \"\$api_status\" 'compatibility-stage evidence acquisition'" "$root/scripts/managed-evidence.sh"

# Exercise the production cleanup definitions in a disposable evidence tree.
# The only removable paths are contract-named preparation/coordinator roots;
# the declared report and result plus an unrelated sibling must survive every
# terminal path.
cleanup_functions="$tmp/cleanup-functions.sh"
awk '
  /^owned_cleanup_roots=\(\)/ {copy=1}
  /^# An interrupted evidence transaction/ {copy=0}
  copy {print}
' "$root/scripts/managed-evidence.sh" >"$cleanup_functions"
[[ -s $cleanup_functions ]]
run_cleanup_fixture() {
  local terminal=$1 fixture="$tmp/cleanup-$1" status
  mkdir -p "$fixture/.constitution/prototypes/ast/managed-evidence-prepare" \
    "$fixture/.constitution/prototypes/ast/managed-evidence-coordinator" \
    "$fixture/.constitution/prototypes/ast"
  : >"$fixture/.constitution/prototypes/ast/managed-evidence-prepare/scratch"
  : >"$fixture/.constitution/prototypes/ast/managed-evidence-coordinator/scratch"
  : >"$fixture/.constitution/prototypes/ast/results.json"
  : >"$fixture/.constitution/prototypes/ast/report.json"
  : >"$fixture/.constitution/prototypes/ast/unrelated-sentinel"
  set +e
  bash -ceu '
    source "$1"
    evidence_root=$2
    tmp="$evidence_root/scratch"
    auth_config="$tmp/auth.conf"
    mkdir -p "$tmp"; : >"$auth_config"
    register_owned_cleanup_root .constitution/prototypes/ast/managed-evidence-prepare
    register_owned_cleanup_root .constitution/prototypes/ast/managed-evidence-coordinator
    ! register_owned_cleanup_root .constitution/prototypes/ast/results.json
    interrupted() { trap - HUP INT TERM; exit 2; }
    trap cleanup EXIT
    trap interrupted HUP INT TERM
    case "$3" in success) exit 0;; rejection) exit 1;; signal) kill -TERM "$$";; esac
  ' -- "$cleanup_functions" "$fixture" "$terminal"
  status=$?
  set -e
  case "$terminal" in success) [[ $status == 0 ]];; rejection) [[ $status == 1 ]];; signal) [[ $status == 2 ]];; esac
  [[ ! -e $fixture/.constitution/prototypes/ast/managed-evidence-prepare ]]
  [[ ! -e $fixture/.constitution/prototypes/ast/managed-evidence-coordinator ]]
  [[ -f $fixture/.constitution/prototypes/ast/results.json ]]
  [[ -f $fixture/.constitution/prototypes/ast/report.json ]]
  [[ -f $fixture/.constitution/prototypes/ast/unrelated-sentinel ]]
}
run_cleanup_fixture success
run_cleanup_fixture rejection
run_cleanup_fixture signal

# Publication may be the first writer in the declared evidence directory.
# Exercise actual accepted and rejected writers with the pinned validator and
# an absent BURL-M003 parent. The role schema is deliberately resolved from
# the immutable local contract directory; this fixture must not stub schema
# validation, otherwise an HTTPS $id could hide a broken relative reference.
publication_functions="$tmp/publication-functions.sh"
{
  awk '/^summary\(\)/ {copy=1} /^require_token\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^filesystem_evidence_verified\(\)/ {copy=1} /^artifact_by_name\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^accepted_report\(\)/ {copy=1} /^workflow_signer=/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
} >"$publication_functions"
publication_root=$tmp/publication
mkdir -p "$publication_root/evidence" "$publication_root/anchor"
jq -cn '
  {
    ticketIdentity:"BURL-M003",
    releaseIdentity:"candidate:1111111111111111111111111111111111111111",
    trustAnchorSha:"1111111111111111111111111111111111111111",
    testedSourceSha:"1111111111111111111111111111111111111111",
    workflowSignerSha:"1111111111111111111111111111111111111111",
    workflowSignerRef:"refs/heads/master",
    baseSha:"2222222222222222222222222222222222222222",
    workflowEvent:"workflow_dispatch",
    evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",
    sourceWriteAllowlist:["scripts/**"],
    buildIdentity:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    corpusIdentity:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    runIdentity:"managed:0123456789abcdef0123456789abcdef",
    artifactNonce:"0123456789abcdef0123456789abcdef",
    requiredRoleIdentities:["linux-x86_64", "macos-26-arm64", "macos-15-arm64"],
    requiredRoleSigners:{
      "linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:"1111111111111111111111111111111111111111"},
      "macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:"1111111111111111111111111111111111111111"},
      "macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:"1111111111111111111111111111111111111111"}
    },
    requiredRoleGuards:{
      "linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",runnerLabel:"ubuntu-24.04",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},
      "macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",runnerLabel:"macos-26",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},
      "macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",runnerLabel:"macos-15",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"}
    },
    requiredEvidenceClasses:{
      "linux-x86_64":["common-functional", "managed-evidence-protocol", "managed-evidence-security", "managed-evidence-isolation", "generated-binding-check", "static-analysis", "desktop-integration"],
      "macos-26-arm64":["common-functional", "managed-evidence-protocol", "managed-evidence-security", "static-analysis", "desktop-integration"],
      "macos-15-arm64":["common-functional", "managed-evidence-protocol", "managed-evidence-security", "static-analysis", "desktop-integration"]
    }
  }
' >"$publication_root/expected.json"
(
  source "$publication_functions"
  die() { exit 2; }
  expected="$publication_root/expected.json"
  expected_digest=$(sha256sum "$expected" | awk '{print $1}')
  ticket=BURL-M003
  evidence_root="$publication_root/evidence"
  anchor_root="$publication_root/anchor"
  output="$evidence_root/.constitution/evidence/BURL-M003/managed-evidence.json"
  AGGREGATE_SCHEMA="$root/.constitution/tech-spec/contracts/ci-evidence.schema.json"
  AGGREGATE_SCHEMA_VERSION=19
  anchor=1111111111111111111111111111111111111111
  workflow_signer=$anchor
  tested=$anchor
  run_identity=managed:0123456789abcdef0123456789abcdef
  run_id=1
  attempt=1
  fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  roles=$(jq -cn --slurpfile expected "$expected" --arg digest "$expected_digest" --arg hash "$fixture_hash" '
    def environment($role):
      if $role == "linux-x86_64" then {runnerLabel:"ubuntu-24.04",imageOS:"ubuntu",imageVersion:"fixture-linux",osRelease:"fixture",architecture:"x86_64",cpuModel:"fixture",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:1,observedStorageAvailableBytes:1,filesystem:"fixture-linux"}
      elif $role == "macos-26-arm64" then {runnerLabel:"macos-26",imageOS:"macos",imageVersion:"fixture-macos-26",osRelease:"fixture",architecture:"aarch64",cpuModel:"fixture",logicalCpuCount:3,documentedMemoryBytes:7000000000,documentedStorageBytes:14000000000,observedMemoryBytes:1,observedStorageAvailableBytes:1,filesystem:"fixture-macos-26"}
      else {runnerLabel:"macos-15",imageOS:"macos",imageVersion:"fixture-macos-15",osRelease:"fixture",architecture:"aarch64",cpuModel:"fixture",logicalCpuCount:3,documentedMemoryBytes:7000000000,documentedStorageBytes:14000000000,observedMemoryBytes:1,observedStorageAvailableBytes:1,filesystem:"fixture-macos-15"}
      end;
    def workflow($role): if $role == "linux-x86_64" then ".github/workflows/ci-role-linux-x86-64.yml" elif $role == "macos-26-arm64" then ".github/workflows/ci-role-macos-26-arm64.yml" else ".github/workflows/ci-role-macos-15-arm64.yml" end;
    def candidate($id; $label; $workflow): {jobId:$id,checkRunId:$id,workflowJobKey:"candidate",workflowPath:$workflow,expectedRunnerLabel:$label,runnerLabels:[$label],placementFixedByTrustedWorkflow:true,topologyVerified:true,labelVerified:true,status:"completed",conclusion:"success",completionVerified:true};
    def seal($id; $label): {jobId:$id,checkRunId:$id,workflowJobKey:"seal",runnerLabels:[$label],runnerEnvironment:"github-hosted",status:"completed",conclusion:"success",hostedOriginVerified:true};
    def artifact($id; $name): {artifactId:$id,artifactName:$name,uploadActionDigest:$hash,artifactDigest:("sha256:" + $hash)};
    $expected[0] as $identity
    | $identity.requiredRoleIdentities
    | to_entries
    | map(.key as $index | .value as $role | (if $role == "linux-x86_64" then "ubuntu-24.04" elif $role == "macos-26-arm64" then "macos-26" else "macos-15" end) as $label | (workflow($role)) as $workflow | {
        manifest:{schemaVersion:15,expectedIdentity:$identity,expectedIdentitySha256:$digest,roleEvidence:{role:$role,capturedIdentity:($identity | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:environment($role),viewport:{width:1920,height:1080,refreshHz:60,verified:false},evidenceClasses:$identity.requiredEvidenceClasses[$role],gates:($identity.requiredEvidenceClasses[$role] | reduce .[] as $class ({}; .[$class] = true)),toolchain:{fixture:"1"},internalArtifacts:[{name:"fixture.txt",bytes:0,sha256:$hash}],compatibilityStage:null}},
        manifestSha256:$hash,
        origin:{repositoryId:1,workflowRunId:1,runAttempt:1,trustAnchorSha:$identity.trustAnchorSha,testedSourceSha:$identity.testedSourceSha,workflowSignerSha:$identity.workflowSignerSha,workflowSignerRef:"refs/heads/master",baseSha:$identity.baseSha,candidatePlacement:candidate(($index * 10) + 1; $label; $workflow),sealingCheckRunId:(($index * 10) + 2),sealingJob:seal(($index * 10) + 2; $label),signerWorkflow:{workflowPath:$workflow,jobWorkflowRef:("SkrOYC/burlmd/" + $workflow + "@refs/heads/master"),jobWorkflowSha:$identity.workflowSignerSha,builderId:("https://github.com/SkrOYC/burlmd/" + $workflow + "@refs/heads/master")},candidateArtifact:artifact(($index * 10) + 3; ("managed-evidence-candidate-" + $role + "-" + $identity.artifactNonce)),sealedArtifact:artifact(($index * 10) + 4; ("managed-evidence-sealed-" + $role + "-" + $identity.artifactNonce)),sealingReceiptArtifact:artifact(($index * 10) + 5; ("managed-evidence-seal-receipt-" + $role + "-" + $identity.artifactNonce)),sealingReceiptSha256:$hash,attestationIssuer:"https://token.actions.githubusercontent.com",sealedAttestationSubjectDigest:("sha256:" + $hash),sealedAttestationBundleSha256:$hash,sealedAttestationVerified:true,sealingReceiptAttestationSubjectDigest:("sha256:" + $hash),sealingReceiptAttestationBundleSha256:$hash,sealingReceiptAttestationVerified:true,roleBundleSha256:$hash,sealedBundleSha256:$hash,restApiVersion:"2026-03-10",verifiedAt:"2026-09-05T00:00:00Z"}
      })
  ')
  expected_artifact=$(jq -cn --arg hash "$fixture_hash" '{artifactId:100,artifactName:"managed-evidence-expected-0123456789abcdef0123456789abcdef",uploadActionDigest:$hash,artifactDigest:("sha256:" + $hash)}')
  receipt_transport_artifact=$(jq -cn --arg hash "$fixture_hash" '{artifactId:101,artifactName:"managed-evidence-receipt-digests-0123456789abcdef0123456789abcdef",artifactDigest:("sha256:" + $hash),downloadedArtifactSha256:$hash}')
  accepted_report "$roles" "$expected_artifact" "$receipt_transport_artifact" true >/dev/null
  [[ -f $output ]] || { echo 'accepted report did not create its declared absent parent' >&2; exit 1; }
  jq -e '.status == "accepted" and .aggregationChecks.filesystemEvidenceVerified == true' "$output" >/dev/null
  check-jsonschema --no-cache --schemafile "$AGGREGATE_SCHEMA" --base-uri "file://$(dirname "$AGGREGATE_SCHEMA")/$(basename "$AGGREGATE_SCHEMA")" "$output" >/dev/null
  rm -rf -- "$publication_root/evidence/.constitution"
  [[ ! -e $(dirname "$output") ]]
  # Rejection reports must use the contract's closed reason-code vocabulary.
  # This first durable report becomes the preservation sentinel for every
  # publication-failure case below.
  rejected aggregation-error 'fixture rejected terminal path' >/dev/null
  [[ -f $output ]] || { echo 'rejected report did not create its declared absent parent' >&2; exit 1; }
  jq -e '.status == "rejected" and .rejectionReasons[0].code == "aggregation-error"' "$output" >/dev/null
  check-jsonschema --no-cache --schemafile "$AGGREGATE_SCHEMA" --base-uri "file://$(dirname "$AGGREGATE_SCHEMA")/$(basename "$AGGREGATE_SCHEMA")" "$output" >/dev/null

  # Exit 1 is permitted only after the replacement rejected report is durable
  # and schema-valid. Every failure before the same-directory atomic rename
  # must instead exit 2 and preserve this prior report byte-for-byte.
  durable_rejection=$publication_root/durable-rejection.json
  cp -- "$output" "$durable_rejection"
  assert_rejection_publication_failure() {
    local fault=$1 status
    set +e
    (
      case "$fault" in
        output-parent) prepare_output_parent() { return 1; };;
        temporary) mktemp() { return 1; };;
        json) jq() { return 1; };;
        schema) validate_schema() { return 1; };;
        atomic-rename) mv() { return 1; };;
        *) exit 2;;
      esac
      rejected aggregation-error "fixture $fault publication failure" >/dev/null
    )
    status=$?
    set -e
    [[ $status == 2 ]] || { echo "rejection $fault failure exited $status, expected 2" >&2; exit 1; }
    cmp -s "$durable_rejection" "$output" || { echo "rejection $fault failure replaced a durable report" >&2; exit 1; }
    check-jsonschema --no-cache --schemafile "$AGGREGATE_SCHEMA" --base-uri "file://$(dirname "$AGGREGATE_SCHEMA")/$(basename "$AGGREGATE_SCHEMA")" "$output" >/dev/null
  }
  for fault in output-parent temporary json schema atomic-rename; do
    assert_rejection_publication_failure "$fault"
  done
  for mutation in missing empty tampered mismatch; do
    case $mutation in
      missing) bad=$(jq 'del(.[0].manifest.roleEvidence.environment.filesystem)' <<<"$roles") ;;
      empty) bad=$(jq '.[1].manifest.roleEvidence.environment.filesystem = ""' <<<"$roles") ;;
      tampered) bad=$(jq '.[2].manifest.roleEvidence.environment.filesystem = "tampered"' <<<"$roles") ;;
      mismatch) bad=$(jq '.[0].manifest.roleEvidence.environment.filesystem = "fixture-mismatch"' <<<"$roles") ;;
    esac
    if [[ $mutation == missing || $mutation == empty ]]; then
      if filesystem_evidence_verified "$bad"; then
        echo "filesystem fixture accepted $mutation evidence" >&2
        exit 1
      fi
    else
      role_file="$publication_root/$mutation-role.json"
      case $mutation in tampered) index=2;; mismatch) index=0;; esac
      jq --argjson index "$index" '.[$index]' <<<"$bad" >"$role_file"
      if filesystem_role_verified "$role_file" "fixture-$index"; then
        echo "filesystem fixture accepted $mutation archive-boundary evidence" >&2
        exit 1
      fi
    fi
    rejected filesystem-evidence-mismatch "fixture $mutation" >/dev/null
    jq -e '.status == "rejected" and .aggregationChecks.filesystemEvidenceVerified == false and .rejectionReasons[0].code == "filesystem-evidence-mismatch"' "$output" >/dev/null
  done
)

# Production keeps complete JSON Schema validation on both terminal paths.
rg -Fq 'validate_schema "$AGGREGATE_SCHEMA" "$report_tmp"' "$root/scripts/managed-evidence.sh"
rg -Fq 'validate_schema "$ROLE_SCHEMA" "$manifest"' "$root/scripts/managed-evidence.sh"
rg -Fq -- '--source-digest "$workflow_signer"' "$root/scripts/managed-evidence.sh"
rg -Fq -- '--source-ref refs/heads/master' "$root/scripts/managed-evidence.sh"
! sed -n '/^verify_attestation()/,/^}$/p' "$root/scripts/managed-evidence.sh" | rg -F -- '--source-digest "$tested"'
printf 'managed-evidence client boundary tests passed\n'
