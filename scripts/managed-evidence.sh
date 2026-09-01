#!/usr/bin/env bash
# Trusted launcher for the two-phase managed evidence protocol. Candidate
# checkout contents are treated as data; this launcher never sources them.
set -euo pipefail

readonly API_VERSION=2026-03-10
readonly REPOSITORY_DEFAULT=SkrOYC/burlmd
readonly ROLES=(linux-x86_64 macos-26-arm64 macos-15-arm64)
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
if compgen -e | command rg -q "^$reserved_fixture_prefix"; then
  die 'production launcher rejects reserved fixture environment'
fi
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
case "$ticket" in CI-M003|AST-H001|PATH-H002|ASSET-I001|GIT-L001|PKG-M001) ;; *) die 'invalid ticket';; esac
for sha in "$anchor" "$tested" "$base"; do [[ $sha =~ ^[0-9a-f]{40}$ ]] || die 'invalid SHA'; done
[[ $source_ref == refs/heads/* && -n $output ]] || usage
if [[ $mode == collect ]]; then
  [[ $run_identity =~ ^managed:[0-9a-f]{32}$ && $run_id =~ ^[1-9][0-9]*$ && $attempt =~ ^[1-9][0-9]*$ ]] || die 'invalid collection identity'
else
  [[ -z $run_identity && -z $run_id && -z $attempt ]] || usage
fi

anchor_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 'not a Git checkout'
output=$(realpath -m "$output")
[[ -n ${EVIDENCE_WORKTREE:-} ]] || die 'EVIDENCE_WORKTREE is required'
evidence_root=$(realpath "$EVIDENCE_WORKTREE")
[[ $output == "$evidence_root"/* && $output != "$anchor_root"/* ]] || die 'output must be under EVIDENCE_WORKTREE and outside trust anchor'
[[ -z $(git symbolic-ref -q HEAD) && $(git rev-parse HEAD) == "$anchor" && -z $(git status --porcelain) ]] || die 'trust anchor must be clean, detached, and at supplied SHA'
readonly CONTRACT=.constitution/tech-spec/contracts/provisional-spikes.toml
readonly ROLE_SCHEMA=.constitution/tech-spec/contracts/ci-role-evidence.schema.json
readonly AGGREGATE_SCHEMA=.constitution/tech-spec/contracts/ci-evidence.schema.json
readonly RESULT_SCHEMA=.constitution/tech-spec/contracts/spike-result.schema.json
[[ -f $CONTRACT && -f $ROLE_SCHEMA && -f $AGGREGATE_SCHEMA && -f $RESULT_SCHEMA ]] || die 'trusted contracts missing'
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
bootstrap_allowlist() {
  awk '/^bootstrap_write_allowlist[[:space:]]*=/ {on=1} on {sub(/^[^=]*=/, ""); print; if (/\]/) exit}' "$CONTRACT" | jq -ce .
}
spike_allowlist() {
  local spike=$1
  awk -v spike="$spike" '/^\[\[spikes\]\]/ {on=0} $0 == "id = \"SPK-" spike "\"" {on=1; next} on && /^write_allowlist[[:space:]]*=/ {sub(/^[^=]*=/, ""); print; exit}' "$CONTRACT" | jq -ce .
}
workflow_path() { case "$1" in linux-x86_64) printf .github/workflows/ci-role-linux-x86-64.yml;; macos-26-arm64) printf .github/workflows/ci-role-macos-26-arm64.yml;; macos-15-arm64) printf .github/workflows/ci-role-macos-15-arm64.yml;; esac; }
role_label() { case "$1" in linux-x86_64) printf ubuntu-24.04;; macos-26-arm64) printf macos-26;; macos-15-arm64) printf macos-15;; esac; }
spike_for() { case "$1" in AST-H001) printf AST-H001;; PATH-H002) printf PATH-H002;; ASSET-I001) printf ASSET-I001;; GIT-L001) printf GIT-L001;; PKG-M001) printf PKG-M001;; esac; }
declared_report_path() {
  if [[ $ticket == CI-M003 ]]; then printf '.constitution/reports/ci-m003-managed-evidence.json'; return; fi
  awk -v spike="SPK-$(spike_for "$ticket")" '
    /^\[\[spikes\]\]/ {on=0}
    $0 == "id = \"" spike "\"" {on=1; next}
    on && /^managed_report[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*\"/, ""); sub(/\"[[:space:]]*$/, ""); print; exit}
  ' "$CONTRACT"
}

path_allowed() {
  local path=$1 roots=$2 root prefix
  [[ $path != /* && $path != *'..'* && $path != */./* && $path != */ ]] || return 1
  while IFS= read -r root; do
    if [[ $root == */** ]]; then prefix=${root%/**}; [[ $path == "$prefix" || $path == "$prefix"/* ]] && return 0
    elif [[ $root == */\* ]]; then prefix=${root%/*}; [[ $path == "$prefix"/* ]] && return 0
    elif [[ $path == "$root" ]]; then return 0
    fi
  done < <(jq -r '.[]' <<<"$roots")
  return 1
}
workflow_guard() {
  local remote_signer
  remote_signer=$(git ls-remote origin refs/heads/master | awk 'NR == 1 {print $1}')
  [[ $remote_signer =~ ^[0-9a-f]{40}$ ]] || return 1
  git fetch --quiet --no-tags origin '+refs/heads/master:refs/managed-evidence/workflow-signer' || return 1
  workflow_signer=$(git rev-parse refs/managed-evidence/workflow-signer^{commit}) || return 1
  [[ $workflow_signer == "$remote_signer" ]] || return 1
  git merge-base --is-ancestor "$anchor" "$workflow_signer" || return 1
  # The caller, reusable workflows, all executable helpers, and their pinned
  # configuration are a single immutable trust surface.  Comparing complete
  # tree entries (not contents alone) also binds executable modes and rejects
  # a later workflow/helper added beneath one of these transitively executed
  # roots.  Third-party actions are SHA-pinned by the trusted workflows.
  git diff --quiet "$anchor" "$workflow_signer" -- \
    .github/workflows scripts .constitution/tech-spec/contracts \
    devenv.nix devenv.lock Cargo.lock pubspec.lock rust-toolchain.toml || return 1
}
resolve_origin_revisions() {
  # Both revisions must be obtained from origin in this invocation.  The local
  # checkout can contain stale refs or unrelated objects, neither of which is
  # evidence that the candidate/base pair is the pair GitHub will execute.
  git fetch --quiet --no-tags origin "+$source_ref:refs/managed-evidence/source" || return 1
  origin_tested=$(git rev-parse refs/managed-evidence/source^{commit}) || return 1
  # Fetching the named source ref transfers its complete ancestry.  Resolve the
  # supplied base from that origin-derived graph, rather than asking every Git
  # server to permit a direct SHA fetch (which hosted servers rightly reject).
  origin_base=$(git rev-parse "$base^{commit}") || return 1
  git merge-base --is-ancestor "$origin_base" "$origin_tested" || return 1
  [[ $origin_tested == "$tested" && $origin_base == "$base" ]]
}
source_guard() {
  local roots line mode_a mode_b path status
  resolve_origin_revisions || return 1
  if [[ $ticket == CI-M003 ]]; then
    [[ $anchor == "$tested" && $anchor == "$workflow_signer" && $(git rev-parse "$anchor^") == "$base" ]] || return 1
    roots=$(bootstrap_allowlist)
  else
    git merge-base --is-ancestor "$base" "$tested" || return 1
    roots=$(spike_allowlist "$(spike_for "$ticket")") || return 1
  fi
  source_allowlist=$roots
  # Raw diff binds object modes; NUL-delimited names protect spaces and both
  # endpoints of renames/copies are checked instead of only their destination.
  while IFS= read -r -d '' line && IFS= read -r -d '' path; do
    mode_a=${line#*:}; mode_a=${mode_a%% *}; mode_b=${line#* }; mode_b=${mode_b%% *}
    status=${line##* }; status=${status%%[0-9]*}
    path_allowed "$path" "$roots" || return 1
    [[ $mode_a != 120000 && $mode_b != 120000 && $mode_a != 160000 && $mode_b != 160000 ]] || return 1
    case "$status" in R|C) IFS= read -r -d '' path || return 1; path_allowed "$path" "$roots" || return 1;; esac
  done < <(git diff --raw -z --no-abbrev --find-renames --find-copies "$base" "$tested")
  if [[ $ticket != CI-M003 ]]; then
    local p
  for p in scripts/managed-evidence.sh scripts/assert-managed-evidence-isolation.sh .github/workflows/ci.yml .github/workflows/ci-role-linux-x86-64.yml .github/workflows/ci-role-macos-26-arm64.yml .github/workflows/ci-role-macos-15-arm64.yml "$ROLE_SCHEMA" "$AGGREGATE_SCHEMA" "$RESULT_SCHEMA" "$CONTRACT"; do
      [[ -z $(git diff --name-only "$base" "$tested" -- "$p") ]] || return 1
    done
  fi
}
completion_guard() {
  # Spikes are not permitted to bootstrap the managed pipeline.  The reviewed
  # evidence record must already name the immutable anchor used by this run.
  [[ $ticket == CI-M003 ]] && return 0
  # Resolve the completion record from a fresh origin/master fetch, rather
  # than the detached anchor's working tree.  Its structured fields bind the
  # prior CI evidence report to exactly this immutable anchor.
  local completion_ref=refs/managed-evidence/completion-master completion report_sha report_path
  git fetch --quiet --no-tags origin '+refs/heads/master:refs/managed-evidence/completion-master' || return 1
  completion=$(git show "$completion_ref:.constitution/reports/ci-m003-completion.md" 2>/dev/null) || return 1
  [[ $(awk -F ': ' '$1 == "trustAnchorSha" {count++} END {print count + 0}' <<<"$completion") == 1 ]] || return 1
  [[ $(awk -F ': ' '$1 == "report" {count++} END {print count + 0}' <<<"$completion") == 1 ]] || return 1
  [[ $(awk -F ': ' '$1 == "reportSha256" {count++} END {print count + 0}' <<<"$completion") == 1 ]] || return 1
  completion_anchor=$(awk -F ': ' '$1 == "trustAnchorSha" {print $2; exit}' <<<"$completion")
  [[ $completion_anchor =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $completion_anchor == "$anchor" ]] || return 1
  [[ $completion == *'report: .constitution/reports/ci-m003-managed-evidence.json'* ]] || return 1
  report_sha=$(awk -F ': ' '$1 == "reportSha256" {print $2; exit}' <<<"$completion")
  [[ $report_sha =~ ^[0-9a-f]{64}$ ]] || return 1
  report_path=$tmp/ci-m003-completion-report.json
  git show "$completion_ref:.constitution/reports/ci-m003-managed-evidence.json" >"$report_path" 2>/dev/null || return 1
  [[ $(sha256_file "$report_path") == "$report_sha" ]] || return 1
  jq -e --arg requested_anchor "$anchor" '
    .status == "accepted"
    and .expectedIdentity.trustAnchorSha == $requested_anchor
    and .expectedIdentity.testedSourceSha == $requested_anchor
    and .expectedIdentity.workflowSignerSha == $requested_anchor
  ' "$report_path" >/dev/null
}
identity_hashes() {
  { printf 'anchor=%s\nsigner=%s\ntested=%s\nbase=%s\n' "$anchor" "$workflow_signer" "$tested" "$base"; git rev-parse "$tested^{tree}"; git diff --raw --no-abbrev --find-renames --find-copies "$base" "$tested"; git ls-tree -r "$anchor" -- Cargo.lock pubspec.lock devenv.lock rust-toolchain.toml devenv.nix .github scripts; } >"$tmp/build-manifest"
  git ls-tree -r "$tested" -- test integration_test test_driver >"$tmp/corpus-manifest"
  build_identity=$(sha256_file "$tmp/build-manifest")
  corpus_identity=$(sha256_file "$tmp/corpus-manifest")
}
make_expected() {
  local profiles='{}' role array nonce=${run_identity#managed:}
  for role in "${ROLES[@]}"; do array=$(profile_for "$ticket" "$role") || die 'missing exact ticket profile'; profiles=$(jq -c --arg r "$role" --argjson p "$array" '. + {($r):$p}' <<<"$profiles"); done
  jq -cn --arg ticket "$ticket" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg build "$build_identity" --arg corpus "$corpus_identity" --arg run "$run_identity" --arg nonce "$nonce" --argjson allow "$source_allowlist" --argjson profiles "$profiles" '{ticketIdentity:$ticket,releaseIdentity:("candidate:"+$tested),trustAnchorSha:$anchor,testedSourceSha:$tested,workflowSignerSha:$signer,workflowSignerRef:"refs/heads/master",baseSha:$base,workflowEvent:"workflow_dispatch",evidenceReportCommitPolicy:"later-reviewed-evidence-pr-with-declared-evidence-only-diff",sourceWriteAllowlist:$allow,buildIdentity:$build,corpusIdentity:$corpus,runIdentity:$run,artifactNonce:$nonce,requiredRoleIdentities:["linux-x86_64","macos-26-arm64","macos-15-arm64"],requiredRoleSigners:{"linux-x86_64":{workflowPath:".github/workflows/ci-role-linux-x86-64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master",jobWorkflowSha:$signer},"macos-26-arm64":{workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master",jobWorkflowSha:$signer},"macos-15-arm64":{workflowPath:".github/workflows/ci-role-macos-15-arm64.yml",jobWorkflowRef:"SkrOYC/burlmd/.github/workflows/ci-role-macos-15-arm64.yml@refs/heads/master",jobWorkflowSha:$signer}},requiredEvidenceClasses:$profiles}' >"$expected"
  expected_digest=$(sha256_file "$expected")
}
summary() { jq -cn --arg status "$1" --arg runIdentity "$run_identity" --argjson workflowRunId "${run_id:-0}" --argjson runAttempt "${attempt:-0}" --arg trustAnchorSha "$anchor" --arg workflowSignerSha "$workflow_signer" --arg testedSourceSha "$tested" --argjson result null --arg report "$output" '{status:$status,runIdentity:$runIdentity,workflowRunId:$workflowRunId,runAttempt:$runAttempt,trustAnchorSha:$trustAnchorSha,workflowSignerSha:$workflowSignerSha,testedSourceSha:$testedSourceSha,result:$result,report:$report}'; }
validate_schema() {
  local schema=$1 instance=$2
  command -v check-jsonschema >/dev/null 2>&1 || return 1
  check-jsonschema --schemafile "$schema" "$instance"
}
rejected() {
  local code=$1 detail=$2 report_tmp
  mkdir -p "$(dirname "$output")" || return 1
  report_tmp=$(mktemp "$(dirname "$output")/.managed-evidence.XXXXXX") || return 1
  jq -cn --slurpfile expected "$expected" --arg digest "$expected_digest" --arg code "$code" --arg detail "$detail" --argjson version "$AGGREGATE_SCHEMA_VERSION" '{schemaVersion:$version,expectedIdentity:$expected[0],expectedIdentitySha256:$digest,expectedIdentityArtifact:null,generatedAt:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),mode:"trusted-anchor-local",status:"rejected",roleEvidence:[],coordinatorExecution:null,aggregationChecks:{rolesComplete:false,identityCompared:false,trustAnchorVerified:false,trustedSurfacesUnchanged:false,sourceAllowlistVerified:false,evidenceProfileVerified:false,roleResultsPassed:false,originAuthenticated:false,hostedOriginVerified:false,jobTopologyVerified:false,artifactNamesVerified:false,artifactIntegrityVerified:false,bundleContentsVerified:false,imageVersionsCompatible:false},rejectionReasons:[{code:$code,detail:$detail}]}' >"$report_tmp" || return 1
  validate_schema "$AGGREGATE_SCHEMA" "$report_tmp" || return 1
  mv -f "$report_tmp" "$output" || return 1
  summary rejected
}
require_token() {
  [[ -n ${GH_TOKEN:-} && ${GH_TOKEN} != *$'\n'* && ${GH_TOKEN} != *$'\r'* ]] || die 'GH_TOKEN is required'
  umask 077
  # Curl's config keeps the secret out of process arguments, stdout, reports,
  # and artifacts. It is removed by the EXIT trap before coordinator execution.
  printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github+json"\nheader = "X-GitHub-Api-Version: %s"\n' "$GH_TOKEN" "$API_VERSION" >"$auth_config"
}
api() { "$CURL_BIN" --fail-with-body --silent --show-error --config "$auth_config" "$@"; }
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
  case "$1" in AST-H001) printf SPK-AST-H001;; PATH-H002) printf SPK-PATH-H002;; ASSET-I001) printf SPK-ASSET-I001;; GIT-L001) printf SPK-GIT-L001;; PKG-M001) printf SPK-PKG-M001;; *) return 1;; esac
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
  local spike=$1 manifest lockfile target binary build raw_root raw_output raw_result raw_results raw_prepare bash_bin source_manifest source_lock source_dir bwrap_bin closure_file
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
  git archive "$tested" | tar -x -C "$source_dir" || return 1
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
  bwrap_bin=$(command -v bwrap) || return 1
  [[ $("$bwrap_bin" --version | awk '{print $NF}') == 0.11.2 ]] || return 1
  command -v nix-store >/dev/null 2>&1 || return 1
  closure_file=$tmp/prepare-closure
  nix-store -qR "$bwrap_bin" "$bash_bin" "$(command -v cargo)" | LC_ALL=C sort -u >"$closure_file" || return 1
  # Fetch is locked and credential-free; the subsequent build runs with the
  # network namespace unshared, source/dependency roots read-only, and only
  # the target directory writable.
  env -i PATH="$(dirname "$(command -v cargo)"):$(dirname "$bash_bin")" HOME="$tmp/prepare-home" CARGO_HOME="$tmp/prepare-cargo" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 cargo fetch --locked --manifest-path "$source_manifest" || return 1
  close_nonstdio_fds || return 1
  build_args=(--unshare-all --unshare-net --die-with-parent --new-session --proc /proc --dev /dev --tmpfs /tmp --dir /home --dir /source --dir /deps --dir /target --ro-bind "$source_dir" /source --ro-bind "$tmp/prepare-cargo" /deps --bind "$spike_target" /target --chdir /source)
  while IFS= read -r closure; do [[ -n $closure ]] && build_args+=(--ro-bind "$closure" "$closure"); done <"$closure_file"
  sandbox_build=${build//$source_dir/\/source}; sandbox_build=${sandbox_build//$spike_target/\/target}
  env -i PATH="$(dirname "$(command -v cargo)"):$(dirname "$bash_bin")" HOME=/home/coordinator CARGO_HOME=/deps GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 "$bwrap_bin" "${build_args[@]}" "$bash_bin" -ceu "$sandbox_build" || return 1
  spike_toolchain_closure_sha=$(sha256_file "$closure_file")
  [[ -x $spike_coordinator_binary ]] || return 1
  spike_executable_sha=$(sha256_file "$spike_coordinator_binary")
  # Bind the coordinator to its own immutable, anchor-owned source tree rather
  # than the whole repository (which also contains untrusted tested-source
  # data for a Spike).
  spike_source_sha=$(git rev-parse "$tested:${manifest%/*}" | sha256sum | awk '{print $1}')
  spike_lockfile_sha=$(sha256_file "$source_lock")
  spike_contract_sha=$(sha256_file "$CONTRACT")
  spike_build_command_sha=$(printf %s "$build" | sha256sum | awk '{print $1}')
  : "${spike_toolchain_closure_sha:=$spike_lockfile_sha}"
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
      and (.runnerLabel == "ubuntu-24.04" or .runnerLabel == "macos-26" or .runnerLabel == "macos-15")
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
wait_for_run() {
  local started=$SECONDS response status conclusion observed
  while ((SECONDS - started < 7200)); do
    response=$(api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id") || return 1
    observed=$(jq -r '.run_attempt // 0' <<<"$response"); status=$(jq -r '.status // empty' <<<"$response"); conclusion=$(jq -r '.conclusion // empty' <<<"$response")
    [[ $observed == "$attempt" ]] || return 2
    [[ $status == completed ]] && { [[ $conclusion == success ]] && return 0 || return 3; }
    sleep 5
  done
  return 4
}

artifact_by_name() {
  local inventory=$1 name=$2 count
  count=$(jq --arg n "$name" '[.artifacts[] | select(.name == $n and .expired == false)] | length' "$inventory")
  [[ $count == 1 ]] || return 1
  jq -ce --arg n "$name" '.artifacts[] | select(.name == $n and .expired == false)' "$inventory"
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
  api -L "$API_BASE/repos/$REPOSITORY/actions/artifacts/$id/zip" >"$archive" || return 1
  safe_zip_member "$archive" "$expected_name" || return 1
  extracted=$tmp/extracted-$id
  mkdir "$extracted" || return 1
  unzip -qq "$archive" -d "$extracted" || return 1
  [[ ! -L $extracted/$expected_name && -f $extracted/$expected_name ]] || return 1
  install -m 600 "$extracted/$expected_name" "$destination"
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
    and (.roleEvidence | keys | sort) == ["capturedIdentity","environment","evidenceClasses","gates","internalArtifacts","role","toolchain","viewport"]
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
job_observation() {
  local jobs=$1 job_name=$2 role=$3 job count label check_id job_id
  label=$(role_label "$role")
  count=$(jq --arg n "$job_name" --arg label "$label" '[.jobs[] | select((.name == $n or (.name | endswith("/ " + $n))) and ((.labels | index($label)) != null))] | length' "$jobs")
  [[ $count == 1 ]] || return 1
  job=$(jq -ce --arg n "$job_name" --arg label "$label" '.jobs[] | select((.name == $n or (.name | endswith("/ " + $n))) and ((.labels | index($label)) != null))' "$jobs") || return 1
  jq -e --arg label "$label" '.status == "completed" and .conclusion == "success" and (.labels | index($label)) != null and (.labels | index("self-hosted")) == null and (.run_id | tostring) == $run' --arg run "$run_id" <<<"$job" >/dev/null || return 1
  check_id=$(jq -er '.check_run_url | capture("/check-runs/(?<id>[1-9][0-9]*)$").id | tonumber' <<<"$job") || return 1
  job_id=$(jq -er '.id | select(type == "number" and . > 0) | floor' <<<"$job") || return 1
  jq -cn --argjson id "$job_id" --argjson check "$check_id" --arg key "$job_name" --argjson labels "$(jq '.labels' <<<"$job")" '{jobId:$id,checkRunId:$check,workflowJobKey:$key,runnerLabels:$labels,runnerEnvironment:"github-hosted",status:"completed",conclusion:"success"}'
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

verify_attestation() {
  local artifact=$1 role=$2 kind=$3 response signer subject bundle_path
  signer="$REPOSITORY/$(workflow_path "$role")"
  response=$($GH_BIN attestation verify "$artifact" --repo "$REPOSITORY" --format json \
    --cert-oidc-issuer https://token.actions.githubusercontent.com \
    --deny-self-hosted-runners --signer-workflow "$signer" \
    --signer-digest "$workflow_signer" --source-digest "$workflow_signer" \
    --source-ref refs/heads/master 2>"$tmp/attestation.stderr") || return 1
  # gh verifies the certificate/signature before emitting JSON. The role
  # manifest, receipt, and artifact names bind runIdentity and artifactNonce;
  # actions/attest does not put those inputs in its default predicate.
  subject=$(sha256_file "$artifact")
  attestation_predicate_valid "$response" "$subject" "$role" || return 1
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
receipt_role() {
  local role=$1 inventory=$2 jobs=$3 nonce=${run_identity#managed:} receipt_artifact receipt_path sealed_artifact candidate_artifact expected_artifact sealed_path inner role_stage manifest candidate_job seal_job candidate_obs seal_obs expected_obs candidate_artifact_obs sealed_artifact_obs receipt_hash workflow
  receipt_artifact=$(artifact_by_name "$inventory" "managed-evidence-seal-receipt-$role-$nonce") || return 1
  receipt_path=$tmp/receipt-$role.json
  download_one_member_zip "$receipt_artifact" ci-seal-receipt.json "$receipt_path" || return 1
  jq -e --arg role "$role" --argjson run "$run_id" --argjson att "$attempt" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg nonce "$nonce" --arg digest "$expected_digest" '.schemaVersion == 1 and .role == $role and .workflowRunId == $run and .runAttempt == $att and .trustAnchorSha == $anchor and .testedSourceSha == $tested and .workflowSignerSha == $signer and .workflowSignerRef == "refs/heads/master" and .baseSha == $base and .artifactNonce == $nonce and .expectedIdentitySha256 == $digest and .runnerEnvironmentClaim == "github-hosted" and (.sealingCheckRunId | type == "number" and . > 0)' "$receipt_path" >/dev/null || return 1
  workflow=$(workflow_path "$role")
  [[ $(jq -r '.workflowPath' "$receipt_path") == "$workflow" ]] || return 1
  expected_artifact=$(artifact_by_name "$inventory" "managed-evidence-expected-$nonce") || return 1
  candidate_artifact=$(artifact_by_name "$inventory" "managed-evidence-candidate-$role-$nonce") || return 1
  sealed_artifact=$(artifact_by_name "$inventory" "managed-evidence-sealed-$role-$nonce") || return 1
  expected_obs=$(artifact_observation "$expected_artifact" "$(jq -r '.expectedArtifact.uploadActionDigest' "$receipt_path")") || return 1
  candidate_artifact_obs=$(artifact_observation "$candidate_artifact" "$(jq -r '.candidateArtifact.uploadActionDigest' "$receipt_path")") || return 1
  sealed_artifact_obs=$(artifact_observation "$sealed_artifact" "$(jq -r '.sealedArtifact.uploadActionDigest' "$receipt_path")") || return 1
  # Receipts bind the REST observations; independently reject swapped IDs/names.
  jq -e --argjson e "$expected_obs" --argjson c "$candidate_artifact_obs" --argjson s "$sealed_artifact_obs" '.expectedArtifact.artifactId == $e.artifactId and .candidateArtifact.artifactId == $c.artifactId and .sealedArtifact.artifactId == $s.artifactId' "$receipt_path" >/dev/null || return 1
  candidate_obs=$(job_observation "$jobs" candidate "$role") || return 1
  seal_obs=$(job_observation "$jobs" seal "$role") || return 1
  [[ $(jq -r '.checkRunId' <<<"$seal_obs") == $(jq -r '.sealingCheckRunId' "$receipt_path") ]] || return 1
  sealed_path=$tmp/sealed-$role.tar.zst
  download_one_member_zip "$sealed_artifact" ci-sealed-role-evidence.tar.zst "$sealed_path" || return 1
  inner=$tmp/inner-$role.tar.zst; role_stage=$tmp/role-$role; manifest=$tmp/manifest-$role.json
  safe_sealed_bundle "$sealed_path" "$inner" "$tmp/sealed-stage-$role" || return 1
  [[ $(sha256_file "$inner") == $(jq -r '.roleBundleSha256' "$receipt_path") && $(sha256_file "$sealed_path") == $(jq -r '.sealedBundleSha256' "$receipt_path") ]] || return 1
  safe_role_bundle "$inner" "$role_stage" "$manifest" || return 1
  manifest_shape_valid "$manifest" "$role" || return 1
  # The complete candidate manifest is schema- and identity-validated from
  # the local trust anchor before invoking the network attestation verifier.
  # This keeps malformed nested environment/viewport/toolchain objects from
  # ever reaching an otherwise-valid provenance path.
  verify_attestation "$sealed_path" "$role" sealed || return 1
  verify_attestation "$receipt_path" "$role" receipt || return 1
  receipt_hash=$(sha256_file "$receipt_path")
  jq -cn --slurpfile manifest "$manifest" --arg manifest_hash "$(sha256_file "$manifest")" --argjson repository "$(jq -er '.repositoryId' "$receipt_path")" --argjson candidate "$candidate_obs" --argjson seal "$seal_obs" --argjson candidate_artifact "$candidate_artifact_obs" --argjson sealed_artifact "$sealed_artifact_obs" --argjson check "$(jq -er '.sealingCheckRunId' "$receipt_path")" --argjson runid "$run_id" --argjson runattempt "$attempt" --arg anchor "$anchor" --arg tested "$tested" --arg signer "$workflow_signer" --arg base "$base" --arg workflow "$workflow" --arg receipt_hash "$receipt_hash" --arg role_bundle "$(sha256_file "$inner")" --arg sealed_bundle "$(sha256_file "$sealed_path")" --arg sealed_attestation "$sealed_attestation_bundle_sha" --arg receipt_attestation "$receipt_attestation_bundle_sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{manifest:$manifest[0],manifestSha256:$manifest_hash,origin:{repositoryId:$repository,workflowRunId:$runid,runAttempt:$runattempt,trustAnchorSha:$anchor,testedSourceSha:$tested,workflowSignerSha:$signer,workflowSignerRef:"refs/heads/master",baseSha:$base,candidateJob:$candidate,sealingCheckRunId:$check,sealingJob:$seal,signerWorkflow:{workflowPath:$workflow,jobWorkflowRef:("SkrOYC/burlmd/"+$workflow+"@refs/heads/master"),jobWorkflowSha:$signer,builderId:("https://github.com/SkrOYC/burlmd/"+$workflow+"@refs/heads/master")},candidateArtifact:$candidate_artifact,sealedArtifact:$sealed_artifact,sealingReceiptSha256:$receipt_hash,attestationIssuer:"https://token.actions.githubusercontent.com",sealedAttestationSubjectDigest:("sha256:"+$sealed_bundle),sealedAttestationBundleSha256:$sealed_attestation,sealedAttestationVerified:true,sealingReceiptAttestationSubjectDigest:("sha256:"+$receipt_hash),sealingReceiptAttestationBundleSha256:$receipt_attestation,sealingReceiptAttestationVerified:true,roleBundleSha256:$role_bundle,sealedBundleSha256:$sealed_bundle,restApiVersion:"2026-03-10",verifiedAt:$now}}'
}

validate_reserved_inventory() {
  local inventory=$1 nonce=${run_identity#managed:} expected_names names expected_count
  expected_names=$(jq -cn --arg nonce "$nonce" --arg ticket "$ticket" '
    ["linux-x86_64", "macos-26-arm64", "macos-15-arm64"] as $roles
    | ["managed-evidence-expected-" + $nonce]
      + [$roles[] | "managed-evidence-candidate-" + . + "-" + $nonce]
      + [$roles[] | "managed-evidence-sealed-" + . + "-" + $nonce]
      + [$roles[] | "managed-evidence-seal-receipt-" + . + "-" + $nonce]
      + (if $ticket == "PKG-M001" then ["managed-evidence-authenticated-stage-macos-26-arm64-" + $nonce] else [] end)') || return 1
  expected_count=$(jq 'length' <<<"$expected_names")
  jq -e --argjson count "$expected_count" --argjson run "$run_id" '
    (.artifacts | type) == "array" and (.artifacts | length) == $count
    and all(.artifacts[]; (.id | type == "number" and . > 0) and .expired == false and (.workflow_run.id | tonumber) == $run)
  ' "$inventory" >/dev/null || return 1
  names=$(jq -c '[.artifacts[].name] | sort' "$inventory") || return 1
  [[ $names == "$(jq -c 'sort' <<<"$expected_names")" ]] || return 1
  # Exact-set equality above rejects extras and collisions.  Lookup still
  # checks each object is unique before it is downloaded.
}
accepted_report() {
  local roles_json=$1 expected_observation=$2 image_compatible=$3 report_tmp coordinator=${spike_coordinator_execution:-null}
  [[ $image_compatible == true ]] || return 1
  report_tmp=$(mktemp "$(dirname "$output")/.managed-evidence.XXXXXX") || return 1
  jq -cn --slurpfile identity "$expected" --arg digest "$expected_digest" --argjson expected_artifact "$expected_observation" --argjson roles "$roles_json" --argjson coordinator "$coordinator" --argjson image_compatible "$image_compatible" --argjson version "$AGGREGATE_SCHEMA_VERSION" '{schemaVersion:$version,expectedIdentity:$identity[0],expectedIdentitySha256:$digest,expectedIdentityArtifact:$expected_artifact,generatedAt:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),mode:"trusted-anchor-local",status:"accepted",roleEvidence:$roles,coordinatorExecution:$coordinator,aggregationChecks:{rolesComplete:true,identityCompared:true,trustAnchorVerified:true,trustedSurfacesUnchanged:true,sourceAllowlistVerified:true,evidenceProfileVerified:true,roleResultsPassed:true,originAuthenticated:true,hostedOriginVerified:true,jobTopologyVerified:true,artifactNamesVerified:true,artifactIntegrityVerified:true,bundleContentsVerified:true,imageVersionsCompatible:$image_compatible},rejectionReasons:[]}' >"$report_tmp" || return 1
  # Full local-registry schema validation precedes the atomic rename. Semantic
  # relationships are additionally checked per role before this point.
  validate_schema "$AGGREGATE_SCHEMA" "$report_tmp" || return 1
  mv -f "$report_tmp" "$output" || return 1
  summary accepted
}

workflow_signer=
declared_report=$(declared_report_path) || die 'missing declared report path'
[[ -n $declared_report && $output == "$evidence_root/$declared_report" ]] || die 'output must be the ticket declared report path'
workflow_guard || die 'workflow-signer guard failed'
source_guard || die 'source allowlist guard failed'
completion_guard || die 'CI-M003 completion record does not authorize this ticket'
identity_hashes
if [[ $mode == run ]]; then nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [[ $nonce =~ ^[0-9a-f]{32}$ ]] || die 'nonce generation failed'; run_identity=managed:$nonce; fi
make_expected
if [[ $ticket != CI-M003 ]]; then
  spike_id=$(spike_id_for_ticket "$ticket") || die 'ticket has no declared coordinator'
  prepare_spike_coordinator "$spike_id" || die 'coordinator preparation failed before authentication'
fi
if [[ $mode == run ]]; then
  require_token
  payload=$(jq -cn --arg ref master --arg encoded "$(base64 -w0 "$expected")" --arg digest "$expected_digest" --arg tested "$tested" --arg base "$base" --arg run "$run_identity" --arg nonce "${run_identity#managed:}" '{ref:$ref,inputs:{expected_identity_base64:$encoded,expected_identity_sha256:$digest,tested_source_sha:$tested,base_sha:$base,run_identity:$run,artifact_nonce:$nonce}}')
  dispatch=$(api -X POST -H 'Content-Type: application/json' --data "$payload" "$API_BASE/repos/$REPOSITORY/actions/workflows/ci.yml/dispatches") || die 'workflow dispatch failed before a run ID existed'
  run_id=$(jq -er '.workflow_run_id | select(type == "number" and . > 0) | floor' <<<"$dispatch") || die 'dispatch response did not provide workflow_run_id'
  attempt=1
fi
require_token
wait_for_run; outcome=$?
case "$outcome" in 0) ;; 3) rejected sealing-job-failed 'workflow attempt completed unsuccessfully'; exit 1;; 4) rejected sealing-job-in-progress 'workflow attempt exceeded 7200 seconds'; exit 1;; *) rejected untrusted-origin 'workflow API run or attempt did not match'; exit 1;; esac

# This authenticated phase reads only API responses and downloaded artifacts;
# none of the candidate checkout or bundle contents is ever executed.
if ! command -v "$GH_BIN" >/dev/null 2>&1; then rejected attestation-unavailable 'GitHub CLI attestation verification is unavailable'; exit 1; fi
run_json=$(api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id") || { rejected untrusted-origin 'workflow run lookup failed'; exit 1; }
jq -e --arg signer "$workflow_signer" --argjson exact_attempt "$attempt" '.event == "workflow_dispatch" and .head_branch == "master" and .head_sha == $signer and .run_attempt == $exact_attempt and (.path == ".github/workflows/ci.yml@master" or .path == ".github/workflows/ci.yml@refs/heads/master")' <<<"$run_json" >/dev/null || { rejected untrusted-origin 'workflow run signer, event, or attempt mismatched'; exit 1; }
# Acquisition can take hours.  Re-resolve both remote control and candidate
# refs after the run terminal state, so no accepted report is based on an
# identity invalidated while artifacts were being collected.
workflow_guard && source_guard && completion_guard || { rejected untrusted-origin 'workflow or source guard changed after acquisition'; exit 1; }
inventory=$tmp/artifacts.json
jobs=$tmp/jobs.json
api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id/artifacts?per_page=100" >"$inventory" || { rejected artifact-api-mismatch 'cannot enumerate run artifacts'; exit 1; }
api "$API_BASE/repos/$REPOSITORY/actions/runs/$run_id/jobs?filter=latest&per_page=100" >"$jobs" || { rejected job-topology-mismatch 'cannot enumerate run jobs'; exit 1; }
validate_reserved_inventory "$inventory" || { rejected artifact-name-collision 'reserved artifact inventory was incomplete, duplicate, expired, or foreign'; exit 1; }
expected_artifact=$(artifact_by_name "$inventory" "managed-evidence-expected-${run_identity#managed:}") || { rejected artifact-name-invalid 'missing expected identity artifact'; exit 1; }
download_one_member_zip "$expected_artifact" expected-identity.json "$tmp/remote-expected.json" || { rejected artifact-corrupt 'expected identity artifact was unsafe or malformed'; exit 1; }
cmp -s "$expected" "$tmp/remote-expected.json" || { rejected identity-mismatch 'remote expected identity bytes differ from locally reconstructed identity'; exit 1; }

roles='[]'
for role in "${ROLES[@]}"; do
  if ! role_json=$(receipt_role "$role" "$inventory" "$jobs"); then
    rejected role-bundle-invalid "role $role did not satisfy receipt, job, artifact, provenance, or bundle validation"
    exit 1
  fi
  roles=$(jq -c --argjson role "$role_json" '. + [$role]' <<<"$roles")
done
expected_upload=$(jq -r '.expectedArtifact.uploadActionDigest' "$tmp/receipt-linux-x86_64.json")
expected_observation=$(artifact_observation "$expected_artifact" "$expected_upload") || { rejected artifact-digest-mismatch 'expected artifact REST digest did not match sealed receipt'; exit 1; }

# Authentication ends before any future coordinator hook. CI-M003 has no
# coordinator; managed Spike execution is a separate, credential-free phase.
unset GH_TOKEN GITHUB_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL SSH_AUTH_SOCK GIT_ASKPASS
rm -f "$auth_config"
if [[ $ticket != CI-M003 ]]; then
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
accepted_report "$roles" "$expected_observation" "$measured_image_versions_compatible" || die 'accepted aggregate publication failed'
exit 0
