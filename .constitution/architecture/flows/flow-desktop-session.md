---
job: JOB-02
capabilities: [CAP-023, CAP-024, CAP-025, CAP-026, CAP-027, CAP-028, CAP-029, CAP-030]
boundaries: [BND-01, BND-02, BND-04, BND-05, BND-08, BND-13]
view: state
certainty: assumed
assumption: "Migrated from markdown; not yet exercised by an integration test."
---
# Desktop session flow

**Maps to:** CAP-PREF-01, CAP-SHELL-02, CAP-SHELL-03, CAP-SHELL-04, CAP-SHELL-05, CAP-SHELL-06, CAP-SHELL-07, CAP-SHELL-08.

```mermaid
stateDiagram-v2
    [*] --> Restore
    Restore --> Active: Workspace and session state available
    Restore --> ChooseWorkspace: No restorable Workspace
    ChooseWorkspace --> Active: Open Workspace succeeds
    Active --> Active: Device preference persists outside Workspace
    Active --> Closing: Close tab, switch Workspace, or exit
    Closing --> Active: Clean close; continue serial batch
    Closing --> Active: Single replacement warning; continue to target Note
    Closing --> Partial: Batch or wider operation warning; stop and cancel
    Closing --> Partial: Close failure
    Partial --> Active: Preserve unprocessed sessions
    Closing --> [*]: Orderly exit completes
```

The Host Platform owns window chrome throughout this flow. Device preferences and per-Workspace session state use separate durable scopes.

## Failure path

- For one Note-to-Note replacement with no batch or wider lifecycle operation, a degraded-durability warning removes the retired tab, reports the warning, and continues to the target Note.
- During a batch, Workspace switch, or orderly exit, a degraded-durability warning removes the retired tab, reports the warning, stops the batch, preserves every unprocessed tab, and cancels the wider operation.
- A close failure keeps the failed and unprocessed tabs open, reports partial progress, and cancels a switch or exit.
- After an active-tab close, Presentation selects the following tab or the preceding tab when needed.
- Missing restored Notes are reported and skipped without blocking startup.
