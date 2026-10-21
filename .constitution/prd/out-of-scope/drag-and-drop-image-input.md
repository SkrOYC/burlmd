---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "File selection and clipboard paste are dependable and drag-and-drop would materially improve repeated image entry."
---

# Drag-and-drop image input

## Context

Images can enter a Note through file selection, clipboard paste, or drag-and-drop.

## Decision

Defer drag-and-drop. First use includes file selection and clipboard paste.

## Reason

The two required inputs cover deliberate file import and copied image data while sharing one safe local Asset outcome.

## Consequences

CAP-031 no longer promises drag-and-drop. A later Product Requirements Evolution pass must restore that input before downstream stages schedule it.
