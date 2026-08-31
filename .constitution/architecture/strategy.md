---
version: v1.4.15
---

# Architectural strategy

## Architectural pattern

burlmd remains a local-first modular desktop application. One authoritative Core boundary coordinates a Canonical Note Model, Workspace state, local durability, guest-change reconciliation, and optional external synchronization. The editing path stays local and synchronous. Remote and Object transfers run asynchronously and can't become prerequisites for local writing.

A separate release pipeline produces installable artifacts for the supported Platform matrix. Pipeline-owned isolated environments run validation without using the Writer's active desktop. Each environment owns its display, compositor, input, and process state.

All three validation roles run the common functional matrix. Linux x86-64 and Apple Silicon macOS 26 are also performance-reference roles. The macOS 26 role also owns visual reference evidence. macOS 15 provides functional compatibility evidence only.

The Release Pipeline establishes the authoritative expected identity for each run. It contains the release, build, corpus, run, and required-role identities. The pipeline hands this identity independently to validation and aggregation. Validation evidence records captured environment and observed release, build, corpus, run, and role identities. Its artifact handoff authenticates the pipeline-owned origin and protects integrity.

The runtime can inspect release metadata and notify the Writer, but installation remains under the Platform or package manager's authority.

## Why this pattern fits

The pattern keeps every local capability available without a Provider or network connection. It also gives guest tools a published filesystem contract without giving them authority over invalid state. The Canonical Note Model prevents editing, rendering, indexing, and reconciliation from developing competing interpretations of one Note.

Remote synchronization and Object transfer are separate logical boundaries because they fail independently and don't share a transaction. A coordination state machine prevents published Note history from referencing unavailable Objects. Explicit Suggestion, Lifecycle Decision, Asset Decision, and guest-write paths keep distinct conflict classes from collapsing into one unsafe workflow.

Release validation is separate from evidence aggregation because execution and acceptance fail independently. Isolation keeps the Writer's desktop state out of visual proof. Aggregation authenticates the evidence origin and compares captured identity with the authoritative expected identity. It doesn't trust evidence self-description alone.

## Accepted trade-offs

- The installed application carries local parsing, indexing, history, monitoring, and synchronization responsibilities, which increases artifact size and internal complexity.
- Local Asset Store and Object Store coordination adds durable state and recovery work, but preserves offline access and user-controlled storage.
- A lowest-common-denominator Workspace path model rejects some host-valid names to preserve identity across systems.
- Structural and Asset Decisions can pause Workspace synchronization. Local editing and history remain available during the pause.
- Owned validation environments and integrity-checked evidence handoffs add pipeline latency and retained artifacts, but make reference results reproducible and attributable.
- Unsigned `0.x` macOS artifacts require accurate installation guidance until stable-release signing becomes release-blocking.
