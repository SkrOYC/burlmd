# Stage 2: Architecture Changelog

## v1.0.0
- Defined the Local-First Thick Client architectural strategy.
- Decomposed the system into four logical containers: Presentation Container, Core Engine, Local Repository, and Sync Manager.
- Established the FFI boundary rules (stateless UI streaming to a stateful engine).
- Defined conflict resolution mechanics occurring within the Core Engine via AST generation.
- Documented cross-cutting resilience concerns for offline operation and FFI serialization risks.
- Upgraded Core Engine container to serve as a cryptographic boundary.
- Added `Secure Storage (OS Keychain)` boundary container.
- Added execution flows for OAuth Handshake (`flow-auth-handshake.md`) and Conflict Resolution (`flow-conflict-resolution.md`).
- Expanded resilience matrix to cover secure storage failures.
