# Data Model: The Workspace On Disk (OKF v0.2 Bundle)

> **Forward status:** This is the delivered v1.6.x bundle contract. TechSpec v2.1.1 (reviewed v1.8.7 lineage) reopens title-verbatim filenames through OD-05 and replaces the deferred Asset section with the required hybrid Local Asset Store and S3-compatible object model. SPK-BURL-H002 and SPK-BURL-I001 must settle those physical forms before final Stage 3 rewrites this contract. Research Tasks must not implement the old filename or Asset text as forward behavior.

`architecture/containers.md` gives the Local Repository two distinct storage forms: the OKF directory tree, and the encrypted search index. This file is the contract for the first; `schema.sql` is the contract for the second. The frontmatter block additionally has a machine-checkable contract in `okf-frontmatter.schema.json`.

The governing decision is ADR-004. Everything below either restates a rule from Open Knowledge Format v0.2 (`GoogleCloudPlatform/knowledge-catalog`, `okf/SPEC.md`) or records a burlmd-specific choice made inside the latitude the specification allows. Where the two are distinguishable, the source is named.

## Layout

```text
<workspace-root>/                 # a Git repository; the OKF bundle root
├── .git/                         # version history; not part of the bundle
├── Welcome.md                    # concept id: "Welcome"
├── projects/
│   ├── burlmd.md                 # concept id: "projects/burlmd"
│   └── architecture.md           # concept id: "projects/architecture"
└── reference/
    └── okf.md                    # concept id: "reference/okf"
```

- A **Note** is one `.md` file. A **Directory** is one filesystem directory.
- `.git/` is not a concept and is never indexed.
- Directories nest to arbitrary depth (CAP-LIFE-05).
- An empty Directory has no file to represent it, so it exists only in the `directories` table of the index. This is why that table exists.

## Identity

Per OKF §2, a concept's id is "the path of the concept's file within the bundle, with the `.md` suffix removed".

- `notes.id` in `schema.sql` holds exactly this value: workspace-relative, forward-slash separated, no leading slash, no `.md`.
- Identity is therefore *positional*. Renaming or moving a Note changes its id, which is why CAP-LIFE-02 and CAP-LIFE-03 require inbound Links to be rewritten as part of those operations rather than left to resolve by chance.
- No UUID is minted, stored, or written to disk. The prior `schema.sql` claim that `notes.id` was "a stable UUID (persisted in Markdown YAML frontmatter)" was never implemented and is now removed.

## Frontmatter

Every non-reserved `.md` file opens with a YAML frontmatter block. This is not a burlmd preference: OKF §11 makes a parseable block containing a non-empty `type` the entire basis of conformance.

```markdown
---
type: Note
title: burlmd
---

# burlmd

Git-backed notes. See [Architecture](/projects/architecture.md).
```

- **Written by burlmd:** `type` (always, default `Note`) and `title`.
- **Preserved verbatim:** every other key, in its original order, spelling, and formatting. Per ADR-007 the block is a byte span that is only rewritten when `title` changes, so preservation requires no round-trip machinery and cannot silently reorder or reformat a user's own keys.
- **Never written:** `generated`, and therefore no modification time of any kind. Per OKF §13.1 this is the v0.2 field of record for a concept's last content change — it supersedes v0.1's `timestamp`, which is legacy and which burlmd also never writes. The reason is the Edit Fidelity constraint in `prd/constraints.yaml`: writing a timestamp on every save produces a diff on every save, which is precisely the whole-file-churn failure that constraint exists to prevent. Git history is the authoritative modification record for this application. The cost is stated plainly in ADR-004 decision 8 — the Agent actor gets no modification time from the bundle and must read it from Git or the filesystem.
- `title` is recommended rather than required by OKF §4.1, which permits consumers to derive one from the filename. burlmd writes it anyway so that display title is decoupled from filename, and therefore from identity.

A file that is missing frontmatter, whose frontmatter does not parse, or whose frontmatter parses without a non-empty `type`, is **not** rejected — it is indexed with a derived title and reported as non-conformant. All three cases, because OKF §11 states three conformance conditions and the second is `type`: a block containing only `title:` parses perfectly and is still non-conformant, so that CAP-PORT-03 (tolerating files written by external tools) and CAP-WS-05 (opening a foreign Workspace) both hold.

Bringing such a file into conformance is an **explicit user action, never automatic**, and no ticket in the current wave implements it. Two things force that. First, prepending a frontmatter block to a file that has none writes bytes outside the span of any edited Block, which `guidelines.md` states as an absolute — ADR-007 decision 5 covers rewriting an *existing* block when `title` changes, and deliberately does not cover creating one that was never there. Second, doing it silently on first edit would mean the application rewrites the header of a file the user opened to change one word, which is exactly the whole-file-churn behaviour the Edit Fidelity constraint exists to prevent. The `okf_conformant` flag therefore exists so the UI can *offer* the repair; until the user accepts, the file stays as its author wrote it. Surfacing that offer is deferred with the rest of the foreign-Workspace path.

## Deriving a filename from a title

`create_note` and `rename_note` both take a title and derive a filename from it. Under positional identity that derivation *is* the mapping between what the user typed and what `notes.id` becomes, so it is specified here rather than left to the implementation:

**The filename is the title verbatim, plus `.md`.** No slugification, no case folding, no whitespace collapsing, no transliteration. `My Great Idea` becomes `My Great Idea.md` with concept id `My Great Idea`.

Three reasons, in order of weight:

1. **`CAP-GRAPH-04` requires the derivation to be invertible.** Following a ghost Link means creating the Note the Link already points at, and the Link carries a *concept id*, not a title. `create_link_target(target_id)` recovers its `(directory_path, title)` pair Core-side and creates that exact identity; the UI never performs this derivation or routes ghost creation through ordinary `create_note`. Any lossy transformation makes inversion guesswork: the Note gets created somewhere other than where the Link points, the ticket's criterion ("the target Note is created and opened") still passes, and the Link is still a ghost. Identity is the only derivation that inverts by construction.
2. **The user chose the title.** Slugifying it means the filename another tool sees is not the name that was typed — the same quiet rewriting of the user's own bytes that `prd/constraints.yaml`'s Edit Fidelity constraint forbids inside a Note, applied to its name instead.
3. It requires no specification of its own beyond this paragraph.

Two consequences to accept:

- **A title containing `/`, or a character the target filesystem rejects, is not derivable.** That returns `PathUnavailable`, whose meaning widens from "occupied or reserved" to "this path cannot be used", with the reason carried in the payload. Refusing is right: silently substituting a character produces a Note at an id the user did not ask for, and the user is present and can retype.
- **Case sensitivity follows the filesystem, not the index.** `notes.id` is a `TEXT` primary key and case-sensitive, while macOS's default filesystem is not — so `Ideas` and `ideas` are two ids over one file there. Creation therefore checks path availability against the *filesystem*, not only against the index, and reports `PathUnavailable` when the filesystem already holds the path under different case.

## Links

Per OKF §6.1 a link is a standard Markdown link, and the **bundle-absolute** form — leading `/`, resolved from the bundle root — is the recommended one. That is the form burlmd writes.

```markdown
See [Architecture](</projects/architecture.md>) for the container split.
```

- **Internal Link** (`InlineElement::Link`): target has no URL scheme and ends in `.md`. Its concept id is the target path with the leading `/` and trailing `.md` removed, after the unescaping described below.
- **External link** (`InlineElement::ExternalLink`): everything else.
- **Ghost Links are valid.** OKF §6.1 requires that "consumers MUST tolerate broken links: a link whose target does not exist in the bundle is not malformed." A Link to a Note that has not been created yet is indexed normally, resolves to nothing, and satisfies CAP-GRAPH-04.
- **`[[` is never stored.** It is only the UI trigger for the completion in CAP-GRAPH-02, which inserts a full Markdown link. The reasoning, including why this was a closer call than it looks, is in the related out-of-scope syntax analysis.
- Relative links are permitted by OKF §6.1 and are read and resolved correctly when encountered in a foreign bundle, but are never generated.
- **Bare destinations are read, never written.** A foreign bundle may contain `[a](/Notes.md)` with no brackets, and it parses fine because it has no space. Reading is governed by what `pulldown-cmark` accepts; only writing is governed by the rule below.

### The destination is always angle-bracket wrapped

**Every link destination burlmd writes is enclosed in `<`…`>`.** Inside those brackets, a literal `\`, `<`, `>` or `&` in the path is prefixed with a backslash; nothing else is transformed.

This is forced by the composition of two rules stated elsewhere in this file, which are individually fine and jointly broken without it. Filenames are derived from titles verbatim, so `Meeting Notes` yields `Meeting Notes.md` — and CommonMark forbids a *bare* link destination from containing a space. The bare form is therefore not a link at all for the ordinary case of a multi-word title. Measured against `pulldown-cmark` 0.12.2, the version `BURL-D003` pins:

```
[a](/Meeting Notes.md)      -> NOT A LINK  (emitted as literal text)
[a](</Meeting Notes.md>)    -> LINK, dest "/Meeting Notes.md"
[a](/Q3 (draft).md)         -> NOT A LINK
[a](</Q3 (draft).md>)       -> LINK, dest "/Q3 (draft).md"
[a](</A > B.md>)            -> NOT A LINK  (unescaped `>` closes the destination)
[a](</A \> B.md>)           -> LINK, dest "/A > B.md"
[a](</100% Done.md>)        -> LINK, dest "/100% Done.md"
[a](</Caf&eacute;.md>)      -> LINK, dest "/Café.md"        <- round trip LOST
[a](</Caf\&eacute;.md>)     -> LINK, dest "/Caf&eacute;.md"
[a](</Tom &amp; Jerry.md>)  -> LINK, dest "/Tom & Jerry.md"  <- collides
[a](</Tom \&amp; Jerry.md>) -> LINK, dest "/Tom &amp; Jerry.md"
[a](</A&B.md>)              -> LINK, dest "/A&B.md"          <- bare & is fine...
[a](</A\&B.md>)             -> LINK, dest "/A&B.md"          <- ...and escaping it is too
```

What a bare destination containing a space actually produces is not a malformed link but ordinary paragraph text, which is the reason this is worth this much space. Nothing reports an error. `BURL-D005` records no `links` edge, so backlinks and `exists` come back empty; `BURL-D006`'s inbound-Link rewrite then finds nothing to rewrite, so a rename silently leaves the old path sitting in the prose — risk 8's partial-rewrite corruption arriving through a path the atomicity STOP cannot see, because from the rewriter's perspective there was nothing there. And `BURL-D006`'s criterion "all three links resolve to the new concept id" passes vacuously against any fixture whose Notes happen to have single-word titles.

**`&` is in that list because CommonMark decodes HTML entity references inside a link destination**, and the angle brackets do not suppress it. A title containing an entity-shaped substring — `Café` written as `Caf&eacute;`, or `Tom &amp; Jerry` — therefore parses back to a *different* concept id than the one written, with the same consequences as the space case: an edge pointing at a concept that does not exist, `exists` false, no backlinks, and nothing for a rename to find. `Tom &amp; Jerry` and `Tom & Jerry` are two distinct titles that collapse onto one `target_id`, so a rename of either rewrites both.

The last two lines above are why escaping `&` **unconditionally** is correct rather than merely sufficient: a bare `&` that begins no valid entity already round-trips, and escaping it round-trips to the same string. There is no case where the escape is wrong, so no predicate is needed — the same property the bracket rule itself is chosen for.

Two further points:

- **Wrap unconditionally, not only when the path needs it.** Conditional wrapping requires a predicate that exactly matches CommonMark's rule for what a bare destination may contain, and a predicate that is subtly wrong reproduces this defect for whichever character it forgot. Wrapping always is one rule with no branch, and makes the failure unrepresentable rather than unlikely — the same reasoning ADR-007's reparse-over-arithmetic decision turns on. The cost is four extra characters visible in raw view on a focused Block.
- **Percent-encoding was the alternative and is rejected.** `[a](/Plan%20A.md)` also parses, but it makes deriving `target_id` lossy: the parser hands back the destination verbatim, so recovering the path requires a percent-decode, and a title that legitimately contains `%` — `100% Done` — then decodes to something the user never wrote. Angle brackets round-trip through `pulldown-cmark` unchanged, so `target_id` derivation stays a strip plus a fixed four-character unescape — no decoding table, and no character whose meaning depends on what follows it.

Deriving `target_id` from a parsed destination is therefore: unescape `\\`, `\<`, `\>` and `\&`, then remove the leading `/` and the trailing `.md`. The parser has already removed the angle brackets — `dest_url` never contains them.

One case this deliberately does not repair: a **foreign** bundle may contain an unescaped entity reference, and the parser will have decoded it before the Core sees it. The recovered `target_id` is then whatever the entity decoded to, which may match no file. That is a broken link in someone else's bundle, and OKF §6.1 requires tolerating it rather than guessing what was meant.

## Reserved filenames

OKF §3.1 reserves `index.md` (directory listing, §8) and `log.md` (update history, §9). Both are optional, and §11 constrains their structure only when they are present.

burlmd **reserves both names and generates neither** (ADR-004 decision 6). A Note whose title would derive to either filename is **rejected with `PathUnavailable`**, and the user is told. It is not silently disambiguated into a different filename — that is the same rule `create_note` states in `contracts/ffi_api.rs` and that `BURL-D006` carries as a STOP condition, and silently altering a name the user chose is worse than refusing it.

One consequence is worth stating plainly: OKF §12 allows a bundle to declare its target specification version via `okf_version` in the frontmatter of a bundle-root `index.md` — and *only* there. Declining to generate that file means a burlmd-authored bundle ships untagged, and a consumer must infer the version. This is acceptable because §11's tolerance rules oblige consumers to accept unknown keys, unknown types, broken links, and missing indices regardless of version.

## Assets

Images (CAP-EDIT-06) live inside the bundle and are referenced by bundle-absolute path, exactly as Links are. They are not concepts: they are not `.md` files, so §11's conformance rules do not apply to them and they are never indexed as Notes. The concrete Asset directory is not specified here because CAP-EDIT-06 is deferred scope; it must be settled before that capability is built, and the choice is constrained by needing to be unambiguously distinguishable from a Directory of Notes.

## Invariants

1. Every `.md` file in the bundle other than `index.md` and `log.md` is a Note.
2. Every Note that burlmd has written has a parseable frontmatter block with a non-empty `type`.
3. A Note's `notes.id` equals its bundle-relative path with `.md` removed, and `notes.path` equals that path with `.md` retained. These are two views of one fact, stored separately so that the FTS and Link tables can key on the id without re-deriving it.
4. Bytes outside the span of an edited Block are identical before and after a write (ADR-007).
5. Every Note **burlmd created** is conformant the moment it is created, not at some later export step (CAP-PORT-01), and no operation burlmd performs makes a conformant Note non-conformant. Conformance is not a mode.

Invariant 5 is deliberately scoped to Notes burlmd *created*, and says *created* rather than *written* for a reason the difference makes concrete: editing a foreign file that has no frontmatter **writes** it and leaves it non-conformant. `prd/constraints.yaml`'s Format Conformance constraint and CAP-PORT-01 are worded the same way and mean the same thing. A Workspace may legitimately contain files it did not write — CAP-WS-05 opens foreign Workspaces and CAP-PORT-03 tolerates external tools writing into this one — and those are indexed with `okf_conformant = 0` and brought into conformance only if the user explicitly asks, which may be never. A stronger invariant covering the whole bundle at all times would be false the moment a foreign Note is added, and would oblige the application to rewrite files the user never asked it to touch.
