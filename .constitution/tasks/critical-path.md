---
version: v1.6.0
---

# Active Backlog Summary

**Total Active Story Points:** 57

- Epic E — Shell & Navigation: 27
- Epic F — Editor Depth: 30

Epics A, B, C and D (99 points — 10, 23, 16 and 50, summed from the ticket efforts in `completed/`) are complete and archived under `completed/`; they contribute nothing to the totals or the graph below.

Epic D is what changed between v1.4.0 and this revision. The Core is now real: a bundle on disk, an encrypted index derived from it, span-preserving editing that never rewrites a byte the user did not touch, the four persistence tiers, and Note and Directory lifecycle with atomic inbound-link rewriting. The claim that opened the previous revision — that every production `INSERT` in the repository lives inside a test module — is no longer true. What remains true is the other half: the application still opens to a login screen that cannot be passed, and nothing built in Epic D is reachable from it. **Everything left in this wave is user-facing.** That is a different kind of work from what just shipped, and it is worth naming, because the remaining 55 points carry all of the product risk and none of the algorithmic risk.

## Critical Path

The longest dependency chain is **33 of the 55 points**. Everything else can be scheduled around it.

1. `SHEL-E001` — Manual-QA Smoke Harness
2. `SHEL-E002` — Open Directly Into the Workspace
3. `SHEL-E003` — Directory Tree Sidebar
4. `SHEL-E004` — Mount the Editor and Navigate
5. `EDIT-F001` — Spike: Rendered-to-Raw Promotion Fidelity
6. `EDIT-F002` — Live Preview Block Promotion
7. `EDIT-F003` — Cross-Block Selection and Copy
8. `EDIT-F007` — Editing Across a Multi-Block Selection

**`SHEL-E001` has moved onto the critical path, and this is the one scheduling consequence of Epic D's completion worth reading carefully.** The previous revision recorded the smoke harness as deliberately *off* the path. That was correct then and is wrong now, and the reason is arithmetic rather than judgement: `SHEL-E004` was reached through `WSPC-D008` at 31 points of Epic D work, which dominated the 10-point `SHEL-E001` → `E002` → `E003` route into the same node. With Epic D archived, that dominating route no longer exists, so the Epic E chain is the only way into `SHEL-E004` and the harness is its root. The practical advice is unchanged and now doubly binding: do it first, since twelve later tickets invoke `smoke-shot.sh` as their verification gate — `SHEL-E002` through `SHEL-E007` and `EDIT-F002` through `EDIT-F007`.

`EDIT-F003` and `EDIT-F004` are interchangeable at step 7: both are 5 points, both depend only on `EDIT-F002`, and both feed `EDIT-F007`, so the chain is 33 points either way. `EDIT-F003` is listed because cross-Block selection is the harder of the two to retrofit.

**An undeclared dependency edge surfaced during Epic D's execution, and is recorded so future DAGs model it.** The published v1.4.0 graph had `WSPC-D006` (Lifecycle) depending only on `WSPC-D005`. In practice it also needed `WSPC-D007` (Persistence Tiers): `D006`'s acceptance criteria require a pathspec-scoped commit covering exactly the paths a lifecycle operation touched, and require carrying every affected Note's buffer, span map, recorded revision and draft row forward through a rename — both of which are `D007`'s to provide. The edge was `D007 → D006`, not the reverse, and it was discovered mid-execution rather than at planning time. The lesson generalizes: a ticket that mutates files *and* must leave open editing sessions coherent depends on whatever owns those sessions, even when the two tickets look independent from their file scopes.

## Build Order Diagram

```mermaid
flowchart LR
    subgraph EpicE [Epic E - Shell and Navigation]
        E001[SHEL-E001<br/>Smoke harness]
        E002[SHEL-E002<br/>Open workspace]
        E003[SHEL-E003<br/>Tree sidebar]
        E004[SHEL-E004<br/>Mount editor]
        E005[SHEL-E005<br/>Lifecycle UI]
        E006[SHEL-E006<br/>Search]
        E007[SHEL-E007<br/>Draft recovery]
        E008[SHEL-E008<br/>Rescan workspace]
    end

    subgraph EpicF [Epic F - Editor Depth]
        F001[EDIT-F001<br/>Spike: promotion]
        F002[EDIT-F002<br/>Live Preview]
        F003[EDIT-F003<br/>Selection]
        F004[EDIT-F004<br/>Block editing]
        F005[EDIT-F005<br/>Shortcuts]
        F006[EDIT-F006<br/>Link completion]
        F007[EDIT-F007<br/>Range editing]
    end

    E001 --> E002
    E002 --> E003
    E003 --> E004
    E004 --> E005
    E004 --> E006
    E004 --> E007
    E003 --> E008

    E004 --> F001
    F001 --> F002
    F002 --> F003
    F002 --> F004
    F002 --> F005
    F002 --> F006
    F003 --> F007
    F004 --> F007
```

Every Epic D node and every edge out of one is gone from the graph above, Epic D being archived. Nine of those edges crossed into this wave — `D004 → E002`, `D009 → E003`, `D008 → E004`, `D006 → E005`, `D009 → E006`, `D007 → E007`, `D008 → F002`, `D009 → F006` and `D006 → F006` — and all nine are **satisfied**, not dropped for convenience: each named a Core capability that now exists and that the target ticket consumes. They are removed because their source nodes are, not because the dependency stopped mattering. A ticket in this wave that cannot find the Core function it needs should treat that as a defect to report rather than as scope to invent.

## Phasing Strategy

### In-Scope (Current Phase)
Desktop only. The outcome is a local-only Workspace the primary actor can use daily: create, rename, move and delete Notes and Directories; write in them with Live Preview across every Block type; select and copy across Blocks; insert Links through completion; search the full text; and have every editing session land in local version history automatically.

The cutover bar is deliberately "genuinely good", not "technically working". Epics D and E alone would produce an application that persists Notes and can open them, but whose editor can only edit plain single-line paragraphs — usable for capture and unpleasant for anything else. Epic F is what makes it worth switching to.

Synchronization is **not** required for that outcome, and this is load-bearing rather than a compromise: in a local-first Workspace every close is a real commit to a real repository, so Notes are version-controlled and recoverable from the first one written. A Remote adds off-machine durability and multi-device access. Neither is a data-safety precondition.

### Deferred (Next Planning Wave)
Wave 3 was shaped by the realignment interview (2026-08-21) rather than inherited: it runs **two genuinely parallel tracks** — the sync/conflict backbone and the interactive design epic — with the handoff points drawn below per open decision OD-03. Every capability the realignment added has a home here; none is orphaned.

**Track 1 — sync backbone:**
- **Epic G — Sync Integration**, carrying: connect and detach (`CAP-SYNC-01/06`), second-device join via `clone_workspace` (`CAP-SYNC-07`) with guided consolidation (`CAP-SYNC-08`, `plan_consolidation`/`apply_consolidation`), session restore, credential readback, scheduler lifecycle wiring, the sync status indicator, bounding the scheduler's shutdown wait, and the post-conflict re-push timing question. Absorbs all six of Epic C's deferred follow-ups plus the `rust/src/api/auth.rs` rework, which is not a wiring item: `OAuthFlowStart` currently returns `code_verifier` and `state`; the contract returns a single-use `flow_id` and neither secret, and `authenticate_workspace(flow_id, auth_code, returned_state) -> SessionState` must raise `OAuthStateMismatch` before any token request. Until Epic G lands, the shipped code still mints a `state` nothing compares — the original CSRF defect, unchanged — and this supersedes Epic C's recorded position that the verifier transiting Dart was an accepted decision: under the current contract it does not transit Dart at all.
- **Epic H — Conflict & Suggestions**: conflict-marker pre-processing, populating the Suggestion node, block-level accept/reject (`CAP-SYNC-04` as ruled at Q4), markers flowing freely through commits per B3, and the delete-vs-edit restore-and-suggest path from Q6. Prerequisite recorded in the contract: `Suggestion.base_content` requires the pull path to set a three-way conflict style.
- **GitLab provider** (`CAP-SYNC-09`, P1) lands behind GitHub inside this track once the seam has one proven consumer (ADR-009, B5).

**Track 2 — design system and surfaces:**
- **Design & Preferences epic** (`CAP-PREF-01`): interactive by decision — human-driven design work expressed through `hitl_sil` and `visual_regression` acceptance modes, not Gherkin-by-default. Produces burlmd's design tokens.

**Handoff points between tracks (OD-03):** the design epic delivers tokens before three consuming surfaces build final UI: the sync status indicator (Epic G renders it, but its visual form waits for tokens), the editor chrome Epic F's wave-3 follow-ups touch, and CAP-PORT-04's rendition, which is explicitly sequenced behind this epic. When both tracks want the same hands on the same day, Track 1's correctness work wins and design slips — solo-dev reality, stated here so the slip is planned rather than felt as failure.

**Riding either track, placed by dependency rather than by theme:**
- Undo (`CAP-EDIT-08`), version restore (`CAP-HIST-01`), in-Note find & replace (`CAP-FIND-03`) — a Wave-3 editor-depth cluster after Epic F proves the promotion model; each consumes its declared contract surface (`undo_note`/`redo_note`, `list_note_versions`/`restore_note_version`, `find_in_note`/`replace_all_in_note`).
- Diagnostics export (`CAP-SUP-01`) — rides Epic I alongside CI, since ADR-011's log channel and the nightly benchmark share the observability work.
- **Epic I — Quality & Portability** (revised): continuous integration as the Linux+macOS matrix chosen at Q9, the nightly non-blocking benchmark job verifying every meter in `prd/constraints.md`, images (`CAP-EDIT-06`, `assets/` per Q7), Export surfacing (`CAP-PORT-02`, `export_workspace` + `.okf` archive), and the graph visualization (`CAP-GRAPH-06`).

### Built, and still unsurfaced
Three Core capabilities were built in Epic D with no consumer in Epic E or F. They are now **built and shipped** rather than planned, and each is still unreachable from the running application — which is exactly the state this section exists to keep visible, since this whole wave was scoped because Epics A–C shipped Core components nothing called.

- **Backlinks** (`CAP-GRAPH-05`, P1). `WSPC-D009` built the query and `idx_links_target` backs it, but no ticket surfaces inbound Links in the UI. The index work was not wasted: the same table and index serve the link rewriting `WSPC-D006` depends on, which is why it was built then rather than deferred wholesale.
- **Title-prefix jump** (`CAP-FIND-02`, P1). `WSPC-D009` built `find_notes_by_title`, but `SHEL-E006` is full-text search and no ticket surfaces the title jump. Two notes for whoever picks it up: it matches a **leading prefix only**, which is a deliberate Stage 3 narrowing of CAP-FIND-02's "part of its title" recorded in `tech-spec/contracts/ffi_api.rs`; and its per-keystroke cost is unmeasured, since `schema.sql` declares no index on `notes(title)` and the query scans the Workspace's rows. Measure it before putting it behind a palette.
- **Opening a foreign Workspace** (`CAP-WS-05`, P1). `WSPC-D004` exposed it and the indexer tolerates non-conformant files for its sake, but no ticket adds a directory picker.

Separately, three capability fragments — two P0, one P1 — are covered by ticket criteria that never cite them, which is a traceability gap rather than a coverage one — but this section exists precisely so gaps get written down rather than discovered:

- `CAP-EDIT-02`'s Block-type list is covered by `EDIT-F002` for headings, lists, blockquotes and code, but the ticket cites no capability id and **thematic breaks appear in no criterion anywhere**. Added to `EDIT-F002`.
- `CAP-GRAPH-03` (follow a Link to open its target) survives only as an incidental criterion inside `EDIT-F006`, a ticket about *insertion*. Named there explicitly now.
- `CAP-GRAPH-04`'s second half — create the Note by following a ghost Link — had no criterion at all, despite the contract asserting the UI "creates the Note on follow". Added to `EDIT-F006`.

Sweeping every `CAP-*` id against the active tickets and the contract afterwards left four unreferenced, all deferred by design and all already accounted for above: `CAP-EDIT-06` (images) and `CAP-GRAPH-06` (graph visualization) to Epic I, `CAP-SYNC-02` to Epic G, and `CAP-EDIT-07`, a P2 explicitly redundant with the keyboard shortcuts `EDIT-F005` delivers. Two P0s — `CAP-WS-02` and `CAP-WS-04` — were covered by `WSPC-D007` and `WSPC-D004` without being named in either; they are named now.


The three built-but-unsurfaced capabilities above — backlinks, the title-prefix jump, and opening a foreign Workspace — need only UI work to become reachable, and all three belong in the next wave alongside Epic G. The traceability fragments listed after them are a separate matter, and are closed in this wave.

### Deferred (Future Scope)
Mobile targets, multiple simultaneous Workspaces, and adopting a non-empty Remote. Each has a standing entry under `prd/out-of-scope/` explaining the reasoning and the conditions that would reopen it.
