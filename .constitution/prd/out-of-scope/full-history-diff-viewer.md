---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The Writer needs recovery beyond Note-level undo and redo and externally accessible local history."
---
# In-app Version history

## Context

burlmd records local Version history. An in-app surface could list, compare, and restore those Versions.

## Decision

Defer in-app Version listing, browsing, comparison, and confirmed restore. Preserve local history capture and its durability behavior.

## Reason

Dependable Note-level undo and redo cover first-use editing recovery. The external-change comparison surface serves a narrower authority decision and isn't a history browser.

## Consequences

CAP-044 remains the later product commitment, but the replacement near-term roadmap must not create implementation tickets for it. This deferral doesn't weaken local history capture or replace first-use undo and redo.
