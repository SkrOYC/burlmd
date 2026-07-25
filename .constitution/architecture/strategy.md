---
version: v1.1.0
---

# Architectural Strategy

## Architectural Pattern: Local-First Thick Client with Eventual Remote Sync
The system adopts a local-first architecture where the client application encapsulates both the presentation layer and a full backend-equivalent data engine. The local data store acts as the primary, synchronous source of truth, while an asynchronous background worker handles eventual consistency with a remote Git repository.

## Why this pattern fits
This pattern perfectly satisfies the PRD's constraints for sub-16ms UI responsiveness and 100% offline functionality. By keeping the Presentation Container completely stateless and streaming updates to a local Core Engine, we eliminate network latency from the user's editing flow. The use of a background sync worker abstracting Git operations fulfills the requirement for seamless, non-technical synchronization while guaranteeing data sovereignty via the remote repository.

## Trade-offs Accepted
- **Client Footprint:** The application binary will be significantly larger than a standard API-driven app because it must embed a full local index and Git-equivalent operational logic.
- **Initial Load Latency:** Adopting an existing Workspace on a *second* device requires a full repository clone, which may be slow on a degraded network compared to lazy-loading a single Note from a cloud database. This no longer applies to first use: under ADR-005 the first Workspace is created locally with `init`, so nothing is cloned and no network is contacted before the first word is written.
- **FFI Complexity:** Maintaining a strict, zero-overhead boundary between a stateless UI and a stateful Core Engine requires rigorous serialization contracts (AST passing), increasing development overhead.
