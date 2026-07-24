# Execution Flow: Conflict Resolution

**Maps to PRD Capability:** CAP-SYNC-04 (concurrent edits to the same Note surface inline as a Suggestion the user can accept or reject, never as raw conflict markers and never by duplicating the Note). Epic: Synchronization & Conflict Resolution, P1.

> **Status:** the body below predates ADR-006 and ADR-007 — it still describes pushing an "active Draft AST" and a "User closes editor / Saves" step, neither of which survives the raw-on-focus editing model or the single-writer working source. Deferred to Epic H, which owns the Suggestion surface and will revise it against the current contract.

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
