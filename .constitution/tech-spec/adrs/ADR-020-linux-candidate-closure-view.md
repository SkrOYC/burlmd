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
6. In the trusted parent, resolve `bwrap` to
   `locked_bubblewrap_store_member/bin/bwrap`. Raw contract version `36` pins
   that x86-64 Linux member to
   `/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2`. Require
   the store member in the manifest. Run that exact path with only `--version`,
   and require the exact output
   `bubblewrap 0.11.2`, one final line feed, empty standard error, and status
   zero. Use the same path for the candidate invocation. The in-namespace
   preflight and candidate must not execute another Bubblewrap process.
7. Add `--disable-userns` and `--assert-userns-disabled` to the one candidate
   Bubblewrap invocation. Bubblewrap enters its internal nested user namespace.
   Candidate assertions check only the resulting namespace, mount, process,
   descriptor, and network properties.
8. Resolve `command -v env` to its absolute store command path and require its
   store member in the manifest. The command path may be an internal member
   symlink. Require `readlink -f` to resolve to a regular executable in the same
   member. Create `/usr` and `/usr/bin` with `--dir`, then use
   `--symlink <env-command-path> /usr/bin/env`. The target is in the already
   mounted same-path, read-only manifest member. Don't bind a store source at
   `/usr/bin/env` or expose host `/usr`.
9. Count the complete null-terminated environment and argument vector before
   `exec`. Include the Bubblewrap arguments, every closure bind, the
   `/usr/bin/env` symlink arguments, and the candidate command. Reject a total
   at or above half of `getconf ARG_MAX`.
10. Before the first candidate command, enumerate every capacity-relevant
    writable root used by `BURL-M003`. Include the source checkout, disposable
    workspace, role output and results, dependency caches, build and generated
    output, temporary storage, candidate home and configuration, closure
    staging, per-session storage, and private Sway runtime. Also include every
    host source of a writable bind and every writable environment path. Create
    and canonicalize the complete set before the guard; no later step may add a
    writable root.
11. Group those roots by distinct `st_dev`. Immediately before namespace entry,
    compute available bytes once per distinct containing filesystem from
    `statvfs.f_bavail * statvfs.f_frsize`. Require at least 4,000,000,000 bytes
    on every device. If a root, device, or observation is missing, inconsistent,
    unavailable, overflowed, or below the floor, fail before candidate commands.
12. Treat the space check only as a start guard. Don't claim that it measures a
   complete phase peak or proves capacity for another ticket.
13. Retain the exact manifest and launch observations in
    `logs/burl-m003-linux-closure-view.log`. The trusted launcher creates this
    internal artifact outside candidate-writable paths. Its byte grammar is the
    raw contract's `closure_view_log_policy`, and the raw contract contains its
    canonical golden fixture. The log records raw contract version `36`, the
    exact Bubblewrap path and version, manifest identity, staging observations,
    complete-vector size, `ARG_MAX`, every root-to-device mapping, each distinct
    filesystem's available bytes, and one source-identity row per member. Its
    literal `manifest-payload:` delimiter precedes the exact length-delimited
    manifest bytes. The manifest's final line feed is the log's final byte.
14. Frame the trusted in-namespace preflight record as the ASCII line
    `preflight-bytes=<canonical-decimal>`, followed by exactly that many body
    bytes and end of file on a parent-owned pipe. The parent validates the
    complete record before it acknowledges candidate start. Candidate commands
    inherit neither preflight pipe descriptor.

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
cmake ninja pkg-config clang openssl jq ip
```

The trusted Linux runtime group is:

```text
bwrap sway swaymsg
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
  and `/nix/var` binds and every extra or missing closure-view bind. The only
  accepted non-bind exception is the exact `--symlink` from the mounted
  canonical `env` path to `/usr/bin/env`; the fixture rejects a bind at that
  destination, a broad `/usr` bind, and any other target.
- An ambient host-store canary outside the manifest stays hidden.
- Every mounted member and the owned store base reject writes.
- Direct references, script interpreters, Executable and Linkable Format (ELF)
  loaders, and runtime search paths resolve only within the manifest.
- A script whose first line is exactly `#!/usr/bin/env bash` runs through the
  canonical store-backed `env` symlink.
- The Flutter Rust Bridge generator, Cargo, `rustc`, the `rustup` shim, Dart,
  CMake, Ninja, Clang, OpenSSL, `jq`, Sway, `swaymsg`, `iproute2`, and
  their runtime dependencies run from the view.
- The trusted parent proves the exact locked Bubblewrap path and version, then
  uses that path for the sole candidate Bubblewrap invocation. The preflight
  and candidate traces contain no other Bubblewrap execution.
- Forbidden clients remain absent.
- The complete null-terminated environment and argument vector stays below
  half of `ARG_MAX`.
- The complete capacity-root inventory maps every root to a device and contains
  one observation per distinct `st_dev`. An omitted root or device fails. The
  exact 4,000,000,000-byte boundary passes on every device; a secondary device
  at 3,999,999,999 bytes fails even when the primary device passes.
- `--disable-userns` enters an internal nested user namespace that prevents the
  candidate from creating further user namespaces. Candidate assertions check
  the resulting property and don't start another Bubblewrap process.
- The no-network, private-PID, descriptor, teardown, and cleanup
  fixtures continue to pass.
- The trusted launcher creates exactly one
  `logs/burl-m003-linux-closure-view.log` internal artifact. Fresh sealing
  validates its exact grammar, golden fixture, Bubblewrap identity, capacity
  rows, source rows, manifest payload, byte count, and SHA-256. Mutation
  fixtures reject noncanonical decimals or hexadecimal, invalid type or
  read-only tokens, bad escaping, reordering, incorrect counts, a changed
  delimiter, payload-length drift, a missing final line feed, and trailing
  data. The accepted role manifest retains the log's name, byte count, and
  SHA-256 through `roleEvidence.internalArtifacts`. The aggregate embeds that
  manifest and binds the unchanged role and sealed bundles through the schema's
  `roleBundleSha256` and `sealedBundleSha256` fields.

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
- ADR-0019's OD-11 authority remains unchanged; its live raw-contract reference
  is version `36`.
- Stage 4 must adapt only the `BURL-M003` closure implementation, trusted-parent
  identity proof, log grammar, and per-device start guard. It must add or retain
  an explicit `BURL-O001` stop and Stage 3 route without changing the epic
  graph.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Linux `/proc/PID/mountinfo` format](https://www.kernel.org/doc/html/latest/filesystems/proc.html#proc-pid-mountinfo-information-about-mounts)
- [Linux `stat` structure](https://man7.org/linux/man-pages/man3/stat.3type.html)
- [Linux `statvfs` filesystem statistics](https://man7.org/linux/man-pages/man3/statvfs.3.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
