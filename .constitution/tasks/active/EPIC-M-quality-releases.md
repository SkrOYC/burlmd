---
version: v2.2.7
status: active
epic: M
---

# Epic M: Quality, diagnostics, packaging, and releases

Make the complete desktop application supportable, measurable, installable, migratable, and releasable through GitHub `0.x` prereleases. The bootstrap tranche makes only `FLAKE-M002` and `CI-M003` executable production work. PKG-M001 runs after that tranche for packaging-dependent work; later production tickets remain blocked until their own evidence, required upstream finalization, and Stage 4 adaptation are merged.

**Bootstrap tranche:** Create `chore/epic-m-ci-foundation` from merged `master`. Execute `FLAKE-M002` and the `CI-M003` implementation, with one full milestone review after each ticket, then independently review and rebase-merge the implementation pull request. Its resulting `master` tip is `TRUST_ANCHOR_SHA`. From that clean detached anchor, validate the merged pipeline against the same SHA. Put only the accepted CI report and completion record on `docs/epic-m-ci-evidence`; independently review and merge this second pull request. `CI-M003` remains incomplete and satisfies no dependency before the second merge. The committed, validated, and independently reviewed `FLAKE-M002` milestone satisfies the implementation within the first branch. Cross-tranche and cross-branch prerequisites must be merged into the base. This partial tranche doesn't archive Epic M.

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
- **Verification Command:** After the `CI-M003` evidence pull request merges and the tested source is pushed, run `TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket PKG-M001 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/packaging/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check`. The clean detached trust-anchor client rejects any base-to-source change outside the packaging write allowlist before dispatch and during collection. The trusted workflow runs the ordered `SPK-PKG-M001.verification_steps`; macOS 15 consumes only the verified macOS 26 sealed bundle. Before authentication, the client builds and identifies the locked result tool. After verifying both jobs and exact candidate and sealed artifacts for each role and tearing down credentials, it runs the prebuilt tool in the nonnetwork sandbox and validates `.constitution/prototypes/packaging/results.json`. The raw contract is the sole authority for these commands and their order.
- **Expected Success Output:** exit 0 with `.constitution/prototypes/packaging/results.json`, accepted `.constitution/prototypes/packaging/managed-evidence.json`, executor-authored `.constitution/spikes/SPK-PKG-M001.md`, and an OD-08 recommendation
- **STOP Conditions:**
  - STOP if the harness uses ambient Git, omits installed-runtime probes, or infers one Platform result from another.
  - STOP if the `CI-M003` evidence pull request isn't merged or any required role bundle is missing, incomplete, stale, mismatched, corrupt, self-hosted, unauthenticated, or rejected.
  - STOP if post-completion API observation doesn't resolve the receipt locator to one completed successful sealing job on the fixed hosted label, or if an expected, candidate, or sealed artifact name or normalized digest is invalid, missing, duplicate, extra, or inconsistent with the run nonce.
  - STOP if the launcher isn't the clean trust-anchor copy, a trusted control file differs at the signer SHA, or the base-to-source diff leaves the packaging write allowlist.
  - STOP if any cross-role archive comes from a manual or environment-selected source, the machine result is missing or invalid, or the evidence commit omits the machine result, accepted managed report, or executor-authored Spike report.
  - STOP if a candidate command or coordinator can observe an authentication or credential canary, the coordinator identity changes after preparation, isolation or its network denial fails, an input is writable, or a path other than its output is writable.
  - STOP and reconcile the contract if Apple's published stable-version list no longer identifies macOS 26 and macOS 15 as the two most recent stable major versions.
  - STOP at the 3-day time box and leave unsupported hosts outside the recommendation.
- **Description:** Build and install the representative harness as AppImage, tagged Nix Flake package, and unsigned Apple Silicon archive across the required Linux and macOS matrix. Authenticate managed role evidence through `CI-M003`. Prove the checksum and provenance-metadata layout inside the prototype; release-candidate attestations remain production workflow work owned by RELEASE-M009 and PUBLISH-M014.
- **Acceptance:**
  - **Mode:** hitl_sil
  - **Evidence:**

```text
Unique hashed and logged runs verify installed Git and runtime, secure storage, file selection, native loading, secret injection, update selection, host chrome, repeatability, and every named Linux candidate. The Linux role provides `packaging-runtime`; macOS 26 provides `packaging-runtime` and `repeatable-construction`; macOS 15 provides `packaging-runtime-compatibility`. This Spike doesn't claim performance, Linux platform-regression, or authoritative macOS visual evidence. Every candidate job produces an untrusted bundle containing the manifest plus every named result, log, raw measurement, and handoff without token, artifact-runtime, OIDC, or attestation access. A fresh dependent sealing job validates the immutable bundle and alone authenticates the sealed artifact. Aggregation verifies the exact packaging evidence profile, trust anchor, workflow signer, separate tested source, ticket base, packaging allowlist, sealing provenance, bundle integrity, and internal artifact hashes. Each named runtime check obtains guest operating system, distribution, version, and architecture from inside the installed probe environment; aggregation requires exact Ubuntu 22.04, 24.04, and 26.04 plus Debian 12 and 13 x86-64 evidence rather than trusting run IDs or the outer Nix host. The versioned build script runs `flutter clean`, enforces the committed dependency lock, normalizes archive metadata from the source revision's epoch, and emits the actual deterministic `.tar.gz` release artifact for each construction. macOS 26 constructs that archive twice from identical inputs; aggregation requires byte-identical archive hashes. Extraction rejects path escape and proves the archive preserves required modes, symlink targets, extended attributes, and one application bundle. The first archive travels in the authenticated macOS 26 sealed bundle. Only after verifying and staging that bundle does the macOS 15 role extract and probe the same bytes. Final aggregation stages all three sealed role bundles under fixed role directories and requires both macOS probes to name the same archive SHA-256. Nix out-links are only build sources: the result tool copies their resolved bytes or closures into `artifacts/` inside the Spike allowlist before size and SHA-256 recording. The aggregate records the prebuilt result-tool identity and proves no network, credential, writable input, or host user state entered coordinator execution. The CLI produces authoritative schema-valid `results.json`; the executor authors its human interpretation and commits both with the accepted managed report.
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
  1. Implement `scripts/check-generated-bindings.sh` from the exact Stage 3 checker contract. Test clean, stale, generator-failure, added-file, removed-file, premodified-file, and interruption cases. Every case must leave `rust/src/frb_generated.rs` and `lib/src/rust/**` byte-identical to their precheck state.
  2. Implement `scripts/assert-managed-evidence-isolation.sh` from the exact Stage 3 fixture contract. The trusted launcher must enumerate and close nonallowlisted descriptors; include a non-`CLOEXEC` descriptor canary. Pin Linux-only `pkgs.bubblewrap` from the locked Nixpkgs revision in `devenv.nix`, and require Bubblewrap `0.11.2` for namespace, network, and filesystem isolation only. Add contract fixtures for the two-job role topology, least-privilege permissions, run-to-artifact nonce derivation, forbidden artifact-name characters, and duplicate or pre-uploaded reserved names. Linux fixtures must run `env -i` candidate code in a private Bubblewrap PID namespace and reject a surviving double-fork probe before upload. Hosted-macOS fixtures must prove fresh-job separation, candidate no-privilege permissions, seal-only authority, and no candidate-byte execution in seal. They must reject a universal macOS containment or zero-survivor assertion. Receipt fixtures must reject any final status, conclusion, or completion field. Post-completion fixtures must accept one successful locator match and reject in-progress, failed, missing, duplicate, wrong-job, wrong-label, and self-hosted matches. Digest fixtures must prove bare action output to canonical REST conversion and reject prefix, case, or byte mismatch. In a disposable checkout, run `cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test test_driver integration_test && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ! rg -n '\[DEBUG-' lib rust test scripts && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-24.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json && ./scripts/assert-managed-evidence-isolation.sh --contract .constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2 && git diff --check`.
  3. Commit and independently review the `CI-M003` milestone on `chore/epic-m-ci-foundation`. Open a ready implementation pull request, obtain independent pull-request review, and rebase-merge it into `master`. Record the resulting full `master` tip as `TRUST_ANCHOR_SHA`; don't treat the ticket as complete.
  4. Create a clean detached `TRUST_ANCHOR_WORKTREE` at `TRUST_ANCHOR_SHA` and create `EVIDENCE_WORKTREE` on `docs/epic-m-ci-evidence` from that merged `master`. Set `BASE_SHA` to the rebased, reviewed `FLAKE-M002` milestone at the trust anchor's first parent. Run `TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket CI-M003 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref refs/heads/master --tested-source-sha TRUST_ANCHOR_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/reports/ci-m003-managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check`.
  5. In the minimally privileged Linux `candidate` job, the trusted workflow runs `./scripts/check-generated-bindings.sh && flutter test && dart analyze && flutter test integration_test -d linux -r github && ./scripts/assert-managed-evidence-isolation.sh --contract .constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2` through `env -i` in its private Bubblewrap PID namespace. It rejects a surviving double-fork probe before upload. On both Apple Silicon macOS roles, it runs `flutter test && dart analyze && flutter test integration_test -d macos -r github`, then performs bounded cleanup of known test processes without claiming universal containment. The dependent `seal` job validates and authenticates the untrusted bundle on a fresh environment with the same fixed role label and never executes candidate bytes.
  6. In `EVIDENCE_WORKTREE`, add `.constitution/reports/ci-m003-completion.md` with the anchor SHA, workflow signer SHA, tested-source SHA, run identity, accepted report digest, implementation pull request, and review evidence. Commit exactly that file and the accepted JSON report. Open, independently review, and merge the ready evidence pull request. Only this merge completes `CI-M003`.
- **Expected Success Output:** local validation exits 0; the reviewed implementation merge establishes `TRUST_ANCHOR_SHA`; all three roles finish their assigned common-functional, analysis, integration, protocol, and security classes without credential access; Linux also finishes generated-binding and managed-isolation classes; no role claims performance or visual evidence; the dedicated evidence pull request contains only the accepted report and completion record and merges after independent review
- **STOP Conditions:**
  - STOP if `FLAKE-M002` isn't committed, validated, and independently reviewed in `chore/epic-m-ci-foundation` or the branch wasn't created from merged `master`.
  - STOP if implementation imports or cherry-picks from the unmerged Epic G branch. Implement the accepted CI and headless contracts from merged `master`; later surgical replay must preserve this merged foundation.
  - STOP if any gate invokes `scripts/check-generated-bindings.sh` before this ticket implements it or if the checker changes either generated surface from its precheck state on any exit path.
  - STOP if any third-party action isn't pinned to the full Stage 3 commit SHA or a role uses ambient repository toolchains instead of repository locks.
  - STOP if private/internal attestation isn't available; emit `attestation-unavailable` and reject the aggregate without a hash-only fallback.
  - STOP if candidate code defines expected identity, the managed-evidence launcher, or a signer workflow; if validation uses a pull-request merge revision, a dynamic local-workflow `uses` expression, or a self-hosted runner; or if identity doesn't separate trust anchor, workflow signer, tested source, base, and later evidence state.
  - STOP if the implementation hasn't completed local, milestone, and pull-request review before its rebase merge; the launcher isn't running from the clean merged anchor; or `master` differs on any trusted control path.
  - STOP if the evidence pull request changes anything except `.constitution/reports/ci-m003-managed-evidence.json` and `.constitution/reports/ci-m003-completion.md`, lacks independent review, or hasn't merged. `CI-M003` remains incomplete until that merge.
  - STOP if a role bundle omits any manifest-named result, log, raw measurement, or handoff, or if any bundled byte fails its size or SHA-256 check.
  - STOP if a role isn't exactly a successful `candidate` job followed by a fresh `seal` job, candidate has OIDC, attestation, or Actions permission, seal doesn't exclusively own signing authority, or candidate bytes execute in the sealing environment.
  - STOP if Linux candidate code does not run through `env -i` in Bubblewrap `0.11.2` with a private PID namespace, its teardown lock cannot reject a surviving double-fork probe, or the implementation treats hosted macOS bounded cleanup as a universal containment or zero-survivor proof.
  - STOP if a sealing receipt claims final job state, lacks `job.check_run_id`, or is stored inside the sealed bundle that it hashes. Only the post-completion coordinator may construct `origin.sealingJob` after the job API reports one matching completed successful job.
  - STOP if a pinned upload action digest isn't bare lowercase 64-hex or if a REST or aggregate digest isn't exactly `sha256:` plus that action output.
  - STOP if `artifactNonce` isn't the exact lowercase 32-hex suffix of `runIdentity`, an artifact name contains a forbidden character, or an expected, candidate, or sealed artifact is missing, duplicate, extra, pre-uploaded, or substituted.
  - STOP if `run` accepts a managed Spike without staging verified role contents, running its declared coordinator steps, and publishing a valid authoritative machine result.
  - STOP if a candidate command receives `GH_TOKEN`, `GITHUB_TOKEN`, OIDC request capability, an ambient credential or configuration path, or an inherited credential descriptor.
  - STOP if coordinator preparation begins after authentication, uses an unlocked input, or doesn't record and revalidate the executable and closure identity.
  - STOP if Bubblewrap `0.11.2` isn't provided by the locked Linux environment, its namespace or network probe fails, the coordinator sees any credential canary or forbidden client, an input is writable, or anything except its output is writable. There is no credential-clearing-only fallback.
  - STOP if the bootstrap profile claims performance, Linux platform-regression, or authoritative macOS visual evidence. Those obligations belong to later benchmark, shell, and release gates.
  - STOP if the Flutter Rust Bridge generator, Rust crate, or Dart package differs from the provisionally authorized `2.12.0` triple. Use that triple only for bootstrap and require revalidation after final Stage 3.
- **Description:** Add one trusted `workflow_dispatch` caller and three distinct two-job reusable role workflows referenced through static local paths. Each role's `candidate` job has only contents read permission, checks out the separate tested SHA as data, and runs candidate commands without artifact or signing credentials. Linux uses `env -i` and Bubblewrap `0.11.2` private PID containment. Hosted macOS performs bounded cleanup only. Every candidate bundle is untrusted. Its dependent `seal` job starts on a fresh environment, never executes candidate bytes, validates identity, candidate job and label, artifact IDs and REST digests, safe archive structure, schemas, and member hashes, and alone receives OIDC and attestation authority. It uploads the sealed bundle before it writes a separate attested receipt. The receipt records `job.check_run_id`, immutable identities, and normalized expected, candidate, and sealed digest pairs, but no final job result. After the attempt completes, `managed-evidence.sh` resolves that locator through the job API and constructs aggregate `origin.sealingJob` only for a completed successful match. Implement the `collect` and `run` forms, the non-mutating generated-binding checker, and the managed-evidence isolation fixture. Add Linux-only Bubblewrap `0.11.2` through the locked Nix environment. Reproduce the specified behavior without importing the Epic G branch. Pin `actions/checkout` to `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09`, `cachix/install-nix-action` to `13d8dd58da0234aa297dedd986986ccb8e7f3e24`, `actions/upload-artifact` to `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`, `actions/download-artifact` to `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c`, and `actions/attest` to `1e69f48acb82d1966a394da916b4c1698aa569d6`. Generate authoritative trust-anchor, workflow-signer, tested-source, base, release, build, corpus, run, artifact-nonce, required-role, and signer identity before fan-out. The coordinator verifies the post-completion jobs, unique artifacts, receipt and sealed-bundle attestations, canonical digest conversion, provenance, and bundled files before writing an accepted or rejected aggregate.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
The `ubuntu-24.04` role provides `common-functional`, `managed-evidence-protocol`, `managed-evidence-security`, `managed-evidence-isolation`, `generated-binding-check`, `static-analysis`, and `desktop-integration`. The Apple Silicon `macos-26` and `macos-15` roles provide `common-functional`, `managed-evidence-protocol`, `managed-evidence-security`, `static-analysis`, and `desktop-integration`. Each role runs the complete Flutter unit suite, analyzer, and desktop integration gate. The evidence records every integration-test file and result and rejects an empty, skipped, or partially discovered suite. The bootstrap profile doesn't include `performance`, `linux-platform-regression`, or `macos-authoritative-visual`. The Linux environment still owns display, compositor, input, process, state directory, and application PID for functional integration without reading the Writer's desktop. Later benchmark, shell, and release tickets own the performance and visual gates.

The trusted `master` caller invokes `.github/workflows/ci-role-linux-x86-64.yml`, `.github/workflows/ci-role-macos-26-arm64.yml`, and `.github/workflows/ci-role-macos-15-arm64.yml` through static local paths. Each role workflow resolves from `WORKFLOW_SIGNER_SHA` and contains exactly `candidate` and `seal` jobs on separate fresh environments. The clean trust-anchor launcher creates expected identity and verifies that the signer retains every trusted control byte. Identity keeps the trust anchor, signer, tested source, base, `managed:<32hex>` run identity, and its exact 32-hex artifact nonce distinct. Expected, candidate, sealed, and sealing-receipt artifact names use fixed safe templates. The local dispatch token has Actions write permission. Candidate narrows its job permissions to contents read; seal alone retains Actions read, contents read, OIDC, and attestations write. Candidate processes can't inherit artifact runtime or signing capabilities.

The sealing receipt validates against the Stage 3 raw definition and contains `job.check_run_id` but no status, conclusion, or completion timestamp. After the attempt completes, collection resolves exactly one job API object from that locator and requires `status=completed`, `conclusion=success`, the expected run, attempt, label, hosted environment, and signed sealing provenance. An in-progress, failed, missing, duplicate, or wrong-job match produces a typed rejected report. For every expected, candidate, and sealed artifact, fixtures require the REST `sha256:<hex>` digest to equal `sha256:` plus the pinned action's bare lowercase 64-hex output. Prefix, case, and byte mismatches produce `artifact-digest-mismatch`. Evidence-profile fixtures accept CI bootstrap without performance or visual classes. They reject an unassigned class, a missing assigned class, or a class assigned to the wrong role. Existing role, bundle, nonce, collision, trust-anchor, source-allowlist, coordinator, and aggregation fixtures remain required. Aggregate `accepted` requires all three post-completion role origins and no rejection reason.

Linux static and integration fixtures prove `env -i` Bubblewrap `0.11.2` PID containment by rejecting a surviving double-fork probe before upload. Hosted-macOS fixtures prove candidate no-privilege permissions, fresh-job separation, seal-only OIDC and attestation authority, safe validation, and no candidate-byte execution in seal. They reject any universal macOS containment or zero-survivor claim. Accepted evidence authenticates reviewed workflow execution and sealed provenance. It does not prove that arbitrary malicious macOS candidate code is contained or that its untrusted output is truthful. Reviewed source and test contracts remain required.

Before the ordered gate invokes it, `CI-M003` creates the missing generated-binding checker. Checker fixtures prove that it snapshots a path-sorted SHA-256 manifest and byte backup for `rust/src/frb_generated.rs` and `lib/src/rust/**`, runs the provisional `2.12.0` generator, and detects every added, removed, or changed generated byte. Clean, stale, generator-failure, premodified-file, and interruption cases restore and verify the exact precheck state before exit. Contract fixtures prove that `collect` and `run` reject extra or missing flags, replace outputs atomically, emit the specified JSON summary, and use exit statuses `0`, `1`, and `2` exactly as Stage 3 defines. Dispatch fixtures require `master`, the exact returned run ID, canonical expected-identity bytes, and separate signer and tested-source SHAs. Managed-Spike fixtures prove that verified manifest members stage only under fixed role directories, coordinator steps use no manual source, and acceptance requires a schema-valid `results.json`. They execute the collector-reconciliation fixture and reject a runner-label mismatch before comparing ordered evidence classes. A non-`CLOEXEC` descriptor canary proves that the trusted launcher closes descriptors before Bubblewrap; namespace and network fixtures remain separate. Packaging fixtures prove that macOS 15 receives the exact macOS 26 archive only through a verified staged role bundle. The workflow never pushes repository content, publishes a release, or receives live product credentials. The implementation review and merge establish the anchor. The dedicated evidence pull request then commits only the accepted CI report and completion record. `CI-M003` satisfies dependencies only after that reviewed pull request merges. Any trusted-control change repeats the sequence. Final Stage 3 must revalidate the generator triple and generated output before downstream production tickets run.
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
The same versioned matrix passes for the AppImage candidate on every accepted Linux runtime. The managed Linux bundle records candidate hash, image and environment identity, app and source version, verified logical viewport, all P0 outcomes, PRD meters, private GitHub canary, S3-compatible credentials, interruption recovery, diagnostics content exclusion, and update notification. Required exact platform-regression capture uses only the pipeline-owned headless Sway and Wayland environment and doesn't claim product visual authority. The authenticated aggregate binds the result to the trust anchor, workflow signer, tested source, ticket base, build, corpus, run, and artifact identity. The matrix connects a local Workspace, enters Consolidation, resolves a collision, and proves that initial Remote publication waits for the atomic Consolidation result. Any failure blocks publication.
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
