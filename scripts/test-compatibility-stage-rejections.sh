#!/usr/bin/env bash
# Runs the production collector compatibility-stage implementation against
# local ZIP, REST, receipt, lineage, and offline-attestation evidence.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-compatibility-stage.XXXXXX")
trap '[[ ${BURLMD_KEEP_FIXTURE_TMP:-} == 1 ]] || rm -rf -- "$tmp"' EXIT HUP INT TERM
jq -e '.properties.schemaVersion.const == 19 and (.properties.compatibilityStage.oneOf | length == 2)' "$root/.constitution/tech-spec/contracts/ci-evidence.schema.json" >/dev/null

collector_functions=$tmp/collector-functions.sh
awk '/^is_operational_api_status\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$collector_functions"
awk '/^artifact_by_name\(\)/ { copy = 1 } /^receipt_role\(\)/ { exit } copy { print }' "$root/scripts/managed-evidence.sh" >>"$collector_functions"
awk '/^compatibility_inventory_preflight\(\)/ { copy = 1 } /^accepted_report\(\)/ { exit } copy { print }' "$root/scripts/managed-evidence.sh" >>"$collector_functions"
source "$collector_functions"
sha256_file() { sha256sum "$1" | awk '{print $1}'; }
workflow_path() { case "$1" in macos-26-arm64) printf .github/workflows/ci-role-macos-26-arm64.yml;; *) return 1;; esac; }

nonce=0123456789abcdef0123456789abcdef
run_identity=managed:$nonce
readonly sha=0123456789012345678901234567890123456789
readonly hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly run_id=4242 attempt=3 REPOSITORY=SkrOYC/burlmd workflow_signer=$sha
readonly ROLES=(linux-x86_64 macos-26-arm64 macos-15-arm64)
readonly API_TRANSIENT=75 API_PERMISSION=76 API_FAILURE=77
export BURLMD_FIXTURE_SIGNER=$sha BURLMD_FIXTURE_RUN=$run_id BURLMD_FIXTURE_ATTEMPT=$attempt
export BURLMD_FIXTURE_UNATTESTED=false
mkdir -p "$tmp/bin" "$tmp/archives" "$tmp/rest"
GH_BIN=$tmp/bin/gh
API_BASE=https://api.github.test

cat >"$GH_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${BURLMD_FIXTURE_UNATTESTED:-false} != true ]] || exit 1
subject=$3
digest=$(sha256sum "$subject" | awk '{print $1}')
jq -cn --arg subject "$digest" --arg signer "$BURLMD_FIXTURE_SIGNER" --argjson run "$BURLMD_FIXTURE_RUN" --argjson attempt "$BURLMD_FIXTURE_ATTEMPT" '
  [{attestation:{bundle:{}},verificationResult:{signature:{certificate:{issuer:"https://token.actions.githubusercontent.com",sourceRepositoryURI:"https://github.com/SkrOYC/burlmd",sourceRepositoryDigest:$signer,sourceRepositoryRef:"refs/heads/master",buildSignerURI:"https://github.com/SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",buildSignerDigest:$signer,runnerEnvironment:"github-hosted",runInvocationURI:("https://github.com/SkrOYC/burlmd/actions/runs/" + ($run|tostring) + "/attempts/" + ($attempt|tostring))}},statement:{subject:[{digest:{sha256:$subject}}],predicateType:"https://slsa.dev/provenance/v1",predicate:{buildDefinition:{buildType:"https://actions.github.io/buildtypes/workflow/v1",externalParameters:{workflow:{repository:"https://github.com/SkrOYC/burlmd",path:".github/workflows/ci.yml",ref:"refs/heads/master"}},internalParameters:{github:{event_name:"workflow_dispatch",runner_environment:"github-hosted"}},resolvedDependencies:[{digest:{gitCommit:$signer}}]},runDetails:{builder:{id:"https://github.com/SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"}}}}}}]'
EOF
chmod +x "$GH_BIN"

api() {
  local url=${!#} id target
  if [[ $url =~ /artifacts/([0-9]+)/zip$ ]]; then
    id=${BASH_REMATCH[1]}; target=zip:$id
    [[ ${BURLMD_FIXTURE_API_TARGET:-} == "$target" ]] && return "${BURLMD_FIXTURE_API_STATUS:?missing fixture API status}"
    cat "$tmp/archives/$id.zip"
  elif [[ $url =~ /artifacts/([0-9]+)$ ]]; then
    id=${BASH_REMATCH[1]}; target=rest:$id
    [[ ${BURLMD_FIXTURE_API_TARGET:-} == "$target" ]] && return "${BURLMD_FIXTURE_API_STATUS:?missing fixture API status}"
    cat "$tmp/rest/$id.json"
  else return 1; fi
}
canonical_json() { LC_ALL=C jq -cS . "$1" | head -c -1; }
zip_members() { local id=$1 directory=$2; (cd "$directory" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -X -q "$tmp/archives/$id.zip" -@); }
artifact() { jq -cn --argjson id "$1" --arg name "$2" --arg digest "$3" --arg created "$4" --arg expires "$5" --argjson expired "$6" --argjson run "$run_id" '{id:$id,name:$name,digest:("sha256:"+$digest),created_at:$created,expires_at:$expires,expired:$expired,workflow_run:{id:$run}}'; }

rebind_lineage() {
  canonical_json "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"
  lineage_sha=$(sha256sum "$tmp/source/lineage.json" | awk '{print $1}')
  jq --slurpfile lineage "$tmp/source/lineage.json" '.compatibilityStage = {producerStage:{stageArtifact:$lineage[0].stageArtifact,stageManifest:$lineage[0].stageManifest,stageManifestSha256:$lineage[0].stageManifestSha256,attestation:$lineage[0].attestation}}' "$tmp/source/producer-receipt.base.json" >"$tmp/receipt-macos-26-arm64.json"
  producer_sha=$(sha256sum "$tmp/receipt-macos-26-arm64.json" | awk '{print $1}')
  jq --slurpfile lineage "$tmp/source/lineage.json" --arg sha "$lineage_sha" --arg producer_sha "$producer_sha" '.roleEvidence.compatibilityStage.producerLineage=$lineage[0] | .roleEvidence.compatibilityStage.producerLineageSha256=$sha | .roleEvidence.compatibilityStage.consumerBinding.producerLineageSha256=$sha | .roleEvidence.compatibilityStage.consumerBinding.producerSealingReceiptSha256=$producer_sha' "$tmp/source/consumer-manifest.base.json" >"$tmp/manifest-macos-15-arm64.json"
  jq --slurpfile lineage "$tmp/source/lineage.json" --arg sha "$lineage_sha" --arg producer_sha "$producer_sha" '.compatibilityStage.producerLineage=$lineage[0] | .compatibilityStage.producerLineageSha256=$sha | .compatibilityStage.consumerBinding.producerLineageSha256=$sha | .compatibilityStage.consumerBinding.producerSealingReceiptSha256=$producer_sha' "$tmp/source/consumer-receipt.base.json" >"$tmp/receipt-macos-15-arm64.json"
}

refresh_lineage_transport() { cp "$tmp/source/lineage.json" "$tmp/lineage/compatibility-stage-producer-lineage.json"; zip_members 102 "$tmp/lineage"; }

make_binding() {
  jq -cn --argjson transport "$1" '
    {producerLineage:null,producerLineageSha256:null,producerLineageArtifact:$transport,
     consumerBinding:{producerLineageSha256:null,producerLineageArtifact:$transport,producerSealingReceiptSha256:null,
       producerSealingReceiptArtifact:{artifactId:103,artifactName:"managed-evidence-seal-receipt-macos-26-arm64-0123456789abcdef0123456789abcdef",uploadActionDigest:("b"*64),artifactDigest:("sha256:"+("b"*64)),createdAt:"2026-09-01T00:00:00Z",expiresAt:"2035-09-01T00:00:00Z",expired:false,workflowRunId:4242},downloadedStageArtifactId:101,downloadActionSha:"3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",digestMismatchBehavior:"error",stageAttestationVerifiedOffline:true,stageAttestationVerificationResultSha256:("a"*64),producerReceiptAttestationVerifiedOffline:true,producerReceiptAttestationVerificationResultSha256:("a"*64),producerLineageAttestationVerifiedOffline:true,producerLineageAttestationVerificationResultSha256:("a"*64),trustedRootSha256:("a"*64),credentialsRemoved:true,membersReadOnly:true,consumerRole:"macos-15-arm64",workflowRunId:4242,runAttempt:3,consumerCandidateCheckRunId:701,verifiedAt:"2026-09-06T00:00:00Z"}}
  '
}

build_fixture() {
  rm -rf -- "$tmp/source" "$tmp/stage" "$tmp/lineage" "$tmp/archives" "$tmp/rest" "$tmp/compatibility-stage" "$tmp/compatibility-lineage"
  mkdir -p "$tmp/source" "$tmp/stage/handoff/outbox" "$tmp/lineage" "$tmp/archives" "$tmp/rest"
  ticket=BURL-O001; BURLMD_FIXTURE_UNATTESTED=false
  stage_name="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce"
  lineage_name="managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$nonce"
  receipt_name="managed-evidence-seal-receipt-macos-26-arm64-$nonce"
  created=2026-09-01T00:00:00Z; expires=2035-09-01T00:00:00Z
  stage_digest=$hash; receipt_digest=$(printf 'b%.0s' {1..64}); lineage_digest=$(printf 'c%.0s' {1..64})
  jq -cn --arg signer "$sha" --argjson run "$run_id" --argjson attempt "$attempt" '{stageSchemaVersion:1,ticketIdentity:"BURL-O001",producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",workflowSignerSha:$signer,testedSourceSha:$signer,workflowRunId:$run,runAttempt:$attempt,producerSealingCheckRunId:700}' >"$tmp/stage/compatibility-stage-manifest.json"
  printf '{"fixture":"stage-attestation"}' >"$tmp/stage/compatibility-stage-attestation.sigstore.json"
  printf bundle >"$tmp/stage/handoff/outbox/macos-current-construction.tar.zst"; printf hash >"$tmp/stage/handoff/outbox/macos-current-construction.sha256"
  stage_manifest_sha=$(sha256sum "$tmp/stage/compatibility-stage-manifest.json" | awk '{print $1}')
  stage_current=$(artifact 101 "$stage_name" "$stage_digest" "$created" "$expires" false)
  receipt_current=$(artifact 103 "$receipt_name" "$receipt_digest" "$created" "$expires" false)
  jq -cn --argjson stage "$stage_current" --argjson receipt "$receipt_current" --slurpfile manifest "$tmp/stage/compatibility-stage-manifest.json" --arg manifest_sha "$stage_manifest_sha" --arg signer "$sha" --argjson run "$run_id" --argjson attempt "$attempt" '
    {lineageSchemaVersion:1,stageArtifact:{artifactId:$stage.id,artifactName:$stage.name,uploadActionDigest:($stage.digest|ltrimstr("sha256:")),artifactDigest:$stage.digest,createdAt:$stage.created_at,expiresAt:$stage.expires_at,expired:false,workflowRunId:$run},stageManifest:$manifest[0],stageManifestSha256:$manifest_sha,attestation:{bundleMember:"compatibility-stage-attestation.sigstore.json",bundleSha256:("d"*64),subjectName:"compatibility-stage-manifest.json",subjectDigest:("sha256:"+$manifest_sha),predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",repository:"SkrOYC/burlmd",repositoryId:1,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$signer,sourceRepositoryDigest:$signer,workflowRunId:$run,runAttempt:$attempt,checkRunId:700,runnerEnvironment:"github-hosted"},producerSealingReceiptArtifact:{artifactId:$receipt.id,artifactName:$receipt.name,uploadActionDigest:($receipt.digest|ltrimstr("sha256:")),artifactDigest:$receipt.digest,createdAt:$receipt.created_at,expiresAt:$receipt.expires_at,expired:false,workflowRunId:$run}}
  ' >"$tmp/source/lineage.json"
  lineage_transport=$(jq -cn --arg name "$lineage_name" --arg digest "$lineage_digest" --arg signer "$sha" --argjson run "$run_id" --argjson attempt "$attempt" '{artifactId:102,artifactName:$name,uploadActionDigest:$digest,artifactDigest:("sha256:"+$digest),attestation:{bundleMember:"compatibility-stage-producer-lineage-attestation.sigstore.json",bundleSha256:("e"*64),subjectName:"compatibility-stage-producer-lineage.json",subjectDigest:("sha256:"+("f"*64)),predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",repository:"SkrOYC/burlmd",repositoryId:1,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$signer,sourceRepositoryDigest:$signer,workflowRunId:$run,runAttempt:$attempt,checkRunId:700,runnerEnvironment:"github-hosted"}}')
  jq -cn '{schemaVersion:2,compatibilityStage:null}' >"$tmp/source/producer-receipt.base.json"
  binding=$(make_binding "$lineage_transport")
  jq -cn --argjson binding "$binding" '{roleEvidence:{role:"macos-15-arm64",compatibilityStage:$binding}}' >"$tmp/source/consumer-manifest.base.json"
  jq -cn --argjson binding "$binding" '{schemaVersion:2,compatibilityStage:$binding}' >"$tmp/source/consumer-receipt.base.json"
  rebind_lineage
  jq -cn '{schemaVersion:2,compatibilityStage:null}' >"$tmp/receipt-linux-x86_64.json"
  cp "$tmp/source/lineage.json" "$tmp/lineage/compatibility-stage-producer-lineage.json"
  printf '{"fixture":"lineage-attestation"}' >"$tmp/lineage/compatibility-stage-producer-lineage-attestation.sigstore.json"
  zip_members 101 "$tmp/stage"; zip_members 102 "$tmp/lineage"
  # The accepted binding records the bytes actually downloaded from the
  # immutable lineage transport, rather than fixture-shaped placeholder
  # hashes. Keep this explicit so mutations of either attestation fact reach
  # the production collector check.
  actual_lineage_sha=$(sha256sum "$tmp/source/lineage.json" | awk '{print $1}')
  actual_lineage_bundle_sha=$(sha256sum "$tmp/lineage/compatibility-stage-producer-lineage-attestation.sigstore.json" | awk '{print $1}')
  jq --arg sha "$actual_lineage_sha" --arg bundle "$actual_lineage_bundle_sha" '
    .roleEvidence.compatibilityStage.producerLineageArtifact.attestation.bundleSha256 = $bundle |
    .roleEvidence.compatibilityStage.producerLineageArtifact.attestation.subjectDigest = ("sha256:" + $sha) |
    .roleEvidence.compatibilityStage.consumerBinding.producerLineageArtifact.attestation.bundleSha256 = $bundle |
    .roleEvidence.compatibilityStage.consumerBinding.producerLineageArtifact.attestation.subjectDigest = ("sha256:" + $sha)
  ' "$tmp/manifest-macos-15-arm64.json" >"$tmp/manifest.next"
  mv "$tmp/manifest.next" "$tmp/manifest-macos-15-arm64.json"
  jq --arg sha "$actual_lineage_sha" --arg bundle "$actual_lineage_bundle_sha" '
    .compatibilityStage.producerLineageArtifact.attestation.bundleSha256 = $bundle |
    .compatibilityStage.producerLineageArtifact.attestation.subjectDigest = ("sha256:" + $sha) |
    .compatibilityStage.consumerBinding.producerLineageArtifact.attestation.bundleSha256 = $bundle |
    .compatibilityStage.consumerBinding.producerLineageArtifact.attestation.subjectDigest = ("sha256:" + $sha)
  ' "$tmp/receipt-macos-15-arm64.json" >"$tmp/receipt.next"
  mv "$tmp/receipt.next" "$tmp/receipt-macos-15-arm64.json"
  lineage_current=$(artifact 102 "$lineage_name" "$lineage_digest" "$created" "$expires" false)
  printf '%s\n' "$stage_current" >"$tmp/rest/101.json"; printf '%s\n' "$lineage_current" >"$tmp/rest/102.json"; printf '%s\n' "$receipt_current" >"$tmp/rest/103.json"
  jq -cn --argjson stage "$stage_current" --argjson lineage "$lineage_current" --argjson receipt "$receipt_current" '{artifacts:[$stage,$lineage,$receipt]}' >"$tmp/inventory.json"
  roles=$(jq -cn --slurpfile consumer "$tmp/manifest-macos-15-arm64.json" --arg signer "$sha" --argjson run "$run_id" --argjson attempt "$attempt" '[{manifest:{roleEvidence:{role:"linux-x86_64",compatibilityStage:null}},origin:{sealingCheckRunId:600,workflowSignerSha:$signer,testedSourceSha:$signer,workflowRunId:$run,runAttempt:$attempt}},{manifest:{roleEvidence:{role:"macos-26-arm64",compatibilityStage:null}},origin:{sealingCheckRunId:700,workflowSignerSha:$signer,testedSourceSha:$signer,workflowRunId:$run,runAttempt:$attempt}},{manifest:$consumer[0],origin:{sealingCheckRunId:701,workflowSignerSha:$signer,testedSourceSha:$signer,workflowRunId:$run,runAttempt:$attempt}}]')
}

refresh_lineage_transport() {
  cp "$tmp/source/lineage.json" "$tmp/lineage/compatibility-stage-producer-lineage.json"
  zip_members 102 "$tmp/lineage"
}

run_case() {
  local name=$1 expected=$2 mutation=${3:-} observed stage_output
  build_fixture
  case "$mutation" in
    '') ;;
    missing) jq 'del(.artifacts[] | select(.id == 101))' "$tmp/inventory.json" >"$tmp/inventory.next"; mv "$tmp/inventory.next" "$tmp/inventory.json" ;;
    duplicate) jq '.artifacts += [.artifacts[] | select(.id == 101) | .id = 104]' "$tmp/inventory.json" >"$tmp/inventory.next"; mv "$tmp/inventory.next" "$tmp/inventory.json" ;;
    substituted) jq '(.artifacts[] | select(.id == 101).workflow_run.id) = 99' "$tmp/inventory.json" >"$tmp/inventory.next"; mv "$tmp/inventory.next" "$tmp/inventory.json" ;;
    expired) jq '(.artifacts[] | select(.id == 101).expired) = true' "$tmp/inventory.json" >"$tmp/inventory.next"; mv "$tmp/inventory.next" "$tmp/inventory.json" ;;
    corrupt-transport) printf 'not a zip' >"$tmp/archives/101.zip" ;;
    digest-mismatch) jq '.digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$tmp/rest/101.json" >"$tmp/rest/101.next"; mv "$tmp/rest/101.next" "$tmp/rest/101.json" ;;
    unattested) BURLMD_FIXTURE_UNATTESTED=true ;;
    wrong-signer) jq '.attestation.jobWorkflowSha = "ffffffffffffffffffffffffffffffffffffffff"' "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"; rebind_lineage; refresh_lineage_transport ;;
    wrong-run) jq '.attestation.workflowRunId = 99' "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"; rebind_lineage; refresh_lineage_transport ;;
    wrong-role) jq '.stageManifest.producerRole = "linux-x86_64"' "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"; rebind_lineage; refresh_lineage_transport ;;
    wrong-seal) jq '.attestation.checkRunId = 999' "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"; rebind_lineage; refresh_lineage_transport ;;
    stale-producer-receipt) jq '.producerSealingReceiptArtifact.expiresAt = "2020-01-01T00:00:00Z"' "$tmp/source/lineage.json" >"$tmp/source/lineage.next"; mv "$tmp/source/lineage.next" "$tmp/source/lineage.json"; jq '.expires_at = "2020-01-01T00:00:00Z"' "$tmp/rest/103.json" >"$tmp/rest/103.next"; mv "$tmp/rest/103.next" "$tmp/rest/103.json"; rebind_lineage; refresh_lineage_transport ;;
    noncanonical-lineage) printf '\n' >>"$tmp/lineage/compatibility-stage-producer-lineage.json"; zip_members 102 "$tmp/lineage" ;;
    lineage-sha-mismatch) jq '.roleEvidence.compatibilityStage.producerLineageSha256 = ("0" * 64)' "$tmp/manifest-macos-15-arm64.json" >"$tmp/manifest.next"; mv "$tmp/manifest.next" "$tmp/manifest-macos-15-arm64.json"; roles=$(jq --slurpfile manifest "$tmp/manifest-macos-15-arm64.json" '.[2].manifest = $manifest[0]' <<<"$roles") ;;
    consumer-unbound) jq '.roleEvidence.compatibilityStage.consumerBinding.downloadedStageArtifactId = 999' "$tmp/manifest-macos-15-arm64.json" >"$tmp/manifest.next"; mv "$tmp/manifest.next" "$tmp/manifest-macos-15-arm64.json"; roles=$(jq --slurpfile manifest "$tmp/manifest-macos-15-arm64.json" '.[2].manifest = $manifest[0]' <<<"$roles") ;;
    consumer-receipt-unbound) jq '.compatibilityStage.consumerBinding.downloadedStageArtifactId = 999' "$tmp/receipt-macos-15-arm64.json" >"$tmp/receipt.next"; mv "$tmp/receipt.next" "$tmp/receipt-macos-15-arm64.json" ;;
    unexpected) ticket=BURL-M003; jq '.compatibilityStage = {unexpected:true}' "$tmp/receipt-macos-15-arm64.json" >"$tmp/receipt.next"; mv "$tmp/receipt.next" "$tmp/receipt-macos-15-arm64.json"; roles=$(jq '.[2].manifest.roleEvidence.compatibilityStage = {unexpected:true}' <<<"$roles") ;;
    *) echo "unknown mutation: $mutation" >&2; exit 2 ;;
  esac
  compatibility_rejection_code=
  if ! compatibility_inventory_preflight "$tmp/inventory.json"; then
    observed=$compatibility_rejection_code
  else
    stage_output=$tmp/compatibility-stage-output.json
    if ! compatibility_stage_for "$tmp/inventory.json" "$roles" >"$stage_output"; then observed=$compatibility_rejection_code
    else observed=accepted; [[ $ticket == BURL-O001 ]] && jq -e '.producerLineage.lineageSchemaVersion == 1 and .consumerBinding.downloadedStageArtifactId == .producerLineage.stageArtifact.artifactId and .consumerBinding.downloadedStageArtifactId == 101' "$stage_output" >/dev/null; fi
  fi
  [[ $observed == "$expected" ]] || { printf '%s: observed %s, expected %s\n' "$name" "$observed" "$expected" >&2; exit 1; }
  printf '%-32s %s\n' "$name" "$observed"
}

run_case valid-burl-o001 accepted

# An unavailable transport or current REST observation is operational, not
# evidence. All three typed API statuses must survive each collector family.
assert_operational_status() {
  local family=$1 target=$2 expected observed
  for expected in "$API_TRANSIENT" "$API_PERMISSION" "$API_FAILURE"; do
    build_fixture
    BURLMD_FIXTURE_API_TARGET=$target BURLMD_FIXTURE_API_STATUS=$expected
    set +e
    compatibility_stage_for "$tmp/inventory.json" "$roles" >"$tmp/compatibility-stage-output.json"
    observed=$?
    set -e
    [[ $observed == "$expected" ]] || {
      printf '%s returned %s, expected operational status %s\n' "$family" "$observed" "$expected" >&2
      exit 1
    }
  done
  unset BURLMD_FIXTURE_API_TARGET BURLMD_FIXTURE_API_STATUS
  printf '%-32s operational statuses preserved\n' "$family"
}

assert_operational_status stage-download zip:101
assert_operational_status lineage-download zip:102
assert_operational_status stage-current-rest rest:101
assert_operational_status producer-receipt-current-rest rest:103

# The aggregate must not copy any macOS 15 consumption field merely because it
# is present in an untrusted manifest. Mutate one representative from every
# transport, verification, REST, locator, and lifecycle field family. The
# production collector must reject before it can render accepted output.
run_binding_field_mutation() {
  local name=$1 path=$2 value=$3 observed
  build_fixture
  jq --argjson path "$path" --argjson value "$value" 'setpath(["roleEvidence", "compatibilityStage"] + $path; $value)' \
    "$tmp/manifest-macos-15-arm64.json" >"$tmp/manifest.next"
  mv "$tmp/manifest.next" "$tmp/manifest-macos-15-arm64.json"
  roles=$(jq --slurpfile manifest "$tmp/manifest-macos-15-arm64.json" '.[2].manifest = $manifest[0]' <<<"$roles")
  compatibility_rejection_code=
  if compatibility_stage_for "$tmp/inventory.json" "$roles" >/dev/null; then
    echo "$name: accepted mutated compatibility binding" >&2
    exit 1
  fi
  observed=$compatibility_rejection_code
  [[ $observed == compatibility-stage-consumer-unbound || $observed == compatibility-stage-lineage-sha-mismatch ]] || {
    echo "$name: unexpected rejection $observed" >&2; exit 1;
  }
  printf '%-32s %s\n' "$name" "$observed"
}

for mutation in \
  'transport-id:["producerLineageArtifact","artifactId"]:999' \
  'transport-digest:["producerLineageArtifact","artifactDigest"]:"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  'transport-attestation:["producerLineageArtifact","attestation","bundleSha256"]:"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  'binding-lineage-sha:["consumerBinding","producerLineageSha256"]:"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  'binding-producer-receipt:["consumerBinding","producerSealingReceiptArtifact","artifactId"]:999' \
  'binding-stage-id:["consumerBinding","downloadedStageArtifactId"]:999' \
  'binding-download-action:["consumerBinding","downloadActionSha"]:"ffffffffffffffffffffffffffffffffffffffff"' \
  'binding-offline-result:["consumerBinding","stageAttestationVerificationResultSha256"]:"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  'binding-trusted-root:["consumerBinding","trustedRootSha256"]:"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  'binding-lifecycle:["consumerBinding","credentialsRemoved"]:false' \
  'binding-role-run:["consumerBinding","consumerRole"]:"linux-x86_64"' \
  'binding-locator:["consumerBinding","consumerCandidateCheckRunId"]:999'; do
  name=${mutation%%:*}; remainder=${mutation#*:}; path=${remainder%%:*}; value=${remainder#*:}
  run_binding_field_mutation "$name" "$path" "$value"
done

# The no-stage BURL-M003 aggregate path is explicitly null.
build_fixture
ticket=BURL-M003
roles=$(jq '.[].manifest.roleEvidence.compatibilityStage = null' <<<"$roles")
jq '.compatibilityStage = null' "$tmp/receipt-macos-15-arm64.json" >"$tmp/receipt.next"
mv "$tmp/receipt.next" "$tmp/receipt-macos-15-arm64.json"
jq '.compatibilityStage = null' "$tmp/receipt-macos-26-arm64.json" >"$tmp/receipt.next"
mv "$tmp/receipt.next" "$tmp/receipt-macos-26-arm64.json"
jq '.artifacts |= map(select(.id == 103))' "$tmp/inventory.json" >"$tmp/inventory.next"
mv "$tmp/inventory.next" "$tmp/inventory.json"
compatibility_rejection_code=
compatibility_inventory_preflight "$tmp/inventory.json"
compatibility_stage_for "$tmp/inventory.json" "$roles" >"$tmp/no-stage.json"
[[ $(<"$tmp/no-stage.json") == null ]]
printf '%-32s %s\n' valid-no-stage-ticket accepted

for case in \
  missing:compatibility-stage-missing \
  duplicate:compatibility-stage-duplicate \
  substituted:compatibility-stage-substituted \
  expired:compatibility-stage-expired \
  corrupt-transport:compatibility-stage-substituted \
  digest-mismatch:compatibility-stage-digest-mismatch \
  unattested:compatibility-stage-unattested \
  wrong-signer:compatibility-stage-wrong-signer \
  wrong-run:compatibility-stage-wrong-run \
  wrong-role:compatibility-stage-wrong-role \
  wrong-seal:compatibility-stage-wrong-seal \
  stale-producer-receipt:compatibility-stage-stale-producer-receipt \
  noncanonical-lineage:compatibility-stage-noncanonical-lineage \
  lineage-sha-mismatch:compatibility-stage-lineage-sha-mismatch \
  consumer-unbound:compatibility-stage-consumer-unbound \
  consumer-receipt-unbound:compatibility-stage-consumer-unbound \
  unexpected:compatibility-stage-unexpected; do
  code=${case%%:*}
  run_case "$code" "${case#*:}" "$code"
done

printf 'compatibility-stage typed rejection fixture passed\n'
