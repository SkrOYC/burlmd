# Spike report: GIT-L001 Structured Git reconciliation analysis

## Time box

- **Budget:** 3 focused days
- **Clock start / stop:** fill during execution

## Question

- **Decision this spike must produce:** Which version-locked Git 2.54.0 command protocol yields complete typed reconciliation analysis without mutating the authoritative Workspace or executing repository-controlled behavior?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-015-structured-git-shaped-reconciliation-analysis.md`
- **Target:** structured analysis inputs for Suggestions, Lifecycle Decisions, Asset Decisions, crash resume, and compare-and-swap publication
- **Archetype / surface:** System/Native distributed version-control integration

## Codebase baseline

- **State today:** Production uses `gix` for selected local operations and the Git CLI for pull/push, collapsing conflicts toward marker-bearing working-tree errors.
- **Discovered constraints:** Structural and binary conflicts have no reliable marker representation; unrelated histories are refused; the release must ship the verified Git executable and runtime.

## Options and trade-offs

- Compare structured `git merge-tree --write-tree -z --messages`, a temporary-index plumbing protocol, and isolated temporary-worktree porcelain against the complete hostile corpus.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the choice to conflict completeness, deterministic parsing, execution isolation, durable identity, recovery, licensing, and solo-maintainer cost
- **Rejected options:** fill one evidence-backed line per rejected candidate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-015 and bind the Git responsibility split in final Stage 3
- **Tickets unblocked in `tasks/active/`:** ANALYZE-L002 directly; SCHED-L003, SUGGEST-L004, LIFE-L006, ASSET-L007, FINAL-L008, and packaging dependents transitively
- **Tickets to add or split:** adapt the Git/reconciliation tickets if the accepted protocol changes command ownership or durable record boundaries
- **Spec edits required:** final Technical Implementation; Architecture only if evidence changes the logical reconciliation flow
