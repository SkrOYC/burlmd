#!/usr/bin/env bash
# Record an immutable artifact's upload digest and REST observation. When a
# stage binding is supplied, also bind its stage and attestation facts.
set -euo pipefail
id= digest= binding= github_output= attestation_bundle=
while (($#)); do case $1 in --artifact-id) id=$2; shift 2;; --upload-action-digest) digest=$2; shift 2;; --binding) binding=$2; shift 2;; --attestation-bundle) attestation_bundle=$2; shift 2;; --github-output) github_output=$2; shift 2;; *) exit 2;; esac; done
: "${GITHUB_REPOSITORY:?}" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}" "${GH_TOKEN:?}"
[[ $id =~ ^[1-9][0-9]*$ && $digest =~ ^[0-9a-f]{64}$ && -f $attestation_bundle && ! -L $attestation_bundle && -n $github_output ]] || exit 2
[[ -z $binding || ( -f $binding && ! -L $binding ) ]] || exit 2
for value in "$GITHUB_REPOSITORY_ID" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"; do [[ $value =~ ^[1-9][0-9]*$ ]] || exit 2; done
[[ $GITHUB_SHA =~ ^[0-9a-f]{40}$ ]] || exit 2

if [[ -n $binding ]]; then
  nonce=$(jq -er '.stageManifest.artifactNonce | select(type == "string" and test("^[0-9a-f]{32}$"))' "$binding") || exit 1
  artifact_name="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce"
  jq -e --arg name "$artifact_name" --arg nonce "$nonce" --arg signer "$GITHUB_SHA" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" --argjson attempt "$GITHUB_RUN_ATTEMPT" '
    .stageArtifact.artifactId == 0 and .stageArtifact.artifactName == $name and
    .stageArtifact.uploadActionDigest == ("0" * 64) and .stageArtifact.artifactDigest == ("sha256:" + ("0" * 64)) and
    .stageArtifact.createdAt == "" and .stageArtifact.expiresAt == "" and .stageArtifact.expired == false and
    .stageManifest.ticketIdentity == "BURL-O001" and .stageManifest.repositoryId == $repository and
    .stageManifest.workflowRunId == $run and .stageManifest.runAttempt == $attempt and
    .stageManifest.workflowSignerSha == $signer and .stageManifest.artifactNonce == $nonce and
    .stageManifest.producerRole == "macos-26-arm64" and .stageManifest.consumerRole == "macos-15-arm64"
  ' "$binding" >/dev/null || exit 1
else
  : "${ARTIFACT_NONCE:?}"
  [[ $ARTIFACT_NONCE =~ ^[0-9a-f]{32}$ ]] || exit 2
  artifact_name="managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$ARTIFACT_NONCE"
fi
artifact=$(gh api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "repos/$GITHUB_REPOSITORY/actions/artifacts/$id")
jq -e --argjson id "$id" --arg name "$artifact_name" --arg digest "sha256:$digest" --arg signer "$GITHUB_SHA" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" '
  .id == $id and .name == $name and .digest == $digest and .expired == false and
  (.created_at | type == "string") and (.expires_at | type == "string") and
  (.workflow_run | type == "object" and .id == $run and .repository_id == $repository and .head_sha == $signer)
' <<< "$artifact" >/dev/null
bundle_sha=$(sha256sum "$attestation_bundle" | awk '{print $1}')
if [[ -n $binding ]]; then
  jq --argjson id "$id" --arg name "$artifact_name" --arg digest "$digest" --arg rest "sha256:$digest" --arg created "$(jq -r .created_at <<< "$artifact")" --arg expires "$(jq -r .expires_at <<< "$artifact")" --arg bundle_sha "$bundle_sha" '.stageArtifact = {artifactId:$id,artifactName:$name,repositoryId:(env.GITHUB_REPOSITORY_ID|tonumber),workflowRunId:(env.GITHUB_RUN_ID|tonumber),uploadActionDigest:$digest,artifactDigest:$rest,createdAt:$created,expiresAt:$expires,expired:false} | .attestation = {bundleMember:"compatibility-stage-attestation.sigstore.json",bundleSha256:$bundle_sha,subjectName:"compatibility-stage-manifest.json",subjectDigest:("sha256:" + .stageManifestSha256),predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",repository:env.GITHUB_REPOSITORY,repositoryId:(env.GITHUB_REPOSITORY_ID|tonumber),workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:(env.GITHUB_REPOSITORY + "/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"),jobWorkflowSha:.stageManifest.workflowSignerSha,sourceRepositoryDigest:.stageManifest.workflowSignerSha,workflowRunId:.stageManifest.workflowRunId,runAttempt:.stageManifest.runAttempt,checkRunId:.stageManifest.producerSealingCheckRunId,runnerEnvironment:"github-hosted"}' "$binding" > "$binding.next"
  mv -- "$binding.next" "$binding"
fi
printf 'rest_digest=sha256:%s\ncreated_at=%s\nexpires_at=%s\nattestation_bundle_sha256=%s\n' "$digest" "$(jq -r .created_at <<< "$artifact")" "$(jq -r .expires_at <<< "$artifact")" "$bundle_sha" >> "$github_output"
