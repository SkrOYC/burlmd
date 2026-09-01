#!/usr/bin/env bash
# Exercise the raw receipt-digest transport acquisition boundary with local
# archives and a recording REST double. The production launcher is not sourced.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/receipt-digest-transport-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
functions=$tmp/functions.sh
{
  printf '%s\n' 'sha256_file() { sha256sum "$1" | awk '\''{print $1}'\''; }'
  awk '/^artifact_by_name\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^artifact_observation\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^derive_receipt_digest_transport_schema\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^validate_receipt_digest_transport_schema\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^validate_schema\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^safe_zip_member\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh"
  awk '/^receipt_digest_transport\(\)/ {copy=1} /^safe_zip_member\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
} >"$functions"
source "$functions"

nonce=0123456789abcdef0123456789abcdef
run_identity=managed:$nonce
expected_digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
workflow_signer=0123456789012345678901234567890123456789
run_id=2
RECEIPT_TRANSPORT_SCHEMA=$root/.constitution/tech-spec/contracts/ci-evidence.schema.json
API_BASE=https://fixture.invalid
REPOSITORY=fixture/repository
inventory=$tmp/inventory.json
jq -cn --arg nonce "$nonce" '{artifacts:[{id:11,name:("managed-evidence-receipt-digests-" + $nonce),digest:"sha256:pending",expired:false,workflow_run:{id:2,repository_id:1}}]}' >"$inventory"

transport_base() {
  jq -cn --arg nonce "$nonce" --arg expected "$expected_digest" --arg signer "$workflow_signer" '
    {schemaVersion:1,expectedIdentitySha256:$expected,repositoryId:1,workflowRunId:2,runAttempt:1,workflowSignerSha:$signer,artifactNonce:$nonce,receipts:[
      {role:"linux-x86_64",artifactId:3,artifactName:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),uploadActionDigest:("a" * 64)},
      {role:"macos-26-arm64",artifactId:4,artifactName:("managed-evidence-seal-receipt-macos-26-arm64-" + $nonce),uploadActionDigest:("a" * 64)},
      {role:"macos-15-arm64",artifactId:5,artifactName:("managed-evidence-seal-receipt-macos-15-arm64-" + $nonce),uploadActionDigest:("a" * 64)}
    ]}'
}
make_archive() {
  local document=$1
  rm -rf -- "$tmp/archive-root" "$tmp/transport.zip" "$tmp/receipt-digest-transport-11"
  mkdir "$tmp/archive-root"
  printf '%s\n' "$document" >"$tmp/archive-root/receipt-upload-digests.json"
  (cd "$tmp/archive-root" && zip -q "$tmp/transport.zip" receipt-upload-digests.json)
  archive_digest=$(sha256_file "$tmp/transport.zip")
  fixture_rest=$(jq -cn --arg nonce "$nonce" --arg digest "$archive_digest" '{id:11,name:("managed-evidence-receipt-digests-" + $nonce),digest:("sha256:" + $digest),expired:false,workflow_run:{id:2,repository_id:1}}')
  jq --arg digest "sha256:$archive_digest" '.artifacts[0].digest = $digest' "$inventory" >"$tmp/inventory.next"
  mv "$tmp/inventory.next" "$inventory"
}
api() {
  local request=${!#}
  case "$request" in
    */actions/artifacts/11) printf '%s\n' "$fixture_rest" ;;
    */actions/artifacts/11/zip) cat -- "${fixture_archive:-$tmp/transport.zip}" ;;
    *) return 77 ;;
  esac
}
assert_code() {
  local name=$1 expected=$2 document=$3
  make_archive "$document"
  fixture_archive=
  set +e
  receipt_digest_transport "$inventory" "$tmp/$name.json" >/dev/null
  status=$?
  set -e
  [[ $status == 1 && ${receipt_transport_rejection_code:-} == "$expected" ]] || {
    printf '%s: status=%s code=%s\n' "$name" "$status" "${receipt_transport_rejection_code:-none}" >&2
    exit 1
  }
}

valid=$(transport_base)
make_archive "$valid"
accepted=$(receipt_digest_transport "$inventory" "$tmp/accepted.json")
jq -e --arg nonce "$nonce" --arg digest "$archive_digest" '
  .observation == {artifactId:11,artifactName:("managed-evidence-receipt-digests-" + $nonce),artifactDigest:("sha256:" + $digest),downloadedArtifactSha256:$digest}
' <<<"$accepted" >/dev/null
jq -e '.transport.receipts | length == 3' <<<"$accepted" >/dev/null

# Every malformed or identity-bound transport shape fails before role receipt
# extraction. The order is part of the transport contract, not presentation.
for case_name in missing extra duplicate malformed reordered wrong-role wrong-run wrong-attempt wrong-signer wrong-nonce wrong-name; do
  case "$case_name" in
    missing) mutation='del(.receipts[2])' ;;
    extra) mutation='.extra = true' ;;
    duplicate) mutation='.receipts[2] = .receipts[1]' ;;
    malformed) mutation='.receipts[0].artifactId = "3"' ;;
    reordered) mutation='.receipts |= reverse' ;;
    wrong-role) mutation='.receipts[0].role = "macos-15-arm64"' ;;
    wrong-run) mutation='.workflowRunId = 99' ;;
    wrong-attempt) mutation='.runAttempt = 2' ;;
    wrong-signer) mutation='.workflowSignerSha = ("f" * 40)' ;;
    wrong-nonce) mutation='.artifactNonce = ("f" * 32)' ;;
    wrong-name) mutation='.receipts[0].artifactName = "managed-evidence-seal-receipt-linux-x86_64-wrong"' ;;
  esac
  assert_code "$case_name" artifact-api-mismatch "$(jq "$mutation" <<<"$valid")"
done

# A fractional identifier passes the retained cross-field jq checks but is not
# an integer. The authoritative receiptDigestTransport schema must reject it
# after extraction and before the collector can accept the transport.
assert_code fractional-artifact-id artifact-api-mismatch "$(jq '.receipts[0].artifactId = 3.5' <<<"$valid")"

# The collector's schema source is the trusted anchor in production. This
# isolated anchor fixture proves that a changed authoritative definition is
# consumed instead of a copied transport shape being accepted.
anchor_fixture=$tmp/anchor-checkout/.constitution/tech-spec/contracts
mkdir -p "$anchor_fixture"
cp -- "$RECEIPT_TRANSPORT_SCHEMA" "$anchor_fixture/ci-evidence.schema.json"
jq '."$defs".receiptDigestTransport.properties.schemaVersion.const = 2' \
  "$anchor_fixture/ci-evidence.schema.json" >"$anchor_fixture/schema.next"
mv -- "$anchor_fixture/schema.next" "$anchor_fixture/ci-evidence.schema.json"
RECEIPT_TRANSPORT_SCHEMA=$anchor_fixture/ci-evidence.schema.json
assert_code authoritative-schema-mutation artifact-api-mismatch "$valid"
RECEIPT_TRANSPORT_SCHEMA=$root/.constitution/tech-spec/contracts/ci-evidence.schema.json

# ID/name correspondence is deliberately checked against each receipt's one
# matching run-inventory REST object in receipt_role, after the transport has
# passed its own syntax and identity validation.
wrong_id=$(jq '.receipts[0].artifactId = 99' <<<"$valid")
make_archive "$wrong_id"
transport=$(receipt_digest_transport "$inventory" "$tmp/wrong-id.json" | jq -c '.transport')
receipt_artifact=$(jq -cn --arg nonce "$nonce" '{id:3,name:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),digest:("sha256:" + ("a" * 64))}')
! jq -e --argjson entry "$(jq -c '.receipts[0]' <<<"$transport")" '.id == $entry.artifactId and .name == $entry.artifactName' <<<"$receipt_artifact" >/dev/null

# The receipt action digest is intentionally checked against its matching REST
# artifact in receipt_role. This focused assertion pins that typed comparison.
wrong_digest=$(jq '.receipts[0].uploadActionDigest = ("b" * 64)' <<<"$valid")
make_archive "$wrong_digest"
transport=$(receipt_digest_transport "$inventory" "$tmp/wrong-digest.json" | jq -c '.transport')
receipt_artifact=$(jq -cn --arg nonce "$nonce" '{id:3,name:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),digest:("sha256:" + ("a" * 64))}')
! artifact_observation "$receipt_artifact" "$(jq -r '.receipts[0].uploadActionDigest' <<<"$transport")"

# Corruption and a substituted valid ZIP both fail on the raw archive hash,
# before ZIP member listing or JSON parsing. REST state mismatches stay typed.
cp "$tmp/transport.zip" "$tmp/corrupt.zip"
printf x >>"$tmp/corrupt.zip"
fixture_archive=$tmp/corrupt.zip
set +e; receipt_digest_transport "$inventory" "$tmp/corrupt.json" >/dev/null; status=$?; set -e
[[ $status == 1 && $receipt_transport_rejection_code == artifact-corrupt ]]
make_archive "$(jq '.workflowRunId = 3' <<<"$valid")"
cp "$tmp/transport.zip" "$tmp/substitute.zip"
make_archive "$valid"
fixture_archive=$tmp/substitute.zip
set +e; receipt_digest_transport "$inventory" "$tmp/substitute.json" >/dev/null; status=$?; set -e
[[ $status == 1 && $receipt_transport_rejection_code == artifact-corrupt ]]
fixture_archive=
for rest_mutation in '.id = 12' '.workflow_run.id = 9' '.workflow_run.repository_id = 9' '.name = "wrong"' '.expired = true'; do
  make_archive "$valid"
  fixture_rest=$(jq "$rest_mutation" <<<"$fixture_rest")
  set +e; receipt_digest_transport "$inventory" "$tmp/rest.json" >/dev/null; status=$?; set -e
  [[ $status == 1 && $receipt_transport_rejection_code == artifact-api-mismatch ]]
done

printf 'receipt digest transport tests passed\n'
