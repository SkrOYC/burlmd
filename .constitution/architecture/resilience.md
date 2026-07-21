# Resilience & Cross-Cutting Concerns

## Sync Failure Handling
- **Network Disconnection:** The Sync Manager utilizes exponential backoff when pushing or pulling from the Remote Repository fails due to network conditions. The UI is never blocked by these failures; an ambient status indicator simply reflects "Offline".
- **Authentication Expiration:** If the OAuth token expires, the Sync Manager pauses all operations and signals the Core Engine, which instructs the Presentation Container to prompt for re-authentication. Local editing remains fully operational.

## Conflict Resilience
- **Non-Destructive Merges:** Standard remote sync conflicts never result in data loss or application crashes. The Core Engine parses raw conflict markers, preserves both variants, and structures them into a safe AST "Suggestion" node. The local index remains valid and searchable even while conflicts are pending resolution by the user.

## Data Integrity
- **Stateless UI Crash Recovery:** Because the Presentation Container is stateless and streams updates to the Core Engine's active draft cache, a UI crash does not result in data loss. Upon restart, the UI requests the active draft from the Core Engine.
- **SQLite Draft Persistence:** To mitigate process-wide crashes (e.g., OOM kills), the Core Engine synchronously persists all ongoing drafts to a local `drafts` SQLite table on every keystroke. Upon application reboot, the draft is restored from the database.
- **Atomic Commits:** Saves to the Local Repository are atomic. If the application terminates abruptly during a save, the previous state is preserved.
