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
   members and create the compatibility stage. The same job uploads and attests
   the stage. Its receipt binds the exact stage name, service artifact ID, bare
   upload-action digest, canonical REST digest, producing seal check-run ID,
   subject, signer, run, attempt, and attestation bundle.
7. Give the macOS 15 candidate job the exact trusted stage and producing-receipt
   inputs. Its trusted wrapper downloads both by immutable artifact ID with
   `digest-mismatch: error`. Before candidate execution, the wrapper verifies
   the seal-exported attestation bundles and binding offline. It then removes
   credentials and exposes only the verified producer members as read-only
   inputs. The candidate remains credential-free.
8. Require the macOS 15 seal to compare the candidate-carried producer lineage
   with the trusted wrapper record. It preserves the producer lineage unchanged
   and adds the consumer binding to its sealing receipt. Final aggregation
   verifies the complete producer-seal-to-consumer chain.
9. Keep strict credential removal and rejection of reserved artifact-name
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
  wrong-seal, unexpected, or consumer-unbound stage.
- Reviewed source and test contracts remain required. Provenance validation
  doesn't replace source review or test review.
- The role and aggregate JSON schemas are versions `15` and `17`. The embedded
  sealing receipt is version `2`. The raw contract is version `33`. These
  contracts separate candidate runtime guards from attested seal origin and
  bind the compatibility-stage lineage without encoding a platform-independent
  process-termination assertion.
- Managed non-Spike source-write authority is an immutable ordered mapping in
  the trust-anchor raw contract. Candidate input can't select, widen, reorder,
  or omit it. BURL-O004 additionally prepares its locked coordinator before
  authentication and executes only the identified binary against fixed
  read-only `/inputs`, with `/output/nightly-prd-meters.json` as its sole
  writable result and no repository mount.

## Verification anchors

- [REST API endpoints for workflow jobs](https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2026-03-10)
- [REST API endpoints for GitHub Actions artifacts](https://docs.github.com/en/rest/actions/artifacts?apiVersion=2026-03-10)
- [OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc#oidc-token-claims)
- [Verifying attestations offline](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline)
- [GitHub CLI `attestation verify` reference](https://cli.github.com/manual/gh_attestation_verify)
- [GitHub CLI `attestation trusted-root` reference](https://cli.github.com/manual/gh_attestation_trusted-root)
- [`actions/upload-artifact` interface at the pinned commit](https://github.com/actions/upload-artifact/blob/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/action.yml)
- [`actions/download-artifact` interface at the pinned commit](https://github.com/actions/download-artifact/blob/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c/action.yml)
- [`actions/attest` interface at the pinned commit](https://github.com/actions/attest/blob/1e69f48acb82d1966a394da916b4c1698aa569d6/action.yml)
- <https://github.com/containers/bubblewrap>
