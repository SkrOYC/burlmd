#!/usr/bin/env bash
# The PATH-only host harness supplies Darwin observations; Pub, Flutter tests,
# and Cargo still use the real installed tools and the production launcher.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-cold-macos.XXXXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
bin=$tmp/bin; marker=$tmp/commands; mkdir -p "$bin"
real_uname=$(command -v uname); real_flutter=$(command -v flutter); real_cargo=$(command -v cargo)
cat >"$bin/uname" <<EOF
#!/usr/bin/env bash
if [[ \${BURLMD_MACOS_COLD_HOST:-} == 1 ]]; then [[ \${1:-} == -m ]] && printf 'arm64\\n' || printf 'Darwin\\n'; else exec "$real_uname" "\$@"; fi
EOF
cat >"$bin/sysctl" <<'EOF'
#!/usr/bin/env bash
case ${2:-} in machdep.cpu.brand_string) echo 'Apple M1 fixture';; hw.logicalcpu) echo 3;; hw.memsize) echo 7000000000;; *) exit 64;; esac
EOF
printf '#!/usr/bin/env bash\nprintf "ProductName:\\tmacOS\\nProductVersion:\\t26.0\\n"\n' >"$bin/sw_vers"
printf '#!/usr/bin/env bash\nprintf "fixture Flutter\\n"\n' >"$bin/head"
cat >"$bin/flutter" <<EOF
#!/usr/bin/env bash
m="$marker"; for v in GH_TOKEN GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN SSH_AUTH_SOCK AWS_SECRET_ACCESS_KEY; do [[ -z \${!v:-} ]] || exit 91; done; unset BURLMD_MACOS_COLD_HOST
case \${1:-} in
pub) [[ \${2:-} == get && " \$* " == *' --enforce-lockfile '* && " \$* " == *' --no-precompile '* && " \$* " == *' --no-example '* ]] || exit 92; echo pub-get >>"\$m"; exec "$real_flutter" "\$@";;
test) [[ " \$* " == *' --no-pub '* ]] || exit 93; echo flutter-no-pub >>"\$m"; exec "$real_flutter" test --no-pub --suppress-analytics test/widget_test.dart;;
*) printf 'fixture Flutter\n';; esac
EOF
cat >"$bin/cargo" <<EOF
#!/usr/bin/env bash
m="$marker"; for v in GH_TOKEN GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN SSH_AUTH_SOCK AWS_SECRET_ACCESS_KEY; do [[ -z \${!v:-} ]] || exit 94; done
case \${1:-} in fetch) [[ " \$* " == *' --locked '* ]] || exit 95; echo cargo-fetch-locked >>"\$m";; metadata) [[ " \$* " == *' --offline '* && " \$* " == *' --locked '* ]] || exit 96; echo cargo-metadata-offline >>"\$m";; esac
exec "$real_cargo" "\$@"
EOF
chmod +x "$bin"/*
source=$tmp/source; output=$tmp/output
git clone -q --no-local "$root" "$source"; sha=$(git -C "$source" rev-parse HEAD)
pub=$(sha256sum "$source/pubspec.lock" | awk '{print $1}'); cargo=$(sha256sum "$source/rust/Cargo.lock" | awk '{print $1}')
# Reuse the isolation fixture's canonical identity shape without binding this
# cold-path fixture to an incidental source line number.
awk '/^\{"ticketIdentity":"AST-H001"/ { print; exit }' "$root/scripts/test-managed-role-isolation.sh" | jq --arg sha "$sha" '
 .ticketIdentity="CI-M003" | .trustAnchorSha=$sha | .testedSourceSha=$sha | .workflowSignerSha=$sha | .baseSha=$sha |
 .requiredEvidenceClasses["linux-x86_64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","managed-evidence-isolation","generated-binding-check","static-analysis","desktop-integration"] |
 .requiredEvidenceClasses["macos-26-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"] |
 .requiredEvidenceClasses["macos-15-arm64"]=["common-functional","managed-evidence-protocol","managed-evidence-security","static-analysis","desktop-integration"]' >"$tmp/expected.json"
: >"$marker"
if ! env BURLMD_MACOS_COLD_HOST=1 ImageOS=fixture ImageVersion=fixture PATH="$bin:$PATH" EXPECTED_IDENTITY="$tmp/expected.json" "$root/scripts/run-managed-role.sh" macos-26-arm64 "$source" "$output" >"$tmp/role.log" 2>&1; then cat "$marker"; tail -n 80 "$tmp/role.log"; exit 1; fi
[[ $(sha256sum "$source/pubspec.lock" | awk '{print $1}') == "$pub" && $(sha256sum "$source/rust/Cargo.lock" | awk '{print $1}') == "$cargo" ]]
[[ $(rg -cx pub-get "$marker") == 1 && $(rg -cx cargo-fetch-locked "$marker") == 1 && $(rg -cx flutter-no-pub "$marker") -ge 3 && $(rg -cx cargo-metadata-offline "$marker") == 1 ]]
jq -e '([.[] | select(.id == "flutter-test" and .status == "passed")] | length == 1) and ([.[] | select(.id == "cargo-metadata" and .status == "passed")] | length == 1)' "$output/results/role-steps.json" >/dev/null
echo 'managed role cold macOS-checkout fixture passed'
