#!/usr/bin/env bash
# Exercise the production Linux candidate boundary from a fresh disposable
# checkout. This deliberately uses the real locked Flutter/Dart/Cargo tools;
# command doubles would not expose a missing cache, interpreter, or namespace
# mount. Run it through scripts/ci-devenv.sh.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-role-cold.XXXXXXXX")
sway_pid=
trap '[[ -z $sway_pid ]] || { kill "$sway_pid" 2>/dev/null || true; wait "$sway_pid" 2>/dev/null || true; }; rm -rf -- "$scratch"' EXIT
git clone -q --no-local "$root" "$scratch/source"
source_root=$scratch/source
prepared=$scratch/prepared
writable=$scratch/writable
mkdir -p "$prepared"/{home,pub-cache,cargo-home} "$writable"/{dart-tool,build,cargo-target,pub-active-roots,linux-flutter-ephemeral,l10n-generated,rust-builder-cargokit} \
  "$scratch"/{home,tmp,gh,xdg/{cache,config,data,state}}

# This is the same credential-free, lock-enforced prefetch surface used by the
# role launcher. The installed Flutter 3.44.3/Dart 3.12.2 help documents all
# three flags; Cargo 1.97.1 documents `fetch --locked`.
pub_before=$(sha256sum "$source_root/pubspec.lock" | awk '{print $1}')
cargo_before=$(sha256sum "$source_root/rust/Cargo.lock" | awk '{print $1}')
cargokit_pub_before=$(sha256sum "$source_root/rust_builder/cargokit/build_tool/pubspec.lock" | awk '{print $1}')
env -i PATH="$PATH" HOME="$prepared/home" TMPDIR="$scratch/tmp" \
  XDG_CACHE_HOME="$prepared/home/xdg-cache" XDG_CONFIG_HOME="$prepared/home/xdg-config" XDG_DATA_HOME="$prepared/home/xdg-data" \
  PUB_CACHE="$prepared/pub-cache" CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
  flutter pub get --enforce-lockfile --no-precompile --no-example --directory "$source_root"
[[ $(sha256sum "$source_root/pubspec.lock" | awk '{print $1}') == "$pub_before" ]]
# The Cargokit Linux plugin runs a separately locked Dart build tool while
# Ninja builds the Rust library. Populate that exact cache before Bubblewrap
# removes network access; the root Flutter package lock does not include it.
env -i PATH="$PATH" HOME="$prepared/home" TMPDIR="$scratch/tmp" \
  XDG_CACHE_HOME="$prepared/home/xdg-cache" XDG_CONFIG_HOME="$prepared/home/xdg-config" XDG_DATA_HOME="$prepared/home/xdg-data" \
  PUB_CACHE="$prepared/pub-cache" CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
  dart pub get --enforce-lockfile --no-precompile --no-example --directory "$source_root/rust_builder/cargokit/build_tool"
[[ $(sha256sum "$source_root/rust_builder/cargokit/build_tool/pubspec.lock" | awk '{print $1}') == "$cargokit_pub_before" ]]
env -i PATH="$PATH" HOME="$prepared/home" TMPDIR="$scratch/tmp" \
  CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
  cargo fetch --locked --manifest-path "$source_root/rust/Cargo.toml"
[[ $(sha256sum "$source_root/rust/Cargo.lock" | awk '{print $1}') == "$cargo_before" ]]

# Establish the control case before namespace preparation: the exact locked
# Flutter toolchain, disposable checkout, and owned PUB_CACHE must pass
# `--no-pub` while those paths are still visible at their host locations.
# The following namespace run uses the same generated package config/cache
# after remapping only that host cache prefix to its private mount point.
mkdir -p "$prepared/pub-cache/active_roots"
env -i PATH="$PATH" HOME="$scratch/home" TMPDIR="$scratch/tmp" \
  XDG_CACHE_HOME="$scratch/home/xdg-cache" XDG_CONFIG_HOME="$scratch/home/xdg-config" XDG_DATA_HOME="$scratch/home/xdg-data" \
  PUB_CACHE="$prepared/pub-cache" CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$scratch/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
  "$(command -v bash)" -ceu 'cd -- "$1"; flutter test --no-pub --suppress-analytics test/widget_test.dart' cold-role-outside "$source_root"

cp -a -- "$source_root/.dart_tool/." "$writable/dart-tool/"
host_pub_cache_uri="file://$prepared/pub-cache"
sandbox_pub_cache_uri='file:///candidate/prepared/pub-cache'
jq --arg host "$host_pub_cache_uri" --arg sandbox "$sandbox_pub_cache_uri" '
  def remap:
    if type == "string" and startswith($host)
    then $sandbox + .[($host | length):]
    elif type == "array" then map(remap)
    elif type == "object" then with_entries(.value |= remap)
    else .
    end;
  remap
' "$writable/dart-tool/package_config.json" >"$writable/dart-tool/package_config.json.next"
mv -- "$writable/dart-tool/package_config.json.next" "$writable/dart-tool/package_config.json"
! rg -F -- "$prepared/pub-cache" "$writable/dart-tool/package_config.json"
rm -rf -- "$source_root/.dart_tool"
mkdir -p "$source_root/.dart_tool" "$source_root/build"
cp -a -- "$source_root" "$scratch/generated-check"
rm -rf -- "$scratch/generated-check/.dart_tool"
mkdir -p "$scratch/generated-check/.dart_tool"
cp -a -- "$writable/dart-tool/." "$scratch/generated-check/.dart_tool/"
cp -a -- "$source_root/linux/flutter/ephemeral/." "$writable/linux-flutter-ephemeral/"
cp -a -- "$source_root/lib/l10n/generated/." "$writable/l10n-generated/"
cp -a -- "$source_root/rust_builder/cargokit/." "$writable/rust-builder-cargokit/"
while IFS= read -r -d '' link; do
  target=$(readlink "$link") || exit 1
  case $target in
    "$source_root"/*) ln -sfn "/source/${target#"$source_root/"}" "$link";;
    "$prepared/pub-cache"/*) ln -sfn "/candidate/prepared/pub-cache/${target#"$prepared/pub-cache/"}" "$link";;
  esac
done < <(find "$writable/linux-flutter-ephemeral" -type l -print0)

# Cargokit normally creates this runner during Ninja and calls `dart pub get`
# without --offline. Build its exact generated cache now, then record the
# upstream hash sentinel so the network-less namespace only reuses it.
cargokit_tool="$writable/build/linux/x64/debug/plugins/rust/cargokit_build/tool"
cargokit_build_tool="$writable/rust-builder-cargokit/build_tool"
mkdir -p "$cargokit_tool/bin"
printf '%s\n' \
  'name: build_tool_runner' \
  'version: 1.0.0' \
  'publish_to: none' \
  '' \
  'environment:' \
  "  sdk: '>=3.0.0 <4.0.0'" \
  '' \
  'dependencies:' \
  '  build_tool:' \
  "    path: \"$cargokit_build_tool\"" \
  >"$cargokit_tool/pubspec.yaml"
printf '%s\n' \
  "import 'package:build_tool/build_tool.dart' as build_tool;" \
  'void main(List<String> args) {' \
  '  build_tool.runMain(args);' \
  '}' \
  >"$cargokit_tool/bin/build_tool_runner.dart"
env -i PATH="$PATH" HOME="$prepared/home" TMPDIR="$scratch/tmp" \
  XDG_CACHE_HOME="$prepared/home/xdg-cache" XDG_CONFIG_HOME="$prepared/home/xdg-config" XDG_DATA_HOME="$prepared/home/xdg-data" \
  PUB_CACHE="$prepared/pub-cache" CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
  dart pub get --offline --no-precompile --no-example --directory "$cargokit_tool"
env -i PATH="$PATH" HOME="$prepared/home" TMPDIR="$scratch/tmp" \
  XDG_CACHE_HOME="$prepared/home/xdg-cache" XDG_CONFIG_HOME="$prepared/home/xdg-config" XDG_DATA_HOME="$prepared/home/xdg-data" \
  PUB_CACHE="$prepared/pub-cache" CARGO_HOME="$prepared/cargo-home" RUSTUP_HOME="$prepared/home/rustup" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
  dart compile kernel "$cargokit_tool/bin/build_tool_runner.dart"
# Match Cargokit's later /source-visible directory headings exactly.
printf '%s\n' "$(LC_ALL=C TZ=UTC ls -lR --full-time --numeric-uid-gid "$cargokit_build_tool" |
  sed -e "s|$writable/rust-builder-cargokit|/source/rust_builder/cargokit|g" \
      -e "s/ $(stat -c '%u' "$cargokit_build_tool") $(stat -c '%g' "$cargokit_build_tool") / 0 0 /g" |
  sha1sum)" >"$cargokit_tool/.package_hash"

# Use the same private headless Linux desktop boundary as the managed role.
# The integration command below must exercise a real Linux desktop target, not
# merely a host-side widget test.
sway_runtime="$scratch/sway-runtime"
mkdir -p "$sway_runtime"; chmod 700 "$sway_runtime"
XDG_RUNTIME_DIR="$sway_runtime" WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 \
  sway --unsupported-gpu >"$scratch/sway.log" 2>&1 &
sway_pid=$!
for _ in $(seq 1 100); do
  for socket in "$sway_runtime"/wayland-*; do [[ -S $socket ]] && { sway_display=${socket##*/}; break 2; }; done
  kill -0 "$sway_pid" 2>/dev/null || break
  sleep 0.1
done
[[ -n ${sway_display:-} ]] || { tail -n 80 "$scratch/sway.log" >&2 || true; exit 1; }
sway_socket="$sway_runtime/sway-ipc.$(id -u).$sway_pid.sock"
[[ -S $sway_socket ]] || { tail -n 80 "$scratch/sway.log" >&2 || true; exit 1; }
SWAYSOCK="$sway_socket" \
  swaymsg output HEADLESS-1 mode 1920x1080@60Hz >"$scratch/sway-mode.log" 2>&1
sway_outputs=$(SWAYSOCK="$sway_socket" swaymsg -t get_outputs -r)
jq -e '
  length == 1 and .[0].rect.width == 1920 and .[0].rect.height == 1080 and
  (.[] | .current_mode.refresh // 0) == 60000
' <<<"$sway_outputs" >/dev/null

tools=(
  bash sh env mkdir mktemp chmod install cp mv rm cmp flock
  awk sed grep rg sort sha256sum wc find tar zstd
  flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup ip
  git nix nix-store cmake ninja pkg-config clang openssl
  bwrap jq taplo check-jsonschema getconf df ps sleep setsid perl timeout
  readlink uname tr head
)
declare -a roots=() closure_paths=() path_entries=() bwrap_args=()
env_interpreter=
for tool in "${tools[@]}"; do
  executable=$(readlink -f "$(command -v "$tool")")
  [[ $executable == /nix/store/* ]] || { echo "unlocked cold-fixture tool: $tool ($executable)" >&2; exit 1; }
  entry=${executable#/nix/store/}
  roots+=("/nix/store/${entry%%/*}")
  path_entries+=("$(dirname "$executable")")
  [[ $tool == env ]] && env_interpreter=$executable
done
mapfile -t closure_paths < <(for entry in "${roots[@]}"; do nix-store -qR "$entry"; done | LC_ALL=C sort -u)
openssl_pkgconfig=$(pkg-config --variable=pcfiledir openssl)
[[ $openssl_pkgconfig == /nix/store/* && -d $openssl_pkgconfig ]]
openssl_include=$(pkg-config --variable=includedir openssl)
openssl_lib=$(pkg-config --variable=libdir openssl)
[[ $openssl_include == /nix/store/* && -d $openssl_include && $openssl_lib == /nix/store/* && -d $openssl_lib ]]
opengl_driver=$(readlink -f /run/opengl-driver)
[[ $opengl_driver == /nix/store/* && -d $opengl_driver/lib/dri && -f $opengl_driver/share/glvnd/egl_vendor.d/50_mesa.json ]]
openssl_entry=${openssl_pkgconfig#/nix/store/}
mapfile -t closure_paths < <(
  { printf '%s\n' "${closure_paths[@]}"; nix-store -qR "/nix/store/${openssl_entry%%/*}"; nix-store -qR "${openssl_include%/include}"; nix-store -qR "${openssl_lib%/lib}"; nix-store -qR "$opengl_driver"; } | LC_ALL=C sort -u
)
mapfile -t path_entries < <(printf '%s\n' "${path_entries[@]}" | LC_ALL=C sort -u)
for entry in "${closure_paths[@]}"; do bwrap_args+=(--ro-bind "$entry" "$entry"); done
path=$(IFS=:; printf '%s' "${path_entries[*]}")
locked_closure=$(IFS=:; printf '%s' "${closure_paths[*]}")
bash_bin=$(command -v bash)
bwrap_bin=$(command -v bwrap)

# /source is read-only, including Git control files. Flutter and Cargo receive
# only explicit writable generated/output roots, while their prepared caches
# are an overlapping read-only mount. Both trusted helpers execute via the
# locked Bash path, never their `/usr/bin/env` shebang.
env -i PATH="$path" HOME="$scratch/home" TMPDIR="$scratch/tmp" \
  "$bwrap_bin" --unshare-all --unshare-user --uid 0 --gid 0 --unshare-net --cap-add CAP_NET_ADMIN --die-with-parent --new-session --clearenv \
  --setenv PATH "$path" --setenv HOME /candidate/home --setenv TMPDIR /candidate/tmp \
  --setenv PUB_CACHE /candidate/prepared/pub-cache --setenv CARGO_HOME /candidate/prepared/cargo-home \
  --setenv CARGO_TARGET_DIR /candidate/writable/cargo-target --setenv RUSTUP_HOME /candidate/home/rustup \
  --setenv CARGO_INCREMENTAL 0 --setenv CARGO_PROFILE_DEV_DEBUG 0 --setenv CARGO_PROFILE_TEST_DEBUG 0 \
  --setenv PKG_CONFIG_PATH "$openssl_pkgconfig" --setenv LIBCLANG_PATH "$LIBCLANG_PATH" --setenv NIX_CFLAGS_COMPILE "-isystem $openssl_include" --setenv NIX_LDFLAGS "-L$openssl_lib" --setenv CFLAGS "-isystem $openssl_include" --setenv LDFLAGS "-L$openssl_lib" \
  --setenv RUSTFLAGS "-L native=$openssl_lib" \
  --setenv LIBGL_DRIVERS_PATH /run/opengl-driver/lib/dri --setenv __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json \
  --setenv BURLMD_LOCKED_NIX_CLOSURE "$locked_closure" \
  --setenv BURLMD_TRUSTED_BASH "$bash_bin" \
  --setenv XDG_CACHE_HOME /candidate/xdg/cache --setenv XDG_CONFIG_HOME /candidate/xdg/config --setenv XDG_DATA_HOME /candidate/xdg/data --setenv XDG_STATE_HOME /candidate/xdg/state --setenv GH_CONFIG_DIR /candidate/gh \
  --setenv XDG_RUNTIME_DIR /sway-runtime --setenv WAYLAND_DISPLAY "$sway_display" --setenv SWAYSOCK "/sway-runtime/${sway_socket##*/}" \
  --setenv GIT_CONFIG_NOSYSTEM 1 --setenv GIT_CONFIG_GLOBAL /dev/null --setenv GIT_CONFIG_COUNT 0 --setenv GIT_TERMINAL_PROMPT 0 \
  --proc /proc --dev /dev --tmpfs /tmp --dir /nix --dir /nix/store --dir /usr --dir /usr/bin \
  --dir /source --ro-bind "$source_root" /source \
  --dir /run --ro-bind "$opengl_driver" /run/opengl-driver \
  --dir /sway-runtime --bind "$sway_runtime" /sway-runtime \
  --dir /checker --bind "$scratch/generated-check" /checker \
  --dir /candidate --dir /candidate/xdg --dir /candidate/writable \
  --bind "$scratch/home" /candidate/home --bind "$scratch/tmp" /candidate/tmp \
  --dir /candidate/xdg/cache --dir /candidate/xdg/config --dir /candidate/xdg/data --dir /candidate/xdg/state \
  --bind "$scratch/xdg/cache" /candidate/xdg/cache --bind "$scratch/xdg/config" /candidate/xdg/config \
  --bind "$scratch/xdg/data" /candidate/xdg/data --bind "$scratch/xdg/state" /candidate/xdg/state \
  --bind "$scratch/gh" /candidate/gh --bind "$writable" /candidate/writable \
  --dir /candidate/prepared --ro-bind "$prepared" /candidate/prepared \
  --dir /trusted --ro-bind "$root" /trusted \
  --ro-bind "$env_interpreter" /usr/bin/env \
  --bind "$writable/dart-tool" /source/.dart_tool --bind "$writable/build" /source/build --bind "$writable/l10n-generated" /source/lib/l10n/generated --ro-bind "$writable/rust-builder-cargokit" /source/rust_builder/cargokit --bind "$writable/rust-builder-cargokit/run_build_tool.sh" /source/rust_builder/cargokit/run_build_tool.sh --bind "$writable/linux-flutter-ephemeral" /source/linux/flutter/ephemeral --bind "$writable/pub-active-roots" /candidate/prepared/pub-cache/active_roots \
  "${bwrap_args[@]}" --chdir /source "$bash_bin" -ceu '
    test ! -w /source/pubspec.lock
    test ! -w /source/.git/HEAD
    test ! -e /candidate/source
    test -w /source/.dart_tool
    test -w /source/build
    test -w /source/lib/l10n/generated
    test -w /source/linux/flutter/ephemeral
    test -w /source/rust_builder/cargokit/run_build_tool.sh
    test ! -w /source/rust_builder/cargokit/build_tool/pubspec.yaml
    test ! -w /source/rust_builder/cargokit/build_tool/lib/build_tool.dart
    test ! -w /candidate/prepared/pub-cache
    test -w /candidate/prepared/pub-cache/active_roots
    test ! -w /candidate/prepared/cargo-home
    ip link set lo up
    ip -4 addr show dev lo | rg -q "inet 127.0.0.1/8"
    ! ip route show default | grep -q .
    # These cover a numeric external TCP endpoint and a DNS-dependent one.
    # The private loopback route remains available only for the Flutter local
    # VM-service connection during the Linux desktop integration run below.
    ! (exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null
    ! (exec 3<>/dev/tcp/example.com/443) 2>/dev/null
    "$BURLMD_TRUSTED_BASH" /trusted/scripts/check-generated-bindings.sh --root /checker
    flutter test --no-pub --suppress-analytics test/widget_test.dart
    set +e
    timeout --preserve-status 900 flutter test --no-pub --suppress-analytics integration_test/production_host_flow_test.dart -d linux -r github
    integration_status=$?
    set -e
    if (( integration_status != 0 )); then
      if [[ $integration_status == 124 || $integration_status == 143 ]]; then
        printf "bounded Linux desktop integration timeout (status=%s)\\n" "$integration_status" >&2
      fi
      exit "$integration_status"
    fi
    # The precompiled Cargokit runner is a build-only helper. Remove it before
    # analysis so Dart does not inspect its private path dependency as project
    # source; the immutable Cargokit tree and prepared Pub cache remain intact.
    rm -rf -- /source/build/linux/x64/debug/plugins/rust/cargokit_build/tool
    dart --suppress-analytics analyze
    cargo metadata --offline --locked --manifest-path /source/rust/Cargo.toml --format-version 1 >/candidate/writable/cargo-metadata.json
    cargo test --offline --locked --manifest-path /source/rust/Cargo.toml --lib okf::concept_id
  '

"$bash_bin" "$root/scripts/assert-managed-evidence-isolation.sh" --contract "$root/.constitution/tech-spec/contracts/provisional-spikes.toml" --sandbox bubblewrap --expected-version 0.11.2

printf 'managed role cold-checkout fixture passed\n'
