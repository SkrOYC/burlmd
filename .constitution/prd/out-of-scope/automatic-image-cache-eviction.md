---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "Retained downloaded image copies create material local-storage pressure after synchronization is dependable."
---

# Automatic local image cleanup

## Context

A connected Workspace can remove eligible inactive local Object copies after it verifies a remote copy and confirms that no Note needs the bytes offline.

## Decision

Defer automatic cleanup and retain downloaded image copies during the first synchronization milestone.

## Reason

Retaining copies reduces early lifecycle complexity and preserves offline availability at the cost of greater local disk use.

## Consequences

CAP-058 remains a later product commitment, but the replacement near-term roadmap must not create implementation tickets for it. Future eviction still requires a verified remote copy and must preserve active offline images and every Object reachable from Protected State.
