---
decision: deferred
date: "2026-09-03"
---
# Additional release architectures

**Context:** Release artifacts could include Intel macOS and Linux ARM64 builds in addition to the selected desktop architectures.

**Decision:** Deferred.

**Reason:** Each architecture expands packaging, dependency, secure-storage, and release-gate work. The selected Apple Silicon macOS and x86-64 Linux artifacts cover this phase.

**Consequences:** The support matrix must not claim Intel macOS or Linux ARM64. Reopening requires Product Requirements Evolution and measured packaging evidence.
