---
id: ADR-0018
status: proposed
date: 2026-08-26
certainty: assumed
assumption: "The packaging decision remains provisional until SPK-BURL-O001 produces accepted evidence and the final Stage 3 evolution settles it."
---
# ADR-018: Installable Unsigned 0.x Desktop Artifacts

**Status:** Proposed; packaging feasibility Spike
**Decision owner:** SPK-BURL-O001, measured PRD, then final Technical Implementation evolution

## Context

Every release in this phase is `0.x` until the user changes that policy. GitHub Releases must provide installable artifacts for Apple Silicon macOS and x86-64 Linux. General Linux uses AppImage; Nix users can import a release-tagged Flake. Intel macOS isn't supported. Signing and self-update are deferred until stability.

## Candidate decision

1. The release matrix has three products: an Apple Silicon macOS archive, an x86-64 AppImage, and a release-tagged Nix Flake exposing the x86-64 Linux package. These are packaging forms of the same application and feature matrix.
2. The AppImage bundles every non-baseline runtime dependency, including the exact Git CLI selected by the final Git Spike, native Rust library, Flutter assets, and required desktop integration files. It must not depend on an ambient Git.
3. The Flake is importable from a tagged repository revision, carries a lock file, exposes a default package, and is checked with `nix flake check`. It is an additional supported install path, not the general Linux artifact.
4. The macOS artifact targets Apple Silicon only and is built with Flutter release mode. It contains no fake Linux or macOS presentation chrome; the host platform owns its window frame.
5. Artifacts are unsigned during `0.x` and disclose the resulting Platform installation warning. They don't implement automatic self-update. The application may check release metadata and notify according to the user's stored preference.
6. A GitHub Release is a prerelease and carries checksums, version, supported platform labels, known installation warnings, and the exact source revision.
7. The release workflow creates keyless GitHub Actions artifact attestations for the AppImage, Apple Silicon archive, and release-tagged Flake source archive. Production pins `actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6` and grants only `id-token: write`, `contents: read`, and `attestations: write`. Verification binds the GitHub/Sigstore trust root, expected repository `SkrOYC/burlmd`, release workflow identity, release ref, source revision, and artifact subject. This is authenticated build provenance, not Developer ID signing or notarization.
8. The validation workflow uses OS-major-pinned standard hosted labels: `ubuntu-22.04`, Apple Silicon `macos-26`, and Apple Silicon `macos-15`. The Linux label is a temporary bridge: the exact BURL-M003 prerequisite passed on image `20260831.284.1`, but GitHub starts deprecation on 2026-09-17 and retires the image on 2027-04-17. These roles define assumed evidence capabilities. A managed run requires only the ticket-specific classes in expected identity. Linux and macOS 26 can produce performance evidence. Linux can produce exact non-authoritative platform regression, and macOS 26 alone can produce authoritative product visual evidence. macOS 15 is functional compatibility-only.
9. Release Pipeline creates authoritative expected identity from a clean checkout of an immutable reviewed trust anchor. It distinguishes all source, build, run, role, and evidence-class identities that the raw contract names. Before dispatch and during collection, the client verifies that the trusted control surface hasn't changed from the anchor. That surface includes `scripts/write-receipt-digest-observation.sh` and the five named compatibility helpers. The client selects each managed non-Spike's ordered source-write allowlist only from the trust-anchor raw contract. Candidate input can't select or change that allowlist. The client verifies the exact base-to-tested-source diff against the selected allowlist. The trusted default-branch caller checks out the tested source as data with persisted credentials disabled. It never loads validation control from that checkout. Per-role evidence captures hosted image and system facts and travels through immutable artifacts with SHA-256 digests. Each role exports its receipt artifact ID and bare upload digest. A fresh caller job carries those outputs in one receipt-digest transport. After completion, the collector resolves the transport's immutable ID from the exact run inventory. It downloads the raw archive by ID and matches its SHA-256 with the canonical REST digest before extraction. The aggregate retains the transport observation and both digest forms for every sealing receipt. This check detects corrupt or substituted transport bytes. It doesn't add provenance beyond the selected GitHub artifact object.
10. Candidate build and probe commands run without GitHub tokens, artifact runtime credentials, OIDC request capability, ambient Git or GitHub configuration, cloud credentials, or inherited credential descriptors. After those commands finish, the trusted candidate wrapper receives job-scoped artifact runtime authority to upload their untrusted bundle. On hosted macOS, a surviving process can corrupt that output or cause upload denial, but can't gain sealing authority. Each role uses a `candidate` job and a dependent `seal` job on separate fresh hosted environments. The sealing job validates the candidate bundle and alone receives OIDC and attestation authority. It publishes a sealed bundle, then writes and attests a separate receipt containing immutable identity, locator, and digest facts available before job completion. The receipt doesn't claim its own final status. After the workflow attempt completes, the trusted client resolves the receipt's check-run locator through the job API and requires the sealing job to have completed successfully. Before using GitHub authentication, the client builds and identifies any declared locked ticket coordinator without credentials or network access. BURL-O004 uses its trust-anchor-owned Cargo manifest, lockfile, exact source inventory, locked offline release build, immutable executable, and required trust-anchor rotation. After destroying authentication state, the client runs that prepared executable once in a nonnetwork sandbox with fixed read-only `/inputs` role artifacts and only `/output/nightly-prd-meters.json` writable. It never mounts the repository or invokes a repository-relative tested-source script. Packaging transfers the macOS 26 archive to the macOS 15 probe only through this verified bundle staging path. No manual or environment-selected handoff is accepted. For a managed Spike, a later evidence commit contains the accepted report, machine result, and executor-authored human interpretation. Only accepted evidence can start milestone review.
11. The initial validation implementation uses a two-pull-request trust-on-first-merge bootstrap. The reviewed implementation merges first and establishes its merge tip as the trust anchor. The merged client then dispatches the trusted pipeline against that exact SHA. A dedicated reviewed evidence pull request records only the accepted report and completion record. `BURL-M003` remains incomplete until that second pull request merges. Any trusted-control change repeats the same anchor rotation and evidence process.

## Evidence required

SPK-BURL-O001 packages a representative harness early. It must verify installed launch, the version-locked Git CLI and runtime, Platform secure storage, file selection, bundled native loading, secret-injection seams, compatible `0.x` prerelease update-channel selection, checksum and provenance metadata layout, absence of emulated chrome, and repeatable release construction. The macOS test constructs the actual deterministic release archive twice, compares archive bytes, safely extracts it, and launches the extracted application on both supported majors; inspecting an unpackaged build directory isn't evidence. It must determine the oldest supportable Linux runtime and named tested distributions for OD-08.

Managed validation runs the ticket-specific profile on the three roles in decision 8. Role-produced bytes validate against `contracts/ci-role-evidence.schema.json`; the enriched coordinator report validates against `contracts/ci-evidence.schema.json`. `BURL-M003` requires common functional, protocol, security, static-analysis, and desktop-integration outcomes on all three roles. Linux also requires isolation and generated-binding outcomes. The bootstrap doesn't require performance, Linux platform-regression, or authoritative macOS visual evidence. AST and Asset Spikes require performance only on Linux and macOS 26. Path and Git Spikes require their filesystem classes. Packaging requires its runtime and repeatable-construction classes. Later shell, benchmark, and release gates retain the PRD performance and visual obligations they explicitly assign.

The Linux and macOS runs are aggregated only after GitHub Sigstore attestations authenticate each sealing workflow, sealed bundle, and separate sealing receipt. During the job, the receipt binds the check-run locator and immutable run, workflow, role, nonce, environment, and artifact facts. It contains no status, conclusion, or observation of its own artifact. After the attempt completes, the coordinator resolves that locator to one job API object. The object must report completed success with the expected labels, run, attempt, and signed hosted provenance.

For every expected, candidate, sealed, sealing-receipt, compatibility-stage, and producer-lineage artifact, the coordinator compares the action output with the canonical REST digest. The receipt-digest transport uses a different noncyclic check. The coordinator resolves its immutable ID from the exact run inventory and fetches that ID's REST object. It downloads the raw archive by ID and compares the downloaded bytes with the REST digest before extraction or JSON parsing. Aggregate `artifactIntegrityVerified` covers both check forms and retains the transport observation. Aggregation also compares captured identity with independently supplied expected identity and verifies every manifest-named internal artifact. These checks establish workflow origin only where authenticated provenance exists. They don't make the hosted image immutable, guarantee physical-host performance, or treat the caller transport as provenance.

Private or internal repositories require GitHub Enterprise Cloud for artifact attestations. The repository's eligible plan isn't guaranteed. Without attestation availability, the bootstrap records the limitation and can't claim authenticated evidence origin. A hash-only fallback is forbidden.

Because the packaging Spike is confined to its prototype allowlist, release attestation creation and adversarial trust verification remain downstream release work. Those release contracts must reject tampered subjects and an unexpected issuer, repository, workflow, ref, revision, or artifact digest.

## Consequences

- Packaging feasibility is tested before production capability work accumulates unshippable assumptions.
- Code signing, notarization, additional architectures, and a self-updater remain separate future decisions.
- A complete post-implementation installed-app matrix remains a release gate even after the harness Spike passes.
- Authenticated artifact provenance ships during `0.x`; Platform signing and notarization remain deferred until stability.
- The `ubuntu-22.04` validation role is a measured bootstrap bridge, not the Linux release baseline. If GitHub removes or disrupts the label, managed validation fails closed until Stage 3 selects and measures a replacement.

## Verification anchors

- <https://docs.flutter.dev/deployment/macos>
- <https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html>
- <https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake.html>
- <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- [GitHub Actions Ubuntu 22.04 image 20260831.284](https://github.com/actions/runner-images/releases/tag/ubuntu22%2F20260831.284)
- [GitHub Actions Ubuntu 22 retirement notice](https://github.com/actions/runner-images/issues/14254)
- <https://docs.github.com/en/actions/reference/security/secure-use>
- <https://docs.github.com/en/rest/actions/artifacts?apiVersion=2026-03-10>
- <https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2026-03-10>
- <https://docs.github.com/en/rest/actions/workflows?apiVersion=2026-03-10>
- <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch>
- <https://docs.github.com/en/actions/reference/security/oidc>
- <https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#job-context>
- <https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows>
- <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions>
- <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating>
- <https://github.com/actions/upload-artifact/tree/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a>
