---
id: ADR-0020
status: accepted
date: 2026-09-07
certainty: assumed
assumption: "The exact read-only closure view and sparse BURL-O001 store preserve Linux isolation on the standard ubuntu-24.04 runner. Local prototypes exercised the mechanism, but no managed runner has exercised it or the complete packaging flow."
---
# ADR-020: Linux candidate closure view

**Status:** Accepted as an assumed implementation contract
**Implementation owners:** `BURL-M003` and `BURL-O001`

## Context

PR #15 commit `9719259f1ecee819af96c98c2be210156f198343`
copies the Linux candidate closure into a private Nix store. A local
measurement put its prebuild allocation at 15,382,421,504 bytes. This value
exceeds the 14,000,000,000-byte standard `ubuntu-24.04` profile.

OD-11 doesn't decide this storage mechanism. It settles candidate and seal
authority, including Linux process containment. This ADR preserves that ruling
and decides only how the Linux launcher exposes locked tools and private build
state.

The replacement has local prototype evidence only. The prototype didn't run
the complete AppImage, Flake, distribution, or macOS archive sequence for
`BURL-O001`. Its 9,910,620,160-byte result describes the state before package
builds. It doesn't prove that the remaining 4,089,379,840 bytes contain the
packaging peak.

## Decision

1. Keep the standard `ubuntu-24.04` runner as an assumed research-runner
   choice. Don't claim that the complete packaging flow fits until managed
   `BURL-O001` evidence records its peak.
2. Expose each locked closure member at its canonical `/nix/store` path through
   an exact read-only Bubblewrap `0.11.2` bind. Don't expose the host store
   root, host Nix state, daemon socket, or an unlisted store path.
3. Give profiles without Nix command authority no Nix database. Give only
   `BURL-O001` a sparse private database and writable private output store.
4. Apply the raw contract's prebuild allocation ceiling and free-space floor
   before any package build. Recheck and record capacity immediately before
   and after every named Linux `BURL-O001` build phase.
5. Reject a phase before it writes output when its precheck is missing, stale,
   malformed, above the allocation ceiling, or below the free-space floor.
   Stop the Spike and report insufficient capacity if any phase crosses the
   bound or fails because storage is exhausted.
6. Treat all prototype numbers in this ADR as local observations. They don't
   settle hosted-runner behavior or artifact feasibility.

## Named packaging phases

The capacity wrapper must identify these exact Linux phase IDs from the raw
contract:

- `linux-flake-check`
- `linux-build`
- `linux-flake-install`
- `linux-appimage-installed-probe`
- `linux-flake-installed-probe`
- `ubuntu-22.04-x86_64`
- `ubuntu-24.04-x86_64`
- `ubuntu-26.04-x86_64`
- `debian-12-x86_64`
- `debian-13-x86_64`

Each phase record contains the phase ID, event, sequence, filesystem identity,
allocated bytes, available bytes, threshold values, timestamp, and output-root
allocation. The wrapper appends the records to
`artifacts/linux-capacity.ndjson`. It includes that file as a named role
artifact. Aggregation converts the ordered records into Spike-result
measurements.

The wrapper writes the precheck before it invokes the phase command. It writes
the postcheck after the command returns and before another phase starts.

## Prototype reproduction

Run the prototype in a disposable checkout at commit
`9719259f1ecee819af96c98c2be210156f198343`. Enter its pinned development shell.
Use Bubblewrap `0.11.2`. For the sparse-store pass, use Nix `2.35.2` from the
pinned `cachix/install-nix-action` source.

The closure derivation must match the trusted launcher's routine at that
commit:

1. Resolve these launcher tools with `command -v` and `readlink -f`:
   `bash`, `sh`, `mkdir`, `mktemp`, `chmod`, `install`, `cp`, `mv`, `rm`,
   `cmp`, `awk`, `sed`, `grep`, `rg`, `sort`, `sha256sum`, `wc`, `find`,
   `tar`, `zstd`, `flock`, `getconf`, `df`, `ps`, `sleep`, `setsid`, `perl`,
   `readlink`, `uname`, `tr`, and `head`.
2. For M003, add `env`, `flutter`, `dart`,
   `flutter_rust_bridge_codegen`, `cargo`, `cargo-expand`, `rustc`, `rustup`,
   `cmake`, `ninja`, `pkg-config`, `clang`, `openssl`, `bwrap`, and `ip`.
   Resolve `cargo-expand` from `BURLMD_CARGO_EXPAND`.
3. For O001, add `env`, `cargo`, `flutter`, `dart`, `cmake`, `ninja`,
   `pkg-config`, `clang`, `openssl`, `nix`, and `nix-store`.
4. Reduce each resolved tool to its top-level `/nix/store` path.
5. Add the OpenSSL package-config, include, and library roots. For M003, also
   add the Mesa DRI and EGL vendor roots.
6. Run `nix-store -qR` for every root, sort with `LC_ALL=C sort -u`, and save
   the LF-terminated result as `locked-nix-closure.manifest`.

Run these measurements against that manifest:

```bash
wc -l locked-nix-closure.manifest
wc -c locked-nix-closure.manifest
getconf ARG_MAX
nix path-info --json $(<locked-nix-closure.manifest) |
  jq -er '[.[] | .narSize] | add'
du --block-size=1 --summarize --files0-from=<(tr '\n' '\0' <locked-nix-closure.manifest)
```

Construct the Bubblewrap argument array with one
`--ro-bind STORE_PATH STORE_PATH` triple for each manifest entry. Include the
complete `env -i` environment and candidate command. Measure the NUL-inclusive
bytes with this command:

```bash
printf '%s\0' "${BWRAP_BIND_ARGV[@]}" | wc -c
{
  printf '%s\0' "${CANDIDATE_ENV[@]}"
  printf '%s\0' "${BWRAP_ARGV[@]}"
  printf '%s\0' "${CANDIDATE_COMMAND[@]}"
} | wc -c
```

`BWRAP_BIND_ARGV` contains only the per-member bind triples.
`CANDIDATE_ENV`, `BWRAP_ARGV`, and `CANDIDATE_COMMAND` contain the complete
arrays that the launcher passes to `exec`. Compare the second byte count with
half of `getconf ARG_MAX`. Run the same complete count for the database-subset
export command.

Create a fresh private state directory and private `/nix/store` mount tree for
the O001 pass. Export and load exactly the manifest subset with these commands
inside the matching private-root view:

```bash
nix-store --dump-db $(<locked-nix-closure.manifest) >closure-db.dump
nix-store --load-db <closure-db.dump
nix-store -qR $(<locked-nix-closure.manifest) | LC_ALL=C sort -u
```

Run one offline derivation whose output enters only the private store. Compare
the host manifest members before and after by SHA-256. Measure the private
state, output mount tree, and complete prebuild inventory with one GNU `du`
invocation per nonoverlapping root:

```bash
du --block-size=1 --summarize \
  "$PRIVATE_STATE" "$PRIVATE_STORE" "$PROBE_OUTPUTS"
du --block-size=1 --summarize --files0-from="$PREBUILD_ROOTS_NUL"
```

`PRIVATE_STATE`, `PRIVATE_STORE`, and `PROBE_OUTPUTS` name the three owned
prototype roots. `PREBUILD_ROOTS_NUL` names a NUL-delimited inventory file.
That file must contain canonical, nonoverlapping roots for the host closure
union and one workspace root that contains both checkouts and dependency
caches. Separate entries cover private state, the private output store, and
candidate-owned roots outside the workspace. Reject duplicate, nested,
missing, or cross-filesystem roots before adding their allocated-byte values.

The local M003 output was 556 manifest paths, 34,824 manifest bytes, 75,208
bind-argument bytes, `ARG_MAX=2097152`, 5,433,337,672 Nix Archive bytes, and
5,627,330,560 allocated host bytes. It found zero top-level symbolic links.
The retained 75,208-byte value covers the bind triples, not the complete
argument and environment total. Reproduction must record both counts and apply
the half-`ARG_MAX` gate to the complete count.

The Nix `2.35.2` O001 pass produced 492 paths and a 213,079-byte database
subset. Private state used 8,785,920 allocated bytes. Private store mount points
and probe outputs used 2,076,672 allocated bytes. The complete prebuild
inventory used 9,910,620,160 bytes.

The prototype also hid an ambient canary, rejected writes, ran representative
loaders and tools, and blocked nested user namespaces. The sparse store queried
the closure and built one offline derivation without changing a host member.
These observations remain assumed until managed fixtures exercise them.

## Consequences

- Linux candidates avoid a second physical copy of the locked closure.
- `BURL-O001` can create Nix outputs without host store write authority.
- The standard runner remains a bounded research choice, not a packaging
  feasibility claim.
- A managed packaging run can stop for capacity. That result answers the Spike
  honestly and requires a later Stage 3 runner or packaging decision.
- BURL-M003 and BURL-O001 fixtures settle this ADR only after they exercise the
  complete closure, sparse-store, and per-phase capacity contract.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Nix `2.35.2` local store](https://nix.dev/manual/nix/2.35/store/types/local-store.html)
- [Nix `2.35.2` database subset export](https://nix.dev/manual/nix/2.35/command-ref/nix-store/dump-db.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
