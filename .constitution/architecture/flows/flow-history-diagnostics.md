---
job: JOB-05
capabilities: [CAP-044, CAP-045]
boundaries: [BND-01, BND-02, BND-05, BND-08]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# History, recovery, and diagnostics flow

**Maps to:** CAP-HIST-01, CAP-SUP-01.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Persist as Workspace Persistence
    participant State as Application State
    participant Destination as Writer-selected destination

    alt View or restore Note history
        UI->>Core: List Note Versions
        Core->>Persist: Read Note history
        Persist-->>Core: Version summaries
        Core-->>UI: Version summaries
        UI->>Core: Confirm restore
        Core->>Persist: Record restored content as the current recoverable state
    else Create Diagnostics Export
        UI->>Core: Create diagnostics
        Core->>State: Read redacted structured events and schema metadata
        Core->>Destination: Write Writer-controlled Diagnostics Export
    end
```

## Failure path

- Restore never discards unwritten work without confirmation and a durability transition.
- Missing historical Objects route through Object recovery before restored content becomes authoritative.
- Diagnostics generation fails rather than including Note bytes, Asset bytes, credentials, or signed locations.
