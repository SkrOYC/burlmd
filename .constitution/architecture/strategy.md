# Architectural strategy

## Architectural pattern

burlmd remains a local-first modular desktop application. One authoritative Core boundary coordinates a Canonical Note Model, Workspace state, local durability, guest-change reconciliation, and optional external synchronization. The editing path stays local and synchronous. Remote and Object transfers run asynchronously and can't become prerequisites for local writing.

A separate Release Pipeline produces installable artifacts for the supported Platform matrix. Pipeline-owned isolated environments run validation without using the Writer's active desktop. Each role owns its display, compositor, and input state, and declares only the process controls it can prove.

The three validation roles define evidence capabilities. A validation request assigns the exact subset its gate requires. Linux x86-64 and Apple Silicon macOS 26 can serve as performance-reference roles. Linux can also supply exact platform-regression evidence, but that evidence isn't a product visual reference. The macOS 26 role alone can supply authoritative product visual evidence. macOS 15 provides functional compatibility evidence only.

The Release Pipeline establishes authoritative expected identity from an immutable reviewed validation anchor. It distinguishes the trust anchor, validation-control signer, tested source, base, release, build, corpus, run, roles, and evidence classes. The pipeline also fixes candidate placement and topology. Runtime observations confirm the expected label and terminal result. These trusted-workflow and runtime guards fail closed, but they don't cryptographically prove hosted origin.

Candidate commands remain credential-free and receive no provenance authority. A trusted wrapper can upload their complete output as an untrusted file handoff. The strict-containment role proves candidate-process teardown before upload. Other hosted roles perform bounded cleanup without claiming arbitrary-process containment.

A separate fresh sealing environment is the sole provenance and hosted-origin authority. It validates handoff identity and integrity and never executes candidate bytes. It authenticates the sealed evidence only after those checks pass. Fresh-seal provenance alone cryptographically authenticates the sealing environment's hosted origin. A surviving candidate process can corrupt or deny its untrusted upload. That outcome fails the role, but it doesn't grant access to sealing authority.

For BURL-O001, the macOS 26 seal also owns the authenticated compatibility handoff. It binds the exact stage identifier and integrity digest to its seal locator and provenance. A trusted macOS 15 wrapper verifies that binding, removes its acquisition credentials, and exposes the stage read-only. The credential-free candidate consumes it and records the lineage in its untrusted output. The macOS 15 seal validates the lineage against the trusted wrapper record before carrying it forward. Aggregation verifies the uninterrupted producer-seal-to-consumer chain. A later evidence-only report remains distinct from the tested source.

The runtime can inspect release metadata and notify the Writer, but installation remains under the Platform or package manager's authority.

## Why this pattern fits

The pattern keeps every local capability available without a Provider or network connection. It also gives guest tools a published filesystem contract without giving them authority over invalid state. The Canonical Note Model prevents editing, rendering, indexing, and reconciliation from developing competing interpretations of one Note.

Remote synchronization and Object transfer are separate logical boundaries because they fail independently and don't share a transaction. A coordination state machine prevents published Note history from referencing unavailable Objects. Explicit Suggestion, Lifecycle Decision, Asset Decision, and guest-write paths keep distinct conflict classes from collapsing into one unsafe workflow.

Release validation is separate from evidence aggregation because execution, sealing, and acceptance fail independently. Isolation keeps the Writer's device state out of validation evidence. Aggregation verifies fresh-seal provenance and compares captured identity with authoritative expected identity. It treats candidate placement and completion as corroborating guards, never as hosted-origin proof. For BURL-O001, it also verifies the complete authenticated stage lineage.

## Accepted trade-offs

- The installed application carries local parsing, indexing, history, monitoring, and synchronization responsibilities, which increases artifact size and internal complexity.
- Local Asset Store and Object Store coordination adds durable state and recovery work, but preserves offline access and Writer-controlled storage.
- A lowest-common-denominator Workspace path model rejects some host-valid names to preserve identity across systems.
- Structural and Asset Decisions can pause Workspace synchronization. Local editing and history remain available during the pause.
- Owned validation environments and integrity-checked evidence handoffs add pipeline latency and retained artifacts, but make reference results reproducible and attributable.
- The BURL-O001 producer-to-consumer lineage adds a sealed stage and credential-separated verification. This cost prevents artifact-name substitution from crossing the compatibility boundary.
- Unsigned `0.x` macOS artifacts require accurate installation guidance until stable-release signing becomes release-blocking.
