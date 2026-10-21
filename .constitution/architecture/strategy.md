# Architectural strategy

## Architectural pattern

burlmd remains a local-first modular desktop application. One authoritative Core boundary coordinates a Canonical Note Model, Workspace state, local durability, guest-change reconciliation, and optional external synchronization. The editing path stays local and synchronous. Remote and Object transfers run asynchronously and can't become prerequisites for local writing.

The first usable boundary is one fresh Workspace on the Writer's private Linux checkout. It combines the selected P0 Markdown language, complete Note editing recovery, local images, automatic guest-change observation, plain-folder Export, local diagnostics, and qualification at 1,000 synthetic Notes. Portable Workspace identities apply from first use even though macOS runtime qualification is P2. Remote synchronization is the next delivery boundary and transfers Notes and local images together.

External Markdown images use a separate untrusted network peer because opening their Note automatically contacts the referenced host. Core requests only each external image reference from the opened Note and treats the response as optional display input. Failure never blocks Note opening or local editing, and automatic loading never rewrites or imports the reference.

A separate Release Pipeline retains the later public-release design. It doesn't gate the private Linux or synchronization milestones. Pipeline-owned isolated environments run supported-release validation without using the Writer's active desktop. Each role owns its display, compositor, and input state, and declares only the process controls it can prove.

The three validation roles define evidence capabilities. A validation request assigns the exact subset its gate requires. Linux x86-64 and Apple Silicon macOS 26 can serve as performance-reference roles. Linux can also supply exact platform-regression evidence, but that evidence isn't a product visual reference. The macOS 26 role alone can supply authoritative product visual evidence. macOS 15 provides functional compatibility evidence only.

The Release Pipeline establishes authoritative expected identity from an immutable reviewed validation anchor. It distinguishes the trust anchor, validation-control signer, tested source, base, release, build, corpus, run, roles, and evidence classes. The pipeline also fixes candidate placement and topology. Runtime observations confirm the expected label and terminal result. These trusted-workflow and runtime guards fail closed, but they don't cryptographically prove hosted origin.

Candidate commands remain credential-free and receive no provenance authority. A trusted wrapper can upload their complete output as an untrusted file handoff. The strict-containment role proves candidate-process teardown before upload. Other hosted roles perform bounded cleanup without claiming arbitrary-process containment.

A separate fresh sealing environment is the sole provenance and hosted-origin authority. It validates handoff identity and integrity and never executes candidate bytes. It authenticates the sealed evidence only after those checks pass. Fresh-seal provenance alone cryptographically authenticates the sealing environment's hosted origin. A surviving candidate process can corrupt or deny its untrusted upload. That outcome fails the role, but it doesn't grant access to sealing authority.

For the cross-version compatibility handoff, the macOS 26 seal also owns the authenticated compatibility handoff. It binds the exact stage identifier and integrity digest to its seal locator and provenance. A trusted macOS 15 wrapper verifies that binding, removes its acquisition credentials, and exposes the stage read-only. The credential-free candidate consumes it and records the lineage in its untrusted output. The macOS 15 seal validates the lineage against the trusted wrapper record before carrying it forward. Aggregation verifies the uninterrupted producer-seal-to-consumer chain. A later evidence-only report remains distinct from the tested source.

The runtime can inspect release metadata and notify the Writer, but installation remains under the Platform or package manager's authority.

## Why this pattern fits

The pattern keeps every local capability available without a Provider or network connection. It also gives guest tools a published filesystem contract without giving them authority over invalid state. The Canonical Note Model prevents editing, rendering, indexing, and reconciliation from developing competing interpretations of one Note.

Remote synchronization and Object transfer are separate logical boundaries because they fail independently and don't share a transaction. A coordination state machine prevents published Note history from referencing unavailable Objects. Explicit Suggestion, Lifecycle Decision, Asset Decision, and guest-write paths keep distinct conflict classes from collapsing into one unsafe workflow.

The delivery phases don't create artificial runtime dependencies. P1 Markdown follows synchronization, and P2 Markdown follows P1. macOS support can begin after P1 independently of the P2 Markdown increment. Existing-collection adoption, multiple-Workspace interfaces, in-app Version history, guided repair, Bundle Archive Export, image drag-and-drop, Consolidation, Object Store migration, automatic local image cleanup, 10,000-Note qualification, and public release remain deferred outcomes rather than expanded active flows.

Release validation is separate from evidence aggregation because execution, sealing, and acceptance fail independently. Isolation keeps the Writer's device state out of validation evidence. Aggregation verifies fresh-seal provenance and compares captured identity with authoritative expected identity. It treats candidate placement and completion as corroborating guards, never as hosted-origin proof. It also verifies the complete authenticated stage lineage for the cross-version compatibility handoff.

## Accepted trade-offs

- The installed application carries local parsing, indexing, history, monitoring, and synchronization responsibilities, which increases artifact size and internal complexity.
- Local Asset Store and Object Store coordination adds durable state and recovery work, but preserves offline access and Writer-controlled storage.
- Automatic external image loading exposes the referenced host and network observer to the request and can fail independently of the Note. Isolating that optional response preserves local availability but means externally referenced images aren't guaranteed offline.
- A lowest-common-denominator Workspace path model rejects some host-valid names to preserve identity across systems.
- Structural and Asset Decisions can pause Workspace synchronization. Local editing and history remain available during the pause.
- Owned validation environments and integrity-checked evidence handoffs add pipeline latency and retained artifacts, but make reference results reproducible and attributable.
- The cross-version compatibility producer-to-consumer lineage adds a sealed stage and credential-separated verification. This cost prevents artifact-name substitution from crossing the compatibility boundary.
- Unsigned `0.x` macOS artifacts require accurate installation guidance until stable-release signing becomes release-blocking.
