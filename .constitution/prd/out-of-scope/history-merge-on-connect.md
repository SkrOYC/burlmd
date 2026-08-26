# Divergent history unification during connection

**Status:** Rejected
**Related:** CAP-SYNC-07 (second-device join), CAP-SYNC-08 (guided Consolidation)

## The rejected concept
When a Writer connects a Workspace that contains local history to a Remote that also carries history, burlmd could unify every Version from both sides into one lineage.

## Why it was considered
Real users arrive with archives on both ends of a connect. Refusing all reconciliation between them would push people toward manual copying or abandonment, both worse than an opinionated answer.

## Why it was rejected
1. **Identity makes collisions structural, not incidental.** Two Workspaces can assign the same identity to different Notes. History unification must decide which lineage survives for every colliding identity.
2. **It duplicates what Suggestions already do, at the wrong granularity.** Content-level divergence after connection is exactly what CAP-SYNC-04 handles. Graph-level divergence before connection is a rarer, once-per-relationship problem.
3. **A cheaper supported path exists.** Guided consolidation (CAP-SYNC-08) migrates non-conflicting Notes into the connected Workspace, resolves each collision explicitly, touches nothing on the source side, and never merges commit graphs. Every Non-Destructive Reconciliation guarantee holds trivially.

## What replaced it
CAP-SYNC-08. Migrated Notes receive fresh history in the connected Workspace; the source Workspace remains a valid standalone archive on disk.

## Conditions that would reopen this
Sustained evidence that Writers hold parallel archives whose *Version histories*, not only current content, they need unified. That is a product decision about archival fidelity, not a synchronization defect.
