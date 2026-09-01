#!/usr/bin/env bash
# Tests for the trusted launcher boundary. Synthetic transports never invoke
# the production collector; their observation-only work uses the harness.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/managed-evidence-client-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

# The production grammar is exactly run|collect. Its reserved fixture prefix
# is rejected before any credential, checkout, or report path is used.
set +e
env ME_TRANSPORT=fixture bash "$root/scripts/managed-evidence.sh" collect >"$tmp/env.out" 2>"$tmp/env.err"
status=$?
set -e
[[ $status == 2 ]]
rg -Fq 'reserved fixture environment' "$tmp/env.err"

set +e
bash "$root/scripts/managed-evidence.sh" test-collect >"$tmp/mode.out" 2>"$tmp/mode.err"
status=$?
set -e
[[ $status == 2 ]]
rg -Fq 'usage:' "$tmp/mode.err"

# The harness is intentionally non-authoritative: it can only emit an
# observation below its temporary root and cannot choose a declared report.
bash "$root/scripts/managed-evidence-test-harness.sh" --workspace "$tmp" --contracts "$root/.constitution/tech-spec/contracts"
jq -e '.kind == "managed-evidence-test-observation" and .status == "observed"' "$tmp/observation.json" >/dev/null
! rg -Fq '"accepted"' "$tmp/observation.json"

# Verify the actual default SLSA v1 predicate created by the pinned
# actions/attest revision.  The predicate's external parameters intentionally
# have no `inputs` member: run identity and nonce are instead authenticated by
# the receipt, manifest, and unique artifact names.
predicate_function="$tmp/attestation-predicate.sh"
awk '/^attestation_predicate_valid\(\)/,/^}/' "$root/scripts/managed-evidence.sh" >"$predicate_function"
[[ -s $predicate_function ]]
source "$predicate_function"
REPOSITORY=SkrOYC/burlmd
workflow_signer=0123456789abcdef0123456789abcdef01234567
run_id=123456789
attempt=2
workflow_path() { case "$1" in linux-x86_64) printf .github/workflows/ci-role-linux-x86-64.yml;; *) return 1;; esac; }
subject=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
builder="https://github.com/$REPOSITORY/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/master"
invocation="https://github.com/$REPOSITORY/actions/runs/$run_id/attempts/$attempt"
fixture=$(jq -cn --arg subject "$subject" --arg signer "$workflow_signer" --arg builder "$builder" --arg invocation "$invocation" '
  [{attestation:{bundle:{mediaType:"application/vnd.dev.sigstore.bundle.v0.3+json"}},verificationResult:{signature:{certificate:{issuer:"https://token.actions.githubusercontent.com",sourceRepositoryURI:"https://github.com/SkrOYC/burlmd",sourceRepositoryDigest:$signer,sourceRepositoryRef:"refs/heads/master",buildSignerURI:$builder,buildSignerDigest:$signer,runnerEnvironment:"github-hosted",runInvocationURI:$invocation}},statement:{subject:[{name:"ci-sealed-role-evidence.tar.zst",digest:{sha256:$subject}}],predicateType:"https://slsa.dev/provenance/v1",predicate:{buildDefinition:{buildType:"https://actions.github.io/buildtypes/workflow/v1",externalParameters:{workflow:{repository:"https://github.com/SkrOYC/burlmd",path:".github/workflows/ci.yml",ref:"refs/heads/master"}},internalParameters:{github:{event_name:"workflow_dispatch",repository_id:"1",repository_owner_id:"2",runner_environment:"github-hosted"}},resolvedDependencies:[{uri:"git+https://github.com/SkrOYC/burlmd@refs/heads/master",digest:{gitCommit:$signer}}]},runDetails:{builder:{id:$builder},metadata:{invocationId:$invocation}}}}}}]')
attestation_predicate_valid "$fixture" "$subject" linux-x86_64
jq -e '.[0].verificationResult.statement.predicate.buildDefinition.externalParameters | has("inputs") | not' <<<"$fixture" >/dev/null
reject_predicate() { if attestation_predicate_valid "$1" "$subject" linux-x86_64; then printf '%s unexpectedly accepted\n' "$2" >&2; exit 1; fi; }
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.runDetails.builder.id = "https://github.com/SkrOYC/burlmd/.github/workflows/ci-role-linux-x86-64.yml@refs/heads/evil"' <<<"$fixture")" wrong-builder
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.ref = "refs/heads/evil"' <<<"$fixture")" wrong-ref
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runnerEnvironment = "self-hosted"' <<<"$fixture")" wrong-certificate-runner
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.internalParameters.github.runner_environment = "self-hosted"' <<<"$fixture")" wrong-predicate-runner
reject_predicate "$(jq '.[0].verificationResult.statement.predicate.buildDefinition.resolvedDependencies[0].digest.gitCommit = "ffffffffffffffffffffffffffffffffffffffff"' <<<"$fixture")" wrong-signer-sha
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runInvocationURI = "https://github.com/SkrOYC/burlmd/actions/runs/999/attempts/2"' <<<"$fixture")" wrong-run
reject_predicate "$(jq '.[0].verificationResult.signature.certificate.runInvocationURI = "https://github.com/SkrOYC/burlmd/actions/runs/123456789/attempts/3"' <<<"$fixture")" wrong-attempt
reject_predicate "$(jq '.[0].verificationResult.statement.subject[0].digest.sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' <<<"$fixture")" wrong-subject

# Exercise the production cleanup definitions in a disposable evidence tree.
# The only removable paths are contract-named preparation/coordinator roots;
# the declared report and result plus an unrelated sibling must survive every
# terminal path.
cleanup_functions="$tmp/cleanup-functions.sh"
awk '
  /^owned_cleanup_roots=\(\)/ {copy=1}
  /^# An interrupted evidence transaction/ {copy=0}
  copy {print}
' "$root/scripts/managed-evidence.sh" >"$cleanup_functions"
[[ -s $cleanup_functions ]]
run_cleanup_fixture() {
  local terminal=$1 fixture="$tmp/cleanup-$1" status
  mkdir -p "$fixture/.constitution/prototypes/ast/managed-evidence-prepare" \
    "$fixture/.constitution/prototypes/ast/managed-evidence-coordinator" \
    "$fixture/.constitution/prototypes/ast"
  : >"$fixture/.constitution/prototypes/ast/managed-evidence-prepare/scratch"
  : >"$fixture/.constitution/prototypes/ast/managed-evidence-coordinator/scratch"
  : >"$fixture/.constitution/prototypes/ast/results.json"
  : >"$fixture/.constitution/prototypes/ast/report.json"
  : >"$fixture/.constitution/prototypes/ast/unrelated-sentinel"
  set +e
  bash -ceu '
    source "$1"
    evidence_root=$2
    tmp="$evidence_root/scratch"
    auth_config="$tmp/auth.conf"
    mkdir -p "$tmp"; : >"$auth_config"
    register_owned_cleanup_root .constitution/prototypes/ast/managed-evidence-prepare
    register_owned_cleanup_root .constitution/prototypes/ast/managed-evidence-coordinator
    ! register_owned_cleanup_root .constitution/prototypes/ast/results.json
    interrupted() { trap - HUP INT TERM; exit 2; }
    trap cleanup EXIT
    trap interrupted HUP INT TERM
    case "$3" in success) exit 0;; rejection) exit 1;; signal) kill -TERM "$$";; esac
  ' -- "$cleanup_functions" "$fixture" "$terminal"
  status=$?
  set -e
  case "$terminal" in success) [[ $status == 0 ]];; rejection) [[ $status == 1 ]];; signal) [[ $status == 2 ]];; esac
  [[ ! -e $fixture/.constitution/prototypes/ast/managed-evidence-prepare ]]
  [[ ! -e $fixture/.constitution/prototypes/ast/managed-evidence-coordinator ]]
  [[ -f $fixture/.constitution/prototypes/ast/results.json ]]
  [[ -f $fixture/.constitution/prototypes/ast/report.json ]]
  [[ -f $fixture/.constitution/prototypes/ast/unrelated-sentinel ]]
}
run_cleanup_fixture success
run_cleanup_fixture rejection
run_cleanup_fixture signal

# Production keeps complete JSON Schema validation on both terminal paths.
rg -Fq 'validate_schema "$AGGREGATE_SCHEMA" "$report_tmp"' "$root/scripts/managed-evidence.sh"
rg -Fq 'validate_schema "$ROLE_SCHEMA" "$manifest"' "$root/scripts/managed-evidence.sh"
rg -Fq -- '--source-digest "$workflow_signer"' "$root/scripts/managed-evidence.sh"
rg -Fq -- '--source-ref refs/heads/master' "$root/scripts/managed-evidence.sh"
! sed -n '/^verify_attestation()/,/^}$/p' "$root/scripts/managed-evidence.sh" | rg -F -- '--source-digest "$tested"'
printf 'managed-evidence client boundary tests passed\n'
