# Architectural strategy

## Architectural pattern

burlmd remains a local-first modular desktop application. One authoritative Core boundary coordinates a Canonical Note Model, Workspace state, local durability, guest-change reconciliation, and optional external synchronization. The editing path stays local and synchronous. Remote and Object transfers run asynchronously and can't become prerequisites for local writing.

A separate Release Pipeline produces installable artifacts for the supported Platform matrix. Pipeline-owned isolated environments run validation without using the Writer's active desktop. Each role owns its display, compositor, and input state, and declares only the process controls it can prove.

The three validation roles define evidence capabilities. A validation request assigns the exact subset its gate requires. Linux x86-64 and Apple Silicon macOS 26 can serve as performance-reference roles. Linux can also supply exact platform-regression evidence, but that evidence isn't a product visual reference. The macOS 26 role alone can supply authoritative product visual evidence. macOS 15 provides functional compatibility evidence only.

The Release Pipeline establishes authoritative expected identity from an immutable reviewed validation anchor. It distinguishes the trust anchor, validation-control signer, tested source, base, release, build, corpus, run, required roles, and role-specific evidence classes. The pipeline verifies the write boundary and hands expected identity independently to validation and aggregation. Candidate commands receive no provenance authority. A trusted wrapper may upload their complete output as an untrusted file handoff. The strict-containment role proves candidate-process teardown before the wrapper uploads the handoff; other hosted roles perform bounded cleanup without claiming arbitrary-process containment.

A separate fresh sealing environment is the sole provenance authority. It validates handoff identity and integrity, never executes candidate bytes, and only then authenticates the sealed evidence. A surviving candidate process can corrupt or deny its untrusted upload, causing that role to fail, but it can't cross into the fresh environment or gain sealing authority. A later evidence-only report state remains distinct from the tested source.

The runtime can inspect release metadata and notify the Writer, but installation remains under the Platform or package manager's authority.

## Why this pattern fits

The pattern keeps every local capability available without a Provider or network connection. It also gives guest tools a published filesystem contract without giving them authority over invalid state. The Canonical Note Model prevents editing, rendering, indexing, and reconciliation from developing competing interpretations of one Note.

Remote synchronization and Object transfer are separate logical boundaries because they fail independently and don't share a transaction. A coordination state machine prevents published Note history from referencing unavailable Objects. Explicit Suggestion, Lifecycle Decision, Asset Decision, and guest-write paths keep distinct conflict classes from collapsing into one unsafe workflow.

Release validation is separate from evidence aggregation because execution, sealing, and acceptance fail independently. Isolation keeps the Writer's device state out of validation evidence. Aggregation verifies fresh-seal provenance and compares captured identity with the authoritative expected identity. It doesn't trust candidate self-description alone.

## Accepted trade-offs

- The installed application carries local parsing, indexing, history, monitoring, and synchronization responsibilities, which increases artifact size and internal complexity.
- Local Asset Store and Object Store coordination adds durable state and recovery work, but preserves offline access and Writer-controlled storage.
- A lowest-common-denominator Workspace path model rejects some host-valid names to preserve identity across systems.
- Structural and Asset Decisions can pause Workspace synchronization. Local editing and history remain available during the pause.
- Owned validation environments and integrity-checked evidence handoffs add pipeline latency and retained artifacts, but make reference results reproducible and attributable.
- Unsigned `0.x` macOS artifacts require accurate installation guidance until stable-release signing becomes release-blocking.
