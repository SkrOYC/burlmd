# Open decisions register

**Date:** 2026-08-25
**Interview target:** Tasks

This register carries only questions that the user saw and explicitly left unresolved or delegated to a downstream Spike. The Tasks interview resolved every other decision it raised.

## OD-02: Conditions for screen-reader certification

The August 21, 2026, Realign interview established keyboard completeness and Flutter `Semantics` labels as required standards. It deferred certification with Orca on Linux and VoiceOver on macOS, but the user didn't select a condition that reopens certification.

This Tasks interview didn't reopen the decision because screen-reader certification remains in `.constitution/prd/out-of-scope/`. A Product Requirements Evolution pass must carry this decision without inventing a trigger.

**Owner:** User, or a later Product Requirements interview that explicitly reopens the out-of-scope entry.

## OD-04: Standards foundation for the canonical AST

The interview asked whether Core must own a canonical extended AST and whether an industry parser or schema should provide its standards foundation. The user required the Core-owned extended AST and delegated the foundation choice to technical judgment. The provisional default is the `markdown` crate's `mdast`, but the AST Spike must compare `mdast`, Comrak, and a complete model derived from `pulldown-cmark` events.

The Spike must prove exhaustive conversion, byte positions, untouched-source fidelity, supported syntax, performance, and FFI projection cost. Technical Implementation Evolution selects and pins the foundation from that evidence.

**Owner:** AST Spike, followed by Technical Implementation Evolution.

## OD-05: Canonical cross-platform path algorithm

The interview asked how one Workspace can remain unambiguous across Linux, macOS, and Windows filesystems. The user chose a lowest-common-denominator on-disk path format and delegated the exact algorithm to a path Spike.

The Spike must settle Unicode normalization, case equivalence, invalid characters, reserved device names, trailing dots and spaces, path limits, collision disambiguation, case-only renames, title-to-path derivation, and ghost-Link creation. Technical Implementation Evolution turns the result into the format contract.

**Owner:** Path Spike, followed by Technical Implementation Evolution.

## OD-06: Maximum image size

The interview accepted 25 MiB as a provisional image-import limit after binary payloads moved from Git to S3-compatible object storage. The user delegated the final threshold to technical judgment and measurement.

The asset Spike must measure decoding, pixel dimensions, memory, caching, local persistence, second-device hydration, and S3-compatible transfer behavior. Product Requirements Evolution retains or revises the user-visible limit from that evidence. Architecture reviews any resulting storage-flow change, and Technical Implementation then binds the accepted constraint. GitHub's Git-object limit isn't the deciding constraint.

**Owner:** Asset Spike, followed by Product Requirements Evolution, Architecture review when required, and Technical Implementation Evolution.

## OD-07: Git repository-health warning threshold

The interview accepted a user-visible warning near a provisional 1 GiB Git repository-health range after binary payloads moved to S3-compatible storage. It delegated the final measured threshold to the asset or performance Spike and Product Requirements Evolution.

The Spike must measure textual and manifest history growth, clone and fetch cost, local Git maintenance, index cost, and the PRD corpus-scale targets. Product Requirements Evolution retains or revises the warning threshold from that evidence. Architecture reviews any resulting flow change, and Technical Implementation binds the accepted meter and probe.

**Owner:** Asset or performance Spike, followed by Product Requirements Evolution, Architecture review when required, and Technical Implementation Evolution.

## OD-08: General Linux runtime baseline

The interview selected an x86-64 AppImage as the general Linux artifact and a release-tagged Nix Flake for Nix-managed installations. It delegated the oldest supported runtime baseline and named tested Linux distributions to the packaging Spike.

The early packaging-feasibility Spike must test a representative Flutter and Rust harness, the version-locked Git CLI, keyring access, file selection, and release construction without implementing production features. Product Requirements Evolution selects the support baseline from that evidence. Provisional and final Technical Implementation define the package contract. A post-implementation release gate must then test the complete installed application, including GitHub authorization, S3-compatible credentials, Workspace access, and update notification, before a distribution enters the named support matrix.

**Owner:** Provisional Technical Implementation, packaging-feasibility Spike, Product Requirements Evolution, final Technical Implementation, and the post-implementation release gate.
