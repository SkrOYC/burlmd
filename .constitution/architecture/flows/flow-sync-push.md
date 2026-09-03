---
job: JOB-04
capabilities: [CAP-064, CAP-065]
boundaries: []
view: state
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Background synchronization flow

**Maps to:** CAP-SYNC-02, CAP-SYNC-03.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Inspecting: Launch, local Version, freshness interval, or final attempt
    Inspecting --> Behind: Incoming history is available
    Inspecting --> Offline: Network unavailable
    Inspecting --> AuthenticationRequired: Authoritative credential rejection
    Inspecting --> PausedDecision: Lifecycle Decision or Asset Decision pending
    Inspecting --> Reconciling: Incoming and local history diverge
    Inspecting --> Failed: Nontransient operation failure
    Inspecting --> UploadingObjects: Unpublished history requires Objects
    UploadingObjects --> Publishing: Every Object verified
    Publishing --> Clean: History publication and incoming application complete
    Behind --> Clean: Incoming history applies without divergence
    Clean --> Idle
    Offline --> Inspecting: Connectivity returns
    AuthenticationRequired --> Inspecting: Reauthorization succeeds
    PausedDecision --> Inspecting: Decision finalizes
    Reconciling --> PendingSuggestions: Valid content state contains Suggestions
    Reconciling --> Publishing: Valid resolved state exists
    PendingSuggestions --> Publishing: Valid history can publish
    Failed --> Inspecting: Writer retries or condition changes
```

## Failure path

- Synchronization state remains explicit and never blocks local editing or history.
- The bounded shutdown attempt reports unfinished work and doesn't delay Platform shutdown indefinitely.
- Startup resumes durable intents, Object obligations, and reconciliation records idempotently.
- Pending Suggestions remain a distinct synchronized state and don't block valid history publication.
