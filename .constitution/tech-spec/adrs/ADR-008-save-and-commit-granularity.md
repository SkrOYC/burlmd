# ADR-008: Four-Tier Persistence — Draft, Write, Commit, Push

**Status:** Accepted

## Context
`architecture/flows/flow-sync-push.md` begins with "Core → Local: Commit final Markdown to disk", and nothing anywhere defines what triggers that. `prd/actors.md` v1.1.0 describes an actor comfortable with version control as a concept but unwilling to perform merges by hand, and `prd/vision.md` positions the product as one you open and write in — so a save button and a commit-message dialog are both out.

Two existing commitments constrain the answer. `architecture/resilience.md` promises that the Core Engine "synchronously persists all ongoing drafts to a local `drafts` SQLite table on every keystroke", restored on reboot — a `drafts` table exists in `data-models/schema.sql` with, as of today, zero readers and zero writers anywhere in the codebase. And PRD v1.1.0's CAP-WS-02 requires every editing session to be captured in local version history, with earlier versions recoverable.

Those two fit together usefully: if drafts absorb crash-safety, file writes need not be per-keystroke, and commits need not be per-write.

`rust/src/sync/scheduler.rs` already implements `SyncScheduler::notify_activity()` and has never had a caller — Epic C deferred item 4.

## Decision
Persistence is tiered, with each tier triggered by a different event and serving a different guarantee.

1. **Keystroke → `drafts` table.** Every edit to the focused Block's source is written to the encrypted `drafts` row for that Note. This is the crash-durability tier and satisfies `resilience.md`'s guarantee and CAP-WS-03. It is cheap, it is encrypted at rest by virtue of living in the index, and it never touches the Workspace tree.
2. **~1s idle → atomic file write.** The Block's edited source is spliced into the file per ADR-007 and written atomically. This is the tier at which the Workspace on disk becomes correct and OKF-conformant, and at which an external tool would see the change.
3. **Note close or application quit → one Git commit.** Deliberately *not* on a timer. A commit covers whatever changed during that editing session for that Note, with a generated message. This is the version-history tier satisfying CAP-WS-02 and CAP-LIFE-04's recoverable deletion.
4. **Commit → `notify_activity()`.** The commit is what signals the sync scheduler, giving the already-built debounce and backoff machinery its first real caller.

The user is never shown a save control, a commit message field, or a Git concept at any tier.

## Consequences
- **Positive:** Version history stays readable — approximately one commit per Note per writing session, rather than one per keystroke or one per arbitrary time slice. Timer-based commits were explicitly rejected on the grounds that a 30-second boundary splits a single thought across two commits for no reason a reader of the log could reconstruct.
- **Positive:** The `drafts` table stops being dead schema, and `notify_activity()` stops being dead code.
- **Positive:** ADR-007's whole-file reparse after a splice sits at tier 2, off the typing path, so its cost never lands inside the 16ms budget from `prd/constraints.md`.
- **Negative:** A Note left open for hours is written to disk but not committed for hours, so it is also not pushed for hours. Local file writes protect against application crash; they do not protect against loss of the machine. This is the accepted cost of clean history, and it is the reason tier 2 exists at all rather than deferring the write to close as well.
- **Negative:** "Application quit" must actually commit, which makes shutdown a correctness path rather than a courtesy. An unclean kill leaves the file written but uncommitted — recoverable, since the content is on disk, but absent from history until the next session closes the Note.
- **Negative:** Three distinct triggers must each be debounced and cancelled correctly when the user switches Notes mid-edit. Switching away from a Note is a close, and must flush tiers 2 and 3 before the new Note opens.
- **Neutral:** Commit message generation becomes a small specified behavior rather than a user input. It has no correctness weight, but it is what the user reads when recovering an earlier version, so it should name the Note and the nature of the change.
