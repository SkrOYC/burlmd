---
version: v2.2.0
status: active
epic: M
---

# Epic M: Quality, diagnostics, packaging, and releases

Make the complete desktop application supportable, measurable, installable, migratable, and releasable through GitHub `0.x` prereleases. The bootstrap tranche makes only `FLAKE-M002` and `CI-M003` executable production work. PKG-M001 runs after that tranche for packaging-dependent work; later production tickets remain blocked until their own evidence, required upstream finalization, and Stage 4 adaptation are merged.

**Bootstrap tranche:** Create `chore/epic-m-ci-foundation` from merged `master`. Execute `FLAKE-M002` and then `CI-M003`, with one full milestone review after each ticket, and merge the pull request before any downstream managed-evidence tranche starts. The committed, validated, and independently reviewed `FLAKE-M002` milestone satisfies `CI-M003` within this declared tranche. Cross-tranche and cross-branch prerequisites must be merged into the base. This partial tranche doesn't archive Epic M.

**Capability coverage:** CAP-SUP-01, CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06, plus every scalar PRD quality meter and the release-blocking feature matrix.

**Total Effort:** 99 story points

#### PKG-M001 Prove prerelease packaging feasibility and Linux baseline
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** CI-M003
- **Category:** DX
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/packaging/**`
  - `.constitution/spikes/SPK-PKG-M001.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't package production or edit active specifications)
- **Verification Command:** After `CI-M003` merges and the source commit is pushed, run `./scripts/managed-evidence.sh run --ticket PKG-M001 --source-ref SOURCE_REF --source-head-sha SOURCE_HEAD_SHA --base-sha BASE_SHA --output .constitution/prototypes/packaging/managed-evidence.json && git diff --check`. The managed workflow runs the complete ordered `SPK-PKG-M001.verification_steps` array from `.constitution/tech-spec/contracts/provisional-spikes.toml` verbatim; that raw contract is the sole authority for its inner commands and order.
- **Expected Success Output:** exit 0 with finalized multi-role schema-valid evidence, an accepted authenticated aggregate, and an OD-08 recommendation
- **STOP Conditions:**
  - STOP if the harness uses ambient Git, omits installed-runtime probes, or infers one Platform result from another.
  - STOP if `CI-M003` isn't merged or any required role bundle is missing, incomplete, stale, mismatched, corrupt, self-hosted, unauthenticated, or rejected.
  - STOP and reconcile the contract if Apple's published stable-version list no longer identifies macOS 26 and macOS 15 as the two most recent stable major versions.
  - STOP at the 3-day time box and leave unsupported hosts outside the recommendation.
- **Description:** Build and install the representative harness as AppImage, tagged Nix Flake package, and unsigned Apple Silicon archive across the required Linux and macOS matrix. Authenticate managed role evidence through `CI-M003`. Prove the checksum and provenance-metadata layout inside the prototype; release-candidate attestations remain production workflow work owned by RELEASE-M009 and PUBLISH-M014.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Unique hashed and logged runs verify installed Git and runtime, secure storage, file selection, native loading, secret injection, update selection, host chrome, repeatability, and every named Linux candidate. Common functional evidence runs on `ubuntu-24.04`, Apple Silicon `macos-26`, and Apple Silicon `macos-15`; macOS 15 remains compatibility-only. Linux and macOS 26 provide their managed performance evidence. macOS 26 alone owns the authoritative product visual reference. The required Linux exact platform-regression path uses the pipeline-owned headless Sway and Wayland environment, never the Writer's desktop, and can't substitute for macOS 26. Every role bundle contains the manifest plus every named result, log, raw measurement, and handoff. Aggregation verifies tested-source and workflow identity, GitHub-hosted provenance, bundle and upload integrity, internal artifact hashes, and exact role before consuming packaging evidence. Each named runtime check obtains guest operating system, distribution, version, and architecture from inside the installed probe environment; aggregation requires exact Ubuntu 22.04, 24.04, and 26.04 plus Debian 12 and 13 x86-64 evidence rather than trusting run IDs or the outer Nix host. The versioned build script runs `flutter clean`, enforces the committed dependency lock, normalizes archive metadata from the source revision's epoch, and emits the actual deterministic `.tar.gz` release artifact for each construction. macOS 26 constructs that archive twice from identical inputs; aggregation requires byte-identical archive hashes. Extraction rejects path escape and proves the archive preserves required modes, symlink targets, extended attributes, and one application bundle. The first archive is transferred with SHA-256 verification, extracted, and probed on macOS 26 and macOS 15. Aggregation requires both probes to name the same archive SHA-256. Nix out-links are only build sources: the result tool copies their resolved bytes or closures into `artifacts/` inside the Spike allowlist before size and SHA-256 recording. The report selects or refuses a baseline.
```

#### LOG-M002 Add content-excluding structured diagnostics
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** CI-M003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/diagnostics/**`
  - `rust/src/api/ffi_api.rs`
  - `rust/Cargo.toml`
  - `rust/Cargo.lock`
  - `lib/src/components/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Automatic telemetry or upload
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh log-m002 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with rotation, failure isolation, redaction, export, and no-network tests passing
- **STOP Conditions:**
  - STOP if Note/Asset content, credentials, tokens, signed locations, content-derived telemetry, or secret-bearing debug values can enter logs or Diagnostics Export.
- **Description:** Add a rotating best-effort local structured log for failures/retries/state decisions and a Writer-created Diagnostics Export containing app/schema versions without content, signed locations, content-derived telemetry, or automatic transmission.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Generated content, credential, signed-location, and content-derived canaries never appear in files or export; required failures and state transitions do; rotation caps storage; logging failure never becomes a product failure; export performs no network request.
```

#### FLAKE-M002 Stabilize the authoritative-success timestamp regression test
- **Type:** Chore
- **Effort:** 3
- **Dependencies:** None
- **Category:** Tech-Debt
- **Scope (In-Scope Files):**
  - `rust/src/workspace/persist.rs`
  - `scripts/repeat-test.sh`
- **Scope (Out-of-Scope Files):**
  - Weakening authoritative-success semantics or deleting timestamp assertions without a deterministic replacement
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml a_structural_draft_failure_after_tier_two_publication_returns_authoritative_success && ./scripts/repeat-test.sh --count 100 -- cargo test --manifest-path rust/Cargo.toml a_structural_draft_failure_after_tier_two_publication_returns_authoritative_success && git diff --check`
- **Expected Success Output:** the targeted regression passes once normally and 100 consecutive isolated repetitions with deterministic timestamp evidence
- **STOP Conditions:**
  - STOP if this ticket isn't running as the first reviewed milestone on `chore/epic-m-ci-foundation` from merged `master`.
  - STOP if the fix can hide a real ordering failure, rely on wall-clock coincidence, or weaken the authoritative-success state comparison.
- **Description:** Replace the one-second `last_modified` race in the existing structural-draft authoritative-success regression with deterministic clock/state evidence while preserving the production invariant and exact state comparison.
- **Acceptance:**
  - **Mode:** stat_threshold
  - **Evidence:**

```text
Metric: targeted-test failures. Dataset: 100 consecutive isolated repetitions after one ordinary run. Threshold: 0 failures and no skipped assertion. Command: the exact verification command above. The assertion still distinguishes authoritative success from rollback/failure without depending on wall-clock second boundaries. The milestone receives one full review before `CI-M003` begins.
```

#### CI-M003 Establish the Linux and Apple Silicon macOS managed validation matrix
- **Type:** Chore
- **Effort:** 8
- **Dependencies:** FLAKE-M002
- **Category:** DX
- **Scope (In-Scope Files):**
  - `.github/workflows/ci.yml`
  - `.github/workflows/ci-role-linux-x86-64.yml`
  - `.github/workflows/ci-role-macos-26-arm64.yml`
  - `.github/workflows/ci-role-macos-15-arm64.yml`
  - `devenv.nix`
  - `devenv.lock`
  - `scripts/**`
  - `lib/visual_capture_main.dart`
  - `test_driver/visual_capture_driver.dart`
  - `test/visual_capture_driver_protocol_test.dart`
  - `test/goldens/**`
  - `integration_test/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - `.constitution/tech-spec/**` (consume the accepted contracts; don't revise them here)
  - Live product or canary credentials, repository-content pushes, release publication, and Writer desktop state
- **Verification Command:** Complete these steps in order:
  1. In a disposable checkout, run `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test test_driver integration_test && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ! rg -n '\[DEBUG-' lib rust test scripts && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-24.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json && git diff --check`.
  2. Push the source commit to `SOURCE_REF`. Confirm that the `push` run records `SOURCE_HEAD_SHA`, the workflow execution SHA and ref, and `BASE_SHA` separately. A draft pull request is optional visibility only.
  3. On `ubuntu-24.04`, run `flutter test && dart analyze && flutter test integration_test -d linux -r github` inside the pipeline-owned headless environment.
  4. On both Apple Silicon `macos-26` and `macos-15`, run `flutter test && dart analyze && flutter test integration_test -d macos -r github`.
  5. After the push run finishes, run `./scripts/managed-evidence.sh collect --source-ref SOURCE_REF --run-id RUN_ID --attempt RUN_ATTEMPT --source-head-sha SOURCE_HEAD_SHA --base-sha BASE_SHA --output .constitution/reports/ci-m003-managed-evidence.json && git diff --check`.
- **Expected Success Output:** local validation exits 0; all three managed roles finish every Flutter unit, analyzer, and desktop integration gate; each complete role bundle passes GitHub-hosted origin and integrity verification; the operator commits an accepted aggregate before milestone review
- **STOP Conditions:**
  - STOP if `FLAKE-M002` isn't committed, validated, and independently reviewed in `chore/epic-m-ci-foundation` or the branch wasn't created from merged `master`.
  - STOP if implementation imports or cherry-picks from the unmerged Epic G branch. Implement the accepted CI and headless contracts from merged `master`; later surgical replay must preserve this merged foundation.
  - STOP if any third-party action isn't pinned to the full Stage 3 commit SHA or a role uses ambient repository toolchains instead of repository locks.
  - STOP if private/internal attestation isn't available; emit `attestation-unavailable` and reject the aggregate without a hash-only fallback.
  - STOP if validation uses a pull-request merge revision, a dynamic local-workflow `uses` expression, a self-hosted runner, or identity that doesn't separate the tested source, workflow execution, base, and later report commit.
  - STOP if a role bundle omits any manifest-named result, log, raw measurement, or handoff, or if any bundled byte fails its size or SHA-256 check.
  - STOP if Linux capture touches the Writer's desktop, macOS 26 can't prove the 1920x1080 at 60 Hz logical viewport on the hosted GUI, or macOS 15 creates visual or performance evidence.
  - STOP if the Flutter Rust Bridge generator, Rust crate, or Dart package differs from the provisionally authorized `2.12.0` triple. Use that triple only for bootstrap and require revalidation after final Stage 3.
- **Description:** Add one push-triggered caller and three distinct single-job reusable role workflows referenced through static local paths. Implement `./scripts/managed-evidence.sh` with only the Stage 3 `collect` and `run` forms. Pin `actions/checkout` to `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09`, `cachix/install-nix-action` to `13d8dd58da0234aa297dedd986986ccb8e7f3e24`, `actions/upload-artifact` to `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`, `actions/download-artifact` to `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c`, and `actions/attest` to `1e69f48acb82d1966a394da916b4c1698aa569d6`. Generate authoritative source, execution, base, release, build, corpus, run, required-role, and signer identity before fan-out. Each role attests and uploads one immutable bundle containing its manifest and every named internal artifact. The coordinator verifies GitHub-hosted signer provenance, run and attempt, hosted labels, upload and bundle digests, and all bundled files before writing an accepted or rejected aggregate. Run the provisional Flutter Rust Bridge `2.12.0` generated-binding gate in a disposable checkout because the committed checker doesn't restore mismatched output.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
The common functional matrix runs on `ubuntu-24.04`, Apple Silicon `macos-26`, and Apple Silicon `macos-15`. Each role runs the complete Flutter unit suite and analyzer gate. Linux runs every discovered desktop integration test with `flutter test integration_test -d linux -r github` inside the pipeline-owned headless environment. macOS 26 and macOS 15 each run every discovered desktop integration test with `flutter test integration_test -d macos -r github`. The evidence records every integration-test file and result and rejects an empty, skipped, or partially discovered suite. Linux and macOS 26 run performance evidence. Linux alone owns the required exact headless Sway and Wayland platform-regression gate, which isn't authoritative product visual evidence. macOS 26 alone owns the authoritative product visual baseline; macOS 15 remains functional compatibility-only. Linux and macOS 26 satisfy the quantitative PRD classes and every role records image, OS, architecture, CPU, memory, storage, 1920x1080 at 60 Hz viewport, build, corpus, run, and role identity. Linux capture owns compositor, display, input, process, state directory, and application PID without reading the Writer's desktop. macOS 26 runs the actual hosted GUI and proves geometry before capture.

The push-triggered caller invokes `.github/workflows/ci-role-linux-x86-64.yml`, `.github/workflows/ci-role-macos-26-arm64.yml`, and `.github/workflows/ci-role-macos-15-arm64.yml` through static `./.github/workflows/...` paths. Each local workflow resolves from the caller's workflow execution commit. Expected identity and the manifests inside role bundles keep the tested source head, workflow execution SHA and ref, base SHA, and run distinct. Caller and signer permissions are only `contents: read`, `id-token: write`, and `attestations: write`; aggregation has only `contents: read`, `actions: read`, and `attestations: read`. Role fixtures prove `ci-role-evidence.schema.json` excludes bundle and service-assigned artifact fields and rejects cross-role evidence classes and unsafe internal paths. Bundle fixtures require one manifest and every named internal artifact and reject missing, extra, duplicate, escaped, size-mismatched, or digest-mismatched members. Aggregate fixtures prove `accepted` requires all roles and successful checks with no reasons, whereas `rejected` permits partial evidence and requires typed reasons. Signed provenance must contain `runner_environment=github-hosted`; a self-hosted fixture with the expected labels is rejected. Fixtures cover every contract code: `expected-identity-invalid`, `role-manifest-invalid`, `role-bundle-invalid`, `missing-role`, `duplicate-role`, `unexpected-role`, `role-gate-failed`, `identity-mismatch`, `stale-evidence`, `workflow-signer-mismatch`, `runner-label-mismatch`, `runner-environment-mismatch`, `untrusted-origin`, `attestation-unavailable`, `artifact-api-mismatch`, `artifact-corrupt`, `mixed-image-version`, and `aggregation-error`.

The generated-binding gate covers both generated sides and fails on drift. Because bootstrap uses the existing non-restoring checker, its disposable checkout absorbs mismatch changes. `./scripts/managed-evidence.sh collect` verifies the exact source-branch push run and writes the accepted or rejected aggregate without selecting by recency. Contract fixtures prove that `collect` and `run` reject extra or missing flags, replace the report atomically, emit the specified JSON summary, and use exit statuses `0`, `1`, and `2` exactly as Stage 3 defines. The workflow never pushes repository content, publishes a release, or receives live product credentials. An operator adds the aggregate in a later evidence-only commit parented directly by the tested source; the report diff contains no other change and doesn't trigger another validation run. Only an accepted evidence commit can start the full `CI-M003` milestone review. Final Stage 3 must revalidate the generator triple and generated output before downstream production tickets run.
```

#### BENCH-M004 Implement deterministic nightly PRD meters
- **Type:** Chore
- **Effort:** 8
- **Dependencies:** SHELL-G011, RESCAN-H012, ASSET-I010, INTEG-L012, HEALTH-M004
- **Category:** Perf
- **Scope (In-Scope Files):**
  - `rust/benches/**`
  - `integration_test/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - Silently changing PRD thresholds
- **Verification Command:** `ubuntu-24.04`: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id linux-reference --expected-host-profile github-ubuntu-24_04-x86_64 --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-linux.json && git diff --check`; Apple Silicon `macos-26`: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id macos-reference --expected-host-profile github-macos-26-arm64 --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-macos.json && git diff --check`; Apple Silicon `macos-15` functional compatibility: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && git diff --check`; coordinator: `./scripts/aggregate-prd-meters.sh --require-run linux-reference=.constitution/reports/nightly-prd-meters-linux.json --require-run macos-reference=.constitution/reports/nightly-prd-meters-macos.json --require-same-corpus-hash --require-same-meter-definition-version --output .constitution/reports/nightly-prd-meters.json && git diff --check`. Validate all role and aggregate evidence through `CI-M003`.
- **Expected Success Output:** deterministic corpus generation succeeds on both managed performance roles, macOS 15 functional compatibility passes, and aggregation emits one authenticated machine-readable nonblocking result for every meter
- **STOP Conditions:**
  - STOP if a meter uses a different corpus/profile/definition than PRD constraints or changes a threshold outside Product Requirements Evolution.
  - STOP if macOS 15 contributes a performance meter or managed evidence lacks authenticated expected-identity and artifact verification.
- **Description:** Generate the 10,000-Note and editing corpora and measure search, UI, open, cold start, idle memory, external changes, capacity, image, history health, and synchronization freshness on named profiles.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
Linux x86-64 and macOS 26 performance bundles record the managed image and environment identity, run, profile, corpus hash, meter-definition version, samples, percentile or threshold, exact command, and Goal or Fail disposition for every scalar PRD meter. macOS 15 records common functional compatibility only. Aggregation verifies expected identity, GitHub-hosted role signer, bundle integrity, exact evidence classes, corpus, and meter definitions. The nightly job is nonblocking during `0.x` but produces a durable regression report; release gates consume the same definitions.
```

#### HEALTH-M004 Warn before local history storage becomes unhealthy
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** ASSET-I001, HIST-G010, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/git/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `lib/src/providers/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Automatic history deletion, compaction, or threshold changes outside Product Requirements Evolution
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh health-m004 && git diff --check`
- **Expected Success Output:** exit 0 with accepted-threshold, deduplication, recovery-action, and boundary tests passing
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't accepted the history-health meter and threshold after ASSET-I001, or if the warning performs destructive maintenance automatically.
- **Description:** Measure stored textual and manifest history against the accepted health threshold, warn the Writer before the threshold, explain the local consequences, and expose only non-destructive inspection and recovery actions.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given local textual and manifest history approaches the accepted health threshold
When the pre-warning boundary is crossed
Then burlmd presents one actionable Writer-facing warning before the threshold
And repeated measurements don't create warning spam
And no history or Object is deleted automatically
And returning below the reset boundary permits a later warning
```

#### MIGRATE-M005 Back up and atomically migrate application state
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STATE-G003, AUTH-H006
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/db/**`
  - `rust/src/workspace/**`
  - `lib/src/providers/**`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Downgrade compatibility and unnecessary Note/OKF rewrites
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh migrate-m005 && git diff --check`
- **Expected Success Output:** exit 0 with backup, forward migration, rebuild, fault injection, rollback, and later-version refusal tests passing
- **STOP Conditions:**
  - STOP if migration can partially publish, changes Markdown unnecessarily, or destroys the only usable prior state before success.
  - STOP if unsupported later-version preference or Workspace-snapshot bytes are migrated, overwritten, normalized, or discarded.
- **Description:** Version application state, back up affected supported data, migrate forward atomically, rebuild derived index state when safer, restore backup on failure, and refuse unsupported later versions. Quarantine and preserve unsupported later-version bytes exactly; runtime may use in-memory defaults, and it may write a separate supported current file only through an explicitly safe path isolated from the preserved bytes.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Fault injection at every migration step leaves either the complete prior state or complete new state; backup remains recoverable until validation; Workspace Markdown stays unchanged unless the accepted path migration explicitly requires it. Unsupported later-version device preferences and Workspace snapshots are refused, quarantined, and preserved byte-for-byte. Runtime defaults remain in memory, and any later supported current-format write uses a separate explicitly safe isolation path without modifying the preserved bytes.
```

#### APPIMAGE-M006 Package the complete x86-64 AppImage
- **Type:** Chore
- **Effort:** 8
- **Dependencies:** PKG-M001, PORT-J006, CONSUI-J007, INTEG-L012, SHELL-G011
- **Category:** DX
- **Scope (In-Scope Files):**
  - `linux/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `pubspec.yaml`
  - `pubspec.lock`
- **Scope (Out-of-Scope Files):**
  - Linux ARM64, signing, and self-update
- **Verification Command:** Run the accepted production AppImage build and installed probes derived from `SPK-PKG-M001`, then `git diff --check`.
- **Expected Success Output:** one installable artifact passes every accepted x86-64 Linux runtime probe with bundled version-locked Git
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted PKG-M001 or artifact behavior depends on ambient Git/runtime libraries outside the accepted baseline.
- **Description:** Package the complete release application, exact Git CLI/runtime, native library, Flutter assets, desktop metadata, and licenses as the general Linux AppImage.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
The built AppImage launches on every accepted named Linux system and passes installed probes for local editing, persistence, Export, GitHub sync, secure storage, recovery, update notification, native loading, file selection, and host-owned chrome without ambient Git.
```

#### NIX-M007 Publish an importable release-tagged Nix Flake package
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** PKG-M001, PORT-J006, CONSUI-J007, INTEG-L012
- **Category:** DX
- **Scope (In-Scope Files):**
  - `flake.nix`
  - `flake.lock`
  - `nix/**`
  - `.github/workflows/**`
- **Scope (Out-of-Scope Files):**
  - Systems not verified by CI and Nix-managed self-replacement
- **Verification Command:** `nix flake check && nix build .#packages.x86_64-linux.default && git diff --check`
- **Expected Success Output:** exit 0 and the installed package probe uses the exact Git package in its closure
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted PKG-M001 or the Flake exposes an unverified system.
- **Description:** Add a locked Flake that users can import from a release tag in NixOS or Home Manager, exposing only verified systems and the complete runtime closure.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Building from a clean tagged checkout yields the default x86-64 Linux package; NixOS/Home Manager import examples evaluate; the closure contains exact Git/native dependencies; installed feature probes pass; Nix remains the upgrade authority.
```

#### MAC-M008 Package Apple Silicon macOS for two current major versions
- **Type:** Chore
- **Effort:** 8
- **Dependencies:** PKG-M001, CI-M003, PORT-J006, CONSUI-J007, INTEG-L012
- **Category:** DX
- **Scope (In-Scope Files):**
  - `macos/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `pubspec.yaml`
  - `pubspec.lock`
- **Scope (Out-of-Scope Files):**
  - Intel macOS, Developer ID signing, and notarization during `0.x`
- **Verification Command:** On managed Apple Silicon `macos-26`, run `flutter build macos --release && git diff --check`; validate common functional construction inputs through `CI-M003`. Installed macOS 26 visual and performance verification and macOS 15 functional-only verification remain in `GATE-M013`.
- **Expected Success Output:** the unsigned Apple Silicon archive is constructed reproducibly with its complete pinned runtime closure and installation disclosure
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted PKG-M001, the archive uses ambient Git, or construction metadata claims installed-host verification owned by GATE-M013.
  - STOP if this construction ticket treats macOS 15 as a performance or visual reference.
- **Description:** Construct the complete Apple Silicon application archive with exact Git/runtime, native library, Flutter assets, licenses, and unsigned `0.x` installation disclosure. Installed verification on the two supported macOS majors belongs to GATE-M013.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Archive inspection proves Apple Silicon architecture, the exact bundled Git/runtime/native closure, Flutter assets, licenses, source revision, and unsigned installation disclosure. Construction is reproducible from the pinned input and emits no Intel artifact, signing/notarization claim, emulated Platform chrome, or assertion that installed-host gates have already passed.
```

#### RELEASE-M009 Construct immutable `0.x` release candidates and provenance
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** APPIMAGE-M006, NIX-M007, MAC-M008, UPDATE-M010, LOG-M002, BENCH-M004, MIGRATE-M005
- **Category:** Security
- **Scope (In-Scope Files):**
  - `.github/workflows/**`
  - `scripts/**`
  - `CHANGELOG.md`
- **Scope (Out-of-Scope Files):**
  - GitHub Release publication, stable-release signing, notarization, and automatic binary replacement
- **Verification Command:** Run the accepted release construction and artifact verification commands from final TechSpec, then `git diff --check`.
- **Expected Success Output:** immutable unpublished candidates have checksums, provenance, compatibility labels, source revision, licenses, and unsigned disclosures
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the release-construction placeholder with exact accepted commands.
  - STOP if a version isn't `0.x`, any candidate lacks checksum or a cryptographically verified GitHub Actions attestation, the attestation identity doesn't match the expected repository/workflow/revision, or metadata claims an untested system.
- **Description:** Build immutable candidate AppImage and Apple Silicon archives plus the release-tagged Flake input and source archive from one revision. Generate checksums, licenses, disclosures, and keyless GitHub Actions artifact attestations using `actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6` with `id-token: write`, `contents: read`, and `attestations: write`; retain the candidates unpublished for installed verification. The accepted contract binds the GitHub/Sigstore trust root, `SkrOYC/burlmd`, the release workflow identity, release ref, source revision, and every artifact subject. Developer ID signing and notarization remain deferred.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Independent verification reproduces every SHA-256 from immutable candidate bytes and runs `gh attestation verify` against the expected `SkrOYC/burlmd` repository plus the accepted release-workflow and source-revision constraints. Tampered bytes, a different repository or workflow identity, an unexpected ref/revision, an untrusted issuer, or a wrong subject fails closed. Compatibility labels match intended systems; unsigned macOS warnings are explicit; candidates remain unpublished and install without source builds. This authenticated build provenance doesn't claim Developer ID signing or notarization.
```

#### UPDATE-M010 Notify about compatible higher `0.x` releases
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** PKG-M001, PREF-G002, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/update/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `lib/src/providers/burl_preferences_provider.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Downloading or replacing installed binaries
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh update-m010 && git diff --check`
- **Expected Success Output:** exit 0 with compatibility/version/preference/offline/rate-limit/release-page tests passing
- **STOP Conditions:**
  - STOP if update handling mutates the installed application or bypasses Nix/package-manager authority.
- **Description:** Check GitHub prerelease metadata according to the stored preference, compare compatible `0.x` versions, notify once, and open the release page for manual installation.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Version fixtures distinguish higher compatible 0.x, current/older, incompatible system, and malformed data; disabled preference performs no check; transient failures are nonblocking; notification opens only the release page and never replaces binaries.
```

#### GATE-M011 Gate the installed x86-64 AppImage candidate
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** LOG-M002, CI-M003, BENCH-M004, MIGRATE-M005, RELEASE-M009
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `integration_test/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - Waiving a failed P0 feature or PRD Fail threshold
- **Verification Command:** Run the accepted x86-64 AppImage installed matrix from final TechSpec against the immutable `RELEASE-M009` candidate on every accepted Linux runtime. Run its common functional, performance, and exact private-headless platform-regression evidence on managed `ubuntu-24.04`, validate the authenticated role and aggregate schemas, then run `git diff --check`.
- **Expected Success Output:** the candidate hash passes the identical release-blocking matrix on every accepted x86-64 Linux runtime
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed AppImage matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, artifact mismatch, or PRD Fail threshold.
- **Description:** Install the immutable AppImage candidate on every accepted Linux runtime and gate it on local editing/session behavior, authority/monitoring, Assets/Object Store, Export, connection-time Consolidation before initial publication, private GitHub sync, every reconciliation form, secure storage, diagnostics, migration, recovery, and update notification.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
The same versioned matrix passes for the AppImage candidate on every accepted Linux runtime. The managed Linux bundle records candidate hash, image and environment identity, app and source version, verified logical viewport, all P0 outcomes, PRD meters, private GitHub canary, S3-compatible credentials, interruption recovery, diagnostics content exclusion, and update notification. Required exact platform-regression capture uses only the pipeline-owned headless Sway and Wayland environment and doesn't claim product visual authority. The authenticated aggregate binds the result to expected source, workflow execution, base, build, corpus, run, signer, and artifact identity. The matrix connects a local Workspace, enters Consolidation, resolves a collision, and proves that initial Remote publication waits for the atomic Consolidation result. Any failure blocks publication.
```

#### GATE-M012 Gate the installed x86-64 Nix Flake candidate
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** LOG-M002, CI-M003, BENCH-M004, MIGRATE-M005, RELEASE-M009
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `integration_test/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - AppImage/macOS verification and waiving a failed P0 capability or PRD Fail threshold
- **Verification Command:** Run the accepted Nix installed matrix from final TechSpec against the immutable `RELEASE-M009` Flake candidate on every exposed x86-64 Linux system. Run the managed `ubuntu-24.04` functional and performance roles through the authenticated `CI-M003` evidence protocol, then run `git diff --check`.
- **Expected Success Output:** the candidate revision passes the identical release-blocking matrix through a clean NixOS/Home Manager import
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed Nix matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, closure mismatch, or PRD Fail threshold.
- **Description:** Import and install the immutable Flake candidate through clean NixOS/Home Manager fixtures and run the same complete application matrix without bypassing Nix upgrade authority.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Clean evaluation, build, import, install, and matrix probes reproduce the candidate revision and closure. The managed Linux evidence records the same P0, privacy, meter, integration, environment, expected-identity, signer, and artifact-integrity outcomes as the AppImage gate. Any failure blocks publication.
```

#### GATE-M013 Gate the installed Apple Silicon macOS candidate
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** LOG-M002, CI-M003, BENCH-M004, MIGRATE-M005, RELEASE-M009
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `integration_test/**`
  - `scripts/**`
  - `.github/workflows/**`
  - `.constitution/reports/**`
- **Scope (Out-of-Scope Files):**
  - Intel macOS, signing/notarization, and waiving a failed P0 capability or PRD Fail threshold
- **Verification Command:** Run the accepted Apple Silicon installed matrix from final TechSpec against the immutable `RELEASE-M009` archive on managed Apple Silicon `macos-26` and `macos-15`. Run common functional evidence on both, performance and the sole authoritative macOS visual baseline on macOS 26 only, validate the authenticated role and aggregate schemas, then run `git diff --check`.
- **Expected Success Output:** one candidate hash passes the common release-blocking matrix on both macOS roles and the performance and visual extensions on macOS 26
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed macOS matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, artifact mismatch, macOS 26 PRD Fail threshold, or inaccurate unsigned-install disclosure.
  - STOP if macOS 15 produces performance evidence or creates or updates a visual baseline.
- **Description:** Query Apple's official stable-version source, record the observed two-major pair and timestamp, then install the immutable unsigned archive candidate on both managed macOS roles. Run the common application matrix and Gatekeeper-disclosure checks on both; run performance and authoritative visual proof on macOS 26 only.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Both managed macOS roles record the same candidate hash, Apple's observed stable-major pair and source timestamp, complete common functional outcomes, image and environment identity, expected identity, signer provenance, and artifact integrity. macOS 26 additionally records the PRD meters, verified hosted-GUI geometry, and the one authoritative macOS visual baseline. macOS 15 records functional compatibility only. Unsigned installation instructions are accurate. Any required failure blocks publication.
```

#### PUBLISH-M014 Publish the verified GitHub `0.x` prerelease
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** GATE-M011, GATE-M012, GATE-M013, REG-K001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `.github/workflows/**`
  - `.constitution/reports/**`
  - `config/github-app.release.toml`
  - `scripts/**`
  - `CHANGELOG.md`
- **Scope (Out-of-Scope Files):**
  - Rebuilding candidates during publication, stable signing/notarization, and automatic binary replacement
- **Verification Command:** Run `./scripts/attest-github-app-token-expiration.sh --client-id "$BURLMD_GITHUB_APP_CLIENT_ID" --output .constitution/reports/github-app-token-expiration-attestation.json`, complete the displayed device-flow authorization as the project administrator, then run `./scripts/verify-github-app-registration.sh --manifest config/github-app.release.toml --installation-url "$BURLMD_GITHUB_APP_INSTALLATION_URL" --expected-client-id "$BURLMD_GITHUB_APP_CLIENT_ID" --require-device-flow --require-private-repository-permissions --forbid-permission workflows --token-expiration-attestation .constitution/reports/github-app-token-expiration-attestation.json --max-attestation-age-hours 24 --output .constitution/reports/github-app-registration.json`; run the accepted GitHub prerelease publication and remote verification commands from final TechSpec for the already-gated candidate hashes; then run `git diff --check`.
- **Expected Success Output:** one GitHub `0.x` prerelease exposes exactly the gated immutable artifacts, checksums, provenance, compatibility labels, source revision, licenses, and unsigned disclosures
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the GitHub publication placeholder with exact accepted commands.
  - STOP if any published byte differs from the gated candidate, any gate is missing or older than its accepted freshness window, the version isn't `0.x`, an artifact attestation fails the accepted repository/workflow/ref/revision trust policy, or metadata claims an untested system.
  - STOP if the fresh GitHub App registration report is missing, the administrator-approved expiring-token attestation is more than 24 hours old, or the App's client ID, installation URL, device-flow setting, private-repository permissions, or absence of Workflows permission has drifted.
  - STOP and return to GATE-M013 if Apple's official stable-version source no longer matches the gate's recorded two-major pair or if that observation is more than 24 hours old; reconcile the packaging contract first when the pair changes.
- **Description:** Immediately before publication, rerun the REG-K001 GitHub App registration and device-flow verification with fresh administrator-approved token-expiration evidence no older than 24 hours. Query Apple's official stable-version source and require the GATE-M013 pair and observation to be current within 24 hours. Publish the already-gated AppImage, Apple Silicon archive, and attested Flake source archive; expose the gated release-tagged Flake revision; attach their existing checksums, attestations, licenses, and disclosures; and mark the GitHub Release as a prerelease without rebuilding.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Remote verification matches every published byte and Flake revision to the three gate reports and verifies each GitHub Actions attestation against the accepted GitHub/Sigstore issuer, `SkrOYC/burlmd`, release workflow, release ref, source revision, and subject identity. Every GitHub REST publication and verification fixture asserts `Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2026-03-10`. The publication record includes a fresh drift-free GitHub App registration report, its administrator-approved token-expiration attestation age, the fresh official Apple version observation, and the matching GATE-M013 pair. The release is marked prerelease, compatibility and unsigned disclosures are accurate, and no publication step rebuilt an artifact.
```
