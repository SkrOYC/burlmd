---
version: v1.0.0
---

# Active Backlog Summary

**Total Active Story Points:** 52

## Critical Path
1. CORE-A001
2. CORE-A002
3. CORE-A003
4. UIDB-B001
5. UIDB-B002
6. UIDB-B003
7. UIDB-B004
8. UIDB-B005
9. SYNC-C001
10. SYNC-C002
11. SYNC-C003
12. SYNC-C004
13. SYNC-C005
14. SYNC-C006

## Build Order Diagram

```mermaid
flowchart LR
    A001[CORE-A001] --> A002[CORE-A002]
    A001 --> B001[UIDB-B001]
    A001 --> B003[UIDB-B003]
    
    A002 --> A003[CORE-A003]
    
    A003 --> B002[UIDB-B002]
    B001 --> B002
    
    B002 --> B004[UIDB-B004]
    B003 --> B004
    B004 --> B005[UIDB-B005]
    
    B001 --> C001[SYNC-C001]
    C001 --> C002[SYNC-C002]
    C001 --> C003[SYNC-C003]
    
    C002 --> C004[SYNC-C004]
    B002 --> C004
    
    B003 --> C005[SYNC-C005]
    
    C004 --> C006[SYNC-C006]
    C005 --> C006
```

## Phasing Strategy
- **In-Scope (Current Phase):** Desktop target exclusively (macOS/Linux). Core FFI parsing, encrypted SQLite storage, and background GitHub sync using OAuth.
- **Deferred (Future Scope):** Mobile targets (iOS/Android) cross-compilation, graph visualization UI, and GitLab support.
