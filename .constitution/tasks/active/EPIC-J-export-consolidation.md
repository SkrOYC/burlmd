---
version: v2.1.7
status: active
epic: J
---

# Epic J: Export and consolidation

Provide complete atomic exit paths and a safe way to bring another local Workspace into the active one without merging unrelated histories or mutating the source.

**Capability coverage:** CAP-PORT-02, CAP-PORT-06, CAP-PORT-07, CAP-PORT-08, CAP-SYNC-08.

**Total Effort:** 47 story points

#### EXPORT-J001 Coordinate one stable Export revision
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** CLOSE-G005, DECIDE-H011, RECOVER-I006, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Destination serialization owned by COPY-J002 and ARCHIVE-J003
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with flush, stable-revision, decision-block, and session-preservation tests passing
- **STOP Conditions:**
  - STOP if Export retires open sessions, reads across revisions, or proceeds with an unresolved external-file decision.
- **Description:** Acquire a stable Workspace Export lease, flush every open Note through normal durability without closing it, stop on unresolved authority, derive the complete Note/Object closure, and release without mutating the Workspace.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Concurrent mutation tests prove every exported path and Object belongs to one revision; all drafts are flushed; no session retires; unresolved external decisions stop before destination writes; and the authoritative Workspace remains unchanged.
```

#### COPY-J002 Publish an atomic plain-copy Export
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** EXPORT-J001, TRANSFER-I005, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/export/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - HTML output and Publishing
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with hydration, verification, nonempty-destination refusal, atomic rename, and cleanup tests passing
- **STOP Conditions:**
  - STOP if any referenced Object is missing/unverified or partial output becomes visible at the selected destination.
- **Description:** Hydrate and verify the stable closure into a temporary sibling directory, validate the bundle, refuse nonempty destinations, and publish only by final atomic rename.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Success exposes one complete byte-preserved copy with all referenced Objects and reports every nonconforming Note without gating Export or repairing it. Every injected failure leaves the selected destination absent/unchanged and removes or reports only the bounded temporary sibling; a nonempty destination is never merged.
```

#### ARCHIVE-J003 Publish an atomic Bundle Archive
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** EXPORT-J001, TRANSFER-I005, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/export/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Workspace-wide or single-Note HTML export
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with archive round-trip, replacement confirmation, atomic publication, and failure cleanup tests passing
- **STOP Conditions:**
  - STOP if archive replacement occurs without confirmation or if extraction can't reproduce the verified stable closure.
- **Description:** Serialize the stable closure into the final `.okf` Bundle Archive contract, verify round-trip completeness, require replacement confirmation, and atomically publish from a temporary sibling.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Schema and round-trip tests reproduce every Note, Directory, Link, manifest, and referenced Object byte. Existing archives survive refusal/failure, replacement requires explicit confirmation, and no partial archive is exposed as success.
```

#### CONS-J004 Plan non-destructive Workspace Consolidation
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** REPAIR-H008, ADOPT-I009, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Git history merging and source-Workspace mutation
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with read-only planning, Asset inventory, and exact collision records passing
- **STOP Conditions:**
  - STOP if planning writes either Workspace or treats unrelated histories as mergeable.
- **Description:** Validate a source Workspace, inventory Notes/Assets, identify nonconflicting migrations and exact identity collisions, and return a stable decision plan without changing either side.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Planning is byte-for-byte read-only, includes conforming Notes and portable Assets, reports invalid inputs, keys every collision by stable identity and revision, and rejects any request to merge histories.
```

#### COLLIDE-J005 Apply Consolidation and collision decisions atomically
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** CONS-J004, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/workspace/**`
  - `rust/src/assets/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Source-Workspace writes
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with stale-plan refusal, keep-local/incoming/both, Link rewrite, Asset copy, rollback, and source-identity tests passing
- **STOP Conditions:**
  - STOP if the plan inputs changed, a decision is missing, or the source Workspace would be modified.
- **Description:** Revalidate the plan, migrate nonconflicting Notes and Assets with fresh history, apply every explicit collision choice, rewrite affected Links, and publish one recoverable destination outcome.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
The source Workspace remains byte-identical; stale inputs refuse before mutation; every collision has one explicit choice; Keep Both derives a valid canonical identity and rewrites Links; Objects verify; and injected failure rolls the active Workspace back completely.
```

#### PORT-J006 Integrate plain-copy and archive Export surfaces
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** COPY-J002, ARCHIVE-J003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/**`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/screens/workspace.dart`
  - `lib/l10n/**`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Consolidation UI, HTML output, Publishing, and history diff viewer
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test && dart analyze && ./scripts/smoke-shot.sh port-j006 && git diff --check`
- **Expected Success Output:** exit 0 with Export destination, replacement confirmation, progress, failure, keyboard, and Semantics tests passing
- **STOP Conditions:**
  - STOP if the UI presents partial Export output as success or parses error strings instead of typed Core state.
- **Description:** Add accessible plain-copy and Bundle Archive Export workflows over typed Core state, including destination rules, replacement confirmation, progress, terminal success, nonconformance reporting, and recoverable failures.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a Workspace with open Notes, Assets, and possible nonconforming guest Notes
When the Writer completes plain-copy or archive Export using keyboard or pointer
Then every required flush, confirmation, verification, report, and atomic publication occurs
And failure reports a typed recovery state without claiming success
```

#### CONSUI-J007 Integrate the Consolidation decision surface
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** COLLIDE-J005
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/**`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/screens/workspace.dart`
  - `lib/l10n/**`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Export UI, automatic collision choices, and history diff viewer
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test && dart analyze && ./scripts/smoke-shot.sh consui-j007 && git diff --check`
- **Expected Success Output:** exit 0 with source selection, plan, collision decision, progress, rollback, keyboard, and Semantics tests passing
- **STOP Conditions:**
  - STOP if Flutter constructs collision outcomes, mutates the source Workspace, or claims success before Core publishes the atomic result.
- **Description:** Present the typed Consolidation plan and explicit collision choices, collect Writer decisions accessibly, and surface authoritative progress, success, rollback, and retry outcomes.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a source Workspace produces typed collisions during Consolidation planning
When the Writer resolves every choice using keyboard or pointer
Then the UI submits only typed decisions to Core
And the source remains unchanged
And success appears only after atomic publication
And a failed attempt exposes a recoverable typed outcome
```
