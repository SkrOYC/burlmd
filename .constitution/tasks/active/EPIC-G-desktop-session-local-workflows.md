---
version: v2.1.21
status: active
epic: G
---

# Epic G: Desktop session and local workflows

Complete the PR #11 shell as a real local-first desktop application. This epic removes presentation-only Platform chrome, persists device and Workspace state separately, makes every tab authoritative, completes orderly closure, and surfaces the remaining local editing and discovery capabilities.

**Capability coverage:** CAP-PREF-01, CAP-SHELL-02, CAP-SHELL-03, CAP-SHELL-04, CAP-SHELL-05, CAP-SHELL-06, CAP-SHELL-07, CAP-SHELL-08, CAP-WS-13, CAP-FIND-02, CAP-FIND-03, CAP-GRAPH-05, CAP-EDIT-08, CAP-HIST-01.

**Total Effort:** 71 story points

**M0 authorization:** M0 authorizes `SHELL-G001`, `PREF-G002`, `STATE-G003`, `TABS-G004`, `CLOSE-G005`, and `NAV-G007` to write production code. M0 defers the remaining Epic G tickets in this epic. Every other production ticket remains blocked.

##### M0 Deviations & Justifications
- **Touched Files:** README.md, .constitution/tech-spec/stack.md, .constitution/tech-spec/data-models/schema.sql, .constitution/tech-spec/data-models/okf-bundle.md
- **Justification:** Review found restated production-stop and version banners outside the original M0 file list. Those copies would instruct executors to stop the authorized Epic G tickets.

#### SHELL-G001 Remove emulated Platform chrome
- **Type:** Chore
- **Effort:** 3
- **Dependencies:** None
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/design/workspace_shell.dart`
  - `lib/src/design/burl_theme.dart`
  - `lib/src/providers/burl_preferences_provider.dart`
  - `lib/src/components/visual_parity_fixture.dart`
  - `test/goldens/**`
  - `lib/l10n/**`
  - `test/**`
  - `integration_test/**`
  - `scripts/visual-regression.sh`
- **Scope (Out-of-Scope Files):**
  - `linux/**` and `macos/**` (the Platform already owns real chrome; don't add a replacement)
- **Verification Command:** On Linux, this command is the executable gate: `flutter test && dart analyze && ./scripts/visual-regression.sh shell-g001 --baseline test/goldens/shell-g001-linux.png --max-different-pixels 0 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`. Before SHELL-G011 closeout or release, run this command on a live Apple Silicon macOS host: `flutter test && dart analyze && ./scripts/visual-regression.sh shell-g001 --baseline test/goldens/shell-g001-macos.png --max-different-pixels 0 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`. Do not capture or fake macOS goldens on Linux.
- **Expected Success Output:** exit 0 and a smoke capture showing only host-owned window chrome
- **STOP Conditions:**
  - STOP if any production or executable test surface still selects, renders, or labels emulated macOS/Linux chrome; remove the obsolete contract instead of hiding it.
- **Description:** Remove the Platform-chrome preference, state, widgets, localized copy, fixtures, tests, and executable visual assumptions introduced for prototype presentation. Preserve design provenance only in non-executable documentation.
- **Acceptance:**
  - **Mode:** visual_regression
  - **Evidence:**

```text
The rebuilt `test/goldens/` Linux and macOS shell baselines contain no simulated traffic lights, Linux title controls, Platform selector, or reserved fake-titlebar spacing. The named verification commands allow zero different pixels. Production and executable tests contain no preference or code path that recreates them. CAP-SHELL-04 passes with host-owned chrome.
```

##### SHELL-G001 Deviations & Justifications
- **Touched Files:** `.constitution/tasks/active/EPIC-G-desktop-session-local-workflows.md`, `devenv.nix`, `scripts/smoke-shot.sh`
- **Justification:** Record the M0 P2 path (`okf-bundle.md`) in the existing M0 deviation list so the recorded scope matches commit dad33d8 / this follow-up. The executable Linux visual gate now owns a pinned headless Sway compositor and receives smoke-shot's launched PID through an inherited FD bound to a private gate-owned file; this eliminates active-desktop windows, focus, geometry, input, desktop noise, and caller-path symlink races from exact capture provenance.

#### PREF-G002 Persist device-global preferences
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** None
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/providers/burl_preferences_provider.dart`
  - `lib/src/design/**`
  - `lib/src/screens/workspace.dart`
  - `test/providers/**`
  - `test/screens/**`
- **Scope (Out-of-Scope Files):**
  - Workspace Notes and Git history (preferences never enter Workspace content)
- **Verification Command:** `flutter test && dart analyze && ./scripts/smoke-shot.sh pref-g002 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Expected Success Output:** exit 0 with restart tests passing
- **STOP Conditions:**
  - STOP if persistence requires storing appearance or update choices in the Workspace; keep them device-global.
- **Description:** Persist theme, font scale, prose measure, focus mode, and update-notification choices through the Platform application-state seam defined by `device-preferences.schema.json`, with atomic replacement and corrupt- or unknown-version fallback.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given each supported device preference has been changed
When the application process restarts
Then every preference is restored on that device
And no Workspace file or Git change contains the preference
```

PREF-G002 implements round-trip restore tests, corrupt- and unknown-version fallback tests, and an exclusion check that no Workspace or Git path contains these keys.

##### PREF-G002 Deviations & Justifications
- **Touched Files:** `pubspec.yaml`, `pubspec.lock`, `lib/l10n/**`, `linux/flutter/generated_plugins.cmake`, `.constitution/tasks/active/EPIC-G-desktop-session-local-workflows.md`
- **Justification:** Device-preference JSON persistence uses `path_provider` for Platform application-support. Flutter regenerates the Linux plugin cmake when that dependency is added. Localization strings for the new update-notification control live in `lib/l10n/**`. This task file records the test-scope deviation.

#### STATE-G003 Persist versioned per-Workspace session snapshots
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** None
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/providers/search_provider.dart`
  - `rust/src/db/**`
  - `rust/src/workspace/**`
  - `rust/src/api/ffi_api.rs`
  - `rust/src/frb_generated.rs`
  - `lib/src/rust/**`
  - `test/providers/**`
- **Scope (Out-of-Scope Files):**
  - Note bodies, credentials, and device-global preferences
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh state-g003 && git diff --check`
- **Expected Success Output:** exit 0 with schema, fallback, and provider restore tests passing
- **STOP Conditions:**
  - STOP if a snapshot can become authoritative Note/session state or contain Note content or secrets.
- **Description:** Implement the Core-owned `workspace-session-snapshot.schema.json` contract and its active-Workspace FFI for versioned, atomic snapshots of open Note identities, active Note, tree expansion, last search state, and synchronization presentation.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
STATE-G003 implements round-trip, Workspace-partition, atomic-replace, corrupt-fallback, and content, credential, and device-preference exclusion tests.
```

##### STATE-G003 Deviations & Justifications
- **Touched Files:** `lib/src/providers/rust_api_provider.dart`, `lib/src/providers/note_providers.dart`, `lib/src/components/workspace_tree.dart`, `lib/src/screens/workspace.dart`, `lib/src/components/lifecycle_actions.dart`, `test/components/lifecycle_actions_test.dart`, `scripts/check-generated-bindings.sh`, `test/widget_test.dart`, `test/screens/workspace_mounting_test.dart`, `test/screens/workspace_rescan_test.dart`, `test/components/editor_test.dart`, `.constitution/tasks/active/EPIC-G-desktop-session-local-workflows.md`
- **Justification:** The Rust API wrapper lets provider tests use a Core fake. The Note provider persists an active identity only after Core opens or retires a session. The tree reads Core-restored expansion state, and the screen publishes a restored active identity after the shell listener mounts. Existing shell fakes return an empty session snapshot. The generated-binding validation script was absent and is required by this ticket's verification command. Lifecycle rename/move paths rekey the snapshot with the operation's explicit old id when no editor session is mounted.

#### TABS-G004 Replace visual-only tabs with authoritative Note sessions
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** STATE-G003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/design/workspace_shell.dart`
  - `lib/src/providers/note_providers.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/screens/workspace.dart`
  - `scripts/smoke-shot.sh`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Canonical AST and path implementation owned by Epic H
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && BURLMD_SMOKE_TABS_G004=1 ./scripts/smoke-shot.sh tabs-g004 && git diff --check`
- **Expected Success Output:** exit 0 and a smoke capture with multiple Core-backed tabs
- **STOP Conditions:**
  - STOP if Flutter invents or restores a writable Note session that Core doesn't own.
- **Description:** Bind every tab to a Core Note session, restore available tabs and the active Note, skip missing Notes with one report, and apply the following-then-preceding selection rule after an active close.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given the `BURLMD_SMOKE_TABS_G004` scenario stages several Core-backed open Notes and one missing Note
When the Workspace is restored and the active tab later closes
Then available Notes reopen as Core sessions
And the missing Note is reported without blocking startup
And focus moves to the following tab or the preceding tab at the end
```

##### TABS-G004 Deviations & Justifications
- **Touched Files:** `lib/main.dart`, `lib/l10n/**`, `lib/src/components/lifecycle_actions.dart`, `test/components/editor_test.dart`, `test/screens/workspace_rescan_test.dart`, `.constitution/tasks/active/EPIC-G-desktop-session-local-workflows.md`
- **Justification:** The smoke scenario must save its Core-backed snapshot before `WorkspaceScreen` restores it. Lifecycle actions retire stale Core sessions, reconcile invalidated tab states, and select a surviving tab after a lifecycle deletion. The localized startup report names unavailable saved Note identities once. Existing shell, editor, and rescan tests now verify Core-backed tab selection instead of visual-only tab behavior.

#### CLOSE-G005 Serialize every Note-close and batch-close lifecycle
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** TABS-G004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/design/workspace_shell.dart`
  - `lib/src/providers/note_providers.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `rust/src/workspace/persist.rs`
  - `test/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Remote shutdown synchronization owned by Epic L
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh close-g005 && git diff --check`
- **Expected Success Output:** exit 0 with all close-entry and partial-batch scenarios passing
- **STOP Conditions:**
  - STOP if any tab button, middle click, shortcut, Close Others, Close All, Workspace switch, or orderly shutdown removes a tab before Core returns its terminal close outcome.
- **Description:** Route all close entry points through one serialized coordinator. Continue after clean success; remove and stop on a retired-session warning; retain failed and unprocessed tabs on error; cancel the enclosing switch or shutdown after any non-clean outcome.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
For every close entry point and injected result sequence, processed Notes preserve input order, no two closes overlap, clean sessions disappear, warned retired sessions disappear and stop the batch, failed/unprocessed sessions remain writable, and a wider switch or shutdown proceeds only after an entirely clean batch.
```

#### OPEN-G006 Restore and explicitly switch the active Workspace
- **Type:** Feature
- **Deferred:** M0 defers implementation. **Owner:** `PREFLIGHT-H007`.
- **Effort:** 8
- **Dependencies:** CLOSE-G005, PREFLIGHT-H007
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/screens/workspace.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `rust/src/workspace/bootstrap.rs`
  - `test/screens/**`
  - `integration_test/**`
- **Scope (Out-of-Scope Files):**
  - Preflight validation and repair rules owned by Epic H
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh open-g006 && git diff --check`
- **Expected Success Output:** exit 0 with startup, picker, switch, and cancellation flows passing
- **STOP Conditions:**
  - STOP if switching bypasses CLOSE-G005 or permits two active Workspaces.
- **Description:** Reopen the last Workspace at startup, expose Open Workspace, run adoption preflight, restore its session snapshot, and keep the previous Workspace active when close or adoption fails.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given one Workspace is active with open Notes
When the Writer selects another valid Workspace
Then the first Workspace completes its serialized close lifecycle
And exactly one Workspace becomes active
And its own saved session state is restored
```

#### NAV-G007 Surface keyboard title jump and backlinks
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** TABS-G004
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `lib/src/components/**`
  - `lib/src/providers/search_provider.dart`
  - `lib/src/providers/note_providers.dart`
  - `test/components/**`
- **Scope (Out-of-Scope Files):**
  - Search/index algorithms already owned by Core
- **Verification Command:** `flutter test && dart analyze && ./scripts/smoke-shot.sh nav-g007 && git diff --check`
- **Expected Success Output:** exit 0 with keyboard and backlink navigation tests passing
- **STOP Conditions:**
  - STOP if the UI reimplements title matching, Link resolution, or backlink queries.
- **Description:** Add a keyboard title-jump surface over the existing Core path and a backlinks surface for the open Note, preserving authoritative tab/session selection.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given indexed Notes and inbound Links
When the Writer searches a title or activates a backlink using only the keyboard
Then Core supplies the candidates and target
And the selected Note opens in an authoritative tab
```

#### EDIT-G008 Implement Core-owned undo and redo
- **Type:** Feature
- **Deferred:** M0 defers implementation. **Owner:** `ADAPT-H004`, `CI-M003`.
- **Effort:** 8
- **Dependencies:** TABS-G004, ADAPT-H004, CI-M003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/draft.rs`
  - `rust/src/markdown/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/providers/note_providers.dart`
  - `lib/src/components/editor.dart`
  - `test/components/**`
- **Scope (Out-of-Scope Files):**
  - Lifecycle and synchronization operations, which aren't undo entries
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh edit-g008 && git diff --check`
- **Expected Success Output:** exit 0 with operation-stack and keyboard tests passing
- **STOP Conditions:**
  - STOP if the final AST contract after AST-H001 changes operation identity or inverse requirements; reconcile this ticket before implementation.
- **Description:** Implement the bounded Core command stack across splice, structural, range, and replace-all edits, with redo invalidation, tier-1 durability, and platform keyboard actions.
- **Acceptance:**
  - **Mode:** invariant
  - **Evidence:**

```text
For every covered content operation, applying undo restores byte-identical prior source and authoritative caret/tree state; redo restores the forward state; a divergent edit clears redo; close/reload clears the stack; lifecycle and sync changes never enter it.
```

#### FIND-G009 Implement in-Note find and atomic replace
- **Type:** Feature
- **Deferred:** M0 defers implementation. **Owner:** `EDIT-G008`, `ADAPT-H004`, `CI-M003`.
- **Effort:** 8
- **Dependencies:** EDIT-G008, ADAPT-H004, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/markdown/**`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/editor.dart`
  - `lib/src/providers/note_providers.dart`
  - `test/components/**`
- **Scope (Out-of-Scope Files):**
  - Workspace-wide search
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh find-g009 && git diff --check`
- **Expected Success Output:** exit 0 with match navigation and one-operation replace-all tests passing
- **STOP Conditions:**
  - STOP if Flutter computes source ranges or replace-all dispatches a sequence of independently visible mutations.
- **Description:** Find matches through the canonical Note model, navigate them in the editor, replace one, and replace all as one durable undoable operation.
- **Acceptance:**
  - **Mode:** contract_test
  - **Evidence:**

```text
Fixtures cover inline syntax, nested Blocks, Unicode, empty/no-match cases, single replacement, and replace-all. Core returns every range and one authoritative post-replace state; replace-all creates exactly one undo entry and no intermediate render state.
```

#### HIST-G010 Surface and restore local Note history
- **Type:** Feature
- **Deferred:** M0 defers implementation. **Owner:** `ADAPT-H004`, `CI-M003`.
- **Effort:** 5
- **Dependencies:** TABS-G004, ADAPT-H004, CI-M003
- **Category:** Feature-Evolution
- **Scope (In-Scope Files):**
  - `rust/src/git/operations.rs`
  - `rust/src/api/ffi_api.rs`
  - `lib/src/components/**`
  - `lib/src/providers/note_providers.dart`
  - `test/**`
- **Scope (Out-of-Scope Files):**
  - Full historical diff viewer
- **Verification Command:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh hist-g010 && git diff --check`
- **Expected Success Output:** exit 0 with list, confirm, restore, and asset-rehydration handoff tests passing
- **STOP Conditions:**
  - STOP if restore silently discards an unwritten draft or depends on a full diff viewer.
- **Description:** List session-granularity Note versions, show timestamps/messages, confirm destructive restore, create a new current history state, and request referenced Object hydration without rewriting earlier history.
- **Acceptance:**
  - **Mode:** gherkin
  - **Evidence:**

```gherkin
Given a Note has local session versions and an unwritten draft
When the Writer selects an earlier version
Then burlmd requires confirmation
And after confirmation restores it as the current source with recoverable history
And requests any referenced Object that is not locally hydrated
```

#### SHELL-G011 Integrate and harden the feature-complete local shell
- **Type:** Feature
- **Deferred:** M0 defers implementation. **Owner:** `OPEN-G006`, `FIND-G009`, `HIST-G010`.
- **Effort:** 8
- **Dependencies:** SHELL-G001, PREF-G002, OPEN-G006, NAV-G007, FIND-G009, HIST-G010
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/design/**`
  - `lib/src/screens/workspace.dart`
  - `lib/src/components/**`
  - `lib/l10n/**`
  - `test/goldens/**`
  - `test/**`
  - `integration_test/**`
  - `scripts/visual-regression.sh`
- **Scope (Out-of-Scope Files):**
  - Assets, Remote sync, and release surfaces owned by later epics
- **Verification Command:** On Linux, this command is the executable gate: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/visual-regression.sh shell-g011 --baseline test/goldens/shell-g011-linux.png --max-different-pixels 0 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`. Before SHELL-G011 closeout or release, run this command on a live Apple Silicon macOS host: `cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/visual-regression.sh shell-g011 --baseline test/goldens/shell-g011-macos.png --max-different-pixels 0 && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`. Do not capture or fake macOS goldens on Linux.
- **Expected Success Output:** exit 0 with the local feature matrix and reviewed visual evidence passing
- **STOP Conditions:**
  - STOP if any pointer action lacks keyboard reachability, Writer-facing string bypasses localization, or state shown by the shell isn't authoritative.
- **Description:** Integrate the completed local workflows into the delivered design system, finish keyboard/focus/Semantics/localization coverage, and rebuild visual evidence after Platform-chrome removal.
- **Acceptance:**
  - **Mode:** visual_regression
  - **Evidence:**

```text
The Linux executable gate compares its capture with the named `test/goldens/` baseline at a zero-different-pixel threshold. Before SHELL-G011 closeout or release, the Apple Silicon macOS command runs on a live Apple Silicon host and compares its own capture with the named macOS baseline. Do not capture or fake macOS goldens on Linux. Together with integration logs, the gates cover preferences, restored tabs, every close path, Workspace switch, title jump, backlinks, undo/redo, find/replace, and history restore. The shell preserves PR #11 design parity without fake Platform chrome, unreachable actions, hardcoded Writer-facing copy, or nonauthoritative placeholder state.
```
