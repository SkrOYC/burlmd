---
id: ADR-0015
status: proposed
date: 2026-08-26
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-015: Structured Git-Shaped Reconciliation Analysis

**Status:** Proposed; implementation-blocking Spike
**Decision owner:** SPK-BURL-L001, then final Technical Implementation evolution

## Context

The delivered pull path treats a merge as either clean or a working tree containing text markers. Git reconciliation also includes rename, modify/delete, add/add, file-directory, mode, and multi-stage index conflicts. Some outcomes have no marker-bearing file. Same-device external edits are a separate optimistic-concurrency workflow and must never become Git Suggestions.

Git 2.54.0 is available in the pinned environment. Its `merge-tree` command exposes `--write-tree`, NUL-delimited output, messages, explicit merge bases, and unrelated-history control. That is a promising analysis boundary, but its output coverage and stability must be measured rather than inferred.

## Candidate decision

1. Remote reconciliation starts with a read-only analysis plan over exact base, local, and incoming object identities before the authoritative Workspace changes. `BND-10` obtains authenticated history and advertised refs from Remote (`BND-20`). Provider (`BND-14`) supplies only authorization and location. Asset outcomes can refer to Object identities, but transfer and storage remain `BND-11` and `BND-21` responsibilities.
2. The plan classifies content conflicts, Lifecycle Decisions, Asset Decisions, unsupported repository entries, and clean changes. It retains Git object IDs and paths needed to revalidate the plan before application.
3. Text Suggestions are derived only for conflicting Note content that the canonical AST can represent. Markers aren't the source of truth.
4. Lifecycle and asset choices apply as explicit Core transactions. The operation rechecks heads and affected object identities before publication and refuses a stale plan.
5. The authoritative worktree isn't the scratch space for analysis. Any temporary index or worktree is isolated, bounded to the Workspace repository, and recoverable after interruption.

## Evidence required

SPK-BURL-L001 compares `merge-tree`, temporary-index plumbing, and isolated-worktree porcelain against the same generated merge matrix. It covers clean and overlapping text edits; add/add and modify/delete; rename/edit, rename/delete, rename/rename, rename/add, and many-to-one rename; file and Directory conflicts and Directory rename effects; mode, symlink, submodule, and type changes; binary assets; case and Unicode collisions; dirty tracked files and untracked blockers; invalid merge bases and unrelated histories; and literal conflict-marker examples in Markdown code fences and raw regions.

The harness also injects interruption at every durable transition, including asset intent, Git commit creation, commit-identifier binding, queue repair, upload verification, and push. It must prove deterministic NUL-delimited parsing under `LC_ALL=C`, structured records with index stages, tentative tree IDs and exit status, no human-error-text parsing, no authoritative-worktree mutation, crash-resume and compare-and-swap inputs, and the commands needed to apply each decision.

Every tested Git process disables repository-controlled hooks, filters, merge drivers, credential helpers, and configuration unless the harness explicitly supplies a safe isolated value. Unsupported submodules and symlinks stop before Workspace mutation. The result also records the redistribution obligations for the exact Git executable and runtime intended for release artifacts.

## Consequences

- The final design may still use Git CLI operations, but it must pin the shipped CLI version and own a typed adapter instead of parsing human prose or relying on markers.
- `gix` may remain for local object and commit operations. The Spike decides responsibilities from measured capability, not a desire for one Git library.
- Remote sync and reconciliation implementation remain blocked until final Stage 3 publishes the typed plan and application contracts.

## Verification anchor

- Git 2.54.0 local `git merge-tree -h`; the Spike records the exact installed binary and fixtures.
