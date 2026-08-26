# Release and upgrade flow

**Maps to:** CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06.

```mermaid
stateDiagram-v2
    [*] --> BuildMatrix
    BuildMatrix --> VerifyInstalled: Artifacts produced for each supported system
    VerifyInstalled --> Publish: Common feature matrix passes
    VerifyInstalled --> Failed: Any supported system fails
    Publish --> Available: Artifacts, integrity, provenance, and compatibility metadata published
    Available --> Notify: Running app detects compatible higher 0.x release
    Notify --> PlatformInstall: Writer opens release information
    PlatformInstall --> Migrating: Platform or package manager installs release
    Migrating --> Ready: State backup and atomic migration succeed
    Migrating --> PreviousState: Migration fails and backup restores
```

## Failure path

- A launch-only result can't admit a system to the supported matrix.
- The Linux compatibility baseline remains provisional until OD-08 evidence is accepted upstream.
- Update notification never replaces installed binaries.
- Unsigned prerelease status and Platform installation guidance remain explicit.
