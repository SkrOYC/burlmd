---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The configured Object Store must be replaced after one-store synchronization and credential updates are dependable."
---

# Object Store migration

## Context

Replacing the configured Object Store requires migration that preserves every Object reachable from current and retained history.

## Decision

Defer Object Store replacement. The first synchronization milestone supports one configured Object Store, credential updates, and safe failure handling.

## Reason

Credential updates keep the selected service usable without adding a second storage destination and a no-loss migration before synchronization works.

## Consequences

CAP-057 now covers credential updates only. A later Product Requirements Evolution pass must restore Object Store replacement before downstream stages schedule migration. No future replacement may silently lose historical images.
