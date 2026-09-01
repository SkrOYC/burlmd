#!/usr/bin/env bash
# Focused contract tests for the caller-owned receipt digest transport.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/receipt-digest-observation-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
nonce=0123456789abcdef0123456789abcdef
digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
signer=0123456789012345678901234567890123456789

(cd "$tmp" && env EXPECTED_IDENTITY_SHA256="$digest" REPOSITORY_ID=1 WORKFLOW_RUN_ID=2 RUN_ATTEMPT=1 \
  WORKFLOW_SIGNER_SHA="$signer" ARTIFACT_NONCE="$nonce" \
  LINUX_RECEIPT_ARTIFACT_ID=3 LINUX_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_26_RECEIPT_ARTIFACT_ID=4 MACOS_26_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_15_RECEIPT_ARTIFACT_ID=5 MACOS_15_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  "$root/scripts/write-receipt-digest-observation.sh" --output receipt-upload-digests.json)

jq -e --arg nonce "$nonce" --arg digest "$digest" --arg signer "$signer" '
  (keys | sort) == ["artifactNonce","expectedIdentitySha256","receipts","repositoryId","runAttempt","schemaVersion","workflowRunId","workflowSignerSha"] and
  .schemaVersion == 1 and .expectedIdentitySha256 == $digest and .repositoryId == 1 and .workflowRunId == 2 and .runAttempt == 1 and .workflowSignerSha == $signer and .artifactNonce == $nonce and
  .receipts == [
    {role:"linux-x86_64",artifactId:3,artifactName:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),uploadActionDigest:$digest},
    {role:"macos-26-arm64",artifactId:4,artifactName:("managed-evidence-seal-receipt-macos-26-arm64-" + $nonce),uploadActionDigest:$digest},
    {role:"macos-15-arm64",artifactId:5,artifactName:("managed-evidence-seal-receipt-macos-15-arm64-" + $nonce),uploadActionDigest:$digest}
  ]
' "$tmp/receipt-upload-digests.json" >/dev/null

# The writer must derive its validator input from the schema in its own
# checkout, rather than accepting a hand-maintained field list or a schema
# selected from the output directory. Mutating that authoritative fixture
# makes the normal version-1 document invalid before it could be uploaded.
fixture_root=$tmp/fixture-checkout
mkdir -p "$fixture_root/scripts" "$fixture_root/.constitution/tech-spec/contracts"
cp -- "$root/scripts/write-receipt-digest-observation.sh" "$fixture_root/scripts/"
cp -- "$root/.constitution/tech-spec/contracts/ci-evidence.schema.json" "$fixture_root/.constitution/tech-spec/contracts/"
git init -q "$fixture_root"
jq '."$defs".receiptDigestTransport.properties.schemaVersion.const = 2' \
  "$fixture_root/.constitution/tech-spec/contracts/ci-evidence.schema.json" >"$fixture_root/schema.next"
mv -- "$fixture_root/schema.next" "$fixture_root/.constitution/tech-spec/contracts/ci-evidence.schema.json"

set +e
(cd "$fixture_root" && env EXPECTED_IDENTITY_SHA256="$digest" REPOSITORY_ID=1 WORKFLOW_RUN_ID=2 RUN_ATTEMPT=1 \
  WORKFLOW_SIGNER_SHA="$signer" ARTIFACT_NONCE="$nonce" \
  LINUX_RECEIPT_ARTIFACT_ID=3 LINUX_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_26_RECEIPT_ARTIFACT_ID=4 MACOS_26_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_15_RECEIPT_ARTIFACT_ID=5 MACOS_15_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  ./scripts/write-receipt-digest-observation.sh --output rejected.json) >/dev/null 2>&1
status=$?
set -e
[[ $status == 2 && ! -e $fixture_root/rejected.json ]]

set +e
(cd "$tmp" && env EXPECTED_IDENTITY_SHA256="$digest" REPOSITORY_ID=1 WORKFLOW_RUN_ID=2 RUN_ATTEMPT=2 \
  WORKFLOW_SIGNER_SHA="$signer" ARTIFACT_NONCE="$nonce" \
  LINUX_RECEIPT_ARTIFACT_ID=3 LINUX_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_26_RECEIPT_ARTIFACT_ID=4 MACOS_26_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  MACOS_15_RECEIPT_ARTIFACT_ID=5 MACOS_15_RECEIPT_UPLOAD_ACTION_DIGEST="$digest" \
  "$root/scripts/write-receipt-digest-observation.sh" --output invalid.json >/dev/null 2>&1)
status=$?
set -e
[[ $status == 2 && ! -e $tmp/invalid.json ]]

printf 'receipt digest observation tests passed\n'
