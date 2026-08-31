# ADR-018: Installable Unsigned 0.x Desktop Artifacts

**Status:** Proposed; packaging feasibility Spike
**Decision owner:** SPK-PKG-M001, measured PRD, then final Technical Implementation evolution

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
8. The validation workflow uses OS-major-pinned standard hosted labels: `ubuntu-24.04`, Apple Silicon `macos-26`, and Apple Silicon `macos-15`. Every role runs the common functional matrix. Linux and macOS 26 run performance meters. Linux also runs the required exact non-authoritative platform regression. macOS 26 alone owns the authoritative product visual baseline. macOS 15 is functional compatibility-only.
9. Release Pipeline creates an authoritative expected identity before role fan-out. It distinguishes the ticket, tested source head SHA, workflow execution SHA and ref, base SHA, release, build, corpus, run, required-role, and required-role-signer identities. A push-triggered caller invokes each distinct single-job reusable workflow through its static same-repository path. GitHub resolves that local workflow from the caller's workflow execution commit. Per-role evidence captures the hosted image and system facts, authenticates its pipeline-owned origin, and travels through immutable artifacts with SHA-256 digests. Aggregation receives expected identity independently and rejects self-description, missing roles, origin failure, corruption, mismatch, duplication, and stale evidence.
10. Candidate validation runs when the source commit is pushed to its source branch. A draft pull request is optional visibility and doesn't define identity. Each role builds one deterministic bundle containing a schema-valid manifest plus every result, log, raw measurement, and handoff named by `internalArtifacts`. It attests those exact bundle bytes, then uploads the unchanged bundle. A coordinator job or authenticated local process verifies each artifact, attestation, bundle, manifest, and member hash before staging manifest-named bytes under the fixed role directory. It then runs the ticket's declared coordinator steps and produces an authoritative schema-valid `results.json` plus a discriminated accepted or rejected report. Packaging transfers the macOS 26 archive to the macOS 15 probe only through this verified bundle staging path. No manual or environment-selected handoff is accepted. For a managed Spike, the later evidence commit contains the accepted report, machine result, and executor-authored human interpretation. Its parent is the tested source head. Only accepted evidence can start milestone review. The candidate workflow doesn't push repository content, publish a release, or receive live product credentials.

## Evidence required

SPK-PKG-M001 packages a representative harness early. It must verify installed launch, the version-locked Git CLI and runtime, Platform secure storage, file selection, bundled native loading, secret-injection seams, compatible `0.x` prerelease update-channel selection, checksum and provenance metadata layout, absence of emulated chrome, and repeatable release construction. The macOS test constructs the actual deterministic release archive twice, compares archive bytes, safely extracts it, and launches the extracted application on both supported majors; inspecting an unpackaged build directory isn't evidence. It must determine the oldest supportable Linux runtime and named tested distributions for OD-08.

Managed validation must run on the three roles in decision 8. Role-produced bytes validate against `contracts/ci-role-evidence.schema.json`; the enriched coordinator report validates against `contracts/ci-evidence.schema.json`. Linux exact platform-regression proof extends the committed private headless Sway and Wayland capture. It is a required zero-pixel implementation gate, not a product visual reference. macOS 26 visual proof runs the actual hosted Apple Silicon GUI and owns the sole authoritative product visual baseline set. Both paths must prove a 1920x1080 at 60 Hz logical viewport. macOS 15 produces no visual baseline.

The Linux and macOS runs are aggregated only after GitHub Sigstore attestations authenticate the exact role-specific static reusable-workflow path, workflow execution SHA and ref, run, attempt, tested source head, and role-bundle digest. The signed OIDC `runner_environment` claim must equal `github-hosted`, and the aggregate retains that verified fact. The artifact API authenticates upload identity and digest. The job API corroborates that the signer workflow's only job used its fixed hosted label. Aggregation doesn't attempt to correlate the artifact and job REST objects, and it doesn't trust a manifest-supplied job name or ID. It compares captured identity with the independently supplied expected identity and verifies every manifest-named internal artifact against bundled bytes. These checks establish workflow origin; they don't make the weekly hosted image immutable or guarantee physical-host performance. Exact image and system facts remain mandatory evidence.

Private or internal repositories require GitHub Enterprise Cloud for artifact attestations. The repository's eligible plan isn't guaranteed. Without attestation availability, the bootstrap records the limitation and can't claim authenticated evidence origin. A hash-only fallback is forbidden.

Because the packaging Spike is confined to its prototype allowlist, release attestation creation and adversarial trust verification remain downstream release work. Those release contracts must reject tampered subjects and an unexpected issuer, repository, workflow, ref, revision, or artifact digest.

## Consequences

- Packaging feasibility is tested before production capability work accumulates unshippable assumptions.
- Code signing, notarization, additional architectures, and a self-updater remain separate future decisions.
- A complete post-implementation installed-app matrix remains a release gate even after the harness Spike passes.
- Authenticated artifact provenance ships during `0.x`; Platform signing and notarization remain deferred until stability.

## Verification anchors

- <https://docs.flutter.dev/deployment/macos>
- <https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html>
- <https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake.html>
- <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- <https://github.com/actions/runner-images>
- <https://docs.github.com/en/actions/reference/security/secure-use>
- <https://docs.github.com/en/rest/actions/artifacts?apiVersion=2026-03-10>
- <https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2026-03-10>
- <https://docs.github.com/en/actions/reference/security/oidc>
- <https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows>
- <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions>
- <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating>
