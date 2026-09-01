#!/usr/bin/env bash
# Contract fixture for the two host-store closure views. It intentionally
# mounts immutable store members at their canonical paths; copying a private
# Nix store would make Nix state and a writable duplicate candidate authority.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
runner=$root/scripts/run-managed-role.sh
nix_store=/nix/store/nskid3yq908g18x6cnvrk2hy96327f3f-nix-2.35.2/bin/nix-store
[[ $($nix_store --version) == 'nix-store (Nix) 2.35.2' ]] || exit 1
rg -Fq 'prepare_linux_candidate_closure_views()' "$runner"
rg -Fq 'prepare_linux_candidate_private_store()' "$runner"
rg -Fq 'base-session-closure.manifest' "$runner"
rg -Fq 'integration-session-closure.manifest' "$runner"
rg -Fq 'bwrap_args+=(--ro-bind "$closure_path" "$closure_path")' "$runner"
# The raw-38 fixture owns only M003's view/controller. The predecessor private
# store is separately selected for non-M003 tickets and must not weaken this
# exact closure proof.
m003_view_scope=$(awk '
  /^prepare_linux_candidate_closure_views\(\)/ { active = 1 }
  /^run_linux_native_isolation_prerequisite\(\)/ { active = 0 }
  active { print }
' "$runner")
m003_controller_scope=$(awk '
  /^m003_prepare_closure_log\(\)/ { active = 1 }
  /^linux_m003_candidate_bwrap\(\)/ { active = 0 }
  active { print }
' "$runner")
printf '%s\n' "$m003_view_scope" | rg -Fq '[[ $ticket == BURL-M003 ]] || return 0'
! printf '%s\n%s\n' "$m003_view_scope" "$m003_controller_scope" | rg -Fq 'candidate_private_store'
! printf '%s\n%s\n' "$m003_view_scope" "$m003_controller_scope" | rg -Fq 'nix copy --offline'

profile_fragment=$(mktemp "${TMPDIR:-/tmp}/burlmd-profile.XXXXXXXX")
scratch=
fixture_source_overlay_root=
fixture_source_overlay_created=()
cleanup_fixture_source_overlay_destinations() {
  local index path status=0
  for ((index = ${#fixture_source_overlay_created[@]} - 1; index >= 0; index--)); do
    path=${fixture_source_overlay_created[index]}
    if [[ $path == "$fixture_source_overlay_root"/* && -d $path && ! -L $path ]]; then
      rmdir -- "$path" || status=1
    else
      status=1
    fi
  done
  fixture_source_overlay_created=()
  return "$status"
}
cleanup_fixture() {
  local status=$?
  cleanup_fixture_source_overlay_destinations || status=1
  [[ -z $scratch ]] || rm -rf -- "$scratch" || status=1
  rm -f -- "$profile_fragment" || status=1
  return "$status"
}
trap cleanup_fixture EXIT INT TERM HUP
awk '/^candidate_profile_tools\(\)/ { copy = 1 } /^candidate_command_executables\(\)/ { copy = 0 } copy { print }' "$runner" >"$profile_fragment"
source "$profile_fragment"
mapfile -t selected_tools < <(candidate_profile_tools BURL-M003 linux-x86_64)
tools=(bash sh env mkdir mktemp chmod install cp mv rm cmp awk sed grep rg sort sha256sum wc find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head "${selected_tools[@]}")
for tool in "${tools[@]}" bwrap sway swaymsg; do
  path=$(readlink -f "$(command -v "$tool")")
  [[ $path == /nix/store/* && -x $path ]] || {
    echo "locked $tool is not available from the Nix store" >&2
    exit 1
  }
done

scratch=$(mktemp -d "$root/.scratch-burlmd-role-closure.XXXXXXXX")
base_manifest=$scratch/base-session-closure.manifest
integration_manifest=$scratch/integration-session-closure.manifest
roots=()
for tool in "${tools[@]}"; do
  executable=$(readlink -f "$(command -v "$tool")")
  roots+=(/nix/store/${executable#/nix/store/})
done
for root_path in "${roots[@]}"; do
  store_name=${root_path#/nix/store/}
  "$nix_store" -qR "/nix/store/${store_name%%/*}"
done | LC_ALL=C sort -u >"$base_manifest"
openssl_pc=$(pkg-config --variable=pcfiledir openssl)
openssl_include=$(pkg-config --variable=includedir openssl)
openssl_lib=$(pkg-config --variable=libdir openssl)
mesa_dri=${BURLMD_MESA_DRI_PATH:?locked Mesa DRI path is required}
mesa_egl=${BURLMD_MESA_EGL_VENDOR_PATH:?locked Mesa EGL path is required}
for extra in "$openssl_pc" "$openssl_include" "$openssl_lib" "${mesa_dri%/lib/dri}" "${mesa_egl%/share/glvnd/egl_vendor.d/50_mesa.json}"; do
  entry=${extra#/nix/store/}
  "$nix_store" -qR "/nix/store/${entry%%/*}"
done | { cat "$base_manifest"; cat; } | LC_ALL=C sort -u >"$base_manifest.next"
mv "$base_manifest.next" "$base_manifest"
sway_root=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12
swaymsg_root=/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12
{ cat "$base_manifest"; "$nix_store" -qR "$sway_root"; "$nix_store" -qR "$swaymsg_root"; } | LC_ALL=C sort -u >"$integration_manifest"
[[ -s $base_manifest && -s $integration_manifest ]]
! rg -n '/nix/var|/nix/store/.*/nix/var' "$base_manifest" "$integration_manifest"
[[ $(wc -l <"$base_manifest" | tr -d ' ') == 488 ]]
[[ $(wc -l <"$integration_manifest" | tr -d ' ') == 547 ]]

args=(--unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv --proc /proc --dev /dev --tmpfs /tmp --dir /nix --dir /nix/store)
while IFS= read -r member; do args+=(--ro-bind "$member" "$member"); done <"$base_manifest"
"$(command -v bwrap)" "${args[@]}" "$(command -v bash)" -ceu '
  ! /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/touch /nix/store/burlmd-m003-write-probe
  test ! -e /nix/var/nix/db/db.sqlite
  /nix/store/qbsvh4fw7lrmkqk870w4sc21kqylph42-iproute2-7.0.0/bin/ip link set dev lo up
  /nix/store/qbsvh4fw7lrmkqk870w4sc21kqylph42-iproute2-7.0.0/bin/ip -o link show up dev lo
'

# Exercise the production private tool-path constructor rather than merely
# asserting its source text. The injected active-isolation assertion needs all
# of these helpers, and each must resolve from the candidate-only directory.
# In particular, rg's final target must already be a member of the locked base
# view; adding a new closure root here would change the raw-38 inventory.
tool_path_fragment=$scratch/tool-path-functions.sh
awk '
  /^candidate_profile_tools\(\)/ { capture = 1 }
  /^candidate_command_executables\(\)/ { capture = 0 }
  capture { print }
' "$runner" >"$tool_path_fragment"
awk '
  /^prepare_candidate_tool_path\(\)/ { capture = 1 }
  /^validate_pub_lock_dependencies\(\)/ { capture = 0 }
  capture { print }
' "$runner" >>"$tool_path_fragment"
# shellcheck source=/dev/null
source "$tool_path_fragment"
ticket=BURL-M003
role=linux-x86_64
script_root=$root
source_root=$root
candidate_workspace=$root
candidate_root=$scratch/production-tool-path
candidate_env=('PATH=untrusted')
prepare_candidate_tool_path
[[ ${candidate_env[0]} == "PATH=$candidate_tool_path" ]]
active_isolation_tools=(bash sh env cat mkdir chmod awk rg sort readlink)
for tool in "${active_isolation_tools[@]}"; do
  resolved_from_tool_path=$(PATH="$candidate_tool_path" command -v "$tool")
  [[ $resolved_from_tool_path == "$candidate_tool_path/$tool" && -L $resolved_from_tool_path ]]
  resolved_target=$(readlink -f -- "$resolved_from_tool_path")
  [[ $resolved_target == /nix/store/* && -x $resolved_target ]]
  store_entry=${resolved_target#/nix/store/}
  store_member=/nix/store/${store_entry%%/*}
  rg -Fxq -- "$store_member" "$base_manifest"
done
if PATH="$candidate_tool_path" command -v bwrap >/dev/null; then
  echo 'candidate tool path exposes parent-only Bubblewrap' >&2
  exit 1
fi

# Exercise the production authority parser against the live mount table.  The
# authority leaf remains declarative; the stable parent fields must be actual
# no-follow stat and decoded mountinfo facts, not fixture constants.
authority_fragment=$scratch/authority-functions.sh
awk '/^m003_file_type\(\)/ { capture = 1 } /^m003_plan_authorities\(\)/ { capture = 0 } capture { print }' "$runner" >"$authority_fragment"
# shellcheck source=/dev/null
source "$authority_fragment"
declare -A m003_current_path=() m003_authority_ids=() m003_capacity_devices=() m003_capacity_device_path=()
declare -A m003_authority_root=() m003_authority_leaf=() m003_authority_session=() m003_authority_kind=() m003_current_frozen_identity=()
declare -A m003_frozen_parent_fd=() m003_frozen_parent_identity=() m003_frozen_parent_uid=() m003_frozen_parent_gid=() m003_frozen_parent_mode=()
declare -A m003_frozen_parent_mount_id=() m003_frozen_parent_mount_device=() m003_frozen_parent_mount_root=() m003_frozen_parent_mount_point=()
m003_authorities=$scratch/authorities.tsv
: >"$m003_authorities"
mkdir "$scratch/declared-leaf"
m003_add_authority 1 fixture candidate-home argv-source "$scratch" declared-leaf
IFS=$'\t' read -r -a authority_fields <"$m003_authorities"
[[ ${#authority_fields[@]} == 16 && ${authority_fields[0]} == capacity-authority && ${authority_fields[8]} =~ ^0[0-7]{3,4}$ && ${authority_fields[9]} == directory && ${authority_fields[10]} =~ ^[0-9]+$ && ${authority_fields[11]} =~ ^[0-9]+$ && ${authority_fields[12]} =~ ^[0-9]+:[0-9]+$ && ${authority_fields[13]} == /* && ${authority_fields[14]} == "$scratch" && ${authority_fields[15]} == declared-leaf ]]
[[ ${m003_current_path[1:candidate-home]} == "$scratch/declared-leaf" && ${#m003_capacity_devices[@]} == 1 && ${m003_capacity_device_path[${authority_fields[10]}]} == "$scratch" ]]
m003_validate_current_authority 1 fixture candidate-home
m003_close_authority_fds

reset_authority_fixture() {
  m003_close_authority_fds
  m003_current_path=(); m003_authority_ids=(); m003_capacity_devices=(); m003_capacity_device_path=()
  m003_authority_root=(); m003_authority_leaf=(); m003_authority_session=(); m003_authority_kind=(); m003_current_frozen_identity=()
  m003_frozen_parent_identity=(); m003_frozen_parent_uid=(); m003_frozen_parent_gid=(); m003_frozen_parent_mode=()
  m003_frozen_parent_mount_id=(); m003_frozen_parent_mount_device=(); m003_frozen_parent_mount_root=(); m003_frozen_parent_mount_point=()
  : >"$m003_authorities"
}

assert_authority_mutation_rejected() {
  local name=$1 parent=$scratch/authority-$1
  mkdir -m 700 "$parent" "$parent/leaf"
  reset_authority_fixture
  m003_add_authority 1 session-one candidate-home argv-source "$parent" leaf
  case $name in
    mode) chmod 755 "$parent" ;;
    ownership) chgrp "$(id -G | tr ' ' '\n' | awk -v current="$(id -g)" '$1 != current { print; exit }')" "$parent" ;;
    substitution)
      mv "$parent" "$parent-frozen"
      mkdir -m 700 "$parent" "$parent/leaf"
      ;;
    symlink)
      rmdir "$parent/leaf"
      mkdir "$parent/alternate"
      ln -s alternate "$parent/leaf"
      ;;
    *) return 1 ;;
  esac
  if m003_validate_current_authority 1 session-one candidate-home; then
    echo "authority $name mutation reached the candidate boundary" >&2
    return 1
  fi
  m003_close_authority_fds
}

assert_authority_mutation_rejected mode
assert_authority_mutation_rejected ownership
assert_authority_mutation_rejected substitution
assert_authority_mutation_rejected symlink

runtime_parent=$scratch/authority-runtime
mkdir -m 700 "$runtime_parent"
reset_authority_fixture
m003_add_authority 5 integration-session xdg-runtime runtime-leaf "$runtime_parent" runtime
mkdir -m 755 "$runtime_parent/runtime"
! m003_validate_current_authority 5 integration-session xdg-runtime
chmod 700 "$runtime_parent/runtime"
printf x >"$runtime_parent/runtime/precreated"
! m003_validate_current_authority 5 integration-session xdg-runtime
rm "$runtime_parent/runtime/precreated"
m003_validate_current_authority 5 integration-session xdg-runtime
m003_close_authority_fds

[[ $(m003_uint64_product 4000000 1024) == 4096000000 ]]
! m003_uint64_product 18446744073709551615 2 >/dev/null
! m003_uint64_product 18446744073709551616 0 >/dev/null

# A bind mount can keep st_dev unchanged while changing mount identity. Freeze
# the parent inside a private test mount namespace, add such a nested mount
# between sessions, and require rejection before a payload marker is written.
mount_fixture=$scratch/authority-mount
mkdir -p "$mount_fixture/parent/leaf" "$mount_fixture/alternate"
mount_bin=$(readlink -f "$(command -v mount)")
bwrap_bin=$(readlink -f "$(command -v bwrap)")
bash_bin=$(readlink -f "$(command -v bash)")
"$bwrap_bin" --unshare-all --uid 0 --gid 0 --cap-add CAP_SYS_ADMIN \
  --ro-bind /nix /nix --bind "$scratch" /fixture --proc /proc --dev /dev -- \
  "$bash_bin" -ceu '
    source /fixture/authority-functions.sh
    declare -A m003_current_path=() m003_authority_ids=() m003_capacity_devices=() m003_capacity_device_path=()
    declare -A m003_authority_root=() m003_authority_leaf=() m003_authority_session=() m003_authority_kind=() m003_current_frozen_identity=()
    declare -A m003_frozen_parent_fd=() m003_frozen_parent_identity=() m003_frozen_parent_uid=() m003_frozen_parent_gid=() m003_frozen_parent_mode=()
    declare -A m003_frozen_parent_mount_id=() m003_frozen_parent_mount_device=() m003_frozen_parent_mount_root=() m003_frozen_parent_mount_point=()
    m003_authorities=/fixture/authority-mount/rows.tsv
    : >"$m003_authorities"
    m003_add_authority 1 session-one candidate-home argv-source /fixture/authority-mount/parent leaf
    before=$(stat -c %d /fixture/authority-mount/parent/leaf)
    "$1" --bind /fixture/authority-mount/alternate /fixture/authority-mount/parent/leaf
    [[ $(stat -c %d /fixture/authority-mount/parent/leaf) == "$before" ]]
    if m003_validate_current_authority 1 session-one candidate-home; then
      : >/fixture/authority-mount/payload-reached
      exit 1
    fi
  ' mount-identity "$mount_bin"
[[ ! -e $mount_fixture/payload-reached ]]

# The exact native compositor and teardown executables are observed without
# starting a compositor server. Wrong path, version, digest, and linked-path
# substitutions must all fail before a session payload exists.
executable_fragment=$scratch/executable-observation-functions.sh
awk '/^m003_observe_exact_executable\(\)/ { capture = 1 } /^prepare_linux_candidate_closure_views\(\)/ { capture = 0 } capture { print }' "$runner" >"$executable_fragment"
# shellcheck source=/dev/null
source "$executable_fragment"
m003_runner_temp_root=$scratch/executable-observation
mkdir -p "$m003_runner_temp_root/burlmd-m003"
m003_revalidate_observed_executables
[[ $m003_sway_path == /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway &&
   $m003_sway_version == 'sway version 1.12' &&
   $m003_sway_sha == 1f10250bedd99cda8a7ef04a585f66a1dd300bd37557dbd9983535b0a8b5667d &&
   $m003_swaymsg_path == /nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg &&
   $m003_flock_path == /nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock ]]
! m003_observe_exact_executable sway "$m003_sway_path" "$m003_swaymsg_path" 'sway version 1.12' "$m003_sway_sha" --version
! m003_observe_exact_executable sway "$m003_sway_path" "$m003_sway_path" 'sway version 1.11' "$m003_sway_sha" --version
! m003_observe_exact_executable sway "$m003_sway_path" "$m003_sway_path" 'sway version 1.12' 000000000000000000000000000000+baddigest --version
hash_order_probe=$scratch/hash-order-sway
printf '%s\n' "#!$(command -v bash)" ": >'$scratch/hash-order-executed'" "printf 'sway version 1.12\\n'" >"$hash_order_probe"
chmod 755 "$hash_order_probe"
! m003_observe_exact_executable sway "$hash_order_probe" "$hash_order_probe" 'sway version 1.12' 0000000000000000000000000000000000000000000000000000000000000000 --version
[[ ! -e $scratch/hash-order-executed ]]
ln -s "$m003_sway_path" "$scratch/substituted-sway"
! m003_observe_exact_executable sway "$scratch/substituted-sway" "$m003_sway_path" 'sway version 1.12' "$m003_sway_sha" --version

# The explicit tested checkout receives only empty destinations for mounts
# already declared by raw-38. Their creation/removal must leave tracked bytes
# and both lockfiles unchanged, and a tracked substitution must be detected.
source_mountpoint_fragment=$scratch/source-mountpoint-functions.sh
awk '/^m003_source_tracked_state_is_clean\(\)/ { capture = 1 } /^prepare_candidate_dependencies\(\)/ { capture = 0 } capture { print }' "$runner" >"$source_mountpoint_fragment"
# shellcheck source=/dev/null
source "$source_mountpoint_fragment"
source_root=$scratch/authenticated-source
mkdir -p "$source_root/rust" "$source_root/linux/flutter"
printf 'pub-lock\n' >"$source_root/pubspec.lock"
printf 'cargo-lock\n' >"$source_root/rust/Cargo.lock"
git -C "$source_root" init -q
git -C "$source_root" config user.email fixture@example.invalid
git -C "$source_root" config user.name fixture
git -C "$source_root" add pubspec.lock rust/Cargo.lock
git -C "$source_root" commit -qm 'fixture authenticated source'
ticket=BURL-M003
role=linux-x86_64
m003_source_mountpoints_created=()
m003_prepare_authenticated_source_mountpoints
[[ -d $source_root/.dart_tool && -d $source_root/build && -d $source_root/linux/flutter/ephemeral ]]
m003_source_tracked_state_is_clean
printf 'changed\n' >"$source_root/pubspec.lock"
! m003_source_tracked_state_is_clean
printf 'pub-lock\n' >"$source_root/pubspec.lock"
m003_cleanup_authenticated_source_mountpoints
[[ ! -e $source_root/.dart_tool && ! -e $source_root/build && ! -e $source_root/linux/flutter/ephemeral ]]
m003_source_tracked_state_is_clean

stdio_fragment=$scratch/stdio-functions.sh
awk '/^m003_write_cleanup_ack\(\)/ { exit } /^m003_descriptor_identity\(\)/ { capture = 1 } capture { print }' "$runner" >"$stdio_fragment"
# shellcheck source=/dev/null
source "$stdio_fragment"
declare -A m003_standard_stream_identity=()
m003_open_standard_streams "$scratch/final.stdin" "$scratch/final.stdout" "$scratch/final.stderr"
[[ -n ${m003_standard_stream_identity[0]} && -n ${m003_standard_stream_identity[1]} && -n ${m003_standard_stream_identity[2]} ]]
[[ $(stat -Lc '%d:%i' -- "$scratch/final.stdin") == $(stat -Lc '%d:%i' -- "/proc/self/fd/$m003_stdin_fd") ]]
[[ $(stat -Lc '%d:%i' -- "$scratch/final.stdout") == $(stat -Lc '%d:%i' -- "/proc/self/fd/$m003_stdout_fd") ]]
[[ $(stat -Lc '%d:%i' -- "$scratch/final.stderr") == $(stat -Lc '%d:%i' -- "/proc/self/fd/$m003_stderr_fd") ]]
m003_close_standard_streams
[[ -z ${m003_stdin_fd:-} && -z ${m003_stdout_fd:-} && -z ${m003_stderr_fd:-} ]]

# Prove the raw retained-descriptor mechanism with the exact kernel flags and
# util-linux OFD lock mode.  Perl owns the original open description across
# the fork; Bubblewrap receives only its pathname lock and must release it
# before the parent's retained FD can acquire an OFD write lock.
lock_session=$scratch/retained-lock-session
mkdir "$lock_session"
lock_ready=$lock_session/namespace-ready
lock_release=$lock_session/namespace-release
mkfifo -m 600 "$lock_ready" "$lock_release"
lock_args=("${args[@]}" --dir /candidate --bind "$lock_session" /candidate/session --lock-file /candidate/session/namespace-teardown.lock)
perl -MFcntl=:DEFAULT -MIO::Select -e '
  my ($session, $flock, $ready_path, $release_path, @command) = @ARGV;
  sysopen(my $dir, $session, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) or die "open session: $!\n";
  my $lock_path = q{/proc/self/fd/} . fileno($dir) . q{/namespace-teardown.lock};
  sysopen(my $lock, $lock_path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) or die "create original lock: $!\n";
  fcntl($lock, F_SETFD, 0) or die "clear lock cloexec: $!\n";
  sysopen(my $ready, $ready_path, O_RDWR | O_NONBLOCK | O_NOFOLLOW) or die "open namespace readiness: $!\n";
  sysopen(my $release, $release_path, O_RDWR | O_NONBLOCK | O_NOFOLLOW) or die "open namespace release: $!\n";
  my $pid = fork(); defined($pid) or die "fork: $!\n";
  my $reaped = 0;
  END {
    if ($pid > 0 && !$reaped) {
      kill(q{TERM}, $pid) if kill(0, $pid);
      waitpid($pid, 0);
    }
  }
  if (!$pid) { close($lock); exec { $command[0] } @command or die "exec bwrap: $!\n"; }
  IO::Select->new($ready)->can_read(10) or die "namespace readiness timed out\n";
  my $ready_value = <$ready>;
  defined($ready_value) && $ready_value eq "ready\n" or die "invalid namespace readiness\n";
  my $status = system($flock, q{--fcntl}, q{--exclusive}, q{--timeout}, q{1}, q{--conflict-exit-code}, q{73}, fileno($lock));
  (($status >> 8) == 73) or die "OFD lock did not conflict while namespace lived: $status\n";
  syswrite($release, "release\n") == length("release\n") or die "release namespace: $!\n";
  local $SIG{ALRM} = sub { die "bubblewrap child did not exit after release\n"; };
  alarm 10;
  waitpid($pid, 0);
  alarm 0;
  $reaped = 1;
  (($? >> 8) == 0) or die "bubblewrap child failed: $?\n";
  $status = system($flock, q{--fcntl}, q{--exclusive}, q{--timeout}, q{5}, q{--conflict-exit-code}, q{73}, fileno($lock));
  (($status >> 8) == 0) or die "OFD lock did not acquire after namespace exit: $status\n";
  system($flock, q{--fcntl}, q{--unlock}, fileno($lock)) == 0 or die "unlock failed\n";
' -- "$lock_session" /nix/store/qjs15klpvpwz64pjdspy3mln6d54pd8f-util-linux-2.42-bin/bin/flock "$lock_ready" "$lock_release" \
  /nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap "${lock_args[@]}" \
  /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash -ceu 'printf "ready\\n" >"$1"; IFS= read -r release <"$2"; [[ $release == release ]]' handshake /candidate/session/namespace-ready /candidate/session/namespace-release

# The inline production controller must clean up and release its original lock
# even if its child exits before preflight.  This executes the actual Perl
# body with an empty-environment direct child, then proves no session/staging/
# contract/runtime leaf remains.
controller_fragment=$scratch/controller-function.sh
awk '/^m003_perl_session_controller\(\)/ { capture = 1 } /^m003_run_session\(\)/ { capture = 0 } capture { print }' "$runner" >"$controller_fragment"
# shellcheck source=/dev/null
source "$controller_fragment"
controller_session=$scratch/controller-session
controller_stage=$scratch/controller-stage
controller_contract=$scratch/controller-contract
controller_runtime=$scratch/controller-runtime
mkdir "$controller_session" "$controller_stage" "$controller_contract" "$controller_runtime"
printf x >"$scratch/controller.expected"
if m003_perl_session_controller "$controller_session" "$scratch/controller.expected" base "$scratch/controller.stdout" "$scratch/controller.stderr" "$scratch/controller.stdin" "$scratch/controller.output" "$controller_stage" "$controller_contract" "$controller_runtime" controller-negative /nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/false; then
  echo 'pre-preflight controller child unexpectedly succeeded' >&2
  exit 1
fi
if ! [[ -f $scratch/controller.output && ! -L $scratch/controller.output && $(stat -Lc '%a' -- "$scratch/controller.output") == 600 && ! -e $controller_session && ! -e $controller_stage && ! -e $controller_contract && -d $controller_runtime ]]; then
  ls -ld "$scratch/controller.output" "$controller_session" "$controller_stage" "$controller_contract" "$controller_runtime" 2>&1
  exit 1
fi

controller_success=$scratch/controller-success
controller_success_stage=$scratch/controller-success-stage
controller_success_contract=$scratch/controller-success-contract
mkdir "$controller_success" "$controller_success_stage" "$controller_success_contract"
printf x >"$scratch/controller-success.expected"
printf '%s\n' '#!/bin/sh' "printf 'preflight-bytes=1\\nx' >&3" 'exec 3>&-' 'value=$(/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/dd bs=1 count=1 status=none <&4)' 'test "$value" = G' 'exec 4<&-' 'test ! -e /proc/self/fd/4' 'printf controller-success' >"$scratch/controller-success-child"
chmod 755 "$scratch/controller-success-child"
controller_result=$(m003_perl_session_controller "$controller_success" "$scratch/controller-success.expected" base "$scratch/controller-success.stdout" "$scratch/controller-success.stderr" "$scratch/controller-success.stdin" "$scratch/controller-success.output" "$controller_success_stage" "$controller_success_contract" "$scratch/controller-success-runtime-unused" controller-success "$scratch/controller-success-child")
[[ $controller_result =~ ^ok$'\t'[1-9][0-9]*:[1-9][0-9]*$ && $(<"$scratch/controller-success.output") == controller-success && ! -e $controller_success && ! -e $controller_success_stage && ! -e $controller_success_contract ]]

# The integration parent must wait for the kernel IN_CLOSE_WRITE event before
# it reads or acknowledges cleanup.frame. A child keeps the frame descriptor
# open across an explicit FIFO handoff; no timing or size-stability heuristic
# can make the parent acknowledge its partial bytes.
slow_session=$scratch/controller-slow-session
slow_stage=$scratch/controller-slow-stage
slow_contract=$scratch/controller-slow-contract
slow_runtime=$scratch/controller-slow-runtime
slow_ready=$scratch/controller-slow-ready
slow_release=$scratch/controller-slow-release
slow_child=$scratch/controller-slow-child
slow_expected=$scratch/controller-slow.expected
slow_result=$scratch/controller-slow.result
slow_output=$scratch/controller-slow.output
mkdir "$slow_session" "$slow_stage" "$slow_contract" "$slow_runtime"
mkfifo "$slow_ready" "$slow_release"
printf x >"$slow_expected"
printf '%s\n' '#!/bin/sh' \
  'printf "preflight-bytes=1\nx" >&3' 'exec 3>&-' 'IFS= read -r acknowledgement <&4' 'test "$acknowledgement" = G || exit 2' 'exec 4<&-' \
  'umask 077' 'exec 9>"$1/cleanup.frame"' 'printf "session-id=slow-session\nsupervisor-result=success\nsway-pid=1\ntermination-path=sway-sigkill\nwait-status=0\nsway-reaped=true\n" >&9' \
  'printf "ready\n" >"$2"' 'IFS= read -r release <"$3"' '[[ $release == release ]]' \
  'printf "cleanup-complete=true\n" >&9' 'exec 9>&-' 'printf slow-complete' >"$slow_child"
chmod 755 "$slow_child"
m003_perl_session_controller "$slow_session" "$slow_expected" integration "$scratch/controller-slow.stdout" "$scratch/controller-slow.stderr" "$scratch/controller-slow.stdin" "$slow_output" "$slow_stage" "$slow_contract" "$slow_runtime" slow-session "$slow_child" "$slow_session" "$slow_ready" "$slow_release" >"$slow_result" &
slow_controller_pid=$!
if ! IFS= read -r -t 10 slow_ready_value <"$slow_ready"; then
  wait "$slow_controller_pid" || true
  [[ ! -e $slow_output ]] || cat "$slow_output" >&2
  exit 1
fi
[[ $slow_ready_value == ready && ! -e $slow_session/cleanup.ack && ! -e $slow_session/cleanup.frame/cleanup.ack ]]
printf 'release\n' >"$slow_release"
wait "$slow_controller_pid"
[[ $(<"$slow_result") =~ ^ok$'\t'[1-9][0-9]*:[1-9][0-9]*$ && $(<"$slow_output") == slow-complete && ! -e $slow_session && ! -e $slow_stage && ! -e $slow_contract && ! -e $slow_runtime ]]

# A well-formed failed integration frame still receives K so the supervisor
# can remove its handshake files. The controller then rejects the nonzero
# outer result; the retained output marker proves acknowledgement happened.
failure_session=$scratch/controller-failure-session
failure_stage=$scratch/controller-failure-stage
failure_contract=$scratch/controller-failure-contract
failure_runtime=$scratch/controller-failure-runtime
failure_expected=$scratch/controller-failure.expected
failure_child=$scratch/controller-failure-child
failure_output=$scratch/controller-failure.output
failure_parent_stderr=$scratch/controller-failure.parent-stderr
mkdir "$failure_session" "$failure_stage" "$failure_contract" "$failure_runtime"
printf x >"$failure_expected"
printf '%s\n' '#!/bin/sh' \
  'printf "preflight-bytes=1\nx" >&3' 'exec 3>&-' 'IFS= read -r acknowledgement <&4' 'test "$acknowledgement" = G || exit 2' 'exec 4<&-' \
  'umask 077' 'printf "session-id=failure-session\nsupervisor-result=candidate-failed\nsway-pid=1\ntermination-path=candidate-exit\nwait-status=1\nsway-reaped=true\ncleanup-complete=true\n" >"$1/cleanup.frame"' \
  'while test ! -e "$1/cleanup.ack"; do :; done' 'IFS= read -r acknowledgement <"$1/cleanup.ack"' 'test "$acknowledgement" = K || exit 2' 'printf failure-ack' 'exit 1' >"$failure_child"
chmod 755 "$failure_child"
if m003_perl_session_controller "$failure_session" "$failure_expected" integration "$scratch/controller-failure.stdout" "$scratch/controller-failure.stderr" "$scratch/controller-failure.stdin" "$failure_output" "$failure_stage" "$failure_contract" "$failure_runtime" failure-session "$failure_child" "$failure_session" 2>"$failure_parent_stderr"; then
  echo 'failed cleanup frame was accepted' >&2
  exit 1
fi
rg -Fq 'candidate or supervisor failed' "$failure_parent_stderr"
[[ ! -e $failure_session && ! -e $failure_stage && ! -e $failure_contract && ! -e $failure_runtime ]]

# A supervisor-owned Sway failure can race a candidate exit0. Its completed
# frame still receives K, then the non-success result rejects the session.
sway_failure_session=$scratch/controller-sway-failure-session
sway_failure_stage=$scratch/controller-sway-failure-stage
sway_failure_contract=$scratch/controller-sway-failure-contract
sway_failure_runtime=$scratch/controller-sway-failure-runtime
sway_failure_expected=$scratch/controller-sway-failure.expected
sway_failure_child=$scratch/controller-sway-failure-child
sway_failure_stderr=$scratch/controller-sway-failure.parent-stderr
mkdir "$sway_failure_session" "$sway_failure_stage" "$sway_failure_contract" "$sway_failure_runtime"
printf x >"$sway_failure_expected"
printf '%s\n' '#!/bin/sh' \
  'printf "preflight-bytes=1\nx" >&3' 'exec 3>&-' 'IFS= read -r acknowledgement <&4' 'test "$acknowledgement" = G || exit 2' 'exec 4<&-' \
  'umask 077' 'printf "session-id=sway-failure-session\nsupervisor-result=sway-failed\nsway-pid=1\ntermination-path=early-sway-failure\nwait-status=0\nsway-reaped=true\ncleanup-complete=true\n" >"$1/cleanup.frame"' 'exit 0' >"$sway_failure_child"
chmod 755 "$sway_failure_child"
if m003_perl_session_controller "$sway_failure_session" "$sway_failure_expected" integration "$scratch/controller-sway-failure.stdout" "$scratch/controller-sway-failure.stderr" "$scratch/controller-sway-failure.stdin" "$scratch/controller-sway-failure.output" "$sway_failure_stage" "$sway_failure_contract" "$sway_failure_runtime" sway-failure-session "$sway_failure_child" "$sway_failure_session" 2>"$sway_failure_stderr"; then
  echo 'sway failure with candidate exit0 was accepted' >&2
  exit 1
fi
rg -Fq 'candidate or supervisor failed' "$sway_failure_stderr"
[[ ! -e $sway_failure_session && ! -e $sway_failure_stage && ! -e $sway_failure_contract && ! -e $sway_failure_runtime ]]

# Both success/nonzero and failure/zero status pairs are malformed producer
# claims. They close their frames without waiting for K; acceptance of either
# would be a controller protocol regression.
invalid_session=$scratch/controller-invalid-session
invalid_stage=$scratch/controller-invalid-stage
invalid_contract=$scratch/controller-invalid-contract
invalid_runtime=$scratch/controller-invalid-runtime
invalid_expected=$scratch/controller-invalid.expected
invalid_child=$scratch/controller-invalid-child
mkdir "$invalid_session" "$invalid_stage" "$invalid_contract" "$invalid_runtime"
printf x >"$invalid_expected"
printf '%s\n' '#!/bin/sh' \
  'printf "preflight-bytes=1\nx" >&3' 'exec 3>&-' 'IFS= read -r acknowledgement <&4' 'test "$acknowledgement" = G || exit 2' 'exec 4<&-' \
  'umask 077' 'printf "session-id=$2\nsupervisor-result=$3\nsway-pid=1\ntermination-path=candidate-exit\nwait-status=$4\nsway-reaped=true\ncleanup-complete=true\n" >"$1/cleanup.frame"' 'exit 1' >"$invalid_child"
chmod 755 "$invalid_child"
for invalid_result in 'success 1' 'candidate-failed 0'; do
  read -r invalid_name invalid_wait <<<"$invalid_result"
  if m003_perl_session_controller "$invalid_session" "$invalid_expected" integration "$scratch/controller-invalid.stdout" "$scratch/controller-invalid.stderr" "$scratch/controller-invalid.stdin" "$scratch/controller-invalid.output" "$invalid_stage" "$invalid_contract" "$invalid_runtime" invalid-session "$invalid_child" "$invalid_session" invalid-session "$invalid_name" "$invalid_wait"; then
    echo "invalid cleanup status/result pair was accepted: $invalid_name/$invalid_wait" >&2
    exit 1
  fi
  [[ ! -e $invalid_session && ! -e $invalid_stage && ! -e $invalid_contract && ! -e $invalid_runtime ]]
  mkdir "$invalid_session" "$invalid_stage" "$invalid_contract" "$invalid_runtime"
done
rm -rf -- "$invalid_session" "$invalid_stage" "$invalid_contract" "$invalid_runtime"

# A child can publish a valid preflight then receive a signal. Its raw wait
# status is nonzero even though shifting it would yield zero; acceptance must
# reject it and leave no accepted controller result or ephemeral leaf.
signal_session=$scratch/controller-signal-session
signal_stage=$scratch/controller-signal-stage
signal_contract=$scratch/controller-signal-contract
signal_expected=$scratch/controller-signal.expected
signal_child=$scratch/controller-signal-child
mkdir "$signal_session" "$signal_stage" "$signal_contract"
printf x >"$signal_expected"
printf '%s\n' '#!/bin/sh' 'printf "preflight-bytes=1\nx" >&3' 'exec 3>&-' 'IFS= read -r acknowledgement <&4' 'test "$acknowledgement" = G || exit 2' 'kill -KILL $$' >"$signal_child"
chmod 755 "$signal_child"
if m003_perl_session_controller "$signal_session" "$signal_expected" base "$scratch/controller-signal.stdout" "$scratch/controller-signal.stderr" "$scratch/controller-signal.stdin" "$scratch/controller-signal.output" "$signal_stage" "$signal_contract" "$scratch/controller-signal-runtime-unused" signal-session "$signal_child"; then
  echo 'signal-terminated controller child was accepted' >&2
  exit 1
fi
[[ -f $scratch/controller-signal.output && ! -L $scratch/controller-signal.output && ! -e $signal_session && ! -e $signal_stage && ! -e $signal_contract ]]

# Run both real raw-38 supervisor branches through the production argv builder
# and the inline Perl controller. This is intentionally a full host-store view
# rather than a command double: the parent validates the complete preflight,
# descriptor handshake, retained lock, and base/integration cleanup paths.
m003_runtime_fragment=$scratch/m003-runtime-functions.sh
awk '/^m003_fsync_file\(\)/ { capture = 1 } /^linux_m003_candidate_bwrap\(\)/ { capture = 0 } capture { print }' "$runner" >"$m003_runtime_fragment"
# shellcheck source=/dev/null
source "$m003_runtime_fragment"
# This fixture isolates the raw-38 controller against the current dirty
# development worktree; the cold role fixture separately exercises the real
# authenticated-source tracked/lock check.
m003_source_tracked_state_is_clean() { return 0; }

role=linux-x86_64
ticket=BURL-M003
script_root=$root
source_root=$root
candidate_execution_root=$root
candidate_root=$scratch/controller-live-candidate
output_root=$scratch/controller-live-output
m003_runner_temp_root=$scratch/controller-live-temp
mkdir -p "$candidate_root"/{home,tmp,gh,tool-path,prepared/{pub-cache/{active_roots},cargo-home},writable/{dart-tool,build,cargo-target,pub-active-roots,linux-flutter-ephemeral,l10n-generated,rust-builder-cargokit},xdg/{cache,config,data,state}} "$output_root/results" "$m003_runner_temp_root"
mkdir -p "$candidate_root/prepared/pub-cache/active_roots"
prepare_fixture_source_overlay_destinations() {
  local relative path parent canonical_parent
  fixture_source_overlay_root=$source_root
  for relative in .dart_tool build linux/flutter/ephemeral; do
    path=$source_root/$relative
    parent=$(dirname -- "$path")
    [[ -d $parent && ! -L $parent ]] || return 1
    canonical_parent=$(realpath -e -- "$parent") || return 1
    [[ $canonical_parent == "$parent" && ( $parent == "$source_root" || $parent == "$source_root"/* ) ]] || return 1
    if [[ -e $path || -L $path ]]; then
      [[ -d $path && ! -L $path && $(realpath -e -- "$path") == "$path" ]] || return 1
    else
      mkdir -- "$path" || return 1
      [[ -d $path && ! -L $path && $(realpath -e -- "$path") == "$path" ]] || return 1
      fixture_source_overlay_created+=("$path")
    fi
  done
}
# Prove the fixture's standalone prerequisite handling before it borrows the
# actual checkout. A pristine source gets only the three declared empty leaves;
# an existing leaf and its content remain untouched by both setup and cleanup.
standalone_source=$scratch/standalone-source
mkdir -p "$standalone_source/linux/flutter"
source_root=$standalone_source
prepare_fixture_source_overlay_destinations
[[ -d $source_root/.dart_tool && -d $source_root/build && -d $source_root/linux/flutter/ephemeral ]]
cleanup_fixture_source_overlay_destinations
[[ ! -e $source_root/.dart_tool && ! -e $source_root/build && ! -e $source_root/linux/flutter/ephemeral ]]
mkdir "$source_root/build"
printf preserved >"$source_root/build/sentinel"
prepare_fixture_source_overlay_destinations
[[ $(<"$source_root/build/sentinel") == preserved ]]
cleanup_fixture_source_overlay_destinations
[[ ! -e $source_root/.dart_tool && ! -e $source_root/linux/flutter/ephemeral && $(<"$source_root/build/sentinel") == preserved ]]
rm -f -- "$source_root/build/sentinel"
rmdir -- "$source_root/build"
source_root=$root
# A pristine checkout has none of these ignored overlay destinations. Create
# only missing empty leaves so the direct raw-38 Bubblewrap fixture doesn't
# rely on an earlier Flutter setup, and leave pre-existing user directories.
prepare_fixture_source_overlay_destinations
printf '%s\n' integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart >"$output_root/results/integration-tests.txt"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$candidate_root/writable/rust-builder-cargokit/run_build_tool.sh"
chmod 755 "$candidate_root/writable/rust-builder-cargokit/run_build_tool.sh"
for tool in bash sh env mkdir mktemp chmod install cp mv rm cmp awk sed grep rg sort sha256sum wc find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head cat ls dirname basename ip; do
  tool_path=$(readlink -f "$(command -v "$tool")")
  ln -s "$tool_path" "$candidate_root/tool-path/$tool"
done

candidate_linux_base_manifest=$base_manifest
candidate_linux_integration_manifest=$integration_manifest
mapfile -t candidate_linux_base_closure_paths <"$candidate_linux_base_manifest"
mapfile -t candidate_linux_integration_closure_paths <"$candidate_linux_integration_manifest"
candidate_linux_openssl_pkgconfig=$(pkg-config --variable=pcfiledir openssl)
candidate_linux_openssl_include=$(pkg-config --variable=includedir openssl)
candidate_linux_openssl_lib=$(pkg-config --variable=libdir openssl)
candidate_linux_mesa_dri=${BURLMD_MESA_DRI_PATH:?locked Mesa DRI path is required}
candidate_linux_mesa_egl=${BURLMD_MESA_EGL_VENDOR_PATH:?locked Mesa EGL path is required}
[[ ${LIBCLANG_PATH:?locked LIBCLANG_PATH is required} == /nix/store/* && $candidate_linux_openssl_pkgconfig == /nix/store/* && $candidate_linux_openssl_include == /nix/store/* && $candidate_linux_openssl_lib == /nix/store/* && $candidate_linux_mesa_dri == /nix/store/* && $candidate_linux_mesa_egl == /nix/store/* ]]

m003_plan_authorities
m003_base_sources=$m003_runner_temp_root/burlmd-m003/base-sources.tsv
m003_integration_sources=$m003_runner_temp_root/burlmd-m003/integration-sources.tsv
m003_source_rows "$candidate_linux_base_manifest" base "$m003_base_sources"
m003_source_rows "$candidate_linux_integration_manifest" integration "$m003_integration_sources"
m003_base_source_count=$(wc -l <"$m003_base_sources" | tr -d ' ')
m003_integration_source_count=$(wc -l <"$m003_integration_sources" | tr -d ' ')
m003_base_source_sha=$(sha256sum "$m003_base_sources" | awk '{print $1}')
m003_integration_source_sha=$(sha256sum "$m003_integration_sources" | awk '{print $1}')
m003_log=$m003_runner_temp_root/burlmd-m003/controller-live.log
: >"$m003_log"
bwrap_root=/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2
"$nix_store" -qR "$bwrap_root" | LC_ALL=C sort -u >"$m003_runner_temp_root/burlmd-m003/trusted-parent-bubblewrap.manifest"
m003_prepare_linux_integration_report_directory

if ! m003_run_session 1 generated-bindings base controller-live-base \
  /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash -ceu 'printf controller-live-base'; then
  cat "$output_root/results/role-step-controller-live-base.log" >&2
  exit 1
fi
controller_live_base_output=$(<"$output_root/results/role-step-controller-live-base.log")
if [[ $controller_live_base_output != controller-live-base ]]; then
  od -An -tx1 -- "$output_root/results/role-step-controller-live-base.log" >&2
  exit 1
fi
if ! m003_run_session 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d integration controller-live-integration \
  /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash -ceu 'printf "%s\n" "{\"testID\":1,\"result\":\"success\",\"skipped\":false,\"hidden\":true,\"type\":\"testDone\",\"time\":1}" "{\"testID\":2,\"result\":\"success\",\"skipped\":false,\"hidden\":false,\"type\":\"testDone\",\"time\":2}" "{\"testID\":3,\"result\":\"success\",\"skipped\":false,\"hidden\":true,\"type\":\"testDone\",\"time\":3}" "{\"success\":true,\"type\":\"done\",\"time\":4}" > /candidate/writable/results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.jsonl'; then
  cat "$output_root/results/role-step-controller-live-integration.log" >&2
  exit 1
fi
m003_consume_linux_integration_report 5 integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d integration_test/production_host_flow_test.dart
cmp -- "$candidate_root/writable/results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.jsonl" "$output_root/results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.jsonl"
jq -e '.id == "378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d" and .file == "integration_test/production_host_flow_test.dart" and .status == "passed" and .exitCode == 0' "$output_root/results/integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d.json" >/dev/null
if ! m003_run_session 6 integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d integration controller-live-integration-shell \
  /nix/store/0641h8qfqaxnwrsw2nzrz6i1wbzyx92l-bash-interactive-5.3p9/bin/bash -ceu 'printf "%s\n" "{\"testID\":1,\"result\":\"success\",\"skipped\":false,\"hidden\":true,\"type\":\"testDone\",\"time\":1}" "{\"testID\":2,\"result\":\"success\",\"skipped\":false,\"hidden\":false,\"type\":\"testDone\",\"time\":2}" "{\"testID\":3,\"result\":\"success\",\"skipped\":false,\"hidden\":true,\"type\":\"testDone\",\"time\":3}" "{\"success\":true,\"type\":\"done\",\"time\":4}" > /candidate/writable/results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.jsonl'; then
  cat "$output_root/results/role-step-controller-live-integration-shell.log" >&2
  exit 1
fi
m003_consume_linux_integration_report 6 integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d integration_test/shell_flow_test.dart
cmp -- "$candidate_root/writable/results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.jsonl" "$output_root/results/integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d.jsonl"
write_integration_outcomes_aggregate
jq -e '
  length == 2 and
  (map(.file) | sort) == ["integration_test/production_host_flow_test.dart", "integration_test/shell_flow_test.dart"] and
  all(.[]; .status == "passed" and .exitCode == 0)
' "$output_root/results/integration-outcomes.json" >/dev/null
[[ $(rg -c '^session\t' "$m003_log") == 3 && ! -e ${m003_current_path[1:session-root]} && ! -e ${m003_current_path[5:session-root]} && ! -e ${m003_current_path[6:session-root]} && ! -e ${m003_current_path[1:closure-staging]} && ! -e ${m003_current_path[5:closure-staging]} && ! -e ${m003_current_path[6:closure-staging]} && ! -e ${m003_current_path[5:xdg-runtime]} && ! -e ${m003_current_path[6:xdg-runtime]} ]]

report_test_id=378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d
report_test_file=integration_test/production_host_flow_test.dart
candidate_report=$candidate_root/writable/results/integration-$report_test_id.jsonl

reset_report_output() {
  local name=$1
  output_root=$scratch/reporter-$name-output
  mkdir -p "$output_root/results"
  printf '%s\n' integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart >"$output_root/results/integration-tests.txt"
}

assert_rejected_linux_report() {
  local name=$1 payload=${2:-}
  reset_report_output "$name"
  rm -f -- "$candidate_report"
  [[ -z $payload ]] || printf '%s\n' "$payload" >"$candidate_report"
  if m003_consume_linux_integration_report 5 integration-$report_test_id "$report_test_file"; then
    echo "invalid Linux reporter was accepted: $name" >&2
    exit 1
  fi
  jq -e --arg id "$report_test_id" --arg file "$report_test_file" '
    .id == $id and .file == $file and .status == "failed" and .exitCode == 0
  ' "$output_root/results/integration-$report_test_id.json" >/dev/null
  [[ ! -e $output_root/results/integration-$report_test_id.jsonl ]]
}

assert_rejected_linux_report missing
assert_rejected_linux_report hidden-only $'{"testID":1,"result":"success","skipped":false,"hidden":true,"type":"testDone","time":1}\n{"testID":2,"result":"success","skipped":false,"hidden":true,"type":"testDone","time":2}\n{"testID":3,"result":"success","skipped":false,"hidden":true,"type":"testDone","time":3}\n{"success":true,"type":"done","time":4}'
assert_rejected_linux_report skipped $'{"testID":1,"result":"success","skipped":true,"type":"testDone","time":1}\n{"success":true,"type":"done","time":2}'
assert_rejected_linux_report no-tests $'{"success":true,"type":"done","time":2}'
assert_rejected_linux_report malformed '{not-json'
assert_rejected_linux_report partial '{"testID":1,"result":"success","skipped":false,"type":"testDone","time":1}'
assert_rejected_linux_report failure $'{"testID":1,"result":"failure","skipped":false,"type":"testDone","time":1}\n{"success":false,"type":"done","time":2}'

reset_report_output report-symlink
printf '%s\n' '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":1}' '{"success":true,"type":"done","time":2}' >"$scratch/escaped-report.jsonl"
rm -f -- "$candidate_report"
ln -s "$scratch/escaped-report.jsonl" "$candidate_report"
if m003_consume_linux_integration_report 5 integration-$report_test_id "$report_test_file"; then
  echo 'symlinked Linux reporter was accepted' >&2
  exit 1
fi
jq -e '.status == "failed"' "$output_root/results/integration-$report_test_id.json" >/dev/null
[[ ! -e $output_root/results/integration-$report_test_id.jsonl ]]
rm -f -- "$candidate_report"

output_root=$scratch/reporter-output-link
linked_output_results=$scratch/reporter-output-link-target
mkdir -p "$output_root" "$linked_output_results"
printf '%s\n' integration_test/production_host_flow_test.dart integration_test/shell_flow_test.dart >"$linked_output_results/integration-tests.txt"
ln -s "$linked_output_results" "$output_root/results"
printf '%s\n' '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":1}' '{"success":true,"type":"done","time":2}' >"$candidate_report"
if m003_consume_linux_integration_report 5 integration-$report_test_id "$report_test_file"; then
  echo 'linked parent packaging destination was accepted' >&2
  exit 1
fi
[[ ! -e $linked_output_results/integration-$report_test_id.jsonl ]]

reset_report_output results-directory-substitution
rm -rf -- "$candidate_root/writable/results"
mkdir -m 700 "$candidate_root/writable/results"
printf '%s\n' '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":1}' '{"success":true,"type":"done","time":2}' >"$candidate_report"
if m003_consume_linux_integration_report 5 integration-$report_test_id "$report_test_file"; then
  echo 'substituted Linux reporter directory was accepted' >&2
  exit 1
fi
jq -e '.status == "failed"' "$output_root/results/integration-$report_test_id.json" >/dev/null
[[ ! -e $output_root/results/integration-$report_test_id.jsonl ]]

printf 'managed role read-only closure-view fixture passed\n'
