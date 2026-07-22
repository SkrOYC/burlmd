---
version: v1.1.0
---

# Active Backlog Summary

**Total Active Story Points:** 39

## Critical Path
1. UIDB-B001
2. UIDB-B002
3. UIDB-B003
4. UIDB-B004
5. UIDB-B005
6. UIDB-B006
7. UIDB-B007
8. SYNC-C001
9. SYNC-C002
10. SYNC-C003

## Build Order Diagram

```mermaid
flowchart LR
    subgraph Completed [Completed - Epic A]
        A001[CORE-A001] --> A002[CORE-A002]
        A002 --> A003[CORE-A003]
    end

    A001 --> B001[UIDB-B001]
    A001 --> B005[UIDB-B005]

    B001 --> B002[UIDB-B002]
    B002 --> B003[UIDB-B003]

    A003 --> B004[UIDB-B004]
    B003 --> B004

    B004 --> B006[UIDB-B006]
    B005 --> B006
    B006 --> B007[UIDB-B007]

    B004 --> C001[SYNC-C001]
    B005 --> C002[SYNC-C002]

    C001 --> C003[SYNC-C003]
    C002 --> C003
```

## Phasing Strategy
- **In-Scope (Current Phase):** Desktop target exclusively (macOS/Linux). Core FFI parsing, encrypted SQLite storage, and background GitHub sync using OAuth.
- **Deferred (Future Scope):** Mobile targets (iOS/Android) cross-compilation, graph visualization UI, and GitLab support.
