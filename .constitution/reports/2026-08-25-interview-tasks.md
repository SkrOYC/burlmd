# Tasks interview record

**Date:** 2026-08-25
**Target:** Tasks
**Mode:** Brownfield discovery with forward Evolution scope

This record captures the full Tasks interview after pull request (PR) #11. The interview starts from the merged implementation and plans forward. It doesn't create a retrospective epic for the redesign. The Product Requirements Document (PRD), Architecture, Technical Implementation, and Tasks stages own the decisions identified in this record.

The next planning phase must make the redesigned desktop app complete for local use. It must then deliver private GitHub synchronization, including conflict resolution. The phase also produces installable `0.x` prereleases.

## Repository findings

- Epics A through F are complete. The active backlog and critical path are empty.
- PR #11 intentionally delivered the design system, responsive shell, preferences surface, localization, accessibility work, and visual test infrastructure before the next Tasks pass.
- PR #11 also left production behavior unfinished. Preferences don't persist. Tab state is partly visual. History, sync, and Suggestion surfaces contain presentation data that isn't connected to Core.
- Directory rename and delete already route through Core-backed lifecycle actions. Treat them as delivered behavior and preserve them through path-model and live-monitoring changes.
- Stage 4 describes Design and Preferences as deferred. Repository reality supersedes that narrative. Reconciliation must plan unfinished behavior, not repackage delivered design work.
- The production shell exposes fake macOS and Linux chrome through a user preference. The prototype used those controls only to present its design. The host platform must own window chrome.
- The Markdown model named `AstNode` is a small rendering and editing projection. It omits or flattens standard Markdown structure and must not remain the canonical Core model.
- The Git implementation reduces distinct conflicts to one error and assumes that every conflict produces working-tree markers. Git's merge model is materially broader.
- The active constitution contains no Amazon Simple Storage Service (Amazon S3)-compatible object-storage contract, although the product decision treats this storage as a primary binary asset boundary.

## Release outcome

The phase ends when the following outcome is true:

1. The redesigned desktop shell is behaviorally complete for local use.
2. A private GitHub Remote works through its complete lifecycle.
3. Markdown content conflicts appear as inline Suggestions.
4. Lifecycle and asset conflicts have dedicated reconciliation workflows.
5. Linux and Apple Silicon macOS pass the same release-blocking feature matrix.
6. GitHub Releases provide installable `0.x` prerelease artifacts.

GitLab doesn't enter this phase. It reopens only after the complete GitHub integration works.

## Forward-planning rulings

The following rulings bind the forward reconciliation and implementation plan.

### Redesign and platform chrome

- PR #11 is delivered foundation work. Stage 4 must not create a fictional past epic to account for it.
- Remove the production platform-chrome preference, state, rendering, copy, localization, and tests. The operating system owns window chrome.
- Remove emulated platform chrome from production and test-only executable surfaces. Preserve design provenance only in documentation or non-executable archived references.
- Rebuild affected visual evidence after removal. Deleting only the production widget leaves an obsolete design contract in fixtures, tests, and copy.

### Local shell completion

The following work is release-blocking:

- Persist theme, font scale, prose measure, focus mode, and update-notification choices.
- Route every tab-close entry point through Core close, flush, and history behavior. This includes the tab button, middle-click, keyboard command, **Close Others**, **Close All**, Workspace switch, and orderly shutdown.
- Run batch closes serially. On clean success, remove the tab and continue. On `CloseNoteWarning`, remove the tab because Core retired the session, report degraded durability, stop before unprocessed tabs, and cancel a Workspace switch or orderly shutdown. On an error, keep the failed and unprocessed tabs open, report the partial result, and cancel the switch or shutdown.
- Crash recovery remains the fallback when the operating system doesn't permit an orderly close.
- After a successful active-tab close, select the following tab in tab order or the preceding tab when no following tab remains.
- Replace visual-only tab state with authoritative Note sessions.
- Restore open tabs and the active Note after restart. Skip missing Notes and report them without blocking startup.
- Reopen the last Workspace at startup. Provide an explicit **Open Workspace** action. Only one Workspace is active at a time.
- Keep device-global appearance preferences separate from per-Workspace navigation and session state.
- Store open tabs, the active Note, tree expansion, last search state, and sync presentation per Workspace.
- Don't synchronize application preferences through the Note repository.

### Local capabilities

This plan includes all specified local capability gaps:

- Open an existing Workspace.
- Surface backlinks and keyboard title jump over their existing Core paths.
- Surface the delivered one-commit-per-edited-session Git history through `list_note_versions`, and implement confirmed `restore_note_version`. Preserve the existing commit behavior.
- Implement undo and redo.
- Implement in-Note find and replace, including atomic replace-all.
- Implement inline images.
- Keep a full historical diff viewer outside this phase. The external-change comparison surface is a narrower workflow.

### Export

- Include both plain-copy Export and the single-file `.okf` Bundle Archive.
- Export must flush every open Note through the normal durability path.
- Export must stop when an external-file collision is unresolved.
- Export must read one stable Workspace revision.
- Both forms must be atomic. Write to a temporary sibling destination, verify it, and rename it into place after success.
- Refuse nonempty copy destinations. Require confirmation before replacing an existing `.okf` archive.
- Don't present partial output as a successful Export.
- Defer Workspace-wide HTML Publishing. A single-Note HTML export is more useful, but it isn't part of this plan. The PRD must change before that form is scheduled.

### Existing Workspace conformance

The burlmd application is the authority for Workspace semantics. External editors and AI agents are guests that must follow the published contract.

- Run a conformance preflight before adopting a directory.
- Add conformant Notes to the authoritative index and editor.
- List invalid Notes and exclude them until the user chooses **Repair** or **Exclude**.
- Preview every repair. Don't rewrite foreign content silently.
- For an invalid live write, preserve the last known-good Note, pause writes to that Note, and offer **Repair**, **Compare**, or **Exclude**.
- Preserve the original bytes during resolution.
- Clarify CAP-WS-05, CAP-PORT-01, CAP-PORT-03, the Agent actor, and the OKF data model. Open storage doesn't make guest tools semantic authorities.

### Live Workspace monitoring

- Add live monitoring with debounced incremental reconciliation.
- Retain manual Rescan as a recovery path.
- If an open Note is clean, validate and index an external conforming change, record it in local history, and reload the Note.
- If an open Note has a dirty draft, pause writes and show an **External change detected** state.
- Offer **Compare**, **Keep burlmd version**, or **Load external version**.
- Preserve both versions before resolution and recheck the disk revision before applying the choice.
- Don't represent same-device file-cache conflicts as Git Suggestions.
- Use the same conformance and lifecycle rules for external create, rename, move, and delete operations.

The PRD, Architecture, and TechSpec only define explicit Rescan. They require Evolution passes before Stage 4 can schedule live monitoring.

## Canonical Note and Workspace models

Core owns the canonical Note and Workspace representations defined in this section.

### Core-owned extended AST

Core must own one canonical, source-backed, extended abstract syntax tree (AST) for every Note.

- Represent the selected CommonMark and GitHub Flavored Markdown schema exhaustively.
- Add burlmd domain nodes and fields for resolved and ghost Links, Suggestions, source spans, conformance, editable Block identity, images, and supported extensions.
- Make parsing and Flutter Rust Bridge serialization adapters around this model.
- Derive Flutter rendering from the canonical tree. Flutter must not own a second document model.
- Run structural edits, undo, find and replace, conflict resolution, rendering, and indexing against the canonical tree.
- Keep the original source buffer, AST, and source ranges as one coherent Core document state.
- Continue targeted source splices followed by reparsing. Don't serialize the whole AST and normalize untouched Markdown.
- Rename or remove the current `AstNode` claim unless that type becomes the exhaustive canonical schema.

### AST decision spike

Run an implementation-blocking Spike before content-model work. Compare the `markdown` crate's `mdast`, Comrak, and a complete model derived from `pulldown-cmark` events. The provisional default is `mdast`; OD-04 keeps the final foundation open until the Spike produces evidence.

The Spike must verify:

- Exact byte positions and untouched-source fidelity.
- CommonMark, GitHub Flavored Markdown, frontmatter, raw HTML, reference definitions, tables, footnotes, images, nested formatting, and malformed input.
- OKF Link classification and ghost resolution.
- Block paths, rendered selections, and range edits.
- Existing Note-size performance meters.
- Conflict representation and Flutter Rust Bridge projection cost.

The canonical Core model also contains a Workspace tree. Note ASTs belong to that tree. Directory, identity, and binary-object decisions must not be forced into Markdown nodes.

## Cross-platform Workspace paths

- Replace title-verbatim filename derivation and host-filesystem identity.
- Define one canonical on-disk path format that is unambiguous on Linux, macOS, and Windows.
- Windows is a storage-interoperability target, not an application release target.
- Keep the Note title in frontmatter. The on-disk path can use a canonical safe derivation.
- Reject nonconforming guest paths during preflight or live monitoring.
- Run a path Spike covering Unicode normalization, case equivalence, reserved device names, invalid characters, trailing dots and spaces, component and path limits, collision disambiguation, case-only renames, and ghost-Link creation. OD-05 keeps the exact algorithm open until this Spike completes.
- Test the algorithm on Linux and default macOS filesystems. Include Windows rules in the format contract.
- Reject symlink and submodule Notes and assets. Don't follow Remote-controlled paths outside the Workspace.

## Binary assets and S3-compatible storage

The asset model combines portable local paths with user-controlled object synchronization.

### Storage boundary

The first supported asset architecture combines Git with user-controlled S3-compatible object storage.

- Keep Notes, Directories, Links, and small textual manifests in Git.
- Keep every active image hydrated at a conforming bundle-root `assets/` path and reference it through standard bundle-absolute Markdown.
- Use canonical hash-derived filenames under `assets/` as the guest-visible, content-addressed Local Asset Store. Stage 3 defines the exact filename and manifest contracts after the asset Spike.
- Synchronize payloads to a user-controlled S3-compatible bucket.
- Keep the Local Asset Store sufficient for offline access to active assets.
- Don't operate a project bucket, content broker, or relay.
- Hydrate referenced objects into plain-copy and `.okf` Exports.
- Defer S3-only Workspaces until the hybrid model is proven.

### Bucket connection

Use a bring-your-own-bucket flow:

- Collect endpoint, region, bucket, and Workspace prefix.
- Collect narrowly scoped access credentials.
- Store secrets in operating-system secure storage. Exclude them from Git and diagnostics.
- Validate list, read, write, and delete operations.
- Reject anonymously readable storage.
- Use content-addressed keys under the Workspace prefix.
- Don't mutate bucket policies or provision cloud accounts.
- Keep local Note work available when S3 is unavailable.

### Image import and lifecycle

- Support file picker, clipboard paste, and drag-and-drop insertion.
- Copy imported bytes into the bundle-root Local Asset Store under `assets/`. Don't depend on the source file.
- Use 25 MiB as the provisional per-image limit. OD-06 delegates the final limit to the asset Spike, which must measure decoding, caching, memory, and sync costs.
- Don't add Git Large File Storage (Git LFS) in this phase.
- Copy referenced assets during Consolidation.
- Deduplicate byte-identical objects.
- Route same-logical-reference and different-byte cases through Asset Decisions.

### Reachability and deletion

- Treat a conforming AST reference as the authority for active asset use.
- Protect objects reachable from the current tree; every commit reachable from the Workspace active branch, local or unpushed branches, every `refs/heads/*` and `refs/tags/*` ref in the attached Remote, or local tags; the merge base, local side, and incoming side of pending reconciliation; or Consolidation state. Provider-internal refs, reflog-only commits, and otherwise unreachable commits aren't protected history.
- Don't prune reachable Git history in this phase. An object referenced by any protected commit remains authoritative regardless of age.
- After 30 days unused by the current tree, evict verified local cached bytes when S3 contains the object.
- Delete an authoritative object only after it remains unreachable from every protected state for 30 days. This deletion applies to never-committed objects and objects made explicitly unreachable, not objects retained by Git history.
- Apply the same protected-state rule to local-only Workspaces, but retain authoritative local bytes because no verified remote copy exists.
- Rehydrate objects when an earlier Note version is restored.
- Before authoritative deletion in a connected Workspace, enumerate the complete attached Remote `refs/heads/*` and `refs/tags/*` namespaces, fetch their reachable history and tags without pruning, and run the final reference check. Stop remote deletion when enumeration or fetch completeness can't be proven. Local cache eviction remains independent when the remote object is hash-verified.

### Adopt an asset-bearing Workspace

- Run an explicit one-time migration for a Workspace that contains ordinary files under `assets/`.
- Inventory every conforming asset reference and hash every referenced file.
- Move or copy each referenced file to its canonical content-addressed `assets/` path.
- Rewrite affected Markdown references through AST source splices.
- Upload migrated objects when S3-compatible storage is connected.
- Commit the migration as one recoverable lifecycle operation. Don't rewrite earlier Git history.
- Stop and list missing, ambiguous, oversized, or nonconforming assets before changing anything.
- Keep unreferenced files available for a separate review instead of deleting them silently.

### Hydrate another device

- After the Git clone validates, open the Workspace without waiting for every asset download.
- Hydrate assets for the active Note first, then hydrate remaining current-tree assets in the background.
- Verify every object against its content hash before exposing the bytes.
- Show an explicit offline or unavailable placeholder for an object that isn't cached.
- Retry hydration without blocking text editing.
- Don't report the Workspace as fully synchronized until every current-tree object is verified locally.

### Recover missing or corrupt objects

- Never expose bytes that fail the expected content hash.
- Preserve a verified local copy and use it to repair the remote object.
- If no verified copy exists, create an Asset Decision and pause Workspace synchronization.
- Offer **Retry**, **Repair from local copy**, **Choose replacement**, or **Remove reference** when each action is valid.
- Choosing a replacement creates a new content hash and updates references through the AST.
- Keep Note editing and local history available.
- Record the failure in diagnostics without asset bytes, credentials, or signed URLs.

### Rotate credentials

- Keep the working credentials while validating the replacement credentials.
- Verify list, read, write, and delete permissions under the configured Workspace prefix with a temporary non-user object.
- Store the replacement atomically in operating-system secure storage.
- Remove only the earlier local keychain entry after validation succeeds.
- Tell the user to revoke the earlier provider credential. The app can't revoke credentials through the generic S3 protocol.
- If credentials expire or are revoked first, pause object synchronization and request replacements without blocking local use.
- Configure credentials per device. Never distribute them through Git.

### Replace or detach a bucket

- Treat an endpoint, bucket, or Workspace-prefix change as an Object Store migration.
- Pause object and Git synchronization during migration.
- Copy and hash-verify every object reachable from the protected states defined in this report.
- Switch configuration atomically only after complete verification.
- Keep the earlier destination active if migration fails.
- Leave the earlier bucket unchanged after success. Don't bulk-delete user-owned storage.
- If no protected state references an object, S3-compatible storage can detach independently.
- For an asset-bearing Workspace, offer migration or a fully local Workspace.
- Before making the Workspace fully local, hydrate and verify every object reachable from the protected states defined in this report.
- After complete hydration, disconnect the S3-compatible Object Store and detach the GitHub Remote. Preserve local Git history and the Local Asset Store.
- Refuse detachment when hydration is incomplete.
- Don't support a Git-connected, asset-bearing Workspace without a connected Object Store in this phase.

### Coordinate Git and object storage

Git and S3-compatible storage don't share one transaction. Use a durable state machine:

1. Store and hash the asset locally.
2. Persist a durable operation intent containing the planned AST edit and required object hashes before creating a commit that references them.
3. Apply the AST reference and create the local Git commit.
4. Bind the resulting commit identifier to the existing intent and durable upload queue.
5. On startup and before every push, derive the object closure from the manifests of all unpushed commits, compare it with durable obligations, and repair any missing queue entries.
6. Upload and verify every required object.
7. Push the Git commit only after its objects are available remotely.
8. On pull, validate object manifests before materializing the Git result.
9. Hydrate assets through the accepted progressive policy.
10. Resume idempotently after a crash at any step.

If S3-compatible storage is unavailable, local commits and editing continue. The dependent Git push waits. The app must never publish a Git commit whose newly referenced objects weren't uploaded.

### Connect an asset-bearing Workspace

- Before attaching a GitHub Remote, inventory current and history-protected asset references.
- Require a configured and validated Object Store connection when any protected state references an object.
- Run the accepted asset migration before publishing Git history.
- Upload and hash-verify every object required by the history that the connection publishes.
- Attach and push the GitHub Remote only after object verification succeeds.
- If configuration, migration, or upload fails, leave the Object Store disconnected and the GitHub Remote detached. Preserve the local Workspace unchanged except for an explicitly completed local migration commit.
- Let the user cancel before GitHub attachment. Don't expose a partially connected Remote.

## GitHub connection and synchronization

GitHub provides the private Note Remote. The GitHub App lifecycle remains optional to local use.

### Provider and privacy

- Use a GitHub App, not a classic OAuth App.
- Use OAuth device flow. Remove the loopback Proof Key for Code Exchange (PKCE) contract and implementation.
- Request the minimum repository permissions that repository provisioning and Git contents require.
- Keep Remotes private-only in this phase.
- Pause synchronization if a connected repository becomes public.
- Treat encrypted repository content or another Remote privacy model as separate research.
- Defer GitLab until GitHub authorization, synchronization, and conflict resolution pass the complete release matrix.

### App registration

- Ship one project-owned GitHub App registration. Don't require each user to register an App.
- Enable device flow on the registration and publish its installation URL.
- Treat the client ID as public release configuration. Don't bundle a client secret or private key in the desktop app.
- Version the requested permissions with the provider contract. Require explicit user approval when a release adds permissions.
- Make registration availability, device-flow enablement, installation URL, client ID, and permission verification release gates.
- Enable expiring user access tokens on the project-owned App registration and verify that setting in release gates.
- Keep release-environment registration values outside local development overrides. A missing or placeholder client ID must fail before opening an authorization page.

### Token lifecycle

- Store the access token, refresh token, and both expiry times in operating-system secure storage. Don't persist them in Workspace files, Git, logs, or diagnostics.
- Refresh once before access-token expiry or after one authenticated `401` response. Retry the failed operation at most once with the replacement token.
- Deduplicate concurrent refresh attempts across scheduler and interactive calls.
- Replace the access token, refresh token, and expiry metadata atomically because each successful refresh invalidates the earlier token pair.
- Clear both tokens and their expiry metadata on sign-out.
- Enter the authentication-required state only after the token endpoint authoritatively rejects an expired, revoked, or invalid refresh credential. Preserve the current token pair and use offline, rate-limited, or retryable-failure states for transport errors, provider `5xx` responses, and rate limiting. Keep local editing and history available.
- Cover expiry, refresh rotation, concurrent refresh, restart restoration, one-time `401` retry, refresh failure, and revocation in provider contract tests and release gates.

### App installation lifecycle

- Device authorization identifies the user.
- List eligible personal and organization App installations.
- For an existing Remote, require access to that specific private repository.
- For a provisioned repository, verify installation access and guide the user through granting it.
- Let organization approval remain pending without blocking local work.
- If authorization, installation access, repository selection, or private visibility is lost, pause synchronization and explain the exact reason.
- Offer reauthorization, restored private visibility, another eligible private repository where valid, or Detach.
- Keep local editing and history available throughout.

### Workspace lifecycle

Include the complete GitHub lifecycle:

- Connect a local Workspace by provisioning or selecting an eligible empty private repository.
- Restore authorization after restart.
- Reauthorize without blocking local use.
- Detach offline while preserving local history and unpushed commits.
- Join on a second device through clone.
- Consolidate a prior local Workspace with explicit identity-collision decisions.
- Keep the source Workspace unchanged during Consolidation.

Signing out clears credentials and leaves the Remote attached in an authentication-required state. Only Detach removes the Remote. The existing foreign function interface (FFI) contract must be corrected.

### Scheduler lifecycle

- Pull on launch.
- Synchronize during application use.
- Make a bounded final push attempt during orderly shutdown.
- Resume safely after abrupt termination.
- Don't add a resident daemon or operating-system background service.
- Keep unresolved Suggestions from blocking commits and pushes after Core materializes them into a valid Git tree.

## Git reconciliation model

Git reconciliation has three user-visible forms:

- *Inline Suggestions* cover source-backed Markdown AST content conflicts.
- *Lifecycle Decisions* cover add, delete, rename, move, Directory, type, and path-identity conflicts.
- *Asset Decisions* cover binary collisions and object-reference outcomes.

The following rules apply:

- Convert content conflicts into the smallest safe independently resolvable AST Suggestion.
- Preserve base, local, and incoming content.
- Keep unresolved content Suggestions in a valid two-parent merge commit so later synchronization can continue.
- Treat delete-versus-edit as restore plus Suggestion. Confirm rejection before deletion wins.
- Don't rely on Git conflict markers for structural or binary conflicts.
- Pause Workspace synchronization while a Lifecycle Decision or Asset Decision remains unresolved. Keep local editing and history available.
- Materialize one valid tree, create the merge commit, and resume after the user resolves the decision.
- Persist the reconciliation base, local and incoming commit identifiers, tentative tree identifier, and recorded decisions before pausing or accepting input.
- Finalize with a compare-and-swap update of the local branch from the recorded local commit. If the branch advanced, recompute reconciliation against the new tip, revalidate recorded decisions, and require renewed input for every changed outcome before creating a merge commit.
- Recover the same recorded inputs and compare-and-swap state after a crash. Never apply decisions to a tentative tree derived from stale commit identifiers.
- Don't promise that unrelated Notes synchronize during an unresolved structural conflict.
- Record authoritative provenance for lifecycle operations created by burlmd. Treat guest-originated rename detection as heuristic and require confirmation when uncertain.
- Reject unrelated-history merges. Consolidation owns that workflow.
- Detect and resume interrupted reconciliation after restart.

### Git analysis spike

The repository's Git implementation isn't an acceptable merge oracle. Run a Spike that verifies a pinned Git command-line interface (CLI) and structured `git merge-tree --write-tree -z --messages` output before implementation.

The corpus must cover:

- Clean and overlapping text edits.
- Add/add and modify/delete.
- Rename/edit, rename/delete, rename/rename, rename/add, and many-to-one rename collisions.
- File and Directory conflicts and Directory rename effects.
- File mode, symlink, submodule, and type changes.
- Binary assets.
- Case and Unicode path collisions.
- Dirty tracked files and untracked checkout blockers.
- Invalid merge bases and unrelated histories.
- Interrupted merges and fault injection at every state transition, including durable asset intent, Git commit creation, commit-identifier binding, queue repair, upload verification, and push.
- Markdown containing literal marker examples in code fences and raw regions.
- Hostile hooks, filters, custom merge drivers, credential helpers, and Git configuration.

Use structured conflict records, index stages, tentative tree identifiers, and exit status. Don't parse human-oriented error text. Release artifacts must provide a version-locked Git CLI instead of launching ambient `git`. Bundle the verified executable and runtime in AppImage and macOS artifacts; include the exact Git package in the Nix closure. Disable unsafe repository-controlled execution paths and satisfy Git's redistribution license obligations.

## Suggestions

The prior Realign rulings remain binding:

- Suggestions resolve at Block or smaller safe AST-subtree granularity.
- Users accept or reject each Suggestion independently.
- A Note can remain partly unresolved.
- The UI never displays raw conflict markers.
- Unresolved content can persist through history and Remote synchronization after Core materializes a valid merge commit.
- Delete-versus-edit preserves the edited Note until the user confirms the deletion outcome.
- Sync status distinguishes pending Suggestions from a clean state.

The PRD domain model must stop calling Suggestions transient. They can persist through history and synchronization.

## Diagnostics and quality

Include the following work:

- A rotating local structured log that excludes Note content.
- A user-created Diagnostics Export with app and schema versions.
- No automatic telemetry upload.
- Linux and Apple Silicon macOS continuous integration (CI).
- Nightly nonblocking benchmarks for every scalar PRD meter.
- Linux and macOS release gates for local editing, persistence, Export, GitHub sync, Suggestions, secure storage, and recovery.
- A measured Git repository-health warning for textual and manifest history near the provisional 1 GiB range. The asset or performance Spike supplies evidence, and Product Requirements Evolution accepts or revises the final threshold before Technical Implementation binds it.

Use layered GitHub verification:

- Run hermetic unit, integration, and protocol-contract tests on every PR.
- Run a scheduled live canary against dedicated private GitHub test repositories.
- Keep canary secrets away from fork-originated PR workflows.
- Run the interactive device authorization as a manual prerelease gate.
- Don't automate a logged-in browser to approve device codes.

## Packaging, releases, and updates

- Publish `0.x` prereleases until the user explicitly authorizes stability.
- Target Apple Silicon macOS. Don't target Intel macOS.
- Target x86-64 Linux for the general artifact.
- Expose only systems verified by CI in the Nix Flake.
- Support the two most recent macOS major versions at each release.
- Let the packaging Spike select and document the oldest verified Linux runtime baseline and named tested distributions.
- Publish a general Linux AppImage and an Apple Silicon macOS artifact through GitHub Releases.
- Publish a release-tagged Nix Flake that users can import into NixOS or Home Manager configuration.
- Publish checksums and provenance for every artifact.
- Check GitHub prereleases for a compatible higher `0.x` version and notify the user. Open the release page for installation.
- Don't replace installed binaries in place. Nix owns upgrades for Nix-managed installations.
- Defer Developer ID signing and notarization until the user declares the product stable. Label unsigned macOS prerelease artifacts and explain the Gatekeeper override.
- At the first stable release, make signing and notarization release-blocking.
- Defer Linux ARM64 and self-updating binaries.

Run an early packaging-feasibility Spike against a representative Flutter and Rust harness. Verify AppImage and Flake construction, bundled runtime and Git dependencies, keyring access, file selection, secret injection seams, and update-channel selection without implementing production features. After implementation, run release-gate tests against the complete installed app for GitHub authorization, S3-compatible credentials, Workspace access, and update notification.

## Upgrade policy

The user delegated upgrade policy. Use this conservative default:

- Migrate application state forward automatically.
- Back up affected state before migration.
- Apply each migration atomically and roll it back on failure.
- Keep Markdown and OKF content unchanged when possible.
- Rebuild the encrypted index when schema migration isn't safer.
- Don't guarantee downgrade compatibility.

## Explicit deferrals

The following items stay outside this plan:

- GitLab, until the GitHub integration passes its complete release matrix.
- S3-only Workspaces, until Git plus S3-compatible storage is proven.
- Workspace-wide HTML Publishing and single-Note HTML export.
- Graphical Note relationship visualization.
- Floating selection formatting toolbar.
- Full version-history diff viewer.
- Intel macOS and Linux ARM64.
- Self-updating binaries.
- Developer ID signing and notarization during `0.x`.
- Mobile device application targets.
- Multiple simultaneous Workspaces.
- History merging between independently populated repositories.

## Roadmap ownership and sequencing

The user delegated roadmap structure to the planning stage. Retire the provisional G, H, and I narrative assignments because none became active tickets. Keep completed A-F history unchanged.

Stage 4 owns epic letters, ticket boundaries, estimates, dependencies, Spikes, and the critical path. Separate the research backlog from the implementation backlog:

1. Run Product Requirements Evolution.
2. Run Architecture Evolution.
3. Run a provisional Technical Implementation Evolution that defines candidate Architecture Decision Records, prototype locations, tools, and exact Spike verification commands without claiming unresolved results.
4. Run a research-only Tasks pass that creates the AST, path, Git, asset, and packaging Spike tickets from the provisional TechSpec.
5. Execute the Spike wave. Spikes produce reports and no production code.
6. Route measured product thresholds through Product Requirements Evolution, then review Architecture for resulting flow changes.
7. Run final Technical Implementation Evolution with the accepted Spike and upstream evidence.
8. Run the final Tasks pass for the implementation backlog.
9. Complete and harden local shell behavior, including platform-chrome removal.
10. Establish the canonical Workspace and Note models.
11. Complete local editing, history, monitoring, assets, and Export.
12. Implement GitHub App authorization and private Remote lifecycle.
13. Implement the durable sync state machine and reconciliation surfaces.
14. Complete diagnostics, cross-platform verification, packaging, and release automation.

The design system already exists. Sync, Suggestion, and release surfaces consume it without a backward-planned design epic.

## Required upstream Evolution

An implementation Tasks pass can't run safely against the present upstream files. Use this forward reconciliation loop:

1. **Product requirements:** state technology-neutral outcomes for guest authority, live monitoring, cross-platform paths, complete reconciliation, user-controlled binary-object storage, asset retention, an optional private Remote, provider lifecycle, release artifacts, and Publishing deferral. Revise CAP-SYNC-09 into a technology-neutral second-provider capability and defer it until the reference provider passes the complete release matrix. Reserve *Remote* for the hosted repository and *Object Store* for remote S3-compatible storage. Define *Asset*, *Local Asset Store*, *Object Store*, *object*, *Lifecycle Decision*, and *Asset Decision*. Reconcile or replace the existing *Attachment* term. Keep GitHub, GitLab, and S3-compatible preferences in `vision.md` operator preferences rather than normative capabilities.
2. **Architecture:** define the logical Canonical Note Model boundary, ownership of Workspace and Note state, logical Repository Remote, Local Asset Store, and Object Store boundaries, monitoring flows, reconciliation state machine, structural conflict pauses, repository and object coordination, and release boundaries without selecting provider protocols or defining the physical AST schema.
3. **Provisional technical implementation:** define candidate ADRs, prototype locations, tools, and exact verification commands for every unresolved Spike. Assign the AST node schema, parser foundation, source-range representation, and Flutter Rust Bridge projection to this layer alongside GitHub App, device flow, permissions, registration, S3-compatible contracts, and release packaging. Mark unresolved results explicitly.
4. **Research Tasks:** create only the decision-producing Spike tickets and placeholders that the provisional TechSpec defines. Don't schedule implementation.
5. **Spike execution:** produce the AST, path, Git, asset, and packaging reports. Don't edit production code or active specifications from a Spike.
6. **Measured product constraints:** return user-visible thresholds, including image size, Git repository health, and the Linux support baseline, to Product Requirements Evolution. Review Architecture when accepted thresholds change storage or synchronization flows.
7. **Final technical implementation:** consume the Spike reports and accepted upstream constraints, replace loopback PKCE with GitHub App device flow, correct sign-out and Export contracts, bind the physical AST node schema, parser foundation, source ranges, and Flutter Rust Bridge projection, define the path contract, define object manifests and S3-compatible credentials, pin structured Git analysis, specify packaging, and publish implementation and release-gate verification commands.
8. **Implementation Tasks:** generate the forward active backlog after the three upstream layers and Spike evidence remove every contract gap.

Running an implementation backlog before this loop completes would force task tickets to invent product and protocol behavior, which the planning stage forbids.

## Prior open-decision disposition

- Prior OD-01 is resolved by repository reality. PR #11 delivered theme, localization, and Semantics foundations. Plan only remaining behavior.
- Prior OD-03 is resolved. The design tokens exist before sync and Suggestion surfaces. The roadmap no longer has competing design and sync tracks.
- Prior OD-02 remains open and is carried into the companion register.
- OD-04 through OD-08 record the foundation, path, image-limit, repository-health, and Linux-baseline questions delegated to Spikes during this interview.

## External verification used during the interview

- GitHub device flow doesn't require a client secret. GitHub Apps provide narrower repository permissions than classic OAuth Apps. Verified on 2026-08-25 against [Authorizing OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps) and [Differences between GitHub Apps and OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps).
- Git's structured merge analysis covers conflicts that working-tree markers can't represent. Verified on 2026-08-25 against [`git merge-tree`](https://git-scm.com/docs/git-merge-tree).
- GitHub warns for Git objects above 50 MiB and blocks objects above 100 MiB. Binary payloads no longer enter Git under the accepted S3-compatible design. Verified on 2026-08-25 against [About large files on GitHub](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).
- Flutter Linux bundles depend on host libraries. AppImage requires explicit NixOS handling, so the Nix Flake is a separate supported installation path. Verified on 2026-08-25 against [Build Linux apps with Flutter](https://docs.flutter.dev/platform-integration/linux/building) and [AppImage on NixOS](https://wiki.nixos.org/wiki/Appimage/en).
- Apple Developer ID signing and notarization remain the direct-distribution trust path for macOS. They become mandatory only when the product leaves `0.x`. Verified on 2026-08-25 against [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
