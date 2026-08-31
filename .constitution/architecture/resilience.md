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
- During replacement-store migration, the replacement first passes the complete private-store validation. A durable intent then makes every publisher verify fresh replacement privacy and new Objects in both stores. Privacy drift pauses migration and publication with the old store authoritative. Cutover uses compare-and-swap against the migration epoch, Workspace revision, and complete Remote-ref inventory after baseline and delta copy. Devices without replacement credentials pause publication but keep local use. Cutover retains the old store's non-secret fallback descriptor. A replacement miss can be repaired with securely supplied old-store credentials or by a credentialed peer; the old bytes are content-verified, backfilled and verified in the replacement, and only then hydrated.
- Complete advertised-Remote-ref analysis is resource-bounded and fail-closed. Count, advertisement-byte, fetched-byte, or deadline exhaustion marks Remote authority incomplete, cleans the isolated quarantine, preserves local use, and blocks only decisions that require complete published history.
- Pull or join validates referenced Object manifests before authoritative materialization and hydrates active Assets first.
- An asset-bearing connected Workspace can't detach its Object Store alone. Offline Remote detachment retains the Object Store. Returning to fully local operation requires fresh authenticated enumeration of all published Remote refs, complete protected hydration, and atomic revision-bound detachment of both external storage boundaries.

## Retention and integrity

- Workspace Model derives Protected State from current state, retained or unpublished local history, reachable published Remote history, pending reconciliation, and Consolidation.
- Core Coordination exposes bytes only after Object identity verification.
- Local cache eviction requires a verified Object Store copy and no active offline need. burlmd doesn't delete authoritative Object Store bytes during `0.x` because Git publication and generic S3-compatible deletion can't form one atomic transaction.

## Security and privacy

- Workspace-controlled paths never escape the Workspace boundary. Unsupported filesystem or nested-storage indirections are rejected before materialization.
- Remote and Object Store privacy are verified before connection and while synchronized. A privacy loss pauses synchronization.
- Persistent secrets exist only in Secure Storage. Transient in-memory material is narrowly scoped and promptly erased.
- Structured local diagnostics exclude Note content, Asset content, credentials, signed locations, and content-derived telemetry.
- No diagnostic or usage information leaves the device automatically. The Writer creates and shares a Diagnostics Export explicitly.

## Validation evidence

- Each validation run owns an isolated display, compositor, input channel, and process lifecycle. If it can't prove ownership, the run emits no acceptable evidence.
- The Writer's active desktop never supplies visual proof or validation input. A captured Writer window or desktop state invalidates the run.
- Release Pipeline establishes an immutable trust-anchor identity from a reviewed and merged validation implementation. It creates authoritative trust-anchor, workflow-signer, tested-source, base, release, build, corpus, run, and required-role identities outside the tested source. It hands the same expectation directly to validation and aggregation.
- Every validation role hands off one complete bundle containing its manifest and every named evidence file. The handoff authenticates managed validation origin and protects upload and bundle integrity.
- Evidence Aggregation compares captured identity with the authoritative expected identity. It verifies that the workflow signer retains the trust-anchor definition and that the exact trusted-base-to-tested-source change stays inside the ticket's declared write boundary. It rejects candidate-defined validation control, self-description alone, an unmanaged or untrusted origin, incomplete or corrupt bundles, mismatches, and stale evidence. A later report state can't replace the tested source identity.
- Evidence Aggregation separates credentialed acquisition from candidate-controlled aggregation. It resolves and identifies the coordinator before acquiring remote credentials. The authenticated phase only downloads and verifies evidence. It then destroys the credential context before running the prepared coordinator with read-only inputs, one writable output boundary, no inherited user configuration, and no network. Any credential, configuration, descriptor, filesystem, or network isolation failure rejects the evidence.
- The validation implementation establishes trust through two reviewed integrations. The first integration lands the locally validated implementation and defines its immutable trust anchor. The merged implementation validates that exact source. A second evidence-only integration records the accepted result and completion state. Validation remains incomplete until both integrations merge. Any later change to the trusted launcher or workflow definition repeats this bootstrap.
- All three roles supply common functional-matrix evidence. Linux x86-64 and Apple Silicon macOS 26 also supply performance evidence. Linux supplies required exact platform-regression evidence, which is non-authoritative implementation evidence and can't replace product visual proof. macOS 26 alone supplies authoritative product visual evidence.
- macOS 15 supplies functional compatibility evidence only. It can't replace either performance role, Linux platform-regression evidence, or macOS 26 authoritative visual evidence.
- A partial run remains incomplete. Each retry receives a distinct run identity instead of reusing an earlier result.

## Observability

Every durable state machine emits structured local events for transitions, retry class, partial outcome, recovery action, and correlation identity. Events contain identifiers needed for support without Note or Asset bytes. Diagnostics include application and schema versions so a report can be interpreted after upgrades.

Release validation records isolation ownership, evidence handoff, identity rejection, freshness rejection, credential-boundary checks, coordinator identity, and aggregation outcomes. These records correlate a release identity without including the Writer's desktop content.

## Configuration

Device preferences, per-Workspace session state, Provider connection, Object Store connection, and release channel are distinct configuration scopes. Defaults and migrations belong to Stage 3. Workspace content never stores device preferences or credentials.
