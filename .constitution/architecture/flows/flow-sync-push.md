# Execution Flow: Background Sync

**Maps to PRD Capability:** CAP-SYNC-02 (once connected, the system automatically synchronizes changes with the Remote in the background without user action). Epic: Synchronization & Conflict Resolution, **P1**.

> **Status:** the body below predates PRD v1.1.0 and ADR-005/ADR-006. It is not updated here because the whole of synchronization is deferred to Epic G, which will revise it against the current contract; the header is corrected because it cited a P0 priority the PRD no longer assigns and an epic name that no longer exists.

```mermaid
sequenceDiagram
    participant Core as Core Engine
    participant Local as Local Repository
    participant Sync as Sync Manager
    participant Remote as Remote Repository

    Core->>Local: Commit final Markdown to disk
    Local-->>Core: Success
    
    Sync->>Local: Observe new un-pushed local commit
    Sync->>Sync: Wait for debounce period (e.g., 5 seconds of inactivity)
    
    Sync->>Remote: Push local commit to remote branch
    alt Push Success
        Remote-->>Sync: OK
        Sync->>Local: Mark commit as pushed
    else Push Failure (Network Error)
        Remote--xSync: Timeout / Disconnect
        Sync->>Sync: Schedule retry with exponential backoff
    else Push Failure (Conflict)
        Remote-->>Sync: Rejected (Non-fast-forward)
        Sync->>Remote: Fetch latest upstream
        Remote-->>Sync: Upstream commits
        Sync->>Local: Merge upstream into local (writes raw conflict markers if overlapping)
        Sync->>Sync: Trigger re-index of notes and notes_fts tables
        Sync->>Core: Notify of potential conflict state
    end
```
