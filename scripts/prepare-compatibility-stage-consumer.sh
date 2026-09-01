#!/usr/bin/env bash
# Trusted macOS wrapper. Only this helper may inspect acquisition evidence.
set -euo pipefail
expected= input= output= binding_output=
while (($#)); do case $1 in
  --expected) expected=$2; shift 2;; --input) input=$2; shift 2;;
  --output) output=$2; shift 2;; --binding-output) binding_output=$2; shift 2;; *) exit 2;;
esac; done
[[ -f $expected && -d $input && -n $output && -n $binding_output && ! -e $output && ! -e $binding_output ]] || exit 2
[[ $output != "$input" && $output != "$input"/* && $binding_output != "$input" && $binding_output != "$input"/* ]] || exit 2
# The acquisition directory is a capability boundary, never a cache.
canonical_lineage=
cleanup() {
  [[ -z $canonical_lineage ]] || rm -f -- "$canonical_lineage" 2>/dev/null || true
  chmod -R u+w -- "$input" 2>/dev/null || true
  rm -rf -- "$input"
}
trap cleanup EXIT
: "${STAGE_ARTIFACT_NAME:?}" "${STAGE_ARTIFACT_ID:?}" "${STAGE_UPLOAD_ACTION_DIGEST:?}" "${STAGE_REST_DIGEST:?}" "${STAGE_CREATED_AT:?}" "${STAGE_EXPIRES_AT:?}" "${STAGE_MANIFEST_SHA256:?}" "${STAGE_ATTESTATION_SUBJECT_DIGEST:?}" "${STAGE_ATTESTATION_BUNDLE_SHA256:?}" "${PRODUCER_WORKFLOW_SIGNER_SHA:?}" "${PRODUCER_WORKFLOW_RUN_ID:?}" "${PRODUCER_RUN_ATTEMPT:?}" "${PRODUCER_SEALING_CHECK_RUN_ID:?}" "${PRODUCER_SEALING_RECEIPT_ARTIFACT_ID:?}" "${PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST:?}" "${PRODUCER_SEALING_RECEIPT_REST_DIGEST:?}" "${PRODUCER_SEALING_RECEIPT_CREATED_AT:?}" "${PRODUCER_SEALING_RECEIPT_EXPIRES_AT:?}" "${PRODUCER_LINEAGE_ARTIFACT_ID:?}" "${PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST:?}" "${PRODUCER_LINEAGE_REST_DIGEST:?}" "${PRODUCER_LINEAGE_SHA256:?}" "${PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST:?}" "${PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256:?}" "${PRODUCER_ROLE:?}" "${CONSUMER_ROLE:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${CONSUMER_CANDIDATE_CHECK_RUN_ID:?}"
stage=$input/stage; receipt=$input/receipt/ci-seal-receipt.json; lineage=$input/lineage/compatibility-stage-producer-lineage.json
stage_manifest=$stage/compatibility-stage-manifest.json; stage_bundle=$stage/compatibility-stage-attestation.sigstore.json
receipt_bundle=$input/receipt/ci-seal-receipt-attestation.sigstore.json; lineage_bundle=$input/lineage/compatibility-stage-producer-lineage-attestation.sigstore.json
for path in "$stage_manifest" "$stage_bundle" "$receipt" "$receipt_bundle" "$lineage" "$lineage_bundle" "$input/trusted_root.jsonl" "$input/stage-verification.json" "$input/receipt-verification.json" "$input/lineage-verification.json"; do [[ -f $path && ! -L $path ]] || exit 1; done
sha256_file() { sha256sum "$1" | awk '{print $1}'; }
stage_sha=$(sha256_file "$stage_manifest"); receipt_sha=$(sha256_file "$receipt"); lineage_sha=$(sha256_file "$lineage")
stage_bundle_sha=$(sha256_file "$stage_bundle"); lineage_bundle_sha=$(sha256_file "$lineage_bundle")
canonical_lineage=$(mktemp "${TMPDIR:-/tmp}/burlmd-compatibility-lineage.XXXXXX")
LC_ALL=C jq -cS . "$lineage" | tr -d '\n' >"$canonical_lineage"
cmp -- "$canonical_lineage" "$lineage"
rm -f -- "$canonical_lineage"
canonical_lineage=
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# gh has checked the signature before emitting JSON. Bind the complete returned
# certificate and predicate to one exact subject instead of trusting its exit.
verify_result() {
  local result=$1 subject_name=$2 subject_sha=$3
  jq -e --arg subject_name "$subject_name" --arg subject "$subject_sha" --arg repository "$GITHUB_REPOSITORY" --arg repository_id "$GITHUB_REPOSITORY_ID" --arg signer "$PRODUCER_WORKFLOW_SIGNER_SHA" --arg run "$PRODUCER_WORKFLOW_RUN_ID" --arg attempt "$PRODUCER_RUN_ATTEMPT" '
    type == "array" and length == 1 and (.[0] | .verificationResult.signature.certificate as $c | .verificationResult.statement as $s | $s.predicate.buildDefinition as $build |
    ($s.subject | type == "array" and length == 1 and .[0].name == $subject_name and .[0].digest.sha256 == $subject) and $s.predicateType == "https://slsa.dev/provenance/v1" and
    $c.issuer == "https://token.actions.githubusercontent.com" and $c.sourceRepositoryURI == ("https://github.com/" + $repository) and $c.sourceRepositoryDigest == $signer and $c.sourceRepositoryRef == "refs/heads/master" and $c.buildSignerURI == ("https://github.com/" + $repository + "/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master") and $c.buildSignerDigest == $signer and $c.runnerEnvironment == "github-hosted" and $c.runInvocationURI == ("https://github.com/" + $repository + "/actions/runs/" + $run + "/attempts/" + $attempt) and
    $build.buildType == "https://actions.github.io/buildtypes/workflow/v1" and $build.externalParameters.workflow.repository == ("https://github.com/" + $repository) and $build.externalParameters.workflow.path == ".github/workflows/ci.yml" and $build.externalParameters.workflow.ref == "refs/heads/master" and $build.internalParameters.github.event_name == "workflow_dispatch" and ($build.internalParameters.github.repository_id | tostring) == $repository_id and $build.internalParameters.github.runner_environment == "github-hosted" and ([ $build.resolvedDependencies[]?.digest.gitCommit? ] | index($signer)) != null and $s.predicate.runDetails.builder.id == $c.buildSignerURI)
  ' "$result" >/dev/null
}
verify_result "$input/stage-verification.json" compatibility-stage-manifest.json "$stage_sha"
verify_result "$input/receipt-verification.json" ci-seal-receipt.json "$receipt_sha"
verify_result "$input/lineage-verification.json" compatibility-stage-producer-lineage.json "$lineage_sha"
nonce=$(jq -er '.artifactNonce | select(test("^[0-9a-f]{32}$"))' "$expected")
# Raw contract v33 deliberately excludes this derived artifact name from the
# consumer_trusted_inputs transport. Its only valid value is fixed locally by
# the authenticated expected-identity nonce.
producer_lineage_artifact_name="managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$nonce"
# The immutable-ID download action has already checked each transport digest.
# The signed canonical lineage and the complete macOS 26 seal interface bind
# their REST observations.  This candidate must not re-query artifacts: final
# authenticated aggregation rechecks their current REST state.
jq -e --arg expected_sha "$(sha256_file "$expected")" --arg now "$now" --arg stage_sha "$stage_sha" --arg receipt_sha "$receipt_sha" --arg lineage_sha "$lineage_sha" --arg stage_bundle "$stage_bundle_sha" --arg lineage_bundle "$lineage_bundle_sha" --arg producer_lineage_artifact_name "$producer_lineage_artifact_name" '
  .lineageSchemaVersion==1 and .stageArtifact.artifactName==env.STAGE_ARTIFACT_NAME and (.stageArtifact.artifactId|tostring)==env.STAGE_ARTIFACT_ID and .stageArtifact.uploadActionDigest==env.STAGE_UPLOAD_ACTION_DIGEST and .stageArtifact.artifactDigest==env.STAGE_REST_DIGEST and .stageArtifact.createdAt==env.STAGE_CREATED_AT and .stageArtifact.expiresAt==env.STAGE_EXPIRES_AT and .stageManifestSha256==$stage_sha and .stageManifestSha256==env.STAGE_MANIFEST_SHA256 and .attestation.subjectDigest==("sha256:"+$stage_sha) and .attestation.subjectDigest==env.STAGE_ATTESTATION_SUBJECT_DIGEST and .attestation.bundleSha256==$stage_bundle and .attestation.bundleSha256==env.STAGE_ATTESTATION_BUNDLE_SHA256 and .stageManifest.expectedIdentitySha256==$expected_sha and .stageManifest.workflowSignerSha==env.PRODUCER_WORKFLOW_SIGNER_SHA and (.stageManifest.workflowRunId|tostring)==env.PRODUCER_WORKFLOW_RUN_ID and (.stageManifest.runAttempt|tostring)==env.PRODUCER_RUN_ATTEMPT and (.stageManifest.producerSealingCheckRunId|tostring)==env.PRODUCER_SEALING_CHECK_RUN_ID and .stageManifest.producerRole==env.PRODUCER_ROLE and .stageManifest.consumerRole==env.CONSUMER_ROLE and (.producerSealingReceiptArtifact.artifactId|tostring)==env.PRODUCER_SEALING_RECEIPT_ARTIFACT_ID and .producerSealingReceiptArtifact.uploadActionDigest==env.PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST and .producerSealingReceiptArtifact.artifactDigest==env.PRODUCER_SEALING_RECEIPT_REST_DIGEST and .producerSealingReceiptArtifact.createdAt==env.PRODUCER_SEALING_RECEIPT_CREATED_AT and .producerSealingReceiptArtifact.expiresAt==env.PRODUCER_SEALING_RECEIPT_EXPIRES_AT and $producer_lineage_artifact_name==("managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-"+.stageManifest.artifactNonce) and env.PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST==(env.PRODUCER_LINEAGE_REST_DIGEST|ltrimstr("sha256:")) and env.PRODUCER_LINEAGE_SHA256==$lineage_sha and env.PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST==("sha256:"+$lineage_sha) and env.PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256==$lineage_bundle and .attestation.issuer=="https://token.actions.githubusercontent.com" and .attestation.repository==env.GITHUB_REPOSITORY and (.attestation.repositoryId|tostring)==env.GITHUB_REPOSITORY_ID and .attestation.workflowPath==".github/workflows/ci-role-macos-26-arm64.yml" and .attestation.jobWorkflowRef==(env.GITHUB_REPOSITORY+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master") and .attestation.jobWorkflowSha==env.PRODUCER_WORKFLOW_SIGNER_SHA and .attestation.sourceRepositoryDigest==env.PRODUCER_WORKFLOW_SIGNER_SHA and (.attestation.workflowRunId|tostring)==env.PRODUCER_WORKFLOW_RUN_ID and (.attestation.runAttempt|tostring)==env.PRODUCER_RUN_ATTEMPT and (.attestation.checkRunId|tostring)==env.PRODUCER_SEALING_CHECK_RUN_ID and .attestation.runnerEnvironment=="github-hosted" and (.producerSealingReceiptArtifact.expiresAt|fromdateiso8601)>($now|fromdateiso8601) and (.stageArtifact.expiresAt|fromdateiso8601)>($now|fromdateiso8601)
' "$lineage" >/dev/null
jq -e --slurpfile lineage "$lineage" '.schemaVersion==2 and .ticketIdentity=="BURL-O001" and .role=="macos-26-arm64" and .compatibilityStage.producerStage.stageArtifact==$lineage[0].stageArtifact and .compatibilityStage.producerStage.stageManifest==$lineage[0].stageManifest and .compatibilityStage.producerStage.stageManifestSha256==$lineage[0].stageManifestSha256 and .compatibilityStage.producerStage.attestation==$lineage[0].attestation' "$receipt" >/dev/null
mkdir -p "$output/roles/macos-26-arm64/handoff/outbox" "$(dirname "$binding_output")"
for member in handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256; do
  source=$stage/$member
  [[ -f $source && ! -L $source ]] || exit 1
  declared=$(jq -ce --arg name "$member" '[.stageManifest.members[]|select(.name==$name)]|if length==1 then .[0] else error("member") end' "$lineage") || exit 1
  actual_sha=$(sha256_file "$source")
  declared_sha=$(jq -er '.sha256 | select(test("^[0-9a-f]{64}$"))' <<<"$declared") || exit 1
  actual_bytes=$(wc -c <"$source")
  declared_bytes=$(jq -er '.bytes | select(type == "number" and floor == . and . >= 0)' <<<"$declared") || exit 1
  [[ $actual_sha == "$declared_sha" && $actual_bytes == "$declared_bytes" ]] || exit 1
  install -m 0444 "$source" "$output/roles/macos-26-arm64/$member"
done
find "$output" -type d -exec chmod 0555 {} +; find "$output" -type f -exec chmod 0444 {} +
root_sha=$(sha256_file "$input/trusted_root.jsonl"); stage_result=$(sha256_file "$input/stage-verification.json"); receipt_result=$(sha256_file "$input/receipt-verification.json"); lineage_result=$(sha256_file "$input/lineage-verification.json")
transport=$(jq -cn --slurpfile lineage "$lineage" --arg bundle_sha "$lineage_bundle_sha" --arg lineage_name "$producer_lineage_artifact_name" '{artifactId:(env.PRODUCER_LINEAGE_ARTIFACT_ID|tonumber),artifactName:$lineage_name,uploadActionDigest:env.PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST,artifactDigest:env.PRODUCER_LINEAGE_REST_DIGEST,attestation:{bundleMember:"compatibility-stage-producer-lineage-attestation.sigstore.json",bundleSha256:$bundle_sha,subjectName:"compatibility-stage-producer-lineage.json",subjectDigest:("sha256:"+env.PRODUCER_LINEAGE_SHA256),predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",repository:env.GITHUB_REPOSITORY,repositoryId:(env.GITHUB_REPOSITORY_ID|tonumber),workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:(env.GITHUB_REPOSITORY+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"),jobWorkflowSha:$lineage[0].stageManifest.workflowSignerSha,sourceRepositoryDigest:$lineage[0].stageManifest.workflowSignerSha,workflowRunId:$lineage[0].stageManifest.workflowRunId,runAttempt:$lineage[0].stageManifest.runAttempt,checkRunId:$lineage[0].stageManifest.producerSealingCheckRunId,runnerEnvironment:"github-hosted"}}')
jq -cn --slurpfile lineage "$lineage" --arg lineage_sha "$lineage_sha" --arg receipt_sha "$receipt_sha" --arg root_sha "$root_sha" --arg stage_result "$stage_result" --arg receipt_result "$receipt_result" --arg lineage_result "$lineage_result" --arg now "$now" --argjson transport "$transport" '{producerLineage:$lineage[0],producerLineageSha256:$lineage_sha,producerLineageArtifact:$transport,consumerBinding:{producerLineageSha256:$lineage_sha,producerLineageArtifact:$transport,producerSealingReceiptSha256:$receipt_sha,producerSealingReceiptArtifact:$lineage[0].producerSealingReceiptArtifact,downloadedStageArtifactId:$lineage[0].stageArtifact.artifactId,downloadActionSha:"3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",digestMismatchBehavior:"error",stageAttestationVerifiedOffline:true,stageAttestationVerificationResultSha256:$stage_result,producerReceiptAttestationVerifiedOffline:true,producerReceiptAttestationVerificationResultSha256:$receipt_result,producerLineageAttestationVerifiedOffline:true,producerLineageAttestationVerificationResultSha256:$lineage_result,trustedRootSha256:$root_sha,credentialsRemoved:true,membersReadOnly:true,consumerRole:"macos-15-arm64",workflowRunId:(env.GITHUB_RUN_ID|tonumber),runAttempt:(env.GITHUB_RUN_ATTEMPT|tonumber),consumerCandidateCheckRunId:(env.CONSUMER_CANDIDATE_CHECK_RUN_ID|tonumber),verifiedAt:$now}}' >"$binding_output"
chmod 0400 "$binding_output"
