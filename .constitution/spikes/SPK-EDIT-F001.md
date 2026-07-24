# Spike Report: EDIT-F001 Rendered-to-Raw Promotion Fidelity

> **Status: placeholder.** Established by the Stage 4 planning pass to satisfy the Spike Protocol. The findings below are filled in during execution of EDIT-F001; nothing here is a result yet.

## 1. Context & Objective
- **Triggering upstream file/section:** `.constitution/tech-spec/adrs/ADR-006-raw-on-focus-editing.md` decisions 2 and 6, and its first Negative consequence; the typographic-identity standard in `tech-spec/guidelines.md`.
- **Target:** Whether promoting a Block from its formatted presentation to its raw editable presentation can be made free of visible layout movement, and what must be held identical for that to hold.

Under CAP-EDIT-01 the text necessarily differs between the two states — `**bold**` versus bold. The geometry must not. If it does, every Block visibly jumps as the caret moves through the Note, which would make the editing model unpleasant in exactly the way it exists to avoid.

## 2. Codebase Baseline
- **Current State:** [To be filled from direct inspection. Known going in: `lib/src/components/editor.dart` already dispatches between a read-only render path and an editable path, so both presentations exist to compare.]
- **Discovered Constraints:** [To be filled.]

## 3. Options & Trade-offs
- **Option A — promote-on-focus** (ADR-006 decision 2). Cheapest, extends the existing dispatch, inherits platform text editing. Viable only if the two states can be made typographically identical.
- **Option B — custom selectable render objects per Block** (ADR-006 decision 6). No promotion at all, so no movement is possible; costs implementing selection highlight painting and selection-event handling directly.
- [Screenshot comparisons per Block type to be recorded here.]

## 4. Execution Directives
- **Chosen Option:** [To be filled.]
- **Why it fits:** [To be filled.]
- **Downstream Backlog Impact:** Unblocks `EDIT-F002` (Live Preview Block Promotion) and through it the rest of Epic F. A not-viable verdict selects ADR-006's escalation path, which changes the shape of `EDIT-F002` and is a Stage 3 decision rather than an improvised widget change.

## 5. Method note
The verdict must come from inspected rendered output, not from widget-property assertions. Property assertions are precisely what failed to catch the structurally similar defect during Epic B's closeout, where six passing tests missed a paragraph rendering bug that a single screenshot exposed.
