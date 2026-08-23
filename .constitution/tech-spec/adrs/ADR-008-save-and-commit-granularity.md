# ADR-008: Four-Tier Persistence — Draft, Write, Commit, Push

**Status:** Accepted

## Context
`architecture/flows/flow-sync-push.md` begins with "Core → Local: Commit final Markdown to disk", and nothing anywhere defines what triggers that. `prd/actors.md` v1.1.0 describes an actor comfortable with version control as a concept but unwilling to perform merges by hand, and `prd/vision.md` positions the product as one you open and write in — so a save button and a commit-message dialog are both out.

Two existing commitments constrain the answer. `architecture/resilience.md` promises that the Core Engine "synchronously persists all ongoing drafts to a local `drafts` SQLite table on every keystroke", restored on reboot — a `drafts` table exists in `data-models/schema.sql` with, as of today, zero readers and zero writers anywhere in the codebase. And PRD v1.1.0's CAP-WS-02 requires every editing session to be captured in local version history, with earlier versions recoverable.

Those two fit together usefully: if drafts absorb crash-safety, file writes need not be per-keystroke, and commits need not be per-write.

`rust/src/sync/scheduler.rs` already implements `SyncScheduler::notify_activity()` and has never had a caller — Epic C deferred item 4.

## Decision
Persistence is tiered, with each tier triggered by a different event and serving a different guarantee.

1. **Every mutation → `drafts` table.** Every edit to the Note's working source is written to the encrypted `drafts` row for that Note — not only the per-keystroke `update_block`, but equally `insert_block`, `delete_block`, `split_block`, `merge_block_with_previous`, `delete_range`, `replace_range` and — outside the editing section, which is why it is easy to miss — `resolve_suggestion`. Each of those is triggered by a discrete user action with no preceding keystroke call, so scoping this tier to "the focused Block's source" — as an earlier revision did — left pressing Enter or Backspace-at-offset-0 living only in memory until the tier 2 timer fired roughly a second later. A kill in that window loses it, which is exactly what this tier exists to prevent. `commit_block` is the sole mutator that writes nothing here, because what it reparses is already in the row. **A successful tier 2 write clears it**, so a draft row means "work not yet on disk" rather than merely "work happened". Without that clearing the row survives every mid-session write, byte-identical to the file — which would make `pending_drafts` and `restored_from_draft` report recovered work for Notes where nothing was lost, and `flow-edit-note.md`'s justification for parsing the draft in preference to disk ("a draft row exists precisely when its content differs from disk") false. Reporting a false alarm on the common path is how a real one stops being believed. This is the crash-durability tier and satisfies `resilience.md`'s guarantee and CAP-WS-03. It is encrypted at rest by virtue of living in the index, and it never touches the Workspace tree.

   **It is not cheap, and an earlier revision of this sentence said it was.** `SPK-WSPC-D001` §4.3 measured it against the encrypted index on real storage, with content that actually changes on each call: **7.96ms median at 102 KiB** and 22.79ms at 1 MiB under SQLite's defaults — half the frame budget at 102 KiB and past it outright at 1 MiB — falling to 2.41ms and 16.14ms under `journal_mode = WAL` with `synchronous = NORMAL`, which `WSPC-D004` accordingly issues on every connection. It is roughly a thousand times the cost of the buffer substitution and span arithmetic it accompanies, and it is the single most expensive thing on the typing path. Two consequences the tiering is structured around: the state lock is released *before* this write (see the amended contention bullet below), so the expensive part runs holding nothing a keystroke needs; and any benchmark that rewrites a constant string measures 0.22ms and is wrong by a factor of 36, because a SQLCipher row write costs radically different amounts depending on whether the content changes.
2. **~1s idle → atomic file write.** The Note's working source is written to the file atomically, in full and verbatim. This is the tier at which the Workspace on disk becomes correct and OKF-conformant, and at which an external tool would see the change. The splice already happened, in `update_block`; this tier performs none of its own, as the paragraphs below work through — an opening sentence saying otherwise is the model this decision replaced.

   The timer measures time since the last `update_block`, and it **may fire while the Block is still focused** — otherwise a Note left focused indefinitely would never reach disk, which is the opposite of what this tier exists for.

   What it writes is the **working source**: one buffer per open Note, holding the Note's full current text, identical to what `drafts.raw_markdown` persists. The substitution happens in `update_block`, not here — this tier writes that buffer verbatim and atomically, and performs no splice of its own.

   That placement is load-bearing rather than stylistic. An earlier revision had this tier splice the buffered Block source over that Block's span and "shift every later span by the byte delta", which is wrong in a way that silently corrupts a Note: the edited Block's own span is **resized**, not shifted, and a rule that only mentions later spans leaves its end where it was. Work it through on `AAA\n\nBBB` with Block 1's span `[0,3)` and a buffer of `AAAXX`. Tier 2 writes `AAAXX\n\nBBB` and moves Block 2 to `[7,10)`, but leaves Block 1 at `[0,3)`. The next splice over `[0,3)` replaces `AAA` with the whole buffer `AAAXX` and yields `AAAXXXX\n\nBBB` — the typed bytes duplicated, inside a Block the user is still typing in, in violation of the Edit Fidelity constraint the entire ADR-007 design exists to guarantee. Having exactly one writer of the working source removes the class rather than patching the instance.

   `update_block` therefore owns the arithmetic: it substitutes the new Block source into the working buffer, moves that Block's span end by the byte delta, and shifts every later span by the same delta. It does **not** reparse, so the focused Block's node may be stale in *shape* — a paragraph that has gained a leading `- ` is still an `AstNode::Paragraph` until blur — but nothing renders from it while it is focused, because under ADR-006 the user is looking at raw source. `commit_block` reparses the working buffer on blur and rebuilds the map outright.

   On `architecture/risks.md` risk 7, which says offset arithmetic is an optimization to reach for only if reparse cost is measured to matter: that warning is about using arithmetic *in place of* a reparse to keep a map valid across a **structural** change, where the errors are silent. This is a narrower thing — one span's end moves and every later span shifts by one uniform delta, within a single Block whose structure is not being re-derived, and a full reparse follows at blur. `WSPC-D001` still decides whether arithmetic is warranted for the *committed* splice path, which is the open question; this case is settled here so the spike is not asked to re-decide it.
3. **Note close or application quit → one Git commit, and none when nothing changed.** Deliberately *not* on a timer. A commit covers whatever changed during that editing session for that Note, with a generated message. This is the version-history tier satisfying CAP-WS-02 and CAP-LIFE-04's recoverable deletion.

   The no-change case is stated explicitly because it is the *most common* path through this tier, not an edge: opening a Note to read it and navigating away calls `close_note`. Committing unconditionally would put one empty commit in history per Note visited, which destroys the readable history the Positive consequence below claims as this design's whole justification. A close with nothing to commit makes no commit and notifies nothing.
4. **Commit → `notify_activity()`.** The commit is what signals the sync scheduler, giving the already-built debounce and backoff machinery its first real caller.

The user is never shown a save control, a commit message field, or a Git concept at any tier.

## Amendment — 2026-08-21 (realignment surfaces)

Decision 1's mutator enumeration was written as exhaustive when the contract had a closed set of content mutators. The realignment adds three — `undo_note`, `redo_note` and `replace_all_in_note` — and the rule is now general rather than enumerative: **every present and future content mutator increments `edit_seq` while it changes state and persists the resulting draft row**, because work an operation restores or produces must be crash-durable the moment it exists, not when the idle timer happens to fire. The row write runs after releasing the state lock, as the later tier-1 locking amendment specifies. Undo's entries store inverses over source text (ADR-010), so an undo after the idle write is itself a tier-1 mutation followed by the ordinary tier sequence; no new persistence mechanism exists or may be invented for it.

## Amendment — PR #10 review, round 4

Each open Note has a per-Note tier 1 mutation lock. A source mutator takes this lock before changing state and retains it through its draft-row write. Lifecycle code takes the same lock before it installs replacement source, spans, AST, metadata, and revision. The lock therefore linearizes source mutation through crash-durable draft persistence and lifecycle installation.

The only permitted acquisition order is lifecycle, tier 2 write, tier 1, state, then connection. A caller can take a suffix of that order, but it must not invert it. The state lock protects the in-memory snapshot only and must be released before database or filesystem I/O. Tier 1 may remain held while its Note's draft statement runs. Tier 2 may remain held across its file write because no typing path takes it.

A structural mutation saves its complete prior state before installation. If its draft statement fails while that state remains authoritative, it restores the prior source, spans, AST, metadata, edit sequence, and write flags, and it does not arm an idle write. If tier 2 has already published the installed source, rollback is unsafe. That branch returns the installed `NoteState` as authoritative success and leaves the source recoverable rather than asking the caller to repeat a mutation already on disk.

The targeted tier 1 test recorded a 2.070 ms p95 draft write for a 102,472-byte Note across 25 paced samples, below the 16 ms interaction gate. This measurement covers that draft-write path only; it does not establish end-to-end UI responsiveness.

## Amendment — PR #10 review, round 7

A source-mutating FFI call takes a Workspace edit lease before it looks up an
open session and retains it through the tier-1 draft write. A lifecycle
operation closes admission, drains every pre-existing lease, then plans from
open-session and `drafts` snapshots. Later source mutations refuse unchanged
while the lifecycle operation is active. The admission state is not a sixth
lock and is never held across source state, SQLite, filesystem, or Git work.
This closes the stale-handle race where a request paused after lookup could
outlive a rename, move, deletion, or same-id inbound-link rewrite.

The FFI owns the one counted lease. Direct `NoteSession` mutation methods
remain safe for internal callers by borrowing that same thread-local lease when
one already exists; they do not attempt a second admission after lifecycle has
closed the gate. A lifecycle reopen guard is constructed immediately after it
closes admission, so even a poisoned wait restores future admission.

Structural operations whose return value must name a post-splice editable leaf
derive that value before state installation and draft persistence. A source
fragment that parses only as unaddressable Markdown therefore refuses without
installing hidden content; retrying with addressable text applies exactly once.

Lifecycle operations distinguish a refusal from a terminal post-publication
warning. After the filesystem, index, and sessions settle, a failed Git commit
returns `LifecycleResult` with the authoritative state, effects, or removed
ids plus `LifecycleWarningStage::Commit`; a later cleanup or advisory state
refresh returns the same result with `LifecycleWarningStage::Settlement`.
When both occur, `Commit` remains primary and records the settlement context.
It does not return `AppError` after publication.
This includes ordinary create and create-on-follow: once their Note/session is
authoritative, a failed Git record is a warning and not a rollback trigger.
Presentation settles that result first and then shows a dismissible warning.
Only a failure before authoritative lifecycle mutation returns `AppError`, so
the prior editor remains writable only when its Core session remains valid.

## Consequences
- **Positive:** Version history stays readable — approximately one commit per Note per writing session, rather than one per keystroke or one per arbitrary time slice. Timer-based commits were explicitly rejected on the grounds that a 30-second boundary splits a single thought across two commits for no reason a reader of the log could reconstruct.
- **Positive:** The `drafts` table stops being dead schema, and `notify_activity()` stops being dead code.
- **Positive:** ADR-007's whole-file reparse lands on blur, in `commit_block`, which takes it off the *keystroke* path — the one place a per-character cost would compound. An earlier version of this bullet placed the reparse at tier 2. That was wrong in both directions: tier 2 is a write, not a parse, and pinning the parse to a *timer* would have let it fire mid-typing during a pause, which is precisely the placement this tiering exists to avoid.
- **Negative, and not to be read away:** blur is *not* outside the 16ms budget. `prd/constraints.md` sets that budget over "writing and editing interactions… including the transition of a Block into and out of its raw editing state", and leaving focus is exactly that transition. Earlier versions of this bullet and of ADR-007's claimed the reparse fell outside the budget, which would have given an implementer a citable reason to dismiss a slow blur as out of scope. It does not: a synchronous O(file) splice-and-reparse sits directly inside a frame the user is watching, which is why `WSPC-D001` measures it at realistic Note sizes and carries a STOP if it cannot be met.
- **Negative:** A Note left open for hours is written to disk but not committed for hours, so it is also not pushed for hours. Local file writes protect against application crash; they do not protect against loss of the machine. This is the accepted cost of clean history, and it is the reason tier 2 exists at all rather than deferring the write to close as well.
- **Negative, settled by `SPK-WSPC-D001` §6.2 and implemented by `WSPC-D007`:** the tier 2 timer is Core-owned and fires on its own thread, while `update_block` and `commit_block` are `#[frb(sync)]` and run on the Dart caller's thread. Both touch the same working source and span map, and the timer side additionally performs an encrypted SQLite write and an atomic file write. Reusing `db::connection`'s process-wide `Mutex<Connection>` naively means a keystroke blocks on a lock held across a disk write — reproduced as a number: a keystroke p95 of 90.4ms at 1 MiB under SQLite's defaults, with the buffer mutation alone, work that does no I/O at all, waiting a p95 of 55.9ms for the lock. The shape that replaces it, and the discipline it imposes:

  1. **A per-Note state lock over an `Arc<String>` working source, never held across I/O.** The lock guards {working source, span map, edit sequence, recorded revision}; every writer takes an `Arc::clone` snapshot under it and releases it before touching the connection or the filesystem, mutating through `Arc::make_mut`. Measured: the tier 2 side holds the state lock for a median, p95, and maximum of 0.000 / 0.000 / 0.001ms at both 102 KiB and 1 MiB, and the keystroke's own buffer-and-span work never waits.
  2. **A per-Note tier 1 mutation lock spans source mutation, draft persistence, and lifecycle installation.** It is acquired after lifecycle and tier 2 and before state. It may remain held for the draft statement, but the state lock must be released first. A Workspace edit lease starts before source-mutation session lookup; lifecycle drains those leases before snapshotting, while later calls refuse without waiting on lifecycle I/O.
  3. **One total acquisition order is lifecycle → tier 2 write → tier 1 → state → connection.** The keystroke path takes tier 1, state, and connection. Tier 2 and lifecycle callers take longer prefixes. No caller may invert this order.
  4. **The edit sequence is persisted in the `drafts` row, and tier 2's clear is conditional on it.** Every tier 1 mutator increments the sequence in the same critical section as the buffer mutation and stores that value in the row it writes. `commit_block` must **not** increment it, since it writes no row and an increment there would suppress every later clear. The timer clears with `DELETE FROM drafts WHERE note_id = ?1 AND edit_seq <= ?2`, bound to its snapshot's sequence, so the comparison is against the row rather than against an in-memory counter that leads it. `<=` rather than `=` because a row lagging the snapshot is redundant once the newer bytes are on disk. The residual case is benign and asymmetric by design: failing to clear costs one spurious "restored from draft" notice, clearing wrongly costs the user's work, so every ambiguous case resolves toward keeping the row.
  5. **A dedicated per-Note tier 2 write lock spans OCC check → write → re-record.** Tier 2 has more than one writer — the idle timer and `close_note` — so two writes for one Note can be in flight at once. The Optimistic Concurrency Control check is a time-of-check-to-time-of-use bug unless one lock spans the whole sequence. This lock is held across the file write because no keystroke path takes it. It also requires uniquely named temporary files per write.
  6. **Standing review rules follow.** No closure passed to `with_connection` may perform file I/O. The state lock must not span I/O. No lock that a keystroke can contend for may be held across an `fsync`. No tier 2 write may be issued outside the tier 2 write lock. All four rules are what a careless persistence change would break first.
- **Negative:** "Application quit" must actually commit, which makes shutdown a correctness path rather than a courtesy. An unclean kill leaves the file written but uncommitted — recoverable, since the content is on disk, but absent from history until the next session closes the Note.
- **Negative:** Three distinct triggers must each be debounced and cancelled correctly when the user switches Notes mid-edit. Switching away from a Note is a close, and must flush tiers 2 and 3 before the new Note opens.
- **Two things tier 3 needs that `rust/src/git/` does not yet provide.** Recorded here because both are contract-shaped rather than wiring. When this was first written the module appeared in no ticket's scope; that is no longer true — `WSPC-D004` scopes `rust/src/git/operations.rs` for the initialization function and `WSPC-D007` scopes it for the pathspec-scoped commit and the author identity, which are exactly the two items below. They are owned. The text stays because it is where the *decisions* live, not because the work is unassigned:
  1. `commit_all(repo_path, message, author_name, author_email)` commits the **whole worktree**. Tier 3 wants one commit covering one Note's session, and with two Notes dirty on disk, closing one would sweep both — contradicting the "approximately one commit per Note per writing session" claim above. It needs a pathspec-scoped sibling.
  2. **Commit identity is unspecified.** `commit_all` demands an author name and email, this ADR says the user is never shown a Git concept, and nothing anywhere says where those values come from. Decided here rather than improvised: commits are authored as `burlmd <noreply@burlmd.invalid>`, using `.invalid` because RFC 2606 reserves it precisely so it can never resolve. This is deliberately not the user's identity — the local Workspace has no account and asking for one would reintroduce the onboarding step ADR-005 removed. Once a Remote is attached, Epic G may set a provider identity for *subsequent* commits; it must not rewrite earlier ones, since the whole point of tier 3 is that history exists before any Remote does.
- **Neutral:** Commit message generation becomes a small specified behavior rather than a user input. It has no correctness weight, but it is what the user reads when recovering an earlier version, so it should name the Note and the nature of the change.
