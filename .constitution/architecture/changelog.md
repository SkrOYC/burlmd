# Stage 2: Architecture Changelog

## v1.0.1
Constitution Freshness & Reconciliation Pass following Epic B execution (UIDB-B001–B007).
- Corrected `containers.md`'s Local Repository description, which implied the raw OKF directory tree was encrypted by this container. The shipped implementation only encrypts the SQLite index (via SQLCipher); raw Markdown files rely on OS-level Full Disk Encryption, per `prd/constraints.md`'s existing rationale (preserving native Git merge capability). This same inconsistency also existed in `prd/capabilities.md` (corrected there, see `prd/changelog.md` v1.0.1).
- Corrected `flows/flow-edit-note.md`: reworded the Active Editing loop's "updated localized AST" to "updated NoteState (full AST)" — `update_block` returns the full note state, not a differential update (differential streaming remains the risk #1 fallback, not something implemented). Annotated the Close/Save phase (serialize AST to Markdown, commit to disk) as not yet implemented: `save_note` currently performs only the OCC bookkeeping check described in risk #6, with no Markdown serializer or file write-through existing yet.
- Amended `risks.md` risk #6 (OCC for Background Sync) with a current-implementation-status note: the shipped `save_note` guards the `notes.last_modified` database column only, since no code path yet serializes the AST back to the on-disk Markdown file. Full protection against the file-clobbering scenario the risk describes is contingent on a future Markdown-serialization + Git-write-through ticket.

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
