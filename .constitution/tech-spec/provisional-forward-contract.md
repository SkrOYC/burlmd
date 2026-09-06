# Provisional Forward Contract

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

The release control surface treats `scripts/prepare-compatibility-stage.sh`, `scripts/record-compatibility-stage-rest.sh`, `scripts/write-compatibility-stage-lineage.sh`, and `scripts/prepare-compatibility-stage-consumer.sh` as immutable trust-anchor controls. The first three helpers create, bind, and record lineage for the macOS 26 seal-owned stage. The fourth helper validates the lineage, removes credentials, and exposes only verified read-only members to the macOS 15 candidate. A byte or mode change in any helper requires reviewed trust-anchor rotation and evidence-only completion.

## Contract-scoped production authorization

The existing Epic G M0 production exceptions remain in force. `BURL-M015` and `BURL-M003` may also implement the reproducibility and managed-validation bootstrap in this TechSpec. `BURL-M003` owns the missing `scripts/check-generated-bindings.sh` file and must create the non-mutating checker before any bootstrap gate invokes it. The checker snapshots and backs up both generated surfaces, runs the provisional Flutter Rust Bridge `2.12.0` generator, compares file sets and bytes, reports stale output, and restores the exact precheck state before exit. Implementation must follow the accepted contract without importing or cherry-picking the coordinating Epic G branch. This authorization doesn't settle any open AST, path, asset, Git, observer, packaging, or release choice.

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
- PR #15 at `ee1a585e08a05ab07fffabf5b8968785dd2f42c6` treats candidate REST labels as hosted-origin proof and uses a separate name-addressed macOS staging job. The unmerged commit is implementation input only and must conform to ADR-019 and the version 33 raw contract.

These are tracked inputs to final reconciliation, not defects for a research Task to patch piecemeal.
