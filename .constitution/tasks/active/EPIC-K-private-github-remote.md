---
version: v2.1.4
status: active
epic: K
---

# Epic K: Private GitHub Remote lifecycle

Implement the complete private GitHub reference connection through GitHub App device flow. Authentication, Remote attachment, Object Store readiness, privacy, sign-out, detach, and reconnect remain distinct state transitions. GitLab and every second Provider remain deferred.

**Capability coverage:** CAP-SYNC-01, CAP-SYNC-05, CAP-SYNC-06, CAP-SYNC-07, CAP-SYNC-12, and the connection prerequisites in CAP-ASSET-03, CAP-ASSET-11, and CAP-ASSET-12. CAP-SYNC-08 is owned by Epic J.

**Total Effort:** 61 story points

#### AUTH-K001 Replace legacy OAuth with GitHub App device flow
- **Type:** Security
- **Effort:** 8
- **Dependencies:** CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/api/auth.rs`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/auth_provider.dart`
  - `lib/src/screens/login.dart`
  - `test/providers/auth_provider_test.dart`
  - `test/screens/login_test.dart`
- **Scope (Out-of-Scope Files):**
  - OAuth redirect listener, client secret, GitHub App private key, and GitLab
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh auth-k001 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with device-code, polling, slowdown, denial, expiry, and cancellation contract tests passing
- **STOP Conditions:**
  - STOP if implementation needs an embedded client secret, App private key, callback listener, or automated browser approval.
- **Description:** Implement the accepted GitHub App device-code request and polling contract, expose verification URI/code and typed progress, and remove the old PKCE redirect/client-secret path.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Protocol fixtures verify the pinned GitHub API contract, polling interval and slow_down handling, terminal denial/expiry, cancellation, public client ID only, and absence of every superseded redirect/secret path.
```

#### TOKEN-K002 Persist, refresh, and revoke the user token pair safely
- **Type:** Security
- **Effort:** 8
- **Dependencies:** AUTH-K001, CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/api/auth.rs`
  - `rust/src/security/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/auth_provider.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Workspace attachment and Git remote configuration
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh token-k002 && git diff --check`
- **Expected Success Output:** exit 0 with secure-store, atomic rotation, concurrent refresh, transient failure, bad-refresh, and sign-out tests passing
- **STOP Conditions:**
  - STOP if tokens transit persistent Dart state, logs, diagnostics, Git config, a remote URL, or Workspace files.
- **Description:** Store expiring access/refresh tokens only in Platform secure storage, serialize refresh, atomically rotate the pair, preserve credentials on transient failure, restart device flow on authoritative rejection, and implement sign-out without detach.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
At most one refresh runs; readers observe either the old valid pair or the new complete pair; transient errors retain the pair and local operation; bad refresh returns to authorization; sign-out removes credentials but preserves Workspace Remote attachment and history.
```

#### REPO-K003 Discover installations and select or provision a private repository
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** TOKEN-K002, CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/provider/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Public repositories and non-GitHub Providers
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh repo-k003 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with installation, permission, private/empty selection, provisioning, and coverage-recheck tests passing
- **STOP Conditions:**
  - STOP if repository privacy, emptiness, App installation coverage, Contents write, or required Administration permission isn't established.
- **Description:** List App installations and accessible repositories, select an eligible private empty repository or provision one privately, explain Administration write, and pause until the installation covers a new repository.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
GitHub API fixtures cover user and organization installations, insufficient permission, selected-repository coverage, private provisioning, public/nonempty refusal, rate limits, and exact 2026-03-10 request headers.
```

#### CONNECT-K004 Attach and publish an existing local Workspace
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** REPO-K003, TRANSFER-I005, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/git/operations.rs`
  - `rust/src/provider/**`
  - `rust/src/sync/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Reconciliation against a populated unrelated repository
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with prerequisite, ephemeral credential, publish, rollback, and privacy-recheck tests passing
- **STOP Conditions:**
  - STOP if protected Objects aren't verified in the Object Store or Git credentials would persist beyond one process invocation.
- **Description:** Recheck private/empty eligibility and Object readiness, attach the Remote without rehoming local state, publish existing history with an ephemeral user token, and persist attachment only after success.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
No Note history publishes before protected Objects verify; Git receives credentials only through the ephemeral adapter; failure leaves the local Workspace/history intact and unattached; success records the exact private Remote without credentials in config or URL.
```

#### CLONE-K005 Join a connected Workspace on another device
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** REPO-K003, REPAIR-H008, TRANSFER-I005, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/workspace/bootstrap.rs`
  - `rust/src/git/operations.rs`
  - `rust/src/provider/**`
  - `rust/src/object_store/**`
  - `rust/src/api/ffi_api.rs`
  - `scripts/verify-second-device-join.sh`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Consolidating another archive, owned by Epic J
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && ./scripts/verify-second-device-join.sh --private-remote "$BURLMD_TEST_PRIVATE_REMOTE_URL" --object-endpoint "$BURLMD_TEST_S3_ENDPOINT" --output target/runbooks/clone-k005.json && git diff --check`
- **Expected Success Output:** exit 0 with empty-destination, live clone, preflight, index, Object configuration, immediate text access, and progressive hydration probes passing
- **STOP Conditions:**
  - STOP if destination isn't empty/absent, Remote isn't private/accessible, or asset-bearing history lacks a verified Object Store configuration.
- **Description:** Authorize, select an accessible private Remote, clone into a safe destination, run canonical preflight/bootstrap, configure Object access, open text promptly, and hydrate active Assets progressively.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
The exact runbook command starts from a clean second-device state, joins the isolated private Remote, and reaches an authoritative local Workspace with full history and index, immediate Note editing, and progressive verified Asset hydration. Its machine-readable log proves no source archive mutation, no credential persisted in the clone, and bounded cleanup of test state.
```

#### DETACH-K006 Separate sign-out, detach, reconnect, and full-local transition
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** CONNECT-K004, DETACH-I012, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/**`
  - `rust/src/git/operations.rs`
  - `rust/src/object_store/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Deleting Remote repositories or Object Store buckets
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with offline/no-credential detach, reconnect, protected-hydration block, and exact-history preservation tests passing
- **STOP Conditions:**
  - STOP if detach deletes history/Objects, requires network/credentials, or can leave an asset-bearing Workspace inconsistently attached.
- **Description:** Keep sign-out credential-only, detach as explicit local bookkeeping, preserve all history, block full-local transition until protected hydration completes, and reconnect the exact prior Remote without rewriting history.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Sign-out preserves attachment; detach works offline without credentials and preserves commits; protected Asset checks gate full-local transition; successful full-local mode retains all bytes and detaches both external stores; reconnect restores publication without history rewrite.
```

#### REMOTE-K007 Integrate Remote settings, privacy, and authorization states
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** CONNECT-K004, CLONE-K005, DETACH-K006, PREF-G002
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/**`
  - `lib/src/providers/auth_provider.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/screens/workspace.dart`
  - `lib/l10n/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Reconciliation UI owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test && dart analyze && ./scripts/smoke-shot.sh remote-k007 && git diff --check`
- **Expected Success Output:** exit 0 with connect, second-device join, reauthorize, public/lost-access pause, sign-out, detach/reconnect, and keyboard/Semantics tests passing
- **STOP Conditions:**
  - STOP if authentication gates local writing or UI conflates sign-out with detach.
- **Description:** Present device flow, repository selection/provisioning, Object prerequisites, initial attachment, second-device authorize/select/clone join, reauthorization, privacy failure, sign-out, full-local detach, and reconnect through typed authoritative states. CLONE-K005 and DETACH-K006 own the Core behavior; this ticket owns their Writer-facing workflows.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a local Workspace in each authorization and attachment state
When the Writer connects a local Workspace, joins from a second device, signs out, reauthorizes, detaches, reconnects, or restores privacy
Then local editing remains available
And the UI shows the exact typed state and valid next actions
And public or inaccessible Remote state pauses synchronization
```

#### CANARY-K008 Establish layered private GitHub verification
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** CLONE-K005, DETACH-K006
- **Category:** Security
- **Scope (In-Scope Files):**
  - `.github/workflows/**`
  - `integration_test/**`
  - `scripts/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - Fork-originated secret access and automated device-code approval
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/run-private-github-canary.sh --private-remote "$BURLMD_TEST_PRIVATE_REMOTE_URL" --object-endpoint "$BURLMD_TEST_S3_ENDPOINT" --cleanup always --output .constitution/reports/canary-k008.json && ./scripts/verify-device-authorization-runbook.sh --require-human-approval --output .constitution/reports/device-auth-k008.json && git diff --check`
- **Expected Success Output:** hermetic PR tests, scheduled live canary apply/probe/cleanup, and manual human-authorized device-flow runbook all pass with isolated secret boundaries
- **STOP Conditions:**
  - STOP if canary secrets can reach fork workflows or a browser is automated to approve device codes.
- **Description:** Add hermetic protocol tests for every PR, a scheduled live canary against dedicated private repositories, and a manual prerelease device-authorization runbook with cleanup.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
The exact commands record apply, probe, and cleanup outcomes. PR verification runs without live secrets; the scheduled canary creates, uses, and cleans dedicated private test state even after injected failure; secret contexts exclude forks; and the manual device-flow gate records human authorization without browser automation. Each report ends in a declared clean state or identifies the bounded residual for manual cleanup.
```
