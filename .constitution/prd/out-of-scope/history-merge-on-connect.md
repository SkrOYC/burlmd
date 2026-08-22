# Out of Scope: Merging Divergent Histories on Connect

**Status:** Rejected
**Related:** CAP-SYNC-07 (second-device join), CAP-SYNC-08 (guided consolidation), ADR-005

## The rejected concept
When a user connects a Workspace that already contains local history to a Remote that also carries history — or joins on a second device that already holds Notes — reconciling the two commit graphs into one lineage, so that every version of every Note from both sides survives in one repository.

## Why it was considered
Real users arrive with archives on both ends of a connect. Refusing all reconciliation between them would push people toward manual copying or abandonment, both worse than an opinionated answer.

## Why it was rejected
1. **Identity makes collisions structural, not incidental.** A Note's identity is its path, so two devices each holding `Welcome.md` collide by construction. History merging must therefore decide, for every divergent version of every colliding file, which lineage survives — a full conflict engine over repositories rather than over Notes.
2. **It duplicates what Suggestions already do, at the wrong granularity.** Content-level divergence after connection is exactly what CAP-SYNC-04 handles. Graph-level divergence before connection is a rarer, once-per-relationship problem.
3. **A cheaper supported path exists.** Guided consolidation (CAP-SYNC-08) migrates non-conflicting Notes into the connected Workspace, resolves each collision explicitly, touches nothing on the source side, and never merges commit graphs. Every Non-Destructive Reconciliation guarantee holds trivially.

## What replaced it
CAP-SYNC-08. Migrated Notes receive fresh history in the connected Workspace; the source Workspace remains a valid standalone archive on disk.

## Conditions that would reopen this
Sustained evidence that users hold long-lived parallel archives whose *version histories* — not merely current content — they need unified. That is a different product decision about archival fidelity, not a sync bug fix.
