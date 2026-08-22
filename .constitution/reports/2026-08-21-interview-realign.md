# Interview record — Realign, 2026-08-21

This record captures a full-sweep Realign interview. The goal: widen and deepen a constitution the user judged too shallow, written against an earlier revision of the stage-skill instructions, and bring it into compliance with the current output contracts. The codebase and constitution are current for Epics A through D, and Epics E and F are active, so the audit ran as a Brownfield diff plus Evolution scoping for all deferred work. Each ruling records what was decided and why, so later sessions can honor the decisions without asking again. Companion register: `2026-08-21-open-decisions.md`.

## Audit findings accepted as realignment scope

- The deferred half of the product has placeholder-grade specifications. `flow-sync-push.md` and `flow-conflict-resolution.md` predate ADR-005/006/007 by their own banners, and Epics G/H/I exist only as deferral paragraphs with recorded contract-shaped debts.

- Compliance gaps against the current stage-skill instructions: `vision.md` lacks the Archetype block; `constraints.md` doesn't use Planguage form; the Stage 1 domain model uses C4 vocabulary; `containers.md` lacks its required structure diagram; flows fall short of one per P0 capability; `flow-search.md` and `flow-workspace-bootstrap.md` lack failure paths; risks carry no STRIDE notes despite real trust boundaries; `guidelines.md` doesn't document a commit convention; version markers on `strategy.md` and `stack.md` lag their changelogs; active-epic tickets lack explicit Acceptance Mode tags.

- Small drifts: README.md uses glossary-forbidden vocabulary ("Notion-like hybrid editor") and overstates provider scope, and `rust/src/api/simple.rs` is absent from the guidelines layout tree.

## Rulings

### Connected lifecycle

- **Q1: Authorize-then-clone.** A second device runs the OAuth flow, selects the existing repository instead of provisioning a new one, and clones it. The clone becomes the Workspace. This completes the clone path that ADR-005 decision 2 reserves.

- **Q2: Detach is a real operation.** Removing the remote flips `workspaces.provider` back to `'local'`; all history stays on the device, and reconnecting re-adds the remote. Unpushed commits simply remain local commits. Sign-out alone doesn't cover this case.

- **Q3: Provider-neutral seam.** GitHub ships first. GitLab is required scope at priority P1 (set at B5), and the seam must make any further Git provider additive. There is no GitLab out-of-scope entry. Consequence: Epic G contracts can't hard-code GitHub provisioning shapes.

### Suggestion lifecycle (Epic H direction)

- **Q4: Block-level Suggestions** support independent accept/reject, matching the domain model as written. A Note can be partially resolved.

- **Q5: Unresolved Suggestions persist as conflict markers on disk.** The UI materializes them as Suggestions and never shows raw marker text. Resolution is never forced, and no sidecar store is allowed because a sidecar misrepresents the files to the Agent actor.

- **Q6: Delete-versus-edit resolves through restore plus Suggestion.** Rejecting performs a real deletion with CAP-LIFE-04-style confirmation.

- **B3: Markers flow freely through commits and pushes.** Sync never blocks on resolution; resolution is just a later edit. The ambient indicator gains a distinct pending-Suggestions state.

### Epic I surface

- **Q7: Attachments live in a single bundle-root `assets/` directory**, referenced bundle-absolutely exactly like Note Links. Research confirmed that Open Knowledge Format (OKF) v0.2 defines no asset convention, so this conflicts with nothing. Asset Directories that hold no Notes stay out of the tree view.

- **Q8: Export ships three forms.** The tree copy stays P0 as contracted. A single-file `.okf` zip archive joins it at P0; OKF §3 explicitly names "a tarball or zip archive of the directory" as a distribution form. A self-contained HTML rendition enters at P1 and waits until burlmd's design system exists. The user chose bare `.okf` over the recommended `.okf.zip` double extension and accepted the consequence: the file has no OS association until someone registers a unified type identifier (UTI) or media type.

- **Q8 research basis:** a subagent verified against the canonical SPEC.md that the format doesn't define renditions, publishing, or hosting; "serving" appears only as deferred future work in §12. Google Cloud Knowledge Catalog serving is product-side, not spec-defined. The reference tooling's self-contained `viz.html` is the informal precedent the HTML rendition follows. Zero Content Telemetry applies to the rendition: an offline artifact with no CDN scripts.

### Quality gates

- **Q9: Continuous integration (CI) runs as a Linux and macOS matrix.** Consequence owned: macOS moves from unverified to a real work item, covering the `bundled-sqlcipher` Security/CommonCrypto linking difference, the duplicate clang, and smoke-harness degradation on macOS.

### Cross-cutting gaps (all previously unnamed)

- **Q10: Undo uses a Core-side command stack** over content mutations such as splice, block, and range operations, with depth capped near 100 steps. Lifecycle renames and everything sync applied are excluded; reverting a remote peer's change is conflict resolution, not undo. New capability at P1.

- **Q11: Diagnostics combine a local structured log (`tracing`, rotating file) with a redacted copy-diagnostics export.** Telemetry upload is rejected and gets an out-of-scope entry.

- **Q12: This wave ships an explicit rescan affordance** backed by a full `reindex_workspace`. Live file-watching is registered as a future P1 capability behind the recorded batch/removal indexing gap, and auto-reconcile follows later under its own interaction ruling.

### Constraint meters (new, in Planguage form)

- **Q13: Corpus scale.** Goal 10k Notes, Stretch 50k, Fail 1k.

- **Q14: Cold start.** Goal 1 second, Fail 3 seconds. The user set the Goal deliberately below the suggested 2 seconds to force optimization over neglect. Idle resident memory caps at 400 MB with 10k Notes open. Both meters can be rebaselined once Epic E makes them measurable.

- **Q15: Sync freshness.** Online pushes land within 60 seconds of a commit, the Remote polls every 60 seconds, and offline backoff caps at 15 minutes.

- **Q16: A nightly benchmark job verifies all meters** once CI lands in Epic I. It reports regressions without blocking merges.

### Capabilities surfaced by the workflow walkthrough

- **Q17: Per-Note version list and restore, P1.** Restore routes through `reload_note` with the destructive-prompt confirmation pattern. A full diff viewer waits until someone asks.

- **Q18: In-Note find and replace, P1,** specified against the existing inline span map. Replace-all wants one atomic multi-range operation; Stage 3 decides its shape.

- **Q19: Preferences ship through a dedicated interactive design epic.** The user was explicit that this epic is human-driven design work, not agent-driven widget assembly. Stage 4 must express it through `hitl_sil` and `visual_regression` acceptance modes rather than Gherkin by default.

### Audience breadth standards

- **Q20: Accessibility baseline.** Keyboard completeness is a hard review bar, and Flutter `Semantics` labels are a standing coding standard. Screen-reader certification is explicitly deferred; see OD-02.

- **Q21: i18n-ready.** Strings externalize through Flutter `gen-l10n`; no translation effort is scheduled. Recorded separately as a finding that needs no decision: IME/CJK composition surviving focus promotion needs an acceptance criterion on `EDIT-F002`.

### Phase B branch resolutions

- **B1: Archetype.** Primary System/Native, Secondary Mobile, confidence high. The user's qualifier goes verbatim into intent: mobile matters, but desktop gets nailed first; Flutter is built responsive-by-construction while mobile surfaces remain open work rather than pre-designed.

- **B2: Guided consolidation** (the user's own middle ground). Connecting initializes the repository empty, then assists migrating non-conflicting Notes from a previous local bundle. Collisions resolve three ways: keep mine, keep theirs, or keep both through rename, which is cheap because the `links_rewrite` machinery exists. The source archive is never modified. Migrated Notes receive fresh history ("Import N Notes"), and commit-graph merging stays out of scope. New capability, run once at connect or setup time.

- **B4: Foundations become documentation now and retrofit later.** Theme, i18n, and Semantics standards become binding text in this realignment, while scaffolding tickets land in a later wave (wave unpinned; see OD-01). The accepted cost: review obligations during Epics E and F.

- **B5: GitLab sits at P1, sequenced behind GitHub** as the proven surface. It lands in Wave 3, outside Epic G.

- **B6: Wave 3 runs two genuinely parallel tracks:** the sync/conflict backbone and the interactive design epic. Stage 4 must draw the handoff points explicitly, with design tokens feeding indicator and editor surfaces, instead of assuming parallelism is free.

## Vocabulary notes for downstream stages

The Stage 1 pass adds these glossary entries: Consolidation, Bundle Archive (`.okf`), Rendition, Diagnostics Export. One repair belongs to ordinary repo work rather than `.constitution/`: fix README.md's forbidden vocabulary. It's noted here so it isn't lost.