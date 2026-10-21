# Flutter Rust Bridge API surface

## Authority

The code-owned `rust/src/api/ffi_api.rs` file and its generated Rust and Dart bindings are authoritative for calls the repository implements. The sibling `.constitution/tech-spec/contracts/ffi_api.rs` file is retained as legacy provisional history and isn't an implementation contract. No ticket can implement a missing API merely because that historical file declares it.

Every ticket that changes the code-owned artifact also owns `rust/src/frb_generated.rs` and `lib/src/rust/**`. Its verification regenerates both binding surfaces, compares them with the committed bytes, and leaves the precheck tree unchanged.

## Forward changes

ADR-013 and ADR-021 define the candidate canonical document, revision-local identity, coordinate, find, edit, and render-projection invariants. OD-04 remains open. BURL-H001 produces evidence only; a reviewed Stage 3 patch must publish the final field-level API after selecting a model and before dependent implementation.

ADR-014 and OD-05 retain the same sequence for portable path identities. ADR-015 retains it for typed reconciliation plans and application records. ADR-016 retains it for local Asset and Object state. None of those proposed records create callable functions or fields before the matching Stage 3 patch.

The GitHub device flow uses the separate `github-app-device-flow.md` companion and future code-owned Provider artifact. External image fetching uses the separate `external-image-fetch.md` companion and future code-owned BND-22 artifact. Flutter receives only validated state from those Core-owned paths.

## Error and state rules

Errors cross the boundary as typed refusals, retry states, warnings, or unavailable presentation state. Presentation doesn't parse error strings to decide authority. A successful mutation returns the authoritative post-operation document and focus or selection target. A stale document revision, node identity, find session, reconciliation plan, or Workspace authority refuses without mutation.

Delivered calls keep their existing signatures until a reviewed implementation or evidence-driven Stage 3 patch changes them. This companion intentionally doesn't copy the current Rust declarations or promise unimplemented calls.
