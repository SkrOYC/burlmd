#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
if [[ ${BURLMD_SEAL_VALIDATORS_LOCKED_SHELL:-} != 1 ]]; then
  exec "$root/scripts/ci-devenv.sh" env BURLMD_SEAL_VALIDATORS_LOCKED_SHELL=1 "$0" "$@"
fi
real_taplo=$(command -v taplo)
export BURLMD_REAL_TAPLO=$real_taplo
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-seal-fixture.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
# The production validator deliberately requires the locked TOML parser for
# Spike paths. This fixture supplies only the tiny trusted contract view it
# needs, so it remains runnable before the local devenv closure is entered.
cat >"$tmp/bin/taplo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${!#} != 'spikes[*]' ]]; then
  exec "$BURLMD_REAL_TAPLO" "$@"
fi
printf '%s\n' '[
  {"id":"SPK-BURL-H001","path":"fixture/BURL-H001","verification_steps":[
    {"run_role":"linux-reference","workdir":".","command":"probe --output fixture/BURL-H001/runs/ast.json --handoff-bundle fixture/BURL-H001/handoff/outbox/ast.tar.zst --handoff-sha256 fixture/BURL-H001/handoff/outbox/ast.sha256"}
  ]},
  {"id":"SPK-BURL-H002","path":"fixture/BURL-H002","verification_steps":[
    {"run_role":"linux-default-filesystem","workdir":".","command":"probe --output fixture/BURL-H002/runs/path.json --handoff-bundle fixture/BURL-H002/handoff/outbox/path.tar.zst --handoff-sha256 fixture/BURL-H002/handoff/outbox/path.sha256"}
  ]},
  {"id":"SPK-BURL-I001","path":"fixture/BURL-I001","verification_steps":[
    {"run_role":"linux-reference","workdir":".","command":"probe --output fixture/BURL-I001/runs/asset.json --handoff-bundle fixture/BURL-I001/handoff/outbox/asset.tar.zst --handoff-sha256 fixture/BURL-I001/handoff/outbox/asset.sha256"}
  ]},
  {"id":"SPK-BURL-L001","path":"fixture/BURL-L001","verification_steps":[
    {"run_role":"linux-default-filesystem","workdir":".","command":"probe --output fixture/BURL-L001/runs/git.json --handoff-bundle fixture/BURL-L001/handoff/outbox/git.tar.zst --handoff-sha256 fixture/BURL-L001/handoff/outbox/git.sha256"}
  ]},
  {"id":"SPK-BURL-O001","path":"fixture","verification_steps":[
    {"run_role":"linux-build","workdir":"fixture","command":"probe --output runs/pkg.json --stdout logs/pkg.stdout --stderr logs/pkg.stderr --copy-artifact-to artifacts/pkg.tar.zst --handoff-bundle handoff/outbox/pkg.tar.zst --handoff-sha256 handoff/outbox/pkg.sha256"},
    {"run_role":"macos-current-stable","workdir":"fixture","command":"probe --output results/result.json --handoff-bundle handoff/outbox/macos-current-construction.tar.zst --handoff-sha256 handoff/outbox/macos-current-construction.sha256"}
  ]}
]'
EOF
chmod +x "$tmp/bin/taplo"
# The production seal invokes the locked local schema validator.  This small
# fixture adapter verifies that exact local-registry call and rejects the
# nested schema omissions exercised below without ever resolving a remote
# schema URI.
cat >"$tmp/bin/check-jsonschema" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --schemafile && $2 == */.constitution/tech-spec/contracts/ci-role-evidence.schema.json && -f $2 && -f $3 ]] || exit 64
jq -e '
  .schemaVersion == 15
  and (.expectedIdentity | type == "object")
  and (.roleEvidence | type == "object")
  and ((.roleEvidence | keys | sort) == ["capturedIdentity","compatibilityStage","environment","evidenceClasses","gates","internalArtifacts","role","toolchain","viewport"])
  and ((.roleEvidence.environment | keys | sort) == ["architecture","cpuModel","documentedMemoryBytes","documentedStorageBytes","filesystem","imageOS","imageVersion","logicalCpuCount","observedMemoryBytes","observedStorageAvailableBytes","osRelease","runnerLabel"])
  and (.roleEvidence.environment.imageOS | type == "string" and length > 0)
  and (.roleEvidence.environment.imageVersion | type == "string" and length > 0)
  and (.roleEvidence.environment.osRelease | type == "string" and length > 0)
  and (.roleEvidence.environment.cpuModel | type == "string" and length > 0)
  and (.roleEvidence.environment.logicalCpuCount | type == "number" and . > 0)
  and (.roleEvidence.environment.documentedMemoryBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.documentedStorageBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.observedMemoryBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.observedStorageAvailableBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.filesystem | type == "string" and length > 0)
  and (.roleEvidence.viewport == {width:1920,height:1080,refreshHz:60,verified:false} or .roleEvidence.viewport == {width:1920,height:1080,refreshHz:60,verified:true})
  and (.roleEvidence.toolchain | type == "object" and length > 0 and all(.[]; type == "string" and length > 0))
' "$3" >/dev/null
EOF
chmod +x "$tmp/bin/check-jsonschema"
export PATH="$tmp/bin:$PATH"
hex=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
jq -cn --arg hex "$hex" '{schemaVersion:2,ticketIdentity:"BURL-M003",expectedIdentitySha256:$hex,repositoryId:1,workflowRunId:1,runAttempt:1,sealingCheckRunId:2,workflowPath:".github/workflows/ci-role-linux-x86-64.yml",workflowSignerSha:"0123456789012345678901234567890123456789",workflowSignerRef:"refs/heads/master",trustAnchorSha:"0123456789012345678901234567890123456789",testedSourceSha:"0123456789012345678901234567890123456789",baseSha:"0123456789012345678901234567890123456789",role:"linux-x86_64",artifactNonce:"0123456789abcdef0123456789abcdef",runnerEnvironmentClaim:"github-hosted",expectedArtifact:{artifactId:1,artifactName:"managed-evidence-expected-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},candidateArtifact:{artifactId:2,artifactName:"managed-evidence-candidate-linux-x86_64-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},sealedArtifact:{artifactId:3,artifactName:"managed-evidence-sealed-linux-x86_64-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},roleBundleSha256:$hex,sealedBundleSha256:$hex,compatibilityStage:null}' >"$tmp/valid.json"
"$root/scripts/validate-sealing-receipt.sh" "$tmp/valid.json"
for mutation in \
  '.["conclusion"]="success"' \
  '.["status"]="completed"' \
  '.["completed_at"]="2026-01-01T00:00:00Z"' \
  '.["completion"]={}' \
  '.["unexpected"]=true' \
  'del(.sealedBundleSha256)' \
  '.sealedArtifact.artifactDigest="sha256:BAD"' \
  '.sealingCheckRunId=0' \
  '.role="macos-26-arm64"' \
  '.workflowPath=".github/workflows/ci-role-macos-26-arm64.yml"' \
  '.candidateArtifact.artifactName="managed-evidence-candidate-macos-26-arm64-0123456789abcdef0123456789abcdef"' \
  '.expectedArtifact.artifactId=.candidateArtifact.artifactId'; do
  jq "$mutation" "$tmp/valid.json" >"$tmp/invalid.json"
  if "$root/scripts/validate-sealing-receipt.sh" "$tmp/invalid.json"; then echo "accepted invalid receipt mutation: $mutation" >&2; exit 1; fi
done

# The signer is the workflow execution SHA; the trust anchor remains the
# distinct immutable value from expected identity even when the signer is a
# descendant commit.
anchor=1111111111111111111111111111111111111111
signer=2222222222222222222222222222222222222222
receipt_base=0000000000000000000000000000000000000000
receipt_identity="$tmp/receipt-identity.json"
jq -cn --arg anchor "$anchor" --arg signer "$signer" --arg base "$receipt_base" --arg nonce "0123456789abcdef0123456789abcdef" '{ticketIdentity:"BURL-M003",trustAnchorSha:$anchor,workflowSignerSha:$signer,testedSourceSha:$signer,baseSha:$base,runIdentity:("managed:"+$nonce),artifactNonce:$nonce}' >"$receipt_identity"
receipt_identity_sha=$(sha256sum "$receipt_identity" | awk '{print $1}')
printf candidate >"$tmp/candidate.tar.zst"
printf sealed >"$tmp/sealed.tar.zst"
ROLE=linux-x86_64 WORKFLOW_PATH=.github/workflows/ci-role-linux-x86-64.yml ARTIFACT_NONCE=0123456789abcdef0123456789abcdef EXPECTED_IDENTITY_SHA256="$receipt_identity_sha" EXPECTED_ID=1 EXPECTED_DIGEST="$hex" CANDIDATE_ID=2 CANDIDATE_DIGEST="$hex" SEALED_ID=3 SEALED_DIGEST="$hex" TESTED_SOURCE_SHA="$signer" BASE_SHA="$receipt_base" CHECK_RUN_ID=4 EXPECTED_IDENTITY_FILE="$receipt_identity" GITHUB_SHA="$signer" GITHUB_REPOSITORY_ID=1 GITHUB_RUN_ID=2 GITHUB_RUN_ATTEMPT=1 "$root/scripts/write-sealing-receipt.sh" "$tmp/candidate.tar.zst" "$tmp/sealed.tar.zst" "$tmp/receipt-from-identity.json"
jq -e --arg anchor "$anchor" --arg signer "$signer" '.trustAnchorSha == $anchor and .workflowSignerSha == $signer and .trustAnchorSha != .workflowSignerSha' "$tmp/receipt-from-identity.json" >/dev/null

# The macOS 15 seal must pass the complete consumer object through
# COMPATIBILITY_STAGE_FILE. This executes the production writer and its v2
# validator, while a no-stage ticket above remains explicitly null.
jq '.ticketIdentity = "BURL-O001"' "$receipt_identity" >"$tmp/o001-receipt-identity.json"
o001_identity_sha=$(sha256sum "$tmp/o001-receipt-identity.json" | awk '{print $1}')
jq -cn --arg hex "$hex" '
  {producerLineage:{stageArtifact:{artifactId:11}},producerLineageSha256:$hex,
   producerLineageArtifact:{artifactId:12},
   consumerBinding:{downloadedStageArtifactId:11,stageAttestationVerificationResultSha256:("a" * 64),producerReceiptAttestationVerificationResultSha256:("b" * 64),producerLineageAttestationVerificationResultSha256:("c" * 64),trustedRootSha256:("d" * 64),verifiedAt:"2026-09-06T00:00:00Z"}}
' >"$tmp/o001-consumption.json"
cp "$tmp/o001-consumption.json" "$tmp/o001-fresh-reconstruction.json"
jq '.consumerBinding.stageAttestationVerificationResultSha256 = ("e" * 64) | .consumerBinding.producerReceiptAttestationVerificationResultSha256 = ("f" * 64) | .consumerBinding.producerLineageAttestationVerificationResultSha256 = ("0" * 64) | .consumerBinding.trustedRootSha256 = ("1" * 64) | .consumerBinding.verifiedAt = "2026-09-07T00:00:00Z"' "$tmp/o001-fresh-reconstruction.json" >"$tmp/o001-fresh.next"
mv "$tmp/o001-fresh.next" "$tmp/o001-fresh-reconstruction.json"
ROLE=macos-15-arm64 WORKFLOW_PATH=.github/workflows/ci-role-macos-15-arm64.yml ARTIFACT_NONCE=0123456789abcdef0123456789abcdef EXPECTED_IDENTITY_SHA256="$o001_identity_sha" EXPECTED_ID=1 EXPECTED_DIGEST="$hex" CANDIDATE_ID=2 CANDIDATE_DIGEST="$hex" SEALED_ID=3 SEALED_DIGEST="$hex" TESTED_SOURCE_SHA="$signer" BASE_SHA="$receipt_base" CHECK_RUN_ID=4 EXPECTED_IDENTITY_FILE="$tmp/o001-receipt-identity.json" COMPATIBILITY_STAGE_FILE="$tmp/o001-consumption.json" GITHUB_SHA="$signer" GITHUB_REPOSITORY_ID=1 GITHUB_RUN_ID=2 GITHUB_RUN_ATTEMPT=1 "$root/scripts/write-sealing-receipt.sh" "$tmp/candidate.tar.zst" "$tmp/sealed.tar.zst" "$tmp/o001-receipt.json"
jq -e --slurpfile candidate "$tmp/o001-consumption.json" '.ticketIdentity == "BURL-O001" and .role == "macos-15-arm64" and .compatibilityStage == $candidate[0]' "$tmp/o001-receipt.json" >/dev/null
jq -e --slurpfile fresh "$tmp/o001-fresh-reconstruction.json" '.compatibilityStage != $fresh[0]' "$tmp/o001-receipt.json" >/dev/null

nonce=0123456789abcdef0123456789abcdef
sha=0123456789012345678901234567890123456789
role=linux-x86_64
role_schema_version=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json")
expected="$tmp/expected-identity.json"
jq -cn --arg sha "$sha" --arg nonce "$nonce" --arg role "$role" --arg hex "$hex" '
  {ticketIdentity:"BURL-M003",releaseIdentity:"fixture",trustAnchorSha:$sha,testedSourceSha:$sha,workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",baseSha:$sha,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:["scripts/**"],buildIdentity:$hex,corpusIdentity:$hex,runIdentity:("managed:"+$nonce),artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:$sha}},requiredRoleGuards:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",runnerLabel:"ubuntu-24.04",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",runnerLabel:"macos-26",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",runnerLabel:"macos-15",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"}},requiredEvidenceClasses:{"linux-x86_64":["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"],"macos-26-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"],"macos-15-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]}}' >"$expected"
m003_raw="$tmp/m003-raw38.json"
"$real_taplo" get --file-path "$root/.constitution/tech-spec/contracts/provisional-spikes.toml" --output-format json ci_bootstrap.linux_candidate_closure_view >"$m003_raw"
source="$tmp/role-source"; mkdir -p "$source/results" "$source/logs"
printf fixture >"$source/results/result.json"
result_bytes=$(wc -c <"$source/results/result.json")
result_sha=$(sha256sum "$source/results/result.json" | awk '{print $1}')
expected_sha=$(sha256sum "$expected" | awk '{print $1}')
jq -jr '.closure_view_log_golden_fixture' "$m003_raw" >"$source/logs/burl-m003-linux-closure-view.log"
closure_log_bytes=$(wc -c <"$source/logs/burl-m003-linux-closure-view.log")
closure_log_sha=$(sha256sum "$source/logs/burl-m003-linux-closure-view.log" | awk '{print $1}')
jq -cn --slurpfile expected "$expected" --arg expected_sha "$expected_sha" --arg role "$role" --arg result_sha "$result_sha" --argjson result_bytes "$result_bytes" --arg closure_log_sha "$closure_log_sha" --argjson closure_log_bytes "$closure_log_bytes" --argjson version "$role_schema_version" '
  {schemaVersion:$version,expectedIdentity:$expected[0],expectedIdentitySha256:$expected_sha,roleEvidence:{role:$role,capturedIdentity:($expected[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:"ubuntu-24.04",imageOS:"fixture-linux",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"x86_64",cpuModel:"fixture-cpu",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:16000000000,observedStorageAvailableBytes:14000000000,filesystem:"fixturefs"},viewport:{width:1920,height:1080,refreshHz:60,verified:false},evidenceClasses:$expected[0].requiredEvidenceClasses[$role],gates:($expected[0].requiredEvidenceClasses[$role] | map({(.):true}) | add),toolchain:{flutter:"fixture",dart:"fixture"},internalArtifacts:[{name:"results/result.json",bytes:$result_bytes,sha256:$result_sha},{name:"logs/burl-m003-linux-closure-view.log",bytes:$closure_log_bytes,sha256:$closure_log_sha}],compatibilityStage:null}}' >"$source/ci-role-evidence.json"
archive() {
  local output=$1
  shift
  (cd "$source" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$output" "$@")
}
validate_role_bundle() {
  "$root/scripts/validate-managed-role-bundle.sh" --expected "$expected" --role "$role" --nonce "$nonce" --bundle "$1"
}
validate_contract_ticket_bundle() {
  local ticket=$1 ticket_expected ticket_sha ticket_root member bytes hash members_json manifest bundle
  shift
  ticket_expected="$tmp/expected-$ticket.json"
  jq --arg ticket "$ticket" '
    .ticketIdentity = $ticket |
    .requiredEvidenceClasses = {
      "BURL-H001": {"linux-x86_64":["common-functional","performance","ast-measurement"],"macos-26-arm64":["common-functional","performance","ast-measurement"],"macos-15-arm64":["common-functional"]},
      "BURL-H002": {"linux-x86_64":["common-functional","filesystem-compatibility"],"macos-26-arm64":["common-functional","filesystem-compatibility"],"macos-15-arm64":["common-functional"]},
      "BURL-I001": {"linux-x86_64":["common-functional","performance","asset-measurement"],"macos-26-arm64":["common-functional","performance","asset-measurement"],"macos-15-arm64":["common-functional"]},
      "BURL-L001": {"linux-x86_64":["common-functional","filesystem-compatibility","git-protocol"],"macos-26-arm64":["common-functional","filesystem-compatibility","git-protocol"],"macos-15-arm64":["common-functional"]},
      "BURL-O001": {"linux-x86_64":["packaging-runtime"],"macos-26-arm64":["packaging-runtime","repeatable-construction"],"macos-15-arm64":["packaging-runtime-compatibility"]}
    }[$ticket]
  ' "$expected" >"$ticket_expected"
  ticket_sha=$(sha256sum "$ticket_expected" | awk '{print $1}')
  ticket_root="$tmp/contract-ticket-$ticket"
  mkdir -p "$ticket_root"
  members_json='[]'
  for member in "$@"; do
    mkdir -p "$ticket_root/$(dirname "$member")"
    printf '%s\n' "$ticket:$member" >"$ticket_root/$member"
    bytes=$(wc -c <"$ticket_root/$member")
    hash=$(sha256sum "$ticket_root/$member" | awk '{print $1}')
    members_json=$(jq -cn --argjson old "$members_json" --arg name "$member" --arg hash "$hash" --argjson bytes "$bytes" '$old + [{name:$name,bytes:$bytes,sha256:$hash}]')
  done
  manifest="$ticket_root/ci-role-evidence.json"
  jq -cn --slurpfile identity "$ticket_expected" --arg digest "$ticket_sha" --arg role linux-x86_64 --argjson members "$members_json" --argjson version "$role_schema_version" '
    {schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,
     roleEvidence:{role:$role,capturedIdentity:($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:"ubuntu-24.04",imageOS:"fixture-linux",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"x86_64",cpuModel:"fixture-cpu",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:16000000000,observedStorageAvailableBytes:14000000000,filesystem:"fixturefs"},viewport:{width:1920,height:1080,refreshHz:60,verified:true},evidenceClasses:$identity[0].requiredEvidenceClasses[$role],gates:($identity[0].requiredEvidenceClasses[$role] | map({(.):true}) | add),toolchain:{flutter:"fixture",dart:"fixture"},internalArtifacts:$members,compatibilityStage:null}}' >"$manifest"
  bundle="$tmp/contract-ticket-$ticket.tar.zst"
  (cd "$ticket_root" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$bundle" ci-role-evidence.json "$@")
  "$root/scripts/validate-managed-role-bundle.sh" --expected "$ticket_expected" --role linux-x86_64 --nonce "$nonce" --bundle "$bundle"
}
assert_rejected() {
  local name=$1 bundle=$2
  if validate_role_bundle "$bundle" >/dev/null 2>&1; then
    echo "accepted unsafe role bundle: $name" >&2
    exit 1
  fi
}
valid_bundle="$tmp/valid-role.tar.zst"
archive "$valid_bundle" ci-role-evidence.json results/result.json logs/burl-m003-linux-closure-view.log
assert_rejected reduced-raw38-golden "$valid_bundle"

# The exact v38 golden is pinned as a byte sequence.  These mutations update
# the manifest hash too, so rejection demonstrates fresh-seal parsing rather
# than only the ordinary artifact-inventory check.
golden_log="$tmp/raw38-golden.log"
jq -jr '.closure_view_log_golden_fixture' "$m003_raw" >"$golden_log"
cmp -s "$golden_log" "$source/logs/burl-m003-linux-closure-view.log"
raw38_manifest="$tmp/raw38-original-manifest.json"
cp "$source/ci-role-evidence.json" "$raw38_manifest"
refresh_raw38_log_digests() {
  local log=$1 base_count base_sha integration_count integration_sha authority_count authority_sha
  base_count=$(awk -F$'\t' '$1 == "base-source" { count++ } END { print count + 0 }' "$log")
  base_sha=$(awk -F$'\t' '$1 == "base-source" { print }' "$log" | sha256sum | awk '{print $1}')
  integration_count=$(awk -F$'\t' '$1 == "integration-source" { count++ } END { print count + 0 }' "$log")
  integration_sha=$(awk -F$'\t' '$1 == "integration-source" { print }' "$log" | sha256sum | awk '{print $1}')
  authority_count=$(awk -F$'\t' '$1 == "capacity-authority" { count++ } END { print count + 0 }' "$log")
  authority_sha=$(awk -F$'\t' '$1 == "capacity-authority" { print }' "$log" | sha256sum | awk '{print $1}')
  awk -v bc="$base_count" -v bs="$base_sha" -v ic="$integration_count" -v is="$integration_sha" -v ac="$authority_count" -v as="$authority_sha" '
    BEGIN { FS = OFS = "\t" }
    /^base-source-identity-count=/ { print "base-source-identity-count=" bc; next }
    /^base-source-identity-sha256=/ { print "base-source-identity-sha256=" bs; next }
    /^integration-source-identity-count=/ { print "integration-source-identity-count=" ic; next }
    /^integration-source-identity-sha256=/ { print "integration-source-identity-sha256=" is; next }
    /^capacity-authority-count=/ { print "capacity-authority-count=" ac; next }
    /^capacity-authority-sha256=/ { print "capacity-authority-sha256=" as; next }
    $1 == "session" { $6 = ($4 == "base" ? bs : is); $7 = as; print; next }
    { print }
  ' "$log" >"$log.next"
  mv "$log.next" "$log"
}
assert_raw38_rejected() {
  local name=$1 expression=$2 bundle bytes hash
  sed "$expression" "$golden_log" >"$source/logs/burl-m003-linux-closure-view.log"
  refresh_raw38_log_digests "$source/logs/burl-m003-linux-closure-view.log"
  bytes=$(wc -c <"$source/logs/burl-m003-linux-closure-view.log")
  hash=$(sha256sum "$source/logs/burl-m003-linux-closure-view.log" | awk '{print $1}')
  jq --arg hash "$hash" --argjson bytes "$bytes" '.roleEvidence.internalArtifacts |= map(if .name == "logs/burl-m003-linux-closure-view.log" then .sha256 = $hash | .bytes = $bytes else . end)' "$raw38_manifest" >"$source/ci-role-evidence.json"
  bundle="$tmp/raw38-$name.tar.zst"
  archive "$bundle" ci-role-evidence.json results/result.json logs/burl-m003-linux-closure-view.log
  assert_rejected "raw38-$name" "$bundle"
  cp "$raw38_manifest" "$source/ci-role-evidence.json"
}
assert_raw38_rejected raw-version 's/^raw-contract-version=38$/raw-contract-version=37/'
assert_raw38_rejected base-payload 's#coreutils-9\.7$#coreutils-9.8#'
assert_raw38_rejected authority '0,/candidate-home/{s/candidate-home/candidate-home-mutated/}'
assert_raw38_rejected source-membership '0,/base-source\t\/nix\/store\/11111111111111111111111111111111-coreutils-9\.7/{s/coreutils-9\.7/coreutils-9.8/}'
assert_raw38_rejected capacity-floor 's/\t5000000000$/\t3999999999/'
assert_raw38_rejected argv-digest '0,/2ee7de5e88503f504271834164eaea7b3686477955c8246293aa046aa17cfd31/{s/2ee7de5e88503f504271834164eaea7b3686477955c8246293aa046aa17cfd31/0000000000000000000000000000000000000000000000000000000000000000/}'
assert_raw38_rejected session-loopback '0,/\ttrue\ttrue\tcompositor-not-applicable/{s/\ttrue\ttrue\tcompositor-not-applicable/\ttrue\tfalse\tcompositor-not-applicable/}'
assert_raw38_rejected host-policy 's/\tnot-applied\t/\tapplied\t/'
cp "$golden_log" "$source/logs/burl-m003-linux-closure-view.log"

# This is deliberately distinct from the compact /work serializer golden above.
# Build the exact raw-v38 production manifests through the locked Nix 2.35.2
# query, then place their retained authorities below deterministic host-shaped
# paths.  The fresh seal sees no test mode: it parses this ordinary role bundle
# and reconstructs every actual full argv from the raw contract and log.
locked_nix=/nix/store/irfrbndi76zhkvqsfhmsn4a99iafck29-nix-2.35.2/bin/nix
locked_nix_store=/nix/store/nskid3yq908g18x6cnvrk2hy96327f3f-nix-2.35.2/bin/nix-store
[[ $($locked_nix --version) == 'nix (Nix) 2.35.2' && $($locked_nix_store --version) == 'nix-store (Nix) 2.35.2' ]]

m003_base_manifest="$tmp/m003-production-base.manifest"
m003_integration_manifest="$tmp/m003-production-integration.manifest"
m003_build_full_manifests() {
  local tool tool_path store_entry root_entry openssl_pc openssl_include openssl_lib mesa_dri mesa_egl
  local -a closure_tools closure_roots
  closure_tools=(bash sh mkdir mktemp chmod install cp mv rm cmp awk sed grep rg sort sha256sum wc find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head env flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup cmake ninja pkg-config clang openssl jq ip)
  closure_roots=()
  for tool in "${closure_tools[@]}"; do
    # Current devenv can expose a newer Procps while raw-v38's production
    # closure deliberately pins 4.0.6. The exact queried root is the contract,
    # never a test-only count override.
    if [[ $tool == ps ]]; then
      tool_path=/nix/store/ly5j6qg2q3vn899jd9dz0hx11gvjh9f1-procps-4.0.6/bin/ps
    else
      tool_path=$(readlink -f "$(command -v "$tool")")
    fi
    [[ $tool_path == /nix/store/* && -x $tool_path ]] || return 1
    store_entry=${tool_path#/nix/store/}
    closure_roots+=("/nix/store/${store_entry%%/*}")
  done
  openssl_pc=$(jq -r '.serializer_golden_resolved_environment[] | select(startswith("PKG_CONFIG_PATH=")) | split("=")[1]' "$m003_raw")
  openssl_include=$(jq -r '.serializer_golden_resolved_environment[] | select(startswith("NIX_CFLAGS_COMPILE=")) | sub("^NIX_CFLAGS_COMPILE=-isystem "; "")' "$m003_raw")
  openssl_lib=$(jq -r '.serializer_golden_resolved_environment[] | select(startswith("NIX_LDFLAGS_x86_64_unknown_linux_gnu=")) | sub("^NIX_LDFLAGS_x86_64_unknown_linux_gnu=-L"; "")' "$m003_raw")
  mesa_dri=$(jq -r '.serializer_golden_resolved_environment[] | select(startswith("LIBGL_DRIVERS_PATH=")) | split("=")[1]' "$m003_raw")
  mesa_egl=$(jq -r '.serializer_golden_resolved_environment[] | select(startswith("__EGL_VENDOR_LIBRARY_FILENAMES=")) | split("=")[1]' "$m003_raw")
  for root_entry in "${openssl_pc%/lib/pkgconfig}" "${openssl_include%/include}" "${openssl_lib%/lib}" "${mesa_dri%/lib/dri}" "${mesa_egl%/share/glvnd/egl_vendor.d/50_mesa.json}"; do
    [[ $root_entry == /nix/store/* ]] || return 1
    closure_roots+=("$root_entry")
  done
  mapfile -t closure_roots < <(printf '%s\n' "${closure_roots[@]}" | LC_ALL=C sort -u)
  for root_entry in "${closure_roots[@]}"; do "$locked_nix_store" -qR "$root_entry"; done | LC_ALL=C sort -u >"$m003_base_manifest"
  { cat "$m003_base_manifest"; "$locked_nix_store" -qR /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12; } | LC_ALL=C sort -u >"$m003_integration_manifest"
  [[ $(wc -l <"$m003_base_manifest") == 488 && $(wc -c <"$m003_base_manifest") == 30717 && $(sha256sum "$m003_base_manifest" | awk '{print $1}') == 127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64 ]]
  [[ $(wc -l <"$m003_integration_manifest") == 547 && $(wc -c <"$m003_integration_manifest") == 34315 && $(sha256sum "$m003_integration_manifest" | awk '{print $1}') == 353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896 ]]
}

declare -A m003_resolved_environment=() m003_current=() m003_synthetic_current=() m003_authority_order=() m003_source_inode=()
m003_source_next_inode=900000
while IFS= read -r m003_environment_entry; do
  m003_resolved_environment[${m003_environment_entry%%=*}]=${m003_environment_entry#*=}
done < <(jq -r '.serializer_golden_resolved_environment[]' "$m003_raw")
mapfile -t m003_mounts < <(jq -r '.dynamic_mount_plan[]' "$m003_raw")

m003_source_rows() {
  local manifest=$1 class=$2 destination=$3 member type inode
  : >"$destination"
  while IFS= read -r member; do
    [[ $member == /nix/store/* && -e $member && ! -L $member ]] || return 1
    [[ -d $member ]] && type=directory || type=regular-file
    if [[ -z ${m003_source_inode[$member]+x} ]]; then
      ((++m003_source_next_inode))
      m003_source_inode[$member]=$m003_source_next_inode
    fi
    inode=${m003_source_inode[$member]}
    # The source path is the immutable selected member. Only departed host
    # metadata is deterministic fixture data; the seal checks its grammar and
    # exact base-to-integration identity relationship.
    printf '%s-source\t%s\t%s\t70001\t%s\t0:2049\t/\t70001\t%s\t0:2049\t%s\tro\n' \
      "$class" "$member" "$type" "$inode" "$inode" "$member" >>"$destination"
  done <"$manifest"
}

m003_fixture_authority() {
  local ordinal=$1 session_id=$2 authority=$3 kind=$4 parent leaf mode=file_type inode
  case $authority in
    closure-staging) parent=/var/lib/burlmd-fixture/runner-temp; leaf=burlmd-m003/staging/$ordinal-$session_id;;
    candidate-home) parent=/var/lib/burlmd-fixture/candidate; leaf=home;;
    candidate-tmp) parent=/var/lib/burlmd-fixture/candidate; leaf=tmp;;
    xdg-cache) parent=/var/lib/burlmd-fixture/candidate/xdg; leaf=cache;;
    xdg-config) parent=/var/lib/burlmd-fixture/candidate/xdg; leaf=config;;
    xdg-data) parent=/var/lib/burlmd-fixture/candidate/xdg; leaf=data;;
    xdg-state) parent=/var/lib/burlmd-fixture/candidate/xdg; leaf=state;;
    gh-config) parent=/var/lib/burlmd-fixture/candidate; leaf=gh;;
    candidate-tool-path) parent=/var/lib/burlmd-fixture/candidate; leaf=tool-path;;
    candidate-writable) parent=/var/lib/burlmd-fixture/candidate; leaf=writable;;
    session-root) parent=/var/lib/burlmd-fixture/candidate/sessions; leaf=$ordinal-$session_id;;
    session-contract-root) parent=/var/lib/burlmd-fixture/runner-temp; leaf=burlmd-m003/contracts/$ordinal-$session_id;;
    xdg-runtime) parent=/var/lib/burlmd-fixture/runner-temp; leaf=burlmd-m003/xdg-runtime/$ordinal-$session_id;;
    prepared-root) parent=/var/lib/burlmd-fixture/candidate; leaf=prepared;;
    trusted-control-root) parent=/opt/actions; leaf=burlmd-trusted-control;;
    tested-source-root) parent=/opt/actions; leaf=burlmd-tested-source;;
    dart-tool) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=dart-tool;;
    flutter-build) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=build;;
    l10n-generated) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=l10n-generated;;
    cargokit-root) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=rust-builder-cargokit;;
    cargokit-launcher) parent=/var/lib/burlmd-fixture/candidate/writable/rust-builder-cargokit; leaf=run_build_tool.sh;;
    linux-flutter-ephemeral) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=linux-flutter-ephemeral;;
    pub-active-roots) parent=/var/lib/burlmd-fixture/candidate/writable; leaf=pub-active-roots;;
    closure-store-base) parent=/var/lib/burlmd-fixture/runner-temp; leaf=burlmd-m003/staging/$ordinal-$session_id/nix/store;;
    *) return 1;;
  esac
  mode=0700; file_type=directory
  [[ $authority != cargokit-launcher ]] || { mode=0755; file_type=regular-file; }
  inode=$((500000 + ${#m003_current[@]} + 1))
  printf 'capacity-authority\t%s\t%s\t%s\t%s\t%s\t1000\t1000\t%s\t%s\t2049\t%s\t2049:0\t/\t%s\t%s\n' \
    "$ordinal" "$session_id" "$authority" "$kind" "$parent" "$mode" "$file_type" "$inode" "$parent" "$leaf" >>"$m003_authorities"
  m003_current["$ordinal:$authority"]=$parent/$leaf
  m003_authority_order[$ordinal]+=" $authority"
}

m003_plan_fixture_authorities() {
  local ordinal session_id session_class mount operation authority destination
  : >"$m003_authorities"
  m003_current=(); m003_authority_order=()
  for ordinal in {1..7}; do
    session_id=$(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].id' "$m003_raw")
    session_class=$(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].class' "$m003_raw")
    m003_fixture_authority "$ordinal" "$session_id" closure-staging staging-leaf
    for mount in "${m003_mounts[@]}"; do
      IFS=: read -r operation authority destination <<<"$mount"
      m003_fixture_authority "$ordinal" "$session_id" "$authority" argv-source
      if [[ $session_class == integration && $authority == session-contract-root ]]; then
        m003_fixture_authority "$ordinal" "$session_id" xdg-runtime runtime-leaf
      fi
    done
  done
}

m003_build_argv() {
  local ordinal=$1 session_id=$2 session_class=$3 manifest=$4 current_name=$5 output=$6 entry key value operation authority destination member joined
  local -n current=$current_name
  local -a argv members candidate_environment command_args
  mapfile -t members <"$manifest"
  joined=$(IFS=:; printf '%s' "${members[*]}")
  candidate_environment=()
  mapfile -t candidate_environment < <(jq -r '.fixed_candidate_environment[]' "$m003_raw")
  while IFS= read -r entry; do
    key=${entry%%=*}; value=${entry#*=}
    case $value in
      SESSION_ID) value=$session_id;;
      /candidate/session/pid) ;;
      SELECTED_MANIFEST_MEMBERS_JOINED_BY_COLON) value=$joined;;
      LOCKED_OPENSSL_PCFILEDIR) value=${m003_resolved_environment[PKG_CONFIG_PATH]};;
      LOCKED_LIBCLANG_LIB) value=${m003_resolved_environment[LIBCLANG_PATH]};;
      '-isystem LOCKED_OPENSSL_INCLUDEDIR') value=${m003_resolved_environment[NIX_CFLAGS_COMPILE]};;
      -LLOCKED_OPENSSL_LIBDIR) value=${m003_resolved_environment[NIX_LDFLAGS_x86_64_unknown_linux_gnu]};;
      LOCKED_MESA_DRI_PATH) value=${m003_resolved_environment[LIBGL_DRIVERS_PATH]};;
      LOCKED_MESA_EGL_VENDOR_PATH) value=${m003_resolved_environment[__EGL_VENDOR_LIBRARY_FILENAMES]};;
      *) return 1;;
    esac
    candidate_environment+=("$key=$value")
  done < <(jq -r '.derived_candidate_environment[]' "$m003_raw")
  [[ ${#candidate_environment[@]} == 33 ]]
  mapfile -t argv < <(jq -r '.namespace_argv[]' "$m003_raw")
  argv=(/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap "${argv[@]}")
  for entry in "${candidate_environment[@]}"; do argv+=(--setenv "${entry%%=*}" "${entry#*=}"); done
  argv+=(--lock-file "$(jq -r .teardown_lock_namespace_path "$m003_raw")")
  mapfile -t command_args < <(jq -r '.fixed_filesystem_argv[]' "$m003_raw")
  argv+=("${command_args[@]}")
  for entry in "${m003_mounts[@]}"; do
    IFS=: read -r operation authority destination <<<"$entry"
    [[ -n ${current["$ordinal:$authority"]+x} ]] || return 1
    argv+=(--"$operation" "${current["$ordinal:$authority"]}" "$destination")
    if [[ $session_class == integration && $authority == session-contract-root ]]; then
      argv+=(--bind "${current["$ordinal:xdg-runtime"]}" /candidate/xdg/runtime)
    fi
  done
  for member in "${members[@]}"; do argv+=(--ro-bind "$member" "$member"); done
  argv+=(--symlink /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env /usr/bin/env)
  [[ $session_class != integration ]] || argv+=(--symlink /nix/store/zh1ijdhb6gng1509b1zrilb6xlzx60j6-bash-5.3p9/bin/bash /bin/sh)
  argv+=(--chdir /source --)
  mapfile -t command_args < <(jq -r '.supervisor_argv_prefix[]' "$m003_raw")
  for entry in "${command_args[@]}"; do argv+=("${entry//SESSION_ID/$session_id}"); done
  for key in "${!argv[@]}"; do argv[$key]=${argv[$key]//SESSION_CLASS/$session_class}; done
  mapfile -t command_args < <(jq -r --arg id "$session_id" '.sessions[] | select(.id == $id) | .command[]' "$m003_raw")
  argv+=("${command_args[@]}")
  printf '%s\0' "${argv[@]}" >"$output"
}

m003_assert_full_vector_records() {
  local ordinal session_id session_class member_count argument_count bytes digest vector map_entry authority source
  for ordinal in {1..7}; do
    session_id=$(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].id' "$m003_raw")
    for map_entry in $(jq -r '.synthetic_source_map[]' "$m003_raw"); do
      authority=${map_entry%%=*}; source=${map_entry#*=}
      source=${source//ORDINAL/$ordinal}; source=${source//SESSION_ID/$session_id}
      m003_synthetic_current["$ordinal:$authority"]=$source
    done
    m003_synthetic_current["$ordinal:closure-staging"]=/work/staging/$ordinal-$session_id
    m003_synthetic_current["$ordinal:session-contract-root"]=/work/contracts/$ordinal-$session_id
  done
  while IFS='|' read -r ordinal session_id session_class member_count argument_count bytes digest; do
    vector="$tmp/m003-synthetic-vector-$ordinal.bin"
    [[ $session_class == base ]] && manifest=$m003_base_manifest || manifest=$m003_integration_manifest
    m003_build_argv "$ordinal" "$session_id" "$session_class" "$manifest" m003_synthetic_current "$vector"
    [[ $(tr -cd '\0' <"$vector" | wc -c) == "$argument_count" && $(wc -c <"$vector") == "$bytes" && $(sha256sum "$vector" | awk '{print $1}') == "$digest" && $(wc -l <"$manifest") == "$member_count" ]] || return 1
  done < <(jq -r '.full_vector_fixture_records[]' "$m003_raw")
}

m003_write_production_log() {
  local log=$1 ordinal session_id session_class manifest source_rows source_sha source_count manifest_sha argv_file preflight_file stage_sha authority source
  m003_base_sources="$tmp/m003-production-base-sources.tsv"
  m003_integration_sources="$tmp/m003-production-integration-sources.tsv"
  m003_source_inode=(); m003_source_next_inode=900000
  m003_source_rows "$m003_base_manifest" base "$m003_base_sources"
  m003_source_rows "$m003_integration_manifest" integration "$m003_integration_sources"
  m003_plan_fixture_authorities
  m003_authority_sha=$(sha256sum "$m003_authorities" | awk '{print $1}')
  {
    printf '%s\n' \
      'format=burlmd-linux-closure-view-v2' 'raw-contract-version=38' \
      'bubblewrap-path=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap' \
      'bubblewrap-version=bubblewrap 0.11.2' \
      'bubblewrap-sha256=c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726' \
      'bubblewrap-tool-closure-manifest-sha256=398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd' \
      "teardown-lock-verifier-path=$(jq -r .teardown_lock_verifier_executable "$m003_raw")" \
      'teardown-lock-verifier-version=flock from util-linux 2.42' \
      "teardown-lock-verifier-sha256=$(jq -r .teardown_lock_verifier_sha256 "$m003_raw")" \
      "base-manifest-bytes=$(jq -r .base_closure_manifest_bytes "$m003_raw")" "base-manifest-sha256=$(jq -r .base_closure_manifest_sha256 "$m003_raw")" "base-member-count=$(jq -r .base_closure_member_count "$m003_raw")" "base-nar-bytes=$(jq -r .base_closure_nar_bytes "$m003_raw")" "base-bind-bytes=$(jq -r .base_closure_bind_argument_bytes "$m003_raw")" \
      "integration-manifest-bytes=$(jq -r .integration_closure_manifest_bytes "$m003_raw")" "integration-manifest-sha256=$(jq -r .integration_closure_manifest_sha256 "$m003_raw")" "integration-member-count=$(jq -r .integration_closure_member_count "$m003_raw")" "integration-nar-bytes=$(jq -r .integration_closure_nar_bytes "$m003_raw")" "integration-bind-bytes=$(jq -r .integration_closure_bind_argument_bytes "$m003_raw")" \
      'sway-path=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway' 'sway-version=sway version 1.12' 'sway-sha256=1f10250bedd99cda8a7ef04a585f66a1dd300bd37557dbd9983535b0a8b5667d' \
      'swaymsg-path=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg' 'swaymsg-version=swaymsg version 1.12' 'swaymsg-sha256=cfefe762ed1ed9463eeddad3b1e624f98fe15996bde77953f303a2a110d1270c' \
      'compositor-closure-sha256=d97a41799b1aecc670e31bfd58b339d748498be2bce09d877a0f1a9ed1c6e673' 'wayland-socket-basename=wayland-1' 'config-sha256=dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a' \
      "base-source-identity-count=$(wc -l <"$m003_base_sources")" "base-source-identity-sha256=$(sha256sum "$m003_base_sources" | awk '{print $1}')" "integration-source-identity-count=$(wc -l <"$m003_integration_sources")" "integration-source-identity-sha256=$(sha256sum "$m003_integration_sources" | awk '{print $1}')" \
      "capacity-root-count=1" "capacity-authority-count=$(wc -l <"$m003_authorities")" "capacity-authority-sha256=$m003_authority_sha" 'capacity-filesystem-count=1' 'base-session-count=5' 'integration-session-count=2' 'session-count=7'
    cat "$m003_base_sources" "$m003_integration_sources" "$m003_authorities"
  } >"$log"
  for ordinal in {1..7}; do
    session_id=$(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].id' "$m003_raw")
    session_class=$(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].class' "$m003_raw")
    if [[ $session_class == base ]]; then manifest=$m003_base_manifest; source_rows=$m003_base_sources; else manifest=$m003_integration_manifest; source_rows=$m003_integration_sources; fi
    manifest_sha=$(sha256sum "$manifest" | awk '{print $1}')
    source_sha=$(sha256sum "$source_rows" | awk '{print $1}')
    source_count=$(wc -l <"$source_rows")
    argv_file="$tmp/m003-production-vector-$ordinal.bin"
    m003_build_argv "$ordinal" "$session_id" "$session_class" "$manifest" m003_current "$argv_file"
    preflight_file="$tmp/m003-production-preflight-$ordinal"
    {
      printf '%s\n' 'format=burlmd-linux-closure-preflight-v2' "session-class=$session_class" "selected-manifest-sha256=$manifest_sha" "source-identity-count=$source_count"
      awk -F$'\t' '{sub(/^[^\t]*\t/, ""); print}' "$source_rows"
      [[ $session_class == base ]] && source=absent || source=pending-supervisor-start
      printf '%s\n' 'pid-namespace-private=true' 'network-namespace-private=true' 'descriptor=0:candidate-stdin' 'descriptor=1:candidate-stdout' 'descriptor=2:candidate-stderr' 'descriptor=3:preflight-record-write' 'descriptor=4:preflight-ack-read' 'store-view-exact=true' 'forbidden-paths-absent=true' "compositor-state=$source"
    } >"$preflight_file"
    stage_sha=$(printf '%s\n' "${m003_current["$ordinal:closure-staging"]}" | sha256sum | awk '{print $1}')
    if [[ $session_class == base ]]; then source=compositor-not-applicable; sway_reaped=not-applicable; else source=success; sway_reaped=true; fi
    printf 'session\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t0\t0\t2097152\t%s\t%s\ttrue\ttrue\t%s\t%s\ttrue\t2049\t%s\ttrue\ttrue\n' \
      "$ordinal" "$session_id" "$session_class" "$manifest_sha" "$source_sha" "$m003_authority_sha" "$stage_sha" "$(wc -c <"$argv_file")" "$(sha256sum "$argv_file" | awk '{print $1}')" "$(wc -l <"$manifest")" "$(wc -c <"$preflight_file")" "$(sha256sum "$preflight_file" | awk '{print $1}')" "$source" "$sway_reaped" "$((9000 + ordinal))" >>"$log"
    for authority in ${m003_authority_order[$ordinal]}; do
      printf 'session-capacity-root\t%s\t%s\t%s\t%s\t2049\n' "$ordinal" "$session_id" "$authority" "${m003_current["$ordinal:$authority"]}" >>"$log"
    done
    printf 'session-capacity-filesystem\t%s\t%s\t2049\t5000000000\n' "$ordinal" "$session_id" >>"$log"
  done
  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' host-policy ubuntu-24.04-fixture 6.8.0-fixture not-present success not-applied not-applicable not-applicable not-applicable
    printf '%s\n' 'base-manifest-payload:'
    cat "$m003_base_manifest"
    printf '%s\n' 'integration-manifest-payload:'
    cat "$m003_integration_manifest"
  } >>"$log"
}

m003_build_full_manifests
m003_assert_full_vector_records
m003_production_source="$tmp/m003-production-source"
mkdir -p "$m003_production_source/results" "$m003_production_source/logs"
printf fixture >"$m003_production_source/results/result.json"
m003_production_log="$m003_production_source/logs/burl-m003-linux-closure-view.log"
m003_authorities="$tmp/m003-production-authorities.tsv"
m003_write_production_log "$m003_production_log"
m003_production_golden_log="$tmp/m003-production-golden.log"
cp "$m003_production_log" "$m003_production_golden_log"
m003_production_result_sha=$(sha256sum "$m003_production_source/results/result.json" | awk '{print $1}')
m003_production_result_bytes=$(wc -c <"$m003_production_source/results/result.json")
m003_production_log_sha=$(sha256sum "$m003_production_log" | awk '{print $1}')
m003_production_log_bytes=$(wc -c <"$m003_production_log")
jq -cn --slurpfile identity "$expected" --arg digest "$expected_sha" --arg role "$role" --arg result_sha "$m003_production_result_sha" --argjson result_bytes "$m003_production_result_bytes" --arg log_sha "$m003_production_log_sha" --argjson log_bytes "$m003_production_log_bytes" --argjson version "$role_schema_version" '
  {schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,
   roleEvidence:{role:$role,capturedIdentity:($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:"ubuntu-24.04",imageOS:"fixture-linux",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"x86_64",cpuModel:"fixture-cpu",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:16000000000,observedStorageAvailableBytes:14000000000,filesystem:"fixturefs"},viewport:{width:1920,height:1080,refreshHz:60,verified:false},evidenceClasses:$identity[0].requiredEvidenceClasses[$role],gates:($identity[0].requiredEvidenceClasses[$role] | map({(.):true}) | add),toolchain:{flutter:"fixture",dart:"fixture"},internalArtifacts:[{name:"results/result.json",bytes:$result_bytes,sha256:$result_sha},{name:"logs/burl-m003-linux-closure-view.log",bytes:$log_bytes,sha256:$log_sha}],compatibilityStage:null}}' >"$m003_production_source/ci-role-evidence.json"
m003_production_bundle="$tmp/m003-production-role.tar.zst"
(cd "$m003_production_source" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$m003_production_bundle" ci-role-evidence.json results/result.json logs/burl-m003-linux-closure-view.log)
# This acceptance is intentionally after the separate reduced-golden rejection:
# it is the first proof that fresh sealing accepts a complete production shape.
validate_role_bundle "$m003_production_bundle"

m003_refresh_manifest() {
  local log=$1 bytes hash
  bytes=$(wc -c <"$log"); hash=$(sha256sum "$log" | awk '{print $1}')
  jq --arg hash "$hash" --argjson bytes "$bytes" '.roleEvidence.internalArtifacts |= map(if .name == "logs/burl-m003-linux-closure-view.log" then .sha256 = $hash | .bytes = $bytes else . end)' "$m003_production_source/ci-role-evidence.json" >"$tmp/m003-production-manifest.next"
  mv "$tmp/m003-production-manifest.next" "$m003_production_source/ci-role-evidence.json"
}
m003_assert_rejected() {
  local name=$1 expression=$2 log bundle mutated
  log=$m003_production_source/logs/burl-m003-linux-closure-view.log
  mutated="$tmp/m003-production-$name.log"
  sed "$expression" "$m003_production_golden_log" >"$mutated"
  cp "$mutated" "$log"
  refresh_raw38_log_digests "$log"
  m003_refresh_manifest "$log"
  bundle="$tmp/m003-production-$name.tar.zst"
  (cd "$m003_production_source" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$bundle" ci-role-evidence.json results/result.json logs/burl-m003-linux-closure-view.log)
  if "$root/scripts/validate-managed-role-bundle.sh" --expected "$expected" --role "$role" --nonce "$nonce" --bundle "$bundle" >/dev/null 2>&1; then
    echo "accepted production-shaped closure mutation: $name" >&2
    exit 1
  fi
  cp "$m003_production_golden_log" "$log"
  m003_refresh_manifest "$log"
}
m003_assert_rejected source-class '0,/^base-source\t/{s/^base-source\t/integration-source\t/}'
m003_assert_rejected argv-digest '0,/^session\t1\t/{s/\t[0-9a-f]\{64\}\t488\t0\t0/\t0000000000000000000000000000000000000000000000000000000000000000\t488\t0\t0/}'
m003_assert_rejected capacity-floor 's/\t5000000000$/\t3999999999/'
m003_assert_rejected capacity-device '0,/^session-capacity-root\t1\tgenerated-bindings\tcandidate-home\t/{s/\t2049$/\t2050/}'
m003_assert_rejected authority-parent '0,/candidate-home\targv-source\t\/var\/lib\/burlmd-fixture\/candidate\t/{s#candidate-home\targv-source\t/var/lib/burlmd-fixture/candidate\t#candidate-home\targv-source\t/var/lib/burlmd-fixture/forged-parent\t#}'
m003_assert_rejected authority-kind '0,/candidate-home\targv-source/{s/candidate-home\targv-source/candidate-home\tstaging-leaf/}'
m003_assert_rejected base-runtime-extra '0,/^session-capacity-filesystem\t1\t/{s#^session-capacity-filesystem\t1\tgenerated-bindings#session-capacity-root\t1\tgenerated-bindings\txdg-runtime\t/var/lib/burlmd-fixture/runner-temp/burlmd-m003/xdg-runtime/1-generated-bindings\t2049\nsession-capacity-filesystem\t1\tgenerated-bindings#}'
m003_assert_rejected preflight-digest '0,/\ttrue\ttrue\tcompositor-not-applicable/{s/[0-9a-f]\{64\}\ttrue\ttrue\tcompositor-not-applicable/0000000000000000000000000000000000000000000000000000000000000000\ttrue\ttrue\tcompositor-not-applicable/}'
m003_assert_rejected loopback '0,/\ttrue\ttrue\tcompositor-not-applicable/{s/\ttrue\ttrue\tcompositor-not-applicable/\ttrue\tfalse\tcompositor-not-applicable/}'
m003_assert_rejected supervisor-result '0,/\tcompositor-not-applicable\t/{s/\tcompositor-not-applicable\t/\tcandidate-failed\t/}'
m003_assert_rejected sway-reaped '0,/\tsuccess\ttrue\ttrue\t2049/{s/\tsuccess\ttrue\ttrue\t2049/\tsuccess\tfalse\ttrue\t2049/}'
m003_assert_rejected cleanup-complete '0,/\tcompositor-not-applicable\tnot-applicable\ttrue\t2049/{s/\tcompositor-not-applicable\tnot-applicable\ttrue\t2049/\tcompositor-not-applicable\tnot-applicable\tfalse\t2049/}'
m003_assert_rejected teardown-acquisition '0,/\ttrue\ttrue$/{s/\ttrue\ttrue$/\ttrue\tfalse/}'
m003_assert_rejected host-policy 's/\tnot-applied\t/\tapplied\t/'

# Every managed ticket gets a bundle whose exact members occupy its trusted
# output roots. The seal validator must accept only the contract-declared
# names, while the manifest continues to bind the complete byte inventory.
validate_contract_ticket_bundle BURL-H001 runs/ast.json handoff/outbox/ast.tar.zst handoff/outbox/ast.sha256
validate_contract_ticket_bundle BURL-H002 runs/path.json handoff/outbox/path.tar.zst handoff/outbox/path.sha256
validate_contract_ticket_bundle BURL-I001 runs/asset.json handoff/outbox/asset.tar.zst handoff/outbox/asset.sha256
validate_contract_ticket_bundle BURL-L001 runs/git.json handoff/outbox/git.tar.zst handoff/outbox/git.sha256
validate_contract_ticket_bundle BURL-O001 runs/pkg.json logs/pkg.stdout logs/pkg.stderr artifacts/pkg.tar.zst handoff/outbox/pkg.tar.zst handoff/outbox/pkg.sha256

# BURL-O001 exports two opaque producer bytes for the authenticated macOS 15
# staging job. They remain normal manifest-owned internal artifacts, so the
# same exact-inventory checks cover their path, type, size, and hash.
mkdir -p "$source/handoff/outbox"
printf bundle >"$source/handoff/outbox/macos-current-construction.tar.zst"
printf hash >"$source/handoff/outbox/macos-current-construction.sha256"
handoff_bundle_bytes=$(wc -c <"$source/handoff/outbox/macos-current-construction.tar.zst")
handoff_bundle_sha=$(sha256sum "$source/handoff/outbox/macos-current-construction.tar.zst" | awk '{print $1}')
handoff_hash_bytes=$(wc -c <"$source/handoff/outbox/macos-current-construction.sha256")
handoff_hash_sha=$(sha256sum "$source/handoff/outbox/macos-current-construction.sha256" | awk '{print $1}')
jq --arg h1 "$handoff_bundle_sha" --arg h2 "$handoff_hash_sha" --argjson b1 "$handoff_bundle_bytes" --argjson b2 "$handoff_hash_bytes" '.roleEvidence.internalArtifacts += [{name:"handoff/outbox/macos-current-construction.tar.zst",bytes:$b1,sha256:$h1},{name:"handoff/outbox/macos-current-construction.sha256",bytes:$b2,sha256:$h2}]' "$source/ci-role-evidence.json" >"$tmp/handoff-manifest.json"
mv "$tmp/handoff-manifest.json" "$source/ci-role-evidence.json"
handoff_valid_bundle="$tmp/handoff-valid-role.tar.zst"
archive "$handoff_valid_bundle" ci-role-evidence.json results/result.json handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256

# The authenticated staging job must preserve the manifest-owned handoff paths
# exactly. This catches a flattened transfer that would otherwise pass sealing
# but leave the macOS 15 role unable to consume the verified producer bytes.
pkg_expected="$tmp/pkg-expected-identity.json"
jq '.ticketIdentity = "BURL-O001" | .requiredEvidenceClasses = {"linux-x86_64":["packaging-runtime"],"macos-26-arm64":["packaging-runtime","repeatable-construction"],"macos-15-arm64":["packaging-runtime-compatibility"]}' "$expected" >"$pkg_expected"
pkg_expected_sha=$(sha256sum "$pkg_expected" | awk '{print $1}')
stage_source="$tmp/stage-source"
cp -a "$source" "$stage_source"
jq --slurpfile identity "$pkg_expected" --arg digest "$pkg_expected_sha" '
  .expectedIdentity = $identity[0] |
  .expectedIdentitySha256 = $digest |
  .roleEvidence.internalArtifacts |= map(select(.name != "logs/burl-m003-linux-closure-view.log")) |
  .roleEvidence.role = "macos-26-arm64" |
  .roleEvidence.capturedIdentity = ($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:"macos-26-arm64"}) |
  .roleEvidence.environment = {runnerLabel:"macos-26",imageOS:"fixture-macos",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"aarch64",cpuModel:"fixture-cpu",logicalCpuCount:3,documentedMemoryBytes:7000000000,documentedStorageBytes:14000000000,observedMemoryBytes:7000000000,observedStorageAvailableBytes:14000000000,filesystem:"fixturefs"} |
  .roleEvidence.evidenceClasses = $identity[0].requiredEvidenceClasses["macos-26-arm64"] |
  .roleEvidence.gates = ($identity[0].requiredEvidenceClasses["macos-26-arm64"] | map({(.):true}) | add)
' "$stage_source/ci-role-evidence.json" >"$stage_source/ci-role-evidence.json.next"
mv "$stage_source/ci-role-evidence.json.next" "$stage_source/ci-role-evidence.json"
# Every hosted-macOS non-CI role carries this bounded-cleanup observation as a
# first-class manifest member. Exercise the seal-side allowance with exact
# bytes and hash, rather than merely checking that the producer archive has it.
jq -cn '{mode:"bounded-marker-process-group-cleanup",containmentClaim:false,zeroSurvivorClaim:false,sessionCount:1,sessions:[],handoffAuthority:"trusted-wrapper-untrusted-candidate-artifact"}' >"$stage_source/results/macos-bounded-cleanup.json"
cleanup_bytes=$(wc -c <"$stage_source/results/macos-bounded-cleanup.json")
cleanup_sha=$(sha256sum "$stage_source/results/macos-bounded-cleanup.json" | awk '{print $1}')
jq --arg hash "$cleanup_sha" --argjson bytes "$cleanup_bytes" '.roleEvidence.internalArtifacts += [{name:"results/macos-bounded-cleanup.json",bytes:$bytes,sha256:$hash}]' "$stage_source/ci-role-evidence.json" >"$stage_source/ci-role-evidence.json.next"
mv "$stage_source/ci-role-evidence.json.next" "$stage_source/ci-role-evidence.json"
stage_inner="$tmp/stage-inner.tar.zst"
(cd "$stage_source" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$stage_inner" ci-role-evidence.json results/result.json results/macos-bounded-cleanup.json handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256)
"$root/scripts/validate-managed-role-bundle.sh" --expected "$pkg_expected" --role macos-26-arm64 --nonce "$nonce" --bundle "$stage_inner"
stage_without_cleanup="$tmp/stage-without-cleanup.tar.zst"
(cd "$stage_source" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$stage_without_cleanup" ci-role-evidence.json results/result.json handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256)
if "$root/scripts/validate-managed-role-bundle.sh" --expected "$pkg_expected" --role macos-26-arm64 --nonce "$nonce" --bundle "$stage_without_cleanup"; then
  echo 'seal accepted a hosted-macOS bundle without bounded cleanup evidence' >&2
  exit 1
fi
mkdir "$tmp/stage-outer"
cp "$stage_inner" "$tmp/stage-outer/ci-role-evidence.tar.zst"
stage_outer="$tmp/stage-outer.tar.zst"
(cd "$tmp/stage-outer" && tar --zstd --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$stage_outer" ci-role-evidence.tar.zst)
stage_role_hash=$(sha256sum "$stage_inner" | awk '{print $1}')
stage_sealed_hash=$(sha256sum "$stage_outer" | awk '{print $1}')
stage_receipt="$tmp/stage-receipt.json"
jq -cn --arg digest "$pkg_expected_sha" --arg sha "$sha" --arg nonce "$nonce" --arg hex "$hex" --arg role_hash "$stage_role_hash" --arg sealed_hash "$stage_sealed_hash" '
  {schemaVersion:2,ticketIdentity:"BURL-O001",expectedIdentitySha256:$digest,repositoryId:1,workflowRunId:2,runAttempt:1,sealingCheckRunId:3,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",trustAnchorSha:$sha,testedSourceSha:$sha,baseSha:$sha,role:"macos-26-arm64",artifactNonce:$nonce,runnerEnvironmentClaim:"github-hosted",expectedArtifact:{artifactId:1,artifactName:("managed-evidence-expected-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},candidateArtifact:{artifactId:2,artifactName:("managed-evidence-candidate-macos-26-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},sealedArtifact:{artifactId:3,artifactName:("managed-evidence-sealed-macos-26-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},roleBundleSha256:$role_hash,sealedBundleSha256:$sealed_hash,compatibilityStage:{producerStage:{}}}
' >"$stage_receipt"
"$root/scripts/stage-authenticated-role-bundle.sh" --expected "$pkg_expected" --receipt "$stage_receipt" --nonce "$nonce" --bundle "$stage_outer" --output "$tmp/authenticated-stage"
cmp -s "$stage_source/handoff/outbox/macos-current-construction.tar.zst" "$tmp/authenticated-stage/roles/macos-26-arm64/handoff/outbox/macos-current-construction.tar.zst"
cmp -s "$stage_source/handoff/outbox/macos-current-construction.sha256" "$tmp/authenticated-stage/roles/macos-26-arm64/handoff/outbox/macos-current-construction.sha256"
jq -e --arg nonce "$nonce" '.interface == "authenticated-producer-stage-v1" and .producerRole == "macos-26-arm64" and .artifactNonce == $nonce' "$tmp/authenticated-stage/stage-provenance.json" >/dev/null

# The PKG handoff is a separate trust boundary: exercise the same REST/job
# checks used by the caller before macOS 15 can receive the staged directory.
mkdir -p "$tmp/fake-bin"
cat >"$tmp/fake-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=${!#}
case $url in
  */jobs) printf '%s\n' "$FAKE_JOBS" ;;
  */artifacts/1) printf '%s\n' "$FAKE_EXPECTED_ARTIFACT" ;;
  */artifacts/2) printf '%s\n' "$FAKE_CANDIDATE_ARTIFACT" ;;
  */artifacts/3) printf '%s\n' "$FAKE_SEALED_ARTIFACT" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/fake-bin/gh"
fake_jobs=$(jq -cn '{jobs:[{check_run_url:"https://api.github.test/check-runs/4",run_id:2,status:"completed",conclusion:"success",name:"managed role / candidate",labels:["macos-26"]},{check_run_url:"https://api.github.test/check-runs/3",run_id:2,status:"completed",conclusion:"success",name:"managed role / seal",labels:["macos-26"]}]}')
fake_expected=$(jq -cn --arg hex "$hex" '{name:"managed-evidence-expected-0123456789abcdef0123456789abcdef",digest:("sha256:"+$hex),expired:false,workflow_run:{id:2}}')
fake_candidate=$(jq -cn --arg hex "$hex" '{name:"managed-evidence-candidate-macos-26-arm64-0123456789abcdef0123456789abcdef",digest:("sha256:"+$hex),expired:false,workflow_run:{id:2}}')
fake_sealed=$(jq -cn --arg hex "$hex" '{name:"managed-evidence-sealed-macos-26-arm64-0123456789abcdef0123456789abcdef",digest:("sha256:"+$hex),expired:false,workflow_run:{id:2}}')
GITHUB_REPOSITORY=SkrOYC/burlmd GITHUB_RUN_ID=2 GITHUB_RUN_ATTEMPT=1 GITHUB_SHA="$sha" GH_BIN="$tmp/fake-bin/gh" FAKE_JOBS="$fake_jobs" FAKE_EXPECTED_ARTIFACT="$fake_expected" FAKE_CANDIDATE_ARTIFACT="$fake_candidate" FAKE_SEALED_ARTIFACT="$fake_sealed" "$root/scripts/validate-authenticated-stage-producer.sh" --expected "$pkg_expected" --receipt "$stage_receipt" --role macos-26-arm64 --nonce "$nonce" --candidate-check-run-id 4 --seal-check-run-id 3 --expected-id 1 --expected-digest "$hex"
bad_stage_jobs=$(jq '(.jobs[1].labels) = ["self-hosted", "macos-26"]' <<<"$fake_jobs")
if GITHUB_REPOSITORY=SkrOYC/burlmd GITHUB_RUN_ID=2 GITHUB_RUN_ATTEMPT=1 GITHUB_SHA="$sha" GH_BIN="$tmp/fake-bin/gh" FAKE_JOBS="$bad_stage_jobs" FAKE_EXPECTED_ARTIFACT="$fake_expected" FAKE_CANDIDATE_ARTIFACT="$fake_candidate" FAKE_SEALED_ARTIFACT="$fake_sealed" "$root/scripts/validate-authenticated-stage-producer.sh" --expected "$pkg_expected" --receipt "$stage_receipt" --role macos-26-arm64 --nonce "$nonce" --candidate-check-run-id 4 --seal-check-run-id 3 --expected-id 1 --expected-digest "$hex"; then
  echo 'accepted a self-hosted staging producer' >&2
  exit 1
fi
cp "$source/ci-role-evidence.json" "$tmp/original-role-manifest.json"

# Schema validation is a seal-side boundary, not just a producer nicety.  The
# malformed nested variants still carry correct hashes and archive inventory,
# so acceptance here would prove that validation happened too late (or not at
# all) before attestation.
jq 'del(.roleEvidence.environment.observedMemoryBytes)' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
missing_environment_bundle="$tmp/missing-environment-role.tar.zst"
archive "$missing_environment_bundle" ci-role-evidence.json results/result.json
assert_rejected missing-environment "$missing_environment_bundle"
jq '.roleEvidence.viewport.verified = "true"' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
malformed_viewport_bundle="$tmp/malformed-viewport-role.tar.zst"
archive "$malformed_viewport_bundle" ci-role-evidence.json results/result.json
assert_rejected malformed-viewport "$malformed_viewport_bundle"
jq '.roleEvidence.toolchain = {}' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
missing_toolchain_bundle="$tmp/missing-toolchain-role.tar.zst"
archive "$missing_toolchain_bundle" ci-role-evidence.json results/result.json
assert_rejected missing-toolchain "$missing_toolchain_bundle"

jq '.roleEvidence.internalArtifacts[0].sha256 = ("0" * 64)' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
wrong_hash_bundle="$tmp/wrong-hash-role.tar.zst"
archive "$wrong_hash_bundle" ci-role-evidence.json results/result.json
assert_rejected wrong-artifact-hash "$wrong_hash_bundle"
jq '.roleEvidence.internalArtifacts += [.roleEvidence.internalArtifacts[0]]' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
duplicate_declaration_bundle="$tmp/duplicate-declaration-role.tar.zst"
archive "$duplicate_declaration_bundle" ci-role-evidence.json results/result.json
assert_rejected duplicate-artifact-declaration "$duplicate_declaration_bundle"
cp "$tmp/original-role-manifest.json" "$source/ci-role-evidence.json"

duplicate_bundle="$tmp/duplicate-role.tar.zst"
archive "$duplicate_bundle" ci-role-evidence.json results/result.json results/result.json
assert_rejected duplicate-member "$duplicate_bundle"
ln -s result.json "$source/results/link.json"
link_bundle="$tmp/link-role.tar.zst"
archive "$link_bundle" ci-role-evidence.json results/result.json results/link.json
assert_rejected symbolic-link "$link_bundle"
rm "$source/results/link.json"
ln "$source/results/result.json" "$source/results/hardlink.json"
hardlink_bundle="$tmp/hardlink-role.tar.zst"
archive "$hardlink_bundle" ci-role-evidence.json results/result.json results/hardlink.json
assert_rejected hard-link "$hardlink_bundle"
rm "$source/results/hardlink.json"
mkfifo "$source/results/pipe.json"
special_bundle="$tmp/special-role.tar.zst"
archive "$special_bundle" ci-role-evidence.json results/result.json results/pipe.json
assert_rejected special-file "$special_bundle"
rm "$source/results/pipe.json"
printf extra >"$source/extra.json"
extra_bundle="$tmp/extra-role.tar.zst"
archive "$extra_bundle" ci-role-evidence.json results/result.json extra.json
assert_rejected unexpected-top-level "$extra_bundle"
rm "$source/extra.json"
mkdir "$source/results/unused"
extra_directory_bundle="$tmp/extra-directory-role.tar.zst"
archive "$extra_directory_bundle" ci-role-evidence.json results/result.json results/unused
assert_rejected undeclared-directory "$extra_directory_bundle"
rmdir "$source/results/unused"
traversal_bundle="$tmp/traversal-role.tar.zst"
(cd "$source" && tar --zstd --transform='s|results/result.json|results/../escape.json|' -cf "$traversal_bundle" ci-role-evidence.json results/result.json)
assert_rejected traversal-member "$traversal_bundle"
absolute_bundle="$tmp/absolute-role.tar.zst"
(cd "$source" && tar --zstd --transform='s|results/result.json|/escape.json|' -cf "$absolute_bundle" ci-role-evidence.json results/result.json)
assert_rejected absolute-member "$absolute_bundle"
truncate -s $((32 * 1024 * 1024 + 1)) "$source/results/oversized.json"
oversized_bundle="$tmp/oversized-role.tar.zst"
archive "$oversized_bundle" ci-role-evidence.json results/oversized.json
assert_rejected oversized-member "$oversized_bundle"

# Two individually valid, all-zero members compress to a tiny bundle. The
# trusted validator must add tar header sizes before extraction and reject the
# aggregate 48 MiB limit rather than relying on compressed bytes or only the
# later manifest-artifact accounting.
truncate -s $((24 * 1024 * 1024)) "$source/results/header-total-a.json"
truncate -s $((24 * 1024 * 1024)) "$source/results/header-total-b.json"
header_a_sha=$(sha256sum "$source/results/header-total-a.json" | awk '{print $1}')
header_b_sha=$(sha256sum "$source/results/header-total-b.json" | awk '{print $1}')
jq --arg a "$header_a_sha" --arg b "$header_b_sha" --argjson bytes $((24 * 1024 * 1024)) '
  .roleEvidence.internalArtifacts = [
    {name:"results/header-total-a.json",bytes:$bytes,sha256:$a},
    {name:"results/header-total-b.json",bytes:$bytes,sha256:$b}
  ]
' "$tmp/original-role-manifest.json" >"$source/ci-role-evidence.json"
header_total_bundle="$tmp/header-total-role.tar.zst"
archive "$header_total_bundle" ci-role-evidence.json results/header-total-a.json results/header-total-b.json
assert_rejected header-total-before-extraction "$header_total_bundle"
cp "$tmp/original-role-manifest.json" "$source/ci-role-evidence.json"
