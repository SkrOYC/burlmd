#!/usr/bin/env bash
# Exercise the real collector's four independent candidate guard outcomes.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-candidate-guards.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
functions=$tmp/functions.sh
awk '/^role_guard_for\(\)/,/^}/ {print} /^caller_job_id_for\(\)/,/^}/ {print} /^candidate_reject\(\)/,/^}/ {print} /^candidate_observation\(\)/,/^}/ {print}' "$root/scripts/managed-evidence.sh" >"$functions"
source "$functions"
anchor_root=$root
run_id=42
guards=$(jq -cn --argjson linux "$(role_guard_for linux-x86_64)" --argjson macos26 "$(role_guard_for macos-26-arm64)" --argjson macos15 "$(role_guard_for macos-15-arm64)" '{"linux-x86_64":$linux,"macos-26-arm64":$macos26,"macos-15-arm64":$macos15}')
jq -cn --argjson guards "$guards" '{requiredRoleGuards:$guards}' >"$tmp/expected.json"
expected=$tmp/expected.json
valid_jobs() {
  jq -cn '
    def job($id; $name; $label): {
      id:$id,
      check_run_url:("https://api.github.test/check-runs/" + (($id + 100) | tostring)),
      run_id:42,
      status:"completed",
      conclusion:"success",
      name:$name,
      labels:[$label]
    };
    {jobs:[
      job(1; "linux / candidate"; "ubuntu-24.04"),
      job(2; "linux / seal"; "ubuntu-24.04"),
      job(3; "macos_26 / candidate"; "macos-26"),
      job(4; "macos_26 / seal"; "macos-26"),
      job(5; "macos_15 / candidate"; "macos-15"),
      job(6; "macos_15 / seal"; "macos-15")
    ]}
  '
}
assert_code() {
  local expected_code=$1 role=$2 jobs=$3 jobs_file=$tmp/jobs.json rejection_channel ignored
  rejection_channel=$tmp/rejection-$expected_code.txt
  printf '%s\n' "$jobs" >"$jobs_file"
  rm -f -- "$rejection_channel"
  # The receipt validator captures this function with command substitution.
  # Prove the typed code travels through the parent-owned channel instead of
  # relying on a shell variable that Bash discards at that boundary.
  if ignored=$(candidate_observation "$jobs_file" "$role" "$rejection_channel"); then
    echo "accepted candidate mutation: $expected_code" >&2; exit 1
  fi
  [[ $(<"$rejection_channel") == "$expected_code" ]] || { echo "observed $(<"$rejection_channel"), expected $expected_code" >&2; exit 1; }
  printf '%s\n' "$(<"$rejection_channel")"
}
valid=$(valid_jobs)
printf '%s\n' "$valid" >"$tmp/jobs.json"
for selection in \
  'linux-x86_64 1 101' \
  'macos-26-arm64 3 103' \
  'macos-15-arm64 5 105'; do
  read -r role job_id check_id <<<"$selection"
  candidate_observation "$tmp/jobs.json" "$role" >"$tmp/$role.json"
  jq -e --argjson job_id "$job_id" --argjson check_id "$check_id" '
    (has("runnerEnvironment") | not) and
    (has("hostedOriginVerified") | not) and
    .jobId == $job_id and .checkRunId == $check_id and
    .placementFixedByTrustedWorkflow and .topologyVerified and
    .labelVerified and .completionVerified
  ' "$tmp/$role.json" >/dev/null
done

# Mutate one outcome at a time, with the other two candidates and all seals
# present, so cross-role REST names cannot satisfy the selected role.
assert_code candidate-placement-mismatch linux-x86_64 "$(jq '(.jobs[] | select(.name == "linux / candidate") | .name) = "other / candidate"' <<<"$valid")"
assert_code candidate-placement-mismatch linux-x86_64 "$(jq '.jobs += [.jobs[] | select(.name == "linux / candidate")]' <<<"$valid")"
assert_code candidate-placement-mismatch linux-x86_64 "$(jq '(.jobs[] | select(.name == "linux / candidate") | .name) = "macos_26 / candidate"' <<<"$valid")"

duplicate_caller_anchor=$tmp/duplicate-caller-anchor
mkdir -p "$duplicate_caller_anchor/.github/workflows"
cp "$root/.github/workflows/ci.yml" "$duplicate_caller_anchor/.github/workflows/ci.yml"
cp "$root/.github/workflows/ci-role-linux-x86-64.yml" "$duplicate_caller_anchor/.github/workflows/ci-role-linux-x86-64.yml"
printf '\n  linux_duplicate:\n    uses: ./.github/workflows/ci-role-linux-x86-64.yml\n' >>"$duplicate_caller_anchor/.github/workflows/ci.yml"
anchor_root=$duplicate_caller_anchor
assert_code candidate-placement-mismatch linux-x86_64 "$valid"
anchor_root=$root

topology_anchor=$tmp/topology-anchor
mkdir -p "$topology_anchor/.github/workflows"
cp "$root/.github/workflows/ci.yml" "$topology_anchor/.github/workflows/ci.yml"
cp "$root/.github/workflows/ci-role-linux-x86-64.yml" "$topology_anchor/.github/workflows/ci-role-linux-x86-64.yml"
sed -i 's/^    needs: candidate$/    needs: different-job/' "$topology_anchor/.github/workflows/ci-role-linux-x86-64.yml"
anchor_root=$topology_anchor
assert_code candidate-topology-mismatch linux-x86_64 "$valid"
anchor_root=$root

assert_code candidate-label-mismatch macos-26-arm64 "$(jq '(.jobs[] | select(.name == "macos_26 / candidate") | .labels) = ["wrong-label"]' <<<"$valid")"
assert_code candidate-completion-mismatch macos-15-arm64 "$(jq '(.jobs[] | select(.name == "macos_15 / candidate") | .conclusion) = "failure"' <<<"$valid")"
