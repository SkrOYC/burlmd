---
id: ADR-0021
status: proposed
date: 2026-10-14
certainty: assumed
assumption: "Two independent designs converged on the syntax profile, but SPK-BURL-H001 has not yet proved the profile's source fidelity, coordinate behavior, rendering safety, or performance."
---
# ADR-021: Selected P0 Markdown profile

## Context

The first private Linux milestone includes tables, footnotes, interactive task lists, reference-style Links, heading Links, code highlighting, math, Mermaid, highlighted text, and external images. CommonMark, formal GitHub Flavored Markdown (GFM), GitHub product behavior, and other Markdown extensions are different contracts. A feature list alone therefore leaves parser, editing, and rendering work free to choose incompatible syntax.

This decision fixes the on-disk P0 profile without choosing the canonical abstract syntax tree (AST), parser, math renderer, syntax highlighter, or Mermaid runtime. OD-04 and ADR-013 continue to own that evidence-dependent physical choice.

## Candidate decision

The P0 profile uses CommonMark 0.31.2 as its base grammar. Only the named GFM extensions and additional forms in this section extend that base. The project does not claim complete GFM, GitHub, Pandoc, or another dialect.

| Construct | P0 source and rendering contract |
| :--- | :--- |
| Tables | Use the GFM 0.29 table extension, including alignment and row-width behavior. |
| Task lists | Use the GFM `[ ]`, `[x]`, and `[X]` task markers, including nested tasks. Activating a rendered checkbox changes only its source marker through one Core-owned undoable operation. |
| Reference-style Links | Use CommonMark full, collapsed, and shortcut reference Links and label normalization. Definitions remain source-addressable even though they produce no ordinary reading output. |
| Footnotes | Use GitHub-compatible `[^label]` references and top-level `[^label]:` definitions. Undefined or malformed references remain visible source. |
| Heading Links | Use ordinary same-Note and cross-Note fragment destinations with the GitHub-documented heading-anchor convention and duplicate suffixes. Core owns anchor generation and resolution. SPK-BURL-H001 must freeze edge cases as fixtures before implementation. |
| Code highlighting | Treat the first token of a fenced code block's info string as its language identifier. A bundled grammar can produce inert styled spans. An unknown identifier renders as plain code, and no code runs. |
| Math | Use GitHub-documented inline `$...$`, display `$$...$$`, and fenced `math` forms. TeX source remains authoritative. The research corpus must freeze escaping, currency, nesting, and multiline behavior. |
| Mermaid | Treat a fenced block whose language identifier is `mermaid` as diagram source. Rendering is local, inert, and offline. Invalid or resource-refused diagrams retain editable source and render a bounded error. |
| Highlighted text | Use the candidate `==marked text==` form. SPK-BURL-H001 must freeze delimiter precedence, escaping, nesting, unmatched delimiters, and interactions with code and math before this ADR can be accepted. |
| External images | Preserve ordinary Markdown image syntax. ADR-022 controls which external destinations can load automatically. Local Asset references remain a separate contract. |

Raw HTML isn't interpreted in P0. Markdown source outside the selected constructs remains byte-preserved and uses a literal or source fallback when no selected renderer applies. P1 and P2 syntax decisions remain deferred until their delivery increments approach execution.

## Source-backed editing contract

Core owns the original bytes, document revision, complete selected-syntax model, semantic resolution, and private source ranges. Every semantic node has an opaque revision-local identity. Flutter receives a render projection and checked interaction coordinates, not authoritative source byte offsets.

An interaction coordinate identifies the document revision, opaque node, coordinate space, and Flutter UTF-16 range. The coordinate space distinguishes raw focused source from rendered text. Core rejects a stale revision, unknown node, or UTF-16 range that splits a surrogate pair. A successful edit returns the resulting revision and authoritative focus or selection target; every prior node identity, find session, and coordinate then becomes stale.

Every selected construct has an addressable raw-source region. Source changes splice only addressed bytes, and an existing-Note save never serializes the whole tree. Unedited bytes, line endings, delimiters, whitespace, and unmanaged metadata remain identical.

In-Note find searches literal, case-sensitive Note-body source, including reference definitions, Link destinations, code, math, and Mermaid. Frontmatter editing remains P1 and is outside this search scope. Find sessions and matches use opaque revision-bound identifiers. A match in nonrendering source focuses its smallest addressable raw-source region. Navigation creates no draft or undo entry. Replace-one consumes one match identity. Replace-all consumes one session, applies one nonoverlapping match set atomically, and produces one undo entry or leaves the source unchanged.

## Rendering boundary

Math, Mermaid, and highlighting are replaceable projections. They cannot become second document models or sources of saved Markdown. Rendering uses bundled code and data only, performs no Note-directed network load, exposes no application bridge, runs no Note-provided script or callback, and doesn't attach Mermaid interaction handlers. A renderer failure never blocks source editing, find, undo, save, or Export.

If Mermaid requires a JavaScript runtime, browser engine, or subprocess boundary, that engine choice requires a separate ADR after the research gate measures its Linux dependencies, security behavior, memory, startup, and rendering cost. This ADR does not authorize a WebView or pin a renderer package.

## Evidence required

SPK-BURL-H001 must exercise the complete P0 profile, malformed and unsupported source, nested constructs, Unicode, CRLF input, reference-definition edits that affect multiple uses, local and external image references, duplicate headings, invalid math, invalid Mermaid, and `==` delimiter edge cases. It must measure parse, edit, projection, and renderer behavior against NFC-02, NFC-05, NFC-18, and NFC-38. The result must show that no candidate needs a second canonical document model and that every untouched byte remains unchanged.

After the evidence is accepted, a Stage 3 patch selects the parser and renderer adapters, pins their versions and exact options, publishes the final field-level document and projection contract, and changes this ADR's status. Stage 4 must place that patch before any dependent production ticket.

## Alternatives considered

Two isolated designers independently converged on CommonMark 0.31.2, the named GFM table and task extensions, GitHub-compatible footnotes and heading fragments, inert code highlighting, `$` and `$$` math, fenced Mermaid, and a candidate `==` mark form. One grounded `==` in `markdown-it-mark`; the other grounded it in PyMdown Mark. The shared syntax and an explicit fixture gate are stronger than either implementation's edge behavior, so the project adopts the common form and measures its exact delimiter rules.

The designs differed on whether Flutter could receive source byte ranges. The selected design keeps byte ranges Core-private and uses revision-local opaque identities plus checked UTF-16 interaction coordinates. This preserves the existing authority boundary and avoids a second source-editing authority in Presentation.

Deferring every syntax detail to OD-04 was rejected because Stage 4 would have to invent the corpus and on-disk forms. Selecting a parser or renderer now was rejected because the required source-fidelity, safety, and performance evidence doesn't exist.

## Consequences

- The profile is precise enough to plan SPK-BURL-H001, but no production syntax ticket can treat this proposed ADR as accepted parser or renderer evidence.
- Reference and footnote definitions become editable source even when they don't produce a normal rendered Block.
- Find semantics intentionally change from the old provisional rendered-text contract to revision-bound literal source search.
- The canonical model and rendering projection must grow beyond the delivered reduced `AstNode`; enabling parser flags alone is insufficient.

## Verification anchors

- [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)
- [GitHub Flavored Markdown 0.29](https://github.github.com/gfm/)
- [GitHub basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
- [GitHub mathematical expressions](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions)
- [GitHub Mermaid diagrams](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)
- [`pulldown-cmark` 0.12.2 source](https://raw.githubusercontent.com/pulldown-cmark/pulldown-cmark/v0.12.2/pulldown-cmark/src/lib.rs)

