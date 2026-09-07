# Provisional forward contract

## Purpose

This document prevents the research wave from becoming an accidental implementation wave. Structured PRD v2.0.5 and Architecture v2.1.2 are binding. The delivered v1.6.x physical contracts remain valid only for already-delivered behavior. Where they conflict with the forward constitution, the forward requirement is authoritative.

## Decision gates

| Forward area | Current physical status | Evidence or decision gate | Final Stage 3 output |
| :--- | :--- | :--- | :--- |
| Desktop preferences and Workspace sessions | Versioned JSON schemas specified for Epic G exceptions | No research Spike; implementation verifies Platform storage APIs and migration behavior | Device-preference schema, per-Workspace session schema, restore and serial-close FFI |
| Canonical Note and Workspace trees | Reduced `AstNode` projection | SPK-BURL-H001 | Canonical document schema, render projection, editing and indexing adapters, revised ADR-007 and FFI |
| Cross-platform paths and conformance repair | Title-verbatim host paths; invalid Notes currently indexed | SPK-BURL-H002 | Path grammar, migration/repair plan, preflight/live-monitor contracts, revised OKF contract and schema |
| Live Workspace monitoring | Manual Rescan only | Final verification of `notify` 8.2.0 and fallback behavior | Observer event contract, debouncing, revision checks, external-change decisions |
| Local history, undo, find, backlinks | Some planned FFI, incomplete production wiring | Canonical AST and path contracts first | Reconciled state and FFI contracts using authoritative Note sessions |
| Atomic Export | Brownfield contract permits partial output | AST, path, and asset closure contracts first | Copy and `.okf` schemas, stable-revision lease, collision and atomic publication contracts |
| Local assets and Object Store | No physical contract | SPK-BURL-I001 plus measured PRD/Architecture review | `BND-06` Local Asset Store model, `BND-11` transfer and verification contract, `BND-21` Object Store configuration and operation contract, identity and key format, hydration, and retention state machine; `BND-14` Provider and `BND-20` Remote don't own Object bytes |
| Private GitHub connection | Superseded OAuth redirect and marker-based merge | ADR-017 plus SPK-BURL-L001 | `BND-14` Provider device authorization, repository selection and provisioning, and eligible `BND-20` Remote location; `BND-20` authenticated history and ref contract; typed `BND-10` analysis and decision schemas; credential adapter; no Object transfer or storage responsibility |
| Releases and updates | Development builds plus committed Epic G headless capture | SPK-BURL-O001 for package choices; BURL-M003 for managed validation bootstrap | Credential-free candidate bundles with noncryptographic runtime guards, fresh-seal provenance, a seal-owned authenticated BURL-O001 compatibility stage, an attested canonical producer-lineage transport that binds producer-receipt freshness, accepted or rejected chain-verifying aggregation, update metadata, and the installed-app release matrix |
| Platform chrome | PR #11 presentation prototype leaked into production | Settled product decision | Remove preference/state/rendering/copy/tests and regenerate visual evidence; no replacement window-frame abstraction |

The release control surface treats the following scripts as immutable trust-anchor controls:

- `scripts/write-receipt-digest-observation.sh`
- `scripts/prepare-compatibility-stage.sh`
- `scripts/record-compatibility-stage-rest.sh`
- `scripts/write-compatibility-stage-lineage.sh`
- `scripts/prepare-compatibility-stage-consumer.sh`
- `scripts/validate-compatibility-stage-interface.sh`

Each reusable role workflow exposes its receipt upload artifact ID and bare digest through exact workflow outputs. The caller's fresh `receipt_digests` job maps all six values into one identity-bound transport without downloading candidate bytes.

Local collection resolves the transport's immutable artifact ID from the exact run inventory. It downloads the raw archive by ID and compares its SHA-256 with the canonical REST digest before extraction. The aggregate retains this check in `receiptDigestTransportArtifact`. Collection then validates the transport and checks each receipt ID and name against REST. It requires each receipt's REST digest to equal `sha256:` plus the transported action digest. The aggregate retains both receipt digest forms in `origin.sealingReceiptArtifact`. The sealing receipt remains version `2` and contains only pre-upload facts. Transport verification detects corruption or substitution but doesn't provide provenance independent of GitHub's artifact service.

Static workflow-shape fixtures use duplicate-aware source parsing to pin the exact ordered 26 producer-output keys, consumer string-input keys, and observable trusted mappings. They also pin every canonical hyphenated consumer input through its uppercase environment variable into the validator's ordered 26-field inventory. Before caller mapping, the macOS 26 output boundary normalizes the three producer sealing aliases for every ticket other than `BURL-O001`. It doesn't rely on omitted reusable-workflow input defaults.

Before acquisition or consumer processing, the macOS 15 trusted workflow wrapper invokes `scripts/validate-compatibility-stage-interface.sh`. Accepted nonempty `BURL-O001` values proceed to all three artifact downloads, offline verification, and `scripts/prepare-compatibility-stage-consumer.sh`. Accepted all-empty values for every other ticket skip only those compatibility steps, then continue the ordinary candidate path. The runtime shell can't validate source key shape or arbitrary value provenance. `scripts/prepare-compatibility-stage-consumer.sh` validates the result files. Downstream checks validate the values it consumes. The script then removes credentials and exposes only verified read-only members to the macOS 15 candidate.

In-workflow validators require literal `GITHUB_RUN_ATTEMPT=1` before relevant work. Local collection requires literal `--attempt 1` and REST `.run_attempt == 1` before acquisition. It re-fetches that exact REST object and requires numeric `.run_attempt == 1` immediately before atomically publishing an accepted report. Local collection does not inspect `GITHUB_RUN_ATTEMPT`. The launcher uses PR #15's `od -An -N16 -tx1 /dev/urandom | tr -d ' \n'` mechanism to generate each 128-bit nonce. It fails closed without a fallback unless the result is exactly 32 lowercase hexadecimal characters. A failed, cancelled, timed-out, or rejected report requires a fresh `workflow_dispatch` run with a new nonce and workflow run ID. GitHub UI and API reruns are forbidden. A recording fake API fixture proves that every path in the complete `trusted_control_paths` inventory makes no artifact-deletion request. Static fixtures require the exact 11-artifact ordinary and 13-artifact BURL-O001 inventories and `overwrite: false` on every upload. A byte or mode change in any helper requires reviewed trust-anchor rotation and evidence-only completion.

ADR-020 defines the assumed version `37` Linux closure view. The trusted launcher mounts each enumerated host store path read-only at the same `/nix/store` path inside Bubblewrap. No host store root, database, or daemon socket enters the namespace. A read-only manifest replaces the closure environment list. It contains every locked Flake input, derivation, requisite, and launcher root required after network removal. Each namespace disables nested user namespaces. `BURL-O001` alone loads a host-exported manifest subset into fresh private database state and writes private Nix outputs. The root, no-user-namespace build keeps `sandbox = false` and an empty `build-users-group =`.

The Linux capacity gate measures allocated bytes across the complete candidate and pre-upload finalization inventory. Initial admission requires at most 10,000,000,000 allocated bytes and at least 4,000,000,000 available bytes. Each phase instead requires a 1,000,000,000-byte safety floor. The wrapper brackets all 14 Linux build, probe, distribution, candidate-output-copy, manifest, bundle-compression, and upload-input-finalization phases. It retains disk-backed temporary bytes through each postcheck. The pinned upload action streams its ZIP in memory and creates no local archive.

The wrapper writes the version `1` capacity transcript to a preallocated protected root that isn't mounted for the candidate. It compares every append with independent parent state. The fresh seal validates the schema and semantics, then attests the unchanged transcript beside the role bundle. Aggregation consumes only this sealed member. A low-space or invalid run fails the candidate job before upload, so the successful-only protocol creates no accepted result.

The local corrected initial observation is 9,910,620,160 bytes, including sparse-store overhead under Nix 2.35.2. It leaves 4,089,379,840 bytes in the nominal profile. The prototype didn't run the complete Linux packaging or finalization sequence. Linux capacity is separate from the macOS archive gates. The standard `ubuntu-24.04` runner remains an assumed, fail-closed research choice until one complete managed run succeeds.

## Contract-scoped production authorization

The existing Epic G M0 production exceptions remain in force. `BURL-M015` and `BURL-M003` may also implement the reproducibility and managed-validation bootstrap in this TechSpec. Tasks v3.2.10 adopted version `35`. Stage 4 must adapt `BURL-M003` and `BURL-O001` directly to version `37` before implementation continues. The patch must add the capacity schema, protected evidence lifecycle, exact 29-record ordering, finalization phases, sparse database contexts, prefetched Flake requisites, and successful-only failure behavior. `BURL-M003` owns the missing `scripts/check-generated-bindings.sh` file and must create the non-mutating checker before any bootstrap gate invokes it. The checker snapshots and backs up both generated surfaces. It runs the provisional Flutter Rust Bridge `2.12.0` generator, compares file sets and bytes, and reports stale output. The checker restores the exact precheck state before exit. Implementation must follow the accepted contract without importing or cherry-picking the coordinating Epic G branch. This authorization doesn't settle any open AST, path, asset, Git, observer, packaging, or release choice.

Every other production ticket remains blocked until its own decision evidence lands. Product Requirements and Architecture are reviewed when that evidence changes an upstream assumption. Final Stage 3 then replaces that ticket's provisional physical contract, and Stage 4 adapts the ticket before implementation. A ticket doesn't wait for an unrelated Spike, and one completed Spike doesn't authorize neighboring production work.

Spike Tasks may read production code and fixtures but may write only within their prototype roots and report records. Final Stage 3 still owns the reconciled FFI, schemas, bill of materials, repository layout, error taxonomy, and exact implementation commands for each affected contract.

## Known brownfield contradictions

- `ffi_api.rs` describes `AstNode` as a render projection, while the forward model requires a canonical extended AST.
- The OAuth redirect and PKCE surfaces require a client-secret-era design superseded by GitHub App device flow.
- The OKF bundle derives filenames verbatim from titles, which OD-05 explicitly reopens.
- The schema and open-Workspace comments tolerate and index invalid Notes, while the authority model now excludes them until Repair or Exclude.
- `export_workspace` describes partial, non-gating output; forward Export must be object-complete and atomic.
- Git Suggestions assume marker-bearing content conflicts and don't cover Lifecycle or Asset Decisions.
- No physical model exists for Workspace observation, S3-compatible object configuration, asset reachability, or release metadata.
- PR #15 at `9719259f1ecee819af96c98c2be210156f198343` copies a 5.48 GB Linux closure into a private store. The conservative prebuild allocation reaches 15,382,421,504 bytes before build outputs, which exceeds the standard runner profile. The unmerged commit is implementation input only and must conform to ADR-019, ADR-020, and raw contract version `37`.

These are tracked inputs to final reconciliation, not defects for a research Task to patch piecemeal.
