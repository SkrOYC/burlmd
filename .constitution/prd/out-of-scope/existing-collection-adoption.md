---
decision: deferred
date: 2026-10-14
ruling: reports/2026-10-14-interview-tasks.md
revisit_when: "The Writer needs burlmd to adopt an arbitrary existing collection instead of migrating Notes manually into the dependable fresh Workspace."
---

# Existing-collection adoption

## Context

Adopting an arbitrary existing collection requires inspection, conformance decisions, path handling, and Asset migration before burlmd can treat the collection as authoritative.

## Decision

Defer automatic inspection, repair, and adoption of arbitrary existing collections. The Writer will begin with one fresh Workspace and migrate Notes manually.

## Reason

Manual migration lets the Writer rewrite Notes to meet burlmd's requirements without making unfamiliar input a prerequisite for dependable local use.

## Consequences

CAP-036, CAP-059, and CAP-060 remain later product commitments, but the replacement near-term roadmap must not create implementation tickets for them. This deferral doesn't weaken conformance, portable paths, containment, or preservation of Notes created through burlmd.
