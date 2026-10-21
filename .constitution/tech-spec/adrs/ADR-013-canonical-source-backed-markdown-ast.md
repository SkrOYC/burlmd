---
id: ADR-0013
status: proposed
date: 2026-08-26
certainty: open
decision: OD-04
---
# ADR-013: Canonical Source-Backed Markdown AST Foundation

**Status:** Proposed; implementation-blocking Spike
**Decision owner:** SPK-BURL-H001, then final Technical Implementation evolution

## Context

The delivered `AstNode` omits standard Markdown structure and treats source spans as a separate rendering aid. PRD v1.3.2 requires one exhaustive Core-owned document state used by parsing, editing, undo, search, conflict resolution, rendering, and indexing. The original source must remain authoritative so untouched bytes aren't normalized.

The current candidates are `markdown` 1.0.0 mdast, Comrak 0.54.0, and complete burlmd models derived from `pulldown-cmark` 0.12.2 and 0.13.4 events. The `markdown` crate exposes `to_mdast(&str, &ParseOptions) -> Result<Node, Message>`, position-bearing nodes, CommonMark, and GitHub Flavored Markdown constructs. That makes mdast the provisional default, not the winner: positions must be proven exact enough for source splices, and its model must cover ADR-021 without a lossy shadow tree.

## Candidate decision

1. Core owns one `Document` containing the original source, one exhaustive extended tree, private half-open UTF-8 source ranges, opaque node identities valid only for that document revision, and conformance state.
2. The standards foundation supplies ADR-021's exact P0 grammar. Burlmd extends that same tree with resolved and ghost Link semantics, Suggestion nodes, local and external image identity, conformance annotations, and editing metadata. These aren't maintained in a second pseudo-AST.
3. Flutter receives a render projection generated from the canonical tree. The projection isn't authoritative and cannot be edited independently.
4. A targeted edit changes source, then reparses into a new coherent `Document`. No production save serializes the whole tree. A successful edit invalidates every prior node identity, find session, and interaction coordinate.
5. Workspace identity, Directories, and object reachability belong to the Core-owned Workspace tree, not to Markdown nodes.
6. Flutter interaction coordinates identify a document revision, opaque node, raw or rendered coordinate space, and UTF-16 range. Core validates and converts them to its private byte ranges. It rejects stale identities and surrogate-interior offsets.

## Evidence required

SPK-BURL-H001 must compare all four candidates on the same deterministic corpus: mdast, Comrak, and distinct complete models over `pulldown-cmark` 0.12.2 and 0.13.4. The Spike report records the corpus inventory, generation inputs, and digests needed to reproduce it; scratch code and generated corpus bytes are removed after measurement rather than becoming committed contracts. The comparison must prove exhaustive representation of ADR-021, exact byte positions, addressable reference and footnote definitions, preservation of malformed and unsupported source, link and heading-fragment classification, conflict representation, task toggles, structural and range edits, revision-bound literal source find and replace, math and Mermaid fallback, existing Note-size performance meters, and Flutter Rust Bridge projection cost. A candidate fails if it needs a second canonical document model, exposes source-byte authority to Presentation, or cannot preserve untouched bytes.

Private Linux evidence can settle the model's source fidelity, memory, projection, and interaction costs for the first-use milestone. It doesn't qualify macOS or a public release. The result must retain portable syntax and path inputs without claiming that a Linux filesystem run settles OD-05.

## Consequences

- Production content-model work is blocked until final Stage 3 accepts one foundation and pins its versions and parse options.
- ADR-007's source-splice fidelity remains binding; only its claim that spans can't be fields of the canonical AST is expected to change.
- The existing `AstNode` name must be removed or explicitly renamed as a render projection in the final FFI contract.
- A successful Spike does not change production by itself. A reviewed Stage 3 patch must accept one candidate, update the stack and FFI contract, and precede dependent implementation.

## Verification anchors

- <https://docs.rs/markdown/1.0.0/markdown/fn.to_mdast.html>
- <https://docs.rs/comrak/0.54.0/comrak/nodes/index.html>
- <https://docs.rs/pulldown-cmark/0.13.4/pulldown_cmark/>
