# Spike report: PATH-H002 Canonical cross-platform Workspace paths

## Time box

- **Budget:** 3 focused days
- **Clock start / stop:** fill during execution

## Question

- **Decision this spike must produce:** What deterministic on-disk component and collision algorithm stays unambiguous across Linux, default macOS, and Windows path rules?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-014-canonical-cross-platform-workspace-paths.md`
- **Target:** Note/asset path grammar, title derivation, identity, collisions, migration, and guest-path validation
- **Archetype / surface:** System/Native cross-platform storage format

## Codebase baseline

- **State today:** The delivered bundle derives filenames verbatim from titles and inherits host-filesystem equivalence.
- **Discovered constraints:** Titles remain in frontmatter; ghost Links must invert; Windows is an interoperability target; symlinks, submodules, traversal, and ambiguous aliases are refused; Linux and macOS runs must carry verified host facts and distinct operating systems rather than trusted labels, then cross hosts only through opaque SHA-256-verified handoff bundles.

## Options and trade-offs

- Compare a canonical encoded title-derived component with a canonical opaque component whose display title exists only in frontmatter.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the choice to cross-platform identity, human readability, invertibility, collision behavior, and migration safety
- **Rejected options:** fill one evidence-backed line per rejected candidate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-014; supersede ADR-004's title-verbatim path decision
- **Tickets unblocked in `tasks/active/`:** PATH-H005 directly; AUTH-H006, PREFLIGHT-H007, and their lifecycle, monitoring, Asset, Export, and sync dependents transitively
- **Tickets to add or split:** adapt or split PATH-H005 and downstream tickets if migration evidence changes their atomic boundary
- **Spec edits required:** final Technical Implementation; Architecture and Product Requirements only if measured behavior changes a boundary or user outcome
