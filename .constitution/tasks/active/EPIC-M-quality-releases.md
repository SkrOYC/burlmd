---
version: v2.1.7
status: active
epic: M
---

# Epic M: Quality, diagnostics, packaging, and releases

Make the complete desktop application supportable, measurable, installable, migratable, and releasable through GitHub `0.x` prereleases. PKG-M001 runs first for packaging-dependent work; later packaging tickets adapt to its accepted Linux baseline and artifact contracts.

**Capability coverage:** CAP-SUP-01, CAP-REL-01, CAP-REL-02, CAP-REL-03, CAP-REL-04, CAP-REL-05, CAP-REL-06, plus every scalar PRD quality meter and the release-blocking feature matrix.

**Total Effort:** 99 story points

#### PKG-M001 Prove prerelease packaging feasibility and Linux baseline
- **Type:** Spike
- **Effort:** 8
- **Dependencies:** None
- **Category:** DX
- **Scope (In-Scope Files):**
  - `.constitution/prototypes/packaging/**`
  - `.constitution/spikes/SPK-PKG-M001.md`
- **Scope (Out-of-Scope Files):**
  - Every repository path not listed above (don't package production or edit active specifications)
- **Verification Command:** Execute these exact commands on their named host roles, preserving order within each role, transfer the opaque handoff bundles, then run the coordinator aggregation:
  - linux-flake-check: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id linux-flake-check --role linux-flake-check --output runs/linux-flake-check.json --stdout logs/linux-flake-check.stdout --stderr logs/linux-flake-check.stderr --success-marker artifacts/linux-flake-check.ok -- nix flake check --print-build-logs`
  - linux-build: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id linux-build --role linux-build --output runs/linux-build.json --stdout logs/linux-build.stdout --stderr logs/linux-build.stderr --artifact result-links/appimage --copy-artifact-to artifacts/appimage -- nix build --print-build-logs --out-link result-links/appimage .#checks.x86_64-linux.appimage`
  - linux-flake-install: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id linux-flake-install --role linux-flake-install --output runs/linux-flake-install.json --stdout logs/linux-flake-install.stdout --stderr logs/linux-flake-install.stderr --artifact result-links/flake-install --copy-artifact-to artifacts/flake-install -- nix build --print-build-logs --out-link result-links/flake-install .#checks.x86_64-linux.flake-install`
  - linux-installed-runtime: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id linux-appimage-installed-probe --role linux-installed-runtime --output runs/linux-appimage-installed-probe.json --stdout logs/linux-appimage-installed-probe.stdout --stderr logs/linux-appimage-installed-probe.stderr --artifact result-links/appimage-installed-probe --copy-artifact-to artifacts/appimage-installed-probe -- nix build --print-build-logs --out-link result-links/appimage-installed-probe .#checks.x86_64-linux.appimage-installed-probe`
  - linux-installed-runtime: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id linux-flake-installed-probe --role linux-installed-runtime --output runs/linux-flake-installed-probe.json --stdout logs/linux-flake-installed-probe.stdout --stderr logs/linux-flake-installed-probe.stderr --artifact result-links/flake-installed-probe --copy-artifact-to artifacts/flake-installed-probe -- nix build --print-build-logs --out-link result-links/flake-installed-probe .#checks.x86_64-linux.flake-installed-probe`
  - linux-runtime-candidate: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id ubuntu-22.04-x86_64 --role linux-runtime-candidate --output runs/ubuntu-22.04-x86_64.json --stdout logs/ubuntu-22.04.stdout --stderr logs/ubuntu-22.04.stderr --artifact result-links/ubuntu-22.04 --copy-artifact-to artifacts/ubuntu-22.04 -- nix build --print-build-logs --out-link result-links/ubuntu-22.04 .#checks.x86_64-linux.ubuntu-22_04`
  - linux-runtime-candidate: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id ubuntu-24.04-x86_64 --role linux-runtime-candidate --output runs/ubuntu-24.04-x86_64.json --stdout logs/ubuntu-24.04.stdout --stderr logs/ubuntu-24.04.stderr --artifact result-links/ubuntu-24.04 --copy-artifact-to artifacts/ubuntu-24.04 -- nix build --print-build-logs --out-link result-links/ubuntu-24.04 .#checks.x86_64-linux.ubuntu-24_04`
  - linux-runtime-candidate: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id ubuntu-26.04-x86_64 --role linux-runtime-candidate --output runs/ubuntu-26.04-x86_64.json --stdout logs/ubuntu-26.04.stdout --stderr logs/ubuntu-26.04.stderr --artifact result-links/ubuntu-26.04 --copy-artifact-to artifacts/ubuntu-26.04 -- nix build --print-build-logs --out-link result-links/ubuntu-26.04 .#checks.x86_64-linux.ubuntu-26_04`
  - linux-runtime-candidate: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id debian-12-x86_64 --role linux-runtime-candidate --output runs/debian-12-x86_64.json --stdout logs/debian-12.stdout --stderr logs/debian-12.stderr --artifact result-links/debian-12 --copy-artifact-to artifacts/debian-12 -- nix build --print-build-logs --out-link result-links/debian-12 .#checks.x86_64-linux.debian-12`
  - linux-runtime-candidate: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- execute --run-id debian-13-x86_64 --role linux-runtime-candidate --output runs/debian-13-x86_64.json --stdout logs/debian-13.stdout --stderr logs/debian-13.stderr --artifact result-links/debian-13 --copy-artifact-to artifacts/debian-13 -- nix build --print-build-logs --out-link result-links/debian-13 .#checks.x86_64-linux.debian-13`
  - macos-current-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --run-id macos-current-aarch64 --role macos-current-stable --output ../runs/macos-current-aarch64.json --stdout ../logs/macos-current.stdout --stderr ../logs/macos-current.stderr --artifact build/macos/Build/Products/Release --copy-artifact-to ../artifacts/macos-current -- flutter build macos --release`
  - macos-current-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --append --run-id macos-current-aarch64 --role macos-current-stable --output ../runs/macos-current-aarch64.json --stdout ../logs/macos-current-probe.stdout --stderr ../logs/macos-current-probe.stderr --artifact ../artifacts/macos-current-probe.json -- build/macos/Build/Products/Release/harness.app/Contents/MacOS/harness --burlmd-packaging-probe ../artifacts/macos-current-probe.json`
  - macos-current-stable: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- handoff export --run-id macos-current-aarch64 --run-file runs/macos-current-aarch64.json --artifact-dir artifacts/macos-current --output handoff/outbox/macos-current-aarch64.tar.zst --sha256-output handoff/outbox/macos-current-aarch64.sha256`
  - macos-previous-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --run-id macos-previous-aarch64 --role macos-previous-stable --output ../runs/macos-previous-aarch64.json --stdout ../logs/macos-previous.stdout --stderr ../logs/macos-previous.stderr --artifact build/macos/Build/Products/Release --copy-artifact-to ../artifacts/macos-previous -- flutter build macos --release`
  - macos-previous-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --append --run-id macos-previous-aarch64 --role macos-previous-stable --output ../runs/macos-previous-aarch64.json --stdout ../logs/macos-previous-probe.stdout --stderr ../logs/macos-previous-probe.stderr --artifact ../artifacts/macos-previous-probe.json -- build/macos/Build/Products/Release/harness.app/Contents/MacOS/harness --burlmd-packaging-probe ../artifacts/macos-previous-probe.json`
  - macos-previous-stable: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- handoff export --run-id macos-previous-aarch64 --run-file runs/macos-previous-aarch64.json --artifact-dir artifacts/macos-previous --output handoff/outbox/macos-previous-aarch64.tar.zst --sha256-output handoff/outbox/macos-previous-aarch64.sha256`
  - coordinator-transfer: `cd .constitution/prototypes/packaging && mkdir -p handoff/inbox && scp "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-aarch64.tar.zst" "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-aarch64.sha256" "$BURLMD_MACOS_PREVIOUS_HANDOFF_SOURCE/macos-previous-aarch64.tar.zst" "$BURLMD_MACOS_PREVIOUS_HANDOFF_SOURCE/macos-previous-aarch64.sha256" handoff/inbox/`
  - coordinator: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- aggregate --contract ../../tech-spec/contracts/provisional-spikes.toml --schema ../../tech-spec/contracts/spike-result.schema.json --import-bundle handoff/inbox/macos-current-aarch64.tar.zst --import-sha256 handoff/inbox/macos-current-aarch64.sha256 --import-bundle handoff/inbox/macos-previous-aarch64.tar.zst --import-sha256 handoff/inbox/macos-previous-aarch64.sha256 --require-role linux-flake-check --require-role linux-build --require-role linux-flake-install --require-role linux-installed-runtime=2 --require-role linux-runtime-candidate=5 --require-role macos-current-stable --require-role macos-previous-stable --require-distinct-macos-versions=2 --output results.json`
- **Expected Success Output:** exit 0 with finalized multi-host schema-valid evidence and OD-08 recommendation
- **STOP Conditions:**
  - STOP if the harness uses ambient Git, omits installed-runtime probes, or infers one Platform result from another.
  - STOP at the 3-day time box and leave unsupported hosts outside the recommendation.
- **Description:** Build and install the representative harness as AppImage, tagged Nix Flake package, and unsigned Apple Silicon archive across the required Linux and macOS matrix.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Unique hashed/logged runs verify installed Git/runtime, secure storage, file selection, native loading, secret injection, update selection, host chrome, repeatability, two current macOS majors, and every named Linux candidate. Nix out-links are only build sources: the result tool copies their resolved bytes or closures into `artifacts/` inside the Spike allowlist before size/SHA-256 recording and aggregation. The report selects or refuses a baseline.
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
  - STOP if the fix can hide a real ordering failure, rely on wall-clock coincidence, or weaken the authoritative-success state comparison.
- **Description:** Replace the one-second `last_modified` race in the existing structural-draft authoritative-success regression with deterministic clock/state evidence while preserving the production invariant and exact state comparison.
- **Acceptance:**
  - **Mode:** stat_threshold
  - **Evidence:**

```text
Metric: targeted-test failures. Dataset: 100 consecutive isolated repetitions after one ordinary run. Threshold: 0 failures and no skipped assertion. Command: the exact verification command above. The assertion still distinguishes authoritative success from rollback/failure without depending on wall-clock second boundaries.
```

#### CI-M003 Establish the Linux and Apple Silicon macOS PR matrix
- **Type:** Chore
- **Effort:** 8
- **Dependencies:** FLAKE-M002
- **Category:** DX
- **Scope (In-Scope Files):**
  - `.github/workflows/**`
  - `devenv.nix`
  - `devenv.lock`
  - `scripts/**`
- **Scope (Out-of-Scope Files):**
  - Live canary secrets on fork-originated PRs
- **Verification Command:** x86-64 Linux runner: `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test integration_test && ./scripts/check-generated-bindings.sh && flutter test && xvfb-run -a flutter test integration_test -d linux -r github && dart analyze && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-os linux --require-arch x86_64 --require-os macos --require-arch arm64 && git diff --check`; Apple Silicon macOS runner: `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test integration_test && ./scripts/check-generated-bindings.sh && flutter test && flutter test integration_test -d macos -r github && dart analyze && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-os linux --require-arch x86_64 --require-os macos --require-arch arm64 && git diff --check`.
- **Expected Success Output:** both runners exit 0, execute the desktop integration suite on their actual device target, and pass workflow syntax/matrix validation
- **STOP Conditions:**
  - STOP if CI uses unpinned ambient Git/toolchains or exposes protected secrets to fork workflows.
- **Description:** Add a non-mutating `scripts/check-generated-bindings.sh` gate that snapshots `lib/src/rust/**` and `rust/src/frb_generated.rs`, reruns the final Stage 3 generator, compares every byte, restores both outputs after a mismatch, and fails when regeneration changes either side. Run that gate with formatting, static analysis, workflow lint/matrix assertions, Rust/Flutter tests, and hermetic integration tests on x86-64 Linux and Apple Silicon macOS using the repository's reproducibility boundary.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Both required runners execute equivalent gates from pinned inputs, including every `integration_test/` file on the actual Linux or macOS desktop target; the Linux job provisions its display through Xvfb. Fixture tests prove the generated-binding gate covers the Dart and Rust FRB outputs, exits 0 for idempotent output, exits nonzero for either stale side, reports the changed paths, and leaves the pre-check working tree unchanged. Formatting, Clippy, workflow syntax, and matrix assertions are executable; CI also detects forbidden debug markers, caches without weakening lock verification, and keeps live credentials outside untrusted PR jobs.
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
- **Verification Command:** Linux reference host: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id linux-reference --expected-host-profile linux-i5-8250u-16gib --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-linux.json && git diff --check`; Apple Silicon macOS reference host: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id macos-reference --expected-host-profile macos-m1-8gib --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-macos.json && git diff --check`; coordinator: `./scripts/aggregate-prd-meters.sh --require-run linux-reference=.constitution/reports/nightly-prd-meters-linux.json --require-run macos-reference=.constitution/reports/nightly-prd-meters-macos.json --require-distinct-hosts 2 --output .constitution/reports/nightly-prd-meters.json && git diff --check`.
- **Expected Success Output:** deterministic corpus generation succeeds on both distinct reference hosts and aggregation emits one machine-readable nonblocking result for every meter
- **STOP Conditions:**
  - STOP if a meter uses a different corpus/profile/definition than PRD constraints or changes a threshold outside Product Requirements Evolution.
- **Description:** Generate the 10,000-Note and editing corpora and measure search, UI, open, cold start, idle memory, external changes, capacity, image, history health, and synchronization freshness on named profiles.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
Each host report records a verified host identity, unique run ID, profile, corpus hash, samples, percentile/threshold, exact command, and Goal/Fail disposition for every scalar PRD meter. Aggregation rejects a missing, duplicated, or same-host pair. The nightly job is nonblocking during 0.x but produces a durable regression report; release gates consume the same definitions.
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
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test && dart analyze && ./scripts/smoke-shot.sh migrate-m005 && git diff --check`
- **Expected Success Output:** exit 0 with backup, forward migration, rebuild, fault injection, rollback, and later-version refusal tests passing
- **STOP Conditions:**
  - STOP if migration can partially publish, changes Markdown unnecessarily, or destroys the only usable prior state before success.
- **Description:** Version application state, back up affected data, migrate forward atomically, rebuild derived index state when safer, restore backup on failure, and report unsupported future versions.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
Fault injection at every migration step leaves either the complete prior state or complete new state; backup remains recoverable until validation; Workspace Markdown stays unchanged unless the accepted path migration explicitly requires it; later versions are refused unchanged.
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
- **Verification Command:** `flutter build macos --release && git diff --check`
- **Expected Success Output:** the unsigned Apple Silicon archive is constructed reproducibly with its complete pinned runtime closure and installation disclosure
- **STOP Conditions:**
  - STOP if final TechSpec hasn't accepted PKG-M001, the archive uses ambient Git, or construction metadata claims installed-host verification owned by GATE-M013.
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
  - STOP if a version isn't `0.x`, any candidate lacks checksum/provenance, or metadata claims an untested system.
- **Description:** Build immutable candidate AppImage and Apple Silicon archives plus the release-tagged Flake input from one revision, generate checksums/provenance/licenses/disclosures, and retain them unpublished for installed verification.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Independent verification reproduces every SHA-256 and provenance subject from immutable candidate bytes/source revision; compatibility labels match intended systems; unsigned macOS warnings are explicit; candidates remain unpublished and install without source builds.
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
- **Verification Command:** Run the accepted x86-64 AppImage installed matrix from final TechSpec against the immutable `RELEASE-M009` candidate on every accepted Linux runtime, then `git diff --check`.
- **Expected Success Output:** the candidate hash passes the identical release-blocking matrix on every accepted x86-64 Linux runtime
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed AppImage matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, artifact mismatch, or PRD Fail threshold.
- **Description:** Install the immutable AppImage candidate on every accepted Linux runtime and gate it on local editing/session behavior, authority/monitoring, Assets/Object Store, Export/Consolidation, private GitHub sync, every reconciliation form, secure storage, diagnostics, migration, recovery, and update notification.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
The same versioned matrix passes for the AppImage candidate on every accepted Linux runtime. Evidence records candidate hash, host, app/source version, all P0 outcomes, PRD meters, private GitHub canary, S3-compatible credentials, interruption recovery, diagnostics content exclusion, and update notification. Any failure blocks publication.
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
- **Verification Command:** Run the accepted Nix installed matrix from final TechSpec against the immutable `RELEASE-M009` Flake candidate on every exposed x86-64 Linux system, then `git diff --check`.
- **Expected Success Output:** the candidate revision passes the identical release-blocking matrix through a clean NixOS/Home Manager import
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed Nix matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, closure mismatch, or PRD Fail threshold.
- **Description:** Import and install the immutable Flake candidate through clean NixOS/Home Manager fixtures and run the same complete application matrix without bypassing Nix upgrade authority.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Clean evaluation, build, import, install, and matrix probes reproduce the candidate revision and closure. Evidence records the same P0, privacy, meter, integration, and recovery outcomes as the AppImage gate. Any failure blocks publication.
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
- **Verification Command:** Run the accepted Apple Silicon installed matrix from final TechSpec against the immutable `RELEASE-M009` archive on the two current stable macOS major versions, then `git diff --check`.
- **Expected Success Output:** one candidate hash passes the identical release-blocking matrix on both required Apple Silicon macOS versions
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed macOS matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, artifact mismatch, PRD Fail threshold, or inaccurate unsigned-install disclosure.
- **Description:** Install the immutable unsigned archive candidate on distinct hosts for both supported macOS majors and run the same complete application matrix plus Gatekeeper-disclosure checks.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Both macOS hosts record the same candidate hash and complete P0, privacy, meter, integration, recovery, update, and host-chrome outcomes. Unsigned installation instructions are accurate. Any failure blocks publication.
```

#### PUBLISH-M014 Publish the verified GitHub `0.x` prerelease
- **Type:** Chore
- **Effort:** 5
- **Dependencies:** GATE-M011, GATE-M012, GATE-M013
- **Category:** Security
- **Scope (In-Scope Files):**
  - `.github/workflows/**`
  - `scripts/**`
  - `CHANGELOG.md`
- **Scope (Out-of-Scope Files):**
  - Rebuilding candidates during publication, stable signing/notarization, and automatic binary replacement
- **Verification Command:** Run the accepted GitHub prerelease publication and remote verification commands from final TechSpec for the already-gated candidate hashes, then `git diff --check`.
- **Expected Success Output:** one GitHub `0.x` prerelease exposes exactly the gated immutable artifacts, checksums, provenance, compatibility labels, source revision, licenses, and unsigned disclosures
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the GitHub publication placeholder with exact accepted commands.
  - STOP if any published byte differs from the gated candidate, any gate is missing, the version isn't `0.x`, or metadata claims an untested system.
- **Description:** Publish the already-gated AppImage and Apple Silicon archive, expose the gated release-tagged Flake revision, attach their existing checksums/provenance/licenses, and mark the GitHub Release as a prerelease without rebuilding.
- **Acceptance:**
  - **Mode:** runbook_probe
  - **Evidence:**

```text
Remote verification matches every published byte and Flake revision to the three gate reports and candidate provenance. The release is marked prerelease, compatibility and unsigned disclosures are accurate, and no publication step rebuilt an artifact.
```
