# Object-Store-only Workspaces

**Context:** A Workspace could store authoritative Asset bytes only in the Object Store and hydrate them on demand.

**Decision:** Deferred.

**Reason:** The accepted phase requires active Assets to remain available through portable local paths. The hybrid Local Asset Store, version history, and Object Store model must prove integrity, migration, hydration, and recovery first.

**Consequences:** Architecture must retain a Local Asset Store. Tasks must not make the Object Store the sole authoritative location for active Asset bytes.
