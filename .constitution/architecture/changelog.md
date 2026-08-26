# Stage 2: Architecture changelog

## v1.4.4 - 2026-08-26

PR #12 full review round 3 restored independent Object Store detach for Remote-connected Workspaces whose complete Protected State contains no Object references. Asset-bearing Workspaces still require a verified Object Store, and full-local transition still detaches both external stores only after complete hydration.

## v1.4.3 - 2026-08-26

PR #12 full review round 2 corrected the Asset failure flow. Missing or corrupt local Objects now enter Object recovery; Asset Decisions remain exclusive to competing Asset outcomes produced by Remote reconciliation. This preserves the product distinction between local recovery and synchronization decisions.

## v1.4.2 - 2026-08-26

Reviewed for PRD v1.3.2. The Link graph flow already models delivered ghost-Link creation and now classifies CAP-GRAPH-04 as delivered rather than active. No boundary or flow change is required.

## v1.4.1 - 2026-08-26

Reviewed for PRD v1.3.1. No structural change is required: Architecture already separates bounded structured local diagnostics from any off-device transmission and excludes content, credentials, signed locations, and content-derived telemetry.

## v1.4.0 - 2026-08-25

Evolution pass for PRD v1.3.0 and the August 25 Tasks interview. This minor release expands the logical architecture for the feature-complete desktop, private Remote, Object Store, reconciliation, and release scope.

### Added

- Added Canonical Note Model, Workspace Model, Workspace Observer, Application State, Object Transfer Coordinator, Host Platform, Object Store, and Release Pipeline boundaries.
- Added logical flows for desktop sessions, live monitoring, Asset adoption, Object Store lifecycle, complete reconciliation, history and diagnostics, and release upgrades.
- Added durable logical state for guest decisions, reconciliation inputs, Object obligations, Protected State, migrations, and per-Workspace sessions.
- Added trust notes and risks for guest writes, Provider and Remote input, Object integrity, release distribution, path portability, stale decisions, and split external transactions.

### Changed

- Replaced the Git-specific eventual-sync strategy with a provider-independent local-first modular desktop strategy.
- Replaced physical protocols, engines, token flows, tables, commands, and interface contracts with logical request, event, storage, and external-service categories.
- Made Presentation responsible for interaction state while Core Coordination remains the sole Workspace authority.
- Separated device preferences, per-Workspace session state, authoritative Workspace bytes, rebuildable indexing, Remote history, and Object bytes.
- Reworked every flow so all 60 active P0 capabilities and the delivered baseline have explicit mappings and failure behavior.

### Removed

- Removed stale loopback authorization, raw-marker conflict, ambient polling, physical serialization, filename-verbatim, and partial-Export designs from normative Architecture.
- Removed retired Epic G, H, and I deferral banners. The forward architecture follows current PRD scope rather than provisional historical assignments.

### Fixed

- Assigned authoritative session ownership only to Workspace Model and limited Application State to persistence and restoration.
- Added the Agent filesystem trust path, Host filesystem edges, and a distinct Local Asset Store boundary.
- Made Export refusal terminal and made every attached Remote state reauthorizable or explicitly detachable.
- Applied durable input recording and conditional finalization to content, lifecycle, and Asset reconciliation.
- Added guest lifecycle monitoring for create, move, rename, and delete outcomes.
- Completed visible synchronization-state mapping and documented Release Distribution as an external boundary.
- Routed Object bytes, identity verification, deduplication, Export closure, hydration, eviction, and retention through Local Asset Store.
- Split content and Decision finalization guards, added retryable authorization-refresh states, and made missing Object recovery pause affected synchronization.
- Routed every authoritative response through Core Coordination, corrected Observer and Derived Index edge directions, and moved ghost identity resolution to Workspace Model.

## v1.3.0
Evolution pass driven by the Realign interview of 2026-08-21 and PRD v1.2.0, closing the compliance gaps the audit named while leaving every logical container, boundary and pattern untouched.

**`containers.md` gains its required structure diagram** — a module-and-process view fitting the System/Native archetype, with every edge carrying its logical protocol category (in-process FFI call, in-process call, OS credential API, network Git smart protocol). The diagram makes the load-bearing property visible: exactly one asynchronous edge exists in the system, belongs to the Sync Manager alone, and never sits on the editing path.

**Four flows added, closing P0 coverage:** `flow-note-lifecycle.md` (create/rename/move/delete as one atomic operation across files, index rows and inbound Link text, with journal unwind drawn explicitly — mapping CAP-LIFE-01…05 and establishing CAP-PORT-01 at creation), `flow-link-graph.md` (completion insertion, follow, ghost create-on-follow with re-resolution instead of cached flags — mapping CAP-GRAPH-02…04), `flow-workspace-navigation.md` (whole-tree render, empty Directories, ephemeral expansion state — mapping CAP-GRAPH-01), and `flow-export.md` (copy or `.okf` Bundle Archive with a reporting-not-gating conformance check — mapping CAP-PORT-02). The edit flow's traceability header widened to CAP-EDIT-02/04/05 with the body gaining the section those mappings require: cross-Block copy and range dispatch as single atomic Core operations, emphasis shortcuts as delimiter wrapping.

**Failure paths written for the two flows that lacked them.** `flow-search.md` now states its two honest states (results or explicit empty) plus index-unavailable degradation that must never block editing; `flow-workspace-bootstrap.md` names each total-failure surface honestly — keychain unavailable refuses rather than falling back to an unencrypted index, because At-Rest Protection makes that fallback a lie, and every step is idempotent so retry converges.

**`risks.md` gains STRIDE notes** over the four real trust boundaries — OAuth loopback redirect, Remote pull path, Agent writes to disk, OS secure storage — recording both posture and the one place a protection previously existed only on paper (the CSRF `state` comparison that shipped unchecked).

**`resilience.md` adds Observability & Diagnostics and Configuration** as cross-cutting concerns: a structured local log is now stated as a first-class deliverable with content exclusion, and the configuration surface stays minimal by decision. Conflict Resilience records the marker-flow ruling — unresolved Suggestions never gate sync and may flow through history until resolved.

**`strategy.md` version marker reconciled** to the stage version after lagging since v1.1.0; its narrative needed no amendment — the pattern and its trade-offs are unchanged.

Not changed, deliberately: the two stale sync flows remain banner-marked for their owning epics' passes, per their standing deferral record.

### Corrections from milestone review, folded into v1.3.0
Nothing beyond this branch has merged; per house convention the review fixes are folded rather than versioned separately.

- The first cut claimed P0 coverage was closed while three capabilities lacked explicit mapping: CAP-LIFE-05 was covered behaviorally but uncited, CAP-EDIT-02 was mapped without body support alongside 04/05, and CAP-PORT-02 had no flow at all. All three are fixed above; the export flow exists because of this finding.
- The structure diagram's dotted edge used a malformed bidirectional token that could fail the whole diagram's render; corrected to the valid dotted form.
- The diagram now draws Local Repository → Secure Storage directly (the key read happens at index open) and Core → Sync Manager (commit-tier notification), matching dependencies its own container sections declare.
- The navigation note on empty Directories now carves out Asset Directories per the Attachment ruling, instead of contradicting it on arrival.
- STRIDE gains an explicit Repudiation out-of-scope clause rather than a silent omission.
## v1.2.0
Freshness pass at the close of **Epic D (Workspace & Persistence)**. Patch-shaped in substance but recorded as a minor bump, because four risks moved from *mitigation planned* to *mitigation implemented* and that is a real change in what this layer asserts about the system. No container, flow or pattern was added, removed or repurposed.

**`risks.md` — risks 3, 6, 7 and 8 now record shipped mitigations, each naming the test that proves it.** The framework's value here is that a mitigation nobody can point a test at is indistinguishable from an intention, so each entry names its proof rather than asserting completion.

- **Risk 3 (large-repository indexing latency)** — `WSPC-D005` ships the `content_hash` short-circuit in `index::incremental::index_note`. Proven by `an_unchanged_note_is_not_rewritten`, which uses `fts_mapping.fts_rowid` as a sentinel so the test fails both if the short-circuit is bypassed and if it is faked by skipping work the changed path needs. A residual gap is recorded rather than glossed: there is no batch entry point over a changed-path set and no incremental removal route, so a pull that deletes files cannot bring the index level short of a full reindex. Owned by the ticket wiring `SyncDeps::reindex`.
- **Risk 6 (OCC for background sync)** — `WSPC-D007` ships the Core-owned revision, compared inside the per-Note tier 2 write lock so that check, write and re-record cannot interleave with a second writer. Proven by `workspace::persist::tests::reloading_rebuilds_from_disk_and_the_next_write_succeeds` and `a_reload_of_a_conflicted_file_yields_suggestion_nodes`. The residual risk is unchanged and still stands: OCC detects the race, it does not resolve it.
- **Risk 7 (span invalidation under splicing)** — `WSPC-D003` ships whole-file reparse on every committed splice, with the cost measured by `SPK-WSPC-D001` rather than assumed (inside one frame to ~360 KiB of prose at a conservative p95). Proven by `markdown::spans::invariants::check` — degenerate spans, non-boundary endpoints, children escaping their parent, and mis-ordered siblings are all rejected — together with the truthful-span **refusal** tests, which are the load-bearing ones for a silent-corruption risk: the engine refuses to emit a span it cannot justify rather than emitting a plausible one. The paragraph deferring the committed-path arithmetic question to `WSPC-D001` is replaced by that spike's answer: arithmetic cannot replace the reparse there, and the structural reason (a committed splice may change a Block's node shape) would hold even if the timings had come out badly.
- **Risk 8 (positional identity and link rewriting)** — `WSPC-D006` ships rename and move as single atomic operations over the file tree, the index rows and every inbound Link, with a `FileJournal` that unwinds completed renames when a later one fails, inside a transaction committed only after every file move succeeds. Proven by `workspace::lifecycle::tests::a_rename_that_fails_partway_leaves_nothing_changed`, which injects a genuine mid-operation failure (an unwritable directory, so an earlier source has already been rewritten before the failing one is reached) and asserts the file bytes, the note ids and the backlink rows are all exactly as they were, and by `an_unrewritable_inbound_link_fails_the_rename`, which establishes that the sweep is a precondition rather than a best effort.

**`resilience.md` — the SQLite Draft Persistence guarantee is implemented.** `WSPC-D007` shipped all four ADR-008 tiers, so the note recording that nothing read or wrote the `drafts` table is superseded in fact and not only in specification; `SHEL-E007` still owns surfacing recovery in the UI, so the guarantee holds in the Core and is not yet visible to a user. One wording correction carried from `SPK-WSPC-D001` §4.3: "synchronously persists… on every keystroke" is accurate and is what ships, but the write costs 7.96ms at 102 KiB under SQLite's defaults, so the tiering is arranged around that number rather than around an assumption that it is negligible.

**`flows/flow-search.md` — the truncation defect is resolved.** The hardcoded cap of 50 that silently truncated results is gone; `search_notes` takes a caller-supplied `limit`, shipped in `WSPC-D009`. The amendment note is re-scoped to say so, and to record that the Core half is built while the UI half (`SHEL-E006`) is not, so nothing in the running application reaches these functions yet. `find_notes_by_title` is noted as prefix-only, per the Stage 3 narrowing recorded in `tech-spec/contracts/ffi_api.rs`.

**Reviewed, no change required.** `flows/flow-edit-note.md` and `flows/flow-workspace-bootstrap.md` were both pre-aligned during the tech-spec v1.1.0 pass and were re-read against the shipped code this pass: the tier boundaries, the parse-the-draft branch, the polled `note_write_status`, the close-flush-commit-notify sequence and the three-bootstrap-paths post-condition all match what `WSPC-D004`/`D006`/`D007` built. `strategy.md` and `containers.md` are unaffected.

## v1.1.0
Amendments driven by PRD v1.1.0 and the decisions recorded in `tech-spec/` ADR-004 through ADR-008. Minor bump: an execution flow was added and two were materially rewritten, but no logical container was added, removed, or repurposed.

These edits were made during a Stage 3 pass. They are recorded here rather than inside `tech-spec/` because the framework's non-trespass rule forbids repairing an upstream defect in a downstream directory — and these are upstream defects. Two of them are the direct cause of the application's current unusable state, so they are corrections of fact, not preference.

**Added `flows/flow-workspace-bootstrap.md`.** The path from a cold start to a writable Workspace had no flow at all. Every documented route to a Workspace ran through `flow-auth-handshake.md`, which is why one did not exist without a network. The new flow contains no network step and no credential.

**Rewrote `flows/flow-auth-handshake.md`.** Three defects corrected. It *cloned* a repository as the only way to obtain a Workspace, making a network round trip a precondition to writing the first word — a direct contradiction of `constraints.md`'s Local-First Mandate, which the implementation faithfully reproduced by gating all of `lib/main.dart` behind a login screen. It *owned the root encryption key*, which protects the local index and has no relationship to whether a Remote exists; that step moved to bootstrap. And it never distinguished "provision" from "connect" despite `capabilities.md` offering both words; both branches are now explicit, and adopting a non-empty remote is excluded as a distinct problem.

**Rewrote `flows/flow-edit-note.md`.** The save phase specified serializing the AST back to Markdown — never implemented, and unimplementable without first inventing a canonical Markdown form that nothing specified. PRD v1.1.0's Edit Fidelity constraint rules that approach out entirely, since a serializer rewrites the whole file by definition. Replaced with source splicing, and the write path expanded into the four tiers of ADR-008.

**Amended `risks.md`.** Risk 6's OCC token is now a content hash rather than a `last_modified` timestamp, which additionally fixes a latent defect the prior status note had not identified: `open_note` returned the placeholder `"head"` while `save_note` compared a stringified `last_modified`, so the two ends were never the same token and any real save would have failed by construction. Added risk 7 (span invalidation under splicing — a silent data-corruption mode, mitigated by whole-file reparse) and risk 8 (positional identity and link rewriting, arising from OKF's path-based concept id).

**Amended `containers.md`.** The Sync Manager is now explicitly optional at runtime, correcting an assumption threaded through v1.0.x that a Remote always exists. Secure Storage's entry now separates the root key from OAuth tokens — v1.0.x coupled them by generating the key inside the OAuth handshake — and records the readback path needed for session restore.

**Not changed.** `strategy.md` and `resilience.md` required no amendment: the Local-First Thick Client pattern and every resilience guarantee hold unchanged, and in the case of the Local-First Mandate the amendments above bring the rest of the architecture into line with what `strategy.md` already claimed.

### Corrections from PR review, rounds 1 and 2
Folded into v1.1.0, since nothing in this pass has merged.

- **Round 1:** `flows/flow-auth-handshake.md` referenced an undeclared `Local` participant, which Mermaid auto-created to the right of `Remote` — reading as though the local repository sat beyond the network boundary. Declared in position.
- **Round 2:** the same flow generated a PKCE `state` parameter, handed it to the UI, and never compared it on the way back. A CSRF parameter that is never checked is exactly as protective as omitting it, while reading in review as though the protection exists. The comparison is now an explicit step that terminates the flow before the token exchange, and the "what changed, and why" list records it as a fourth defect rather than three.

### Corrections from PR review, round 3
- **Round 2's own fix to this flow was wrong in placement.** It drew the `state` comparison in the Core lane while `contracts/ffi_api.rs` still declared the check a UI obligation and `authenticate_workspace` took no `state` to compare — so the diagram could not be implemented against the signature it described. The control now genuinely lives in the Core: the verifier and `state` are retained against a single-use flow id and neither crosses the boundary. The diagram also still passed `workspace_id` to `connect_remote`, which round 2 removed contract-wide, and omitted the `provider` it does take.

### Corrections from PR review, round 4
- **`flow-edit-note.md` parsed before restoring the draft, and never reparsed.** A draft exists precisely when its content differs from disk, so on the recovery path the returned AST was the *disk* document while `restored_from_draft` was true — and the Core-side span map was built against bytes that are not the working source, so the first `commit_block` after a recovery would splice at offsets derived from a different file. It contradicted `SHEL-E007`'s and `WSPC-D007`'s own acceptance criteria, and nothing else in the spec set resolved the ordering. The open sequence now branches: the draft, when present, is what gets parsed, while `base_revision` stays the hash of what is on disk because that is what the write tier must compare against.
- **`strategy.md` never had its version marker bumped** to v1.1.0 with the rest of the stage, because this changelog recorded the file as needing no amendment. It did: its Initial Load Latency trade-off still described a full clone as the cost of provisioning a Workspace, which ADR-005 replaces with `init` for the first device.
- **`resilience.md` carried the last stale Epic B status note**, saying the `drafts` mechanism needed its own ticket. `WSPC-D007` is that ticket, and ADR-008 is now the specification for the guarantee.

### Corrections from PR review, round 5
- **`containers.md` carried the fourth surviving instance of the at-rest overclaim.** Section 3 still said the OKF tree "relies on OS-level Full Disk Encryption", pointing at a `prd/constraints.md` that this pass had already changed to say the opposite. Sections 4 and 5 of the same file were edited here; section 3 was not read for it.
- **`flow-auth-handshake.md`'s CSRF `alt` had no `else`**, so Mermaid rendered the token exchange as unconditional continuation rather than as the branch not taken. The prose was unambiguous, but the entire point of the round 2 and 3 fixes was that the diagram is what an implementer follows.
- **`flow-edit-note.md` drew the tier 2 write only after the blur commit**, while ADR-008 specifies the timer may fire while the Block is still focused — which is the case `WSPC-D007`'s mid-focus criterion exists to require. Both placements are now drawn.

### Corrections from PR review, round 6
- **`containers.md` carried a mangled sentence from round 5's own sweep** — the replacement clause was inserted without removing the one it replaced. The fix for an overclaim should not itself need a fix, and this one did.
- **`flow-edit-note.md` never received round 5's OCC fix.** The mid-focus tier 2 write was drawn with no return arrow and no comparison, so following the diagram literally reproduces the defect round 5 removed: the baseline never advances and the next write fails against this application's own output. Both tier 2 writes now show the comparison and the re-record.

### Corrections from PR review, round 7
- **`risks.md` risk 7 proscribed the offset arithmetic ADR-008 mandates**, and `SPK-WSPC-D001` was chartered to decide a question ADR-008 had already answered. Reconciled by narrowing the risk to what it is actually about — arithmetic replacing a reparse across a structural change, where the errors are silent — rather than by asserting the conflict away. The spike still owns the committed-splice question.
- **`flow-workspace-bootstrap.md` never drew the `workspaces` row being written**, though the prose lists it as a required post-condition and the contract makes it explicit. Every other post-condition had a diagram step. Same shape as the CSRF `state` in round 2 and the OCC baseline in round 6, at much lower stakes.

### Corrections from PR review, round 8
- **`flow-edit-note.md` had not received round 7's one-writer fix.** It still drew tier 2 splicing the buffered source, and never showed `update_block` performing the substitution and span adjustment at all — so following the diagram leads into exactly the duplication ADR-008 works through. Third round in which a contract fix failed to reach this set of diagrams, after the CSRF `state` and the OCC baseline.

### Corrections from PR review, round 9
- **`risks.md` risk 6's Mitigation still specified the design three rounds removed** — a caller-supplied `expected_base_revision` on a deleted `save_note`. The appended Resolution redefined the token without recording that the parameter was deleted outright, so the Mitigation still read as buildable. Marked superseded, matching how the same file already handles its Epic B notes.
- **`flow-edit-note.md` never showed tier 2 clearing the draft row**, which is what makes the flow's own claim — "a draft row exists precisely when its content differs from disk" — true rather than aspirational.
- **`flow-auth-handshake.md`'s Connect Remote sequence sat outside the CSRF `alt`**, so Mermaid drew it as unconditional continuation after `OAuthStateMismatch`. A note marking it a separate later user action removes the ambiguity without restructuring the diagram.
- **Recorded why risks jump from 3 to 6.** Risks 4 and 5 were removed before v1.0.0 and the numbers are cited across roughly a dozen files, so renumbering would silently redirect every citation. A comment now says so, rather than leaving the next reader to wonder whether a citation was lost.

### Corrections from PR review, round 10
- **`flow-workspace-bootstrap.md` never learned about the third bootstrap path.** It still said "Two bootstrap paths, one post-condition" and did not mention `open_workspace` at all — while `WSPC-D004` instructs the implementer to build `open_workspace` *per this flow*. Now three paths, with repository-present added to the shared post-condition and the reason stated.
- **Risk 8's mitigation was necessary and not sufficient.** File-level atomicity does not prevent the corruption it describes, because a source Note that is open — or that carries an unflushed draft — reverts the Link rewrite afterwards from its buffer. The mitigation now says so and names what has to move with the rename.
- **`flow-edit-note.md`'s second tier 2 write was missing the draft-clearing step its sibling has**, the same one-instance-fixed-sibling-missed shape rounds 6 and 8 catalogued for this diagram.
- **`flow-sync-push.md` and `flow-conflict-resolution.md` carried pre-v1.1.0 traceability headers**, one asserting P0 for a capability the PRD now makes P1. Headers corrected and both bodies marked explicitly as predating ADR-005/006/007, since Epics G and H own the revisions.

### Corrections from PR review, round 11
- **`flow-search.md` carried a pre-v1.1.0 traceability header** — the flow round 10's sweep missed, and unlike the two sync flows this one is built in the current wave (`WSPC-D009`, `SHEL-E006`) and its contract changed here: a caller-supplied `limit` replacing a hardcoded cap of 50 that truncated silently, and Workspace scoping moved from a parameter into the Core.

### Corrections from PR review, round 12
- **`flow-edit-note.md` drew tier 2's revision comparison with no mismatch branch**, and `note_write_status` appeared nowhere in the flow — the surface round 9 added precisely because tier 2's trigger is a Core-owned timer with no caller to return `RevisionMismatch`, `DiskFull` or `IoError` to. An implementer following the sequence literally builds the version that raises them into nothing. Both tier 2 writes now branch, matching the treatment round 5 gave the auth flow.
- **The same diagram drew tier 3 committing unconditionally**, where ADR-008 decision 3 as amended in round 10 says a close with nothing to commit makes no commit and notifies nothing — and calls that the *most common* path through the tier. As drawn it specified one empty commit per Note visited.

This is the third round in which a fix landed everywhere except this diagram. The pattern is now explicit enough to state: a change to the persistence tiers is not finished until `flow-edit-note.md` shows it.

### Corrections from PR review, round 13
- **Risk 6's residual paragraph named a recovery with no function behind it.** "The UI must reload" was the terminal step of the OCC mitigation in three documents, and nothing in the contract performed one — `open_note` restores the surviving draft in preference to disk, so it would hand back the buffer that just lost the comparison and fail identically on the next tick. The paragraph now names `reload_note`, added to the contract this round, and states why the obvious candidate cannot serve.

## v1.0.1
Constitution Freshness & Reconciliation Pass following Epic B execution (UIDB-B001–B007).
- Corrected `containers.md`'s Local Repository description, which implied the raw OKF directory tree was encrypted by this container. The shipped implementation only encrypts the SQLite index (via SQLCipher); raw Markdown files rely on OS-level Full Disk Encryption, per `prd/constraints.md`'s existing rationale (preserving native Git merge capability). This same inconsistency also existed in `prd/capabilities.md` (corrected there, see `prd/changelog.md` v1.0.1).
- Corrected `flows/flow-edit-note.md`: reworded the Active Editing loop's "updated localized AST" to "updated NoteState (full AST)" — `update_block` returns the full note state, not a differential update (differential streaming remains the risk #1 fallback, not something implemented). Annotated the Close/Save phase (serialize AST to Markdown, commit to disk) as not yet implemented: `save_note` currently performs only the OCC bookkeeping check described in risk #6, with no Markdown serializer or file write-through existing yet.
- Amended `risks.md` risk #6 (OCC for Background Sync) with a current-implementation-status note: the shipped `save_note` guards the `notes.last_modified` database column only, since no code path yet serializes the AST back to the on-disk Markdown file. Full protection against the file-clobbering scenario the risk describes is contingent on a future Markdown-serialization + Git-write-through ticket.

## v1.0.0
- Defined the Local-First Thick Client architectural strategy.
- Decomposed the system into four logical containers: Presentation Container, Core Engine, Local Repository, and Sync Manager.
- Established the FFI boundary rules (stateless UI streaming to a stateful engine).
- Defined conflict resolution mechanics occurring within the Core Engine via AST generation.
- Documented cross-cutting resilience concerns for offline operation and FFI serialization risks.
- Upgraded Core Engine container to serve as a cryptographic boundary.
- Added `Secure Storage (OS Keychain)` boundary container.
- Added execution flows for OAuth Handshake (`flow-auth-handshake.md`) and Conflict Resolution (`flow-conflict-resolution.md`).
- Expanded resilience matrix to cover secure storage failures.
