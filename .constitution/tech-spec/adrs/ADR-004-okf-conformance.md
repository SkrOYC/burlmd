---
id: ADR-0004
status: accepted
date: 2026-09-03
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-004: Conformance to Open Knowledge Format v0.2

**Status:** Accepted

## Context
`prd/vision.md` has named "Open Knowledge Format (OKF)" as the on-disk Workspace structure since v1.0.0, but nothing downstream ever defined it. `prd/glossary.md` did not carry the term, no tech-spec file specified a layout, and `data-models/schema.sql` asserted a fact about it (`notes.id` is "a stable UUID persisted in Markdown YAML frontmatter") that no code implements and no document justifies — `markdown/parser.rs` has no frontmatter handling at all, and `api::ffi_api::open_note` in fact sets `id` to the filesystem path. The project's own storage format was undefined canonical vocabulary carrying a contradictory schema claim.

Investigation established that OKF is a real published specification, originated by Google Cloud and announced 2026-06-12, currently at **v0.2** (`GoogleCloudPlatform/knowledge-catalog`, `okf/SPEC.md`). It is deliberately minimal: a directory of Markdown files with YAML frontmatter, plus a small set of conventions.

The specification's own framing is aimed at organizational data catalogs and AI-agent grounding context (BigQuery tables, metrics, runbooks), not personal note-taking. Adopting it is therefore a real choice with a real cost, not an obvious default. Three facts made the cost small enough to accept:

1. §2 defines a concept's identity as "the path of the concept's file within the bundle, with the `.md` suffix removed" — which authoritatively settles an identity question this project had gotten wrong, at no cost.
2. §11's conformance requirements are only three, and all are cheap: parseable YAML frontmatter on every non-reserved `.md`, a non-empty `type` field in each, and reserved filenames following §8/§9 *when present*.
3. §6.1's link form is a standard Markdown link, which any Markdown renderer already resolves.

`prd/actors.md` v1.1.0 additionally introduced the **Agent** actor — an external tool or AI agent reading the Workspace directly from disk — which gives conformance a stated beneficiary rather than leaving it an unmotivated technical preference. `prd/capabilities.md` CAP-PORT-01 makes it a P0 requirement that conformance holds *continuously*, not at Export time.

## Decision
1. **Pin to OKF v0.2.** The on-disk Workspace is an OKF bundle conforming to specification version 0.2 exactly. The full on-disk contract is specified in `data-models/okf-bundle.md`, with a machine-checkable frontmatter schema in `data-models/okf-frontmatter.schema.json`.
2. **Identity is the path.** A Note's identity is its bundle-relative path with `.md` removed, per §2. `notes.id` in `data-models/schema.sql` holds exactly that value. No UUID is minted, stored, or written to disk.
3. **Write two frontmatter fields, preserve everything else.** The application writes `type` (required by §11) and `title` (recommended by §4.1; note the specification does *not* require it, and permits consumers to derive a title from the filename — we write it anyway because it decouples display title from filename). Every other key found in an existing frontmatter block is preserved byte-for-byte and never reordered, reformatted, or dropped. See ADR-007 for the mechanism that makes this preservation free rather than engineered.
4. **`type: Note` is the default.** Per §4.1 there is no central type registry and "consumers MUST tolerate unknown types gracefully", so a project-specific value is conformant. A richer type vocabulary is left open as a future product capability.
5. **Links are standard Markdown, bundle-absolute, with the destination angle-bracket wrapped.** Per §6.1, absolute (bundle-relative, leading `/`) is the recommended form and is what is written — as `[Architecture](</projects/architecture.md>)`, with a literal `\`, `<`, `>` or `&` in the path backslash-escaped inside the brackets. The `[[` sequence is retained purely as the UI trigger for a completion that inserts such a link; it is never stored. Recorded in `prd/out-of-scope/wikilink-syntax-on-disk.md`.

   The brackets follow from this decision meeting the verbatim filename derivation in `data-models/okf-bundle.md`: a multi-word title yields a path containing a space, and CommonMark forbids a bare link destination from containing one. Unwrapped, `[a](/Meeting Notes.md)` is paragraph text rather than a link — no parse error, no `links` edge, no backlink, and nothing for a rename to rewrite. The full derivation, the rejected percent-encoding alternative, and the measurements against `pulldown-cmark` 0.12.2 are in `data-models/okf-bundle.md` under Links; recorded here because it is a property of the on-disk format this decision defines, not an implementation detail beneath it.
6. **Reserve `index.md` and `log.md`; never generate them.** Both are optional under §3.1/§8/§9, and conformance rule §11 constrains them only when present. Not generating them keeps the bundle conformant with no maintenance burden.
7. **Do not declare `okf_version` on disk.** §12 permits a bundle to declare its target version, but only via `okf_version` in the frontmatter of a bundle-root `index.md`. Since decision 6 declines to generate that file, the bundle ships untagged. The version this project targets is recorded here and in `stack.md` instead.
8. **Do not write `generated`, and therefore record no modification time in the bundle.** OKF §13.1 made `generated: { by, at }` the v0.2 field of record for a concept's last content change, superseding v0.1's `timestamp`. Writing it would mean rewriting the frontmatter block on every save, producing a diff on every save — the exact whole-file-churn failure the Edit Fidelity constraint exists to prevent, and the thing ADR-007 is built to avoid. Git history is the authoritative modification record here. The honest cost: the Agent actor, which is the stated beneficiary of conformance, gets no modification time from the bundle itself and must read it from Git or the filesystem. This is a real gap in what conformance buys, and it is accepted rather than overlooked.

## Consequences
- **Positive:** The Agent actor is served directly. Any conforming consumer reads the Notes and traverses the Links with no export step, no running application, and no bespoke parser — which is what makes CAP-PORT-01 a continuous property rather than a feature.
- **Positive:** The identity question is settled by an external authority rather than by local preference, and the `schema.sql` contradiction is resolved by deleting the UUID claim rather than by implementing it.
- **Positive:** Export (CAP-PORT-02) collapses to approximately a directory copy, because the live Workspace is already in the target state. This is why it is P1 rather than P0 without weakening the sovereignty guarantee.
- **Negative:** Every Note carries a frontmatter block it did not ask for. The primary actor edits raw source (ADR-006) and therefore sees those two lines constantly. This is the direct, accepted cost of conformance.
- **Negative:** The frontmatter block is an additional Git merge-conflict surface on lines carrying no user-authored meaning. Mitigated by the block being small, stable, and rarely rewritten — under ADR-007 it is only touched when `title` actually changes.
- **Negative:** Links are verbose in raw view (`[Architecture](/projects/architecture.md)` rather than `[[Architecture]]`). Mitigated by the completion affordance in CAP-GRAPH-02, so the path is never typed by hand — but it is still read constantly. Accepted deliberately; the reasoning is recorded in full in `prd/out-of-scope/wikilink-syntax-on-disk.md`.
- **Negative:** OKF v0.2 is young — v0.1 shipped in June 2026 and v0.2 followed within weeks. §12 states that a major bump may rename required fields or change reserved filenames, either of which would be a migration for us. The pin in this ADR is the mitigation: an upstream revision is an explicit decision to re-evaluate, not an automatic adoption.
- **Neutral:** Bundle-level version tagging is unavailable to us as a consequence of decision 6. Consumers must infer the target version. Acceptable because §11's tolerance rules require consumers to accept unknown keys and missing indices regardless.
