#!/usr/bin/env bash
# Validates the untrusted candidate handoff before a fresh seal job is allowed
# to create an attestation or authoritative upload. The same checks are made
# again after sealing so the receipt binds the REST-observed objects.
set -euo pipefail

phase= role= nonce= expected= expected_id= expected_digest=
candidate_check= candidate_id= candidate_digest=
sealed_id= sealed_digest= receipt_id= receipt_digest=
while (($#)); do
  case $1 in
    --phase) phase=${2:-}; shift 2;;
    --role) role=${2:-}; shift 2;;
    --nonce) nonce=${2:-}; shift 2;;
    --expected) expected=${2:-}; shift 2;;
    --expected-id) expected_id=${2:-}; shift 2;;
    --expected-digest) expected_digest=${2:-}; shift 2;;
    --candidate-check-run-id) candidate_check=${2:-}; shift 2;;
    --candidate-id) candidate_id=${2:-}; shift 2;;
    --candidate-digest) candidate_digest=${2:-}; shift 2;;
    --sealed-id) sealed_id=${2:-}; shift 2;;
    --sealed-digest) sealed_digest=${2:-}; shift 2;;
    --receipt-id) receipt_id=${2:-}; shift 2;;
    --receipt-digest) receipt_digest=${2:-}; shift 2;;
    *) exit 2;;
  esac
done

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GH_TOKEN:?}"
GH_BIN=${GH_BIN:-gh}
[[ $phase =~ ^(candidate|sealed)$ && $role =~ ^(linux-x86_64|macos-26-arm64|macos-15-arm64)$ && $nonce =~ ^[0-9a-f]{32}$ && -f $expected ]] || exit 2
for value in "$expected_id" "$candidate_check" "$candidate_id"; do [[ $value =~ ^[1-9][0-9]*$ ]] || exit 2; done
for digest in "$expected_digest" "$candidate_digest"; do [[ $digest =~ ^[0-9a-f]{64}$ ]] || exit 2; done
if [[ $phase == sealed ]]; then
  for value in "$sealed_id" "$receipt_id"; do [[ $value =~ ^[1-9][0-9]*$ ]] || exit 2; done
  for digest in "$sealed_digest" "$receipt_digest"; do [[ $digest =~ ^[0-9a-f]{64}$ ]] || exit 2; done
  [[ $expected_id != "$candidate_id" && $expected_id != "$sealed_id" && $expected_id != "$receipt_id" && $candidate_id != "$sealed_id" && $candidate_id != "$receipt_id" && $sealed_id != "$receipt_id" ]] || exit 1
fi

workflow_path=".github/workflows/ci-role-${role//_/-}.yml"
runner_label=$([[ $role == linux-x86_64 ]] && printf ubuntu-24.04 || printf '%s' "${role%-arm64}")
signer_sha=$(jq -er --arg nonce "$nonce" --arg role "$role" --arg path "$workflow_path" '
  . as $identity |
  if type == "object" and .artifactNonce == $nonce and .runIdentity == ("managed:" + $nonce) and
     (.requiredRoleIdentities | type == "array" and index($role)) and
     (.workflowSignerSha | type == "string" and test("^[0-9a-f]{40}$")) and
     (.requiredRoleSigners[$role] | type == "object" and .workflowPath == $path and .jobWorkflowSha == $identity.workflowSignerSha)
  then .workflowSignerSha else empty end
' "$expected") || exit 1

api() {
  "$GH_BIN" api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "$1"
}
validate_artifact() {
  local id=$1 digest=$2 name=$3 object
  object=$(api "repos/$GITHUB_REPOSITORY/actions/artifacts/$id")
  jq -e --arg digest "sha256:$digest" --arg name "$name" --argjson run "$GITHUB_RUN_ID" --arg signer "$signer_sha" '
    .name == $name and .digest == $digest and .expired == false and
    .workflow_run.id == $run and .workflow_run.head_sha == $signer
  ' <<<"$object" >/dev/null
}

# A direct job lookup is not subject to list pagination and binds the output
# locator to exactly one completed GitHub-hosted candidate job in this run.
candidate_job=$(api "repos/$GITHUB_REPOSITORY/actions/jobs/$candidate_check")
jq -e --argjson check "$candidate_check" --arg runner "$runner_label" --argjson run "$GITHUB_RUN_ID" --arg signer "$signer_sha" '
  .id == $check and .run_id == $run and .head_sha == $signer and
  .status == "completed" and .conclusion == "success" and
  (.name | test("candidate$")) and (.labels | type == "array" and index($runner)) and
  (.labels | index("self-hosted") | not) and
  (.check_run_url | endswith("/" + ($check | tostring)))
' <<<"$candidate_job" >/dev/null

validate_artifact "$expected_id" "$expected_digest" "managed-evidence-expected-$nonce"
validate_artifact "$candidate_id" "$candidate_digest" "managed-evidence-candidate-$role-$nonce"

if [[ $phase == sealed ]]; then
  validate_artifact "$sealed_id" "$sealed_digest" "managed-evidence-sealed-$role-$nonce"
  validate_artifact "$receipt_id" "$receipt_digest" "managed-evidence-seal-receipt-$role-$nonce"
fi
