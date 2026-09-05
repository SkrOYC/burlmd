# Provisional Forward Contract

## Purpose

This document prevents the research wave from becoming an accidental implementation wave. Structured PRD v2.0.0 and Architecture v2.0.1 are binding. The delivered v1.6.x physical contracts remain valid only for already-delivered behavior. Where they conflict with the forward constitution, the forward requirement is authoritative.

## Decision gates

| Forward area | Current physical status | Evidence or decision gate | Final Stage 3 output |
| :--- | :--- | :--- | :--- |
| Desktop preferences and Workspace sessions | Versioned JSON schemas specified for Epic G exceptions | No research Spike; implementation verifies Platform storage APIs and migration behavior | Device-preference schema, per-Workspace session schema, restore and serial-close FFI |
| Canonical Note and Workspace trees | Reduced `AstNode` projection | SPK-BURL-H001 | Canonical document schema, render projection, editing and indexing adapters, revised ADR-007 and FFI |
| Cross-platform paths and conformance repair | Title-verbatim host paths; invalid Notes currently indexed | SPK-BURL-H002 | Path grammar, migration/repair plan, preflight/live-monitor contracts, revised OKF contract and schema |
| Live Workspace monitoring | Manual Rescan only | Final verification of `notify` 8.2.0 and fallback behavior | Observer event contract, debouncing, revision checks, external-change decisions |
| Local history, undo, find, backlinks | Some planned FFI, incomplete production wiring | Canonical AST and path contracts first | Reconciled state and FFI contracts using authoritative Note sessions |
| Atomic Export | Brownfield contract permits partial output | AST, path, and asset closure contracts first | Copy and `.okf` schemas, stable-revision lease, collision and atomic publication contracts |
| Local assets and Object Store | No physical contract | SPK-BURL-I001 plus measured PRD/Architecture review | Asset manifest schema, identity/hash/key format, secure configuration schema, hydration and retention state machine |
| Private GitHub Remote | Old OAuth redirect and marker-centric merge | ADR-017 plus SPK-BURL-L001 | Device-flow FFI, GitHub API contract, typed analysis and decision schemas, credential adapter |
| Releases and updates | Development builds plus committed Epic G headless capture | SPK-BURL-O001 for package choices; BURL-M003 for managed validation bootstrap | Untrusted candidate bundles, fresh-job sealed role bundles, role-specific workflow signers, accepted or rejected authenticated aggregation, update metadata, installed-app release matrix |
| Platform chrome | PR #11 presentation prototype leaked into production | Settled product decision | Remove preference/state/rendering/copy/tests and regenerate visual evidence; no replacement window-frame abstraction |

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

These are tracked inputs to final reconciliation, not defects for a research Task to patch piecemeal.
