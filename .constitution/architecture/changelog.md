# Stage 2: Architecture Changelog

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
