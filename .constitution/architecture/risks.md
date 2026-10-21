# Logical risks and technical debt

## Trust boundaries and threat notes

The following table summarizes the Stage 2 trust boundaries:

| Boundary | Dominant threats | Logical mitigation |
| :--- | :--- | :--- |
| Agent to Workspace | Tampering, path escape, denial of service | Treat every guest write as a proposal. Validate conformance, containment, size, and revision before authority changes. |
| Provider and Remote | Spoofing, tampering, information disclosure, denial of service | Use explicit authorization and privacy states. Validate incoming history and keep local work available. |
| Object Store | Tampering, information disclosure, denial of service | Refuse anonymous list, read, write, and delete access; verify Object identity; isolate credentials; and pause dependent history publication. |
| External Image Origin | Tampering, information disclosure, denial of service | Request only the external image reference from the opened Note, send no application credentials or other Note content, treat responses as untrusted, and degrade to an unavailable image without changing local state. |
| Platform secure storage | Information disclosure, elevation of privilege | Persist secrets only through Platform facilities and limit transient exposure. |
| Validation Environment to Evidence Aggregation | Spoofing, tampering, information disclosure, denial of service, elevation of privilege | Treat candidate placement and completion as trusted-workflow and runtime guards only. Keep candidates credential-free, treat their output as untrusted, and verify only the sealing environment's hosted origin through fresh non-executing seal provenance. For the cross-version compatibility handoff, bind the exact macOS 26 stage and producing seal through credential-free macOS 15 consumption and final aggregation. |
| Release Distribution | Tampering, spoofing | Publish common-matrix evidence, integrity data, and provenance for every artifact. |

Repudiation isn't a release claim because burlmd is a single-Writer local product and doesn't provide third-party authorship attestation.

## Risk 1: Canonical model projection cost

- **Risk:** A complete Canonical Note Model can exceed input-latency or memory constraints when every edit projects a large tree to Presentation.
- **Sensitivity point:** Projection granularity and source-range ownership affect responsiveness without changing the logical boundary.
- **Mitigation:** The canonical-model research must cover every selected syntax class, full and partial projections, source fidelity, and the 1,000-Note first-use profile before Stage 3 accepts a physical model. OD-04 remains open.

## Risk 2: Cross-platform path rejection

- **Risk:** A lowest-common-denominator path model can reject names that are valid on the current host or create unexpected disambiguation.
- **Sensitivity point:** Normalization and collision rules affect portability, Link stability, and adoption friction together.
- **Mitigation:** OD-05 remains open for the deterministic algorithm. Private Linux creates only portable paths from first use, and guest paths fail preflight before mutation. Linux evidence doesn't claim macOS runtime qualification.

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
- **Mitigation:** Private Linux evidence makes no supported-release claim. When public release work resumes, admit a system only after the complete installed-app matrix passes and OD-08 supplies the Linux baseline.

## Risk 9: Unsigned prerelease trust

- **Risk:** Unsigned `0.x` macOS artifacts create installation friction and a weaker trust signal.
- **Mitigation:** Publish integrity and provenance, label the artifact accurately, and provide Platform guidance. Signing becomes release-blocking at stability.

## Risk 10: Delivered-model migration

- **Risk:** Replacing the smaller rendering projection with the Canonical Note Model can regress delivered editing, selection, Links, or lifecycle behavior.
- **Mitigation:** Treat delivered A-F behavior as compatibility evidence. The AST Spike and final implementation contracts must preserve source fidelity and existing acceptance suites.

## Risk 11: External image request disclosure and hostile responses

- **Risk:** Automatically loading an external Markdown image discloses a request to its host and network observers. The host can also return invalid, unexpectedly large, or slow content.
- **Sensitivity point:** Request metadata and response handling can widen disclosure or let optional network content consume resources and degrade local editing.
- **Mitigation:** Request only the external image reference from the opened Note, send no other Note content, application credentials, or telemetry, and treat every response as untrusted. Failure produces an unavailable image state without rewriting source, importing bytes, or blocking local use. Stage 3 must set evidence-backed request and resource policies without weakening this boundary.

## Contaminated or misattributed validation evidence

- **Risk:** Validation can capture the Writer's device, accept evidence from another environment, or expose credentials to candidate-controlled code. A candidate can also imitate expected placement labels without proving hosted origin. For the cross-version compatibility handoff, a name-only stage can substitute different producer bytes before macOS 15 consumes them.
- **Sensitivity point:** Weak separation, identity matching, or lineage binding can make deterministic output prove the wrong system state. The same weakness can grant candidate bytes authority they didn't earn.
- **Mitigation:** Release Pipeline creates authoritative expected identity from an immutable reviewed validation anchor. It sends that identity directly to validation and aggregation. Trusted workflow fixes candidate placement and topology, and runtime observations confirm labels and completion. Aggregation treats those facts only as guards. They never authenticate hosted origin.

  Candidate commands remain credential-free and receive no provenance authority. Their output remains an untrusted handoff. The strict-containment role proves teardown before upload, and other hosted roles record bounded cleanup. A fresh environment validates handoff identity and integrity without executing candidate bytes. Its provenance alone cryptographically authenticates the sealing environment's hosted origin.

  For the cross-version compatibility handoff, the macOS 26 seal creates the compatibility stage after producer validation. It binds the exact stage identifier and integrity digest to its seal locator and provenance. The macOS 15 wrapper verifies that chain before credential-free, read-only consumption. The macOS 15 seal validates the lineage against the trusted wrapper record and preserves it. Aggregation rejects any absent, duplicate, substituted, expired, integrity-mismatched, unauthenticated, wrong-producer, wrong-role, wrong-run, wrong-seal, or consumer-unbound stage.

  Aggregation destroys acquisition credentials before it runs candidate-controlled coordination. The coordinator has verified read-only inputs, one writable output boundary, no network, and no ambient user state. Any isolation failure rejects the evidence. The later report state remains distinct from tested source.
