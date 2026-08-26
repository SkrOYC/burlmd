# Functional capabilities

Priorities describe the forward release path. `P0` capabilities are required for the feature-complete `0.x` desktop release defined by this pass. Deferred work lives under `out-of-scope/` and doesn't appear in the active capability set.

## Delivered baseline

The following capabilities are implemented. Downstream stages must preserve them but must not schedule them as unfinished work:

| Capability ID | Delivered outcome | Rationale |
| :--- | :--- | :--- |
| CAP-EDIT-01 | The focused Block shows Markdown source, and other Blocks render formatted content. | Writers edit real source without losing a readable Note. |
| CAP-EDIT-02 | Writers can author and render headings, lists, blockquotes, code blocks, and thematic breaks. | Notes can express structured thought. |
| CAP-EDIT-03 | Writers can create, split, merge, and delete Blocks through ordinary typing. | Note structure can evolve during composition. |
| CAP-EDIT-04 | Writers can select and copy content across Block boundaries as faithful Markdown. | Common editing actions aren't limited by Block boundaries. |
| CAP-EDIT-05 | Writers can apply inline emphasis through standard keyboard shortcuts. | Formatting doesn't require manual delimiter entry. |
| CAP-LIFE-01 | Writers can create a Note in a chosen Directory. | A Workspace needs a direct content-creation path. |
| CAP-LIFE-02 | Writers can rename a Note without breaking inbound Links. | Routine renames must preserve the graph. |
| CAP-LIFE-03 | Writers can move a Note without breaking inbound Links. | Organization can evolve after writing. |
| CAP-LIFE-04 | Writers can delete a Note with recoverable local history. | Deletion remains safe to use. |
| CAP-LIFE-05 | Writers can create nested Directories. | The Workspace supports hierarchical organization. |
| CAP-LIFE-06 | Writers can rename and delete Directories while preserving contained Notes and inbound Links. | Hierarchy management is complete. |
| CAP-GRAPH-01 | Writers can browse the Workspace tree and open any Note. | Every Note remains reachable. |
| CAP-GRAPH-02 | Writers can insert a Link by searching existing Note titles. | Link creation doesn't require path entry. |
| CAP-GRAPH-03 | Writers can follow a rendered Link to its target Note. | The knowledge graph is traversable. |
| CAP-GRAPH-04 | Writers can create a Link to a Note that doesn't exist and create that Note by following the Link. | Ghost Links and create-on-follow are implemented end to end. |
| CAP-WS-01 | Writers can start in a local Workspace without an account or network connection. | Local writing has no external gate. |
| CAP-WS-02 | Closing an edited Note records its session in local history. | Local-only Workspaces retain recoverable versions. |
| CAP-WS-03 | Drafts survive abrupt process termination. | A crash doesn't discard in-progress work. |
| CAP-WS-04 | The local aggregate search index is encrypted with a key in Platform secure storage. | Aggregated Note content receives application-managed protection. |
| CAP-WS-06 | Writers can run an explicit Workspace Rescan. | Manual recovery remains available when automatic observation needs repair. |
| CAP-FIND-01 | Writers can search all Notes and open a result. | Knowledge remains retrievable as the Workspace grows. |
| CAP-PORT-01 | Every Note that burlmd creates conforms to the Open Knowledge Format. | Guest tools can read and traverse burlmd-created content. |

PR #11 also delivered the design system, responsive shell, preferences surface, localization foundation, keyboard accessibility, semantic labels, and deterministic visual evidence. Downstream stages must consume this foundation and must not create a retrospective design epic.

## Desktop session

- **Priority:** P0
- **Capability ID:** CAP-PREF-01
- **Capability:** When the Writer changes the theme, font scale, prose measure, focus mode, or update-notification preference, burlmd restores that device-specific choice after restart without synchronizing it through Workspace content.
- **Rationale:** The delivered preferences surface isn't complete until its choices persist.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-02
- **Capability:** Every tab-close entry point closes the affected Note through its durability and history lifecycle before burlmd removes the tab.
- **Rationale:** A tab button, middle-click, keyboard command, or batch action must not bypass Note persistence.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-03
- **Capability:** After restart, burlmd reopens the last Workspace and restores that Workspace's open Notes, active Note, navigation state, search state, and synchronization presentation when those items remain available.
- **Rationale:** A desktop writing environment must preserve working context across routine restarts.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-04
- **Capability:** The host operating system provides all window chrome. burlmd doesn't display or offer emulated operating-system chrome.
- **Rationale:** Presentation-only prototype controls conflict with the Platform and aren't part of the product.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-05
- **Capability:** During a batch close, burlmd processes Notes serially and stops before unprocessed tabs after the first error or degraded-durability warning.
- **Rationale:** Serial handling gives every closed or retained tab an unambiguous outcome.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-06
- **Capability:** If burlmd retires a Note session with a degraded-durability warning, it removes that closed tab, reports the warning, preserves every unprocessed tab, and cancels any Workspace switch or orderly shutdown.
- **Rationale:** A retired session can't remain as an open but unusable tab.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-07
- **Capability:** If a Note fails to close, burlmd keeps the failed and unprocessed tabs open, reports the partial result, and cancels the Workspace switch or orderly shutdown.
- **Rationale:** A close failure must not discard an active session or let a wider lifecycle operation continue.

- **Priority:** P0
- **Capability ID:** CAP-SHELL-08
- **Capability:** After the active tab closes, burlmd selects the following tab or the preceding tab when no following tab remains.
- **Rationale:** Deterministic focus preserves keyboard continuity.

## Note editing and retrieval

- **Priority:** P0
- **Capability ID:** CAP-EDIT-06
- **Capability:** Writers can insert images from a file, clipboard, or drag-and-drop action and view them inline in the Note.
- **Rationale:** Images are part of feature-complete daily note-taking.

- **Priority:** P0
- **Capability ID:** CAP-EDIT-08
- **Capability:** When the Writer invokes undo or redo, burlmd reverses or reapplies the most recent content operation in the open Note without consulting version history.
- **Rationale:** Undo must cover structural and cross-Block editing without conflating editing with synchronization or lifecycle history.

- **Priority:** P0
- **Capability ID:** CAP-FIND-02
- **Capability:** Writers can open a Note by typing part of its title without leaving the keyboard.
- **Rationale:** Title-based navigation is the primary retrieval path for a known Note.

- **Priority:** P0
- **Capability ID:** CAP-FIND-03
- **Capability:** Within an open Note, Writers can find matches, navigate between them, replace one match, or replace all matches as one undoable operation.
- **Rationale:** Workspace search doesn't replace precise editing inside a long Note.

- **Priority:** P0
- **Capability ID:** CAP-GRAPH-05
- **Capability:** Writers can view the Notes that link to the open Note.
- **Rationale:** Backlinks make the knowledge graph navigable in both directions.

## Workspace authority and recovery

- **Priority:** P0
- **Capability ID:** CAP-WS-05
- **Capability:** When the Writer opens a directory that burlmd didn't create, burlmd validates it before adoption, includes conforming Notes, and lists invalid Notes for explicit Repair or Exclude decisions.
- **Rationale:** Open storage permits guest tools, but burlmd remains the authority for Workspace semantics and must not rewrite foreign content silently.

- **Priority:** P0
- **Capability ID:** CAP-WS-07
- **Capability:** While a Workspace is open, burlmd detects guest file creates, edits, moves, renames, and deletes without requiring Rescan.
- **Rationale:** A guest tool can write while burlmd runs, and those changes must not remain invisible.

- **Priority:** P0
- **Capability ID:** CAP-WS-08
- **Capability:** When a guest changes a clean open Note with conforming content, burlmd validates and indexes the change, records it in local history, and reloads the Note.
- **Rationale:** A clean Note can adopt valid guest work without an unnecessary decision.

- **Priority:** P0
- **Capability ID:** CAP-WS-09
- **Capability:** When a guest changes a Note with an unsaved burlmd draft, burlmd preserves both versions and offers **Compare**, **Keep burlmd version**, or **Load external version**.
- **Rationale:** Same-device concurrent writes are file-authority decisions, not Remote Suggestions.

- **Priority:** P0
- **Capability ID:** CAP-WS-10
- **Capability:** Before burlmd applies a dirty-Note decision, it verifies that the guest file revision hasn't changed and requests another decision when it has.
- **Rationale:** A Writer's choice must not apply to a guest revision they didn't review.

- **Priority:** P0
- **Capability ID:** CAP-WS-11
- **Capability:** Before repairing invalid guest content, burlmd preserves the original bytes and previews every proposed change for the Writer.
- **Rationale:** Explicit repair isn't informed when the Writer can't inspect what burlmd will rewrite.

- **Priority:** P0
- **Capability ID:** CAP-WS-12
- **Capability:** For an invalid guest write detected while the Workspace is open, burlmd preserves the last known-good Note and offers **Repair**, **Compare**, or **Exclude** before authoritative state changes.
- **Rationale:** Invalid live input must not silently replace readable content or block access to the preserved version.

- **Priority:** P0
- **Capability ID:** CAP-WS-13
- **Capability:** Writers can explicitly open or switch to an existing Workspace. burlmd keeps one Workspace active and completes the normal Note close lifecycle before switching.
- **Rationale:** Workspace access must not depend only on restart restoration or first-time adoption.

- **Priority:** P0
- **Capability ID:** CAP-HIST-01
- **Capability:** Writers can list a Note's past versions and restore a selected version after confirming the operation.
- **Rationale:** The delivered session history must be visible and recoverable through the application.

- **Priority:** P0
- **Capability ID:** CAP-SUP-01
- **Capability:** Writers can create a Diagnostics Export that contains application and schema versions, errors, retries, and failures without Note or Asset content.
- **Rationale:** User-controlled diagnostics provide supportability without automatic telemetry.

## Portability and paths

- **Priority:** P0
- **Capability ID:** CAP-PORT-02
- **Capability:** Writers can Export one stable Workspace revision as either a plain bundle copy or a single Bundle Archive.
- **Rationale:** Both supported forms provide a complete exit path without application-specific tooling.

- **Priority:** P0
- **Capability ID:** CAP-PORT-06
- **Capability:** Before Export, burlmd flushes every open Note through its durability lifecycle without retiring the session and stops when an external-file decision remains unresolved.
- **Rationale:** Export must not capture stale drafts or an undecided authority state.

- **Priority:** P0
- **Capability ID:** CAP-PORT-07
- **Capability:** A plain-copy Export refuses a nonempty destination, and a Bundle Archive requires confirmation before replacement.
- **Rationale:** Export must not silently combine with or overwrite unrelated content.

- **Priority:** P0
- **Capability ID:** CAP-PORT-08
- **Capability:** burlmd exposes an Export destination only after the complete output is verified. A failed Export doesn't appear successful or leave partial output at the selected destination.
- **Rationale:** Atomic visibility keeps the portability guarantee trustworthy.

- **Priority:** P0
- **Capability ID:** CAP-PORT-03
- **Capability:** When a guest tool changes Workspace files, burlmd validates the change against the published Workspace contract and preserves the last known-good state until invalid input is repaired or excluded.
- **Rationale:** Interoperability requires clear authority and recovery rules, not silent trust in every filesystem write.

- **Priority:** P0
- **Capability ID:** CAP-PORT-05
- **Capability:** Every Workspace path that burlmd creates remains unambiguous when the Workspace moves among supported Linux and macOS hosts and Windows-compatible storage.
- **Rationale:** A Workspace must not change identity or develop collisions because another filesystem applies different case, normalization, or reserved-name rules.

## Assets and object storage

- **Priority:** P0
- **Capability ID:** CAP-ASSET-01
- **Capability:** Each Asset uses a portable Workspace reference and remains available offline while the Asset is active.
- **Rationale:** A Note must not depend on the source location from which the Writer imported an image.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-02
- **Capability:** burlmd deduplicates byte-identical Objects and preserves distinct bytes when two Asset references conflict.
- **Rationale:** Content identity reduces unnecessary storage without turning a collision into silent data loss.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-03
- **Capability:** Before a Workspace with Assets connects to a Remote, the Writer connects a user-controlled Object Store and burlmd verifies that every protected Object is available there.
- **Rationale:** A published Note history must not reference binary content that another device can't retrieve.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-04
- **Capability:** After a Writer joins a connected Workspace on another device, active Assets become available progressively without blocking Note editing.
- **Rationale:** Text remains usable during large transfers, and active context receives priority.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-05
- **Capability:** When an Object is missing or corrupt, burlmd preserves verified copies, pauses affected synchronization, and offers **Retry**, **Repair from local copy**, **Choose replacement**, or **Remove reference** when each action is valid.
- **Rationale:** Missing bytes must not become silent reference deletion or corrupt content.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-06
- **Capability:** Writers can rotate Object Store credentials or replace the Object Store without losing any Object reachable from a Protected State.
- **Rationale:** User-controlled storage must remain replaceable without weakening history.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-07
- **Capability:** burlmd can delete an authoritative Object only after the Object remains unreachable from every Protected State for 30 days and burlmd has enumerated complete published Remote history.
- **Rationale:** Cleanup must not break restorable history or another published branch.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-08
- **Capability:** In a connected Workspace, burlmd can evict inactive local Object bytes after 30 days only when the Object Store contains a verified copy and no current Note requires the bytes offline.
- **Rationale:** Local cache control must remain distinct from deleting an authoritative Object.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-09
- **Capability:** Before adopting a Workspace with ordinary Asset files, burlmd inventories references and reports missing, ambiguous, oversized, or nonconforming Assets without changing the Workspace.
- **Rationale:** Migration must not begin from incomplete or ambiguous input.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-10
- **Capability:** After preflight succeeds, burlmd migrates referenced Assets to portable identities as one recoverable lifecycle outcome and keeps unreferenced files available for review.
- **Rationale:** Adoption must preserve both referenced content and guest files that burlmd doesn't own.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-11
- **Capability:** Before an asset-bearing Workspace becomes fully local, burlmd verifies that every Object reachable from a Protected State is available locally, then detaches both the Object Store and Remote.
- **Rationale:** Returning to local operation must not strand history in storage that the Workspace no longer uses.

- **Priority:** P0
- **Capability ID:** CAP-ASSET-12
- **Capability:** burlmd blocks Object Store detachment when protected hydration is incomplete and doesn't keep an asset-bearing Workspace Remote-connected without a verified Object Store.
- **Rationale:** Remote Note history and synchronized Object availability form one user-visible integrity guarantee.

## Private Remote synchronization

- **Priority:** P0
- **Capability ID:** CAP-SYNC-01
- **Capability:** Writers can connect a local Workspace to an eligible private Remote by provisioning one or selecting an empty one, then publish local history after all prerequisites pass.
- **Rationale:** Connection adds off-device durability without becoming a prerequisite for local use.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-02
- **Capability:** After connection, burlmd synchronizes changes during application use and makes a bounded final attempt during orderly shutdown.
- **Rationale:** Synchronization must continue without a resident background service or a manual command.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-03
- **Capability:** Writers can distinguish clean, active, offline, behind, failed, authentication-required, paused-decision, and pending-Suggestion synchronization states.
- **Rationale:** Different recovery actions require distinct and visible states.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-04
- **Capability:** When concurrent edits affect the same Note content, burlmd preserves base, local, and incoming content and represents each smallest safe difference as an independently resolvable Suggestion.
- **Rationale:** Content reconciliation must not expose raw conflict markers, duplicate Notes, or force an all-or-nothing choice.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-05
- **Capability:** When authorization expires or is revoked, burlmd pauses Remote synchronization, keeps local capabilities available, and guides the Writer through reauthorization.
- **Rationale:** Credential state is a synchronization concern, not a writing gate.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-06
- **Capability:** Writers can sign out without removing the Remote, detach through an explicit operation that preserves local history and protected Assets, and reconnect later without loss.
- **Rationale:** Authentication and Workspace attachment have different consequences and must remain separate.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-07
- **Capability:** On another device, Writers can authorize the same Provider, select the connected private Remote, and create a complete local Workspace from it.
- **Rationale:** Multi-device access is the primary value of Remote synchronization.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-08
- **Capability:** During connection, Writers can consolidate Notes from another local Workspace by migrating nonconflicting Notes and deciding each identity collision without changing the source Workspace.
- **Rationale:** Consolidation supports established local archives without merging unrelated histories.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-10
- **Capability:** When synchronization produces a lifecycle or path-identity conflict, burlmd pauses Workspace synchronization and requires a Lifecycle Decision while keeping local editing and history available.
- **Rationale:** Structural outcomes can't be represented safely as inline content Suggestions.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-11
- **Capability:** When synchronization produces conflicting Asset bytes, references, or availability, burlmd pauses Workspace synchronization and requires an Asset Decision while keeping local editing and history available.
- **Rationale:** Binary outcomes require explicit choices and verified Object state.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-12
- **Capability:** If a connected Remote becomes public or loses required access, burlmd pauses synchronization and preserves the complete local Workspace until the Writer restores a valid private connection or detaches it.
- **Rationale:** This phase promises private repositories and must fail closed when that privacy boundary changes.

- **Priority:** P0
- **Capability ID:** CAP-SYNC-13
- **Capability:** When one side deletes a Note and the other edits it, burlmd restores the edited Note as a Suggestion and requires confirmation before deletion wins.
- **Rationale:** Delete-versus-edit contains recoverable content and must not collapse into a structural deletion choice.

## Releases and upgrades

- **Priority:** P0
- **Capability ID:** CAP-REL-01
- **Capability:** Writers can install an Apple Silicon macOS or x86-64 Linux `0.x` release from published artifacts without building burlmd from source.
- **Rationale:** A feature-complete desktop application isn't releasable if installation depends on the development environment.

- **Priority:** P0
- **Capability ID:** CAP-REL-02
- **Capability:** Every supported release system passes the same release-blocking matrix for local editing, persistence, Export, synchronization, secure storage, recovery, and update notification.
- **Rationale:** An artifact isn't supported merely because it launches.

- **Priority:** P0
- **Capability ID:** CAP-REL-03
- **Capability:** When a compatible higher `0.x` release is available, burlmd notifies the Writer and opens the release information without replacing installed binaries.
- **Rationale:** Update awareness is useful before the project owns a safe self-update mechanism.

- **Priority:** P0
- **Capability ID:** CAP-REL-04
- **Capability:** After an application-state schema change, burlmd backs up affected state, migrates it atomically, and restores the earlier state when migration fails.
- **Rationale:** Prerelease iteration must not make a Workspace unusable after an upgrade.

- **Priority:** P0
- **Capability ID:** CAP-REL-05
- **Capability:** Writers can independently verify the integrity and provenance of every published release artifact.
- **Rationale:** Installability without verifiable origin or bytes leaves the release trust boundary incomplete.

- **Priority:** P0
- **Capability ID:** CAP-REL-06
- **Capability:** Each release supports the two most recent macOS major versions available on its release date and the x86-64 Linux runtime baseline accepted from OD-08 evidence.
- **Rationale:** A release needs an explicit, evidence-backed compatibility window before its artifacts can be called supported.
