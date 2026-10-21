---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The Writer needs to create, select, or switch among genuinely separate collections after the one-collection workflow is dependable."
---
# Multiple Workspace interfaces

## Context

The first usable version begins with one fresh Workspace and one collection. Directories organize that collection.

## Decision

Defer interfaces for creating, selecting, or switching among separate collections. Also defer simultaneous Workspaces, cross-Workspace search, and Links across Workspace boundaries.

## Reason

The Writer chose one collection for first use and can organize it with Directories. Interfaces for multiple Workspaces would expand session, search, Link, and lifecycle scope before that single collection is dependable.

## Consequences

CAP-043 remains the later product commitment for opening or switching Workspaces, but the replacement near-term roadmap must not create implementation tickets for it. Delivered Workspace-partitioned storage and session-safety behavior remain intact.
