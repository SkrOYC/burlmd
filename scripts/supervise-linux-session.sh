#!/usr/bin/env bash
# The only in-namespace supervisor used by BURL-M003. Its argv is part of the
# raw-39 Bubblewrap vector; this process never interprets candidate shell text.
set -euo pipefail

readonly supervisor_timeout_seconds=7200
readonly coreutils_env=/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env
readonly coreutils_bin=/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin
readonly ip_command=/nix/store/qbsvh4fw7lrmkqk870w4sc21kqylph42-iproute2-7.0.0/bin/ip
readonly ps_command=/nix/store/ly5j6qg2q3vn899jd9dz0hx11gvjh9f1-procps-4.0.6/bin/ps
readonly sway_command=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway
readonly swaymsg_command=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg
readonly bubblewrap_command=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap
readonly runtime_dir=/candidate/xdg/runtime
readonly session_dir=/candidate/session
readonly contract_sources=/contract/locked-nix-closure.sources

session_id= session_class= preflight_fd= ack_fd= timeout_seconds=
candidate_pid= sway_pid= recorded_sway_pid= candidate_status=125 sway_status=125 wait_status=
session_identity=
supervisor_pid=
declare -a standard_descriptor_identity=()
declare -A selected_store_members=() mount_count=() mount_device=() mount_root=() mount_options=()
declare -a supervisor_log_identity=() supervisor_log_target=()
supervisor_result=pending termination_path=none interrupted=false

fail() { printf '%s\n' "$*" >&2; exit 2; }

assert_descriptor_set() {
  local expected=$1 entry number seen= owner_pid=$BASHPID
  for entry in /proc/$owner_pid/fd/[0-9]*; do
    number=${entry##*/}; [[ $number =~ ^[0-9]+$ ]] || continue
    # Expanding procfs can allocate a temporary directory descriptor. Recheck
    # the owning Bash process before treating an expanded number as open.
    [[ -e /proc/$owner_pid/fd/$number ]] || continue
    case " $expected " in *" $number "*) seen+=" $number" ;; *) fail "unexpected descriptor $number" ;; esac
  done
  for number in $expected; do [[ $seen == *" $number"* ]] || fail "missing descriptor $number"; done
}

read_descriptor_identity() {
  # Commands run in substitutions receive capture pipes.  Address the owning
  # Bash process explicitly so the identity is for the inherited descriptor,
  # never for a helper's stdout pipe.
  local fd=$1 identity stat_line target flags
  [[ $supervisor_pid =~ ^[1-9][0-9]*$ && -e /proc/$supervisor_pid/fd/$fd ]] || fail "missing descriptor $fd"
  identity=$(perl -MFcntl=:mode -e '
    my ($pid, $fd) = @ARGV; my $path = "/proc/$pid/fd/$fd";
    my @s = stat($path) or die "stat: $!\n";
    my $type = S_ISREG($s[2]) ? q{regular file} : S_ISDIR($s[2]) ? q{directory} : S_ISFIFO($s[2]) ? q{fifo} : S_ISSOCK($s[2]) ? q{socket} : q{other};
    my $target = readlink($path); defined($target) or die "readlink: $!\n";
    open(my $info, q{<}, "/proc/$pid/fdinfo/$fd") or die "fdinfo: $!\n";
    my $flags = q{}; while (my $line = <$info>) { if ($line =~ /^flags:\s*(0[0-7]+)\s*$/) { $flags = $1; last } }
    $flags ne q{} or die "flags missing\n";
    print join("\t", join(q{:}, $type, $s[0], $s[1], sprintf(q{%o}, $s[2] & 07777)), $target, $flags), "\n";
  ' -- "$supervisor_pid" "$fd") || fail "cannot inspect descriptor $fd"
  IFS=$'\t' read -r stat_line target flags <<<"$identity"
  [[ $stat_line =~ ^[^:]+:[1-9][0-9]*:[1-9][0-9]*:[0-7]+$ && $flags =~ ^0[0-7]+$ ]] || fail "malformed descriptor identity $fd"
  REPLY="$stat_line|$target|$flags"
  return 0
}

record_standard_descriptors() {
  local fd
  for fd in 0 1 2; do
    read_descriptor_identity "$fd"
    standard_descriptor_identity[$fd]=$REPLY
  done
}

verify_standard_descriptors() {
  local fd
  for fd in 0 1 2; do
    read_descriptor_identity "$fd"
    [[ $REPLY == "${standard_descriptor_identity[$fd]}" ]] || fail "standard descriptor $fd changed"
  done
}

close_descriptors_above_stderr() {
  local entry number owner_pid=$BASHPID
  for entry in /proc/$owner_pid/fd/[0-9]*; do
    number=${entry##*/}; [[ $number =~ ^[0-9]+$ ]] || continue
    [[ -e /proc/$owner_pid/fd/$number ]] || continue
    (( number <= 2 )) && continue
    eval "exec ${number}>&-" || fail "cannot close descriptor $number"
  done
  assert_descriptor_set '0 1 2'
}

require_regular_file() { [[ -f $1 && ! -L $1 ]] || fail "required regular file is unsafe: $1"; }

selected_manifest_sha256() {
  [[ ${BURLMD_LOCKED_NIX_CLOSURE:-} == /nix/store/* ]] || fail 'missing locked Nix closure'
  printf '%s\n' "$BURLMD_LOCKED_NIX_CLOSURE" | "$coreutils_bin/tr" ':' '\n' | "$coreutils_bin/sha256sum" | awk '{print $1}'
}

decode_mountinfo_field() {
  local encoded=$1
  # mountinfo escapes only whitespace, backslash, and other bytes as \ooo.
  [[ $encoded =~ ^([^\\]|\\[0-7]{3})*$ ]] || fail 'malformed mountinfo escape'
  printf -v REPLY '%b' "$encoded"
}

is_canonical_store_member() {
  local path=$1 canonical
  [[ $path =~ ^/nix/store/[a-z0-9]{32}-[^/:[:space:]]+$ && ! -L $path ]] || return 1
  canonical=$("$coreutils_bin/readlink" -f -- "$path") || return 1
  [[ $canonical == "$path" ]]
}

mount_options_are_read_only() {
  local options=$1
  [[ ,$options, == *,ro,* && ,$options, != *,rw,* ]]
}

build_mountinfo_table() {
  local line index separator device root mountpoint options count
  mount_count=(); mount_device=(); mount_root=(); mount_options=()
  while IFS= read -r line; do
    local -a fields=()
    IFS=' ' read -r -a fields <<<"$line"
    (( ${#fields[@]} >= 7 )) || fail 'malformed mountinfo row'
    separator=-1
    for ((index = 6; index < ${#fields[@]}; index++)); do [[ ${fields[$index]} == - ]] && { separator=$index; break; }; done
    (( separator >= 6 && separator + 3 < ${#fields[@]} )) || fail 'malformed mountinfo separator'
    device=${fields[2]}; root=${fields[3]}; mountpoint=${fields[4]}; options=${fields[5]}
    decode_mountinfo_field "$root"; root=$REPLY
    decode_mountinfo_field "$mountpoint"; mountpoint=$REPLY
    count=${mount_count[$mountpoint]:-0}
    mount_count[$mountpoint]=$((count + 1))
    mount_device[$mountpoint]=$device
    mount_root[$mountpoint]=$root
    mount_options[$mountpoint]=$options
    if [[ $mountpoint == /nix/store/* ]]; then
      [[ -n ${selected_store_members[$mountpoint]+x} ]] || fail "unlisted store mount: $mountpoint"
    fi
  done </proc/self/mountinfo
  return 0
}

require_exact_mount() {
  local expected_path=$1 expected_device=$2 expected_root=$3
  [[ ${mount_count[$expected_path]:-0} == 1 ]] || fail "store mount count mismatch: $expected_path"
  [[ ${mount_device[$expected_path]} == "$expected_device" && ${mount_root[$expected_path]} == "$expected_root" ]] || fail "store mount identity mismatch: $expected_path"
  mount_options_are_read_only "${mount_options[$expected_path]}" || fail "store mount is writable: $expected_path"
  return 0
}

require_contract_mount() {
  local entry
  [[ -d /contract && ! -L /contract && -f $contract_sources && ! -L $contract_sources ]] || fail 'contract source snapshot is unsafe'
  [[ $("$coreutils_bin/stat" -Lc '%a' -- "$contract_sources") == 444 ]] || fail 'contract source snapshot mode drift'
  for entry in /contract/*; do [[ $entry == "$contract_sources" ]] || fail 'contract mount has an extra entry'; done
  [[ ${mount_count[/contract]:-0} == 1 ]] || fail 'contract mount count mismatch'
  mount_options_are_read_only "${mount_options[/contract]}" || fail 'contract mount is writable'
  return 0
}

require_private_namespaces() {
  local pid_one_executable interfaces routes
  [[ $$ != 1 && -r /proc/1/comm && -r /proc/1/exe ]] || fail 'PID namespace is not private'
  pid_one_executable=$("$coreutils_bin/readlink" /proc/1/exe) || fail 'cannot inspect namespace reaper'
  [[ $pid_one_executable == "$bubblewrap_command" && ! -e $bubblewrap_command && ! -L $bubblewrap_command ]] || fail 'unexpected namespace reaper or visible Bubblewrap'
  interfaces=$("$coreutils_env" -i -- "$ip_command" -o link show) || fail 'cannot inspect network namespace'
  [[ $interfaces == 1:\ lo:* && $interfaces != *$'\n'* ]] || fail 'network namespace exposes a non-loopback interface'
  routes=$("$coreutils_env" -i -- "$ip_command" route show) || fail 'cannot inspect network routes'
  [[ -z $routes ]] || fail 'network namespace exposes a route'
  return 0
}

require_forbidden_paths_absent() {
  local path
  for path in /nix/var /nix/var/nix/db /nix/var/nix/daemon-socket /run/current-system "$bubblewrap_command"; do
    [[ ! -e $path && ! -L $path ]] || fail "forbidden path is visible: $path"
  done
  if command -v bwrap >/dev/null 2>&1; then fail 'Bubblewrap is visible in candidate PATH'; fi
  return 0
}

validate_source_identity_snapshot() {
  local row previous_path= path type host_dev host_inode host_device host_root namespace_dev namespace_inode namespace_device namespace_root access
  local actual file_type source_count=0
  selected_store_members=()
  local -a selected_members=()
  IFS=: read -r -a selected_members <<<"${BURLMD_LOCKED_NIX_CLOSURE:?missing locked Nix closure}"
  (( ${#selected_members[@]} > 0 )) || fail 'empty locked Nix closure'
  for path in "${selected_members[@]}"; do
    is_canonical_store_member "$path" || fail "invalid locked Nix closure member: $path"
    [[ -z ${selected_store_members[$path]+x} ]] || fail "duplicate locked Nix closure member: $path"
    selected_store_members[$path]=1
  done
  build_mountinfo_table
  require_contract_mount
  while IFS= read -r row || [[ -n $row ]]; do
    local -a fields=()
    IFS=$'\t' read -r -a fields <<<"$row"
    (( ${#fields[@]} == 11 )) || fail 'malformed source identity row'
    path=${fields[0]}; type=${fields[1]}; host_dev=${fields[2]}; host_inode=${fields[3]}; host_device=${fields[4]}; host_root=${fields[5]}
    namespace_dev=${fields[6]}; namespace_inode=${fields[7]}; namespace_device=${fields[8]}; namespace_root=${fields[9]}; access=${fields[10]}
    [[ -n ${selected_store_members[$path]+x} && $type =~ ^(directory|regular-file)$ && $host_dev =~ ^[1-9][0-9]*$ && $host_inode =~ ^[1-9][0-9]*$ && $namespace_dev =~ ^[1-9][0-9]*$ && $namespace_inode =~ ^[1-9][0-9]*$ && $host_device =~ ^[0-9]+:[0-9]+$ && $namespace_device =~ ^[0-9]+:[0-9]+$ && $host_root == /* && $namespace_root == "$path" && $access == ro ]] || fail 'invalid source identity row'
    [[ -z $previous_path || $previous_path < $path ]] || fail 'source identity rows are not path-sorted'
    previous_path=$path
    actual=$("$coreutils_bin/stat" -Lc '%F:%d:%i' -- "$path") || fail "cannot fstat source member: $path"
    file_type=${actual%%:*}; actual=${actual#*:}
    case $file_type in 'regular file'|'regular empty file') file_type=regular-file;; esac
    [[ $file_type == "$type" && ${actual%%:*} == "$namespace_dev" && ${actual#*:} == "$namespace_inode" && $host_dev == "$namespace_dev" && $host_inode == "$namespace_inode" && $host_device == "$namespace_device" ]] || fail "source identity mismatch: $path"
    require_exact_mount "$path" "$namespace_device" "$namespace_root"
    ((++source_count))
  done <"$contract_sources"
  (( source_count == ${#selected_members[@]} )) || fail 'source identity count does not match locked closure'
  return 0
}

validate_compositor_surface() {
  local entry key
  if [[ $session_class == base ]]; then
    [[ ! -e $runtime_dir && ! -L $runtime_dir ]] || fail 'base session exposes compositor runtime'
    while IFS= read -r -d '' entry; do
      key=${entry%%=*}
      case $key in WAYLAND_DISPLAY|SWAYSOCK|DISPLAY|XDG_RUNTIME_DIR|WLR_*) fail "base session exposes compositor environment: $key";; esac
    done < <("$coreutils_env" -0)
  else
    [[ -d $runtime_dir && ! -L $runtime_dir && -z $(/candidate/tool-path/find -P "$runtime_dir" -mindepth 1 -maxdepth 1 -print -quit) ]] || fail 'integration runtime leaf is unsafe'
    [[ $("$coreutils_bin/stat" -Lc '%a:%u:%g' -- "$runtime_dir") == '700:0:0' ]] || fail 'integration runtime identity drift'
  fi
  return 0
}

validate_preflight_runtime() {
  validate_source_identity_snapshot
  require_private_namespaces
  require_forbidden_paths_absent
  validate_compositor_surface
}

write_preflight() {
  local manifest_sha source_count compositor_state body body_bytes
  require_regular_file "$contract_sources"
  [[ ! -w $contract_sources ]] || fail 'contract source snapshot is writable'
  validate_preflight_runtime
  manifest_sha=$(selected_manifest_sha256)
  source_count=$("$coreutils_bin/wc" -l <"$contract_sources" | "$coreutils_bin/tr" -d ' ')
  [[ $source_count =~ ^[1-9][0-9]*$ ]] || fail 'empty source identity snapshot'
  [[ $session_class == base ]] && compositor_state=absent || compositor_state=pending-supervisor-start
  body=$(
    printf '%s\n' 'format=burlmd-linux-closure-preflight-v2' "session-class=$session_class" "selected-manifest-sha256=$manifest_sha" "source-identity-count=$source_count"
    "$coreutils_bin/cat" "$contract_sources"
    printf '%s\n' 'pid-namespace-private=true' 'network-namespace-private=true' \
      'descriptor=0:candidate-stdin' 'descriptor=1:candidate-stdout' 'descriptor=2:candidate-stderr' \
      'descriptor=3:preflight-record-write' 'descriptor=4:preflight-ack-read' \
      'store-view-exact=true' 'forbidden-paths-absent=true' "compositor-state=$compositor_state"
  )
  # Command substitution strips final newlines, so restore the contract's LF.
  body+=$'\n'
  body_bytes=$(LC_ALL=C printf '%s' "$body" | "$coreutils_bin/wc" -c | "$coreutils_bin/tr" -d ' ') || fail 'cannot measure preflight bytes'
  [[ $body_bytes =~ ^[1-9][0-9]*$ ]] || fail 'invalid preflight byte count'
  printf 'preflight-bytes=%s\n%s' "$body_bytes" "$body" >&"$preflight_fd" || fail 'cannot write preflight'
  eval "exec ${preflight_fd}>&-" || fail 'cannot close preflight descriptor'
}

accept_preflight_acknowledgement() {
  local acknowledgement extra= acknowledgement_status
  IFS= read -r -N 1 acknowledgement <&"$ack_fd" || fail 'missing preflight acknowledgement'
  [[ $acknowledgement == G ]] || fail 'invalid preflight acknowledgement'
  set +e
  IFS= read -r -N 1 extra <&"$ack_fd"
  acknowledgement_status=$?
  set -e
  [[ $acknowledgement_status != 0 && -z $extra ]] || fail 'acknowledgement has trailing bytes'
  eval "exec ${ack_fd}<&-" || fail 'cannot close acknowledgement descriptor'
}

run_loopback() {
  local line
  "$coreutils_env" -i -- "$ip_command" link set dev lo up || fail 'cannot raise loopback'
  line=$("$coreutils_env" -i -- "$ip_command" -o link show up dev lo) || fail 'cannot inspect loopback'
  [[ $line == *'<LOOPBACK,UP,'* ]] || fail 'loopback is not UP'
}

candidate_environment() {
  local -n destination=$1; local key entry
  local -a keys=(
    PATH HOME TMPDIR XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME GH_CONFIG_DIR PUB_CACHE CARGO_HOME CARGO_TARGET_DIR RUSTUP_HOME
    GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT GIT_TERMINAL_PROMPT LC_ALL LANG BURLMD_CANDIDATE_LOOPBACK NIX_REMOTE NIX_PATH NIX_CONFIG
    BURLMD_CANDIDATE_SESSION BURLMD_CANDIDATE_PID_FILE BURLMD_LOCKED_NIX_CLOSURE PKG_CONFIG_PATH LIBCLANG_PATH NIX_CFLAGS_COMPILE NIX_LDFLAGS_x86_64_unknown_linux_gnu CFLAGS LDFLAGS LIBGL_DRIVERS_PATH __EGL_VENDOR_LIBRARY_FILENAMES
  )
  destination=()
  for key in "${keys[@]}"; do
    [[ ${!key+x} ]] || fail "candidate environment is missing $key"
    [[ ${!key} != *'SESSION_ID'* && ${!key} != *'LOCKED_'* ]] || fail "candidate environment has unresolved $key"
    destination+=("$key=${!key}")
  done
  local -a fixed=(
    'PATH=/candidate/tool-path' 'HOME=/candidate/home' 'TMPDIR=/candidate/tmp' 'XDG_CACHE_HOME=/candidate/xdg/cache' 'XDG_CONFIG_HOME=/candidate/xdg/config' 'XDG_DATA_HOME=/candidate/xdg/data' 'XDG_STATE_HOME=/candidate/xdg/state' 'GH_CONFIG_DIR=/candidate/gh' 'PUB_CACHE=/candidate/prepared/pub-cache' 'CARGO_HOME=/candidate/prepared/cargo-home' 'CARGO_TARGET_DIR=/candidate/writable/cargo-target' 'RUSTUP_HOME=/candidate/home/rustup' 'GIT_CONFIG_NOSYSTEM=1' 'GIT_CONFIG_GLOBAL=/dev/null' 'GIT_CONFIG_COUNT=0' 'GIT_TERMINAL_PROMPT=0' 'LC_ALL=C.UTF-8' 'LANG=C.UTF-8' 'BURLMD_CANDIDATE_LOOPBACK=1' 'NIX_REMOTE=local' 'NIX_PATH=' 'NIX_CONFIG=sandbox = false'
  )
  for ((key = 0; key < ${#fixed[@]}; key++)); do [[ ${destination[$key]} == "${fixed[$key]}" ]] || fail "fixed candidate environment drift at $key"; done
  [[ ${destination[22]} == "BURLMD_CANDIDATE_SESSION=$session_id" &&
    ${destination[23]} == 'BURLMD_CANDIDATE_PID_FILE=/candidate/session/pid' &&
    ${destination[24]} == "BURLMD_LOCKED_NIX_CLOSURE=$BURLMD_LOCKED_NIX_CLOSURE" &&
    ${destination[25]} == 'PKG_CONFIG_PATH=/nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/lib/pkgconfig' &&
    ${destination[26]} == 'LIBCLANG_PATH=/nix/store/7306wrcri9nmdp7w4pbqc5rqdn6y048d-clang-21.1.8-lib/lib' &&
    ${destination[27]} == 'NIX_CFLAGS_COMPILE=-isystem /nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/include' &&
    ${destination[28]} == 'NIX_LDFLAGS_x86_64_unknown_linux_gnu=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib' &&
    ${destination[29]} == 'CFLAGS=-isystem /nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev/include' &&
    ${destination[30]} == 'LDFLAGS=-L/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib' &&
    ${destination[31]} == 'LIBGL_DRIVERS_PATH=/nix/store/g30agk6fz47x0kyfpvapm8ddhp8fvn4y-mesa-26.1.4/lib/dri' &&
    ${destination[32]} == '__EGL_VENDOR_LIBRARY_FILENAMES=/nix/store/g30agk6fz47x0kyfpvapm8ddhp8fvn4y-mesa-26.1.4/share/glvnd/egl_vendor.d/50_mesa.json' ]] || fail 'candidate environment derivation drift'
  while IFS= read -r -d '' entry; do
    key=${entry%%=*}
    case " $key " in
      ' PWD '|' SHLVL '|' _ ') ;;
      *) [[ " ${keys[*]} " == *" $key "* ]] || fail "unexpected inherited environment key $key" ;;
    esac
  done < <("$coreutils_env" -0)
  if [[ $session_class == integration ]]; then destination+=('XDG_RUNTIME_DIR=/candidate/xdg/runtime' 'WAYLAND_DISPLAY=wayland-1' 'GDK_BACKEND=wayland' 'LIBGL_ALWAYS_SOFTWARE=1'); fi
  [[ ${#destination[@]} == $([[ $session_class == integration ]] && printf 37 || printf 33) ]] || fail 'candidate environment entry count drift'
}

create_log_file() {
  local path=$1
  [[ ! -e $path && ! -L $path ]] || fail "precreated supervisor log: $path"
  perl -MFcntl=:DEFAULT -MIO::Handle -e '
    my ($path) = @ARGV; sysopen(my $fh, $path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "$!\n";
    defined($fh->sync) or die "sync: $!\n";
  ' -- "$path" || fail "cannot create supervisor log: $path"
  [[ $("$coreutils_bin/stat" -Lc '%F:%a:%d:%i' -- "$path") =~ ^regular(\ empty)?\ file:600:[1-9][0-9]*:[1-9][0-9]*$ ]] || fail "unsafe supervisor log: $path"
}

record_supervisor_log_descriptor() {
  local fd=$1 expected_path=$2 rest flags_decimal
  read_descriptor_identity "$fd"
  supervisor_log_identity[$fd]=${REPLY%%|*}
  rest=${REPLY#*|}; supervisor_log_target[$fd]=${rest%|*}
  [[ ${supervisor_log_identity[$fd]} == regular\ file:* && ${supervisor_log_target[$fd]} == "$expected_path" ]] || fail "supervisor log descriptor drift: $fd"
  flags_decimal=$((8#${rest##*|}))
  (( (flags_decimal & 3) == 1 && (flags_decimal & 02000) != 0 )) || fail "supervisor log descriptor access drift: $fd"
}

verify_supervisor_log_descriptors() {
  local fd rest flags_decimal
  for fd in 3 4 5 6; do
    read_descriptor_identity "$fd"
    rest=${REPLY#*|}
    [[ ${REPLY%%|*} == "${supervisor_log_identity[$fd]}" && ${rest%|*} == "${supervisor_log_target[$fd]}" ]] || fail "supervisor log descriptor changed: $fd"
    flags_decimal=$((8#${rest##*|}))
    (( (flags_decimal & 3) == 1 && (flags_decimal & 02000) != 0 )) || fail "supervisor log descriptor access changed: $fd"
  done
}

prepare_supervisor_logs() {
  create_log_file "$session_dir/sway.stdout"; create_log_file "$session_dir/sway.stderr"
  create_log_file "$session_dir/readiness.stdout"; create_log_file "$session_dir/readiness.stderr"
  exec 3>>"$session_dir/sway.stdout"; exec 4>>"$session_dir/sway.stderr"
  exec 5>>"$session_dir/readiness.stdout"; exec 6>>"$session_dir/readiness.stderr"
  assert_descriptor_set '0 1 2 3 4 5 6'
  record_supervisor_log_descriptor 3 "$session_dir/sway.stdout"
  record_supervisor_log_descriptor 4 "$session_dir/sway.stderr"
  record_supervisor_log_descriptor 5 "$session_dir/readiness.stdout"
  record_supervisor_log_descriptor 6 "$session_dir/readiness.stderr"
}

start_sway() {
  (
    exec 1>&3 2>&4; exec 3>&- 4>&- 5>&- 6>&-
    exec "$coreutils_env" -i PATH=/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin HOME=/candidate/home XDG_CONFIG_HOME=/candidate/xdg/config XDG_RUNTIME_DIR=/candidate/xdg/runtime LC_ALL=C.UTF-8 LANG=C.UTF-8 WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 SWAYSOCK=/candidate/xdg/runtime/sway-ipc.sock "$sway_command" --verbose --config /trusted/scripts/managed-sway.conf
  ) & sway_pid=$!; recorded_sway_pid=$sway_pid
}

runtime_is_exact() {
  local entry name
  [[ -S $runtime_dir/wayland-1 && -S $runtime_dir/sway-ipc.sock && -e $runtime_dir/wayland-1.lock ]] || return 1
  for entry in "$runtime_dir"/*; do name=${entry##*/}; case $name in wayland-1|wayland-1.lock|sway-ipc.sock) ;; *) return 1 ;; esac; done
  return 0
}

no_swaybg_activity() {
  if "$ps_command" -eo comm= | awk '$1 == "swaybg" { found = 1 } END { exit found ? 0 : 1 }'; then return 1; fi
  # Sway 1.12 verbose mode emits these two measured parser echoes for the
  # required `swaybg_command -` directive. They do not start a helper. Keep
  # the exception byte-shape-specific: any other swaybg byte still rejects.
  if { grep -aFh swaybg "$session_dir/sway.stdout" "$session_dir/sway.stderr" "$session_dir/readiness.stdout" "$session_dir/readiness.stderr" || true; } | awk '
    /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] \[INFO\] \[sway\/commands\.c:(381|404)\] (Config command|After replacement): swaybg_command -$/ { next }
    { invalid = 1 }
    END { exit invalid }
  '; then :; else return 1; fi
  return 0
}

await_sway_readiness() {
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    runtime_is_exact || { kill -0 "$sway_pid" 2>/dev/null || return 1; sleep 0.1; continue; }
    if (exec 1>&5 2>&6; exec 3>&- 4>&- 5>&- 6>&-; exec "$coreutils_env" -i XDG_RUNTIME_DIR=/candidate/xdg/runtime LC_ALL=C.UTF-8 LANG=C.UTF-8 "$swaymsg_command" --socket /candidate/xdg/runtime/sway-ipc.sock --type get_version --raw); then return 0; fi
    sleep 0.1
  done
  return 1
}

start_candidate() {
  local -a environment=(); candidate_environment environment
  (
    close_descriptors_above_stderr
    exec perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- "$coreutils_env" -i -- "${environment[@]}" "$@"
  ) & candidate_pid=$!
}

wait_direct_child() {
  local pid=$1 limit=$2 attempt process_stat state
  for ((attempt = 0; attempt < limit; attempt++)); do
    if [[ ! -r /proc/$pid/stat ]]; then
      set +e; wait "$pid"; wait_status=$?; set -e
      return 0
    fi
    IFS= read -r process_stat <"/proc/$pid/stat" || fail "cannot inspect direct child: $pid"
    process_stat=${process_stat##*) }; state=${process_stat%% *}
    if [[ $state == Z || $state == X ]]; then
      set +e; wait "$pid"; wait_status=$?; set -e
      return 0
    fi
    sleep 0.1
  done
  return 1
}

direct_child_is_running() {
  local pid=$1 process_stat state
  [[ -r /proc/$pid/stat ]] || return 1
  IFS= read -r process_stat <"/proc/$pid/stat" || return 1
  process_stat=${process_stat##*) }; state=${process_stat%% *}
  [[ $state != Z && $state != X ]]
}

reap_integration_children() {
  local status
  if [[ -n $candidate_pid ]]; then
    kill -TERM -- "-$candidate_pid" 2>/dev/null || true
    if wait_direct_child "$candidate_pid" 50; then candidate_status=$wait_status; else kill -KILL -- "-$candidate_pid" 2>/dev/null || true; wait_direct_child "$candidate_pid" 50 || fail 'candidate direct child did not exit'; candidate_status=$wait_status; termination_path=candidate-sigkill; fi
    candidate_pid=
  fi
  if [[ -n $sway_pid ]]; then
    kill -TERM "$sway_pid" 2>/dev/null || true
    if wait_direct_child "$sway_pid" 50; then sway_status=$wait_status; else kill -KILL "$sway_pid" 2>/dev/null || true; wait_direct_child "$sway_pid" 50 || fail 'Sway direct child did not exit'; sway_status=$wait_status; termination_path=sway-sigkill; fi
    [[ ! -e /proc/$sway_pid ]] || fail 'Sway process survived direct wait'; sway_pid=
  fi
  verify_supervisor_log_descriptors
  no_swaybg_activity || fail 'swaybg activity detected'
}

complete_cleanup_handshake() {
  local frame
  frame=$(printf '%s\n' "session-id=$session_id" "supervisor-result=$supervisor_result" "sway-pid=${recorded_sway_pid:-0}" "termination-path=$termination_path" "wait-status=$candidate_status" 'sway-reaped=true' 'cleanup-complete=true')
  frame+=$'\n'
  perl -MFcntl=:DEFAULT -MIO::Handle -e '
    use constant SYS_openat => 257;   # Linux x86_64 is the raw-39 platform.
    use constant SYS_unlinkat => 263;
    use constant O_CLOEXEC_LINUX => 02000000;
    my ($directory, $expected, $body) = @ARGV;
    sysopen(my $dir, $directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC_LINUX) or die "open session: $!\n";
    fileno($dir) == 3 or die "session directory did not receive descriptor 3\n";
    my @s = stat($dir); join(q{:}, @s[0, 1, 4, 5]) eq $expected or die "session identity changed\n";
    (-e q{/proc/self/fd/3/cleanup.ack} || -l q{/proc/self/fd/3/cleanup.ack}) and die "preexisting cleanup.ack\n";
    my $frame_name = q{cleanup.frame};
    my $frame_fd = syscall(SYS_openat, fileno($dir), $frame_name, O_WRONLY | O_NOFOLLOW | O_CREAT | O_EXCL | O_CLOEXEC_LINUX, 0600);
    $frame_fd >= 0 or die "openat cleanup.frame: $!\n";
    open(my $frame, ">&=$frame_fd") or die "fdopen cleanup.frame: $!\n";
    binmode($frame); print {$frame} $body or die "write cleanup.frame: $!\n"; defined($frame->sync) or die "fsync cleanup.frame: $!\n"; close($frame) or die "close cleanup.frame: $!\n";
    my $ok = 0;
    for (1 .. 500) {
      if (lstat(q{/proc/self/fd/3/cleanup.ack}) && -f _ && !-l _) {
        my $ack_name = q{cleanup.ack}; my $ack_fd = syscall(SYS_openat, fileno($dir), $ack_name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC_LINUX, 0);
        $ack_fd >= 0 or die "openat cleanup.ack: $!\n";
        open(my $ack, "<&=$ack_fd") or die "fdopen cleanup.ack: $!\n";
        binmode($ack); my $bytes = q{}; sysread($ack, $bytes, 3); close($ack) or die "close cleanup.ack: $!\n";
        $bytes eq "K\n" or die "invalid cleanup.ack\n"; $ok = 1; last;
      }
      select undef, undef, undef, 0.1;
    }
    $ok or die "cleanup acknowledgement timed out\n";
    my $frame_unlink = q{cleanup.frame}; syscall(SYS_unlinkat, fileno($dir), $frame_unlink, 0) == 0 or die "unlinkat cleanup.frame: $!\n";
    my $ack_unlink = q{cleanup.ack}; syscall(SYS_unlinkat, fileno($dir), $ack_unlink, 0) == 0 or die "unlinkat cleanup.ack: $!\n";
    close($dir) or die "close session directory: $!\n";
  ' -- "$session_dir" "$session_identity" "$frame" || fail 'cleanup handshake failed'
}

finish_integration() {
  reap_integration_children
  exec 3>&- 4>&- 5>&- 6>&-; assert_descriptor_set '0 1 2'
  [[ -d $session_dir && ! -L $session_dir && -n $session_identity ]] || fail 'unsafe session directory'
  complete_cleanup_handshake
  assert_descriptor_set '0 1 2'
}

handle_signal() { interrupted=true; termination_path=signal; }

main() {
  while (($#)); do
    case $1 in
      --session-id) (($# >= 2)) || fail 'missing session ID'; session_id=$2; shift 2 ;;
      --class) (($# >= 2)) || fail 'missing session class'; session_class=$2; shift 2 ;;
      --preflight-fd) (($# >= 2)) || fail 'missing preflight descriptor'; preflight_fd=$2; shift 2 ;;
      --ack-fd) (($# >= 2)) || fail 'missing acknowledgement descriptor'; ack_fd=$2; shift 2 ;;
      --timeout-seconds) (($# >= 2)) || fail 'missing timeout'; timeout_seconds=$2; shift 2 ;;
      --) shift; break ;;
      *) fail 'unknown supervisor argument' ;;
    esac
  done
  [[ $session_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $session_class =~ ^(base|integration)$ && $preflight_fd == 3 && $ack_fd == 4 && $timeout_seconds == "$supervisor_timeout_seconds" && $# -gt 0 ]] || fail 'invalid raw-39 supervisor invocation'
  # The source-to-EOF launcher has already closed Bash's source reader. This
  # remains a defensive raw-39 close and must preserve the handshake FDs.
  supervisor_pid=$BASHPID
  exec 255<&-
  [[ ! -e /proc/self/fd/255 ]] || fail 'Bash script descriptor survived close'
  assert_descriptor_set '0 1 2 3 4'; record_standard_descriptors; write_preflight; accept_preflight_acknowledgement; assert_descriptor_set '0 1 2'; verify_standard_descriptors; run_loopback
  if [[ $session_class == base ]]; then local -a environment=(); candidate_environment environment; verify_standard_descriptors; exec "$coreutils_env" -i -- "${environment[@]}" "$@"; fi
  [[ -d $session_dir && ! -L $session_dir ]] || fail 'unsafe session directory'
  session_identity=$("$coreutils_bin/stat" -c '%d:%i:%u:%g' "$session_dir") || fail 'cannot record session identity'
  trap handle_signal INT HUP QUIT TERM
  prepare_supervisor_logs; start_sway
  if ! await_sway_readiness; then supervisor_result=sway-failed; termination_path=early-sway-failure; finish_integration; exit 1; fi
  start_candidate "$@"
  local started=$SECONDS
  while direct_child_is_running "$candidate_pid"; do
    if $interrupted; then supervisor_result=interrupted; break; fi
    if (( SECONDS - started >= timeout_seconds )); then supervisor_result=timeout; termination_path=timeout; break; fi
    if ! direct_child_is_running "$sway_pid"; then supervisor_result=sway-failed; termination_path=sway-failed; break; fi
    runtime_is_exact || { supervisor_result=socket-disrupted; termination_path=socket-disrupted; break; }
    no_swaybg_activity || { supervisor_result=cleanup-failed; termination_path=swaybg-detected; break; }
    sleep 0.1
  done
  if [[ $supervisor_result == pending ]]; then set +e; wait "$candidate_pid"; candidate_status=$?; set -e; candidate_pid=; if (( candidate_status == 0 )); then supervisor_result=success; else supervisor_result=candidate-failed; fi; termination_path=candidate-exit; fi
  finish_integration
  [[ $supervisor_result == success ]] || exit 1
  exit 0
}
