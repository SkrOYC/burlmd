---
decision: deferred
date: 2026-08-26
---
# HTML output

**Context:** The PRD proposed a Workspace-wide self-contained HTML file. The interview also considered a single-Note HTML export as the more useful shape.

**Decision:** Deferred.

**Reason:** Neither HTML form is required for the feature-complete desktop and synchronization release. A single-Note export has more direct value than a Workspace-wide file, but it doesn't outrank local completion, assets, Export, synchronization, or packaging.

**Consequences:** Downstream stages must remove CAP-PORT-04 and must not schedule either HTML form. Reopening requires a Product Requirements Evolution pass that selects one user-facing outcome.
