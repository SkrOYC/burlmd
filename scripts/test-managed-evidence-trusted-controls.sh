#!/usr/bin/env bash
# Mutation coverage for the contract-owned trusted-control surface. The
# production launcher must reject every listed control file when either bytes
# or executable mode diverges from the trust anchor.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
if [[ ${BURLMD_TRUSTED_CONTROL_LOCKED_SHELL:-} != 1 ]]; then
  exec "$root/scripts/ci-devenv.sh" env BURLMD_TRUSTED_CONTROL_LOCKED_SHELL=1 "$0" "$@"
fi
contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
tmp=$(mktemp -d "${TMPDIR:-/tmp}/managed-evidence-trusted-controls.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
repo=$tmp/repo
mkdir -p "$repo"
cp -- "$contract" "$tmp/anchor-contract.toml"

command -v taplo >/dev/null || { echo 'locked taplo is required for trusted-control mutations' >&2; exit 2; }
mapfile -t paths < <(
  taplo get --file-path "$contract" --output-format json ci_bootstrap.trust_anchor.trusted_control_paths |
    jq -er '.[] | strings'
)
(( ${#paths[@]} > 0 ))
[[ ${#paths[@]} == 35 ]] || { echo "trusted-control inventory must contain 35 paths, found ${#paths[@]}" >&2; exit 1; }
for raw38_control in scripts/supervise-linux-session.sh scripts/managed-sway.conf; do
  [[ $(printf '%s\n' "${paths[@]}" | rg -Fxc -- "$raw38_control") == 1 ]] || {
    echo "raw-38 trusted-control addition is missing, duplicated, or substituted: $raw38_control" >&2
    exit 1
  }
done
[[ $(stat -Lc '%a' -- "$root/scripts/supervise-linux-session.sh") == 755 ]] || { echo 'raw-38 supervisor mode must be 0755' >&2; exit 1; }
[[ $(stat -Lc '%a' -- "$root/scripts/managed-sway.conf") == 644 ]] || { echo 'raw-38 Sway configuration mode must be 0644' >&2; exit 1; }
for path in "${paths[@]}"; do
  [[ -f $root/$path && ! -L $root/$path ]] || { echo "authoritative trusted control is not a regular file: $path" >&2; exit 1; }
  # Collection never deletes GitHub artifacts. Scan the complete authoritative
  # inventory, rather than only the launcher, so a future trusted helper
  # cannot add a deletion request outside the fake API fixture's call paths.
  if rg -n -i -- '(-X[[:space:]]+DELETE|--request[[:space:]]+DELETE|actions/artifacts[^[:space:]]*.*DELETE|DELETE.*actions/artifacts)' "$root/$path"; then
    echo "trusted control contains an artifact-deletion endpoint: $path" >&2
    exit 1
  fi
  mkdir -p "$repo/$(dirname "$path")"
  cp -- "$root/$path" "$repo/$path"
done

git -C "$repo" init -q
git -C "$repo" config user.email fixture@example.invalid
git -C "$repo" config user.name fixture
git -C "$repo" add .
git -C "$repo" commit -qm anchor
anchor=$(git -C "$repo" rev-parse HEAD)

functions=$tmp/trusted-controls-functions.sh
awk '/^read_trusted_control_paths\(\)/ {copy=1} /^workflow_guard\(\)/ {copy=0} copy {print}' \
  "$root/scripts/managed-evidence.sh" >"$functions"
[[ -s $functions ]]
(
  cd "$repo"
  CONTRACT=$tmp/anchor-contract.toml
  anchor_root=$repo
  source "$functions"
  for path in "${paths[@]}"; do
    git checkout -q --detach "$anchor"
    printf '\nfixture mutation\n' >>"$path"
    git add -- "$path"
    git commit -qm "mutate $path"
    candidate=$(git rev-parse HEAD)
    if trusted_controls_equivalent "$anchor" "$candidate"; then
      echo "trusted control byte mutation was accepted: $path" >&2
      exit 1
    fi
  done

  # The object-mode comparison is a separate contract obligation from byte
  # equivalence. Toggle a script's executable bit without changing its blob.
  git checkout -q --detach "$anchor"
  chmod 644 scripts/managed-evidence.sh
  git add -- scripts/managed-evidence.sh
  git commit -qm 'mutate trusted control mode'
  if trusted_controls_equivalent "$anchor" "$(git rev-parse HEAD)"; then
    echo 'trusted control mode mutation was accepted' >&2
    exit 1
  fi

  # Raw-38 adds one executable controller and one non-executable config to the
  # trusted inventory. Each must independently reject a mode-only mutation;
  # the byte loop above already mutates every listed member including both.
  for path in scripts/supervise-linux-session.sh scripts/managed-sway.conf; do
    git checkout -q --detach "$anchor"
    if [[ $path == scripts/supervise-linux-session.sh ]]; then chmod 644 "$path"; else chmod 755 "$path"; fi
    git add -- "$path"
    git commit -qm "mutate raw-38 trusted control mode $path"
    if trusted_controls_equivalent "$anchor" "$(git rev-parse HEAD)"; then
      echo "raw-38 trusted control mode mutation was accepted: $path" >&2
      exit 1
    fi
  done
)

source_guard=$(sed -n '/^source_guard()/,/^completion_guard()/p' "$root/scripts/managed-evidence.sh")
grep -Fq 'trusted_controls_equivalent "$anchor" "$workflow_signer" "$tested"' <<<"$source_guard"
# Bootstrap identity is deliberately stricter than a normal ancestor range.
# Model the reviewed M015 base followed by every BURL-M003 commit and prove
# the final trust anchor accepts that whole range but rejects an older base.
identity_functions=$tmp/m003-identity-functions.sh
awk '/^burl_m003_identity_guard\(\)/,/^completion_guard\(\)/ { if ($0 !~ /^completion_guard\(\)/) print }' "$root/scripts/managed-evidence.sh" >"$identity_functions"
(
  cd "$repo"
  git checkout -q --detach "$anchor"
  pre_m015=$(git rev-parse HEAD)
  printf 'm015\n' > reviewed-base
  git add reviewed-base
  git commit -qm 'reviewed BURL-M015 milestone'
  base=$(git rev-parse HEAD)
  # Root consolidates the BURL-M003 implementation before review, so the
  # complete reviewed range is exactly this one final trust-anchor commit.
  printf 'm003 implementation\n' > m003-one
  printf 'm003 fixture\n' > m003-two
  git add m003-one m003-two
  git commit -qm 'BURL-M003 reviewed trust-anchor tip'
  anchor=$(git rev-parse HEAD)
  tested=$anchor
  workflow_signer=$anchor
  anchor_root=$repo
  source "$identity_functions"
  burl_m003_identity_guard
  [[ $(git rev-list --ancestry-path "$base..$anchor" | wc -l) == 1 ]]
  base=$pre_m015
  if burl_m003_identity_guard; then
    echo 'BURL-M003 accepted a non-parent base' >&2
    exit 1
  fi
)

# Completion is a second, evidence-only authorization boundary. Exercise it in
# a tiny Git remote so the production guard resolves the committed aggregate,
# rather than trusting a working-tree fixture or a freeform completion note.
completion_repo=$tmp/completion-repo
completion_remote=$tmp/completion-remote.git
mkdir -p "$completion_repo"
git init --bare -q "$completion_remote"
git -C "$completion_repo" init -q
git -C "$completion_repo" config user.email fixture@example.invalid
git -C "$completion_repo" config user.name fixture
mkdir -p "$completion_repo/.constitution/tech-spec/contracts"
cp -- "$contract" "$completion_repo/.constitution/tech-spec/contracts/provisional-spikes.toml"
printf 'anchor\n' >"$completion_repo/anchor"
git -C "$completion_repo" add .
git -C "$completion_repo" commit -qm anchor
git -C "$completion_repo" branch -M master
git -C "$completion_repo" remote add origin "$completion_remote"
git -C "$completion_repo" push -q -u origin master
completion_anchor=$(git -C "$completion_repo" rev-parse HEAD)

completion_functions=$tmp/completion-functions.sh
{
  awk '/^profile_for\(\)/ {copy=1} /^bootstrap_allowlist\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^completion_field\(\)/ {copy=1} /^identity_hashes\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
} >"$completion_functions"
(
  cd "$completion_repo"
  source "$completion_functions"
  ROLES=(linux-x86_64 macos-26-arm64 macos-15-arm64)
  CONTRACT=$completion_repo/.constitution/tech-spec/contracts/provisional-spikes.toml
  AGGREGATE_SCHEMA=$completion_repo/unused-schema.json
  validate_schema() { return 0; }
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
  tmp=$tmp/completion-scratch; mkdir -p "$tmp"
  anchor_root=$completion_repo
  anchor=$completion_anchor
  ticket=BURL-H001

  profile_json() {
    local profiles='{}' role profile
    for role in "${ROLES[@]}"; do
      profile=$(profile_for BURL-M003 "$role")
      profiles=$(jq -cn --argjson prior "$profiles" --arg role "$role" --argjson profile "$profile" '$prior + {($role): $profile}')
    done
    printf '%s\n' "$profiles"
  }
  write_valid_evidence() {
    local evidence=.constitution/evidence/BURL-M003 profiles report_sha report_bytes completion_sha completion_bytes
    mkdir -p "$evidence"
    profiles=$(profile_json)
    jq -cn --arg anchor "$anchor" --argjson profiles "$profiles" '
      {status:"accepted",expectedIdentity:{ticketIdentity:"BURL-M003",trustAnchorSha:$anchor,testedSourceSha:$anchor,workflowSignerSha:$anchor,workflowSignerRef:"refs/heads/master",runIdentity:"managed:0123456789abcdef0123456789abcdef",requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredEvidenceClasses:$profiles}}
    ' >"$evidence/managed-evidence.json"
    refresh_completion
    report_sha=$(sha256_file "$evidence/managed-evidence.json")
    completion_sha=$(sha256_file "$evidence/completion.md")
    report_bytes=$(wc -c <"$evidence/managed-evidence.json")
    completion_bytes=$(wc -c <"$evidence/completion.md")
    printf 'owner: BURL-M003\nmode: contract_test\nproduced:\n  date: 2026-09-06\n  commit: %s\n  command: fixture\nfiles:\n  - path: .constitution/evidence/BURL-M003/managed-evidence.json\n    sha256: %s\n    bytes: %s\n  - path: .constitution/evidence/BURL-M003/completion.md\n    sha256: %s\n    bytes: %s\n' "$anchor" "$report_sha" "$report_bytes" "$completion_sha" "$completion_bytes" >"$evidence/manifest.yaml"
  }
  refresh_completion() {
    local evidence=.constitution/evidence/BURL-M003 report_sha
    report_sha=$(sha256_file "$evidence/managed-evidence.json")
    printf 'ticketIdentity: BURL-M003\ntrustAnchorSha: %s\nworkflowSignerSha: %s\ntestedSourceSha: %s\nrunIdentity: managed:0123456789abcdef0123456789abcdef\nreport: .constitution/evidence/BURL-M003/managed-evidence.json\nreportSha256: %s\nimplementationPullRequest: https://github.com/SkrOYC/burlmd/pull/15\nimplementationReview: https://github.com/SkrOYC/burlmd/pull/15\nevidencePullRequest: https://github.com/SkrOYC/burlmd/pull/16\nevidenceReview: https://github.com/SkrOYC/burlmd/pull/16\nacceptance: independently-reviewed-and-merged\n' "$anchor" "$anchor" "$anchor" "$report_sha" >"$evidence/completion.md"
  }
  refresh_manifest() {
    local evidence=.constitution/evidence/BURL-M003 report_sha report_bytes completion_sha completion_bytes
    report_sha=$(sha256_file "$evidence/managed-evidence.json")
    completion_sha=$(sha256_file "$evidence/completion.md")
    report_bytes=$(wc -c <"$evidence/managed-evidence.json")
    completion_bytes=$(wc -c <"$evidence/completion.md")
    printf 'owner: BURL-M003\nmode: contract_test\nproduced:\n  date: 2026-09-06\n  commit: %s\n  command: fixture\nfiles:\n  - path: .constitution/evidence/BURL-M003/managed-evidence.json\n    sha256: %s\n    bytes: %s\n  - path: .constitution/evidence/BURL-M003/completion.md\n    sha256: %s\n    bytes: %s\n' "$anchor" "$report_sha" "$report_bytes" "$completion_sha" "$completion_bytes" >"$evidence/manifest.yaml"
  }
  publish_fixture() {
    git reset --hard -q "$anchor"
    write_valid_evidence
    "$@"
    git add .
    git commit -qm fixture-completion
    git push -q --force origin HEAD:master
  }
  assert_completion_rejected() {
    local name=$1
    if completion_guard; then
      echo "completion fixture unexpectedly accepted: $name" >&2
      exit 1
    fi
  }
  mutate_minimal_report() {
    printf '{}\n' >.constitution/evidence/BURL-M003/managed-evidence.json
    refresh_completion
    refresh_manifest
  }
  mutate_wrong_role_profile() {
    jq '.expectedIdentity.requiredEvidenceClasses = {}' .constitution/evidence/BURL-M003/managed-evidence.json >report.next
    mv report.next .constitution/evidence/BURL-M003/managed-evidence.json
    refresh_completion
    refresh_manifest
  }
  mutate_missing_acceptance() {
    grep -v '^acceptance: ' .constitution/evidence/BURL-M003/completion.md >completion.next
    mv completion.next .constitution/evidence/BURL-M003/completion.md
    refresh_manifest
  }
  mutate_extra_manifest_member() {
    printf '  - path: .constitution/evidence/BURL-M003/forged.json\n    sha256: %064d\n    bytes: 0\n' 0 >>.constitution/evidence/BURL-M003/manifest.yaml
  }
  mutate_bad_manifest_digest() {
    sed -i 's/^    sha256: .*/    sha256: deadbeef/' .constitution/evidence/BURL-M003/manifest.yaml
  }
  mutate_bad_manifest_size() {
    sed -i 's/^    bytes: .*/    bytes: 999999/' .constitution/evidence/BURL-M003/manifest.yaml
  }
  mutate_out_of_scope_commit() { printf forged >out-of-scope; }

  publish_fixture :
  completion_guard || { echo 'valid completion fixture was rejected' >&2; exit 1; }

  publish_fixture mutate_minimal_report
  assert_completion_rejected minimal-report
  publish_fixture mutate_wrong_role_profile
  assert_completion_rejected wrong-role-profile
  publish_fixture mutate_missing_acceptance
  assert_completion_rejected missing-acceptance
  publish_fixture mutate_extra_manifest_member
  assert_completion_rejected extra-manifest-member
  publish_fixture mutate_bad_manifest_digest
  assert_completion_rejected bad-manifest-digest
  publish_fixture mutate_bad_manifest_size
  assert_completion_rejected bad-manifest-size
  publish_fixture mutate_out_of_scope_commit
  assert_completion_rejected out-of-scope-commit
)
printf 'managed-evidence trusted-control mutation fixture passed\n'
