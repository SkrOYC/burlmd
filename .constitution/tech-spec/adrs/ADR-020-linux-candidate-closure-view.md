---
id: ADR-0020
status: accepted
date: 2026-09-07
certainty: assumed
assumption: "The exact read-only closure view, sparse BURL-O001 store, and protected capacity transcript preserve Linux isolation on the standard ubuntu-24.04 runner. Local prototypes exercised part of the mechanism, but no managed runner has exercised the complete packaging and finalization flow."
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
and decides only how the Linux launcher exposes locked tools, private build
state, and capacity evidence.

The replacement has local prototype evidence only. The prototype didn't run
the complete AppImage, Flake, distribution, output-copy, bundle, or upload-input
finalization sequence. Its 9,910,620,160-byte result describes initial state,
not the packaging peak. The separate macOS archive gates remain responsible
for macOS packaging completeness.

## Decision

1. Keep the standard `ubuntu-24.04` runner as an assumed research-runner
   choice. Don't claim that the complete packaging flow fits until managed
   `BURL-O001` evidence records every required capacity observation.
2. Expose each locked closure member at its canonical `/nix/store` path through
   an exact read-only Bubblewrap `0.11.2` bind. Don't expose the host store
   root, host Nix state, daemon socket, or an unlisted store path.
3. Give profiles without Nix command authority no Nix database. Give only
   `BURL-O001` a fresh private database and writable private output store.
4. Apply the 10,000,000,000-byte allocation ceiling and 4,000,000,000-byte
   available-space floor once, at initial admission. They prove that the run
   starts within the assumed runner profile. They don't reserve all remaining
   space from the build.
5. Apply a separate 1,000,000,000-byte available-space safety floor before and
   after every disk-allocating phase. This floor leaves about 3.09 GB of the
   local prototype's initial free space available to the flow. The value is an
   assumed fail-closed reserve until hosted peak evidence exists.
6. Keep the capacity transcript outside every candidate mount. Authenticate it
   only after the fresh seal validates it and includes it in the attested
   sealed Linux artifact. Aggregation must ignore candidate-authored capacity
   bytes and unsealed diagnostics.
7. Fail the candidate job before upload when admission, a phase check, schema
   validation, wrapper-state comparison, or storage operation fails. The seal
   job then remains skipped, and no accepted aggregate or schema-valid Spike
   result exists. A later attempt requires a fresh dispatch.
8. Treat all prototype numbers in this ADR as local observations. They don't
   settle hosted-runner behavior or either platform's packaging feasibility.

## Capacity phases

The capacity wrapper uses this exact ordered phase list:

1. `linux-flake-check`
2. `linux-build`
3. `linux-flake-install`
4. `linux-appimage-installed-probe`
5. `linux-flake-installed-probe`
6. `ubuntu-22.04-x86_64`
7. `ubuntu-24.04-x86_64`
8. `ubuntu-26.04-x86_64`
9. `debian-12-x86_64`
10. `debian-13-x86_64`
11. `linux-copy-candidate-outputs`
12. `linux-write-role-manifest`
13. `linux-compress-role-bundle`
14. `linux-finalize-upload-inputs`

The wrapper writes one initial admission record. It then writes an immediately
preceding `precheck` and an immediately following `postcheck` for each phase.
An accepted transcript therefore contains exactly 29 records.

The final four phases run after the Bubblewrap teardown lock proves that every
candidate process has exited. They copy allowlisted candidate output into a
wrapper-owned staging root, write the role manifest, compress
`ci-role-evidence.tar.zst`, and finalize the exact upload inputs. No later local
step may copy, compress, extract, or otherwise allocate disk before upload.

Each phase directs disk-backed temporary output into a measured phase root and
retains it until the postcheck. Ephemeral scratch uses the existing tmpfs.
The wrapper rejects an allocator that can delete or truncate disk-backed
temporary bytes before the postcheck. This retention rule makes each boundary
postcheck include that phase's peak disk allocation.

The pinned `actions/upload-artifact` commit
`043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` is v7.0.1. Its locked
`@actions/artifact` 6.2.0 dependency pipes `archiver` into a bounded in-memory
upload stream. It doesn't create a local ZIP file. The capacity window can
therefore close after `linux-finalize-upload-inputs`. Any action pin or archive
mode change must reverify this behavior. If the action can allocate a local
archive, the upload becomes another bracketed phase before the contract can
accept evidence.

## Protected evidence lifecycle

Before admission, the trusted host wrapper creates
`$RUNNER_TEMP/burlmd-capacity-linux-x86_64-$ARTIFACT_NONCE` with mode `0700`.
It opens the `linux-capacity.ndjson` newline-delimited JSON (NDJSON) file there
and reserves 1,048,576 allocated bytes with keep-size semantics before taking
the initial measurement. Failure to reserve the bytes rejects the run. The
protected root isn't under the checkout, candidate output, or sparse store, and
no Bubblewrap argument exposes it.
`ARTIFACT_NONCE` is the authenticated 32-hex run nonce.

The wrapper uses util-linux `2.42` from the pinned development shell:

```bash
fallocate --keep-size --length 1048576 \
  "$RUNNER_TEMP/burlmd-capacity-linux-x86_64-$ARTIFACT_NONCE/linux-capacity.ndjson"
```

The launcher verifies that `fallocate` and the existing `flock` command resolve
from the same locked store object before it uses either command.

The wrapper keeps the expected next phase, event, sequence, and monotonic time
in parent memory. After every append, it compares the parsed record with that
independent state before advancing. After the final postcheck, it validates
every line against `contracts/linux-capacity-record.schema.json`, applies the
cross-record invariants in this ADR, compares the transcript with the final
wrapper state, syncs the preallocated file, and closes it. These read-only
operations allocate no new transcript blocks.

The candidate upload contains exactly two Linux `BURL-O001` members:
`ci-role-evidence.tar.zst` and the protected `linux-capacity.ndjson`. The
capacity transcript isn't an `internalArtifacts` member and never enters the
candidate-writable role tree. The fresh seal validates the untrusted role
bundle, validates the transcript independently against the trust-anchor schema
and semantics, and places both exact bytes in the attested sealed artifact.
Final aggregation reads only that sealed member after artifact, digest,
attestation, seal-origin, and inner-byte verification succeed.

Candidate output that reserves `linux-capacity.ndjson`, names it in
`internalArtifacts`, or attempts a second capacity member causes rejection.
Neither a candidate bundle nor an unsealed candidate artifact is capacity
evidence.

## Capacity record

`contracts/linux-capacity-record.schema.json` version `1` defines each NDJSON
line. Its exact fields are:

- `schemaVersion`, integer constant `1`.
- `ticketId`, string constant `BURL-O001`.
- `roleId`, string constant `linux-x86_64`.
- `runIdentity`, string `managed:` followed by 32 lowercase hexadecimal
  characters.
- `phaseId`, one value from the admission and ordered phase enums.
- `event`, one of `initial`, `precheck`, or `postcheck`.
- `sequence`, an integer from `0` through `28`.
- `observedAt`, an RFC 3339 Coordinated Universal Time (UTC) timestamp with
  exactly nine fractional digits, such as
  `2026-09-07T12:34:56.123456789Z`.
- `monotonicNanoseconds`, a nonnegative integer from the wrapper's monotonic
  clock.
- `filesystem`, an object containing the nonempty `device`, absolute
  `mountPoint`, nonempty `type`, and positive integer `totalBytes` identity.
- `inventoryAllocatedBytes`, `filesystemAvailableBytes`, and
  `outputRootsAllocatedBytes`, each a nonnegative integer byte count.
- `thresholds`, the four exact integer constants defined by the schema.

Semantic validation requires these invariants:

- Sequence starts at `0`, increases by one, and has no gaps or duplicates.
- Record `0` is the sole `initial` admission record. Each ordered phase then has
  one adjacent `precheck` and `postcheck` pair.
- UTC and monotonic timestamps increase strictly. A phase starts within one
  monotonic second of its precheck, with no intervening wrapper action.
- The run identity, filesystem identity, and threshold object are byte-for-byte
  equal across all records.
- The complete UTF-8 NDJSON file is no larger than the preallocated 1,048,576
  bytes and ends with one line feed after record `28`.
- `inventoryAllocatedBytes` doesn't exceed filesystem-used bytes.
  `outputRootsAllocatedBytes` doesn't exceed `inventoryAllocatedBytes`.
- Admission has at most 10,000,000,000 allocated inventory bytes and at least
  4,000,000,000 available filesystem bytes.
- Every phase precheck and postcheck has at least 1,000,000,000 available
  filesystem bytes. The wrapper stops before a failing precheck's phase starts.
- Aggregation derives four exact `cross-cutting` measurements with unit `bytes`
  and `samples: 29`: `linux-capacity-inventory-allocated-peak-bytes`,
  `linux-capacity-filesystem-used-peak-bytes`,
  `linux-capacity-filesystem-available-minimum-bytes`, and
  `linux-capacity-output-roots-allocated-peak-bytes`. Filesystem-used peak is
  `filesystem.totalBytes` minus the minimum available-byte observation.
- Every disk allocator is bracketed, its disk-backed temporary bytes remain
  through its postcheck, the transcript blocks are preallocated, and the pinned
  upload streams in memory. These properties make both recorded peaks complete
  for the Linux candidate job's disk-allocation window.

JSON Schema enforces each line's local shape. The trusted semantic validator
enforces ordering, equality, arithmetic, and wrapper-state invariants. Both the
seal and final aggregator run both validation layers against the exact sealed
bytes.

The wrapper derives `device`, `mountPoint`, `type`, `totalBytes`, and
`filesystemAvailableBytes` from one `LC_ALL=C df --block-size=1
--output=source,target,fstype,size,avail ROOT` observation. Replace `ROOT` with
the canonical inventory root. It derives allocated-byte fields from one GNU
`du --block-size=1 --summarize` pass over the validated nonoverlapping root
inventory.

## Nix closure and database contexts

The host wrapper resolves and realizes the complete manifest while network is
available. For `BURL-O001`, this inventory includes every locked Flake input,
the selected package derivation, every transitive derivation and requisite,
and every launcher root. The wrapper runs `nix flake archive
--no-write-lock-file` against the locked Flake, verifies that `flake.lock`
doesn't change, realizes every input derivation of the selected target, and
recomputes `nix-store -qR --include-outputs` for those inputs before network
removal. It rejects an invalid or absent requisite, a target output in the
manifest, and any reference outside the final manifest.

The host uses these commands before network removal. Replace `SOURCE_ROOT` with
the tested checkout and `PACKAGE_ATTR` with the contract-selected Flake package:

```bash
nix flake archive --json --no-write-lock-file \
  "path:$SOURCE_ROOT" >flake-inputs.json
TARGET_DRV=$(nix path-info --derivation \
  "path:$SOURCE_ROOT#$PACKAGE_ATTR")
nix-store -qR "$TARGET_DRV" >flake-source-derivations.manifest
mapfile -t INPUT_DRVS < <(
  awk -v target="$TARGET_DRV" \
    '/[.]drv$/ && $0 != target' flake-source-derivations.manifest
)
((${#INPUT_DRVS[@]} == 0)) || nix-store --realise "${INPUT_DRVS[@]}"
{
  cat flake-source-derivations.manifest
  ((${#INPUT_DRVS[@]} == 0)) || \
    nix-store -qR --include-outputs "${INPUT_DRVS[@]}"
} | LC_ALL=C sort -u >flake-build-requisites.manifest
```

The wrapper adds every store path in `flake-inputs.json`, `TARGET_DRV`, and
`flake-build-requisites.manifest` to the launcher-root closure. It rejects a
changed lock file, an unrealized input, an invalid store path, a target output
in the manifest, or a reference outside the final manifest. It repeats the
selected target evaluation with `--offline` before namespace entry.

The trusted host exports only that final manifest subset before namespace
entry:

```bash
mapfile -t MANIFEST_PATHS <locked-nix-closure.manifest
nix-store --dump-db "${MANIFEST_PATHS[@]}" \
  >"$PROTECTED_CONTRACT_ROOT/closure-db.dump.tmp"
mv -- "$PROTECTED_CONTRACT_ROOT/closure-db.dump.tmp" \
  "$PROTECTED_CONTRACT_ROOT/closure-db.dump"
```

This command uses the host database selected by the pinned Nix installation.
`PROTECTED_CONTRACT_ROOT` names the wrapper-owned root that Bubblewrap mounts
read-only at `/contract`.
The wrapper verifies and mounts `closure-db.dump` read-only under `/contract`.
It then starts the fresh private namespace with the owned empty state root at
`/nix/var/nix` and the owned sparse output root at `/nix/store`.

Inside that namespace, the root, no-user-namespace context loads and verifies
the subset against the selected private database:

```bash
mapfile -t MANIFEST_PATHS </contract/locked-nix-closure.manifest
env -i PATH=/candidate/tool-path NIX_REMOTE=local NIX_PATH= \
  NIX_CONFIG="$PRIVATE_NIX_CONFIG" \
  nix-store --load-db </contract/closure-db.dump
env -i PATH=/candidate/tool-path NIX_REMOTE=local NIX_PATH= \
  NIX_CONFIG="$PRIVATE_NIX_CONFIG" \
  nix-store -qR "${MANIFEST_PATHS[@]}" | LC_ALL=C sort -u
```

`PRIVATE_NIX_CONFIG` retains `sandbox = false` and an empty
`build-users-group =`. Nix otherwise attempts another sandbox or build-user
transition that this root, no-user-namespace context doesn't provide. The
configuration also keeps substituters and the Flake registry empty. The
namespace has no network or daemon socket.

## Prototype reproduction

Run the prototype in a disposable checkout at commit
`9719259f1ecee819af96c98c2be210156f198343`. Enter its pinned development shell.
Use Bubblewrap `0.11.2` and Nix `2.35.2`.

The closure-root derivation must match the launcher at that commit:

1. Resolve the exact `required_tools` array: `bash`, `sh`, `mkdir`, `mktemp`,
   `chmod`, `install`, `cp`, `mv`, `rm`, `awk`, `sed`, `grep`, `rg`, `sort`,
   `sha256sum`, `wc`, `find`, `tar`, `zstd`, `flock`, `getconf`, `df`, `ps`,
   `sleep`, `setsid`, `perl`, `readlink`, `uname`, `tr`, and `head`.
2. Resolve the launcher's runtime-link array: `bash`, `sh`, `env`, `mkdir`,
   `rm`, `cp`, `mv`, `ln`, `find`, `grep`, `sed`, `awk`, `sort`, `head`,
   `tail`, `dirname`, `basename`, `readlink`, `sleep`, `perl`, `tr`, `cat`, and
   `ls`. Verify that each resolved top-level store root is already present or
   add it before closure expansion.
3. For M003, add `env`, `flutter`, `dart`,
   `flutter_rust_bridge_codegen`, `cargo`, `cargo-expand`, `rustc`, `rustup`,
   `cmake`, `ninja`, `pkg-config`, `clang`, `openssl`, `jq`, `bwrap`, `sway`,
   `swaymsg`, and `ip`. Resolve `cargo-expand` from `BURLMD_CARGO_EXPAND`.
4. For O001, add `env`, `cargo`, `flutter`, `dart`, `cmake`, `ninja`,
   `pkg-config`, `clang`, `openssl`, `nix`, and `nix-store`.
5. Reduce each resolved tool to its top-level `/nix/store` path. Add the OpenSSL
   package-config, include, and library roots. For M003, also add the Mesa DRI
   and EGL vendor roots.
6. Run `nix-store -qR` for every root, sort with `LC_ALL=C sort -u`, and save
   the LF-terminated result as `locked-nix-closure.manifest`.

The commit's closure-root array doesn't contain `cmp`; don't add it to the
reproduction. Version `37` implementation adds only wrapper tools that the new
capacity and sparse-store contract requires, and Stage 4 must record those
additions separately from the commit reproduction.

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
`--ro-bind STORE_PATH STORE_PATH` triple for each manifest entry. Measure both
the bind-only count and the complete argument and environment count:

```bash
printf '%s\0' "${BWRAP_BIND_ARGV[@]}" | wc -c
{
  printf '%s\0' "${CANDIDATE_ENV[@]}"
  printf '%s\0' "${BWRAP_ARGV[@]}"
  printf '%s\0' "${CANDIDATE_COMMAND[@]}"
} | wc -c
```

`BWRAP_BIND_ARGV` contains only the per-member bind triples. The second count
contains the complete `env -i` environment, Bubblewrap arguments, closure
binds, and candidate command passed to `exec`. Apply the half-`ARG_MAX` gate
only to the complete count. Run the same complete count for the host database
subset-export command.

Measure the private state, private output store, and complete initial inventory
with one GNU `du` invocation per nonoverlapping root. The inventory contains
the host closure union, one workspace root for both checkouts and dependency
caches, private state, the private output store, and candidate-owned roots
outside the workspace. Reject duplicate, nested, missing, or cross-filesystem
roots before adding their allocated-byte values.

The local M003 output was 556 manifest paths, 34,824 manifest bytes, 75,208
bind-argument bytes, `ARG_MAX=2097152`, 5,433,337,672 Nix Archive bytes, and
5,627,330,560 allocated host bytes. It found zero top-level symbolic links.
The retained 75,208-byte value covers only bind triples. The prototype didn't
retain the complete argument and environment count, so reproduction must
record it before the half-`ARG_MAX` claim can settle.

The Nix `2.35.2` O001 pass produced 492 paths and a 213,079-byte database
subset. Private state used 8,785,920 allocated bytes. Private store mount points
and probe outputs used 2,076,672 allocated bytes. The complete initial
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
- An insufficient-capacity run produces no accepted evidence under the
  successful-only protocol. BURL-O001 feasibility remains assumed until a
  complete hosted run succeeds.
- BURL-M003 and BURL-O001 fixtures settle this ADR only after they exercise the
  complete closure, sparse-store, protected-evidence, and capacity contracts.

## Verification anchors

- [Bubblewrap `0.11.2` command contract](https://github.com/containers/bubblewrap/blob/v0.11.2/bwrap.xml)
- [Nix `2.35.2` database subset export](https://nix.dev/manual/nix/2.35/command-ref/nix-store/dump-db.html)
- [Nix `2.35.2` database subset load](https://nix.dev/manual/nix/2.35/command-ref/nix-store/load-db.html)
- [Nix `2.35.2` local store](https://nix.dev/manual/nix/2.35/store/types/local-store.html)
- [Nix `2.35.2` Flake archive command](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-flake-archive.html)
- [Nix `2.35.2` requisite query](https://nix.dev/manual/nix/2.35/command-ref/nix-store/query.html)
- [Pinned Nix installer script](https://github.com/cachix/install-nix-action/blob/13d8dd58da0234aa297dedd986986ccb8e7f3e24/install-nix.sh)
- [Pinned upload action entrypoint](https://github.com/actions/upload-artifact/blob/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/src/shared/upload-artifact.ts)
- [Pinned upload action bundle with the `@actions/artifact` 6.2.0 ZIP stream](https://github.com/actions/upload-artifact/blob/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/dist/upload/index.js)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
