---
job: JOB-02
capabilities: [CAP-016, CAP-019, CAP-020, CAP-036, CAP-043]
boundaries: [BND-01, BND-02, BND-03, BND-04, BND-05, BND-07, BND-08, BND-12, BND-13]
view: state
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Workspace bootstrap flow

The active first-use path creates or restores one fresh local Workspace without an account or network connection.

```mermaid
stateDiagram-v2
    [*] --> Restore
    Restore --> Initialize: Prior fresh Workspace is available
    Restore --> CreateLocal: No Workspace exists
    CreateLocal --> Initialize
    Initialize --> Usable: Local history, secure index, and session scope ready
    Usable --> Rescan: Writer requests recovery
    Rescan --> Usable
```

Every entry path converges on one active Workspace with local history, secure aggregate indexing, authority state, and per-Workspace session scope.

CAP-036 and CAP-043 retain ownership of existing-collection adoption and multiple-Workspace interfaces. Those workflows are deferred and don't expand this first-use flow. Joining the same connected Workspace belongs to the Remote connection flow.

## Failure path

- Secure index setup failure never falls back to an unprotected aggregate index.
- Missing or unusable restored session state falls back to a safe local bootstrap outcome without rewriting Note bytes.
- A failed initialization preserves any complete earlier Workspace state and doesn't claim the partial state as usable.
- Rescan failure leaves the last authoritative Workspace state available and reports the recovery failure.
