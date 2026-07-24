# Data Model: The Workspace On Disk (OKF v0.2 Bundle)

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
- **Never written:** `generated`, and therefore no modification time of any kind. Per OKF §13.1 this is the v0.2 field of record for a concept's last content change — it supersedes v0.1's `timestamp`, which is legacy and which burlmd also never writes. The reason is the Edit Fidelity constraint in `prd/constraints.md`: writing a timestamp on every save produces a diff on every save, which is precisely the whole-file-churn failure that constraint exists to prevent. Git history is the authoritative modification record for this application. The cost is stated plainly in ADR-004 decision 8 — the Agent actor gets no modification time from the bundle and must read it from Git or the filesystem.
- `title` is recommended rather than required by OKF §4.1, which permits consumers to derive one from the filename. burlmd writes it anyway so that display title is decoupled from filename, and therefore from identity.

A file that is missing frontmatter, or whose frontmatter does not parse, is **not** rejected — it is indexed with a derived title and reported as non-conformant, so that CAP-PORT-03 (tolerating files written by external tools) and CAP-WS-05 (opening a foreign Workspace) both hold. burlmd brings such a file into conformance only when the user next edits it.

## Links

Per OKF §6.1 a link is a standard Markdown link, and the **bundle-absolute** form — leading `/`, resolved from the bundle root — is the recommended one. That is the form burlmd writes.

```markdown
See [Architecture](/projects/architecture.md) for the container split.
```

- **Internal Link** (`InlineElement::Link`): target has no URL scheme and ends in `.md`. Its concept id is the target path with the leading `/` and trailing `.md` removed.
- **External link** (`InlineElement::ExternalLink`): everything else.
- **Ghost Links are valid.** OKF §6.1 requires that "consumers MUST tolerate broken links: a link whose target does not exist in the bundle is not malformed." A Link to a Note that has not been created yet is indexed normally, resolves to nothing, and satisfies CAP-GRAPH-04.
- **`[[` is never stored.** It is only the UI trigger for the completion in CAP-GRAPH-02, which inserts a full Markdown link. The reasoning, including why this was a closer call than it looks, is in `prd/out-of-scope/wikilink-syntax-on-disk.md`.
- Relative links are permitted by OKF §6.1 and are read and resolved correctly when encountered in a foreign bundle, but are never generated.

## Reserved filenames

OKF §3.1 reserves `index.md` (directory listing, §8) and `log.md` (update history, §9). Both are optional, and §11 constrains their structure only when they are present.

burlmd **reserves both names and generates neither** (ADR-004 decision 6). A Note whose title would derive to either filename is **rejected with `PathUnavailable`**, and the user is told. It is not silently disambiguated into a different filename — that is the same rule `create_note` states in `contracts/ffi_api.rs` and that `WSPC-D006` carries as a STOP condition, and silently altering a name the user chose is worse than refusing it.

One consequence is worth stating plainly: OKF §12 allows a bundle to declare its target specification version via `okf_version` in the frontmatter of a bundle-root `index.md` — and *only* there. Declining to generate that file means a burlmd-authored bundle ships untagged, and a consumer must infer the version. This is acceptable because §11's tolerance rules oblige consumers to accept unknown keys, unknown types, broken links, and missing indices regardless of version.

## Attachments

Images (CAP-EDIT-06) live inside the bundle and are referenced by bundle-absolute path, exactly as Links are. They are not concepts: they are not `.md` files, so §11's conformance rules do not apply to them and they are never indexed as Notes. The concrete attachment directory is not specified here because CAP-EDIT-06 is deferred scope; it must be settled before that capability is built, and the choice is constrained by needing to be unambiguously distinguishable from a Directory of Notes.

## Invariants

1. Every `.md` file in the bundle other than `index.md` and `log.md` is a Note.
2. Every Note that burlmd has written has a parseable frontmatter block with a non-empty `type`.
3. A Note's `notes.id` equals its bundle-relative path with `.md` removed, and `notes.path` equals that path with `.md` retained. These are two views of one fact, stored separately so that the FTS and Link tables can key on the id without re-deriving it.
4. Bytes outside the span of an edited Block are identical before and after a write (ADR-007).
5. Every Note **burlmd has written** is conformant the moment the write completes, not at some later export step (CAP-PORT-01). Conformance is not a mode.

Invariant 5 is deliberately scoped to Notes burlmd wrote. A Workspace may legitimately contain files it did not write — CAP-WS-05 opens foreign Workspaces and CAP-PORT-03 tolerates external tools writing into this one — and those are indexed with `okf_conformant = 0` and brought into conformance only when the user next edits them, which may be never. A stronger invariant covering the whole bundle at all times would be false the moment a foreign Note is added, and would oblige the application to rewrite files the user never asked it to touch.
