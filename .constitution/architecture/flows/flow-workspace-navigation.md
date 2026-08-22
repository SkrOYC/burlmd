# Execution Flow: Workspace Navigation

**Maps to PRD Capability:** CAP-GRAPH-01 (browse the Workspace as a nested Directory tree and open any Note from it).

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository

    Note over UI,Local: Precondition: bootstrap has converged (see flow-workspace-bootstrap.md)

    UI->>Core: Request tree
    Core->>Local: Query Directories and Notes scoped to the active Workspace
    Local-->>Core: Tree entries — empty Directories included
    Core-->>UI: Whole-tree payload
    UI->>UI: Render nested tree; expansion state is ephemeral UI state

    UI->>Core: Select Note
    Core-->>UI: Opened state (routed through flow-edit-note.md)
```

## Design notes

- **One call renders the whole sidebar.** The tree arrives as a single payload with children nested, so expanding a collapsed level costs no further round trip. Per-call whole-tree rebuilds are acceptable at the Corpus Scale Goal but are a known sensitivity point at the Stretch (`risks.md` risk 3's indexing family); measure before putting this behind keystrokes.
- **Empty Directories appear** — except Asset Directories, which the Attachment ruling keeps out of the tree entirely. The tree payload is derived from indexed Notes, so a Directory with no Note inside it would vanish from the view unless the index tracks Directories separately — which is exactly why it does.
- **Expansion state is the UI's own.** Which nodes stand open is ephemeral interaction state, exactly like selection coordinates — not Note content, so the Presentation Container may hold it without becoming an owner of data.

## Failure path

- **Tree query fails:** the shell shows an error state for the sidebar with a retry affordance. The editor keeps working — an index hiccup must not take open Notes down with the navigation surface.
- **Selected Note fails to open:** the failure surfaces per `flow-edit-note.md`'s error handling rather than leaving a silent half-open state; the tree selection reverts.
- **Workspace changed underneath the view** (external tool wrote while open, or a sync pull landed): the tree reflects reality only after the rescan affordance runs (CAP-WS-06) or the next full reload; staleness until then is visible, not fictional.
