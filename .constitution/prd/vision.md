---
version: v1.0.0
---

# Product Vision

## Executive Summary
A Git-backed, local-first note-taking application designed for general consumers. It provides a clean, Notion-like hybrid Markdown editing experience while organizing knowledge through a hybrid Open Knowledge Format (OKF) structure—combining familiar directory trees with a lateral knowledge graph. Sync is seamlessly handled via OAuth, with concurrent edit conflicts resolved intuitively through margin suggestions, offering users total data sovereignty without the technical complexity.

## Jobs to Be Done (JTBD)
- **Capture and Format:** Quickly jot down thoughts and format them effortlessly without seeing raw markup syntax.
- **Organize and Connect:** Structure knowledge logically in hierarchies while also linking related ideas laterally to build a knowledge graph.
- **Sync Seamlessly:** Access up-to-date notes across all devices automatically, regardless of intermittent offline periods.
- **Retain Ownership:** Guarantee that personal data remains fully portable and owned by the user, escaping proprietary platform lock-in.
- **Resolve Smoothly:** Handle offline concurrent edits on multiple devices without dealing with intimidating technical diffs or data loss.

## Appendix: Operator Preferences
- The UI layer (Presentation & Interaction) should be built with Flutter (multiplatform).
- The Core Engine should be built in Rust, communicating with the UI via zero-overhead FFI.
- Local indexing via SQLite.
- Background sync powered by low-level Git plumbing.
- The storage target is a private GitHub/GitLab repository.
