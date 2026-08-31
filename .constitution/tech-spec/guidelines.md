# Project Structure & Guidelines

## Provisional research boundary

TechSpec v1.8.0-provisional permits research code only under `.constitution/prototypes/`. The existing Epic G M0 production exceptions remain unchanged. `FLAKE-M002` and `CI-M003` may write production code only for their reproducibility and validation bootstrap. Every other production ticket remains blocked by its own decision evidence and a matching Stage 3 and Stage 4 adaptation. Except for these contract-scoped exceptions, production directories (`lib/`, `rust/`, `linux/`, and `macos/`) are read-only inputs to this research wave.

The five exact prototype roots and verification commands are machine-readable in `contracts/provisional-spikes.toml`. Its allowlist is exhaustive: each Spike may write only its named prototype root and report path. Every unlisted repository path is read-only. Framework bookkeeping may update the owning active Task after the Spike process exits, but that isn't part of the Spike's write authority.

Each harness writes one `results.json` that validates against `contracts/spike-result.schema.json`, records each platform run and exact tool and dependency versions, names its corpus, reports every required measurement, and makes one evidence-backed recommendation. Every gate and measurement names the candidate it evaluates or the reserved `cross-cutting` value. The harness must also read its own TOML entry and fail unless its result contains exactly the declared candidate names and required gate names, every candidate has attributed outcomes, run IDs are unique, and every required run role is present; JSON Schema alone can't enforce those cross-file constraints. The mandatory result validator semantically parses every timestamp as RFC 3339 and rejects impossible calendar dates rather than trusting the schema's shape pattern. It also resolves each recorded 40- or 64-hex Git revision in the captured checkout and requires it to equal that run's captured revision.

Command execution records exit status and separate standard-output and standard-error artifacts. Before aggregation, the harness verifies that every referenced evidence and artifact path is inside the Spike's write allowlist, exists, matches its byte count and SHA-256 digest, and isn't replaced by a later command. Raw fixtures and measurements stay beside the result. A conclusion without reproducible evidence does not settle an open decision.

Research Tasks stop on a failed safety or fidelity gate. A performance miss is evidence, not permission to weaken the PRD: the result records it and final Product Requirements or Technical Implementation evolution decides the response. A production ticket starts only after its own decision evidence settles its physical contract and Stage 4 adapts that ticket. Unrelated unresolved Spikes don't form a global stop.

## Generated-binding bootstrap checker

The merged base for `CI-M003` doesn't contain `scripts/check-generated-bindings.sh`. Before any validation gate invokes that path, `CI-M003` must implement the checker under its existing `scripts/**` scope. The implementation must not import or cherry-pick the coordinating Epic G branch.

The checker must perform these steps in order:

1. Capture a path-sorted SHA-256 manifest and a byte-for-byte backup of `rust/src/frb_generated.rs` and every regular file under `lib/src/rust/**`.
2. Run `flutter_rust_bridge_codegen generate` with the provisional `2.12.0` generator.
3. Capture a second path-sorted SHA-256 manifest. Compare both file sets and every file byte-for-byte. Fail if generation exits nonzero or adds, removes, or changes a generated file.
4. On success, failure, or interruption, restore both generated surfaces exactly to their precheck state. Remove generated files that weren't present before the check, restore files that generation changed or removed, and preserve preexisting modifications.
5. Before exit, verify that both generated surfaces match the precheck manifest. Exit nonzero if restoration or verification fails.

The stale-binding diagnostic names both generated surfaces and instructs the developer to regenerate and review the changes. The checker leaves the precheck working tree unchanged, including when it detects stale bindings.

## Managed validation evidence protocol

`CI-M003` implements only the bootstrap described here. Validation starts when a source commit is pushed to its source branch. A draft pull request can make the branch visible, but pull-request state and the synthetic merge revision never define validation identity. The caller produces an authoritative expected-identity document before fan-out. It distinguishes the ticket, tested source head SHA, workflow execution SHA and ref, base SHA, release, build, corpus, run, required roles, and role signers. Its SHA-256 digest is passed independently to each validation role and to aggregation.

The one repository-owned entry point is `./scripts/managed-evidence.sh`; `CI-M003` implements it as a narrow client for this protocol, not as a general workflow framework. It uses GitHub REST API version `2026-03-10` and the fixed caller `.github/workflows/ci.yml`. `GH_TOKEN` supplies authentication and must never appear in an argument, log, report, or artifact. The command has exactly two forms:

- `./scripts/managed-evidence.sh collect --ticket TICKET_ID --source-ref SOURCE_REF --run-id RUN_ID --attempt RUN_ATTEMPT --source-head-sha SOURCE_HEAD_SHA --base-sha BASE_SHA --output REPORT_JSON` verifies an existing push-triggered run. It accepts `CI-M003` or one of the five managed Spike tickets. It requires the named source ref to resolve remotely to `SOURCE_HEAD_SHA`. It also requires the run and attempt to use the `push` event, `.github/workflows/ci.yml`, that ticket, source ref, source head, and expected base. For a managed Spike, collection stages role contents, runs coordinator aggregation, and publishes the declared machine result. `CI-M003` collection writes only its aggregate report.
- `./scripts/managed-evidence.sh run --ticket TICKET_ID --source-ref SOURCE_REF --source-head-sha SOURCE_HEAD_SHA --base-sha BASE_SHA --output REPORT_JSON` is available after `CI-M003` merges. It accepts only a decision ticket declared in `contracts/provisional-spikes.toml`. The source commit must already be pushed. The command finds the one caller run whose event, workflow path, source ref, and source head match exactly, waits up to 7,200 seconds for attempt 1 to finish, and performs the same collection and verification. It rejects a missing or ambiguous run and never selects by recency or a self-reported job name.

`SOURCE_REF` is the full pushed `refs/heads/...` ref. `SOURCE_HEAD_SHA` is the tested 40-hex source commit. `BASE_SHA` is the 40-hex merge base with the tranche's base branch that the caller records independently. `REPORT_JSON` must match one of the evidence-only paths ignored by the caller. `OUTPUT_DIR` is the parent directory of `REPORT_JSON`. `RUN_ID` and `RUN_ATTEMPT` identify one exact push-triggered workflow attempt.

Before fan-out, the caller uploads `managed-evidence-expected-RUN_ID-RUN_ATTEMPT`, containing only `expected-identity.json`. Each signer uploads `managed-evidence-ROLE-RUN_ID-RUN_ATTEMPT`, containing only `ci-role-evidence.tar.zst`. Collection obtains the expected identity separately from the role artifacts. It verifies that every upload belongs to the exact repository, run, attempt, source ref, source head, workflow execution, and base before it applies the signer and bundle checks below. It writes one aggregate conforming to `contracts/ci-evidence.schema.json` at `REPORT_JSON`, replacing that file atomically. For a managed Spike, it also writes the declared `results.json`. Standard output is one JSON object with `status`, `runId`, `runAttempt`, `result`, and `report`; `result` is null for the `CI-M003` bootstrap. Diagnostics go to standard error.

Exit status `0` means the written report is `accepted` and, for a managed Spike, the declared machine result is present and valid. Exit status `1` means the written report is schema-valid but `rejected`; evidence or coordinator failure never suppresses its durable report. Exit status `2` means invalid arguments, insufficient API permission, interruption, no unique push run, timeout before authoritative identity is available, or an output failure prevented a schema-valid report. After authoritative identity is available, service, timeout, missing-bundle, verification, staging, coordinator, and result-validation failures instead produce a rejected report and exit `1`. Both forms need only Actions, attestations, and contents read access.

For a source-branch run, release identity is `candidate:` followed by the 40-hex tested source head. Build identity is the SHA-256 of an exact input manifest containing that source head, repository tree, base SHA, workflow execution SHA and ref, lockfiles, toolchain pins, action pins, and build configuration. Corpus identity is the SHA-256 of the generated corpus manifest. Run identity is the decimal workflow-run ID and run attempt joined by `:`. Required roles are exactly `linux-x86_64`, `macos-26-arm64`, and `macos-15-arm64`. The expected identity also assigns one signer to each role:

- `linux-x86_64`: `.github/workflows/ci-role-linux-x86-64.yml`
- `macos-26-arm64`: `.github/workflows/ci-role-macos-26-arm64.yml`
- `macos-15-arm64`: `.github/workflows/ci-role-macos-15-arm64.yml`

Each signer is a reusable workflow with exactly one role job and a fixed hosted label. The caller uses the static same-repository form `./.github/workflows/WORKFLOW_FILE`; expressions and ref suffixes are forbidden in `jobs.<job_id>.uses`. GitHub resolves that local reusable workflow from the caller's workflow execution commit. The expected identity records the source-branch `job_workflow_ref` and the separate `job_workflow_sha`. Aggregation requires the static role path, requires `job_workflow_sha` to equal the workflow execution SHA, and requires the tested source head to equal the workflow execution SHA for this push protocol. The expected-identity digest covers the exact generated JSON bytes; roles receive that immutable file rather than reconstructing it.

Each role first writes every result, log, raw measurement, and handoff file. It records each relative path, byte count, and SHA-256 digest in `internalArtifacts`, then writes `ci-role-evidence.json` against `contracts/ci-role-evidence.schema.json`. The role creates one deterministic `ci-role-evidence.tar.zst` bundle containing that manifest and every file named by `internalArtifacts`. It attests the exact bundle bytes and uploads an artifact containing only that unchanged bundle. The manifest doesn't contain the bundle digest, artifact ID, upload digest, attestation, or another value assigned after bundling or upload, which prevents a digest cycle.

The coordinator downloads the uploaded object and verifies the service-reported upload digest. It extracts the one expected bundle, verifies the bundle digest against the attestation subject, and safely unpacks it without path escape. The coordinator then validates the manifest and verifies every `internalArtifacts` entry against the bundled bytes before using a result. A missing, extra, duplicate, escaped, size-mismatched, or digest-mismatched member rejects the role bundle.

For a managed Spike, every `internalArtifacts.name` is relative to that Spike's prototype root. After verification, the CLI atomically replaces `OUTPUT_DIR/managed-evidence-coordinator` and stages only manifest-named bytes under `roles/ROLE_ID/`, preserving each relative name. The fixed role directories are `linux-x86_64`, `macos-26-arm64`, and `macos-15-arm64`. The CLI rejects absolute paths, traversal, links, name collisions, files outside the ticket allowlist, and any staged byte that differs from its verified manifest entry.

The CLI then runs the ticket's ordered `coordinator_steps` from `contracts/provisional-spikes.toml`. Those steps copy or import only exact paths from the authenticated role staging directories. They don't use a network transfer, a manual handoff source, an environment-selected path, or an unstaged role output. Before execution, the CLI snapshots each declared `coordinator_mutable_paths` entry. After it copies the validated machine result, it restores those paths to their exact precheck state and removes the owned coordinator root. The packaging workflow applies the same bundle verification and staging rules to the macOS 26 construction bundle before the macOS 15 role imports and probes that archive.

The signed provenance must bind the role's exact static reusable-workflow path, workflow execution SHA and ref, invocation run and attempt, and `runner_environment` claim. That claim must equal `github-hosted`; a self-hosted job is rejected even if it supplies the expected custom labels. The aggregate retains the verified `github-hosted` fact. The coordinator also uses the versioned job API to corroborate that the same run contains the signer workflow's single job with its fixed hosted label. It doesn't correlate artifact and job REST objects directly, and it doesn't trust an artifact-supplied job name or ID.

Aggregation runs either in a coordinator job or locally with authenticated read access. It compares each manifest with the independently supplied expected identity and writes `contracts/ci-evidence.schema.json`. For each of the five managed Spikes, the coordinator steps write `coordinator_result` inside the fixed coordinator root. The CLI validates that file against `contracts/spike-result.schema.json` and enforces the declared Spike ID, candidates, gates, runs, and role separation. It then atomically copies the validated bytes to `managed_results`. An accepted report requires this authoritative machine result. A missing or invalid result produces a rejected report with `aggregation-error` and exit status `1`.

An `accepted` result contains all required enriched roles, successful aggregation checks, and no rejection reasons. A `rejected` result can contain partial or no role evidence and must contain one or more typed rejection reasons. Therefore missing, mismatched, stale, corrupt, unauthenticated, or unaggregated evidence produces a durable fail-closed result instead of becoming schema-invalid.

The CLI writes `results.json` and `REPORT_JSON` atomically and reports both paths in its standard-output summary. The executor writes the human Spike report as an interpretation of the accepted `results.json`; the CLI doesn't author that report. Milestone evidence commits the authoritative `results.json`, accepted `REPORT_JSON`, and human Spike report together.

The caller and each signer grant only `contents: read`, `id-token: write`, and `attestations: write` for role production, as GitHub requires both caller and called workflows to permit the OIDC request. The coordinator grants only `contents: read`, `actions: read`, and `attestations: read`. Neither phase grants release, package, or repository-content write authority, and neither receives live product credentials.

GitHub artifact attestations for private or internal repositories require GitHub Enterprise Cloud. Repository plan eligibility isn't guaranteed by this specification. If the candidate repository can't create and verify the attestation, `CI-M003` must return a rejected aggregate with `attestation-unavailable`. It must not substitute a hash-only protocol.

Aggregation verifies each bundle and compares its captured identities with the independently supplied expected identity. It also requires the exact evidence-class sequence for each role. Linux can't claim macOS authoritative visual evidence, macOS can't claim Linux platform-regression evidence, and macOS 15 can't claim performance or either regression class. For a managed Spike, the later evidence commit contains exactly the accepted `REPORT_JSON`, authoritative `results.json`, and executor-authored human report declared by the raw contract. For `CI-M003` bootstrap, the commit contains only `REPORT_JSON`. The commit's parent is the tested source head. The caller ignores these exact evidence paths, so the evidence commit doesn't start another validation run. The workflow never pushes repository content. Milestone review starts only from accepted evidence. A draft-pull-request status alone is not evidence.

The hosted OS labels are mutable image channels. Every result records `ImageOS` and `ImageVersion`, and performance or visual aggregation refuses mixed image versions. GitHub doesn't guarantee physical host identity, CPU scheduling, storage throughput, or absence of neighboring load. Repeated samples and captured resource facts bound the claim; they don't turn a hosted label into physical-workstation proof.

The required evidence consumers are:

| Consumer | `ubuntu-24.04` | `macos-26` | `macos-15` |
| :--- | :--- | :--- | :--- |
| Common functional matrix | Required | Required | Required; compatibility only |
| AST and FFI projection measurements | Performance reference | Performance reference | Not accepted |
| Asset decode and memory measurements | Performance reference | Performance reference | Not accepted |
| Workspace-observer latency | Performance reference | Performance reference | Functional behavior only |
| Nightly PRD meters | Performance reference | Performance reference | Not accepted |
| Packaging and installed-app proof | x86-64 Linux artifact | Apple Silicon macOS 26 artifact | Same Apple Silicon artifact on macOS 15 |
| Platform and product visual regression | Required non-authoritative exact Linux platform regression | Sole authoritative product visual baseline | Not accepted |

Linux platform-regression capture extends the committed private headless Sway and Wayland implementation. It owns compositor, display, input, process, state directory, and application PID. The current committed capture is `1878x989`; `CI-M003` must reconcile it to the PRD's verified 1920x1080 at 60 Hz logical viewport before claiming `linux-platform-regression` evidence. The zero-pixel result is required implementation-regression evidence, not authoritative product visual evidence. It must not fall back to the Writer's desktop or substitute for macOS 26.

macOS 26 visual capture runs the actual Apple Silicon hosted desktop application. It produces the sole authoritative product visual baseline set and verifies the 1920x1080 logical application viewport before capture. The installed Flutter 3.44.3 source provides `FlutterDriver.screenshot`, but it doesn't guarantee the host window geometry. `CI-M003` must prove geometry on the hosted GUI or leave the visual role failed. Widget-test or Linux platform-regression output can't substitute. macOS 15 never creates or updates visual baselines.

All workflow actions use the full commit SHAs in `stack.md`. The workflow uses the repository's Nix, Rust, Cargo, and Pub locks rather than hosted preinstalled tool versions. It captures any unavoidable host utility version. The OS-major labels and image versions remain evidence inputs, not lockfile replacements.

## Commits
This repository uses [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): summary`, with types `feat`, `fix`, `docs`, `chore`, `refactor`, and
`test`; scope names the area (`docs(prd)`, `fix(editor)`). The history has followed
this shape since Epic A; it is documented here so review can hold work to it rather
than infer it.

## Monorepo Layout (Standard FRB Template)
The repository follows the default `flutter_rust_bridge` template structure to minimize custom build script overhead.

```text
/
├── .agents/                 # Agent skill definitions (Dart/Flutter workflows)
├── .constitution/           # AI Project Development Framework artifacts
├── .envrc                   # direnv entrypoint; activates the devenv shell
├── .gitignore
├── README.md                # Onboarding: how to enter the environment
├── devenv.nix               # Developer environment: toolchains, native deps, git hooks
├── devenv.yaml              # devenv inputs (nixpkgs, rust-overlay, git-hooks)
├── devenv.lock              # Pinned input revisions; the reproducibility boundary
├── rust-toolchain.toml      # Rust version pin, read by devenv and by rustup
├── linux/                   # Flutter Linux build files (in-scope target)
├── macos/                   # Flutter macOS build files (in-scope target)
├── lib/                     # Dart/Flutter UI source code
│   ├── main.dart
│   ├── src/
│   │   ├── components/      # Reusable UI blocks
│   │   ├── design/          # Presentation composition, theme, and motion
│   │   ├── providers/       # Riverpod state definitions
│   │   ├── rust/            # Auto-generated FRB Dart bindings
│   │   └── screens/         # Full-screen routes (workspace.dart, login.dart —
│   │                        #   login retained for the deferred connect flow,
│   │                        #   no longer a startup gate since SHEL-E002)
├── scripts/                 # Repository-owned validation entry points
│   ├── smoke-shot.sh        # Manual QA gate for every UI ticket (SHEL-E001)
│   ├── visual-regression.sh # Exact visual gate introduced by SHELL-G001
│   └── managed-evidence.sh  # Managed evidence client implemented by CI-M003
├── test/                    # Dart widget tests
├── rust/                    # Rust Core Engine source code
│   └── src/frb_generated.rs # Auto-generated FRB Rust bridge; changes with Dart bindings
│   ├── Cargo.toml
│   ├── tests/               # Rust integration tests
│   ├── src/
│   │   ├── api/             # FFI interface exposed to Dart (thin #[frb] wrappers)
│   │   │   ├── auth.rs      # OAuth flow, token storage, session state
│   │   │   ├── ffi_api.rs   # The contract surface
│   │   │   └── simple.rs    # FRB template init hook (outside the contract)
│   │   ├── db/              # rusqlite database management
│   │   ├── assets/          # Planned: Local Asset Store identity, manifest,
│   │   │                      hydration, verification, and retention
│   │   ├── diagnostics/     # Planned: rotating structured log and export
│   │   ├── draft.rs         # Active-draft-state domain: NoteState/NoteMetadata,
│   │   │                      the open-note cache, block_path-addressed edits
│   │   ├── error.rs         # Shared AppError, so db/security don't depend on api
│   │   ├── git/             # gix integration
│   │   ├── index/           # Bundle -> SQLite indexer: notes, notes_fts,
│   │   │                      fts_mapping, links, directories. `scan` (full
│   │   │                      walk, owns reindex_workspace), `incremental`
│   │   │                      (single-Note reindex, content_hash
│   │   │                      short-circuit), `query` (read paths: search,
│   │   │                      backlinks, tree, title prefix).
│   │   ├── markdown/        # AST parsing logic; owns the span map (ADR-007).
│   │   │                      `parser`/`ast` (parse to Block tree), `spans`
│   │   │                      (span map + its invariants), `splice`
│   │   │                      (span-preserving source edits)
│   │   ├── okf/             # OKF v0.2 bundle domain: `frontmatter` (read and
│   │   │                      validate), `concept_id` (concept-id <-> path,
│   │   │                      reserved-filename rules), `links` (target
│   │   │                      resolution and serialization)
│   │   ├── export/          # Planned: stable-revision copy/archive Export
│   │   ├── object_store/    # Planned: S3-compatible transfer and validation
│   │   ├── provider/        # Planned: private GitHub App/provider integration
│   │   ├── security/        # OS Keychain root-key integration
│   │   ├── sync/            # Debounced background sync scheduler
│   │   ├── update/          # Planned: compatible release-metadata checks
│   │   ├── workspace/       # `bootstrap` (init/open, Git repo adoption),
│   │   │                      `lifecycle` (note & directory create/rename/
│   │   │                      move/delete, atomic write), `links_rewrite`
│   │   │                      (inbound-Link source rewriting on rename),
│   │   │                      `persist` (the ADR-008 tiers and their locks)
│   │   └── test_support.rs  # #[cfg(test)]-only fixtures shared across unit test modules
├── pubspec.yaml             # Dart dependencies
├── .github/workflows/       # Planned: PR, canary, benchmark, and release gates
├── flake.nix                # Planned: release-tagged Nix package entrypoint
├── flake.lock               # Planned: release Flake reproducibility boundary
├── nix/                     # Planned: release package modules and checks
└── flutter_rust_bridge.yaml # FRB configuration
```

The directories marked **Planned** are the physical homes for the forward boundaries already accepted by Architecture v1.4.15. They remain absent until their owning implementation ticket begins. A Spike never creates them. Final Stage 3 may refine files inside a planned directory after evidence, but moving responsibility to a different boundary requires Architecture review and a Tasks adaptation.

`android/` and `ios/` are absent by design: mobile targets are deferred per
`tasks/critical-path.md`, and no mobile toolchain is provisioned. `ANDROID_HOME`
is pointed at an in-repo path that deliberately holds no SDK, so Flutter cannot silently
adopt an SDK from the contributor's home directory; see `stack.md`.

## Toolchain
All commands below assume the `devenv` shell (`devenv shell`, or automatic via
`direnv`). Toolchain versions are pinned there and in `rust-toolchain.toml`; see
`stack.md` for the compatibility policy.

## Coding Standards
1. **Rust:**
   - Must pass `cargo clippy -- -D warnings`.
   - Must be formatted with `cargo fmt`.
   - Avoid async/await unless absolutely necessary (e.g., long-running sync operations on a dedicated thread). Local index queries remain synchronous for maximum performance, except where `tech-spec/contracts/ffi_api.rs` itself declares a function `async` (e.g. `search_notes`) — the contract's FFI-boundary signature takes precedence over this preference; the function's own body should still execute synchronously to completion rather than actually yielding to an executor.
   - In the delivered v1.6.x model, source spans are Core-side state keyed by `block_path` and aren't fields of the reduced `AstNode` render projection. Forward work must instead keep source ranges inside the canonical Core document/AST state required by ADR-013; a Flutter render projection still receives only the coordinates its interaction contract needs. Final Stage 3 settles the exact range and projection types after SPK-AST-H001. No UI code may treat a byte offset into Core-owned source as independent authority.
   - No code path may rewrite bytes outside the span of an edited Block. This is the Edit Fidelity constraint in `prd/constraints.md` and it is the reason no AST-to-Markdown serializer exists for the save path; adding one for that path reintroduces exactly the failure the constraint forbids.
2. **Dart:**
   - Must pass `dart analyze`.
   - Must be formatted with `dart format`.
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB. Ephemeral selection coordinates (`block_path` plus Flutter UTF-16 rendered offset) are UI state, not note content, and are exempt — this is what allows cross-Block selection under ADR-006 without amending `architecture/containers.md`.
   - **`lib/src/design/` is presentation-only composition.** It owns shell
     composition, theme tokens/construction, and motion. It may depend on
     components, providers, and generated types, but must not define provider
     state or call Core/FRB directly; provider modules own state and Core
     access remains behind their existing seams.
   - The rendered and raw presentations of a Block must be typographically identical. Only the text differs (`**bold**` versus bold); font, size, weight, line height, and padding must not, or the Block visibly jumps when it takes focus.
   - **Every error returned across the FFI boundary must reach a user-visible surface.** No call site may swallow a Core error. This rule exists because the editor shipped through Epic B with no error path at all — failures crossed the boundary and were discarded, a gap Epic B's review recorded but could not reach until the editor was mounted (`SHEL-E004`, which landed the shell's error surface).
   - **Shell surfaces coordinate through provider seams, not widget ownership.** Note selection flows through the shared selection seam (`selectedNoteIdProvider`) so the tree, editor and lifecycle actions stay coherent without referencing each other; the Directory tree renders from the Core's single whole-tree payload (one call, children nested) and holds only expansion state as ephemeral UI state. Note switching must close the outgoing Note through the Core before opening the next, so its session reaches the commit tier (`SHEL-E004`).
   - **Close a Note.** An FFI error refuses the close and keeps the outgoing
     session writable. `CloseNoteResult.warning` means Core retired the session
     after a safe write. The UI removes the retired tab and shows a dismissible
     status. It continues only one Note-to-Note replacement when no batch,
     Workspace switch, or orderly shutdown encloses the close. A batch stops
     with every unprocessed tab preserved, and an enclosing switch or shutdown
     is canceled. The UI must not restore a writable snapshot for a retired
     session. After an incoming open fails with its ID still selected, another
     explicit selection of that Note must issue the open request again.
   - **Settle lifecycle results before warnings.** `LifecycleResult.warning`
     is not an FFI error. When it is populated, Presentation must adopt the
     returned state, apply `LifecycleEffects`, and clear each removed editor
     before it shows one localized dismissible status selected by the typed
     warning stage. It must not parse `detail` or restore the previous editor.
     An `AppError` remains a true refusal, so only that path retains the prior
     Core-valid session. A `Settlement` warning can report an advisory
     post-publication state refresh (such as Link-existence badges); its
     destination state and IDs remain authoritative and writable.
   - **Link-completion grammar is fixed.** A completion is eligible only when a collapsed caret has a last unmatched `[[` on the same line before it; its query is the intervening text. The UI snapshots that exact trigger range and source value, requests no more than 10 Core candidates, and rejects/dismisses the list if a newline, `]]`, focus/selection change, or edit invalidates the snapshot. Core supplies either an existing candidate or a distinguishable prospective ghost when the query is a valid future target. Acceptance replaces the snapshot range with the Core-supplied `LinkCompletion.insert_text`; no Dart code may construct or repair a destination. Follow always re-resolves first, then calls `create_link_target(target_id)` only for a still-missing target.
   - **A cross-Block selection uses one direct `TextInputClient` proxy, not a hidden `TextField`.** Its initial/current proxy value is `TextEditingValue.empty`; after `TextInput.attach`, it calls `setEditingState` with that value before `show`. It owns exactly one `TextInputConnection`, resets the empty platform value after a Core result, and closes before promotion or disposal. `updateEditingValue` handles only ordinary committed text/IME; an `Actions`/`Shortcuts` layer compatible with Flutter 3.44.3 `DefaultTextEditingShortcuts` explicitly handles Delete/Backspace and clipboard copy/cut/paste intents. While `TextEditingValue.composing` is valid and non-collapsed it neither mutates Core nor replaces the platform value. `RangeEditResult` is a present atomic operation, compatible with later undo but not an implementation of deferred CAP-EDIT-08 (ADR-012).
3. **Nix:**
   - Every `*.nix` file must be formatted with `nixfmt` (RFC style). Today that is only `devenv.nix`.
4. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for editor rendering (verifying AST nodes render correctly).
   - **Round-trip property tests are mandatory for the splice path.** For any Note and any Block, splicing that Block's own unmodified source back over its span must produce a byte-identical file. This is the executable form of the Edit Fidelity constraint and is cheap to state as a property over a corpus of fixture Notes, including ones with frontmatter keys the application does not manage.
   - **Every ticket touching UI must launch the real application in its Verification Command.** Not `flutter test` alone. The gap this closes is documented under "Running the real app" below: through Epic B, no ticket's gate ever started the app, and a real regression shipped that six passing widget tests could not see.

5. **Accessibility (standing standard, adopted before Epic E paints widgets):**
   - Keyboard completeness is a hard review bar: every capability reachable by pointer is reachable by keyboard, and focus order follows visual order.
   - Every user-visible widget carries Flutter `Semantics` labels as it is written — not retrofitted. Screen-reader certification is deferred scope (`prd/out-of-scope/screen-reader-certification.md`); semantic structure is not.
6. **Internationalization readiness (standing standard, same timing):**
   - User-facing strings externalize through Flutter `gen-l10n` from the first screen onward; no new hardcoded UI text lands once Epic E begins.
   - No translation effort is scheduled; this standard exists because retrofitting string extraction across painted screens is a sweep nobody enjoys.
   - The current repository has **no** `l10n.yaml`, ARB source, or generated localization output despite that standing rule. `EDIT-F006` must establish `flutter: generate: true`, `l10n.yaml`, and `lib/l10n/app_en.arb` before it adds completion, Link, or create-offer strings. It runs `flutter pub add "flutter_localizations@{sdk: flutter}" intl@0.20.2`, committing `pubspec.lock`; `intl` `0.20.2` is the direct requirement of pinned Flutter 3.44.3 `flutter_localizations`. Its pinned configuration is `arb-dir: lib/l10n`, `output-dir: lib/l10n/generated`, `output-localization-file: app_localizations.dart`, and imports `package:burlmd/l10n/generated/app_localizations.dart`. `flutter gen-l10n --help` confirms synthetic packages cannot be enabled in this SDK and default output is the ARB directory, so the explicit output directory is required. `lib/l10n/generated/**` is repository-owned generated Dart: refresh it with `flutter gen-l10n` and commit it with its ARB/config change; never hand-edit it.

## Persistence lock rules

Before restoring a current-version Workspace session snapshot, Core performs semantic validation after JSON Schema validation. `workspace_id` must equal the active Workspace identity. Every Note and Directory identity must be nonempty, unique in its array, and valid under Core's applicable identity rules. `active_note_id` must be null or one of the `open_note_ids` values. Core rejects duplicate identities and every cross-field violation.

For any malformed current-version snapshot, Core quarantines and preserves the original bytes and returns an empty writable session for the active Workspace. It never restores malformed state. The normal current-version snapshot path remains writable after quarantine, without changing the preserved bytes. Unsupported later-version snapshots keep the separate isolation behavior defined by `workspace-session-snapshot.schema.json`.

`rust/src/workspace/persist.rs` uses this acquisition order: lifecycle, tier 2 write, tier 1, state, then connection. A caller can take a suffix of this order, but it must not acquire these locks in reverse order.

- The per-Note tier 1 lock serializes a source mutation through its draft write and serializes lifecycle state installation with that mutation.
- A source mutation obtains a Workspace edit lease before open-session lookup and retains it through its draft write. Lifecycle closes admission and drains those leases before snapshotting Notes; later source mutations refuse unchanged and retry after the lifecycle call. Admission state is not a lock and must not make a keystroke wait behind filesystem or Git work.
- The FFI owns one counted lease. A direct internal session mutator borrows an existing same-thread lease rather than attempting a second admission; lifecycle must install its reopen guard immediately after closing admission, before any fallible wait.
- The state lock protects the in-memory snapshot and must not span database or filesystem I/O.
- No closure passed to `with_connection` may perform file I/O.
- No lock that a keystroke can contend for may span an `fsync`.
- Tier 2 writes must use the per-Note tier 2 write lock for the full OCC check, file write, and revision re-record sequence.

## Terminology introduced at this layer

`prd/glossary.md` owns the product vocabulary and deliberately holds no implementation terms. Four terms this specification introduces are load-bearing across the contract, the ADRs and every Epic D ticket, and are defined here because they belong to the physical layer:

| Term | Definition |
| :--- | :--- |
| Concept id | A Note's identity under OKF §2: its bundle-relative path with `.md` removed. Unique within a bundle, **not** globally, which is why ADR-005 decision 7 makes exactly one Workspace active. Stored as `notes.id`. |
| Working source | The single in-memory buffer holding an open Note's full current text — byte-identical to what `drafts.raw_markdown` persists for it. It is what `update_block` substitutes into and what the tier 2 write copies verbatim. |
| Span map | The Core-side map from `block_path` to a byte range in the working source. Never crosses the FFI boundary and never appears on the AST (ADR-007 decision 3). |
| Block path | An index path into a Note's AST, addressing one Block. **Not stable across any reparsing call** — a splice can change a Block's node shape — so callers re-derive it from the returned state rather than retaining it. |

The distinction most worth stating: the **working source** is not the draft row. They hold the same bytes, but the buffer is the live editing state and the row is its crash-durable copy, and tier 2 clears the row while the buffer persists until the Note closes. Conflating them makes "a draft row exists" mean "a Note is open", which is false in both directions.

## Editor-depth verification commands

The active editor-depth tickets quote these commands exactly. `BURLMD_SMOKE_F005`, `BURLMD_SMOKE_F006`, and `BURLMD_SMOKE_F007` are required readiness inputs: the smoke harness must reject a generic Workspace window and capture only after the named staged interaction is ready.

- `flutter test test/components/emphasis_shortcuts_test.dart && BURLMD_SMOKE_F005=1 ./scripts/smoke-shot.sh f005-emphasis && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target && cargo test --lib --manifest-path rust/Cargo.toml create_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml create_link_target && flutter_rust_bridge_codegen generate && flutter gen-l10n && flutter test test/components/link_completion_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F006=1 ./scripts/smoke-shot.sh f006-link-completion && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate && cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_editing_test.dart test/components/text_input_client_test.dart test/components/selection_test.dart && BURLMD_SMOKE_F007=1 ./scripts/smoke-shot.sh f007-range-editing && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`

## Forward implementation verification commands

Stage 4 tickets quote one of these gates and replace `<ticket-id>` with their lowercase ticket identifier. Ticket-specific tests and hardware-in-the-loop procedures supplement the gate; they don't remove it.

- **Core-only:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Core/FFI/UI:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh <ticket-id> && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Flutter-only:** `flutter test && dart analyze && ./scripts/smoke-shot.sh <ticket-id> && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Release Flake:** `nix flake check && nix build .#packages.x86_64-linux.default && git diff --check`
- **macOS release build:** `flutter build macos --release && git diff --check`

Spike-dependent implementation tickets may quote the stable portion of these commands while the TechSpec is provisional. They must stop before implementation until final Stage 3 replaces every candidate-specific command and Stage 4 adapts the ticket.

## Index connection obligations

Every connection opened against the encrypted index must issue `PRAGMA foreign_keys = ON` immediately after the key pragma, and before any statement that touches a table. SQLite defaults it off and does not persist it in the file, so it is a property of the connection rather than of the database.

The ordering is stated that precisely because an earlier revision said *before any other statement*, which is unsatisfiable here: on a SQLCipher connection `rust/src/db/connection.rs` must issue `PRAGMA key` first, then the `SELECT count(*) FROM sqlite_master` unlock probe. An obligation the file it cites cannot meet invites the reader to discount the whole rule. The entire key design in `data-models/schema.sql` depends on it: with the pragma off the `ON UPDATE CASCADE` clauses that make a rename possible do not error, they silently do not fire, and the result is orphaned `links` and `fts_mapping` rows with nothing to signal the loss. Today only `init_schema` reliably runs on the singleton connection, while `open_encrypted_db_with_key` is reachable without it — which is how the tests use it.

`PRAGMA user_version` is the other connection-time concern. `init_schema`
must read it before applying the schema. A fresh index records version 2.
A version 1 index must add and backfill `notes.title_lookup_key` in one
transaction before it records version 2. The lookup key uses NFKC, full default
Unicode case folding, and NFC. It supports Unicode title-prefix matching without
depending on the ASCII-only `LIKE` and `NOCASE` behavior in the bundled
SQLCipher build. An index with a later version remains unchanged.

## Workspace location

The default local Workspace (ADR-005 decision 1) resolves to `$XDG_DATA_HOME/burlmd/workspace`, falling back to `~/.local/share/burlmd/workspace` when `XDG_DATA_HOME` is unset, and to `~/Library/Application Support/burlmd/workspace` on macOS.

This is deliberately *not* a visible directory in the user's home. The bundle is a Git repository the application manages, and CAP-WS-05 already provides the path for pointing burlmd at a Workspace the user placed wherever they prefer. Moving this default later is a user-visible migration, so it is recorded here rather than left to the implementation.

The encrypted index does not live inside the bundle. It is derived state (`data-models/schema.sql`), and placing it in the bundle would put an encrypted binary blob inside a Git repository whose entire premise is human-readable plaintext, producing a large opaque diff on every write. It belongs alongside the Workspace, not within it: it resolves to `$XDG_DATA_HOME/burlmd/index.sqlite3` — a *sibling* of the bundle root inside the shared `burlmd/` parent, not a file within the bundle and not an ancestor of it — with the same fallbacks as the Workspace path above, and `BURLMD_DB_PATH` continuing to override it for tests.

`WSPC-D004` moved the code to this path. `rust/src/db/connection.rs` previously resolved `$HOME/.burlmd/index.sqlite3`, a placeholder written in Epic B before any Workspace path existed and never reconciled with one; it now resolves the path above, with a test asserting the legacy location is neither read nor created. Because that ticket also rewrote the index schema, an index file left at the old path by a development build is not migrated and not read — it is stale derived state under a path this specification no longer names, and the bundle it was derived from can rebuild it.

The *mechanical* rules above — `cargo fmt`, `cargo clippy`, `dart format`,
`dart analyze`, `nixfmt` — are enforced as pre-commit hooks installed on entry
to the devenv shell. All of them exclude `.constitution/`, so editing the spec's
FFI contract does not trigger a build gate. The four *language* hooks each guard
on their manifest, but `rust/Cargo.toml` and `pubspec.yaml` both exist as of
Epic A, so all five hooks run on every applicable commit today.

`cargo clippy --workspace --all-targets` on every `.rs` commit is therefore a
live gate now. Against a warm `target/` it costs ~20s (measured at Epic D's
close, on a tree where the dev-profile dependencies were already built). The
multi-minute case is a cold or invalidated `target/` — `bundled-sqlcipher`
compiles the SQLCipher amalgamation from source, and `--all-targets`
additionally builds tests and benches, so a toolchain or feature bump pays for
all of it inside the commit. The standing suggestion is unchanged and still not
acted on: consider moving clippy to the `pre-push` stage, leaving `cargo fmt` on
`pre-commit`.

The coordinating Epic G branch proves the hash-and-regenerate drift check and contains the first private headless visual gate. The merged base doesn't contain the generated-binding checker or accepted managed CI evidence. `CI-M003` implements the stronger non-mutating checker from the preceding contract and may bootstrap both gates without importing the Epic G branch. Until an evidence commit passes milestone review, the broader testing standard, Rust async-avoidance rule, and Dart widget-statelessness rule remain review obligations.

## Running the real app (manual visual verification)

No ticket's Verification Command through Epic B ever actually launches the
built app (`cargo build`/`cargo test` exercise the Rust half in isolation;
`flutter test` exercises the Dart half against fakes) — so `flutter run`
launching successfully, and the UI actually rendering correctly, had never
once been checked. `flutter run -d linux` in debug mode crashes on startup:
`flutter_rust_bridge`'s generated Dart loader
(`lib/src/rust/frb_generated.dart`, `ioDirectory: 'rust/target/release/'`)
looks for the native library at `rust/target/release/librust.so`, resolved
relative to the process's working directory — a location distinct from the
`bundled-sqlcipher` debug artifact `cargokit` builds into
`build/linux/x64/debug/bundle/lib/librust.so` for the actual app bundle.
Before running the desktop app locally (`flutter run -d linux`, or any manual
visual check), run `cargo build --release` once from `rust/` (and again after
any change to the Rust API surface) so that path exists.

Since `SHEL-E001` the procedure below is also a command: `scripts/smoke-shot.sh <name>` builds the release native library and app bundle, launches, waits for actual rendering, captures `.qa/<name>.png`, and exits non-zero if the application fails to start or render. `BURLMD_SMOKE_SHOT_DIR` may direct a deliberately reviewed evidence capture elsewhere; `SPK-EDIT-F001` is the sole current exception, with its four generated captures kept under `.constitution/evidence/edit-f001/`. Render detection compares raw pixels against a measured desktop noise floor rather than byte-comparing images, because background desktop animation always differs between two captures. Every UI ticket's Verification Command gates on it.

For actually looking at rendered output rather than only asserting widget
properties in `flutter test` — screenshot with `grim`, and, when keystroke
simulation is needed, inject text with `wtype` (both provisioned in
`devenv.nix` for this purpose; Wayland-only, not part of the CI/build path).
This caught a real regression during Epic B's closeout that six passing
`flutter test` cases missed entirely: every test's paragraphs happened to be
single-run, so the bug (a multi-run paragraph silently collapsing to one
uniform, unstyled `TextField` once made editable) was invisible to the suite
until an actual rendered screenshot was inspected.
