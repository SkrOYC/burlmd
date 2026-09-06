---
job: JOB-09
capabilities: [CAP-075, CAP-076, CAP-077, CAP-078, CAP-079, CAP-080]
boundaries: [BND-13, BND-15, BND-16, BND-17, BND-18, BND-19]
view: dag
certainty: assumed
assumption: "The user settled candidate guards, fresh-seal authority, and the cross-version compatibility handoff, but the complete release and upgrade path remains unexercised across all six capabilities."
---
# Release and upgrade flow

**Maps to:** CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06.

```mermaid
flowchart TD
    Build[Build supported artifacts]
    Trust[Immutable reviewed validation trust anchor]
    Expected[Authoritative expected identity\ntrust anchor, validation-control signer, tested source, base, release, build, corpus, run, roles, evidence classes, placement, topology, and completion]
    Linux[Credential-free strict-containment candidate\nassigned Linux x86-64 evidence classes]
    MacReference[Credential-free reference candidate\nassigned Apple Silicon macOS 26 evidence classes]
    StageAcquire[Trusted macOS 15 stage verification\nacquire exact cross-version compatibility stage, verify producer-seal binding, remove credentials, expose read-only]
    MacCompatibility[Credential-free compatibility candidate\nassigned macOS 15 evidence classes]
    Placement[Candidate placement and completion guards\nfixed workflow placement, topology, observed label, and terminal result\nnot cryptographic hosted-origin proof]
    LinuxSeal[Fresh Linux sealing environment\nvalidate handoff, execute no candidate bytes, authenticate provenance]
    MacReferenceSeal[Fresh macOS 26 sealing environment\nvalidate handoff, execute no candidate bytes, authenticate provenance]
    MacCompatibilitySeal[Fresh macOS 15 sealing environment\nvalidate handoff, execute no candidate bytes, authenticate provenance]
    Stage[Authenticated cross-version compatibility stage\nexact identifier and integrity digest bound to macOS 26 seal locator and provenance]
    Observe[Post-completion observation\nrequire successful sealing environment]
    Integrity[Verify fresh-seal provenance and complete evidence handoff integrity]
    Lineage[Verify cross-version compatibility producer seal, stage, credential-free consumption, and unchanged consumer binding]
    Identity[Compare captured identity with authoritative expected identity]
    Complete[Require complete current evidence set]
    Report[Review evidence-only integration after tested source]
    Publish[Publish artifacts, evidence, provenance, and compatibility metadata]
    Available[Compatible higher 0.x release available]
    Notify[Notify Writer and open release information]
    PlatformInstall[Platform or package manager installs release]
    Migrating[Back up and migrate application state]
    Ready[Release ready]
    PreviousState[Restore previous state]
    Failed[Release evidence incomplete]
    Rejected[Reject evidence]

    Trust -->|trusted identity authority| Expected
    Build -->|release candidate and required roles| Expected
    Build -->|artifact and validation request| Linux
    Build -->|artifact and validation request| MacReference
    Build -->|artifact and validation request| MacCompatibility
    Expected -->|authoritative expected-identity handoff| Linux
    Expected -->|authoritative expected-identity handoff| MacReference
    Expected -->|authoritative expected-identity handoff| MacCompatibility
    Expected -->|authoritative expected-identity handoff| Identity
    Linux -->|trusted-wrapper file handoff: complete untrusted role bundle| LinuxSeal
    MacReference -->|trusted-wrapper file handoff: complete untrusted role bundle| MacReferenceSeal
    MacCompatibility -->|trusted-wrapper file handoff: complete untrusted role bundle| MacCompatibilitySeal
    Linux -->|runtime observation| Placement
    MacReference -->|runtime observation| Placement
    MacCompatibility -->|runtime observation| Placement
    LinuxSeal -->|fresh-sealed bundle and pre-completion locator| Observe
    MacReferenceSeal -->|fresh-sealed bundle and pre-completion locator| Observe
    MacCompatibilitySeal -->|fresh-sealed bundle and pre-completion locator| Observe
    MacReferenceSeal -->|authenticated cross-version compatibility handoff| Stage
    Stage -->|trusted acquisition and offline verification| StageAcquire
    StageAcquire -->|verified read-only members with no credential context| MacCompatibility
    Observe -->|completed successful sealing handoff| Integrity
    Linux -->|ownership or validation failure| Failed
    MacReference -->|ownership or validation failure| Failed
    MacCompatibility -->|ownership or validation failure| Failed
    Placement -->|guards pass as corroboration only| Complete
    Placement -->|placement, topology, label, or completion failure| Rejected
    LinuxSeal -->|identity, integrity, or authority separation failure| Rejected
    MacReferenceSeal -->|identity, integrity, or authority separation failure| Rejected
    MacCompatibilitySeal -->|identity, integrity, or authority separation failure| Rejected
    Observe -->|in-progress, failed, missing, duplicate, substituted, or mismatched handoff| Rejected
    Integrity -->|provenance and handoff valid| Identity
    Integrity -->|untrusted provenance, missing handoff, or corrupt handoff| Rejected
    MacReferenceSeal -->|producer seal binding| Lineage
    Stage -->|stage identifier, integrity digest, locator, and provenance| Lineage
    MacCompatibilitySeal -->|consumer binding| Lineage
    Lineage -->|uninterrupted cross-version compatibility lineage| Complete
    Lineage -->|absent, substituted, stale, or mismatched chain| Rejected
    Identity -->|captured identity matches expected identity| Complete
    Identity -->|expected identity missing or captured identity mismatched or stale| Rejected
    Complete -->|all assigned roles accepted| Report
    Complete -->|required role missing| Failed
    Report -->|reviewed evidence state remains distinct from tested source| Publish
    Publish --> Available
    Available --> Notify
    Notify --> PlatformInstall
    PlatformInstall --> Migrating
    Migrating -->|migration succeeds| Ready
    Migrating -->|migration fails| PreviousState
```

## Failure path

- Every validation role owns its display, compositor, and input state. The strict-containment role proves candidate-process teardown before its trusted wrapper uploads the handoff. Other hosted roles record bounded cleanup and don't claim that arbitrary candidate processes ended. A missing assigned ownership, teardown, or cleanup result produces no acceptable evidence.
- The Writer's active device never supplies visual proof or validation input. Writer windows, desktop state, or active-device input in a capture invalidate the complete run.
- Missing authoritative trust-anchor, validation-control signer, tested-source, base, release, build, corpus, run, required-role, role-specific evidence-class, candidate-placement, topology, or completion expectation prevents evidence acceptance.
- A candidate-defined launcher, provenance control, expected identity, or change outside the declared write boundary prevents dispatch or evidence acceptance.
- Candidate commands are credential-free and receive no provenance authority. A trusted wrapper can upload the complete candidate bundle, but the file handoff remains untrusted. A candidate survivor can corrupt or deny that upload and fail the role. It can't enter a fresh sealing environment or gain its authority.
- Trusted workflow fixes candidate placement and topology. Runtime observations confirm the expected label and terminal result. These guards don't cryptographically prove hosted origin. A failed guard rejects the role, but a passing guard can't substitute for seal provenance.
- Each fresh sealing environment is the sole provenance and hosted-origin authority for its role. It never executes candidate bytes. It validates candidate-environment identity, exact inventory, and complete integrity before authenticating a sealed handoff. Fresh-seal provenance alone cryptographically authenticates the sealing environment's hosted origin. If that separation or validation can't be proved, evidence is rejected.
- For the cross-version compatibility handoff, the macOS 26 seal validates the producer members and creates the authenticated compatibility stage. It binds the exact stage identifier and integrity digest to its seal locator and provenance.
- The trusted macOS 15 wrapper acquires that exact stage and verifies its producer-seal binding before candidate execution. It removes the acquisition credential context and exposes verified members read-only. The candidate receives no credential or provenance authority.
- The macOS 15 seal validates the producer stage lineage against the trusted wrapper record and preserves it. Aggregation rejects any absent, duplicate, substituted, expired, integrity-mismatched, unauthenticated, wrong-producer, wrong-role, wrong-run, wrong-seal, or consumer-unbound stage.
- A sealing environment can't attest its own final result before it finishes. Aggregation must observe one completed successful sealing environment independently; an in-progress, failed, missing, duplicate, substituted, or role-inconsistent handoff prevents evidence acceptance.
- Validation bootstrap needs a reviewed implementation integration followed by a reviewed evidence-only integration. The validation capability remains incomplete between them.
- Untrusted or unmanaged sealing provenance, an incomplete evidence handoff, or corrupt evidence fails verification before aggregation.
- Candidate-controlled aggregation never shares the authenticated acquisition context. Missing coordinator identity, reachable credentials or user configuration, writable inputs, an extra writable filesystem boundary, or available network access rejects the run.
- Aggregation compares captured identity with the expected identity supplied directly by Release Pipeline. Self-description alone is insufficient. For the cross-version compatibility handoff, aggregation also verifies the uninterrupted producer-seal-to-consumer lineage.
- A captured identity that is mismatched or stale is rejected. Evidence from another run can't satisfy the current release gate.
- The later evidence commit remains distinct from the tested source. A commit that changes anything except declared evidence can't represent that run.
- Every role must pass exactly the evidence classes assigned by the current gate. An environment capability isn't required unless the gate assigns it. macOS 15 can't replace either performance role, Linux platform-regression evidence, or the macOS 26 authoritative product visual role.
- A launch-only result can't admit a system to the supported matrix.
- Update notification never replaces installed binaries.
- Unsigned prerelease status and Platform installation guidance remain explicit.
