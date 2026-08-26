---
version: v2.1.20
status: active
epic: K
---

# Epic K: Private GitHub Remote lifecycle

Implement the complete private GitHub reference connection through GitHub App device flow. Authentication, Remote attachment, Object Store readiness, privacy, sign-out, detach, and reconnect remain distinct state transitions. GitLab and every second Provider remain deferred.

**Capability coverage:** CAP-SYNC-01, CAP-SYNC-05, CAP-SYNC-06, CAP-SYNC-07, CAP-SYNC-12, and the connection prerequisites in CAP-ASSET-03, CAP-ASSET-11, and CAP-ASSET-12. Epic J owns CAP-SYNC-08 Consolidation behavior and UI; CONNECT-K004 and REMOTE-K007 own its connection-time orchestration.

**Total Effort:** 66 story points

#### REG-K001 Register and release-gate the project GitHub App
- **Type:** Security
- **Effort:** 5
- **Dependencies:** CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `config/github-app.release.toml`
  - `docs/github-app-installation.md`
  - `scripts/attest-github-app-token-expiration.sh`
  - `scripts/verify-github-app-registration.sh`
  - `.github/workflows/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - Embedding a client secret, GitHub App private key, or installation token minting authority
- **Verification Command:** Run `./scripts/attest-github-app-token-expiration.sh --client-id "$BURLMD_GITHUB_APP_CLIENT_ID" --output .constitution/reports/github-app-token-expiration-attestation.json`, complete the displayed device-flow authorization as the project administrator, then run `./scripts/verify-github-app-registration.sh --manifest config/github-app.release.toml --installation-url "$BURLMD_GITHUB_APP_INSTALLATION_URL" --expected-client-id "$BURLMD_GITHUB_APP_CLIENT_ID" --require-device-flow --require-private-repository-permissions --forbid-permission workflows --token-expiration-attestation .constitution/reports/github-app-token-expiration-attestation.json --max-attestation-age-hours 24 --output .constitution/reports/github-app-registration.json && git diff --check`.
- **Expected Success Output:** exit 0 with a non-placeholder public client ID, reachable installation URL, exact versioned Contents/Administration/implicit Metadata permissions, no Workflows permission, required versioned REST headers, a successful device-code request, a fresh expiring-token attestation, and a drift-free release report
- **STOP Conditions:**
  - STOP if release configuration uses a placeholder client ID, requires a client secret/private key in the binary or CI, omits the public installation URL, or differs from the versioned permission manifest.
- **Description:** Register the project-owned GitHub App through the administrator runbook, publish its installation URL, version its repository and account permissions, enable device flow and expiring user tokens, and inject the public release client ID. Automate public metadata, installation URL, permission, client-ID, and device-code checks. Require a fresh administrator-approved device-flow attestation for token expiration before release.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
The administrator runbook records registration and ownership without exporting secrets. The automated probe reads public App metadata and proves the installation URL, release client ID, exact Contents/Administration/implicit Metadata permissions, absence of Workflows permission, manifest version, required `Accept` and `X-GitHub-Api-Version: 2026-03-10` REST headers, and a successful device-code request. A human-approved device flow must issue `expires_in`, `refresh_token`, and `refresh_token_expires_in`. The attestation records their presence and lifetimes but never their values, securely discards the tokens, and expires after 24 hours. Missing or stale evidence blocks AUTH-K001 and release verification.
```

#### AUTH-K001 Replace legacy OAuth with GitHub App device flow
- **Type:** Security
- **Effort:** 8
- **Dependencies:** REG-K001, CI-M003
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
- **Expected Success Output:** exit 0 with device-code, polling, slowdown, denial, cancellation, bad-code restart, both documented expiry identifiers, unverified-email guidance, and every documented fatal device-flow error contract test passing
- **STOP Conditions:**
  - STOP if implementation needs an embedded client secret, App private key, callback listener, or automated browser approval.
- **Description:** Implement the accepted GitHub App device-code request and polling contract, expose verification URI/code and typed progress, and remove the old PKCE redirect/client-secret path. Treat both `expired_token` and GitHub's documented `token_expired` wording as expiry responses that discard the code and restart device authorization.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Protocol fixtures verify the pinned GitHub API contract, polling interval and `slow_down` handling, terminal denial, cancellation, public client ID only, and absence of every superseded redirect/secret path. Success requires the complete expiring token pair, both lifetimes, empty `scope`, and bearer `token_type` in JSON. `bad_verification_code`, `expired_token`, and `token_expired` each discard the unusable code and restart device flow with a fresh code. `unverified_user_email` stops polling and guides the Writer to verify their primary email before restarting. `unsupported_grant_type`, `incorrect_client_credentials`, `incorrect_device_code`, and `device_flow_disabled` stop polling immediately and surface typed configuration or protocol failures.
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
- **Expected Success Output:** exit 0 with secure-store, pre-expiry refresh, concurrent refresh, atomic rotation, one-401 retry, second-401 refusal, transient failure, bad-refresh, fatal refresh configuration/protocol, unverified-email, and sign-out tests passing
- **STOP Conditions:**
  - STOP if tokens transit persistent Dart state, logs, diagnostics, Git config, a remote URL, or Workspace files.
- **Description:** Store expiring access/refresh tokens only in Platform secure storage, serialize refresh, atomically rotate the pair before expiry or after one authenticated `401`, replay the failed operation at most once, treat a second `401` as authentication-required, and preserve credentials on transient failure. A definitive bad refresh token restarts device flow. `unsupported_grant_type` and `incorrect_client_credentials` preserve the current pair, stop refresh, and surface typed configuration/protocol failure without retry. `unverified_user_email` preserves the pair, prompts the Writer to verify the primary email, and then restarts device flow. Implement sign-out without detach.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
At most one refresh runs. JSON fixtures require `access_token`, `expires_in`, `refresh_token`, `refresh_token_expires_in`, empty `scope`, and bearer `token_type` before rotation. Missing, malformed, or form-encoded success responses preserve the earlier pair and fail as protocol errors. Readers observe either the old valid pair or the new complete pair; access-token expiry refreshes proactively; one authenticated `401` causes exactly one refresh and one replay; a second `401` stops as authentication-required; transient errors retain the pair and local operation; a definitively bad refresh returns to authorization. `unsupported_grant_type` and `incorrect_client_credentials` never retry and expose distinct typed configuration/protocol outcomes. `unverified_user_email` exposes Writer guidance and restarts only after verification. Sign-out removes credentials but preserves Workspace Remote attachment and history.
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
GitHub API fixtures cover user and organization installations, insufficient permission, selected-repository coverage, private provisioning, public/nonempty refusal, and rate limits. Every REST fixture asserts `Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2026-03-10`; OAuth device and token endpoints remain outside the REST-header rule.
```

#### CONNECT-K004 Attach and publish an existing local Workspace
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** REPO-K003, TRANSFER-I005, CONSUI-J007, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/git/operations.rs`
  - `rust/src/provider/**`
  - `rust/src/sync/**`
  - `rust/src/api/ffi_api.rs`
  - `test/**`
  - `integration_test/connect_consolidation_flow_test.dart`
- **Scope (Out-of-Scope Files):**
  - Reconciliation against a populated unrelated repository
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test integration_test/connect_consolidation_flow_test.dart -d linux && dart analyze && git diff --check`
- **Expected Success Output:** exit 0 with prerequisite, workflow-history refusal, optional prepublication Consolidation, ephemeral credential, publish, rollback, and privacy-recheck tests passing
- **STOP Conditions:**
  - STOP if protected Objects aren't verified in the Object Store or Git credentials would persist beyond one process invocation.
  - STOP if any commit reachable from a local publication ref contains `.github/workflows/**`; keep the Workspace local and offer Consolidation into a clean Workspace.
- **Description:** Recheck private/empty eligibility, Object readiness, and the complete local publication closure, then enter the connection `Preparing` state. Refuse workflow-bearing history without requesting Workflows permission. Before initial publication, let the Writer either continue with the active Workspace or complete the typed Consolidation workflow from Epic J. Attach the Remote without rehoming local state, publish with an ephemeral user token, and persist attachment only after success.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
No Note history publishes before protected Objects verify and the Writer completes or declines Consolidation. Generated refs prove that a workflow path in current or historical commits refuses publication while local use remains available. The connection integration test drives `Preparing → Consolidating → Preparing → Connected`, including a collision decision, and proves the source stays unchanged. It asserts that the second preparation phase rechecks Object/privacy prerequisites and that initial publication completes before `Connected`. Git receives credentials only through the ephemeral adapter. Failure leaves the local Workspace and history intact and unattached; success records the exact private Remote without credentials in configuration or URL.
```

#### CLONE-K005 Join a connected Workspace on another device
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** REPO-K003, REPAIR-H008, TRANSFER-I005, MIGRATE-I011, CI-M003
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
  - Choosing or retiring Object Store migration authority, owned by MIGRATE-I011
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && ./scripts/verify-second-device-join.sh --private-remote "$BURLMD_TEST_PRIVATE_REMOTE_URL" --object-endpoint "$BURLMD_TEST_S3_ENDPOINT" --output target/runbooks/clone-k005.json && git diff --check`
- **Expected Success Output:** exit 0 with empty-destination, live clone, preflight, index, Object configuration, migration fallback onboarding, immediate text access, and progressive hydration probes passing
- **STOP Conditions:**
  - STOP if destination isn't empty/absent, Remote isn't private/accessible, asset-bearing history lacks a verified Object Store configuration, or a retained migration fallback can't be credentialed or serviced by an already credentialed peer.
- **Description:** Authorize, select an accessible private Remote, clone into a safe destination, run canonical preflight/bootstrap, configure authoritative replacement Object access, and detect any retained old-store fallback descriptor. Store supplied fallback credentials only in secure storage; otherwise allow a connected credentialed peer to service verified on-demand backfill. Open text promptly and hydrate active Assets progressively from the replacement, invoking the MIGRATE-I011 fallback path on a verified replacement miss.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
The exact runbook command starts from a clean second-device state, joins the isolated private Remote, and reaches an authoritative local Workspace with full history and index, immediate Note editing, and progressive verified Asset hydration. A migration fixture proves a replacement miss invokes the retained old-store fallback through securely supplied credentials or a credentialed peer, verifies the fetched content hash, backfills and verifies the replacement, and hydrates only from that replacement. Its machine-readable log proves no source archive mutation, no credential persisted in the clone, and bounded cleanup of test state.
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
- **Expected Success Output:** exit 0 with offline transition to local-with-store, required reconnect before retained-store removal, online full-local transition, hydration refusal, and exact-history preservation tests passing
- **STOP Conditions:**
  - STOP if detach deletes history or Objects, or can leave an asset-bearing Workspace inconsistently attached.
  - STOP if a full-local transition relies on cached Remote refs, stale readiness, or no authenticated online Remote revalidation.
  - STOP if removing the Object Store from `LocalWithObjectStore` can proceed without reconnecting the exact prior Remote and obtaining fresh authenticated ref/revision-bound readiness from DETACH-I012.
- **Description:** Keep sign-out credential-only. Offline Remote detachment moves to `LocalWithObjectStore` and retains Object Store configuration. From that state, reconnect the exact prior Remote before either resuming publication or returning fully local. For a full-local transition, authenticate online, enumerate all published refs again, hydrate and verify the resulting Protected Object closure, and consume the ref/revision-bound readiness atomically before detaching both external stores. Never delete remote Object bytes or rewrite history.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Sign-out preserves attachment. Offline detachment removes only local Remote bookkeeping, enters `LocalWithObjectStore`, retains the Object Store, and preserves local commits. That state can't remove the retained store directly. Reconnecting the exact prior Remote restores publication without history rewrite or allows a full-local transition through authenticated online Remote-ref revalidation immediately before hydration readiness and compare-and-swap detach. The transition refuses offline, stale, incomplete, or advanced ref evidence. Success retains all protected bytes and deletes no authoritative remote Object.
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
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh remote-k007 && git diff --check`
- **Expected Success Output:** exit 0 with connect, second-device join, reauthorize, public/lost-access pause, sign-out, detach/reconnect, and keyboard/Semantics tests passing
- **STOP Conditions:**
  - STOP if authentication gates local writing or UI conflates sign-out with detach.
- **Description:** Present device flow, repository selection/provisioning, Object prerequisites, optional prepublication Consolidation, initial attachment, second-device authorize/select/clone join, reauthorization, privacy failure, sign-out, full-local detach, and reconnect through typed authoritative states. CLONE-K005 and DETACH-K006 own the Core behavior; this ticket owns their Writer-facing workflows.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a local Workspace in each authorization and attachment state
When the Writer connects a local Workspace, optionally consolidates another local Workspace before publication, joins from a second device, signs out, reauthorizes, detaches, reconnects, or restores privacy
Then local editing remains available
And the UI shows the exact typed state and valid next actions
And connection can't publish while Consolidation is active or unresolved
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
