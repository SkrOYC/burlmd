# Stage 1: Product Requirements Changelog

## v1.1.0
Evolution pass driven by a pre-Tasks interview, which surfaced that the previous PRD described a different product for a different person than the one actually being built. Minor bump: new capabilities and materially expanded scope, no structural rewrite of the stage.

**Primary actor corrected.** `actors.md` described a "General Consumer" whose defining friction was being "intimidated by technical tools, raw Markdown syntax, and Git concepts." The actual primary actor writes Markdown by preference and wants to see the real source of what they are editing. Replaced with the **Writer** persona: Markdown-literate, desktop-first, comfortable with version control as a concept while unwilling to perform merges by hand. Their frictions inverted accordingly — the problem is now editors that *hide* Markdown, and tools that reformat regions of a file the user did not touch.

**Secondary actor added.** Introduced the **Agent** persona: an external tool or AI agent reading the Workspace directly from disk while the application is not running. This makes the on-disk format-conformance requirement traceable to a stated actor instead of appearing as an unmotivated technical preference.

**Editing model replaced.** The first P0 capability — formatting "without seeing raw Markdown asterisks/backticks" — was rejected outright and replaced by **CAP-EDIT-01 (Live Preview)**: the focused Block shows raw Markdown source, every other Block renders formatted. Recorded in `out-of-scope/hidden-markdown-wysiwyg.md` with the full reasoning, including that this was also the single largest engineering risk in the plan and the source of a real shipped regression.

**Local-first made literal.** The previous capability set had authorization as the only path to a Workspace, which contradicted `constraints.md`'s own Local-First Mandate and, in the shipped implementation, gated the entire application behind a login screen that cannot currently be passed at all. Added **CAP-WS-01** (write immediately on first launch with no account and no network) and rewrote **CAP-SYNC-01** so connecting to a Remote is an opt-in step that publishes existing local history upward. Rejection recorded in `out-of-scope/mandatory-account-on-first-run.md`.

**Note and Directory lifecycle added.** The previous capability set never stated that users can create, rename, move, or delete a Note, or create a Directory — the application's most basic operations had no capability to trace to. Added as a new epic (**CAP-LIFE-01** … **CAP-LIFE-06**), including the requirement that renaming or moving a Note updates inbound Links automatically.

**Portability & Interoperability added as an epic.** **CAP-PORT-01** requires the on-disk Workspace to conform to the Open Knowledge Format continuously rather than at export time. **CAP-PORT-02** promotes "Export Workspace" from a clause inside `constraints.md`'s Data Portability constraint into a real capability with an owner and a priority. **CAP-PORT-03** requires tolerating external tools having written to the Workspace — the reciprocal obligation of adopting a format other tools can write.

**Glossary expanded and drift closed.** `vision.md` and `constraints.md` both referenced "Open Knowledge Format (OKF)" while `glossary.md` never defined it, leaving the project's own storage format as undefined canonical vocabulary. Now defined as the published open specification it actually is. Added **Live Preview**, **Remote**, and **Export** as canonical terms, and split **Remote** out of the **Workspace** definition, which previously asserted a Workspace is "backed by a remote repository" — no longer true, and the assertion was the root of the login-gate error. Added `Wikilink` and `Concept` to avoided synonyms.

**Capability IDs introduced.** Every capability now carries a stable `CAP-*` identifier so downstream architecture, specification, and task artifacts can trace to it by reference rather than by quotation.

**Constraints tightened and de-leaked.** Added **Edit Fidelity** (writing a Note must leave untouched regions byte-identical), **Format Conformance**, **Non-Destructive Reconciliation**, **Credential Isolation**, **Non-Proprietary Storage**, **Durability of In-Progress Work**, and **Workspace Open Latency**. Removed the "Export Workspace" clause, now CAP-PORT-02. Rewrote the at-rest protection constraint to describe the *distinction* it draws — Notes rely on operating-system encryption so standard tooling can still merge them, the index is encrypted by the application — without naming specific database engines or mobile platforms, which were implementation leaks into Stage 1.

**Domain model updated.** The Remote is now explicitly optional rather than the Workspace's backing store, the Agent actor and the Suggestion concept appear, and a Link may target a Note that does not exist yet.

**Anti-scope database established.** `out-of-scope/` created, with five entries: `hidden-markdown-wysiwyg.md`, `mandatory-account-on-first-run.md`, `wikilink-syntax-on-disk.md`, `multiple-simultaneous-workspaces.md`, and `mobile-targets.md`.

**Deliberately not resolved here.** Storage-format specifics — the exact specification version pinned, frontmatter field set, link target form, and canonical file layout — are implementation decisions and belong to Stage 3. `vision.md`'s Operator Preferences records only that conformance is intended.

### Corrections from PR review, rounds 1 and 2
Folded into v1.1.0, since nothing in this pass has merged.

- **Round 1** reworded `constraints.md`'s at-rest claim, which asserted operating-system full-disk encryption as though it were a platform guarantee. On the primary desktop target it is an install-time opt-in this application cannot assure.
- **Round 2** found the same claim standing in `capabilities.md` (`CAP-WS-04`), because round 1 fixed the sentence it was shown rather than searching for the assertion. Both now state the two protections separately: the encrypted index is a guarantee this application makes, and what protects the plaintext Notes beside it is not.

## v1.0.1
Constitution Freshness & Reconciliation Pass following Epic B execution (UIDB-B001–B007).
- Corrected `capabilities.md`'s at-rest encryption capability, which implied Notes on disk and the SQLite index receive identical, uniform encryption. The shipped implementation (and `constraints.md`'s own pre-existing rationale) draws a real distinction: Notes on disk are protected via OS-level Full Disk Encryption only, while the SQLite search index is additionally encrypted at the application level via SQLCipher. Reworded to state that distinction explicitly rather than imply both are encrypted the same way.

## v1.0.0
- Initial formulation of the Product Requirements Document.
- Defined target persona as General Consumer seeking a Notion-like experience.
- Established hybrid Markdown editing and hybrid OKF (Directory + Link) organization models.
- Abstracted Git complexity via OAuth provisioning and inline Suggestion-based conflict resolution.
- Set explicit bounds on local-first capabilities and user data sovereignty.
- Expanded PRD to include detailed capabilities for inline formatting and block structures.
- Added explicit Security & Auth Epic, formalizing OAuth and at-rest encryption requirements.
- Expanded constraints to enforce AES-256 local encryption without compromising data portability.
