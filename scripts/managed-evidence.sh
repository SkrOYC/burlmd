#!/usr/bin/env bash
# Trusted launcher for the two-phase managed evidence protocol. Candidate
# checkout contents are treated as data; this launcher never sources them.
set -euo pipefail

readonly API_VERSION=2026-03-10
readonly REPOSITORY_DEFAULT=SkrOYC/burlmd
readonly ROLES=(linux-x86_64 macos-26-arm64 macos-15-arm64)
readonly API_TRANSIENT=75
readonly API_PERMISSION=76
readonly API_FAILURE=77
readonly POLL_TRANSIENT_RETRIES=5
# PR #39's independently reviewed post-merge closure records the immediate
# reviewed master tip for this same-contract correction.
readonly BURL_M003_REVIEWED_BASE_SHA=5e9935d1c8a8c100593c0cdc2dee21d3ae97de2b
die() { printf 'managed-evidence: %s\n' "$*" >&2; exit 2; }
sha256_file() { sha256sum "$1" | awk '{print $1}'; }

usage() {
  printf '%s\n' 'usage: managed-evidence.sh run|collect --ticket ID --trust-anchor-sha SHA --source-ref REF --tested-source-sha SHA --base-sha SHA [--run-identity managed:NONCE --run-id ID --attempt N] --output REPORT' >&2
  exit 2
}
mode=${1:-}; shift || true
case "$mode" in run|collect) ;; *) usage;; esac
# The launcher is a trust boundary, not a test adapter.  Fixture transports,
# schemas, completion records, and sandbox substitutes live in the separate
# non-authoritative harness.  Refuse the whole reserved namespace so a
# misspelled harness variable cannot silently become production authority.
reserved_fixture_prefix=M; reserved_fixture_prefix+=E_
# Do not put this in a `compgen | rg -q` pipeline. With `pipefail`, rg can
# stop after the first match, leave compgen with SIGPIPE, and make a reserved
# fixture variable look like a failed search in a large environment.
environment_names=$(compgen -e) || die 'could not enumerate launcher environment'
while IFS= read -r environment_name; do
  [[ $environment_name == "$reserved_fixture_prefix"* ]] && die 'production launcher rejects reserved fixture environment'
done <<<"$environment_names"
ticket= anchor= source_ref= tested= base= run_identity= run_id= attempt= output=
source_allowlist=
while (($#)); do
  (($# >= 2)) || usage
  case "$1" in
    --ticket) ticket=$2;; --trust-anchor-sha) anchor=$2;; --source-ref) source_ref=$2;;
    --tested-source-sha) tested=$2;; --base-sha) base=$2;; --run-identity) run_identity=$2;;
    --run-id) run_id=$2;; --attempt) attempt=$2;; --output) output=$2;; *) usage;;
  esac
  shift 2
done
[[ $ticket =~ ^BURL-[A-Z][0-9]{3}$ ]] || die 'invalid ticket'
for sha in "$anchor" "$tested" "$base"; do [[ $sha =~ ^[0-9a-f]{40}$ ]] || die 'invalid SHA'; done
[[ $source_ref == refs/heads/* && -n $output ]] || usage
if [[ $mode == collect ]]; then
  # A collection is bound to a fresh dispatch.  Do not normalize a caller's
  # value: only the literal CLI spelling `--attempt 1` is valid.
  [[ $run_identity =~ ^managed:[0-9a-f]{32}$ && $run_id =~ ^[1-9][0-9]*$ && $attempt == 1 ]] || die 'invalid collection identity'
else
  [[ -z $run_identity && -z $run_id && -z $attempt ]] || usage
fi

# Resolve the launched file before looking up the checkout. The trusted
# launcher is commonly invoked by its canonical absolute path from a separate
# evidence workspace, where the caller's current directory is untrusted and
# may not be a Git checkout at all.
launcher_path=$(realpath -e -- "$0" 2>/dev/null) || die 'launcher path is unavailable'
launcher_dir=$(dirname -- "$launcher_path") || die 'launcher directory is unavailable'
anchor_root=$(git -C "$launcher_dir" rev-parse --show-toplevel 2>/dev/null) || die 'launcher is not in a Git checkout'
anchor_root=$(realpath -e -- "$anchor_root") || die 'trust anchor path is unavailable'
[[ $launcher_path == "$anchor_root/scripts/managed-evidence.sh" ]] || die 'launcher must be the trust anchor managed-evidence script'
[[ $output == /* ]] || die 'output must be an absolute path'
output=$(realpath -m "$output")
# REPORT_JSON is the CLI's authoritative publication boundary.  Derive the
# separate evidence checkout from its nearest existing parent so the first
# report in a declared directory is still allowed to create that directory.
# Do not accept an ambient root: the documented command forms intentionally
# expose no EVIDENCE_WORKTREE input.
output_parent=$(dirname -- "$output")
while [[ ! -d $output_parent ]]; do
  next_parent=$(dirname -- "$output_parent") || die 'output parent is unavailable'
  [[ $next_parent != "$output_parent" ]] || die 'output parent is unavailable'
  output_parent=$next_parent
done
evidence_root=$(git -C "$output_parent" rev-parse --show-toplevel 2>/dev/null) || die 'output must be inside an evidence Git worktree'
evidence_root=$(realpath -e -- "$evidence_root") || die 'evidence worktree path is unavailable'
[[ $output == "$evidence_root"/* && $output != "$anchor_root"/* ]] || die 'output must be under the evidence worktree and outside trust anchor'
[[ -z $(git -C "$anchor_root" symbolic-ref -q HEAD) && $(git -C "$anchor_root" rev-parse HEAD) == "$anchor" && -z $(git -C "$anchor_root" status --porcelain) ]] || die 'trust anchor must be clean, detached, and at supplied SHA'
readonly CONTRACT=$anchor_root/.constitution/tech-spec/contracts/provisional-spikes.toml
readonly ROLE_SCHEMA=$anchor_root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json
readonly AGGREGATE_SCHEMA=$anchor_root/.constitution/tech-spec/contracts/ci-evidence.schema.json
readonly RECEIPT_TRANSPORT_SCHEMA=$anchor_root/.constitution/tech-spec/contracts/ci-evidence.schema.json
readonly RESULT_SCHEMA=$anchor_root/.constitution/tech-spec/contracts/spike-result.schema.json
[[ -f $CONTRACT && -f $ROLE_SCHEMA && -f $AGGREGATE_SCHEMA && -f $RECEIPT_TRANSPORT_SCHEMA && -f $RESULT_SCHEMA ]] || die 'trusted contracts missing'
readonly ROLE_SCHEMA_VERSION=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$ROLE_SCHEMA")
readonly AGGREGATE_SCHEMA_VERSION=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$AGGREGATE_SCHEMA")
readonly RESULT_SCHEMA_VERSION=$(jq -er '.properties.schemaVersion.const | select(type == "number")' "$RESULT_SCHEMA")
readonly CONTRACT_RESULT_SCHEMA_VERSION=$(awk -F ' = ' '$1 == "result_schema_version" {print $2; exit}' "$CONTRACT")
[[ $CONTRACT_RESULT_SCHEMA_VERSION == "$RESULT_SCHEMA_VERSION" ]] || die 'result schema and contract versions disagree'
REPOSITORY=$REPOSITORY_DEFAULT
API_BASE=https://api.github.com
CURL_BIN=curl
GH_BIN=gh
readonly REPOSITORY API_BASE CURL_BIN GH_BIN
tmp=$(mktemp -d "${TMPDIR:-/tmp}/managed-evidence.XXXXXX")
owned_cleanup_roots=()
register_owned_cleanup_root() {
  local relative=$1 absolute
  # Only the two contract-declared ephemeral roots are removable.  Reports
  # and managed results are siblings and therefore survive successful,
  # rejected, and interrupted transactions.
  case "$relative" in
    .constitution/prototypes/*/managed-evidence-prepare|.constitution/prototypes/*/managed-evidence-coordinator) ;;
    *) return 1 ;;
  esac
  absolute=$(realpath -m "$evidence_root/$relative") || return 1
  [[ $absolute == "$evidence_root"/* && $absolute != "$evidence_root" ]] || return 1
  local root
  for root in "${owned_cleanup_roots[@]}"; do [[ $root == "$absolute" ]] && return 0; done
  owned_cleanup_roots+=("$absolute")
}
cleanup() {
  local status=$? root
  rm -f -- "$auth_config" 2>/dev/null || true
  for root in "${owned_cleanup_roots[@]}"; do
    rm -rf -- "$root" 2>/dev/null || true
  done
  rm -rf -- "$tmp" 2>/dev/null || true
  return "$status"
}
# An interrupted evidence transaction is neither accepted nor rejected: no
# caller may mistake a partly downloaded bundle for a decision.  Preserve the
# documented exit-2 distinction and let the EXIT hook clean owned scratch
# state exactly once.
interrupted() { trap - HUP INT TERM; exit 2; }
trap cleanup EXIT
trap interrupted HUP INT TERM
expected=$tmp/expected-identity.json
auth_config=$tmp/curl.conf

# This fixed-section reader intentionally accepts only the anchor-owned format.
profile_for() {
  local requested=$1 role=$2
  awk -v ticket="$requested" -v role="$role" '
    $0 == "[ci_bootstrap.ticket_evidence_profiles.\"" ticket "\"]" {in_section=1; next}
    /^\[/ {in_section=0}
    in_section && $0 ~ "^\"" role "\"[[:space:]]*=" {sub(/^[^=]*=[[:space:]]*/, ""); print; exit}
  ' "$CONTRACT" | jq -ce .
}
ticket_profile_exists() {
  local requested=$1
  [[ $(profile_for "$requested" linux-x86_64 2>/dev/null) != '' ]] &&
    [[ $(profile_for "$requested" macos-26-arm64 2>/dev/null) != '' ]] &&
    [[ $(profile_for "$requested" macos-15-arm64 2>/dev/null) != '' ]]
}
bootstrap_allowlist() {
  awk '/^bootstrap_write_allowlist[[:space:]]*=/ {on=1} on {sub(/^[^=]*=/, ""); print; if (/\]/) exit}' "$CONTRACT" | jq -ce .
}
spike_allowlist() {
  local spike=$1
  awk -v spike="$spike" '/^\[\[spikes\]\]/ {on=0} $0 == "id = \"SPK-" spike "\"" {on=1; next} on && /^write_allowlist[[:space:]]*=/ {sub(/^[^=]*=/, ""); print; exit}' "$CONTRACT" | jq -ce .
}
non_spike_allowlist() {
  command -v taplo >/dev/null || return 1
  taplo get --file-path "$CONTRACT" --output-format json "ci_bootstrap.non_spike_source_write_allowlists.tickets.\"$1\"" | jq -ce .
}
is_spike_ticket() { [[ -n $(spike_for "$1") ]]; }
workflow_path() { case "$1" in linux-x86_64) printf .github/workflows/ci-role-linux-x86-64.yml;; macos-26-arm64) printf .github/workflows/ci-role-macos-26-arm64.yml;; macos-15-arm64) printf .github/workflows/ci-role-macos-15-arm64.yml;; esac; }
role_label() { case "$1" in linux-x86_64) printf ubuntu-22.04;; macos-26-arm64) printf macos-26;; macos-15-arm64) printf macos-15;; esac; }
spike_for() { case "$1" in BURL-H001) printf BURL-H001;; BURL-H002) printf BURL-H002;; BURL-I001) printf BURL-I001;; BURL-L001) printf BURL-L001;; BURL-O001) printf BURL-O001;; esac; }
declared_report_path() {
  if [[ $ticket == BURL-M003 ]]; then printf '.constitution/evidence/BURL-M003/managed-evidence.json'; return; fi
  if ! is_spike_ticket "$ticket"; then
    command -v taplo >/dev/null || return 1
    taplo get --file-path "$CONTRACT" --output-format json "ci_bootstrap.evidence_only_integration.\"$ticket\".managed_report" | jq -er .
    return
  fi
  awk -v spike="SPK-$(spike_for "$ticket")" '
    /^\[\[spikes\]\]/ {on=0}
    $0 == "id = \"" spike "\"" {on=1; next}
    on && /^managed_report[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*\"/, ""); sub(/\"[[:space:]]*$/, ""); print; exit}
  ' "$CONTRACT"
}

path_allowed() {
  local path=$1 roots=$2 root prefix root_lines
  [[ $path != /* && $path != *'..'* && $path != */./* && $path != */ ]] || return 1
  root_lines=$(jq -er '.[] | strings' <<<"$roots") || return 1
  while IFS= read -r root; do
    if [[ $root == */** ]]; then prefix=${root%/**}; [[ $path == "$prefix" || $path == "$prefix"/* ]] && return 0
    elif [[ $root == */\* ]]; then prefix=${root%/*}; [[ $path == "$prefix"/* ]] && return 0
    elif [[ $path == "$root" ]]; then return 0
    fi
  done <<<"$root_lines"
  return 1
}
read_trusted_control_paths() {
  local controls_json control_lines
  command -v taplo >/dev/null || return 1
  # Materialize each producer only after its status is known. A process
  # substitution hides taplo/jq failure from mapfile and can leave a partial
  # trusted-control list that accidentally authorizes a candidate.
  controls_json=$(taplo get --file-path "$CONTRACT" --output-format json ci_bootstrap.trust_anchor.trusted_control_paths) || return 1
  control_lines=$(jq -er '.[] | strings' <<<"$controls_json") || return 1
  mapfile -t trusted_control_paths <<<"$control_lines"
  (( ${#trusted_control_paths[@]} > 0 ))
}
trusted_control_entry() {
  local revision=$1 path=$2 entry metadata entry_path mode kind object
  entry=$(git -C "$anchor_root" ls-tree "$revision" -- "$path") || return 1
  IFS=$'\t' read -r metadata entry_path <<<"$entry"
  [[ $entry_path == "$path" ]] || return 1
  read -r mode kind object <<<"$metadata"
  [[ ( $mode == 100644 || $mode == 100755 ) && $kind == blob && $object =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s %s\n' "$mode" "$object"
}
trusted_controls_equivalent() {
  local reference=$1 revision path expected actual
  shift
  read_trusted_control_paths || return 1
  for path in "${trusted_control_paths[@]}"; do
    expected=$(trusted_control_entry "$reference" "$path") || return 1
    for revision in "$@"; do
      actual=$(trusted_control_entry "$revision" "$path") || return 1
      [[ $actual == "$expected" ]] || return 1
    done
  done
}
workflow_guard() {
  local remote_signer
  remote_signer=$(git -C "$anchor_root" ls-remote origin refs/heads/master | awk 'NR == 1 {print $1}')
  [[ $remote_signer =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$anchor_root" fetch --quiet --no-tags origin '+refs/heads/master:refs/managed-evidence/workflow-signer' || return 1
  workflow_signer=$(git -C "$anchor_root" rev-parse refs/managed-evidence/workflow-signer^{commit}) || return 1
  [[ $workflow_signer == "$remote_signer" ]] || return 1
  git -C "$anchor_root" merge-base --is-ancestor "$anchor" "$workflow_signer" || return 1
  # The anchor-owned contract lists every control file. Compare complete Git
  # tree entries rather than a hand-maintained subset: this binds bytes, mode,
  # regular-file type, and future additions to the authoritative surface.
  trusted_controls_equivalent "$anchor" "$workflow_signer" || return 1
}
resolve_origin_revisions() {
  # Both revisions must be obtained from origin in this invocation.  The local
  # checkout can contain stale refs or unrelated objects, neither of which is
  # evidence that the candidate/base pair is the pair GitHub will execute.
  git -C "$anchor_root" fetch --quiet --no-tags origin "+$source_ref:refs/managed-evidence/source" || return 1
  origin_tested=$(git -C "$anchor_root" rev-parse refs/managed-evidence/source^{commit}) || return 1
  # Fetching the named source ref transfers its complete ancestry.  Resolve the
  # supplied base from that origin-derived graph, rather than asking every Git
  # server to permit a direct SHA fetch (which hosted servers rightly reject).
  origin_base=$(git -C "$anchor_root" rev-parse "$base^{commit}") || return 1
  git -C "$anchor_root" merge-base --is-ancestor "$origin_base" "$origin_tested" || return 1
  [[ $origin_tested == "$tested" && $origin_base == "$base" ]]
}
source_guard() {
  local roots line mode_a mode_b path status diff_raw
  resolve_origin_revisions || return 1
  if [[ $ticket == BURL-M003 ]]; then
    burl_m003_identity_guard || return 1
    roots=$(bootstrap_allowlist)
  elif is_spike_ticket "$ticket"; then
    git -C "$anchor_root" merge-base --is-ancestor "$base" "$tested" || return 1
    roots=$(spike_allowlist "$(spike_for "$ticket")") || return 1
  else
    git -C "$anchor_root" merge-base --is-ancestor "$base" "$tested" || return 1
    roots=$(non_spike_allowlist "$ticket") || return 1
  fi
  source_allowlist=$roots
  # A later ticket's source allowlist cannot authorize a trusted-control
  # mutation. Require every contract-owned control path to be a regular file
  # with identical bytes and mode at the anchor, signer, and tested source.
  trusted_controls_equivalent "$anchor" "$workflow_signer" "$tested" || return 1
  # Raw diff binds object modes; NUL-delimited names protect spaces and both
  # endpoints of renames/copies are checked instead of only their destination.
  # Keep the NUL-delimited diff in a parent-owned file. `while ... < <(git
  # diff)` cannot distinguish a clean empty diff from a failed producer.
  diff_raw=$tmp/source-guard.diff
  git -C "$anchor_root" diff --raw -z --no-abbrev --find-renames --find-copies "$base" "$tested" >"$diff_raw" || return 1
  while IFS= read -r -d '' line && IFS= read -r -d '' path; do
    mode_a=${line#*:}; mode_a=${mode_a%% *}; mode_b=${line#* }; mode_b=${mode_b%% *}
    status=${line##* }; status=${status%%[0-9]*}
    path_allowed "$path" "$roots" || return 1
    [[ $mode_a != 120000 && $mode_b != 120000 && $mode_a != 160000 && $mode_b != 160000 ]] || return 1
    case "$status" in R|C) IFS= read -r -d '' path || return 1; path_allowed "$path" "$roots" || return 1;; esac
  done <"$diff_raw"
}
burl_m003_identity_guard() {
  # The bootstrap may authenticate only the reviewed BURL-M003 range.  Its
  # base is not an arbitrary ancestor: it is the replacement anchor's sole
  # first parent, followed by exactly one reviewed implementation commit.
  [[ $anchor == "$tested" && $anchor == "$workflow_signer" ]] || return 1
  [[ $base == "$BURL_M003_REVIEWED_BASE_SHA" ]] || return 1
  [[ $(git -C "$anchor_root" rev-parse "$anchor^{commit}") == "$anchor" ]] || return 1
  [[ $(git -C "$anchor_root" rev-parse "$anchor^") == "$base" ]] || return 1
  ! git -C "$anchor_root" rev-parse --verify --quiet "$anchor^2" >/dev/null || return 1
  [[ $(git -C "$anchor_root" rev-list --ancestry-path "$base..$anchor" | wc -l | tr -d ' ') == 1 ]] || return 1
  git -C "$anchor_root" merge-base --is-ancestor 6d30b7445b0108a6a5dd963cd2aa2ae5f5090485 "$anchor" || return 1
  git -C "$anchor_root" merge-base --is-ancestor f72659cef4487317c9e984e01f775a358f814a41 "$anchor" || return 1
  [[ $(git -C "$anchor_root" rev-parse f72659cef4487317c9e984e01f775a358f814a41^) == 6d30b7445b0108a6a5dd963cd2aa2ae5f5090485 ]]
}
completion_field() {
  local record=$1 name=$2
  awk -F ': ' -v name="$name" '$1 == name { print $2; exit }' "$record"
}
completion_record_valid() {
  local record=$1 field count
  # This is intentionally a small, line-oriented completion format. It makes
  # the manually reviewed acceptance facts auditable without treating freeform
  # Markdown as an authority surface.
  awk -F ': ' '
    BEGIN {
      split("ticketIdentity trustAnchorSha workflowSignerSha testedSourceSha runIdentity report reportSha256 implementationPullRequest implementationReview evidencePullRequest evidenceReview acceptance", fields, " ")
      for (i in fields) allowed[fields[i]] = 1
    }
    NF != 2 || !allowed[$1] || $2 == "" { exit 1 }
    { count[$1]++ }
    END {
      for (field in allowed) if (count[field] != 1) exit 1
      if (NR != 12) exit 1
    }
  ' "$record" || return 1
  [[ $(completion_field "$record" ticketIdentity) == BURL-M003 ]] || return 1
  [[ $(completion_field "$record" trustAnchorSha) =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $(completion_field "$record" workflowSignerSha) =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $(completion_field "$record" testedSourceSha) =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $(completion_field "$record" runIdentity) =~ ^managed:[0-9a-f]{32}$ ]] || return 1
  [[ $(completion_field "$record" report) == .constitution/evidence/BURL-M003/managed-evidence.json ]] || return 1
  [[ $(completion_field "$record" reportSha256) =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ $(completion_field "$record" implementationPullRequest) =~ ^https://github\.com/SkrOYC/burlmd/pull/[1-9][0-9]*$ ]] || return 1
  [[ $(completion_field "$record" implementationReview) =~ ^https://github\.com/SkrOYC/burlmd/pull/[1-9][0-9]*$ ]] || return 1
  [[ $(completion_field "$record" evidencePullRequest) =~ ^https://github\.com/SkrOYC/burlmd/pull/[1-9][0-9]*$ ]] || return 1
  [[ $(completion_field "$record" evidenceReview) =~ ^https://github\.com/SkrOYC/burlmd/pull/[1-9][0-9]*$ ]] || return 1
  [[ $(completion_field "$record" acceptance) == independently-reviewed-and-merged ]]
}
manifest_scalar() {
  local manifest=$1 name=$2
  awk -v name="$name" '
    $0 ~ "^[[:space:]]*" name ": " {
      count++
      value=$0
      sub("^[[:space:]]*" name ": ", "", value)
    }
    END { if (count == 1) print value; else exit 1 }
  ' "$manifest"
}
completion_manifest_valid() {
  local manifest=$1 report=$2 completion=$3 report_sha completion_sha report_bytes completion_bytes members
  # A manifest cannot safely digest itself. Its exact two content members are
  # the report and completion record; the third member of the evidence-only
  # commit is the manifest itself and is verified by the exact commit diff.
  [[ $(manifest_scalar "$manifest" owner) == BURL-M003 ]] || return 1
  [[ $(manifest_scalar "$manifest" mode) == contract_test ]] || return 1
  [[ $(manifest_scalar "$manifest" commit) == "$anchor" ]] || return 1
  report_sha=$(sha256_file "$report") || return 1
  completion_sha=$(sha256_file "$completion") || return 1
  report_bytes=$(wc -c <"$report") || return 1
  completion_bytes=$(wc -c <"$completion") || return 1
  [[ $(grep -Ec '^[[:space:]]*-[[:space:]]+path: ' "$manifest") == 2 ]] || return 1
  members=$(awk '
    /^  - path: / { path=substr($0, 11); sha=""; bytes=""; next }
    path != "" && /^    sha256: / { sha=substr($0, 13); next }
    path != "" && /^    bytes: / { bytes=substr($0, 12); print path "\t" sha "\t" bytes; path=""; sha=""; bytes=""; next }
    END { if (path != "") exit 1 }
  ' "$manifest") || return 1
  [[ $(wc -l <<<"$members") == 2 ]] || return 1
  grep -Fxq ".constitution/evidence/BURL-M003/managed-evidence.json	$report_sha	$report_bytes" <<<"$members" || return 1
  grep -Fxq ".constitution/evidence/BURL-M003/completion.md	$completion_sha	$completion_bytes" <<<"$members" || return 1
}
completion_report_valid() {
  local report=$1 profiles='{}' role profile run
  validate_schema "$AGGREGATE_SCHEMA" "$report" || return 1
  for role in "${ROLES[@]}"; do
    profile=$(profile_for BURL-M003 "$role") || return 1
    profiles=$(jq -c --arg role "$role" --argjson profile "$profile" '. + {($role): $profile}' <<<"$profiles") || return 1
  done
  run=$(completion_field "$completion_record" runIdentity) || return 1
  jq -e --arg anchor "$anchor" --arg run "$run" --argjson profiles "$profiles" '
    .status == "accepted"
    and .expectedIdentity.ticketIdentity == "BURL-M003"
    and .expectedIdentity.trustAnchorSha == $anchor
    and .expectedIdentity.testedSourceSha == $anchor
    and .expectedIdentity.workflowSignerSha == $anchor
    and .expectedIdentity.workflowSignerRef == "refs/heads/master"
    and .expectedIdentity.runIdentity == $run
    and .expectedIdentity.requiredRoleIdentities == ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"]
    and .expectedIdentity.requiredEvidenceClasses == $profiles
  ' "$report" >/dev/null
}
completion_guard() {
  # Spikes are not permitted to bootstrap the managed pipeline.  The reviewed
  # evidence record must already name the immutable anchor used by this run.
  [[ $ticket == BURL-M003 ]] && return 0
  # Resolve the completion record from a fresh origin/master fetch, rather
  # than the detached anchor's working tree.  Its structured fields bind the
  # prior CI evidence report to exactly this immutable anchor.
  local completion_ref=refs/managed-evidence/completion-master completion_path report_path manifest_path completion_commit completion_parent changed_paths
  git -C "$anchor_root" fetch --quiet --no-tags origin '+refs/heads/master:refs/managed-evidence/completion-master' || return 1
  completion_path=$tmp/ci-m003-completion.md
  report_path=$tmp/ci-m003-completion-report.json
  manifest_path=$tmp/ci-m003-completion-manifest.yaml
  completion_record=$completion_path
  git -C "$anchor_root" show "$completion_ref:.constitution/evidence/BURL-M003/completion.md" >"$completion_path" 2>/dev/null || return 1
  git -C "$anchor_root" show "$completion_ref:.constitution/evidence/BURL-M003/managed-evidence.json" >"$report_path" 2>/dev/null || return 1
  git -C "$anchor_root" show "$completion_ref:.constitution/evidence/BURL-M003/manifest.yaml" >"$manifest_path" 2>/dev/null || return 1
  completion_record_valid "$completion_path" || return 1
  [[ $(completion_field "$completion_path" trustAnchorSha) == "$anchor" ]] || return 1
  [[ $(completion_field "$completion_path" workflowSignerSha) == "$anchor" ]] || return 1
  [[ $(completion_field "$completion_path" testedSourceSha) == "$anchor" ]] || return 1
  [[ $(sha256_file "$report_path") == $(completion_field "$completion_path" reportSha256) ]] || return 1
  completion_manifest_valid "$manifest_path" "$report_path" "$completion_path" || return 1
  completion_report_valid "$report_path" || return 1
  completion_commit=$(git -C "$anchor_root" log -n 1 --format=%H "$completion_ref" -- .constitution/evidence/BURL-M003/completion.md) || return 1
  [[ $completion_commit =~ ^[0-9a-f]{40}$ ]] || return 1
  completion_parent=$(git -C "$anchor_root" rev-parse "$completion_commit^") || return 1
  [[ $completion_parent == "$anchor" ]] || return 1
  changed_paths=$(git -C "$anchor_root" diff-tree --no-commit-id --name-only -r "$completion_commit" | LC_ALL=C sort) || return 1
  [[ $changed_paths == $'.constitution/evidence/BURL-M003/completion.md\n.constitution/evidence/BURL-M003/managed-evidence.json\n.constitution/evidence/BURL-M003/manifest.yaml' ]]
}
identity_hashes() {
  : >"$tmp/build-manifest" || return 1
  printf 'anchor=%s\nsigner=%s\ntested=%s\nbase=%s\n' "$anchor" "$workflow_signer" "$tested" "$base" >>"$tmp/build-manifest" || return 1
  git -C "$anchor_root" rev-parse "$tested^{tree}" >>"$tmp/build-manifest" || return 1
  git -C "$anchor_root" diff --raw --no-abbrev --find-renames --find-copies "$base" "$tested" >>"$tmp/build-manifest" || return 1
  git -C "$anchor_root" ls-tree -r "$anchor" -- Cargo.lock pubspec.lock devenv.lock rust-toolchain.toml devenv.nix .github scripts >>"$tmp/build-manifest" || return 1
  git -C "$anchor_root" ls-tree -r "$tested" -- test integration_test test_driver >"$tmp/corpus-manifest" || return 1
  build_identity=$(sha256_file "$tmp/build-manifest")
  corpus_identity=$(sha256_file "$tmp/corpus-manifest")
}
make_expected() {
  local profiles='{}' guards='{}' role array guard nonce=${run_identity#managed:}
  for role in "${ROLES[@]}"; do
    array=$(profile_for "$ticket" "$role") || die 'missing exact ticket profile'
    guard=$(role_guard_for "$role") || die 'trusted role workflow has no canonical candidate guard'
    profiles=$(jq -c --arg r "$role" --argjson p "$array" '. + {($r):$p}' <<<"$profiles")
    guards=$(jq -c --arg r "$role" --argjson g "$guard" '. + {($r):$g}' <<<"$guards")
  done
  jq -cn --arg ticket "$ticket" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg build "$build_identity" --arg corpus "$corpus_identity" --arg run "$run_identity" --arg nonce "$nonce" --argjson allow "$source_allowlist" --argjson profiles "$profiles" --argjson guards "$guards" '{ticketIdentity:$ticket,releaseIdentity:("candidate:"+$tested),trustAnchorSha:$anchor,testedSourceSha:$tested,workflowSignerSha:$signer,workflowSignerRef:"refs/heads/master",baseSha:$base,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:$allow,buildIdentity:$build,corpusIdentity:$corpus,runIdentity:$run,artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:$signer},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$signer},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:$signer}},requiredRoleGuards:$guards,requiredEvidenceClasses:$profiles}' >"$expected"
  expected_digest=$(sha256_file "$expected")
}
summary() { jq -cn --arg status "$1" --arg runIdentity "$run_identity" --argjson workflowRunId "${run_id:-0}" --argjson runAttempt "${attempt:-0}" --arg trustAnchorSha "$anchor" --arg workflowSignerSha "$workflow_signer" --arg testedSourceSha "$tested" --argjson result null --arg report "$output" '{status:$status,runIdentity:$runIdentity,workflowRunId:$workflowRunId,runAttempt:$runAttempt,trustAnchorSha:$trustAnchorSha,workflowSignerSha:$workflowSignerSha,testedSourceSha:$testedSourceSha,result:$result,report:$report}'; }
validate_schema() {
  local schema=$1 instance=$2 schema_dir schema_name schema_base_uri
  command -v check-jsonschema >/dev/null 2>&1 || return 1
  # The aggregate schema has an HTTPS $id but intentionally references the
  # immutable role schema by a relative filename.  Override that retrieval
  # base with the trusted checkout's local schema file, so validation neither
  # follows the HTTPS identifier nor lets an instance select another schema.
  schema_dir=$(realpath -e -- "$(dirname -- "$schema")") || return 1
  schema_name=$(basename -- "$schema") || return 1
  schema_base_uri="file://$schema_dir/$schema_name"
  check-jsonschema --no-cache --schemafile "$schema" --base-uri "$schema_base_uri" "$instance"
}

derive_receipt_digest_transport_schema() {
  local schema=$1 fragment=$2
  # Do not restate a structural subset in jq. The fragment roots validation at
  # the authoritative definition and retains every definition it can reach.
  jq -ce '
    {
      "$schema": .["$schema"],
      "$ref": "#/$defs/receiptDigestTransport",
      "$defs": .["$defs"]
    }
    | select((.["$schema"] | type) == "string")
    | select((.["$defs"] | type) == "object")
    | select((.["$defs"].receiptDigestTransport | type) == "object")
  ' "$schema" >"$fragment"
}

validate_receipt_digest_transport_schema() {
  local instance=$1 fragment=$tmp/receipt-digest-transport.schema.json
  derive_receipt_digest_transport_schema "$RECEIPT_TRANSPORT_SCHEMA" "$fragment" || return 1
  validate_schema "$fragment" "$instance" >/dev/null
}

dispatch_run_id() {
  local dispatch=$1 run
  run=$(jq -er '.workflow_run_id | select(type == "number" and . > 0) | floor' <<<"$dispatch") || return 1
  jq -e --argjson id "$run" '
    .workflow_run_id == $id and
    (.run_url | type == "string" and length > 0) and
    (.html_url | type == "string" and length > 0)
  ' <<<"$dispatch" >/dev/null || return 1
  printf '%s\n' "$run"
}
rejected() {
  local code=$1 detail=$2 report_tmp
  # Exit 1 is reserved for a durable, schema-valid fail-closed decision.  A
  # broken output parent, temporary file, JSON writer, validator, or rename is
  # an operational failure, so leave any previous report untouched and exit 2.
  prepare_output_parent || die 'rejected aggregate output parent is unavailable'
  report_tmp=$(mktemp "$(dirname "$output")/.managed-evidence.XXXXXX") || die 'rejected aggregate temporary report creation failed'
  if ! jq -cn --slurpfile expected "$expected" --arg digest "$expected_digest" --arg code "$code" --arg detail "$detail" --argjson version "$AGGREGATE_SCHEMA_VERSION" '{schemaVersion:$version,expectedIdentity:$expected[0],expectedIdentitySha256:$digest,expectedIdentityArtifact:null,receiptDigestTransportArtifact:null,generatedAt:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),mode:"trusted-anchor-local",status:"rejected",roleEvidence:[],compatibilityStage:null,coordinatorExecution:null,aggregationChecks:{rolesComplete:false,identityCompared:false,trustAnchorVerified:false,trustedSurfacesUnchanged:false,sourceAllowlistVerified:false,evidenceProfileVerified:false,roleResultsPassed:false,candidatePlacementVerified:false,candidateTopologyVerified:false,candidateLabelsVerified:false,candidateCompletionVerified:false,sealOriginsAuthenticated:false,hostedOriginVerified:false,compatibilityStageVerified:null,artifactNamesVerified:false,artifactIntegrityVerified:false,bundleContentsVerified:false,filesystemEvidenceVerified:false,imageVersionsCompatible:false},rejectionReasons:[{code:$code,detail:$detail}]}' >"$report_tmp"; then
    rm -f -- "$report_tmp"
    die 'rejected aggregate JSON generation failed'
  fi
  if ! validate_schema "$AGGREGATE_SCHEMA" "$report_tmp"; then
    rm -f -- "$report_tmp"
    die 'rejected aggregate schema validation failed'
  fi
  if ! mv -f -- "$report_tmp" "$output"; then
    rm -f -- "$report_tmp"
    die 'rejected aggregate atomic publication failed'
  fi
  summary rejected
}
prepare_output_parent() {
  local requested_parent canonical_parent
  requested_parent=$(dirname -- "$output") || return 1
  mkdir -p -- "$requested_parent" || return 1
  canonical_parent=$(realpath -e -- "$requested_parent") || return 1
  # The declared report path was compared against the canonical evidence root
  # before authentication. Recheck after creation so an absent parent cannot
  # turn a later mktemp or rename into a symlink escape.
  [[ $canonical_parent == "$requested_parent" &&
     ( $canonical_parent == "$evidence_root" || $canonical_parent == "$evidence_root"/* ) &&
     $canonical_parent != "$anchor_root" && $canonical_parent != "$anchor_root"/* ]] || return 1
  [[ ! -L $canonical_parent ]] || return 1
}
require_token() {
  [[ -n ${GH_TOKEN:-} && ${GH_TOKEN} != *$'\n'* && ${GH_TOKEN} != *$'\r'* ]] || die 'GH_TOKEN is required'
  umask 077
  # Curl's config keeps the secret out of process arguments, stdout, reports,
  # and artifacts. It is removed by the EXIT trap before coordinator execution.
  printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github+json"\nheader = "X-GitHub-Api-Version: %s"\n' "$GH_TOKEN" "$API_VERSION" >"$auth_config"
}
api() {
  # Callers must never turn an unavailable API observation into evidence. Keep
  # response bytes on stdout, but return a typed operational status for retry
  # and terminal exit-2 routing. GitHub's 429/5xx/transport class is retriable
  # only at the bounded run-poll boundary; 401/403 is immediately operational.
  local body status curl_status
  body=$(mktemp "$tmp/api-response.XXXXXX") || return "$API_FAILURE"
  if status=$("$CURL_BIN" --silent --show-error --location --config "$auth_config" --output "$body" --write-out '%{http_code}' "$@"); then curl_status=0; else curl_status=$?; fi
  if ((curl_status != 0)); then rm -f -- "$body"; return "$API_TRANSIENT"; fi
  case $status in
    2??) cat -- "$body"; rm -f -- "$body"; return 0;;
    408|425|429|5??) rm -f -- "$body"; return "$API_TRANSIENT";;
    401|403) rm -f -- "$body"; return "$API_PERMISSION";;
    *) rm -f -- "$body"; return "$API_FAILURE";;
  esac
}
operational_api_failure() {
  local status=$1 context=$2
  case $status in
    "$API_TRANSIENT") die "$context: transient GitHub transport, server, or rate-limit failure";;
    "$API_PERMISSION") die "$context: GitHub authentication or permission was denied";;
    "$API_FAILURE") die "$context: GitHub API response was unavailable or invalid";;
    *) return 1;;
  esac
}
is_operational_api_status() {
  case $1 in
    "$API_TRANSIENT"|"$API_PERMISSION"|"$API_FAILURE") return 0;;
    *) return 1;;
  esac
}
close_nonstdio_fds() {
  local descriptor number target
  local descriptors
  # Snapshot first: iterating /proc can itself create a directory descriptor;
  # it must not be mistaken for a capability that survives into Bubblewrap.
  descriptors=$(printf '%s\n' /proc/self/fd/[0-9]* | sed 's!.*/!!')
  for number in $descriptors; do
    [[ $number =~ ^[0-9]+$ && $number -gt 2 && $number != 255 ]] || continue
    eval "exec ${number}>&-" 2>/dev/null || true
  done
  for descriptor in /proc/self/fd/*; do
    [[ -e $descriptor ]] || continue
    number=${descriptor##*/}
    [[ $number =~ ^[0-9]+$ && $number -gt 2 && $number != 255 ]] || continue
    target=$(readlink "$descriptor" 2>/dev/null || true)
    [[ $target == /proc/*/fd ]] && continue
    return 1
  done
}
spike_id_for_ticket() {
  case "$1" in BURL-H001) printf SPK-BURL-H001;; BURL-H002) printf SPK-BURL-H002;; BURL-I001) printf SPK-BURL-I001;; BURL-L001) printf SPK-BURL-L001;; BURL-O001) printf SPK-BURL-O001;; *) return 1;; esac
}
spike_field() {
  local spike=$1 field=$2
  awk -v spike="$spike" -v field="$field" '
    /^\[\[spikes\]\]/ {on=0}
    $0 == "id = \"" spike "\"" {on=1; next}
    on && $0 ~ "^" field "[[:space:]]*=" {sub(/^[^=]*=[[:space:]]*/, ""); sub(/^"/, ""); sub(/"$/, ""); print; exit}
  ' "$CONTRACT"
}
prepare_spike_coordinator() {
  local spike=$1 manifest lockfile target binary build raw_root raw_output raw_result raw_results raw_prepare bash_bin cc_bin source_manifest source_lock source_dir bwrap_bin closure_file build_path
  raw_root=$(spike_field "$spike" coordinator_root)
  raw_output=$(spike_field "$spike" coordinator_output_root)
  raw_result=$(spike_field "$spike" coordinator_result)
  raw_results=$(spike_field "$spike" managed_results)
  raw_prepare=$(spike_field "$spike" coordinator_prepare_root)
  spike_coordinator_root=$evidence_root/$raw_root
  spike_output_root=$evidence_root/$raw_output
  spike_result=$evidence_root/$raw_result
  spike_results=$evidence_root/$raw_results
  manifest=$(spike_field "$spike" coordinator_manifest)
  lockfile=$(spike_field "$spike" coordinator_lockfile)
  target=$(spike_field "$spike" coordinator_target_dir)
  binary=$(spike_field "$spike" coordinator_binary)
  build=$(spike_field "$spike" coordinator_build)
  [[ -n $raw_root && -n $raw_output && -n $raw_result && -n $raw_results && -n $raw_prepare && -n $manifest && -n $lockfile && -n $target && -n $binary && -n $build ]] || return 1
  register_owned_cleanup_root "$raw_root" || return 1
  register_owned_cleanup_root "$raw_prepare" || return 1
  # Materialize the already origin-verified tested revision into an owned
  # directory.  No coordinator source, manifest, or lockfile may be read from
  # the trust-anchor checkout merely because it is convenient to do so.
  source_dir=$tmp/verified-tested-source
  mkdir -p "$source_dir" || return 1
  git -C "$anchor_root" archive "$tested" | tar -x -C "$source_dir" || return 1
  source_manifest=$source_dir/$manifest
  source_lock=$source_dir/$lockfile
  [[ -f $source_manifest && ! -L $source_manifest && -f $source_lock && ! -L $source_lock ]] || return 1
  # Coordinator construction and dependency resolution occur before GitHub
  # authentication. The candidate tree and lockfile are read-only inputs; the
  # target directory is the sole writable build output.
  spike_target=$evidence_root/$target
  spike_coordinator_binary=$evidence_root/$binary
  mkdir -p "$spike_target" || return 1
  build=${build//$manifest/$source_manifest}
  build=${build//$target/$spike_target}
  build=${build//$binary/$spike_coordinator_binary}
  bash_bin=$(command -v bash) || return 1
  cc_bin=$(command -v cc) || return 1
  bwrap_bin=$(command -v bwrap) || return 1
  [[ $("$bwrap_bin" --version | awk '{print $NF}') == 0.11.2 ]] || return 1
  command -v nix-store >/dev/null 2>&1 || return 1
  closure_file=$tmp/prepare-closure
  # Cargo's default Linux linker is `cc`. Include the exact locked wrapper and
  # its transitive closure; after env -i the coordinator must not borrow a
  # host compiler or linker through PATH.
  nix-store -qR "$bwrap_bin" "$bash_bin" "$(command -v cargo)" "$cc_bin" | LC_ALL=C sort -u >"$closure_file" || return 1
  build_path="$(dirname "$(command -v cargo)"):$(dirname "$bash_bin"):$(dirname "$cc_bin")"
  # Fetch is locked and credential-free; the subsequent build runs with the
  # network namespace unshared, source/dependency roots read-only, and only
  # the target directory writable.
  env -i PATH="$(dirname "$(command -v cargo)"):$(dirname "$bash_bin")" HOME="$tmp/prepare-home" CARGO_HOME="$tmp/prepare-cargo" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 cargo fetch --locked --manifest-path "$source_manifest" || return 1
  close_nonstdio_fds || return 1
  build_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /source --dir /deps --dir /target --ro-bind "$source_dir" /source --ro-bind "$tmp/prepare-cargo" /deps --bind "$spike_target" /target --chdir /source)
  while IFS= read -r closure; do [[ -n $closure ]] && build_args+=(--ro-bind "$closure" "$closure"); done <"$closure_file"
  sandbox_build=${build//$source_dir/\/source}; sandbox_build=${sandbox_build//$spike_target/\/target}
  # The contract's build command supplies the writable target. PATH is the
  # only compiler build variable needed by a fresh locked Rust binary; do not
  # leak devenv's aggregate flags into this credential-free namespace.
  env -i PATH="$build_path" HOME=/home/coordinator CARGO_HOME=/deps GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 "$bwrap_bin" "${build_args[@]}" "$bash_bin" -ceu "$sandbox_build" || return 1
  spike_toolchain_closure_sha=$(sha256_file "$closure_file")
  [[ -x $spike_coordinator_binary ]] || return 1
  spike_executable_sha=$(sha256_file "$spike_coordinator_binary")
  # Bind the coordinator to its own immutable, anchor-owned source tree rather
  # than the whole repository (which also contains untrusted tested-source
  # data for a Spike).
  spike_source_sha=$(git -C "$anchor_root" rev-parse "$tested:${manifest%/*}" | sha256sum | awk '{print $1}')
  spike_lockfile_sha=$(sha256_file "$source_lock")
  spike_contract_sha=$(sha256_file "$CONTRACT")
  spike_build_command_sha=$(printf %s "$build" | sha256sum | awk '{print $1}')
  : "${spike_toolchain_closure_sha:=$spike_lockfile_sha}"
}
prepare_burl_o004_coordinator() {
  # The coordinator package is intentionally future-owned.  Parse its declared
  # identity before authentication and fail closed until the rotated anchor has
  # the reviewed regular files; never substitute a tested-source script.
  command -v taplo >/dev/null || return 1
  [[ $(taplo get --file-path "$CONTRACT" --output-format json 'ci_bootstrap.non_spike_coordinators."BURL-O004".coordinator_artifact_status' | jq -er .) == future ]] || return 1
  [[ $(taplo get --file-path "$CONTRACT" --output-format json 'ci_bootstrap.non_spike_coordinators."BURL-O004".trust_anchor_rotation_required' | jq -er .) == true ]] || return 1
  return 1
}
stage_spike_inputs() {
  local role member stage role_root
  rm -rf "$spike_coordinator_root" || return 1
  mkdir -p "$spike_coordinator_root/roles" "$spike_output_root" || return 1
  for role in "${ROLES[@]}"; do
    role_root=$spike_coordinator_root/roles/$role
    mkdir -p "$role_root" || return 1
    while IFS= read -r member; do
      safe_path "$member" || return 1
      [[ -f $tmp/role-$role/$member && ! -L $tmp/role-$role/$member ]] || return 1
      mkdir -p "$role_root/$(dirname "$member")" || return 1
      install -m 444 "$tmp/role-$role/$member" "$role_root/$member" || return 1
    done < <(jq -r '.manifest.roleEvidence.internalArtifacts[].name' <<<"$(jq -c --arg r "$role" '.[] | select(.manifest.roleEvidence.role == $r)' <<<"$roles")")
  done
}
spike_commands() {
  local spike=$1
  awk -v spike="$spike" '
    /^\[\[spikes\]\]/ {on=0}
    $0 == "id = \"" spike "\"" {on=1; next}
    on && /^coordinator_steps[[:space:]]*=/ {steps=1; next}
    steps && /^\][[:space:]]*$/ {exit}
    steps && /command = / {
      line=$0; at=index(line, "command = "); line=substr(line, at + 10)
      if (substr(line, 1, 1) == "\"") line=substr(line, 2)
      sub(/"[[:space:]]*[,}][,[:space:]]*$/, "", line)
      gsub("\\\\\"", "\"", line); print line
    }
  ' "$CONTRACT"
}
validate_spike_result() {
  local result=$1 spike=$2
  # The coordinator output is untrusted until it satisfies the complete
  # anchor-owned result contract.  Keep this validator executable with the
  # locked jq helper rather than accepting a small, hand-picked subset of the
  # schema fields.
  validate_schema "$RESULT_SCHEMA" "$result" || return 1
  jq -e --arg spike "$spike" --argjson version "$RESULT_SCHEMA_VERSION" '
    def exact_keys($keys): (keys | sort) == ($keys | sort);
    def allowed_keys($keys): (keys - $keys | length) == 0;
    def nonempty_string: type == "string" and length > 0;
    def sha256: type == "string" and test("^[0-9a-f]{64}$");
    def evidence_class:
      . == "common-functional" or . == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual" or
      . == "managed-evidence-protocol" or . == "managed-evidence-security" or . == "managed-evidence-isolation" or . == "generated-binding-check" or
      . == "static-analysis" or . == "desktop-integration" or . == "ast-measurement" or . == "filesystem-compatibility" or . == "git-protocol" or
      . == "asset-measurement" or . == "packaging-runtime" or . == "packaging-runtime-compatibility" or . == "repeatable-construction";
    def classes: type == "array" and length > 0 and (unique | length) == length and all(.[]; evidence_class);
    def profile:
      exact_keys(["runnerLabel", "imageOS", "imageVersion", "cpuModel", "logicalCpuCount", "memoryBytes", "storageBytes", "logicalViewportWidth", "logicalViewportHeight", "logicalViewportRefreshHz", "logicalViewportVerified", "capabilities"])
      and (.runnerLabel == "ubuntu-22.04" or .runnerLabel == "macos-26" or .runnerLabel == "macos-15")
      and (.imageOS, .imageVersion, .cpuModel | nonempty_string)
      and (.logicalCpuCount, .memoryBytes, .storageBytes | type == "number" and floor == . and . >= 1)
      and .logicalViewportWidth == 1920 and .logicalViewportHeight == 1080 and .logicalViewportRefreshHz == 60
      and (.logicalViewportVerified | type == "boolean")
      and (.capabilities | type == "array" and length > 0 and (unique | length) == length and all(.[]; . == "common-functional" or . == "common-functional-compatibility" or . == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual"))
      and (if .runnerLabel == "macos-15" then all(.capabilities[]; . == "common-functional" or . == "common-functional-compatibility") else true end);
    def input_context:
      exact_keys(["repositoryRevision", "repositoryTreeSha256", "lockfiles", "contractSha256", "schemaSha256", "probeSourceTreeSha256", "probeBinarySha256", "corpusManifestSha256"])
      and (.repositoryRevision | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))
      and (.repositoryTreeSha256, .contractSha256, .schemaSha256, .probeSourceTreeSha256, .probeBinarySha256, .corpusManifestSha256 | sha256)
      and (.lockfiles | type == "object" and length > 0 and all(.[]; sha256));
    def run:
      allowed_keys(["id", "role", "claimedEvidenceClasses", "inputContext", "host", "toolchain", "runtimeEvidence", "commandResults", "measurements", "artifacts"])
      and (.id, .role | nonempty_string)
      and (.claimedEvidenceClasses | classes)
      and (.inputContext | input_context)
      and (.host | allowed_keys(["hostFingerprint", "os", "osVersion", "distribution", "releaseChannel", "architecture", "filesystem", "profile"]) and (.hostFingerprint | sha256) and (.os, .osVersion, .architecture, .filesystem | nonempty_string) and (if has("distribution") then (.distribution | nonempty_string) else true end) and (if has("releaseChannel") then (.releaseChannel == "stable" or .releaseChannel == "lts" or .releaseChannel == "other") else true end) and (.profile | profile))
      and (.toolchain | type == "object" and length > 0 and all(.[]; nonempty_string))
      and (if has("runtimeEvidence") then (.runtimeEvidence | type == "array" and length > 0 and all(.[]; exact_keys(["environment", "os", "distribution", "version", "architecture", "captureSource"]) and (.environment, .os, .distribution, .version, .architecture | nonempty_string) and .captureSource == "system-api-inside-guest")) else true end)
      and (.commandResults | type == "array" and length > 0 and all(.[]; exact_keys(["command", "exitCode", "stdout", "stderr"]) and (.command | nonempty_string) and (.exitCode | type == "number" and floor == . and . >= 0 and . <= 255) and (.stdout, .stderr | type == "string")))
      and (.measurements | type == "array" and length > 0 and all(.[]; exact_keys(["candidate", "name", "value", "unit", "samples"]) and (.candidate, .name, .unit | nonempty_string) and (.value | type == "number") and (.samples | type == "number" and floor == . and . >= 1)))
      and (.artifacts | type == "array" and length > 0 and all(.[]; exact_keys(["path", "kind", "bytes", "sha256"]) and (.path, .kind | nonempty_string) and (.bytes | type == "number" and floor == . and . >= 0) and (.sha256 | sha256)))
      and (if (.claimedEvidenceClasses | any(. == "performance" or . == "linux-platform-regression" or . == "macos-authoritative-visual")) then .host.profile.logicalViewportVerified == true else true end)
      and (if .host.profile.runnerLabel == "macos-15" then all(.claimedEvidenceClasses[]; . == "common-functional" or . == "managed-evidence-protocol" or . == "managed-evidence-security" or . == "static-analysis" or . == "desktop-integration" or . == "packaging-runtime-compatibility") else true end);
    exact_keys(["schemaVersion", "spikeId", "generatedAt", "corpus", "candidates", "gates", "runs", "recommendation", "unresolved"])
    and .schemaVersion == $version and .spikeId == $spike
    and (.generatedAt | type == "string" and test("^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$"))
    and (.corpus | type == "array" and length > 0 and (unique | length) == length and all(.[]; nonempty_string))
    and (.candidates | type == "array" and length > 0 and all(.[]; exact_keys(["name", "version", "configuration"]) and (.name, .version | nonempty_string) and (.configuration | type == "object")))
    and (.gates | type == "array" and length > 0 and all(.[]; exact_keys(["candidate", "name", "passed", "evidence"]) and (.candidate, .name | nonempty_string) and (.passed | type == "boolean") and (.evidence | type == "array" and length > 0 and all(.[]; nonempty_string))))
    and (.runs | type == "array" and length > 0 and all(.[]; run))
    and (.recommendation | nonempty_string)
    and (.unresolved | type == "array" and all(.[]; nonempty_string))
  ' "$result" >/dev/null
}
rfc3339_calendar_valid() {
  local value=$1
  # GNU date is available in the pinned Linux collector closure; the BSD form
  # keeps the launcher usable from the macOS compatibility host as well.
  if date -u -d "$value" +%s >/dev/null 2>&1; then return 0; fi
  date -ju -f '%Y-%m-%dT%H:%M:%SZ' "$value" +%s >/dev/null 2>&1
}
spike_toml_list() {
  local spike=$1 field=$2
  awk -v spike="$spike" -v field="$field" '
    /^\[\[spikes\]\]/ {on=0}
    $0 == "id = \"" spike "\"" {on=1; next}
    on && $0 ~ "^" field "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, ""); print; exit
    }
  ' "$CONTRACT" | jq -ce .
}
authenticated_role_for_result_role() {
  case "$1" in
    linux-x86_64|linux-*) printf linux-x86_64;;
    macos-26-arm64|macos-26-*|macos-current-*|macos-repeat-*|macos-default-*) printf macos-26-arm64;;
    macos-15-arm64|macos-15-*|macos-previous-*) printf macos-15-arm64;;
    *) return 1;;
  esac
}
toml_required_run_roles() {
  local command rest role count index
  while IFS= read -r command; do
    rest=$command
    while [[ $rest =~ --require-role[[:space:]]+([^[:space:],]+) ]]; do
      role=${BASH_REMATCH[1]}
      rest=${rest#*"--require-role $role"}
      count=1
      if [[ $role =~ ^(.+)=([1-9][0-9]*)$ ]]; then role=${BASH_REMATCH[1]}; count=${BASH_REMATCH[2]}; fi
      for ((index = 0; index < count; index++)); do printf '%s\n' "$role"; done
    done
  done < <(spike_commands "$spike_id")
}
image_versions_compatible() {
  local roles_json=$1 result=${2:-} manifest_images
  # The contract records an image tuple for every sealed role manifest, but
  # requires compatibility only before performance or visual aggregation. A
  # functional or packaging-only result must not acquire a stricter rule.
  manifest_images=$(jq -ce --slurpfile expected "$expected" '
    [.[] | .manifest.roleEvidence | {
      role,
      imageOS: .environment.imageOS,
      imageVersion: .environment.imageVersion
    }] as $images
    | ($expected[0].requiredRoleIdentities | sort) as $required_roles
    | if (
        ($images | map(.role) | sort) == $required_roles
        and ($images | length) == ($images | unique_by(.role) | length)
        and all($images[]; (.imageOS | type == "string" and length > 0) and (.imageVersion | type == "string" and length > 0))
      ) then $images else empty end
  ' <<<"$roles_json") || return 1
  [[ -n $result ]] || return 0
  jq -e --argjson images "$manifest_images" --slurpfile expected "$expected" '
    def authenticated_role:
      if . == "linux-x86_64" or startswith("linux-") then "linux-x86_64"
      elif . == "macos-26-arm64" or startswith("macos-26-") or startswith("macos-current-") or startswith("macos-repeat-") or startswith("macos-default-") then "macos-26-arm64"
      elif . == "macos-15-arm64" or startswith("macos-15-") or startswith("macos-previous-") then "macos-15-arm64"
      else error("unknown result role") end;
    all(.runs[];
      .role as $result_role
      | ($result_role | authenticated_role) as $role
      | $expected[0].requiredEvidenceClasses[$role] as $classes
      | if ($classes | index("performance") != null or index("macos-authoritative-visual") != null) then
          ($images[] | select(.role == $role)) as $image
          | .host.profile.imageOS == $image.imageOS
          and .host.profile.imageVersion == $image.imageVersion
        else true
        end
    )
  ' "$result" >/dev/null
}
reconcile_spike_result() {
  local result=$1 role result_role expected_label expected_classes count generated candidates gates required_roles actual_roles required_count actual_count
  spike_rejection_code=
  generated=$(jq -r '.generatedAt' "$result") || return 1
  rfc3339_calendar_valid "$generated" || { spike_rejection_code=aggregation-error; return 1; }
  # A Spike machine result is a reconciliation record, not merely a schema
  # shaped blob. Bind exact run roles (including multiplicity) from trusted
  # coordinator steps, not the broad authentication role names.
  candidates=$(spike_toml_list "$spike_id" candidates) || return 1
  gates=$(spike_toml_list "$spike_id" required_gates) || return 1
  required_roles=$(toml_required_run_roles | jq -Rsc 'split("\n") | map(select(length > 0))') || return 1
  [[ $(jq 'length' <<<"$required_roles") -gt 0 ]] || { spike_rejection_code=aggregation-error; return 1; }
  actual_roles=$(jq -c '[.runs[].role]' "$result") || return 1
  [[ $(jq -c 'sort' <<<"$actual_roles") == "$(jq -c 'sort' <<<"$required_roles")" ]] || { spike_rejection_code=evidence-profile-mismatch; return 1; }
  jq -e --argjson candidates "$candidates" --argjson gates "$gates" '
    ([.runs[].id] | unique | length) == (.runs | length)
    and ([.runs[].artifacts[].path] | unique | length) == ([.runs[].artifacts[].path] | length)
    and ([.gates[].name] | unique | sort) == ($gates | sort)
    and all(.gates[]; .passed == true and (.candidate as $candidate | ($candidates | index($candidate)) != null))
    and ([.candidates[] | (.name + " " + .version)] | sort) == ($candidates | sort)
    and all(.runs[]; ([.artifacts[].sha256] | all(test("^[0-9a-f]{64}$"))) and ([.artifacts[].path] | unique | length) == ([.artifacts[].path] | length))
  ' "$result" >/dev/null || { spike_rejection_code=aggregation-error; return 1; }
  jq -e --arg tested "$tested" 'all(.runs[]; .inputContext.repositoryRevision == $tested)' "$result" >/dev/null || { spike_rejection_code=coordinator-identity-mismatch; return 1; }
  # All authenticated-role observations must carry one common repository and
  # corpus context.  Probe binaries may differ by host and remain attributed
  # inside the individual run, but candidate identity cannot drift by role.
  jq -e '
    [.runs[].inputContext | {repositoryRevision,repositoryTreeSha256,lockfiles,contractSha256,schemaSha256,probeSourceTreeSha256,corpusManifestSha256}]
    | unique | length == 1
  ' "$result" >/dev/null || { spike_rejection_code=coordinator-identity-mismatch; return 1; }
  while IFS= read -r result_role; do
    role=$(authenticated_role_for_result_role "$result_role") || { spike_rejection_code=evidence-profile-mismatch; return 1; }
    expected_label=$(role_label "$role")
    expected_classes=$(jq -c --arg role "$role" '.requiredEvidenceClasses[$role]' "$expected") || return 1
    # A result role can legitimately repeat. `jq -e` otherwise uses the last
    # emitted boolean, allowing an earlier corrupted occurrence to be masked
    # by a later valid one. Require every matched run to satisfy its exact
    # role label and ordered evidence profile.
    jq -e --arg resultRole "$result_role" --arg label "$expected_label" '
      [.runs[] | select(.role == $resultRole)] as $matches
      | ($matches | length > 0)
      and all($matches[]; .host.profile.runnerLabel == $label)
    ' "$result" >/dev/null || { spike_rejection_code=runner-label-mismatch; return 1; }
    jq -e --arg resultRole "$result_role" --argjson classes "$expected_classes" '
      [.runs[] | select(.role == $resultRole)] as $matches
      | ($matches | length > 0)
      and all($matches[]; .claimedEvidenceClasses == $classes)
    ' "$result" >/dev/null || { spike_rejection_code=evidence-profile-mismatch; return 1; }
  done < <(jq -r '.runs[].role' "$result")
  image_versions_compatible "$roles" "$result" || { spike_rejection_code=mixed-image-version; return 1; }
  [[ -z $spike_rejection_code ]] || return 1
}
run_spike_coordinator() {
  local command staged_binary output_tmp result_tmp bwrap_bin bash_bin mkdir_bin cp_bin jq_bin runtime_path closure_path
  [[ $(sha256_file "$spike_coordinator_binary") == "$spike_executable_sha" ]] || return 1
  [[ $(sha256_file "$CONTRACT") == "$spike_contract_sha" ]] || return 1
  staged_binary=$tmp/coordinator-bin
  install -m 555 "$spike_coordinator_binary" "$staged_binary" || return 1
  output_tmp=$tmp/coordinator-output
  mkdir "$output_tmp" || return 1
  bwrap_bin=$(command -v bwrap) || return 1
  bash_bin=$(command -v bash) || return 1
  mkdir_bin=$(command -v mkdir) || return 1
  cp_bin=$(command -v cp) || return 1
  jq_bin=$(command -v jq) || return 1
  # Mount only the pinned runtime closure, explicit inputs, contract and
  # coordinator binary.  In particular never give an untrusted coordinator a
  # read-only view of host root (which exposes credentials and network clients).
  runtime_path=$(dirname "$bash_bin"):$(dirname "$mkdir_bin"):$(dirname "$cp_bin"):$(dirname "$jq_bin")
  closure_path=$tmp/runtime-closure
  command -v nix-store >/dev/null 2>&1 || return 1
  nix-store -qR "$bwrap_bin" "$bash_bin" "$mkdir_bin" "$cp_bin" "$jq_bin" | LC_ALL=C sort -u >"$closure_path" || return 1
  while IFS= read -r command; do
    [[ -n $command ]] || continue
    bwrap_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /inputs --dir /output --dir /contract --dir /coordinator --ro-bind "$spike_coordinator_root" /inputs --ro-bind "$(dirname "$CONTRACT")" /contract --ro-bind "$staged_binary" /coordinator/bin --bind "$output_tmp" /output --chdir /output)
    while IFS= read -r closure; do [[ -n $closure ]] && bwrap_args+=(--ro-bind "$closure" "$closure"); done <"$closure_path"
    # This is the sole cross-role producer handoff. In particular the
    # packaging coordinator receives macOS 26 bytes only below
    # /inputs/roles/macos-26-arm64 after manifest/hash verification.
    env -i PATH="$runtime_path" HOME=/home/coordinator XDG_CONFIG_HOME=/tmp/xdg-config XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data GH_CONFIG_DIR=/tmp/gh-config GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 COORDINATOR_BIN=/coordinator/bin INPUT_ROOT=/inputs BURLMD_AUTHENTICATED_STAGE_ROOT=/inputs OUTPUT_ROOT=/output CONTRACT_ROOT=/contract \
      "$bwrap_bin" "${bwrap_args[@]}" "$bash_bin" -ceu "PATH='$runtime_path'; export PATH; $command" || return 1
  done < <(spike_commands "$spike_id")
  spike_execution_closure_sha=$(sha256_file "$closure_path")
  [[ -f $output_tmp/results.json && ! -L $output_tmp/results.json ]] || return 1
  # This strict minimum is shared by all five declared result schemas; the
  # The ticket's Spike ID remains bound to the TOML entry, not candidate bytes.
  validate_spike_result "$output_tmp/results.json" "$spike_id" || return 1
  reconcile_spike_result "$output_tmp/results.json" || return 1
  result_tmp=$(mktemp "$(dirname "$spike_results")/.managed-results.XXXXXX") || return 1
  install -m 644 "$output_tmp/results.json" "$result_tmp" || return 1
  mv -f "$result_tmp" "$spike_results" || return 1
  probe_coordinator_isolation "$bwrap_bin" "$bash_bin" "$closure_path" "$output_tmp" || return 1
  spike_coordinator_execution=$(jq -cn --arg executable "$spike_executable_sha" --arg source "$spike_source_sha" --arg lock "$spike_lockfile_sha" --arg toolchain "$spike_toolchain_closure_sha" --arg runtime "$spike_execution_closure_sha" --arg contract "$spike_contract_sha" --arg build "$spike_build_command_sha" --argjson network "$isolation_network" --argjson credentials "$isolation_credentials" --argjson descriptors "$isolation_descriptors" --argjson user_state "$isolation_user_state" --argjson inputs "$isolation_inputs" --argjson output "$isolation_output" --argjson forbidden "$isolation_forbidden_tools" --argjson canaries "$isolation_canaries" --argjson representative "$isolation_representative" '{executableSha256:$executable,sourceTreeSha256:$source,lockfileSha256:$lock,toolchainClosureSha256:$toolchain,executionClosureSha256:$runtime,contractSha256:$contract,buildCommandSha256:$build,sandbox:"bubblewrap-0.11.2",networkIsolated:$network,credentialsSanitized:$credentials,descriptorsClosed:$descriptors,emptyUserState:$user_state,inputsReadOnly:$inputs,outputOnlyWritable:$output,forbiddenToolsAbsent:$forbidden,credentialCanariesAbsent:$canaries,representativeResultPassed:$representative}')
}

# A report may state isolation facts only after an executable probe has observed
# the exact closure and namespace used by coordinator commands.  Keep the
# probe's output in the owned scratch directory: no candidate file can supply
# or influence these values.
probe_coordinator_isolation() {
  local bwrap_bin=$1 bash_bin=$2 closure_file=$3 output_dir=$4 closure probe_result runtime_path
  runtime_path=$(dirname "$bash_bin")
  probe_result=$tmp/isolation-probe.json
  [[ $("$bwrap_bin" --version | awk '{print $NF}') == 0.11.2 ]] || return 1
  while IFS= read -r closure; do
    case "$closure" in *'/bin/git'|*'/bin/gh'|*'/bin/ssh'|*'/bin/curl'|*'/bin/wget'|*'/bin/aws'|*'/bin/az'|*'/bin/gcloud') return 1;; esac
  done <"$closure_file"
  probe_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /inputs --dir /output --ro-bind "$spike_coordinator_root" /inputs --bind "$output_dir" /output --chdir /output)
  while IFS= read -r closure; do [[ -n $closure ]] && probe_args+=(--ro-bind "$closure" "$closure"); done <"$closure_file"
  env -i PATH="$runtime_path" HOME=/home/coordinator XDG_CONFIG_HOME=/tmp/xdg-config XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data GH_CONFIG_DIR=/tmp/gh-config GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
    "$bwrap_bin" "${probe_args[@]}" "$bash_bin" -ceu '
      test ! -e /home/coordinator/.gitconfig
      test ! -e /proc/self/fd/19
      ! command -v gh; ! command -v git; ! command -v ssh; ! command -v curl; ! command -v wget
      ! (exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null
      set -- /inputs/*; test "$1" != "/inputs/*"
      test ! -w /inputs
      printf "%s\\n" "{\"networkIsolated\":true,\"credentialsSanitized\":true,\"descriptorsClosed\":true,\"emptyUserState\":true,\"inputsReadOnly\":true,\"outputOnlyWritable\":true,\"forbiddenToolsAbsent\":true,\"credentialCanariesAbsent\":true,\"representativeResultPassed\":true}" >/output/.isolation-probe.json
    ' || return 1
  install -m 600 "$output_dir/.isolation-probe.json" "$probe_result" || return 1
  jq -e 'keys | sort == ["credentialCanariesAbsent", "credentialsSanitized", "descriptorsClosed", "emptyUserState", "forbiddenToolsAbsent", "inputsReadOnly", "networkIsolated", "outputOnlyWritable", "representativeResultPassed"] and all(.[]; . == true)' "$probe_result" >/dev/null || return 1
  isolation_network=$(jq -c '.networkIsolated' "$probe_result")
  isolation_credentials=$(jq -c '.credentialsSanitized' "$probe_result")
  isolation_descriptors=$(jq -c '.descriptorsClosed' "$probe_result")
  isolation_user_state=$(jq -c '.emptyUserState' "$probe_result")
  isolation_inputs=$(jq -c '.inputsReadOnly' "$probe_result")
  isolation_output=$(jq -c '.outputOnlyWritable' "$probe_result")
  isolation_forbidden_tools=$(jq -c '.forbiddenToolsAbsent' "$probe_result")
  isolation_canaries=$(jq -c '.credentialCanariesAbsent' "$probe_result")
  isolation_representative=$(jq -c '.representativeResultPassed' "$probe_result")
}
workflow_run_is_fresh_dispatch() {
  local response=$1
  jq -e --arg signer "$workflow_signer" '
    .event == "workflow_dispatch" and .head_branch == "master" and
    .head_sha == $signer and
    (.run_attempt | type == "number" and . == 1) and
    # The GitHub workflow-run REST object identifies the workflow by its exact
    # repository-relative path.  The signer branch and immutable commit are
    # independently checked above; accepting a synthetic @ref suffix here
    # would make the REST shape itself less strict.
    .path == ".github/workflows/ci.yml"
  ' <<<"$response" >/dev/null
}

managed_observation_now_microseconds() {
  # Pinned Bash 5.3 obtains this value from the system monotonic clock on the
  # Linux collector. Do not fall back to a wall clock: an unavailable or
  # malformed required monotonic reading fails the observation closed.
  local epoch_before=${EPOCHSECONDS-} seconds=${BASH_MONOSECONDS-} epoch_after=${EPOCHSECONDS-}
  [[ $seconds =~ ^[0-9]+$ && ${#seconds} -le 12 ]] || return 1
  [[ $epoch_before =~ ^[0-9]+$ && $epoch_after =~ ^[0-9]+$ ]] || return 1
  # Bash documents EPOCHSECONDS as its fallback when the system has no
  # monotonic clock. Reject that fallback before constructing the deadline.
  [[ $seconds != "$epoch_before" && $seconds != "$epoch_after" ]] || return 1
  printf '%s\n' "$((10#$seconds * 1000000))"
}

managed_observation_duration() {
  local microseconds=$1
  # The transfer timeout in curl is millisecond-based. Reject a smaller remainder
  # instead of risking conversion to its unlimited zero value.
  ((microseconds >= 1000)) || return 1
  printf '%d.%06d' "$((microseconds / 1000000))" "$((microseconds % 1000000))"
}

managed_observation_advance() {
  local observed
  observed=$(managed_observation_now_microseconds) || return 1
  [[ $observed =~ ^[0-9]+$ ]] || return 1
  # Equal readings are normal at the one-second resolution of BASH_MONOSECONDS.
  # A backwards reading is not normal and fails closed.
  ((observed >= observation_last)) || return 1
  observation_last=$observed
  now=$observed
}

wait_for_run() {
  local started deadline now observation_last remaining request_timeout sleep_budget sleep_duration
  local observation_budget=21600000000 observation_resolution=1000000
  local response status conclusion failures=0 result
  started=$(managed_observation_now_microseconds) || return "$API_FAILURE"
  observation_last=$started
  # BASH_MONOSECONDS advances in integral seconds. Reserve one full clock tick
  # so a reading equal to the computed deadline cannot represent a real time
  # up to almost one second beyond the contract's 21,600-second maximum.
  deadline=$((started + observation_budget - observation_resolution))
  while :; do
    managed_observation_advance || return "$API_FAILURE"
    remaining=$((deadline - now))
    ((remaining > 0)) || return 4
    request_timeout=$(managed_observation_duration "$remaining") || return 4
    if response=$(api --max-time "$request_timeout" "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id"); then result=0; else result=$?; fi
    managed_observation_advance || return "$API_FAILURE"
    ((now <= deadline)) || return 4
    if ((result != 0)); then
      if ((result == API_TRANSIENT && failures < POLL_TRANSIENT_RETRIES)); then
        failures=$((failures + 1))
        managed_observation_advance || return "$API_FAILURE"
        ((now <= deadline)) || return 4
        remaining=$((deadline - now))
        ((remaining > 0)) || return 4
        sleep_budget=$((failures * 1000000))
        ((sleep_budget <= remaining)) || sleep_budget=$remaining
        sleep_duration=$(managed_observation_duration "$sleep_budget") || return 4
        sleep "$sleep_duration"
        continue
      fi
      return "$result"
    fi
    failures=0
    status=$(jq -r '.status // empty' <<<"$response") || return "$API_FAILURE"
    conclusion=$(jq -r '.conclusion // empty' <<<"$response") || return "$API_FAILURE"
    workflow_run_is_fresh_dispatch "$response" || return 2
    # JSON parsing and identity validation consume the same observation budget.
    # Refresh at the decision boundary so neither a terminal success nor the
    # next poll sleep uses the stale post-transfer remainder.
    managed_observation_advance || return "$API_FAILURE"
    ((now <= deadline)) || return 4
    [[ $status == completed ]] && { [[ $conclusion == success ]] && return 0 || return 3; }
    remaining=$((deadline - now))
    ((remaining > 0)) || return 4
    sleep_budget=5000000
    ((sleep_budget <= remaining)) || sleep_budget=$remaining
    sleep_duration=$(managed_observation_duration "$sleep_budget") || return 4
    sleep "$sleep_duration"
  done
}

filesystem_evidence_verified() {
  local roles_json=$1
  jq -e '
    type == "array" and length == 3 and
    all(.[]; (.manifest.roleEvidence.environment.filesystem | type == "string" and length > 0))
  ' <<<"$roles_json" >/dev/null
}

filesystem_manifest_verified() {
  local manifest=$1 captured=${2:-}
  jq -e --arg captured "$captured" '
    (.roleEvidence.environment.filesystem | type == "string" and length > 0)
    and (if $captured == "" then true else .roleEvidence.environment.filesystem == $captured end)
  ' "$manifest" >/dev/null
}

filesystem_role_verified() {
  local role_json=$1 captured=$2
  jq -e --arg captured "$captured" '
    (.manifest.roleEvidence.environment.filesystem | type == "string" and length > 0)
    and .manifest.roleEvidence.environment.filesystem == $captured
  ' "$role_json" >/dev/null
}

artifact_by_name() {
  local inventory=$1 name=$2 count
  count=$(jq --arg n "$name" '[.artifacts[] | select(.name == $n and .expired == false)] | length' "$inventory")
  [[ $count == 1 ]] || return 1
  jq -ce --arg n "$name" '.artifacts[] | select(.name == $n and .expired == false)' "$inventory"
}
receipt_digest_transport() {
  # The caller transport is selected by its reserved name, then rebound to the
  # immutable REST object and raw ID-addressed archive before any JSON member
  # is extracted.  Do not let a ZIP member choose an artifact identity.
  local inventory=$1 destination=$2 nonce=${run_identity#managed:} name listed id rest archive extracted hash repository_id transport
  receipt_transport_rejection_code=artifact-api-mismatch
  name="managed-evidence-receipt-digests-$nonce"
  listed=$(artifact_by_name "$inventory" "$name") || return 1
  id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$listed") || return 1
  if rest=$(api "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id"); then :; else return $?; fi
  jq -e --argjson id "$id" --arg name "$name" --argjson run "$run_id" --argjson listed "$listed" '
    .id == $id and .name == $name and .expired == false and
    (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.workflow_run.id | tonumber) == $run and
    (.workflow_run.repository_id | type == "number" and . > 0) and
    .id == $listed.id and .name == $listed.name and .digest == $listed.digest and
    (.workflow_run.id | tonumber) == ($listed.workflow_run.id | tonumber) and
    (.workflow_run.repository_id | tonumber) == ($listed.workflow_run.repository_id | tonumber)
  ' <<<"$rest" >/dev/null || return 1
  repository_id=$(jq -er '.workflow_run.repository_id | select(type == "number" and . > 0) | floor' <<<"$rest") || return 1
  archive=$tmp/receipt-digest-transport-$id.zip
  if api -L "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id/zip" >"$archive"; then :; else return $?; fi
  hash=$(sha256_file "$archive") || return 1
  [[ $(jq -r '.digest' <<<"$rest") == "sha256:$hash" ]] || { receipt_transport_rejection_code=artifact-corrupt; return 1; }
  extracted=$tmp/receipt-digest-transport-$id
  safe_zip_member "$archive" receipt-upload-digests.json || { receipt_transport_rejection_code=artifact-corrupt; return 1; }
  mkdir "$extracted" || return 1
  unzip -qq "$archive" -d "$extracted" || { receipt_transport_rejection_code=artifact-corrupt; return 1; }
  [[ -f $extracted/receipt-upload-digests.json && ! -L $extracted/receipt-upload-digests.json ]] || { receipt_transport_rejection_code=artifact-corrupt; return 1; }
  install -m 600 "$extracted/receipt-upload-digests.json" "$destination"
  # Schema validation supplements the retained identity, ordering, and REST
  # comparisons below. The authoritative source is always the anchor checkout.
  validate_receipt_digest_transport_schema "$destination" || { receipt_transport_rejection_code=artifact-api-mismatch; return 1; }
  transport=$(jq -ce --arg digest "$expected_digest" --arg signer "$workflow_signer" --arg nonce "$nonce" --argjson run "$run_id" --argjson repository "$repository_id" '
    . as $transport | select([
      (($transport | keys | sort) == ["artifactNonce","expectedIdentitySha256","receipts","repositoryId","runAttempt","schemaVersion","workflowRunId","workflowSignerSha"]),
      ($transport.schemaVersion == 1), ($transport.expectedIdentitySha256 == $digest), ($transport.repositoryId == $repository),
      ($transport.workflowRunId == $run), ($transport.runAttempt == 1), ($transport.workflowSignerSha == $signer), ($transport.artifactNonce == $nonce),
      (($transport.receipts | type) == "array"), (($transport.receipts | length) == 3),
      ($transport.receipts == [
        {role:"linux-x86_64",artifactId:$transport.receipts[0].artifactId,artifactName:("managed-evidence-seal-receipt-linux-x86_64-" + $nonce),uploadActionDigest:$transport.receipts[0].uploadActionDigest},
        {role:"macos-26-arm64",artifactId:$transport.receipts[1].artifactId,artifactName:("managed-evidence-seal-receipt-macos-26-arm64-" + $nonce),uploadActionDigest:$transport.receipts[1].uploadActionDigest},
        {role:"macos-15-arm64",artifactId:$transport.receipts[2].artifactId,artifactName:("managed-evidence-seal-receipt-macos-15-arm64-" + $nonce),uploadActionDigest:$transport.receipts[2].uploadActionDigest}
      ]),
      ([$transport.receipts[].artifactId] | all(type == "number" and . > 0)), ([$transport.receipts[].artifactId] | unique | length == 3),
      ([$transport.receipts[].uploadActionDigest] | all(type == "string" and test("^[0-9a-f]{64}$")))
    ] | all)
  ' "$destination") || { receipt_transport_rejection_code=artifact-api-mismatch; return 1; }
  jq -cn --argjson transport "$transport" --argjson id "$id" --arg name "$name" --arg digest "$(jq -r '.digest' <<<"$rest")" --arg hash "$hash" '{transport:$transport,observation:{artifactId:$id,artifactName:$name,artifactDigest:$digest,downloadedArtifactSha256:$hash}}'
}
safe_zip_member() {
  local archive=$1 expected_name=$2 listing line
  listing=$(unzip -Z1 "$archive") || return 1
  [[ $listing == "$expected_name" ]] || return 1
  # ZIP central-directory names are validated before extraction, and extraction
  # happens in a new owned directory. A link is not a valid evidence member.
  case "$listing" in /*|*'..'*|*'//'|*/|*$'\n'*) return 1;; esac
}
download_one_member_zip() {
  local artifact_json=$1 expected_name=$2 destination=$3 id archive extracted
  id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$artifact_json") || return 1
  archive=$tmp/artifact-$id.zip
  api -L "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id/zip" >"$archive" || return $?
  safe_zip_member "$archive" "$expected_name" || return 1
  extracted=$tmp/extracted-$id
  mkdir "$extracted" || return 1
  unzip -qq "$archive" -d "$extracted" || return 1
  [[ ! -L $extracted/$expected_name && -f $extracted/$expected_name ]] || return 1
  install -m 600 "$extracted/$expected_name" "$destination"
}
download_sealing_receipt_zip() {
  local artifact_json=$1 receipt_destination=$2 bundle_destination=$3 id archive extracted listing
  id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$artifact_json") || return 1
  archive=$tmp/artifact-$id.zip
  api -L "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id/zip" >"$archive" || return $?
  listing=$(unzip -Z1 "$archive" | LC_ALL=C sort) || return 1
  [[ $listing == $'ci-seal-receipt-attestation.sigstore.json\nci-seal-receipt.json' ]] || return 1
  extracted=$tmp/extracted-receipt-$id
  mkdir "$extracted" || return 1
  unzip -qq "$archive" -d "$extracted" || return 1
  for member in ci-seal-receipt.json ci-seal-receipt-attestation.sigstore.json; do
    [[ -f $extracted/$member && ! -L $extracted/$member ]] || return 1
  done
  install -m 600 "$extracted/ci-seal-receipt.json" "$receipt_destination"
  install -m 600 "$extracted/ci-seal-receipt-attestation.sigstore.json" "$bundle_destination"
}
download_exact_members_zip() {
  # Artifact downloads are addressed by immutable service ID.  Names are
  # checked only after the ID lookup; they never select a downloadable object.
  local artifact_json=$1 destination=$2; shift 2
  local id archive extracted listing expected actual member
  id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$artifact_json") || return 1
  [[ ! -e $destination ]] || return 1
  archive=$tmp/artifact-$id.zip
  api -L "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id/zip" >"$archive" || return $?
  listing=$(unzip -Z1 "$archive") || return 1
  expected=$(printf '%s\n' "$@" | LC_ALL=C sort)
  actual=$(printf '%s\n' "$listing" | LC_ALL=C sort)
  [[ $actual == "$expected" ]] || return 1
  while IFS= read -r member; do
    [[ -n $member ]] || return 1
    case "$member" in /*|*'..'*|*'//'|*/|*$'\n'*) return 1;; esac
  done <<<"$listing"
  mkdir "$destination" || return 1
  unzip -qq "$archive" -d "$destination" || return 1
  for member in "$@"; do
    [[ -f $destination/$member && ! -L $destination/$member ]] || return 1
  done
}
safe_path() {
  local value=$1
  [[ $value != /* && $value != */ && $value != *'..'* && $value != *'//' && $value != *$'\n'* && $value != *$'\r'* ]]
}
safe_sealed_bundle() {
  local sealed=$1 inner=$2 stage=$3 listing verbose expected
  expected=ci-role-evidence.tar.zst
  listing=$(tar --zstd -tf "$sealed") || return 1
  [[ $listing == "$expected" ]] || return 1
  verbose=$(tar --zstd -tvf "$sealed") || return 1
  [[ $verbose == -* && $verbose != h* ]] || return 1
  mkdir "$stage" || return 1
  tar --zstd -xf "$sealed" -C "$stage" --no-same-owner --no-same-permissions || return 1
  [[ -f $stage/$expected && ! -L $stage/$expected ]] || return 1
  install -m 600 "$stage/$expected" "$inner"
}
safe_role_bundle() {
  local inner=$1 stage=$2 manifest=$3 listing verbose declared actual file name bytes hash
  listing=$(tar --zstd -tf "$inner") || return 1
  [[ $(printf '%s\n' "$listing" | sort | uniq -d) == '' ]] || return 1
  verbose=$(tar --zstd -tvf "$inner") || return 1
  while IFS= read -r line; do [[ $line == -* && $line != h* ]] || return 1; done <<<"$verbose"
  while IFS= read -r name; do safe_path "$name" || return 1; done <<<"$listing"
  mkdir "$stage" || return 1
  tar --zstd -xf "$inner" -C "$stage" --no-same-owner --no-same-permissions || return 1
  [[ -f $stage/ci-role-evidence.json && ! -L $stage/ci-role-evidence.json ]] || return 1
  install -m 600 "$stage/ci-role-evidence.json" "$manifest"
  declared=$(jq -ce '[.roleEvidence.internalArtifacts[] | {(.name): {bytes,sha256}}] | add' "$manifest") || return 1
  actual=$(find "$stage" -type f -printf '%P\n' | LC_ALL=C sort)
  [[ $actual == $(jq -r 'keys[]' <<<"$declared" | { printf 'ci-role-evidence.json\n'; cat; } | LC_ALL=C sort) ]] || return 1
  while IFS= read -r name; do
    [[ $name == ci-role-evidence.json ]] && continue
    safe_path "$name" || return 1
    file=$stage/$name
    [[ -f $file && ! -L $file ]] || return 1
    bytes=$(wc -c <"$file" | tr -d ' '); hash=$(sha256_file "$file")
    [[ $(jq -r --arg n "$name" '.[$n].bytes' <<<"$declared") == "$bytes" && $(jq -r --arg n "$name" '.[$n].sha256' <<<"$declared") == "$hash" ]] || return 1
  done < <(jq -r 'keys[]' <<<"$declared")
}
manifest_shape_valid() {
  local manifest=$1 role=$2
  validate_schema "$ROLE_SCHEMA" "$manifest" || return 1
  jq -e --slurpfile expected "$expected" --arg digest "$expected_digest" --arg role "$role" --argjson roleSchemaVersion "$ROLE_SCHEMA_VERSION" '
    (keys | sort) == ["expectedIdentity","expectedIdentitySha256","roleEvidence","schemaVersion"]
    and .schemaVersion == $roleSchemaVersion
    and .expectedIdentitySha256 == $digest and .expectedIdentity == $expected[0]
    and (.roleEvidence | keys | sort) == ["capturedIdentity","compatibilityStage","environment","evidenceClasses","gates","internalArtifacts","role","toolchain","viewport"]
    and .roleEvidence.role == $role and .roleEvidence.capturedIdentity.roleIdentity == $role
    and .roleEvidence.capturedIdentity.ticketIdentity == $expected[0].ticketIdentity
    and .roleEvidence.capturedIdentity.trustAnchorSha == $expected[0].trustAnchorSha
    and .roleEvidence.capturedIdentity.testedSourceSha == $expected[0].testedSourceSha
    and .roleEvidence.capturedIdentity.workflowSignerSha == $expected[0].workflowSignerSha
    and .roleEvidence.capturedIdentity.baseSha == $expected[0].baseSha
    and .roleEvidence.capturedIdentity.runIdentity == $expected[0].runIdentity
    and .roleEvidence.capturedIdentity.artifactNonce == $expected[0].artifactNonce
    and .roleEvidence.evidenceClasses == $expected[0].requiredEvidenceClasses[$role]
    and ([.roleEvidence.gates | to_entries[] | select(.value != true)] | length == 0)
    and ((.roleEvidence.gates | keys | sort) == ($expected[0].requiredEvidenceClasses[$role] | sort))
    and (.roleEvidence.internalArtifacts | type == "array" and length > 0)
    and all(.roleEvidence.internalArtifacts[]; (.name | type == "string") and (.bytes | type == "number" and . >= 0) and (.sha256 | test("^[0-9a-f]{64}$")))
    and (.roleEvidence.environment | type == "object")
    and (.roleEvidence.viewport.width == 1920 and .roleEvidence.viewport.height == 1080 and .roleEvidence.viewport.refreshHz == 60 and (.roleEvidence.viewport.verified | type == "boolean"))
  ' "$manifest" >/dev/null
}
role_guard_for() {
  # These are static facts from the immutable trusted reusable workflow, not
  # candidate output or a REST hosted-origin claim.
  local role=$1 path workflow candidate_block seal_block label needs_candidate
  case "$role" in
    linux-x86_64) path=.github/workflows/ci-role-linux-x86-64.yml;;
    macos-26-arm64) path=.github/workflows/ci-role-macos-26-arm64.yml;;
    macos-15-arm64) path=.github/workflows/ci-role-macos-15-arm64.yml;;
    *) return 1;;
  esac
  workflow=$anchor_root/$path
  [[ -f $workflow && ! -L $workflow ]] || return 1
  candidate_block=$(sed -n '/^  candidate:/,/^  seal:/p' "$workflow") || return 1
  seal_block=$(sed -n '/^  seal:/,$p' "$workflow") || return 1
  label=$(awk '/^[[:space:]]*runs-on:[[:space:]]*/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, ""); print; exit}' <<<"$candidate_block")
  [[ $label =~ ^(ubuntu-22\.04|macos-26|macos-15)$ ]] || return 1
  needs_candidate=false
  rg -qx '    needs: candidate' <<<"$seal_block" && needs_candidate=true
  jq -cn --arg path "$path" --arg label "$label" --argjson needs_candidate "$needs_candidate" '{workflowPath:$path,runnerLabel:$label,candidateJobId:"candidate",sealingJobId:"seal",sealNeedsCandidate:$needs_candidate,requiredCandidateStatus:"completed",requiredCandidateConclusion:"success"}'
}
caller_job_id_for() {
  # GitHub exposes jobs from a local reusable workflow using the caller job
  # key as the REST-name prefix (for example, "linux / candidate"). Resolve
  # that key from the immutable caller instead of accepting it from REST data.
  local path=$1 caller
  caller=$anchor_root/.github/workflows/ci.yml
  [[ -f $caller && ! -L $caller ]] || return 1
  awk -v target="./$path" '
    /^jobs:[[:space:]]*$/ { in_jobs=1; next }
    in_jobs && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ {
      job=$1
      sub(/:$/, "", job)
      next
    }
    in_jobs && /^    uses:[[:space:]]*/ {
      value=$0
      sub(/^    uses:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*/, "", value)
      if (value == target) {
        count++
        caller_job=job
      }
    }
    END { if (count == 1) print caller_job; else exit 1 }
  ' "$caller"
}
candidate_reject() {
  local code=$1 channel=${2:-}
  candidate_guard_code=$code
  if [[ -n $channel ]]; then
    printf '%s\n' "$code" >"$channel" || return 1
  fi
  return 1
}
candidate_observation() {
  local jobs=$1 role=$2 rejection_channel=${3:-} job count label check_id job_id workflow guard actual caller_job_id candidate_job_id candidate_name
  candidate_guard_code=
  guard=$(jq -ce --arg role "$role" '.requiredRoleGuards[$role]' "$expected") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  actual=$(role_guard_for "$role") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  # Placement and topology are separately measured against the trusted role
  # workflow. Neither fact is inferred from the candidate REST object.
  jq -e --argjson actual "$actual" '.workflowPath == $actual.workflowPath and .runnerLabel == $actual.runnerLabel and .candidateJobId == $actual.candidateJobId' <<<"$guard" >/dev/null || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  jq -e --argjson actual "$actual" '.sealingJobId == $actual.sealingJobId and .sealNeedsCandidate == $actual.sealNeedsCandidate' <<<"$guard" >/dev/null || { candidate_reject candidate-topology-mismatch "$rejection_channel"; return 1; }
  label=$(jq -er '.runnerLabel' <<<"$guard") || { candidate_reject candidate-label-mismatch "$rejection_channel"; return 1; }
  workflow=$(jq -er '.workflowPath' <<<"$guard") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  caller_job_id=$(caller_job_id_for "$workflow") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  candidate_job_id=$(jq -er '.candidateJobId' <<<"$guard") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  candidate_name="$caller_job_id / $candidate_job_id"
  count=$(jq --arg name "$candidate_name" '[.jobs[] | select(.name == $name)] | length' "$jobs")
  [[ $count == 1 ]] || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  job=$(jq -ce --arg name "$candidate_name" '.jobs[] | select(.name == $name)' "$jobs") || { candidate_reject candidate-placement-mismatch "$rejection_channel"; return 1; }
  jq -e --arg label "$label" '(.labels | type == "array") and (.labels | index($label)) != null and (.labels | index("self-hosted")) == null' <<<"$job" >/dev/null || { candidate_reject candidate-label-mismatch "$rejection_channel"; return 1; }
  jq -e --arg status "$(jq -r '.requiredCandidateStatus' <<<"$guard")" --arg conclusion "$(jq -r '.requiredCandidateConclusion' <<<"$guard")" --arg run "$run_id" '.status == $status and .conclusion == $conclusion and (.run_id | tostring) == $run' <<<"$job" >/dev/null || { candidate_reject candidate-completion-mismatch "$rejection_channel"; return 1; }
  check_id=$(jq -er '.check_run_url | capture("/check-runs/(?<id>[1-9][0-9]*)$").id | tonumber' <<<"$job") || return 1
  job_id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$job") || return 1
  jq -cn --argjson id "$job_id" --argjson check "$check_id" --arg workflow "$workflow" --arg label "$label" --argjson labels "$(jq '.labels' <<<"$job")" '{jobId:$id,checkRunId:$check,workflowJobKey:"candidate",workflowPath:$workflow,expectedRunnerLabel:$label,runnerLabels:$labels,placementFixedByTrustedWorkflow:true,topologyVerified:true,labelVerified:true,status:"completed",conclusion:"success",completionVerified:true}'
}
seal_observation() {
  local jobs=$1 role=$2 rejection_channel=${3:-} job count matching_count label guard check_id job_id
  guard=$(jq -ce --arg role "$role" '.requiredRoleGuards[$role]' "$expected") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  label=$(jq -er '.runnerLabel | select(type == "string" and length > 0)' <<<"$guard") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  # A managed invocation contains one reusable workflow per role. Select only
  # this role's seal using its anchor-derived expected runner label; seals for
  # the other roles must neither make this role duplicate nor hide its locator.
  count=$(jq '[.jobs[] | select((.name | type == "string") and (.name == "seal" or (.name | endswith("/ seal"))))] | length' "$jobs") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  [[ $count -gt 0 ]] || { role_reject "$rejection_channel" sealing-job-missing; return 1; }
  matching_count=$(jq --arg label "$label" '[.jobs[] | select((.name | type == "string") and (.name == "seal" or (.name | endswith("/ seal"))) and ((.labels | type == "array") and (.labels | index($label)) != null))] | length' "$jobs") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  [[ $matching_count -gt 0 ]] || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  [[ $matching_count == 1 ]] || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  job=$(jq -ce --arg label "$label" '.jobs[] | select((.name | type == "string") and (.name == "seal" or (.name | endswith("/ seal"))) and ((.labels | type == "array") and (.labels | index($label)) != null))' "$jobs") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  jq -e '(.labels | index("self-hosted") | not)' <<<"$job" >/dev/null || { role_reject "$rejection_channel" sealing-runner-environment-mismatch; return 1; }
  jq -e --arg run "$run_id" '(.run_id | tostring) == $run' <<<"$job" >/dev/null || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  jq -e '.status == "completed"' <<<"$job" >/dev/null || { role_reject "$rejection_channel" sealing-job-in-progress; return 1; }
  jq -e '.conclusion == "success"' <<<"$job" >/dev/null || { role_reject "$rejection_channel" sealing-job-failed; return 1; }
  check_id=$(jq -er '.check_run_url | capture("/check-runs/(?<id>[1-9][0-9]*)$").id | tonumber' <<<"$job") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  job_id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$job") || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  jq -cn --argjson id "$job_id" --argjson check "$check_id" --argjson labels "$(jq '.labels' <<<"$job")" '{jobId:$id,checkRunId:$check,workflowJobKey:"seal",runnerLabels:$labels,runnerEnvironment:"github-hosted",status:"completed",conclusion:"success",hostedOriginVerified:true}'
}
artifact_observation() {
  local artifact=$1 upload_digest=$2
  [[ $upload_digest =~ ^[0-9a-f]{64}$ ]] || return 1
  jq -e --arg digest "sha256:$upload_digest" '.digest == $digest' <<<"$artifact" >/dev/null || return 1
  jq -cn --argjson id "$(jq -er '.id | floor' <<<"$artifact")" --arg name "$(jq -er '.name' <<<"$artifact")" --arg upload "$upload_digest" --arg digest "sha256:$upload_digest" '{artifactId:$id,artifactName:$name,uploadActionDigest:$upload,artifactDigest:$digest}'
}
attestation_predicate_valid() {
  local response=$1 subject=$2 role=$3 signer workflow_uri builder_uri invocation
  signer="$REPOSITORY/$(workflow_path "$role")"
  workflow_uri="https://github.com/$REPOSITORY/$(workflow_path "$role")"
  builder_uri="$workflow_uri@refs/heads/master"
  invocation="https://github.com/$REPOSITORY/actions/runs/$run_id/attempts/$attempt"
  # actions/attest@1e69f48 delegates default provenance creation to
  # @actions/attest 3.2.0. The pinned source has no external inputs or
  # workflow SHA: runner_environment is nested under github and the called
  # reusable workflow is the SLSA builder.
  jq -e --arg subject "$subject" --arg repository "$REPOSITORY" --arg signer "$workflow_signer" --arg builder "$builder_uri" --arg runInvocation "$invocation" '
    length > 0 and any(.[];
      (.verificationResult.statement.subject[]?.digest.sha256? == $subject)
      and .verificationResult.statement.predicateType == "https://slsa.dev/provenance/v1"
      and (.verificationResult.signature.certificate | type == "object")
      and .verificationResult.signature.certificate.issuer == "https://token.actions.githubusercontent.com"
      and .verificationResult.signature.certificate.sourceRepositoryURI == ("https://github.com/" + $repository)
      and .verificationResult.signature.certificate.sourceRepositoryDigest == $signer
      and .verificationResult.signature.certificate.sourceRepositoryRef == "refs/heads/master"
      and .verificationResult.signature.certificate.buildSignerURI == $builder
      and .verificationResult.signature.certificate.buildSignerDigest == $signer
      and .verificationResult.signature.certificate.runnerEnvironment == "github-hosted"
      and .verificationResult.signature.certificate.runInvocationURI == $runInvocation
      and .verificationResult.statement.predicate.buildDefinition.buildType == "https://actions.github.io/buildtypes/workflow/v1"
      and .verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.repository == ("https://github.com/" + $repository)
      and .verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.ref == "refs/heads/master"
      and (.verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.path | type == "string" and startswith(".github/workflows/"))
      and .verificationResult.statement.predicate.buildDefinition.internalParameters.github.event_name == "workflow_dispatch"
      and .verificationResult.statement.predicate.buildDefinition.internalParameters.github.runner_environment == "github-hosted"
      and ([.verificationResult.statement.predicate.buildDefinition.resolvedDependencies[]? | .digest.gitCommit?] | index($signer)) != null
      and .verificationResult.statement.predicate.runDetails.builder.id == $builder
    )' <<<"$response" >/dev/null
}

attestation_failure_status() {
  # `gh` documents exit 1 for any command failure and 4 for authentication.
  # Online verification therefore needs the diagnostic text to distinguish an
  # unavailable service from a durable cryptographic or policy rejection.
  local gh_status=$1 stderr_path=$2
  attestation_rejection_code=untrusted-origin
  (( gh_status == 4 )) && return "$API_PERMISSION"
  (( gh_status == 2 )) && return "$API_TRANSIENT"
  (( gh_status == 1 )) || return "$API_FAILURE"
  [[ -s $stderr_path ]] || return "$API_FAILURE"
  if rg -qi '(^|[^0-9])(401|403)([^0-9]|$)|authentication( is)? required|requires authentication|forbidden|resource not accessible' "$stderr_path"; then
    return "$API_PERMISSION"
  fi
  if rg -qi '(^|[^0-9])(408|425|429|5[0-9]{2})([^0-9]|$)|rate limit|timed out|timeout|connection (reset|refused)|network is unreachable|no such host|temporary failure|tls handshake' "$stderr_path"; then
    return "$API_TRANSIENT"
  fi
  if rg -qi 'attestations? (are |is )?(not )?(available|supported)|attestation.*(unavailable|not supported)|github enterprise cloud' "$stderr_path"; then
    attestation_rejection_code=attestation-unavailable
  elif rg -qi '(^|[^0-9])([1-4][0-9]{2})([^0-9]|$)|api (error|request)|request failed' "$stderr_path"; then
    return "$API_FAILURE"
  fi
  return 1
}

verify_attestation() {
  local artifact=$1 role=$2 kind=$3 supplied_bundle=${4:-} rejection_channel=${5:-} response signer subject bundle_path gh_status classified_status
  local -a verify_args
  signer="$REPOSITORY/$(workflow_path "$role")"
  [[ -z $supplied_bundle || ( -f $supplied_bundle && ! -L $supplied_bundle ) ]] || return 1
  verify_args=(--repo "$REPOSITORY" --format json --cert-oidc-issuer https://token.actions.githubusercontent.com --deny-self-hosted-runners --signer-workflow "$signer" --signer-digest "$workflow_signer" --source-digest "$workflow_signer" --source-ref refs/heads/master)
  [[ -z $supplied_bundle ]] || verify_args+=(--bundle "$supplied_bundle")
  if response=$($GH_BIN attestation verify "$artifact" "${verify_args[@]}" 2>"$tmp/attestation-$role-$kind.stderr"); then gh_status=0; else gh_status=$?; fi
  if (( gh_status != 0 )); then
    if attestation_failure_status "$gh_status" "$tmp/attestation-$role-$kind.stderr"; then classified_status=0; else classified_status=$?; fi
    case "$classified_status" in
      "$API_TRANSIENT"|"$API_PERMISSION"|"$API_FAILURE") return "$classified_status";;
      1) role_reject "$rejection_channel" "$attestation_rejection_code"; return 1;;
      *) return "$API_FAILURE";;
    esac
  fi
  # gh verifies the certificate/signature before emitting JSON. The role
  # manifest, receipt, and artifact names bind runIdentity and artifactNonce;
  # actions/attest does not put those inputs in its default predicate.
  subject=$(sha256_file "$artifact")
  attestation_predicate_valid "$response" "$subject" "$role" || { role_reject "$rejection_channel" untrusted-origin; return 1; }
  # Preserve verified attestation bundle material separately from its subject.
  # The subject is the downloaded artifact; repeating its hash here is not a
  # bundle provenance record.
  bundle_path=$tmp/attestation-$role-$kind.json
  jq -ce '[.[].attestation.bundle]' <<<"$response" >"$bundle_path" || return 1
  case "$kind" in
    sealed) sealed_attestation_bundle_sha=$(sha256_file "$bundle_path");;
    receipt) receipt_attestation_bundle_sha=$(sha256_file "$bundle_path");;
    *) return 1;;
  esac
}

verify_offline_attestation() {
  # This is deliberately separate from artifact-attestation acquisition: stage
  # and lineage attestations are bundled *inside* their immutable transports.
  # Verify the exact downloaded subject and bundle before parsing either.
  local subject_path=$1 bundle_path=$2 role=$3 response subject
  [[ -f $subject_path && ! -L $subject_path && -f $bundle_path && ! -L $bundle_path ]] || return 1
  response=$($GH_BIN attestation verify "$subject_path" --bundle "$bundle_path" --repo "$REPOSITORY" --format json \
    --cert-oidc-issuer https://token.actions.githubusercontent.com \
    --deny-self-hosted-runners --signer-workflow "$REPOSITORY/$(workflow_path "$role")" \
    --signer-digest "$workflow_signer" --source-digest "$workflow_signer" \
    --source-ref refs/heads/master 2>"$tmp/offline-attestation.stderr") || return 1
  subject=$(sha256_file "$subject_path")
  attestation_predicate_valid "$response" "$subject" "$role"
}

compatibility_fail() { compatibility_rejection_code=$1; return 1; }
compatibility_time_after() {
  local later=$1 earlier=$2 later_epoch earlier_epoch
  later_epoch=$(date -u -d "$later" +%s 2>/dev/null) || return 1
  earlier_epoch=$(date -u -d "$earlier" +%s 2>/dev/null) || return 1
  (( later_epoch > earlier_epoch ))
}
compatibility_artifact_once() {
  local inventory=$1 name=$2 count
  count=$(jq --arg name "$name" '[.artifacts[] | select(.name == $name)] | length' "$inventory") || return 1
  case "$count" in 0) return 10;; 1) jq -ce --arg name "$name" '.artifacts[] | select(.name == $name)' "$inventory";; *) return 11;; esac
}
compatibility_current_artifact() {
  local artifact=$1 expected=$2 current
  current=$(api "$API_BASE/repos/$REPOSITORY/actions/artifacts/$(jq -er '.id' <<<"$artifact")") || return $?
  jq -e --argjson expected "$expected" '
    .id == $expected.artifactId and .name == $expected.artifactName and
    .digest == $expected.artifactDigest and .expired == false and
    .created_at == $expected.createdAt and .expires_at == $expected.expiresAt and
    (.workflow_run.id | tonumber) == $expected.workflowRunId
  ' <<<"$current" >/dev/null
}
canonical_lineage_bytes() {
  local input=$1 canonical=$tmp/compatibility-lineage-canonical.json
  # jq produces a terminating LF; RFC 8785 transport explicitly does not.
  LC_ALL=C jq -cS . "$input" >"$canonical" || return 1
  truncate -s -1 "$canonical" || return 1
  cmp -s "$canonical" "$input"
}
compatibility_stage_for() {
  local inventory=$1 roles_json=$2 nonce=${run_identity#managed:}
  local stage_name lineage_name stage_artifact lineage_artifact stage_dir lineage_dir lineage_path producer_receipt consumer_receipt producer_manifest consumer_manifest producer_lineage lineage_sha producer_receipt_sha consumer_receipt_sha verified_at lineage_transport lineage_bundle_sha producer_receipt_artifact api_status
  compatibility_rejection_code=
  if [[ $ticket != BURL-O001 ]]; then
    jq -e 'all(.[]; .manifest.roleEvidence.compatibilityStage == null)' <<<"$roles_json" >/dev/null || { compatibility_fail compatibility-stage-unexpected; return 1; }
    for role in "${ROLES[@]}"; do jq -e '.compatibilityStage == null' "$tmp/receipt-$role.json" >/dev/null || { compatibility_fail compatibility-stage-unexpected; return 1; }; done
    printf 'null\n'
    return 0
  fi
  stage_name="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce"
  lineage_name="managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$nonce"
  stage_artifact=$(compatibility_artifact_once "$inventory" "$stage_name") || { case $? in 10) compatibility_fail compatibility-stage-missing;; 11) compatibility_fail compatibility-stage-duplicate;; *) compatibility_fail aggregation-error;; esac; return 1; }
  lineage_artifact=$(compatibility_artifact_once "$inventory" "$lineage_name") || { case $? in 10) compatibility_fail compatibility-stage-missing;; 11) compatibility_fail compatibility-stage-duplicate;; *) compatibility_fail aggregation-error;; esac; return 1; }
  [[ $(jq -r '.expired' <<<"$stage_artifact") == false ]] || { compatibility_fail compatibility-stage-expired; return 1; }
  [[ $(jq -r '.expired' <<<"$lineage_artifact") == false ]] || { compatibility_fail compatibility-stage-expired; return 1; }
  [[ $(jq -r '.workflow_run.id' <<<"$stage_artifact") == "$run_id" && $(jq -r '.workflow_run.id' <<<"$lineage_artifact") == "$run_id" ]] || { compatibility_fail compatibility-stage-substituted; return 1; }
  stage_dir=$tmp/compatibility-stage; lineage_dir=$tmp/compatibility-lineage
  if download_exact_members_zip "$stage_artifact" "$stage_dir" compatibility-stage-manifest.json compatibility-stage-attestation.sigstore.json handoff/outbox/macos-current-construction.tar.zst handoff/outbox/macos-current-construction.sha256; then api_status=0; else api_status=$?; fi
  if ((api_status != 0)); then
    is_operational_api_status "$api_status" && return "$api_status"
    compatibility_fail compatibility-stage-substituted; return 1
  fi
  if download_exact_members_zip "$lineage_artifact" "$lineage_dir" compatibility-stage-producer-lineage.json compatibility-stage-producer-lineage-attestation.sigstore.json; then api_status=0; else api_status=$?; fi
  if ((api_status != 0)); then
    is_operational_api_status "$api_status" && return "$api_status"
    compatibility_fail compatibility-stage-substituted; return 1
  fi
  lineage_path=$lineage_dir/compatibility-stage-producer-lineage.json
  canonical_lineage_bytes "$lineage_path" || { compatibility_fail compatibility-stage-noncanonical-lineage; return 1; }
  lineage_sha=$(sha256_file "$lineage_path")
  producer_receipt=$tmp/receipt-macos-26-arm64.json; consumer_receipt=$tmp/receipt-macos-15-arm64.json
  producer_manifest=$tmp/manifest-macos-26-arm64.json; consumer_manifest=$tmp/manifest-macos-15-arm64.json
  producer_receipt_sha=$(sha256_file "$producer_receipt"); consumer_receipt_sha=$(sha256_file "$consumer_receipt")
  producer_lineage=$(jq -ce . "$lineage_path") || { compatibility_fail compatibility-stage-noncanonical-lineage; return 1; }
  # Validate the three independently attested producer facts before allowing
  # the candidate-carried macOS 15 record to influence the aggregate.
  jq -e --arg signer "$workflow_signer" --argjson run "$run_id" --argjson att "$attempt" '
    .attestation.workflowPath == ".github/workflows/ci-role-macos-26-arm64.yml" and
    .attestation.jobWorkflowSha == $signer and .attestation.sourceRepositoryDigest == $signer
  ' "$lineage_path" >/dev/null || { compatibility_fail compatibility-stage-wrong-signer; return 1; }
  jq -e --argjson run "$run_id" --argjson att "$attempt" '
    .attestation.workflowRunId == $run and .attestation.runAttempt == $att and
    .stageManifest.workflowRunId == $run and .stageManifest.runAttempt == $att
  ' "$lineage_path" >/dev/null || { compatibility_fail compatibility-stage-wrong-run; return 1; }
  jq -e '.attestation.checkRunId == .stageManifest.producerSealingCheckRunId' "$lineage_path" >/dev/null || { compatibility_fail compatibility-stage-wrong-seal; return 1; }
  verify_offline_attestation "$stage_dir/compatibility-stage-manifest.json" "$stage_dir/compatibility-stage-attestation.sigstore.json" macos-26-arm64 || { compatibility_fail compatibility-stage-unattested; return 1; }
  verify_offline_attestation "$lineage_path" "$lineage_dir/compatibility-stage-producer-lineage-attestation.sigstore.json" macos-26-arm64 || { compatibility_fail compatibility-stage-unattested; return 1; }
  jq -e --slurpfile lineage "$lineage_path" --arg sha "$lineage_sha" --arg producer_sha "$producer_receipt_sha" --arg consumer_sha "$consumer_receipt_sha" '
    .compatibilityStage.producerStage.stageArtifact == $lineage[0].stageArtifact and
    .compatibilityStage.producerStage.stageManifest == $lineage[0].stageManifest and
    .compatibilityStage.producerStage.stageManifestSha256 == $lineage[0].stageManifestSha256 and
    .compatibilityStage.producerStage.attestation == $lineage[0].attestation
  ' "$producer_receipt" >/dev/null || { compatibility_fail compatibility-stage-substituted; return 1; }
  jq -e --arg sha "$lineage_sha" '.roleEvidence.compatibilityStage.producerLineageSha256 == $sha' "$consumer_manifest" >/dev/null || { compatibility_fail compatibility-stage-lineage-sha-mismatch; return 1; }
  jq -e --arg sha "$lineage_sha" '.compatibilityStage.producerLineageSha256 == $sha' "$consumer_receipt" >/dev/null || { compatibility_fail compatibility-stage-lineage-sha-mismatch; return 1; }
  jq -e --slurpfile lineage "$lineage_path" --arg producer_sha "$producer_receipt_sha" '
    .roleEvidence.compatibilityStage.producerLineage == $lineage[0] and
    .roleEvidence.compatibilityStage.consumerBinding.producerSealingReceiptSha256 == $producer_sha and
    .roleEvidence.compatibilityStage.consumerBinding.downloadedStageArtifactId == $lineage[0].stageArtifact.artifactId
  ' "$consumer_manifest" >/dev/null || { compatibility_fail compatibility-stage-consumer-unbound; return 1; }
  jq -e --slurpfile lineage "$lineage_path" --arg producer_sha "$producer_receipt_sha" '
    .compatibilityStage.producerLineage == $lineage[0] and
    .compatibilityStage.consumerBinding.producerSealingReceiptSha256 == $producer_sha and
    .compatibilityStage.consumerBinding.downloadedStageArtifactId == $lineage[0].stageArtifact.artifactId
  ' "$consumer_receipt" >/dev/null || { compatibility_fail compatibility-stage-consumer-unbound; return 1; }
  jq -e --slurpfile lineage "$lineage_path" '
    .stageManifest.producerRole == "macos-26-arm64" and .stageManifest.consumerRole == "macos-15-arm64" and
    .stageManifest.producerSealingCheckRunId > 0 and .stageArtifact.artifactDigest == ("sha256:" + .stageArtifact.uploadActionDigest) and
    .producerSealingReceiptArtifact.artifactDigest == ("sha256:" + .producerSealingReceiptArtifact.uploadActionDigest) and
    .stageArtifact.expired == false and .producerSealingReceiptArtifact.expired == false
  ' "$lineage_path" >/dev/null || { compatibility_fail compatibility-stage-wrong-role; return 1; }
  jq -e --argjson producer_origin "$(jq -ce '.[] | select(.manifest.roleEvidence.role == "macos-26-arm64") | .origin' <<<"$roles_json")" --argjson consumer_origin "$(jq -ce '.[] | select(.manifest.roleEvidence.role == "macos-15-arm64") | .origin' <<<"$roles_json")" '
    .stageManifest.producerSealingCheckRunId == $producer_origin.sealingCheckRunId and
    .stageManifest.producerSealingCheckRunId != $consumer_origin.sealingCheckRunId and
    .stageManifest.workflowSignerSha == $producer_origin.workflowSignerSha and
    .stageManifest.testedSourceSha == $producer_origin.testedSourceSha and
    .stageManifest.workflowRunId == $producer_origin.workflowRunId and .stageManifest.runAttempt == $producer_origin.runAttempt
  ' "$lineage_path" >/dev/null || { compatibility_fail compatibility-stage-wrong-seal; return 1; }
  if compatibility_current_artifact "$stage_artifact" "$(jq -ce '.stageArtifact' "$lineage_path")"; then api_status=0; else api_status=$?; fi
  if ((api_status != 0)); then
    is_operational_api_status "$api_status" && return "$api_status"
    compatibility_fail compatibility-stage-digest-mismatch; return 1
  fi
  producer_receipt_artifact=$(artifact_by_name "$inventory" "managed-evidence-seal-receipt-macos-26-arm64-$nonce") || { compatibility_fail compatibility-stage-stale-producer-receipt; return 1; }
  if compatibility_current_artifact "$producer_receipt_artifact" "$(jq -ce '.producerSealingReceiptArtifact' "$lineage_path")"; then api_status=0; else api_status=$?; fi
  if ((api_status != 0)); then
    is_operational_api_status "$api_status" && return "$api_status"
    compatibility_fail compatibility-stage-stale-producer-receipt; return 1
  fi
  verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  compatibility_time_after "$(jq -r '.producerSealingReceiptArtifact.expiresAt' "$lineage_path")" "$verified_at" || { compatibility_fail compatibility-stage-stale-producer-receipt; return 1; }
  compatibility_time_after "$(jq -r '.stageArtifact.expiresAt' "$lineage_path")" "$verified_at" || { compatibility_fail compatibility-stage-expired; return 1; }
  # Every accepted transport/binding value is reconstructed from downloaded
  # lineage bytes, its immutable artifact observation, the signed lineage,
  # and the current producer-receipt observation.  Do not promote a field
  # merely because an untrusted macOS 15 manifest or receipt repeats it.
  lineage_bundle_sha=$(sha256_file "$lineage_dir/compatibility-stage-producer-lineage-attestation.sigstore.json")
  lineage_transport=$(jq -cn --argjson artifact "$lineage_artifact" --slurpfile lineage "$lineage_path" --arg bundle "$lineage_bundle_sha" --arg sha "$lineage_sha" '
    {artifactId:$artifact.id,artifactName:$artifact.name,
     uploadActionDigest:($artifact.digest | ltrimstr("sha256:")),artifactDigest:$artifact.digest,
     attestation:{bundleMember:"compatibility-stage-producer-lineage-attestation.sigstore.json",bundleSha256:$bundle,
       subjectName:"compatibility-stage-producer-lineage.json",subjectDigest:("sha256:"+$sha),
       predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",
       repository:$lineage[0].attestation.repository,repositoryId:$lineage[0].attestation.repositoryId,
       workflowPath:$lineage[0].attestation.workflowPath,jobWorkflowRef:$lineage[0].attestation.jobWorkflowRef,
       jobWorkflowSha:$lineage[0].attestation.jobWorkflowSha,sourceRepositoryDigest:$lineage[0].attestation.sourceRepositoryDigest,
       workflowRunId:$lineage[0].attestation.workflowRunId,runAttempt:$lineage[0].attestation.runAttempt,
       checkRunId:$lineage[0].attestation.checkRunId,runnerEnvironment:$lineage[0].attestation.runnerEnvironment}}
  ') || { compatibility_fail compatibility-stage-substituted; return 1; }
  # Compare both independently sealed copies with all grounded values.  The
  # wrapper's verification result and trusted-root hashes cannot be inferred
  # from a candidate claim, so require exact manifest/receipt agreement and
  # their declared immutable hash shape while the rest of the binding is tied
  # to downloaded bytes and REST observations above.
  jq -e --slurpfile lineage "$lineage_path" --arg sha "$lineage_sha" --argjson transport "$lineage_transport" --arg verified "$verified_at" '
    .roleEvidence.compatibilityStage as $stage |
    $stage.producerLineage == $lineage[0] and
    $stage.producerLineageSha256 == $sha and
    $stage.producerLineageArtifact == $transport and
    $stage.consumerBinding.producerLineageSha256 == $sha and
    $stage.consumerBinding.producerLineageArtifact == $transport and
    $stage.consumerBinding.producerSealingReceiptArtifact == $lineage[0].producerSealingReceiptArtifact and
    $stage.consumerBinding.downloadedStageArtifactId == $lineage[0].stageArtifact.artifactId and
    $stage.consumerBinding.downloadActionSha == "3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c" and
    $stage.consumerBinding.digestMismatchBehavior == "error" and
    $stage.consumerBinding.stageAttestationVerifiedOffline and $stage.consumerBinding.producerReceiptAttestationVerifiedOffline and $stage.consumerBinding.producerLineageAttestationVerifiedOffline and
    $stage.consumerBinding.credentialsRemoved and $stage.consumerBinding.membersReadOnly and
    $stage.consumerBinding.consumerRole == "macos-15-arm64" and
    $stage.consumerBinding.workflowRunId == $lineage[0].stageManifest.workflowRunId and
    $stage.consumerBinding.runAttempt == $lineage[0].stageManifest.runAttempt and
    ($stage.consumerBinding.consumerCandidateCheckRunId | type == "number" and . > 0) and
    ($stage.consumerBinding.verifiedAt | fromdateiso8601) <= ($verified | fromdateiso8601) and
    ([$stage.consumerBinding.stageAttestationVerificationResultSha256,$stage.consumerBinding.producerReceiptAttestationVerificationResultSha256,$stage.consumerBinding.producerLineageAttestationVerificationResultSha256,$stage.consumerBinding.trustedRootSha256] | all(test("^[0-9a-f]{64}$")))
  ' "$consumer_manifest" >/dev/null || { compatibility_fail compatibility-stage-consumer-unbound; return 1; }
  jq -e --slurpfile manifest "$consumer_manifest" '
    .compatibilityStage == $manifest[0].roleEvidence.compatibilityStage
  ' "$consumer_receipt" >/dev/null || { compatibility_fail compatibility-stage-consumer-unbound; return 1; }
  jq -e --slurpfile lineage "$lineage_path" --arg sha "$lineage_sha" --arg producer_sha "$producer_receipt_sha" --arg consumer_sha "$consumer_receipt_sha" --arg verified "$verified_at" '
    {producerLineage:$lineage[0],producerLineageArtifact:.roleEvidence.compatibilityStage.producerLineageArtifact,consumerBinding:.roleEvidence.compatibilityStage.consumerBinding,producerSealingReceiptSha256:$producer_sha,consumerSealingReceiptSha256:$consumer_sha,lineageSha256:$sha,verifiedAt:$verified}
  ' "$consumer_manifest"
}
role_reject() {
  local channel=$1 code=$2
  printf '%s\n' "$code" >"$channel" || return 1
  return 1
}
receipt_role() {
  local role=$1 inventory=$2 jobs=$3 rejection_channel=$4 transport_observation=${5:-} nonce=${run_identity#managed:} receipt_artifact receipt_transport_entry receipt_path receipt_bundle_path sealed_artifact candidate_artifact expected_artifact sealed_path candidate_path inner role_stage manifest candidate_stage candidate_manifest candidate_filesystem filesystem_before candidate_job seal_job candidate_obs seal_obs expected_obs candidate_artifact_obs sealed_artifact_obs receipt_artifact_obs receipt_hash workflow role_json
  if [[ -n $transport_observation ]]; then
    receipt_transport_entry=$(jq -ce --arg role "$role" '.transport.receipts[] | select(.role == $role)' <<<"$transport_observation") || { role_reject "$rejection_channel" artifact-api-mismatch; return 1; }
    [[ $(jq --arg role "$role" '[.transport.receipts[] | select(.role == $role)] | length' <<<"$transport_observation") == 1 ]] || { role_reject "$rejection_channel" artifact-api-mismatch; return 1; }
    receipt_artifact=$(artifact_by_name "$inventory" "managed-evidence-seal-receipt-$role-$nonce") || { role_reject "$rejection_channel" artifact-api-mismatch; return 1; }
    jq -e --argjson entry "$receipt_transport_entry" '.id == $entry.artifactId and .name == $entry.artifactName' <<<"$receipt_artifact" >/dev/null || { role_reject "$rejection_channel" artifact-api-mismatch; return 1; }
    receipt_artifact_obs=$(artifact_observation "$receipt_artifact" "$(jq -r '.uploadActionDigest' <<<"$receipt_transport_entry")") || { role_reject "$rejection_channel" artifact-digest-mismatch; return 1; }
  else
    # Direct-function fixtures deliberately omit the transport. Production
    # collection always passes the verified caller observation above.
    receipt_artifact=$(artifact_by_name "$inventory" "managed-evidence-seal-receipt-$role-$nonce") || return 1
    receipt_artifact_obs=
  fi
  receipt_path=$tmp/receipt-$role.json; receipt_bundle_path=$tmp/receipt-$role-attestation.sigstore.json
  download_sealing_receipt_zip "$receipt_artifact" "$receipt_path" "$receipt_bundle_path" || return $?
  "$launcher_dir/validate-sealing-receipt.sh" "$receipt_path" || return 1
  if [[ $ticket == BURL-O001 && $role == macos-26-arm64 ]]; then
    jq -e '.compatibilityStage | type == "object" and (keys | sort) == ["producerStage"] and (.producerStage | type == "object")' "$receipt_path" >/dev/null || { role_reject "$rejection_channel" compatibility-stage-missing; return 1; }
  fi
  # Keep seal-origin claims on the parent-owned rejection channel.  These
  # fields select a seal or assert its provenance; a malformed role bundle is
  # not an adequate explanation when one of them disagrees.
  jq -e '.runnerEnvironmentClaim == "github-hosted"' "$receipt_path" >/dev/null || { role_reject "$rejection_channel" sealing-runner-environment-mismatch; return 1; }
  jq -e '(.sealingCheckRunId | type == "number" and . > 0)' "$receipt_path" >/dev/null || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  jq -e --argjson run "$run_id" --argjson att "$attempt" '.workflowRunId == $run and .runAttempt == $att' "$receipt_path" >/dev/null || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  jq -e --arg signer "$workflow_signer" --arg tested "$tested" '.workflowSignerSha == $signer and .workflowSignerRef == "refs/heads/master" and .testedSourceSha == $tested' "$receipt_path" >/dev/null || { role_reject "$rejection_channel" untrusted-origin; return 1; }
  jq -e --arg ticket "$ticket" --arg role "$role" --arg anchor "$anchor" --arg base "$base" --arg nonce "$nonce" --arg digest "$expected_digest" '.schemaVersion == 2 and .ticketIdentity == $ticket and .role == $role and .trustAnchorSha == $anchor and .baseSha == $base and .artifactNonce == $nonce and .expectedIdentitySha256 == $digest' "$receipt_path" >/dev/null || return 1
  workflow=$(workflow_path "$role")
  [[ $(jq -r '.workflowPath' "$receipt_path") == "$workflow" ]] || { role_reject "$rejection_channel" untrusted-origin; return 1; }
  expected_artifact=$(artifact_by_name "$inventory" "managed-evidence-expected-$nonce") || return 1
  candidate_artifact=$(artifact_by_name "$inventory" "managed-evidence-candidate-$role-$nonce") || return 1
  sealed_artifact=$(artifact_by_name "$inventory" "managed-evidence-sealed-$role-$nonce") || return 1
  expected_obs=$(artifact_observation "$expected_artifact" "$(jq -r '.expectedArtifact.uploadActionDigest' "$receipt_path")") || { role_reject "$rejection_channel" artifact-digest-mismatch; return 1; }
  candidate_artifact_obs=$(artifact_observation "$candidate_artifact" "$(jq -r '.candidateArtifact.uploadActionDigest' "$receipt_path")") || { role_reject "$rejection_channel" artifact-digest-mismatch; return 1; }
  sealed_artifact_obs=$(artifact_observation "$sealed_artifact" "$(jq -r '.sealedArtifact.uploadActionDigest' "$receipt_path")") || { role_reject "$rejection_channel" artifact-digest-mismatch; return 1; }
  # Receipts bind the REST observations; independently reject swapped IDs/names.
  jq -e --argjson e "$expected_obs" --argjson c "$candidate_artifact_obs" --argjson s "$sealed_artifact_obs" '.expectedArtifact.artifactId == $e.artifactId and .candidateArtifact.artifactId == $c.artifactId and .sealedArtifact.artifactId == $s.artifactId' "$receipt_path" >/dev/null || return 1
  candidate_obs=$(candidate_observation "$jobs" "$role" "$rejection_channel") || { [[ -s $rejection_channel ]] || role_reject "$rejection_channel" candidate-placement-mismatch; return 1; }
  seal_obs=$(seal_observation "$jobs" "$role" "$rejection_channel") || return 1
  [[ $(jq -r '.checkRunId' <<<"$seal_obs") == $(jq -r '.sealingCheckRunId' "$receipt_path") ]] || { role_reject "$rejection_channel" sealing-job-mismatch; return 1; }
  sealed_path=$tmp/sealed-$role.tar.zst
  candidate_path=$tmp/candidate-$role.tar.zst
  download_one_member_zip "$candidate_artifact" ci-role-evidence.tar.zst "$candidate_path" || return $?
  download_one_member_zip "$sealed_artifact" ci-sealed-role-evidence.tar.zst "$sealed_path" || return $?
  inner=$tmp/inner-$role.tar.zst; role_stage=$tmp/role-$role; manifest=$tmp/manifest-$role.json
  candidate_stage=$tmp/candidate-role-$role; candidate_manifest=$tmp/candidate-manifest-$role.json
  # Candidate and seal archives are distinct trust boundaries. Inspect their
  # safe manifests before the receipt hashes are compared so filesystem drift
  # remains a typed evidence failure instead of a generic bundle failure.
  safe_role_bundle "$candidate_path" "$candidate_stage" "$candidate_manifest" || return 1
  filesystem_manifest_verified "$candidate_manifest" || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  candidate_filesystem=$(jq -er '.roleEvidence.environment.filesystem' "$candidate_manifest") || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  safe_sealed_bundle "$sealed_path" "$inner" "$tmp/sealed-stage-$role" || return 1
  safe_role_bundle "$inner" "$role_stage" "$manifest" || return 1
  # This is a typed evidence invariant.  Do not let an omitted, empty, or
  # changed filesystem observation disappear into the generic archive error.
  filesystem_manifest_verified "$manifest" || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  filesystem_before=$(jq -er '.roleEvidence.environment.filesystem' "$manifest") || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  [[ $filesystem_before == "$candidate_filesystem" ]] || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  # Classify compatibility absence at the boundary where the candidate manifest
  # is first parsed, rather than allowing schema rejection to erase the
  # contract's required typed stage decision.
  if [[ $ticket == BURL-O001 ]]; then
    case "$role" in
      macos-26-arm64) jq -e '.roleEvidence.compatibilityStage == null' "$manifest" >/dev/null || { role_reject "$rejection_channel" compatibility-stage-unexpected; return 1; };;
      macos-15-arm64) jq -e '.roleEvidence.compatibilityStage | type == "object" and has("consumerBinding") and has("producerLineage") and has("producerLineageArtifact") and has("producerLineageSha256")' "$manifest" >/dev/null || { role_reject "$rejection_channel" compatibility-stage-missing; return 1; };;
      *) jq -e '.roleEvidence.compatibilityStage == null' "$manifest" >/dev/null || { role_reject "$rejection_channel" compatibility-stage-unexpected; return 1; };;
    esac
  else
    jq -e '.roleEvidence.compatibilityStage == null' "$manifest" >/dev/null || { role_reject "$rejection_channel" compatibility-stage-unexpected; return 1; }
  fi
  [[ $(sha256_file "$inner") == $(jq -r '.roleBundleSha256' "$receipt_path") && $(sha256_file "$sealed_path") == $(jq -r '.sealedBundleSha256' "$receipt_path") ]] || return 1
  manifest_shape_valid "$manifest" "$role" || return 1
  # The complete candidate manifest is schema- and identity-validated from
  # the local trust anchor before invoking the network attestation verifier.
  # This keeps malformed nested environment/viewport/toolchain objects from
  # ever reaching an otherwise-valid provenance path.
  verify_attestation "$sealed_path" "$role" sealed '' "$rejection_channel" || return $?
  verify_attestation "$receipt_path" "$role" receipt "$receipt_bundle_path" "$rejection_channel" || return $?
  receipt_hash=$(sha256_file "$receipt_path")
  if [[ -n $receipt_artifact_obs ]]; then receipt_artifact_arg=(--argjson receipt_artifact "$receipt_artifact_obs"); else receipt_artifact_arg=(--argjson receipt_artifact 'null'); fi
  role_json=$(jq -cn --slurpfile manifest "$manifest" --arg manifest_hash "$(sha256_file "$manifest")" --argjson repository "$(jq -er '.repositoryId' "$receipt_path")" --argjson candidate "$candidate_obs" --argjson seal "$seal_obs" --argjson candidate_artifact "$candidate_artifact_obs" --argjson sealed_artifact "$sealed_artifact_obs" "${receipt_artifact_arg[@]}" --argjson check "$(jq -er '.sealingCheckRunId' "$receipt_path")" --argjson runid "$run_id" --argjson runattempt "$attempt" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg workflow "$workflow" --arg receipt_hash "$receipt_hash" --arg role_bundle "$(sha256_file "$inner")" --arg sealed_bundle "$(sha256_file "$sealed_path")" --arg sealed_attestation "$sealed_attestation_bundle_sha" --arg receipt_attestation "$receipt_attestation_bundle_sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{manifest:$manifest[0],manifestSha256:$manifest_hash,origin:{repositoryId:$repository,workflowRunId:$runid,runAttempt:$runattempt,trustAnchorSha:$anchor,testedSourceSha:$tested,workflowSignerSha:$signer,workflowSignerRef:"refs/heads/master",baseSha:$base,candidatePlacement:$candidate,sealingCheckRunId:$check,sealingJob:$seal,signerWorkflow:{workflowPath:$workflow,jobWorkflowRef:("SkrOYC/burlmd/"+$workflow+"@refs/heads/master"),jobWorkflowSha:$signer,builderId:("https://github.com/SkrOYC/burlmd/"+$workflow+"@refs/heads/master")},candidateArtifact:$candidate_artifact,sealedArtifact:$sealed_artifact,sealingReceiptArtifact:$receipt_artifact,sealingReceiptSha256:$receipt_hash,attestationIssuer:"https://token.actions.githubusercontent.com",sealedAttestationSubjectDigest:("sha256:"+$sealed_bundle),sealedAttestationBundleSha256:$sealed_attestation,sealedAttestationVerified:true,sealingReceiptAttestationSubjectDigest:("sha256:"+$receipt_hash),sealingReceiptAttestationBundleSha256:$receipt_attestation,sealingReceiptAttestationVerified:true,roleBundleSha256:$role_bundle,sealedBundleSha256:$sealed_bundle,restApiVersion:"2026-03-10",verifiedAt:$now}}') || return 1
  filesystem_role_verified <(printf '%s\n' "$role_json") "$filesystem_before" || { role_reject "$rejection_channel" filesystem-evidence-mismatch; return 1; }
  printf '%s\n' "$role_json"
}

validate_reserved_inventory() {
  local inventory=$1 nonce=${run_identity#managed:} expected_names names expected_count
  expected_names=$(jq -cn --arg nonce "$nonce" --arg ticket "$ticket" '
    ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"] as $roles
    | ["managed-evidence-expected-" + $nonce]
      + [$roles[] | "managed-evidence-candidate-" + . + "-" + $nonce]
      + [$roles[] | "managed-evidence-sealed-" + . + "-" + $nonce]
      + [$roles[] | "managed-evidence-seal-receipt-" + . + "-" + $nonce]
      + ["managed-evidence-receipt-digests-" + $nonce]
      + (if $ticket == "BURL-O001" then ["managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-" + $nonce, "managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-" + $nonce] else [] end)') || return 1
  expected_count=$(jq 'length' <<<"$expected_names")
  jq -e --argjson count "$expected_count" --argjson run "$run_id" '
    (.artifacts | type) == "array" and (.artifacts | length) == $count
    and all(.artifacts[]; (.id | type == "number" and . > 0) and (.workflow_run.id | tonumber) == $run)
  ' "$inventory" >/dev/null || return 1
  names=$(jq -c '[.artifacts[].name] | sort' "$inventory") || return 1
  [[ $names == "$(jq -c 'sort' <<<"$expected_names")" ]] || return 1
  # Exact-set equality above rejects extras and collisions.  Lookup still
  # checks each object is unique before it is downloaded.
}
compatibility_inventory_preflight() {
  local inventory=$1 nonce=${run_identity#managed:} name object
  if [[ $ticket != BURL-O001 ]]; then
    jq -e --arg nonce "$nonce" 'all(.artifacts[]; (.name | startswith("managed-evidence-authenticated-stage-") or startswith("managed-evidence-producer-lineage-")) | not)' "$inventory" >/dev/null || compatibility_fail compatibility-stage-unexpected
    return
  fi
  for name in "managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce" "managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$nonce"; do
    object=$(compatibility_artifact_once "$inventory" "$name") || { case $? in 10) compatibility_fail compatibility-stage-missing;; 11) compatibility_fail compatibility-stage-duplicate;; *) compatibility_fail aggregation-error;; esac; return 1; }
    [[ $(jq -r '.expired' <<<"$object") == false ]] || { compatibility_fail compatibility-stage-expired; return 1; }
  done
}
accepted_report() {
  local roles_json=$1 expected_observation=$2 receipt_transport_observation=$3 image_compatible=$4 compatibility_stage=${5:-null} report_tmp coordinator=${spike_coordinator_execution:-null} compatibility_verified candidate_placement candidate_topology candidate_labels candidate_completion
  [[ $image_compatible == true ]] || return 1
  filesystem_evidence_verified "$roles_json" || return 1
  candidate_placement=$(jq -e 'all(.[]; .origin.candidatePlacement.placementFixedByTrustedWorkflow == true)' <<<"$roles_json") || return 1
  candidate_topology=$(jq -e 'all(.[]; .origin.candidatePlacement.topologyVerified == true)' <<<"$roles_json") || return 1
  candidate_labels=$(jq -e 'all(.[]; .origin.candidatePlacement.labelVerified == true)' <<<"$roles_json") || return 1
  candidate_completion=$(jq -e 'all(.[]; .origin.candidatePlacement.completionVerified == true)' <<<"$roles_json") || return 1
  [[ $candidate_placement == true && $candidate_topology == true && $candidate_labels == true && $candidate_completion == true ]] || return 1
  if [[ $ticket == BURL-O001 ]]; then compatibility_verified=true; else compatibility_verified=null; fi
  prepare_output_parent || return 1
  report_tmp=$(mktemp "$(dirname "$output")/.managed-evidence.XXXXXX") || return 1
  if ! jq -cn --slurpfile identity "$expected" --arg digest "$expected_digest" --argjson expected_artifact "$expected_observation" --argjson receipt_transport_artifact "$receipt_transport_observation" --argjson roles "$roles_json" --argjson compatibility_stage "$compatibility_stage" --argjson compatibility_verified "$compatibility_verified" --argjson coordinator "$coordinator" --argjson image_compatible "$image_compatible" --argjson candidate_placement "$candidate_placement" --argjson candidate_topology "$candidate_topology" --argjson candidate_labels "$candidate_labels" --argjson candidate_completion "$candidate_completion" --argjson version "$AGGREGATE_SCHEMA_VERSION" '{schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,expectedIdentityArtifact:$expected_artifact,receiptDigestTransportArtifact:$receipt_transport_artifact,generatedAt:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),mode:"trusted-anchor-local",status:"accepted",roleEvidence:$roles,compatibilityStage:$compatibility_stage,coordinatorExecution:$coordinator,aggregationChecks:{rolesComplete:true,identityCompared:true,trustAnchorVerified:true,trustedSurfacesUnchanged:true,sourceAllowlistVerified:true,evidenceProfileVerified:true,roleResultsPassed:true,candidatePlacementVerified:$candidate_placement,candidateTopologyVerified:$candidate_topology,candidateLabelsVerified:$candidate_labels,candidateCompletionVerified:$candidate_completion,sealOriginsAuthenticated:true,hostedOriginVerified:true,compatibilityStageVerified:$compatibility_verified,artifactNamesVerified:true,artifactIntegrityVerified:true,bundleContentsVerified:true,filesystemEvidenceVerified:true,imageVersionsCompatible:$image_compatible},rejectionReasons:[]}' >"$report_tmp"; then
    rm -f -- "$report_tmp"
    return 1
  fi
  # Full local-registry schema validation precedes the atomic rename. Semantic
  # relationships are additionally checked per role before this point.
  if ! validate_schema "$AGGREGATE_SCHEMA" "$report_tmp"; then
    rm -f -- "$report_tmp"
    return 1
  fi
  if ! mv -f -- "$report_tmp" "$output"; then
    rm -f -- "$report_tmp"
    return 1
  fi
  summary accepted
}

workflow_signer=
ticket_profile_exists "$ticket" || die 'ticket is absent from trusted managed profile inventory'
declared_report=$(declared_report_path) || die 'missing declared report path'
[[ -n $declared_report && $output == "$evidence_root/$declared_report" ]] || die 'output must be the ticket declared report path'
workflow_guard || die 'workflow-signer guard failed'
source_guard || die 'source allowlist guard failed'
completion_guard || die 'BURL-M003 completion record does not authorize this ticket'
identity_hashes
if [[ $mode == run ]]; then nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [[ $nonce =~ ^[0-9a-f]{32}$ ]] || die 'nonce generation failed'; run_identity=managed:$nonce; fi
make_expected
if is_spike_ticket "$ticket"; then
  spike_id=$(spike_id_for_ticket "$ticket") || die 'ticket has no declared coordinator'
  prepare_spike_coordinator "$spike_id" || die 'coordinator preparation failed before authentication'
elif [[ $ticket == BURL-O004 ]]; then
  prepare_burl_o004_coordinator || die 'BURL-O004 coordinator is not yet a rotated trusted control'
fi
if [[ $mode == run ]]; then
  require_token
  payload=$(jq -cn --arg ref master --arg encoded "$(base64 -w0 "$expected")" --arg digest "$expected_digest" --arg tested "$tested" --arg base "$base" --arg run "$run_identity" --arg nonce "${run_identity#managed:}" '{ref:$ref,inputs:{expected_identity_base64:$encoded,expected_identity_sha256:$digest,tested_source_sha:$tested,base_sha:$base,run_identity:$run,artifact_nonce:$nonce}}')
  dispatch=$(api -X POST -H 'Content-Type: application/json' --data "$payload" "$API_BASE/repos/$REPOSITORY/actions/workflows/ci.yml/dispatches") || die 'workflow dispatch failed before a run ID existed'
  run_id=$(dispatch_run_id "$dispatch") || die 'dispatch response did not provide complete run details'
  attempt=1
fi
require_token
if wait_for_run; then outcome=0; else outcome=$?; fi
case "$outcome" in
  0) ;;
  2) rejected untrusted-origin 'workflow API run attempt did not match'; exit 1;;
  3) rejected sealing-job-failed 'workflow attempt completed unsuccessfully'; exit 1;;
  4) rejected sealing-job-in-progress 'workflow attempt exceeded 21600 seconds'; exit 1;;
  *) operational_api_failure "$outcome" 'workflow run polling' || die 'workflow run polling failed operationally';;
esac

# This authenticated phase reads only API responses and downloaded artifacts;
# none of the candidate checkout or bundle contents is ever executed.
if ! command -v "$GH_BIN" >/dev/null 2>&1; then rejected attestation-unavailable 'GitHub CLI attestation verification is unavailable'; exit 1; fi
if run_json=$(api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id"); then api_status=0; else api_status=$?; fi
((api_status == 0)) || { operational_api_failure "$api_status" 'workflow run lookup' || die 'workflow run lookup failed operationally'; }
workflow_run_is_fresh_dispatch "$run_json" || { rejected untrusted-origin 'workflow run signer, event, or attempt mismatched'; exit 1; }
# Acquisition can take hours.  Re-resolve both remote control and candidate
# refs after the run terminal state, so no accepted report is based on an
# identity invalidated while artifacts were being collected.
workflow_guard && source_guard && completion_guard || { rejected untrusted-origin 'workflow or source guard changed after acquisition'; exit 1; }
inventory=$tmp/artifacts.json
jobs=$tmp/jobs.json
if api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id/artifacts?per_page=100" >"$inventory"; then api_status=0; else api_status=$?; fi
((api_status == 0)) || { operational_api_failure "$api_status" 'run artifact enumeration' || die 'run artifact enumeration failed operationally'; }
if api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id/jobs?filter=latest&per_page=100" >"$jobs"; then api_status=0; else api_status=$?; fi
((api_status == 0)) || { operational_api_failure "$api_status" 'run job enumeration' || die 'run job enumeration failed operationally'; }
if ! compatibility_inventory_preflight "$inventory"; then
  rejected "${compatibility_rejection_code:-aggregation-error}" 'compatibility-stage reserved inventory was missing, duplicate, expired, or unexpected'
  exit 1
fi
validate_reserved_inventory "$inventory" || { rejected artifact-name-collision 'reserved artifact inventory was incomplete, duplicate, expired, or foreign'; exit 1; }
expected_artifact=$(artifact_by_name "$inventory" "managed-evidence-expected-${run_identity#managed:}") || { rejected artifact-name-invalid 'missing expected identity artifact'; exit 1; }
if download_one_member_zip "$expected_artifact" expected-identity.json "$tmp/remote-expected.json"; then api_status=0; else api_status=$?; fi
((api_status == 0)) || { operational_api_failure "$api_status" 'expected identity artifact download' || { rejected artifact-corrupt 'expected identity artifact was unsafe or malformed'; exit 1; }; }
cmp -s "$expected" "$tmp/remote-expected.json" || { rejected identity-mismatch 'remote expected identity bytes differ from locally reconstructed identity'; exit 1; }

receipt_transport_path=$tmp/receipt-upload-digests.json
receipt_transport_result=$tmp/receipt-digest-transport-observation.json
if receipt_digest_transport "$inventory" "$receipt_transport_path" >"$receipt_transport_result"; then api_status=0; else api_status=$?; fi
if ((api_status != 0)); then
  operational_api_failure "$api_status" 'receipt digest transport acquisition' || {
    rejected "${receipt_transport_rejection_code:-artifact-api-mismatch}" 'receipt digest transport REST identity, raw archive, or semantic binding failed'
    exit 1
  }
fi
receipt_transport=$(<"$receipt_transport_result")
receipt_transport_artifact=$(jq -ce '.observation' <<<"$receipt_transport") || die 'verified receipt digest transport observation was malformed'

roles='[]'
for role in "${ROLES[@]}"; do
  # Candidate observation runs in command substitution inside receipt_role.
  # Keep both outer receipt channels parent-owned: the JSON is captured in a
  # file and every durable typed rejection is written separately before return.
  # API statuses still travel as process statuses (75/76/77) and therefore
  # retain their operational, report-preserving routing below.
  role_json_path=$tmp/role-evidence-$role.json
  role_rejection_path=$tmp/role-rejection-$role.txt
  rm -f -- "$role_json_path" "$role_rejection_path"
  if receipt_role "$role" "$inventory" "$jobs" "$role_rejection_path" "$receipt_transport" >"$role_json_path"; then api_status=0; else api_status=$?; fi
  if ((api_status != 0)); then
    role_rejection_code=role-bundle-invalid
    if [[ -s $role_rejection_path ]]; then
      IFS= read -r role_rejection_code <"$role_rejection_path" || die 'role rejection channel was unreadable'
      [[ $role_rejection_code =~ ^(artifact-digest-mismatch|candidate-placement-mismatch|candidate-topology-mismatch|candidate-label-mismatch|candidate-completion-mismatch|filesystem-evidence-mismatch|compatibility-stage-missing|compatibility-stage-unexpected|sealing-job-in-progress|sealing-job-failed|sealing-job-missing|sealing-job-mismatch|sealing-runner-environment-mismatch|untrusted-origin|attestation-unavailable)$ ]] || die 'role rejection channel contained an invalid code'
    fi
    operational_api_failure "$api_status" "role $role evidence acquisition" || {
    rejected "$role_rejection_code" "role $role did not satisfy receipt, job, artifact, provenance, bundle, or filesystem validation"
    exit 1
    }
  fi
  role_json=$(<"$role_json_path")
  roles=$(jq -c --argjson role "$role_json" '. + [$role]' <<<"$roles")
done
expected_upload=$(jq -r '.expectedArtifact.uploadActionDigest' "$tmp/receipt-linux-x86_64.json")
expected_observation=$(artifact_observation "$expected_artifact" "$expected_upload") || { rejected artifact-digest-mismatch 'expected artifact REST digest did not match sealed receipt'; exit 1; }
filesystem_evidence_verified "$roles" || { rejected filesystem-evidence-mismatch 'role filesystem evidence was missing, empty, tampered, or mismatched after archive validation'; exit 1; }
# Do not capture the validator with command substitution: Bash runs that in a
# subshell, which would discard compatibility_rejection_code and collapse every
# typed compatibility failure into aggregation-error.  The collector-owned
# temporary file keeps the validated JSON separate while preserving the code
# selected by the real validation branch.
compatibility_stage_path=$tmp/compatibility-stage.json
if compatibility_stage_for "$inventory" "$roles" >"$compatibility_stage_path"; then api_status=0; else api_status=$?; fi
if ((api_status != 0)); then
  operational_api_failure "$api_status" 'compatibility-stage evidence acquisition' || {
  rejected "${compatibility_rejection_code:-aggregation-error}" 'compatibility stage, lineage, receipt, provenance, or consumer binding validation failed'
  exit 1
  }
fi
compatibility_stage=$(<"$compatibility_stage_path")

# Authentication ends before any future coordinator hook. BURL-M003 has no
# coordinator; managed Spike execution is a separate, credential-free phase.
unset GH_TOKEN GITHUB_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL SSH_AUTH_SOCK GIT_ASKPASS
rm -f "$auth_config"
if is_spike_ticket "$ticket"; then
  close_nonstdio_fds || { rejected coordinator-isolation-failed 'could not close inherited descriptors before coordinator'; exit 1; }
  stage_spike_inputs || { rejected role-bundle-invalid 'could not stage verified role members'; exit 1; }
  if ! run_spike_coordinator; then
    rejected "${spike_rejection_code:-aggregation-error}" 'coordinator sandbox, exact steps, result schema, or authenticated evidence reconciliation failed'
    exit 1
  fi
fi
workflow_guard && source_guard && completion_guard || { rejected untrusted-origin 'workflow or source guard changed before publication'; exit 1; }
measured_image_versions_compatible=false
if image_versions_compatible "$roles" "${spike_results:-}"; then
  measured_image_versions_compatible=true
else
  rejected mixed-image-version 'captured ImageOS/ImageVersion did not match the authenticated role image policy'
  exit 1
fi
# This is intentionally the final external observation before publication.
# A rerun can happen while artifacts or coordinator output are being verified;
# it is neither durable evidence nor a rejection of the prior report. Preserve
# an existing report and require a new dispatch with a new nonce instead.
if final_run_json=$(api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id"); then api_status=0; else api_status=$?; fi
((api_status == 0)) || { operational_api_failure "$api_status" 'workflow run final freshness lookup' || die 'workflow run final freshness lookup failed operationally'; }
workflow_run_is_fresh_dispatch "$final_run_json" || die 'workflow run attempt drifted before accepted publication'
accepted_report "$roles" "$expected_observation" "$receipt_transport_artifact" "$measured_image_versions_compatible" "$compatibility_stage" || die 'accepted aggregate publication failed'
exit 0
