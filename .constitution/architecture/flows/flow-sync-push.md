---
job: JOB-04
capabilities: [CAP-064, CAP-065]
boundaries: [BND-01, BND-02, BND-04, BND-05, BND-06, BND-08, BND-10, BND-11, BND-12, BND-13, BND-14, BND-20, BND-21]
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
    Inspecting --> PausedObject: Required Object is missing, corrupt, or unverified
    Inspecting --> Reconciling: Incoming and local history diverge
    Inspecting --> Failed: Nontransient operation failure
    Inspecting --> UploadingObjects: Unpublished history requires Objects
    UploadingObjects --> Publishing: Every Object verified
    UploadingObjects --> PausedObject: Verification or transfer can't complete
    Publishing --> Clean: History publication and incoming application complete
    Behind --> HydratingObjects: Incoming history references local images
    Behind --> Clean: Incoming asset-free history applies without divergence
    HydratingObjects --> Clean: Active images available and remaining obligations durable
    HydratingObjects --> PausedObject: Required Object can't be verified
    Clean --> Idle
    Offline --> Inspecting: Connectivity returns
    AuthenticationRequired --> Inspecting: Reauthorization succeeds
    PausedDecision --> Inspecting: Decision finalizes
    PausedObject --> Inspecting: Object recovery verifies required bytes
    Reconciling --> PendingSuggestions: Valid content state contains Suggestions
    Reconciling --> Publishing: Valid resolved state exists
    PendingSuggestions --> Publishing: Valid history can publish
    Failed --> Inspecting: Writer retries or condition changes
    Idle --> Stopping: Orderly shutdown requests final attempt
    Stopping --> [*]: Attempt completes or unfinished intent is held durably
```

## Failure path

- Synchronization state remains explicit and never blocks local editing or history.
- The bounded shutdown attempt reports unfinished work, preserves its durable intent, and doesn't delay Platform shutdown indefinitely.
- Startup resumes durable intents, Object obligations, and reconciliation records idempotently.
- Pending Suggestions remain a distinct synchronized state and don't block valid history publication.
- A cancellation, timeout, or Object failure never publishes Note history ahead of its protected image bytes. It holds the affected publication while unrelated local work remains available.
