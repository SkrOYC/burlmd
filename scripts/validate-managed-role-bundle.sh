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
  # BURL-M003 only exports trusted launcher records under results/. Its runtime
  # inventory is exact because the manifest owns every regular member.
  if [[ $ticket == BURL-M003 ]]; then
    [[ $member == results/* || $member == logs/burl-m003-linux-closure-view.log ]]
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

# The closure-view record is produced by an untrusted candidate role and is
# interpreted only here, in the fresh seal.  Its paths describe a departed
# host, so this checker establishes grammar and internal consistency only; it
# deliberately never stats, canonicalizes, or otherwise claims knowledge of
# those old host paths.
valid_retained_path() {
  local path=$1
  [[ $path == /* && $path != *$'\t'* && $path != *$'\n'* && $path != *$'\r'* && $path != *\\* && $path != *'//' && $path != *'/./'* && $path != */. && $path != *'/../'* && $path != */.. ]] || return 1
  [[ $path != /work && $path != /work/* && $path != /contract && $path != /contract/* ]]
}

sha256_lines() { sha256sum | awk '{print $1}'; }
canonical_uint64() {
  local value=$1
  [[ $value =~ ^(0|[1-9][0-9]*)$ && ( ${#value} -lt 20 || ( ${#value} -eq 20 && $value < 18446744073709551616 ) ) ]]
}

validate_m003_closure_view() {
  local log=$1 raw=$tmp/m003-closure-contract.json line index marker base_marker integration_marker
  local base_payload=$tmp/m003-base.manifest integration_payload=$tmp/m003-integration.manifest
  command -v taplo >/dev/null || { echo 'locked taplo is required to validate the M003 closure view' >&2; return 1; }
  taplo get --file-path "$contract" --output-format json ci_bootstrap.linux_candidate_closure_view >"$raw" || return 1
  [[ -s $log && $(head -c 3 "$log") != $'\xef\xbb\xbf' && $(tail -c 1 "$log" | od -An -t x1) == *0a* ]] || return 1
  LC_ALL=C grep -q $'\r' "$log" && return 1
  iconv -f UTF-8 -t UTF-8 "$log" >/dev/null || return 1

  mapfile -t lines <"$log"
  (( ${#lines[@]} > 45 )) || return 1
  # bubblewrap_process_environment is intentionally empty; its executable is
  # owned by the separate trusted-parent record rather than an environment.
  expected_header=(
    'format=burlmd-linux-closure-view-v2' 'raw-contract-version=39'
    'bubblewrap-path=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap'
    'bubblewrap-version=bubblewrap 0.11.2'
    'bubblewrap-sha256=c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726'
    'bubblewrap-tool-closure-manifest-sha256=398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd'
    'teardown-lock-verifier-path='"$(jq -r .teardown_lock_verifier_executable "$raw")"
    'teardown-lock-verifier-version=flock from util-linux 2.42'
    'teardown-lock-verifier-sha256='"$(jq -r .teardown_lock_verifier_sha256 "$raw")"
    'base-manifest-bytes='"$(jq -r .base_closure_manifest_bytes "$raw")"
    'base-manifest-sha256='"$(jq -r .base_closure_manifest_sha256 "$raw")"
    'base-member-count='"$(jq -r .base_closure_member_count "$raw")"
    'base-nar-bytes='"$(jq -r .base_closure_nar_bytes "$raw")"
    'base-bind-bytes='"$(jq -r .base_closure_bind_argument_bytes "$raw")"
    'integration-manifest-bytes='"$(jq -r .integration_closure_manifest_bytes "$raw")"
    'integration-manifest-sha256='"$(jq -r .integration_closure_manifest_sha256 "$raw")"
    'integration-member-count='"$(jq -r .integration_closure_member_count "$raw")"
    'integration-nar-bytes='"$(jq -r .integration_closure_nar_bytes "$raw")"
    'integration-bind-bytes='"$(jq -r .integration_closure_bind_argument_bytes "$raw")"
    'sway-path=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway'
    'sway-version=sway version 1.12'
    'sway-sha256=1f10250bedd99cda8a7ef04a585f66a1dd300bd37557dbd9983535b0a8b5667d'
    'swaymsg-path=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg'
    'swaymsg-version=swaymsg version 1.12'
    'swaymsg-sha256=cfefe762ed1ed9463eeddad3b1e624f98fe15996bde77953f303a2a110d1270c'
    'compositor-closure-sha256=d97a41799b1aecc670e31bfd58b339d748498be2bce09d877a0f1a9ed1c6e673'
    'wayland-socket-basename=wayland-1'
    'config-sha256=dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a'
  )
  for index in "${!expected_header[@]}"; do [[ ${lines[$index]} == "${expected_header[$index]}" ]] || return 1; done
  index=${#expected_header[@]}
  [[ ${lines[$index]} =~ ^base-source-identity-count=[1-9][0-9]*$ ]] || return 1; ((index++))
  [[ ${lines[$index]} =~ ^base-source-identity-sha256=[0-9a-f]{64}$ ]] || return 1; ((index++))
  [[ ${lines[$index]} =~ ^integration-source-identity-count=[1-9][0-9]*$ ]] || return 1; ((index++))
  [[ ${lines[$index]} =~ ^integration-source-identity-sha256=[0-9a-f]{64}$ ]] || return 1; ((index++))
  [[ ${lines[$index]} =~ ^capacity-root-count=[1-9][0-9]*$ && ${lines[$index+1]} =~ ^capacity-authority-count=[1-9][0-9]*$ && ${lines[$index+2]} =~ ^capacity-authority-sha256=[0-9a-f]{64}$ && ${lines[$index+3]} =~ ^capacity-filesystem-count=[1-9][0-9]*$ ]] || return 1
  ((index += 4))
  [[ ${lines[$index]} == base-session-count=5 && ${lines[$index+1]} == integration-session-count=2 && ${lines[$index+2]} == session-count=7 ]] || return 1
  ((index += 3))
  base_marker=$(printf '%s\n' "${lines[@]}" | grep -n -x 'base-manifest-payload:' | cut -d: -f1)
  integration_marker=$(printf '%s\n' "${lines[@]}" | grep -n -x 'integration-manifest-payload:' | cut -d: -f1)
  [[ $base_marker =~ ^[0-9]+$ && $integration_marker =~ ^[0-9]+$ && $base_marker -lt $integration_marker ]] || return 1
  (( $(printf '%s\n' "$base_marker" | wc -l) == 1 && $(printf '%s\n' "$integration_marker" | wc -l) == 1 )) || return 1
  sed -n "$((base_marker + 1)),$((integration_marker - 1))p" "$log" >"$base_payload"
  sed -n "$((integration_marker + 1)),\$p" "$log" >"$integration_payload"
  for payload in "$base_payload" "$integration_payload"; do
    [[ $(LC_ALL=C sort -cu "$payload"; echo $?) == 0 ]] && awk 'BEGIN{ok=1} !/^\/nix\/store\/[0-9a-z]{32}-[^\/]+$/{ok=0} END{exit !ok}' "$payload" || return 1
  done
  [[ $(wc -c <"$base_payload") == $(jq -r .base_closure_manifest_bytes "$raw") && $(sha256sum "$base_payload" | awk '{print $1}') == $(jq -r .base_closure_manifest_sha256 "$raw") && $(wc -l <"$base_payload") == $(jq -r .base_closure_member_count "$raw") ]] || return 1
  [[ $(wc -c <"$integration_payload") == $(jq -r .integration_closure_manifest_bytes "$raw") && $(sha256sum "$integration_payload" | awk '{print $1}') == $(jq -r .integration_closure_manifest_sha256 "$raw") && $(wc -l <"$integration_payload") == $(jq -r .integration_closure_member_count "$raw") ]] || return 1
  comm -23 "$base_payload" "$integration_payload" | grep -q . && return 1
  declare -A authority=() authority_device=() authority_parent=() current=() frame=() source_seen=() source_identity=() capacity_fs_seen=() capacity_devices=()
  local base_source_count=0 integration_source_count=0 authority_count=0 session_count=0 capacity_fs_count=0 phase=source source_group=base last_session=0 row_hash_input=$tmp/m003-authorities.txt
  : >"$row_hash_input"
  for ((; index < base_marker - 2; index++)); do
    line=${lines[$index]}; IFS=$'\t' read -r -a fields <<<"$line"
    case ${fields[0]} in
      base-source|integration-source)
        [[ $phase == source ]] || return 1
        if [[ ${fields[0]} == base-source ]]; then
          [[ $source_group == base ]] || return 1
        else
          source_group=integration
        fi
        [[ ${#fields[@]} == 12 && ${fields[1]} =~ ^/nix/store/[0-9a-z]{32}-[^/]+$ && ${fields[2]} =~ ^(directory|regular-file)$ && ${fields[3]} =~ ^[1-9][0-9]*$ && ${fields[4]} =~ ^[1-9][0-9]*$ && ${fields[5]} =~ ^[0-9]+:[0-9]+$ && ${fields[7]} == "${fields[3]}" && ${fields[8]} == "${fields[4]}" && ${fields[9]} == "${fields[5]}" && ${fields[10]} == "${fields[1]}" && ${fields[11]} == ro ]] || return 1
        # The host mount root comes from the longest matching mountinfo entry,
        # so a normal host root of `/` is valid.  Bubblewrap's same-path member
        # bind, however, must retain the complete selected store member as its
        # namespace mount root; treating the two roots as identical only worked
        # for the reduced serializer fixture.
        valid_retained_path "${fields[6]}" || return 1
        [[ -z ${source_seen[${fields[0]}:${fields[1]}]+x} ]] || return 1; source_seen[${fields[0]}:${fields[1]}]=1
        source_identity[${fields[0]}:${fields[1]}]="${fields[*]:2}"
        if [[ ${fields[0]} == base-source ]]; then
          ((++base_source_count))
        else
          ((++integration_source_count))
        fi
        ;;
      capacity-authority)
        [[ $phase == source || $phase == authority ]] || return 1; phase=authority
        [[ ${#fields[@]} == 16 && ${fields[1]} =~ ^[1-7]$ && ${fields[3]} =~ ^[a-z0-9-]+$ && ${fields[6]} =~ ^[0-9]+$ && ${fields[7]} =~ ^[0-9]+$ && ${fields[8]} =~ ^0[0-7]{3}$ && ${fields[9]} =~ ^(directory|regular-file)$ && ${fields[10]} =~ ^[1-9][0-9]*$ && ${fields[11]} =~ ^[1-9][0-9]*$ && ${fields[12]} =~ ^[0-9]+:[0-9]+$ && ${fields[13]} == / && ${fields[15]} != /* && ${fields[15]} != *'//' && ${fields[15]} != *'/./'* && ${fields[15]} != *'/../'* ]] || return 1
        valid_retained_path "${fields[5]}" && valid_retained_path "${fields[14]}" || return 1
        # The frozen authority parent is the only provenance for its current
        # leaf.  A second parent field that can drift while argv still uses the
        # old current source would turn this retained record into a forged
        # authority claim, so require the canonical parent to be identical.
        [[ ${fields[5]} == "${fields[14]}" && ${fields[14]}/${fields[15]} != *'//' && -z ${authority[${fields[1]}:${fields[3]}]+x} ]] || return 1
        authority[${fields[1]}:${fields[3]}]="${fields[14]}/${fields[15]}"; printf '%s\n' "$line" >>"$row_hash_input"; ((authority_count++))
        authority_device[${fields[1]}:${fields[3]}]=${fields[10]}
        authority_parent[${fields[1]}:${fields[3]}]=${fields[5]}
        [[ ${fields[2]} == $(jq -r --argjson ordinal "${fields[1]}" '.sessions[$ordinal - 1].id' "$raw") ]] || return 1
        ;;
      session)
        [[ $phase == authority || $phase == session ]] || return 1; phase=session
        [[ ${#fields[@]} == 25 && ${fields[1]} =~ ^[1-7]$ && ${fields[3]} =~ ^(base|integration)$ && ${fields[4]} =~ ^[0-9a-f]{64}$ && ${fields[8]} =~ ^[0-9]+$ && ${fields[9]} =~ ^[0-9a-f]{64}$ && ${fields[10]} =~ ^[0-9]+$ && ${fields[11]} == 0 && ${fields[12]} == 0 && ${fields[13]} =~ ^[1-9][0-9]*$ && ${fields[14]} =~ ^[0-9]+$ && ${fields[15]} =~ ^[0-9a-f]{64}$ && ${fields[16]} == true && ${fields[17]} == true && ${fields[20]} == true && ${fields[21]} =~ ^[1-9][0-9]*$ && ${fields[22]} =~ ^[1-9][0-9]*$ && ${fields[23]} == true && ${fields[24]} == true ]] || return 1
        [[ -z ${frame[${fields[1]}]+x} && ${fields[1]} == $((last_session + 1)) ]] || return 1; frame[${fields[1]}]="$line"; last_session=${fields[1]}; ((session_count++))
        ;;
      session-capacity-root)
        [[ $phase == session && ${fields[1]} == "$last_session" ]] || return 1
        [[ ${#fields[@]} == 6 && ${fields[1]} =~ ^[1-7]$ && ${fields[5]} =~ ^[1-9][0-9]*$ ]] || return 1
        [[ ${fields[2]} == $(jq -r --argjson ordinal "${fields[1]}" '.sessions[$ordinal - 1].id' "$raw") ]] || return 1
        valid_retained_path "${fields[4]}" || return 1
        [[ ${authority[${fields[1]}:${fields[3]}]-} == "${fields[4]}" && ${authority_device[${fields[1]}:${fields[3]}]-} == "${fields[5]}" && -z ${current[${fields[1]}:${fields[3]}]+x} ]] || return 1
        current[${fields[1]}:${fields[3]}]=${fields[4]}
        ;;
      session-capacity-filesystem)
        [[ $phase == session && ${fields[1]} == "$last_session" ]] || return 1
        [[ ${#fields[@]} == 5 && ${fields[1]} =~ ^[1-7]$ && ${fields[3]} =~ ^[1-9][0-9]*$ && ${fields[4]} =~ ^[1-9][0-9]*$ && ${fields[4]} -ge 4000000000 && -z ${capacity_fs_seen[${fields[1]}:${fields[3]}]+x} ]] || return 1
        [[ ${fields[2]} == $(jq -r --argjson ordinal "${fields[1]}" '.sessions[$ordinal - 1].id' "$raw") ]] || return 1
        canonical_uint64 "${fields[4]}" || return 1
        capacity_fs_seen[${fields[1]}:${fields[3]}]=1; capacity_devices[${fields[3]}]=1; ((capacity_fs_count++))
        ;;
      *) return 1;;
    esac
  done
  [[ $authority_count == ${lines[$(( ${#expected_header[@]} + 5 ))]#capacity-authority-count=} && $(sha256sum "$row_hash_input" | awk '{print $1}') == ${lines[$(( ${#expected_header[@]} + 6 ))]#capacity-authority-sha256=} && $session_count == 7 && $capacity_fs_count == 7 ]] || return 1
  [[ $base_source_count == ${lines[$(( ${#expected_header[@]} ))]#base-source-identity-count=} && $integration_source_count == ${lines[$(( ${#expected_header[@]} + 2 ))]#integration-source-identity-count=} ]] || return 1
  [[ $(awk -F$'\t' '$1=="base-source"{print}' "$log" | sha256_lines) == ${lines[$(( ${#expected_header[@]} + 1 ))]#base-source-identity-sha256=} && $(awk -F$'\t' '$1=="integration-source"{print}' "$log" | sha256_lines) == ${lines[$(( ${#expected_header[@]} + 3 ))]#integration-source-identity-sha256=} ]] || return 1
  [[ ${lines[$((base_marker - 2))]} == $'host-policy\t'* ]] || return 1
  IFS=$'\t' read -r -a fields <<<"${lines[$((base_marker - 2))]}"
  [[ ${#fields[@]} == 9 && ${fields[4]} == success && ${fields[5]} == not-applied && ${fields[6]} == not-applicable && ${fields[7]} == not-applicable && ${fields[8]} == not-applicable ]] || return 1
  [[ ${#capacity_devices[@]} == ${lines[$(( ${#expected_header[@]} + 7 ))]#capacity-filesystem-count=} ]] || return 1
  while IFS= read -r entry; do
    [[ -n ${source_identity[base-source:$entry]+x} && ${source_identity[base-source:$entry]} == "${source_identity[integration-source:$entry]-}" ]] || return 1
  done <"$base_payload"
  while IFS= read -r entry; do [[ -n ${source_identity[integration-source:$entry]+x} ]] || return 1; done <"$integration_payload"
  [[ $(awk -F$'\t' '$1=="base-source"{print $2}' "$log" | LC_ALL=C sort -cu; echo $?) == 0 && $(awk -F$'\t' '$1=="integration-source"{print $2}' "$log" | LC_ALL=C sort -cu; echo $?) == 0 ]] || return 1
  local ordinal session_id session_class selected_manifest expected_sha expected_count argv_file entry key value operation authority_id destination source_class source_file preflight_file compositor_state
  local -a manifest_members namespace_args fixed_filesystem mounts supervisor command_args candidate_environment argv
  local manifest_joined base_sha integration_sha
  base_sha=$(jq -r .base_closure_manifest_sha256 "$raw")
  integration_sha=$(jq -r .integration_closure_manifest_sha256 "$raw")
  mapfile -t namespace_args < <(jq -r '.namespace_argv[]' "$raw")
  mapfile -t fixed_filesystem < <(jq -r '.fixed_filesystem_argv[]' "$raw")
  mapfile -t mounts < <(jq -r '.dynamic_mount_plan[]' "$raw")
  mapfile -t supervisor < <(jq -r '.supervisor_argv_prefix[]' "$raw")
  declare -A resolved_environment=()
  while IFS= read -r entry; do
    key=${entry%%=*}; resolved_environment[$key]=${entry#*=}
  done < <(jq -r '.serializer_golden_resolved_environment[]' "$raw")
  for ordinal in {1..7}; do
    IFS=$'\t' read -r -a fields <<<"${frame[$ordinal]-}"
    [[ ${#fields[@]} == 25 ]] || return 1
    session_id=${fields[2]}; session_class=${fields[3]}
    [[ $session_id == $(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].id' "$raw") && $session_class == $(jq -r --argjson ordinal "$ordinal" '.sessions[$ordinal - 1].class' "$raw") ]] || return 1
    [[ ${fields[6]} == ${lines[$(( ${#expected_header[@]} + 6 ))]#capacity-authority-sha256=} && ${fields[7]} == $(printf '%s\n' "${current[$ordinal:closure-staging]-}" | sha256_lines) && ${fields[13]} =~ ^[1-9][0-9]*$ && ${fields[8]} -lt $((fields[13] / 2)) ]] || return 1
    if [[ $session_class == base ]]; then
      [[ ${fields[5]} == ${lines[$(( ${#expected_header[@]} + 1 ))]#base-source-identity-sha256=} && ${fields[18]} == compositor-not-applicable && ${fields[19]} == not-applicable ]] || return 1
    else
      [[ ${fields[5]} == ${lines[$(( ${#expected_header[@]} + 3 ))]#integration-source-identity-sha256=} && ${fields[18]} == success && ${fields[19]} == true ]] || return 1
    fi
    [[ ${current[$ordinal:closure-staging]-} == */burlmd-m003/staging/"$ordinal-$session_id" && ${current[$ordinal:session-contract-root]-} == */burlmd-m003/contracts/"$ordinal-$session_id" ]] || return 1
    [[ ${current[$ordinal:trusted-control-root]-} != "${current[$ordinal:tested-source-root]-}" ]] || return 1
    if [[ $session_class == integration ]]; then
      [[ ${current[$ordinal:xdg-runtime]-} == */burlmd-m003/xdg-runtime/"$ordinal-$session_id" ]] || return 1
    else
      [[ -z ${current[$ordinal:xdg-runtime]+x} ]] || return 1
    fi
    declare -A expected_authorities=([closure-staging]=staging-leaf)
    for entry in "${mounts[@]}"; do IFS=: read -r operation authority_id destination <<<"$entry"; expected_authorities[$authority_id]=argv-source; done
    [[ $session_class != integration ]] || expected_authorities[xdg-runtime]=runtime-leaf
    local matching_authorities=0
    for key in "${!authority[@]}"; do
      [[ $key == "$ordinal:"* ]] || continue
      ((++matching_authorities))
      authority_id=${key#*:}
      [[ ${expected_authorities[$authority_id]-} == $(awk -F$'\t' -v ordinal="$ordinal" -v authority="$authority_id" '$1=="capacity-authority" && $2==ordinal && $4==authority{print $5}' "$log") && -n ${current[$key]+x} ]] || return 1
    done
    [[ $matching_authorities == ${#expected_authorities[@]} ]] || return 1
    if [[ $session_class == base ]]; then
      selected_manifest=$base_payload; expected_sha=$base_sha; expected_count=$(jq -r .base_closure_member_count "$raw")
      source_class=base-source; compositor_state=absent
    else
      selected_manifest=$integration_payload; expected_sha=$integration_sha; expected_count=$(jq -r .integration_closure_member_count "$raw")
      source_class=integration-source; compositor_state=pending-supervisor-start
    fi
    [[ ${fields[4]} == "$expected_sha" && ${fields[10]} == "$expected_count" ]] || return 1
    source_file="$tmp/m003-preflight-source-$ordinal"
    awk -F$'\t' -v source_class="$source_class" '$1 == source_class { sub(/^[^\t]*\t/, ""); print }' "$log" >"$source_file"
    preflight_file="$tmp/m003-preflight-$ordinal"
    {
      printf '%s\n' 'format=burlmd-linux-closure-preflight-v2' "session-class=$session_class" "selected-manifest-sha256=$expected_sha" "source-identity-count=$expected_count"
      cat "$source_file"
      printf '%s\n' 'pid-namespace-private=true' 'network-namespace-private=true' 'descriptor=0:candidate-stdin' 'descriptor=1:candidate-stdout' 'descriptor=2:candidate-stderr' 'descriptor=3:preflight-record-write' 'descriptor=4:preflight-ack-read' 'store-view-exact=true' 'forbidden-paths-absent=true' "compositor-state=$compositor_state"
    } >"$preflight_file"
    [[ ${fields[14]} == $(wc -c <"$preflight_file") && ${fields[15]} == $(sha256sum "$preflight_file" | awk '{print $1}') ]] || return 1
    mapfile -t manifest_members <"$selected_manifest"
    manifest_joined=$(IFS=:; printf '%s' "${manifest_members[*]}")
    candidate_environment=()
    mapfile -t candidate_environment < <(jq -r '.fixed_candidate_environment[]' "$raw")
    while IFS= read -r entry; do
      key=${entry%%=*}; value=${entry#*=}
      case $value in
        SESSION_ID) value=$session_id ;;
        /candidate/session/pid) ;;
        SELECTED_MANIFEST_MEMBERS_JOINED_BY_COLON) value=$manifest_joined ;;
        LOCKED_OPENSSL_PCFILEDIR) value=${resolved_environment[PKG_CONFIG_PATH]-} ;;
        LOCKED_LIBCLANG_LIB) value=${resolved_environment[LIBCLANG_PATH]-} ;;
        '-isystem LOCKED_OPENSSL_INCLUDEDIR') value=${resolved_environment[NIX_CFLAGS_COMPILE]-} ;;
        -LLOCKED_OPENSSL_LIBDIR) value=${resolved_environment[NIX_LDFLAGS_x86_64_unknown_linux_gnu]-} ;;
        LOCKED_MESA_DRI_PATH) value=${resolved_environment[LIBGL_DRIVERS_PATH]-} ;;
        LOCKED_MESA_EGL_VENDOR_PATH) value=${resolved_environment[__EGL_VENDOR_LIBRARY_FILENAMES]-} ;;
        *) return 1;;
      esac
      [[ -n $value ]] || return 1
      candidate_environment+=("$key=$value")
    done < <(jq -r '.derived_candidate_environment[]' "$raw")
    # The four integration-only assignments are created by the in-namespace
    # supervisor at its final env boundary. They are not Bubblewrap --setenv
    # arguments and therefore are intentionally absent from this vector.
    [[ ${#candidate_environment[@]} == 33 ]] || return 1
    argv=(/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap "${namespace_args[@]}")
    for entry in "${candidate_environment[@]}"; do argv+=(--setenv "${entry%%=*}" "${entry#*=}"); done
    argv+=(--lock-file "$(jq -r .teardown_lock_namespace_path "$raw")" "${fixed_filesystem[@]}")
    for entry in "${mounts[@]}"; do
      IFS=: read -r operation authority_id destination <<<"$entry"
      [[ -n ${current[$ordinal:$authority_id]-} ]] || return 1
      argv+=(--"$operation" "${current[$ordinal:$authority_id]}" "$destination")
      if [[ $session_class == integration && $authority_id == session-contract-root ]]; then
        [[ -n ${current[$ordinal:xdg-runtime]-} ]] || return 1
        argv+=(--bind "${current[$ordinal:xdg-runtime]}" /candidate/xdg/runtime)
      fi
    done
    for entry in "${manifest_members[@]}"; do argv+=(--ro-bind "$entry" "$entry"); done
    argv+=(--symlink /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env /usr/bin/env)
    [[ $session_class != integration ]] || argv+=(--symlink /nix/store/zh1ijdhb6gng1509b1zrilb6xlzx60j6-bash-5.3p9/bin/bash /bin/sh)
    argv+=(--chdir /source --)
    for entry in "${supervisor[@]}"; do argv+=("${entry//SESSION_ID/$session_id}"); done
    for index in "${!argv[@]}"; do argv[$index]=${argv[$index]//SESSION_CLASS/$session_class}; done
    mapfile -t command_args < <(jq -r --arg id "$session_id" '.sessions[] | select(.id == $id) | .command[]' "$raw")
    (( ${#command_args[@]} > 0 )) || return 1
    argv+=("${command_args[@]}")
    argv_file="$tmp/m003-complete-argv-$ordinal"
    printf '%s\0' "${argv[@]}" >"$argv_file"
    [[ ${fields[8]} == $(wc -c <"$argv_file") && ${fields[9]} == $(sha256sum "$argv_file" | awk '{print $1}') ]] || return 1
  done
  return 0
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
header_total_bytes=0
for index in "${!members[@]}"; do
  header=${verbose[$index]}
  case ${members[$index]} in
    */) [[ ${header:0:1} == d ]] || { echo "directory member is not a directory: ${members[$index]}" >&2; exit 1; } ;;
    *) [[ ${header:0:1} == - ]] || { echo "role bundle contains a non-regular member: ${members[$index]}" >&2; exit 1; } ;;
  esac
  member_bytes=$(awk '{print $3}' <<<"$header")
  [[ $member_bytes =~ ^[0-9]+$ ]] && (( member_bytes <= max_member_bytes )) || { echo "role bundle member exceeds size limit: ${members[$index]}" >&2; exit 1; }
  # Header sizes are available before extraction and include the manifest,
  # directory entries, and every regular member—not just the manifest-owned
  # artifacts checked below. This rejects a highly compressible archive bomb
  # before tar writes any untrusted byte to the staging directory.
  (( header_total_bytes += member_bytes, header_total_bytes <= max_total_bytes )) || { echo 'role bundle exceeds declared archive size limit' >&2; exit 1; }
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
# seal authority. BURL-M003 already has an exact results/ inventory of its own.
if [[ $(jq -r '.ticketIdentity' "$expected") != BURL-M003 && ( $role == macos-26-arm64 || $role == macos-15-arm64 ) ]]; then
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
if [[ $(jq -r '.ticketIdentity' "$expected") == BURL-M003 && $role == linux-x86_64 ]]; then
  [[ ${declared_seen[logs/burl-m003-linux-closure-view.log]+x} ]] || {
    echo 'BURL-M003 Linux bundle omits the required closure-view log' >&2
    exit 1
  }
  validate_m003_closure_view "$tmp/logs/burl-m003-linux-closure-view.log" || {
    echo 'BURL-M003 Linux closure-view log is malformed or inconsistent' >&2
    exit 1
  }
fi

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
