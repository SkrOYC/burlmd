# Out of Scope: Double-Bracket Link Syntax Stored On Disk

**Status:** Rejected as a storage format (retained as an input affordance)
**Related:** CAP-GRAPH-02, CAP-PORT-01

## The rejected concept
Storing Links in Notes as double-bracket wiki-style syntax (`[[Some Note]]`) — the convention used by several existing Markdown knowledge tools — rather than as standard Markdown links.

## Why it was considered
It is markedly more concise to read and type, which matters a great deal now that the primary actor edits raw source directly (CAP-EDIT-01) and therefore sees the stored syntax constantly. It is also directly compatible with other tools in this category, and — *as the domain model stood when this was considered* — it matched its shape, a Link being defined by the *title* of its target rather than by a location. That is no longer the model: under ADR-004 a Link carries its target's concept id, which is a path. The argument is left as it was made because the conclusion never rested on it.

## Why it was rejected
It is not resolvable by standard Markdown tooling. A conforming Open Knowledge Format consumer reading the Workspace sees double-bracket syntax as literal text, not as a traversable edge — so the knowledge graph, which is half the product's organizing premise, would be invisible to exactly the Automated Consumer actor that on-disk format conformance exists to serve.

Worth recording precisely, because it is a subtler call than it looks: this would **not** have broken conformance. The format's conformance rules cover frontmatter and reserved filenames only, and say nothing about link syntax. The Workspace would have remained technically conforming while failing at the thing conformance was adopted for. Choosing a format for interoperability and then declining its interoperable link syntax would have been conformance in letter and not in substance.

The concision argument is real and was accepted as a genuine cost. It is mitigated by the insertion affordance rather than by the storage format.

## What replaced it
Links are stored as standard Markdown links with bundle-absolute targets. Users never type those targets by hand: an in-editor completion (CAP-GRAPH-02) is triggered by typing, searches existing Notes by title, and inserts the full link. The double-bracket sequence is retained as the *trigger* for that completion — it remains what the user types, and simply is not what gets stored.

## Conditions that would reopen this
Adoption of double-bracket syntax into the Open Knowledge Format specification itself, or a decision that compatibility with a specific competing tool outranks machine-traversability.
