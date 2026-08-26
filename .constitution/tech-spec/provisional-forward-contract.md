# Provisional Forward Contract

## Purpose

This document prevents the research wave from becoming an accidental implementation wave. PRD v1.3.5 and Architecture v1.4.11 are binding. The delivered v1.6.x physical contracts remain valid only for already-delivered behavior. Where they conflict with the forward constitution, the forward requirement is authoritative and production work waits for final Stage 3.

## Decision gates

| Forward area | Current physical status | Evidence or decision gate | Final Stage 3 output |
| :--- | :--- | :--- | :--- |
| Desktop preferences and Workspace sessions | No durable forward schema | No research Spike; Platform storage APIs and migration need final verification | Device-preference schema, per-Workspace session schema, restore and serial-close FFI |
| Canonical Note and Workspace trees | Reduced `AstNode` projection | SPK-AST-H001 | Canonical document schema, render projection, editing and indexing adapters, revised ADR-007 and FFI |
| Cross-platform paths and conformance repair | Title-verbatim host paths; invalid Notes currently indexed | SPK-PATH-H002 | Path grammar, migration/repair plan, preflight/live-monitor contracts, revised OKF contract and schema |
| Live Workspace monitoring | Manual Rescan only | Final verification of `notify` 8.2.0 and fallback behavior | Observer event contract, debouncing, revision checks, external-change decisions |
| Local history, undo, find, backlinks | Some planned FFI, incomplete production wiring | Canonical AST and path contracts first | Reconciled state and FFI contracts using authoritative Note sessions |
| Atomic Export | Brownfield contract permits partial output | AST, path, and asset closure contracts first | Copy and `.okf` schemas, stable-revision lease, collision and atomic publication contracts |
| Local assets and Object Store | No physical contract | SPK-ASSET-I001 plus measured PRD/Architecture review | Asset manifest schema, identity/hash/key format, secure configuration schema, hydration and retention state machine |
| Private GitHub Remote | Old OAuth redirect and marker-centric merge | ADR-017 plus SPK-GIT-L001 | Device-flow FFI, GitHub API contract, typed analysis and decision schemas, credential adapter |
| Releases and updates | Development builds only | SPK-PKG-M001 plus measured Linux baseline | Artifact manifests, build commands, update-metadata contract, installed-app release matrix |
| Platform chrome | PR #11 presentation prototype leaked into production | Settled product decision | Remove preference/state/rendering/copy/tests and regenerate visual evidence; no replacement window-frame abstraction |

## Production implementation stop

Only the five Spikes declared in `contracts/provisional-spikes.toml` are executable while this provisional contract remains current. Stage 4 may plan the complete downstream epic and ticket set now, but every Spike-dependent implementation ticket must depend on its owning Spike and stop until measured Product Requirements, Architecture review, and final Stage 3 reconcile its contract. Spike Tasks may read production code and fixtures but may write only within their prototype roots and report records. Final Stage 3 replaces every proposed ADR and reconciles the FFI, schemas, bill of materials, repository layout, error taxonomy, and exact implementation verification commands; Stage 4 then adapts affected tickets without discarding the roadmap.

## Known brownfield contradictions

- `ffi_api.rs` describes `AstNode` as a render projection, while the forward model requires a canonical extended AST.
- The OAuth redirect and PKCE surfaces require a client-secret-era design superseded by GitHub App device flow.
- The OKF bundle derives filenames verbatim from titles, which OD-05 explicitly reopens.
- The schema and open-Workspace comments tolerate and index invalid Notes, while the authority model now excludes them until Repair or Exclude.
- `export_workspace` describes partial, non-gating output; forward Export must be object-complete and atomic.
- Git Suggestions assume marker-bearing content conflicts and don't cover Lifecycle or Asset Decisions.
- No physical model exists for Workspace observation, application session state, S3-compatible object configuration, asset reachability, or release metadata.

These are tracked inputs to final reconciliation, not defects for a research Task to patch piecemeal.
