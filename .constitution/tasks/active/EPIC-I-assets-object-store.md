---
version: v2.1.11
status: active
epic: I
---

# Epic I: Assets and Object Store

Deliver inline images through a portable Local Asset Store and a first-class, user-controlled S3-compatible Object Store. ASSET-I001 runs first; dependent tickets adapt to the measured manifest, client, limits, and repository-health contract accepted by the upstream evolution pass.

**Capability coverage:** CAP-EDIT-06, CAP-ASSET-01, CAP-ASSET-02, CAP-ASSET-03, CAP-ASSET-04, CAP-ASSET-05, CAP-ASSET-06, CAP-ASSET-08, CAP-ASSET-09, CAP-ASSET-10, CAP-ASSET-11, CAP-ASSET-12.

**Total Effort:** 98 story points

#### ASSET-I001 Measure the hybrid Asset and Object Store contract
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** None
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/assets/**`
  - `.constitution/spikes/SPK-ASSET-I001.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't touch production or active specifications)
- **Verification Command:** Run these exact commands in order on their named hosts: common: `cargo test --locked --manifest-path .constitution/prototypes/assets/Cargo.toml --all-targets`; Linux reference profile: `cargo run --locked --release --manifest-path .constitution/prototypes/assets/Cargo.toml -- probe --run-id linux-reference --role linux-reference-profile --expected-os linux --expected-arch x86_64 --profile linux-i5-8250u-16gib --fixture-dir .constitution/prototypes/assets/fixtures --output .constitution/prototypes/assets/runs/linux-reference.json --handoff-bundle .constitution/prototypes/assets/handoff/outbox/linux-reference.tar.zst --handoff-sha256 .constitution/prototypes/assets/handoff/outbox/linux-reference.sha256`; macOS reference profile: `cargo run --locked --release --manifest-path .constitution/prototypes/assets/Cargo.toml -- probe --run-id macos-reference --role macos-reference-profile --expected-os macos --expected-arch aarch64 --profile macos-m1-8gib --fixture-dir .constitution/prototypes/assets/fixtures --output .constitution/prototypes/assets/runs/macos-reference.json --handoff-bundle .constitution/prototypes/assets/handoff/outbox/macos-reference.tar.zst --handoff-sha256 .constitution/prototypes/assets/handoff/outbox/macos-reference.sha256`; coordinator transfer: `mkdir -p .constitution/prototypes/assets/handoff/inbox && scp "$BURLMD_LINUX_HANDOFF_SOURCE/linux-reference.tar.zst" "$BURLMD_LINUX_HANDOFF_SOURCE/linux-reference.sha256" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-reference.tar.zst" "$BURLMD_MACOS_HANDOFF_SOURCE/macos-reference.sha256" .constitution/prototypes/assets/handoff/inbox/`; coordinator aggregation: `cargo run --locked --release --manifest-path .constitution/prototypes/assets/Cargo.toml -- aggregate --contract .constitution/tech-spec/contracts/provisional-spikes.toml --schema .constitution/tech-spec/contracts/spike-result.schema.json --import-bundle .constitution/prototypes/assets/handoff/inbox/linux-reference.tar.zst --import-sha256 .constitution/prototypes/assets/handoff/inbox/linux-reference.sha256 --import-bundle .constitution/prototypes/assets/handoff/inbox/macos-reference.tar.zst --import-sha256 .constitution/prototypes/assets/handoff/inbox/macos-reference.sha256 --require-role linux-reference-profile --require-role macos-reference-profile --require-distinct-hosts 2 --require-distinct-operating-systems 2 --require-role-os linux-reference-profile=linux --require-role-arch linux-reference-profile=x86_64 --require-role-profile linux-reference-profile=linux-i5-8250u-16gib --require-role-os macos-reference-profile=macos --require-role-arch macos-reference-profile=aarch64 --require-role-profile macos-reference-profile=macos-m1-8gib --output .constitution/prototypes/assets/results.json`.
- **Expected Success Output:** exit 0 with a finalized schema-valid report and explicit OD-06/OD-07 disposition
- **STOP Conditions:**
  - STOP if credentials would enter committed files or evidence.
  - STOP if a result weakens Protected State or deletion safety.
  - STOP at the 3-day time box and leave thresholds unresolved when full meters aren't established.
- **Description:** Compare the accepted S3 client candidates and measure content identity, immutable manifests, image limits, hydration, reachability, retention, and repository health.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
Candidate-attributed results cover both reference profiles, all declared gates, exact tool/service configurations without secrets, UI Responsiveness and Idle Memory disposition, and a recommendation for client and thresholds or an explicit unresolved outcome. The result tool captures CPU, core count, memory, storage, graphics, display, power, and thermal facts from system APIs. Aggregation matches them to the PRD profiles and rejects a missing role, duplicate host, duplicate operating system, or role/profile mismatch.
```

#### STORE-I002 Implement the Local Asset Store and immutable manifest
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ASSET-I001, AUTH-H006, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/workspace/**`
  - `rust/src/git/operations.rs`
  - `rust/src/api/ffi_api.rs`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Remote transfer and mutable device state owned by later tickets
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && ./scripts/check-generated-bindings.sh && git diff --check`
- **Expected Success Output:** exit 0 with identity, dedupe, manifest, atomic-copy, containment, and Git-payload-exclusion tests passing
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted ASSET-I001 or mutable device state enters the Git manifest.
  - STOP if commit safety depends on a writable, readable, present, or trustworthy `.gitignore` file.
- **Description:** Add the accepted content identity, canonical `assets/objects/` payload path, immutable textual manifest, atomic imported-byte adoption, deduplication, and local verification state. Enforce a Core commit-path exclusion for `assets/objects/**` before staging, independent of ignore files and ambient Git configuration. Stage only authoritative Note and textual-manifest paths selected by the operation.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Byte-identical imports share one Object; distinct bytes never collide; active bytes are copied inside the contained Workspace before reference; the manifest contains only accepted immutable facts; and device-local hydration/verification state never enters Git. Missing, modified, unreadable, or symlinked `.gitignore` fixtures can't place payload bytes in the index or a commit. Existing tracked payload paths, broad commit requests, and adversarial path aliases fail closed before staging, while the textual manifest remains committable.
```

#### IMAGE-I003 Complete inline image import and rendering
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STORE-I002, ADAPT-H004, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/markdown/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/editor.dart`
  - `lib/src/components/block_view.dart`
  - `lib/src/providers/note_providers.dart`
  - `pubspec.yaml`
  - `pubspec.lock`
  - `linux/**`
  - `macos/**`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Object Store transfer
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh image-i003 && git diff --check`
- **Expected Success Output:** exit 0 with picker, clipboard, drag/drop, refusal, and inline-render tests passing
- **STOP Conditions:**
  - STOP if import references the source file in place, bypasses the accepted size/pixel limits, or lets Flutter invent Object identity.
- **Description:** Import images from file selection, clipboard, and drag/drop into the Local Asset Store, splice a standard bundle-absolute Markdown reference, and render verified bytes inline with accessible fallbacks.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a supported image from each import channel
When the Writer inserts it
Then Core adopts and verifies the bytes before writing a portable Markdown reference
And the image renders offline
And oversized, unsafe, or invalid input is refused without changing the Note
```

#### OBJECT-I004 Connect and validate a private S3-compatible Object Store
- **Type:** Security
- **Effort:** 8
- **Dependencies:** ASSET-I001, CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/security/**`
  - `rust/src/api/ffi_api.rs`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Bucket-policy mutation, cloud-account provisioning, or a burlmd-operated bucket
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh object-i004 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with protocol, credential-isolation, privacy, and probe cleanup tests passing
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted the client/configuration contract.
  - STOP if anonymous read can't be disproved or credentials leave Platform secure storage.
- **Description:** Collect endpoint, region, bucket, prefix, and narrowly scoped credentials; store secrets securely; validate list/read/write/delete with a disposable Object; reject anonymously readable storage without mutating policy.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
AWS and safe non-AWS S3-compatible contract fixtures prove endpoint/addressing behavior, disposable list/read/write/delete, cleanup, anonymous-read refusal, secret redaction, and no credential persistence in Workspace, Dart state, Git, or diagnostics.
```

#### TRANSFER-I005 Upload, verify, and progressively hydrate Objects
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STORE-I002, OBJECT-I004, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/assets/**`
  - `rust/src/sync/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Git history publication owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh transfer-i005 && git diff --check`
- **Expected Success Output:** exit 0 with verified-before-publish obligations and progressive/offline hydration tests passing
- **STOP Conditions:**
  - STOP if an Object is marked available before hash verification or transfers block local Note editing.
- **Description:** Upload content-addressed Objects, verify remote bytes, prioritize active hydration on another device, retain offline Note work, and persist resumable transfer state outside the manifest.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
No history-publication obligation completes before every referenced Object verifies remotely; hydration exposes only verified bytes, prioritizes active Assets, resumes after interruption, and never blocks local Note editing while offline.
```

#### RECOVER-I006 Resolve missing or corrupt Objects safely
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** TRANSFER-I005, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/object_store/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Remote reconciliation Asset Decisions owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh recover-i006 && git diff --check`
- **Expected Success Output:** exit 0 with Retry/Repair/Replace/Remove and pause/resume tests passing
- **STOP Conditions:**
  - STOP if recovery discards a verified copy, silently removes a reference, or resumes affected sync before verification.
- **Description:** Detect missing/corrupt bytes, preserve verified copies, pause affected synchronization, and expose only valid Retry, Repair from local, Choose replacement, or Remove reference actions.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given an active Object is missing or fails content verification
When recovery state is shown
Then all verified copies remain preserved and affected synchronization pauses
And only valid recovery actions are offered
And resume occurs only after the resulting Object verifies
```

#### RETAIN-I007 Enforce Protected State reachability and retention
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** TRANSFER-I005, AUTH-H006
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/git/operations.rs`
  - `rust/src/object_store/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Pruning Git history
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Expected Success Output:** exit 0 with generated-history reachability, 30-day local cache eviction, and remote-deletion refusal simulations passing
- **STOP Conditions:**
  - STOP if age overrides reachability, cache eviction lacks a verified remote copy, or any path can delete an authoritative Object Store byte.
- **Description:** Derive Object reachability from canonical AST references across every Protected State, evict only verified inactive local cache copies after 30 days, and prohibit authoritative Object Store deletion during `0.x`.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Property tests generate arbitrary advertised refs, local or unpublished history, reconciliation, Consolidation, and unreachable Objects. Every reachable Object survives regardless of age. Local eviction requires a verified remote copy, 30 unused days, and no active offline need. No production path issues delete for an authoritative Object; delete remains limited to disposable connection probes.
```

#### ROTATE-I008 Rotate Object Store credentials atomically
- **Type:** Security
- **Effort:** 5
- **Dependencies:** TRANSFER-I005, CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/security/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Replacement Object Store migration and full-local detach
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh rotate-i008 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with credential preflight, atomic replacement, revocation, and rollback tests passing
- **STOP Conditions:**
  - STOP if old credentials are removed before the replacement authenticates and verifies existing Objects.
- **Description:** Preflight replacement Object Store credentials, atomically publish the verified credential reference, remove the superseded secret from local Secure Storage only after success, instruct the Writer to revoke it at the storage provider, and preserve the working connection after any failure.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Fault injection proves the active credential reference is always either the verified old secret or verified replacement; no credential reaches Workspace state, logs, or history; failure leaves the original connection usable.
```

#### MIGRATE-I011 Migrate protected Objects to a replacement store
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** TRANSFER-I005, RETAIN-I007, REFS-L010, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/sync/**`
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Credential rotation and S3-only Workspaces
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh migrate-i011 && git diff --check`
- **Expected Success Output:** exit 0 with durable intent, dual-write, baseline/delta copy, revision-bound cutover, resume, and rollback tests passing
- **STOP Conditions:**
  - STOP if the old store can retire before every Protected Object is verified in the replacement.
  - STOP if any device can publish during migration without first verifying each new Object in both stores, or if a device without replacement credentials can publish after cutover.
  - STOP if a Remote-detached Workspace with prior published history attempts replacement migration; reconnect for coordinated migration or hydrate and remove the retained store.
- **Description:** Publish a durable migration intent with non-secret old/new store identities. While the intent is active, every connected device dual-writes and verifies new Objects before publication; devices without replacement credentials pause publication but keep local use. Copy and verify the baseline Protected Object closure, repeatedly reconcile deltas against complete advertised refs and local publication state, then publish a compare-and-swap cutover bound to the migration epoch, Workspace revision, and Remote-ref inventory. Keep the old store as a readable fallback because authoritative deletion is disabled during `0.x`.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Concurrency and interruption tests start publication before, during, and after baseline copy. Every publication under the migration intent verifies its Objects in both stores. Delta reconciliation reaches the exact bound Workspace and Remote inventories before compare-and-swap cutover. A stale epoch, revision, ref inventory, missing replacement credential, or failed verification blocks publication or cutover without changing authority. Restart resumes durable progress; successful cutover makes the replacement authoritative and retains the old store as readable fallback without changing Object identities.
```

#### DETACH-I012 Prepare every protected Object for full-local transition
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** RETAIN-I007, RECOVER-I006, REFS-L010, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Remote/Object Store attachment mutation owned by DETACH-K006 and S3-only Workspace operation
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh detach-i012 && git diff --check`
- **Expected Success Output:** exit 0 with attached-Remote revalidation, detached-Remote local hydration, readiness-token, refusal, and restart tests passing
- **STOP Conditions:**
  - STOP if readiness can be issued while any Protected Object is missing, unverified, or based on stale reachability.
  - STOP if attached-Remote preparation can't authenticate online and re-enumerate all published Remote refs immediately before closure computation.
  - STOP if `LocalWithObjectStore` preparation consults a detached Remote, omits any locally protected state, or can remove the retained store before every protected byte verifies locally.
- **Description:** Support two explicit preparation modes. With an attached Remote, authenticate online, re-enumerate every published Remote ref, compute the complete Protected Object closure, and bind readiness to the ref inventory and Workspace revision. In `LocalWithObjectStore`, derive the closure from current state, retained or unpublished local history, pending reconciliation, and Consolidation without consulting the detached Remote; hydrate and verify every byte, then bind readiness to the complete local revision. Neither mode changes an external connection.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a Workspace has an attached Remote and protected Objects that may not be local
When burlmd prepares a full-local transition while online and authenticated
Then it freshly enumerates every published Remote ref
And hydrates and verifies every protected Object reachable from that authority
And returns readiness bound to the Remote-ref inventory and Workspace revision
And leaves both external connections unchanged

Given a Workspace is in LocalWithObjectStore after offline Remote detach
When the Writer prepares removal of the retained Object Store
Then burlmd derives every locally Protected State without consulting the detached Remote
And hydrates and verifies every protected Object
And returns readiness bound to the complete local revision
And restart preserves prepared bytes but requires renewed readiness after local revision advance
```

#### UNLINK-I013 Detach an unused Object Store without detaching the Remote
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** OBJECT-I004, RETAIN-I007, REFS-L010, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/object_store/**`
  - `rust/src/security/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Full-local Remote detach owned by DETACH-I012 and DETACH-K006
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh unlink-i013 && git diff --check`
- **Expected Success Output:** exit 0 with empty-protected-set, stale-enumeration refusal, credential removal, Remote-preservation, and reconnect tests passing
- **STOP Conditions:**
  - STOP if published history is incomplete, any Protected Object exists, the enumerated revision has advanced, or Object Store detach can alter Remote attachment/history.
- **Description:** Enumerate every Protected State through the complete published-ref inventory, prove the protected Object set is empty at compare-and-swap time, remove only the Object Store configuration and local credential, keep the private GitHub Remote attached, and permit later Object Store reconnection.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Property and interruption tests cover current state, retained or unpublished local history, every fetchable ref from unfiltered Remote advertisement, pending reconciliation, and Consolidation. Detach succeeds only for a revision-bound empty protected set; it removes the local Object Store credential and configuration, preserves the exact Remote and Git history, and refuses stale, incomplete, unclassified, unfetchable, or nonempty enumeration without changing either connection.
```

#### ADOPT-I009 Inventory and migrate foreign Workspace Assets
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STORE-I002, PREFLIGHT-H007, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/workspace/bootstrap.rs`
  - `rust/src/markdown/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Silent or destructive cleanup of unreferenced files
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh adopt-i009 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with inventory, preview, atomic migration, rollback, and unreferenced-file tests passing
- **STOP Conditions:**
  - STOP if preflight changes bytes or migration guesses among missing/ambiguous references.
- **Description:** Inventory guest Asset references, report missing/ambiguous/oversized/nonconforming inputs, preview canonical migration, adopt referenced bytes atomically, and leave unreferenced files available for review.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a foreign Workspace contains ordinary Asset paths and unrelated files
When preflight and confirmed migration run
Then every issue is reported before mutation
And referenced bytes and Markdown references migrate as one recoverable outcome
And unreferenced files remain unchanged for review
```

#### ASSET-I010 Integrate Asset state with restore, Consolidation, and shell status
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** IMAGE-I003, RECOVER-I006, ROTATE-I008, MIGRATE-I011, DETACH-I012, UNLINK-I013, ADOPT-I009, HIST-G010, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/assets/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `lib/src/providers/**`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Remote Asset Decisions owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh asset-i010 && git diff --check`
- **Expected Success Output:** exit 0 with restore hydration, local-only, transfer status, and failure-surface integration passing
- **STOP Conditions:**
  - STOP if UI state becomes an authority for Object availability or hides an unresolved integrity failure.
- **Description:** Integrate progressive availability, recovery, version restore rehydration, adoption, and local-only state into authoritative shell surfaces and Core handoffs used by Export and Consolidation.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Offline, degraded Object Store, second-device hydration, historical restore, and local-only runs show accurate authoritative status; Notes remain editable; only verified bytes render; and every unresolved integrity state exposes its valid recovery action.
```
