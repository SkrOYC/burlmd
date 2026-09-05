---
owner: tasks
---

# Authorized tranche sequence

Each tranche uses its own isolated worktree, branch, and pull request created from the then-current merged `master`. Each ticket is one milestone and receives one full milestone review before the next ticket starts. Cross-tranche and cross-branch prerequisites must be merged into the base before the dependent tranche starts. Within one declared tranche, an earlier committed, validated, and independently reviewed milestone satisfies the next ticket; working-tree changes or an unreviewed commit don't.

1. `chore/epic-m-ci-foundation`: `BURL-M015`, then the reviewed `BURL-M003` implementation; rebase-merge the implementation to establish `TRUST_ANCHOR_SHA`.
2. `docs/epic-m-ci-evidence`: validate the merged anchor against itself, then review and merge only `.constitution/evidence/BURL-M003/managed-evidence.json`, `completion.md`, and `manifest.yaml`. This merge completes `BURL-M003`; the two-ticket Epic M is complete.
3. `spike/epic-h-canonical-foundations`: `BURL-H001`, then `BURL-H002`.
4. Constitution evidence-finalization pull request: reconcile the accepted Spike evidence across Stages 1 through 4.
5. `feat/epic-h-authority-foundation`: `BURL-H003`, `BURL-H005`, `BURL-H004`, `BURL-H006`, then `BURL-H007`.
6. Recreate `feat/epic-g-desktop-session` from merged `master`, surgically replay the reviewed Epic G M0 changes without overwriting the merged CI and headless-capture foundation, then execute the remaining Epic G dependency sequence.

Epic M completes after the evidence merge. Both H tranches remain partial delivery and don't archive Epic H. The session's terminal objective is to complete and archive Epic G after its replay.
