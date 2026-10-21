---
job: JOB-05
capabilities: [CAP-046, CAP-047, CAP-048, CAP-049]
boundaries: [BND-01, BND-02, BND-04, BND-05, BND-06, BND-13]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Workspace Export flow

**Maps to:** CAP-PORT-02, CAP-PORT-06, CAP-PORT-07, CAP-PORT-08.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Workspace as Workspace Model
    participant Persist as Workspace Persistence
    participant LocalAssets as Local Asset Store
    participant Host as Host Platform

    UI->>Core: Export form and destination
    Core->>Workspace: Flush every open Note, require resolved guest decisions
    Core->>Persist: Pin one stable Workspace revision
    Core->>Workspace: Derive referenced Object closure for pinned revision
    Core->>LocalAssets: Verify every referenced Object
    alt Object closure is complete and verified
        Core->>Host: Inspect selected Export destination
        alt Destination is empty
            Core->>Host: Prepare and verify complete plain-folder copy at selected destination
            Core->>Host: Publish complete output atomically
            Core-->>UI: Export success
        else Destination is nonempty
            Core-->>UI: Refuse nonempty destination, terminal outcome
        end
    else Object is unavailable or corrupt
        Core-->>UI: Stop Export and report required local Object recovery, terminal outcome
    end
```

Bundle Archive Export is deferred and doesn't add an archive or replacement branch to this flow. A connected Workspace can recover an unavailable Object through the Object lifecycle before the Writer retries Export, but a complete local Object closure never depends on Remote synchronization.

## Failure path

- A flush failure or unresolved guest decision stops Export before revision capture.
- A read, write, or verification failure removes temporary output and doesn't expose partial success.
- A missing or corrupt local Object stops publication and reports Object recovery without making connected storage a prerequisite for complete local Export.
- Foreign nonconforming content remains byte-preserved in Export and is reported rather than silently repaired.
