---
job: JOB-08
capabilities: [CAP-031, CAP-052, CAP-053, CAP-056, CAP-057, CAP-059, CAP-060]
boundaries: [BND-01, BND-02, BND-03, BND-04, BND-06, BND-05]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Asset import and adoption flow

**Maps to:** CAP-EDIT-06, CAP-ASSET-01, CAP-ASSET-02, CAP-ASSET-05, CAP-ASSET-06, CAP-ASSET-09, CAP-ASSET-10.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Note as Canonical Note Model
    participant Workspace as Workspace Model
    participant LocalAssets as Local Asset Store
    participant Persist as Workspace Persistence

    alt New image import
        UI->>Core: File, clipboard, or drag-and-drop Asset
        Core->>LocalAssets: Copy bytes, verify identity, and deduplicate Object
        LocalAssets-->>Core: Verified Object identity
        Core->>Workspace: Create portable Asset reference
        Core->>Note: Insert standard image reference through source-preserving edit
        Core->>Persist: Record updated Note and recoverable lifecycle outcome
    else Adopt ordinary Asset files
        UI->>Core: Begin Asset preflight
        Core->>Workspace: Inventory references and validate every candidate
        alt Missing, ambiguous, oversized, or nonconforming input
            Core-->>UI: Report all blockers; mutate nothing
        else Preflight succeeds
            Core->>LocalAssets: Migrate and verify referenced Object bytes
            Core->>Note: Rewrite affected references through source-preserving edits
            Core->>Persist: Record one recoverable adoption outcome
            Core-->>UI: Preserve unreferenced files for review
        end
    end
```

## Failure path

- Imported source locations never remain dependencies after a successful copy.
- Same bytes reuse one Object. Different local bytes for one reference enter Object recovery; competing Asset outcomes produced by Remote reconciliation require an Asset Decision.
- Missing or corrupt local Objects preserve every verified copy and enter the Object recovery flow, which offers Retry, Repair from local copy, Choose replacement, or Remove reference when valid. Local corruption doesn't create an Asset Decision. Synchronization pauses only when Object availability or a separately created reconciliation decision makes publication unsafe.
- A failed adoption leaves the preflighted Workspace unchanged unless one complete local migration outcome already committed.
