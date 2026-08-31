# Release and upgrade flow

**Maps to:** CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06.

```mermaid
flowchart TD
    Build[Build supported artifacts]
    Linux[Linux x86-64 performance\nowned isolated environment]
    MacReference[Apple Silicon macOS 26 performance and visual\nowned isolated environment]
    MacCompatibility[macOS 15 functional compatibility\nowned isolated environment]
    Integrity[Verify evidence artifact integrity]
    Identity[Match environment, build, corpus, role, and run identity]
    Complete[Require complete current evidence set]
    Publish[Publish artifacts, evidence, provenance, and compatibility metadata]
    Available[Compatible higher 0.x release available]
    Notify[Notify Writer and open release information]
    PlatformInstall[Platform or package manager installs release]
    Migrating[Back up and migrate application state]
    Ready[Release ready]
    PreviousState[Restore previous state]
    Failed[Release evidence incomplete]
    Rejected[Reject evidence]

    Build -->|validation request with build and corpus identity| Linux
    Build -->|validation request with build and corpus identity| MacReference
    Build -->|validation request with build and corpus identity| MacCompatibility
    Linux -->|integrity-checked evidence artifact handoff| Integrity
    MacReference -->|integrity-checked evidence artifact handoff| Integrity
    MacCompatibility -->|integrity-checked evidence artifact handoff| Integrity
    Linux -->|ownership or validation failure| Failed
    MacReference -->|ownership or validation failure| Failed
    MacCompatibility -->|ownership or validation failure| Failed
    Integrity -->|artifact valid| Identity
    Integrity -->|missing or corrupt artifact| Rejected
    Identity -->|identity current and matched| Complete
    Identity -->|mismatched or stale identity| Rejected
    Complete -->|all assigned roles accepted| Publish
    Complete -->|required role missing| Failed
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
- Missing or corrupt evidence fails integrity verification before aggregation.
- Mismatched environment, build, corpus, role, or run identity is rejected. Stale evidence can't satisfy a current release gate.
- macOS 15 evidence can satisfy only functional compatibility. It can't replace either performance role or the macOS 26 visual role.
- A launch-only result can't admit a system to the supported matrix.
- Update notification never replaces installed binaries.
- Unsigned prerelease status and Platform installation guidance remain explicit.
