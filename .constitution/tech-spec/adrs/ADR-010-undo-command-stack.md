---
id: ADR-0010
status: accepted
date: 2026-08-21
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-010: Core-Side Undo Command Stack Over Content Operations

**Status:** Accepted

## Context
Nothing specified undo anywhere in any layer before the realignment interview. Flutter's IME gives per-field undo inside a focused Block only; across Block boundaries, range deletions, splits and merges there is no recovery short of version history, whose granularity is one commit per editing session. CAP-EDIT-08 rules that unacceptable: lost work is the failure this actor forgives least, and every competing editor reverses structural operations.

## Decision
1. **The Core owns the undo stack, per open Note.** Every content mutation that changes the working source — splice, block insert/delete/split/merge, range delete/replace, find-and-replace-all — records enough inverse information to reverse itself exactly. The UI stays stateless, consistent with the container rule; undo is Note content state.
2. **Depth is bounded at roughly 100 steps per Note;** at the bound the oldest step falls off. Unbounded stacks are memory leaks with good intentions.
3. **Exclusions are part of the decision, not omissions:**
   - *Lifecycle operations* (create/rename/move/delete) are outside undo — they are atomic, confirmed where destructive, and recoverable through version history by design.
   - *Sync-applied changes* (a pull altering files under the user) are outside undo — reverting a remote peer's contribution is conflict resolution, not undo, and belongs to the Suggestion surface.
   - Anything that closes or reloads the Note clears its stack: undo cannot reach across a re-derivation of state from disk.
4. **Undo entries survive tier transitions within a session** — an undo after the idle write must restore prior content and record a new change, not fight the persistence tiers. The stack stores inverses over source text, which is stable across tiers precisely because ADR-007 made splicing the only mutation mechanism.
5. **`undo_note` / `redo_note` return authoritative post-operation state**, like every other mutator, so focus and spans re-derive rather than persist.

## Consequences
- **Positive:** Cross-Block deletion, the operation IME undo cannot see, becomes reversible in place.
- **Positive:** Undo composes with Edit Fidelity for free — reversing a splice is another splice, so untouched regions stay untouched.
- **Negative:** Every new content mutator now owes an inverse; forgetting one is a silent coverage gap. The contract section lists the covered set explicitly, and a mutator absent from it is a defect to raise, not an extension to improvise.
- **Negative:** Memory holds inverse text for ~100 steps per open Note; acceptable at the Idle Memory meter's scale, and the bound caps it.
- **Neutral:** Redo is the same stack's forward pointer; clearing on any divergent new edit follows ordinary editor convention.
