#!/usr/bin/env bash
set -euo pipefail
: "${ROLE:?}" "${WORKFLOW_PATH:?}" "${ARTIFACT_NONCE:?}" "${EXPECTED_IDENTITY_SHA256:?}" "${EXPECTED_ID:?}" "${EXPECTED_DIGEST:?}" "${CANDIDATE_ID:?}" "${CANDIDATE_DIGEST:?}" "${SEALED_ID:?}" "${SEALED_DIGEST:?}" "${TESTED_SOURCE_SHA:?}" "${BASE_SHA:?}" "${CHECK_RUN_ID:?}" "${EXPECTED_IDENTITY_FILE:?}" "${GITHUB_SHA:?}"
candidate=${1:?candidate bundle}; sealed=${2:?sealed bundle}; output=${3:?receipt output}
[[ $ROLE =~ ^(linux-x86_64|macos-26-arm64|macos-15-arm64)$ && $ARTIFACT_NONCE =~ ^[0-9a-f]{32}$ && $CHECK_RUN_ID =~ ^[1-9][0-9]*$ && $GITHUB_SHA =~ ^[0-9a-f]{40}$ ]] || exit 2
for sha in "$EXPECTED_IDENTITY_SHA256" "$EXPECTED_DIGEST" "$CANDIDATE_DIGEST" "$SEALED_DIGEST"; do [[ $sha =~ ^[0-9a-f]{64}$ ]] || exit 2; done
for id in "$EXPECTED_ID" "$CANDIDATE_ID" "$SEALED_ID" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}"; do [[ $id =~ ^[1-9][0-9]*$ ]] || exit 2; done
[[ -f $EXPECTED_IDENTITY_FILE && $(sha256sum "$EXPECTED_IDENTITY_FILE" | awk '{print $1}') == "$EXPECTED_IDENTITY_SHA256" ]] || exit 1
trust_anchor=$(jq -er --arg tested "$TESTED_SOURCE_SHA" --arg base "$BASE_SHA" --arg signer "$GITHUB_SHA" --arg nonce "$ARTIFACT_NONCE" '
  .trustAnchorSha | select(test("^[0-9a-f]{40}$"))
  ' "$EXPECTED_IDENTITY_FILE")
jq -e --arg tested "$TESTED_SOURCE_SHA" --arg base "$BASE_SHA" --arg signer "$GITHUB_SHA" --arg nonce "$ARTIFACT_NONCE" '
  .testedSourceSha == $tested and .baseSha == $base and .workflowSignerSha == $signer and
  .runIdentity == ("managed:" + $nonce) and .artifactNonce == $nonce
' "$EXPECTED_IDENTITY_FILE" >/dev/null || exit 1
jq -cn --arg expectedSha "$EXPECTED_IDENTITY_SHA256" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" --argjson attempt "$GITHUB_RUN_ATTEMPT" --argjson check "$CHECK_RUN_ID" --arg role "$ROLE" --arg workflow "$WORKFLOW_PATH" --arg nonce "$ARTIFACT_NONCE" --arg tested "$TESTED_SOURCE_SHA" --arg base "$BASE_SHA" --arg trust "$trust_anchor" --arg expected "$EXPECTED_DIGEST" --arg candidateDigest "$CANDIDATE_DIGEST" --arg sealedDigest "$SEALED_DIGEST" --argjson expectedId "$EXPECTED_ID" --argjson candidateId "$CANDIDATE_ID" --argjson sealedId "$SEALED_ID" --arg roleHash "$(sha256sum "$candidate" | awk '{print $1}')" --arg sealedHash "$(sha256sum "$sealed" | awk '{print $1}')" '{schemaVersion:1,expectedIdentitySha256:$expectedSha,repositoryId:$repository,workflowRunId:$run,runAttempt:$attempt,sealingCheckRunId:$check,workflowPath:$workflow,workflowSignerSha:env.GITHUB_SHA,workflowSignerRef:"refs/heads/master",trustAnchorSha:$trust,testedSourceSha:$tested,baseSha:$base,role:$role,artifactNonce:$nonce,runnerEnvironmentClaim:"github-hosted",expectedArtifact:{artifactId:$expectedId,artifactName:("managed-evidence-expected-"+$nonce),uploadActionDigest:$expected,artifactDigest:("sha256:"+$expected)},candidateArtifact:{artifactId:$candidateId,artifactName:("managed-evidence-candidate-"+$role+"-"+$nonce),uploadActionDigest:$candidateDigest,artifactDigest:("sha256:"+$candidateDigest)},sealedArtifact:{artifactId:$sealedId,artifactName:("managed-evidence-sealed-"+$role+"-"+$nonce),uploadActionDigest:$sealedDigest,artifactDigest:("sha256:"+$sealedDigest)},roleBundleSha256:$roleHash,sealedBundleSha256:$sealedHash}' >"$output"
"$(dirname "$0")/validate-sealing-receipt.sh" "$output"
