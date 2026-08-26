---
version: v1.3.4
---

# Product vision

## Archetype

- **Primary:** `System/Native`. The shipped surface is an installable desktop application with local editing, indexing, history, secure credential handling, and offline operation.
- **Secondary:** None. Mobile device applications remain deferred and don't define this phase's product surface.
- **Confidence:** `high`.
- **Rationale:** Desktop lifecycle, filesystem interoperability, input latency, memory use, and installability determine whether the product can serve as a daily writing environment.

## Executive summary

burlmd is a local-first desktop note-taking application for people who write Markdown by choice. Notes remain plain files in a published open format on the user's disk. A Workspace combines a Directory tree with a knowledge graph of Links. The focused Block exposes its source, and other Blocks render as formatted content. A Workspace works without an account or network connection. An optional private Remote adds multi-device synchronization. burlmd presents content conflicts as Suggestions and gives structural or asset conflicts their own explicit decisions.

## Jobs to be done

- **Write directly:** Compose in real Markdown without an editor that hides, rewrites, or second-guesses the syntax.
- **Read finished:** See the document as it will be read, without leaving the editing surface or toggling into a separate preview mode.
- **Start immediately:** Open the application and write the first Note without an account, a network connection, or any setup step.
- **Organize and connect:** Structure knowledge hierarchically in Directories while linking related ideas laterally to build a knowledge graph.
- **Sync seamlessly:** Access up-to-date Notes across devices automatically, tolerating long offline periods.
- **Retain ownership:** Keep every Note as a portable file that outlives the application itself and can be read with no application-specific tooling.
- **Resolve smoothly:** Reconcile concurrent offline edits without hand-editing conflict markers or losing work.
- **Stay machine-readable:** Keep the Workspace consumable by automated tools and agents without bespoke parsing or a separate export step.
- **Keep visual context:** Include images without placing large binary payloads in Note history or losing offline access to active assets.
- **Install confidently:** Install a tested prerelease without building the application from source and receive a notification when a compatible update exists.

## Appendix: Operator preferences

- The UI layer (Presentation & Interaction) should be built with Flutter (multiplatform).
- The Core Engine should be built in Rust, communicating with the UI via zero-overhead FFI.
- Local indexing via SQLite.
- Use a version-locked Git command-line interface for local history and synchronization analysis.
- Use a project-owned GitHub App and private GitHub repositories as the reference Remote connection. Consider GitLab only after the GitHub connection passes the complete release matrix.
- Use user-controlled S3-compatible storage as the Object Store. Keep a hybrid Local Asset Store, Git, and Object Store model before considering an Object-Store-only Workspace.
- Publish `0.x` artifacts through GitHub Releases for x86-64 Linux and Apple Silicon macOS. Also publish a release-tagged Nix Flake for NixOS and Home Manager users.
- Defer Developer ID signing and notarization until the user declares the product stable.
- On-disk Workspace structure conforms to the Open Knowledge Format (OKF). The exact specification version is pinned downstream in the implementation constitution, not here.
