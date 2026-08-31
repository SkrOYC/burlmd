# Release and upgrade flow

**Maps to:** CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06.

```mermaid
flowchart TD
    Build[Build supported artifacts]
    Trust[Immutable reviewed validation trust anchor]
    Expected[Authoritative expected identity\ntrust anchor, workflow signer, tested source, base, build, corpus, run, and required roles]
    Linux[Linux x86-64 common functional, performance, and non-authoritative exact platform regression\nowned isolated environment]
    MacReference[Apple Silicon macOS 26 common functional, performance, and authoritative product visual\nowned isolated environment]
    MacCompatibility[macOS 15 common functional compatibility only\nowned isolated environment]
    Integrity[Authenticate managed validation origin and verify complete evidence bundle integrity]
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
    Linux -->|authenticated-origin complete evidence bundle handoff| Integrity
    MacReference -->|authenticated-origin complete evidence bundle handoff| Integrity
    MacCompatibility -->|authenticated-origin complete evidence bundle handoff| Integrity
    Linux -->|ownership or validation failure| Failed
    MacReference -->|ownership or validation failure| Failed
    MacCompatibility -->|ownership or validation failure| Failed
    Integrity -->|origin and artifact valid| Identity
    Integrity -->|untrusted origin, missing artifact, or corrupt artifact| Rejected
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

- Every validation environment owns its display, compositor, input, and process state. If ownership isn't proven, it produces no acceptable evidence.
- The Writer's active desktop never supplies visual proof. The Writer's desktop state in a capture invalidates the complete run.
- Missing authoritative trust-anchor, workflow-signer, tested-source, base, release, build, corpus, run, or required-role identity prevents evidence acceptance.
- A candidate-defined launcher, signer workflow, expected identity, or change outside the ticket's declared write boundary prevents dispatch or evidence acceptance.
- Validation bootstrap needs a reviewed implementation integration followed by a reviewed evidence-only integration. The validation capability remains incomplete between them.
- An untrusted or unmanaged validation origin, an incomplete evidence bundle, or corrupt evidence fails verification before aggregation.
- Candidate-controlled aggregation never shares the authenticated acquisition context. Missing coordinator identity, reachable credentials or user configuration, writable inputs, an extra writable filesystem boundary, or available network access rejects the run.
- Aggregation compares captured identity with the expected identity supplied directly by Release Pipeline. Self-description alone is insufficient.
- A captured identity that is mismatched or stale is rejected. Evidence from another run can't satisfy the current release gate.
- The later evidence commit remains distinct from the tested source. A commit that changes anything except declared evidence can't represent that run.
- All three roles must pass the common functional matrix. Linux must also pass its exact non-authoritative platform-regression gate. macOS 15 can't replace either performance role, Linux platform-regression evidence, or the macOS 26 authoritative product visual role.
- A launch-only result can't admit a system to the supported matrix.
- Update notification never replaces installed binaries.
- Unsigned prerelease status and Platform installation guidance remain explicit.
