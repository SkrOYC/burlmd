# Spike Report: WSPC-D001 Span Invalidation Under Source Splicing

> **Status: placeholder.** Established by the Stage 4 planning pass to satisfy the Spike Protocol. The findings below are filled in during execution of WSPC-D001; nothing here is a result yet.

## 1. Context & Objective
- **Triggering upstream file/section:** `.constitution/architecture/risks.md` risk 7 (Span Invalidation Under Splicing); `.constitution/tech-spec/adrs/ADR-007-span-preserving-splice-edits.md` decision 1 and its first Negative consequence.
- **Target:** How the Core Engine maintains source spans across a splice, and the Note size at which the chosen strategy stops meeting the 16ms frame budget in `prd/constraints.md`.

The risk is a silent data-corruption mode rather than a crash: splicing one Block shifts every subsequent byte offset, so a stale span map writes a later edit into the wrong region of the file. ADR-007 names whole-file reparse as the mitigation because it makes an incorrect span map unrepresentable, but the cost of that choice has never been measured.

## 2. Codebase Baseline
- **Current State:** [To be filled from direct inspection. Known going in: `rust/src/markdown/parser.rs` builds an AST with no span information today; `Parser::into_offset_iter()` is confirmed present in the pinned parser version.]
- **Discovered Constraints:** [To be filled.]

## 3. Options & Trade-offs
- **Option A — whole-file reparse after every committed splice.** Correct by construction; an incorrect span map cannot be represented. Cost is O(file) per committed edit. ADR-008's tiering is what keeps this off the per-keystroke path.
- **Option B — arithmetic offset adjustment.** Shift spans after the splice point by the length delta. Cheaper, but reintroduces exactly the failure mode risk 7 describes, and the errors it produces are silent.
- [Measured timings across at least three Note sizes to be recorded here.]

## 4. Execution Directives
- **Chosen Option:** [To be filled.]
- **Why it fits:** [To be filled.]
- **Downstream Backlog Impact:** Unblocks `WSPC-D003` (Span-Preserving Parse and Splice Engine), and through it the whole of Epic D's write path. If Option A proves unviable at realistic Note sizes, that is a STOP condition requiring a Stage 3 pass rather than an improvised move to Option B.
