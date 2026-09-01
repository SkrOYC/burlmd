#!/usr/bin/env bash
# Validate dispatcher values before they influence a checkout, artifact name,
# or shell command.  Workflow expressions are copied into environment values;
# no untrusted input is interpolated into a run block.
set -euo pipefail

role= output=
while (($#)); do
  case $1 in
    --role) role=${2:-}; shift 2 ;;
    --output) output=${2:-}; shift 2 ;;
    *) echo 'usage: validate-managed-workflow-inputs.sh --role ROLE --output FILE' >&2; exit 2 ;;
  esac
done

: "${EXPECTED_IDENTITY_BASE64:?}" "${EXPECTED_IDENTITY_SHA256:?}" \
  "${TESTED_SOURCE_SHA:?}" "${BASE_SHA:?}" "${RUN_IDENTITY:?}" "${ARTIFACT_NONCE:?}" \
  "${GITHUB_SHA:?}"
[[ $role =~ ^(linux-x86_64|macos-26-arm64|macos-15-arm64)$ && -n $output && $output != *$'\n'* && $output != *$'\r'* ]] || exit 2
for sha in "$EXPECTED_IDENTITY_SHA256" "$TESTED_SOURCE_SHA" "$BASE_SHA" "$GITHUB_SHA"; do
  [[ $sha =~ ^[0-9a-f]{40}$ || $sha =~ ^[0-9a-f]{64}$ ]] || exit 2
done
[[ $EXPECTED_IDENTITY_SHA256 =~ ^[0-9a-f]{64}$ && $TESTED_SOURCE_SHA =~ ^[0-9a-f]{40}$ && $BASE_SHA =~ ^[0-9a-f]{40}$ && $RUN_IDENTITY == "managed:$ARTIFACT_NONCE" && $ARTIFACT_NONCE =~ ^[0-9a-f]{32}$ ]] || exit 2
[[ $EXPECTED_IDENTITY_BASE64 =~ ^[A-Za-z0-9+/]*={0,2}$ && ${#EXPECTED_IDENTITY_BASE64} -gt 0 && $(( ${#EXPECTED_IDENTITY_BASE64} % 4 )) -eq 0 ]] || exit 2
if [[ -n ${EXPECTED_ARTIFACT_ID:-} || -n ${EXPECTED_ARTIFACT_DIGEST:-} ]]; then
  [[ ${EXPECTED_ARTIFACT_ID:-} =~ ^[1-9][0-9]*$ && ${EXPECTED_ARTIFACT_DIGEST:-} =~ ^[0-9a-f]{64}$ ]] || exit 2
fi

parent=$(dirname -- "$output")
[[ -d $parent && ! -L $parent ]] || exit 2
tmp=$(mktemp "$parent/.expected-identity.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
printf '%s' "$EXPECTED_IDENTITY_BASE64" | base64 --decode >"$tmp" || exit 2
[[ $(sha256sum "$tmp" | awk '{print $1}') == "$EXPECTED_IDENTITY_SHA256" ]] || exit 1
# This is deliberately a semantic validator rather than a permissive JSON
# parser. The reusable workflows use the decoded bytes as a trust boundary, so
# accepting an identity that only happens to contain the requested role would
# let a caller alter the ticket profile or a different role's signer.
jq -e \
  --arg tested "$TESTED_SOURCE_SHA" --arg base "$BASE_SHA" --arg nonce "$ARTIFACT_NONCE" --arg role "$role" --arg signer "$GITHUB_SHA" '
  def sha: type == "string" and test("^[0-9a-f]{40}$");
  def digest: type == "string" and test("^[0-9a-f]{64}$");
  def signer($path):
    type == "object" and (keys | sort) == ["jobWorkflowRef", "jobWorkflowSha", "workflowPath"] and
    .workflowPath == $path and
    .jobWorkflowRef == ("SkrOYC/burlmd/" + $path + "@refs/heads/master") and
    .jobWorkflowSha == $signer;
  def profile($ticket):
    if $ticket == "CI-M003" then {
      "linux-x86_64":["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"],
      "macos-26-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"],
      "macos-15-arm64":["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]}
    elif $ticket == "AST-H001" then {"linux-x86_64":["common-functional","performance","ast-measurement"],"macos-26-arm64":["common-functional","performance","ast-measurement"],"macos-15-arm64":["common-functional"]}
    elif $ticket == "PATH-H002" then {"linux-x86_64":["common-functional","filesystem-compatibility"],"macos-26-arm64":["common-functional","filesystem-compatibility"],"macos-15-arm64":["common-functional"]}
    elif $ticket == "ASSET-I001" then {"linux-x86_64":["common-functional","performance","asset-measurement"],"macos-26-arm64":["common-functional","performance","asset-measurement"],"macos-15-arm64":["common-functional"]}
    elif $ticket == "GIT-L001" then {"linux-x86_64":["common-functional","filesystem-compatibility","git-protocol"],"macos-26-arm64":["common-functional","filesystem-compatibility","git-protocol"],"macos-15-arm64":["common-functional"]}
    elif $ticket == "PKG-M001" then {"linux-x86_64":["packaging-runtime"],"macos-26-arm64":["packaging-runtime","repeatable-construction"],"macos-15-arm64":["packaging-runtime-compatibility"]}
    else empty end;
  type == "object" and
  (keys | sort) == ["artifactNonce","baseSha","buildIdentity","corpusIdentity","evidenceReportCommitPolicy","releaseIdentity","requiredEvidenceClasses","requiredRoleIdentities","requiredRoleSigners","runIdentity","sourceWriteAllowlist","testedSourceSha","ticketIdentity","trustAnchorSha","workflowEvent","workflowSignerRef","workflowSignerSha"] and
  (.ticketIdentity | IN("CI-M003", "AST-H001", "PATH-H002", "ASSET-I001", "GIT-L001", "PKG-M001")) and
  (.releaseIdentity | type == "string" and length > 0) and
  (.trustAnchorSha | sha) and .testedSourceSha == $tested and .workflowSignerSha == $signer and .baseSha == $base and
  .workflowSignerRef == "refs/heads/master" and .workflowEvent == "workflow_dispatch" and
  .evidenceReportCommitPolicy == "later-reviewed-evidence-pr-with-declared-evidence-only-diff" and
  (.sourceWriteAllowlist | type == "array" and length > 0 and unique == . and all(.[]; type == "string" and test("^(?!/)(?!.*(?:^|/)\\.\\.?(?:/|$))(?!.*//)(?!.*\\/$)[A-Za-z0-9._/*-]+$"))) and
  (.buildIdentity | digest) and (.corpusIdentity | digest) and
  .runIdentity == ("managed:" + $nonce) and .artifactNonce == $nonce and
  .requiredRoleIdentities == ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"] and
  (.requiredRoleSigners | type == "object" and (keys | sort) == ["linux-x86_64", "macos-15-arm64", "macos-26-arm64"]) and
  (.requiredRoleSigners["linux-x86_64"] | signer(".github/workflows/ci-role-linux-x86-64.yml")) and
  (.requiredRoleSigners["macos-26-arm64"] | signer(".github/workflows/ci-role-macos-26-arm64.yml")) and
  (.requiredRoleSigners["macos-15-arm64"] | signer(".github/workflows/ci-role-macos-15-arm64.yml")) and
  .requiredEvidenceClasses == profile(.ticketIdentity) and
  (.requiredEvidenceClasses[$role] | type == "array" and length > 0)
' "$tmp" >/dev/null || exit 1
mv -f -- "$tmp" "$output"
trap - EXIT

# Only values that passed the strict grammar and canonical identity comparison
# become workflow outputs. They are safe to use in action inputs later on.
printf 'nonce=%s\n' "$ARTIFACT_NONCE"
printf 'tested_source_sha=%s\n' "$TESTED_SOURCE_SHA"
printf 'base_sha=%s\n' "$BASE_SHA"
printf 'expected_identity_sha256=%s\n' "$EXPECTED_IDENTITY_SHA256"
printf 'expected_identity_file=%s\n' "$output"
printf 'ticket_identity=%s\n' "$(jq -er '.ticketIdentity' "$output")"
printf 'workflow_signer_sha=%s\n' "$(jq -er '.workflowSignerSha' "$output")"
printf 'trust_anchor_sha=%s\n' "$(jq -er '.trustAnchorSha' "$output")"
if [[ $(jq -r '.ticketIdentity' "$output") == PKG-M001 ]]; then
  printf 'requires_macos_15_stage=true\n'
else
  printf 'requires_macos_15_stage=false\n'
fi
if [[ -n ${EXPECTED_ARTIFACT_ID:-} ]]; then
  printf 'expected_artifact_id=%s\nexpected_artifact_digest=%s\n' "$EXPECTED_ARTIFACT_ID" "$EXPECTED_ARTIFACT_DIGEST"
fi
