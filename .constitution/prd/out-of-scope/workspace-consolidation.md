---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The Writer needs to combine independent collections after connecting and joining the same collection works end to end."
---

# Workspace Consolidation

## Context

Consolidation combines Notes and images from independent local collections, resolves identity and destination collisions, and leaves the source Workspace unchanged.

## Decision

Defer Consolidation beyond the first synchronization milestone. Connecting the single collection, joining that collection on another device, synchronizing Notes and images, and resolving concurrent edits remain required.

## Reason

The Writer chose one fresh collection and doesn't need independent histories combined before synchronization works for that collection.

## Consequences

CAP-070 remains a later product commitment, but the replacement near-term roadmap must not create implementation tickets for it.
