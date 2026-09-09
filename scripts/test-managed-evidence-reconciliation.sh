#!/usr/bin/env bash
# Exercise collector reconciliation against the exact contract-derived role
# multiplicities and image tuples. The production collector is intentionally
# not sourceable, so extract only the pure reconciliation definitions.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/managed-evidence-reconciliation-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

functions=$tmp/reconciliation-functions.sh
{
  awk '/^profile_for\(\)/ {copy=1} /^bootstrap_allowlist\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^role_label\(\)/ { print; exit }' "$root/scripts/managed-evidence.sh"
  awk '/^spike_id_for_ticket\(\)/ {copy=1} /^spike_field\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^spike_commands\(\)/ {copy=1} /^validate_spike_result\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
  awk '/^validate_spike_result\(\)/,/^rfc3339_calendar_valid\(\)/ { if ($0 !~ /^rfc3339_calendar_valid\(\)/) print }' "$root/scripts/managed-evidence.sh"
  awk '/^validate_schema\(\)/,/^derive_receipt_digest_transport_schema\(\)/ { if ($0 !~ /^derive_receipt_digest_transport_schema\(\)/) print }' "$root/scripts/managed-evidence.sh"
  awk '/^rfc3339_calendar_valid\(\)/ {copy=1} /^run_spike_coordinator\(\)/ {copy=0} copy {print}' "$root/scripts/managed-evidence.sh"
} >"$functions"
source "$functions"

CONTRACT=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
RESULT_SCHEMA=$root/.constitution/tech-spec/contracts/spike-result.schema.json
RESULT_SCHEMA_VERSION=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$RESULT_SCHEMA")
CONTRACT_RESULT_SCHEMA_VERSION=$(awk -F ' = ' '$1 == "result_schema_version" {print $2; exit}' "$CONTRACT")
[[ $RESULT_SCHEMA_VERSION == 21 && $CONTRACT_RESULT_SCHEMA_VERSION == "$RESULT_SCHEMA_VERSION" ]]
tested=0123456789012345678901234567890123456789
hex=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

make_expected() {
  local ticket=$1 profiles='{}' role profile
  for role in linux-x86_64 macos-26-arm64 macos-15-arm64; do
    profile=$(profile_for "$ticket" "$role")
    profiles=$(jq -cn --argjson old "$profiles" --arg role "$role" --argjson profile "$profile" '$old + {($role): $profile}')
  done
  expected=$tmp/expected-$ticket.json
  jq -cn --arg ticket "$ticket" --argjson profiles "$profiles" '
    {
      ticketIdentity: $ticket,
      requiredRoleIdentities: ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"],
      requiredEvidenceClasses: $profiles
    }
  ' >"$expected"
}

make_roles() {
  roles=$(jq -cn --slurpfile expected "$expected" '
    $expected[0].requiredRoleIdentities
    | map(. as $role | {
        manifest: {
          roleEvidence: {
            role: $role,
            environment: {
              imageOS: ("fixture-" + $role + "-os"),
              imageVersion: ("fixture-" + $role + "-version")
            }
          }
        }
      })
  ')
}

make_result() {
  local ticket=$1 required_roles candidates gates
  spike_id=$(spike_id_for_ticket "$ticket")
  required_roles=$(toml_required_run_roles | jq -Rsc 'split("\n") | map(select(length > 0))')
  candidates=$(spike_toml_list "$spike_id" candidates)
  gates=$(spike_toml_list "$spike_id" required_gates)
  result=$tmp/$ticket-results.json
  jq -cn --arg spike "$spike_id" --arg tested "$tested" --arg hash "$hex" --argjson schema_version "$RESULT_SCHEMA_VERSION" --argjson required_roles "$required_roles" --argjson candidates "$candidates" --argjson gates "$gates" --slurpfile expected "$expected" --argjson manifests "$roles" '
    def authenticated_role($role):
      if $role == "linux-x86_64" or ($role | startswith("linux-")) then "linux-x86_64"
      elif $role == "macos-26-arm64" or ($role | startswith("macos-26-")) or ($role | startswith("macos-current-")) or ($role | startswith("macos-repeat-")) or ($role | startswith("macos-default-")) then "macos-26-arm64"
      else "macos-15-arm64" end;
    def runner_label($role):
      if $role == "linux-x86_64" then "ubuntu-22.04"
      elif $role == "macos-26-arm64" then "macos-26"
      else "macos-15" end;
    def image($role): $manifests[] | select(.manifest.roleEvidence.role == $role) | .manifest.roleEvidence.environment;
    {
      schemaVersion: $schema_version,
      spikeId: $spike,
      generatedAt: "2026-09-01T00:00:00Z",
      corpus: ["fixture"],
      candidates: ($candidates | map(capture("^(?<name>.*) (?<version>[^ ]+)$") + {configuration: {}})),
      gates: ($gates | map({candidate: $candidates[0], name: ., passed: true, evidence: ["fixture"]})),
      runs: [
        $required_roles | to_entries[]
        | .key as $index
        | .value as $result_role
        | authenticated_role($result_role) as $role
        | image($role) as $image
        | $expected[0].requiredEvidenceClasses[$role] as $classes
        | {
            id: ("fixture-run-" + ($index | tostring)),
            role: $result_role,
            claimedEvidenceClasses: $classes,
            inputContext: {
              repositoryRevision: $tested,
              repositoryTreeSha256: $hash,
              lockfiles: {"Cargo.lock": $hash},
              contractSha256: $hash,
              schemaSha256: $hash,
              probeSourceTreeSha256: $hash,
              probeBinarySha256: $hash,
              corpusManifestSha256: $hash
            },
            host: {
              hostFingerprint: $hash,
              os: "fixture-os",
              osVersion: "fixture-os-version",
              architecture: "fixture-architecture",
              filesystem: "fixture-filesystem",
              profile: {
                runnerLabel: runner_label($role),
                imageOS: $image.imageOS,
                imageVersion: $image.imageVersion,
                cpuModel: "fixture-cpu",
                logicalCpuCount: 4,
                memoryBytes: 16000000000,
                storageBytes: 14000000000,
                logicalViewportWidth: 1920,
                logicalViewportHeight: 1080,
                logicalViewportRefreshHz: 60,
                logicalViewportVerified: ($classes | any(. == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual")),
                capabilities: ["common-functional"]
              }
            },
            toolchain: {fixture: "1"},
            commandResults: [{command: "fixture", exitCode: 0, stdout: "", stderr: ""}],
            measurements: [{candidate: "fixture", name: "fixture", value: 1, unit: "count", samples: 1}],
            artifacts: [{path: ("fixture/" + ($index | tostring)), kind: "fixture", bytes: 0, sha256: $hash}]
          }
      ],
      recommendation: "fixture",
      unresolved: []
    }
  ' >"$result"
  validate_spike_result "$result" "$spike_id" || {
    printf 'generated fixture does not satisfy Spike-result schema version %s: %s\n' "$RESULT_SCHEMA_VERSION" "$ticket" >&2
    exit 1
  }
}

assert_accepted() {
  if ! reconcile_spike_result "$1"; then
    printf 'rejected a valid %s result: %s\n' "$ticket" "${spike_rejection_code:-none}" >&2
    exit 1
  fi
}

assert_rejected() {
  local expected_code=$1 file=$2
  if reconcile_spike_result "$file"; then
    printf 'accepted unsafe %s result\n' "$expected_code" >&2
    exit 1
  fi
  [[ ${spike_rejection_code:-} == "$expected_code" ]] || {
    printf 'rejected with %s, expected %s\n' "${spike_rejection_code:-none}" "$expected_code" >&2
    exit 1
  }
}

mutate_occurrence() {
  local input=$1 output=$2 result_role=$3 occurrence=$4 field=$5 id
  id=$(jq -er --arg role "$result_role" --argjson occurrence "$occurrence" '[.runs[] | select(.role == $role)][$occurrence].id' "$input")
  case "$field" in
    runner-label) jq --arg id "$id" '(.runs[] | select(.id == $id) | .host.profile.runnerLabel) = "wrong-runner"' "$input" >"$output" ;;
    claimed-class) jq --arg id "$id" '(.runs[] | select(.id == $id) | .claimedEvidenceClasses) = ["common-functional"]' "$input" >"$output" ;;
    image-version) jq --arg id "$id" '(.runs[] | select(.id == $id) | .host.profile.imageVersion) = "wrong-image-version"' "$input" >"$output" ;;
    image-os) jq --arg id "$id" '(.runs[] | select(.id == $id) | .host.profile.imageOS) = "wrong-image-os"' "$input" >"$output" ;;
    *) exit 2 ;;
  esac
}

# Every declared Spike must pass on exact contract-derived roles and profiles.
# The raw contract requires image compatibility only for performance or visual
# aggregation, so the other three Spikes prove that no invented universal
# image-equality policy applies.
for ticket in BURL-H001 BURL-H002 BURL-I001 BURL-L001 BURL-O001; do
  make_expected "$ticket"
  make_roles
  make_result "$ticket"
  assert_accepted "$result"
  bad_image=$tmp/$ticket-bad-image.json
  mutate_occurrence "$result" "$bad_image" "$(jq -r '.runs[0].role' "$result")" 0 image-version
  if jq -e 'any(.requiredEvidenceClasses[]; index("performance") != null or index("macos-authoritative-visual") != null)' "$expected" >/dev/null; then
    assert_rejected mixed-image-version "$bad_image"
  else
    assert_accepted "$bad_image"
  fi
done

# The production schema validator rejects the preceding Spike-result version.
ticket=BURL-H001
make_expected "$ticket"
make_roles
make_result "$ticket"
preceding_version_result=$tmp/preceding-version-result.json
jq '.schemaVersion = 20' "$result" >"$preceding_version_result"
if validate_spike_result "$preceding_version_result" "$spike_id" >/dev/null 2>&1; then
  echo 'the Spike-result validator accepted schema version 20' >&2
  exit 1
fi

# Exercise both captured image fields on a performance aggregation.
ticket=BURL-H001
make_expected "$ticket"
make_roles
make_result "$ticket"
bad_image_os=$tmp/ast-bad-image-os.json
mutate_occurrence "$result" "$bad_image_os" "$(jq -r '.runs[0].role' "$result")" 0 image-os
assert_rejected mixed-image-version "$bad_image_os"

# BURL-M003 has no coordinator result. It can assert compatibility only after
# all three independently measured role-manifest tuples are present.
ticket=BURL-M003
make_expected "$ticket"
make_roles
image_versions_compatible "$roles"
bad_ci_roles=$(jq '.[0].manifest.roleEvidence.environment.imageVersion = ""' <<<"$roles")
! image_versions_compatible "$bad_ci_roles"

# BURL-O001 repeats linux-installed-runtime twice and linux-runtime-candidate
# five times. Mutate early, middle, and final occurrences so no last-output
# jq behavior can hide a corrupt runner label or evidence-class claim.
ticket=BURL-O001
make_expected "$ticket"
make_roles
make_result "$ticket"
for mutation in \
  'linux-installed-runtime 0 runner-label runner-label-mismatch' \
  'linux-installed-runtime 1 claimed-class evidence-profile-mismatch' \
  'linux-runtime-candidate 0 runner-label runner-label-mismatch' \
  'linux-runtime-candidate 2 claimed-class evidence-profile-mismatch' \
  'linux-runtime-candidate 4 runner-label runner-label-mismatch'; do
  read -r result_role occurrence field code <<<"$mutation"
  mutated=$tmp/pkg-$result_role-$occurrence-$field.json
  mutate_occurrence "$result" "$mutated" "$result_role" "$occurrence" "$field"
  assert_rejected "$code" "$mutated"
done

printf 'managed-evidence reconciliation tests passed\n'
