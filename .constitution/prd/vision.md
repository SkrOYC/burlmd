# Product vision

## Archetype

- **Primary:** `System/Native`. The shipped surface is an installable desktop application with local editing, indexing, history, secure credential handling, and offline operation.
- **Secondary:** None. Mobile device applications remain deferred and don't define this phase's product surface.
- **Confidence:** `high`.
- **Rationale:** Desktop lifecycle, filesystem interoperability, input latency, memory use, and installability determine whether the product can serve as a daily writing environment.

## Executive summary

burlmd is a local-first desktop note-taking application for people who write Markdown by choice. Notes remain plain files in a published open format on the user's disk. A Workspace combines a Directory tree with a knowledge graph of Links. The focused Block exposes its source, and other Blocks render as formatted content. A Workspace works without an account or network connection. An optional private Remote adds multi-device synchronization. burlmd presents content conflicts as Suggestions and gives structural or asset conflicts their own explicit decisions.

## Private Linux-first usable milestone

The first usable milestone serves one Writer who runs burlmd locally on Linux from a checkout. The Writer begins with one fresh Workspace and one collection, organized through Directories. They can migrate an existing collection manually instead of requiring burlmd to adopt it.

This milestone includes dependable Note-level undo and redo, in-Note find and replace, local images from file selection and clipboard paste, automatic local external-change detection, preservation and clear reporting of invalid external changes, plain-folder Export, and minimal local Diagnostics Export. It also includes the P0 Markdown capabilities in `capabilities.yaml`, including tables and footnotes. Every delivered editing operation participates in undo and redo, and selected Markdown source remains editable and faithfully rendered where applicable.

Externally referenced Markdown images load automatically when the Writer opens their Note. This behavior doesn't turn those references into local Assets and doesn't authorize transmitting other Note content, application credentials, or telemetry.

Local Linux evidence supports private use only. It doesn't qualify a package, a published release, macOS, another Linux system, or any other platform.

This milestone retains cross-platform Workspace format and path portability. It doesn't permit data loss, Linux-specific file-format changes, or weaker ownership guarantees.

## Delivery order

Delivery proceeds through four acceptance boundaries:

1. Complete the private Linux P0 local milestone.
2. Synchronize Notes and local images together, including in-app Suggestions for concurrent content edits and safe detachment back to complete local-only use.
3. Deliver the P1 Markdown capabilities after the synchronization milestone works.
4. Deliver the P2 Markdown capabilities after P1.

These boundaries express product priority, not false technical dependencies. Scope-disjoint work can proceed concurrently when the approved execution graph permits it. The P1 and P2 Markdown capabilities remain active incremental product scope, but they don't need speculative implementation tickets before their increment approaches execution.

macOS support and qualification are P2 product scope after P1, with no required ordering relative to the P2 Markdown increment. They don't block private Linux use or synchronization and don't require public packaging first. CAP-075 through CAP-077 and CAP-079 through CAP-080 retain the longer-term public `0.x` release commitments. CAP-078 remains active migration safety for private use and upgrades. The user will reconsider publication and hosted release gates only when they explicitly resume that delivery outcome.

Other deferred delivery outcomes remain recorded under `out-of-scope/` with explicit revisit conditions. Their product intent and stable capability identifiers remain intact, but they don't receive implementation tickets in the replacement near-term roadmap.

## Established product baseline

PR #11 established the design system, responsive shell, preferences surface, localization foundation, keyboard accessibility, semantic labels, and deterministic visual evidence. The repository retains this foundation in `lib/src/design/`, `lib/src/screens/workspace.dart`, `lib/src/providers/burl_preferences_provider.dart`, `lib/l10n/`, `integration_test/`, and `test_driver/`. `REDESIGN.md` preserves the completed visual-redesign record.

Downstream product work must evolve this delivered baseline. It must not schedule a retrospective design epic to recreate it.

## Jobs to be done

- **Write directly:** Compose in real Markdown without an editor that hides, rewrites, or second-guesses the syntax.
- **Read finished:** See the document as it will be read, without leaving the editing surface or toggling into a separate preview mode.
- **Start immediately:** Open the application into one fresh local Workspace and write the first Note without an account or network connection.
- **Organize and connect:** Structure knowledge hierarchically in Directories while linking related ideas laterally to build a knowledge graph.
- **Sync seamlessly:** Access up-to-date Notes and local images across devices automatically, tolerating long offline periods.
- **Retain ownership:** Keep every Note and referenced local image portable beyond the application and Export a consistent local copy.
- **Resolve smoothly:** Reconcile concurrent offline edits without hand-editing conflict markers or losing work.
- **Stay machine-readable:** Keep the Workspace consumable by automated tools and agents without bespoke parsing or a separate export step.
- **Keep visual context:** Include images without placing large binary payloads in Note history or losing offline access to active assets.
- **Install confidently:** Install a tested prerelease without building the application from source and receive a notification when a compatible update exists.

## Appendix: Operator preferences

- The UI layer (Presentation & Interaction) should be built with Flutter (multiplatform).
- The Core Engine should be built in Rust, communicating with the UI through zero-overhead FFI.
- Use SQLite for local indexing.
- Use a version-locked Git command-line interface for local history and synchronization analysis.
- Use a project-owned GitHub App and private GitHub repositories as the reference Remote connection. Consider GitLab only after the GitHub connection passes the complete release matrix.
- Exercise the reference Remote connection through burlmd's OAuth flow. A pasted personal access token or inherited command-line authorization isn't a substitute for that product flow.
- Use user-controlled S3-compatible storage as the Object Store. Keep a hybrid Local Asset Store, Git, and Object Store model before considering an Object-Store-only Workspace.
- Publish `0.x` artifacts through GitHub Releases for x86-64 Linux and Apple Silicon macOS. Also publish a release-tagged Nix Flake for NixOS and Home Manager users.
- Defer Developer ID signing and notarization until the user declares the product stable.
- On-disk Workspace structure conforms to the Open Knowledge Format (OKF). The exact specification version is pinned downstream in the implementation constitution, not here.
