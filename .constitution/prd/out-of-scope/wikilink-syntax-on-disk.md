---
decision: rejected
date: 2026-07-24
---
# Double-bracket Link syntax on disk

**Status:** Rejected as a storage format (retained as an input affordance)
**Related:** CAP-GRAPH-02, CAP-PORT-01

## The rejected concept
Storing Links in Notes as double-bracket wiki-style syntax (`[[Some Note]]`) — the convention used by several existing Markdown knowledge tools — rather than as standard Markdown links.

## Why it was considered
Double-bracket syntax is concise to read and type. That matters because the Writer edits source directly and sees stored Link syntax. Several Markdown knowledge tools also accept this form.

## Why it was rejected
It is not resolvable by standard Markdown tooling. A conforming Open Knowledge Format consumer reading the Workspace sees double-bracket syntax as literal text, not as a traversable edge — so the knowledge graph, which is half the product's organizing premise, would be invisible to exactly the Automated Consumer actor that on-disk format conformance exists to serve.

Worth recording precisely, because it is a subtler call than it looks: this would **not** have broken conformance. The format's conformance rules cover frontmatter and reserved filenames only, and say nothing about link syntax. The Workspace would have remained technically conforming while failing at the thing conformance was adopted for. Choosing a format for interoperability and then declining its interoperable link syntax would have been conformance in letter and not in substance.

The concision argument is real and was accepted as a genuine cost. It is mitigated by the insertion affordance rather than by the storage format.

## What replaced it

burlmd stores Links in a form that standard Markdown consumers can traverse. Writers don't type a target by hand. In-editor completion searches Note titles and inserts the conforming Link. The double-bracket sequence remains an input trigger but isn't the stored syntax.

## Conditions that would reopen this
Adoption of double-bracket syntax into the Open Knowledge Format specification itself, or a decision that compatibility with a specific competing tool outranks machine-traversability.
