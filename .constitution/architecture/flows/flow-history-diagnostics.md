---
job: JOB-05
capabilities: [CAP-044, CAP-045, CAP-106]
boundaries: [BND-01, BND-02, BND-08, BND-13]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Local diagnostics flow

The active path records bounded content-free diagnostics and creates a Diagnostics Export only when the Writer requests one. Local Version capture continues through Workspace Persistence, but in-app Version listing and restore under CAP-044 are deferred.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant State as Application State
    participant Host as Host Platform

    UI->>Core: Request Diagnostics Export and choose destination
    Core->>State: Read bounded redacted events and application and schema versions
    State-->>Core: Content-free diagnostic records or recording failure
    alt Records are available and destination write succeeds
        Core->>Host: Prepare and verify Diagnostics Export at selected destination
        Core-->>UI: Report export success
    else Recording or export fails
        Core-->>UI: Report diagnostic failure separately
    end
```

## Failure path

- Diagnostics generation fails rather than including Note bytes, Asset bytes, credentials, signed locations, or content-derived metadata.
- Recording failure doesn't fail or roll back the Writer's original product operation and doesn't change Workspace data.
- Export failure doesn't claim success or expose a partial Diagnostics Export at the selected destination.
- No diagnostic record or Diagnostics Export leaves the device automatically.
