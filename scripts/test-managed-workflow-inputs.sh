#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-workflow-inputs.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
sha=0123456789012345678901234567890123456789
nonce=0123456789abcdef0123456789abcdef
jq -cn --arg sha "$sha" --arg nonce "$nonce" --arg digest "$(printf fixture | sha256sum | awk '{print $1}')" '
  {ticketIdentity:"BURL-M003",releaseIdentity:"fixture",trustAnchorSha:$sha,testedSourceSha:$sha,workflowSignerSha:$sha,workflowSignerRef:"refs/heads/master",baseSha:$sha,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:[".github/workflows/ci.yml",".github/workflows/ci-role-linux-x86-64.yml",".github/workflows/ci-role-macos-26-arm64.yml",".github/workflows/ci-role-macos-15-arm64.yml","devenv.nix","devenv.lock","scripts/**","lib/visual_capture_main.dart","test_driver/visual_capture_driver.dart","test/visual_capture_driver_protocol_test.dart","test/goldens/**","integration_test/**"],buildIdentity:$digest,corpusIdentity:$digest,runIdentity:("managed:"+$nonce),artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$sha},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:$sha}},requiredRoleGuards:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",runnerLabel:"ubuntu-22.04",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",runnerLabel:"macos-26",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",runnerLabel:"macos-15",candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"}},requiredEvidenceClasses:{"linux-x86_64":["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"],"macos-26-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"],"macos-15-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]}}' >"$tmp/identity.json"
digest=$(sha256sum "$tmp/identity.json" | awk '{print $1}')
encoded=$(base64 -w0 "$tmp/identity.json")
run_valid() {
  EXPECTED_IDENTITY_BASE64="$encoded" EXPECTED_IDENTITY_SHA256="$digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT=1 RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE="$nonce" EXPECTED_ARTIFACT_ID=1 EXPECTED_ARTIFACT_DIGEST="$digest" "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/output.json"
}
run_valid >"$tmp/outputs"
cmp "$tmp/identity.json" "$tmp/output.json"
expected_output_lines=11
[[ $(wc -l <"$tmp/outputs") == "$expected_output_lines" ]] || { echo 'validator emitted an unexpected workflow output count' >&2; exit 1; }
while IFS= read -r line; do
  [[ $line =~ ^(nonce|tested_source_sha|base_sha|expected_identity_sha256|expected_identity_file|ticket_identity|workflow_signer_sha|trust_anchor_sha|requires_macos_15_stage|expected_artifact_id|expected_artifact_digest)=([^$'\r\n']*)$ ]] || {
    echo "unsafe workflow output: $line" >&2
    exit 1
  }
done <"$tmp/outputs"
if EXPECTED_IDENTITY_BASE64='"; touch injected' EXPECTED_IDENTITY_SHA256="$digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT=1 RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE="$nonce" "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/rejected.json"; then
  echo 'accepted shell-metacharacter dispatcher input' >&2
  exit 1
fi
if EXPECTED_IDENTITY_BASE64="$encoded" EXPECTED_IDENTITY_SHA256="$digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT=1 RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE=ABCDEF0123456789ABCDEF0123456789 "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/rejected-nonce.json"; then
  echo 'accepted noncanonical nonce' >&2
  exit 1
fi

# Workflow command files consume only one output per line. A syntactically
# valid identity with a newline in a derived field must not create a second
# output or otherwise weaken the trusted fan-out.
jq '.ticketIdentity = "BURL-M003\nspoof=true"' "$tmp/identity.json" >"$tmp/injected-identity.json"
injected_digest=$(sha256sum "$tmp/injected-identity.json" | awk '{print $1}')
injected_encoded=$(base64 -w0 "$tmp/injected-identity.json")
if EXPECTED_IDENTITY_BASE64="$injected_encoded" EXPECTED_IDENTITY_SHA256="$injected_digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT=1 RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE="$nonce" "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/rejected-output-injection.json"; then
  echo 'accepted output-injection identity' >&2
  exit 1
fi

# The workflow boundary receives GitHub's runtime attempt as an environment
# value. It must reject absence, malformed forms, and every non-fresh rerun.
for bad_attempt in '' 0 2 01 1.0 -1 '1 '; do
  if EXPECTED_IDENTITY_BASE64="$encoded" EXPECTED_IDENTITY_SHA256="$digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT="$bad_attempt" RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE="$nonce" "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/rejected-attempt.json"; then
    echo 'accepted non-fresh workflow attempt' >&2
    exit 1
  fi
done
if EXPECTED_IDENTITY_BASE64="$encoded" EXPECTED_IDENTITY_SHA256="$digest" TESTED_SOURCE_SHA="$sha" BASE_SHA="$sha" GITHUB_SHA="$sha" RUN_IDENTITY="managed:$nonce" ARTIFACT_NONCE="$nonce" "$root/scripts/validate-managed-workflow-inputs.sh" --role linux-x86_64 --output "$tmp/rejected-missing-attempt.json"; then
  echo 'accepted missing workflow attempt' >&2
  exit 1
fi
