---
decision: deferred
date: 2026-08-26
---
# Self-updating binaries

**Context:** burlmd could download and replace its installed executable after detecting a release.

**Decision:** Deferred.

**Reason:** Update notification and release-page handoff provide awareness without introducing a privileged binary replacement path. Externally managed installations already have a separate upgrade authority.

**Consequences:** CAP-REL-03 can notify and open release information but must not replace installed binaries. Reopening requires Product Requirements, Architecture, security, and packaging Evolution passes.
