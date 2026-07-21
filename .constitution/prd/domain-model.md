# Domain Model

```mermaid
C4Context
    title Conceptual Domain Model

    Person(consumer, "General Consumer", "A knowledge worker writing and organizing notes.")
    
    System_Boundary(workspace_boundary, "Workspace") {
        System(directory, "Directory", "Hierarchical container for organizing notes.")
        System(note, "Note", "A distinct unit of knowledge (concept).")
        System(block, "Block", "A distinct structural element in a Note.")
        System(link, "Link", "A connection between two Notes.")
    }
    
    System_Ext(remote_repo, "Remote Repository", "The user's private Git repository (e.g., GitHub) acting as the synchronization backend.")

    Rel(consumer, note, "Creates, edits, reads")
    Rel(consumer, directory, "Organizes")
    Rel(directory, note, "Contains (1:N)")
    Rel(directory, directory, "Nests (1:N)")
    Rel(note, block, "Composed of (1:N)")
    Rel(note, link, "Contains")
    Rel(link, note, "Targets")
    Rel(workspace_boundary, remote_repo, "Syncs to/from via OAuth")
```
