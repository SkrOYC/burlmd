---
version: v2.1.19
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
  - macos-current-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --run-id macos-release-a --role macos-current-stable --expected-os macos --expected-arch aarch64 --expected-os-major 26 --output ../runs/macos-release-a.json --stdout ../logs/macos-release-a.stdout --stderr ../logs/macos-release-a.stderr --artifact ../artifacts/burlmd-macos-aarch64-a.tar.gz -- ./scripts/build-macos-release.sh --output-archive ../artifacts/burlmd-macos-aarch64-a.tar.gz --source-date-epoch-from-git HEAD`
  - macos-current-stable: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- archive extract --run-id macos-release-a --append-run runs/macos-release-a.json --archive artifacts/burlmd-macos-aarch64-a.tar.gz --output-dir artifacts/macos-release-a-extracted --require-single-app harness.app --preserve-mode --preserve-symlinks --preserve-xattrs --reject-path-escape`
  - macos-current-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --append --run-id macos-release-a --role macos-current-stable --expected-os macos --expected-arch aarch64 --expected-os-major 26 --output ../runs/macos-release-a.json --stdout ../logs/macos-release-a-probe.stdout --stderr ../logs/macos-release-a-probe.stderr --artifact ../artifacts/burlmd-macos-aarch64-a.tar.gz --artifact ../artifacts/macos-release-a-probe.json -- ../artifacts/macos-release-a-extracted/harness.app/Contents/MacOS/harness --burlmd-packaging-probe ../artifacts/macos-release-a-probe.json`
  - macos-repeat-construction: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --run-id macos-release-b --role macos-repeat-construction --expected-os macos --expected-arch aarch64 --expected-os-major 26 --output ../runs/macos-release-b.json --stdout ../logs/macos-release-b.stdout --stderr ../logs/macos-release-b.stderr --artifact ../artifacts/burlmd-macos-aarch64-b.tar.gz -- ./scripts/build-macos-release.sh --output-archive ../artifacts/burlmd-macos-aarch64-b.tar.gz --source-date-epoch-from-git HEAD`
  - macos-current-export: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- handoff export --run-id macos-current-handoff --run-file runs/macos-release-a.json --run-file runs/macos-release-b.json --artifact artifacts/burlmd-macos-aarch64-a.tar.gz --artifact artifacts/burlmd-macos-aarch64-b.tar.gz --output handoff/outbox/macos-current-construction.tar.zst --sha256-output handoff/outbox/macos-current-construction.sha256`
  - macos-previous-import: `cd .constitution/prototypes/packaging && mkdir -p handoff/current-inbox && scp "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-construction.tar.zst" "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-construction.sha256" handoff/current-inbox/`
  - macos-previous-import: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- handoff import --bundle handoff/current-inbox/macos-current-construction.tar.zst --sha256 handoff/current-inbox/macos-current-construction.sha256 --artifact artifacts/burlmd-macos-aarch64-a.tar.gz --copy-artifact-to artifacts/burlmd-macos-aarch64-under-test.tar.gz`
  - macos-previous-stable: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- archive extract --archive artifacts/burlmd-macos-aarch64-under-test.tar.gz --output-dir artifacts/macos-release-under-test --require-single-app harness.app --preserve-mode --preserve-symlinks --preserve-xattrs --reject-path-escape`
  - macos-previous-stable: `cd .constitution/prototypes/packaging/harness && cargo run --locked --release --manifest-path ../result-tool/Cargo.toml -- execute --run-id macos-previous-aarch64 --role macos-previous-stable --expected-os macos --expected-arch aarch64 --expected-os-major 15 --output ../runs/macos-previous-aarch64.json --stdout ../logs/macos-previous-probe.stdout --stderr ../logs/macos-previous-probe.stderr --artifact ../artifacts/burlmd-macos-aarch64-under-test.tar.gz --artifact ../artifacts/macos-previous-probe.json -- ../artifacts/macos-release-under-test/harness.app/Contents/MacOS/harness --burlmd-packaging-probe ../artifacts/macos-previous-probe.json`
  - macos-previous-export: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- handoff export --run-id macos-previous-handoff --run-file runs/macos-previous-aarch64.json --artifact artifacts/burlmd-macos-aarch64-under-test.tar.gz --output handoff/outbox/macos-previous-probe.tar.zst --sha256-output handoff/outbox/macos-previous-probe.sha256`
  - coordinator-transfer: `cd .constitution/prototypes/packaging && mkdir -p handoff/inbox && scp "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-construction.tar.zst" "$BURLMD_MACOS_CURRENT_HANDOFF_SOURCE/macos-current-construction.sha256" "$BURLMD_MACOS_PREVIOUS_HANDOFF_SOURCE/macos-previous-probe.tar.zst" "$BURLMD_MACOS_PREVIOUS_HANDOFF_SOURCE/macos-previous-probe.sha256" handoff/inbox/`
  - coordinator: `cd .constitution/prototypes/packaging && cargo run --locked --release --manifest-path result-tool/Cargo.toml -- aggregate --contract ../../tech-spec/contracts/provisional-spikes.toml --schema ../../tech-spec/contracts/spike-result.schema.json --import-bundle handoff/inbox/macos-current-construction.tar.zst --import-sha256 handoff/inbox/macos-current-construction.sha256 --import-bundle handoff/inbox/macos-previous-probe.tar.zst --import-sha256 handoff/inbox/macos-previous-probe.sha256 --require-role linux-flake-check --require-role linux-build --require-role linux-flake-install --require-role linux-installed-runtime=2 --require-role linux-runtime-candidate=5 --require-role macos-current-stable --require-role macos-repeat-construction --require-role macos-previous-stable --require-role-os linux-flake-check=linux --require-role-os linux-build=linux --require-role-os linux-flake-install=linux --require-role-os linux-installed-runtime=linux --require-role-os linux-runtime-candidate=linux --require-role-arch linux-flake-check=x86_64 --require-role-arch linux-build=x86_64 --require-role-arch linux-flake-install=x86_64 --require-role-arch linux-installed-runtime=x86_64 --require-role-arch linux-runtime-candidate=x86_64 --require-verified-runtime ubuntu-22.04-x86_64=ubuntu:22.04:x86_64 --require-verified-runtime ubuntu-24.04-x86_64=ubuntu:24.04:x86_64 --require-verified-runtime ubuntu-26.04-x86_64=ubuntu:26.04:x86_64 --require-verified-runtime debian-12-x86_64=debian:12:x86_64 --require-verified-runtime debian-13-x86_64=debian:13:x86_64 --require-distinct-role-hosts macos-current-stable=macos-previous-stable --require-same-role-host macos-current-stable=macos-repeat-construction --require-role-os macos-current-stable=macos --require-role-os macos-previous-stable=macos --require-role-arch macos-current-stable=aarch64 --require-role-arch macos-previous-stable=aarch64 --require-role-os-major macos-current-stable=26 --require-role-os-major macos-previous-stable=15 --require-same-artifact-sha256 macos-current-stable:artifacts/burlmd-macos-aarch64-a.tar.gz=macos-previous-stable:artifacts/burlmd-macos-aarch64-under-test.tar.gz --require-repeatable-artifact macos-current-stable:artifacts/burlmd-macos-aarch64-a.tar.gz=macos-repeat-construction:artifacts/burlmd-macos-aarch64-b.tar.gz --output results.json`
- **Expected Success Output:** exit 0 with finalized multi-host schema-valid evidence and OD-08 recommendation
- **STOP Conditions:**
  - STOP if the harness uses ambient Git, omits installed-runtime probes, or infers one Platform result from another.
  - STOP and reconcile the contract if Apple's published stable-version list no longer identifies macOS 26 and macOS 15 as the two most recent stable major versions.
  - STOP at the 3-day time box and leave unsupported hosts outside the recommendation.
- **Description:** Build and install the representative harness as AppImage, tagged Nix Flake package, and unsigned Apple Silicon archive across the required Linux and macOS matrix. Prove the checksum and provenance-metadata layout inside the prototype; authenticated GitHub Actions attestation creation remains production workflow work owned by RELEASE-M009 and PUBLISH-M014.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Unique hashed and logged runs verify installed Git/runtime, secure storage, file selection, native loading, secret injection, update selection, host chrome, repeatability, and every named Linux candidate. The result tool obtains host fingerprints, operating systems, architectures, and versions from system APIs; command flags only assert expected values. Aggregation binds every Linux build/install role to a recorded Linux/x86-64 host. Each named runtime check obtains guest operating system, distribution, version, and architecture from inside the installed probe environment; aggregation requires exact Ubuntu 22.04, 24.04, and 26.04 plus Debian 12 and 13 x86-64 evidence rather than trusting run IDs or the outer Nix host. The versioned build script runs `flutter clean`, enforces the committed dependency lock, normalizes archive metadata from the source revision's epoch, and emits the actual deterministic `.tar.gz` release artifact for each construction. One macOS 26 host constructs that archive twice from identical inputs; aggregation requires byte-identical archive hashes. Extraction rejects path escape and proves the archive preserves required modes, symlink targets, extended attributes, and a single application bundle. The first archive is transferred with SHA-256 verification, extracted, and probed on both the macOS 26 construction host and a distinct macOS 15 host. Aggregation requires both probes to name the same archive SHA-256. Nix out-links are only build sources: the result tool copies their resolved bytes or closures into `artifacts/` inside the Spike allowlist before size and SHA-256 recording. The report selects or refuses a baseline.
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
- **Verification Command:** x86-64 Linux runner: `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test integration_test && ./scripts/check-generated-bindings.sh && flutter test && xvfb-run -a flutter test integration_test -d linux -r github && dart analyze && ! rg -n '\[DEBUG-' lib rust test scripts && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-os linux --require-arch x86_64 --require-os macos --require-arch arm64 && git diff --check`; Apple Silicon macOS runner: `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test integration_test && ./scripts/check-generated-bindings.sh && flutter test && flutter test integration_test -d macos -r github && dart analyze && ! rg -n '\[DEBUG-' lib rust test scripts && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-os linux --require-arch x86_64 --require-os macos --require-arch arm64 && git diff --check`.
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
- **Verification Command:** Linux reference host: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id linux-reference --expected-host-profile linux-i5-8250u-16gib --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-linux.json && git diff --check`; Apple Silicon macOS reference host: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/bench-prd-meters.sh --all --run-id macos-reference --expected-host-profile macos-m1-8gib --corpus-size 10000 --output .constitution/reports/nightly-prd-meters-macos.json && git diff --check`; coordinator: `./scripts/aggregate-prd-meters.sh --require-run linux-reference=.constitution/reports/nightly-prd-meters-linux.json --require-run macos-reference=.constitution/reports/nightly-prd-meters-macos.json --require-distinct-hosts 2 --require-same-corpus-hash --require-same-meter-definition-version --output .constitution/reports/nightly-prd-meters.json && git diff --check`.
- **Expected Success Output:** deterministic corpus generation succeeds on both distinct reference hosts and aggregation emits one machine-readable nonblocking result for every meter
- **STOP Conditions:**
  - STOP if a meter uses a different corpus/profile/definition than PRD constraints or changes a threshold outside Product Requirements Evolution.
- **Description:** Generate the 10,000-Note and editing corpora and measure search, UI, open, cold start, idle memory, external changes, capacity, image, history health, and synchronization freshness on named profiles.
- **Acceptance:**
  - **Mode:** benchmark
  - **Evidence:**

```text
Each host report records a verified host identity, unique run ID, profile, corpus hash, meter-definition version, samples, percentile/threshold, exact command, and Goal/Fail disposition for every scalar PRD meter. Aggregation rejects a missing, duplicated, same-host, corpus-mismatched, or meter-definition-mismatched pair. The nightly job is nonblocking during 0.x but produces a durable regression report; release gates consume the same definitions.
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
  - STOP if a version isn't `0.x`, any candidate lacks checksum or a cryptographically verified GitHub Actions attestation, the attestation identity doesn't match the expected repository/workflow/revision, or metadata claims an untested system.
- **Description:** Build immutable candidate AppImage and Apple Silicon archives plus the release-tagged Flake input and source archive from one revision. Generate checksums, licenses, disclosures, and keyless GitHub Actions artifact attestations using `actions/attest@v4` pinned to a verified full commit SHA with `id-token: write`, `contents: read`, and `attestations: write`; retain the candidates unpublished for installed verification. The accepted contract binds the GitHub/Sigstore trust root, `SkrOYC/burlmd`, the release workflow identity, release ref, source revision, and every artifact subject. Developer ID signing and notarization remain deferred.
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
- **Verification Command:** Run the accepted x86-64 AppImage installed matrix from final TechSpec against the immutable `RELEASE-M009` candidate on every accepted Linux runtime, then `git diff --check`.
- **Expected Success Output:** the candidate hash passes the identical release-blocking matrix on every accepted x86-64 Linux runtime
- **STOP Conditions:**
  - STOP if final Stage 3 hasn't replaced the installed AppImage matrix placeholder with exact accepted commands.
  - STOP release on any missing P0 capability, privacy/content leak, failed recovery path, artifact mismatch, or PRD Fail threshold.
- **Description:** Install the immutable AppImage candidate on every accepted Linux runtime and gate it on local editing/session behavior, authority/monitoring, Assets/Object Store, Export, connection-time Consolidation before initial publication, private GitHub sync, every reconciliation form, secure storage, diagnostics, migration, recovery, and update notification.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
The same versioned matrix passes for the AppImage candidate on every accepted Linux runtime. Evidence records candidate hash, host, app/source version, all P0 outcomes, PRD meters, private GitHub canary, S3-compatible credentials, interruption recovery, diagnostics content exclusion, and update notification. The matrix connects a local Workspace, enters Consolidation, resolves a collision, and proves that initial Remote publication waits for the atomic Consolidation result. Any failure blocks publication.
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
- **Description:** Query Apple's official stable-version source, record the observed two-major pair and timestamp, then install the immutable unsigned archive candidate on distinct hosts for both current supported macOS majors and run the same complete application matrix plus Gatekeeper-disclosure checks.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Both macOS hosts record the same candidate hash, Apple's observed stable-major pair and source timestamp, and complete P0, privacy, meter, integration, recovery, update, and host-chrome outcomes. Unsigned installation instructions are accurate. Any failure blocks publication.
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
