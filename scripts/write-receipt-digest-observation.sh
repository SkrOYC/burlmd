#!/usr/bin/env bash
# Write the caller-owned, post-seal receipt digest transport.  The values are
# supplied only by the trusted caller through reusable-workflow outputs.
set -euo pipefail

die() { printf 'receipt digest transport: %s\n' "$*" >&2; exit 2; }

output=
while (($#)); do
  case "$1" in
    --output) output=${2:-}; shift 2 ;;
    *) die "usage: $0 --output PATH" ;;
  esac
done
[[ -n $output && $output != /* && $output != *'..'* && $output != */ ]] || {
  die 'output is invalid'
}

# The caller writes a receipt-digest transport, but its schema is a trusted control.
# Resolve that control from this script's checkout, never from the current
# directory or the artifact output directory.
script_path=$(realpath -e -- "$0" 2>/dev/null) || die 'script path is unavailable'
script_dir=$(dirname -- "$script_path") || die 'script directory is unavailable'
script_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null) || die 'script is not in a Git checkout'
script_root=$(realpath -e -- "$script_root") || die 'script checkout path is unavailable'
[[ $script_path == "$script_root/scripts/write-receipt-digest-observation.sh" ]] || die 'script must run from its checkout'
receipt_transport_schema=$script_root/.constitution/tech-spec/contracts/ci-evidence.schema.json
[[ -f $receipt_transport_schema && ! -L $receipt_transport_schema ]] || die 'trusted receipt transport schema is unavailable'
command -v check-jsonschema >/dev/null 2>&1 || die 'locked check-jsonschema is required'

[[ ${EXPECTED_IDENTITY_SHA256:-} =~ ^[0-9a-f]{64}$ ]] || die 'expected identity digest is invalid'
[[ ${WORKFLOW_SIGNER_SHA:-} =~ ^[0-9a-f]{40}$ ]] || die 'workflow signer is invalid'
[[ ${ARTIFACT_NONCE:-} =~ ^[0-9a-f]{32}$ ]] || die 'nonce is invalid'
for scalar in REPOSITORY_ID WORKFLOW_RUN_ID RUN_ATTEMPT LINUX_RECEIPT_ARTIFACT_ID MACOS_26_RECEIPT_ARTIFACT_ID MACOS_15_RECEIPT_ARTIFACT_ID; do
  [[ ${!scalar:-} =~ ^[1-9][0-9]*$ ]] || die "$scalar is invalid"
done
[[ $RUN_ATTEMPT == 1 ]] || die 'requires run attempt 1'
for scalar in LINUX_RECEIPT_UPLOAD_ACTION_DIGEST MACOS_26_RECEIPT_UPLOAD_ACTION_DIGEST MACOS_15_RECEIPT_UPLOAD_ACTION_DIGEST; do
  [[ ${!scalar:-} =~ ^[0-9a-f]{64}$ ]] || die "$scalar is invalid"
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/receipt-digest-transport.XXXXXX") || die 'temporary directory creation failed'
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
document=$tmp/receipt-upload-digests.json
schema_fragment=$tmp/receipt-digest-transport.schema.json
jq -cn \
  --arg expected "$EXPECTED_IDENTITY_SHA256" \
  --argjson repository "$REPOSITORY_ID" \
  --argjson run "$WORKFLOW_RUN_ID" \
  --arg signer "$WORKFLOW_SIGNER_SHA" \
  --arg nonce "$ARTIFACT_NONCE" \
  --argjson linux_id "$LINUX_RECEIPT_ARTIFACT_ID" \
  --arg linux_digest "$LINUX_RECEIPT_UPLOAD_ACTION_DIGEST" \
  --argjson macos_26_id "$MACOS_26_RECEIPT_ARTIFACT_ID" \
  --arg macos_26_digest "$MACOS_26_RECEIPT_UPLOAD_ACTION_DIGEST" \
  --argjson macos_15_id "$MACOS_15_RECEIPT_ARTIFACT_ID" \
  --arg macos_15_digest "$MACOS_15_RECEIPT_UPLOAD_ACTION_DIGEST" \
  '{schemaVersion:1,expectedIdentitySha256:$expected,repositoryId:$repository,workflowRunId:$run,runAttempt:1,workflowSignerSha:$signer,artifactNonce:$nonce,receipts:[
    {role:"linux-x86_64",artifactId:$linux_id,artifactName:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),uploadActionDigest:$linux_digest},
    {role:"macos-26-arm64",artifactId:$macos_26_id,artifactName:("managed-evidence-seal-receipt-macos-26-arm64-" + $nonce),uploadActionDigest:$macos_26_digest},
    {role:"macos-15-arm64",artifactId:$macos_15_id,artifactName:("managed-evidence-seal-receipt-macos-15-arm64-" + $nonce),uploadActionDigest:$macos_15_digest}
  ]}' >"$document" || die 'JSON generation failed'

# Keep the authoritative $defs intact and make the receipt transport its root.
# An explicit local base URI keeps every fragment reference in this ephemeral
# schema local, regardless of the aggregate schema's HTTPS $id.
jq -ce '
  {
    "$schema": .["$schema"],
    "$ref": "#/$defs/receiptDigestTransport",
    "$defs": .["$defs"]
  }
  | select((.["$schema"] | type) == "string")
  | select((.["$defs"] | type) == "object")
  | select((.["$defs"].receiptDigestTransport | type) == "object")
' "$receipt_transport_schema" >"$schema_fragment" || die 'trusted receipt transport schema is malformed'
check-jsonschema --no-cache --schemafile "$schema_fragment" --base-uri "file://$schema_fragment" "$document" >/dev/null || die 'receipt transport does not satisfy trusted schema'

mkdir -p -- "$(dirname -- "$output")" || die 'output directory creation failed'
mv -f -- "$document" "$output" || die 'validated transport publication failed'
