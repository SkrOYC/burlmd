# Execution Flow: Note & Directory Lifecycle

**Maps to PRD Capability:** CAP-LIFE-01 (create a Note in a chosen Directory), CAP-LIFE-02 (rename with inbound Links updated), CAP-LIFE-03 (move with inbound Links updated), CAP-LIFE-04 (delete recoverable from version history), CAP-LIFE-05 (create Directories nested to arbitrary depth). Also establishes CAP-PORT-01 for created Notes: a Note conforms to the Open Knowledge Format from the moment of creation.

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository

    UI->>Core: Create Note (directory, title)
    Core->>Core: Derive filename from title verbatim
    alt Path occupied, reserved, or underivable
        Core-->>UI: Path unavailable — the user retitles; nothing is silently altered
    else Path available
        Core->>Local: Write conformant frontmatter + body atomically
        Core->>Local: Index the new Note (notes, search, links)
        Core-->>UI: State of the opened Note
    end

    UI->>Core: Rename or Move Note (identity, new path)
    Core->>Local: Begin: filesystem journal + index transaction
    Core->>Local: Move the file
    Core->>Local: Rewrite every inbound Link's target in its source Note
    Core->>Local: Cascade identity through index rows
    alt Any step fails
        Core->>Local: Unwind the journal; roll back the transaction
        Core-->>UI: Failure reported; file tree, index and Link text all exactly as before
    else All steps succeed
        Core->>Local: One atomic commit covering exactly the touched paths
        Core-->>UI: New state + the list of rewritten source Notes so open views can refresh
    end

    UI->>Core: Delete Note (confirmed in the UI first)
    Core->>Local: Remove file, index rows, search entry — one transaction
    Core->>Local: Commit the deletion
    Note over Local: Recovery is version history (CAP-WS-02), not an undo stack
```

## Why rename is drawn as one atomic operation

A Note's identity is its path. Renaming therefore changes the identity every inbound Link names, and a rewrite that stops halfway leaves dangling Links indistinguishable from deliberate ghost Links — silent graph decay (`risks.md` risk 8). The operation is atomic across three stores at once: files, index rows, and Link text inside other Notes' sources.

## Failure path

- **Collision or reserved name:** refused before anything moves; the user chooses again.
- **Mid-operation failure:** the journal unwinds completed renames and the transaction rolls back, leaving no partial state — proven by the lifecycle tests that inject failures mid-sweep.
- **An unrewritable inbound Link:** aborts the whole operation rather than being skipped. The sweep is a precondition, not a best effort.
- **Open Notes holding rewritten Links:** the Core reports which Notes it rewrote so their open buffers, span maps and recorded revisions move forward too — otherwise their next idle write would copy the old Link text back over the correction.

## Directory operations follow the same shape

Creating, renaming, moving and deleting Directories reuse this discipline, including the identity remapping returned when a rename changes the ids of every Note beneath it.
