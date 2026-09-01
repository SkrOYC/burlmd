#!/usr/bin/env bash
# Trusted seal-side validation of an untrusted inner role bundle.
set -euo pipefail
expected= role= nonce= bundle=
while (($#)); do
  case $1 in
    --expected) expected=$2; shift 2;; --role) role=$2; shift 2;; --nonce) nonce=$2; shift 2;; --bundle) bundle=$2; shift 2;;
    *) echo 'usage: validate-managed-role-bundle.sh --expected FILE --role ROLE --nonce HEX --bundle FILE' >&2; exit 2;;
  esac
done
[[ -f $expected && -f $bundle && $nonce =~ ^[0-9a-f]{32}$ ]] || exit 2
project_root=$(git rev-parse --show-toplevel)
role_schema=$project_root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json
contract=$project_root/.constitution/tech-spec/contracts/provisional-spikes.toml
role_schema_version=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$role_schema")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-role-validate.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
readonly max_bundle_bytes=$((64 * 1024 * 1024))
readonly max_member_bytes=$((32 * 1024 * 1024))
readonly max_total_bytes=$((48 * 1024 * 1024))
readonly max_members=256
safe_member_name() {
  local member=$1
  [[ $member != /* && $member != *$'\n'* && $member != *$'\r'* && $member != *'//' && $member != *'/./'* && $member != . && $member != */. && $member != .. && $member != ../* && $member != */../* && $member != */.. ]] || return 1
  # A role may export declared opaque handoff bytes for a later authenticated
  # stage.  They are evidence inputs, not a free-form archive escape hatch:
  # the manifest still owns their exact names, types, sizes, and hashes.
  [[ $member == ci-role-evidence.json || $member == runs/ || $member == runs/* || $member == logs/ || $member == logs/* || $member == artifacts/ || $member == artifacts/* || $member == results/ || $member == results/* || $member == handoff/ || $member == handoff/* ]] || return 1
}

role_pattern_for() {
  case $1 in
    linux-x86_64) printf '%s' '^linux';;
    macos-26-arm64) printf '%s' '^macos-(26|current|repeat|default)';;
    macos-15-arm64) printf '%s' '^macos-(15|previous)';;
    *) return 2;;
  esac
}

normalize_contract_path() {
  local raw=$1 segment joined= parts=()
  [[ $raw != /* && $raw != *'//' ]] || return 1
  IFS=/ read -r -a segments <<<"$raw"
  for segment in "${segments[@]}"; do
    case $segment in
      ''|.) ;;
      ..) ((${#parts[@]} > 0)) || return 1; unset "parts[$((${#parts[@]} - 1))]";;
      *$'\n'*|*$'\r'*) return 1;;
      *) parts+=("$segment");;
    esac
  done
  ((${#parts[@]} > 0)) || return 1
  (IFS=/; printf '%s' "${parts[*]}")
}

contract_output_specs() {
  local ticket=$1 requested_role=$2 role_pattern
  role_pattern=$(role_pattern_for "$requested_role") || return 1
  command -v taplo >/dev/null || { echo 'locked taplo is required to validate Spike bundle paths' >&2; return 1; }
  taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -r --arg id "SPK-$ticket" --arg pattern "$role_pattern" '
      .[] | select(.id == $id) | .path as $root | .verification_steps[] |
      select((has("run_role") | not) or (.run_role | test($pattern))) |
      select(has("requires_authenticated_stage_role") | not) |
      .workdir as $workdir | .command |
      scan("--(?:output|stdout|stderr|copy-artifact-to|success-marker|handoff-bundle|handoff-sha256|sha256-output|output-archive|append-run)[[:space:]]+([^[:space:]]+)")[0] |
      ["file", $root, $workdir, .] | @tsv
    '
  taplo get --file-path "$contract" --output-format json 'spikes[*]' |
    jq -r --arg id "SPK-$ticket" --arg pattern "$role_pattern" '
      .[] | select(.id == $id) | .path as $root | .verification_steps[] |
      select((has("run_role") | not) or (.run_role | test($pattern))) |
      select(has("requires_authenticated_stage_role") | not) |
      .workdir as $workdir | .command |
      scan("--output-dir[[:space:]]+([^[:space:]]+)")[0] |
      ["directory", $root, $workdir, .] | @tsv
    '
}

contract_allows_member() {
  local member=$1 ticket path kind ticket_root workdir output combined normalized root_normalized candidate
  ticket=$(jq -er '.ticketIdentity | strings' "$expected")
  # CI-M003 only exports trusted launcher records under results/. Its runtime
  # inventory is exact because the manifest owns every regular member.
  if [[ $ticket == CI-M003 ]]; then
    [[ $member == results/* ]]
    return
  fi
  # Hosted macOS has no universal process-containment guarantee. Its bounded
  # cleanup record is a mandatory, manifest-bound observation for every
  # non-CI macOS role, independent of which Spike output paths it produces.
  if [[ $member == results/macos-bounded-cleanup.json && ( $role == macos-26-arm64 || $role == macos-15-arm64 ) ]]; then
    return
  fi
  # The launcher, rather than the candidate contract command, owns raw
  # viewport observation bytes. They are permitted only for a role whose
  # authenticated profile actually requires exact viewport evidence; the
  # manifest's exact inventory then binds the JSON and the Flutter run log.
  if [[ $member == results/viewport-linux.json && $role == linux-x86_64 ]] || \
     [[ $member == results/viewport-macos.json || $member == results/viewport-macos-run.log ]] && [[ $role == macos-26-arm64 ]]; then
    jq -e --arg role "$role" '
      .requiredEvidenceClasses[$role] |
      any(.[]; . == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual")
    ' "$expected" >/dev/null
    return
  fi
  while IFS=$'\t' read -r kind ticket_root workdir output; do
    root_normalized=$(normalize_contract_path "$ticket_root") || return 1
    combined=$workdir/$output
    normalized=$(normalize_contract_path "$combined") || return 1
    [[ $normalized == "$root_normalized/"* ]] || return 1
    candidate=${normalized#"$root_normalized/"}
    case $kind in
      file) [[ $member == "$candidate" ]] && return 0;;
      directory) [[ $member == "$candidate/"* ]] && return 0;;
      *) return 1;;
    esac
  done < <(contract_output_specs "$ticket" "$role")
  return 1
}
bundle_bytes=$(wc -c <"$bundle")
(( bundle_bytes > 0 && bundle_bytes <= max_bundle_bytes )) || { echo 'role bundle exceeds the compressed size limit' >&2; exit 1; }
mapfile -t members < <(LC_ALL=C tar --zstd -tf "$bundle")
(( ${#members[@]} >= 2 && ${#members[@]} <= max_members )) || { echo 'role bundle has an invalid member count' >&2; exit 1; }
[[ ${members[0]} == ci-role-evidence.json ]] || { echo 'manifest must be first' >&2; exit 1; }
declare -A seen=()
for member in "${members[@]}"; do
  safe_member_name "$member" || { echo "unsafe or unexpected bundle member: $member" >&2; exit 1; }
  [[ -z ${seen[$member]+x} ]] || { echo "duplicate bundle member: $member" >&2; exit 1; }
  seen[$member]=1
done

# Inspect every header before extraction. The role bundle has only regular files
# plus the results directories that contain them; links and special files are
# never valid evidence members. GNU tar is supplied by the locked CI closure.
mapfile -t verbose < <(LC_ALL=C tar --zstd -tvf "$bundle")
(( ${#verbose[@]} == ${#members[@]} )) || { echo 'role bundle has an ambiguous tar inventory' >&2; exit 1; }
for index in "${!members[@]}"; do
  header=${verbose[$index]}
  case ${members[$index]} in
    */) [[ ${header:0:1} == d ]] || { echo "directory member is not a directory: ${members[$index]}" >&2; exit 1; } ;;
    *) [[ ${header:0:1} == - ]] || { echo "role bundle contains a non-regular member: ${members[$index]}" >&2; exit 1; } ;;
  esac
  member_bytes=$(awk '{print $3}' <<<"$header")
  [[ $member_bytes =~ ^[0-9]+$ ]] && (( member_bytes <= max_member_bytes )) || { echo "role bundle member exceeds size limit: ${members[$index]}" >&2; exit 1; }
done

# The owned empty destination and the prevalidated all-regular inventory make
# this extraction non-following. Validate again afterwards to guard tool quirks.
tar --zstd -xf "$bundle" -C "$tmp" --no-same-owner --no-same-permissions --no-overwrite-dir
[[ ! -L $tmp/ci-role-evidence.json && ! -L $tmp/results && ! -L $tmp/handoff ]] || { echo 'role bundle extracted a link' >&2; exit 1; }
if find "$tmp" -xdev -type l -print -quit | grep -q .; then
  echo 'role bundle extracted a symbolic link' >&2
  exit 1
fi
manifest="$tmp/ci-role-evidence.json"
[[ -f $manifest ]] || exit 1
# The seal must reject a structurally incomplete role manifest before it can
# package or attest any candidate bytes.  The schema lives in the immutable
# local trust-anchor checkout; do not permit a candidate-supplied registry or
# remote schema lookup to define this boundary.
command -v check-jsonschema >/dev/null 2>&1 || { echo 'locked check-jsonschema is required to validate role evidence' >&2; exit 1; }
check-jsonschema --schemafile "$role_schema" "$manifest" || { echo 'role manifest does not satisfy the trusted schema' >&2; exit 1; }
expected_sha=$(sha256sum "$expected" | awk '{print $1}')
jq -e --slurpfile expected "$expected" --arg expectedSha "$expected_sha" --arg role "$role" --arg nonce "$nonce" --argjson roleSchemaVersion "$role_schema_version" '
  .schemaVersion == $roleSchemaVersion and .expectedIdentity == $expected[0] and .expectedIdentitySha256 == $expectedSha and
  .expectedIdentity.runIdentity == ("managed:" + $nonce) and .expectedIdentity.artifactNonce == $nonce and
  .roleEvidence.role == $role and .roleEvidence.capturedIdentity.artifactNonce == $nonce and
  .roleEvidence.capturedIdentity == ($expected[0] | {ticketIdentity,releaseIdentity,trustAnchorSha,testedSourceSha,workflowSignerSha,workflowSignerRef,baseSha,workflowEvent,sourceWriteAllowlist,buildIdentity,corpusIdentity,runIdentity,artifactNonce} + {roleIdentity:$role}) and
  .roleEvidence.evidenceClasses == $expected[0].requiredEvidenceClasses[$role] and
  # evidenceClasses is an ordered profile copied from the trusted contract;
  # gates is an object, whose key iteration is deliberately unordered.  Keep
  # the former exact while treating the latter as the assigned set.
  ((.roleEvidence.gates | keys | sort) == ($expected[0].requiredEvidenceClasses[$role] | sort)) and
  all(.roleEvidence.gates[]; . == true)
' "$manifest" >/dev/null
mapfile -t declared < <(jq -r '.roleEvidence.internalArtifacts[].name' "$manifest")
(( ${#declared[@]} > 0 )) || exit 1
# This is a required trusted observation, not merely an allowed extra member:
# hosted-macOS role bundles must bind the bounded cleanup outcome that the
# fresh seal relies on when distinguishing untrusted candidate execution from
# seal authority. CI-M003 already has an exact results/ inventory of its own.
if [[ $(jq -r '.ticketIdentity' "$expected") != CI-M003 && ( $role == macos-26-arm64 || $role == macos-15-arm64 ) ]]; then
  jq -e 'any(.roleEvidence.internalArtifacts[]; .name == "results/macos-bounded-cleanup.json")' "$manifest" >/dev/null || {
    echo 'hosted-macOS role bundle omits bounded cleanup observation' >&2
    exit 1
  }
fi
declare -A declared_seen=()
total_bytes=0
for path in "${declared[@]}"; do
  safe_member_name "$path" && [[ $path != */ && -z ${declared_seen[$path]+x} && -f "$tmp/$path" && ! -L $tmp/$path ]] || { echo "missing, duplicate, or unsafe declared artifact: $path" >&2; exit 1; }
  contract_allows_member "$path" || { echo "artifact is not a contract-declared role output: $path" >&2; exit 1; }
  declared_seen[$path]=1
  bytes=$(wc -c <"$tmp/$path")
  (( bytes <= max_member_bytes )) || { echo "declared artifact exceeds size limit: $path" >&2; exit 1; }
  (( total_bytes += bytes, total_bytes <= max_total_bytes )) || { echo 'role bundle exceeds extracted size limit' >&2; exit 1; }
  jq -e --arg path "$path" --arg hash "$(sha256sum "$tmp/$path" | awk '{print $1}')" --argjson bytes "$bytes" '.roleEvidence.internalArtifacts[] | select(.name == $path and .sha256 == $hash and .bytes == $bytes)' "$manifest" >/dev/null
done

# A directory header is allowed only when it is an ancestor of a declared file;
# every regular member must be the manifest or a declared artifact. This closes
# the gap between a path-safe archive and the contract's exact inventory.
for member in "${members[@]}"; do
  if [[ $member == ci-role-evidence.json ]]; then
    continue
  elif [[ $member == */ ]]; then
    prefix=$member
    directory_used=false
    for path in "${declared[@]}"; do
      [[ $path == "$prefix"* ]] && { directory_used=true; break; }
    done
    [[ $directory_used == true ]] || { echo "undeclared directory member: $member" >&2; exit 1; }
  elif [[ -z ${declared_seen[$member]+x} ]]; then
    echo "undeclared regular bundle member: $member" >&2
    exit 1
  fi
done
mapfile -t actual < <(cd "$tmp" && find runs logs artifacts results handoff -xdev -type f -print 2>/dev/null | LC_ALL=C sort)
[[ $(printf '%s\n' "${declared[@]}" | LC_ALL=C sort) == $(printf '%s\n' "${actual[@]}" | LC_ALL=C sort) ]] || { echo 'bundle contains undeclared or missing artifacts' >&2; exit 1; }
