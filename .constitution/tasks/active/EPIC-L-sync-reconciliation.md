---
version: v2.1.20
status: active
epic: L
---

# Epic L: Synchronization and reconciliation

Deliver continuous Git synchronization and all three reconciliation forms: canonical-AST Suggestions, Lifecycle Decisions, and Asset Decisions. GIT-L001 runs after `CI-M003` merges so its cross-platform evidence uses the managed role workflows; every dependent ticket adapts to the measured Git protocol accepted by final TechSpec.

**Capability coverage:** CAP-SYNC-02, CAP-SYNC-03, CAP-SYNC-04, CAP-SYNC-10, CAP-SYNC-11, CAP-SYNC-13, and the runtime privacy behavior of CAP-SYNC-12.

**Total Effort:** 90 story points

#### GIT-L001 Select the structured Git analysis protocol
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/git-analysis/**`
  - `.constitution/spikes/SPK-GIT-L001.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't touch production or active specifications)
- **Verification Command:** After `CI-M003` merges and the source commit is pushed, run `./scripts/managed-evidence.sh run --ticket GIT-L001 --source-ref SOURCE_REF --source-head-sha SOURCE_HEAD_SHA --base-sha BASE_SHA --output .constitution/prototypes/git-analysis/managed-evidence.json && git diff --check`. The managed workflow runs the complete ordered `SPK-GIT-L001.verification_steps` array from `.constitution/tech-spec/contracts/provisional-spikes.toml` verbatim on its declared Linux and macOS filesystem roles.
- **Expected Success Output:** exit 0 with distinct Linux and macOS default-filesystem runs and one finalized schema-valid hostile-corpus report
- **STOP Conditions:**
  - STOP if `CI-M003` isn't merged or if evidence is missing, stale, mismatched, corrupt, self-hosted, unauthenticated, assigned to the wrong filesystem role, or rejected.
  - STOP if analysis parses human error prose, relies on markers, mutates the authoritative worktree, or executes repository-controlled behavior.
  - STOP at the 3-day time box and report uncovered conflict classes.
- **Description:** Compare `merge-tree`, temporary-index plumbing, and isolated-worktree porcelain across the complete Git corpus and fault matrix.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Every declared candidate and conflict/security gate has attributed structured evidence on both default Linux and macOS filesystems. The result tool captures host fingerprints, filesystem facts, and effective `core.ignoreCase`, `core.precomposeUnicode`, `core.protectHFS`, and filemode behavior from system and Git probes. The complete role bundles and accepted managed aggregate bind the evidence to the tested source, workflow execution, base, build, corpus, run, hosted origin, signer, and exact filesystem role. Aggregation rejects missing, same-host, same-operating-system, role-mismatched, unauthenticated, or single-role candidate evidence. The report contains exact object/tree identities, crash/CAS inputs, worktree nonmutation proof, and redistribution obligations.
```

#### ANALYZE-L002 Implement typed read-only Git reconciliation analysis
- **Type:** Security
- **Effort:** 8
- **Dependencies:** GIT-L001, ADAPT-H004, PATH-H005, CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/git/**`
  - `rust/src/sync/**`
  - `rust/src/api/ffi_api.rs`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Applying Writer decisions
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && ./scripts/check-generated-bindings.sh && git diff --check`
- **Expected Success Output:** exit 0 with the complete accepted Git matrix and hostile-configuration isolation passing
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted GIT-L001 or any analysis path uses ambient/version-unchecked Git.
- **Description:** Wrap the accepted version-locked Git protocol in typed records for exact base/local/incoming commits, paths, stages, tentative trees, Suggestions, Lifecycle Decisions, Asset Decisions, and unsupported entries.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
The complete Spike corpus maps deterministically into typed outcomes without worktree mutation, localized text parsing, marker dependence, repository hooks/filters/drivers/helpers, or unsupported alias execution.
```

#### SCHED-L003 Complete the durable synchronization scheduler
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ANALYZE-L002, CONNECT-K004, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/git/**`
  - `rust/src/bin/sync_freshness_meter.rs`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/workspace_provider.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Resident daemon or operating-system background service
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh sched-l003 && cargo run --release --manifest-path rust/Cargo.toml --bin sync-freshness-meter -- --private-remote "$BURLMD_TEST_PRIVATE_REMOTE_URL" --local-versions 100 --incoming-versions 100 --offline-cycles 10 --offline-duration-seconds 3600 --output target/sync-meters/sched-l003.json && git diff --check`
- **Expected Success Output:** exit 0 with debounce, backoff, offline, refresh, workflow-history pause, bounded shutdown, restart, privacy-pause, and machine-readable freshness measurements passing
- **STOP Conditions:**
  - STOP if network work blocks editing, shutdown waits without a bound, or an abrupt kill loses durable sync intent.
  - STOP before push if any commit reachable from a local publication ref contains `.github/workflows/**`; preserve durable intent and offer Consolidation into a clean Workspace.
- **Description:** Wire commit activity and application lifecycle into durable fetch/analyze/reconcile/push scheduling, retry/backoff, authorization/privacy pauses, workflow-history refusal, and one bounded final shutdown attempt.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
Against the isolated private Remote named by the exact verification command, all 100 healthy local Versions publish within the 60-second Sync Latency Goal and all 100 incoming Versions surface within the 60-second Remote Freshness Goal. A current or historical `.github/workflows/**` path pauses push without requesting Workflows permission or blocking local use. Ten offline/reconnect cycles include an explicit 3,600-second offline interval, honor the 15-minute maximum backoff, and surface incoming changes within 60 seconds of the one-hour reconnect. Editing remains nonblocking; shutdown obeys its bound; and restart resumes every incomplete durable intent without a daemon.
```

#### SUGGEST-L004 Materialize content conflicts as canonical AST Suggestions
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ANALYZE-L002, ADAPT-H004, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/markdown/**`
  - `rust/src/sync/**`
  - `rust/src/git/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Raw conflict-marker UI
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with smallest-safe-subtree, base/local/incoming, multi-Suggestion, and valid-merge-tree tests passing
- **STOP Conditions:**
  - STOP if literal marker text is misclassified, either side is lost, or unresolved Suggestions can't live in a valid two-parent merge commit.
- **Description:** Convert source-backed Markdown content conflicts into independently resolvable canonical AST Suggestions, preserve all three variants, and materialize a valid merge tree that can continue syncing while Suggestions remain.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Every content fixture preserves base/local/incoming bytes, partitions only at the smallest safe AST subtree, never exposes raw markers, produces no duplicate Note, and records a valid two-parent merge commit even with unresolved Suggestions.
```

#### SUGUI-L005 Resolve Suggestions independently in the editor
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** SUGGEST-L004, TABS-G004, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/editor.dart`
  - `lib/src/components/block_view.dart`
  - `lib/src/providers/note_providers.dart`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Same-device external change decisions
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh sug-l005 && git diff --check`
- **Expected Success Output:** exit 0 with local/incoming/both/custom, partial unresolved, keyboard, Semantics, and persistence tests passing
- **STOP Conditions:**
  - STOP if resolving one Suggestion implicitly resolves another or if UI owns conflict source.
- **Description:** Render canonical Suggestions inline and support independent accept-local, accept-incoming, accept-both, and custom source replacement while retaining unresolved siblings through history and sync.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a Note contains several unresolved Suggestions
When the Writer resolves one using any supported choice
Then only that Suggestion changes
And the Note remains valid and durable
And unresolved siblings remain visible and synchronizable
```

#### LIFE-L006 Implement durable Lifecycle Decisions
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ANALYZE-L002, AUTH-H006, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/workspace/**`
  - `rust/src/git/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Content Suggestions and Asset Decisions
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh life-l006 && git diff --check`
- **Expected Success Output:** exit 0 with all structural classes, durable pause, editing availability, explicit choices, and resume tests passing
- **STOP Conditions:**
  - STOP if uncertain guest rename provenance is accepted automatically or local editing/history is blocked while sync pauses.
- **Description:** Persist and present explicit decisions for add/delete/rename/move/Directory/type/path-identity conflicts, preserve candidates, pause Workspace sync, and apply one validated lifecycle outcome.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Every structural conflict maps to a durable keyed decision with exact input commits/tree; sync pauses but local editing/history continues; uncertain rename is explicit; and only a complete revalidated decision set can publish one canonical tree.
```

#### ASSET-L007 Implement durable Asset Decisions
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** ANALYZE-L002, RECOVER-I006, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/assets/**`
  - `rust/src/object_store/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Silent binary merge or reference deletion
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh asset-l007 && git diff --check`
- **Expected Success Output:** exit 0 with byte/reference/availability conflict, verified candidate, pause, choice, and Object publication tests passing
- **STOP Conditions:**
  - STOP if either byte candidate is discarded before decision or a chosen Object isn't verified locally and remotely before resume.
- **Description:** Persist and present Asset Decisions for conflicting bytes, references, or availability; preserve every candidate Object; coordinate recovery and Object publication; and pause only affected Workspace synchronization.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Every binary/reference conflict retains both identities and verified bytes, offers only valid actions, keeps local editing/history available, and resumes only after the selected reference and Object verify against the recorded reconciliation inputs.
```

#### FINAL-L008 Finalize reconciliation with compare-and-swap and crash recovery
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** SUGGEST-L004, LIFE-L006, ASSET-L007, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/git/**`
  - `rust/src/db/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Force-updating a branch after it advances
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with fault injection at every state transition, restart, stale branch, revalidation, and CAS tests passing
- **STOP Conditions:**
  - STOP if a decision can apply to different commit/tree identities than the Writer reviewed.
- **Description:** Persist base/local/incoming/tentative identities and decisions before input, recover them after crash, CAS the branch from recorded local, recompute after advancement, and require renewed input for changed outcomes.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Fault injection at every durable transition resumes or safely abandons without losing candidates. Branch advancement prevents stale publication, recomputation retains only decisions whose exact outcome is unchanged, and final CAS creates one valid merge commit.
```

#### STATE-L009 Expose complete synchronization state and recovery actions
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** SCHED-L003, SUGUI-L005, FINAL-L008, REMOTE-K007, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/components/**`
  - `lib/l10n/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - String parsing of Core errors or status
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh state-l009 && git diff --check`
- **Expected Success Output:** exit 0 with clean/active/offline/behind/failed/auth/decision/Suggestion state tests passing
- **STOP Conditions:**
  - STOP if pending Suggestions are presented as clean or a paused Decision shares the same action model as offline/auth failure.
- **Description:** Expose and render typed synchronization states, timestamps, pending commits, pending Suggestions, decision pauses, privacy failures, and only the recovery actions valid for each.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given each synchronization state and transition
When the shell renders status
Then the Writer can distinguish the state and its valid action
And pending Suggestions are not clean
And Decision pauses do not block local editing or history
```

#### REFS-L010 Integrate complete Remote refs with Protected Object retention
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** SCHED-L003, RETAIN-I007
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/git/**`
  - `rust/src/sync/**`
  - `rust/src/assets/**`
  - `rust/src/object_store/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Reflog-only and non-advertised Provider-internal refs as Protected State
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Expected Success Output:** exit 0 with unfiltered advertised-ref enumeration, quarantined no-prune fetch, incomplete stop, and deletion integration tests passing
- **STOP Conditions:**
  - STOP if an advertised ref is excluded or can't be fetched into quarantine without an accepted upstream classification that proves it isn't published history.
  - STOP and mark Remote authority incomplete if advertisement or quarantine work exceeds 100,000 refs, 16 MiB of advertised-ref bytes, 2 GiB of cumulative fetched data, or 30 minutes of wall-clock time.
- **Description:** Run unfiltered `git ls-remote --refs` against the attached Remote and stream-parse every advertised `refs/*` entry under explicit count and byte limits. Fetch each Object ID into an isolated, bounded, no-prune temporary quarantine namespace without mutating Workspace refs. Enforce 100,000 refs, 16 MiB of advertisement data, 2 GiB of cumulative fetched data, and a 30-minute wall-clock deadline, with cancellation and cleanup on success, failure, cancellation, and restart. Extend Protected State roots with every fetched history for recovery, migration, detach, cache-retention, and reconciliation decisions. Fail closed when enumeration, classification, fetch completeness, or resource bounds are unproven while preserving local use.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Generated Remote namespaces include branches, annotated and lightweight tags, pull-request refs, and arbitrary advertised ref hierarchies. Every fetchable advertised Object ID expands Protected State. Reflog-only and non-advertised Provider-internal refs don't expand authority. Boundary tests cover every limit, streaming behavior, cancellation, crash recovery, path confinement, and unconditional quarantine cleanup. An unclassified or unfetchable advertised ref, authorization failure, enumeration failure, fetch failure, or exceeded limit marks Remote authority incomplete and stops migration, detach, retention, or reconciliation decisions that require complete published history without blocking local editing. Independent verified local cache eviction remains possible; authoritative remote deletion doesn't exist during `0.x`.
```

#### DELETE-L011 Resolve delete-versus-edit without content loss
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** SUGGEST-L004, LIFE-L006, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/markdown/**`
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Automatic deletion victory
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh delete-l011 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with both direction orders, restore-plus-Suggestion, confirmation, and history tests passing
- **STOP Conditions:**
  - STOP if edited content becomes only a structural decision or deletion wins without explicit confirmation.
- **Description:** Restore the edited Note, represent the content difference as a Suggestion, preserve both outcomes, and require explicit confirmation before deletion wins.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given one side deleted a Note and the other edited it
When reconciliation materializes
Then the edited Note is restored with a Suggestion and recoverable history
And deletion occurs only after the Writer explicitly confirms that outcome
```

#### INTEG-L012 Validate the complete synchronization lifecycle
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STATE-L009, REFS-L010, DELETE-L011, CANARY-K008
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/git/**`
  - `rust/src/assets/**`
  - `lib/src/components/**`
  - `lib/src/providers/**`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - GitLab and resident background services
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh integ-l012 && git diff --check`
- **Expected Success Output:** exit 0 with hermetic and private canary lifecycle evidence passing
- **STOP Conditions:**
  - STOP if any full-lifecycle path loses local/incoming state, publishes a Note before its Objects, or blocks local editing on network state.
- **Description:** Exercise connect, multi-device sync, offline/reconnect, content/lifecycle/asset conflicts, unresolved Suggestions, privacy/auth failure, crash recovery, shutdown attempt, detach, and reconnect as one feature matrix.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Hermetic fixtures and the dedicated private GitHub canary complete the full matrix with exact state transitions, protected Objects, no content loss, local-first editing throughout, bounded shutdown, recoverable interruption, and no public repository or credential exposure.
```
