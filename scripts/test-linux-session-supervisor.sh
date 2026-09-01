#!/usr/bin/env bash
# Executable raw-38 fixture for the definitions-only in-namespace supervisor.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
supervisor=$root/scripts/supervise-linux-session.sh
pinned_bash=/nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash
core_env=/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env
core_cmp=/nix/store/3c05s0vxy8wafaa7lkj4bfh69wa0ch10-diffutils-3.12/bin/cmp
source_command='source "$1"; shift; main "$@"'

[[ -x $supervisor && -x $pinned_bash && -x $core_env && -x $core_cmp ]] || { echo 'pinned supervisor prerequisites are unavailable' >&2; exit 1; }
bash -n "$supervisor"
[[ $(tail -n 1 "$supervisor") == '}' ]] || { echo 'supervisor is not definitions-only' >&2; exit 1; }
! rg -n '^main "\$@"$|close_bash_script_reader' "$supervisor"
debug_marker='['
debug_marker+='DEBUG-'
! rg -Fq "$debug_marker" "$supervisor"
! rg -Fq 'local -n environment=$1' "$supervisor"
rg -Fq -- '-MIO::Handle' "$supervisor"
rg -Fq '$frame->sync' "$supervisor"
! rg -Fq -- '-MPOSIX=fsync' "$supervisor"

scratch=$(mktemp -d "$root/.scratch-burlmd-supervisor.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT INT TERM HUP
: >"$scratch/empty-log"
chmod 600 "$scratch/empty-log"
[[ $(/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/stat -Lc '%F:%a:%d:%i' "$scratch/empty-log") =~ ^regular(\ empty)?\ file:600:[1-9][0-9]*:[1-9][0-9]*$ ]]
perl -MFcntl=:DEFAULT -MIO::Handle -e 'sysopen(my $fh, $ARGV[0], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "$!\n"; print {$fh} "frame\n" or die "$!\n"; defined($fh->sync) or die "sync: $!\n"; close($fh) or die "$!\n";' -- "$scratch/cleanup.frame"
printf '%s\n' '00:00:00.004 [INFO] [sway/commands.c:381] Config command: swaybg_command -' '00:00:00.004 [INFO] [sway/commands.c:404] After replacement: swaybg_command -' >"$scratch/sway-config-echo.log"
{ grep -aFh swaybg "$scratch/sway-config-echo.log" || true; } | awk '/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] \[INFO\] \[sway\/commands\.c:(381|404)\] (Config command|After replacement): swaybg_command -$/ { next } { invalid = 1 } END { exit invalid }'
printf 'config: swaybg_command - but not a measured Sway verbose echo\n' >"$scratch/sway-config-near-miss.log"
if { grep -aFh swaybg "$scratch/sway-config-near-miss.log" || true; } | awk '/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] \[INFO\] \[sway\/commands\.c:(381|404)\] (Config command|After replacement): swaybg_command -$/ { next } { invalid = 1 } END { exit invalid }'; then
  echo 'swaybg near-miss echo unexpectedly accepted' >&2
  exit 1
fi
printf 'swaybg emitted unexpected output\n' >"$scratch/swaybg-output.log"
if { grep -aFh swaybg "$scratch/swaybg-output.log" || true; } | awk '/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] \[INFO\] \[sway\/commands\.c:(381|404)\] (Config command|After replacement): swaybg_command -$/ { next } { invalid = 1 } END { exit invalid }'; then
  echo 'swaybg output unexpectedly accepted' >&2
  exit 1
fi

write_fixture() {
  local path=$1 terminal=$2
  printf '%s\n' 'set -euo pipefail' \
    'readonly source_complete=true trusted_fixture_path=${BASH_SOURCE[0]}' \
    'main() {' \
    '  [[ ${source_complete:-false} == true && ${BASH_SOURCE[0]} == "$trusted_fixture_path" ]] || exit 81' \
    '  owner_pid=$BASHPID' \
    '  for fd in /proc/$owner_pid/fd/[0-9]*; do number=${fd##*/}; [[ -e /proc/$owner_pid/fd/$number ]] || continue; (( number <= 2 )) || exit 82; done' \
    '  before=$(stat -Lc "%F:%d:%i:%a" "/proc/$owner_pid/fd/1"); target_before=$(readlink "/proc/$owner_pid/fd/1"); flags_before=$(awk "/^flags:/ { print \$2; exit }" "/proc/$owner_pid/fdinfo/1")' \
    '  exec 255<&-' \
    '  [[ ! -e /proc/$owner_pid/fd/255 ]] || exit 83' \
    '  after=$(stat -Lc "%F:%d:%i:%a" "/proc/$owner_pid/fd/1"); target_after=$(readlink "/proc/$owner_pid/fd/1"); flags_after=$(awk "/^flags:/ { print \$2; exit }" "/proc/$owner_pid/fdinfo/1")' \
    '  [[ $before == "$after" && $target_before == "$target_after" && $flags_before == "$flags_after" ]] || exit 84' \
    "  $terminal" \
    '}' >"$path"
  chmod 600 "$path"
}

launch_source_fixture() {
  local fixture=$1 stdout_path=$2 stderr_path=$3 extra_fd=${4:-false}
  shift 4 || true
  (
    local entry number
    for entry in /proc/self/fd/[0-9]*; do
      number=${entry##*/}
      (( number <= 2 )) || eval "exec ${number}>&-"
    done
    [[ $extra_fd != true ]] || exec 9</dev/null
    exec "$pinned_bash" -c "$source_command" _ "$fixture" "$@"
  ) >"$stdout_path" 2>"$stderr_path"
}

write_fixture "$scratch/direct" 'printf direct-exit; exit 0'
launch_source_fixture "$scratch/direct" "$scratch/direct.stdout" "$scratch/direct.stderr" false
[[ $(<"$scratch/direct.stdout") == direct-exit && ! -s $scratch/direct.stderr ]]

write_fixture "$scratch/final" "exec '$core_env' -i /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/printf final-exec"
launch_source_fixture "$scratch/final" "$scratch/final.stdout" "$scratch/final.stderr" false
[[ $(<"$scratch/final.stdout") == final-exec && ! -s $scratch/final.stderr ]]

if launch_source_fixture "$scratch/direct" /dev/null /dev/null true; then
  echo 'source launcher accepted an extra inherited descriptor' >&2
  exit 1
fi

# A caller commonly names its output array `environment`; the helper nameref
# must use a distinct local name or Bash makes a circular reference.
"$pinned_bash" -c 'set -euo pipefail; build() { local -n destination=$1; destination=(exact); }; declare -a environment=(); build environment; [[ ${environment[0]} == exact ]]'

# Direct-file Bash launch parses definitions but cannot invoke main. The parent
# owns rejecting this changed argv shape; this proves the file has no fallback.
"$pinned_bash" "$scratch/direct" >"$scratch/direct-file.stdout" 2>"$scratch/direct-file.stderr"
[[ ! -s $scratch/direct-file.stdout && ! -s $scratch/direct-file.stderr ]]

# Source parse/read/runtime failures are fail-closed before main can run.
printf '%s\n' 'set -euo pipefail' 'main() { printf invoked >"'$scratch'/runtime-invoked"; exit 0; }' 'false' >"$scratch/source-runtime-error"
if launch_source_fixture "$scratch/source-runtime-error" /dev/null /dev/null false; then
  echo 'source runtime failure invoked main' >&2
  exit 1
fi
[[ ! -e $scratch/runtime-invoked ]]
printf '%s\n' 'set -euo pipefail' 'main() {' >"$scratch/source-parse-error"
if launch_source_fixture "$scratch/source-parse-error" /dev/null /dev/null false; then
  echo 'source parse failure invoked main' >&2
  exit 1
fi

# Omitting shift forwards the source path to main and must fail its raw-38
# argument parser. Direct-file vector rejection remains parent-controller work.
if "$pinned_bash" -c 'source "$1"; main "$@"' _ "$supervisor" --session-id x --class base --preflight-fd 3 --ack-fd 4 --timeout-seconds 7200 -- /bin/true >/dev/null 2>&1; then
  echo 'changed source launcher unexpectedly accepted' >&2
  exit 1
fi

# Execute the production negative-path helper in a real empty Bubblewrap view.
# This guards the required success branch where bwrap is absent: it must return
# zero rather than leak `command -v`'s status through `set -e`.
fixture_bwrap=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap
fixture_nix_store=$(command -v nix-store)
[[ -x $fixture_bwrap && -x $fixture_nix_store ]] || { echo 'forbidden-path regression fixture prerequisites are unavailable' >&2; exit 1; }
mapfile -t fixture_bash_closure < <("$fixture_nix_store" -qR "${pinned_bash%/bin/bash}" | LC_ALL=C sort -u)
(( ${#fixture_bash_closure[@]} > 0 )) || { echo 'cannot resolve pinned Bash closure' >&2; exit 1; }
mkdir "$scratch/forbidden-path-bin"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$scratch/forbidden-path-bin/bwrap"
chmod 755 "$scratch/forbidden-path-bin/bwrap"

forbidden_bwrap_args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --die-with-parent --new-session --clearenv --proc /proc --dev /dev --dir /nix --dir /nix/store --dir /trusted --dir /candidate --ro-bind "$root/scripts" /trusted/scripts)
for closure_member in "${fixture_bash_closure[@]}"; do forbidden_bwrap_args+=(--ro-bind "$closure_member" "$closure_member"); done
"$fixture_bwrap" "${forbidden_bwrap_args[@]}" -- "$pinned_bash" -c 'source "$1"; require_forbidden_paths_absent; printf absent-ok' _ /trusted/scripts/supervise-linux-session.sh >"$scratch/forbidden-absent.stdout"
[[ $(<"$scratch/forbidden-absent.stdout") == absent-ok ]]
if "$fixture_bwrap" "${forbidden_bwrap_args[@]}" --bind "$scratch/forbidden-path-bin" /candidate --setenv PATH=/candidate -- "$pinned_bash" -c 'source "$1"; require_forbidden_paths_absent' _ /trusted/scripts/supervise-linux-session.sh >/dev/null 2>&1; then
  echo 'forbidden-path helper accepted a visible bwrap command' >&2
  exit 1
fi

# Exercise the real final Coreutils env boundary, rather than merely scanning
# the supervisor source. The target-qualified key must be the sole OpenSSL
# linker assignment and env -i must pass exactly the declared base vector.
candidate_environment_fixture=(
  'PATH=/candidate/tool-path' 'HOME=/candidate/home' 'TMPDIR=/candidate/tmp'
  'XDG_CACHE_HOME=/candidate/xdg/cache' 'XDG_CONFIG_HOME=/candidate/xdg/config'
  'XDG_DATA_HOME=/candidate/xdg/data' 'XDG_STATE_HOME=/candidate/xdg/state'
  'GH_CONFIG_DIR=/candidate/gh' 'PUB_CACHE=/candidate/prepared/pub-cache'
  'CARGO_HOME=/candidate/prepared/cargo-home' 'CARGO_TARGET_DIR=/candidate/writable/cargo-target'
  'RUSTUP_HOME=/candidate/home/rustup' 'GIT_CONFIG_NOSYSTEM=1' 'GIT_CONFIG_GLOBAL=/dev/null'
  'GIT_CONFIG_COUNT=0' 'GIT_TERMINAL_PROMPT=0' 'LC_ALL=C.UTF-8' 'LANG=C.UTF-8'
  'BURLMD_CANDIDATE_LOOPBACK=1' 'NIX_REMOTE=local' 'NIX_PATH=' 'NIX_CONFIG=sandbox = false'
  'BURLMD_CANDIDATE_SESSION=fixture-base' 'BURLMD_CANDIDATE_PID_FILE=/candidate/session/pid'
  'BURLMD_LOCKED_NIX_CLOSURE=/nix/store/fixture-a:/nix/store/fixture-b'
  'PKG_CONFIG_PATH=/nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/lib/pkgconfig'
  'LIBCLANG_PATH=/nix/store/7306wrcri9nmdp7w4pbqc5rqdn6y048d-clang-21.1.8-lib/lib'
  'NIX_CFLAGS_COMPILE=-isystem /nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/include'
  'NIX_LDFLAGS_x86_64_unknown_linux_gnu=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib'
  'CFLAGS=-isystem /nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/include'
  'LDFLAGS=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib'
  'LIBGL_DRIVERS_PATH=/nix/store/g30agk6fz47x0kyfpvapm8ddhp8fvn4y-mesa-26.1.4/lib/dri'
  '__EGL_VENDOR_LIBRARY_FILENAMES=/nix/store/g30agk6fz47x0kyfpvapm8ddhp8fvn4y-mesa-26.1.4/share/glvnd/egl_vendor.d/50_mesa.json'
)
"$core_env" -i "${candidate_environment_fixture[@]}" "$pinned_bash" -ceu '
  source "$1"
  session_id=fixture-base
  session_class=base
  candidate_environment actual
  [[ ${#actual[@]} == 33 ]]
  [[ ${actual[28]} == NIX_LDFLAGS_x86_64_unknown_linux_gnu=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib ]]
  for entry in "${actual[@]}"; do [[ ${entry%%=*} != NIX_LDFLAGS ]]; done
  printf "%s\0" "${actual[@]}" >"$2"
  "$coreutils_env" -i -- "${actual[@]}" "$coreutils_env" -0 >"$3"
' _ "$supervisor" "$scratch/candidate-environment.expected" "$scratch/candidate-environment.actual"
"$core_cmp" -s "$scratch/candidate-environment.expected" "$scratch/candidate-environment.actual"

# A generic key is an inherited extra at the direct-entry boundary and must
# fail even when the required target-specific assignment is also present.
if "$core_env" -i "${candidate_environment_fixture[@]}" 'NIX_LDFLAGS=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib' "$pinned_bash" -ceu '
  source "$1"
  session_id=fixture-base
  session_class=base
  candidate_environment actual
' _ "$supervisor" 2>"$scratch/generic-key-rejection.stderr"; then
  echo 'supervisor accepted generic NIX_LDFLAGS at the candidate boundary' >&2
  exit 1
fi
rg -Fqx 'unexpected inherited environment key NIX_LDFLAGS' "$scratch/generic-key-rejection.stderr"

printf 'source-to-EOF supervisor fixture passed\n'
