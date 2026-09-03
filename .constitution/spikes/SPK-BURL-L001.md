# Spike report: BURL-L001 Structured Git reconciliation analysis

## Effort budget

- **Budget:** 8 points, matching the effort of the owning Spike ticket BURL-L001
- **Stop rule:** stop and report when the budget is spent, whatever the state of the answer

## Question

- **Decision this spike must produce:** Which version-locked Git 2.54.0 command protocol yields complete typed reconciliation analysis without mutating the authoritative Workspace or executing repository-controlled behavior?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-015-structured-git-shaped-reconciliation-analysis.md`
- **Target:** structured analysis inputs for Suggestions, Lifecycle Decisions, Asset Decisions, crash resume, and compare-and-swap publication
- **Archetype / surface:** System/Native distributed version-control integration

## Codebase baseline

- **State today:** Production uses `gix` for selected local operations and the Git CLI for pull/push, collapsing conflicts toward marker-bearing working-tree errors.
- **Discovered constraints:** Structural and binary conflicts have no reliable marker representation; unrelated histories are refused; the release must ship the verified Git executable and runtime. Every candidate runs on distinct default Linux and macOS filesystems because case handling, Unicode precomposition, HFS protection, file modes, and checkout blockers vary by host. The hosts exchange opaque SHA-256-verified result bundles.

## Options and trade-offs

- Compare structured `git merge-tree --write-tree -z --messages`, a temporary-index plumbing protocol, and isolated temporary-worktree porcelain against the complete hostile corpus.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the choice to conflict completeness, deterministic parsing, execution isolation, durable identity, recovery, licensing, and solo-maintainer cost
- **Rejected options:** fill one evidence-backed line per rejected candidate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-015 and bind the Git responsibility split in final Stage 3
- **Tickets unblocked in `tasks/epics/`:** BURL-L002 directly; BURL-L003, BURL-L004, BURL-L006, BURL-L007, BURL-L008, and packaging dependents transitively
- **Tickets to add or split:** adapt the Git/reconciliation tickets if the accepted protocol changes command ownership or durable record boundaries
- **Spec edits required:** final Technical Implementation; Architecture only if evidence changes the logical reconciliation flow
