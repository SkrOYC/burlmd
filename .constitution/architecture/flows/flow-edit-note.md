# Execution Flow: Edit Note

**Maps to PRD Capability:** Users can create and edit Notes using a hybrid editor that auto-formats text without displaying raw markup. (Epic: Core Editing & Organization, P0)

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository

    UI->>Core: Open Note (ID)
    Core->>Local: Fetch Markdown content
    Local-->>Core: Raw Markdown string
    Core->>Core: Parse Markdown to AST
    Core-->>UI: Initial Draft AST
    
    loop Active Editing
        UI->>Core: Stream block modification (e.g., Keystroke on Block 3)
        Core->>Core: Update active Draft AST in memory
        Core-->>UI: Acknowledge & return updated NoteState (full AST)
        UI->>UI: Re-render note (whole block list; per-block differential re-render is a future optimization, see risks.md #1)
    end
    
    UI->>Core: Close Editor / Explicit Save
    Core->>Core: Serialize final AST back to Markdown
    Core->>Local: Commit Markdown to disk (Atomic Save)
    Local-->>Core: Commit Success
```

**Current implementation status (Epic B):** the "Active Editing" loop is fully implemented (`update_block`, synchronous FFI round-trip). The "Close Editor / Explicit Save" phase is **not yet implemented** — `save_note` currently performs only an Optimistic Concurrency Control check against `notes.last_modified` (see `architecture/risks.md` risk #6); no Markdown serializer exists, and no code path commits AST content back to the on-disk file. That half of this flow is deferred to a future ticket.
