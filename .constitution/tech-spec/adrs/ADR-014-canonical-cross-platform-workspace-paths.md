---
id: ADR-0014
status: proposed
date: 2026-08-26
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-014: Canonical Cross-Platform Workspace Paths

**Status:** Proposed; implementation-blocking Spike
**Decision owner:** SPK-BURL-H002, then final Technical Implementation evolution
**Supersedes when accepted:** ADR-004's title-verbatim filename choice and the matching OKF bundle section

## Context

The delivered format derives a filename verbatim from a title and lets the host filesystem decide equivalence. The same Git tree can therefore contain identities that collide or become unusable on default macOS or Windows filesystems. Windows is an interoperability target even though it isn't a release target.

The user selected a lowest-common-denominator on-disk format but intentionally left Unicode normalization, encoding, limits, and disambiguation to measurement. Choosing those rules by preference would create a permanent format migration.

## Candidate decision

1. Every Note and asset path consists only of canonical components accepted unchanged by Linux, default macOS filesystems, and Windows path rules.
2. A Note's display title remains in frontmatter and isn't constrained to equal its path component.
3. Core owns title-to-path derivation, collision disambiguation, concept identity, and ghost-Link inversion. Flutter and guest tools don't invent alternate derivations.
4. Preflight and live monitoring reject noncanonical guest paths until the Writer repairs or excludes them.
5. Note and asset discovery never follows symlinks, junction-like escape paths, or Git submodules.

## Evidence required

SPK-BURL-H002 must compare at least an encoded title-derived component and an opaque canonical component. It must cover Unicode normalization and case equivalence, Windows device names and invalid characters, trailing dots and spaces, component and full-path limits, deterministic collisions, case-only rename, round-trip title display, ghost creation, reserved burlmd paths, and path traversal. It must run filesystem probes on Linux and default macOS; Windows rules are fixture-driven in this phase.

## Consequences

- No production lifecycle, Link, monitoring, Export, Consolidation, or asset-path work proceeds until the final algorithm is accepted.
- Existing Workspaces require a previewed migration plan; a final format contract must state how collisions are repaired without silent data loss.
- Exact user-facing default Workspace locations remain a host-platform concern and aren't part of this decision.
