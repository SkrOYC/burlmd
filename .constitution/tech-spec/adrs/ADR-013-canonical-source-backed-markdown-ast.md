# ADR-013: Canonical Source-Backed Markdown AST Foundation

**Status:** Proposed; implementation-blocking Spike
**Decision owner:** SPK-AST-H001, then final Technical Implementation evolution

## Context

The delivered `AstNode` omits standard Markdown structure and treats source spans as a separate rendering aid. PRD v1.3.2 requires one exhaustive Core-owned document state used by parsing, editing, undo, search, conflict resolution, rendering, and indexing. The original source must remain authoritative so untouched bytes aren't normalized.

The current candidates are `markdown` 1.0.0 mdast, Comrak 0.54.0, and a complete burlmd model derived from `pulldown-cmark` events. The `markdown` crate exposes `to_mdast(&str, &ParseOptions) -> Result<Node, Message>`, position-bearing nodes, CommonMark, and GitHub Flavored Markdown constructs. That makes mdast the provisional default, not the winner: positions must be proven exact enough for source splices, and its model must cover burlmd's required extensions without a lossy shadow tree.

## Candidate decision

1. Core owns one `Document` containing the original source, one exhaustive extended tree, source ranges, stable editing identities valid for that document revision, and conformance state.
2. The standards foundation supplies the CommonMark and selected GitHub Flavored Markdown grammar. Burlmd extends that same tree with resolved and ghost Link semantics, Suggestion nodes, asset identity, conformance annotations, and editing metadata. These aren't maintained in a second pseudo-AST.
3. Flutter receives a render projection generated from the canonical tree. The projection isn't authoritative and cannot be edited independently.
4. A targeted edit changes source, then reparses into a new coherent `Document`. No production save serializes the whole tree.
5. Workspace identity, Directories, and object reachability belong to the Core-owned Workspace tree, not to Markdown nodes.

## Evidence required

SPK-AST-H001 must compare all four candidates on the same checked-in corpus: mdast, Comrak, and distinct complete models over `pulldown-cmark` 0.12.2 and 0.13.4. It must prove exhaustive representation of the selected syntax, exact byte positions, preservation of malformed and unsupported source, link classification, conflict representation, structural and range edits, existing Note-size performance meters, and Flutter Rust Bridge projection cost. A candidate fails if it needs a second canonical document model or cannot preserve untouched bytes.

## Consequences

- Production content-model work is blocked until final Stage 3 accepts one foundation and pins its versions and parse options.
- ADR-007's source-splice fidelity remains binding; only its claim that spans can't be fields of the canonical AST is expected to change.
- The existing `AstNode` name must be removed or explicitly renamed as a render projection in the final FFI contract.

## Verification anchors

- <https://docs.rs/markdown/1.0.0/markdown/fn.to_mdast.html>
- <https://docs.rs/comrak/0.54.0/comrak/nodes/index.html>
- <https://docs.rs/pulldown-cmark/0.13.4/pulldown_cmark/>
