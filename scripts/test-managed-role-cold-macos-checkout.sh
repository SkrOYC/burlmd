#!/usr/bin/env bash
# The PATH-only host harness supplies Darwin observations; Pub, Flutter tests,
# and Cargo still use the real installed tools and the production launcher.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
# This fixture is intentionally invoked directly by the BURL-M003 local
# verification command.  Re-enter the pinned CI shell so the trusted role
# helper receives its locked protocol tools instead of ambient host PATH.
if [[ ${BURLMD_COLD_MACOS_LOCKED_SHELL:-} != 1 ]]; then
  exec "$root/scripts/ci-devenv.sh" env BURLMD_COLD_MACOS_LOCKED_SHELL=1 "$0" "$@"
fi

# The Linux fixture below models the macOS role's authority boundaries, but a
# Darwin runner must also exercise Cargokit's real native desktop build path.
# In particular, it proves the locked rustup shim advertises the native target
# that Cargokit asks for before Flutter compiles the macOS integration target.
if [[ $(uname) == Darwin ]]; then
  [[ ${GITHUB_ACTIONS:-} == true ]] || {
    echo 'native macOS fixture is restricted to a GitHub-hosted runner' >&2
    exit 2
  }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-native-macos.XXXXXXXX")
  trap '[[ ${BURLMD_KEEP_FIXTURE_TMP:-} == 1 ]] || rm -rf -- "$tmp"' EXIT
  source=$tmp/source
  git clone -q --no-local "$root" "$source"
  profile_fragment=$tmp/candidate-profile.sh
  awk '/^candidate_profile_tools\(\)/ { copy = 1 } /^candidate_command_executables\(\)/ { exit } copy { print }' "$root/scripts/run-managed-role.sh" >"$profile_fragment"
  # Import the production profile and recreate its restricted candidate PATH.
  # Native coverage must not accidentally exercise the developer shell.
  source "$profile_fragment"
  mapfile -t selected_tools < <(candidate_profile_tools BURL-M003 macos-26-arm64)
  candidate_path=$tmp/candidate-path
  mkdir -p "$candidate_path"
  for tool in "${selected_tools[@]}" bash sh env mkdir rm cp mv ln find grep sed awk sort head tail dirname basename readlink sleep perl tr cat ls xcrun xcodebuild clang clang++ ld libtool plutil lipo install_name_tool arch open; do
    tool_path=$(command -v "$tool") || { echo "native fixture missing production candidate tool: $tool" >&2; exit 1; }
    resolved=$(readlink -f "$tool_path") || exit 1
    ln -s "$resolved" "$candidate_path/$tool"
  done
  [[ -x $candidate_path/rustup ]] || { echo 'native fixture omitted the pinned rustup shim' >&2; exit 1; }
  [[ $(readlink "$candidate_path/open") == /usr/bin/open ]] || { echo 'native fixture did not pin open to /usr/bin/open' >&2; exit 1; }
  for forbidden in gh git actionlint taplo curl wget ssh shasum; do
    [[ ! -e $candidate_path/$forbidden ]] || { echo "native fixture exposed forbidden candidate tool: $forbidden" >&2; exit 1; }
  done
  env -i PATH="$candidate_path" HOME="$tmp/home" TMPDIR="$tmp/tmp" \
    XDG_CACHE_HOME="$tmp/xdg-cache" XDG_CONFIG_HOME="$tmp/xdg-config" XDG_DATA_HOME="$tmp/xdg-data" \
    PUB_CACHE="$tmp/pub-cache" CARGO_HOME="$tmp/cargo-home" RUSTUP_HOME="$tmp/rustup-home" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
    bash -ceu '
      cd -- "$1"
      expected=aarch64-apple-darwin
      rustup toolchain list | grep -Fx "stable-$expected (default)"
      rustup target list --toolchain stable --installed | grep -Fx "$expected"
      rustup run stable cargo --version >/dev/null
      flutter pub get --enforce-lockfile --no-precompile --no-example
      flutter test integration_test -d macos -r github
    ' cold-native-macos "$source"
  # The desktop integration invocation above stops before the role's final
  # manifest collector. Run the real hosted-role path too, so a native Darwin
  # runner proves filesystem capture reaches ci-role-evidence.json.
  sha=$(git -C "$source" rev-parse HEAD)
  awk '/^\{"ticketIdentity":"BURL-H001"/ { print; exit }' "$root/scripts/test-managed-role-isolation.sh" | jq --arg sha "$sha" '
   .ticketIdentity="BURL-M003" | .trustAnchorSha=$sha | .testedSourceSha=$sha | .workflowSignerSha=$sha | .baseSha=$sha |
   .requiredEvidenceClasses["linux-x86_64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"] |
   .requiredEvidenceClasses["macos-26-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"] |
   .requiredEvidenceClasses["macos-15-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]' >"$tmp/expected.json"
  env -u BURLMD_AUTHENTICATED_STAGE_ROOT \
    BURLMD_ROLE_RUNTIME_ROOT="$tmp/runtime-role-manifest" \
    ImageOS="${ImageOS:?ImageOS is required from the hosted macOS runner}" \
    ImageVersion="${ImageVersion:?ImageVersion is required from the hosted macOS runner}" \
    EXPECTED_IDENTITY="$tmp/expected.json" \
    "$root/scripts/run-managed-role.sh" macos-26-arm64 "$source" "$tmp/output-role-manifest"
  jq -e '.roleEvidence.environment.filesystem | strings | select(length > 0)' "$tmp/output-role-manifest/ci-role-evidence.json" >/dev/null
  echo 'managed role native macOS desktop and manifest fixture passed'
  exit 0
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-cold-macos.XXXXXXXX"); trap '[[ ${BURLMD_KEEP_FIXTURE_TMP:-} == 1 ]] || rm -rf -- "$tmp"' EXIT
bin=$tmp/bin; marker=$tmp/commands; mkdir -p "$bin"
real_uname=$(command -v uname); real_flutter=$(command -v flutter); real_cargo=$(command -v cargo)
env_bin=$(readlink -f "$(command -v env)")
sh_bin=$(readlink -f "$(command -v sh)")
[[ $env_bin == /nix/store/* ]] || { echo 'cold macOS fixture requires the locked env executable' >&2; exit 1; }
[[ $sh_bin == /nix/store/* ]] || { echo 'cold macOS fixture requires the locked sh executable' >&2; exit 1; }
cat >"$bin/uname" <<EOF
#!/usr/bin/env bash
if [[ \${BURLMD_MACOS_COLD_HOST:-} == 1 ]]; then [[ \${1:-} == -m ]] && printf 'arm64\\n' || printf 'Darwin\\n'; else exec "$real_uname" "\$@"; fi
EOF
cat >"$bin/sysctl" <<'EOF'
#!/usr/bin/env bash
case ${2:-} in machdep.cpu.brand_string) echo 'Apple M1 fixture';; hw.logicalcpu) echo 3;; hw.memsize) echo 7000000000;; *) exit 64;; esac
EOF
cat >"$bin/sw_vers" <<'EOF'
#!/usr/bin/env bash
case ${BURLMD_EXPECTED_DF_TARGET:-} in
  *output-macos-26) major=26;;
  *output-macos-15) major=15;;
  *) exit 64;;
esac
case ${1:-} in
  '') printf 'ProductName:\tmacOS\nProductVersion:\t%s.0\n' "$major";;
  -productVersion) [[ $# == 1 ]] || exit 64; printf '%s.0\n' "$major";;
  *) exit 64;;
esac
EOF
printf '#!/usr/bin/env bash\nprintf "fixture Flutter\\n"\n' >"$bin/head"
cat >"$bin/df" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  -P) [[ $# == 2 && ${2:-} == "${BURLMD_EXPECTED_DF_TARGET:?}" ]] || exit 64
      printf '%s\n' 'Filesystem 512-blocks Used Available Capacity Mounted on' '/dev/disk9s1 1000 100 900 10% /fixture-volume'
      printf 'df-posix:%s\n' "$2" >>"${BURLMD_DF_MARKER:?}"
      ;;
  -Pk) [[ $# == 2 && ${2:-} == "${BURLMD_EXPECTED_DF_TARGET:?}" ]] || exit 64
       printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' '/dev/disk9s1 500 50 450 10% /fixture-volume'
       ;;
  *) exit 64;;
esac
EOF
cat >"$bin/diskutil" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == info && ${2:-} == -plist && $# == 3 ]] || exit 64
[[ ${3:-} == /dev/disk9s1 ]] || exit 65
printf '%s\n' '<plist><dict><key>FilesystemType</key><string>fixturefs</string></dict></plist>'
EOF
cat >"$bin/plutil" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -extract && ${2:-} == FilesystemType && ${3:-} == raw && ${4:-} == -o && ${5:-} == - && ${6:-} == - ]] || exit 64
cat >/dev/null
printf 'fixturefs\n'
EOF
for native_tool in xcrun xcodebuild clang clang++ ld libtool lipo install_name_tool arch open; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/$native_tool"
done
cat >"$bin/flutter" <<EOF
#!/usr/bin/env bash
m="$marker"; for v in GH_TOKEN GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN SSH_AUTH_SOCK AWS_SECRET_ACCESS_KEY; do [[ -z \${!v:-} ]] || exit 91; done; unset BURLMD_MACOS_COLD_HOST
case \${1:-} in
pub)
  [[ \${2:-} == get && " \$* " == *' --enforce-lockfile '* && " \$* " == *' --no-precompile '* && " \$* " == *' --no-example '* ]] || exit 92
  for ((i = 1; i <= \$#; i++)); do if [[ \${!i} == --directory ]]; then j=\$((i + 1)); directory=\${!j}; fi; done
  [[ -n \${directory:-} && \$PWD == "\$directory" ]] || exit 97
  echo pub-get >>"\$m"
  exec "$real_flutter" "\$@"
  ;;
test)
  [[ " \$* " == *' --no-pub '* ]] || exit 93
  reporter=
  for argument in "\$@"; do
    case \$argument in --file-reporter=json:*) reporter=\${argument#--file-reporter=json:};; esac
  done
  if [[ " \$* " == *' -r github '* ]]; then [[ -n \$reporter ]] || exit 98; fi
  echo flutter-no-pub >>"\$m"
  "$real_flutter" test --no-pub --suppress-analytics test/widget_test.dart
  result=\$?
  if ((result == 0)); then
    printf '%s\\n' '{"type":"testDone","skipped":false,"hidden":false,"result":"success"}' '{"type":"done","success":true}' >"\$reporter"
  fi
  exit "\$result"
  ;;
*) printf 'fixture Flutter\n';; esac
EOF
cat >"$bin/cargo" <<EOF
#!/usr/bin/env bash
m="$marker"; for v in GH_TOKEN GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN SSH_AUTH_SOCK AWS_SECRET_ACCESS_KEY; do [[ -z \${!v:-} ]] || exit 94; done
case \${1:-} in fetch) [[ " \$* " == *' --locked '* ]] || exit 95; echo cargo-fetch-locked >>"\$m";; metadata) [[ " \$* " == *' --offline '* && " \$* " == *' --locked '* ]] || exit 96; echo cargo-metadata-offline >>"\$m";; esac
exec "$real_cargo" "\$@"
EOF
chmod +x "$bin"/*
source=$tmp/source
git clone -q --no-local "$root" "$source"; sha=$(git -C "$source" rev-parse HEAD)
signer_sha=$(git -C "$root" rev-parse HEAD)
signer_git_common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
signer_git_parent=${signer_git_common%/*}
[[ $signer_git_common == /* && -d $signer_git_common && ! -L $signer_git_common && $signer_git_parent == /* && -d $signer_git_parent && ! -L $signer_git_parent ]] || {
  echo 'cold macOS fixture requires the trusted checkout common Git directory' >&2
  exit 1
}
# Keep the fixture command doubles under the disposable tested checkout. The
# production launcher admits only locked tools or fixture-local doubles; it
# must never grant the surrounding host PATH to a macOS candidate.
cp -a "$bin" "$source/fixture-bin"
pub=$(sha256sum "$source/pubspec.lock" | awk '{print $1}'); cargo=$(sha256sum "$source/rust/Cargo.lock" | awk '{print $1}')
# Reuse the isolation fixture's canonical identity shape without binding this
# cold-path fixture to an incidental source line number.
awk '/^\{"ticketIdentity":"BURL-H001"/ { print; exit }' "$root/scripts/test-managed-role-isolation.sh" | jq --arg sha "$sha" --arg signer "$signer_sha" '
 .ticketIdentity="BURL-M003" | .trustAnchorSha=$sha | .testedSourceSha=$sha | .workflowSignerSha=$signer | .baseSha=$sha |
 (.requiredRoleSigners[] | .jobWorkflowSha) = $signer |
 .requiredEvidenceClasses["linux-x86_64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"] |
 .requiredEvidenceClasses["macos-26-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"] |
 .requiredEvidenceClasses["macos-15-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]' >"$tmp/expected.json"
: >"$marker"
# The production launcher intentionally calls the macOS filesystem APIs by
# their absolute paths. A Linux local fixture cannot replace those through
# PATH, so build a minimal transient root around the locked Nix store and bind
# deterministic fixtures only at those two paths. The source, output, and
# runtime roots remain the ordinary disjoint production roots; this does not
# introduce a launcher bypass or expose a writable host root.
run_cold_macos_role() {
  local role=$1 output=$2 log=$3
  if ! env -u BURLMD_AUTHENTICATED_STAGE_ROOT BURLMD_MACOS_COLD_HOST=1 BURLMD_ROLE_RUNTIME_ROOT="$tmp/runtime-$role" BURLMD_EXPECTED_DF_TARGET="$output" BURLMD_DF_MARKER="$marker" ImageOS=fixture ImageVersion=fixture PATH="$source/fixture-bin:$PATH" EXPECTED_IDENTITY="$tmp/expected.json" \
    bwrap --die-with-parent --tmpfs / --proc /proc --dev /dev --ro-bind /nix /nix --ro-bind /etc /etc \
      --dir /home --dir /home/oscar --dir /home/oscar/GitHub --dir "$signer_git_parent" --ro-bind "$root" "$root" --ro-bind "$signer_git_common" "$signer_git_common" \
      --dir /tmp --bind "$tmp" "$tmp" --dir /bin --ro-bind "$sh_bin" /bin/sh --dir /usr --dir /usr/bin --dir /usr/sbin \
      --ro-bind "$env_bin" /usr/bin/env --ro-bind "$bin/open" /usr/bin/open --ro-bind "$bin/df" /bin/df --ro-bind "$bin/diskutil" /usr/sbin/diskutil --ro-bind "$bin/plutil" /usr/bin/plutil \
      "$root/scripts/run-managed-role.sh" "$role" "$source" "$output" >"$log" 2>&1; then
    cat "$marker"
    tail -n 80 "$log"
    return 1
  fi
}

run_cold_macos_role macos-26-arm64 "$tmp/output-macos-26" "$tmp/role-macos-26.log"
# BURL-M003 has no authenticated producer stage. Its macOS 15 candidate must
# launch with the stage-root variable absent, rather than pointing it at an
# uncreated runner-temp directory.
run_cold_macos_role macos-15-arm64 "$tmp/output-macos-15" "$tmp/role-macos-15.log"
[[ ! -e $tmp/authenticated-input ]] || { echo 'no-stage macOS 15 fixture created an authenticated input root' >&2; exit 1; }
[[ $(rg -c '^df-posix:' "$marker") == 2 ]] || { echo 'macOS fixture did not resolve each output root with df -P' >&2; exit 1; }
[[ $(sha256sum "$source/pubspec.lock" | awk '{print $1}') == "$pub" && $(sha256sum "$source/rust/Cargo.lock" | awk '{print $1}') == "$cargo" ]]
[[ $(rg -cx pub-get "$marker") == 2 && $(rg -cx cargo-fetch-locked "$marker") == 2 && $(rg -cx flutter-no-pub "$marker") -ge 6 && $(rg -cx cargo-metadata-offline "$marker") == 2 ]]
for output in "$tmp/output-macos-26" "$tmp/output-macos-15"; do
  jq -e '([.[] | select(.id == "flutter-test" and .status == "passed")] | length == 1) and ([.[] | select(.id == "cargo-metadata" and .status == "passed")] | length == 1)' "$output/results/role-steps.json" >/dev/null
  for json_log in "$output"/results/integration-*.jsonl; do
    jq -se '
      [ .[] | select(.type == "testDone") ] as $tests |
      [ .[] | select(.type == "done") ] as $done |
      ($tests | length) > 0 and
      ($tests | map(select(.hidden == false)) | length) > 0 and
      ($done | length) == 1 and $done[0].success == true and
      all($tests[]; .skipped == false and .result == "success")
    ' "$json_log" >/dev/null
  done
done
# The real launcher constructs this candidate PATH. Verify the resulting
# executable inventory rather than relying on a source-pattern assertion: no
# authenticated client, VCS, linter, TOML parser, or ambient network client is
# reachable from either macOS candidate.
for role in macos-26 macos-15; do
  inventory="$tmp/output-$role/candidate-environment/tool-path"
  [[ -d $inventory ]] || { echo "macOS candidate inventory is absent: $role" >&2; exit 1; }
  # `shasum` fingerprints a BURL-O001 authenticated stage in the trusted
  # wrapper. BURL-M003 has no stage, and candidate commands never invoke it,
  # so it must not be granted to this role merely because the wrapper uses it.
  for forbidden in gh git actionlint taplo curl wget ssh shasum; do
    [[ ! -e $inventory/$forbidden ]] || { echo "macOS candidate inherited forbidden tool: $forbidden" >&2; exit 1; }
  done
  # The launcher already checked `open` was executable while the Bubblewrap
  # namespace was live. Its inventory entry points at /usr/bin/open, which is
  # absent on the Linux host after teardown, so do not dereference it here.
  for required in cargo rustc rustup dart env flutter perl tr cat ls xcrun xcodebuild clang clang++ ld libtool plutil lipo install_name_tool arch; do
    [[ -x $inventory/$required ]] || { echo "macOS candidate missed required locked tool: $required" >&2; exit 1; }
  done
  [[ $(readlink "$inventory/open") == /usr/bin/open ]] || { echo "macOS candidate did not pin open to /usr/bin/open: $role" >&2; exit 1; }
done
echo 'managed role cold macOS-checkout fixture passed'
