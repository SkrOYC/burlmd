# Spike report: PKG-M001 Installable 0.x desktop artifacts

## Time box

- **Budget:** 3 focused days
- **Clock start / stop:** fill during execution

## Question

- **Decision this spike must produce:** Can one representative Flutter/Rust harness ship as an x86-64 AppImage, importable release-tagged Nix Flake package, and unsigned Apple Silicon macOS archive with the complete required runtime behavior, and what Linux baseline is supportable?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-018-prerelease-desktop-artifacts.md`
- **Target:** artifact construction, runtime closure, Git bundling, platform integration, checksums/provenance, update metadata, and OD-08
- **Archetype / surface:** System/Native desktop distribution

## Codebase baseline

- **State today:** Development builds exist; GitHub Releases don't provide the required installable artifacts. The production shell still contains presentation-only emulated Platform chrome, which the harness must not reproduce.
- **Discovered constraints:** Apple Silicon only on macOS; x86-64 general Linux; Nix Flake for Nix-managed installs; unsigned `0.x`; no ambient Git or self-updater. Apple's published stable-version list identifies macOS Tahoe 26 and macOS Sequoia 15 as the two stable major versions on August 26, 2026. Distinct Apple Silicon hosts must run those versions. If that pair changes before execution, stop and reconcile the contract. The macOS 26 host performs two clean, lock-enforced constructions of the actual deterministic `.tar.gz` release archive, with timestamps normalized from the source revision. It proves archive-byte reproducibility and safe extraction with modes, symlink targets, extended attributes, and a single application bundle preserved. Both hosts then extract and probe one transferred immutable archive with the same SHA-256. Nix out-links resolve outside the repository, so every measured artifact or closure must be copied into the Spike's `artifacts/` directory before containment, byte-count, and SHA-256 evidence is recorded. The macOS hosts export opaque SHA-256-verified handoff bundles for coordinator import; no shared checkout is assumed.

## Options and trade-offs

- Exercise AppImage, tagged Flake, and Apple Silicon archive forms as required complementary outputs while measuring supported Linux distributions and minimum runtime.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the recommendation to installed behavior, repeatability, runtime closure, user friction during unsigned `0.x`, and support-matrix cost
- **Rejected options:** record any artifact form or Linux baseline that fails its evidence gate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-018 and bind final artifact/build/update contracts
- **Tickets unblocked in `tasks/active/`:** APPIMAGE-M006, NIX-M007, MAC-M008, and UPDATE-M010 directly; RELEASE-M009, GATE-M011, GATE-M012, GATE-M013, and PUBLISH-M014 transitively
- **Tickets to add or split:** adapt packaging/release tickets when the accepted Linux baseline or artifact construction changes scope
- **Spec edits required:** Product Requirements for OD-08; final Technical Implementation; Architecture only if packaging evidence changes a boundary
