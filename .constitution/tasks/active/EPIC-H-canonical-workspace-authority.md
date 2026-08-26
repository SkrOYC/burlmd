---
version: v2.1.7
status: active
epic: H
---

# Epic H: Canonical Workspace authority and live monitoring

Replace the reduced Markdown projection and host-dependent path model with the canonical Core-owned Note and Workspace models. Establish burlmd's authority over guest input, conformance repair, cross-platform identity, and live Workspace observation.

AST-H001 and PATH-H002 execute first. Their reports feed measured upstream evolution. Every dependent ticket must be reconciled against the accepted final TechSpec before implementation; the ticket stays in this epic and adapts rather than being discarded.

**Capability coverage:** CAP-WS-05, CAP-WS-07, CAP-WS-08, CAP-WS-09, CAP-WS-10, CAP-WS-11, CAP-WS-12, CAP-PORT-03, CAP-PORT-05, and preservation of all delivered Note, lifecycle, Link, search, and conformance capabilities, including CAP-GRAPH-04.

**Total Effort:** 93 story points

#### AST-H001 Select the canonical source-backed Markdown AST foundation
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** None
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/ast/**`
  - `.constitution/spikes/SPK-AST-H001.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't touch production or active specifications)
- **Verification Command:** Run these exact commands on their named hosts: common: `cargo test --locked --manifest-path .constitution/prototypes/ast/Cargo.toml --all-targets`; Linux reference profile: `cargo run --locked --release --manifest-path .constitution/prototypes/ast/Cargo.toml -- probe --run-id linux-reference --role linux-reference-profile --profile linux-i5-8250u-16gib --output .constitution/prototypes/ast/runs/linux-reference.json --handoff-bundle .constitution/prototypes/ast/handoff/outbox/linux-reference.tar.zst --handoff-sha256 .constitution/prototypes/ast/handoff/outbox/linux-reference.sha256`; Apple Silicon macOS reference profile: `cargo run --locked --release --manifest-path .constitution/prototypes/ast/Cargo.toml -- probe --run-id macos-reference --role macos-reference-profile --profile macos-m1-8gib --output .constitution/prototypes/ast/runs/macos-reference.json --handoff-bundle .constitution/prototypes/ast/handoff/outbox/macos-reference.tar.zst --handoff-sha256 .constitution/prototypes/ast/handoff/outbox/macos-reference.sha256`; coordinator transfer: `mkdir -p .constitution/prototypes/ast/handoff/inbox && scp "$BURLMD_LINUX_HANDOFF_SOURCE/linux-reference.tar.zst" "$BURLMD_LINUX_HANDOFF_SOURCE/linux-reference.sha256" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-reference.tar.zst" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-reference.sha256" .constitution/prototypes/ast/handoff/inbox/`; coordinator aggregation: `cargo run --locked --release --manifest-path .constitution/prototypes/ast/Cargo.toml -- aggregate --contract .constitution/tech-spec/contracts/provisional-spikes.toml --schema .constitution/tech-spec/contracts/spike-result.schema.json --import-bundle .constitution/prototypes/ast/handoff/inbox/linux-reference.tar.zst --import-sha256 .constitution/prototypes/ast/handoff/inbox/linux-reference.sha256 --import-bundle .constitution/prototypes/ast/handoff/inbox/macos-reference.tar.zst --import-sha256 .constitution/prototypes/ast/handoff/inbox/macos-reference.sha256 --require-role linux-reference-profile --require-role macos-reference-profile --require-distinct-hosts 2 --output .constitution/prototypes/ast/results.json`.
- **Expected Success Output:** exit 0 with distinct reference-host runs and a finalized schema-valid result and Spike report
- **STOP Conditions:**
  - STOP if a candidate can't preserve untouched bytes or represent any required syntax/domain case.
  - STOP when the 3-day time box expires; record partial evidence without choosing by intuition.
- **Description:** Compare mdast, Comrak, and a complete `pulldown-cmark`-derived model using the full canonical-AST contract and corpus.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Every declared candidate and gate has attributed evidence for syntax, positions, source fidelity, Links, rendered selections, structural edits, and Suggestions. Distinct Linux and Apple Silicon macOS reference-host evidence covers performance and FFI projection cost. Aggregation rejects missing, duplicated, or same-host evidence and recommends one foundation or explicitly leaves the decision unresolved.
```

#### PATH-H002 Select the canonical cross-platform path algorithm
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** None
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/path/**`
  - `.constitution/spikes/SPK-PATH-H002.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't touch production or active specifications)
- **Verification Command:** Run these exact commands in order on their named hosts: common: `cargo test --locked --manifest-path .constitution/prototypes/path/Cargo.toml --all-targets`; Linux default filesystem: `cargo run --locked --release --manifest-path .constitution/prototypes/path/Cargo.toml -- probe --run-id linux-default-filesystem --role linux-default-filesystem --expected-os linux --expected-filesystem default --output .constitution/prototypes/path/runs/linux-default-filesystem.json --handoff-bundle .constitution/prototypes/path/handoff/outbox/linux-default-filesystem.tar.zst --handoff-sha256 .constitution/prototypes/path/handoff/outbox/linux-default-filesystem.sha256`; macOS default filesystem: `cargo run --locked --release --manifest-path .constitution/prototypes/path/Cargo.toml -- probe --run-id macos-default-filesystem --role macos-default-filesystem --expected-os macos --expected-filesystem default --output .constitution/prototypes/path/runs/macos-default-filesystem.json --handoff-bundle .constitution/prototypes/path/handoff/outbox/macos-default-filesystem.tar.zst --handoff-sha256 .constitution/prototypes/path/handoff/outbox/macos-default-filesystem.sha256`; coordinator transfer: `mkdir -p .constitution/prototypes/path/handoff/inbox && scp "$BURLMD_LINUX_HANDOFF_SOURCE/linux-default-filesystem.tar.zst" "$BURLMD_LINUX_HANDOFF_SOURCE/linux-default-filesystem.sha256" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-default-filesystem.tar.zst" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-default-filesystem.sha256" .constitution/prototypes/path/handoff/inbox/`; coordinator aggregation: `cargo run --locked --release --manifest-path .constitution/prototypes/path/Cargo.toml -- aggregate --contract .constitution/tech-spec/contracts/provisional-spikes.toml --schema .constitution/tech-spec/contracts/spike-result.schema.json --import-bundle .constitution/prototypes/path/handoff/inbox/linux-default-filesystem.tar.zst --import-sha256 .constitution/prototypes/path/handoff/inbox/linux-default-filesystem.sha256 --import-bundle .constitution/prototypes/path/handoff/inbox/macos-default-filesystem.tar.zst --import-sha256 .constitution/prototypes/path/handoff/inbox/macos-default-filesystem.sha256 --require-role linux-default-filesystem --require-role macos-default-filesystem --require-distinct-operating-systems 2 --output .constitution/prototypes/path/results.json`.
- **Expected Success Output:** exit 0 with distinct filesystem runs and a finalized schema-valid report
- **STOP Conditions:**
  - STOP if identity remains host-dependent or an accepted path can escape/alias the Workspace.
  - STOP when the 3-day time box expires; don't select a permanent format from incomplete platform evidence.
- **Description:** Compare the encoded-title and opaque-component candidates across Linux, default macOS, and Windows-compatible rules.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Generated and adversarial fixtures prove deterministic identity, collision freedom under all target equivalence rules, invertible ghost Links, safe case-only rename, and refusal of reserved, aliased, traversal, symlink, and submodule input. Aggregation verifies recorded host facts and rejects missing roles, duplicate operating systems, or an operating system that doesn't match its declared role.
```

#### MODEL-H003 Implement the canonical source-backed Note document
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** AST-H001
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/markdown/**`
  - `rust/src/draft.rs`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
- **Scope (Out-of-Scope Files):**
  - Flutter rendering and the derived index adapters owned by ADAPT-H004
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Expected Success Output:** exit 0 with canonical corpus, fidelity, and migration tests passing
- **STOP Conditions:**
  - STOP if the final TechSpec hasn't accepted AST-H001 or changes this ticket's physical model; reconcile scope and estimates first.
  - STOP if implementation keeps the old projection as a second authoritative AST.
- **Description:** Implement the accepted exhaustive Core document with original source, extended Markdown/domain nodes, exact ranges, editable identities, conformance state, and targeted splice/reparse coherence.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
For the canonical corpus, parsing yields the accepted exhaustive tree and exact ranges; every supported targeted edit reparses into one coherent document; untouched bytes remain identical; and no second authoritative Note representation exists.
```

#### ADAPT-H004 Replace parser, FFI, rendering, and index projections
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** MODEL-H003, CI-M003
- **Category:** Tech-Debt
- **Scope (In-Scope Files):**
  - `rust/src/api/**`
  - `rust/src/index/**`
  - `rust/src/workspace/**`
  - `lib/src/rust/**`
  - `lib/src/components/block_view.dart`
  - `lib/src/components/editor.dart`
  - `lib/src/providers/rust_api_provider.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Whole-tree Markdown serialization (forbidden on the edit/save path)
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh adapt-h004 && git diff --check`
- **Expected Success Output:** exit 0 with old `AstNode` authority removed and rendering parity preserved
- **STOP Conditions:**
  - STOP if the final FFI projection contract isn't accepted or if Flutter gains a second document model.
- **Description:** Replace the brownfield `AstNode` authority with adapters from the canonical document for Flutter rendering, interaction coordinates, Links, search/indexing, and conflict materialization.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Generated bindings expose only the accepted projection; rendering/index fixtures derive from the canonical document; every UI mutation returns through Core; source ranges retain Core authority; and the old pseudo-AST no longer drives editing or indexing.
```

#### PATH-H005 Implement canonical paths and recoverable migration
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** PATH-H002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/okf/concept_id.rs`
  - `rust/src/workspace/**`
  - `rust/src/index/**`
  - `rust/src/db/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Guest repair UI owned by REPAIR-H008
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Expected Success Output:** exit 0 with format, collision, migration, and rollback tests passing
- **STOP Conditions:**
  - STOP if the final TechSpec hasn't accepted PATH-H002 or migration would silently choose among collisions.
- **Description:** Implement canonical Note/Directory/Asset path validation and derivation, case-only rename, ghost-Link identity, and a previewable atomic migration from delivered title-verbatim paths.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Every burlmd-created path satisfies the accepted cross-platform grammar; migration preserves titles and bytes, rewrites identities/Links atomically, reports collisions for decision, and rolls back without partial publication on failure.
```

#### AUTH-H006 Establish the canonical Workspace authority tree
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ADAPT-H004, PATH-H005, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/draft.rs`
  - `rust/src/index/**`
  - `rust/src/api/ffi_api.rs`
- **Scope (Out-of-Scope Files):**
  - Object reachability implementation owned by Epic I
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with authority, containment, session, and Protected State invariants passing
- **STOP Conditions:**
  - STOP if Persistence, the index, a guest write, or Flutter can override Workspace Model authority.
- **Description:** Make one Workspace tree own Directories, canonical identities, authoritative Note sessions, lifecycle provenance, decision records, and Protected State roots while rejecting symlink/submodule/path escape input.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Exactly one Core Workspace tree decides every identity and open session; every mutation passes containment and conformance; derived/presentation state cannot override it; and all required local, history, reconciliation, and Consolidation roots are enumerable as Protected State.
```

#### PREFLIGHT-H007 Preflight and adopt an existing Workspace
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** AUTH-H006, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/workspace/bootstrap.rs`
  - `rust/src/index/scan.rs`
  - `rust/src/okf/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Repair mutation owned by REPAIR-H008
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh preflight-h007 && git diff --check`
- **Expected Success Output:** exit 0 with conforming inclusion, invalid inventory, and exclusion tests passing
- **STOP Conditions:**
  - STOP if preflight rewrites source, follows unsupported aliases, or admits an invalid Note into the editor/index.
- **Description:** Scan a selected directory without mutation, include conforming Notes, inventory invalid/noncanonical paths and Notes, preserve original bytes, and let the Writer exclude items explicitly before adoption.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a foreign directory contains conforming, invalid, aliased, and unsupported entries
When burlmd runs adoption preflight
Then only conforming contained Notes enter authoritative state
And every other entry is listed without changing a byte
And explicit exclusion preserves the original entry outside the editor and index
```

#### REPAIR-H008 Preview and apply conformance/path repairs
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** PREFLIGHT-H007, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/okf/**`
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Automatic or silent repair
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh repair-h008 && git diff --check`
- **Expected Success Output:** exit 0 with preview fidelity, confirm, rollback, and exclude tests passing
- **STOP Conditions:**
  - STOP if the Writer can't inspect original and proposed bytes or if repair changes unrelated content.
- **Description:** Produce previewed conformance/path repairs, preserve original bytes, apply only confirmed changes as one recoverable lifecycle outcome, and retain Exclude as a non-mutating choice.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Every repair preview identifies exact byte/path changes; confirmation applies only those changes atomically and records recovery history; rejection/exclusion preserves original bytes; failure restores the prior authoritative Workspace.
```

#### OBS-H009 Add debounced live Workspace observation
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** AUTH-H006, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/api/**`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Authority decisions owned by EXT-H010 and DECIDE-H011
- **Verification Command:** Linux reference host: `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && ./scripts/check-generated-bindings.sh && cargo run --release --manifest-path rust/Cargo.toml --bin workspace-observer-meter -- --run-id linux-reference --profile linux-i5-8250u-16gib --operations 100 --output target/observer-meters/linux-reference.json && git diff --check`; Apple Silicon macOS reference host: `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && ./scripts/check-generated-bindings.sh && cargo run --release --manifest-path rust/Cargo.toml --bin workspace-observer-meter -- --run-id macos-reference --profile macos-m1-8gib --operations 100 --output target/observer-meters/macos-reference.json && git diff --check`.
- **Expected Success Output:** exit 0 with burst/debounce/fallback and missed-event recovery tests passing
- **STOP Conditions:**
  - STOP if the final TechSpec hasn't pinned the observer adapter and polling fallback.
  - STOP if an event directly mutates authority without Core validation.
- **Description:** Convert Platform filesystem events into debounced candidate create/edit/rename/move/delete proposals with fallback polling and explicit Rescan recovery.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
The two exact host commands record 100 deterministic single and burst operations apiece on the PRD reference hardware and its supported filesystems. Each run produces one candidate set within the 2-second Goal, with no missed or duplicate history outcome and no direct authoritative mutation.
```

#### EXT-H010 Reconcile valid external Note and lifecycle changes
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** OBS-H009, PREFLIGHT-H007, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/index/**`
  - `rust/src/git/operations.rs`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/workspace_provider.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Dirty and invalid decisions owned by DECIDE-H011
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh ext-h010 && git diff --check`
- **Expected Success Output:** exit 0 with valid edit/create/rename/move/delete history and reload tests passing
- **STOP Conditions:**
  - STOP if rename provenance is uncertain; route it to a decision rather than guessing.
- **Description:** Validate clean external changes, update the authoritative tree and index, record local history, reload clean open Notes, and apply the same lifecycle/Link rules as Writer actions.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a clean open Workspace
When a guest performs a conforming create, edit, move, rename, or delete
Then burlmd validates it, records one local history outcome, updates authoritative state and the index, and reloads affected clean sessions
```

#### DECIDE-H011 Resolve dirty, stale, and invalid external changes
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** EXT-H010, REPAIR-H008, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `lib/src/providers/note_providers.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Git Suggestions and Remote reconciliation owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh decide-h011 && git diff --check`
- **Expected Success Output:** exit 0 with Compare/Keep/Load/Repair/Exclude and stale-revision tests passing
- **STOP Conditions:**
  - STOP if same-device changes become Suggestion nodes or either version is discarded before resolution.
- **Description:** Pause writes for dirty or invalid external changes, preserve last-known-good and guest bytes, offer the valid decisions, compare exact revisions, and require renewed input after a guest revision advances.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Both versions remain recoverable through every decision; the reviewed guest revision is compared again before application; stale input never applies; invalid input never replaces authoritative state; and no path produces a Git Suggestion.
```

#### RESCAN-H012 Retain Rescan as observation recovery
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** OBS-H009, DECIDE-H011
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/index/scan.rs`
  - `rust/src/workspace/**`
  - `lib/src/screens/workspace.dart`
  - `test/screens/workspace_rescan_test.dart`
- **Scope (Out-of-Scope Files):**
  - A second authority or alternate conformance path
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test && dart analyze && ./scripts/smoke-shot.sh rescan-h012 && git diff --check`
- **Expected Success Output:** exit 0 with observer-recovery and decision-preservation tests passing
- **STOP Conditions:**
  - STOP if Rescan bypasses live-monitor validation/decision rules or discards pending decisions.
- **Description:** Reconcile the delivered Rescan affordance with live observation as an explicit recovery path using the same candidate, validation, authority, and decision pipeline.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
After injected missed/coalesced events, Rescan converges the index and authoritative tree through the same validation rules, preserves drafts and pending decisions, and creates no duplicate history.
```
