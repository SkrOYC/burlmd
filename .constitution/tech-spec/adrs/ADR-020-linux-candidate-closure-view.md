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
physical copy while preserving the ADR-0019 Linux containment boundary.

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
2. Immediately before namespace entry, the trusted launcher records each host
   member's file type, device, inode, containing-mount device, and computed
   mount root. It exposes the path-sorted snapshot read-only at
   `/contract/locked-nix-closure.sources`. Create a fresh owned staging root
   whose only child is the store base. The base contains exactly one
   source-distinct, empty mount point of the correct type for each member. Bind
   the base read-only at `/nix/store`, then bind each member read-only at its
   canonical path.
3. Before the first candidate command, a trusted namespace preflight verifies
   each member against that host snapshot. The decoded `/proc/self/mountinfo`
   data must contain exactly one mount at the member path. Its root,
   `major:minor` device, and `ro` mount option must match the source snapshot.
   The member's `st_dev`, `st_ino`, and file type must also match. A placeholder
   without its member `--ro-bind` therefore fails even when its name and type
   are correct.
4. Expose no host store root, Nix state, Nix database, daemon socket, or
   unlisted store path. Require the visible store entries to equal the manifest.
   Require `/nix/var`, `/nix/var/nix/db`,
   `/nix/var/nix/db/db.sqlite`, and
   `/nix/var/nix/daemon-socket/socket` to return `ENOENT`.
5. Preserve the `env -i`, private process identifier (PID) namespace,
   no-network, descriptor-closure, teardown-lock, and cleanup controls.
6. Add `--disable-userns` and `--assert-userns-disabled` to the single
   Bubblewrap invocation. Candidate assertions consume the mounted manifest and
   don't start a second Bubblewrap process.
7. Count the complete null-terminated environment and argument vector before
   `exec`. Include the Bubblewrap arguments, every closure bind, and the
   candidate command. Reject a total at or above half of `getconf ARG_MAX`.
8. Immediately before namespace entry, require at least 4,000,000,000 available
   bytes on the workspace filesystem. If the observation fails or falls below
   the floor, fail the candidate before it produces accepted evidence.
9. Treat the space check only as a start guard. Don't claim that it measures a
   complete phase peak or proves capacity for another ticket.
10. Retain the exact manifest and launch observations in
    `logs/burl-m003-linux-closure-view.log`. The trusted launcher creates this
    internal artifact outside candidate-writable paths. Its fixed-order header
    records raw contract version `36`, manifest byte count and SHA-256, member
    and placeholder counts, zero staging payload entries and bytes,
    complete-vector byte count, `ARG_MAX`, start-available bytes, and one
    source-identity row per member. The final length-delimited payload is the
    exact manifest bytes.

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
- Every member has exactly one decoded mountinfo record at its canonical path.
  Its root, device, and read-only option match the trusted host snapshot. Its
  file type, `st_dev`, and `st_ino` match the host source.
- Omitting one member `--ro-bind` leaves a correctly typed placeholder and
  preserves manifest-to-view name equality, but fails source-identity checks.
- A fixture seeds copied member contents and private Nix state beneath otherwise
  valid member binds. The pre-namespace staging-shape check must reject it, so
  hidden copied state can't satisfy the closure-view contract.
- `/nix/var`, `/nix/var/nix/db`, `/nix/var/nix/db/db.sqlite`, and
  `/nix/var/nix/daemon-socket/socket` return `ENOENT`. The accepted runtime
  fixture first requires those host paths to exist with directory, regular-file,
  and socket types as applicable, so the namespace absence proof isn't vacuous.
- A duplicate-aware source-shape fixture accepts exactly one owned-store-base
  `--ro-bind` to `/nix/store` and one same-path `--ro-bind` per manifest member.
  It rejects every other bind-family option whose source or destination is
  `/nix` or a descendant. Rejected cases include broad `/nix`, `/nix/store`,
  and `/nix/var` binds and every extra or missing closure-view bind.
- An ambient host-store canary outside the manifest stays hidden.
- Every mounted member and the owned store base reject writes.
- Direct references, script interpreters, Executable and Linkable Format (ELF)
  loaders, and runtime search paths resolve only within the manifest.
- The Flutter Rust Bridge generator, Cargo, `rustc`, the `rustup` shim, Dart,
  CMake, Ninja, Clang, OpenSSL, `jq`, Sway, `swaymsg`, `iproute2`, and
  Bubblewrap run from the view.
- Forbidden clients remain absent.
- The complete null-terminated environment and argument vector stays below
  half of `ARG_MAX`.
- The exact 4,000,000,000-byte start-space boundary passes, and one byte below
  it fails before candidate execution.
- `--disable-userns` enters an internal nested user namespace that prevents the
  candidate from creating further user namespaces. Candidate assertions don't
  start a second Bubblewrap process.
- The no-network, private-PID, descriptor, teardown, and cleanup
  fixtures continue to pass.
- The trusted launcher creates exactly one
  `logs/burl-m003-linux-closure-view.log` internal artifact. Fresh sealing
  validates its fixed-order fields, source rows, exact manifest payload, byte
  count, and SHA-256. The accepted role manifest retains its name, byte count,
  and SHA-256 through `roleEvidence.internalArtifacts`. The aggregate embeds
  that manifest and binds the unchanged role and sealed bundles through the
  schema's `roleBundleSha256` and `sealedBundleSha256` fields.

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
  successful-only evidence contract.
- ADR-0019 remains unchanged and continues to govern OD-11 authority.
- Stage 4 must adapt only the `BURL-M003` closure implementation. It must add or
  retain an explicit `BURL-O001` stop and Stage 3 route without changing the
  epic graph.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Linux `/proc/PID/mountinfo` format](https://www.kernel.org/doc/html/latest/filesystems/proc.html#proc-pid-mountinfo-information-about-mounts)
- [Linux `stat` structure](https://man7.org/linux/man-pages/man3/stat.3type.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
