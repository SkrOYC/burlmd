# Note and Directory lifecycle flow

**Maps to delivered:** CAP-LIFE-01, CAP-LIFE-02, CAP-LIFE-03, CAP-LIFE-04, CAP-LIFE-05, CAP-LIFE-06, CAP-PORT-01.

**Maps to active:** CAP-PORT-05.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Workspace as Workspace Model
    participant Persist as Workspace Persistence
    participant Index as Derived Index

    UI->>Core: Create, rename, move, or delete
    Core->>Workspace: Validate canonical path, containment, identity, and affected Links
    Workspace-->>Core: Complete change set or refusal
    alt Change set is valid
        Core->>Persist: Apply one recoverable lifecycle outcome
        Core->>Index: Apply derived projection
        Core-->>UI: Updated tree and open-session identities
    else Invalid or ambiguous path
        Core-->>UI: Refuse before mutation
    end
```

## Failure path

- A path collision, unsupported indirection, or containment escape fails before mutation.
- A mid-operation failure restores the earlier files, Link text, open-session state, and derived projection.
- Delete remains recoverable through local history and isn't an undo operation.
