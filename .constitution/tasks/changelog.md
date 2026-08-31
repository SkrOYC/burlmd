# Stage 4: Tasks changelog

## v2.1.21 - 2026-08-30

M0 authorizes the six Epic G production exceptions: SHELL-G001, PREF-G002, STATE-G003, TABS-G004, CLOSE-G005, and NAV-G007. The contracts define device preferences, per-Workspace session snapshots, active-Workspace FFI, and Linux/macOS visual-regression gates. OPEN-G006, EDIT-G008, FIND-G009, HIST-G010, and SHELL-G011 remain in Epic G with live owners.

## v2.1.20 - 2026-08-26

PR #12 full review round 18 closes the device-flow expiry identifier gap. AUTH-K001 tests and accepts both `expired_token` and GitHub's documented `token_expired` wording as restart outcomes. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 217 edges, and 153 points.

## v2.1.19 - 2026-08-26

PR #12 full review round 17 closes two P1 and one P2 evidence gaps. PATH roles are bound to Linux/ext4 and macOS/APFS. Packaging requires Linux/x86-64 build hosts and system-captured guest evidence for every named Ubuntu and Debian runtime. GitHub REST fixtures assert the accepted media type and `X-GitHub-Api-Version` header. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 217 edges, and 153 points.

## v2.1.18 - 2026-08-26

PR #12 full review round 15 fixes the executable Spike bootstrap. Every Rust prototype now creates and commits a lockfile before its first `--locked` command and regenerates that lock after CLI-declared dependency changes. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 217 edges, and 153 points.

## v2.1.17 - 2026-08-26

PR #12 full review round 14 closes two P1 gaps. Privacy-paused Object synchronization resumes only after the complete negative anonymous List, Get, Put, and Delete probe. PUBLISH-M014 now depends directly on REG-K001 and reruns its drift check with administrator-approved token-expiration evidence no older than 24 hours. The new direct dependency produces 217 edges; ticket count, effort, and critical path remain 80 tickets, 564 points, and 153 points.

## v2.1.16 - 2026-08-26

PR #12 full review round 12 expands Object Store privacy validation from anonymous read denial to negative anonymous List, Get, Put, and Delete probes. Disposable sentinels, post-delete survival verification, and unconditional authenticated cleanup make metadata disclosure and anonymous mutation release-blocking. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 216 edges, and 153 points.

## v2.1.15 - 2026-08-26

PR #12 full review round 11 removes a detach-state ambiguity in the auth flow. Direct transition to `LocalOnly` is asset-free only; asset-bearing Workspaces enter `LocalWithObjectStore` from connected, privacy-paused, authentication-required, or signed-out states and must reconnect the exact prior Remote before full-local preparation. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 216 edges, and 153 points.

## v2.1.14 - 2026-08-26

PR #12 full review round 10 closes three P1 and three P2 gaps. Replacement-store migration now validates privacy before intent or copy and continuously through migration. Consolidation tests include the second preparation and publication phase. Offline Remote detach retains the Object Store until the exact prior Remote reconnects and supplies fresh authenticated authority for a full-local transition, preserving CAP-ASSET-11. Refresh errors have typed terminal or Writer-action outcomes, and Spike evidence validates semantic timestamps and real Git revision widths. Ticket count, effort, dependencies, and critical path remain 80 tickets, 564 points, 216 edges, and 153 points.

## v2.1.13 - 2026-08-26

PR #12 full review round 9 closes three P1 and three P2 execution gaps. Consolidation must return through prerequisite verification and initial publication. Object Store privacy is revalidated on startup, periodically, and before publication, with drift pausing synchronization. Authenticated attestations stay with RELEASE-M009 and PUBLISH-M014 instead of the prototype-only packaging Spike. Stable Export leases now bind empty Directories, profile-bound Spike results require complete hardware facts, and UI-only tickets no longer mutate unscoped generated FFI outputs during verification. Ticket count, effort, dependencies, and the 153-point critical path remain unchanged at 80 tickets, 564 points, and 216 edges.

## v2.1.12 - 2026-08-26

PR #12 full review round 8 closes four P1 and four P2 execution gaps. Spike result schema v7 binds multi-host evidence to the same immutable inputs, the AST Spike evaluates both `pulldown-cmark` versions independently, and the packaging Spike tests the actual deterministic macOS archive. Release tickets require authenticated GitHub Actions attestations, nightly aggregation rejects corpus or meter-definition drift, publication rechecks the current macOS support pair, and complete advertised-ref analysis has explicit resource limits and cleanup. Replacement-store migration retains an old-store fallback and CLONE-K005 exercises it from a fresh device. The added `MIGRATE-I011` → `CLONE-K005` dependency produces 216 edges; the backlog remains 80 tickets and 564 points, and the recomputed critical path remains 153 points with migration and fresh-device recovery now on it.

## v2.1.11 - 2026-08-26

PR #12 full review round 7 found four P1 integrity gaps and one P2 schema defect. This patch resolves all five.

### Changed

- Deferred authoritative Object Store deletion during `0.x`; verified 30-day local cache eviction remains planned.
- Added durable replacement-store migration intent, mandatory dual-write publication, delta reconciliation, and revision-bound compare-and-swap cutover.
- Enforced `assets/objects/**` exclusion in every Core staging and commit path without trusting `.gitignore` or ambient Git configuration.
- Added direct hydration and retained-store removal from `LocalWithObjectStore` without reconnecting the detached Remote.
- Allowed honest empty stdout and stderr strings in result schema v6.
- Re-estimated MIGRATE-I011 and DETACH-I012 from 5 to 8 points each. The active backlog remains 80 tickets and becomes 564 points; 215 dependency edges remain, and the critical path becomes 153 points.

## v2.1.10 - 2026-08-26

PR #12 full review round 6 found one P1 and four P2 contract gaps. This patch resolves all five and corrects one stale lineage banner.

### Fixed

- Expanded the Git-analysis Spike to distinct verified default Linux and macOS filesystems, with every candidate and host-dependent Git behavior required on both.
- Required JSON refresh-token responses with every field needed for atomic access-token and refresh-token rotation.
- Added the explicit local-with-Object-Store state, Remote reconnection, and safe retained-store removal after offline Remote detach.
- Separated read-only find queries and navigation from editing, replacement, undo, and draft persistence.
- Added the forbidden-debug-marker scan to both exact CI runner commands.
- Updated the FFI forward-status banner to PRD v1.3.4, Architecture v1.4.7, and TechSpec v1.7.8-provisional.
- Revalidated the unchanged 80-ticket, 558-point, 215-edge graph and 150-point critical path.

## v2.1.9 - 2026-08-26

PR #12 full review round 5 found four P1 and two P2 contract gaps. This patch resolves all six.

### Fixed

- Added schema v5 system-captured CPU, core, memory, storage, graphics, display, power, and thermal facts, then bound AST and Asset evidence to the complete PRD reference profiles.
- Reworked the macOS packaging protocol so one immutable SHA-256-identical artifact runs on distinct macOS 26 and macOS 15 hosts. A separate same-host repeated construction proves reproducibility.
- Expanded Protected State enumeration from branches and tags to every fetchable ref advertised by unfiltered `git ls-remote --refs`; unclassified or unfetchable advertised refs block authoritative deletion.
- Kept the GitHub App at least privilege by refusing current or historical `.github/workflows/**` publication instead of requesting Workflows permission. Consolidation into a clean Workspace is the recovery path.
- Added typed `bad_verification_code` restart and `unverified_user_email` guidance to the GitHub device-flow contract and fixtures.
- Revalidated the unchanged 80-ticket, 558-point, 215-edge graph and 150-point critical path.

## v2.1.8 - 2026-08-26

PR #12 full review round 4 found six P1 and two P2 contract gaps. This patch resolves all eight.

### Fixed

- Bound AST evidence to system-captured host fingerprints and verified x86-64 Linux and Apple Silicon macOS facts; caller-supplied flags are assertions only.
- Made the macOS packaging Spike run each installed probe from the copied artifact that aggregation hashes.
- Bound packaging evidence to distinct Apple Silicon hosts running macOS 26 and macOS 15.
- Split GitHub App verification into automated public drift checks and a fresh administrator-approved expiring-token attestation.
- Limited offline Remote detach to attachment-only mode that retains the Object Store. Full-local transition now requires fresh authenticated Remote-ref enumeration.
- Integrated optional Consolidation into the connection state machine before initial Remote publication, including an end-to-end release-matrix scenario.
- Clarified full-local transition in PRD v1.3.3, evolved Architecture to v1.4.5, bound Stage 3 to both, corrected the earlier v1.4.4 lineage marker, and reconciled ADR-011 with the prohibition on signed-location and content-derived diagnostics.
- Recomputed 215 dependency edges. The 150-point critical path now includes the required Consolidation-to-connection sequence; ticket count and effort remain 80 tickets and 558 points.

## v2.1.7 - 2026-08-26

PR #12 full review round 3 found three P1 and two P2 gaps. This patch resolves all five.

### Added

- Added `REG-K001` to own project GitHub App registration, installation URL, versioned permissions, device-flow/expiring-token settings, release client ID, and live drift gate.
- Added `UNLINK-I013` for independent Object Store detach when complete Protected-State enumeration proves no Object reference exists, without detaching the private GitHub Remote.
- Added `FLAKE-M002` to stabilize the existing authoritative-success timestamp regression before CI makes the full Rust suite a required gate.

### Fixed

- Added proactive access-token refresh and exactly one refresh/replay after an authenticated `401`; a second `401` becomes authentication-required.
- Reconciled provisional Stage 3 against Architecture v1.4.4.
- Added opaque SHA-256-verified cross-host result export, SCP transfer, import, and aggregation for AST, path, Asset, and packaging Spikes.
- Recomputed the active backlog to 80 tickets, 558 points, and 214 dependency edges. The critical path remains 129 points.

## v2.1.6 - 2026-08-26

PR #12 full review round 2 found five P1 and two P2 gaps. This patch resolves all seven.

### Fixed

- Bound Asset-Spike reference-profile evidence to verified, distinct Linux and macOS hosts.
- Made both CI runners execute the real desktop `integration_test/` suite on their named device target, with Xvfb on Linux.
- Required replacement-store migration and full-local preparation to wait for complete published Remote branch/tag enumeration.
- Required Rescan to wait for the guest-change decision pipeline it preserves.
- Staged a real Core-backed multi-tab smoke scenario rather than using the screenshot name as implied setup.
- Updated the repository README to describe the active 77-ticket, 545-point roadmap and current deferrals.
- Recomputed 206 dependency edges and the 129-point critical path. Ticket count and effort are unchanged.

## v2.1.5 - 2026-08-26

PR #12 full review round 1 found three P1 and five low-cost P2 contract gaps. This patch resolves all of them without changing ticket count, effort, dependencies, or the critical path.

### Fixed

- Required the packaging Spike to copy Nix out-link results into its contained `artifacts/` directory before hashing or aggregation.
- Split AST performance and FFI projection evidence across distinct Linux and Apple Silicon macOS reference hosts with rejecting aggregation.
- Extended the generated-output convention and checker to `rust/src/frb_generated.rs` as well as `lib/src/rust/**`.
- Bound path-Spike runs to verified operating-system roles and required two distinct operating systems.
- Classified all documented GitHub device-flow polling errors as transient, terminal authorization, or fatal configuration/protocol outcomes.
- Made the CI ticket run formatting, Clippy, workflow lint, and explicit Linux/macOS matrix assertions.
- Added required production manifests and Platform seams to the Object Store and image-import ticket scopes.
- Required Spike result tools to validate RFC 3339 timestamps without assuming an optional JSON Schema format plugin.

## v2.1.4 - 2026-08-26

The fourth and final fresh review found no P0 issues and two P1 dependency/evidence gaps.

### Fixed

- Made the Writer-facing Remote UI depend on completed second-device join and detach/reconnect Core behavior, and explicitly assigned both workflows to that UI ticket.
- Split nightly PRD-meter verification into exact Linux and Apple Silicon macOS host commands plus an aggregation command that rejects missing, duplicate, or same-host evidence.
- Recomputed 203 dependency edges. Ticket count and effort remain 77 tickets and 545 points; the complete Remote UI dependencies move the critical path to 113 points.

## v2.1.3 - 2026-08-26

A third fresh full-stage review found no P0 issues and five P1 verification gaps. This patch resolves all five.

### Fixed

- Removed the pre-check binding generation that could erase stale evidence before `check-generated-bindings.sh` took its snapshot. All 43 FFI tickets now call the non-mutating checker directly.
- Added the mandatory real-application smoke launch to the six remaining UI-touching tickets.
- Added an explicit 3,600-second offline scenario to the live synchronization freshness meter.
- Narrowed `MAC-M008` to reproducible archive construction; installed two-version verification remains solely in dependent `GATE-M013`.
- Added exact apply/probe/cleanup commands and machine-readable outcomes to the second-device and private GitHub canary runbooks.
- Aligned the PRD vision version marker and corrected the extra H1 in the critical-path document.

## v2.1.2 - 2026-08-26

A second fresh full-stage review found no P0 issues and four P1 gaps. This patch resolves all four and the review’s lower-priority correctness/style observations.

### Changed

- Made immutable candidate construction depend on diagnostics, the complete nightly/product chain, and migration so later product changes can't fall outside the candidate hash.
- Added `CI-M003` as an explicit dependency of every FFI-changing ticket and made its non-mutating generated-binding checker part of all 43 FFI verification gates.
- Replaced the observer’s unavailable single-host benchmark script with exact Rust meter commands for the distinct Linux and Apple Silicon macOS reference hosts.
- Added an exact live private-Remote freshness command and dataset to `SCHED-L003`.
- Clarified that Object Store credential rotation removes the earlier local secret and instructs the Writer to revoke it at the provider.
- Reclassified implemented CAP-GRAPH-04 as delivered and retained it as a preservation obligation.
- Applied sentence case to the new Stage 4 document headings.
- Recomputed 201 dependency edges. The active total remains 77 tickets and 545 points, and the critical path remains 108 points.

## v2.1.1 - 2026-08-26

Fresh full-stage review found no P0 issues and nine P1 gaps. This patch resolves all nine and the review’s ticket-size concern.

### Added

- Added `HEALTH-M004` for the accepted history-storage meter and Writer-facing warning.
- Split Object Store credential rotation, replacement-store migration, and full-local detach into `ROTATE-I008`, `MIGRATE-I011`, and `DETACH-I012`.
- Split Export and Consolidation UI into `PORT-J006` and `CONSUI-J007`.
- Split the installed release matrix into AppImage, Nix, and Apple Silicon macOS gates and added terminal `PUBLISH-M014` publication.
- Added a shared execution gate: only the five Spikes run while Stage 3 is provisional. Every production ticket waits for measured upstream evolution, final Stage 3, and Stage 4 adaptation.
- Added a shared generated-binding scope convention for every FFI-changing ticket.

### Changed

- Recomputed the active backlog to 77 tickets and 545 story points. The critical path is now 108 points and ends with verified GitHub prerelease publication.
- Moved update-notification implementation before immutable candidate construction. Publication now depends on three installed-artifact gates.
- Made nightly meters depend on complete synchronization and the history-health warning, and gave the observer and nightly meters exact profile commands.
- Quoted the exact multi-host PATH, Asset, and packaging Spike commands.
- Made Platform-chrome removal own `burl_theme.dart`, named its visual baselines, and set the visual-diff threshold explicitly.
- Required plain-copy Export to preserve and report nonconforming guest Notes without repair or refusal.
- Aligned local diagnostics with PRD v1.3.1 and Architecture v1.4.1, including signed-location and content-derived-data exclusions.

## v2.1.0 - 2026-08-26

### Added

- Added the complete forward backlog: 70 atomic tickets across seven active epics and 522 story points.
- Added Epic G (desktop session and local workflows), Epic H (canonical Workspace authority and monitoring), Epic I (Assets and Object Store), Epic J (Export and Consolidation), Epic K (private GitHub Remote), Epic L (synchronization and reconciliation), and Epic M (quality and releases).
- Added explicit capability coverage for all 60 active PRD capabilities and preservation/integration obligations for the delivered baseline.
- Added the complete cross-epic dependency graph and the 114-point critical path from canonical AST research through the installed release gate.

### Changed

- Moved each decision-producing Spike into the epic it governs: AST-H001 and PATH-H002, ASSET-I001, GIT-L001, and PKG-M001.
- Planned downstream implementation tickets now. Spike-dependent tickets depend on their owning Spike and stop until measured upstream evolution accepts the contract; Stage 4 then adapts their scope, estimates, and verification rather than recreating the roadmap.
- Replaced the one-epic research-only plan with the forward execution sequence: independent foundations, canonical local application, Assets/portability/private Remote, synchronization/reconciliation, then quality/release.

### Fixed

- Corrected the earlier interpretation that a provisional TechSpec prevented epic planning. It prevents premature implementation of unresolved contracts; it doesn't prevent dependency-ordered backlog design.

### Removed

- Removed the single umbrella **Research Foundations** epic. Its five Spikes remain, now as the first relevant tickets of their owning epics.

## v2.0.0 - 2026-08-25

### Added

- Added active Epic G, **Research Foundations**, with five independent 8-point Spike tickets for the canonical AST, cross-platform paths, Git reconciliation analysis, hybrid assets and S3-compatible objects, and prerelease packaging.
- Added one framework-standard Spike report placeholder per ticket under `.constitution/spikes/`.
- Added exact TechSpec-derived prototype roots, write allowlists, verification commands, STOP conditions, and mode-tagged evidence to every ticket.

### Changed

- Replaced the empty active backlog with 40 research-only points and five equal parallel 8-point critical paths.
- Replaced the obsolete Wave 3 narrative with the forward pipeline: execute Spikes, route measured thresholds through Product Requirements and Architecture, finalize Technical Implementation, then generate the production backlog.
- Reserved PR #11 as delivered redesign foundation. No retrospective design epic or fictional reconciliation ticket was created for it.

### Removed

- Removed the provisional Epic G/H/I narrative assignments from the active roadmap. The new Epic G is a real active research epic with explicit tickets; it isn't the prior placeholder for sync integration.

## v1.9.4

Bounded PR #10 review round 23 documentation for an archived Epic F scope
deviation. The record covers schema recovery for version-zero SQLite files and
its verification. It does not reopen tickets or change active scope,
estimates, dependencies, acceptance criteria, the backlog, or the critical
path.

## v1.9.3

Bounded PR #10 review round 7 correction to archived Epic F. The correction
hardens the existing editor-depth persistence and continuation behavior; it
does not reopen scope, estimates, dependencies, acceptance criteria, active
backlog, or the critical path.

The correction also carries authoritative lifecycle outcomes across the Rust
FFI. A commit-stage warning no longer causes Dart to restore a renamed, moved,
or deleted editor. The completed Epic remains archived.

## v1.9.2

PR #10 review round 6 corrected the archived Epic F scope-closeout statement
and recorded the post-closeout hardening. The correction does not change task
scope, estimates, dependencies, acceptance criteria, the active backlog, or
the critical path.

## v1.9.1

Reviewed for upstream delta; no task changes required.

## v1.9.0
**Epic F — Editor Depth completed and archived.** All seven tickets
(`EDIT-F001` through `EDIT-F007`, 38 story points) are complete. The delivery
spans 25 commits (`a960e34` through `1dd94d3`), including the feature work,
contract reconciliation, and mandatory review corrections. The epic moves from
`active/` to `completed/` with completion notes and deferred follow-ups.

**Milestone validation and review are recorded at ticket level.** The evidence
includes the ticket-specific Rust and Flutter tests, Flutter Rust Bridge code
generation, readiness-gated smoke captures where applicable, `dart analyze`,
`git diff --check`, and debug-marker scans. Each milestone received one fresh,
independent bounded Sol review, and mandatory findings were fixed before the
next milestone. A pull-request-level comprehensive review has not run; it
remains part of final integration.

**Active planning recomputed from `active/` only.** Archiving Epic F changes
the active backlog from 38 points to **0 points**. The active critical path and
build graph are empty. The Wave 3 deferred narrative remains the planning home
for synchronization and conflict work, design and accessibility work,
editor-depth follow-ups, and quality and portability work.

**Reconciliation outcome.** The live PRD, architecture, and technical
implementation layers were reread and remain aligned with the completed Epic F
work. No upstream mismatch required a downstream documentation patch.

## v1.8.0
Evolution pass consuming Technical Implementation v1.6.0. Minor bump: the
remaining active Editor Depth tickets materially expand in scope and effort,
while their dependency topology stays unchanged.

- `EDIT-F005` remains 2 points but is now implementation-ready: platform-primary
  B/I/E and platform-primary+Shift+X are explicit, reversed selection is
  preserved, active composition is immutable, and the smoke is required to be
  `BURLMD_SMOKE_F005=1` readiness-gated.
- `EDIT-F006` grows 5 → 8 points and now owns the Rust/FFI/index/provider/
  generated/UI/rendered-Link/l10n/smoke path. Its trigger grammar, immutable
  snapshot rejection, 10-result bound, Core existing-or-prospective-ghost
  insertion text, keyboard/semantics behavior, and follow-time re-resolution/
  exact-target creation path all trace to Stage 3 v1.6.0. Its l10n output is
  explicit, repository-owned `lib/l10n/generated/` Dart rather than the
  unavailable synthetic package.
- `EDIT-F007` grows 3 → 8 points and now owns the Rust/FFI/provider/generated
  bindings/editor/direct `TextInputClient` proxy/tests/smoke path. Its gates
  require set-state-before-show, explicit desktop edit Actions, one atomic Core
  range operation for type, delete/backspace and paste; Core-returned
  Block-or-Phantom caret; partial remainders; UTF-16 emoji; and composition
  lifecycle behavior. This is not an undo implementation.
- Recomputed the active Epic F total to **38 points** and its critical path to
  **23 points**: `EDIT-F001` → `EDIT-F002` → `EDIT-F003` → `EDIT-F007` (the
  F004 branch ties F003). Completed ticket rows stay in the active Epic and
  count until epic closeout, matching the repository's current epic-level
  archival convention; only completed *epics* are excluded from the active
  total and graph.
- Exact ticket gates now quote the Stage 3 guidelines' focused/full Rust tests,
  FRB codegen, Flutter suites, env-prefixed readiness smoke commands, analyze,
  diff, and debug-marker checks.

## v1.7.1
Independent-review correction to **EDIT-F001**: the original Spike's single-commit STOP remains historical rather than being rewritten. A separately committed correction is explicitly allowed for independent-review findings, with its out-of-scope production/test/ADR/evidence touches documented in the active Epic. It closes the focused-drag range loophole, adds durable production-font `hitl_sil` captures, and stabilizes raw-source wrap-boundary height without changing the Stage 3 model.

## v1.7.0
**Epic E — Shell & Navigation completed and archived.** All eight tickets (`SHEL-E001` … `E008`, 27 story points) are implemented, independently reviewed and merged across 15 commits (`713de70` … `b3cd66f`: nine feature commits, three docs commits recording deviations, one review-fix commit, one harness hardening, one integration milestone). `EPIC-E-shell-navigation.md` moves from `active/` to `completed/` with Completion Notes appended. The active backlog drops from **57 points to 30** — Epic F alone. Minor bump: scope removed by completion, no restructuring of the stage.

**The application became usable, and the gates proved it.** Every ticket in this epic launched the real application as its verification gate — the standard this wave was scoped around after Epic B's rendering regression — so thirteen smoke screenshots exist where previously no gate had ever started the app. Startup opens straight into the Workspace (`SHEL-E002`; login retained for the deferred connect flow), the tree navigates from a single whole-tree call (`E003`), note switches close the outgoing session through the commit tier before the next opens (`E004`, serialized mid-execution after review), lifecycle actions re-anchor identity changes through the Core's id remapping (`E005`), search and crash recovery are visible (`E006`, `E007`), and CAP-WS-06 ships as a rescan affordance that refuses to run under open unflushed sessions (`E008`).

**The epic-level carry-forward was discharged at reconciliation, not waved through.** Execution had recorded that no ticket mounted `SearchPanel`, `RecoveredDraftsPanel` or `WriteTierNotice` into the shell — all three unreachable by users. The integration milestone (`b3cd66f`) mounted them before archival: search toggled from the sidebar, drafts above the tree, write-tier notice above the editor, polling arming when a Note is open.

**Critical path recomputed: 18 of the 30 points**, now starting at `EDIT-F001`: `EDIT-F001` → `EDIT-F002` → `EDIT-F003` → `EDIT-F007`. The chain into the Spike is gone — its remaining dependency, `SHEL-E004`, is done — so for the first time since planning the path is entirely intra-epic. `EDIT-F003` and `EDIT-F004` remain interchangeable at step 3 (both 5 points, both gated only by `EDIT-F002`, both feeding `F007`), so the chain measures 18 either way. The graph pruned the `EpicE` subgraph; the single cross-epic edge out of it, `E004 → F001`, is **satisfied**, not dropped — the mounted, navigating editor it named exists.

**Deferred follow-ups recorded in the archived epic**, five carried from execution plus one found at reconciliation: a Zero-Directory Workspace has no entry point for creating a root-level Directory (a recorded limitation of `SHEL-E005`); `RecoveredDraftsPanel` can overflow vertically with many drafts (P3, no scroll container); the tree-row move picker silently no-ops while the tree snapshot loads (P3); whether Core-side `reindex_workspace` transactionality covers typing into a previously-clean Note during a rescan is an open question from the `SHEL-E008` review; there is no test coverage of the periodic-timer arm path (a fake-clock tradeoff); and the two standing pre-Epic-E standards — `Semantics` labels and `gen-l10n` string externalization — were not met by the epic's own widgets, recorded in both the archived epic and `tech-spec/changelog.md` v1.4.0 rather than silently dropped.

## v1.6.0
Stage 4 pass of the 2026-08-21 constitution realignment, executed after PRD v1.2.0, architecture v1.3.0 and tech-spec v1.3.0. Totals change: **55 → 57 active points**; the critical path is unchanged at 33.

**Acceptance modes made explicit across both active epics.** The fourteen pre-existing tickets were retrofitted to carry `Acceptance / Mode: gherkin / Evidence` in the current template shape instead of an unlabeled Gherkin block; behavior is unchanged and no criterion moved. `SHEL-E008` was born with its tag. The one deliberate exception: `EDIT-F001`'s mode corrected to `hitl_sil`, since its evidence is human-inspected rendered output against pass/fail criteria, not scenarios — tagging it gherkin would have been the template satisfied and the standard betrayed.

**`SHEL-E008` added (Rescan Workspace, 2 points)**, honoring ruling Q12 that an explicit refresh affordance ships this wave rather than waiting for file-watching. Drives the existing full-reindex Core call; its STOP encodes the recorded transient-drop window by refusing to run under open sessions with unwritten edits. Not on the critical path; hangs off `SHEL-E003` in the graph.

**`EDIT-F002` gained the IME composition scenario** from the realignment audit: a live composition string must survive blur/commit without loss or duplication. ADR-006 inherits the platform IME and nothing tested this; it rides F002 because that is where promotion first meets composition.

**Wave 3 reshaped in the phasing strategy per rulings B5/B6:** two genuinely parallel tracks (sync/conflict backbone vs interactive design epic), GitLab at P1 behind GitHub inside Track 1, and the OD-03 handoff points drawn explicitly — design tokens gate the sync indicator, editor chrome, and CAP-PORT-04's rendition, with correctness beating design when the tracks compete for the same hands. Undo/version-restore/find-and-replace placed as a Wave-3 editor cluster consuming their declared contract surfaces; diagnostics rides Epic I with CI and the nightly benchmark job; Epic I revised to the Linux+macOS matrix chosen at Q9.

### Corrections from milestone review, folded into v1.6.0
Nothing beyond this branch has merged; fixes fold rather than version separately.

- A first mechanical retrofit tagged the Spike `EDIT-F001` as `gherkin`; corrected to `hitl_sil` above rather than left as template noise.
- The traceability sweep for this pass confirmed every new capability id from PRD v1.2.0 now has either an active ticket (`CAP-WS-06`), a Wave-3 home in the phasing strategy, or a named deferral with reasoning — none is orphaned.
## v1.5.0
**Epic D — Workspace & Persistence completed and archived.** All nine tickets (`WSPC-D001` … `WSPC-D009`, 50 story points, one of them a Spike) are implemented, reviewed and merged across 17 commits, and `EPIC-D-workspace-persistence.md` moves from `active/` to `completed/` with a Completion Notes section appended. The active backlog drops from **105 points to 55** — Epic E (25) and Epic F (30). Minor bump: scope removed by completion, no restructuring of the stage.

**What this changes about the shape of the remaining work.** Every ticket left is user-facing. The Core is built: a bundle on disk, an encrypted index derived from it, span-preserving editing, the four persistence tiers, and Note and Directory lifecycle with atomic link rewriting. The v1.4.0 framing — "every production `INSERT` in the repository is inside a test module" — no longer holds, while its companion claim still does: the application opens to a login screen that cannot be passed, and nothing Epic D built is reachable from it.

**Critical path recomputed: 33 of the 55 points, and it acquired a new root.** The chain is now `SHEL-E001` → `SHEL-E002` → `SHEL-E003` → `SHEL-E004` → `EDIT-F001` → `EDIT-F002` → `EDIT-F003` → `EDIT-F007`. `SHEL-E001` (the smoke harness) was recorded in v1.4.0 as deliberately *off* the critical path; that is no longer true, and the reason is arithmetic rather than a change of judgement. `SHEL-E004` was previously reached through `WSPC-D008` at 31 points of Epic D work, which dominated the 10-point Epic E route into the same node. With Epic D archived that route is gone, so the Epic E chain is the only way in and the harness is its root. The practical advice is unchanged and now doubly binding: build it first, since twelve later tickets invoke it as their verification gate. `EDIT-F003` and `EDIT-F004` are interchangeable at step 7 — both 5 points, both gated only by `EDIT-F002`, both feeding `EDIT-F007` — so the chain measures 33 either way.

**Graph pruned.** The `EpicD` subgraph, its eleven intra-epic edges, and the nine cross-epic edges out of it (`D004 → E002`, `D009 → E003`, `D008 → E004`, `D006 → E005`, `D009 → E006`, `D007 → E007`, `D008 → F002`, `D009 → F006`, `D006 → F006`) are removed, their source nodes no longer existing. Recorded explicitly in the file that all nine are **satisfied** rather than dropped: each named a Core capability that now exists and that the target ticket still consumes.

**A dependency-edge correction, recorded because the DAG got it wrong.** Execution surfaced an undeclared `WSPC-D007` → `WSPC-D006` edge. The published graph had `D006` (Lifecycle) depending only on `D005`; in practice its acceptance criteria also need `D007`'s pathspec-scoped commit and its write tiers, since a lifecycle operation must commit exactly the paths it touched and must carry every affected Note's buffer, span map, recorded revision and draft row through a rename. The edge was discovered mid-execution rather than at planning time. The generalizable lesson is written into `critical-path.md`: a ticket that mutates files *and* must leave open editing sessions coherent depends on whatever owns those sessions, even when the two look independent from their file scopes alone.

**Review convention followed.** One single-pass full review per milestone, with every P0 and P1 fixed before the next ticket began. Every one of the eight feature milestones returned findings worth fixing, so the epic carries eight review-fix commits alongside its eight feature commits and one Spike commit. Validation at close: 312 Rust tests, 18 Flutter widget tests, a clean `dart analyze`, and a non-gating smoke check confirming the built application launches and reaches the login screen.

**Also corrected: Epic D's preamble claimed "No ticket here touches Dart."** Three did — `WSPC-D006`, `WSPC-D008` and `WSPC-D009` landed the wrapper and provider call sites the regenerated bindings require, and `D008` additionally adapted `editor.dart` and its test to the `save_note` → `flush_note` change. Gated with `dart analyze` per the accepted reading of the preamble's second and still-true claim, that nothing in the epic is reachable in the running application. Recorded in the archived epic file rather than silently corrected.

**Deferred follow-ups recorded in the archived epic**, five in total: the dependency edge above; a rare flake in `git::operations::tests::path_in_head_distinguishes_a_new_note_from_one_already_in_history` (~1 run in 15), recorded here at the time as pre-existing and not introduced by this epic — which was wrong on both counts, since `path_in_head` is added by this epic and the cause was two sibling tests mutating `GIT_CONFIG_*` in the process environment while other tests spawned `git`; root-caused and fixed in PR #7 review round 13, and corrected in full in the archived epic file; relative links pointing *out* of a moved Note are not re-resolved, which suits a CAP-PORT-03 expansion rather than a bug fix; `find_notes_by_title`'s per-keystroke cost is unmeasured and has no supporting index, which Epic E's palette ticket must measure before shipping; and no Dart-side wrapper tests exist, the mis-wiring guard living only in the Rust wrapper-layer tests.

## v1.4.0
New active backlog: **Epic D (Workspace & Persistence, 50 points)**, **Epic E (Shell & Navigation, 25)** and **Epic F (Editor Depth, 30)**, totalling **105 story points** across 23 tickets, of which 2 are Spikes. Minor bump: new scope, no restructuring of the stage.

**Why this pass ran against a rewritten constitution rather than the previous one.** A pre-planning interview established that Stage 4 could not proceed as the constitution then stood. The planner is forbidden from inventing contracts, and too much of what these epics need did not exist: the project's own on-disk format was named in the PRD but defined nowhere, the FFI contract had no function for creating, deleting, renaming or listing a Note, and `open_note`'s identity model contradicted both the schema and the specification. PRD v1.1.0, architecture v1.1.0 and tech-spec v1.1.0 were produced first. Every ticket below traces to a contract that now exists.

**The finding that shaped the scope.** Every production `INSERT` into `notes`, `notes_fts`, `fts_mapping` or `workspaces` in the repository is inside a `#[cfg(test)]` module. No production code path writes a row to the index or a byte to a Note. Search is correct, tested and bm25-ranked, and returns an empty list in the running application permanently; `links` and `directories` have neither readers nor writers; the editor widget is built and tested but has never been mounted; and the application opens to a login screen that cannot currently be passed because no OAuth App is registered. Epics A–C built four good components with no wiring between them. This wave builds the application around them.

**Epic D — Workspace & Persistence (`WSPC-D001` … `WSPC-D009`).** Core-side only; nothing here is visible in the running application. Covers the OKF bundle domain, the span-preserving splice engine that replaces the never-implemented AST serializer, local Workspace bootstrap with no credential path, the indexer that gives the index its first production writer, Note and Directory lifecycle with atomic inbound-link rewriting, the four persistence tiers, and the editing and discovery FFI surfaces.

**Epic E — Shell & Navigation (`SHEL-E001` … `SHEL-E007`).** Removes the startup authentication gate, builds the Directory tree, mounts the editor for the first time, and adds lifecycle actions, search and draft recovery. `SHEL-E001` is a small DX chore creating the manual-QA smoke harness that twelve later tickets use as their verification gate.

**Epic F — Editor Depth (`EDIT-F001` … `EDIT-F007`).** Live Preview across every Block type, cross-Block selection and copy, Block creation and splitting and merging through ordinary typing, emphasis shortcuts, Link completion, and editing across a multi-Block selection.

**Two Spikes, both guarding silent-failure modes.** `WSPC-D001` measures the cost of whole-file reparse after a splice, since `architecture/risks.md` risk 7 is a data-corruption mode rather than a crash and the mitigation's cost has never been measured. `EDIT-F001` establishes from rendered output whether the raw-on-focus promotion can be made typographically stable, with an explicit STOP condition forbidding a verdict drawn from widget-property assertions — which is exactly what missed the structurally similar defect during Epic B's closeout. Placeholders established at `.constitution/spikes/SPK-WSPC-D001.md` and `.constitution/spikes/SPK-EDIT-F001.md`.

**Every UI ticket launches the real application.** Through Epic B no ticket's Verification Command ever started the app — `cargo test` exercised the Rust half in isolation and `flutter test` exercised the Dart half against fakes — which is how a rendering regression shipped past six passing tests. `SHEL-E001` turns the ad-hoc procedure documented in `tech-spec/guidelines.md` into a command, and every subsequent UI ticket gates on it.

**Critical path is 54 of the 105 points**, running `WSPC-D002` → `WSPC-D003` → `WSPC-D005` → `WSPC-D007` → `WSPC-D008` → `SHEL-E004` → `EDIT-F001` → `EDIT-F002` → `EDIT-F003` → `EDIT-F007`. Neither Spike sits on it: `WSPC-D001` runs alongside `WSPC-D002` and finishes sooner, so it gates the splice engine without delaying it.

**Deferred by decision, with reasons.** Epic G (sync integration, absorbing all six of Epic C's deferred follow-ups), Epic H (conflict and Suggestions) and Epic I (CI, images, Export, graph) are all scoped out of this wave. Synchronization is deferrable specifically because a local-first Workspace commits on every Note close, so version history and recoverability exist from the first Note — a Remote adds off-machine durability, not data safety.

**Known risk accepted: no CI during this wave.** Continuous integration was raised as close to mandatory for a 105-point wave on an application about to hold real notes, and was deliberately deferred to Epic I to keep the wave tight. It is recorded here rather than silently dropped. For the duration, `tech-spec/guidelines.md`'s statement stands unchanged — the testing standard, the Rust async-avoidance rule and the Dart statelessness rule are review obligations, not gated checks, and the only mechanical enforcement is the pre-commit hook set.

**Second known risk: wave size.** 105 points is more than double Epics A, B and C combined (49 points, summed from the ticket efforts in `completed/`). The scope was chosen deliberately over a smaller "technically working" cut, on the grounds that Epics D and E alone yield an editor that can only edit plain single-line paragraphs. If the wave needs to be shortened, Epic F is where to cut, and `EDIT-F007` is the only ticket that can go without dropping a P0 capability. `EDIT-F005` and `EDIT-F006` were originally listed beside it because nothing depends on them, which is true of the graph and false of the product: between them they are the whole of `CAP-EDIT-05`, `CAP-GRAPH-02` and `CAP-GRAPH-03`. Cutting those is a Stage 1 priority decision, not a scheduling one.

**Constitution maintenance.** Epics A, B and C remain under `completed/` and contribute nothing to the totals or the Build Order diagram, which is recomputed from active work only. `critical-path.md` bumped to v1.4.0.

### Corrections from PR review, round 1
Folded into v1.4.0 rather than versioned separately, since nothing in this pass has merged. Totals, dependency graph and critical path are unchanged — every fix was a scope or acceptance-criteria correction, not a re-estimation.

- **Four scope holes that would have forced an executing agent into an unjustified deviation.** The worst was on the critical path: `rust/src/db/schema.sql` is the DDL the application actually executes (`include_str!` in `rust/src/db/connection.rs`), it is still byte-identical to the pre-v1.1.0 constitution schema, and it appeared in no ticket's in-scope list — while `WSPC-D005` is required to write columns that do not exist in it. Added to `WSPC-D004`. Likewise `rust/src/error.rs` to `WSPC-D002` (the `AppError` variants the contract adds), `rust/src/markdown/ast.rs` to `WSPC-D003` (the `InlineElement::Link` reshape), and regenerated-bindings scope to `WSPC-D004`–`WSPC-D007`, each of which adds `#[frb]` functions but only two of which were permitted to regenerate the bindings for them.
- **`WSPC-D008` and `EDIT-F002` rewritten for the per-keystroke split.** The contract previously had `update_block` reparse on every keystroke, contradicting the tiering that ADR-007, ADR-008 and `risks.md` risk 7 all rely on. Both tickets now distinguish the buffering call from the committing one, with a STOP condition on each forbidding a reparse on the typing path.
- **`SHEL-E005` gained two acceptance criteria** for the case where a Directory operation invalidates the open Note's identity — renaming a Directory changes the concept id of every Note beneath it, and the Core now returns the remapping needed to re-anchor.
- **`critical-path.md` gained a "Built in this wave, surfaced in the next" section.** Backlinks (`CAP-GRAPH-05`) and opening a foreign Workspace (`CAP-WS-05`) land in Epic D with no consumer in E or F, and appeared in no deferral list. Recording them explicitly matters here more than usual: shipping Core capability with no caller and no note is precisely the pattern that made this whole wave necessary.

### Corrections from PR review, round 2
Folded into v1.4.0 on the same grounds as round 1. Totals, dependency graph and critical path are again unchanged.

- **`WSPC-D004` now owns the index path.** It was moving the index out of the bundle without ever naming where to, against a `connection.rs` that resolves an Epic B placeholder. The path is now pinned in `guidelines.md`, with a STOP forbidding the migration of a stale index file and an acceptance criterion asserting the new location.
- **`WSPC-D007` reworded for Core-side Optimistic Concurrency Control**, following the `save_note` → `flush_note` change, and gained a measured criterion for the one per-keystroke cost in this design that scales with document length: tier 1's synchronous encrypted write of the Note's full source, against the frame budget in `prd/constraints.md`. Left unmeasured it would be discovered by feel, on a long Note, after the tiering is load-bearing.
- **`WSPC-D008` and `SHEL-E002` gained the files they were already required to change** — `note_providers.dart` and `workspace.dart` respectively — and `WSPC-D008`'s weakest acceptance criterion was replaced with one that asserts no exposed function takes a `workspace_id`, which is the invariant the contract change actually established.
- **`critical-path.md` was missing a third built-but-unsurfaced capability.** `find_notes_by_title` (`CAP-FIND-02`) is built in `WSPC-D009` with no consumer, exactly like backlinks. The section exists to stop precisely this from going unrecorded, so a gap in it is worse than not having written it.

### Corrections from PR review, round 3
Folded into v1.4.0. Totals, dependency graph and critical path are again unchanged.

- **Three more scope holes, all the same class as round 1's `schema.sql` one.** `rust/src/error.rs` was scoped to `WSPC-D002` for two variants, but the contract adds four, and `WSPC-D007` cannot pass its own revision-mismatch criterion without `RevisionMismatch` existing. `rust/src/draft.rs` — where `NoteMetadata` and `NoteState` are actually defined, `api/ffi_api.rs` only re-exporting them — was scoped to `WSPC-D007` alone, while `WSPC-D009` returns `Vec<NoteMetadata>` from four functions and depends only on `WSPC-D005`, so it is schedulable first and its gate would be unpassable. Added to `WSPC-D008` and `WSPC-D009`.
- **`open_workspace` was credited to `WSPC-D004` but appeared nowhere in it.** `critical-path.md` said D004 exposes it, ADR-005 decision 7 assumes it exists, and `WSPC-D005` tolerates non-conformant files for its sake — but D004's description named only `open_or_create_local_workspace` and none of its criteria mentioned opening a directory the application did not create. Added to both.
- **`WSPC-D003` now owns the inline-granularity span map** that ADR-007 decision 8 introduces, with a criterion asserting the concrete case (`hello **bold** world`, rendered offset 6 → source offset 8). Without this the mapping `EDIT-F003`/`EDIT-F007` depend on belonged to no ticket while sitting at the end of the critical path.
- **`EPIC-F`'s preamble overclaimed.** "Mapping formatted output to editable spans is no longer a requirement at all" is true for the focused Block and false for a selection across unfocused ones, which is the only kind `BlockRange` describes. Rewritten to scope the claim and state what survives, with a matching STOP on `EDIT-F001`.
- **`WSPC-D007` gained a criterion for the idle write firing mid-focus**, which ADR-008 now specifies, and `WSPC-D006` one for clearing a deleted Note's draft row — reproduced as a real orphan against SQLite, since `drafts` has no foreign key and nothing cascades.
- **`critical-path.md` said "Two" and "Both" over three bullets**, an off-by-one introduced when round 2 added `find_notes_by_title`. In a section whose entire purpose is keeping built-but-unsurfaced capability from being lost, a miscount is worth fixing.

### Corrections from PR review, round 4
Folded into v1.4.0. The point totals below change; the graph and critical path do not.

- **Seven of Epic D's nine gates passed against zero tests.** `cargo test <filter>` exits 0 when the filter matches nothing — verified: `cargo test okf::` reports "0 passed … 74 filtered out" and exits 0. The `clippy` half catches compile failures but not absent tests, so `WSPC-D002` and six others could have shipped green with no tests at all. This is round 2's spike-placeholder defect one layer up. Every filtered gate now asserts the filter matched at least one test first (`cargo test <filter> -- --list | grep -q ': test'`).
- **Both spike gates were trivially true.** `git diff --quiet HEAD -- rust/src` compares the *working tree* to `HEAD`, so it passes on any clean tree — including right after the spike commits production code, which is the order the workflow actually runs in. Pinned to `git merge-base HEAD master`.
- **`WSPC-D002` added variants to an `#[frb]` type without scoping the generated bindings.** `AppError` is mirrored into `lib/src/rust/error.dart` and the generated codecs fall through to `unimplemented!()` on an unknown discriminant, so a Rust-only addition compiles, passes the gate, and panics the first time the new variant crosses the boundary. Round 3 added the variants and reasoned about the Rust half only.
- **Five capability fragments had no criterion citing them** (four P0, plus P1 `CAP-GRAPH-04`) — three the review named, two more found by sweeping every `CAP-*` id against the active tickets and the contract afterwards rather than fixing only what was reported. `CAP-EDIT-02`'s thematic breaks appeared nowhere at all; `CAP-GRAPH-03` survived as an incidental line inside a ticket about Link *insertion*; and `CAP-GRAPH-04`'s "create that Note by following the Link" had no criterion despite the contract asserting the UI does it. `CAP-WS-02` (one commit per editing session) and `CAP-WS-04` (the encrypted index and its key) were covered by `WSPC-D007` and `WSPC-D004` without either naming them. Criteria added or annotated across `EDIT-F002`, `EDIT-F006`, `WSPC-D004` and `WSPC-D007`, with the full sweep — including the four capabilities that are legitimately deferred — recorded in `critical-path.md` rather than quietly closed.
- **The wave-shortening plan dropped three P0 capabilities.** "`EDIT-F005`/`F006`/`F007` — none blocks anything else" is true of the dependency graph and false of the product: F005 is the whole of `CAP-EDIT-05`, F006 the whole of `CAP-GRAPH-02` and `CAP-GRAPH-03`. Only `EDIT-F007` can go without a Stage 1 priority change, and that is now what it says.
- **`WSPC-D006` had no criterion for the one case the missing `drafts` foreign key exists to permit.** The schema's sole justification for omitting it is that a draft must survive a rename, and round 3 added a criterion for *deletion* while leaving the rename case untested — reproduced: after the rename, the draft row still sits under the old concept id.
- **The completed epics sum to 49 points, not 52.** Ticket efforts in `completed/` are 10 + 23 + 16. The 52 was carried forward from an earlier revision and this wave restated it, deriving "roughly twice the size" from it. Low stakes, but a document set whose value is that its numbers are checkable should not contain one its own artifacts contradict.
- **`SHEL-E001` gained `.gitignore`** (twelve later tickets each write a screenshot to `.qa/`, which is neither ignored nor scoped anywhere), and Epic E's preamble now states the blast radius of that 2-point ticket gating twelve of fourteen UI gates on Wayland-only tooling.

### Corrections from PR review, round 5
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **Filtered gates could not see breakage outside their own filter, and one ticket guarantees such breakage.** Round 4 closed "gates that pass against zero tests"; this is the adjacent hole. `WSPC-D004` rewrites `rust/src/db/schema.sql`, and the existing tests in `rust/src/api/ffi_api.rs` insert into `notes` without `content_hash` and into `fts_mapping` without `workspace_id` — both now `NOT NULL`, both string literals that `clippy` compiles without executing. `WSPC-D005`, `D006`, `D007` and `D009` all filter past it too, so the first gate that would run them is `WSPC-D008`, four tickets later on the critical path. For that whole stretch `cargo test` is red while every gate is green. `WSPC-D002` and `WSPC-D004` — the two tickets that change shared DDL or shared types — now append an unfiltered `cargo test`.
- **`WSPC-D007` gained the criterion the OCC fix requires**: two idle writes in one session must both succeed. Its previous external-change criterion was satisfiable by the very failure it was meant to exclude.
- **`WSPC-D002` gained the parseable-but-typeless frontmatter criterion**, and `WSPC-D006` one asserting a deleted Note's text no longer matches a search.
- **"Seven later tickets use `SHEL-E001` as their gate" was wrong twice**, contradicted by "twelve" elsewhere in the same PR. Counted: `SHEL-E002`–`E007` and `EDIT-F002`–`F007`. Round 4 wrote a paragraph about that 2-point ticket's blast radius on Wayland-only tooling; the two stale sevens understated it by 40% in the documents most likely to be read for scheduling.
- **`CAP-GRAPH-04` is P1, not P0.** Round 4's traceability sweep counted it among the P0s. The gap it named and the criterion added were both right; only the label was wrong, in a section whose entire value is that its claims check out against the PRD.

### Corrections from PR review, round 6
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **`WSPC-D003` could not compile, let alone pass its gate.** It reshapes `InlineElement::Link`, an `#[frb]` type, without scoping the generated bindings — ten references in `frb_generated.rs` and two in `lib/src/rust/markdown/ast.dart` — while its own `cargo clippy --all-targets` builds the whole crate. Round 4 fixed exactly this for `WSPC-D002`, where a variant *addition* compiled and panicked at runtime; a field *rename* does not get that far. D003 sits at position 2 on the critical path.
- **`WSPC-D008` and `WSPC-D009` end in `dart analyze` against callers they do not scope.** `rust_api_provider.dart` is the only file touching `ffi.*` directly and wraps `openNote`, `searchNotes`, `updateBlock` with its old `AstNode` parameter, and `saveNote` — which this contract deletes outright. `editor_test.dart` overrides `updateBlock` with the old signature, and `dart analyze` covers `test/`. D008's scope note reasoned correctly about `note_providers.dart` and stopped one layer short of the wrapper that file calls. `dart analyze` reports no issues on the current tree, so these gates go genuinely red.
- **Epic G's deferral inventory omitted the `auth.rs` rework the contract now mandates**, listing only wiring items and asserting "it needs no further Stage 3 work". `OAuthFlowStart` and `authenticate_workspace` both change shape. The consequence is worth stating plainly: the CSRF check rounds 2 and 3 spent two passes relocating has **no owning ticket in this 105-point wave**, so until Epic G lands the shipped code still mints a `state` nothing compares. Round 3 counted "it removes an obligation no ticket owned" as a benefit of moving the check Core-side; that only becomes true once the Core-side obligation is owned. Also records that this supersedes Epic C's "accepted design decision (not a gap)" note about the verifier transiting Dart.
- **`flow-edit-note.md` never received round 5's fix.** The mid-focus tier 2 write was drawn with no return arrow and no comparison step, so an implementer following the sequence literally reproduces the exact defect round 5 removed — the baseline does not advance, and the next write raises `RevisionMismatch` against this application's own output. Both tier 2 writes now show the comparison and the re-record. Same "corrected in the contract, left standing in the diagram" shape as the CSRF `state` in round 2.
- **`WSPC-D008` sent the implementer looking for a function that does not exist.** "Remove `open_note_by_id` by merging it into `open_note`" — `open_note_by_id` appears only in the pre-v1.1.0 contract and was never implemented. Reworded, and `save_note`'s deletion, which *is* real and was unstated, named.
- **`critical-path.md`'s "All three" lost its antecedent** to the paragraph round 4 inserted between it and the list it refers to.

### Corrections from PR review, round 7
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **Five tickets create Rust modules without scoping the file that declares them, and five gates therefore fail.** `rust/src/lib.rs` is a flat declaration list and each module directory needs its own `mod.rs`. `WSPC-D002` and `WSPC-D003` got this right; `D004` and `D005` create `workspace/` and `index/` without scoping `lib.rs`, and `D006`, `D007` and `D009` add submodules without scoping the `mod.rs` that declares them. Round 4's own fix is what makes this hard rather than cosmetic: each gate now opens with `cargo test <path> -- --list | grep -q ': test'`, and an undeclared module matches nothing. Verified — `cargo test workspace::bootstrap -- --list` reports "0 tests" and the guard exits 1. Third round running in which the finding is a ticket that cannot pass its own gate.
- **`WSPC-D005` gained the FTS deletion ordering** — a STOP, a description sentence and a criterion — which round 5 wrote for the delete path only. Reindex touches every row and runs on first open, after a merge, and on recovery, so a rebuild that clears `notes` first strands the whole Workspace's text each time.
- **`WSPC-D007`'s mid-focus criterion restated the rule that was wrong.** It repeated "later spans shift by the byte delta" verbatim from ADR-008, which omits resizing the edited span. Replaced with three criteria: the tier writes the working source verbatim, the edited span's end moves as well as later spans shifting, and the typed text appears exactly once after a mid-focus write followed by a blur.
- **`WSPC-D006` gained the rename cases**: a rename onto an existing or reserved filename must report the path unavailable on the same terms as creation, and a rename must refresh the FTS title row or search keeps answering with the old title.
- **`WSPC-D001` gained the timer-contention question**, which no ticket owned and which lands inside the 16ms budget if the obvious mutex shape is reused.

### Corrections from PR review, round 8
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **The Dart wrapper surface was systemically unowned.** `lib/src/providers/rust_api_provider.dart` is the seam every widget and every widget test overrides, and the only file touching `ffi.*` directly. It appeared in three tickets, none of which was described as *adding* wrappers — while **eight** later tickets across Epics E and F call methods that do not exist on `RustApi`: `workspaceTree`, `closeNote`, the seven lifecycle calls, `pendingDrafts`, `getBlockSource`/`commitBlock`, the four Block-manipulation calls, `linkCompletions`, and the three range operations. Every one of those gates ends in `flutter test`, and each test needs a `RustApi` override that cannot compile against a class lacking the method. Previous rounds closed this class one instance at a time; here it was systemic. `WSPC-D008` now lands the editing half of the surface in full and `WSPC-D009` the discovery half — checked against the dependency graph so every consumer has its wrapper before it needs one.
- **`WSPC-D009` reshapes `NoteMetadata` and `test/components/editor_test.dart` constructs it directly**, with `workspaceId`. D009's gate ends in `dart analyze`, which covers `test/`, and D009 depends only on `WSPC-D005` — so it is schedulable before `WSPC-D008`, the only other ticket scoping that file. Round 6 fixed this class for the same file but reasoned only about `updateBlock`'s signature; `NoteMetadata` reaches it by a second route. Also recorded: `WSPC-D007` adds `restoredFromDraft` to `NoteState`, which the same file constructs, and D007's gate has no `dart analyze`.
- **Round 4's spike gate fix traded trivially-true for order-dependent.** `git diff --quiet $(git merge-base HEAD master) HEAD` fails once *any* earlier commit on the branch touched those paths. `EDIT-F001` is safe only because it is first in Epic F; `WSPC-D001` is not — it and `WSPC-D002` both have no dependencies and `critical-path.md` numbers D002 first, so the gate would already be dirty on arrival. Both now compare the Spike's own commit (`HEAD~1..HEAD`), with a STOP stating the one-commit assumption that form carries.
- **`WSPC-D004` and `WSPC-D007` gained `rust/src/git/operations.rs`**, for the missing `init` and the missing pathspec-scoped commit respectively, plus criteria that a close commits one Note rather than the worktree and that the author is the fixed application identity.
- **The unfiltered `cargo test` rounds 5 added to `WSPC-D002`/`WSPC-D004` requires a live OS secret service.** Three keyring tests hang past 60s without one. Both gates now skip them explicitly, which is also what a headless CI in Epic I will need.

### Corrections from PR review, round 9
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **Round 8's wrapper fix checked the consumer direction and not the producer direction.** It verified that every ticket *needing* a `RustApi` method depends on the ticket landing it — which held — but `WSPC-D008` was given the seven lifecycle wrappers while depending only on `WSPC-D003` and `WSPC-D007`. `WSPC-D006` implements those seven FFI functions and is not in D008's dependency closure, so `ffi.createNote` and friends would be unresolved identifiers at D008's `dart analyze` gate. Moved them to `WSPC-D006`, which implements them and now ends its gate in `dart analyze` — rather than adding a dependency, which would have pulled an 8-point ticket onto the critical path. The rule is now explicit: **a wrapper ships with the function it wraps**, and both directions are checked mechanically.
- **`WSPC-D006` gained the open-Note rename criteria**, covering the working source, the span map and the recorded revision — and its existing draft criterion was corrected, since "the drafted content is intact" mandated preserving the pre-rename frontmatter and would have made the next write revert the rename.
- **`SHEL-E007` gained the write-failure surface**, a STOP and two criteria. Nothing in Epic E acted on a tier 2 failure, which no caller can observe.
- **Both Spikes required running code while scoping only their own report.** `WSPC-D001` must report measured reparse timings and timer contention; `EDIT-F001` must produce screenshot comparisons of a presentation `EDIT-F002` builds — and `EDIT-F002` depends on it. The gates only forbid *committing* production code, but the Gherkin said "no file under lib or rust/src has been modified", which reads as the working tree and closes the door on the prototyping both require. Both now say the constraint is on the Spike's own commit and name where prototypes go.
- **`WSPC-D004` gained the no-history criterion** for `open_workspace`, per ADR-005 decision 8.

### Corrections from PR review, round 10
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **`WSPC-D004`'s description contradicted its own acceptance criteria** on whether `open_workspace` initializes a repository. The criteria were round 9's fix; the description was the sentence round 9 did not reach.
- **`WSPC-D006` gained the source-Note obligations.** A rename rewrites every inbound Link, so it writes files other than the renamed Note — and those Notes' buffers, spans, revisions and draft rows all have to move with it, or the rewrite is reverted later by a verbatim write. Four criteria: a source Note open with buffered edits, a source Note with an unflushed draft, the self-link case, and the renamed Note itself.
- **`WSPC-D007` gained the no-edit close criterion.** Reading a Note and navigating away is the most common path through the commit tier, and nothing said not to commit.
- **`EDIT-F004`'s Enter criterion was replaced with three** that specify the empty-Block state the Core cannot represent: UI-side until the first character, then `insert_block`, then `update_block` against the returned path — and nothing inserted if focus leaves without typing.

### Corrections from PR review, round 11
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **`WSPC-D007` gained the tier-1 breadth criteria.** The draft-row obligation was written for `update_block` alone, so a structural edit — split, merge, insert, delete — had no specified persistence until the write tier fired ~1s later. Two criteria: a structural edit writes a draft row immediately, and a kill inside that window preserves it.
- **`WSPC-D005` was given the `InlineElement::Link.exists` obligation**, which `WSPC-D003` declares but cannot satisfy from upstream of the index.
- **`SHEL-E005` gained four criteria and a STOP for `LifecycleEffects.rewritten`.** A rename rewrites Links inside other Notes; without the list the shell cannot refresh them, and a stale Link followed from a stale view recreates the concept the rename just removed.
- **Both Spikes were moved out of `rust/examples/`.** `cargo clippy --all-targets` compiles examples, which would have made Spike prototype code a lint gate on `WSPC-D003`.
- **A verification command filtered on `--skip keyring --skip keyring_token_store`**, where the second is a substring of the first and therefore had no effect.

### Corrections from PR review, round 12
Folded into v1.4.0. Points unchanged at 105; one dependency edge added, so the graph is now 34 edges. The critical path is unchanged — `EDIT-F006` rises to 51 points and `EDIT-F007` remains the longest terminal at 54.

- **`EDIT-F006` could not pass its own gate.** Its create-on-follow criterion needs `RustApi.createNote`, which `WSPC-D006` lands, and `WSPC-D006` was nowhere in `EDIT-F006`'s transitive closure. Its gate ends in a `flutter test` whose `RustApi` override would not compile against a class lacking the method, and it scopes no provider file and no Rust, so it could not self-remedy. Same shape as rounds 8 and 9 — and it survived round 9's closure check for a recordable reason: that check walked the wrapper *table*, and this ticket's row lists only `linkCompletions`. The `createNote` need came from a criterion round 4 added. Closure checks have to run against criteria text, not against the wrapper inventory.
- **`WSPC-D002` gained three link-serialization criteria**, including a round-trip property test over titles containing spaces, parentheses, `#` and `%` — because the on-disk link form must be angle-bracket wrapped or a multi-word title produces something CommonMark does not parse as a link at all.
- **`WSPC-D006`'s rename criterion now specifies a target title containing a space.** As written it passed vacuously against single-word fixtures: with no edge indexed there is nothing to rewrite and nothing left pointing anywhere.
- **`WSPC-D009` gained a criterion that `insert_text` parses back to a Link** for a multi-word title, since `EDIT-F006`'s STOP forbids the UI from repairing it.
- **`WSPC-D005` gained two criteria** asserting the search query plan and the `ANALYZE` obligation, rather than relying on a timing at a corpus size where the wrong plan still passes.

### Corrections from PR review, round 13
Folded into v1.4.0. Totals, graph and critical path unchanged.

- **`WSPC-D008` could not pass its own `dart analyze` gate.** It scopes `note_providers.dart` and `editor_test.dart` for exactly this reason but excludes `lib/src/components/**`, and `editor.dart` builds an `AstNode.paragraph` and passes it to `NoteController.updateBlock` — an argument-type error the moment that becomes source-text-based, which the ticket's own STOP requires. `NoteController.open` breaks the same way when `open_note` becomes `async`. `editor.dart` is now carved out of the exclusion, narrowly: adapt the call sites, do not start `EDIT-F002`'s work five tickets early.
- **`WSPC-D007` gained three `reload_note` criteria** — the draft row is deleted and everything rebuilt from disk, the next write succeeds rather than repeating the mismatch, and conflict markers arrive as Suggestion nodes. `SHEL-E007` gained the two consuming criteria, including that the confirmation says plainly that reloading discards the buffered text. It is the only prompt in the application that destroys unwritten work.
- **`EDIT-F003`'s selection fixture is now heterogeneous.** Rendered-text offsets are defined per `AstNode` variant, so a three-paragraph fixture exercises one definition while satisfying the criterion.
- **`EDIT-F006` gained the two `exists`-staleness criteria**, in both directions: a ghost Link whose target was created elsewhere, and a resolving Link whose target was deleted.
- **`WSPC-D002`'s round-trip property test now includes `&`, a named entity and a numeric reference.** Without them it passed with the entity defect in place — the same vacuous-criterion shape round 12 recorded.
- **Both Spike gates passed when their report file was missing.** `! grep -q PATTERN FILE` inverts `grep`'s exit 2 into success. Prefixed with `test -s`. Rounds 2, 4 and 8 each caught a different variant of a spike gate that could not fail.

## v1.3.0
- Completed **Epic C: Security & Sync** (`SYNC-C001`–`SYNC-C003`), total 16 story points: a `gix`/`git`-CLI hybrid for clone/commit/push/pull against the local Workspace, a GitHub OAuth PKCE login flow with OS-Keychain token storage, and a debounced background sync scheduler with exponential-backoff retry and conflict-path re-index/notify hooks.
- Each milestone passed an independent single-pass review gate before the next started; `SYNC-C001` needed one follow-up fix commit (`ecd705e`) for two P2 findings (a `commit_all` deletion/rename bug, and redacting `GitCredentials`' `Debug` output so a stray `{:?}` can never print a token). `SYNC-C002` and `SYNC-C003` each passed their single review pass clean.
- Archived `EPIC-C-security-sync.md` to `.constitution/tasks/completed/`, with a new "Completion Notes & Deferred Follow-Ups" section recording six concrete deferred items un-ticketed by this epic: GitHub OAuth App registration (real-network exchange is only mock/fixture-tested so far); a keychain credential-readback accessor the scheduler needs but `api::auth` doesn't yet expose; the missing `notes`/`notes_fts` re-index function the scheduler's conflict hook currently no-ops against; app-lifecycle wiring (constructing/starting the scheduler, `notify_activity()` from save, the login flow's clone+index-init tail, and session-restore-on-startup — none of which exist yet, so every restart re-shows login); `SyncScheduler::stop()`'s unbounded wait on an in-flight git subprocess; and the open question of whether a post-conflict clean auto-merge should re-push immediately rather than waiting for the next natural trigger.
- Recomputed the active backlog to 0 story points and the critical path to empty (see `tasks/critical-path.md` v1.3.0) — all three epics originally scoped (52 story points total) are now complete. Moved the `SYNC-C001`→`SYNC-C003` nodes into a "Completed - Epic C" subgraph in the Build Order diagram, preserving all existing edges and styling.
- Ran the tech-spec half of the Constitution Freshness & Reconciliation Pass alongside this closeout: corrected a doc-drift bug in `tech-spec/changelog.md`'s `v1.0.4` entry (named a nonexistent `KeyringTokenStore` type instead of the real `store_tokens_in_keyring` function), backfilled `stack.md`'s BOM with the `reqwest` direct dependency and a `keyring` 4.1.5 known-issue note, and added the `rust/src/sync/` and `lib/src/screens/` directories to `guidelines.md`'s repo-layout tree. See `tech-spec/changelog.md` v1.0.5.
- Recommend a future `/planning-engineering-execution` pass to convert the deferred follow-ups above into a ticketed integration-work epic before further capability work begins.

## v1.2.5
PR #4 dual-axis review, round 4 (confirming pass after round 3's material behavior changes) — loop closed, no fixes needed.
- Both axes returned zero P0/P1, the third consecutive clean high-priority round (after 2 and 3), satisfying the review loop's stop condition. No code changes this round.
- Documented, not fixed: a Feature-Envy P2 (Standards) — `search_notes_impl`/`save_note_impl`/`fts5_phrase_query` still live in `api::ffi_api` rather than `db`, the other half of round 2's Divergent-Change fix; a missing error surface for FFI failures in `note_providers.dart` (P2, Spec, currently unreachable since `Editor` isn't mounted); and an Investigate (Spec) that `search_notes` has no `workspace_id` filter despite `prd/capabilities.md`'s "search... in their Workspace" wording — currently unreachable since only one hardcoded workspace exists and no workspace-selection ticket has landed.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review round 4" note for full detail.

## v1.2.4
PR #4 dual-axis review, round 3 (confirming pass after round 2's clean high-priority result).
- Fixed a real correctness regression introduced by round 2's own fix (Spec axis): quoting the *entire* search query as one phrase turned multi-word search into exact-adjacent-phrase matching, contradicting `prd/capabilities.md`'s "search across all Notes." `fts5_phrase_query` now quotes each whitespace-split token individually and joins with a space, restoring implicit-AND-across-terms matching while still avoiding FTS5 syntax errors on hyphens/colons/parens/unmatched quotes. Replaced the round-2 test that had encoded the wrong phrase-only semantics.
- Fixed a zeroization gap (P2, Standards axis): the SQLCipher key's hex encoding was built via a chain of per-byte `format!` calls (each an un-zeroized, dropped-not-wiped intermediate `String`) before the final result was wrapped in `Zeroizing`. Now writes hex digits directly into one pre-sized `Zeroizing<String>` via `std::fmt::Write`, so there is exactly one key-hex allocation and it was zeroizing-wrapped from the start.
- Fixed a Single-Responsibility P2 (Standards axis): split `_EditableBlock` into a top-level `_buildBlock`/`_isSingleTextRun` eligibility dispatcher and a narrower `_EditableParagraph` that operates on an already-validated single-run `content` list rather than a whole `AstNode`.
- Fixed a spec-honesty P2 (Standards axis): `schema.sql`'s header comment claimed migration tracking via `PRAGMA user_version`, but no statement ever set it. Added `PRAGMA user_version = 1;` to both schema copies, with a comment that the first real migration should branch on this baseline. Added a test asserting the pragma reads back as `1`.
- Backfilled a documentation gap in `UIDB-B001`'s Justification (P2, Standards axis): the `zeroize` crate addition was never recorded alongside `keyring`/`getrandom`.
- Documented (not fixed): `architecture/resilience.md`'s "SQLite Draft Persistence" bullet describes per-keystroke persistence to the `drafts` table with restore-on-boot, but no Epic B ticket ever wired this up — `update_block` only mutates the in-memory cache. Added a "Current implementation status (Epic B)" note flagging this as needing its own future ticket. Also noted `devenv.nix`'s `grim`/`wtype` additions as intentionally outside this ticket's production-code scope.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review fixes (round 3)" note for full detail. Rounds 2 and 3 both produced zero P0/P1 findings, satisfying the review loop's two-consecutive-clean-round stop condition.

## v1.2.3
PR #4 dual-axis review, round 2.
- Fixed a real, exploitable-by-any-ordinary-search P2 (Spec axis): `search_notes_impl` passed raw user input straight into FTS5's `MATCH`, whose query grammar throws syntax errors on hyphens, colons, parens, and unmatched quotes — everyday search terms. Now wraps the query in a quoted-phrase escape (`fts5_phrase_query`) so it's always treated as one literal phrase. Added tests for the exact previously-broken inputs.
- Fixed `Editor`'s `ListView(children: [...])` eagerly building every block (both axes independently flagged this against `architecture/risks.md` #1/#3); switched to `ListView.builder`.
- Fixed a Divergent-Change P2 (Standards axis): extracted the active-note draft-state domain (`NoteMetadata`, `NoteState`, the in-memory cache, `set_node_at_path`) out of `api::ffi_api` into a new `rust/src/draft.rs` leaf module, matching `containers.md`'s framing of draft-state management as distinct from the FFI bridge. Regenerated FRB bindings; updated Dart imports accordingly.
- Documented (not fixed) the search result cap (`LIMIT 50`, no pagination) in both the contract and implementation, and a second facet of the open→save wiring gap (`open_note`'s path-based id vs. `notes.id`'s UUID shape) alongside the existing `base_revision` note.
- See `tasks/completed/EPIC-B-ui-database.md`'s "Post-PR-review fixes (round 2)" note for full detail.

## v1.2.2
PR #4 dual-axis review, round 1.
- Fixed a real architectural defect (P1, Standards axis): `db::connection` and `security::keyring` imported `AppError` from the FFI-facing `api::ffi_api` module, an upward dependency `architecture/containers.md` explicitly rules out for those containers. Moved `AppError` into a new shared leaf module (`rust/src/error.rs`); `api`, `db`, and `security` all depend on it inward now. Also corrected `containers.md`'s Local Repository entry, which claimed "Depends on: None" despite always having called into Secure Storage for the root key.
- Fixed two duplicated-code P2s (Standards axis): `renderInline`'s identical Link/ExternalLink arms, and the repeated DB-singleton-acquire-and-lock preamble in `search_notes`/`save_note` (now a shared `with_connection` helper).
- Fixed an unclear-error P2 (Spec axis): `save_note` on an unknown note id now reports `AppError::IoError` instead of a raw `DatabaseError` surfaced from `rusqlite::Error::QueryReturnedNoRows`.
- Documented (not fixed, no reachable path exists yet) a real latent inconsistency both review axes independently found: `open_note`'s placeholder `base_revision` and `save_note`'s DB-sourced `expected_base_revision` are not the same token yet, since `open_note` never touches the `notes` table. Added explicit comments at both ends instead of inventing the open→edit→save wiring this epic never scoped.
- See `tasks/completed/EPIC-B-ui-database.md`'s new "Post-PR-review fixes (round 1)" note for full detail.

## v1.2.1
Post-closeout correction for Epic B, prompted by a request to actually visually verify the shipped UI rather than rely solely on `flutter test` assertions against fakes.
- Discovered and fixed a real regression in `lib/src/components/editor.dart`: multi-run paragraphs (any paragraph mixing plain text with a bold/italic/code/strikethrough run, or containing a Link) were silently made editable via `TextField` alongside single-run ones, and `_paragraphStyle` only reads the first run — so the field displayed the whole paragraph in one flattened style, dropping every other run's formatting even before any edit. This directly regressed `UIDB-B006`'s own bold-rendering Gherkin and was invisible to all six existing widget tests, since every test paragraph happened to be single-run. Fixed by gating paragraph editability on a new `_isSingleTextRun` check; multi-run and Link-containing paragraphs now correctly stay read-only via `renderBlock`. Added a regression test (`a multi-run paragraph stays read-only and keeps each run's distinct styling`).
- Discovered, separately, that `flutter run -d linux` crashed on startup with no code involved: `flutter_rust_bridge`'s generated Dart loader expects `rust/target/release/librust.so`, but no ticket's Verification Command through Epic A or B ever ran `cargo build --release` or `flutter run` — every gate exercised either the Rust half alone (`cargo build`/`cargo test`) or the Dart half against fakes (`flutter test`), so the actual compiled app had never once been launched. Documented the fix (`cargo build --release` from `rust/`) and the underlying gap in `tech-spec/guidelines.md`'s new "Running the real app" section.
- Added `grim` (screenshot) and `wtype` (keystroke injection) to `devenv.nix` as standing Wayland-only manual-QA tooling, so rendered output can be inspected directly rather than only through widget-test property assertions.
- See `tasks/completed/EPIC-B-ui-database.md`'s `UIDB-B007` section for the full write-up, and `tech-spec/guidelines.md` for the standing workflow note.

## v1.2.0
- Completed **Epic B: UI & Database** (`UIDB-B001`–`UIDB-B007`), total 23 story points: OS Keychain root-key generation, SQLCipher-encrypted SQLite (raw-key PRAGMA, no PBKDF2), schema initialization with FTS5 search, `search_notes`/`save_note`/`update_block` exposed across the FFI boundary, Riverpod provider wiring, and a hybrid Markdown editor widget with live keystroke streaming back to the Rust core.
- Archived `EPIC-B-ui-database.md` to `.constitution/tasks/completed/`. Recomputed the active backlog to 16 story points (Epic C only); `SYNC-C001` and `SYNC-C002`'s dependencies on `UIDB-B004`/`UIDB-B005` are now satisfied, so Epic C is front-of-line.
- Ran the Constitution Freshness & Reconciliation Pass: corrected `architecture/containers.md` and `prd/capabilities.md` to distinguish OS-level (raw Markdown files) from application-level SQLCipher (SQLite index) at-rest encryption, corrected `architecture/flows/flow-edit-note.md` to accurately describe `update_block`'s full-NoteState return and flag the not-yet-implemented Markdown-serialize/commit-to-disk phase, and annotated `architecture/risks.md` risk #6 to record that `save_note`'s OCC currently guards only the database's `last_modified` bookkeeping, not file content. See `architecture/changelog.md` v1.0.1 and `prd/changelog.md` v1.0.1.
- Recorded deferred follow-ups (not blocking, tracked for future tickets): no Markdown serializer/write-through exists yet for `save_note`; the `Editor` widget is fully built and tested but not yet mounted in `main.dart` (no note-open or search UI exists in the running app); paragraph editing collapses to a single plain-text run per keystroke (rich multi-run inline editing, and list/heading/blockquote editing, remain out of scope); inline links are dropped from the AST on the first edit of a paragraph that contains them; `Image.asset` cannot load real note images (placeholder only).

## v1.1.0
- Completed **Epic A: Scaffolding & Core Engine** (`CORE-A001`, `CORE-A002`, `CORE-A003`), total 10 story points.
- Monorepo scaffolded using `flutter_rust_bridge` (v2), Markdown AST parser implemented with `pulldown-cmark`, and AST/FFI API contracts exposed across the FFI boundary to Dart.

## v1.0.1
- Recorded Phase 0 (tooling readiness), executed ahead of `CORE-A001`. It provisions the reproducible `devenv` environment and the pre-commit quality gates; it adds no application code and consumes no story points, so the critical path and totals are unchanged.
- Every file it introduces falls outside the `Scope (In-Scope Files)` of Epics A/B/C by design. `CORE-A001` keeps `Dependencies: None`, but its verification commands are now expected to run inside the devenv shell, per the Toolchain section of `tech-spec/guidelines.md`.
- Added a note to `CORE-A001`: FRB scaffolds vendored third-party Dart under `rust_builder/cargokit/`, which must be excluded via `analyzer.exclude` in `analysis_options.yaml` or the `dart analyze` gate will fail on code the project does not own.
- Corrected the `UIDB-B002` acceptance criterion, which asserted AES-256-GCM. SQLCipher 4.x is AES-256-CBC with HMAC-SHA512 page authentication; see `tech-spec/stack.md` v1.0.1.

## v1.0.0
- Initial formulation of the execution constitution.
- Created active backlog totaling 52 Story Points.
- Sequenced work into Desktop-first phased delivery (Epic A: Scaffolding, Epic B: UI/DB, Epic C: Security/Sync).
- Mapped Build Order diagram and defined critical path.
