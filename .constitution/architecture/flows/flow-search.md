# Execution Flow: Instant Search

**Maps to PRD Capability:** CAP-FIND-01 (search the full text of every Note in the Workspace and open a result directly). Epic: Discovery & Retrieval, P0.

> **Amended for tech-spec v1.1.0. Core half implemented by `WSPC-D009`; the UI half is `SHEL-E006` and is not built yet.** The contract beneath this flow changed here, and the changes have shipped: `search_notes` takes a caller-supplied `limit`, which **resolves** the hardcoded cap of 50 that silently truncated results with no signal to the caller; it is scoped to the active Workspace by the Core rather than by a `workspace_id` parameter (contract rule 2); and `find_notes_by_title` sits alongside it for CAP-FIND-02, matching a leading title prefix only. The Workspace filter is not drawn as a step below because there is nothing for the caller to pass: it is ambient in the Core. Until `SHEL-E006` mounts a search surface, nothing in the running application reaches these functions.

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository

    UI->>Core: Dispatch search query ("project x")
    Core->>Local: Execute full-text indexed search
    Local-->>Core: Return list of matching Note IDs and snippets
    Core-->>UI: Formatted search results payload
    UI->>UI: Render search result list
```

## Failure path

The search surface has exactly two honest states: results, or an explicit empty state. Both are rendered; neither invents content.

- **No matches:** an empty state, never an error — a query matching nothing is a normal answer (CAP-FIND-01).
- **Query syntax hazards:** punctuation that a full-text engine would treat as grammar reaches the Core escaped or quoted so it yields results or an empty state, never a raw engine error surfaced to the user.
- **Index unavailable or unreadable:** the Core reports the failure upward and the shell renders it as an error state with the recovery affordance — a full reindex exists precisely because the index is derived state. Search is degraded, never the editor: the Local-First Mandate means a broken index must not block reading or writing Notes.
- **Result limit:** the caller supplies the limit, so truncation is a visible choice of the surface rather than a silent cap; the UI pages or widens it rather than hiding matches.
