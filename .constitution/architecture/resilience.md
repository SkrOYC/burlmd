# Resilience and cross-cutting concerns

## Local durability

- Core Coordination persists drafts before acknowledging edits that must survive abrupt termination.
- Orderly close routes every entry point through one Note lifecycle. Batch close runs serially and records each clean, degraded, failed, or unprocessed outcome.
- A degraded-durability warning can retire a session. Presentation removes that tab, reports the warning, stops the batch, and cancels a wider switch or shutdown.
- Application-state migrations back up affected state, apply atomically, and restore the backup after failure.

## Guest-change resilience

- Workspace Observer reports candidate changes. Core Coordination validates conformance, containment, and the latest disk revision before changing authoritative state.
- A clean open Note adopts a conforming guest change through local history and reload.
- A dirty Note preserves both versions and pauses writes until the Writer chooses a reviewed outcome. Core Coordination revalidates the guest revision before applying the choice.
- Invalid guest input preserves original bytes and the last known-good Note. Repair requires a preview. Exclude keeps the input outside authoritative state.
- Rescan remains an explicit recovery path when event observation is incomplete.

## Reconciliation resilience

- Content differences become independently resolvable Suggestions in valid Note state. Pending Suggestions can persist through local and Remote history.
- Lifecycle Decisions and Asset Decisions pause Workspace synchronization. Local editing and history remain available.
- Every reconciliation durably records base, local, incoming, tentative, and Writer-decision state before materializing content Suggestions or pausing for a Decision.
- Before any reconciled history finalizes, Core Coordination verifies that the local history tip still matches the recorded input. If it advanced, reconciliation recomputes and revalidates content and Decisions.
- Crash recovery resumes from the durable reconciliation record and never applies a decision to stale tentative state.

## Remote and Object coordination

- External synchronization is optional. Offline, rate-limited, service-failure, authentication-required, privacy-failure, paused-decision, and pending-Suggestion states remain distinct.
- Transient Provider failures retain credentials and enter retryable states. Only an authoritative credential rejection enters authentication-required state.
- Before local history can reference a new Object, Application State records a durable operation intent and Object obligation.
- Before history publication, Object Transfer verifies every required Object in the Object Store. Startup and prepublication reconciliation derive missing obligations from unpublished history.
- Pull or join validates referenced Object manifests before authoritative materialization and hydrates active Assets first.
- An asset-bearing connected Workspace can't detach its Object Store alone. Offline Remote detachment retains the Object Store. Returning to fully local operation requires fresh authenticated enumeration of all published Remote refs, complete protected hydration, and atomic revision-bound detachment of both external storage boundaries.

## Retention and integrity

- Workspace Model derives Protected State from current state, retained or unpublished local history, reachable published Remote history, pending reconciliation, and Consolidation.
- Core Coordination exposes bytes only after Object identity verification.
- Local cache eviction requires a verified Object Store copy. Authoritative deletion also requires 30 days of unreachability and complete published-history enumeration.
- If published-history completeness can't be proven, authoritative deletion stops.

## Security and privacy

- Workspace-controlled paths never escape the Workspace boundary. Unsupported filesystem or nested-storage indirections are rejected before materialization.
- Remote and Object Store privacy are verified before connection and while synchronized. A privacy loss pauses synchronization.
- Persistent secrets exist only in Secure Storage. Transient in-memory material is narrowly scoped and promptly erased.
- Structured local diagnostics exclude Note content, Asset content, credentials, signed locations, and content-derived telemetry.
- No diagnostic or usage information leaves the device automatically. The Writer creates and shares a Diagnostics Export explicitly.

## Observability

Every durable state machine emits structured local events for transitions, retry class, partial outcome, recovery action, and correlation identity. Events contain identifiers needed for support without Note or Asset bytes. Diagnostics include application and schema versions so a report can be interpreted after upgrades.

## Configuration

Device preferences, per-Workspace session state, Provider connection, Object Store connection, and release channel are distinct configuration scopes. Defaults and migrations belong to Stage 3. Workspace content never stores device preferences or credentials.
