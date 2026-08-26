# Edit Note flow

**Maps to delivered:** CAP-EDIT-01, CAP-EDIT-02, CAP-EDIT-03, CAP-EDIT-04, CAP-EDIT-05, CAP-WS-02, CAP-WS-03.

**Maps to active:** CAP-EDIT-08, CAP-FIND-03.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Model as Canonical Note Model
    participant State as Application State
    participant Workspace as Workspace Persistence

    UI->>Core: Open Note
    Core->>Workspace: Read source and current Version
    Core->>State: Read recoverable draft
    Core->>Model: Build source-backed Note state from authoritative working source
    Model-->>Core: Rendered and editable Note state
    Core-->>UI: Authoritative Note state
    UI->>Core: Edit, structural operation, undo, redo, find, or replace
    Core->>Model: Apply one semantic operation
    Model-->>Core: Source-preserving result and inverse operation
    Core->>State: Persist recoverable draft and undo state
    Core-->>UI: Updated Note state
    UI->>Core: Close Note
    Core->>Workspace: Flush source and record one changed session Version
```

## Failure path

- If draft persistence fails, Core reports unwritten state and doesn't claim durability.
- If the source revision changed, Core preserves the draft and routes the candidate disk change through the guest-change flow.
- Replace-all applies as one operation or leaves the Note unchanged.
- A close warning or failure follows the desktop-session flow.
