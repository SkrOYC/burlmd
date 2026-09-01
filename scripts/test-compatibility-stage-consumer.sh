#!/usr/bin/env bash
# Exercise the real macOS compatibility consumer helper with locally signed
# shaped evidence.  The gh command is deliberately outside this fixture: these
# JSON files are its post-signature --format json boundary.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-compat-consumer.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
signer=0123456789012345678901234567890123456789
nonce=0123456789abcdef0123456789abcdef
hex=$(printf 'a%.0s' {1..64})
repository=SkrOYC/burlmd
run=4242; attempt=3; check=700
created=2026-09-01T00:00:00Z; expires=2035-09-01T00:00:00Z
sha() { sha256sum "$1" | awk '{print $1}'; }
verification() {
  local subject_name=$1 subject_sha=$2 output=$3
  jq -cn --arg name "$subject_name" --arg subject "$subject_sha" --arg signer "$signer" --arg repo "$repository" --argjson run "$run" --argjson attempt "$attempt" '
    [{verificationResult:{
      signature:{certificate:{issuer:"https://token.actions.githubusercontent.com",sourceRepositoryURI:("https://github.com/"+$repo),sourceRepositoryDigest:$signer,sourceRepositoryRef:"refs/heads/master",buildSignerURI:("https://github.com/"+$repo+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"),buildSignerDigest:$signer,runnerEnvironment:"github-hosted",runInvocationURI:("https://github.com/"+$repo+"/actions/runs/"+($run|tostring)+"/attempts/"+($attempt|tostring))}},
      statement:{subject:[{name:$name,digest:{sha256:$subject}}],predicateType:"https://slsa.dev/provenance/v1",predicate:{buildDefinition:{buildType:"https://actions.github.io/buildtypes/workflow/v1",externalParameters:{workflow:{repository:("https://github.com/"+$repo),path:".github/workflows/ci.yml",ref:"refs/heads/master"}},internalParameters:{github:{event_name:"workflow_dispatch",repository_id:"9",runner_environment:"github-hosted"}},resolvedDependencies:[{digest:{gitCommit:$signer}}]},runDetails:{builder:{id:("https://github.com/"+$repo+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master")}}}}
    }}]' >"$output"
}
make_fixture() {
  local input=$tmp/acquisition
  chmod -R u+w -- "$tmp/members" 2>/dev/null || true
  rm -rf -- "$input" "$tmp/members" "$tmp/handoff.json" "$tmp/expected.json"
  mkdir -p "$input/stage/handoff/outbox" "$input/receipt" "$input/lineage"
  printf construction >"$input/stage/handoff/outbox/macos-current-construction.tar.zst"
  printf '%s  %s\n' "$hex" macos-current-construction.tar.zst >"$input/stage/handoff/outbox/macos-current-construction.sha256"
  local construction_sha checksum_sha expected_sha manifest_sha lineage_sha receipt_sha bundle_sha
  construction_sha=$(sha "$input/stage/handoff/outbox/macos-current-construction.tar.zst")
  checksum_sha=$(sha "$input/stage/handoff/outbox/macos-current-construction.sha256")
  jq -cn --arg nonce "$nonce" '{artifactNonce:$nonce}' >"$tmp/expected.json"
  expected_sha=$(sha "$tmp/expected.json")
  jq -cn --arg expected "$expected_sha" --arg signer "$signer" --arg nonce "$nonce" --arg construction "$construction_sha" --arg checksum "$checksum_sha" '
    {expectedIdentitySha256:$expected,workflowSignerSha:$signer,workflowRunId:4242,runAttempt:3,producerSealingCheckRunId:700,producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",artifactNonce:$nonce,members:[{name:"handoff/outbox/macos-current-construction.tar.zst",sha256:$construction,bytes:12},{name:"handoff/outbox/macos-current-construction.sha256",sha256:$checksum,bytes:101}]}' >"$input/stage/compatibility-stage-manifest.json"
  # Correct the exact fixture byte counts after the files exist.
  jq --argjson construction_bytes "$(wc -c <"$input/stage/handoff/outbox/macos-current-construction.tar.zst")" --argjson checksum_bytes "$(wc -c <"$input/stage/handoff/outbox/macos-current-construction.sha256")" '.members[0].bytes=$construction_bytes | .members[1].bytes=$checksum_bytes' "$input/stage/compatibility-stage-manifest.json" >"$input/stage/next" && mv "$input/stage/next" "$input/stage/compatibility-stage-manifest.json"
  printf stage-bundle >"$input/stage/compatibility-stage-attestation.sigstore.json"
  manifest_sha=$(sha "$input/stage/compatibility-stage-manifest.json")
  bundle_sha=$(sha "$input/stage/compatibility-stage-attestation.sigstore.json")
  jq -cn --arg signer "$signer" --arg nonce "$nonce" --arg manifest "$manifest_sha" --arg bundle "$bundle_sha" --arg hex "$hex" --arg created "$created" --arg expires "$expires" --arg repo "$repository" '
    {lineageSchemaVersion:1,stageArtifact:{artifactId:101,artifactName:("managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex),createdAt:$created,expiresAt:$expires,expired:false,workflowRunId:4242},stageManifest:{expectedIdentitySha256:"",workflowSignerSha:$signer,workflowRunId:4242,runAttempt:3,producerSealingCheckRunId:700,producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",artifactNonce:$nonce,members:[]},stageManifestSha256:$manifest,attestation:{subjectDigest:("sha256:"+$manifest),bundleSha256:$bundle,issuer:"https://token.actions.githubusercontent.com",repository:$repo,repositoryId:9,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:($repo+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"),jobWorkflowSha:$signer,sourceRepositoryDigest:$signer,workflowRunId:4242,runAttempt:3,checkRunId:700,runnerEnvironment:"github-hosted"},producerSealingReceiptArtifact:{artifactId:103,artifactName:("managed-evidence-seal-receipt-macos-26-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex),createdAt:$created,expiresAt:$expires,expired:false,workflowRunId:4242}}' >"$input/lineage/lineage.base.json"
  jq --slurpfile manifest "$input/stage/compatibility-stage-manifest.json" --arg expected "$expected_sha" '.stageManifest=$manifest[0] | .stageManifest.expectedIdentitySha256=$expected' "$input/lineage/lineage.base.json" | LC_ALL=C jq -cS . | tr -d '\n' >"$input/lineage/compatibility-stage-producer-lineage.json"
  printf lineage-bundle >"$input/lineage/compatibility-stage-producer-lineage-attestation.sigstore.json"
  lineage_sha=$(sha "$input/lineage/compatibility-stage-producer-lineage.json")
  jq -cn --slurpfile lineage "$input/lineage/compatibility-stage-producer-lineage.json" '{schemaVersion:2,ticketIdentity:"BURL-O001",role:"macos-26-arm64",compatibilityStage:{producerStage:{stageArtifact:$lineage[0].stageArtifact,stageManifest:$lineage[0].stageManifest,stageManifestSha256:$lineage[0].stageManifestSha256,attestation:$lineage[0].attestation}}}' >"$input/receipt/ci-seal-receipt.json"
  printf receipt-bundle >"$input/receipt/ci-seal-receipt-attestation.sigstore.json"
  receipt_sha=$(sha "$input/receipt/ci-seal-receipt.json")
  verification compatibility-stage-manifest.json "$manifest_sha" "$input/stage-verification.json"
  verification ci-seal-receipt.json "$receipt_sha" "$input/receipt-verification.json"
  verification compatibility-stage-producer-lineage.json "$lineage_sha" "$input/lineage-verification.json"
  printf root >"$input/trusted_root.jsonl"
}
run_helper() {
  STAGE_ARTIFACT_NAME="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce" STAGE_ARTIFACT_ID=101 STAGE_UPLOAD_ACTION_DIGEST="$hex" STAGE_REST_DIGEST="sha256:$hex" STAGE_CREATED_AT="$created" STAGE_EXPIRES_AT="$expires" STAGE_MANIFEST_SHA256="$(sha "$tmp/acquisition/stage/compatibility-stage-manifest.json")" STAGE_ATTESTATION_SUBJECT_DIGEST="sha256:$(sha "$tmp/acquisition/stage/compatibility-stage-manifest.json")" STAGE_ATTESTATION_BUNDLE_SHA256="$(sha "$tmp/acquisition/stage/compatibility-stage-attestation.sigstore.json")" PRODUCER_WORKFLOW_SIGNER_SHA="$signer" PRODUCER_WORKFLOW_RUN_ID="$run" PRODUCER_RUN_ATTEMPT="$attempt" PRODUCER_SEALING_CHECK_RUN_ID="$check" PRODUCER_SEALING_RECEIPT_ARTIFACT_ID=103 PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST="$hex" PRODUCER_SEALING_RECEIPT_REST_DIGEST="sha256:$hex" PRODUCER_SEALING_RECEIPT_CREATED_AT="$created" PRODUCER_SEALING_RECEIPT_EXPIRES_AT="$expires" PRODUCER_LINEAGE_ARTIFACT_ID=102 PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST="$hex" PRODUCER_LINEAGE_REST_DIGEST="sha256:$hex" PRODUCER_LINEAGE_SHA256="$(sha "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json")" PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST="sha256:$(sha "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json")" PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256="$(sha "$tmp/acquisition/lineage/compatibility-stage-producer-lineage-attestation.sigstore.json")" PRODUCER_ROLE=macos-26-arm64 CONSUMER_ROLE=macos-15-arm64 GITHUB_REPOSITORY="$repository" GITHUB_REPOSITORY_ID=9 GITHUB_RUN_ID="$run" GITHUB_RUN_ATTEMPT="$attempt" CONSUMER_CANDIDATE_CHECK_RUN_ID=701 env ${BURLMD_FIXTURE_ENV:-} "$root/scripts/prepare-compatibility-stage-consumer.sh" --expected "$tmp/expected.json" --input "$tmp/acquisition" --output "$tmp/members" --binding-output "$tmp/handoff.json"
}
make_fixture; run_helper
[[ ! -e $tmp/acquisition && -f $tmp/members/roles/macos-26-arm64/handoff/outbox/macos-current-construction.tar.zst && -f $tmp/members/roles/macos-26-arm64/handoff/outbox/macos-current-construction.sha256 && $(find "$tmp/members" -type f | wc -l) == 2 && -f $tmp/handoff.json ]] || exit 1
[[ $(find "$tmp/members" -type f -printf '%P\n' | LC_ALL=C sort) == $'roles/macos-26-arm64/handoff/outbox/macos-current-construction.sha256\nroles/macos-26-arm64/handoff/outbox/macos-current-construction.tar.zst' ]] || exit 1
[[ $(stat -c '%a' "$tmp/members/roles/macos-26-arm64/handoff/outbox/macos-current-construction.tar.zst") == 444 && $(stat -c '%a' "$tmp/members/roles/macos-26-arm64/handoff/outbox/macos-current-construction.sha256") == 444 && $(stat -c '%a' "$tmp/handoff.json") == 400 ]] || exit 1
[[ $(jq -r '.consumerBinding.downloadedStageArtifactId' "$tmp/handoff.json") == 101 ]] || exit 1
[[ $(jq -r '.consumerBinding.downloadedStageArtifactId == .producerLineage.stageArtifact.artifactId' "$tmp/handoff.json") == true ]] || exit 1
for result in stage receipt lineage; do make_fixture; jq '.[] .verificationResult.signature.certificate.runnerEnvironment="self-hosted"' "$tmp/acquisition/$result-verification.json" >"$tmp/acquisition/next" && mv "$tmp/acquisition/next" "$tmp/acquisition/$result-verification.json"; if run_helper >/dev/null 2>&1; then exit 1; fi; [[ ! -e $tmp/acquisition ]] || exit 1; done
for result in stage receipt lineage; do
  make_fixture
  case $result in
    stage) cp "$tmp/acquisition/receipt-verification.json" "$tmp/acquisition/stage-verification.json";;
    receipt) cp "$tmp/acquisition/lineage-verification.json" "$tmp/acquisition/receipt-verification.json";;
    lineage) cp "$tmp/acquisition/stage-verification.json" "$tmp/acquisition/lineage-verification.json";;
  esac
  if run_helper >/dev/null 2>&1; then echo "accepted swapped $result verification result" >&2; exit 1; fi
  [[ ! -e $tmp/acquisition ]] || exit 1
done
for mutation in corrupt-member-hash corrupt-member-size; do
  make_fixture
  case $mutation in
    corrupt-member-hash) jq '.stageManifest.members[0].sha256 = ("0" * 64)' "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" >"$tmp/acquisition/next" ;;
    corrupt-member-size) jq '.stageManifest.members[0].bytes += 1' "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" >"$tmp/acquisition/next" ;;
  esac
  LC_ALL=C jq -cS . "$tmp/acquisition/next" | tr -d '\n' >"$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json"
  verification compatibility-stage-producer-lineage.json "$(sha "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json")" "$tmp/acquisition/lineage-verification.json"
  if run_helper >/dev/null 2>&1; then echo "accepted $mutation" >&2; exit 1; fi
  [[ ! -e $tmp/acquisition ]] || exit 1
done
for mutation in trailing-lf trailing-lfs trailing-space pretty; do
  make_fixture
  case $mutation in
    trailing-lf) printf '\n' >>"$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" ;;
    trailing-lfs) printf '\n\n' >>"$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" ;;
    trailing-space) printf ' ' >>"$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" ;;
    pretty) jq . "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" >"$tmp/acquisition/next" && mv "$tmp/acquisition/next" "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json" ;;
  esac
  verification compatibility-stage-producer-lineage.json "$(sha "$tmp/acquisition/lineage/compatibility-stage-producer-lineage.json")" "$tmp/acquisition/lineage-verification.json"
  if run_helper >/dev/null 2>&1; then echo "accepted noncanonical lineage: $mutation" >&2; exit 1; fi
  [[ ! -e $tmp/acquisition ]] || exit 1
done
consumer_trusted_inputs=(STAGE_ARTIFACT_NAME STAGE_ARTIFACT_ID STAGE_UPLOAD_ACTION_DIGEST STAGE_REST_DIGEST STAGE_CREATED_AT STAGE_EXPIRES_AT STAGE_MANIFEST_SHA256 STAGE_ATTESTATION_SUBJECT_DIGEST STAGE_ATTESTATION_BUNDLE_SHA256 PRODUCER_WORKFLOW_SIGNER_SHA PRODUCER_WORKFLOW_RUN_ID PRODUCER_RUN_ATTEMPT PRODUCER_SEALING_CHECK_RUN_ID PRODUCER_SEALING_RECEIPT_ARTIFACT_ID PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST PRODUCER_SEALING_RECEIPT_REST_DIGEST PRODUCER_SEALING_RECEIPT_CREATED_AT PRODUCER_SEALING_RECEIPT_EXPIRES_AT PRODUCER_LINEAGE_ARTIFACT_ID PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST PRODUCER_LINEAGE_REST_DIGEST PRODUCER_LINEAGE_SHA256 PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256 PRODUCER_ROLE CONSUMER_ROLE)
[[ ${#consumer_trusted_inputs[@]} == 26 ]] || exit 1
for input in "${consumer_trusted_inputs[@]}"; do make_fixture; if BURLMD_FIXTURE_ENV="$input=invalid" run_helper >/dev/null 2>&1; then echo "accepted mutated static input: $input" >&2; exit 1; fi; [[ ! -e $tmp/acquisition ]] || exit 1; done
printf 'compatibility stage consumer fixture passed\n'
