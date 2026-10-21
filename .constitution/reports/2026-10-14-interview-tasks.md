# Tasks interview for the private Linux roadmap

## Status and source

This full Tasks interview is complete. It records rulings and the required upstream routing for a later planning pass. It does not rewrite the active epic graph or authorize product implementation. At interview closure, generation-stage approval remained pending. The post-interview authorization at the end of this record approves the four ordered realignment stages.

The inspected baseline is merged `master` at `2c6de152d2a84a82bdb85f2395db00a308fcca64`. The working checkout remains the historical `feat/epic-g-desktop-session` branch. Do not mistake its stage files for the inspected baseline or discard this interview record with obsolete work.

The user selected the full interview rather than a quick pass. Four GPT-5.6-Sol reconnaissance agents inspected the complete remaining Tasks surface read-only. No spikes were authorized. Ask one question at a time, with context, a precise question, and options. The user subsequently requested a complete Markdown-related feature checklist for selection together; this is an exception to the one-question-at-a-time format for that syntax inventory only.

## Established constraints

The following directions remain in force:

- Prioritize the sole user's private Linux checkout and dependable local use.
- Preserve data safety, privacy, editing fidelity, and portable on-disk format.
- Keep packaging, public supported releases, and non-Linux qualification deferred.
- Plan explicit epic dependencies and generate waves. There is no blanket one-epic-at-a-time rule; concurrent epics must be scope-disjoint.
- Keep completed epics and their history intact. Assess obsolete branches separately from the reviewed code on merged master.
- Use Sol agents, never Astra. The lead orchestrates and validates.
- Follow `google-style` and never hardwrap Markdown prose. Keep each paragraph on one source line.
- Run application verification headlessly. Clean disposable builds and worktrees after use.
- Do not overwrite or install hooks without approval. Devenv owns their configuration; the restored hook still references the removed G checkout.

## Reconnaissance summary

The baseline has eight active epics, 67 planned tickets, and 482 open points. Its rendered waves form a width-one chain. This is not a reliable readiness claim: several first tickets still require dormant M003 qualification.

The material findings are:

- H/I/L research and P observation retain managed multi-platform gates that contradict the approved private Linux delivery boundary.
- G's deferred Workspace switching, undo/redo, find/replace, and history outcomes need explicit active or deferred ownership in the replacement plan.
- I combines local Assets with remote Object Store work. J combines Export with connection-time Consolidation. N combines several distinct Remote and Object lifecycle flows. O combines local diagnostics/migration with releases.
- Every active epic claims `test/**` and the shared FFI file. Narrowing dependencies alone cannot make those scopes safely concurrent.
- Forward contracts and live-verification recipes remain provisional. Stage 4 must not invent missing interfaces, algorithms, or failure/cancellation states.
- Native validation reports 24 TS-001 command-resolution errors and 13 legacy warnings. Existing tool paths were used without activating devenv or hooks. These results are not a clean validation pass. Review-round calibration is also incomplete because its generated counter uses commit subjects.

These findings come from the baseline's PRD, Architecture, TechSpec, active epics, latest Tasks changelog, open-decisions register, and source inspection. No additional runtime verification was performed during reconnaissance.

## Rulings

### Local usability precedes synchronization acceptance

Question: Must private Remote synchronization be part of the first usable milestone?

Options presented:

1. Local usability first. Synchronization follows; independent Remote groundwork may run in parallel where the approved graph permits it.
2. Local usability and private synchronization together. A local-only milestone would not satisfy the first-usable target.

The user chose option 1 and explained that exercising synchronization is separate from local usage, so the two make sense as separate outcomes.

Ruling: Define the first usable milestone through local Linux workflows. Remote synchronization and its integration evidence are a separate delivery outcome, not prerequisites for accepting local usability. This does not delete the longer-term synchronization vision or introduce false dependencies between independent work.

### Fresh Workspace for first use

Question: Does the first usable version need the user's existing Markdown collection, or can it start with a fresh Workspace?

Options presented:

1. Fresh Workspace first, with safe adoption of existing collections later.
2. Existing collection required, making safe inspection and adoption part of first-usable acceptance.

The user chose the fresh-Workspace path. They plan to migrate their collection manually, rewriting Notes to meet burlmd's requirements rather than requiring burlmd to retrofit the collection.

Ruling: Automatic import, inspection, repair, and adoption of an arbitrary existing collection are not prerequisites for the first usable milestone. This does not remove the longer-term adoption capability or weaken conformance, portable paths, or preservation of any Notes already created through burlmd.

### One collection for the first usable version

Question: Does the first usable version need one collection, or the ability to create and switch between separate collections?

Options presented:

1. One collection first, organized with directories inside one Workspace.
2. Separate collections from the start, with safe closing and session restoration when switching Workspaces.

The user chose one collection and reserved multiple collections for a later version.

Ruling: Workspace creation/selection/switching interfaces for multiple collections are not prerequisites for the first usable milestone. Keep directory organization within the single collection. This does not remove the longer-term switching capability or justify changing delivered Workspace-partitioned storage and session safety.

### Complete editing undo and redo

Question: Must undo and redo cover every editing operation included in the first usable version?

Options presented:

1. Yes, with dependable Note-level undo and redo required for first use.
2. Later, with the initial limitation stated explicitly.

The user chose option 1.

Ruling: Every content-editing operation delivered in the first usable version must participate in dependable Note-level undo and redo, including operations across Block boundaries. Per-field undo, draft recovery, and local Version history are not substitutes. This does not add rename, move, delete, or other Workspace lifecycle operations to editing undo; their recovery semantics remain separate under ADR-010.

### Find and replace within a Note

Question: Which in-Note search tools must the first usable version include?

Options presented:

1. Find matches and navigate between them, with replacement following later.
2. Find and replace, including replacing one match and replacing all matches as one undoable operation.
3. Defer in-Note tools and retain Workspace-wide search initially.

The user chose option 2.

Ruling: First-usable acceptance includes finding matches within the open Note, navigating matches, replacing one match, and replacing all matches. Replace-all is one operation in the Note-level undo and redo history. Workspace-wide search is already delivered and is not a substitute for these tools.

### Defer the saved-Version recovery interface

Question: Must the first usable version let the user recover a Note from its saved history?

Options presented:

1. List previous saved Versions and restore a selected Version after confirmation, without a full history-diff viewer.
2. Continue recording local history, but defer browsing and restoring it through the app.

The user chose option 2.

Ruling: Preserve delivered local history capture and its durability behavior. The first usable milestone does not require an in-app Version browser or restoration workflow. Note-level undo and redo remain required and are not replaced by this history deferral. The longer-term Version recovery capability remains in the roadmap.

### Local images in the first usable version

Question: Must images work in the first usable version?

Options presented:

1. Add local images to Notes and display them offline, keeping cloud storage and synchronization separate.
2. Deliver a text-only milestone and add images later.

The user chose option 1.

Ruling: The first usable milestone includes adding local images to Notes and displaying them offline. Plan local Asset storage and rendering independently of Remote synchronization and cloud Object Store integration. Preserve the binding integrity, containment, portable-reference, and offline-availability requirements. This ruling does not select an implementation package or decide which image-input methods are required.

### Image input through file selection and clipboard paste

Question: Which image-input methods must the first usable version support?

Options presented:

1. File selection and clipboard paste, with drag-and-drop deferred.
2. File selection, clipboard paste, and drag-and-drop together.
3. File selection only, with the other methods following later.

The user chose option 1.

Ruling: First-usable image input includes selecting a local file and pasting an image from the clipboard. Drag-and-drop remains a later capability. Both included input paths must produce the same safe local Asset behavior, preserve offline availability, and participate in the required editing undo and redo semantics.

### Automatic local external-change detection with KIS scope

Question: How will the user use external editors or agents while burlmd is open?

Options presented:

1. Detect local external changes automatically and handle overlapping edits safely.
2. Allow local external changes with explicit Rescan or reload rather than automatic detection.
3. Use external tools only while burlmd is closed initially, deferring live-change handling.

The user chose option 1 and added the explicit constraint "but KIS."

Ruling: The first usable milestone must detect changes made by local editors or agents while burlmd is open. Do not make this depend on Remote synchronization or release qualification. Keep the implementation and user workflow simple without weakening conformance, containment, revision checks, or preservation of competing versions. Manual Rescan remains a recovery path, not the normal substitute for automatic detection. The existing preserve-and-review architecture remains binding; this ruling does not add automatic merging or settle the scope of guided repair tooling.

### Flag and preserve invalid external changes

Question: How should the first usable version handle external changes that violate burlmd's required metadata or path rules?

Options presented:

1. Explain the problem, preserve the incoming bytes and last valid Note, and let the user or their agent correct the file without a built-in repair wizard.
2. Preview proposed corrections and apply them only after approval, preserving the original bytes.

The user chose option 1.

Ruling: Invalid external changes must be detected, flagged, and kept outside authoritative editable state. Preserve the incoming bytes and any last known-good Note without silent repair or loss. The user or their agent corrects the file. Guided repair tooling is not required for first-usable acceptance, and this deferral does not weaken guest-input validation or data preservation.

### Plain-folder Export in the first usable version

Question: What Export support must the first usable version include?

Options presented:

1. Defer in-app Export and copy or back up the collection externally after closing burlmd.
2. Export a consistent copy of Notes and referenced images to another folder, with archives deferred.
3. Include both plain-folder Export and a single-file archive.

The user chose option 2.

Ruling: First-usable acceptance includes plain-folder Export of a consistent Workspace revision with its Notes and referenced local images. Preserve the existing flush, revision, complete-output verification, destination-safety, and failure-preservation requirements. Single-file archives are not required for this milestone. Export must not depend on Remote synchronization or a cloud Object Store when the complete required image bytes are local.

### Minimal local Diagnostics Export

Question: Must the first usable version include a built-in Diagnostics Export?

Options presented:

1. Provide clear, actionable errors first and add diagnostic reports later.
2. Keep bounded, content-free local diagnostics and let the user explicitly export a minimal troubleshooting report.

The user chose option 2.

Ruling: First-usable acceptance includes minimal local diagnostics and a user-requested Diagnostics Export with application/schema versions, errors, retries, and failures. Keep retention and storage bounded. Exclude Note and Asset content, credentials, signed locations, and content-derived metadata. Do not upload or share reports automatically, and do not let logging failure become a product failure. This is separate from plain-folder Workspace Export and does not require a release pipeline.

### Tables and footnotes are essential

Question: Does the delivered Markdown baseline cover first-use needs, or are additional constructs essential?

Options presented:

1. Keep the delivered baseline with the already-selected first-use features and expand syntax support later.
2. Name additional constructs required before using burlmd for real work.

The user stated that tables and footnotes are very important and requested a full Markdown-related feature checklist rather than discovering syntax requirements one at a time. They clarified that this request concerns Markdown features, not every application feature.

Ruling: Tables and footnotes are first-use requirements. Do not treat limitations of the delivered rendering projection as the intended Markdown scope. Include both constructs in the selected-syntax, editing, undo, find/replace, source-fidelity, and rendering acceptance work. The following checklist records the user's priorities and delivery cutoff for additional Markdown features.

### Markdown feature priorities and delivery cutoff

The user requested a Markdown-only checklist and assigned the priorities below. Keep delivered basic editing, existing Note links, and the already-selected local images, tables, and footnotes. The labels below are interview choices, not new ticket identifiers. These are feature priorities, not pull-request finding severities. Features beyond existing product scope need explicit upstream treatment before task generation. Included features need usable rendering and source editing, with the required undo and find/replace behavior where applicable; this does not imply a separate visual editing tool for every construct.

| Choice | Feature | Priority |
| --- | --- | --- |
| M1 | Task lists and interactive checkboxes | P0 |
| M2 | Reference-style links and reusable link definitions | P0 |
| M3 | Automatic links for bare URLs and email addresses | P1 |
| M4 | Links to headings and sections within Notes | P0 |
| M5 | Syntax highlighting for code blocks | P0 |
| M6 | Safe static rendering of raw HTML, without scripts | P2 |
| M7 | HTML comments hidden when reading but editable in source | P2 |
| M8 | Editing YAML frontmatter and custom metadata within the editor | P1 |
| M9 | Inline and display mathematical notation | P0 |
| M10 | Mermaid diagrams | P0 |
| M11 | Callouts, alerts, or admonitions | P1 |
| M12 | Collapsible details sections | P2 |
| M13 | Definition lists | P2 |
| M14 | Highlighted text syntax | P0 |
| M15 | Superscript and subscript | P1 |
| M16 | Emoji shortcodes | P2 |
| M17 | Citations and bibliographies | P1 |
| M18 | Note outline or generated table of contents | P1 |
| M19 | Visual table controls for adding/removing rows and columns | P2 |
| M20 | Images referenced by web URL, separate from required local images | P0 |
| M21 | Custom element IDs and attributes | P2 |

Question: Which priority levels must be delivered before the first usable version?

Options presented:

1. P0 required first; P1 next; P2 later.
2. P0 and P1 required first; P2 later.
3. Priorities indicate ordering only; decide the delivery cutoff separately.

The user clarified: "P0 is for the first usable version, P1 is next, once it works, P2 after that."

Ruling: All eight P0 checklist features are required for the first usable version, alongside the previously selected local requirements, including tables and footnotes. Deliver the six P1 checklist features in the next increment once that version works, followed by the seven P2 features. P1 and P2 do not block first-use acceptance. This staging applies to the Markdown checklist; it does not establish the ordering of synchronization against the later Markdown increments.

The checklist distinguishes CommonMark/GFM syntax from additional dialect extensions and editor aids; it is not a claim that every dialect or plugin is covered. The existing rejection of on-disk wiki-style links remains in force. The `[[` insertion affordance stores ordinary Markdown links instead. Raw unsupported source must remain byte-preserved regardless of whether its rendering feature is selected.

Grounding checked on October 14, 2026: [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/), [GFM specification](https://github.github.com/gfm/), [GitHub formatting documentation](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax), and [Pandoc Markdown extensions](https://pandoc.org/MANUAL.html#pandocs-markdown). No parser/library choice follows from these references.

### Synchronize Notes and images together

Question: Must the first usable synchronization milestone include images?

Context: Synchronization is separate from first-use local acceptance. The existing design synchronizes Notes through a private GitHub repository and local images through a separate storage service controlled by the Writer.

Options presented:

1. Notes and images together, so the real collection can synchronize without missing images.
2. Text-only synchronization first, with image synchronization later. Collections containing local images cannot connect until image synchronization is ready.

The user chose option 1.

Ruling: The first usable synchronization milestone must include both Notes and local images. Text-only synchronization does not satisfy that milestone. Preserve the existing requirement to verify protected image availability before publishing connected history. Local image use remains independent of Remote and Object Store connection.

### Resolve concurrent content edits inside burlmd

Question: Must in-app conflict resolution work in the first synchronization milestone?

Context: Two devices can edit the same passage while offline. The existing design preserves both versions and presents Suggestions that the Writer resolves inside burlmd.

Options presented:

1. Require in-app resolution, so synchronization handles conflicting edits end to end rather than only the happy path.
2. Initially preserve both versions and pause synchronization, requiring resolution outside burlmd. Deliver in-app Suggestions later.

The user chose option 1.

Ruling: The first usable synchronization milestone includes in-app resolution of concurrent content edits through Suggestions. Preservation followed by external-only resolution is not sufficient. Keep both variants recoverable and retain the existing distinction between content Suggestions, Lifecycle Decisions, and Asset Decisions. This ruling does not replace those separate structural and image-conflict requirements.

### Defer combining independent collections

Question: When is combining Notes from separate local collections required?

Context: Connecting the existing local collection publishes it to a Remote. Joining that same collection on another device downloads it and enables synchronization. Combining independent collections instead imports Notes and images from a different collection, resolves identity or destination collisions, and leaves the source collection unchanged. The existing CAP-070 describes this separate Consolidation workflow.

Options presented:

1. Defer combining independent collections. Keep connecting the single collection, joining it on another device, and resolving synchronization conflicts in the first usable synchronization milestone.
2. Include combining independent collections and resolving their collisions in the first synchronization milestone.

The user requested clarification, then chose option 1. This follows their earlier choice to start fresh with one collection.

Ruling: Consolidation of independent collections is a later delivery outcome, not a prerequisite for the first usable synchronization milestone. Connecting the existing collection, joining that same collection on another device, synchronizing Notes and images, and resolving concurrent content edits inside burlmd remain required. Preserve future Consolidation ownership rather than deleting its product intent.

### Defer image-store migration

Question: Must migration to a different image-storage service be ready in the first synchronization milestone?

Context: The existing CAP-057 includes both credential rotation for the configured Object Store and replacement of that store. Updating credentials keeps the existing connection usable. Replacing the store requires a separate migration that preserves images needed by Notes and retained history.

Options presented:

1. Defer service migration. Support one configured image store, including credential updates and safe handling of failures, then add migration afterward.
2. Include service migration from the start, verifying preservation of images needed by Notes and retained history.

The user chose option 1.

Ruling: The first usable synchronization milestone supports one configured Object Store, credential updates, and safe failure handling. Migration to another Object Store is a later delivery outcome. Preserve future replacement ownership and the existing no-loss requirement; this staging does not authorize destructive replacement or silent loss of historical images.

### Defer automatic image-cache cleanup

Question: Does the first synchronization milestone need automatic image-cache cleanup?

Context: CAP-058 permits removing eligible inactive local Object copies only after verifying a remote copy. Images used by current Notes remain available offline. This product feature is separate from cleaning disposable development builds and worktrees.

Options presented:

1. Defer automatic cleanup and retain downloaded images initially. This reduces initial complexity but uses more disk space.
2. Include safe removal of eligible local copies and later retrieval in the first synchronization milestone.

The user chose option 1.

Ruling: Automatic image-cache cleanup is a later delivery outcome, not a prerequisite for the first usable synchronization milestone. Retain downloaded image copies initially. Preserve offline availability and the existing requirements for verified remote copies before any future eviction. Continue cleaning unused development builds and worktrees as separately instructed.

### Return safely to local-only use

Question: Must the first synchronization milestone include a safe operation to disconnect and keep everything local?

Context: Pausing synchronization or signing out leaves the connection configured. Returning to local-only use requires verifying that Notes, history, and their images remain available without either remote service. The existing CAP-061, CAP-062, and CAP-068 distinguish these operations and preserve protected image availability.

Options presented:

1. Require safe disconnection to local-only use without losing access to the collection or its history. This does not delete remote data.
2. Defer disconnection. Initially allow pausing and signing out, but not removing the connection through burlmd.

The user chose option 1.

Ruling: The first usable synchronization milestone includes safe disconnection to local-only use, preserving Notes, local history, and all protected images. Keep the existing fresh-authority and verified-local-availability requirements for detaching both services. Do not conflate disconnection with pausing, signing out, or deleting remote data. If required verification or retrieval cannot complete, preserve the existing state rather than reporting complete disconnection.

### Prioritize synchronization before later Markdown increments

Question: After the P0 local version works, which outcome takes priority?

Context: Local first use and synchronization are separate outcomes. The selected Markdown order is P0, then P1, then P2. Their relationship to synchronization still needed a ruling.

Options presented:

1. P1 Markdown, then synchronization, then P2 Markdown.
2. Synchronization, then P1 Markdown, then P2 Markdown.
3. P1 Markdown, then P2 Markdown, then synchronization.

The user chose option 2.

Ruling: Prioritize delivery in this order: the P0 local first-usable version, the first usable synchronization milestone, P1 Markdown, then P2 Markdown. These priorities do not create technical dependencies between independent work. The approved epic graph may still permit scope-disjoint work in parallel. Preserve the previously agreed acceptance boundaries for each outcome.

### Initial collection size

Question: Roughly how many Notes will the collection contain after manual migration?

Context: The existing NFC-07 performance Goal is 10,000 Notes. The expected initial collection size informs first-use performance verification. Synthetic Notes can provide evidence without accessing private content.

Options presented:

1. Up to 1,000 Notes.
2. Between 1,000 and 10,000 Notes.
3. More than 10,000 Notes.

The user chose option 1.

Ruling: Plan around an initial collection of up to 1,000 Notes. This estimate informs a proposed first-use verification profile; it does not itself amend the 10,000-Note long-term Goal, select timing thresholds, or approve deferring existing performance requirements.

### Qualify first-use performance at the initial collection scale

Question: What performance evidence must block the first usable version?

Context: The existing 10,000-Note performance Goal exceeds the expected initial collection of up to 1,000 Notes. First-use qualification and larger-scale optimization can be separate outcomes without weakening data safety.

Options presented:

1. Qualify up to 1,000 synthetic Notes on Linux first, then qualify 10,000 later.
2. Require the full 10,000-Note performance target before first use.

Both options include editing responsiveness, search, opening the collection, and indexing rather than launch-only evidence. The user chose option 1.

Ruling: First-use performance qualification covers up to 1,000 synthetic Notes on Linux. Defer qualification at the existing 10,000-Note Goal to a later delivery outcome; retain that Goal and explicit future ownership. Preserve data-safety requirements. This ruling does not select replacement timing thresholds, Note-size distributions, or verification commands; those need an explicit upstream record before task generation.

### Pause after each completed wave

Question: Once a wave is approved, where must execution pause?

Context: The updated workflow groups independent, non-overlapping epics into generated waves. Each wave has an approved execution plan.

Options presented:

1. After the wave is implemented, reviewed, merged, and reconciled, before starting the next wave.
2. Before merging each epic's review-clean pull request, requiring approval for every merge within an approved wave.

Both options keep progress and remaining scope recorded in the repository. The user chose option 1.

Ruling: After approval of a wave plan, execute that wave through implementation, review, merge, and reconciliation. Pause before starting the next wave and obtain approval of its plan. Do not require a separate approval for each merge within the approved wave. Follow the execution skills and the plan's autonomy policy; this cadence does not authorize expanding scope or bypassing review, validation, hook restrictions, or other required approvals.

### Discard obsolete branch work after the interview

Question: For cleanup after this interview, must merged `origin/master` be the sole baseline?

Context: The working checkout remains on the historical G branch, and local `master` diverges from merged `origin/master`. Read-only inspection found an old constitution-migration snapshot unique to local `master`, three patch-equivalent local commits, a disposable hosted-prerequisite CI probe, and patch-equivalent receipt-contract work. The G branch also retains an alternate `.envrc`. Cleanup therefore discards obsolete unique work as well as merged copies.

Options presented:

1. Use merged `origin/master` as the sole baseline. Preserve this interview record, discard divergent local work, and delete the obsolete G, receipt-contract, and CI-probe branches locally and remotely where present. Create no archive branches or tags.
2. Retain the unmerged migration snapshot and CI probe for a separate review before deletion.

The user chose option 1.

Ruling: After this interview, align the checkout to merged `origin/master` and remove obsolete branch work without archive branches or tags. The approved targets are local `feat/epic-g-desktop-session`, the divergent commits of local `master`, remote `feat/epic-g-desktop-session`, remote `docs/receipt-artifact-integrity-contract`, and remote `chore/epic-m-hosted-prerequisite-probe`, with corresponding local branches only if present. Preserve this interview record and completed epic history on merged master. Recheck exact refs and working-tree changes before cleanup; unexpected new work is not covered by this approval. This ruling does not approve hook installation or modification.

### Regenerate hooks through devenv after checkout alignment

Question: After aligning the checkout, may the existing devenv configuration regenerate the hooks?

Context: The restored pre-commit hook still points to the removed G worktree. Hook rules already live in `devenv.nix`. Branch-cleanup approval does not override the user's separate restriction on hook changes.

Options presented:

1. Let devenv install the configured hooks after checkout alignment, then verify them. Do not manually edit hook files or change rules.
2. Leave hooks untouched and postpone commits until hook repair receives separate approval.

The user chose option 1.

Ruling: After aligning the checkout to the approved baseline, regenerate hooks through the existing devenv configuration and verify that they reference the intended checkout and valid configuration. This is approval for the configured installation, not for manual hook edits, rule changes, or bypassing hooks. Escalate unexpected conflicts instead of overwriting them by hand. No hook changes occurred during this interview.

### Track deferred outcomes without speculative implementation tickets

Question: How much detail must the replacement roadmap give deferred work?

Context: Multiple collections, history browsing, collection combining, image-store migration, cache cleanup, and 10,000-Note qualification are later outcomes. They need durable tracking without becoming prerequisites for earlier acceptance.

Options presented:

1. Track each deferred outcome with its scope and revisit condition. Create implementation tickets when the outcome approaches execution.
2. Write detailed epics and tickets for all deferred outcomes immediately, accepting that they may require replanning.

Both options retain deferred scope. The user chose option 1.

Ruling: Record deferred outcomes durably with scope and an explicit revisit condition. Do not create speculative implementation tickets for them now. Detail those tickets when the outcome approaches execution. Keep this delivery backlog distinct from the open-decisions register, which records unanswered decisions rather than features whose delivery has been postponed. Use the supported constitution structure; do not invent a new framework merely to represent deferrals.

## Phase A closure and Phase B grounding

The lead summarized the local-first, synchronization, and later-Markdown delivery map and asked whether any essential workflow was missing. The user chose to continue without adding another workflow. This closes the agreed full workflow sweep, not the interview or generation-stage approval.

Phase B resolves the remaining planning gaps. One parallel read-only grounding batch was dispatched to two GPT-5.6-Sol agents: Markdown dialect and pinned parser compatibility, and headless Linux live verification. Their briefs prohibit implementation, file edits, builds, application launches, hook activation, and Git or GitHub mutations. External findings remain unverified until the lead checks the sources. No spikes or generation passes were authorized by closing Phase A.

### Checked grounding findings

Both grounding agents completed read-only work without builds, application launches, or file changes. The lead checked the following findings against the baseline and primary documentation on October 14, 2026. These checks do not select an implementation stack or settle the open canonical-AST decision.

- Markdown: `rust/Cargo.toml` pins `pulldown-cmark` 0.12.2. `rust/src/markdown/parser.rs` enables strikethrough, task lists, and document-start YAML metadata, but not tables, footnotes, or math. The pinned crate exposes additional syntax through flags and event types; library support is not delivered application support. The existing image projection uses `Image.asset`, not a working web-image or local-Note-image loader. [Pinned parser source, version 0.12.2](https://raw.githubusercontent.com/pulldown-cmark/pulldown-cmark/v0.12.2/pulldown-cmark/src/lib.rs).
- Dialects: CommonMark, formal GFM, GitHub formatting, and other Markdown extensions are not one interchangeable standard. GitHub interprets fenced `mermaid` source as a diagram; the delivered app instead renders code. Stage 3 must declare the selected syntax and rendering contracts rather than allowing Tasks to guess. [GitHub diagram documentation, retrieved October 14, 2026](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams).
- Headless verification: `scripts/visual-regression.sh` owns a private compositor and removes ambient display selection. `scripts/smoke-shot.sh` sets a temporary home and data tree but inherits other environment values, including any exported XDG configuration root. The production keyring uses fixed application service and account identifiers. Private filesystem paths alone therefore do not prove independent credential stores or complete user-state isolation. Treat the remaining isolation work as a prerequisite for future live recipes, not as permission to run against user configuration or credentials. No private data was accessed by this static inspection.
- Live recipes: the baseline guidelines front matter contains verification commands, layout, and commit convention, but no `live_verification` recipes. Stage 3 owns declaring the missing recipes and their isolation and evidence boundaries. Flutter 3.44.3 supports integration tests, but its built-in screenshot support names Android, iOS, and Web, not Linux. The Linux compositor capture and app-interaction driver must remain distinct, honest evidence mechanisms. [Flutter 3.44.3 integration-test README](https://github.com/flutter/flutter/blob/3.44.3/packages/integration_test/README.md), [Flutter integration-test guidance, retrieved October 14, 2026](https://docs.flutter.dev/testing/integration-tests).

## Phase B rulings

### macOS is P2

Question prompting the ruling: What must gate development of the private Linux version: repository tests, static checks, and isolated headless Linux workflows, or the existing hosted, signed multi-platform prerequisites?

The user instead directed: "Make macOS a P2."

Ruling: macOS support and qualification are P2 delivery scope. They do not block the first usable Linux version or the first usable synchronization milestone. Track macOS as a deferred outcome with scope and a revisit condition rather than detailed implementation tickets now. This changes macOS delivery priority; it does not establish whether private Linux milestones require local headless or hosted, signed evidence. Ask that narrower question before resolving the Linux evidence policy. Do not infer a change for other platforms.

### Use private headless Linux verification for development

Question: For private Linux development, which evidence must be required?

Options presented:

1. Tests, static checks, and isolated headless app workflows on the user's Linux machine. Defer hosted, signed release qualification.
2. Require hosted, signed Linux evidence before milestones can pass, with macOS still deferred to P2.

The user chose option 1.

Ruling: Gate private Linux development on repository tests, static checks, and isolated headless live workflows on the user's Linux machine. Hosted, signed release qualification is deferred and must not block these milestones. macOS remains P2. Do not claim hosted provenance, multi-platform support, or release qualification from private Linux evidence. Preserve data-safety checks and the prohibition on using the active desktop or private user content for verification.

### Load web images automatically when opening a Note

Question: When must burlmd fetch externally referenced images?

Context: The selected P0 web-image feature loads images from external servers, unlike imported local images.

Options presented:

1. Load only on an explicit request for a Note, showing placeholders initially to avoid unsolicited network requests.
2. Load automatically when opening a Note containing external images, contacting those servers without a separate action.

The user chose option 2.

Ruling: Automatically fetch externally referenced images when opening a Note containing them. Treat this as the selected feature's network behavior, not permission to upload Note content, transmit application credentials to image servers, or add telemetry. Keep external image references distinct from imported local Assets. Stage 2 owns the network and failure boundary; Stage 3 must declare supported schemes, redirect and resource limits, credential/referrer handling, and offline and Export semantics. This ruling does not itself select those technical policies or require automatic conversion of web images into local Assets.

### Prepare real-provider verification through OAuth before its wave

Question: When synchronization work is ready, how must authorization and test-resource setup be handled?

Context: Real synchronization verification needs dedicated private GitHub and image-store resources containing synthetic data. GitHub's device flow requires the user to authorize in a browser. Simulated services alone cannot prove the real-provider integration.

Options presented:

1. Arrange user authorization and test-resource setup before approving the relevant autonomous wave.
2. Use simulated services until the user is available, keeping real-provider verification incomplete and not declaring synchronization ready.

The user chose option 1 and added: "it must work through oauth."

Ruling: Prepare real-provider authorization and dedicated test resources before approving the relevant autonomous synchronization wave. Exercise burlmd's GitHub OAuth connection flow, not a pasted personal access token or inherited GitHub CLI authorization as a substitute. The existing GitHub App device flow is an OAuth flow; this ruling does not replace it with a different grant or require a callback server. Keep browser approval under the user's control. Do not request secrets in chat or use the user's real collection as test data. Image-store authentication remains a separate boundary under its existing contract; no new image-store authentication protocol is selected by this ruling. Exact resource targets and permitted creation, mutation, and cleanup must be recorded in the wave plan. Authorization expiry or revocation may require renewed user action; do not promise permanently unattended authorization.

Primary grounding checked October 14, 2026: [GitHub App user access tokens and device flow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token). The existing binding record is `tech-spec/adrs/ADR-017-github-app-device-flow.md`.

### Keep portable filename rules from first use

Question: Must the portable-format requirement remain in the first Linux version after moving macOS support to P2?

Context: The existing format requirements aim to keep the stored collection transferable between operating systems. Format compatibility and runtime support qualification are separate outcomes. Using unrestricted Linux-native filenames initially may require a collection migration later.

Options presented:

1. Establish portable filename rules from first use and defer macOS runtime qualification to P2.
2. Use Linux-native filenames initially, then address portability and any migration alongside macOS support in P2.

The user chose option 1.

Ruling: Retain portable filename rules as a first-use requirement. macOS runtime qualification remains P2 and must not become an execution prerequisite through the path spike. Do not invent a filename or collision algorithm in Tasks or claim that Linux fixtures prove macOS filesystem behavior. Stage 3 must adapt the evidence plan to the approved Linux-first scope while retaining the portability contract. OD-05 remains open until its evidence-based algorithm selection is actually completed.

## Existing open decisions retained

This interview does not select a parser, filename algorithm, image-size limit, or history-health threshold. The existing register on the inspected baseline remains authoritative and unchanged. No new unanswered decision was deferred or closed by evidence during this interview, so no register entries were added.

| Decision | Treatment before replacement planning |
| --- | --- |
| OD-02: screen-reader certification trigger | Preserve the existing deferral and register entry. Do not reopen certification as a first-use prerequisite. |
| OD-04: canonical Markdown model | Keep open. Update the research acceptance corpus for the selected first-use syntax through the owning stage, then plan evidence before dependent implementation. |
| OD-05: portable path algorithm | Keep open. Retain portability intent while removing macOS runtime qualification as a first-use prerequisite. |
| OD-06: imported-image size limit | Keep open with the existing provisional limit. Plan the required bounded measurement before treating a replacement limit as settled. |
| OD-07: history-health warning threshold | Keep open with its existing interim assumption. Do not silently settle or remove the warning because history browsing was deferred. |
| OD-08: supported Linux release baseline | Preserve for the deferred public-release scope; it does not block the private checkout's headless Linux workflows. |

## Ordered, bounded realignment route

Task generation cannot safely run immediately. The accepted priorities change product requirements, and the baseline lacks final contracts and live-verification recipes. The owning stages must resolve those gaps before Stage 4 consumes them. This is a delta to the existing constitution, not a full redesign or a rebuild of completed work.

1. Apply the separately approved checkout cleanup and devenv-managed hook regeneration. Recheck exact refs and preserve this record before discarding obsolete branch state. This operational step is outside interview write authority and has not run.
2. Run `defining-product-requirements` in Evolution mode. Record the selected Markdown priorities, Linux-first delivery boundary, synchronization acceptance, explicit deferrals and revisit conditions, initial performance qualification, web-image loading behavior, and macOS P2. Preserve stable identifiers, delivered capabilities, data safety, and the longer-term vision. Keep operator technology preferences separate from product requirements.
3. Run `designing-solution-architecture` in Evolution mode only for affected flows and trust boundaries. Align local versus connected image behavior, external-image network and failure behavior, selected editing operations, synchronization lifecycle and failure/cancellation paths, and the separation of deferred operations. Preserve unrelated boundaries. Do not design deferred features in detail merely because they are listed.
4. Run `specifying-technical-implementation` in Evolution mode. Declare private Linux live recipes and their remaining isolation prerequisites, real-provider OAuth verification boundaries, the 1,000-Note qualification profile, and the contracts required by active local and synchronization work. Adapt research gates to the selected syntax and Linux-first evidence policy. Preserve evidence-dependent choices as open until measured; do not invent final AST or path choices. Resolve command-validation compatibility and legacy sidecar drift through their proper owners rather than claiming validation is clean or bypassing it.
5. Run `planning-engineering-execution` only after those upstream changes are ready. Replace the active epic graph with reviewable vertical slices and explicit dependencies, then generate waves. Apply the delivery order of P0 local use, synchronization, P1 Markdown, and P2 Markdown. Keep macOS P2 and other deferred outcomes out of early execution prerequisites. Use narrow owned paths where they are real, not speculative concurrency scaffolding. Preserve completed epics and historical rulings. State calibration limitations rather than presenting the old 482-point estimate as a reliable forecast.

Each stage uses its own constitution-only pull request and document review, as its skill requires. Do not combine all layers into one approval-obscuring rewrite. Do not start product implementation during these passes. At execution time, approve one wave plan, complete its reviews, merges, and reconciliation, then pause before the next wave.

## Interview handoff

The only file written by this interview is `reports/2026-10-14-interview-tasks.md`. No stage files, product code, hooks, branches, or remote resources were changed. Both grounding agents finished; no spike was run. Preserve the interview as a constitution-only commit after the approved checkout and hook preparation. At interview closure, the next action was to ask for approval to begin the bounded Stage 1 Evolution pass. Do not run Stage 4 while its upstream inputs remain stale.

## Post-interview authorization for the realignment

After interview closure, the user approved all four ordered realignment stages and directed that every resulting `.constitution/` patch be part of one pull request. Each stage must remain aligned with the interview decisions and respect its write authority. Run the stages in pipeline order so each downstream layer reads the approved upstream result.

This ruling supersedes the earlier packaging instruction that assigned a separate pull request to each stage. It does not erase the ordered route, collapse stage ownership, or weaken per-stage validation and review requirements.

This authorization covers constitution changes from Stage 1 through Stage 4 in the single realignment pull request. It does not authorize product-code changes, global tooling repairs, validation exceptions, suppressed checks, or application implementation.
