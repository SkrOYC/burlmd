---
version: v1.9.0
---

# Active Backlog Summary

**Total Active Story Points:** 0

No active epics remain. Epics A through F are complete and archived under
`completed/`; completed epics contribute nothing to the total or graph.

The delivered desktop Workspace opens without a login gate, navigates its
Directory tree, persists and recovers Notes, and supports Live Preview,
cross-Block selection and copy, structural editing, emphasis shortcuts, Link
completion and follow, and atomic multi-Block range edits. Ticket gates record
smoke captures for user-facing flows alongside their automated validation.

## Critical Path

There is no active critical path. Active story points are zero because the
`active/` directory contains no ticket-bearing Epic file.

**A dependency-modeling lesson from Epic D remains useful for later planning.**
The published v1.4.0 graph had `WSPC-D006` (Lifecycle) depending only on
`WSPC-D005`. In practice, it also needed `WSPC-D007` (Persistence Tiers): its
acceptance criteria require pathspec-scoped commits and coherent open editing
sessions. Later tickets that mutate files and must preserve open sessions must
depend on the work that owns those sessions.

## Build Order Diagram

The active build graph is empty. Archived dependencies remain historical
evidence, not active scheduling edges.

## Phasing Strategy

### In-Scope (Current Phase)
There is no active implementation scope. The completed local-only desktop
Workspace supports creating, renaming, moving, and deleting Notes and
Directories; editing every supported Block type; selecting and copying across
Blocks; inserting and following Links; searching the full text; and recording
each editing session in local version history.

Synchronization is **not** required for that outcome, and this is load-bearing rather than a compromise: in a local-first Workspace every close is a real commit to a real repository, so Notes are version-controlled and recoverable from the first one written. A Remote adds off-machine durability and multi-device access. Neither is a data-safety precondition.

### Deferred (Next Planning Wave)
Wave 3 was shaped by the realignment interview (2026-08-21) rather than
inherited. It has two parallel tracks: the sync and conflict backbone, and the
interactive design epic. The handoff points follow open decision OD-03. Every
capability added during realignment has a home or named deferral.

**Track 1 — sync backbone:**
- **Epic G — Sync Integration**, carrying: connect and detach (`CAP-SYNC-01/06`), second-device join via `clone_workspace` (`CAP-SYNC-07`) with guided consolidation (`CAP-SYNC-08`, `plan_consolidation`/`apply_consolidation`), session restore, credential readback, scheduler lifecycle wiring, the sync status indicator, bounding the scheduler's shutdown wait, and the post-conflict re-push timing question. Absorbs all six of Epic C's deferred follow-ups plus the `rust/src/api/auth.rs` rework, which is not a wiring item: `OAuthFlowStart` currently returns `code_verifier` and `state`; the contract returns a single-use `flow_id` and neither secret, and `authenticate_workspace(flow_id, auth_code, returned_state) -> SessionState` must raise `OAuthStateMismatch` before any token request. Until Epic G lands, the shipped code still mints a `state` nothing compares — the original CSRF defect, unchanged — and this supersedes Epic C's recorded position that the verifier transiting Dart was an accepted decision: under the current contract it does not transit Dart at all.
- **Epic H — Conflict & Suggestions**: conflict-marker pre-processing, populating the Suggestion node, block-level accept/reject (`CAP-SYNC-04` as ruled at Q4), markers flowing freely through commits per B3, and the delete-vs-edit restore-and-suggest path from Q6. Prerequisite recorded in the contract: `Suggestion.base_content` requires the pull path to set a three-way conflict style.
- **GitLab provider** (`CAP-SYNC-09`, P1) lands behind GitHub inside this track once the seam has one proven consumer (ADR-009, B5).

**Track 2 — design system and surfaces:**
- **Design & Preferences epic** (`CAP-PREF-01`): interactive by decision — human-driven design work expressed through `hitl_sil` and `visual_regression` acceptance modes, not Gherkin-by-default. Produces burlmd's design tokens. Owes the string externalization and `Semantics` pass recorded at `tech-spec/changelog.md` v1.4.0 — Epic E's widgets ship hardcoded literals with no accessibility labels, and retrofitting extraction across more surfaces only gets more expensive.

**Handoff points between tracks (OD-03):** The design epic delivers tokens
before the sync status indicator, editor chrome follow-ups, and
`CAP-PORT-04`'s rendition build their final UI. When both tracks compete for
the same time, Track 1's correctness work takes priority and the design work
moves later.

**Riding either track, placed by dependency rather than by theme:**
- Undo (`CAP-EDIT-08`), version restore (`CAP-HIST-01`), and in-Note find and
  replace (`CAP-FIND-03`) form a Wave 3 editor-depth cluster that builds on
  Epic F's promotion model. Each consumes its declared contract surface:
  `undo_note` and `redo_note`, `list_note_versions` and `restore_note_version`,
  or `find_in_note` and `replace_all_in_note`.
- Diagnostics export (`CAP-SUP-01`) — rides Epic I alongside CI, since ADR-011's log channel and the nightly benchmark share the observability work.
- The three built-but-unsurfaced capabilities — backlinks (`CAP-GRAPH-05`), the title-prefix jump (`CAP-FIND-02`), and opening a foreign Workspace (`CAP-WS-05`) — surface as small UI tickets inside Track 1: they need only shell work over shipped Core, and the foreign-Workspace picker is a natural neighbor of `clone_workspace`'s destination selection.
- **Epic I — Quality & Portability** (revised): continuous integration as the Linux+macOS matrix chosen at Q9, the nightly non-blocking benchmark job verifying every meter in `prd/constraints.md`, images (`CAP-EDIT-06`, `assets/` per Q7), Export surfacing (`CAP-PORT-02`, `export_workspace` + `.okf` archive), and the graph visualization (`CAP-GRAPH-06`).

### Built, and still unsurfaced
Three Core capabilities were built in Epic D with no consumer in Epics E or F.
They remain unreachable from the running application. This section keeps that
state visible because Epics A-C shipped Core components with no caller.

- **Backlinks** (`CAP-GRAPH-05`, P1). `WSPC-D009` built the query and `idx_links_target` backs it, but no ticket surfaces inbound Links in the UI. The index work was not wasted: the same table and index serve the link rewriting `WSPC-D006` depends on, which is why it was built then rather than deferred wholesale.
- **Title-prefix jump** (`CAP-FIND-02`, P1). `WSPC-D009` built `find_notes_by_title`, but `SHEL-E006` is full-text search and no ticket surfaces the title jump. Two notes for whoever picks it up: it matches a **leading prefix only**, which is a deliberate Stage 3 narrowing of CAP-FIND-02's "part of its title" recorded in `tech-spec/contracts/ffi_api.rs`; and its per-keystroke cost is unmeasured, since `schema.sql` declares no index on `notes(title)` and the query scans the Workspace's rows. Measure it before putting it behind a palette.
- **Opening a foreign Workspace** (`CAP-WS-05`, P1). `WSPC-D004` exposed it and the indexer tolerates non-conformant files for its sake, but no ticket adds a directory picker.

The Epic F planning pass closed three capability-traceability gaps:

- `EDIT-F002` explicitly covers `CAP-EDIT-02`, including thematic breaks.
- `EDIT-F006` explicitly covers `CAP-GRAPH-03`, following a Link to its target.
- `EDIT-F006` also covers `CAP-GRAPH-04`, creating a Note when a ghost Link is
  followed.

The capability sweep left four intentionally deferred items: `CAP-EDIT-06`
(images) and `CAP-GRAPH-06` (graph visualization) in Epic I, `CAP-SYNC-02` in
Epic G, and `CAP-EDIT-07`, which is redundant with the keyboard shortcuts in
`EDIT-F005`. `WSPC-D007` and `WSPC-D004` cover `CAP-WS-02` and `CAP-WS-04`.

The three built-but-unsurfaced capabilities above need shell work over shipped
Core to become reachable. Epic E proved that shape by turning `search_notes`
and the recovery and write-status queries into user-facing surfaces
(`SHEL-E006`, `SHEL-E007`) without touching Rust. All three belong to Wave 3's
Track 1. The traceability work closed during Epic F.

### Deferred (Future Scope)
Mobile targets, multiple simultaneous Workspaces, and adopting a non-empty Remote. Each has a standing entry under `prd/out-of-scope/` explaining the reasoning and the conditions that would reopen it.
