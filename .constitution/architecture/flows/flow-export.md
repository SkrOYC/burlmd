---
job: JOB-05
capabilities: [CAP-046, CAP-047, CAP-048, CAP-049]
boundaries: [BND-01, BND-02, BND-04, BND-05, BND-06, BND-11]
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
    participant ObjectTransfer as Object Transfer Coordinator
    participant Destination as Export Destination

    UI->>Core: Export form and destination
    Core->>Workspace: Flush every open Note, require resolved guest decisions
    Core->>Persist: Pin one stable Workspace revision
    Core->>Workspace: Derive referenced Object closure for pinned revision
    Core->>LocalAssets: Verify every referenced Object
    opt Missing Object can be hydrated or repaired
        Core->>ObjectTransfer: Recover missing Object closure
        ObjectTransfer->>LocalAssets: Store verified recovered Objects
        Core->>LocalAssets: Verify complete closure again
    end
    alt Object closure is complete and verified
        alt Plain copy
            alt Destination is empty
                Core->>Destination: Prepare and verify complete copy with Objects
                Core->>Destination: Publish complete output atomically
                Core-->>UI: Export success
            else Destination is nonempty
                Core-->>UI: Refuse, terminal outcome
            end
        else Bundle Archive
            alt Replacement is absent or confirmed
                Core->>Destination: Prepare and verify complete archive with Objects
                Core->>Destination: Publish complete output atomically
                Core-->>UI: Export success
            else Replacement isn't confirmed
                Core-->>UI: Refuse, terminal outcome
            end
        end
    else Object is unavailable or corrupt
        Core-->>UI: Stop Export and enter Object recovery, terminal outcome
    end
```

## Failure path

- A flush failure or unresolved guest decision stops Export before revision capture.
- A read, write, or verification failure removes temporary output and doesn't expose partial success.
- A missing or corrupt Object stops publication and enters Object recovery.
- Foreign nonconforming content remains byte-preserved in Export and is reported rather than silently repaired.
