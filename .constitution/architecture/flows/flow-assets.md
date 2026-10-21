---
job: JOB-08
capabilities: [CAP-031, CAP-052, CAP-053, CAP-056, CAP-057, CAP-059, CAP-060]
boundaries: [BND-01, BND-02, BND-03, BND-04, BND-05, BND-06, BND-13]
view: sequence
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Local Asset import flow

The active path accepts a local image through file selection or clipboard paste. Both inputs create the same verified local Asset outcome and remain independent of Remote synchronization.

```mermaid
sequenceDiagram
    participant UI as Presentation and Interaction
    participant Core as Core Coordination
    participant CanonicalNote as Canonical Note Model
    participant Workspace as Workspace Model
    participant LocalAssets as Local Asset Store
    participant Persist as Workspace Persistence
    participant Host as Host Platform

    alt Select local image file
        UI->>Host: Request Writer-approved file selection
        Host-->>UI: Selected file or cancellation
    else Paste image data
        UI->>Host: Request clipboard image data
        Host-->>UI: Image data or unavailable result
    end
    opt Image input is available
        UI->>Core: Accepted local image input
        Core->>LocalAssets: Copy bytes, verify identity, and deduplicate Object
        LocalAssets-->>Core: Verified Object identity
        Core->>Workspace: Create portable Asset reference
        Core->>CanonicalNote: Insert image reference as one source-preserving edit
        CanonicalNote-->>Core: Updated Note and inverse operation
        Core->>Persist: Record updated Note and recoverable local outcome
        Core-->>UI: Display the local image from the verified local copy
    end
```

CAP-059 and CAP-060 retain ownership of existing-collection Asset adoption, but that workflow is deferred and doesn't expand this active flow. Drag-and-drop input is also deferred. CAP-057 remains owned by the Object Store lifecycle flow.

## Failure path

- Imported source locations never remain dependencies after a successful copy.
- Cancellation or unavailable clipboard image data leaves the Note and Local Asset Store unchanged.
- A copy, identity, reference, or persistence failure leaves the Note unchanged and preserves every verified byte already present.
- Undo removes the inserted Note reference through its inverse editing operation. Object retention remains governed by Protected State rather than by immediate deletion.
- Same bytes reuse one Object. Different local bytes for one reference enter Object recovery; competing Asset outcomes produced by Remote reconciliation require an Asset Decision.
- Missing or corrupt local Objects preserve every verified copy and enter the Object recovery flow, which offers Retry, Repair from local copy, Choose replacement, or Remove reference when valid. Local corruption doesn't create an Asset Decision. Synchronization pauses only when Object availability or a separately created reconciliation decision makes publication unsafe.
