# Spike report: AST-H001 Canonical source-backed Markdown AST foundation

## Time box

- **Budget:** 3 focused days
- **Clock start / stop:** fill during execution

## Question

- **Decision this spike must produce:** Which standards foundation can support burlmd's one exhaustive Core-owned Markdown AST while preserving exact source bytes, interaction semantics, and performance?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-013-canonical-source-backed-markdown-ast.md`
- **Target:** canonical document tree, source ranges, editing/indexing adapters, and Flutter Rust Bridge render projection
- **Archetype / surface:** System/Native desktop Markdown editor

## Codebase baseline

- **State today:** Production uses `pulldown-cmark =0.12.2` events and a reduced `AstNode` render/edit projection.
- **Discovered constraints:** The original source remains authoritative; untouched bytes can't be normalized; Flutter can't own a second document model; all declared syntax and burlmd domain nodes must be represented. Performance and FFI projection cost require distinct hosts that match the complete PRD profiles for CPU, cores, memory, storage, graphics, display, AC power, and thermal state. The result tool captures those facts from system APIs. The hosts exchange opaque SHA-256-verified handoff bundles rather than relying on a shared checkout.

## Options and trade-offs

- Compare `markdown` 1.0.0 mdast, Comrak 0.54.0, and separate complete burlmd models derived from `pulldown-cmark` 0.12.2 and 0.13.4 events using the exact contract corpus and measurements.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the recommendation to Edit Fidelity, canonical Core ownership, syntax coverage, performance, and projection cost
- **Rejected options:** fill one evidence-backed line per rejected candidate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-013; revise ADR-007 and FFI contracts in final Stage 3
- **Tickets unblocked in `tasks/active/`:** MODEL-H003 directly; ADAPT-H004, EDIT-G008, FIND-G009, SUGGEST-L004, and later dependents transitively
- **Tickets to add or split:** adapt these tickets when the accepted model changes physical scope or estimates
- **Spec edits required:** measured Technical Implementation evolution; earlier stages only if evidence changes product behavior or boundaries
