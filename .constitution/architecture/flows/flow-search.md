# Workspace search flow

**Maps to delivered:** CAP-FIND-01.

**Maps to active:** CAP-FIND-02.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant Index as Derived Index

    UI->>Core: Submit full-text or title query
    Core->>Index: Query active Workspace projection
    Index-->>Core: Results, empty result, or index failure
    Core-->>UI: Present explicit outcome
    UI->>Core: Open selected Note
```

## Failure path

- No matches produce an empty state, not an error.
- An unavailable index exposes rebuild or retry while open Notes remain readable and editable.
- Result truncation must be explicit to Presentation rather than silent.
