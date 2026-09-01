#!/usr/bin/env bash
# The macOS 15 candidate receives this interface only through the macOS 26
# seal's reusable-workflow outputs.  Keep presence/absence exhaustive: a
# partial stage is neither an optional no-stage invocation nor usable input.
set -euo pipefail

ticket=${1:?ticket identity is required}
fields=(
  STAGE_ARTIFACT_NAME STAGE_ARTIFACT_ID STAGE_UPLOAD_ACTION_DIGEST
  STAGE_REST_DIGEST STAGE_CREATED_AT STAGE_EXPIRES_AT STAGE_MANIFEST_SHA256
  STAGE_ATTESTATION_SUBJECT_DIGEST STAGE_ATTESTATION_BUNDLE_SHA256
  PRODUCER_WORKFLOW_SIGNER_SHA PRODUCER_WORKFLOW_RUN_ID PRODUCER_RUN_ATTEMPT
  PRODUCER_SEALING_CHECK_RUN_ID PRODUCER_SEALING_RECEIPT_ARTIFACT_ID
  PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST
  PRODUCER_SEALING_RECEIPT_REST_DIGEST PRODUCER_SEALING_RECEIPT_CREATED_AT
  PRODUCER_SEALING_RECEIPT_EXPIRES_AT PRODUCER_LINEAGE_ARTIFACT_ID
  PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST PRODUCER_LINEAGE_REST_DIGEST
  PRODUCER_LINEAGE_SHA256 PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST
  PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256 PRODUCER_ROLE CONSUMER_ROLE
)

for field in "${fields[@]}"; do
  value=${!field-}
  if [[ $ticket == BURL-O001 ]]; then
    [[ -n $value ]] || { printf 'missing compatibility interface field: %s\n' "$field" >&2; exit 1; }
  else
    [[ -z $value ]] || { printf 'unexpected compatibility interface field for %s: %s\n' "$ticket" "$field" >&2; exit 1; }
  fi
done
