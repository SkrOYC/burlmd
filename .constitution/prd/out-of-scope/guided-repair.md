---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "Repeated invalid external changes make correction through the Writer's editor or Agent materially unreliable."
---

# Guided repair

## Context

A guided repair surface could propose corrections for invalid external changes, preview every rewrite, and apply the accepted result.

## Decision

Defer guided repair. First use detects and flags invalid external input, preserves its incoming bytes and the last known-good Note, and keeps it outside authoritative editable state until the Writer or Agent corrects it.

## Reason

The preservation-first workflow satisfies data safety without adding a repair wizard before the normal external-editing workflow is proven.

## Consequences

CAP-041 remains the later product commitment for previewed repair, but the replacement near-term roadmap must not create implementation tickets for it. CAP-042 and CAP-050 retain validation, reporting, and preservation without silent repair.
