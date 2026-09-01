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
  "${GITHUB_SHA:?}" "${GITHUB_RUN_ATTEMPT:?}"
script_root=$(cd "$(dirname "$0")/.." && pwd -P)
contract=$script_root/.constitution/tech-spec/contracts/provisional-spikes.toml
role_schema=$script_root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json
[[ -f $contract && -f $role_schema ]] || exit 2
[[ $(awk -F ' = ' '$1 == "ci_role_evidence_schema_version" { print $2; exit }' "$contract") == $(jq -er '.properties.schemaVersion.const' "$role_schema") ]] || exit 2
[[ $role =~ ^(linux-x86_64|macos-26-arm64|macos-15-arm64)$ && -n $output && $output != *$'\n'* && $output != *$'\r'* ]] || exit 2
for sha in "$EXPECTED_IDENTITY_SHA256" "$TESTED_SOURCE_SHA" "$BASE_SHA" "$GITHUB_SHA"; do
  [[ $sha =~ ^[0-9a-f]{40}$ || $sha =~ ^[0-9a-f]{64}$ ]] || exit 2
done
[[ $EXPECTED_IDENTITY_SHA256 =~ ^[0-9a-f]{64}$ && $TESTED_SOURCE_SHA =~ ^[0-9a-f]{40}$ && $BASE_SHA =~ ^[0-9a-f]{40}$ && $RUN_IDENTITY == "managed:$ARTIFACT_NONCE" && $ARTIFACT_NONCE =~ ^[0-9a-f]{32}$ ]] || exit 2
# A GitHub UI/API rerun increments this value.  The workflows put it in the
# validator's environment before any candidate, artifact, seal, or attestation
# boundary, so only a fresh workflow_dispatch attempt can proceed.
[[ $GITHUB_RUN_ATTEMPT == 1 ]] || exit 2
[[ $EXPECTED_IDENTITY_BASE64 =~ ^[A-Za-z0-9+/]*={0,2}$ && ${#EXPECTED_IDENTITY_BASE64} -gt 0 && $(( ${#EXPECTED_IDENTITY_BASE64} % 4 )) -eq 0 ]] || exit 2
if [[ -n ${EXPECTED_ARTIFACT_ID:-} || -n ${EXPECTED_ARTIFACT_DIGEST:-} ]]; then
  [[ ${EXPECTED_ARTIFACT_ID:-} =~ ^[1-9][0-9]*$ && ${EXPECTED_ARTIFACT_DIGEST:-} =~ ^[0-9a-f]{64}$ ]] || exit 2
fi

parent=$(dirname -- "$output")
[[ -d $parent && ! -L $parent ]] || exit 2
tmp=$(mktemp "$parent/.expected-identity.XXXXXX")
identity_schema=$(mktemp "$parent/.expected-identity-schema.XXXXXX")
trap 'rm -f -- "$tmp" "$identity_schema"' EXIT
printf '%s' "$EXPECTED_IDENTITY_BASE64" | base64 --decode >"$tmp" || exit 2
[[ $(sha256sum "$tmp" | awk '{print $1}') == "$EXPECTED_IDENTITY_SHA256" ]] || exit 1
# Validate the identity against the current role schema's exact embedded
# expectedIdentity definition before any semantic comparison. This keeps the
# workflow boundary synchronized with the versioned schema rather than an
# obsolete hand-maintained top-level key list.
jq '{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs": ."$defs","$ref":"#/$defs/expectedIdentity"}' "$role_schema" >"$identity_schema" || exit 2
check-jsonschema --no-cache --schemafile "$identity_schema" "$tmp" >/dev/null || exit 1
ticket=$(jq -er '.ticketIdentity | strings' "$tmp") || exit 1
# Reject an invalid ticket before it can become an input to the raw-contract
# profile lookup (and, in turn, jq's JSON-valued argument parser).
[[ $ticket =~ ^BURL-[A-Z][0-9]{3}$ ]] || exit 1
profile_for() {
  local requested_ticket=$1 requested_role=$2
  awk -v ticket="$requested_ticket" -v role="$requested_role" '
    $0 == "[ci_bootstrap.ticket_evidence_profiles.\"" ticket "\"]" { on=1; next }
    /^\[/ { on=0 }
    on && $0 ~ "^\"" role "\"[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$contract" | jq -ce .
}
expected_profile=$(jq -cn \
  --argjson linux "$(profile_for "$ticket" linux-x86_64)" \
  --argjson macos26 "$(profile_for "$ticket" macos-26-arm64)" \
  --argjson macos15 "$(profile_for "$ticket" macos-15-arm64)" \
  '{"linux-x86_64":$linux,"macos-26-arm64":$macos26,"macos-15-arm64":$macos15}') || exit 1
role_guard_for() {
  local requested_role=$1 path workflow candidate_block seal_block label
  case "$requested_role" in
    linux-x86_64) path=.github/workflows/ci-role-linux-x86-64.yml;;
    macos-26-arm64) path=.github/workflows/ci-role-macos-26-arm64.yml;;
    macos-15-arm64) path=.github/workflows/ci-role-macos-15-arm64.yml;;
    *) return 1;;
  esac
  workflow=$script_root/$path
  [[ -f $workflow && ! -L $workflow ]] || return 1
  candidate_block=$(sed -n '/^  candidate:/,/^  seal:/p' "$workflow") || return 1
  seal_block=$(sed -n '/^  seal:/,$p' "$workflow") || return 1
  label=$(awk '/^[[:space:]]*runs-on:[[:space:]]*/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, ""); print; exit}' <<<"$candidate_block")
  [[ $label =~ ^(ubuntu-24\.04|macos-26|macos-15)$ ]] || return 1
  rg -qx '    needs: candidate' <<<"$seal_block" || return 1
  jq -cn --arg path "$path" --arg label "$label" '{workflowPath:$path,runnerLabel:$label,candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:true,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"}'
}
expected_guards=$(jq -cn --argjson linux "$(role_guard_for linux-x86_64)" --argjson macos26 "$(role_guard_for macos-26-arm64)" --argjson macos15 "$(role_guard_for macos-15-arm64)" '{"linux-x86_64":$linux,"macos-26-arm64":$macos26,"macos-15-arm64":$macos15}') || exit 1
expected_allowlist=''
if [[ $ticket == BURL-M003 ]]; then
  expected_allowlist=$(awk '/^bootstrap_write_allowlist[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }' "$contract" | jq -ce .) || exit 1
else
  command -v taplo >/dev/null || exit 2
  expected_allowlist=$(taplo get --file-path "$contract" --output-format json "ci_bootstrap.non_spike_source_write_allowlists.tickets.\"$ticket\"" 2>/dev/null | jq -ce .) || true
  if [[ -z $expected_allowlist ]]; then
    expected_allowlist=$(taplo get --file-path "$contract" --output-format json 'spikes[*]' | jq -ce --arg id "SPK-$ticket" '[.[] | select(.id == $id) | .write_allowlist] | if length == 1 then .[0] else empty end') || exit 1
  fi
fi
# This is deliberately a semantic validator rather than a permissive JSON
# parser. The reusable workflows use the decoded bytes as a trust boundary, so
# accepting an identity that only happens to contain the requested role would
# let a caller alter the ticket profile or a different role's signer.
jq -e \
  --arg tested "$TESTED_SOURCE_SHA" --arg base "$BASE_SHA" --arg nonce "$ARTIFACT_NONCE" --arg role "$role" --arg signer "$GITHUB_SHA" --argjson profile "$expected_profile" --argjson allowlist "$expected_allowlist" --argjson guards "$expected_guards" '
  def sha: type == "string" and test("^[0-9a-f]{40}$");
  def digest: type == "string" and test("^[0-9a-f]{64}$");
  def signer($path):
    type == "object" and (keys | sort) == ["jobWorkflowRef", "jobWorkflowSha", "workflowPath"] and
    .workflowPath == $path and
    .jobWorkflowRef == ("SkrOYC/burlmd/" + $path + "@refs/heads/master") and
    .jobWorkflowSha == $signer;
  type == "object" and
  (.ticketIdentity | type == "string") and
  (.releaseIdentity | type == "string" and length > 0) and
  (.trustAnchorSha | sha) and .testedSourceSha == $tested and .workflowSignerSha == $signer and .baseSha == $base and
  .workflowSignerRef == "refs/heads/master" and .workflowEvent == "workflow_dispatch" and
  .evidenceReportCommitPolicy == "later-reviewed-evidence-pr-with-declared-evidence-only-diff" and
  (.sourceWriteAllowlist == $allowlist) and
  (.buildIdentity | digest) and (.corpusIdentity | digest) and
  .runIdentity == ("managed:" + $nonce) and .artifactNonce == $nonce and
  .requiredRoleIdentities == ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"] and
  (.requiredRoleSigners | type == "object" and (keys | sort) == ["linux-x86_64", "macos-15-arm64", "macos-26-arm64"]) and
  (.requiredRoleSigners["linux-x86_64"] | signer(".github/workflows/ci-role-linux-x86-64.yml")) and
  (.requiredRoleSigners["macos-26-arm64"] | signer(".github/workflows/ci-role-macos-26-arm64.yml")) and
  (.requiredRoleSigners["macos-15-arm64"] | signer(".github/workflows/ci-role-macos-15-arm64.yml")) and
  .requiredRoleGuards == $guards and
  .requiredEvidenceClasses == $profile and
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
if [[ $(jq -r '.ticketIdentity' "$output") == BURL-O001 ]]; then
  printf 'requires_macos_15_stage=true\n'
else
  printf 'requires_macos_15_stage=false\n'
fi
if [[ -n ${EXPECTED_ARTIFACT_ID:-} ]]; then
  printf 'expected_artifact_id=%s\nexpected_artifact_digest=%s\n' "$EXPECTED_ARTIFACT_ID" "$EXPECTED_ARTIFACT_DIGEST"
fi
