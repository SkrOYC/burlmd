# Stage 4: Tasks Changelog

## v1.0.1
- Recorded Phase 0 (tooling readiness), executed ahead of `CORE-A001`. It provisions the reproducible `devenv` environment and the pre-commit quality gates; it adds no application code and consumes no story points, so the critical path and totals are unchanged.
- Every file it introduces falls outside the `Scope (In-Scope Files)` of Epics A/B/C by design. `CORE-A001` keeps `Dependencies: None`, but its verification commands are now expected to run inside the devenv shell, per the Toolchain section of `tech-spec/guidelines.md`.
- Corrected the `UIDB-B002` acceptance criterion, which asserted AES-256-GCM. SQLCipher 4.x is AES-256-CBC with HMAC-SHA512 page authentication; see `tech-spec/stack.md` v1.0.1.

## v1.0.0
- Initial formulation of the execution constitution.
- Created active backlog totaling 52 Story Points.
- Sequenced work into Desktop-first phased delivery (Epic A: Scaffolding, Epic B: UI/DB, Epic C: Security/Sync).
- Mapped Build Order diagram and defined critical path.
