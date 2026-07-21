# Execution Flow: Conflict Resolution

**Maps to PRD Capability:** The system surfaces concurrent offline edits as inline Suggestions for the user to accept or reject. (Epic: Seamless Synchronization & Security, P1)

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository
    participant Sync as Sync Manager

    Sync->>Core: Notify of Git Merge Conflict
    Core->>Local: Read conflicting file with Git markers
    Local-->>Core: Raw text with `<<<<<<< HEAD`
    
    Core->>Core: Parse raw text into structured AST
    Core->>Core: Convert conflict block into `Suggestion` AST Node
    
    Core-->>UI: Push updated active Draft AST (containing Suggestion)
    
    UI->>UI: Render Suggestion inline (Google Docs style)
    
    UI->>Core: User clicks "Accept Incoming"
    Core->>Core: Update AST (replace Suggestion node with Incoming block)
    Core-->>UI: Acknowledge & return clean AST
    
    UI->>Core: User closes editor / Saves
    Core->>Local: Commit resolved Markdown (no markers)
    Core->>Sync: Notify resolution complete
    Sync->>Sync: Finalize Git merge and push upstream
```
