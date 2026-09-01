#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-seal-fixture.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
# The production validator deliberately requires the locked TOML parser for
# Spike paths. This fixture supplies only the tiny trusted contract view it
# needs, so it remains runnable before the local devenv closure is entered.
cat >"$tmp/bin/taplo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${!#} == 'spikes[*]' ]] || exit 64
printf '%s\n' '[
  {"id":"SPK-AST-H001","path":"fixture/AST-H001","verification_steps":[
    {"run_role":"linux-reference","workdir":".","command":"probe --output fixture/AST-H001/runs/ast.json --handoff-bundle fixture/AST-H001/handoff/outbox/ast.tar.zst --handoff-sha256 fixture/AST-H001/handoff/outbox/ast.sha256"}
  ]},
  {"id":"SPK-PATH-H002","path":"fixture/PATH-H002","verification_steps":[
    {"run_role":"linux-default-filesystem","workdir":".","command":"probe --output fixture/PATH-H002/runs/path.json --handoff-bundle fixture/PATH-H002/handoff/outbox/path.tar.zst --handoff-sha256 fixture/PATH-H002/handoff/outbox/path.sha256"}
  ]},
  {"id":"SPK-ASSET-I001","path":"fixture/ASSET-I001","verification_steps":[
    {"run_role":"linux-reference","workdir":".","command":"probe --output fixture/ASSET-I001/runs/asset.json --handoff-bundle fixture/ASSET-I001/handoff/outbox/asset.tar.zst --handoff-sha256 fixture/ASSET-I001/handoff/outbox/asset.sha256"}
  ]},
  {"id":"SPK-GIT-L001","path":"fixture/GIT-L001","verification_steps":[
    {"run_role":"linux-default-filesystem","workdir":".","command":"probe --output fixture/GIT-L001/runs/git.json --handoff-bundle fixture/GIT-L001/handoff/outbox/git.tar.zst --handoff-sha256 fixture/GIT-L001/handoff/outbox/git.sha256"}
  ]},
  {"id":"SPK-PKG-M001","path":"fixture","verification_steps":[
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
  .schemaVersion == 9
  and (.expectedIdentity | type == "object")
  and (.roleEvidence | type == "object")
  and ((.roleEvidence | keys | sort) == ["capturedIdentity","environment","evidenceClasses","gates","internalArtifacts","role","toolchain","viewport"])
  and ((.roleEvidence.environment | keys | sort) == ["architecture","cpuModel","documentedMemoryBytes","documentedStorageBytes","imageOS","imageVersion","logicalCpuCount","observedMemoryBytes","observedStorageAvailableBytes","osRelease","runnerLabel"])
  and (.roleEvidence.environment.imageOS | type == "string" and length > 0)
  and (.roleEvidence.environment.imageVersion | type == "string" and length > 0)
  and (.roleEvidence.environment.osRelease | type == "string" and length > 0)
  and (.roleEvidence.environment.cpuModel | type == "string" and length > 0)
  and (.roleEvidence.environment.logicalCpuCount | type == "number" and . > 0)
  and (.roleEvidence.environment.documentedMemoryBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.documentedStorageBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.observedMemoryBytes | type == "number" and . > 0)
  and (.roleEvidence.environment.observedStorageAvailableBytes | type == "number" and . > 0)
  and (.roleEvidence.viewport == {width:1920,height:1080,refreshHz:60,verified:false} or .roleEvidence.viewport == {width:1920,height:1080,refreshHz:60,verified:true})
  and (.roleEvidence.toolchain | type == "object" and length > 0 and all(.[]; type == "string" and length > 0))
' "$3" >/dev/null
EOF
chmod +x "$tmp/bin/check-jsonschema"
export PATH="$tmp/bin:$PATH"
hex=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
jq -cn --arg hex "$hex" '{schemaVersion:1,expectedIdentitySha256:$hex,repositoryId:1,workflowRunId:1,runAttempt:1,sealingCheckRunId:2,workflowPath:".github/workflows/ci-role-linux-x86-64.yml",workflowSignerSha:"0123456789012345678901234567890123456789",workflowSignerRef:"refs/heads/master",trustAnchorSha:"0123456789012345678901234567890123456789",testedSourceSha:"0123456789012345678901234567890123456789",baseSha:"0123456789012345678901234567890123456789",role:"linux-x86_64",artifactNonce:"0123456789abcdef0123456789abcdef",runnerEnvironmentClaim:"github-hosted",expectedArtifact:{artifactId:1,artifactName:"managed-evidence-expected-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},candidateArtifact:{artifactId:2,artifactName:"managed-evidence-candidate-linux-x86_64-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},sealedArtifact:{artifactId:3,artifactName:"managed-evidence-sealed-linux-x86_64-0123456789abcdef0123456789abcdef",uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},roleBundleSha256:$hex,sealedBundleSha256:$hex}' >"$tmp/valid.json"
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
jq -cn --arg anchor "$anchor" --arg signer "$signer" --arg base "$receipt_base" --arg nonce "0123456789abcdef0123456789abcdef" '{trustAnchorSha:$anchor,workflowSignerSha:$signer,testedSourceSha:$signer,baseSha:$base,runIdentity:("managed:"+$nonce),artifactNonce:$nonce}' >"$receipt_identity"
receipt_identity_sha=$(sha256sum "$receipt_identity" | awk '{print $1}')
printf candidate >"$tmp/candidate.tar.zst"
printf sealed >"$tmp/sealed.tar.zst"
ROLE=linux-x86_64 WORKFLOW_PATH=.github/workflows/ci-role-linux-x86-64.yml ARTIFACT_NONCE=0123456789abcdef0123456789abcdef EXPECTED_IDENTITY_SHA256="$receipt_identity_sha" EXPECTED_ID=1 EXPECTED_DIGEST="$hex" CANDIDATE_ID=2 CANDIDATE_DIGEST="$hex" SEALED_ID=3 SEALED_DIGEST="$hex" TESTED_SOURCE_SHA="$signer" BASE_SHA="$receipt_base" CHECK_RUN_ID=4 EXPECTED_IDENTITY_FILE="$receipt_identity" GITHUB_SHA="$signer" GITHUB_REPOSITORY_ID=1 GITHUB_RUN_ID=2 GITHUB_RUN_ATTEMPT=1 "$root/scripts/write-sealing-receipt.sh" "$tmp/candidate.tar.zst" "$tmp/sealed.tar.zst" "$tmp/receipt-from-identity.json"
jq -e --arg anchor "$anchor" --arg signer "$signer" '.trustAnchorSha == $anchor and .workflowSignerSha == $signer and .trustAnchorSha != .workflowSignerSha' "$tmp/receipt-from-identity.json" >/dev/null

nonce=0123456789abcdef0123456789abcdef
sha=0123456789012345678901234567890123456789
role=linux-x86_64
role_schema_version=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json")
expected="$tmp/expected-identity.json"
jq -cn --arg sha "$sha" --arg nonce "$nonce" --arg role "$role" --arg hex "$hex" '
  {ticketIdentity:"CI-M003",releaseIdentity:"fixture",trustAnchorSha:$sha,testedSourceSha:$sha,workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",baseSha:$sha,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:["scripts/**"],buildIdentity:$hex,corpusIdentity:$hex,runIdentity:("managed:"+$nonce),artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:$sha}},requiredEvidenceClasses:{"linux-x86_64":["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"],"macos-26-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"],"macos-15-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]}}' >"$expected"
source="$tmp/role-source"; mkdir -p "$source/results"
printf fixture >"$source/results/result.json"
result_bytes=$(wc -c <"$source/results/result.json")
result_sha=$(sha256sum "$source/results/result.json" | awk '{print $1}')
expected_sha=$(sha256sum "$expected" | awk '{print $1}')
jq -cn --slurpfile expected "$expected" --arg expected_sha "$expected_sha" --arg role "$role" --arg result_sha "$result_sha" --argjson result_bytes "$result_bytes" --argjson version "$role_schema_version" '
  {schemaVersion:$version,expectedIdentity:$expected[0],expectedIdentitySha256:$expected_sha,roleEvidence:{role:$role,capturedIdentity:($expected[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:"ubuntu-24.04",imageOS:"fixture-linux",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"x86_64",cpuModel:"fixture-cpu",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:16000000000,observedStorageAvailableBytes:14000000000},viewport:{width:1920,height:1080,refreshHz:60,verified:false},evidenceClasses:$expected[0].requiredEvidenceClasses[$role],gates:($expected[0].requiredEvidenceClasses[$role] | map({(.):true}) | add),toolchain:{flutter:"fixture",dart:"fixture"},internalArtifacts:[{name:"results/result.json",bytes:$result_bytes,sha256:$result_sha}]}}' >"$source/ci-role-evidence.json"
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
      "AST-H001": {"linux-x86_64":["common-functional","performance","ast-measurement"],"macos-26-arm64":["common-functional","performance","ast-measurement"],"macos-15-arm64":["common-functional"]},
      "PATH-H002": {"linux-x86_64":["common-functional","filesystem-compatibility"],"macos-26-arm64":["common-functional","filesystem-compatibility"],"macos-15-arm64":["common-functional"]},
      "ASSET-I001": {"linux-x86_64":["common-functional","performance","asset-measurement"],"macos-26-arm64":["common-functional","performance","asset-measurement"],"macos-15-arm64":["common-functional"]},
      "GIT-L001": {"linux-x86_64":["common-functional","filesystem-compatibility","git-protocol"],"macos-26-arm64":["common-functional","filesystem-compatibility","git-protocol"],"macos-15-arm64":["common-functional"]},
      "PKG-M001": {"linux-x86_64":["packaging-runtime"],"macos-26-arm64":["packaging-runtime","repeatable-construction"],"macos-15-arm64":["packaging-runtime-compatibility"]}
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
     roleEvidence:{role:$role,capturedIdentity:($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}),environment:{runnerLabel:"ubuntu-24.04",imageOS:"fixture-linux",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"x86_64",cpuModel:"fixture-cpu",logicalCpuCount:4,documentedMemoryBytes:16000000000,documentedStorageBytes:14000000000,observedMemoryBytes:16000000000,observedStorageAvailableBytes:14000000000},viewport:{width:1920,height:1080,refreshHz:60,verified:true},evidenceClasses:$identity[0].requiredEvidenceClasses[$role],gates:($identity[0].requiredEvidenceClasses[$role] | map({(.):true}) | add),toolchain:{flutter:"fixture",dart:"fixture"},internalArtifacts:$members}}' >"$manifest"
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
archive "$valid_bundle" ci-role-evidence.json results/result.json
validate_role_bundle "$valid_bundle"

# Every managed ticket gets a bundle whose exact members occupy its trusted
# output roots. The seal validator must accept only the contract-declared
# names, while the manifest continues to bind the complete byte inventory.
validate_contract_ticket_bundle AST-H001 runs/ast.json handoff/outbox/ast.tar.zst handoff/outbox/ast.sha256
validate_contract_ticket_bundle PATH-H002 runs/path.json handoff/outbox/path.tar.zst handoff/outbox/path.sha256
validate_contract_ticket_bundle ASSET-I001 runs/asset.json handoff/outbox/asset.tar.zst handoff/outbox/asset.sha256
validate_contract_ticket_bundle GIT-L001 runs/git.json handoff/outbox/git.tar.zst handoff/outbox/git.sha256
validate_contract_ticket_bundle PKG-M001 runs/pkg.json logs/pkg.stdout logs/pkg.stderr artifacts/pkg.tar.zst handoff/outbox/pkg.tar.zst handoff/outbox/pkg.sha256

# PKG-M001 exports two opaque producer bytes for the authenticated macOS 15
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
jq '.ticketIdentity = "PKG-M001" | .requiredEvidenceClasses = {"linux-x86_64":["packaging-runtime"],"macos-26-arm64":["packaging-runtime","repeatable-construction"],"macos-15-arm64":["packaging-runtime-compatibility"]}' "$expected" >"$pkg_expected"
pkg_expected_sha=$(sha256sum "$pkg_expected" | awk '{print $1}')
stage_source="$tmp/stage-source"
cp -a "$source" "$stage_source"
jq --slurpfile identity "$pkg_expected" --arg digest "$pkg_expected_sha" '
  .expectedIdentity = $identity[0] |
  .expectedIdentitySha256 = $digest |
  .roleEvidence.role = "macos-26-arm64" |
  .roleEvidence.capturedIdentity = ($identity[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:"macos-26-arm64"}) |
  .roleEvidence.environment = {runnerLabel:"macos-26",imageOS:"fixture-macos",imageVersion:"fixture-image",osRelease:"fixture-release",architecture:"aarch64",cpuModel:"fixture-cpu",logicalCpuCount:3,documentedMemoryBytes:7000000000,documentedStorageBytes:14000000000,observedMemoryBytes:7000000000,observedStorageAvailableBytes:14000000000} |
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
  {schemaVersion:1,expectedIdentitySha256:$digest,repositoryId:1,workflowRunId:2,runAttempt:1,sealingCheckRunId:3,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",trustAnchorSha:$sha,testedSourceSha:$sha,baseSha:$sha,role:"macos-26-arm64",artifactNonce:$nonce,runnerEnvironmentClaim:"github-hosted",expectedArtifact:{artifactId:1,artifactName:("managed-evidence-expected-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},candidateArtifact:{artifactId:2,artifactName:("managed-evidence-candidate-macos-26-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},sealedArtifact:{artifactId:3,artifactName:("managed-evidence-sealed-macos-26-arm64-"+$nonce),uploadActionDigest:$hex,artifactDigest:("sha256:"+$hex)},roleBundleSha256:$role_hash,sealedBundleSha256:$sealed_hash}
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
