---
job: JOB-06
capabilities: [CAP-066, CAP-071, CAP-072, CAP-074]
boundaries: [BND-01, BND-02, BND-04, BND-05, BND-10]
view: state
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Reconciliation flow

**Maps to:** CAP-SYNC-04, CAP-SYNC-10, CAP-SYNC-11, CAP-SYNC-13.

```mermaid
stateDiagram-v2
    [*] --> Analyze
    Analyze --> RecordInputs: Classify divergence
    RecordInputs --> MaterializeTentative: Persist base, local, incoming, and tentative identity
    MaterializeTentative --> Content: Independently resolvable Note content
    MaterializeTentative --> Lifecycle: Identity, hierarchy, type, or path outcome
    MaterializeTentative --> Asset: Asset bytes, reference, or availability outcome
    Content --> FinalizeContent: Valid Note state contains persistent Suggestions
    FinalizeContent --> Analyze: Local history advanced
    FinalizeContent --> SynchronizedWithSuggestions: Recorded local input remains current
    SynchronizedWithSuggestions --> Resolved: Writer accepts or rejects each Suggestion
    Lifecycle --> Paused: Lifecycle Decision required
    Asset --> Paused: Asset Decision required
    Paused --> FinalizeDecision: Writer records decision
    FinalizeDecision --> Analyze: Local history advanced or outcome changed
    FinalizeDecision --> Resolved: Recorded inputs and decisions remain valid
    Resolved --> [*]
```

Delete-versus-edit follows the content path. burlmd restores the edited Note as a Suggestion and requires confirmation before deletion wins.

## Failure path

- Reconciliation records preserve base, local, incoming, tentative, and Writer-decision state before input is accepted.
- Crash recovery resumes from the record.
- Finalization fails closed when local state advanced and requires renewed input for changed outcomes.
- Raw conflict markers never become the user-facing or authoritative resolution model.
