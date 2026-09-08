# Provisional Forward Contract

## Purpose

This document prevents the research wave from becoming an accidental implementation wave. Structured PRD v2.0.5 and Architecture v2.1.2 are binding. The delivered v1.6.x physical contracts remain valid only for already-delivered behavior. Where they conflict with the forward constitution, the forward requirement is authoritative.

## Decision gates

| Forward area | Current physical status | Evidence or decision gate | Final Stage 3 output |
| :--- | :--- | :--- | :--- |
| Desktop preferences and Workspace sessions | Versioned JSON schemas specified for Epic G exceptions | No research Spike; implementation verifies Platform storage APIs and migration behavior | Device-preference schema, per-Workspace session schema, restore and serial-close FFI |
| Canonical Note and Workspace trees | Reduced `AstNode` projection | SPK-BURL-H001 | Canonical document schema, render projection, editing and indexing adapters, revised ADR-007 and FFI |
| Cross-platform paths and conformance repair | Title-verbatim host paths; invalid Notes currently indexed | SPK-BURL-H002 | Path grammar, migration/repair plan, preflight/live-monitor contracts, revised OKF contract and schema |
| Live Workspace monitoring | Manual Rescan only | Final verification of `notify` 8.2.0 and fallback behavior | Observer event contract, debouncing, revision checks, external-change decisions |
| Local history, undo, find, backlinks | Some planned FFI, incomplete production wiring | Canonical AST and path contracts first | Reconciled state and FFI contracts using authoritative Note sessions |
| Atomic Export | Brownfield contract permits partial output | AST, path, and asset closure contracts first | Copy and `.okf` schemas, stable-revision lease, collision and atomic publication contracts |
| Local assets and Object Store | No physical contract | SPK-BURL-I001 plus measured PRD/Architecture review | `BND-06` Local Asset Store model, `BND-11` transfer and verification contract, `BND-21` Object Store configuration and operation contract, identity and key format, hydration, and retention state machine; `BND-14` Provider and `BND-20` Remote don't own Object bytes |
| Private GitHub connection | Superseded OAuth redirect and marker-based merge | ADR-017 plus SPK-BURL-L001 | `BND-14` Provider device authorization, repository selection and provisioning, and eligible `BND-20` Remote location; `BND-20` authenticated history and ref contract; typed `BND-10` analysis and decision schemas; credential adapter; no Object transfer or storage responsibility |
| Releases and updates | Development builds plus committed Epic G headless capture | SPK-BURL-O001 for package choices; BURL-M003 for managed validation bootstrap | Credential-free candidate bundles with noncryptographic runtime guards, fresh-seal provenance, a seal-owned authenticated BURL-O001 compatibility stage, an attested canonical producer-lineage transport that binds producer-receipt freshness, accepted or rejected chain-verifying aggregation, update metadata, and the installed-app release matrix |
| Platform chrome | PR #11 presentation prototype leaked into production | Settled product decision | Remove preference/state/rendering/copy/tests and regenerate visual evidence; no replacement window-frame abstraction |

The release control surface treats the following scripts as immutable trust-anchor controls:

- `scripts/write-receipt-digest-observation.sh`
- `scripts/prepare-compatibility-stage.sh`
- `scripts/record-compatibility-stage-rest.sh`
- `scripts/write-compatibility-stage-lineage.sh`
- `scripts/prepare-compatibility-stage-consumer.sh`
- `scripts/validate-compatibility-stage-interface.sh`

Each reusable role workflow exposes its receipt upload artifact ID and bare digest through exact workflow outputs. The caller's fresh `receipt_digests` job maps all six values into one identity-bound transport without downloading candidate bytes.

Local collection resolves the transport's immutable artifact ID from the exact run inventory. It downloads the raw archive by ID and compares its SHA-256 with the canonical REST digest before extraction. The aggregate retains this check in `receiptDigestTransportArtifact`. Collection then validates the transport and checks each receipt ID and name against REST. It requires each receipt's REST digest to equal `sha256:` plus the transported action digest. The aggregate retains both receipt digest forms in `origin.sealingReceiptArtifact`. The sealing receipt remains version `2` and contains only pre-upload facts. Transport verification detects corruption or substitution but doesn't provide provenance independent of GitHub's artifact service.

Static workflow-shape fixtures use duplicate-aware source parsing to pin the exact ordered 26 producer-output keys, consumer string-input keys, and observable trusted mappings. They also pin every canonical hyphenated consumer input through its uppercase environment variable into the validator's ordered 26-field inventory. Before caller mapping, the macOS 26 output boundary normalizes the three producer sealing aliases for every ticket other than `BURL-O001`. It doesn't rely on omitted reusable-workflow input defaults.

Before acquisition or consumer processing, the macOS 15 trusted workflow wrapper invokes `scripts/validate-compatibility-stage-interface.sh`. Accepted nonempty `BURL-O001` values proceed to all three artifact downloads, offline verification, and `scripts/prepare-compatibility-stage-consumer.sh`. Accepted all-empty values for every other ticket skip only those compatibility steps, then continue the ordinary candidate path. The runtime shell can't validate source key shape or arbitrary value provenance. `scripts/prepare-compatibility-stage-consumer.sh` validates the result files. Downstream checks validate the values it consumes. The script then removes credentials and exposes only verified read-only members to the macOS 15 candidate.

In-workflow validators require literal `GITHUB_RUN_ATTEMPT=1` before relevant work. Local collection requires literal `--attempt 1` and REST `.run_attempt == 1` before acquisition. It re-fetches that exact REST object and requires numeric `.run_attempt == 1` immediately before atomically publishing an accepted report. Local collection does not inspect `GITHUB_RUN_ATTEMPT`. The launcher uses PR #15's `od -An -N16 -tx1 /dev/urandom | tr -d ' \n'` mechanism to generate each 128-bit nonce. It fails closed without a fallback unless the result is exactly 32 lowercase hexadecimal characters. A failed, cancelled, timed-out, or rejected report requires a fresh `workflow_dispatch` run with a new nonce and workflow run ID. GitHub UI and API reruns are forbidden. A recording fake API fixture proves that every path in the complete `trusted_control_paths` inventory makes no artifact-deletion request. Static fixtures require the exact 11-artifact ordinary and 13-artifact BURL-O001 inventories and `overwrite: false` on every upload. A byte or mode change in any helper requires reviewed trust-anchor rotation and evidence-only completion.

ADR-020 and raw contract version `37` define two exact read-only Bubblewrap views for `BURL-M003`. Five base sessions receive the 488-member base closure. Only the two integration sessions receive the 547-member integration closure, which adds exact unwrapped Sway and `swaymsg` requisites. Bubblewrap remains the sole parent-launched process and never enters either view.

Each session commits to its complete effective Bubblewrap argv. The canonical encoding writes the exact UTF-8 bytes of `argv[0]` and every following argument, with one NUL after each value. It covers every namespace, capability, environment, directory, symlink, bind source and destination, selected manifest member, supervisor argument, and session command. Fresh sealing reconstructs these bytes from trusted contract version `37` plus retained authority/current-path rows. Static and fresh-seal fixtures reject every addition, omission, reordering, duplication, or substitution, including extra capabilities and host-root alias binds.

Each session also creates an authority-backed contract leaf from its frozen `session-contract-root` parent. The complete argv creates `/contract` and mounts that leaf read-only after the session-root bind and before the prepared-root bind. The leaf contains only the exact mode-0444 `locked-nix-closure.sources` file that preflight reads. Fixtures reject missing, writable, substituted, linked, duplicated, incorrectly named, or extra content and any mount-order, source, destination, or retained-authority mismatch.

Only the two integration sessions append `XDG_RUNTIME_DIR`, so only those sessions receive an `xdg-runtime` authority and leaf. Each complete argv mounts the matching current leaf writable at `/candidate/xdg/runtime`; fixed directory creation doesn't create that destination. The source must have the frozen ownership, mode `0700`, empty initial contents, unchanged mount and device identity, and no symbolic link. Teardown removes its sockets, lock, and leaf before the next session. Fixtures reject an omitted or read-only bind, a wrong source or destination, a mode-0755 directory fallback, a substituted or reused leaf, and precreated socket or other content. Base sessions have no runtime leaf, mount, socket, or Wayland variable.

The updated NUL-delimited integration argv golden is 783 bytes with SHA-256 `a4e021dfad7430fda7a0143646a7f8971d9a703930b8a9279d8da5575b4e4ad4`. The capacity-authority golden has 16 rows and SHA-256 `84c452be4629b446fbba93e15c771dab5f79c499d1d620968e1736ce583def52`.

The closure view retains source-distinct staging, exact source identity, hidden Nix state, same-path member binds, the store-backed `/usr/bin/env` symlink, descriptor handshake, and capacity authority. A byte count, fixed-flag digest, set comparison, successful parse, or successful execution doesn't bind the invocation.

Two pinned-Nix reproductions produced identical closures. The base has 488 paths, 30,717 manifest bytes, SHA-256 `127043afe260d7756ee6cbda03e39a5bfceb4f7f79ae3a5be1595e447ce15e64`, 6,184,635,112 summed NAR bytes, and 66,314 bind bytes. The integration closure has 547 paths, 34,315 manifest bytes, SHA-256 `353e927fb857fe8f8fc213da4ac53e0a12147ead779e2e29289c6a3034415896`, 6,338,147,240 NAR bytes, and 74,100 bind bytes. The exact unwrapped compositor subset has 195 paths, 11,865 manifest bytes, SHA-256 `d97a41799b1aecc670e31bfd58b339d748498be2bce09d877a0f1a9ed1c6e673`, 649,324,904 NAR bytes, and 25,680 bind bytes. The Bubblewrap parent remains eight paths, 480 manifest bytes, SHA-256 `398d11c9cd9249369cbb18d36661014eafef5ac18ff7adeb076c2c51ef0141fd`, 40,679,016 NAR bytes, and 1,040 bind bytes.

The trusted parent keeps Bubblewrap in its separate eight-path tool closure. It proves the exact canonical store path, `bubblewrap 0.11.2` output, executable SHA-256, and tool-closure manifest SHA-256. It calls Bubblewrap directly with an empty process environment once per session and starts nothing else.

The binding Linux sequence retains the exact seven ordered session IDs and descriptor handshake. Every invocation uses the exact raw contract version `37` vector. The in-namespace preflight and candidate don't execute another Bubblewrap process.

Base sessions mount no compositor member or runtime leaf, expose no Wayland variable or socket, and run no compositor process. Only the two integration sessions start Sway and the candidate as untrusted siblings under the trusted in-namespace supervisor. Sway uses `env -i`, the headless backend, pixman renderer, and exact launch arguments. Its 72-byte reviewed configuration starts with `swaybg_command -`, disables Xwayland, and has SHA-256 `dfb19c5d5cd33e3e2ba7570511cee6c96222a94f1a717886bbbaa7d91dd1ab8a`. It creates `/candidate/xdg/runtime/wayland-1` inside the authority-backed leaf. The candidate receives that basename and runtime path, not a parent socket. No `swaybg` process or output is allowed.

The Bash supervisor receives the environment declared by Bubblewrap, then uses the exact Coreutils 9.11 `env -i --` executable as the final candidate environment boundary. It passes 33 resolved fixed and derived assignments in contract order. Integration sessions append four assignments for a total of 37. Direct-entry fixtures inject hostile `PWD`, `SHLVL`, `_`, and canary values and reject every leak or variant. Pinned script interpreters can create their own runtime variables after entry; fixtures record those values and don't describe them as globally absent.

The supervisor terminates and reaps Sway on success, candidate failure, early Sway failure, timeout, socket disruption, and interruption. It verifies that the PID no longer exists and that no `swaybg` process or output remains. With no hostile process alive, it writes the cleanup record. The parent validates and fsyncs the retained session frame before acknowledging namespace exit. Candidate output, Sway, `swaymsg`, and their sockets remain untrusted. Only fresh sealing is authoritative.

Each preflight begins with candidate standard streams fixed as descriptors 0 through 2. Descriptor 3 is the preflight-record write end, and descriptor 4 is the acknowledgement read end. The parent owns only the opposite ends. The wrapper closes descriptor 3 after its length-prefixed record. The parent validates the complete record and end of file before it sends ASCII `G` and closes its acknowledgement end. The wrapper requires `G` and end of file, closes descriptor 4, verifies each standard stream's recorded file type, device, inode, decoded `/proc/self/fd` target, and access mode, and requires the exact descriptor set 0 through 2. It then replaces itself with the candidate. No handshake descriptor survives candidate exec.

Before the first candidate session, the launcher freezes every BURL-M003 capacity authority. The set covers all dynamic argv sources and writable paths, including exactly two per-integration-session runtime leaves. No step can add a parent, mount, device, slot, leaf, writable path, or argv source outside that authority. The existing per-device 4,000,000,000-byte start guard remains a start guard, not a packaging claim.

The Linux role retains one `logs/burl-m003-linux-closure-view.log` through unchanged `roleEvidence.internalArtifacts`. Raw contract version `37` defines its version 2 grammar and golden fixture. The log retains both manifests, complete argv digests, authorities, current paths, preflight, capacity, the Sway configuration hash, and integration cleanup. Fresh sealing reconstructs and validates the contract mount, exact candidate entry environment, and absence of `swaybg`. Accepted aggregation binds the unchanged role and sealed bundles without adding a schema field or service artifact.

## Contract-scoped production authorization

The Epic G M0 production exceptions remain in force. `BURL-M015` and `BURL-M003` may implement only the existing reproducibility and validation bootstrap. Stage 4 may adapt `BURL-M003` within its existing `devenv.nix`, `devenv.lock`, and `scripts/**` scope. It may add the exact supervisor and Sway config. It must retain the `BURL-O001` stop and later Stage 3 route. This patch doesn't authorize or solve `BURL-O001`.

Every other production ticket remains blocked until its own decision evidence lands. Product Requirements and Architecture are reviewed when that evidence changes an upstream assumption. Final Stage 3 then replaces that ticket's provisional physical contract, and Stage 4 adapts the ticket before implementation. A ticket doesn't wait for an unrelated Spike, and one completed Spike doesn't authorize neighboring production work.

Spike Tasks may read production code and fixtures but may write only within their prototype roots and report records. Final Stage 3 still owns the reconciled FFI, schemas, bill of materials, repository layout, error taxonomy, and exact implementation commands for each affected contract.

## Known brownfield contradictions

- `ffi_api.rs` describes `AstNode` as a render projection, while the forward model requires a canonical extended AST.
- The OAuth redirect and PKCE surfaces require a client-secret-era design superseded by GitHub App device flow.
- The OKF bundle derives filenames verbatim from titles, which OD-05 explicitly reopens.
- The schema and open-Workspace comments tolerate and index invalid Notes, while the authority model now excludes them until Repair or Exclude.
- `export_workspace` describes partial, non-gating output; forward Export must be object-complete and atomic.
- Git Suggestions assume marker-bearing content conflicts and don't cover Lifecycle or Asset Decisions.
- No physical model exists for Workspace observation, S3-compatible object configuration, asset reachability, or release metadata.
- PR #15 at `9719259f1ecee819af96c98c2be210156f198343` copies the Linux candidate closure into a private store. Its measured prebuild allocation exceeds the standard runner profile. `BURL-M003` must use ADR-020 and raw contract version `37`. `BURL-O001` remains blocked on a later Stage 3 packaging-isolation and capacity decision.

These are tracked inputs to final reconciliation, not defects for a research Task to patch piecemeal.
