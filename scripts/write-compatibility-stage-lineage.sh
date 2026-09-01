#!/usr/bin/env bash
# Produces the immutable, no-newline RFC 8785-compatible lineage byte record.
set -euo pipefail
stage_id= stage_digest= receipt_id= receipt_digest= binding= output= github_output=
while (($#)); do case $1 in --stage-id) stage_id=$2; shift 2;; --stage-upload-action-digest) stage_digest=$2; shift 2;; --receipt-id) receipt_id=$2; shift 2;; --receipt-upload-action-digest) receipt_digest=$2; shift 2;; --stage-binding) binding=$2; shift 2;; --output) output=$2; shift 2;; --github-output) github_output=$2; shift 2;; *) exit 2;; esac; done
: "${GITHUB_REPOSITORY:?}" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}" "${GH_TOKEN:?}"
for id in "$stage_id" "$receipt_id"; do [[ $id =~ ^[1-9][0-9]*$ ]] || exit 2; done
for digest in "$stage_digest" "$receipt_digest"; do [[ $digest =~ ^[0-9a-f]{64}$ ]] || exit 2; done
[[ -f $binding && ! -L $binding && ! -e $output && -n $github_output ]] || exit 2
for value in "$GITHUB_REPOSITORY_ID" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"; do [[ $value =~ ^[1-9][0-9]*$ ]] || exit 2; done
[[ $GITHUB_SHA =~ ^[0-9a-f]{40}$ && $stage_id != "$receipt_id" ]] || exit 2
nonce=$(jq -er '.stageManifest.artifactNonce | select(type == "string" and test("^[0-9a-f]{32}$"))' "$binding") || exit 1
stage_name="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce"
receipt_name="managed-evidence-seal-receipt-macos-26-arm64-$nonce"
jq -e --arg stage_name "$stage_name" --arg stage_digest "$stage_digest" --arg signer "$GITHUB_SHA" --arg nonce "$nonce" --argjson stage_id "$stage_id" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" --argjson attempt "$GITHUB_RUN_ATTEMPT" '
  .stageArtifact.artifactId == $stage_id and .stageArtifact.artifactName == $stage_name and
  .stageArtifact.repositoryId == $repository and .stageArtifact.workflowRunId == $run and
  .stageArtifact.uploadActionDigest == $stage_digest and .stageArtifact.artifactDigest == ("sha256:" + $stage_digest) and
  (.stageArtifact.createdAt | type == "string") and (.stageArtifact.expiresAt | type == "string") and .stageArtifact.expired == false and
  .stageManifest.ticketIdentity == "BURL-O001" and .stageManifest.repositoryId == $repository and
  .stageManifest.workflowRunId == $run and .stageManifest.runAttempt == $attempt and .stageManifest.workflowSignerSha == $signer and
  .stageManifest.artifactNonce == $nonce and .stageManifest.producerRole == "macos-26-arm64" and .stageManifest.consumerRole == "macos-15-arm64" and
  .attestation.bundleMember == "compatibility-stage-attestation.sigstore.json" and
  (.attestation.bundleSha256 | type == "string" and test("^[0-9a-f]{64}$")) and .attestation.subjectName == "compatibility-stage-manifest.json" and
  .attestation.subjectDigest == ("sha256:" + .stageManifestSha256) and .attestation.predicateType == "https://slsa.dev/provenance/v1" and
  .attestation.issuer == "https://token.actions.githubusercontent.com" and .attestation.repository == env.GITHUB_REPOSITORY and
  .attestation.repositoryId == $repository and .attestation.workflowPath == ".github/workflows/ci-role-macos-26-arm64.yml" and
  .attestation.jobWorkflowRef == (env.GITHUB_REPOSITORY + "/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master") and
  .attestation.jobWorkflowSha == $signer and .attestation.sourceRepositoryDigest == $signer and
  .attestation.workflowRunId == $run and .attestation.runAttempt == $attempt and
  .attestation.checkRunId == .stageManifest.producerSealingCheckRunId and .attestation.runnerEnvironment == "github-hosted"
' "$binding" >/dev/null || exit 1
api() { gh api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "repos/$GITHUB_REPOSITORY/actions/artifacts/$1"; }
stage=$(api "$stage_id"); receipt=$(api "$receipt_id")
jq -e --argjson id "$stage_id" --arg name "$stage_name" --arg digest "sha256:$stage_digest" --arg created "$(jq -r .stageArtifact.createdAt "$binding")" --arg expires "$(jq -r .stageArtifact.expiresAt "$binding")" --arg signer "$GITHUB_SHA" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" '
  .id == $id and .name == $name and .digest == $digest and .expired == false and
  .created_at == $created and .expires_at == $expires and
  (.workflow_run | type == "object" and .id == $run and .repository_id == $repository and .head_sha == $signer)
' <<< "$stage" >/dev/null
jq -e --argjson id "$receipt_id" --arg name "$receipt_name" --arg digest "sha256:$receipt_digest" --arg signer "$GITHUB_SHA" --argjson repository "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" '
  .id == $id and .name == $name and .digest == $digest and .expired == false and
  (.created_at | type == "string") and (.expires_at | type == "string") and
  (.workflow_run | type == "object" and .id == $run and .repository_id == $repository and .head_sha == $signer)
' <<< "$receipt" >/dev/null
jq -cn --slurpfile binding "$binding" --argjson receipt_id "$receipt_id" --arg receipt_name "$receipt_name" --arg receipt_digest "$receipt_digest" --arg created "$(jq -r .created_at <<< "$receipt")" --arg expires "$(jq -r .expires_at <<< "$receipt")" '{lineageSchemaVersion:1,stageArtifact:$binding[0].stageArtifact,stageManifest:$binding[0].stageManifest,stageManifestSha256:$binding[0].stageManifestSha256,attestation:$binding[0].attestation,producerSealingReceiptArtifact:{artifactId:$receipt_id,artifactName:$receipt_name,uploadActionDigest:$receipt_digest,artifactDigest:("sha256:"+$receipt_digest),createdAt:$created,expiresAt:$expires,expired:false}}' | jq -cS . | tr -d '\n' > "$output"
sha=$(sha256sum "$output" | awk '{print $1}')
printf 'sha256=%s\nreceipt_rest_digest=sha256:%s\nreceipt_created_at=%s\nreceipt_expires_at=%s\nattestation_subject_digest=sha256:%s\n' "$sha" "$receipt_digest" "$(jq -r .created_at <<< "$receipt")" "$(jq -r .expires_at <<< "$receipt")" "$sha" >> "$github_output"
