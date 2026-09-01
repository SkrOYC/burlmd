#!/usr/bin/env bash
# Static CI contract checks. Deliberately conservative: a missing invariant fails.
set -euo pipefail
workflow= role_schema= aggregate_schema=
declare -a runners=()
while (($#)); do
  case $1 in
    --workflow) workflow=$2; shift 2;;
    --require-runner) runners+=("$2"); shift 2;;
    --require-role-schema) role_schema=$2; shift 2;;
    --require-aggregate-schema) aggregate_schema=$2; shift 2;;
    *) echo "usage: $0 --workflow PATH --require-runner LABEL ... --require-role-schema PATH --require-aggregate-schema PATH" >&2; exit 2;;
  esac
done
[[ -n $workflow && -f $workflow && -f $role_schema && -f $aggregate_schema ]] || exit 2
for runner in "${runners[@]}"; do rg -Fq "runs-on: $runner" .github/workflows || { echo "missing required runner: $runner" >&2; exit 1; }; done
for role in linux-x86-64 macos-26-arm64 macos-15-arm64; do
  case $role in linux-x86-64) role_id=linux-x86_64;; *) role_id=$role;; esac
  file=".github/workflows/ci-role-$role.yml"
  [[ -f $file ]] || { echo "missing $file" >&2; exit 1; }
  rg -q '^  candidate:$' "$file" && rg -q '^  seal:$' "$file" || { echo "$file must expose exactly candidate and seal" >&2; exit 1; }
  [[ $(sed -n '/^jobs:/,$p' "$file" | rg -c '^  [a-zA-Z0-9_-]+:$') -eq 2 ]] || { echo "$file has unexpected jobs" >&2; exit 1; }
  rg -q 'needs: candidate' "$file" || { echo "$file seal must need candidate" >&2; exit 1; }
  [[ $(rg -Fc 'uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' "$file") -eq $(rg -Fc 'persist-credentials: false' "$file") ]] || { echo "$file must disable credentials on every checkout" >&2; exit 1; }
  rg -Fq 'job.check_run_id' "$file" || { echo "$file receipt must use job.check_run_id" >&2; exit 1; }
  rg -Fq "managed-evidence-seal-receipt-$role_id-" "$file" || { echo "$file must upload its separate receipt" >&2; exit 1; }
  rg -Fq 'validate-managed-role-bundle.sh' "$file" || { echo "$file must validate its candidate bundle in seal" >&2; exit 1; }
  (rg -Fq 'permissions: {contents: read}' "$file" || rg -Uq 'permissions:\n      contents: read' "$file") || { echo "$file candidate permissions must be contents read only" >&2; exit 1; }
  rg -Fq 'permissions: {actions: read, contents: read, id-token: write, attestations: write}' "$file" || { echo "$file seal permissions mismatch" >&2; exit 1; }
  rg -Fq 'overwrite: false' "$file" || { echo "$file must use immutable artifact upload" >&2; exit 1; }
  candidate_block=$(sed -n '/^  candidate:/,/^  seal:/p' "$file")
  seal_block=$(sed -n '/^  seal:/,$p' "$file")
  # Candidate commands execute only through the credential-scrubbing launcher.
  # The following upload action belongs to the trusted workflow wrapper, but
  # its bytes remain untrusted until the distinct fresh seal job validates them.
  grep -Fq 'Run candidate as credential-free data' <<<"$candidate_block" || { echo "$file candidate launcher missing" >&2; exit 1; }
  grep -Fq './scripts/run-managed-role.sh' <<<"$candidate_block" || { echo "$file candidate does not use the trusted launcher" >&2; exit 1; }
  grep -Fq 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' <<<"$candidate_block" || { echo "$file candidate wrapper cannot upload the untrusted handoff" >&2; exit 1; }
  if grep -Fq 'GH_TOKEN:' <<<"$candidate_block"; then
    echo "$file candidate must not receive the GitHub API token" >&2
    exit 1
  fi
  if grep -Eq 'id-token:[[:space:]]*write|attestations:[[:space:]]*write|actions:[[:space:]]*read' <<<"$candidate_block"; then
    echo "$file candidate command job has provenance or Actions authority" >&2
    exit 1
  fi
  grep -Fq 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' <<<"$seal_block" || { echo "$file fresh seal lacks sole attestation authority" >&2; exit 1; }
  grep -Fq 'validate-managed-role-bundle.sh' <<<"$seal_block" || { echo "$file fresh seal lacks untrusted handoff validation" >&2; exit 1; }
  grep -Fq 'Authenticate candidate job and artifact before authority' <<<"$seal_block" || { echo "$file must authenticate the candidate before using seal authority" >&2; exit 1; }
  grep -Fq 'GH_TOKEN: ${{ github.token }}' <<<"$seal_block" || { echo "$file trusted seal API checks require an explicit token" >&2; exit 1; }
  grep -Fq 'EXPECTED_IDENTITY_FILE: ${{ steps.validated.outputs.expected_identity_file }}' <<<"$seal_block" || { echo "$file must REST-validate against the locally validated identity" >&2; exit 1; }
  [[ $(rg -Fc -- '--phase candidate' "$file") -eq 1 && $(rg -Fc -- '--phase sealed' "$file") -eq 1 ]] || { echo "$file must precheck and recheck REST objects" >&2; exit 1; }
  precheck_line=$(rg -n -F 'Authenticate candidate job and artifact before authority' "$file" | cut -d: -f1)
  attest_line=$(rg -n -F 'uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' "$file" | head -n1 | cut -d: -f1)
  sealed_upload_line=$(rg -n -F 'id: upload_sealed' "$file" | cut -d: -f1)
  [[ $precheck_line -lt $attest_line && $precheck_line -lt $sealed_upload_line ]] || { echo "$file must precheck before attestation or sealed upload" >&2; exit 1; }
  if grep -Fq './scripts/run-managed-role.sh' <<<"$seal_block"; then
    echo "$file seal must never execute candidate bytes" >&2
    exit 1
  fi
done
rg -Fq './.github/workflows/ci-role-linux-x86-64.yml' "$workflow"
rg -Fq './.github/workflows/ci-role-macos-26-arm64.yml' "$workflow"
rg -Fq './.github/workflows/ci-role-macos-15-arm64.yml' "$workflow"
rg -Fq 'workflow_dispatch:' "$workflow"
rg -Fq 'permissions: {}' "$workflow"
rg -Fq 'needs: expected' "$workflow"
[[ $(rg -Fc 'uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' "$workflow") -eq $(rg -Fc 'persist-credentials: false' "$workflow") ]] || { echo "$workflow must disable credentials on every checkout" >&2; exit 1; }
rg -Fq './scripts/validate-managed-workflow-inputs.sh' "$workflow" || { echo "$workflow must validate canonical expected identity before fan-out" >&2; exit 1; }
[[ -x scripts/validate-managed-workflow-inputs.sh && -x scripts/stage-authenticated-role-bundle.sh && -x scripts/validate-authenticated-stage-producer.sh ]] || { echo 'trusted workflow helpers must be executable' >&2; exit 1; }
if rg -n 'run:.*\$\{\{[[:space:]]*inputs\.' .github/workflows >/dev/null; then
  echo 'a workflow interpolates a dispatcher input directly into a shell command' >&2
  exit 1
fi
rg -Fq 'stage_macos_26_for_15:' "$workflow" || { echo 'missing authenticated macOS producer staging job' >&2; exit 1; }
rg -Fq 'needs: [expected, macos_26, stage_macos_26_for_15]' "$workflow" || { echo 'macOS 15 must wait for macOS 26 staging' >&2; exit 1; }
rg -Fq 'gh attestation verify' "$workflow" || { echo 'macOS producer staging must verify attestation' >&2; exit 1; }
rg -Fq 'validate-authenticated-stage-producer.sh' "$workflow" || { echo 'macOS producer staging must authenticate jobs and REST artifacts' >&2; exit 1; }
rg -Fq 'managed-evidence-seal-receipt-macos-26-arm64-' "$workflow" || { echo 'macOS producer staging must fetch the separate receipt' >&2; exit 1; }
rg -Fq 'SkrOYC/burlmd/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master' "$workflow" || { echo 'macOS producer staging must pin the exact signer workflow path' >&2; exit 1; }
rg -Fq -- '--signer-digest "$SIGNER_SHA"' "$workflow" || { echo 'macOS producer staging must pin the signer digest from expected identity' >&2; exit 1; }
rg -Fq 'candidate_check_run_id' "$workflow" || { echo 'macOS producer staging must receive the candidate check-run locator' >&2; exit 1; }
rg -Fq 'sealing_check_run_id' "$workflow" || { echo 'macOS producer staging must receive the sealing check-run locator' >&2; exit 1; }
stage_block=$(sed -n '/^  stage_macos_26_for_15:/,/^  macos_15:/p' "$workflow")
[[ $(grep -Fc 'GH_TOKEN: ${{ github.token }}' <<<"$stage_block") -eq 3 ]] || { echo 'PKG producer staging must scope its token to each gh verification/API step' >&2; exit 1; }
rg -Fq 'BURLMD_AUTHENTICATED_STAGE_ROOT' .github/workflows/ci-role-macos-15-arm64.yml || { echo 'macOS 15 runner must receive only the fixed authenticated stage root' >&2; exit 1; }
rg -Fq 'authenticated_stage_artifact' .github/workflows/ci-role-macos-15-arm64.yml || { echo 'macOS 15 must have an explicit staged-artifact interface' >&2; exit 1; }
rg -Fq 'managed-evidence.sh' .github/workflows scripts
# Every command that parses, hashes, archives, or copies an expected identity,
# candidate bundle, or sealing receipt must come from the pinned devenv
# closure. The workflow shell itself is not a protocol-tool source.
if rg -n '(^|[[:space:];|$(])(base64|sha256sum|awk|jq|tar|cp|mkdir|tr)[[:space:]]' .github/workflows | rg -Fv './scripts/ci-devenv.sh' >/dev/null; then
  echo 'managed evidence workflow invokes an ambient helper tool' >&2
  exit 1
fi
if rg -n 'always\(\)|uses:.*\$\{\{|uses:.*@refs/' .github/workflows >/dev/null; then echo 'dynamic workflow reference or always override is forbidden' >&2; exit 1; fi
for action in \
  'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' \
  'cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24' \
  'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' \
  'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c' \
  'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6'; do
  rg -Fq "$action" .github/workflows || { echo "missing pinned action: $action" >&2; exit 1; }
done
