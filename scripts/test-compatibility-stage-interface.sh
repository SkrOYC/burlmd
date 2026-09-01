#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
validator=$root/scripts/validate-compatibility-stage-interface.sh
fields=(
  STAGE_ARTIFACT_NAME STAGE_ARTIFACT_ID STAGE_UPLOAD_ACTION_DIGEST
  STAGE_REST_DIGEST STAGE_CREATED_AT STAGE_EXPIRES_AT STAGE_MANIFEST_SHA256
  STAGE_ATTESTATION_SUBJECT_DIGEST STAGE_ATTESTATION_BUNDLE_SHA256
  PRODUCER_WORKFLOW_SIGNER_SHA PRODUCER_WORKFLOW_RUN_ID PRODUCER_RUN_ATTEMPT
  PRODUCER_SEALING_CHECK_RUN_ID PRODUCER_SEALING_RECEIPT_ARTIFACT_ID
  PRODUCER_SEALING_RECEIPT_UPLOAD_ACTION_DIGEST
  PRODUCER_SEALING_RECEIPT_REST_DIGEST PRODUCER_SEALING_RECEIPT_CREATED_AT
  PRODUCER_SEALING_RECEIPT_EXPIRES_AT PRODUCER_LINEAGE_ARTIFACT_ID
  PRODUCER_LINEAGE_UPLOAD_ACTION_DIGEST PRODUCER_LINEAGE_REST_DIGEST
  PRODUCER_LINEAGE_SHA256 PRODUCER_LINEAGE_ATTESTATION_SUBJECT_DIGEST
  PRODUCER_LINEAGE_ATTESTATION_BUNDLE_SHA256 PRODUCER_ROLE CONSUMER_ROLE
)
[[ ${#fields[@]} == 26 ]] || { echo 'compatibility interface must contain exactly 26 fields' >&2; exit 1; }

base_env=()
for field in "${fields[@]}"; do base_env+=("$field=fixture-$field"); done

# BURL-O001 accepts exactly the complete interface. Each single-field deletion
# is a representative fuzz mutation over the entire closed input surface.
env "${base_env[@]}" "$validator" BURL-O001
for field in "${fields[@]}"; do
  mutated=()
  for entry in "${base_env[@]}"; do [[ $entry == "$field="* ]] || mutated+=("$entry"); done
  if env "${mutated[@]}" "$validator" BURL-O001 >/dev/null 2>&1; then
    echo "accepted partial BURL-O001 compatibility interface missing $field" >&2
    exit 1
  fi
done

# Every other ticket accepts only the all-absent interface. Inject each field
# independently to prevent a future caller from treating any subset as inert.
env -i PATH="$PATH" "$validator" BURL-M003
for field in "${fields[@]}"; do
  if env -i PATH="$PATH" "$field=unexpected" "$validator" BURL-M003 >/dev/null 2>&1; then
    echo "accepted unexpected BURL-M003 compatibility interface field $field" >&2
    exit 1
  fi
done

# The shell validator proves runtime values only. The trusted workflow shape is
# separately observable, so pin it with ordered, duplicate-aware inventories.
# Keep this parser deliberately narrow: it validates these static workflow
# blocks, not arbitrary YAML semantics.
common_inputs=(tested_source_sha expected_identity_base64 expected_identity_sha256 expected_artifact_id expected_artifact_digest run_identity artifact_nonce base_sha)
common_outputs=(sealing-receipt-artifact-id sealing-receipt-upload-action-digest)
hyphenated_fields=()
for field in "${fields[@]}"; do
  hyphenated=${field,,}
  case $field in
    PRODUCER_WORKFLOW_RUN_ID) hyphenated_fields+=(workflow-run-id);;
    PRODUCER_RUN_ATTEMPT) hyphenated_fields+=(run-attempt);;
    *) hyphenated_fields+=("${hyphenated//_/-}");;
  esac
done

inventory() { printf '%s\n' "$@"; }

assert_inventory() {
  local label=$1 actual=$2
  shift 2
  local expected
  expected=$(inventory "$@")
  [[ $actual == "$expected" ]] || {
    printf '%s inventory was missing, extra, duplicated, swapped, or reordered\n' "$label" >&2
    return 1
  }
}

workflow_outputs() {
  awk '
    /^    outputs:$/ { inside = 1; next }
    inside && /^jobs:$/ { exit }
    inside && /^      [[:alnum:]_-]+:/ { line = $0; sub(/^      /, "", line); sub(/:.*/, "", line); print line }
  ' "$1/.github/workflows/ci-role-macos-26-arm64.yml"
}

consumer_inputs() {
  awk '
    /^    inputs:$/ { inside = 1; next }
    inside && /^    outputs:$/ { exit }
    inside && /^      [[:alnum:]_-]+:/ { line = $0; sub(/^      /, "", line); sub(/:.*/, "", line); print line }
  ' "$1/.github/workflows/ci-role-macos-15-arm64.yml"
}

caller_mappings() {
  awk '
    /^  macos_15:$/ { job = 1; next }
    job && /^    with:$/ { inside = 1; next }
    inside && /^  [[:alnum:]_]+:$/ { exit }
    inside && /^      [[:alnum:]_-]+:/ {
      line = $0; sub(/^      /, "", line); split(line, pair, /: /); print pair[1] "=" pair[2]
    }
  ' "$1/.github/workflows/ci.yml"
}

validator_inventory() {
  awk '
    /^fields=\($/ { inside = 1; next }
    inside && /^\)$/ { exit }
    inside { for (i = 1; i <= NF; i++) if ($i ~ /^[A-Z][A-Z0-9_]*$/) print $i }
  ' "$1/scripts/validate-compatibility-stage-interface.sh"
}

validator_environment() {
  awk '
    /^      - name: Require the complete producer seal interface only for BURL-O001$/ { step = 1; next }
    step && /^        env:$/ { inside = 1; next }
    inside && /^        run:/ { exit }
    inside && /^          [A-Z][A-Z0-9_]*:/ {
      line = $0; sub(/^          /, "", line); split(line, pair, /: /); print pair[1] "=" pair[2]
    }
  ' "$1/.github/workflows/ci-role-macos-15-arm64.yml"
}

assert_line_once() {
  local file=$1 expected=$2 count
  count=$(rg -Fxc -- "$expected" "$file" || true)
  [[ $count == 1 ]] || { printf 'missing or duplicate static boundary: %s\n' "$expected" >&2; return 1; }
}

assert_workflow_shape() {
  local work_root=$1 mac26 mac15
  mac26=$work_root/.github/workflows/ci-role-macos-26-arm64.yml
  mac15=$work_root/.github/workflows/ci-role-macos-15-arm64.yml
  assert_inventory 'macOS 26 reusable workflow outputs' "$(workflow_outputs "$work_root")" "${common_outputs[@]}" \
    stage-artifact-name stage-artifact-id stage-upload-action-digest stage-rest-digest stage-created-at stage-expires-at stage-manifest-sha256 stage-attestation-subject-digest stage-attestation-bundle-sha256 producer-workflow-signer-sha workflow-run-id run-attempt \
    producer-sealing-check-run-id producer-sealing-receipt-artifact-id producer-sealing-receipt-upload-action-digest producer-sealing-receipt-rest-digest producer-sealing-receipt-created-at producer-sealing-receipt-expires-at producer-lineage-artifact-id producer-lineage-upload-action-digest producer-lineage-rest-digest producer-lineage-sha256 producer-lineage-attestation-subject-digest producer-lineage-attestation-bundle-sha256 producer-role consumer-role || return 1
  assert_inventory 'macOS 15 consumer inputs' "$(consumer_inputs "$work_root")" "${common_inputs[@]}" "${hyphenated_fields[@]}" || return 1

  local caller_expected=() environment_expected=('TICKET=${{ steps.validated.outputs.ticket_identity }}') validator_expected=()
  local index
  for index in "${!fields[@]}"; do
    local field=${fields[$index]} hyphenated=${hyphenated_fields[$index]}
    caller_expected+=("$hyphenated=\${{ needs.macos_26.outputs.$hyphenated }}")
    environment_expected+=("$field=\${{ inputs.$hyphenated }}")
    validator_expected+=("$field")
  done
  assert_inventory 'trusted caller compatibility mappings' "$(caller_mappings "$work_root" | tail -n 26)" "${caller_expected[@]}" || return 1
  # The caller has exactly the common eight mappings plus this closed 26-field
  # edge; an undeclared mapping is a contract change, not an inert default.
  assert_inventory 'trusted caller complete mappings' "$(caller_mappings "$work_root")" \
    'tested_source_sha=${{ needs.expected.outputs.tested_source_sha }}' 'expected_identity_base64=${{ needs.expected.outputs.expected_identity_base64 }}' 'expected_identity_sha256=${{ needs.expected.outputs.expected_identity_sha256 }}' 'expected_artifact_id=${{ needs.expected.outputs.artifact_id }}' 'expected_artifact_digest=${{ needs.expected.outputs.artifact_digest }}' 'run_identity=${{ needs.expected.outputs.run_identity }}' 'artifact_nonce=${{ needs.expected.outputs.artifact_nonce }}' 'base_sha=${{ needs.expected.outputs.base_sha }}' "${caller_expected[@]}" || return 1
  assert_inventory 'validator environment mappings' "$(validator_environment "$work_root")" "${environment_expected[@]}" || return 1
  assert_inventory 'ordered validator inventory' "$(validator_inventory "$work_root")" "${validator_expected[@]}" || return 1

  # Each of the 26 sealed values has one observable producer.  Names alone are
  # insufficient: a stale or swapped step output can still leave every public
  # interface declaration intact while silently exporting an empty or unrelated
  # value to macOS 15.
  local -a producer_job_outputs=(
    'stage-artifact-name=steps.stage.outputs.artifact_name'
    'stage-artifact-id=steps.upload_stage.outputs.artifact-id'
    'stage-upload-action-digest=steps.upload_stage.outputs.artifact-digest'
    'stage-rest-digest=steps.stage_rest.outputs.rest_digest'
    'stage-created-at=steps.stage_rest.outputs.created_at'
    'stage-expires-at=steps.stage_rest.outputs.expires_at'
    'stage-manifest-sha256=steps.stage.outputs.manifest_sha256'
    'stage-attestation-subject-digest=steps.stage.outputs.attestation_subject_digest'
    'stage-attestation-bundle-sha256=steps.stage_rest.outputs.attestation_bundle_sha256'
    'producer-workflow-signer-sha=steps.stage.outputs.producer_workflow_signer_sha'
    'workflow-run-id=steps.stage.outputs.workflow_run_id'
    'run-attempt=steps.stage.outputs.run_attempt'
    'producer-sealing-check-run-id=steps.seal_locator.outputs.check_run_id'
    'producer-sealing-receipt-artifact-id=steps.upload_receipt.outputs.artifact-id'
    'producer-sealing-receipt-upload-action-digest=steps.upload_receipt.outputs.artifact-digest'
    'producer-sealing-receipt-rest-digest=steps.lineage.outputs.receipt_rest_digest'
    'producer-sealing-receipt-created-at=steps.lineage.outputs.receipt_created_at'
    'producer-sealing-receipt-expires-at=steps.lineage.outputs.receipt_expires_at'
    'producer-lineage-artifact-id=steps.upload_lineage.outputs.artifact-id'
    'producer-lineage-upload-action-digest=steps.upload_lineage.outputs.artifact-digest'
    'producer-lineage-rest-digest=steps.lineage_rest.outputs.rest_digest'
    'producer-lineage-sha256=steps.lineage.outputs.sha256'
    'producer-lineage-attestation-subject-digest=steps.lineage.outputs.attestation_subject_digest'
    'producer-lineage-attestation-bundle-sha256=steps.lineage_rest.outputs.attestation_bundle_sha256'
    'producer-role=steps.stage.outputs.producer_role'
    'consumer-role=steps.stage.outputs.consumer_role'
  )
  [[ ${#producer_job_outputs[@]} == 26 ]] || return 1
  local producer_output field source
  for producer_output in "${producer_job_outputs[@]}"; do
    field=${producer_output%%=*}; source=${producer_output#*=}
    case $field in
      producer-sealing-check-run-id|producer-sealing-receipt-artifact-id|producer-sealing-receipt-upload-action-digest)
        assert_line_once "$mac26" "      $field: \${{ steps.validated.outputs.ticket_identity == 'BURL-O001' && $source || '' }}" || return 1
        assert_line_once "$mac26" "      $field: {value: \"\${{ jobs.seal.outputs.ticket-identity == 'BURL-O001' && jobs.seal.outputs.$field || '' }}\"}" || return 1
        ;;
      *)
        assert_line_once "$mac26" "      $field: \${{ $source }}" || return 1
        assert_line_once "$mac26" "      $field: {value: \"\${{ jobs.seal.outputs.$field }}\"}" || return 1
        ;;
    esac
  done

  local lineage_attest_line lineage_upload_line lineage_rest_line lineage_rest_block
  lineage_attest_line=$(rg -n -F 'id: attest_lineage' "$mac26" | cut -d: -f1)
  lineage_upload_line=$(rg -n -F 'id: upload_lineage' "$mac26" | cut -d: -f1)
  lineage_rest_line=$(rg -n -F 'id: lineage_rest' "$mac26" | cut -d: -f1)
  [[ $lineage_attest_line -lt $lineage_upload_line && $lineage_upload_line -lt $lineage_rest_line ]] || return 1
  lineage_rest_block=$(sed -n '/^      - id: lineage_rest$/,/^      - /p' "$mac26")
  grep -Fq 'REST validate exact producer lineage after upload' <<<"$lineage_rest_block" || return 1
  grep -Fq 'ARTIFACT_ID: ${{ steps.upload_lineage.outputs.artifact-id }}' <<<"$lineage_rest_block" || return 1
  grep -Fq 'ACTION_DIGEST: ${{ steps.upload_lineage.outputs.artifact-digest }}' <<<"$lineage_rest_block" || return 1
  grep -Fq 'ARTIFACT_NONCE: ${{ steps.validated.outputs.nonce }}' <<<"$lineage_rest_block" || return 1
  grep -Fq 'record-compatibility-stage-rest.sh --artifact-id "$ARTIFACT_ID" --upload-action-digest "$ACTION_DIGEST" --attestation-bundle compatibility-stage-producer-lineage-attestation.sigstore.json --github-output "$GITHUB_OUTPUT"' <<<"$lineage_rest_block" || return 1

  # The validator is the sole compatibility gate: all three downloads, all
  # three offline verifications, and consumer processing follow it; the normal
  # candidate path follows the conditional compatibility block for every ticket.
  local validator_line first_download first_verify consumer_line candidate_line
  validator_line=$(rg -n -F 'validate-compatibility-stage-interface.sh "$TICKET"' "$mac15" | cut -d: -f1)
  first_download=$(rg -n -F 'artifact-ids: "${{ inputs.stage-artifact-id }}"' "$mac15" | head -1 | cut -d: -f1)
  first_verify=$(rg -n -F 'gh attestation verify "$acquisition/stage/compatibility-stage-manifest.json"' "$mac15" | head -1 | cut -d: -f1)
  consumer_line=$(rg -n -F 'prepare-compatibility-stage-consumer.sh --expected "$EXPECTED_IDENTITY"' "$mac15" | head -1 | cut -d: -f1)
  candidate_line=$(rg -n -F 'Run candidate as credential-free data' "$mac15" | head -1 | cut -d: -f1)
  [[ $validator_line -lt $first_download && $first_download -lt $first_verify && $first_verify -lt $consumer_line && $consumer_line -lt $candidate_line ]] || return 1
  [[ $(rg -F -c 'gh attestation verify ' "$mac15") == 6 ]] || return 1
  [[ $(rg -F -c 'artifact-ids:' "$mac15") == 6 ]] || return 1
}

assert_workflow_shape "$root"

# Mutation fixtures prove the checker rejects source-shape changes rather than
# merely documenting the expected source. These are small textual fixtures;
# behavior and artifact fixtures own the heavier /var/tmp corpus separately.
shape_tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-compatibility-shape.XXXXXX")
trap 'rm -rf -- "$shape_tmp"' EXIT
mkdir -p "$shape_tmp/.github/workflows" "$shape_tmp/scripts"
cp "$root/.github/workflows/ci.yml" "$root/.github/workflows/ci-role-macos-26-arm64.yml" "$root/.github/workflows/ci-role-macos-15-arm64.yml" "$shape_tmp/.github/workflows/"
cp "$root/scripts/validate-compatibility-stage-interface.sh" "$shape_tmp/scripts/"

reject_shape_mutation() {
  if assert_workflow_shape "$shape_tmp"; then
    echo 'accepted malformed static compatibility workflow shape' >&2
    exit 1
  fi
}

perl -0pi -e 's/(      stage-artifact-name: \{value:.*?\}\n)/$1$1/' "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci-role-macos-26-arm64.yml" "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
perl -0pi -e 's/^      stage-artifact-name: \{required: false[^\n]*\n//m' "$shape_tmp/.github/workflows/ci-role-macos-15-arm64.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci-role-macos-15-arm64.yml" "$shape_tmp/.github/workflows/ci-role-macos-15-arm64.yml"
perl -0pi -e 's/(      stage-artifact-name: [^\n]+\n)(      stage-artifact-id: [^\n]+\n)/$2$1/' "$shape_tmp/.github/workflows/ci.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci.yml" "$shape_tmp/.github/workflows/ci.yml"
perl -0pi -e 's/(  STAGE_ARTIFACT_NAME )/  EXTRA_FIELD $1/' "$shape_tmp/scripts/validate-compatibility-stage-interface.sh"
reject_shape_mutation
cp "$root/scripts/validate-compatibility-stage-interface.sh" "$shape_tmp/scripts/validate-compatibility-stage-interface.sh"
perl -0pi -e 's/steps\.lineage_rest\.outputs\.rest_digest/steps.lineage.outputs.rest_digest/' "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci-role-macos-26-arm64.yml" "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
perl -0pi -e 's/jobs\.seal\.outputs\.producer-lineage-attestation-bundle-sha256/jobs.seal.outputs.producer-lineage-sha256/' "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci-role-macos-26-arm64.yml" "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
perl -0pi -e 's/^      - id: lineage_rest$/      - id: lineage_observation/m' "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
reject_shape_mutation
cp "$root/.github/workflows/ci-role-macos-26-arm64.yml" "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
perl -0pi -e 's/(      - id: lineage_rest\n.*?          ACTION_DIGEST: [^\n]+\n)          ARTIFACT_NONCE: \$\{\{ steps\.validated\.outputs\.nonce \}\}\n/$1/s' "$shape_tmp/.github/workflows/ci-role-macos-26-arm64.yml"
reject_shape_mutation

# The REST helpers receive untrusted response JSON. Exercise both the stage and
# lineage-observation invocations, then both stage and receipt lineage reads,
# to prove every response identity field is bound to caller authority before a
# binding, output, or signed lineage byte can be written.
mkdir -p "$shape_tmp/bin" "$shape_tmp/lineage-observation"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'case "${*: -1}" in' \
  '  */101) printf "%s\\n" "$FAKE_STAGE";;' '  */103) printf "%s\\n" "$FAKE_RECEIPT";;' \
  '  */404) printf "%s\\n" "$FAKE_ARTIFACT";;' '  *) exit 2;;' 'esac' >"$shape_tmp/bin/gh"
chmod +x "$shape_tmp/bin/gh"
repository=SkrOYC/burlmd
repository_id=9
run_id=4242
run_attempt=1
signer=0123456789012345678901234567890123456789
nonce=0123456789abcdef0123456789abcdef
stage_digest=$(printf 'a%.0s' {1..64})
receipt_digest=$(printf 'b%.0s' {1..64})
lineage_digest=$(printf 'c%.0s' {1..64})
stage_name="managed-evidence-authenticated-stage-macos-26-arm64-for-macos-15-arm64-$nonce"
receipt_name="managed-evidence-seal-receipt-macos-26-arm64-$nonce"
lineage_name="managed-evidence-producer-lineage-macos-26-arm64-for-macos-15-arm64-$nonce"
rest_artifact() {
  local id=$1 name=$2 digest=$3
  jq -cn --argjson id "$id" --arg name "$name" --arg digest "$digest" --arg signer "$signer" --argjson repository "$repository_id" --argjson run "$run_id" \
    '{id:$id,name:$name,digest:("sha256:"+$digest),expired:false,created_at:"2026-09-06T00:00:00Z",expires_at:"2035-09-06T00:00:00Z",workflow_run:{id:$run,repository_id:$repository,head_sha:$signer}}'
}
trusted_rest_env=(GITHUB_REPOSITORY="$repository" GITHUB_REPOSITORY_ID="$repository_id" GITHUB_RUN_ID="$run_id" GITHUB_RUN_ATTEMPT="$run_attempt" GITHUB_SHA="$signer" GH_TOKEN=fixture-token)
make_stage_binding() {
  jq -cn --arg nonce "$nonce" --arg name "$stage_name" --arg signer "$signer" --argjson repository "$repository_id" --argjson run "$run_id" --argjson attempt "$run_attempt" \
    '{stageArtifact:{artifactId:0,artifactName:$name,uploadActionDigest:("0"*64),artifactDigest:("sha256:"+("0"*64)),createdAt:"",expiresAt:"",expired:false},stageManifest:{ticketIdentity:"BURL-O001",repositoryId:$repository,workflowRunId:$run,runAttempt:$attempt,workflowSignerSha:$signer,artifactNonce:$nonce,producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",producerSealingCheckRunId:700},stageManifestSha256:("d"*64)}'
}
make_bound_stage_binding() {
  jq -cn --arg nonce "$nonce" --arg name "$stage_name" --arg digest "$stage_digest" --arg signer "$signer" --arg repository "$repository" --argjson repository_id "$repository_id" --argjson run "$run_id" --argjson attempt "$run_attempt" \
    '{stageArtifact:{artifactId:101,artifactName:$name,repositoryId:$repository_id,workflowRunId:$run,uploadActionDigest:$digest,artifactDigest:("sha256:"+$digest),createdAt:"2026-09-06T00:00:00Z",expiresAt:"2035-09-06T00:00:00Z",expired:false},stageManifest:{ticketIdentity:"BURL-O001",repositoryId:$repository_id,workflowRunId:$run,runAttempt:$attempt,workflowSignerSha:$signer,artifactNonce:$nonce,producerRole:"macos-26-arm64",consumerRole:"macos-15-arm64",producerSealingCheckRunId:700},stageManifestSha256:("d"*64),attestation:{bundleMember:"compatibility-stage-attestation.sigstore.json",bundleSha256:("e"*64),subjectName:"compatibility-stage-manifest.json",subjectDigest:("sha256:"+("d"*64)),predicateType:"https://slsa.dev/provenance/v1",issuer:"https://token.actions.githubusercontent.com",repository:$repository,repositoryId:$repository_id,workflowPath:".github/workflows/ci-role-macos-26-arm64.yml",jobWorkflowRef:($repository+"/.github/workflows/ci-role-macos-26-arm64.yml@refs/heads/master"),jobWorkflowSha:$signer,sourceRepositoryDigest:$signer,workflowRunId:$run,runAttempt:$attempt,checkRunId:700,runnerEnvironment:"github-hosted"}}'
}
printf bundle >"$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json"
FAKE_ARTIFACT=$(rest_artifact 404 "$lineage_name" "$lineage_digest")
export FAKE_ARTIFACT
env PATH="$shape_tmp/bin:$PATH" ARTIFACT_NONCE="$nonce" "${trusted_rest_env[@]}" \
  "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$lineage_digest" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$shape_tmp/lineage-observation/github-output"
[[ $(rg -Fxc "rest_digest=sha256:$lineage_digest" "$shape_tmp/lineage-observation/github-output") == 1 ]] || exit 1
[[ $(rg -Fxc "attestation_bundle_sha256=$(sha256sum "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" | awk '{print $1}')" "$shape_tmp/lineage-observation/github-output") == 1 ]] || exit 1

assert_record_rejected() {
  local invocation=$1 mutation=$2 name digest artifact binding output before
  case $invocation in
    generic) name=$lineage_name; digest=$lineage_digest;;
    stage) name=$stage_name; digest=$stage_digest;;
    *) exit 2;;
  esac
  artifact=$(jq "$mutation" <<<"$(rest_artifact 404 "$name" "$digest")")
  output=$shape_tmp/lineage-observation/rejected-output
  rm -f -- "$output"
  if [[ $invocation == generic ]]; then
    if env PATH="$shape_tmp/bin:$PATH" FAKE_ARTIFACT="$artifact" ARTIFACT_NONCE="$nonce" "${trusted_rest_env[@]}" \
      "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$digest" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$output" >/dev/null 2>&1; then
      echo "accepted generic lineage REST mutation: $mutation" >&2; exit 1
    fi
  else
    binding=$shape_tmp/lineage-observation/stage-binding.json
    make_stage_binding >"$binding"
    before=$(sha256sum "$binding" | awk '{print $1}')
    if env PATH="$shape_tmp/bin:$PATH" FAKE_ARTIFACT="$artifact" "${trusted_rest_env[@]}" \
      "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$digest" --binding "$binding" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$output" >/dev/null 2>&1; then
      echo "accepted stage REST mutation: $mutation" >&2; exit 1
    fi
    [[ $(sha256sum "$binding" | awk '{print $1}') == "$before" ]] || exit 1
  fi
  [[ ! -e $output ]] || exit 1
}

assert_record_accepted() {
  local invocation=$1 name digest binding output
  case $invocation in
    generic) name=$lineage_name; digest=$lineage_digest;;
    stage) name=$stage_name; digest=$stage_digest;;
    *) exit 2;;
  esac
  output=$shape_tmp/lineage-observation/accepted-$invocation-output
  rm -f -- "$output"
  if [[ $invocation == generic ]]; then
    env PATH="$shape_tmp/bin:$PATH" FAKE_ARTIFACT="$(rest_artifact 404 "$name" "$digest")" ARTIFACT_NONCE="$nonce" "${trusted_rest_env[@]}" \
      "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$digest" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$output"
  else
    binding=$shape_tmp/lineage-observation/stage-binding.json
    make_stage_binding >"$binding"
    env PATH="$shape_tmp/bin:$PATH" FAKE_ARTIFACT="$(rest_artifact 404 "$name" "$digest")" "${trusted_rest_env[@]}" \
      "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$digest" --binding "$binding" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$output"
  fi
  [[ -s $output ]] || { echo "missing accepted $invocation REST output" >&2; exit 1; }
}

assert_record_accepted generic
assert_record_accepted stage

for field in id name workflow_run.id workflow_run.repository_id workflow_run.head_sha; do
  case $field in
    id) missing='del(.id)'; wrong='.id=405';;
    name) missing='del(.name)'; wrong='.name="wrong"';;
    workflow_run.id) missing='del(.workflow_run.id)'; wrong='.workflow_run.id=999';;
    workflow_run.repository_id) missing='del(.workflow_run.repository_id)'; wrong='.workflow_run.repository_id=99';;
    workflow_run.head_sha) missing='del(.workflow_run.head_sha)'; wrong='.workflow_run.head_sha="ffffffffffffffffffffffffffffffffffffffff"';;
  esac
  assert_record_rejected generic "$missing"
  assert_record_rejected generic "$wrong"
  assert_record_rejected stage "$missing"
  assert_record_rejected stage "$wrong"
done
assert_record_rejected generic '.digest="sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
assert_record_rejected generic '.expired=true'

FAKE_ARTIFACT=$(rest_artifact 404 "$stage_name" "$stage_digest")
binding=$shape_tmp/lineage-observation/stage-binding.json
make_stage_binding >"$binding"
env PATH="$shape_tmp/bin:$PATH" "${trusted_rest_env[@]}" \
  "$root/scripts/record-compatibility-stage-rest.sh" --artifact-id 404 --upload-action-digest "$stage_digest" --binding "$binding" --attestation-bundle "$shape_tmp/lineage-observation/compatibility-stage-producer-lineage-attestation.sigstore.json" --github-output "$shape_tmp/lineage-observation/stage-output"
[[ $(jq -r '.stageArtifact.artifactId' "$binding") == 404 && $(jq -r '.stageArtifact.artifactName' "$binding") == "$stage_name" ]] || exit 1

FAKE_STAGE=$(rest_artifact 101 "$stage_name" "$stage_digest")
FAKE_RECEIPT=$(rest_artifact 103 "$receipt_name" "$receipt_digest")
export FAKE_STAGE FAKE_RECEIPT
make_bound_stage_binding >"$shape_tmp/lineage-observation/bound-stage-binding.json"
env PATH="$shape_tmp/bin:$PATH" "${trusted_rest_env[@]}" \
  "$root/scripts/write-compatibility-stage-lineage.sh" --stage-id 101 --stage-upload-action-digest "$stage_digest" --receipt-id 103 --receipt-upload-action-digest "$receipt_digest" --stage-binding "$shape_tmp/lineage-observation/bound-stage-binding.json" --output "$shape_tmp/lineage-observation/lineage.json" --github-output "$shape_tmp/lineage-observation/lineage-output"
LC_ALL=C jq -cS . "$shape_tmp/lineage-observation/lineage.json" | tr -d '\n' >"$shape_tmp/lineage-observation/canonical-lineage.json"
cmp -- "$shape_tmp/lineage-observation/canonical-lineage.json" "$shape_tmp/lineage-observation/lineage.json"
[[ $(jq -r '.producerSealingReceiptArtifact.artifactId' "$shape_tmp/lineage-observation/lineage.json") == 103 && $(jq -r '.producerSealingReceiptArtifact.artifactName' "$shape_tmp/lineage-observation/lineage.json") == "$receipt_name" ]] || exit 1

assert_lineage_rejected() {
  local target=$1 mutation=$2 output=$shape_tmp/lineage-observation/rejected-lineage.json
  rm -f -- "$output"
  make_bound_stage_binding >"$shape_tmp/lineage-observation/bound-stage-binding.json"
  FAKE_STAGE=$(rest_artifact 101 "$stage_name" "$stage_digest")
  FAKE_RECEIPT=$(rest_artifact 103 "$receipt_name" "$receipt_digest")
  if [[ $target == stage ]]; then FAKE_STAGE=$(jq "$mutation" <<<"$FAKE_STAGE"); else FAKE_RECEIPT=$(jq "$mutation" <<<"$FAKE_RECEIPT"); fi
  if env PATH="$shape_tmp/bin:$PATH" FAKE_STAGE="$FAKE_STAGE" FAKE_RECEIPT="$FAKE_RECEIPT" "${trusted_rest_env[@]}" \
    "$root/scripts/write-compatibility-stage-lineage.sh" --stage-id 101 --stage-upload-action-digest "$stage_digest" --receipt-id 103 --receipt-upload-action-digest "$receipt_digest" --stage-binding "$shape_tmp/lineage-observation/bound-stage-binding.json" --output "$output" --github-output "$shape_tmp/lineage-observation/rejected-lineage-output" >/dev/null 2>&1; then
    echo "accepted $target lineage REST mutation: $mutation" >&2; exit 1
  fi
  [[ ! -e $output ]] || exit 1
}

for field in id name workflow_run.id workflow_run.repository_id workflow_run.head_sha; do
  case $field in
    id) missing='del(.id)'; wrong='.id=999';;
    name) missing='del(.name)'; wrong='.name="wrong"';;
    workflow_run.id) missing='del(.workflow_run.id)'; wrong='.workflow_run.id=999';;
    workflow_run.repository_id) missing='del(.workflow_run.repository_id)'; wrong='.workflow_run.repository_id=99';;
    workflow_run.head_sha) missing='del(.workflow_run.head_sha)'; wrong='.workflow_run.head_sha="ffffffffffffffffffffffffffffffffffffffff"';;
  esac
  for target in stage receipt; do
    assert_lineage_rejected "$target" "$missing"
    assert_lineage_rejected "$target" "$wrong"
  done
done
assert_lineage_rejected stage '.expired=true'
assert_lineage_rejected receipt '.expired=true'
assert_lineage_rejected stage '.created_at="2026-09-07T00:00:00Z"'
assert_lineage_rejected stage '.expires_at="2035-09-07T00:00:00Z"'

printf 'complete compatibility interface and workflow-shape fixture passed\n'
