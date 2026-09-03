---
owner: tasks
---

# Authorized tranche sequence

Each tranche uses its own isolated worktree, branch, and pull request created from the then-current merged `master`. Each ticket is one milestone and receives one full milestone review before the next ticket starts. Cross-tranche and cross-branch prerequisites must be merged into the base before the dependent tranche starts. Within one declared tranche, an earlier committed, validated, and independently reviewed milestone satisfies the next ticket; working-tree changes or an unreviewed commit don't.

1. `chore/epic-m-ci-foundation`: `FLAKE-M002`, then the reviewed `CI-M003` implementation; rebase-merge the implementation to establish `TRUST_ANCHOR_SHA`.
2. `docs/epic-m-ci-evidence`: validate the merged anchor against itself, then review and merge only its accepted report and completion record. This merge completes `CI-M003`.
3. `spike/epic-h-canonical-foundations`: `AST-H001`, then `PATH-H002`.
4. Constitution evidence-finalization pull request: reconcile the accepted Spike evidence across Stages 1 through 4.
5. `feat/epic-h-authority-foundation`: `MODEL-H003`, `PATH-H005`, `ADAPT-H004`, `AUTH-H006`, then `PREFLIGHT-H007`.
6. Recreate `feat/epic-g-desktop-session` from merged `master`, surgically replay the reviewed Epic G M0 changes without overwriting the merged CI and headless-capture foundation, then execute the remaining Epic G dependency sequence.

The M bootstrap and both H tranches are partial delivery. They don't archive Epic M or Epic H, and the Epic G replay doesn't archive Epic G until every ticket in that epic is complete.
