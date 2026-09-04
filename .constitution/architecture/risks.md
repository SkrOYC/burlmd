# Logical risks and technical debt

## Trust boundaries and threat notes

The following table summarizes the Stage 2 trust boundaries:

| Boundary | Dominant threats | Logical mitigation |
| :--- | :--- | :--- |
| Agent to Workspace | Tampering, path escape, denial of service | Treat every guest write as a proposal. Validate conformance, containment, size, and revision before authority changes. |
| Provider and Remote | Spoofing, tampering, information disclosure, denial of service | Use explicit authorization and privacy states. Validate incoming history and keep local work available. |
| Object Store | Tampering, information disclosure, denial of service | Refuse anonymous list, read, write, and delete access; verify Object identity; isolate credentials; and pause dependent history publication. |
| Platform secure storage | Information disclosure, elevation of privilege | Persist secrets only through Platform facilities and limit transient exposure. |
| Validation Environment to Evidence Aggregation | Spoofing, tampering, information disclosure, denial of service, elevation of privilege | Create expected identity from an immutable reviewed trust anchor, keep tested source separate from provenance authority, treat candidate output as an untrusted file handoff, make a fresh non-executing sealing environment the sole provenance authority, verify the write boundary, and run candidate-controlled aggregation only after destroying the credential context inside a non-networked, filesystem-restricted execution boundary. |
| Release Distribution | Tampering, spoofing | Publish common-matrix evidence, integrity data, and provenance for every artifact. |

Repudiation isn't a release claim because burlmd is a single-Writer local product and doesn't provide third-party authorship attestation.

## Risk 1: Canonical model projection cost

- **Risk:** A complete Canonical Note Model can exceed input-latency or memory constraints when every edit projects a large tree to Presentation.
- **Sensitivity point:** Projection granularity and source-range ownership affect responsiveness without changing the logical boundary.
- **Mitigation:** The AST Spike measures candidate foundations, full and partial projections, source fidelity, and reference profiles before Stage 3 accepts a physical model.

## Risk 2: Cross-platform path rejection

- **Risk:** A lowest-common-denominator path model can reject names that are valid on the current host or create unexpected disambiguation.
- **Sensitivity point:** Normalization and collision rules affect portability, Link stability, and adoption friction together.
- **Mitigation:** The path Spike tests supported host filesystems and Windows-compatible rules. Guest paths fail preflight before mutation.

## Risk 3: Missed or reordered guest events

- **Risk:** Platform event streams can omit, duplicate, or reorder changes, leaving the derived index or open Note stale.
- **Sensitivity point:** Debounce duration trades detection latency against duplicate lifecycle outcomes.
- **Mitigation:** Events are hints, not authority. Reconcile against disk state and revision, deduplicate bursts, and retain Rescan as recovery.

## Risk 4: Stale reconciliation decisions

- **Risk:** Local history can advance while a Lifecycle Decision or Asset Decision is open.
- **Sensitivity point:** Allowing local editing improves availability but invalidates a tentative result.
- **Mitigation:** Persist reconciliation inputs and condition finalization on unchanged local state. Recompute and request renewed input when outcomes differ.

## Risk 5: Remote and Object split transaction

- **Risk:** A crash can leave Note history referencing an Object without a durable upload obligation.
- **Sensitivity point:** Intent timing affects local responsiveness and publication safety.
- **Mitigation:** Persist the Object obligation before referenced history, repair obligations from unpublished history on startup and before publication, and verify Objects before push.

## Risk 6: Cross-system Object deletion race

- **Risk:** A Remote history reference can publish an Object reference between reachability inspection and deletion from the Object Store.
- **Sensitivity point:** Remote history publication and Object Store operations don't share an atomic transaction, and guest publishers can't be required to honor a burlmd-only lease.
- **Mitigation:** During `0.x`, burlmd evicts only verified local cache copies and never deletes authoritative Object Store bytes.

## Risk 7: Provider state ambiguity

- **Risk:** Network failure, rate limiting, expired tokens, revoked authorization, lost installation access, and public visibility can collapse into one authentication error.
- **Mitigation:** Keep distinct state classes and recovery actions. Reauthorization follows only authoritative credential rejection or revocation.

## Risk 8: Release support drift

- **Risk:** An artifact can launch but fail secure storage, file selection, authorization, synchronization, or update checks on a named system.
- **Sensitivity point:** A wider Platform matrix multiplies release-gate cost.
- **Mitigation:** Admit a system only after the complete installed-app matrix passes. The packaging Spike selects the Linux baseline before Stage 3 binds it.

## Risk 9: Unsigned prerelease trust

- **Risk:** Unsigned `0.x` macOS artifacts create installation friction and a weaker trust signal.
- **Mitigation:** Publish integrity and provenance, label the artifact accurately, and provide Platform guidance. Signing becomes release-blocking at stability.

## Risk 10: Delivered-model migration

- **Risk:** Replacing the smaller rendering projection with the Canonical Note Model can regress delivered editing, selection, Links, or lifecycle behavior.
- **Mitigation:** Treat delivered A-F behavior as compatibility evidence. The AST Spike and final implementation contracts must preserve source fidelity and existing acceptance suites.

## Contaminated or misattributed validation evidence

- **Risk:** Validation can capture the Writer's device, accept evidence from another environment, let a candidate survivor corrupt or deny its untrusted upload, or expose aggregation credentials to candidate-controlled code.
- **Sensitivity point:** Weak environment separation or identity matching can make deterministic output look valid while proving the wrong system state, leaking remote authority, or granting candidate bytes provenance they didn't earn.
- **Mitigation:** Release Pipeline runs from an immutable reviewed validation anchor and sends authoritative trust-anchor, validation-control signer, tested-source, base, build, corpus, run, and role identity directly to validation and aggregation. Before dispatch and during collection, it rejects a changed validation control surface or a tested-source delta outside the write boundary. Candidate commands receive no provenance authority; a trusted wrapper may upload only an untrusted handoff. The strict-containment role proves teardown before the wrapper uploads the handoff, while other hosted roles record bounded cleanup without claiming arbitrary-process containment. A fresh environment that never executes candidate bytes validates handoff identity and integrity and is the sole authority that authenticates provenance. A candidate survivor can spoil or deny the untrusted upload and fail the role, but can't enter that environment or gain its authority. Aggregation verifies fresh-seal provenance, destroys remote credentials, and runs the identified coordinator without network or ambient user state. It rejects unmanaged, candidate-controlled, out-of-boundary, missing, duplicated, unsealed, mismatched, stale, corrupt, or insufficiently isolated evidence. The later report state remains distinct from tested source.
