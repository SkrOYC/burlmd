---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "A portable single-file Workspace transfer provides material value beyond the complete plain-folder Export."
---

# Bundle Archive Export

## Context

A Bundle Archive would package one complete Workspace revision into a single file.

## Decision

Defer Bundle Archive Export. First use exports a verified plain folder containing Notes and referenced local images.

## Reason

The plain-folder form provides the required application-independent exit path without adding archive creation, replacement, and validation behavior.

## Consequences

CAP-046 and CAP-048 now describe only the required plain-folder form. A later Product Requirements Evolution pass must restore an active Bundle Archive capability before downstream stages schedule it.
