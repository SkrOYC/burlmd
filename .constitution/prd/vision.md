---
version: v1.2.0
---

# Product Vision

## Archetype

- **Primary:** `System/Native`. The shipped surfaces are a desktop application embedding a full data engine — Markdown parsing, an encrypted local index, version history, and all cryptographic material — behind an in-process boundary, with the interface layer deliberately stateless. That is a native system product, not a web or cloud one.
- **Secondary:** `Mobile`, declared but deferred. Multi-device access is a stated expectation of the primary actor, so the architecture carries synchronization and offline tolerance as requirements rather than afterthoughts; the touch surfaces themselves are open work.
- **Confidence:** `high`.
- **Rationale:** Desktop gets nailed first. Flutter is built responsive-by-construction so the layout system never assumes one form factor, but the mobile interaction design is deliberately left open rather than pre-drawing every surface twice. Constraint focus therefore follows System/Native — input-to-effect latency, memory ceilings, startup cost — with Mobile rows added when that surface unshelves.

## Executive Summary
A local-first, Git-backed note-taking application for people who write Markdown by choice. Notes are plain Markdown files in a published, non-proprietary open format on the user's own disk, organized through a hybrid structure that combines a familiar Directory tree with a lateral knowledge graph of Links. Editing is direct: the Block under the cursor shows its raw Markdown source, while every other Block renders formatted — so the user always reads a finished document and always edits real text. A Workspace works fully offline with no account; connecting it to a Remote is an opt-in step that adds multi-device sync, with concurrent edits surfaced as inline Suggestions rather than raw merge conflicts.

## Jobs to Be Done (JTBD)
- **Write directly:** Compose in real Markdown without an editor that hides, rewrites, or second-guesses the syntax.
- **Read finished:** See the document as it will be read, without leaving the editing surface or toggling into a separate preview mode.
- **Start immediately:** Open the application and write the first Note without an account, a network connection, or any setup step.
- **Organize and connect:** Structure knowledge hierarchically in Directories while linking related ideas laterally to build a knowledge graph.
- **Sync seamlessly:** Access up-to-date Notes across devices automatically, tolerating long offline periods.
- **Retain ownership:** Keep every Note as a portable file that outlives the application itself and can be read with no application-specific tooling.
- **Resolve smoothly:** Reconcile concurrent offline edits without hand-editing conflict markers or losing work.
- **Stay machine-readable:** Keep the Workspace consumable by automated tools and agents without bespoke parsing or a separate export step.

## Appendix: Operator Preferences
- The UI layer (Presentation & Interaction) should be built with Flutter (multiplatform).
- The Core Engine should be built in Rust, communicating with the UI via zero-overhead FFI.
- Local indexing via SQLite.
- Background sync powered by low-level Git plumbing.
- The storage target is a private GitHub/GitLab repository once a Workspace is connected. A Workspace that has never been connected is backed by a purely local Git repository, so version history exists from the first Note regardless of whether a Remote is ever configured.
- On-disk Workspace structure conforms to the Open Knowledge Format (OKF). The exact specification version is pinned downstream in the implementation constitution, not here.
