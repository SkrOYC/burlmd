# Stage 1: Product Requirements Changelog

## v1.3.3 - 2026-08-26

### Fixed

- Clarified that an offline Remote detach retains the Object Store. A full-local transition requires fresh authenticated Remote authority before burlmd verifies and detaches every protected Object.

## v1.3.2 - 2026-08-26

### Fixed

- Reclassified CAP-GRAPH-04 as delivered after the full sweep confirmed production Link completion, follow-time resolution, create-on-follow, FFI, UI, and regression coverage. Downstream work preserves and adapts the capability; it doesn't schedule it as unfinished.

## v1.3.1 - 2026-08-26

### Fixed

- Clarified that Zero Automatic Telemetry prohibits automatic off-device transmission, not bounded content-excluding local diagnostics. Local diagnostic records and Writer-created exports still exclude content, credentials, signed locations, and content-derived telemetry; only the Writer may choose to share an export.

## v1.3.0 - 2026-08-25

Evolution pass driven by the Tasks interview after PR #11. This minor release defines the complete forward product scope and removes delivered or deferred work from the active capability set.

### Added

- Added active capabilities for desktop-session durability, live guest-change reconciliation, canonical cross-platform paths, Assets, a user-controlled Object Store, complete private-Remote reconciliation, installable prereleases, update notification, and safe application-state migration.
- Added the Platform actor and clarified that an Agent is a guest to burlmd's Workspace authority.
- Added Asset, Object, Local Asset Store, Object Store, Lifecycle Decision, and Asset Decision to the glossary and domain model.
- Added measurable constraints for external-change detection, image import, repository-health warnings, Object integrity, protected history, release parity, and migration safety.
- Added out-of-scope records for the second Remote provider, HTML output, Object-Store-only Workspaces, optional editing surfaces, the full history diff viewer, additional release architectures, self-updating binaries, and prerelease signing.

### Changed

- Separated the delivered A-F capability baseline from unfinished `P0` release scope so downstream Tasks don't replan shipped work.
- Made Suggestions persistent through history and synchronization. Added separate Lifecycle Decision and Asset Decision outcomes for conflicts that aren't content edits.
- Replaced CAP-PORT-04 and provider-specific CAP-SYNC-09 with explicit deferrals.
- Declared `System/Native` as the only active archetype because mobile device applications remain deferred.
- Moved GitHub, GitLab, S3-compatible storage, release architecture, and implementation choices into the operator-preferences appendix.

### Removed

- Removed emulated operating-system chrome, HTML output, the floating formatting toolbar, graph visualization, and a second Remote provider from active product scope.

### Fixed

- Restored one-to-one traceability for every delivered capability instead of collapsing stable IDs into ranges.
- Specified serial close, warning, failure, focus, guest-write, Export, asset-adoption, and delete-versus-edit outcomes that the first draft left ambiguous.
- Replaced mechanism-specific Remote polling with an observable freshness meter and defined reproducible corpus and desktop performance profiles.
- Expanded Zero Automatic Telemetry to prohibit automatic usage, error, diagnostic, content, and content-derived reporting.
- Added Provider, Protected State, Suggestion ownership, and Decision ownership relationships to the domain model.
- Updated the screen-reader deferral to reference the August 25 open-decision register.
- Separated device preferences from per-Workspace session state and Workspace synchronization.
- Added informed guest repair, Workspace containment, coupled Remote and Object Store detachment, and release-artifact provenance requirements.
- Corrected the Open Knowledge Format definition, transient encryption-key rule, technology-neutral history meter, and Search Latency failure threshold.
- Excluded invalid guest Notes from editing until repair, restored every missing-Object recovery choice, and removed Note-level Version terminology from Workspace history retention.
- Added explicit Workspace switching, binding release systems and macOS support windows, and the private Object Store boundary.

## v1.2.0
Evolution pass driven by the Realign interview of 2026-08-21 (see `reports/2026-08-21-interview-realign.md`), widening and deepening the layer after the operator judged the original planning shallow. Minor bump: new capabilities, a mandatory block the stage contract now requires, and materially expanded constraints; no restructuring of the stage.

**Archetype block added to `vision.md`.** Primary System/Native, Secondary Mobile, confidence high. The rationale records the operator's qualifier verbatim in intent: desktop first, Flutter responsive-by-construction, mobile surfaces deliberately open work rather than pre-designed.

**Eleven capabilities added, opening three new epics.** CAP-EDIT-08 (undo as a Core-side command stack over content operations, excluding lifecycle renames and sync-applied changes), CAP-FIND-03 (in-Note find and replace), CAP-HIST-01 (per-Note version list and restore) under a new **History & Recovery** epic, CAP-SUP-01 (content-excluding diagnostics export) under a new **Supportability** epic, CAP-WS-06 (explicit Workspace rescan for mid-session external writes), CAP-SYNC-06 (detach the Remote), CAP-SYNC-07 (second-device authorize-then-clone join), CAP-SYNC-08 (guided consolidation of a previous local Workspace into a connected one, with three-way collision resolution), and CAP-SYNC-09 (GitLab as a second provider at P1). CAP-PREF-01 opens a new **Preferences & Appearance** epic owned by an interactive design epic that precedes surfaces consuming its tokens.

**CAP-PORT-02 widened and split.** Export now covers both the plain bundle copy and a single-file `.okf` Bundle Archive — the packaged distribution form OKF §3 itself names — both P0. New CAP-PORT-04 adds a self-contained HTML rendition at P1, sequenced behind burlmd's own design system and inheriting Zero Content Telemetry absolutely.

**Constraints rewritten in Planguage form**, every scalar constraint carrying Scale/Meter/Goal/Fail with Stretch where one is honest: the three pre-existing meters plus four new ones from interview rulings — Cold Start (Goal 1s, Fail 3s, set aggressively by operator intent with explicit-rebaseline wording), Idle Memory (400 MB at corpus Goal), Corpus Scale (10k Goal / 50k Stretch / 1k Fail), and Synchronization Freshness (60-second push and poll Goals, 15-minute offline backoff ceiling). A Verification section commits meters to a nightly non-blocking benchmark once CI exists. Non-Blocking Sync now states the marker-flow ruling: unresolved Suggestions never gate commits or pushes, and ambient state distinguishes pending Suggestions from clean.

**Glossary expanded** with Bundle Archive, Consolidation, Rendition, and Diagnostics Export, each with avoided synonyms.

**Domain model de-C4'd.** The C4 context diagram is replaced by a problem-space concept sketch per the current Stage 1 contract, and gains two concepts the rulings introduced: Attachment (non-Note content referenced by Links) and Version (a past Note state making restore possible). The Agent actor now reads *and writes*.

**Four out-of-scope entries created:** `history-merge-on-connect.md` (rejected; guided consolidation replaces it), `telemetry-upload.md` (rejected; diagnostics export replaces it), `static-site-pipeline.md` (rejected; single-file rendition replaces it), and `screen-reader-certification.md` (deferred with its reopen trigger honestly recorded as unknown, per open decision OD-02).

### Corrections from milestone review, folded into v1.2.0
Nothing in this pass has merged beyond this branch; per house convention the review fixes are folded rather than versioned separately.

- The first cut of this entry claimed every scalar constraint carries a Stretch field; Remote Poll Cadence honestly has none. Sentence weakened to "Stretch where one is honest."
- A stale duplicate of CAP-PORT-02 (the old P1 copy-only wording) survived beside its replacement and was removed.
- CAP-EDIT-08's rationale now states the lifecycle-rename exclusion explicitly instead of leaving it in this changelog only, and Preferences & Appearance is an `##` epic heading like its siblings.

## v1.1.1
Reviewed for downstream delta following Epic D execution (WSPC-D001–D009); no layer-specific changes required. Epic D is Core-side only, so no capability's user-visible statement changed and no capability was added, reworded or descoped.
- One narrowing was made downstream and is recorded here as a pointer rather than a PRD edit, so it is not mistaken for drift on the next pass: CAP-FIND-02 says a user jumps to a Note "by typing part of its title", while the Stage 3 contract and `WSPC-D009`'s implementation both match a **leading prefix only**. That is a deliberate Stage 3 reading, documented at `find_notes_by_title` in `tech-spec/contracts/ffi_api.rs`. Widening it to substring match would be a change to this layer and would need its own index strategy; if the narrowing is the wrong reading, the correction belongs here first.

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

### Corrections from PR review, round 3
- **`CAP-PORT-01` promised more than the format allows.** It asserted the Workspace conforms to OKF "at all times", but §11 defines conformance over an entire bundle, so a single file an external tool dropped in without frontmatter falsifies it — and CAP-WS-05 and CAP-PORT-03 both make that state supported and possibly permanent. Round 2 scoped the derived statements in `tech-spec/` without sweeping the capability they derive from. Now scoped to what the application writes, which is the promise it can actually keep without rewriting files the user never asked it to touch.

### Corrections from PR review, round 9
- **The Format Conformance constraint promised something a supported workflow falsifies.** It covered every Note the application "writes", while the tech spec decides that repairing a non-conformant file another tool wrote is an explicit user action — so editing such a file writes it and leaves it non-conformant. Round 3 caught the same shape on `CAP-PORT-01` and rescoped it to "writes", which turns out to be the ambiguous word between *creates* and *writes bytes to*. Now pinned to **creates**, with the exception stated in the constraint itself rather than three documents away.

### Corrections from PR review, round 12
- **CAP-PORT-01 still scoped conformance to every Note the application *writes*.** Round 9 pinned the equivalent sentence in `constraints.md` to *creates*, with the reasoning stated there in full: editing a foreign file that has no frontmatter **writes** it and leaves it non-conformant, and both CAP-WS-05 and CAP-PORT-03 support that state deliberately. The constraint was fixed by rewriting the sentence it was shown; the P0 capability it derives from was not swept. Corrected here, and `tech-spec/data-models/okf-bundle.md` invariant 5 — a third wording of the same rule — aligned with both.

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
