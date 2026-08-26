# Workspace navigation flow

**Maps to delivered:** CAP-GRAPH-01.

**Maps to active:** CAP-SHELL-03.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Workspace as Workspace Model
    participant State as Application State

    UI->>Core: Request active Workspace tree
    Core->>Workspace: Read authoritative Directories and Notes
    Workspace-->>Core: Nested tree including empty Directories
    Core-->>UI: Authoritative nested tree
    UI->>Core: Update expansion, active Note, and search presentation
    Core->>State: Persist state for this Workspace
    UI->>Core: Open selected Note
    Core-->>UI: Authoritative Note session
```

## Failure path

- A tree-projection failure leaves open Note sessions usable and offers retry.
- A missing selected Note reverts selection and reports the missing path.
- Guest or synchronized lifecycle changes refresh the authoritative tree through their owning flows.
