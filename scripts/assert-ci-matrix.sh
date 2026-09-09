#!/usr/bin/env bash
# Static CI contract checks. Deliberately conservative: a missing invariant fails.
set -euo pipefail
workflow= role_schema= aggregate_schema= run_fixtures=true
declare -a runners=()
declare -a artifact_runtime_variables=(ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL)
while (($#)); do
  case $1 in
    --workflow) workflow=$2; shift 2;;
    --require-runner) runners+=("$2"); shift 2;;
    --require-role-schema) role_schema=$2; shift 2;;
    --require-aggregate-schema) aggregate_schema=$2; shift 2;;
    --skip-fixtures) run_fixtures=false; shift;;
    *) echo "usage: $0 --workflow PATH --require-runner LABEL ... --require-role-schema PATH --require-aggregate-schema PATH [--skip-fixtures]" >&2; exit 2;;
  esac
done
[[ -n $workflow && -f $workflow && -f $role_schema && -f $aggregate_schema ]] || exit 2
for runner in "${runners[@]}"; do rg -Fq "runs-on: $runner" .github/workflows || { echo "missing required runner: $runner" >&2; exit 1; }; done

expected_block=$(sed -n '/^  expected:/,/^  linux:/p' "$workflow")
grep -Fxc '    runs-on: ubuntu-24.04' <<<"$expected_block" | grep -Fxq 1 || { echo 'expected control job runner mismatch' >&2; exit 1; }

# The pinned action exits successfully when Nix is already on PATH. Each direct
# action site therefore rejects an ambient executable and proves the action's
# transitive 2.35.2 installation before any ordinary workflow step can run.
readonly nix_action='cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24'
readonly nix_preinstall_name='      - name: Reject preinstalled Nix'
readonly nix_postinstall_name='      - name: Verify action-installed Nix interface'
readonly nix_preinstall_command='          if command -v nix >/dev/null 2>&1; then'
readonly nix_profile_command='          nix_profile=/nix/var/nix/profiles/default'
readonly nix_path_command='          nix_path=$(command -v nix)'
readonly nix_store_path_command='          nix_store_path=$(command -v nix-store)'
readonly nix_version_command='          nix_version=$(nix --version 2>&1)'
readonly nix_store_version_command='          nix_store_version=$(nix-store --version 2>&1)'
readonly nix_version_assertion="          [[ \$nix_version == 'nix (Nix) 2.35.2' ]] || { echo 'nix version must equal 2.35.2' >&2; exit 1; }"
readonly nix_store_version_assertion="          [[ \$nix_store_version == 'nix-store (Nix) 2.35.2' ]] || { echo 'nix-store version must equal 2.35.2' >&2; exit 1; }"
readonly nix_real_path_command="          nix_real_path=\$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \"\$nix_path\")"
readonly nix_store_real_path_command="          nix_store_real_path=\$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \"\$nix_store_path\")"
readonly nix_profile_identity_assertion='          [[ ${nix_real_path%/*} == "${nix_store_real_path%/*}" ]] || { echo '\''nix and nix-store must resolve through one installed Nix profile'\'' >&2; exit 1; }'
nix_workflows=(
  .github/workflows/ci.yml
  .github/workflows/ci-role-linux-x86-64.yml
  .github/workflows/ci-role-macos-26-arm64.yml
  .github/workflows/ci-role-macos-15-arm64.yml
)

if rg -n -i 'install_url|input_install_url' .github/workflows; then
  echo 'trusted workflows must not provide an install_url override' >&2
  exit 1
fi

for nix_workflow in "${nix_workflows[@]}"; do
  case $nix_workflow in
    .github/workflows/ci.yml) expected_nix_sites=2;;
    *) expected_nix_sites=2;;
  esac
  nix_install_lines=()
  nix_preinstall_lines=()
  nix_postinstall_lines=()
  while IFS=: read -r line _; do nix_install_lines+=("$line"); done < <(rg -n -F "$nix_action" "$nix_workflow" || true)
  while IFS=: read -r line _; do nix_preinstall_lines+=("$line"); done < <(rg -n -F "$nix_preinstall_name" "$nix_workflow" || true)
  while IFS=: read -r line _; do nix_postinstall_lines+=("$line"); done < <(rg -n -F "$nix_postinstall_name" "$nix_workflow" || true)
  [[ ${#nix_install_lines[@]} -eq $expected_nix_sites ]] || { echo "$nix_workflow has an unexpected number of direct Nix action sites" >&2; exit 1; }
  [[ ${#nix_preinstall_lines[@]} -eq $expected_nix_sites && ${#nix_postinstall_lines[@]} -eq $expected_nix_sites ]] || { echo "$nix_workflow must guard every Nix action site" >&2; exit 1; }
  for nix_line in \
    "$nix_preinstall_command" \
    "$nix_profile_command" \
    "$nix_path_command" \
    "$nix_store_path_command" \
    "$nix_version_command" \
    "$nix_store_version_command" \
    "$nix_version_assertion" \
    "$nix_store_version_assertion" \
    "$nix_real_path_command" \
    "$nix_store_real_path_command" \
    "$nix_profile_identity_assertion"; do
    nix_line_count=$(grep -Fc "$nix_line" "$nix_workflow" || true)
    [[ $nix_line_count -eq $expected_nix_sites ]] || { echo "$nix_workflow is missing a required Nix installer interface assertion" >&2; exit 1; }
  done
  for ((nix_index = 0; nix_index < expected_nix_sites; nix_index++)); do
    preinstall_line=${nix_preinstall_lines[nix_index]}
    install_line=${nix_install_lines[nix_index]}
    postinstall_line=${nix_postinstall_lines[nix_index]}
    [[ $preinstall_line -lt $install_line && $install_line -lt $postinstall_line ]] || { echo "$nix_workflow must order Nix checks around each installer" >&2; exit 1; }
    preinstall_step_count=$(sed -n "${preinstall_line},${install_line}p" "$nix_workflow" | rg -c '^      - ' || true)
    postinstall_step_count=$(sed -n "${install_line},${postinstall_line}p" "$nix_workflow" | rg -c '^      - ' || true)
    [[ $preinstall_step_count -eq 2 && $postinstall_step_count -eq 2 ]] || { echo "$nix_workflow must run Nix checks immediately around each installer" >&2; exit 1; }
    sed -n "${install_line},$((install_line + 1))p" "$nix_workflow" | grep -Fxq '        with: {enable_kvm: false}' || { echo "$nix_workflow must set literal enable_kvm false" >&2; exit 1; }
    preinstall_step=$(sed -n "${preinstall_line},$((install_line - 1))p" "$nix_workflow")
    # Read the workflow directly. A sed producer can receive SIGPIPE when awk
    # stops at the next step, making this exact assertion fail intermittently
    # with status 141 under pipefail.
    postinstall_step=$(awk -v start="$postinstall_line" '
      NR < start { next }
      NR == start { print; next }
      /^      - / { exit }
      { print }
    ' "$nix_workflow")
    for guard_step in "$preinstall_step" "$postinstall_step"; do
      if grep -Eq '^[[:space:]]+(if|continue-on-error):' <<<"$guard_step"; then
        echo "$nix_workflow must run every Nix installer guard unconditionally and fail closed" >&2
        exit 1
      fi
    done
    postinstall_window=$(sed -n "${postinstall_line},$((postinstall_line + 20))p" "$nix_workflow")
    grep -Fqx '        shell: bash' <<<"$postinstall_window" || { echo "$nix_workflow must run the Nix interface check with Bash" >&2; exit 1; }
  done
done

[[ $(rg -F 'enable_kvm' "${nix_workflows[@]}" | wc -l | tr -d ' ') -eq 8 ]] || { echo 'every Nix action must use literal enable_kvm false' >&2; exit 1; }

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
  role_output_block=$(sed -n '/^    outputs:/,/^jobs:/p' "$file")
  case $role in
    linux-x86-64|macos-15-arm64)
      expected_role_outputs=(
        sealing-receipt-artifact-id
        sealing-receipt-upload-action-digest
      )
      ;;
    macos-26-arm64)
      expected_role_outputs=(
        sealing-receipt-artifact-id
        sealing-receipt-upload-action-digest
        stage-artifact-name
        stage-artifact-id
        stage-upload-action-digest
        stage-rest-digest
        stage-created-at
        stage-expires-at
        stage-manifest-sha256
        stage-attestation-subject-digest
        stage-attestation-bundle-sha256
        producer-workflow-signer-sha
        workflow-run-id
        run-attempt
        producer-sealing-check-run-id
        producer-sealing-receipt-artifact-id
        producer-sealing-receipt-upload-action-digest
        producer-sealing-receipt-rest-digest
        producer-sealing-receipt-created-at
        producer-sealing-receipt-expires-at
        producer-lineage-artifact-id
        producer-lineage-upload-action-digest
        producer-lineage-rest-digest
        producer-lineage-sha256
        producer-lineage-attestation-subject-digest
        producer-lineage-attestation-bundle-sha256
        producer-role
        consumer-role
      )
      ;;
  esac
  actual_role_outputs=$(awk '
    /^    outputs:$/ { inside = 1; next }
    inside && /^jobs:$/ { exit }
    inside && /^      [[:alnum:]_-]+:/ { line = $0; sub(/^      /, "", line); sub(/:.*/, "", line); print line }
  ' "$file")
  expected_role_outputs_text=$(printf '%s\n' "${expected_role_outputs[@]}")
  [[ $actual_role_outputs == "$expected_role_outputs_text" ]] || { echo "$file reusable-workflow outputs differ from the contract" >&2; exit 1; }
  rg -Fq 'validate-managed-role-bundle.sh' "$file" || { echo "$file must validate its candidate bundle in seal" >&2; exit 1; }
  (rg -Fq 'permissions: {contents: read}' "$file" || rg -Uq 'permissions:\n      contents: read' "$file") || { echo "$file candidate permissions must be contents read only" >&2; exit 1; }
  rg -Fq 'permissions: {actions: read, contents: read, id-token: write, attestations: write}' "$file" || { echo "$file seal permissions mismatch" >&2; exit 1; }
  rg -Fq 'overwrite: false' "$file" || { echo "$file must use immutable artifact upload" >&2; exit 1; }
  validation_count=$(rg -Fc './scripts/validate-managed-workflow-inputs.sh' "$file")
  attempt_binding_count=$(rg -Fc 'GITHUB_RUN_ATTEMPT: ${{ github.run_attempt }}' "$file")
  [[ $validation_count -gt 0 && $validation_count == "$attempt_binding_count" ]] || { echo "$file must bind the literal GitHub run attempt into every validator" >&2; exit 1; }
  candidate_block=$(sed -n '/^  candidate:/,/^  seal:/p' "$file")
  seal_block=$(sed -n '/^  seal:/,$p' "$file")
  case $role in
    linux-x86-64) expected_role_runner=ubuntu-22.04;;
    macos-26-arm64) expected_role_runner=macos-26;;
    macos-15-arm64) expected_role_runner=macos-15;;
  esac
  [[ $(grep -Fxc "    runs-on: $expected_role_runner" <<<"$candidate_block") -eq 1 ]] || { echo "$file candidate runner mismatch" >&2; exit 1; }
  [[ $(grep -Fxc "    runs-on: $expected_role_runner" <<<"$seal_block") -eq 1 ]] || { echo "$file seal runner mismatch" >&2; exit 1; }
  [[ $(grep -Fxc '    timeout-minutes: 120' <<<"$candidate_block") -eq 1 ]] || { echo "$file candidate timeout must be the literal 120-minute budget" >&2; exit 1; }
  if grep -Eq '^[[:space:]]+continue-on-error:' <<<"$candidate_block"; then
    echo "$file candidate must not soften failures with continue-on-error" >&2
    exit 1
  fi
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
  if [[ $role == macos-26-arm64 || $role == macos-15-arm64 ]]; then
    # The pinned Nix installer falls back to github.token even when its optional
    # input is empty. A macOS candidate has no filesystem namespace, so it must
    # scrub the persisted global token and reload Nix before candidate execution.
    grep -Fq 'Remove persisted Nix credentials before candidate execution' <<<"$candidate_block" || { echo "$file macOS candidate must scrub persisted Nix credentials" >&2; exit 1; }
    grep -Fq "sed -i '' -E '/^[[:space:]]*access-tokens[[:space:]]*=/d' /etc/nix/nix.conf" <<<"$candidate_block" || { echo "$file macOS candidate must delete Nix access-token configuration" >&2; exit 1; }
    grep -Fq 'launchctl kickstart -k system/org.nixos.nix-daemon' <<<"$candidate_block" || { echo "$file macOS candidate must reload Nix after credential removal" >&2; exit 1; }
    grep -Fq "grep -Eq '^[[:space:]]*access-tokens[[:space:]]*=' /etc/nix/nix.conf" <<<"$candidate_block" || { echo "$file macOS candidate must verify Nix access-token removal" >&2; exit 1; }
    grep -Fq "grep -Eq '^[[:space:]]*access-tokens[[:space:]]*=[[:space:]]*[^[:space:]]'" <<<"$candidate_block" || { echo "$file macOS candidate must verify the reloaded Nix daemon has no access token" >&2; exit 1; }
    nix_install_line=$(rg -n -F 'uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24' "$file" | head -n1 | cut -d: -f1)
    nix_scrub_line=$(rg -n -F 'Remove persisted Nix credentials before candidate execution' "$file" | head -n1 | cut -d: -f1)
    candidate_line=$(rg -n -F 'Run candidate as credential-free data' "$file" | head -n1 | cut -d: -f1)
    [[ $nix_install_line -lt $nix_scrub_line && $nix_scrub_line -lt $candidate_line ]] || { echo "$file must scrub Nix credentials between install and candidate execution" >&2; exit 1; }
    grep -Fq 'env -u GH_TOKEN -u GITHUB_TOKEN' <<<"$candidate_block" || { echo "$file macOS candidate must clear ambient GitHub tokens" >&2; exit 1; }
    grep -Fq -- '-u NIX_CONFIG -u NIX_CONF_DIR -u NIX_USER_CONF_FILES' <<<"$candidate_block" || { echo "$file macOS candidate must clear alternate Nix configuration" >&2; exit 1; }
    # macOS candidates share a host with the workflow shell. Removing these
    # variables only from the child would leave artifact authority visible in
    # the parent environment, so clear them before launching and require the
    # child boundary to remove them too.
    runtime_unset_line=$(rg -n -F 'unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL' "$file" | head -n1 | cut -d: -f1)
    candidate_launcher_line=$(rg -n -F 'env -u GH_TOKEN -u GITHUB_TOKEN' "$file" | head -n1 | cut -d: -f1)
    [[ -n $runtime_unset_line && -n $candidate_launcher_line && $runtime_unset_line -gt $nix_scrub_line && $runtime_unset_line -lt $candidate_launcher_line ]] || { echo "$file must clear artifact-runtime authority before candidate launch" >&2; exit 1; }
    candidate_launcher=$(sed -n '/^[[:space:]]*env -u /,/run-managed-role\.sh/p' <<<"$candidate_block")
    [[ -n $candidate_launcher ]] || { echo "$file macOS candidate launcher environment is missing" >&2; exit 1; }
    for runtime_variable in "${artifact_runtime_variables[@]}"; do
      grep -Eq -- "(^|[[:space:]])-u[[:space:]]+$runtime_variable([[:space:]]|$)" <<<"$candidate_launcher" || { echo "$file candidate launcher inherits $runtime_variable" >&2; exit 1; }
    done
  fi
  grep -Fq 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' <<<"$seal_block" || { echo "$file fresh seal lacks sole attestation authority" >&2; exit 1; }
  attest_count=$(rg -Fc 'uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' "$file")
  explicit_attest_input_count=$(rg -c 'with: \{subject-path: .*, push-to-registry: false, create-storage-record: false\}' "$file" || true)
  [[ $attest_count == "$explicit_attest_input_count" ]] || { echo "$file must explicitly disable registry pushes and storage records for every attestation" >&2; exit 1; }
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
receipt_digest_block=$(sed -n '/^  receipt_digests:/,$p' "$workflow")
[[ -n $receipt_digest_block ]] || { echo 'caller must define receipt_digests' >&2; exit 1; }
grep -Fq 'needs: [expected, linux, macos_26, macos_15]' <<<"$receipt_digest_block" || { echo 'receipt_digests needs contract mismatch' >&2; exit 1; }
grep -Fq 'runs-on: ubuntu-24.04' <<<"$receipt_digest_block" || { echo 'receipt_digests runner mismatch' >&2; exit 1; }
grep -Fq 'permissions: {contents: read}' <<<"$receipt_digest_block" || { echo 'receipt_digests permissions mismatch' >&2; exit 1; }
grep -Fq './scripts/write-receipt-digest-observation.sh --output receipt-upload-digests.json' <<<"$receipt_digest_block" || { echo 'receipt_digests must use the trusted writer' >&2; exit 1; }
for output in \
  'needs.linux.outputs.sealing-receipt-artifact-id' \
  'needs.linux.outputs.sealing-receipt-upload-action-digest' \
  'needs.macos_26.outputs.sealing-receipt-artifact-id' \
  'needs.macos_26.outputs.sealing-receipt-upload-action-digest' \
  'needs.macos_15.outputs.sealing-receipt-artifact-id' \
  'needs.macos_15.outputs.sealing-receipt-upload-action-digest'; do
  grep -Fq "$output" <<<"$receipt_digest_block" || { echo "receipt_digests is missing $output" >&2; exit 1; }
done
grep -Fq 'name: managed-evidence-receipt-digests-${{ needs.expected.outputs.artifact_nonce }}' <<<"$receipt_digest_block" || { echo 'receipt_digests artifact name mismatch' >&2; exit 1; }
grep -Fq 'path: receipt-upload-digests.json' <<<"$receipt_digest_block" || { echo 'receipt_digests artifact member mismatch' >&2; exit 1; }
grep -Fq 'overwrite: false' <<<"$receipt_digest_block" && grep -Fq 'if-no-files-found: error' <<<"$receipt_digest_block" || { echo 'receipt_digests upload must be immutable and fail closed' >&2; exit 1; }
[[ $(rg -Fc 'uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' "$workflow") -eq $(rg -Fc 'persist-credentials: false' "$workflow") ]] || { echo "$workflow must disable credentials on every checkout" >&2; exit 1; }
rg -Fq './scripts/validate-managed-workflow-inputs.sh' "$workflow" || { echo "$workflow must validate canonical expected identity before fan-out" >&2; exit 1; }
[[ $(rg -Fc './scripts/validate-managed-workflow-inputs.sh' "$workflow") == $(rg -Fc 'GITHUB_RUN_ATTEMPT: ${{ github.run_attempt }}' "$workflow") ]] || { echo "$workflow must bind the GitHub run attempt before expected-artifact upload" >&2; exit 1; }
[[ -x scripts/validate-managed-workflow-inputs.sh && -x scripts/stage-authenticated-role-bundle.sh && -x scripts/validate-authenticated-stage-producer.sh && -x scripts/prepare-compatibility-stage.sh && -x scripts/record-compatibility-stage-rest.sh && -x scripts/write-compatibility-stage-lineage.sh && -x scripts/prepare-compatibility-stage-consumer.sh && -x scripts/validate-compatibility-stage-interface.sh && -x scripts/write-receipt-digest-observation.sh ]] || { echo 'trusted workflow helpers must be executable' >&2; exit 1; }
if rg -n 'run:.*\$\{\{[[:space:]]*inputs\.' .github/workflows >/dev/null; then
  echo 'a workflow interpolates a dispatcher input directly into a shell command' >&2
  exit 1
fi
! rg -q '^  stage_macos_26_for_15:' "$workflow" || { echo 'BURL-O001 stage must be seal-owned, not a caller staging job' >&2; exit 1; }
rg -Fq 'needs: [expected, macos_26]' "$workflow" || { echo 'macOS 15 must wait for its producer role' >&2; exit 1; }
macos_26_workflow=.github/workflows/ci-role-macos-26-arm64.yml
macos_26_seal_block=$(sed -n '/^  seal:/,$p' "$macos_26_workflow")
grep -Fq 'Create authenticated compatibility stage in the producer seal' <<<"$macos_26_seal_block" || { echo 'macOS 26 seal must own compatibility stage creation' >&2; exit 1; }
grep -Fq 'prepare-compatibility-stage.sh' <<<"$macos_26_seal_block" || { echo 'macOS 26 seal must validate exactly the declared producer members' >&2; exit 1; }
grep -Fq 'record-compatibility-stage-rest.sh' <<<"$macos_26_seal_block" || { echo 'macOS 26 seal must REST validate the stage' >&2; exit 1; }
grep -Fq 'write-compatibility-stage-lineage.sh' <<<"$macos_26_seal_block" || { echo 'macOS 26 seal must create canonical producer lineage after receipt upload' >&2; exit 1; }
[[ $(rg -Fc 'compatibility-stage-producer-lineage.json' "$macos_26_workflow") -ge 3 ]] || { echo 'macOS 26 must attest and upload immutable lineage bytes' >&2; exit 1; }
for output in stage-artifact-name stage-artifact-id stage-upload-action-digest stage-rest-digest stage-created-at stage-expires-at stage-manifest-sha256 stage-attestation-subject-digest stage-attestation-bundle-sha256 producer-workflow-signer-sha workflow-run-id run-attempt producer-sealing-check-run-id producer-sealing-receipt-artifact-id producer-sealing-receipt-upload-action-digest producer-sealing-receipt-rest-digest producer-sealing-receipt-created-at producer-sealing-receipt-expires-at producer-lineage-artifact-id producer-lineage-upload-action-digest producer-lineage-rest-digest producer-lineage-sha256 producer-lineage-attestation-subject-digest producer-lineage-attestation-bundle-sha256 producer-role consumer-role; do
  rg -Fq "$output" "$macos_26_workflow" || { echo "macOS 26 missing trusted stage output: $output" >&2; exit 1; }
done
macos_15_workflow=.github/workflows/ci-role-macos-15-arm64.yml
macos_15_candidate_block=$(sed -n '/^  candidate:/,/^  seal:/p' "$macos_15_workflow")
rg -Fq 'producer-lineage-artifact-id' "$macos_15_workflow" || { echo 'macOS 15 must accept the complete producer interface' >&2; exit 1; }
# The only cross-role candidate input is BURL-O001's authenticated macOS 26
# handoff. BURL-M003 and every other no-stage ticket must leave the launcher
# variable empty: a non-existent runner-temp path is not an optional input.
    grep -Fq 'validate-compatibility-stage-interface.sh' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must validate the complete stage interface' >&2; exit 1; }
    [[ $(grep -Fc 'STAGE_' <<<"$macos_15_candidate_block") -ge 9 && $(grep -Fc 'PRODUCER_' <<<"$macos_15_candidate_block") -ge 17 ]] || { echo 'macOS 15 must carry all 26 sealed stage fields' >&2; exit 1; }
[[ $(grep -Fc 'artifact-ids:' <<<"$macos_15_candidate_block") -eq 3 && $(grep -Fc 'digest-mismatch: error' <<<"$macos_15_candidate_block") -eq 3 ]] || { echo 'macOS 15 must download all producer artifacts by immutable ID with digest errors' >&2; exit 1; }
grep -Fq 'gh attestation trusted-root' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must acquire a fresh offline trusted root' >&2; exit 1; }
[[ $(grep -Fc 'gh attestation verify' <<<"$macos_15_candidate_block") -eq 3 ]] || { echo 'macOS 15 must offline-verify stage, receipt, and lineage' >&2; exit 1; }
grep -Fq 'prepare-compatibility-stage-consumer.sh' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must remove credentials before read-only exposure' >&2; exit 1; }
grep -Fq 'compatibility-acquisition' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must isolate acquisition evidence' >&2; exit 1; }
grep -Fq 'authenticated-stage-members' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must expose a fresh member-only root' >&2; exit 1; }
grep -Fq 'wrapper-handoff/compatibility-stage-consumption.json' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must use a separate wrapper handoff' >&2; exit 1; }
grep -Fq '[[ ! -e $STAGE_ROOT ]]' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must remove acquisition tree before candidate execution' >&2; exit 1; }
grep -Fq '! -e "$MEMBER_ROOT/stage-verification.json"' <<<"$macos_15_candidate_block" || { echo 'macOS 15 must expose only producer members' >&2; exit 1; }
    grep -Fq 'env -u GH_TOKEN -u GITHUB_TOKEN' <<<"$macos_15_candidate_block" || { echo 'macOS 15 candidate wrapper must clear credentials' >&2; exit 1; }
    ! grep -Fq 'gh api' <<<"$macos_15_candidate_block" || { echo 'macOS 15 candidate must not query artifact REST APIs' >&2; exit 1; }
    ! grep -Fq 'GH_TOKEN:' <<<"$macos_15_candidate_block" || { echo 'macOS 15 candidate must not receive a GitHub token' >&2; exit 1; }
grep -Fq '[[ ! -e "$RUNNER_TEMP/wrapper-handoff/compatibility-stage-consumption.json" ]]' <<<"$macos_15_candidate_block" || { echo 'macOS 15 wrapper must consume and unlink its handoff before candidate completion' >&2; exit 1; }
! grep -Fq 'authenticated-input' <<<"$macos_15_candidate_block" || { echo 'macOS 15 candidate must never receive acquisition root' >&2; exit 1; }
macos_15_seal_block=$(sed -n '/^  seal:/,$p' "$macos_15_workflow")
[[ $(grep -Fc 'artifact-ids:' <<<"$macos_15_seal_block") -eq 3 && $(grep -Fc 'digest-mismatch: error' <<<"$macos_15_seal_block") -eq 3 ]] || { echo 'macOS 15 fresh seal must reacquire all producer artifacts by ID' >&2; exit 1; }
[[ $(grep -Fc 'gh attestation verify' <<<"$macos_15_seal_block") -eq 3 ]] || { echo 'macOS 15 fresh seal must independently verify all attestations' >&2; exit 1; }
grep -Fq 'gh attestation trusted-root' <<<"$macos_15_seal_block" || { echo 'macOS 15 fresh seal must acquire its own trusted root' >&2; exit 1; }
grep -Fq 'prepare-compatibility-stage-consumer.sh' <<<"$macos_15_seal_block" || { echo 'macOS 15 fresh seal must reconstruct compatibility facts through the trusted consumer' >&2; exit 1; }
grep -Fq 'Compare candidate compatibility manifest to fresh seal reconstruction' <<<"$macos_15_seal_block" || { echo 'macOS 15 seal must compare a fresh compatibility reconstruction' >&2; exit 1; }
grep -Fq 'candidate-compatibility-stage.json' <<<"$macos_15_seal_block" || { echo 'macOS 15 receipt must preserve the validated candidate compatibility binding' >&2; exit 1; }
! grep -Fq 'COMPATIBILITY_STAGE_FILE: ${{ steps.validated.outputs.ticket_identity == '\''BURL-O001'\'' && format('\''{0}/fresh-seal-handoff.json'\'', runner.temp) || '\'''\'' }}' <<<"$macos_15_seal_block" || { echo 'macOS 15 receipt must not write the fresh seal reconstruction' >&2; exit 1; }
compare_line=$(rg -n -F 'Compare candidate compatibility manifest to fresh seal reconstruction' "$macos_15_workflow" | cut -d: -f1)
receipt_line=$(rg -n -F 'Write pre-completion receipt' "$macos_15_workflow" | cut -d: -f1)
[[ $compare_line -lt $receipt_line ]] || { echo 'macOS 15 fresh reconstruction must precede receipt v2' >&2; exit 1; }
for role_workflow in .github/workflows/ci-role-linux-x86-64.yml .github/workflows/ci-role-macos-26-arm64.yml .github/workflows/ci-role-macos-15-arm64.yml; do
  receipt_block=$(sed -n '/id: attest_receipt/,/Re-authenticate sealed artifacts and receipt after upload/p' "$role_workflow")
  grep -Fq 'ci-seal-receipt.json' <<<"$receipt_block" || { echo "$role_workflow must upload the receipt" >&2; exit 1; }
  grep -Fq 'ci-seal-receipt-attestation.sigstore.json' <<<"$receipt_block" || { echo "$role_workflow must upload the receipt attestation bundle" >&2; exit 1; }
done
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
upload_count=$(rg -F 'uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' .github/workflows | wc -l | tr -d ' ')
immutable_upload_count=$(rg -F 'overwrite: false' .github/workflows | wc -l | tr -d ' ')
[[ $upload_count -gt 0 && $upload_count == "$immutable_upload_count" ]] || { echo 'every managed upload must set overwrite: false' >&2; exit 1; }

# BURL-M003's exact acceptance command reaches this entrypoint. Keep its
# contract fixtures here, after the static workflow surface has been accepted,
# so a passing local gate proves generated bindings, dispatch inputs, seals,
# role bundles, trusted-control reconciliation, production role isolation and
# closure views, and the macOS cold-checkout boundary. The coordinator umbrella
# already runs the non-M003 legacy private-store, client, and reconciliation
# fixtures. Don't invoke those leaves a second time. The full Linux cold checkout remains
# separately required milestone and hosted evidence: it materializes a large
# private Nix closure, so nesting it here would make the canonical gate depend
# on retained Rust and Flutter build artifacts. The M003 isolation and
# locked-closure fixtures use read-only closure views and retain contract coverage
# here with their owned scratch under `/var/tmp`; the coordinator harness retains
# its lightweight `/tmp` workspace. The mutation fixture recurses into this
# checker with --skip-fixtures, avoiding repeated fixture execution for every
# intentionally broken workflow copy.
if [[ $run_fixtures == true ]]; then
  for fixture in \
    scripts/test-check-generated-bindings.sh \
    scripts/test-ci-matrix-mutations.sh \
    scripts/test-ci-nix-installer-interface.sh \
    scripts/test-repeat-test.sh \
    scripts/test-managed-workflow-inputs.sh \
    scripts/test-candidate-failure-diagnostic.sh \
    scripts/test-candidate-guards.sh \
    scripts/test-seal-validators.sh \
    scripts/test-managed-evidence-trusted-controls.sh \
    scripts/test-receipt-digest-observation.sh \
    scripts/test-receipt-digest-transport.sh \
    scripts/test-compatibility-stage-consumer.sh \
    scripts/test-compatibility-stage-interface.sh \
    scripts/test-compatibility-stage-rejections.sh \
    scripts/test-managed-evidence-coordinator.sh \
    scripts/test-managed-role-production-contract.sh \
    scripts/test-managed-role-isolation.sh \
    scripts/test-managed-role-locked-closure.sh \
    scripts/test-ci-devenv-systems.sh \
    scripts/test-managed-role-cold-macos-checkout.sh; do
    [[ -x $fixture ]] || { echo "missing executable BURL-M003 fixture: $fixture" >&2; exit 1; }
    case "$fixture" in
      scripts/test-managed-role-isolation.sh|scripts/test-managed-role-locked-closure.sh|scripts/test-managed-role-cold-macos-checkout.sh) TMPDIR=/var/tmp "$fixture";;
      *) "$fixture";;
    esac
  done
fi
