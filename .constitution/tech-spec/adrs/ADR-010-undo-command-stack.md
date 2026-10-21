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
2. **Depth is bounded, with roughly 100 steps per Note as the provisional input to measurement;** at the accepted bound the oldest step falls off. SPK-BURL-H001 and the final Stage 3 patch must publish the exact bounded retention value against NFC-05 and NFC-38 rather than converting "roughly" into an invented constant. Unbounded stacks are memory leaks with good intentions.
3. **Exclusions are part of the decision, not omissions:**
   - *Lifecycle operations* (create/rename/move/delete) are outside undo — they are atomic, confirmed where destructive, and recoverable through version history by design.
   - *Sync-applied changes* (a pull altering files under the user) are outside undo — reverting a remote peer's contribution is conflict resolution, not undo, and belongs to the Suggestion surface.
   - Anything that closes or reloads the Note clears its stack: undo cannot reach across a re-derivation of state from disk.
4. **Undo entries survive tier transitions within a session** — an undo after the idle write must restore prior content and record a new change, not fight the persistence tiers. The stack stores inverses over source text, which is stable across tiers precisely because ADR-007 made splicing the only mutation mechanism.
5. **`undo_note` / `redo_note` return authoritative post-operation state**, like every other mutator, so focus and spans re-derive rather than persist.

## Amendment — 2026-10-14 (first-use editing completeness)

Every first-use content operation has one explicit undo transaction boundary. A task-checkbox toggle, local-image reference insertion, formatting command, structural or range edit, replace-one, and replace-all each create one command. One committed input-method composition creates one command. Find navigation creates none.

Consecutive typing or deletion can coalesce while edit-driven caret advancement stays in the same editing context. Explicit caret navigation, a user selection change, focus change, command-kind change, or another semantic command ends the group. No timing heuristic defines correctness. Replace-all computes one nonoverlapping match set against one document revision and either records the complete operation once or leaves source and undo history unchanged.

ADR-021 changes the provisional in-Note find contract to literal, case-sensitive Note-body source search. Find sessions and match identities are revision-bound. A match in nonrendering source focuses its addressable raw region. Any intervening mutation rejects a stale session rather than applying replacement to shifted content.

## Consequences
- **Positive:** Cross-Block deletion, the operation IME undo cannot see, becomes reversible in place.
- **Positive:** Undo composes with Edit Fidelity for free — reversing a splice is another splice, so untouched regions stay untouched.
- **Negative:** Every new content mutator now owes an inverse; forgetting one is a silent coverage gap. The contract section lists the covered set explicitly, and a mutator absent from it is a defect to raise, not an extension to improvise.
- **Negative:** Memory holds inverse text for ~100 steps per open Note; acceptable at the Idle Memory meter's scale, and the bound caps it.
- **Neutral:** Redo is the same stack's forward pointer; clearing on any divergent new edit follows ordinary editor convention.
