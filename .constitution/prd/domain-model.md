# Domain Model

```mermaid
C4Context
    title Conceptual Domain Model

    Person(writer, "Writer", "A Markdown-literate knowledge worker authoring and organizing Notes.")
    Person_Ext(agent, "Agent", "An external tool or AI agent reading the Workspace directly from disk.")

    System_Boundary(workspace_boundary, "Workspace") {
        System(directory, "Directory", "Hierarchical container for organizing Notes.")
        System(note, "Note", "A distinct unit of knowledge.")
        System(block, "Block", "A distinct structural element within a Note.")
        System(link, "Link", "A lateral connection from one Note to another.")
        System(suggestion, "Suggestion", "An unresolved divergence between two concurrent versions of a Block.")
    }

    System_Ext(remote, "Remote", "The user's private hosted repository. Optional — attached only once the user connects the Workspace.")

    Rel(writer, note, "Creates, edits, reads, deletes")
    Rel(writer, directory, "Organizes")
    Rel(writer, suggestion, "Accepts or rejects")
    Rel(agent, note, "Reads")
    Rel(agent, link, "Traverses")
    Rel(directory, note, "Contains (1:N)")
    Rel(directory, directory, "Nests (1:N)")
    Rel(note, block, "Composed of (1:N)")
    Rel(block, link, "Contains")
    Rel(link, note, "Targets (may be unresolved)")
    Rel(block, suggestion, "May be superseded by")
    Rel(workspace_boundary, remote, "Syncs to/from, once connected")
```

## Notes on the model
- A **Workspace** is complete without a **Remote**. The Remote is an optional attachment that adds multi-device synchronization; every other relationship in this diagram holds with no Remote present.
- A **Link** may target a Note that does not exist yet. Such a Link remains valid and traversable as an intent, and resolves once the target Note is created.
- A **Suggestion** exists only transiently, between the discovery of concurrent edits and the user's decision. It is a state a Block can be in, not a separate stored artifact.
- The **Agent** reads the same on-disk Workspace the Writer edits, with no export, API, or running application in between. This is why on-disk format conformance is a continuous requirement rather than a feature of an export path.
