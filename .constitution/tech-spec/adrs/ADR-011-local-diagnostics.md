# ADR-011: Local Structured Log With Content-Excluding Diagnostics Export

**Status:** Accepted

## Context
The Core computes diagnostic outcomes that go nowhere: PR #7 review round 11 recorded that `ScratchSweep`'s result is unreachable in production because "this crate has no logging channel," and the write tiers, scheduler, and bootstrap all have failure modes a user could report if anything captured them. CAP-SUP-01 requires a diagnostics export; Zero Content Telemetry forbids collection that includes Note content or phoning home.

## Decision
1. **One structured logging channel Core-side, writing to a rotating local file** under the application data directory, next to — not inside — the Workspace bundle. Rotation caps total size; the log is best-effort infrastructure and must never make logging failures into user-facing failures. Candidate named by ruling Q11: the `tracing` crate family; the ticket that wires the channel confirms and pins it in `stack.md` rather than this ADR pre-empting the BOM.
2. **Note content never enters the log in any form.** Not truncated, not hashed, not sampled. Paths and concept ids may appear; body text may not. This is the line that makes the export safe without redaction heuristics.
3. **Diagnostics are exported on demand only** via `collect_diagnostics`, returning recent entries plus app/schema versions. Nothing transmits automatically; there is no telemetry endpoint and none may be added without reversing `prd/out-of-scope/telemetry-upload.md`.
4. **Every component that can fail reports that it did** through this channel — sweep outcomes, tier-2 write errors, scheduler retries, bootstrap steps. Resilience.md's observability section is the logical statement; this ADR is its physical commitment.

## Consequences
- **Positive:** Silent-failure modes — the class this project has repeatedly caught in review — acquire a witness.
- **Positive:** Bug reports become actionable: the bundle answers "what happened" without asking users to reproduce anything.
- **Negative:** Log discipline is a standing review obligation: a stray `{:?}` on a Note struct would violate the content exclusion exactly the way a redacted `Debug` impl once had to be fixed for credentials. Content-bearing types get the same treatment tokens got.
- **Neutral:** The channel is also where future supportability features (verbose modes, problem reporters) would hang; nothing else is built now.
