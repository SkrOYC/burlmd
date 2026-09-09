#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-candidate-diagnostic.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
functions=$tmp/functions.sh
{
  sed -n '/^candidate_exec_status=0/,/^validate_candidate_tool_profile$/p' "$root/scripts/run-managed-role.sh" | sed '$d'
  sed -n '/^integration_report_has_successful_tests()/,/^m003_prepare_linux_integration_report_directory()/p' "$root/scripts/run-managed-role.sh" | sed '$d'
  sed -n '/^run_integration_files()/,/^ticket_root_for()/p' "$root/scripts/run-managed-role.sh" | sed '$d'
} >"$functions"
# shellcheck source=/dev/null
source "$functions"
ticket=BURL-M003
role=macos-26-arm64
output_root=$tmp/output
runtime_root=$tmp/runtime
contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
candidate_tool_path=$(dirname "$(command -v perl)")
trusted_perl=$(readlink -f "$(command -v perl)")
mkdir -p "$output_root/results" "$runtime_root"
uname() { printf Darwin; }
prefix='burlmd-m003-diagnostic: '

resolver_functions=$tmp/resolver-functions.sh
awk '/^resolve_trusted_perl\(\)/ { copy = 1 } /^resolve_trusted_perl \|\|/ { copy = 0 } copy { print }' "$root/scripts/run-managed-role.sh" >"$resolver_functions"
bash -ceu 'source "$1"; resolve_trusted_perl; [[ $trusted_perl == /nix/store/* && -f $trusted_perl && -x $trusted_perl ]]' -- "$resolver_functions"
trusted_bash=$(command -v bash)
trusted_readlink_dir=$(dirname "$(command -v readlink)")
for writable_authority in source-root script-root; do
  writable_perl_root=$tmp/$writable_authority
  mkdir "$writable_perl_root"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$writable_perl_root/perl"
  chmod 755 "$writable_perl_root/perl"
  PATH="$writable_perl_root:$trusted_readlink_dir" "$trusted_bash" -ceu 'source "$1"; ! resolve_trusted_perl' -- "$resolver_functions"
done
resolver_line=$(rg -n '^resolve_trusted_perl \|\|' "$root/scripts/run-managed-role.sh" | cut -d: -f1)
dependency_line=$(rg -n '^prepare_candidate_dependencies$' "$root/scripts/run-managed-role.sh" | cut -d: -f1)
[[ $resolver_line -lt $dependency_line ]] || { echo 'trusted Perl is not resolved before candidate dependency work' >&2; exit 1; }

assert_capture() {
  local size=$1 name=$2 source="$output_root/results/role-step-flutter-test.log" output expected actual retained
  perl -e 'print "A" x shift; print "\n::error::candidate bytes\n"' "$size" >"$source"
  : >"$tmp/step-stream.log"
  exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
  emit_candidate_failure_diagnostic flutter-test 17
  output=$(<"$tmp/step-stream.log")
  mapfile -t lines <"$tmp/step-stream.log"
  [[ ${#lines[@]} == 6 ]] || { echo "unexpected diagnostic line count for $name" >&2; exit 1; }
  for line in "${lines[@]}"; do [[ $line == "$prefix"* ]] || { echo "missing exact diagnostic prefix" >&2; exit 1; }; done
  [[ ${lines[0]} == "${prefix}gate_id=flutter-test" && ${lines[1]} == "${prefix}original_exit_status=17" ]] || exit 1
  [[ ${lines[2]} == "${prefix}source_log_bytes=$(wc -c <"$source" | tr -d ' ')" ]] || exit 1
  retained=$(wc -c <"$source" | tr -d ' '); ((retained > 65536)) && retained=65536
  [[ ${lines[3]} == "${prefix}retained_tail_bytes=$retained" ]] || exit 1
  if (( $(wc -c <"$source") > 65536 )); then tail -c 65536 "$source" >"$tmp/expected"; else cp "$source" "$tmp/expected"; fi
  expected=$(sha256sum "$tmp/expected" | awk '{print $1}')
  [[ ${lines[4]} == "${prefix}retained_tail_sha256=$expected" ]] || exit 1
  actual=${lines[5]#"${prefix}base64="}
  [[ $actual == "$(base64 <"$tmp/expected" | tr -d '\n')" ]] || { echo "base64 did not bind the retained bytes" >&2; exit 1; }
  [[ $output != *$'\n::error::candidate bytes'* ]] || { echo 'candidate bytes escaped their base64 diagnostic line' >&2; exit 1; }
}

assert_capture 65509 below-bound
assert_capture 65510 at-bound
assert_capture 65511 above-bound

# Workflow-command-looking bytes remain inert and appear only inside the
# single padded, unwrapped Base64 field.
source="$output_root/results/role-step-flutter-test.log"
printf '%s\n' '::error::hostile' '::warning file=x::hostile' '::notice::hostile' '$(touch should-not-run)' >"$source"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
emit_candidate_failure_diagnostic flutter-test 17
mapfile -t command_lines <"$tmp/step-stream.log"
[[ ${#command_lines[@]} == 6 ]] || exit 1
encoded=${command_lines[5]#"${prefix}base64="}
"$candidate_tool_path/perl" -MMIME::Base64=decode_base64 -e 'print decode_base64(shift)' "$encoded" >"$tmp/decoded-command-payload"
cmp -s "$source" "$tmp/decoded-command-payload"
! rg -q '^::(error|warning|notice)' "$tmp/step-stream.log"
[[ ! -e should-not-run ]]

# A sparse regular file has a genuinely large logical fstat size but must still be read
# only through the fixed tail snapshot; its holes are data, not a reason to
# scan the preceding file.
source="$output_root/results/role-step-flutter-test.log"
truncate -s 8589934592 "$source"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
emit_candidate_failure_diagnostic flutter-test 29
mapfile -t sparse_lines <"$tmp/step-stream.log"
[[ ${sparse_lines[2]} == "${prefix}source_log_bytes=8589934592" && ${sparse_lines[3]} == "${prefix}retained_tail_bytes=65536" ]] || { echo 'sparse tail bounds drifted' >&2; exit 1; }
tail -c 65536 "$source" >"$tmp/sparse-expected"
[[ ${sparse_lines[4]} == "${prefix}retained_tail_sha256=$(sha256sum "$tmp/sparse-expected" | awk '{print $1}')" ]] || exit 1
[[ -z $(find "$runtime_root" -name 'candidate-failure-diagnostic.*' -print -quit) ]] || { echo 'wrapper snapshot pathname remained visible' >&2; exit 1; }

# Concurrent size changes may suppress the diagnostic, but cannot trigger an
# unbounded read or produce internally inconsistent size/retained metadata.
truncate -s 8589934592 "$source"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
(
  for ((mutation = 0; mutation < 2000; mutation++)); do
    truncate -s $((8589934592 + mutation % 2)) "$source" 2>/dev/null || exit 0
  done
) &
changer_pid=$!
emit_candidate_failure_diagnostic flutter-test 31
wait "$changer_pid" 2>/dev/null || true
mapfile -t changing_lines <"$tmp/step-stream.log"
[[ ${#changing_lines[@]} == 0 || ${#changing_lines[@]} == 6 ]] || { echo 'changing source produced a partial diagnostic' >&2; exit 1; }
if [[ ${#changing_lines[@]} == 6 ]]; then
  changing_size=${changing_lines[2]#"${prefix}source_log_bytes="}
  changing_retained=${changing_lines[3]#"${prefix}retained_tail_bytes="}
  [[ $changing_size =~ ^[0-9]+$ && $changing_retained == 65536 ]] || { echo 'changing source metadata was inconsistent' >&2; exit 1; }
fi

# Exercise the production nesting shape: candidate_exec restores errexit before
# returning a failure, run_ci_gate must retain that status, and candidate_phase
# remains an unconditional fail-closed call whose log redirection cannot hide
# the diagnostic from the saved step stream.
record_step() { printf '%s\n' "$1" >>"$tmp/recorded-gates"; }
candidate_exec() {
  candidate_pid=fixture-active
  candidate_wait_pid=fixture-child
  candidate_session=fixture-session
  candidate_macos_cleanup_count=$((candidate_macos_cleanup_count + 1))
  : >"$tmp/cleanup-complete"
  candidate_pid=
  candidate_wait_pid=
  candidate_session=
  candidate_invocation_status=17
  set -e
  return 17
}
candidate_phase() {
  run_ci_gate flutter-test results/role-step-flutter-test.log false
  : >"$tmp/later-gate-ran"
}
candidate_macos_cleanup_count=0
printf 'hostile ::error::candidate command\n' >"$source"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
set +e
(candidate_phase >"$output_root/results/candidate.log" 2>&1)
phase_status=$?
set -e
[[ $phase_status == 17 && -f $tmp/cleanup-complete && ! -e $tmp/later-gate-ran ]] || { echo 'nested candidate failure lost status, cleanup, or fail-closed ordering' >&2; exit 1; }
rg -Fq "${prefix}original_exit_status=17" "$tmp/step-stream.log"
! rg -Fq "$prefix" "$output_root/results/candidate.log" || { echo 'diagnostic remained trapped in candidate.log' >&2; exit 1; }

# Candidate PATH remains writable on hosted macOS. A failed candidate may
# replace its exposed Perl link before the trusted wrapper records the
# diagnostic, but the wrapper must keep using the immutable locked interpreter
# it resolved before candidate execution.
replaceable_tool_path=$tmp/replaceable-tool-path
mkdir "$replaceable_tool_path"
ln -s "$trusted_perl" "$replaceable_tool_path/perl"
candidate_tool_path=$replaceable_tool_path
malicious_marker=$tmp/candidate-perl-executed
github_output=$tmp/github-output
github_env=$tmp/github-env
raw_log=$tmp/raw-workflow-log
: >"$github_output"; : >"$github_env"; : >"$raw_log"
export GITHUB_OUTPUT=$github_output GITHUB_ENV=$github_env
export BURLMD_FIXTURE_MALICIOUS_MARKER=$malicious_marker BURLMD_FIXTURE_RAW_LOG=$raw_log
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf executed >"$BURLMD_FIXTURE_MALICIOUS_MARKER"' \
  'printf hostile-output >>"$GITHUB_OUTPUT"' \
  'printf hostile-env >>"$GITHUB_ENV"' \
  'printf "::error::candidate perl executed\n" >>"$BURLMD_FIXTURE_RAW_LOG"' \
  'exit 0' >"$tmp/malicious-perl"
chmod 755 "$tmp/malicious-perl"
candidate_exec() {
  rm -- "$candidate_tool_path/perl"
  cp -- "$tmp/malicious-perl" "$candidate_tool_path/perl"
  candidate_macos_cleanup_count=$((candidate_macos_cleanup_count + 1))
  : >"$tmp/replacement-cleanup"
  printf 'bounded candidate bytes\n'
  candidate_invocation_status=17
  set -e
  return 17
}
printf 'bounded candidate bytes\n' >"$source"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
set +e
(run_ci_gate flutter-test results/role-step-flutter-test.log false)
replacement_status=$?
set -e
[[ $replacement_status == 17 && -f $tmp/replacement-cleanup ]] || { echo 'candidate Perl replacement changed status or cleanup' >&2; exit 1; }
mapfile -t replacement_lines <"$tmp/step-stream.log"
[[ ${#replacement_lines[@]} == 6 ]] || { echo 'candidate Perl replacement suppressed the bounded diagnostic' >&2; exit 1; }
[[ ${replacement_lines[1]} == "${prefix}original_exit_status=17" ]] || exit 1
replacement_encoded=${replacement_lines[5]#"${prefix}base64="}
"$trusted_perl" -MMIME::Base64=decode_base64 -e 'print decode_base64(shift)' "$replacement_encoded" >"$tmp/replacement-decoded"
cmp -s "$source" "$tmp/replacement-decoded"
[[ ! -e $malicious_marker && ! -s $github_output && ! -s $github_env && ! -s $raw_log ]] || {
  echo 'candidate-controlled Perl executed in the trusted diagnostic path' >&2
  exit 1
}
unset GITHUB_OUTPUT GITHUB_ENV BURLMD_FIXTURE_MALICIOUS_MARKER BURLMD_FIXTURE_RAW_LOG
candidate_tool_path=$(dirname "$trusted_perl")

# Exercise both production integration IDs. The first failing invocation stops
# the loop, retains status 17, records exactly one cleanup per invocation, and
# emits at most one diagnostic block.
candidate_exec() {
  local argument test_file= json_log=
  for argument in "$@"; do
    case $argument in
      integration_test/*_test.dart) test_file=$argument ;;
      --file-reporter=json:*) json_log=${argument#--file-reporter=json:} ;;
    esac
  done
  printf '%s\n' "$test_file" >>"$tmp/integration-cleanups"
  if [[ $test_file == "$fixture_failure_path" ]]; then
    candidate_invocation_status=17
    set -e
    return 17
  fi
  printf '%s\n' '{"type":"testDone","hidden":false,"skipped":false,"result":"success"}' '{"type":"done","success":true}' >"$json_log"
  candidate_invocation_status=0
  set -e
  return 0
}
for fixture_failure_path in integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart; do
  integration_root=$tmp/integration-${fixture_failure_path##*/}
  output_root=$integration_root/output
  runtime_root=$integration_root/runtime
  mkdir -p "$output_root/results" "$runtime_root"
  printf '%s\n' integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart >"$output_root/results/integration-tests.txt"
  for id in 378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d 2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d; do
    printf 'candidate bytes for %s\n' "$id" >"$output_root/results/integration-$id.log"
  done
  : >"$tmp/integration-cleanups"
  : >"$tmp/step-stream.log"
  exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
  set +e
  (run_integration_files macos '' '')
  integration_status=$?
  set -e
  [[ $integration_status == 17 ]] || { echo "integration failure status drifted for $fixture_failure_path" >&2; exit 1; }
  expected_cleanup_count=1
  [[ $fixture_failure_path == integration_test/shell_flow_test.dart ]] && expected_cleanup_count=2
  [[ $(wc -l <"$tmp/integration-cleanups" | tr -d ' ') == "$expected_cleanup_count" ]] || { echo "integration cleanup count drifted for $fixture_failure_path" >&2; exit 1; }
  [[ $(rg -c "${prefix}gate_id=" "$tmp/step-stream.log") == 1 ]] || { echo "integration diagnostic count drifted for $fixture_failure_path" >&2; exit 1; }
  failed_id=$(printf '%s' "$fixture_failure_path" | sha256sum | awk '{print $1}')
  rg -Fq "${prefix}gate_id=integration-$failed_id" "$tmp/step-stream.log"
  rg -Fq "${prefix}original_exit_status=17" "$tmp/step-stream.log"
  if [[ $fixture_failure_path == integration_test/production_host_flow_test.dart ]]; then
    [[ ! -e $output_root/results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.json ]] || { echo 'later integration gate ran after the first failure' >&2; exit 1; }
  fi
done

# A zero-status process with unusable reporter data is a semantic rejection.
# It fails closed without a diagnostic or a fabricated child status.
for reporter_case in missing malformed empty no-success; do
  semantic_root=$tmp/semantic-$reporter_case
  output_root=$semantic_root/output
  runtime_root=$semantic_root/runtime
  mkdir -p "$output_root/results" "$runtime_root"
  printf '%s\n' integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart >"$output_root/results/integration-tests.txt"
  : >"$semantic_root/invocations"
  : >"$semantic_root/step-stream"
  candidate_exec() {
    local argument test_file= json_log=
    for argument in "$@"; do
      case $argument in
        integration_test/*_test.dart) test_file=$argument ;;
        --file-reporter=json:*) json_log=${argument#--file-reporter=json:} ;;
      esac
    done
    printf '%s\n' "$test_file" >>"$semantic_root/invocations"
    case $reporter_case in
      missing) ;;
      malformed) printf '{' >"$json_log" ;;
      empty) : >"$json_log" ;;
      no-success) printf '%s\n' '{"type":"done","success":true}' >"$json_log" ;;
    esac
    candidate_invocation_status=0
    set -e
    return 0
  }
  exec {candidate_diagnostic_fd}>>"$semantic_root/step-stream"
  set +e
  (run_integration_files macos '' '')
  semantic_status=$?
  set -e
  eval "exec ${candidate_diagnostic_fd}>&-"
  candidate_diagnostic_fd=
  first_id=378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d
  second_id=2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d
  [[ $semantic_status == 1 ]] || { echo "$reporter_case reporter rejection returned $semantic_status" >&2; exit 1; }
  [[ $(wc -l <"$semantic_root/invocations" | tr -d ' ') == 1 ]] || { echo "$reporter_case reporter rejection ran a later gate" >&2; exit 1; }
  jq -e '.status == "failed" and .exitCode == 0' "$output_root/results/integration-$first_id.json" >/dev/null || {
    echo "$reporter_case reporter rejection invented a process status" >&2
    exit 1
  }
  [[ ! -e $output_root/results/integration-$second_id.json ]] || { echo "$reporter_case reporter rejection published a later outcome" >&2; exit 1; }
  [[ ! -s $semantic_root/step-stream ]] || { echo "$reporter_case reporter rejection emitted a diagnostic" >&2; exit 1; }
done
output_root=$tmp/output
runtime_root=$tmp/runtime

ln -s "$output_root/results/role-step-flutter-test.log" "$output_root/results/role-step-dart-analyze.log"
: >"$tmp/step-stream.log"
exec {candidate_diagnostic_fd}>>"$tmp/step-stream.log"
emit_candidate_failure_diagnostic dart-analyze 23
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic followed a symbolic link' >&2; exit 1; }
mkdir "$output_root/results/role-step-cargo-metadata.log"
emit_candidate_failure_diagnostic cargo-metadata 23
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic read a directory' >&2; exit 1; }
rmdir "$output_root/results/role-step-cargo-metadata.log"
mkfifo "$output_root/results/role-step-cargo-metadata.log"
emit_candidate_failure_diagnostic cargo-metadata 23
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic read a FIFO' >&2; exit 1; }
rm -- "$output_root/results/role-step-cargo-metadata.log"

# Unavailable and special files are rejected without blocking. A Unix socket
# is held open while the real emitter probes its exact mapped pathname.
emit_candidate_failure_diagnostic cargo-metadata 23
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic read an unavailable source' >&2; exit 1; }
socket_path=$output_root/results/role-step-cargo-metadata.log
"$candidate_tool_path/perl" -MIO::Socket::UNIX -MSocket=SOCK_STREAM -e '
  my ($directory, $name) = @ARGV;
  chdir $directory or die "chdir $directory: $!";
  my $socket = IO::Socket::UNIX->new(Type => SOCK_STREAM, Local => $name, Listen => 1) or die $!;
  sleep 30;
' "$output_root/results" "${socket_path##*/}" &
socket_pid=$!
for ((attempt = 0; attempt < 50; attempt++)); do [[ -S $socket_path ]] && break; sleep 0.02; done
if [[ ! -S $socket_path ]]; then
  kill "$socket_pid" 2>/dev/null || true
  wait "$socket_pid" 2>/dev/null || true
  rm -f -- "$socket_path"
  echo 'socket fixture failed to create its Unix socket' >&2
  exit 1
fi
emit_candidate_failure_diagnostic cargo-metadata 23
kill "$socket_pid" 2>/dev/null || true
wait "$socket_pid" 2>/dev/null || true
rm -f -- "$output_root/results/role-step-cargo-metadata.log"
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic read a socket' >&2; exit 1; }
if mknod "$output_root/results/role-step-cargo-metadata.log" c 1 3 2>/dev/null; then
  emit_candidate_failure_diagnostic cargo-metadata 23
  rm -- "$output_root/results/role-step-cargo-metadata.log"
  [[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic read a device' >&2; exit 1; }
fi

# A linked results parent would escape the canonical role-output root even
# though the final mapped filename itself is regular.
mv "$output_root/results" "$output_root/results-real"
ln -s "$output_root/results-real" "$output_root/results"
printf candidate >"$output_root/results-real/role-step-cargo-metadata.log"
emit_candidate_failure_diagnostic cargo-metadata 23
[[ ! -s $tmp/step-stream.log ]] || { echo 'diagnostic accepted a linked parent path' >&2; exit 1; }
rm -- "$output_root/results"
mv "$output_root/results-real" "$output_root/results"

# Every diagnostic-side failure is advisory. Closing the saved step stream
# forces the final printf to fail, but run_ci_gate still returns status 17.
printf candidate >"$output_root/results/role-step-flutter-test.log"
candidate_exec() { : >"$tmp/closed-sink-cleanup"; candidate_invocation_status=17; set -e; return 17; }
exec {candidate_diagnostic_fd}>"$tmp/closed-step-stream.log"
eval "exec ${candidate_diagnostic_fd}>&-"
set +e
(run_ci_gate flutter-test results/role-step-flutter-test.log false) 2>/dev/null
closed_sink_status=$?
set -e
[[ $closed_sink_status == 17 ]] || { echo 'closed diagnostic sink replaced original candidate status' >&2; exit 1; }
[[ -f $tmp/closed-sink-cleanup ]] || { echo 'closed diagnostic sink skipped candidate cleanup' >&2; exit 1; }
runtime_root=$tmp/unavailable-snapshot-root
candidate_diagnostic_fd=
exec {candidate_diagnostic_fd}>>"$tmp/unavailable-snapshot-stream.log"
set +e
(run_ci_gate flutter-test results/role-step-flutter-test.log false)
unavailable_snapshot_status=$?
set -e
[[ $unavailable_snapshot_status == 17 && ! -s $tmp/unavailable-snapshot-stream.log ]] || { echo 'unavailable snapshot root changed failure handling' >&2; exit 1; }
runtime_root=$tmp/runtime

assert_contract_mutation_rejected() {
  local name=$1 program=$2 mutated=$tmp/contract-$name.toml
  cp -- "$root/.constitution/tech-spec/contracts/provisional-spikes.toml" "$mutated"
  "$candidate_tool_path/perl" -0pi -e "$program" "$mutated"
  cmp -s "$mutated" "$root/.constitution/tech-spec/contracts/provisional-spikes.toml" && { echo "contract mutation did not apply: $name" >&2; exit 1; }
  contract=$mutated
  if validate_candidate_failure_diagnostic_contract; then
    echo "diagnostic contract mutation was accepted: $name" >&2
    exit 1
  fi
  contract=$root/.constitution/tech-spec/contracts/provisional-spikes.toml
}
assert_contract_mutation_rejected missing-entry 's/^  \{ gate_id = "flutter-test"[^\n]*\n//m'
assert_contract_mutation_rejected extra-entry 's/(candidate_failure_diagnostic_gate_log_map = \[\n)/$1  { gate_id = "unknown", relative_source_log = "results\/unknown.log" },\n/'
assert_contract_mutation_rejected duplicate-entry 's/(^  \{ gate_id = "flutter-test"[^\n]*\n)/$1$1/m'
assert_contract_mutation_rejected substituted-entry 's/gate_id = "flutter-test"/gate_id = "flutter-tests"/'
assert_contract_mutation_rejected reordered-entry 's/(^  \{ gate_id = "flutter-test"[^\n]*\n)(  \{ gate_id = "dart-analyze"[^\n]*\n)/$2$1/m'
assert_contract_mutation_rejected unknown-path 's#results/role-step-flutter-test\.log#results/unknown.log#'
assert_contract_mutation_rejected linux-first-integration-path 's#results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d\.log#results/role-step-integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.log#'
assert_contract_mutation_rejected linux-second-integration-path 's#results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d\.log#results/role-step-integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.log#'
assert_contract_mutation_rejected prefix-missing-space 's/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic: "/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic:"/'
assert_contract_mutation_rejected prefix-extra-space 's/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic: "/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic:  "/'
assert_contract_mutation_rejected prefix-substituted-space 's/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic: "/candidate_failure_diagnostic_output_prefix = "burlmd-m003-diagnostic:\\t"/'

# The actual production candidate lifecycle closes the saved diagnostic FD at
# the exec boundary while retaining state across repeated direct invocations.
lifecycle_functions=$tmp/lifecycle-functions.sh
{
  sed -n '/^candidate_session_pids()/,/^candidate_profile_tools()/p' "$root/scripts/run-managed-role.sh" | sed '$d'
  sed -n '/^start_candidate_session()/,/^validate_candidate_tool_profile$/p' "$root/scripts/run-managed-role.sh" | sed '$d'
  sed -n '/^validate_candidate_failure_diagnostic_contract()/,/^ticket_root_for()/p' "$root/scripts/run-managed-role.sh" | sed '$d'
} >"$lifecycle_functions"
bash -ceu '
  source "$1"
  lifecycle_root=$2
  candidate_root=$lifecycle_root/candidate
  output_root=$lifecycle_root/output
  mkdir -p "$candidate_root" "$output_root/results"
  role=macos-26-arm64
  ticket=BURL-M003
  candidate_linux_namespace=false
  candidate_pid= candidate_wait_pid= candidate_session= candidate_marker_file=
  candidate_teardown_lock= candidate_teardown_lock_fd=
  candidate_macos_cleanup_count=0
  candidate_shell=$(command -v bash)
  trusted_perl=$(readlink -f "$(command -v perl)")
  candidate_tool_path=$(dirname "$(command -v perl)")
  candidate_env=("PATH=$PATH")
  exec {candidate_diagnostic_fd}>>"$lifecycle_root/step-stream"
  for expected in 0 0 17; do
    capture_candidate_exec_status "$candidate_shell" -c '\''if { printf leaked >&"$1"; } 2>/dev/null; then exit 99; fi; exit "$2"'\'' _ "$candidate_diagnostic_fd" "$expected"
    [[ $candidate_exec_status == "$expected" ]] || exit 1
  done
  [[ $candidate_macos_cleanup_count == 3 ]] || exit 1
  [[ -z $candidate_pid && -z $candidate_wait_pid && -z $candidate_session ]] || exit 1
  jq -se '\''length == 3 and [.[].session] == [1,2,3] and all(.[]; .containmentClaim == false and .zeroSurvivorClaim == false)'\'' "$output_root/results/macos-bounded-cleanup-observations.ndjson" >/dev/null
  [[ ! -s $lifecycle_root/step-stream ]]
' -- "$lifecycle_functions" "$tmp/actual-lifecycle"

# Keep the direct-child result separate from cleanup-record failure. A failed
# child retains status 17. A successful child with failed cleanup fails closed
# without inventing a process status for the diagnostic channel.
bash -ceu '
  source "$1"
  lifecycle_root=$2
  candidate_root=$lifecycle_root/candidate
  output_root=$lifecycle_root/output
  runtime_root=$lifecycle_root/runtime
  mkdir -p "$candidate_root" "$output_root/results" "$runtime_root"
  role=macos-26-arm64
  ticket=BURL-M003
  contract=$3
  candidate_linux_namespace=false
  candidate_pid= candidate_wait_pid= candidate_session= candidate_marker_file=
  candidate_teardown_lock= candidate_teardown_lock_fd=
  candidate_macos_cleanup_count=0
  candidate_shell=$(command -v bash)
  trusted_perl=$(readlink -f "$(command -v perl)")
  candidate_tool_path=$(dirname "$(command -v perl)")
  candidate_env=("PATH=$PATH")
  cleanup_record_attempts=0
  uname() { printf Darwin; }
  candidate_group_alive() { return 1; }
  candidate_has_survivors() { return 1; }
  kill() {
    local target=${!#}
    if [[ $candidate_wait_pid =~ ^[1-9][0-9]*$ && ( $target == "$candidate_wait_pid" || $target == "-$candidate_wait_pid" ) ]]; then
      return 1
    fi
    : >"$lifecycle_root/unsafe-signal-target"
    return 98
  }
  record_macos_bounded_cleanup() {
    cleanup_record_attempts=$((cleanup_record_attempts + 1))
    return 31
  }
  start_candidate_session() {
    candidate_session=cleanup-failure-fixture
    candidate_marker_file=$lifecycle_root/marker
    printf "%s\n" "$candidate_session" >"$candidate_marker_file"
    "$candidate_shell" -c "exit \"\$1\"" fixture "$1" &
    candidate_wait_pid=$!
    candidate_pid=$candidate_wait_pid
  }
  for case_record in "17 17 17" "0 1 0"; do
    read -r child_status expected_status expected_original <<<"$case_record"
    printf "candidate output\n" >"$output_root/results/role-step-flutter-test.log"
    step_stream=$lifecycle_root/step-stream-$child_status
    later_gate=$lifecycle_root/later-gate-$child_status
    : >"$step_stream"
    exec {candidate_diagnostic_fd}>>"$step_stream"
    capture_candidate_exec_status "$child_status"
    [[ $candidate_exec_status == "$expected_status" ]]
    [[ $candidate_invocation_status == "$expected_original" ]]
    [[ $candidate_cleanup_status == 31 ]]
    if ((candidate_exec_status != 0)); then
      emit_candidate_failure_diagnostic flutter-test "$candidate_invocation_status"
    else
      : >"$later_gate"
    fi
    eval "exec ${candidate_diagnostic_fd}>&-"
    candidate_diagnostic_fd=
    [[ ! -e $later_gate ]]
    if ((child_status == 17)); then
      [[ $(rg -c "burlmd-m003-diagnostic: gate_id=flutter-test" "$step_stream") == 1 ]]
      rg -Fq "burlmd-m003-diagnostic: original_exit_status=17" "$step_stream"
      if rg -Fxq "burlmd-m003-diagnostic: original_exit_status=1" "$step_stream"; then
        echo "cleanup failure replaced the original child status" >&2
        exit 1
      fi
    else
      [[ ! -s $step_stream ]]
    fi
    [[ -z $candidate_pid && -z $candidate_wait_pid && -z $candidate_session ]]
  done
  [[ $cleanup_record_attempts == 2 ]]
  [[ ! -e $lifecycle_root/unsafe-signal-target ]]
' -- "$lifecycle_functions" "$tmp/cleanup-status-separation" "$contract"

# The startup call itself must not place a nested Linux launcher in a Bash
# conditional context. A failed check inside that nested function must exit its
# real launch child before the later sentinel can execute.
bash -ceu '
  source "$1"
  lifecycle_root=$2
  candidate_root=$lifecycle_root/candidate
  output_root=$lifecycle_root/output
  mkdir -p "$candidate_root" "$output_root/results"
  role=linux-x86_64
  ticket=BURL-H001
  candidate_linux_namespace=false
  candidate_pid= candidate_wait_pid= candidate_session= candidate_marker_file=
  candidate_teardown_lock= candidate_teardown_lock_fd=
  candidate_macos_cleanup_count=0
  linux_candidate_bwrap() {
    false
    : >"$lifecycle_root/later-linux-launcher-check-ran"
  }
  capture_candidate_exec_status ignored
  [[ $candidate_exec_status == 1 ]] || exit 1
  [[ ! -e $lifecycle_root/later-linux-launcher-check-ran ]] || {
    echo "failed Linux launcher check continued under an ignored-errexit context" >&2
    exit 1
  }
  [[ -z $candidate_pid && -z $candidate_wait_pid && -z $candidate_session ]] || exit 1
' -- "$lifecycle_functions" "$tmp/linux-launcher-errexit"

# A Darwin launcher can fail after its real direct child exists but before a
# trustworthy leader PID is published.  Exercise both an absent publication and
# a hostile numeric substitution through the production lifecycle.  The kill
# shim permits signals only to the owned direct child or its exact process group;
# values such as 0 and -1 are refused before the shell builtin can see them.
partial_tool_path=$tmp/partial-tool-path
mkdir "$partial_tool_path"
real_perl=$(command -v perl)
real_bash=$(command -v bash)
printf '%s\n' \
  "#!$real_bash" \
  'set -eu' \
  'if [[ ${1:-} != -MPOSIX=setsid ]]; then exec "$BURLMD_FIXTURE_REAL_PERL" "$@"; fi' \
  'printf "%s\n" "$$" >"$BURLMD_FIXTURE_OBSERVED_PID"' \
  'case $BURLMD_FIXTURE_PUBLICATION in' \
  '  missing) trap "exit 143" TERM; while :; do read -r -t 1 _ || :; done ;;' \
  '  malformed) printf "not-a-pid\n" >"$BURLMD_CANDIDATE_PID_FILE"; trap "exit 143" TERM; while :; do read -r -t 1 _ || :; done ;;' \
  '  hostile) printf "1\n" >"$BURLMD_CANDIDATE_PID_FILE"; "$BURLMD_FIXTURE_REAL_PERL" -e "select undef,undef,undef,0.05"; exit 17 ;;' \
  '  *) exit 99 ;;' \
  'esac' >"$partial_tool_path/perl"
chmod 755 "$partial_tool_path/perl"

for publication in missing malformed hostile; do
  partial_root=$tmp/partial-$publication
  mkdir -p "$partial_root/candidate" "$partial_root/output/results" "$partial_root/runtime"
  printf 'candidate diagnostic source\n' >"$partial_root/output/results/role-step-flutter-test.log"
  set +e
  bash -ceu '
    source "$1"
    lifecycle_root=$2
    publication=$3
    candidate_root=$lifecycle_root/candidate
    output_root=$lifecycle_root/output
    runtime_root=$lifecycle_root/runtime
    role=macos-26-arm64
    ticket=BURL-M003
    contract=$4
    candidate_linux_namespace=false
    candidate_pid= candidate_wait_pid= candidate_session= candidate_marker_file=
    candidate_teardown_lock= candidate_teardown_lock_fd=
    candidate_macos_cleanup_count=0
    candidate_shell=$(command -v bash)
    trusted_perl=$(readlink -f "$5/perl")
    candidate_tool_path=$5
    export BURLMD_FIXTURE_REAL_PERL=$6
    candidate_env=("PATH=$PATH" "BURLMD_FIXTURE_REAL_PERL=$6" "BURLMD_FIXTURE_PUBLICATION=$publication" "BURLMD_FIXTURE_OBSERVED_PID=$lifecycle_root/observed-pid")
    uname() { printf Darwin; }
    parent_state=preserved
    exec {candidate_diagnostic_fd}>>"$lifecycle_root/step-stream"
    sleep() { command sleep 0.01; }
    sentinel_pid=
    command sleep 30 & sentinel_pid=$!
    cleanup_fixture_children() {
      local observed=
      if [[ -s $lifecycle_root/observed-pid ]]; then observed=$(<"$lifecycle_root/observed-pid"); fi
      if [[ -n $observed ]] && ! builtin kill -0 "$observed" 2>/dev/null; then
        printf absent >"$lifecycle_root/direct-child-state"
      else
        printf present >"$lifecycle_root/direct-child-state"
        [[ -z $observed ]] || builtin kill -KILL "$observed" 2>/dev/null || true
      fi
      if builtin kill -0 "$sentinel_pid" 2>/dev/null; then printf alive >"$lifecycle_root/sentinel-state"; else printf signalled >"$lifecycle_root/sentinel-state"; fi
      builtin kill -TERM "$sentinel_pid" 2>/dev/null || true
      wait "$sentinel_pid" 2>/dev/null || true
    }
    trap cleanup_fixture_children EXIT
    kill() {
      local target=${!#}
      case $target in
        0|-1) printf "%s\n" "$target" >>"$lifecycle_root/refused-signals"; return 98 ;;
      esac
      if [[ -n ${candidate_wait_pid:-} && ( $target == "$candidate_wait_pid" || $target == "-$candidate_wait_pid" ) ]]; then
        builtin kill "$@"
        return
      fi
      if [[ $target == "$sentinel_pid" || $target == "-$sentinel_pid" ]]; then
        printf "%s\n" "$target" >>"$lifecycle_root/refused-signals"
        return 98
      fi
      printf "%s\n" "$target" >>"$lifecycle_root/refused-signals"
      return 98
    }
    candidate_phase() {
      capture_candidate_exec_status "$candidate_shell" -c "exit 0" >"$output_root/results/role-step-flutter-test.log" 2>&1
      local status=$candidate_exec_status
      if ((status != 0)); then
        emit_candidate_failure_diagnostic flutter-test "$status"
        return "$status"
      fi
      : >"$lifecycle_root/later-gate-ran"
    }
    trap '\''printf "%s:%s\n" "$parent_state" "$candidate_macos_cleanup_count" >"$lifecycle_root/parent-state"'\'' ERR
    candidate_phase
  ' -- "$lifecycle_functions" "$partial_root" "$publication" "$root/.constitution/tech-spec/contracts/provisional-spikes.toml" "$partial_tool_path" "$real_perl"
  partial_status=$?
  set -e
  [[ $partial_status == 1 ]] || { echo "$publication PID publication did not preserve the start failure" >&2; exit 1; }
  [[ $(<"$partial_root/parent-state") == preserved:1 ]] || { echo "$publication PID publication lost parent state or cleanup count" >&2; exit 1; }
  [[ $(<"$partial_root/direct-child-state") == absent ]] || { echo "$publication PID publication left its direct child alive" >&2; exit 1; }
  [[ $(<"$partial_root/sentinel-state") == alive ]] || { echo "$publication PID publication signalled an unrelated child" >&2; exit 1; }
  [[ ! -s $partial_root/refused-signals ]] || { echo "$publication PID publication attempted an unsafe signal target" >&2; exit 1; }
  [[ ! -e $partial_root/later-gate-ran ]] || { echo "$publication PID publication continued to a later gate" >&2; exit 1; }
  [[ $(rg -c "${prefix}gate_id=flutter-test" "$partial_root/step-stream") == 1 ]] || { echo "$publication PID publication did not emit exactly one diagnostic" >&2; exit 1; }
  rg -Fq "${prefix}original_exit_status=1" "$partial_root/step-stream"
done

expected_map=$(taplo get --file-path "$contract" --output-format json ci_bootstrap.role_execution.candidate_failure_diagnostic_gate_log_map | jq -c .)
[[ $expected_map == '[{"gate_id":"flutter-test","relative_source_log":"results/role-step-flutter-test.log"},{"gate_id":"dart-analyze","relative_source_log":"results/role-step-dart-analyze.log"},{"gate_id":"cargo-metadata","relative_source_log":"results/role-step-cargo-metadata.log"},{"gate_id":"integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d","relative_source_log":"results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.log"},{"gate_id":"integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d","relative_source_log":"results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.log"}]' ]] || { echo 'raw contract diagnostic map drifted' >&2; exit 1; }
rg -Fq 'if [[ $ticket == BURL-M003 && $role != linux-x86_64 && $(uname) == Darwin ]]; then' "$root/scripts/run-managed-role.sh"
rg -Fq 'exec {candidate_diagnostic_fd}>&1' "$root/scripts/run-managed-role.sh"
rg -Fq 'close_inherited_candidate_fds' "$root/scripts/run-managed-role.sh"
! rg -Fq '(candidate_exec ' "$root/scripts/run-managed-role.sh"
diagnostic_source=$(sed -n '/^emit_candidate_failure_diagnostic()/,/^ticket_root_for()/p' "$root/scripts/run-managed-role.sh")
[[ $(rg -c 'sysread\(\$input' <<<"$diagnostic_source") == 1 ]]
! rg -q 'tail -c|sha256sum "\$source"|base64 <"\$source"|cat "\$source"' <<<"$diagnostic_source"
printf 'candidate failure diagnostic fixture passed\n'
