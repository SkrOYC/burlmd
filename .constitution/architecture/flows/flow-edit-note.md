# Execution Flow: Edit Note

**Maps to PRD Capability:** CAP-EDIT-01 (the focused Block shows raw Markdown source while every other Block renders formatted), CAP-EDIT-03 (create, split, merge and delete Blocks through ordinary typing), CAP-WS-02 (every editing session captured in local version history), CAP-WS-03 (in-progress edits survive abrupt termination).

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository

    UI->>Core: Open Note (concept id)
    Core->>Local: Read Markdown source
    Local-->>Core: Raw source
    Core->>Core: Parse to AST + span map (spans stay Core-side)
    Core->>Local: Restore unflushed draft, if any
    Core-->>UI: NoteState (AST, base_revision, restored_from_draft)

    UI->>UI: Render every Block formatted, inside one selection region

    loop Focused Block
        UI->>Core: Get Block source (block_path)
        Core-->>UI: Raw Markdown for that Block
        UI->>UI: Promote Block to raw editable field

        loop Keystroke
            UI->>Core: Update Block (block_path, new source)
            Core->>Core: Splice source over the Block's span, reparse
            Core->>Local: Write draft row (tier 1, every keystroke)
            Core-->>UI: NoteState (new AST)
        end

        Note over Core,Local: ~1s idle
        Core->>Local: Atomic write (tier 2): temp file + rename
        Local-->>Core: New base_revision (content hash)
    end

    UI->>Core: Close Note (navigate away / quit)
    Core->>Local: Flush pending write
    Core->>Local: One Git commit for this session (tier 3)
    Core->>Local: Clear draft row
    Core->>Core: notify_activity() to the sync scheduler
    Local-->>Core: Commit success
```

## The save phase is a splice, not a serialization

The previous version of this flow specified "Serialize final AST back to Markdown" — a phase that was never implemented, and that could not be implemented without first inventing a canonical Markdown form (bullet character, emphasis delimiter, heading style, wrap policy) that nothing ever specified.

`prd/constraints.md`'s Edit Fidelity constraint makes that approach unusable regardless: writing a Note must leave every byte the user did not edit identical, and an AST-to-Markdown serializer rewrites the whole file by definition. Since CAP-EDIT-01 made editing *raw*, the editor already holds exactly the bytes belonging in the edited Block's span, so the save phase reduces to replacing those bytes. Nothing is reconstructed. See `tech-spec/adrs/ADR-007-span-preserving-splice-edits.md`.

## Why three write tiers rather than one

Draft rows absorb crash durability, so file writes need not be per-keystroke; file writes make the bundle correct on disk, so commits need not be per-write. The commit boundary is the editing *session* — closing the Note — rather than a timer, so that version history reads as one entry per Note per sitting instead of arbitrary time slices splitting a single thought. The accepted cost is that a Note left open for hours is written but uncommitted, and therefore unpushed, for hours. See `tech-spec/adrs/ADR-008-save-and-commit-granularity.md`.

## `block_path` is not stable across a commit

A splice can change a Block's node shape — a paragraph that gains a leading `- ` reparses as a list. The Presentation Container must therefore re-derive focus from the returned `NoteState` rather than retaining a path across a mutation. This is a real constraint on the UI, not an implementation detail.
