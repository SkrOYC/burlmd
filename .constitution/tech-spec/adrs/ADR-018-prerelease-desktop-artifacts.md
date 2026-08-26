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
7. The release workflow creates keyless GitHub Actions artifact attestations for the AppImage, Apple Silicon archive, and release-tagged Flake source archive. Production pins `actions/attest@v4` to a verified full commit SHA and grants only `id-token: write`, `contents: read`, and `attestations: write`. Verification binds the GitHub/Sigstore trust root, expected repository `SkrOYC/burlmd`, release workflow identity, release ref, source revision, and artifact subject. This is authenticated build provenance, not Developer ID signing or notarization.

## Evidence required

SPK-PKG-M001 packages a representative harness early. It must verify installed launch, the version-locked Git CLI and runtime, Platform secure storage, file selection, bundled native loading, secret-injection seams, compatible `0.x` prerelease update-channel selection, checksum and provenance metadata layout, absence of emulated chrome, and repeatable release construction. The macOS test constructs the actual deterministic release archive twice, compares archive bytes, safely extracts it, and launches the extracted application on both supported majors; inspecting an unpackaged build directory isn't evidence. It must determine the oldest supportable Linux runtime and named tested distributions for OD-08. Apple Silicon validation must run on Apple Silicon and cover the two most recent macOS major versions; the Linux host can't settle those gates by inspection. The Linux and macOS runs are aggregated into one schema-valid decision result whose input-context hashes prove that every host evaluated the same revision, lockfiles, contracts, schema, probe sources, and corpus. Because the Spike is confined to its prototype allowlist and doesn't own a privileged GitHub workflow, authenticated attestation creation and adversarial trust verification belong to RELEASE-M009 and PUBLISH-M014. Those release tickets must reject tampered subjects and an unexpected issuer, repository, workflow, ref, or revision.

## Consequences

- Packaging feasibility is tested before production capability work accumulates unshippable assumptions.
- Code signing, notarization, additional architectures, and a self-updater remain separate future decisions.
- A complete post-implementation installed-app matrix remains a release gate even after the harness Spike passes.
- Authenticated artifact provenance ships during `0.x`; Platform signing and notarization remain deferred until stability.

## Verification anchors

- <https://docs.flutter.dev/deployment/macos>
- <https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html>
- <https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake.html>
