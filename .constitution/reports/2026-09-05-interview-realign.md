# Realign interview record — managed CI authority chain

**Date:** 2026-09-05
**Target:** Realign
**Mode:** Evolution
**Depth:** Focused full security sweep

The user delegated this decision and approved the recommended ruling. The domain
is intrinsically high-complexity despite the narrow file delta: candidate code,
three hosted validation roles, cross-job artifacts, OIDC-backed attestations,
and a cross-version macOS handoff meet at one release trust boundary. The agreed
depth was therefore a full sweep of this security delta rather than a quick
pass. No generation-stage file changes in this interview.

## Evidence considered

- Authoritative `master` is `2d5ec3a`. It has no `.github/` workflow directory
  and none of the managed-evidence scripts added by PR #15. BND-15, BND-17, and
  `flow-release` consequently remain assumed; BND-16 is settled only by the
  earlier fresh-seal ruling, not by repository execution evidence.
- Constitution validation at that tip reports 0 errors and 0 warnings. Its
  relevant certainty inventory is 1 settled and 36 assumed Architecture
  records, 18 settled and 44 assumed TechSpec records, and 117 assumed Tasks.
  The validator also reports that 70% of open tickets are at the 8-point
  ceiling. No decayed-evidence warning created a separate agenda item.
- The binding release records are `JOB-09`, `CAP-075` through `CAP-080`,
  `NFC-34`, `NFC-35`, `NFC-37` through `NFC-39`, BND-15 through BND-19,
  `architecture/flows/flow-release.md`, ADR-019, the two CI evidence schemas,
  `contracts/provisional-spikes.toml`, and tickets `BURL-M003` and `BURL-O001`.
- PR #15 head `ee1a585` contains 7,280 added lines across four workflows and the
  managed-evidence implementation. Candidate jobs have only `contents: read`;
  fresh seal jobs alone receive `id-token: write` and `attestations: write`.
  Candidate commands also run behind the intended credential and runtime
  sanitization. Those least-privilege and fresh-environment properties remain
  correct and are preserved by this ruling.
- PR #15 review rounds fixed the preceding implementation and security defects.
  Round 6 records a remaining P1 logical-contract drift: REST job labels cannot
  cryptographically authenticate candidate hosted origin, and the BURL-O001
  stage is not bound end to end. The literal `BURL-M003` acceptance chain and its
  focused fixtures passed after the other fixes, but GitHub reports no check
  rollup for the PR. The verification evidence at `ee1a585` is the owner-posted
  milestone and review-loop record. PR #15 remains unmerged and must not be
  treated as authoritative repository evidence.
- A read-only reproduction at `ee1a585` passed `test-seal-validators.sh` and the
  complete `assert-ci-matrix.sh` gate, including the cold macOS checkout. The
  run emitted the expected negative-fixture diagnostics. It also warned that
  the installed `devenv` CLI is 2.2.2 while `devenv.lock` records input 2.1.2;
  that pre-existing tool warning doesn't change this authority ruling.
- GitHub's versioned [REST API endpoints for workflow
  jobs](https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2026-03-10)
  exposes runner name, group, and labels but no authenticated
  `runner_environment` field. GitHub documents `runner_environment` as an
  [OpenID Connect (OIDC)
  claim](https://docs.github.com/en/actions/reference/security/oidc#oidc-token-claims).
  Its [Use self-hosted runners in a
  workflow](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/use-in-a-workflow)
  permits runners without default labels and permits arbitrary custom labels.
  The `gh attestation verify` interface can reject self-hosted provenance and
  constrain the signer workflow, which is suitable for the fresh seal jobs that
  actually hold attestation authority.

## Phase A — delta sweep

### Candidate roles

All candidate jobs must remain credential-free data producers. They receive no
OIDC request capability, attestation permission, Actions API authority, or
repository-content write authority. Their commands may produce only an
untrusted bundle. The immutable trusted workflow fixes each candidate job's
`runs-on` value and reusable-workflow topology, and the runtime observes the
expected label and successful completion. That is a trusted-workflow and
runtime placement guard. It is useful fail-closed corroboration, but it is not
cryptographic proof that the candidate itself ran on GitHub-hosted hardware.

TechSpec v2.1.1 contradicts that limit. `validate-seal-rest.sh` accepts a
candidate from the job API when its label matches and `self-hosted` is absent;
`managed-evidence.sh` then constructs
`candidateJob.runnerEnvironment: github-hosted`. The aggregate schema requires
that value and `hostedOriginVerified: true`. A self-hosted runner can omit the
default `self-hosted` label and use a hosted-looking custom label, so these
observations cannot support the claimed authentication.

### Fresh seal roles

The existing fresh, non-executing seal jobs retain the cryptographic authority.
They validate the untrusted candidate artifact, attest the sealed bundle and
receipt, and expose a pre-completion seal locator. Final acquisition verifies
the attestation signer, source, invocation, and `runner_environment` claim, then
resolves the locator to one completed successful seal. This is the only hosted
origin that the accepted evidence may describe as cryptographically attested.

### BURL-O001 macOS handoff

The macOS 26 candidate produces the release archive that macOS 15 must probe.
PR #15 at `ee1a585` adds a separate `stage_macos_26_for_15` job. That job verifies
the macOS 26 seal and publishes a stage artifact, but macOS 15 receives only the
stage artifact name. Neither the macOS 15 sealed evidence nor the final
aggregate binds the stage artifact's service-assigned ID, upload/REST digest,
attestation, and producing seal locator. Artifact-name validation therefore
does not prove that the consumer and final report used the exact stage created
by the authenticated producer.

No adjacent product-scope, release-matrix, candidate credential, coordinator
credential-destruction, process-containment, or evidence-only-integration
decision changed during the sweep.

## Phase B — delegated ruling (OD-11)

Adopt **Split candidate placement from seal provenance and make the macOS 26
seal own the authenticated stage**.

1. Preserve candidate jobs as credential-free, with only `contents: read` and
   no OIDC or attestation authority. Preserve candidate output as untrusted.
2. Treat the candidate's static trusted-workflow placement, observed label,
   topology, and terminal result as a runtime guard only. Do not call it signed,
   cryptographically authenticated, or proof of GitHub-hosted origin.
3. Preserve each fresh seal job as the sole provenance authority. Accepted
   hosted-origin evidence comes from its verified attestation, including the
   GitHub-hosted runner claim, exact signer workflow and digest, source, and run
   invocation, plus its independently observed completed-success state.
4. For `BURL-O001` only, the existing macOS 26 seal also validates the declared
   producer members, constructs the compatibility stage, uploads and attests
   that stage, and records its exact artifact ID, action digest and canonical
   REST digest in the seal receipt. Do not create a fourth staging authority.
5. The trusted macOS 15 wrapper downloads that exact stage artifact by service
   ID, verifies its carried attestation bundle and producer-seal binding offline
   before exposing its files read-only to the credential-free candidate, and
   carries the stage artifact ID, digest, producing seal locator, and
   attestation result into its own sealed evidence. It receives no GitHub API
   credential, OIDC request capability, or attestation permission.
6. Final evidence aggregation verifies the same chain and retains it in the
   accepted report. Any absent, duplicate, substituted, expired, digest-mismatched,
   unattested, wrong-signer, wrong-run, wrong-role, or wrong-seal stage fails
   closed.

The rejected alternatives are granting candidates OIDC/attestation—which
collapses the least-privilege boundary by giving candidate execution a signing
capability—and retaining label-derived candidate authentication plus the
name-only staging job—which leaves both identified gaps open.

## Contradiction classification

This is both specification drift and an implementation defect. The intended
least-privilege separation is correct, but Architecture and TechSpec overclaim
what candidate-job REST observations prove, while the PR implements that
overclaim. The BURL-O001 staging placement and downstream bindings are also
physically incomplete. Because trust-boundary meaning belongs to Stage 2, the
PR cannot repair this solely as a Stage 3 patch or code change. PR #15 must wait
for the ordered Evolution passes and then conform without editing the
constitution in its code commit.

## Ordered realignment plan

### Architecture evolution

There is no Stage 1 delta: `JOB-09`, `CAP-075` through `CAP-080`, and the PRD
meters retain their current product outcomes.

Run `designing-solution-architecture` in Evolution mode. Update only the
release trust delta in BND-15, BND-16, BND-17, their edges,
`containers.md`, `flow-release.md`, `strategy.md`, `resilience.md`, and
`risks.md`. State that candidate placement and job completion are
trusted-workflow/runtime guards without cryptographic hosted-origin proof;
fresh seal provenance alone authenticates hosted origin. Add the logical
`BURL-O001` path in which the macOS 26 seal produces an authenticated
producer-to-consumer handoff, macOS 15 consumes it without credentials, and
Evidence Aggregation verifies its uninterrupted producer-seal-to-consumer
lineage. Preserve BND-16 as the existing trust boundary rather than adding a
shallow staging boundary. Cite this interview as ruling evidence and update the
Architecture changelog against PRD v2.0.5.

### TechSpec evolution

Run `specifying-technical-implementation` in Evolution mode. Revise ADR-019,
`contracts/provisional-spikes.toml`,
`contracts/ci-role-evidence.schema.json`,
`contracts/ci-evidence.schema.json`, their semantic validation rules and
fixtures in `guidelines.md`, and the TechSpec changelog. Split the current
generic job observation into an explicitly non-cryptographic candidate
placement observation and an attestation-backed sealing-job origin. Remove the
candidate-derived `runnerEnvironment: github-hosted` assertion and ensure
`hostedOriginVerified` means seal origin only.

For `BURL-O001`, make the macOS 26 `seal` job create, upload, and attest the
authenticated stage after producer validation. Extend the receipt and final
aggregate contracts with the exact stage artifact name and ID, bare upload
digest, canonical REST digest, producing sealing check-run locator, verified
attestation bundle and its subject/signer/run facts, and consumer binding. Pass
those trusted values into the macOS 15 workflow; its wrapper must use the pinned
download action's exact artifact-ID input and digest-mismatch failure, verify
the seal-exported attestation bundle offline before candidate execution, mount
only validated members read-only, and bind the unchanged lineage into the
macOS 15 seal. Update reserved-inventory, collision, substitution,
wrong-producer, wrong-locator, attestation, digest, and no-stage-ticket
fixtures. Preserve candidate permissions, fresh-seal permissions, credential
teardown, and the no-candidate-byte-execution rule.

### Tasks evolution

Run `planning-engineering-execution` in Evolution mode. Revise only
`BURL-M003` and `BURL-O001` plus the Tasks changelog and rendered
critical path. `BURL-M003` acceptance must stop claiming authenticated
candidate hosted origin, require the candidate-placement guard and
attestation-backed seal origin separately, require the seal-owned BURL-O001
stage chain and its negative fixtures, and keep the implementation/evidence
two-PR bootstrap. `BURL-O001` acceptance must require that exact macOS 26 stage
identity and attestation to survive macOS 15 consumption and final aggregation.
The existing EPIC-M and EPIC-O ownership already covers the workflow and script
paths; no new epic, dependency, or cross-epic order is implied. Re-estimate only
if the revised evidence work changes ticket uncertainty, then render and
validate.

After those passes, update PR #15 to the realigned contracts, rerun its exact
acceptance and mutation suites, and restart independent PR review. That code
work is deliberately outside this interview.

## Register handling

OD-01 through OD-10 remain unchanged. OD-11 is closed in this interview under
the user's delegated authority; it creates no unresolved downstream block.

The next authorized stage is `designing-solution-architecture`. Should I run
`designing-solution-architecture` now?
