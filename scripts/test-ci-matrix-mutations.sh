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
  if (cd "$tmp/repo" && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-24.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json) >/dev/null 2>&1; then
    echo "matrix accepted mutation: $label" >&2; exit 1
  fi
}
mutate() { local label=$1 expression=$2 file=${3:-$tmp/repo/.github/workflows/ci-role-linux-x86-64.yml}; rm -rf "$tmp/repo"; fixture; if [[ $file == all ]]; then perl -0pi -e "$expression" "$tmp/repo"/.github/workflows/*.yml; else perl -0pi -e "$expression" "$file"; fi; assert_rejected "$label"; }
mutate bad-action 's/fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09/0000000000000000000000000000000000000000/g' all
mutate candidate-write 's/permissions: \{contents: read\}/permissions: {contents: write}/'
mutate trusted-checkout-credentials 's/persist-credentials: false/persist-credentials: true/g' all
mutate always 's/needs: candidate/needs: candidate\n    if: always()/'
mutate extra-job 's/^  seal:/  unexpected:\n    runs-on: ubuntu-24.04\n  seal:/m'
mutate direct-input-shell 's#run: \./scripts/ci-devenv\.sh \./scripts/run-managed-role\.sh#run: echo "\${{ inputs.artifact_nonce }}" && ./scripts/ci-devenv.sh ./scripts/run-managed-role.sh#'
mutate missing-input-validation 's#\./scripts/validate-managed-workflow-inputs\.sh#./scripts/not-the-validator.sh#' "$tmp/repo/.github/workflows/ci.yml"
mutate missing-macos-stage 's/stage_macos_26_for_15:/stage_removed:/' "$tmp/repo/.github/workflows/ci.yml"
mutate candidate-actions-read 's/permissions: \{contents: read\}/permissions: {actions: read, contents: read}/'
mutate candidate-token-leak 's/env: \{EXPECTED_IDENTITY:/env: {GH_TOKEN: forbidden, EXPECTED_IDENTITY:/'
mutate missing-pre-attestation-rest-check 's/--phase candidate/--phase missing/'
mutate missing-post-upload-rest-check 's/--phase sealed/--phase missing/'
mutate unpinned-stage-download 's/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c/refs\/heads\/main/' "$tmp/repo/.github/workflows/ci.yml"
mutate missing-stage-api-authentication 's#validate-authenticated-stage-producer\.sh#missing-stage-producer-validator.sh#' "$tmp/repo/.github/workflows/ci.yml"
mutate missing-stage-verification-token 's/GH_TOKEN: \$\{\{ github\.token \}\}/GH_TOKEN: missing/g' "$tmp/repo/.github/workflows/ci.yml"
mutate missing-stage-signer-digest 's/--signer-digest "\$SIGNER_SHA"/--signer-digest "untrusted"/g' "$tmp/repo/.github/workflows/ci.yml"
mutate missing-stage-receipt 's#managed-evidence-seal-receipt-macos-26-arm64-#managed-evidence-wrong-receipt-#' "$tmp/repo/.github/workflows/ci.yml"
rm -rf "$tmp/repo"; fixture
perl -0pi -e 's#uses: \./\.github/workflows/ci-role-linux-x86-64\.yml#uses: ./.github/workflows/\${{ inputs.role }}.yml#' "$tmp/repo/.github/workflows/ci.yml"
assert_rejected dynamic-use
"$root/scripts/test-seal-rest-precheck.sh"
