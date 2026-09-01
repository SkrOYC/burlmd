#!/usr/bin/env bash
# Trusted macOS 26 seal helper.  It operates only on an already validated
# producer bundle and creates the two-member stage; it never runs its bytes.
set -euo pipefail
expected= sealed= nonce= check= output= github_output=
while (($#)); do
  case $1 in
    --expected) expected=$2; shift 2;; --sealed) sealed=$2; shift 2;;
    --nonce) nonce=$2; shift 2;; --sealing-check-run-id) check=$2; shift 2;;
    --output) output=$2; shift 2;; --github-output) github_output=$2; shift 2;;
    *) exit 2;;
  esac
done
[[ -f $expected && -f $sealed && $nonce =~ ^[0-9a-f]{32}$ && $check =~ ^[1-9][0-9]*$ && -n $output && ! -e $output && -n $github_output ]] || exit 2
jq -e --arg nonce "$nonce" '.ticketIdentity == "BURL-O001" and .artifactNonce == $nonce and .runIdentity == ("managed:" + $nonce)' "$expected" >/dev/null
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-compatibility-stage.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
tar --zstd -xf "$sealed" -C "$tmp"
[[ -f $tmp/ci-role-evidence.tar.zst ]] || exit 1
mkdir "$tmp/role"
tar --zstd -xf "$tmp/ci-role-evidence.tar.zst" -C "$tmp/role"
manifest=$tmp/role/ci-role-evidence.json
[[ -f $manifest ]] || exit 1
mkdir -p "$output/handoff/outbox"
members='[]'
for member in handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256; do
  [[ -f $tmp/role/$member && ! -L $tmp/role/$member ]] || exit 1
  bytes=$(wc -c < "$tmp/role/$member")
  digest=$(sha256sum "$tmp/role/$member" | awk '{print $1}')
  jq -e --arg name "$member" --arg digest "$digest" --argjson bytes "$bytes" '.roleEvidence.internalArtifacts[] | select(.name == $name and .sha256 == $digest and .bytes == $bytes)' "$manifest" >/dev/null
  install -m 0444 "$tmp/role/$member" "$output/$member"
  members=$(jq -cn --argjson old "$members" --arg name "$member" --argjson bytes "$bytes" --arg digest "$digest" '$old + [{name:$name,bytes:$bytes,sha256:$digest}]')
done
expected_digest=$(sha256sum "$expected" | awk '{print $1}')
jq -cn --slurpfile expected "$expected" --arg digest "$expected_digest" --argjson check "$check" --argjson members "$members" '
  {schemaVersion:1,ticketIdentity:"BURL-O001",expectedIdentitySha256:$digest,
   repositoryId:env.GITHUB_REPOSITORY_ID|tonumber,workflowRunId:env.GITHUB_RUN_ID|tonumber,
   runAttempt:env.GITHUB_RUN_ATTEMPT|tonumber,trustAnchorSha:$expected[0].trustAnchorSha,
   workflowSignerSha:$expected[0].workflowSignerSha,testedSourceSha:$expected[0].testedSourceSha,
   baseSha:$expected[0].baseSha,producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",
   producerSealingCheckRunId:$check,members:$members}' > "$output/compatibility-stage-manifest.json"
sha256sum "$output/compatibility-stage-manifest.json" | awk '{print $1}' > "$output/.manifest-sha256"
jq -cn --slurpfile manifest "$output/compatibility-stage-manifest.json" --arg name "managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce" --arg sha "$(<"$output/.manifest-sha256")" '{stageArtifact:{artifactId:0,artifactName:$name,uploadActionDigest:("0"*64),artifactDigest:("sha256:"+("0"*64)),createdAt:"",expiresAt:"",expired:false},stageManifest:$manifest[0],stageManifestSha256:$sha}' > "$output/producer-stage-binding.json"
printf 'artifact_name=managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-%s\n' "$nonce" >> "$github_output"
printf 'manifest_sha256=%s\nproducer_role=macos-26-arm64\nconsumer_role=macos-15-arm64\nproducer_workflow_signer_sha=%s\nworkflow_run_id=%s\nrun_attempt=%s\nattestation_subject_digest=sha256:%s\n' "$(<"$output/.manifest-sha256")" "$(jq -r .workflowSignerSha "$expected")" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$(<"$output/.manifest-sha256")" >> "$github_output"
