# Domain model

```mermaid
graph TD
    writer([Writer])
    agent([Agent])
    provider([Provider])
    remote([Remote])
    objectStore([Object Store])
    platform([Platform])

    subgraph workspace[Workspace]
        directory[Directory]
        note[Note]
        block[Block]
        link[Link]
        localAssetStore[Local Asset Store]
        asset[Asset]
        object[Object]
        version[Version]
        suggestion[Suggestion]
        lifecycleDecision[Lifecycle Decision]
        assetDecision[Asset Decision]
        protectedState[Protected State]
    end

    writer -- "creates, edits, reads, deletes" --> note
    writer -- "organizes" --> directory
    writer -- "accepts or rejects" --> suggestion
    writer -- resolves --> lifecycleDecision
    writer -- resolves --> assetDecision
    writer -- "browses, restores" --> version
    agent -- reads --> note
    agent -- traverses --> link
    agent -- writes --> note
    platform -- "hosts and protects local state" --> workspace
    directory -- "contains (1:N)" --> note
    directory -- "nests (1:N)" --> directory
    note -- "composed of (1:N)" --> block
    note -- "may contain" --> suggestion
    suggestion -- "scopes to" --> block
    block -- contains --> link
    link -- "targets a Note (may be unresolved)" --> note
    note -- references --> asset
    asset -- identifies --> object
    localAssetStore -- "keeps active bytes" --> object
    workspace -- contains --> localAssetStore
    note -- "has past states (1:N)" --> version
    workspace -- "may pause on" --> lifecycleDecision
    workspace -- "may pause on" --> assetDecision
    lifecycleDecision -- "governs identity or hierarchy" --> note
    lifecycleDecision -- "governs identity or hierarchy" --> directory
    assetDecision -- governs --> asset
    workspace -- defines --> protectedState
    version -- "contributes history" --> protectedState
    remote -- "contributes published history" --> protectedState
    protectedState -- retains --> object
    provider -- hosts --> remote
    workspace -- syncs to/from once connected --> remote
    workspace -- "syncs Object bytes when connected" --> objectStore
    objectStore -- stores --> object
```

## Model rules

- A **Workspace** is complete without a **Remote**. The Remote is an optional connection that adds multi-device synchronization. Every other relationship in this diagram holds with no Remote present.
- A **Link** may target a Note that does not exist yet. Such a Link remains valid and traversable as an intent, and resolves once the target Note is created.
- A **Suggestion** can persist through history and Remote synchronization until the Writer accepts or rejects it.
- A **Lifecycle Decision** or **Asset Decision** pauses Workspace synchronization until the Writer resolves it. Local editing and history remain available.
- An **Asset** is a user-visible reference. An **Object** contains immutable bytes. The Local Asset Store keeps active Objects available offline, and an optional Object Store synchronizes Objects between devices.
- A **Protected State** includes current Workspace state, all retained or unpublished local history, all reachable published Remote history, pending reconciliation, and Consolidation. Every reachable Object remains authoritative.
- A **Version** is a past state of one Note, captured by local history. Versions make deletion recoverable and restore possible; they belong to the problem space because users reason about "what this Note looked like last Tuesday," not about repositories.
- The **Agent** can read or write the same on-disk Workspace that the Writer edits. The Agent must follow burlmd's published Workspace contract. Guest access doesn't transfer semantic authority away from burlmd.
