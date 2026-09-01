#!/usr/bin/env bash
# Receipt is intentionally pre-completion: status, conclusion, and timestamps
# are forbidden and later verified through the authenticated job API.
set -euo pipefail
receipt=${1:?receipt path required}
[[ -f $receipt && ! -L $receipt ]] || exit 2
jq -e '
  def sha: type == "string" and test("^[0-9a-f]{64}$");
  def gitsha: type == "string" and test("^[0-9a-f]{40}$");
  def positive: type == "number" and floor == . and . >= 1;
  def artifact($name):
    type == "object" and
    (keys | sort) == ["artifactDigest", "artifactId", "artifactName", "uploadActionDigest"] and
    (.artifactId | positive) and .artifactName == $name and
    (.uploadActionDigest | sha) and .artifactDigest == ("sha256:" + .uploadActionDigest);
  def path_for($role):
    if $role == "linux-x86_64" then ".github/workflows/ci-role-linux-x86-64.yml"
    elif $role == "macos-26-arm64" then ".github/workflows/ci-role-macos-26-arm64.yml"
    elif $role == "macos-15-arm64" then ".github/workflows/ci-role-macos-15-arm64.yml"
    else empty end;
  . as $r |
  ($r | type == "object") and
  (($r | keys | sort) == ["artifactNonce", "baseSha", "candidateArtifact", "expectedArtifact", "expectedIdentitySha256", "repositoryId", "role", "roleBundleSha256", "runAttempt", "runnerEnvironmentClaim", "schemaVersion", "sealedArtifact", "sealedBundleSha256", "sealingCheckRunId", "testedSourceSha", "trustAnchorSha", "workflowPath", "workflowRunId", "workflowSignerRef", "workflowSignerSha"]) and
  ($r.schemaVersion == 1) and ($r.expectedIdentitySha256 | sha) and
  ($r.repositoryId | positive) and ($r.workflowRunId | positive) and ($r.runAttempt | positive) and ($r.sealingCheckRunId | positive) and
  ($r.role | IN("linux-x86_64", "macos-26-arm64", "macos-15-arm64")) and
  ($r.workflowPath == path_for($r.role)) and ($r.workflowSignerRef == "refs/heads/master") and
  ($r.workflowSignerSha | gitsha) and ($r.trustAnchorSha | gitsha) and ($r.testedSourceSha | gitsha) and ($r.baseSha | gitsha) and
  ($r.artifactNonce | type == "string" and test("^[0-9a-f]{32}$")) and ($r.runnerEnvironmentClaim == "github-hosted") and
  ($r.expectedArtifact | artifact("managed-evidence-expected-" + $r.artifactNonce)) and
  ($r.candidateArtifact | artifact("managed-evidence-candidate-" + $r.role + "-" + $r.artifactNonce)) and
  ($r.sealedArtifact | artifact("managed-evidence-sealed-" + $r.role + "-" + $r.artifactNonce)) and
  ([$r.expectedArtifact.artifactId, $r.candidateArtifact.artifactId, $r.sealedArtifact.artifactId] | unique | length == 3) and
  ($r.roleBundleSha256 | sha) and ($r.sealedBundleSha256 | sha)
' "$receipt" >/dev/null
