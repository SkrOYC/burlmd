# Epic E: Shell & Navigation

Makes the application usable. Epic D produces a working Core with nothing on screen: the editor widget exists but has never been mounted, and every launch shows a login screen that cannot currently be passed. This epic removes that gate and builds the surfaces that reach a Note — a Directory tree, navigation, lifecycle actions, search, and draft recovery.

Every ticket here changes what the user sees, so every Verification Command launches the real application. That standard exists because no ticket through Epic B ever did, and a rendering regression shipped past six passing widget tests as a result.

That makes `SHEL-E001` a 2-point ticket gating twelve of this wave's fourteen UI tickets, on tooling (`grim`/`wtype`) that `tech-spec/guidelines.md` records as Wayland-only and outside every build path. Its STOP condition already forbids substituting a widget-test assertion if capture proves impossible, and the consequence of hitting it is stated here rather than left implicit: the twelve dependent gates degrade to `flutter test` alone, which is the exact blind spot this standard exists to close, so hitting it is a signal to fix the harness or change platform — not to proceed with weaker gates.

#### SHEL-E001 Manual-QA Smoke Harness
- **Type:** Chore
- **Effort:** 2
- **Dependencies:** None
- **Category:** DX
- **Scope (In-Scope Files):**
  - `scripts/smoke-shot.sh`
  - `devenv.nix`
  - `.gitignore` (adds `.qa/`. Twelve later tickets each write a screenshot there, and a repository whose stated premise is readable plaintext diffs should not accumulate PNGs — nor should every UI ticket leave the tree dirty.)
- **Scope (Out-of-Scope Files):**
  - `lib/**`
  - `rust/src/**`
- **Verification Command:** `./scripts/smoke-shot.sh harness-selftest && test -s .qa/harness-selftest.png`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the harness cannot capture a screenshot in this environment; report the limitation rather than substituting a widget-test assertion, because substituting one recreates exactly the blind spot this ticket exists to close."
- **Description:** Provide the repeatable command every subsequent UI ticket uses as its gate. It builds the native library in release mode (required because the generated loader resolves it from a path the debug bundle does not populate), builds and launches the desktop application, waits for it to render, captures a screenshot to a known location, and terminates cleanly with a non-zero exit if the application failed to start. The screenshot tooling is already provisioned in the developer environment for this purpose; this ticket turns an ad-hoc procedure documented in `tech-spec/guidelines.md` into a command.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a clean checkout in the developer environment
When the smoke harness is run with a name
Then the application builds, launches, is screenshotted to a file under that name, and the process exits zero

Given the application fails to launch
When the smoke harness is run
Then it exits non-zero and no screenshot is written
```

#### SHEL-E002 Open Directly Into the Workspace
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** WSPC-D004, SHEL-E001
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/main.dart`
  - `lib/src/screens/workspace.dart` (created here as the minimal shell this ticket's screenshot asserts on; `SHEL-E003` fills it with the tree)
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/providers/rust_api_provider.dart`
  - `test/widget_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/screens/login.dart` (retained for the deferred connect flow; not deleted)
  - `lib/src/providers/auth_provider.dart`
- **Verification Command:** `flutter test && ./scripts/smoke-shot.sh e002-workspace-opens`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if removing the gate requires deleting the login screen or the auth provider; both remain for the deferred connect flow and only stop being a startup gate."
  - "STOP if any editing, navigation or search surface remains reachable only when authenticated; CAP-WS-01 requires none of them be."
- **Description:** Remove the authentication gate from application startup. The application opens the local Workspace on launch and presents it directly. Authentication state governs synchronization only, and no editing capability depends on it. This is the change that makes the application usable at all — it is currently unusable end to end, for a reason that is a specification defect rather than a bug.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given no credentials exist in secure storage and no network is reachable
When the application is launched
Then the Workspace is presented and no login screen appears

Given the application has been launched with no credentials
When a screenshot is captured
Then it shows the Workspace shell rather than a login prompt

Given the application is restarted
When it opens
Then the same local Workspace is reused rather than recreated
```

#### SHEL-E003 Directory Tree Sidebar
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D009, SHEL-E002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/workspace_tree.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `lib/src/screens/workspace.dart`
  - `test/components/workspace_tree_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/editor.dart`
- **Verification Command:** `flutter test test/components/workspace_tree_test.dart && ./scripts/smoke-shot.sh e003-tree`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the tree holds Note content in widget state; `tech-spec/guidelines.md` permits only ephemeral UI state such as which nodes are expanded."
  - "STOP if rendering the tree requires one call per Directory level; the contract returns the tree in a single call."
- **Description:** Render the Workspace as a nested, expandable Directory tree and open a Note when one is selected. This is the primary navigation surface — without it no Note is reachable after being written. Directories sort before Notes at each level. Empty Directories appear, which is why they are indexed at all.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Workspace with nested Directories and Notes
When the tree is rendered
Then each level lists Directories before Notes, sorted by name

Given a Directory containing no Notes
When the tree is rendered
Then that Directory still appears

Given a collapsed Directory
When it is expanded
Then its children appear without a further Workspace-wide reload

Given a Note in the tree
When it is selected
Then that Note opens
```

#### SHEL-E004 Mount the Editor and Navigate
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D008, SHEL-E003
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/screens/workspace.dart`
  - `lib/src/components/editor.dart`
  - `lib/src/providers/note_providers.dart`
  - `test/components/editor_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/workspace_tree.dart`
- **Verification Command:** `flutter test test/components/editor_test.dart && ./scripts/smoke-shot.sh e004-editor-mounted`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if switching Notes does not close the outgoing Note through the Core; leaving it unclosed skips the commit tier and loses the session from version history."
  - "STOP if an error returned across the boundary is swallowed rather than surfaced; the editor currently has no error surface at all."
- **Description:** Mount the editor for the first time. Selecting a Note in the tree opens it and renders its Blocks; switching to another Note closes the outgoing one through the Core so its session is written and committed. Failures crossing the boundary are surfaced rather than discarded — a gap the review of Epic B recorded but left unreachable because the editor was never mounted.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Note is selected in the tree
When it opens
Then its Blocks render as formatted output

Given a Note with unsaved edits is open
When a different Note is selected
Then the outgoing Note is closed through the Core before the new one opens

Given the Core returns an error when opening a Note
When the editor handles it
Then the failure is shown to the user rather than silently ignored

Given a Note has been opened in the running application
When a screenshot is captured
Then its rendered content is visible
```

#### SHEL-E005 Note and Directory Lifecycle Actions
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** WSPC-D006, SHEL-E004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/workspace_tree.dart`
  - `lib/src/components/lifecycle_actions.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `test/components/lifecycle_actions_test.dart`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**` (the Core surface already exists)
- **Verification Command:** `flutter test test/components/lifecycle_actions_test.dart && ./scripts/smoke-shot.sh e005-lifecycle`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if deletion is offered without confirmation."
  - "STOP if a rejected name collision is worked around client-side by altering the name; the Core reports the path unavailable and the user must be told."
  - "STOP if `LifecycleEffects.rewritten` is ignored. Those Notes' ids did not change and nothing about them looks stale, which is exactly why the Core returns the list — an open one holds a Link to an id that no longer exists, and following it recreates the concept the rename removed."
- **Description:** Surface creation, rename, move and deletion for Notes, and creation, rename and deletion for Directories. Because a rename or move changes a Note's identity, the open Note must re-anchor to the returned state rather than retaining its previous identifier. Moving is available at least through an explicit action; drag-and-drop is not required.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Directory is selected
When a new Note is created in it with a title
Then it appears in the tree and opens for editing

Given a Note is open and is renamed
When the rename completes
Then the tree shows the new title and the open editor remains anchored to the same Note

Given a title collides with an existing Note
When creation is attempted
Then the conflict is reported to the user and no Note is created

Given a Note is selected for deletion
When deletion is confirmed
Then it disappears from the tree and the editor closes it

Given a Note is moved to another Directory
When the move completes
Then it appears under the new Directory in the tree

Given a Note from inside a Directory is open
When that Directory is renamed
Then the open Note re-anchors using the id remapping the Core returns, rather than holding a dead identifier

Given Note B is open and contains a Link to Note A
When A is renamed
Then B reloads, because `LifecycleEffects.rewritten` names it — B's own id did not change, so nothing looks wrong, but its in-memory AST still carries A's old `target_id`

Given B was not reloaded after such a rename
When its stale Link is followed
Then the failure this criterion exists to prevent is visible: the create-on-follow path recreates the concept the rename removed

Given the Block containing that Link is the focused one in B
When A is renamed
Then B's editable field is refreshed from the returned state before the next keystroke — otherwise `update_block` substitutes the pre-rewrite source back and reverts the rename

Given a Note is open
When its containing Directory is deleted
Then the editor closes that Note rather than leaving it open against a removed file
```

#### SHEL-E006 Search Surface
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** WSPC-D009, SHEL-E004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/search_panel.dart`
  - `lib/src/providers/search_provider.dart`
  - `test/components/search_panel_test.dart`
- **Scope (Out-of-Scope Files):**
  - `lib/src/components/workspace_tree.dart`
- **Verification Command:** `flutter test test/components/search_panel_test.dart && ./scripts/smoke-shot.sh e006-search`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if the result limit is hardcoded in the UI; the Core takes it as a parameter precisely so the surface controls it."
- **Description:** Give full-text search a surface for the first time. Search is scoped to the current Workspace, returns ranked results with snippets, and opens a Note when a result is selected. Results must remain responsive within the sub-100ms constraint, so queries are issued against the index rather than filtered client-side.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a Workspace containing Notes with distinct content
When a query matching one of them is entered
Then that Note appears in the results with a snippet

Given a search result is shown
When it is selected
Then the corresponding Note opens

Given a query matching no Note
When it is entered
Then an empty state is shown rather than an error

Given a query containing punctuation such as hyphens and parentheses
When it is entered
Then results or an empty state are shown and no error surfaces
```

#### SHEL-E007 Recovered Draft Surface
- **Type:** Feature
- **Effort:** 2
- **Dependencies:** WSPC-D007, SHEL-E004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `lib/src/components/draft_recovery.dart`
  - `lib/src/providers/workspace_provider.dart`
  - `test/components/draft_recovery_test.dart`
- **Scope (Out-of-Scope Files):**
  - `rust/src/**`
- **Verification Command:** `flutter test test/components/draft_recovery_test.dart && ./scripts/smoke-shot.sh e007-draft-recovery`
- **Expected Success Output:** `exit 0`
- **STOP Conditions:**
  - "STOP if recovered content is discarded when the user dismisses the notice; dismissal hides the notice, it does not delete work."
  - "STOP if a write-tier failure is left unsurfaced. `note_write_status` exists because the write tier's trigger is a Core-owned timer with no caller to return an error to; if nothing polls it, `RevisionMismatch`, `DiskFull` and `IoError` are raised into nothing while the user keeps typing into a buffer nothing can persist."
- **Description:** Make crash recovery visible, and write failure visible with it — the two share a surface because both are the application telling the user something about durability that it cannot say through the editor itself. On startup, Notes carrying an unflushed draft from a previous session are surfaced so the user knows work was recovered rather than silently finding a Note in an unexpected state. Opening such a Note shows the recovered content, and the state carries the fact that it came from a draft.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a draft exists from a session that ended without flushing
When the application starts
Then the affected Note is surfaced as having recovered work

Given a recovered Note is opened
When it renders
Then it shows the drafted content rather than the last content written to disk

Given the recovery notice is dismissed
When the Note is opened afterwards
Then the recovered content is still present

Given the write tier fails with a revision mismatch on an open Note
When the UI next polls its write status
Then the failure is shown, and the user is offered a reload rather than a retry — the file changed underneath the draft, so retrying would overwrite it

Given that reload is accepted
When it completes
Then the Note re-renders from disk and the write status clears — the offer calls `reload_note`, not `open_note`, which would restore the surviving draft and reproduce the mismatch on the next tick

Given that reload is offered
When the user has not yet chosen
Then their buffered text is still reachable, and the confirmation says plainly that reloading discards it — `reload_note` destroys unwritten work by design, and this is the only prompt in the application that does

Given the write tier fails because the disk is full
When the UI next polls
Then the failure is shown persistently rather than once, since every subsequent write fails the same way until it is resolved
```
