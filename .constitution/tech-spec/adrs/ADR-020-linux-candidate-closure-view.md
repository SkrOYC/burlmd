---
id: ADR-0020
status: accepted
date: 2026-09-07
certainty: assumed
assumption: "An exact read-only Bubblewrap view of the locked BURL-M003 runtime closure preserves Linux isolation and fits the standard ubuntu-24.04 runner. Local prototypes exercised the mechanism, but no managed BURL-M003 run has exercised it."
---
# ADR-020: Linux candidate closure view

**Status:** Accepted as an assumed implementation contract
**Implementation owner:** `BURL-M003`

## Context

PR #15 commit `9719259f1ecee819af96c98c2be210156f198343`
copies the Linux candidate closure into a private Nix store. A local
measurement put its prebuild allocation at 15,382,421,504 bytes. This value
exceeds the 14,000,000,000-byte standard `ubuntu-24.04` profile.

`BURL-M003` needs an exact runtime closure but doesn't need Nix command
authority. Mounting the complete realized closure read-only avoids the second
physical copy while preserving the existing Linux containment boundary.

OD-11 and ADR-0019 define candidate and seal authority. They don't select this
storage mechanism. This ADR changes no placement, credential, provenance,
artifact, receipt, or evidence-schema contract.

The local prototype didn't run on a managed runner. Its results support the
mechanism and a conservative start-space guard. They don't constitute accepted
`BURL-M003` evidence.

## Decision

1. Derive the exact `BURL-M003` closure manifest from the authoritative
   launcher's locked runtime roots. Expand the roots with `nix-store -qR`, sort
   them with `LC_ALL=C`, and write one canonical path per line.
2. Create an owned store base with one correctly typed empty mount point for
   each manifest member. Bind the base read-only at `/nix/store`, then bind each
   manifest member read-only at its canonical path.
3. Expose no host store root, Nix state, Nix database, daemon socket, or
   unlisted store path. Require the visible store entries to equal the manifest
   before candidate execution.
4. Preserve the existing `env -i`, private process identifier (PID) namespace,
   no-network, descriptor-closure, teardown-lock, and cleanup controls.
5. Add `--disable-userns` and `--assert-userns-disabled` to the existing single
   Bubblewrap invocation. Candidate assertions consume the mounted manifest and
   don't start a second Bubblewrap process.
6. Count the complete null-terminated environment and argument vector before
   `exec`. Include the Bubblewrap arguments, every closure bind, and the
   candidate command. Reject a total at or above half of `getconf ARG_MAX`.
7. Immediately before namespace entry, require at least 4,000,000,000 available
   bytes on the workspace filesystem. If the observation fails or falls below
   the floor, fail the candidate before it produces accepted evidence.
8. Treat the space check only as a start guard. Don't claim that it measures a
   complete phase peak or proves capacity for another ticket.

## Exact closure roots

Resolve the following command groups through the authoritative `BURL-M003`
launcher environment. Reduce each resolved command to its top-level
`/nix/store` path before closure expansion.

The required-tool group is:

```text
bash sh mkdir mktemp chmod install cp mv rm awk sed grep rg sort sha256sum wc
find tar zstd flock getconf df ps sleep setsid perl readlink uname tr head
```

The runtime-link group is:

```text
bash sh env mkdir rm cp mv ln find grep sed awk sort head tail dirname basename
readlink sleep perl tr cat ls
```

The `BURL-M003` profile group is:

```text
env flutter dart flutter_rust_bridge_codegen cargo cargo-expand rustc rustup
cmake ninja pkg-config clang openssl jq bwrap sway swaymsg ip
```

Resolve `cargo-expand` from `BURLMD_CARGO_EXPAND`. Resolve the OpenSSL
`pcfiledir`, `includedir`, and `libdir` values through `pkg-config`. Resolve the
Mesa roots from `BURLMD_MESA_DRI_PATH` and `BURLMD_MESA_EGL_VENDOR_PATH`.

Reject an empty manifest, a duplicate or noncanonical path, a missing member,
a top-level symbolic link, or a direct Nix reference outside the manifest.
Record the manifest SHA-256 and verify the same bytes before each candidate
session. Internal links remain inside their mounted store object.

## Fixtures

The `BURL-M003` contract fixtures must preserve these checks:

- The visible store entries equal the exact manifest.
- An ambient host-store canary outside the manifest stays hidden.
- Every mounted member and the owned store base reject writes.
- Direct references, script interpreters, ELF loaders, and runtime search paths
  resolve only within the manifest.
- The Flutter Rust Bridge generator, Cargo, `rustc`, the `rustup` shim, Dart,
  CMake, Ninja, Clang, OpenSSL, `jq`, Sway, `swaymsg`, iproute2, and Bubblewrap
  run from the view.
- Forbidden clients remain absent.
- The complete null-terminated environment and argument vector stays below
  half of `ARG_MAX`.
- The exact 4,000,000,000-byte start-space boundary passes, and one byte below
  it fails before candidate execution.
- `--disable-userns` enters an internal nested user namespace that prevents the
  candidate from creating further user namespaces. Candidate assertions don't
  start a second Bubblewrap process.
- The existing no-network, private-PID, descriptor, teardown, and cleanup
  fixtures continue to pass.

## Local prototype facts

An independent reproduction used pinned Nix `2.35.2` and Bubblewrap `0.11.2`
against PR #15 commit `9719259f1ecee819af96c98c2be210156f198343`.
It derived 558 manifest paths, 34,986 manifest bytes, and 75,552 bind-only
argument bytes. The host closure used 5,627,330,560 allocated bytes. `ARG_MAX`
was 2,097,152 bytes.

The prototype found no top-level symbolic links. It hid an unlisted host path,
rejected writes to a member and the store base, ran representative dynamic and
script tools, exposed no forbidden PATH client, and prevented the candidate
from creating further user namespaces.

The 75,552-byte value covers only bind triples. The prototype didn't retain the
complete environment and argument count. The complete-vector fixture therefore
remains an assumed requirement until a managed `BURL-M003` run exercises it.

These local results prove the closure-view mechanics. They don't establish
hosted capacity or feature availability and can't settle ADR-0020 without
accepted managed `BURL-M003` completion evidence from the standard runner.

The documented 14,000,000,000-byte runner profile exceeds the measured host
closure allocation by 8,372,669,440 bytes before checkout and cache use. The
4,000,000,000-byte start guard leaves margin within that local observation. It
doesn't establish a complete run peak.

## Scope boundary

This decision doesn't authorize or solve `BURL-O001` Nix packaging isolation
or capacity. `BURL-O001` requires a later Stage 3 decision before
implementation. That decision must follow its own packaging evidence and
upstream scope. This ADR makes no `BURL-O001` runner, storage, evidence, or
coordinator decision.

## Consequences

- `BURL-M003` avoids a second physical copy of its locked runtime closure.
- Candidate code can read only manifest-listed store paths and can't change the
  host closure.
- A missing closure dependency, excessive argument vector, unavailable start
  space, or failed isolation check produces no accepted evidence under the
  existing evidence contract.
- ADR-0019 remains unchanged and continues to govern OD-11 authority.
- Stage 4 must adapt only the `BURL-M003` closure implementation. It must add or
  retain an explicit `BURL-O001` stop and Stage 3 route without changing the
  epic graph.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
