# Non-Functional Constraints

## Performance
- **Search Latency:** Full-text search and title filtering must return results in under 100 milliseconds.
- **UI Responsiveness:** Writing and editing interactions must execute in under 16 milliseconds (60fps), including the transition of a Block into and out of its raw editing state.
- **Workspace Open Latency:** Opening a Workspace must not block interaction for more than 1 second, regardless of Note count. Index construction beyond that point must proceed incrementally in the background while the Workspace is already usable.

## Reliability
- **Local-First Mandate:** The application must be 100% functional when completely disconnected from the internet, and must never require an account, credential, or provider authorization in order to create, read, edit, search, or organize Notes. Reads, writes, searches, and Link traversals must all resolve locally.
- **Non-Blocking Sync:** Background synchronization must never block the main UI thread or interrupt the user's editing flow.
- **Durability of In-Progress Work:** Edits not yet written to a Note must survive abrupt process termination, including termination the application receives no opportunity to handle.

## Correctness & Fidelity
- **Edit Fidelity:** Writing a Note to disk must not alter any region of that Note the user did not edit. A session that modifies one Block must produce a change confined to that Block's source, leaving all other bytes — including whitespace, delimiter style, and any metadata keys the application does not itself manage — byte-identical.
- **Format Conformance:** Every Note the application writes must satisfy the Open Knowledge Format's conformance rules at the moment it is written, not only at Export time.
- **Non-Destructive Reconciliation:** Reconciling concurrent edits must never discard either side's content or duplicate a Note. Both variants must remain recoverable until the user resolves the Suggestion.

## Security & Sovereignty
- **Decentralized Storage:** Note content is stored exclusively on the user's own device and, when connected, in the user's designated Remote. No component operated by this project may act as a storage broker, relay, or intermediary for Note content.
- **At-Rest Protection (Local):** The application relies on operating-system full-disk encryption for Notes on disk, so that standard version-control tooling can still operate on them directly. The local search index, which aggregates the content of every Note, must be encrypted by the application independently of the operating system, and its key must reside in operating-system secure storage rather than in application memory or configuration.
- **Credential Isolation:** Provider credentials must never be persisted outside operating-system secure storage, and must never be written to logs, diagnostics, or version history.
- **Non-Proprietary Storage:** Every Note must remain a plain-text file in a published, openly specified format, fully readable and editable with any text editor and with no tooling produced by this project.

## Privacy
- **Zero Content Telemetry:** The application must not collect, transmit, or analyze the contents of the user's Notes for analytics, telemetry, or diagnostic purposes.
