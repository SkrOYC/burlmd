---
id: ADR-0020
status: accepted
date: 2026-09-07
certainty: assumed
assumption: "An exact read-only view of the locked BURL-M003 candidate closure, with Bubblewrap kept in a separate trusted-parent tool closure, preserves Linux isolation and fits the standard ubuntu-24.04 runner. Local prototypes exercised the mechanism, but no managed BURL-M003 run has exercised it."
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

1. Derive the exact `BURL-M003` candidate-closure manifest from the
   authoritative launcher's locked runtime roots. Expand the roots with pinned
   Nix `2.35.2` and `nix-store -qR`. Sort them with `LC_ALL=C`, and write one
   canonical path per line. Require `cmp` from locked Diffutils `3.12` and `ps`
   from locked Procps `4.0.6`. Reject any root-resolution result under ambient
   `/usr`, `/run/current-system`, or another non-store path. Exclude Bubblewrap
   and any member that only its trusted-parent tool closure reaches.
2. Immediately before every namespace entry, the trusted launcher records each
   host member's file type, device, inode, containing-mount device, and
   computed mount root. It exposes the path-sorted snapshot read-only at
   `/contract/locked-nix-closure.sources`. Create a fresh owned staging root
   whose only child is the store base. The base contains exactly one
   source-distinct, empty mount point of the correct type for each member. Bind
   the base read-only at `/nix/store`, then bind each member read-only at its
   canonical path.
3. Before every session's candidate command, a trusted namespace preflight
   verifies each member against that host snapshot. The decoded
   `/proc/self/mountinfo` data must contain exactly one mount at the member path.
   Its root,
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
   no-network, descriptor-closure, teardown-lock, and cleanup controls for
   every candidate session.
6. Keep Bubblewrap in a separate trusted-parent-only tool closure. Raw contract
   version `36` pins its x86-64 Linux store member to
   `/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2`. The
   sorted eight-path tool-closure manifest is 480 bytes and has SHA-256
   `398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd`.
   The exact `bin/bwrap` executable has SHA-256
   `c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726`.
   Require those identities before the first session and revalidate both
   digests before every later session. Run the executable with only
   `--version`, and require the exact output `bubblewrap 0.11.2` plus one final
   line feed, empty standard error, and status zero.
7. Invoke that trusted-parent executable once per candidate session. Each
   invocation includes `--unshare-all`, `--unshare-user`, `--uid 0`, `--gid 0`,
   `--unshare-net`, `--disable-userns`, `--assert-userns-disabled`,
   `--cap-add CAP_NET_ADMIN`, `--die-with-parent`, and `--new-session`.
   Bubblewrap enters its internal nested user namespace. Candidate assertions
   check only the resulting namespace, mount, process, descriptor, and network
   properties. The in-namespace preflight and candidate don't execute another
   Bubblewrap process.
8. Resolve `command -v env` to its absolute store command path and require its
   store member in the manifest. The command path may be an internal member
   symlink. Require `readlink -f` to resolve to a regular executable in the same
   member. Create `/usr` and `/usr/bin` with `--dir`, then use
   `--symlink <env-command-path> /usr/bin/env`. The target is in the already
   mounted same-path, read-only manifest member. Don't bind a store source at
   `/usr/bin/env` or expose host `/usr`.
9. Before each `exec`, count that session's complete null-terminated
   environment and argument vector. Include the Bubblewrap arguments, every
   closure bind, the `/usr/bin/env` symlink arguments, and the candidate
   command. Reject a total at or above half of `getconf ARG_MAX`.
10. Before the first candidate session, create and canonicalize every stable
    writable parent used by `BURL-M003`. Freeze the complete capacity authority
    set from those parents, not from session leaves. Include the source
    checkout, disposable workspace, role output and results, dependency caches,
    build and generated output, temporary storage, candidate home and
    configuration, closure staging, session storage, private Sway runtime,
    every writable-bind source, and every writable environment path. For each
    capacity slot, freeze its stable identifier, kind, canonical parent,
    `st_dev`, and decoded containing-mount ID, device, root, and mount point.
    Also freeze whether the slot uses
    the stable parent itself or one declared per-session staging, session, or
    writable-bind leaf. No later step may add a parent, mount, device, capacity
    slot, leaf declaration, or writable path outside this authority set.
11. For each session, create its declared ephemeral leaves only under their
    frozen stable parents. Walk and canonicalize each current leaf without
    following symbolic links. Require strict containment, the parent's frozen
    mount ID on every path component, and a leaf `st_dev` equal to the
    parent's frozen `st_dev`. Add only the current leaf to that session's frame.
    Immediately before namespace entry, revalidate every stable parent and
    current leaf. Group the frozen parent devices by distinct `st_dev`, and
    compute available bytes once per device from
    `statvfs.f_bavail * statvfs.f_frsize`. Require at least 4,000,000,000 bytes
    on every device. Reject a missing or changed authority, an undeclared leaf,
    a symbolic-link escape, a nested mount, a device mismatch, or an unavailable,
    inconsistent, overflowed, or smaller observation before the candidate
    command. After each session, remove all of its ephemeral leaves. A later
    session must not stat or include a removed leaf from an earlier session.
12. Treat each space check only as a start guard. Don't claim that it measures
    a complete phase peak or proves capacity for another ticket.
13. Retain the exact manifest and launch observations in
    `logs/burl-m003-linux-closure-view.log`. The trusted launcher creates this
    internal artifact outside candidate-writable paths. Its byte grammar is the
    raw contract's `closure_view_log_policy`, and the raw contract contains its
    canonical golden fixture. The log records raw contract version `36`, the
    exact Bubblewrap path, version, executable digest, and tool-closure digest.
    It also records the candidate-manifest identity and one source-identity row
    per member. Seven ordered session frames retain each invocation's manifest,
    source, namespace-flag, unique staging-root, and preflight digests. Each
    frame also retains the stable-parent-to-current-path mapping,
    complete-vector, start-space, and cleanup observations.
    Its literal `manifest-payload:` delimiter precedes the exact
    length-delimited candidate manifest bytes. The manifest's final line feed
    is the log's final byte.
14. Before it creates the handshake pipes, establish the candidate's final
    standard streams as descriptors 0, 1, and 2. In the Bubblewrap launch
    branch, map only the preflight-record write end to descriptor 3 and the
    acknowledgement read end to descriptor 4. Close the opposite and original
    ends before executing Bubblewrap. The parent closes both child ends. The
    preflight must report exactly descriptors 0 through 4 and their assigned
    directions. It frames its record as the ASCII line
    `preflight-bytes=<canonical-decimal>`, followed by exactly that many body
    bytes and end of file on descriptor 3. The wrapper closes descriptor 3
    before it waits for acknowledgement. The parent validates the complete
    record and end of file, closes its read end, writes exactly ASCII `G`, and
    closes its acknowledgement end. The wrapper requires `G` followed by end
    of file, then closes descriptor 4. Immediately before it replaces itself
    with the candidate, the wrapper requires exactly descriptors 0, 1, and 2
    with the original `fstat` file type, `st_dev`, `st_ino`, decoded
    `/proc/self/fd` target, and access mode for each standard stream. The parent
    and candidate retain no handshake descriptor.
15. Use these seven session IDs in this exact order:
    `generated-bindings`, `flutter-test`, `dart-analyze`, `cargo-metadata`,
    `integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d`,
    `integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d`,
    and `managed-isolation`. Sort the two repository-relative integration-test
    paths by their UTF-8 bytes with `LC_ALL=C`. For each path, hash exactly its
    UTF-8 bytes without a byte-order mark, Unicode normalization, delimiter,
    NUL, carriage return, line feed, or other terminator. Append the lowercase
    SHA-256 to `integration-`. Require fresh ephemeral leaves, a preflight,
    namespace, teardown, and cleanup for every ID. Don't start the next session
    before the preceding teardown lock is free and its staging root is absent.
16. Keep Bubblewrap absent from the candidate manifest, mounts, and `PATH`.
    Inside every session, require `command -v bwrap` to fail. Require an
    exact-path probe of the trusted-parent executable to return `ENOENT`, and a
    command-name invocation to return status `127`.

## Exact closure roots

Resolve the following command groups through the authoritative `BURL-M003`
launcher environment. Reduce each resolved command to its top-level
`/nix/store` path before closure expansion.

The required-tool group is:

```text
bash sh mkdir mktemp chmod install cp mv rm awk sed grep rg sort sha256sum wc
find tar zstd flock getconf df ps cmp sleep setsid perl readlink uname tr head
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

The candidate's trusted Linux runtime group is:

```text
sway swaymsg
```

Resolve `cargo-expand` from `BURLMD_CARGO_EXPAND`. Resolve the OpenSSL
`pcfiledir`, `includedir`, and `libdir` values through `pkg-config`. Resolve the
Mesa roots from `BURLMD_MESA_DRI_PATH` and `BURLMD_MESA_EGL_VENDOR_PATH`.
`BURL-M003` must add `pkgs.diffutils` and Linux-only `pkgs.procps` to
`devenv.nix`. Require these exact command paths:

```text
/nix/store/3c05s0vxy8wafaa7lkj4bfh69wa0ch10-diffutils-3.12/bin/cmp
/nix/store/ly5j6qg2q3vn899jd9dz0hx11gvjh9f1-procps-4.0.6/bin/ps
```

Reject an empty manifest, a duplicate or noncanonical path, a missing member,
a top-level symbolic link, or a direct Nix reference outside the manifest.
Reject the Bubblewrap store member and any member that only its parent tool
closure reaches. Record the manifest SHA-256 and verify the same bytes before
each candidate session. Internal links remain inside their mounted store object.

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
- The trusted parent proves the exact locked Bubblewrap path, version,
  executable digest, and separate tool-closure digest. It uses that path for
  each of the seven candidate-session invocations. The candidate manifest and
  `PATH` omit Bubblewrap, exact-path and command-name probes fail, and the
  preflight and candidate traces contain no other Bubblewrap execution.
- Forbidden clients remain absent.
- `cmp` and `ps` resolve to the exact locked paths. A path under `/usr`,
  `/run/current-system`, or another non-store root fails before candidate
  execution.
- The integration session hashes cover only each repository-relative path's
  UTF-8 bytes. Fixtures reject a byte-order mark, normalization, a NUL, a line
  feed, a carriage return, another terminator, and platform newline conversion.
- Every session's complete null-terminated environment and argument vector
  stays below half of `ARG_MAX`.
- For every session, each capacity slot maps to a frozen stable parent and
  device. Each ephemeral staging, session, or
  writable-bind leaf is created only under its declared parent. Before the
  guard, the launcher canonicalizes the current leaf without following links.
  It rejects a symbolic-link escape, nested mount, or `st_dev` mismatch. The
  session frame contains only that session's current leaves. The launcher
  removes those leaves after the session and doesn't stat a removed earlier
  leaf during a later session. Fixtures run this create, check, and remove
  sequence for all seven sessions. They also reject an undeclared leaf, an
  omitted stable parent or device, and any parent, mount, device, or writable
  path outside the frozen authority set. The exact 4,000,000,000-byte boundary
  passes on every device. A secondary stable device at 3,999,999,999 bytes
  fails even when the primary device passes.
- `--disable-userns` enters an internal nested user namespace that prevents the
  candidate from creating further user namespaces. Candidate assertions check
  the resulting property and don't start another Bubblewrap process.
- Every session gets one fresh namespace, staging root, preflight, and cleanup.
  The preflight has exactly descriptors 0 through 4 with the specified stream
  and pipe directions. The candidate has exactly descriptors 0 through 2 with
  unchanged standard-stream identities and access modes. Fixtures reject
  reversed or leaked pipe ends, an extra descriptor, early acknowledgement,
  either missing end of file, a wrong acknowledgement byte, standard-stream
  substitution, or candidate execution before the complete validated exchange.
  The no-network, private-PID, teardown, survivor-rejection, and cleanup
  fixtures continue to pass. Nested and candidate-started Bubblewrap remain
  forbidden.
- The trusted launcher creates exactly one
  `logs/burl-m003-linux-closure-view.log` internal artifact. Fresh sealing
  validates its exact grammar, golden fixture, parent tool identity, session
  order, session count, namespace flags, capacity authority rows, current-leaf
  rows, source rows, preflight digests, cleanup results, manifest payload, byte
  count, and SHA-256. Mutation
  fixtures reject noncanonical decimals or hexadecimal, invalid type or
  read-only tokens, bad escaping, reordering, an incorrect session ID or count,
  a missing session boundary, a changed digest or delimiter, payload-length
  drift, a missing final line feed, and trailing data. The accepted role
  manifest retains the log's name, byte count, and SHA-256 through
  `roleEvidence.internalArtifacts`. The aggregate embeds that manifest and
  binds the unchanged role and sealed bundles through the schema's
  `roleBundleSha256` and `sealedBundleSha256` fields.

## Local prototype facts

Two independent reproductions used pinned Nix `2.35.2` against PR #15 commit
`9719259f1ecee819af96c98c2be210156f198343`. After separating Bubblewrap and
resolving the two command roots from the locked Nixpkgs revision, each run
derived 549 candidate-manifest paths, 34,418 manifest bytes, and 74,326
bind-only argument bytes. The candidate manifest's SHA-256 is
`c82bb681b260902382f9a747d0f8588ab29bb1d8d56cec0f7b7c30fc368399d9`.
The summed Nix archive (NAR) sizes are 6,338,161,576 bytes. `ARG_MAX` was
2,097,152 bytes.

The separate trusted-parent Bubblewrap closure contains eight paths. Its
480-byte manifest has SHA-256
`398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd`,
its bind-only arguments use 1,040 bytes, and its summed NAR sizes are
40,679,016 bytes. The candidate closure removes the Bubblewrap store member and
its otherwise unreferenced `libcap` member. The pinned executable has SHA-256
`c500b527e18f7e32634ac497b78a0150ceb31ae70fa8afef3fbbe79fd1d9f726`.

The prototype found no top-level symbolic links. It hid an unlisted host path,
rejected writes to a member and the store base, and ran representative dynamic
and script tools. Candidate-manifest inspection found no Bubblewrap member. The
prototype also exposed no forbidden `PATH` client and prevented the candidate
from creating further user namespaces.

The 74,326-byte value covers only bind triples. The prototype didn't retain any
session's complete environment and argument count. The per-session
complete-vector fixture therefore remains assumed until a managed `BURL-M003`
run exercises it.

These local results prove the closure-view mechanics. They don't establish
hosted capacity or feature availability and can't settle ADR-0020 without
accepted managed `BURL-M003` completion evidence from the standard runner.

The 4,000,000,000-byte per-session start guard remains an assumed admission
floor. The reproducible NAR-size sum isn't a host-allocation or peak-usage
measurement, so this ADR makes no exact runner-headroom claim.

## Scope boundary

This decision doesn't authorize or solve `BURL-O001` Nix packaging isolation
or capacity. `BURL-O001` requires a later Stage 3 decision before
implementation. That decision must follow its own packaging evidence and
upstream scope. This ADR makes no `BURL-O001` runner, storage, evidence, or
coordinator decision.

## Consequences

- `BURL-M003` avoids a second physical copy of its locked candidate runtime
  closure.
- Bubblewrap remains a trusted-parent tool and doesn't enter the candidate
  closure or `PATH`.
- Candidate code can read only manifest-listed store paths and can't change the
  host closure.
- A missing closure dependency, excessive argument vector, unavailable start
  space, session mismatch, incomplete teardown, or failed isolation check
  produces no accepted evidence under the successful-only evidence contract.
- ADR-0019's OD-11 authority remains unchanged; its live raw-contract reference
  is version `36`.
- Within `BURL-M003`'s existing `devenv.nix`, `devenv.lock`, and `scripts/**`
  scope, Stage 4 may adapt the locked Diffutils and Procps packages,
  per-session lifecycle, and retained proof. It must preserve one namespace
  per session, no nested or candidate Bubblewrap, no network, private PID
  ownership, the exact descriptor handshake, teardown, and exact closure-view
  identity. It must add or retain an explicit `BURL-O001` stop and Stage 3
  route without changing the epic graph.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Bubblewrap `0.11.2` descriptor handling](https://github.com/containers/bubblewrap/blob/v0.11.2/bubblewrap.c)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Linux `/proc/PID/mountinfo` format](https://www.kernel.org/doc/html/latest/filesystems/proc.html#proc-pid-mountinfo-information-about-mounts)
- [Linux `stat` structure](https://man7.org/linux/man-pages/man3/stat.3type.html)
- [Linux `statvfs` filesystem statistics](https://man7.org/linux/man-pages/man3/statvfs.3.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
