---
id: ADR-0020
status: accepted
date: 2026-09-07
certainty: assumed
assumption: "Two exact read-only BURL-M003 session closures, complete Bubblewrap argv commitments, and in-namespace Sway supervision preserve the Linux isolation boundary within the standard ubuntu-24.04 runner. Local measurements and a supervisor prototype exercised the mechanism, but no accepted managed run has settled it."
---
# ADR-020: Linux candidate closure view

**Status:** Accepted as an assumed implementation contract
**Implementation owner:** `BURL-M003`

## Context

PR #15 commit `9719259f1ecee819af96c98c2be210156f198343`
copies the Linux candidate closure into a private Nix store. Its measured
prebuild allocation is 15,382,421,504 bytes. This exceeds the
14,000,000,000-byte standard `ubuntu-24.04` profile.

`BURL-M003` needs exact runtime members, but it doesn't need Nix command
authority. An exact read-only view avoids the second copy and preserves
ADR-0019's containment boundary.

The earlier draft had two trust defects. It retained only a fixed flag digest
and a complete-vector byte count. Those values didn't bind the effective
Bubblewrap invocation. It also ran Sway in the trusted parent and bound a
parent-owned Wayland socket into every session. Arbitrary tested-source code is
hostile, so the parent must not receive candidate-controlled display traffic.

This correction doesn't change candidate placement, fresh-seal authority,
evidence schemas, service artifacts, session IDs, or `BURL-O001` scope.

## Decision

### Keep one trusted parent tool

The trusted parent keeps only Bubblewrap `0.11.2`. Its executable is:

```text
/nix/store/g7svy17fhkg2cq3q4lfzzc0mmsl3d8hq-bubblewrap-0.11.2/bin/bwrap
```

The parent validates its exact version output, executable SHA-256, and
eight-member closure before every session. It calls `execve` directly with an
empty process environment and launches that executable once per session. It
launches no Sway, `swaymsg`, candidate helper, `env` process, or display proxy.
Bubblewrap doesn't enter either session closure or `PATH`.

### Use two session closures

Five base sessions use the exact base manifest:

```text
generated-bindings
flutter-test
dart-analyze
cargo-metadata
managed-isolation
```

The two integration sessions use the exact integration manifest:

```text
integration-378c340b182c219c9b1067d7918e48a70ed42307453d3b69402a1b075786b58d
integration-2aa91e4e2d4b0febdfc223ef1bae763bf139e2fc6f81409a05bf19c5c9139e9d
```

The integration manifest is the sorted union of the base manifest and the
requisite closure of these exact executables:

```text
/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway
/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/swaymsg
```

Use the unwrapped Sway executable. The Nix wrapper can start a D-Bus session,
which would add an unnecessary process and environment boundary.

Base sessions must not mount a compositor-only member. They must not expose
`WAYLAND_DISPLAY`, `SWAYSOCK`, `DISPLAY`, or a `WLR_*` variable. They must not
create a Wayland or Sway IPC socket or run a compositor process.

### Bind the complete Bubblewrap argv

For every session, serialize `argv[0]` and each following argument as exact
UTF-8 bytes followed by one NUL byte. An empty argument is one NUL byte. There
is no count, prefix, alternate delimiter, or trailing byte after the final NUL.

The encoded vector includes all of these values in their binding order:

- The exact Bubblewrap executable.
- Every namespace, user, capability, environment, lifecycle, and session
  option.
- Every directory, device, process, temporary-filesystem, symbolic-link, and
  bind option.
- Every bind source and destination, including each same-path closure member.
- The selected base or integration manifest.
- The trusted preflight and supervisor executable and arguments.
- The exact session command and all its arguments.

Raw contract version `37` defines the complete ordered construction. Dynamic
sources come only from the retained capacity-authority and current-path rows.
The launcher hashes the complete NUL-delimited bytes and executes the same
in-memory vector without shell reparsing.

Each session frame retains the complete-vector byte count and SHA-256. Fresh
sealing reconstructs the vector from raw contract version `37`, the selected
manifest payload, and retained authority/current-path rows. It requires exact
byte count and SHA-256 equality.

A flag-subsequence digest, byte count, set comparison, successful parse, or
successful execution can't replace this commitment. Duplicate-aware fixtures
reject every extra, omitted, reordered, duplicated, or substituted argument.
The mutations include extra capabilities, contract-mount changes, and host-root
alias binds.

### Preserve the closure view

For each session, the launcher creates one fresh staging leaf under its frozen
stable parent. The leaf contains one empty, source-distinct placeholder per
selected manifest member and no other payload.

The complete argv binds the owned store base read-only at `/nix/store`, then
binds every selected manifest member read-only at its canonical path. The view
hides host `/`, `/usr`, `/nix`, `/nix/store`, `/nix/var`, the Nix database, the
daemon socket, Bubblewrap, and unlisted store members.

The preflight reads its selected source identities from
`/contract/locked-nix-closure.sources`. The launcher creates one per-session
contract leaf under the frozen `session-contract-root` parent. Its retained
authority and current-path row is the only source for the bind. The leaf
contains only the mode-0444 regular file `locked-nix-closure.sources`. Its bytes
and SHA-256 match the selected source-identity rows.

The complete argv creates `/contract`, then mounts that leaf read-only after
the session-root bind and before the prepared-root bind. Fixtures reject a
missing, writable, linked, substituted, duplicated, incorrectly named, or extra
entry. They also reject another `/contract` mount, a changed source or
destination, and an authority row that doesn't resolve uniquely.

The trusted in-namespace preflight validates the selected manifest against
decoded mount information, device, inode, type, and read-only state. It also
preserves the existing descriptor handshake:

- Descriptors 0 through 2 are the final candidate streams.
- Descriptor 3 is the preflight-record write end.
- Descriptor 4 is the acknowledgement read end.
- The parent validates the complete framed record and end of file before it
  sends ASCII `G` and closes its end.
- The candidate receives only descriptors 0 through 2.

### Start Sway only inside integration sessions

The trusted supervisor starts Sway and the candidate as untrusted siblings in
the integration session's existing Bubblewrap namespace. It uses `env -i`
with exactly these Sway variables:

```text
PATH=/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin
HOME=/candidate/home
XDG_CONFIG_HOME=/candidate/xdg/config
XDG_RUNTIME_DIR=/candidate/xdg/runtime
LC_ALL=C.UTF-8
LANG=C.UTF-8
WLR_BACKENDS=headless
WLR_RENDERER=pixman
WLR_HEADLESS_OUTPUTS=1
WLR_LIBINPUT_NO_DEVICES=1
SWAYSOCK=/candidate/xdg/runtime/sway-ipc.sock
```

It starts Sway with exactly:

```text
/nix/store/b8fqdxmnygnqv5p29fhw85d3lcgsi4qn-sway-unwrapped-1.12/bin/sway
--verbose
--config
/trusted/scripts/managed-sway.conf
```

The reviewed configuration is exactly:

```text
swaybg_command -
xwayland disable
output HEADLESS-1 mode 1920x1080@60Hz
```

The 72-byte file has SHA-256
`dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a`.
The first directive is the supported Sway 1.12 form for disabling the default
`swaybg` helper. The file contains no `include`, `exec`, `exec_always`, or shell
expansion. Sway gets no ambient configuration. The supervisor rejects any
`swaybg` process or output.

Sway `1.12` tries `wayland-1` through `wayland-32` in order. The supervisor
starts from an empty mode-0700 runtime directory and accepts only
`/candidate/xdg/runtime/wayland-1`. The socket's lock file and the exact
`sway-ipc.sock` are the only other permitted runtime entries. The candidate
receives `WAYLAND_DISPLAY=wayland-1` and
`XDG_RUNTIME_DIR=/candidate/xdg/runtime`. It doesn't receive `SWAYSOCK`,
`DISPLAY`, or a `WLR_*` variable.

The supervisor calls the exact `swaymsg` with `--socket`, `--type get_version`,
and `--raw` for readiness. The parent never opens or parses Wayland or Sway IPC
traffic. Candidate output, Sway, `swaymsg`, sockets, and compositor output are
untrusted. Only fresh sealing of retained artifacts is authoritative.

### Clear the candidate environment at final launch

Bubblewrap passes the fixed and derived variables from the raw contract to the Bash
supervisor. While Bash 5.3p9 runs, it creates exported `PWD`, `SHLVL`, and `_`
values. The supervisor must not pass those additions to the candidate.

Immediately before candidate execution, the supervisor invokes this exact GNU
`env` executable as the final environment boundary:

```text
/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin/env
```

For a base session, the supervisor replaces itself with `env -i --`, followed
by the 33 resolved fixed and derived assignments in contract order. The exact
candidate command follows those assignments. For an integration session, the
new candidate process group appends the four integration assignments. It
therefore passes 37 entries before the candidate command. The supervisor rejects
duplicate keys, unresolved placeholders, and any extra, missing, reordered, or
changed assignment.

This boundary passes only the declared environment to the candidate executable.
A pinned script interpreter can add its own `PWD`, `SHLVL`, or `_` after entry.
Those interpreter-local values aren't inherited launch authority and aren't
claimed to be absent from later child processes. Fixtures probe both boundaries.
They inject hostile inherited values and reject any leak or variant at direct
candidate entry. They also record the variables that each pinned interpreter
adds after entry.

### Clean up before namespace exit

The supervisor monitors the candidate, Sway, `wayland-1`, its lock, and the
session timeout. On success, candidate failure, early Sway failure, socket
disruption, interruption, or timeout, it performs these steps:

1. Stop and reap the candidate process group and all descendants.
2. Send `SIGTERM` to Sway and wait for it.
3. Send `SIGKILL` only after the bounded graceful wait expires, then wait
   again.
4. Require `kill(pid, 0)` to return `ESRCH`, `/proc/PID` to be absent, and no
   `swaybg` process to remain.
5. Securely create and fsync the canonical cleanup frame after no hostile
   process remains.
6. Wait while the parent validates and fsyncs the matching retained session
   frame, then accept the parent's exact `K` acknowledgement.
7. Remove the cleanup handshake files and exit the namespace.

The cleanup frame records the session ID, result class, Sway PID, termination
path, wait status, `sway-reaped=true`, and `cleanup-complete=true`. A malformed
record, precreated link, wrong inode, missing fsync, missing acknowledgement,
unexpected supervisor signal, or failed reap rejects the session.

Fixtures cover early Sway failure, hostile candidate exit and descendants,
timeout, socket disruption, handled interruption, successful graceful reap,
the `SIGKILL` fallback, cleanup-frame precreation, and injected `swaybg` process
and output canaries.

### Retain capacity and evidence authority

Preserve the frozen stable-parent authority, current-leaf mapping, per-device
4,000,000,000-byte start guard, source identities, staging checks, teardown
lock, and exact seven-session order.

The version 2 closure-view log retains both manifest payloads, every complete
argv digest, every authority/current-path mapping, and integration cleanup
results. Fresh sealing validates the complete log before it authenticates the
bundle. The unchanged role and aggregate schemas bind the log through existing
role-bundle and sealed-bundle digests.

## Reproduced measurements

Two independent runs used pinned Nix `2.35.2` and produced identical results:

| Closure | Paths | Manifest bytes | SHA-256 | Summed NAR bytes | Bind argv bytes |
| :--- | ---: | ---: | :--- | ---: | ---: |
| Base session | 488 | 30,717 | `127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64` | 6,184,635,112 | 66,314 |
| Unwrapped compositor only | 195 | 11,865 | `d97a41799b1aecc670e31bfd58b339d748498be2bce09d877a0f1a9ed1c6e673` | 649,324,904 | 25,680 |
| Integration session | 547 | 34,315 | `353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896` | 6,338,147,240 | 74,100 |
| Bubblewrap parent | 8 | 480 | `398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd` | 40,679,016 | 1,040 |

The bind values measure only the manifest-dependent `--ro-bind PATH PATH`
triples. Every production session must measure and hash its complete argv.

A local prototype started the exact unwrapped Sway and `swaymsg` executables
with the exact environment, arguments, and configuration. It covered success,
early Sway failure, socket disruption, timeout, and a hostile candidate that
exited with status 42 after starting a descendant. Every case removed the
candidate descendants, waited for Sway, and verified that its PID was absent.

The argv prototype reproduced the 533-byte golden digest,
`31df65a44206be9976b25562dab9fcf675dc4500a268c54171e79c60253fa1e4`.
It includes the ordered `/contract` directory and read-only bind. The prototype
rejected extra, omitted, reordered, duplicated, substituted, contract-mount,
and host-alias mutations.

The revised 72-byte Sway configuration passed Sway 1.12 validation and a
headless launch. The launch created the expected IPC socket and no `swaybg`
process. A Bubblewrap 0.11.2 and Bash 5.3p9 probe injected hostile `PWD`,
`SHLVL`, `_`, and canary values. The final GNU `env -i` boundary exposed only
the declared candidate environment.

These local results don't establish hosted capacity or feature availability.
They can't settle ADR-0020 without accepted managed `BURL-M003` completion
evidence.

## Scope boundary

This decision doesn't authorize or solve `BURL-O001` Nix packaging isolation
or capacity. `BURL-O001` requires a later Stage 3 decision based on its own
packaging evidence. This ADR makes no packaging runner, storage, evidence, or
coordinator decision.

## Consequences

- Bubblewrap remains the only parent-launched session process.
- Base sessions have no compositor surface.
- Integration sessions treat Sway as untrusted code inside their existing
  containment boundary.
- The complete argv commitment detects extra authority that counts or partial
  flag digests miss.
- Missing dependencies, invalid cleanup, excessive argv size, or failed
  isolation produce no accepted evidence.
- Stage 4 may adapt only `BURL-M003` within its existing paths. It must retain
  the explicit `BURL-O001` stop and Stage 3 route.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Bubblewrap `0.11.2` implementation](https://github.com/containers/bubblewrap/blob/v0.11.2/bubblewrap.c)
- [Sway `1.12` command and environment contract](https://github.com/swaywm/sway/blob/1.12/sway/sway.1.scd)
- [Sway `1.12` configuration contract](https://github.com/swaywm/sway/blob/1.12/sway/sway.5.scd)
- [Sway `1.12` fixed Wayland socket selection](https://github.com/swaywm/sway/blob/1.12/sway/server.c)
- [Sway `1.12` IPC client](https://github.com/swaywm/sway/blob/1.12/swaymsg/swaymsg.1.scd)
- [wlroots `0.20.1` environment variables](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.1/docs/env_vars.md)
- [Wayland `1.25.0` display connection semantics](https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Linux `/proc/PID/mountinfo` format](https://www.kernel.org/doc/html/latest/filesystems/proc.html#proc-pid-mountinfo-information-about-mounts)
