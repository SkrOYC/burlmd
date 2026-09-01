#!/usr/bin/env bash
# Exercises the REST precondition separately from workflow actions: a failed
# candidate lookup must stop before the workflow can reach attestation/upload.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-seal-rest.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

sha=0123456789012345678901234567890123456789
digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
nonce=0123456789abcdef0123456789abcdef
jq -cn --arg nonce "$nonce" --arg sha "$sha" '
  {artifactNonce:$nonce,runIdentity:("managed:" + $nonce),workflowSignerSha:$sha,
   requiredRoleIdentities:["linux-x86_64"],requiredRoleSigners:{"linux-x86_64":
     {workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowSha:$sha}}}
' >"$tmp/expected.json"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case ${!#} in
  */actions/jobs/2) printf '%s\n' "$FAKE_JOB" ;;
  */actions/artifacts/1) printf '%s\n' "$FAKE_EXPECTED" ;;
  */actions/artifacts/3) printf '%s\n' "$FAKE_CANDIDATE" ;;
  */actions/artifacts/4) printf '%s\n' "$FAKE_SEALED" ;;
  */actions/artifacts/5) printf '%s\n' "$FAKE_RECEIPT" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

job() {
  jq -cn --arg sha "$sha" --argjson labels "$1" --arg conclusion "${2:-success}" '
    {id:2,run_id:99,head_sha:$sha,status:"completed",conclusion:$conclusion,
     name:"managed role / candidate",labels:$labels,
     check_run_url:"https://api.github.test/check-runs/2"}
  '
}
artifact() {
  jq -cn --arg name "$1" --arg digest "$digest" --arg sha "$sha" '
    {name:$name,digest:("sha256:" + $digest),expired:false,
     workflow_run:{id:99,head_sha:$sha}}
  '
}
base_env() {
  export GITHUB_REPOSITORY=SkrOYC/burlmd GITHUB_RUN_ID=99 GITHUB_RUN_ATTEMPT=1
  export GH_TOKEN=fixture-token GH_BIN="$tmp/bin/gh"
  export FAKE_JOB FAKE_EXPECTED FAKE_CANDIDATE FAKE_SEALED FAKE_RECEIPT
  FAKE_JOB=$(job '["ubuntu-24.04"]')
  FAKE_EXPECTED=$(artifact "managed-evidence-expected-$nonce")
  FAKE_CANDIDATE=$(artifact "managed-evidence-candidate-linux-x86_64-$nonce")
  FAKE_SEALED=$(artifact "managed-evidence-sealed-linux-x86_64-$nonce")
  FAKE_RECEIPT=$(artifact "managed-evidence-seal-receipt-linux-x86_64-$nonce")
}
precheck() {
  "$root/scripts/validate-seal-rest.sh" --phase candidate --role linux-x86_64 --nonce "$nonce" \
    --expected "$tmp/expected.json" --expected-id 1 --expected-digest "$digest" \
    --candidate-check-run-id 2 --candidate-id 3 --candidate-digest "$digest"
}
finalcheck() {
  "$root/scripts/validate-seal-rest.sh" --phase sealed --role linux-x86_64 --nonce "$nonce" \
    --expected "$tmp/expected.json" --expected-id 1 --expected-digest "$digest" \
    --candidate-check-run-id 2 --candidate-id 3 --candidate-digest "$digest" \
    --sealed-id 4 --sealed-digest "$digest" --receipt-id 5 --receipt-digest "$digest"
}
assert_rejected() {
  local label=$1
  if precheck >/dev/null 2>&1; then
    printf 'accepted unsafe candidate precheck: %s\n' "$label" >&2
    exit 1
  fi
}

base_env
precheck
finalcheck
base_env; FAKE_JOB=$(job '["ubuntu-24.04"]' failure); assert_rejected wrong-job
base_env; FAKE_JOB=$(job '["self-hosted","ubuntu-24.04"]'); assert_rejected self-hosted-label
base_env; FAKE_JOB=$(job '["macos-26"]'); assert_rejected wrong-label
base_env; FAKE_CANDIDATE=$(jq --arg bad "sha256:${digest%?}0" '.digest = $bad' <<<"$FAKE_CANDIDATE"); assert_rejected wrong-artifact-digest

printf 'seal REST pre-attestation fixture passed\n'
