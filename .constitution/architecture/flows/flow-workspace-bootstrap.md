---
job: JOB-02
capabilities: [CAP-016, CAP-019, CAP-020, CAP-036, CAP-043]
boundaries: [BND-01, BND-02, BND-03, BND-04, BND-05, BND-07, BND-08, BND-10, BND-12, BND-13, BND-14]
view: state
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Workspace bootstrap and adoption flow

**Maps to delivered:** CAP-WS-01, CAP-WS-04, CAP-WS-06.

**Maps to active:** CAP-WS-05, CAP-WS-13.

```mermaid
stateDiagram-v2
    [*] --> Select
    Select --> CreateLocal: Create local Workspace
    Select --> Preflight: Open or switch Workspace
    Select --> JoinRemote: Join connected Workspace
    Preflight --> RepairReview: Invalid Notes found
    RepairReview --> Preflight: Repair or Exclude decisions complete
    Preflight --> Initialize: Valid adoption set
    CreateLocal --> Initialize
    JoinRemote --> Initialize
    Initialize --> Usable: Local history, secure index, and session scope ready
    Usable --> Rescan: Writer requests recovery
    Rescan --> Usable
```

Every entry path converges on one active Workspace with local history, secure aggregate indexing, authority state, and per-Workspace session scope.

## Failure path

- Secure index setup failure never falls back to an unprotected aggregate index.
- Invalid Notes remain excluded and uneditable until previewed Repair or Exclude.
- A Workspace switch runs the desktop-session close flow before changing the active Workspace.
- Partial initialization is recoverable and doesn't rewrite guest Note bytes silently.
