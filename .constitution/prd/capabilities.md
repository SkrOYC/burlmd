# Functional Capabilities

Priorities express the critical path to a Workspace the primary actor can rely on daily. `P0` is required before the application is usable for real note-taking, `P1` is the following phase, `P2` is optional.

## Epic: Core Editing & Formatting

- **Priority:** P0
- **Capability ID:** CAP-EDIT-01
- **Capability:** When the user places the cursor in a Block, that Block displays its raw Markdown source for direct editing, while every other Block in the Note remains rendered as formatted output.
- **Rationale:** The primary actor writes Markdown deliberately and needs to see exactly what is stored, without giving up reading the Note as a finished document.

- **Priority:** P0
- **Capability ID:** CAP-EDIT-02
- **Capability:** Users can author and render the full set of structural Block types: headings, bulleted and numbered lists, blockquotes, code blocks, and thematic breaks.
- **Rationale:** Foundational elements for knowledge organization; a Note limited to plain paragraphs cannot hold structured thought.

- **Priority:** P0
- **Capability ID:** CAP-EDIT-03
- **Capability:** Users can create, split, merge, and delete Blocks through ordinary typing — beginning a new Block from the end of an existing one, and merging back into the previous Block when deleting from the start.
- **Rationale:** Without this, a Note's structure is fixed at creation and the editor cannot be used to compose anything.

- **Priority:** P0
- **Capability ID:** CAP-EDIT-04
- **Capability:** Users can select text spanning multiple Blocks and copy it, receiving Markdown that reproduces the selected content faithfully.
- **Rationale:** Selection that stops at Block boundaries breaks the most common editing actions in any document of length.

- **Priority:** P0
- **Capability ID:** CAP-EDIT-05
- **Capability:** Users can apply inline emphasis (bold, italic, strikethrough, inline code) to a selection in the focused Block via standard keyboard shortcuts.
- **Rationale:** Even a writer fluent in Markdown expects the shortcut to wrap a selection rather than typing delimiters by hand.

- **Priority:** P1
- **Capability ID:** CAP-EDIT-06
- **Capability:** Users can embed images stored inside the Workspace and see them previewed inline.
- **Rationale:** Visual capture (diagrams, screenshots) is a routine part of note-taking, but a Note without it is still fully useful.

- **Priority:** P2
- **Capability ID:** CAP-EDIT-07
- **Capability:** Users can apply inline formatting through a floating toolbar surfaced on selection.
- **Rationale:** Redundant with keyboard shortcuts for this actor; valuable only for occasional or pointer-driven use.

- **Priority:** P1
- **Capability ID:** CAP-EDIT-08
- **Capability:** When the user invokes undo, the application reverses their most recent content change in the open Note — including changes that spanned multiple Blocks or destroyed a range — without consulting version history, and redo reapplies it.
- **Rationale:** Every editor this actor writes in reverses structural operations; an undo that stops at Block boundaries makes a cross-Block deletion unrecoverable by any means short of archaeology, and lost work is the failure the primary actor forgives least. Undo covers the user's own editing actions only: reverting what another device contributed is conflict resolution, not undo.

## Epic: Note & Directory Lifecycle

- **Priority:** P0
- **Capability ID:** CAP-LIFE-01
- **Capability:** Users can create a new Note inside a chosen Directory.
- **Rationale:** The application cannot be used at all without this; it was absent from the previous capability set entirely.

- **Priority:** P0
- **Capability ID:** CAP-LIFE-02
- **Capability:** Users can rename a Note, and every existing Link pointing at it is updated automatically to continue resolving.
- **Rationale:** Renaming is routine during writing, and a rename that silently breaks the knowledge graph makes Links untrustworthy.

- **Priority:** P0
- **Capability ID:** CAP-LIFE-03
- **Capability:** Users can move a Note into a different Directory, with inbound Links updated automatically.
- **Rationale:** Organization emerges after writing, so Notes must be reorganizable without cost.

- **Priority:** P0
- **Capability ID:** CAP-LIFE-04
- **Capability:** Users can delete a Note, with the deletion captured in local version history so it remains recoverable.
- **Rationale:** Deletion must be safe enough to use freely.

- **Priority:** P0
- **Capability ID:** CAP-LIFE-05
- **Capability:** Users can create Directories, nested to arbitrary depth.
- **Rationale:** Primary hierarchical organization paradigm.

- **Priority:** P1
- **Capability ID:** CAP-LIFE-06
- **Capability:** Users can rename and delete Directories, with contained Notes and inbound Links following correctly.
- **Rationale:** Completes hierarchy management, but is reachable manually in the interim by moving Notes individually.

## Epic: Knowledge Graph & Navigation

- **Priority:** P0
- **Capability ID:** CAP-GRAPH-01
- **Capability:** Users can browse the Workspace as a nested Directory tree and open any Note from it.
- **Rationale:** Primary navigation surface; without it, no Note is reachable after it is written.

- **Priority:** P0
- **Capability ID:** CAP-GRAPH-02
- **Capability:** While editing, users can insert a Link to another Note through an in-editor completion that searches existing Notes by title, without typing the target location by hand.
- **Rationale:** Enables lateral exploration of ideas; hand-authoring link targets is error-prone and would discourage linking entirely.

- **Priority:** P0
- **Capability ID:** CAP-GRAPH-03
- **Capability:** Users can follow a Link from a rendered Block to open the target Note.
- **Rationale:** A knowledge graph that cannot be traversed is only decoration.

- **Priority:** P1
- **Capability ID:** CAP-GRAPH-04
- **Capability:** Users can create a Link to a Note that does not yet exist, and create that Note by following the Link.
- **Rationale:** Supports writing forward into concepts not yet captured, a core knowledge-graph workflow.

- **Priority:** P1
- **Capability ID:** CAP-GRAPH-05
- **Capability:** Users can see which other Notes link to the Note they are currently reading.
- **Rationale:** Inbound connections are how a graph becomes navigable in both directions.

- **Priority:** P2
- **Capability ID:** CAP-GRAPH-06
- **Capability:** Users can visualize the relationships between Notes through a graphical map.
- **Rationale:** Helps users understand the macro-structure of their knowledge graph; exploratory rather than load-bearing.

## Epic: Workspace & Local Durability

- **Priority:** P0
- **Capability ID:** CAP-WS-01
- **Capability:** On first launch, users can begin writing in a local Workspace immediately, with no account, no provider authorization, and no network connection.
- **Rationale:** Requiring a network handshake before the first word contradicts the Local-First Mandate and blocks all use of the application when no provider is configured.

- **Priority:** P0
- **Capability ID:** CAP-WS-02
- **Capability:** Every editing session on a Note is captured in the Workspace's local version history when the Note is closed, and any earlier version remains recoverable.
- **Rationale:** Version history is the durability guarantee that makes a local-only Workspace trustworthy before any Remote exists.

- **Priority:** P0
- **Capability ID:** CAP-WS-03
- **Capability:** In-progress edits that have not yet been written to the Note survive abrupt termination of the application, and are restored when it next opens.
- **Rationale:** Unsaved work lost to a crash is the failure the primary actor forgives least.

- **Priority:** P0
- **Capability ID:** CAP-WS-04
- **Capability:** The local search index — which aggregates the content of every Note into one file — is encrypted by the application, with its key held in operating-system secure storage. Notes themselves are stored as plaintext so that standard tooling can operate on them, and their at-rest protection is whatever the operating system provides rather than anything the application guarantees.
- **Rationale:** Limits what a compromised device yields without making the Notes unreadable to the tooling that must merge them. Stated as two separate guarantees deliberately: only the first is something this application can actually deliver.

- **Priority:** P1
- **Capability ID:** CAP-WS-05
- **Capability:** Users can open an existing Workspace directory that the application did not create, including one populated by another tool.
- **Rationale:** Adoption path for users with existing Markdown collections; not required to start writing.

- **Priority:** P1
- **Capability ID:** CAP-WS-06
- **Capability:** When the user invokes an explicit refresh action, the application re-derives its internal view of the Workspace from the files currently on disk, so that changes made by external tools while the application was open become visible.
- **Rationale:** CAP-PORT-03 recognizes external changes made while the application was closed. An Agent actor can also write while it runs; until live monitoring exists, an honest user-invoked rescan keeps that state reachable rather than invisible.

## Epic: History & Recovery

- **Priority:** P1
- **Capability ID:** CAP-HIST-01
- **Capability:** For the Note they are reading, users can see the list of its past versions and restore any earlier version as the current content.
- **Rationale:** CAP-WS-02 guarantees every session lands in version history, but a guarantee nobody can see or act on protects nothing. Restore is destructive to unwritten work, so it confirms first.

## Epic: Supportability

- **Priority:** P1
- **Capability ID:** CAP-SUP-01
- **Capability:** When something goes wrong, users can produce a diagnostics bundle describing the application's recent behavior — errors, retries, and failures, with Note content excluded — and hand it to someone troubleshooting.
- **Rationale:** Zero Content Telemetry forbids phoning home, so when the application misbehaves there is otherwise nothing a user can attach to a bug report. The exclusion of content is what makes the bundle safe to share.

## Epic: Synchronization & Conflict Resolution

- **Priority:** P1
- **Capability ID:** CAP-SYNC-01
- **Capability:** Users can connect an existing local Workspace to a Remote by authorizing a provider, either provisioning a new private repository or selecting one they already own, after which existing local history is published to it.
- **Rationale:** Multi-device access and off-machine durability, offered as a deliberate step rather than a precondition to use.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-02
- **Capability:** Once connected, the system automatically synchronizes changes with the Remote in the background without user action.
- **Rationale:** Sync the user has to remember to perform is sync that silently stops happening.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-03
- **Capability:** Users can see an ambient indication of synchronization state, including when the Workspace is offline, behind, or failing to sync.
- **Rationale:** Silent sync failure erodes trust in the archive more than visible failure does.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-04
- **Capability:** When the same Note is edited concurrently on two devices, the system surfaces the divergence inline as a Suggestion the user can accept or reject, never as raw conflict markers and never by duplicating the Note.
- **Rationale:** Converts the single most intimidating failure mode of version-controlled storage into an ordinary editing decision.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-05
- **Capability:** When provider authorization expires or is revoked, the Workspace remains fully readable and editable locally, and the user is prompted to re-authorize rather than blocked.
- **Rationale:** A lapsed credential is a sync problem; it must never become a writing problem.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-06
- **Capability:** Users can detach the Remote from a connected Workspace, returning it to fully functional local-only operation with all history intact, and reconnect later without loss.
- **Rationale:** Connection must remain reversible. A user who attached a work account to a personal archive needs an exit that does not cost them their Notes, and sign-out alone leaves the attachment in place.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-07
- **Capability:** On a second device, users can join an existing connected Workspace by authorizing the same provider and selecting the repository the first device publishes to; the application clones it and the clone becomes a full local Workspace.
- **Rationale:** Multi-device access is the point of connecting at all. Authorize-then-clone completes the path ADR decisions reserve for it and matches how version-controlled storage is normally adopted on a second machine.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-08
- **Capability:** While connecting, users can consolidate Notes from a previous local Workspace into the freshly connected one: non-conflicting Notes migrate automatically, and each collision — the same identity arising on both sides — resolves explicitly as keep mine, keep theirs, or keep both under a new name. The source Workspace is never modified.
- **Rationale:** Real users arrive with existing local archives on both ends of a connect. Full history merging between divergent archives stays out of scope (`out-of-scope/history-merge-on-connect.md`); guided consolidation gives those users a supported path that never silently discards either side.

- **Priority:** P1
- **Capability ID:** CAP-SYNC-09
- **Capability:** Users can connect a Workspace through a second hosting provider, GitLab, with the same authorize, provision-or-select, publish, detach, and consolidate behaviors the first provider supports.
- **Rationale:** Provider choice is stated in operator intent, and a seam built for exactly one provider tends to ossify around it. Sequenced behind the first provider, which proves the surface before a second consumer arrives.

## Epic: Discovery & Retrieval

- **Priority:** P0
- **Capability ID:** CAP-FIND-01
- **Capability:** Users can search the full text of every Note in the Workspace and open a result directly.
- **Rationale:** Essential for retrieving knowledge as volume scales beyond what the Directory tree makes visible.

- **Priority:** P1
- **Capability ID:** CAP-FIND-02
- **Capability:** Users can jump directly to a Note by typing part of its title, without leaving the keyboard.
- **Rationale:** The dominant navigation path once a Workspace is large; full-text search covers the need until then.

- **Priority:** P1
- **Capability ID:** CAP-FIND-03
- **Capability:** Within the Note they are editing, users can find every occurrence of a search string — including occurrences inside rendered inline structure — navigate between them, and replace found occurrences individually or all at once.
- **Rationale:** Workspace search stops at the Note boundary, leaving long Notes to scroll-and-squint. Replacement composes with the same machinery that powers cross-Block selection, and replace-all must behave as one operation rather than many.

## Epic: Portability & Interoperability

- **Priority:** P0
- **Capability ID:** CAP-PORT-01
- **Capability:** Every Note the application *creates* conforms to the Open Knowledge Format the moment it is created, so that any conforming tool or agent can read the Notes and traverse the Links with no export step and no application-specific parser.
- **Rationale:** Makes data sovereignty concrete rather than aspirational, and serves the Automated Consumer actor directly. Conformance is continuous, not a mode. Scoped to what the application *creates* rather than to the whole Workspace at all times, because the format defines conformance over an entire bundle: one file an external tool dropped in without frontmatter makes the bundle non-conformant, and CAP-WS-05 and CAP-PORT-03 both make that a supported and possibly permanent state. Promising more would be a promise the application can only keep by rewriting files the user never asked it to touch. *Creates* rather than *writes* for a second reason inside that same scoping: editing one of those foreign files **writes** it and leaves it non-conformant, so the wider verb would be false on a path the design supports rather than merely optimistic.

- **Priority:** P1
- **Capability ID:** CAP-PORT-02
- **Capability:** Users can Export the Workspace to a location of their choosing, producing Notes readable with no application-specific tooling.
- **Rationale:** Guarantees an exit path. Lower priority than it would otherwise be precisely because CAP-PORT-01 keeps the live Workspace already in that state.

- **Priority:** P0
- **Capability ID:** CAP-PORT-02
- **Capability:** Users can Export the Workspace to a location of their choosing, producing Notes readable with no application-specific tooling — either as a plain copy of the bundle or as a single `.okf` Bundle Archive.
- **Rationale:** Guarantees an exit path. Lower priority than it would otherwise be precisely because CAP-PORT-01 keeps the live Workspace already in that state. The archive form is distribution of the bundle in the packaged form the Open Knowledge Format itself names, not a proprietary container.

- **Priority:** P1
- **Capability ID:** CAP-PORT-03
- **Capability:** Changes made to Workspace files by external tools while the application is closed are recognized and reflected when it next opens.
- **Rationale:** A format other tools can write is only genuinely open if the application tolerates them having written to it.

- **Priority:** P1
- **Capability ID:** CAP-PORT-04
- **Capability:** Users can Publish the Workspace as a self-contained HTML rendition — a single file presenting every Note with Links navigable — readable offline in any browser with no network access beyond loading the file itself.
- **Rationale:** Serves readers who will never install anything, following the shape the format's own reference tooling demonstrates. Deliberately sequenced after the application has a design system of its own: a rendition worth publishing should look like the product, and it inherits Zero Content Telemetry absolutely — no external scripts, no load-time calls.

### Epic: Preferences & Appearance

- **Priority:** P1
- **Capability ID:** CAP-PREF-01
- **Capability:** Users can adjust how the application looks and behaves through a preferences surface — appearance theme, text size, and comparable settings — with choices persisted across sessions.
- **Rationale:** Writers live in this application for hours; light and dark environments alone make fixed styling a daily irritation. This capability is owned by an interactive design epic: the settings surface defines burlmd's design language, and human design judgment drives it rather than widget-by-widget assembly. It precedes the surfaces that consume its tokens, notably CAP-PORT-04's rendition.
