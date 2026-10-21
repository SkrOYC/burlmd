---
job: JOB-07
capabilities: [CAP-037, CAP-038, CAP-039, CAP-040, CAP-041, CAP-042, CAP-050]
boundaries: [BND-13, BND-09, BND-02, BND-04, BND-01]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Live Workspace monitoring flow

**Maps to:** CAP-WS-07, CAP-WS-08, CAP-WS-09, CAP-WS-10, CAP-WS-11, CAP-WS-12, CAP-PORT-03.

```mermaid
sequenceDiagram
    participant Host as Host Platform
    participant Observer as Workspace Observer
    participant Core as Core Coordination
    participant Workspace as Workspace Model
    participant UI as Presentation and Interaction

    Host->>Observer: Filesystem event burst
    Observer->>Core: Debounced candidate change set
    Core->>Workspace: Re-read disk state, validate containment and conformance
    alt Valid create, move, rename, or delete
        Core->>Workspace: Validate canonical identity, provenance, ambiguity, and current revision
        Workspace-->>Core: One recoverable lifecycle outcome or required confirmation
        Core-->>UI: Refresh tree or present ambiguous lifecycle choice
    else Clean open Note and conforming edit
        Core->>Workspace: Record guest change in local history and authoritative tree
        Core-->>UI: Reload Note and affected tree state
    else Dirty open Note
        Core-->>UI: Preserve both, offer Compare, Keep burlmd version, Load external version
        UI->>Core: Reviewed decision
        Core->>Workspace: Revalidate guest revision
        Workspace-->>Core: Apply decision or request renewed review
        Core-->>UI: Authoritative result or renewed review
    else Invalid guest write
        Core->>Workspace: Hold incoming bytes outside authoritative editable state
        Core-->>UI: Flag the problem and retain the last known-good Note
        Host->>Observer: Writer or Agent writes a corrected revision
        Observer->>Core: Debounced corrected candidate
        Core->>Workspace: Re-read and validate the corrected revision
    end
```

## Failure path

- Missed, duplicate, or reordered events converge by comparing candidate events with disk state.
- Invalid input remains preserved and visible as a problem but can't replace or become editable as authoritative state. Guided repair is deferred.
- A revision change between review and apply invalidates the decision.
- Ambiguous lifecycle provenance or identity requires confirmation. A revision change before application renews that confirmation.
- If automatic observation can't prove completeness, it preserves authoritative state and reports the degraded observation state. Rescan rebuilds observation state as an explicit recovery path.
