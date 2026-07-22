# Stage 1: Product Requirements Changelog

## v1.0.1
Constitution Freshness & Reconciliation Pass following Epic B execution (UIDB-B001–B007).
- Corrected `capabilities.md`'s at-rest encryption capability, which implied Notes on disk and the SQLite index receive identical, uniform encryption. The shipped implementation (and `constraints.md`'s own pre-existing rationale) draws a real distinction: Notes on disk are protected via OS-level Full Disk Encryption only, while the SQLite search index is additionally encrypted at the application level via SQLCipher. Reworded to state that distinction explicitly rather than imply both are encrypted the same way.

## v1.0.0
- Initial formulation of the Product Requirements Document.
- Defined target persona as General Consumer seeking a Notion-like experience.
- Established hybrid Markdown editing and hybrid OKF (Directory + Link) organization models.
- Abstracted Git complexity via OAuth provisioning and inline Suggestion-based conflict resolution.
- Set explicit bounds on local-first capabilities and user data sovereignty.
- Expanded PRD to include detailed capabilities for inline formatting and block structures.
- Added explicit Security & Auth Epic, formalizing OAuth and at-rest encryption requirements.
- Expanded constraints to enforce AES-256 local encryption without compromising data portability.
