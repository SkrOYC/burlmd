---
id: ADR-0019
status: accepted
date: 2026-09-05
certainty: settled
evidence:
  kind: ruling
  ref: reports/2026-09-05-interview-realign.md
  date: 2026-09-05
  note: "OD-11 preserves the fresh non-executing seal as the sole hosted-origin authority, limits candidate placement to runtime guards, and assigns the BURL-O001 compatibility stage to the macOS 26 seal."
---
# ADR-019: Hosted candidate and seal authority

**Status:** Accepted
**Implementation owners:** `BURL-M003` and `BURL-O001`

## Context

Managed validation runs candidate code on standard GitHub-hosted Linux and
macOS environments. Candidate output can support a release decision only after
a separate sealing job validates and attests it.

The GitHub REST API for workflow jobs exposes runner labels and completion
state. It doesn't expose a cryptographically authenticated runner-environment
field. A self-hosted runner can omit default labels and use a custom label.
Candidate job placement, topology, labels, and completion are therefore useful
fail-closed guards, but they don't prove GitHub-hosted origin.

Linux can establish the required candidate-process boundary with Bubblewrap
`0.11.2`. A trusted launcher starts candidate commands through `env -i` in a
private PID namespace. The launcher must prove that an adversarial double-fork
process does not survive teardown before it uploads the untrusted bundle.

Standard GitHub-hosted macOS environments do not provide an equivalent
candidate-process containment boundary. Process groups, environment markers,
and process-table scans cannot prove that arbitrary candidate code cannot
survive. The release contract must not make that claim.

## Decision

1. Treat every candidate artifact as untrusted on every platform.
2. Keep Linux candidate containment as a required evidence claim. The trusted
   launcher uses `env -i` and Bubblewrap `0.11.2` with a private PID namespace,
   verifies the teardown lock, and rejects a surviving double-fork probe before
   candidate artifact upload.
3. On hosted macOS, run bounded cleanup only. The launcher must remove its
   credentials and configuration, terminate and reap known test processes, and
   record cleanup failure. It must not claim universal containment, zero
   survivors, or that arbitrary candidate code cannot falsify its own
   untrusted output.
4. Give candidate commands only the declared toolchain, locale, input, and
   output variables. Candidate commands receive no OIDC, attestation, Actions,
   artifact-runtime, or repository-content write authority. The trusted
   workflow wrapper receives short-lived artifact-upload authority after
   candidate commands finish.
5. Make the fresh `seal` job the sole provenance authority. It never executes
   candidate bytes. It validates the expected identity, candidate runtime
   guards, reserved artifact inventory and IDs, canonical REST digests, safe
   archive shape, schemas, and every declared member hash. It then attests the
   sealed bundle and separate receipt. Only the seal attestation can establish
   `runner_environment: github-hosted`.
6. For `BURL-O001`, make the macOS 26 `seal` job validate the declared producer
   members and create the compatibility stage through the trusted
   `scripts/prepare-compatibility-stage.sh` helper. The same job uploads and
   attests the stage and its sealing receipt. The trusted
   `scripts/record-compatibility-stage-rest.sh` helper binds the uploaded stage
   to its REST identity, digest, lifetime, and attestation. After the receipt
   REST object exists, the trusted `scripts/write-compatibility-stage-lineage.sh`
   helper creates the immutable `compatibility-stage-producer-lineage.json`
   transport artifact. The seal attests that artifact. The canonical bytes bind
   the exact stage and producer receipt name, service ID, action digest, REST
   digest, `createdAt`, `expiresAt`, producing seal check-run ID, subject,
   signer, run, attempt, and attestation. Static workflow-shape fixtures pin the
   exact ordered 26 producer-output declarations, consumer string-input
   declarations, and observable trusted caller mappings. For each canonical
   hyphenated consumer input, the fixture also pins its uppercase environment
   variable and its matching position in the validator's ordered 26-field
   inventory.
7. Give the macOS 15 candidate job exact trusted stage, producing-receipt, and
   producer-lineage artifact inputs. Before caller mapping, the macOS 26 output
   boundary explicitly ticket-gates and conditionally normalizes the three
   producer sealing aliases to empty strings for every ticket other than
   `BURL-O001`. It does not rely on omitted reusable-workflow input defaults.
   Before any compatibility artifact acquisition or consumer processing, the
   macOS 15 trusted wrapper invokes
   `scripts/validate-compatibility-stage-interface.sh` with the fixed 26-field
   mapping. For `BURL-O001`, accepted values are all nonempty and proceed to all
   three immutable-ID downloads, offline verification, and the consumer helper.
   For every other ticket, accepted values are all empty. The wrapper skips only
   compatibility acquisition, offline verification, and consumer processing, then
   continues the ordinary candidate path. The consumer helper validates the
   result files, hashes and validates canonical lineage bytes, requires the
   signed producer receipt to remain unexpired, removes credentials, and exposes
   only verified producer members as read-only inputs. The candidate remains
   credential-free.
8. Require the macOS 15 seal to compare the candidate-carried parsed lineage,
   lineage SHA-256, lineage transport receipt, and consumer binding with the
   trusted wrapper record. The binding's `downloadedStageArtifactId` must equal
   `producerLineage.stageArtifact.artifactId`. It preserves them in its sealing
   receipt. Final aggregation verifies the complete producer-seal-to-consumer
   chain.
9. Keep sealing receipt version `2` limited to facts available before its
   upload. Each reusable role workflow must expose the receipt upload step's
   artifact ID and bare digest as `sealing-receipt-artifact-id` and
   `sealing-receipt-upload-action-digest`. A fresh caller `receipt_digests` job
   must carry all six outputs in one identity-bound transport artifact. After
   completion, the collector must resolve the transport's immutable ID from the
   exact run inventory. It must download the raw archive by ID and compare its
   SHA-256 with the canonical REST digest before extraction. The aggregate must
   retain this check in `receiptDigestTransportArtifact`. The collector then
   compares each transported receipt digest with the matching REST digest and
   retains both in `origin.sealingReceiptArtifact`. The caller job doesn't
   execute or download candidate bytes and isn't a hosted-origin authority.
   Transport verification detects corrupt or substituted downloaded bytes. It
   doesn't provide provenance independent of GitHub's artifact service.
10. Keep strict credential removal and rejection of reserved artifact-name
   collisions on all roles.

## Consequences

- A surviving hosted-macOS candidate process cannot obtain signing authority or
  execute in the fresh sealing environment.
- On hosted macOS, a surviving candidate process can interfere with the later
  untrusted upload. The outcome is untrusted-output corruption or a fail-closed
  upload denial, not an authenticated candidate result.
- Accepted evidence authenticates reviewed workflow execution and sealed
  provenance from the fresh seal. It does not authenticate candidate hosted
  origin, establish lifecycle containment for arbitrary malicious macOS
  candidate code, or make candidate output trustworthy by itself.
- Candidate placement, topology, label, and completion mismatches reject the
  role. Passing those guards doesn't change their noncryptographic status.
- `BURL-O001` rejects a missing, duplicate, substituted, expired,
  digest-mismatched, unattested, wrong-signer, wrong-run, wrong-role,
  wrong-seal, unexpected, stale-producer-receipt, noncanonical-lineage,
  lineage-SHA-mismatch, or consumer-unbound stage.
- Reviewed source and test contracts remain required. Provenance validation
  doesn't replace source review or test review.
- The role and aggregate JSON schemas are versions `15` and `19`. The embedded
  sealing receipt is version `2`. The raw contract is version `36`. These
  contracts separate candidate runtime guards from attested seal origin and
  bind an immutable canonical compatibility-stage lineage. They also carry the
  post-upload receipt digest without making the receipt self-report it. The
  aggregate also retains the receipt-digest transport's REST digest and raw
  download hash.
- Managed non-Spike source-write authority is an immutable ordered mapping in
  the trust-anchor raw contract. Candidate input can't select, widen, reorder,
  or omit it. BURL-O004 additionally prepares its locked coordinator before
  authentication and executes only the identified binary against fixed
  read-only `/inputs`, with `/output/nightly-prd-meters.json` as its sole
  writable result and no repository mount.
- The five compatibility-stage helpers are immutable members of
  `ci_bootstrap.trust_anchor.trusted_control_paths`. The client requires their
  bytes and object modes to equal the trust anchor before dispatch and during
  collection. Any change requires reviewed trust-anchor rotation and
  evidence-only completion.
- `scripts/write-receipt-digest-observation.sh` is also an immutable member of
  `ci_bootstrap.trust_anchor.trusted_control_paths`. It writes only the
  three-role receipt digest transport from trusted caller outputs.
- The collector acquires that transport by immutable artifact ID. It verifies
  the raw archive against the selected artifact's REST digest before reading
  the JSON member.

## Verification anchors

- [REST API endpoints for workflow jobs](https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2026-03-10)
- [REST API endpoints for GitHub Actions artifacts](https://docs.github.com/en/rest/actions/artifacts?apiVersion=2026-03-10)
- [OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc#oidc-token-claims)
- [Verifying attestations offline](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline)
- [GitHub CLI `attestation verify` reference](https://cli.github.com/manual/gh_attestation_verify)
- [GitHub CLI `attestation trusted-root` reference](https://cli.github.com/manual/gh_attestation_trusted-root)
- [`actions/upload-artifact` interface at the pinned commit](https://github.com/actions/upload-artifact/blob/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/action.yml)
- [Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-outputs-from-a-reusable-workflow)
- [`actions/download-artifact` interface at the pinned commit](https://github.com/actions/download-artifact/blob/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c/action.yml)
- [`actions/attest` interface at the pinned commit](https://github.com/actions/attest/blob/1e69f48acb82d1966a394da916b4c1698aa569d6/action.yml)
- <https://github.com/containers/bubblewrap>
