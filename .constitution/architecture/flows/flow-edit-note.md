---
job: JOB-01
capabilities: [CAP-001, CAP-002, CAP-003, CAP-004, CAP-005, CAP-017, CAP-018, CAP-032, CAP-034, CAP-081, CAP-082, CAP-083, CAP-084, CAP-085, CAP-086, CAP-087, CAP-088, CAP-089, CAP-090]
boundaries: [BND-01, BND-02, BND-03, BND-05, BND-08, BND-22]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Edit Note flow

This flow covers the delivered editing baseline, local history and draft durability, complete Note-level undo and redo, in-Note find and replace, the selected P0 Markdown syntax, and external Markdown image loading.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Model as Canonical Note Model
    participant State as Application State
    participant Workspace as Workspace Persistence
    participant ExternalImage as External Image Origin

    UI->>Core: Open Note
    Core->>Workspace: Read source and current Version
    Core->>State: Read recoverable draft
    Core->>Model: Build source-backed Note state and classify local and external image references
    Model-->>Core: Rendered and editable Note state
    Core-->>UI: Authoritative Note state
    opt Note contains external image references
        Core-)ExternalImage: Schedule background retrieval for each external image reference
        Core-->>UI: Keep local editing, find, and navigation available
    end
    UI->>Core: Find query or next/previous match
    Core->>Model: Locate matches without mutation
    Model-->>Core: Match ranges and active match
    Core-->>UI: Read-only find state
    UI->>Core: Edit selected syntax, toggle task, replace, undo, or redo
    Core->>Model: Apply one source-preserving semantic operation
    Model-->>Core: Source-preserving result and inverse operation
    Core->>State: Persist recoverable draft and undo state
    Core-->>UI: Updated Note state
    opt Scheduled external image result arrives
        ExternalImage--)Core: Untrusted response bytes or explicit failure
        Core-->>UI: Display current validated image content or an unavailable state
    end
    UI->>Core: Close Note
    Core->>Workspace: Flush source and record one changed session Version
```

## Failure path

- If draft persistence fails, Core reports unwritten state and doesn't claim durability.
- If the source revision changed, Core preserves the draft and routes the candidate disk change through the guest-change flow.
- Find queries and match navigation are read-only. They don't create inverse operations, drafts, or undo entries.
- Replace-all and every other delivered content-editing operation apply with one reversible Note-level outcome or leave the Note unchanged.
- A failed, unavailable, or invalid external image response produces an unavailable state for that image. It doesn't block Note opening, local editing, or offline use, and it doesn't rewrite or import the external reference.
- If the Note closes or its external reference changes before a response arrives, Core discards the stale result without reopening or editing the Note.
- External image requests carry only what each reference requires. Other Note content, application credentials, and telemetry don't cross the boundary.
- A close warning or failure follows the desktop-session flow.
