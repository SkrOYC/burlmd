#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-ci-matrix.XXXXXX"); trap 'rm -rf -- "$tmp"' EXIT
fixture() {
  mkdir -p "$tmp/repo/.constitution/tech-spec/contracts"
  cp -a "$root/.github" "$tmp/repo/"
  cp -a "$root/scripts" "$tmp/repo/"
  cp "$root/devenv.nix" "$tmp/repo/"
  cp "$root/.constitution/tech-spec/contracts/ci-role-evidence.schema.json" "$tmp/repo/.constitution/tech-spec/contracts/"
  cp "$root/.constitution/tech-spec/contracts/ci-evidence.schema.json" "$tmp/repo/.constitution/tech-spec/contracts/"
}
assert_rejected() {
  local label=$1
  if (cd "$tmp/repo" && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-22.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json --skip-fixtures) >/dev/null 2>&1; then
    echo "matrix accepted mutation: $label" >&2; exit 1
  fi
}
mutate() { local label=$1 expression=$2 file=${3:-$tmp/repo/.github/workflows/ci-role-linux-x86-64.yml}; rm -rf "$tmp/repo"; fixture; if [[ $file == all ]]; then perl -0pi -e "$expression" "$tmp/repo"/.github/workflows/*.yml; else perl -0pi -e "$expression" "$file"; fi; assert_rejected "$label"; }
fixture
if ! (cd "$tmp/repo" && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-22.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json --skip-fixtures) >/dev/null 2>&1; then
  echo 'clean matrix fixture was rejected' >&2
  exit 1
fi
mutate bad-action 's/fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09/0000000000000000000000000000000000000000/g' all
mutate expected-control-runner 's/(^  expected:\n    runs-on: )ubuntu-24\.04/$1ubuntu-22.04/m' "$tmp/repo/.github/workflows/ci.yml"
mutate receipt-control-runner 's/(^  receipt_digests:\n    needs:.*\n    runs-on: )ubuntu-24\.04/$1ubuntu-22.04/m' "$tmp/repo/.github/workflows/ci.yml"
mutate linux-candidate-runner 's/(^  candidate:\n    runs-on: )ubuntu-22\.04/$1ubuntu-24.04/m'
mutate linux-seal-runner 's/(^  seal:\n    needs: candidate\n    runs-on: )ubuntu-22\.04/$1ubuntu-24.04/m'
mutate candidate-write 's/permissions: \{contents: read\}/permissions: {contents: write}/'
mutate trusted-checkout-credentials 's/persist-credentials: false/persist-credentials: true/g' all
mutate always 's/needs: candidate/needs: candidate\n    if: always()/'
mutate extra-job 's/^  seal:/  unexpected:\n    runs-on: ubuntu-22.04\n  seal:/m'
mutate direct-input-shell 's#run: \./scripts/ci-devenv\.sh \./scripts/run-managed-role\.sh#run: echo "\${{ inputs.artifact_nonce }}" && ./scripts/ci-devenv.sh ./scripts/run-managed-role.sh#'
mutate missing-input-validation 's#\./scripts/validate-managed-workflow-inputs\.sh#./scripts/not-the-validator.sh#' "$tmp/repo/.github/workflows/ci.yml"
mutate caller-owned-macos-stage 's/^  macos_15:/  stage_macos_26_for_15:\n    runs-on: macos-26\n  macos_15:/m' "$tmp/repo/.github/workflows/ci.yml"
mutate candidate-actions-read 's/permissions: \{contents: read\}/permissions: {actions: read, contents: read}/'
mutate candidate-token-leak 's/env: \{EXPECTED_IDENTITY:/env: {GH_TOKEN: forbidden, EXPECTED_IDENTITY:/'
mutate candidate-timeout-missing 's/    timeout-minutes: 120\n//'
mutate candidate-timeout-wrong 's/timeout-minutes: 120/timeout-minutes: 119/'
mutate candidate-soft-failure 's#(  candidate:\n)#$1    continue-on-error: true\n#'
mutate legacy-role-output 's#(    outputs:\n)#$1      sealed_artifact_id:\n        value: unexpected\n#'
mutate missing-receipt-output 's/sealing-receipt-upload-action-digest:/unexpected-receipt-output:/'
mutate missing-macos-26-stage-output 's/stage-artifact-name:/unexpected-stage-artifact-name:/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate nix-enable-kvm-missing 's/with: \{enable_kvm: false\}/with: {}/'
mutate nix-enable-kvm-true 's/enable_kvm: false/enable_kvm: true/'
mutate nix-enable-kvm-expression 's/enable_kvm: false/enable_kvm: \${{ inputs.enable_kvm }}/'
mutate nix-install-url-key 's/with: \{enable_kvm: false\}/with: {enable_kvm: false, install_url: https:\/\/example.invalid\/nix}/'
mutate nix-input-install-url-environment 's#(      - uses: cachix/install-nix-action\@13d8dd58da0234aa297dedd986986ccb8e7f3e24)#      - name: Override Nix install URL\n        env: {INPUT_INSTALL_URL: https://example.invalid/nix}\n        run: :\n$1#'
mutate nix-action-wrapper 's#uses: cachix/install-nix-action\@13d8dd58da0234aa297dedd986986ccb8e7f3e24#uses: ./.github/actions/install-nix#'
mutate nix-preinstalled 's/if command -v nix >\/dev\/null 2>\&1; then/if false; then/'
mutate nix-precheck-disabled 's#(      - name: Reject preinstalled Nix\n)#$1        if: false\n#'
mutate nix-precheck-soft-failure 's#(      - name: Reject preinstalled Nix\n)#$1        continue-on-error: true\n#'
mutate nix-postcheck-disabled 's#(      - name: Verify action-installed Nix interface\n)#$1        if: false\n#'
mutate nix-postcheck-soft-failure 's#(      - name: Verify action-installed Nix interface\n)#$1        continue-on-error: true\n#'
mutate nix-version-output 's/nix \(Nix\) 2\.35\.2/nix (Nix) 2.35.1/'
mutate nix-store-version-command 's/nix_store_version=\$\(nix-store --version 2>\&1\)/nix_store_version=$(nix --version 2>\&1)/'
mutate nix-profile-path 's#nix_profile=/nix/var/nix/profiles/default#nix_profile=/tmp/untrusted-nix-profile#'
mutate nix-resolved-profile 's/nix_store_real_path=\$\(python3/nix_store_path=\$\(python3/'
mutate missing-macos-nix-credential-scrub 's/Remove persisted Nix credentials before candidate execution/Skip Nix credential scrub/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate missing-macos-nix-credential-verification "s/grep -Eq '\^\[\[:space:\]\]\*access-tokens\[\[:space:\]\]\*='/grep -Eq '^nix-credentials-removed='/" "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate missing-macos-nix-daemon-reload 's/launchctl kickstart -k system\/org.nixos.nix-daemon/launchctl print system\/org.nixos.nix-daemon/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate missing-macos-effective-nix-credential-verification 's/\[\^\[:space:\]\]/[[:space:]]/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-26-runtime-token-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-26-runtime-url-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-26-results-url-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-15-runtime-token-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-15-runtime-url-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-15-results-url-parent-leak 's/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL ACTIONS_RESULTS_URL/unset ACTIONS_RUNTIME_TOKEN ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-26-runtime-token-launcher-leak 's/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RUNTIME_URL/-u ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-26-runtime-url-launcher-leak 's/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RUNTIME_URL -u ACTIONS_RESULTS_URL/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-26-results-url-launcher-leak 's/-u ACTIONS_RUNTIME_URL -u ACTIONS_RESULTS_URL/-u ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate macos-15-runtime-token-launcher-leak 's/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RUNTIME_URL/-u ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-15-runtime-url-launcher-leak 's/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RUNTIME_URL -u ACTIONS_RESULTS_URL/-u ACTIONS_RUNTIME_TOKEN -u ACTIONS_RESULTS_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate macos-15-results-url-launcher-leak 's/-u ACTIONS_RUNTIME_URL -u ACTIONS_RESULTS_URL/-u ACTIONS_RUNTIME_URL/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate missing-pre-attestation-rest-check 's/--phase candidate/--phase missing/'
mutate missing-post-upload-rest-check 's/--phase sealed/--phase missing/'
mutate attest-registry-enabled 's/push-to-registry: false/push-to-registry: true/'
mutate attest-storage-record-enabled 's/create-storage-record: false/create-storage-record: true/'
mutate unpinned-stage-download 's/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c/refs\/heads\/main/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate missing-seal-stage-helper 's#prepare-compatibility-stage\.sh#missing-stage-helper.sh#' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate missing-lineage-helper 's#write-compatibility-stage-lineage\.sh#missing-lineage-helper.sh#' "$tmp/repo/.github/workflows/ci-role-macos-26-arm64.yml"
mutate missing-required-stage-gate 's#validate-compatibility-stage-interface\.sh#missing-stage-interface.sh#' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate missing-immutable-stage-download 's/artifact-ids:/artifact-name:/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
mutate missing-offline-trusted-root 's/gh attestation trusted-root/gh attestation no-root/' "$tmp/repo/.github/workflows/ci-role-macos-15-arm64.yml"
rm -rf "$tmp/repo"; fixture
perl -0pi -e 's#(\n      - name: Verify action-installed Nix interface\n.*?)(\n      - id: validated\n.*?)(\n      - id: upload\n)#$2$1$3#s' "$tmp/repo/.github/workflows/ci.yml"
assert_rejected reordered-nix-interface-check
rm -rf "$tmp/repo"; fixture
perl -0pi -e 's#uses: \./\.github/workflows/ci-role-linux-x86-64\.yml#uses: ./.github/workflows/\${{ inputs.role }}.yml#' "$tmp/repo/.github/workflows/ci.yml"
assert_rejected dynamic-use
"$root/scripts/test-seal-rest-precheck.sh"
