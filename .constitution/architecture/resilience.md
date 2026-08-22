# Resilience & Cross-Cutting Concerns

## Sync Failure Handling
- **Network Disconnection:** The Sync Manager utilizes exponential backoff when pushing or pulling from the Remote Repository fails due to network conditions. The UI is never blocked by these failures; an ambient status indicator simply reflects "Offline".
- **Authentication Expiration:** If the OAuth token expires, the Sync Manager pauses all operations and signals the Core Engine, which instructs the Presentation Container to prompt for re-authentication. Local editing remains fully operational.

## Conflict Resilience
- **Non-Destructive Merges:** Standard remote sync conflicts never result in data loss or application crashes. The Core Engine parses raw conflict markers, preserves both variants, and structures them into a safe AST "Suggestion" node. The local index remains valid and searchable even while conflicts are pending resolution by the user.
- **Reconciliation never gates:** unresolved Suggestions do not block commits, pushes, or any editing capability; they may flow through version history as marker-bearing commits until resolved. The ambient synchronization state distinguishes "pending Suggestions" from clean, so honesty replaces blocking.

## Data Integrity
- **Stateless UI Crash Recovery:** Because the Presentation Container is stateless and streams updates to the Core Engine's active draft cache, a UI crash does not result in data loss. Upon restart, the UI requests the active draft from the Core Engine.
- **SQLite Draft Persistence:** To mitigate process-wide crashes (e.g., OOM kills), the Core Engine synchronously persists all ongoing drafts to a local `drafts` SQLite table on every keystroke. Upon application reboot, the draft is restored from the database.
  - **Superseded (Epic B status note), and now implemented.** The note here recorded that nothing read or wrote the `drafts` table and that the mechanism needed its own ticket. `WSPC-D007` shipped all four tiers of ADR-008, of which this guarantee is tier 1: every mutation writes the encrypted `drafts` row, a successful tier 2 file write clears it conditionally, and `pending_drafts` reports what survived a kill. `SHEL-E007` still owns surfacing the recovery in the UI, so the guarantee holds in the Core and is not yet visible to a user. ADR-008 is the specification for the behaviour described above, including the ordering `flow-edit-note.md` makes explicit — a restored draft is the source that gets *parsed*, not a flag attached to an AST built from the disk bytes.
  - **One correction to the wording above, carried from `SPK-WSPC-D001` §4.3.** "Synchronously persists… on every keystroke" is accurate and is what ships, but it is not free: the encrypted row write costs 7.96ms at 102 KiB under SQLite's defaults and 2.41ms under the WAL/`NORMAL` settings now issued at connection open. The tiering is arranged around that number — no lock a keystroke needs is held across the write — rather than around an assumption that it is negligible. See ADR-008 tier 1.
- **Atomic Commits:** Saves to the Local Repository are atomic. If the application terminates abruptly during a save, the previous state is preserved.

## Observability & Diagnostics
- **A structured local log is a first-class deliverable**, not an afterthought: the Core's internal outcomes — sweep results, write-tier failures, retries, scheduler decisions — must have somewhere to go besides vanishing. Today at least one diagnostic result is computed and then unreachable because no channel exists to receive it; every future Core-side outcome assumes this channel exists.
- **The log never leaves the device on its own.** It exists so a user can produce a content-excluding diagnostics bundle on demand (CAP-SUP-01) and hand it to someone troubleshooting. Note content never enters the log in any form.
- **Failure visibility is part of resilience:** a write tier that fails silently, or a rescan that discards rows without trace, is indistinguishable from success. Every component that can fail reports that it did.

## Configuration
- **The configuration surface stays minimal and explicit:** where the Workspace lives, and overrides for tests. Everything else is behavior, not preference — until the Preferences capability lands its design system, no hidden settings file may accrete.
- **Defaults are decisions.** Each default location is recorded in the implementation specification rather than improvised, because moving one later is a user-visible migration.
