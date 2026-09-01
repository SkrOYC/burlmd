#!/usr/bin/env bash
# Run only in the caller's authenticated staging job. The macOS 15 candidate
# receives the resulting directory as data; it never downloads or copies a
# producer bundle itself.
set -euo pipefail
expected= nonce= bundle= output= receipt=
while (($#)); do
  case $1 in
    --expected) expected=${2:-}; shift 2;; --nonce) nonce=${2:-}; shift 2;;
    --bundle) bundle=${2:-}; shift 2;; --output) output=${2:-}; shift 2;;
    --receipt) receipt=${2:-}; shift 2;; *) exit 2;;
  esac
done
[[ -f $expected && -f $bundle && -f $receipt && $nonce =~ ^[0-9a-f]{32}$ && -n $output && ! -e $output ]] || exit 2
jq -e --arg nonce "$nonce" '.ticketIdentity == "PKG-M001" and .runIdentity == ("managed:" + $nonce) and .artifactNonce == $nonce' "$expected" >/dev/null || exit 1
"$(dirname "$0")/validate-sealing-receipt.sh" "$receipt"
jq -e --arg nonce "$nonce" --arg digest "$(sha256sum "$expected" | awk '{print $1}')" '
  .role == "macos-26-arm64" and .artifactNonce == $nonce and .expectedIdentitySha256 == $digest
' "$receipt" >/dev/null || exit 1
[[ $(sha256sum "$bundle" | awk '{print $1}') == $(jq -er '.sealedBundleSha256' "$receipt") ]] || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-stage-role.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
mapfile -t outer < <(tar --zstd -tf "$bundle")
[[ ${#outer[@]} == 1 && ${outer[0]} == ci-role-evidence.tar.zst ]] || exit 1
tar --zstd -xf "$bundle" -C "$tmp" --no-same-owner --no-same-permissions
[[ $(sha256sum "$tmp/ci-role-evidence.tar.zst" | awk '{print $1}') == $(jq -er '.roleBundleSha256' "$receipt") ]] || exit 1
"$(dirname "$0")/validate-managed-role-bundle.sh" --expected "$expected" --role macos-26-arm64 --nonce "$nonce" --bundle "$tmp/ci-role-evidence.tar.zst"
mkdir -p "$tmp/stage/roles/macos-26-arm64"
mkdir "$tmp/inner"
tar --zstd -xf "$tmp/ci-role-evidence.tar.zst" -C "$tmp/inner"
for member in handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256; do
  jq -e --arg member "$member" '.roleEvidence.internalArtifacts | any(.name == $member)' "$tmp/inner/ci-role-evidence.json" >/dev/null || exit 1
  [[ -f $tmp/inner/$member && ! -L $tmp/inner/$member ]] || exit 1
  # Preserve the contract-declared member path. The macOS 15 role runner
  # imports the authenticated stage by that exact path, so flattening it would
  # silently discard the interface boundary after validation.
  mkdir -p "$tmp/stage/roles/macos-26-arm64/$(dirname "$member")"
  install -m 0444 "$tmp/inner/$member" "$tmp/stage/roles/macos-26-arm64/$member"
done
# Preserve a compact, immutable audit trail with the staged bytes.  The
# consumer does not use it as an authority; it lets the coordinator connect the
# fixed handoff directory to the separately attested seal receipt without
# adding unverified producer data to the consumer manifest.
jq -cn --arg receiptSha256 "$(sha256sum "$receipt" | awk '{print $1}')" --slurpfile receipt "$receipt" '
  {schemaVersion:1,interface:"authenticated-producer-stage-v1",producerRole:"macos-26-arm64",sealingReceiptSha256:$receiptSha256,sealingCheckRunId:$receipt[0].sealingCheckRunId,workflowRunId:$receipt[0].workflowRunId,runAttempt:$receipt[0].runAttempt,artifactNonce:$receipt[0].artifactNonce,roleBundleSha256:$receipt[0].roleBundleSha256,sealedBundleSha256:$receipt[0].sealedBundleSha256}
' >"$tmp/stage/stage-provenance.json"
chmod 0444 "$tmp/stage/stage-provenance.json"
mv -- "$tmp/stage" "$output"
