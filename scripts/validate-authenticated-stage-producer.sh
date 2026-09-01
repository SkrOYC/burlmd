#!/usr/bin/env bash
# Authenticate the completed macOS 26 producer before its PKG handoff reaches
# macOS 15. This runs in the caller's fresh staging job, never in either role.
set -euo pipefail

expected= receipt= role= nonce= candidate_check= seal_check= expected_id= expected_digest=
while (($#)); do
  case $1 in
    --expected) expected=${2:-}; shift 2 ;;
    --receipt) receipt=${2:-}; shift 2 ;;
    --role) role=${2:-}; shift 2 ;;
    --nonce) nonce=${2:-}; shift 2 ;;
    --candidate-check-run-id) candidate_check=${2:-}; shift 2 ;;
    --seal-check-run-id) seal_check=${2:-}; shift 2 ;;
    --expected-id) expected_id=${2:-}; shift 2 ;;
    --expected-digest) expected_digest=${2:-}; shift 2 ;;
    *) exit 2 ;;
  esac
done

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}" "${GH_BIN:=gh}"
[[ $role == macos-26-arm64 && $nonce =~ ^[0-9a-f]{32}$ && $candidate_check =~ ^[1-9][0-9]*$ && $seal_check =~ ^[1-9][0-9]*$ && $expected_id =~ ^[1-9][0-9]*$ && $expected_digest =~ ^[0-9a-f]{64}$ && $GITHUB_SHA =~ ^[0-9a-f]{40}$ && -f $expected && -f $receipt ]] || exit 2
"$(dirname "$0")/validate-sealing-receipt.sh" "$receipt"
expected_sha=$(sha256sum "$expected" | awk '{print $1}')
jq -e --arg sha "$expected_sha" --arg nonce "$nonce" --arg signer "$GITHUB_SHA" --argjson expected_id "$expected_id" --arg expected_digest "$expected_digest" '
  .expectedIdentitySha256 == $sha and .role == "macos-26-arm64" and .artifactNonce == $nonce and
  .workflowPath == ".github/workflows/ci-role-macos-26-arm64.yml" and .workflowSignerSha == $signer and
  .expectedArtifact.artifactId == $expected_id and .expectedArtifact.uploadActionDigest == $expected_digest
' "$receipt" >/dev/null
jq -e --arg nonce "$nonce" --arg signer "$GITHUB_SHA" '
  .ticketIdentity == "PKG-M001" and .artifactNonce == $nonce and .runIdentity == ("managed:" + $nonce) and
  .workflowSignerSha == $signer and .requiredRoleSigners["macos-26-arm64"].jobWorkflowSha == $signer
' "$expected" >/dev/null

jobs=$($GH_BIN api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs")
validate_job() {
  local check=$1 suffix=$2
  jq -e --argjson check "$check" --arg suffix "$suffix" --argjson run "$GITHUB_RUN_ID" '
    [.jobs[] | select(.check_run_url | endswith("/" + ($check | tostring)))] |
    length == 1 and .[0].run_id == $run and .[0].status == "completed" and .[0].conclusion == "success" and
    (.[0].name | test($suffix + "$")) and (.[0].labels | index("macos-26")) and (.[0].labels | index("self-hosted") | not)
  ' <<<"$jobs" >/dev/null
}
validate_job "$candidate_check" candidate
validate_job "$seal_check" seal

validate_artifact() {
  local id=$1 digest=$2 name=$3 object
  object=$($GH_BIN api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "repos/$GITHUB_REPOSITORY/actions/artifacts/$id")
  jq -e --arg name "$name" --arg digest "sha256:$digest" --argjson run "$GITHUB_RUN_ID" '
    .name == $name and .digest == $digest and .expired == false and .workflow_run.id == $run
  ' <<<"$object" >/dev/null
}
validate_artifact "$expected_id" "$expected_digest" "managed-evidence-expected-$nonce"
validate_artifact "$(jq -er '.candidateArtifact.artifactId' "$receipt")" "$(jq -er '.candidateArtifact.uploadActionDigest' "$receipt")" "managed-evidence-candidate-macos-26-arm64-$nonce"
validate_artifact "$(jq -er '.sealedArtifact.artifactId' "$receipt")" "$(jq -er '.sealedArtifact.uploadActionDigest' "$receipt")" "managed-evidence-sealed-macos-26-arm64-$nonce"
