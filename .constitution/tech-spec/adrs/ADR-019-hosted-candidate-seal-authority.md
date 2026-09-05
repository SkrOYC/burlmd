---
id: ADR-0019
status: accepted
date: 2026-09-04
certainty: settled
evidence:
  kind: ruling
  ref: "2026-09-04 user ruling: fresh-seal authority"
  date: 2026-09-04
  note: "The user accepted platform-specific cleanup obligations and made the fresh non-executing seal environment the sole provenance authority."
---
# ADR-019: Hosted candidate and seal authority

**Status:** Accepted
**Decision owner:** `BURL-M003`

## Context

Managed validation runs candidate code on standard GitHub-hosted Linux and
macOS environments. Candidate output can support a release decision only after
a separate sealing job validates and attests it.

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
   candidate bytes. It validates the expected identity, candidate job and
   hosted label, reserved artifact inventory and IDs, normalized REST digests,
   safe archive shape, schemas, and every declared member hash before it
   attests the sealed bundle and separate receipt.
6. Keep strict credential removal and rejection of reserved artifact name
   collisions on all roles.

## Consequences

- A surviving hosted-macOS candidate process cannot obtain signing authority or
  execute in the fresh sealing environment.
- On hosted macOS, a surviving candidate process can interfere with the later
  untrusted upload. The outcome is untrusted-output corruption or a fail-closed
  upload denial, not an authenticated candidate result.
- Accepted evidence authenticates reviewed workflow execution and sealed
  provenance. It does not establish lifecycle containment for arbitrary
  malicious macOS candidate code or make candidate output trustworthy by
  itself.
- Reviewed source and test contracts remain required. Provenance validation
  doesn't replace source review or test review.
- The role and aggregate JSON schemas are versions `10` and `12`. They
  record identity, job, artifact, and provenance facts; they don't encode a
  platform-independent process-termination assertion. The raw contract and
  executable PR #15 fixtures own this platform-specific execution policy.

## Verification anchors

- <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- <https://docs.github.com/en/actions/reference/security/secure-use>
- <https://github.com/containers/bubblewrap>
