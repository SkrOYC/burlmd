---
job: JOB-03
capabilities: [CAP-013, CAP-014, CAP-015, CAP-033, CAP-035]
boundaries: [BND-01, BND-02, BND-03, BND-04, BND-07]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Link graph flow

**Maps to delivered:** CAP-GRAPH-02, CAP-GRAPH-03, CAP-GRAPH-04.

**Maps to active:** CAP-FIND-02, CAP-GRAPH-05.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Model as Canonical Note Model
    participant Workspace as Workspace Model
    participant Index as Derived Index

    UI->>Core: Search title or request Link completion
    Core->>Index: Query Note titles and backlinks
    Index-->>Core: Candidates or inbound Links
    Core-->>UI: Candidates or inbound Links
    alt Insert Link
        UI->>Core: Accept completion target
        Core->>Model: Apply source-preserving Link edit
        Model-->>Core: Updated Note state
        Core-->>UI: Authoritative Note state
    else Follow Link
        UI->>Core: Follow rendered Link
        Core->>Model: Interpret Link target
        Model-->>Core: Target identity
        Core->>Workspace: Resolve current Workspace identity
        alt Target exists
            Workspace-->>Core: Existing Note session
            Core-->>UI: Open target Note
        else Target is a ghost
            Core-->>UI: Offer create-on-follow
            UI->>Core: Confirm creation
            Core->>Workspace: Validate identity and create conforming Note lifecycle
            Workspace-->>Core: Created Note session
            Core-->>UI: Open created Note
        end
    end
```

## Failure path

- No title match or backlink is an explicit empty state.
- A target collision that appears before create-on-follow is refused without changing the Link.
- An unavailable index degrades graph search but doesn't block opening a known Note path.
