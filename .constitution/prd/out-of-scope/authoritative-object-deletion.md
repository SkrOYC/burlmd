---
decision: deferred
date: 2026-08-26
---
# Authoritative Object deletion

**Decision:** Deferred during `0.x`.

**Reason:** Git refs and a generic S3-compatible Object Store don't share an atomic transaction. A device can prove an Object unreachable while another device or guest Remote push publishes a reference before deletion completes. A burlmd-only lease can't constrain guest pushes, so a 30-day scan doesn't prevent published history from losing its bytes.

**Current behavior:** burlmd can evict a local cache copy after 30 unused days when the Object Store contains a verified copy and no active Note needs it offline. burlmd doesn't delete the authoritative Object Store copy.

**Reopen condition:** Reconsider deletion only after the supported Remote and every accepted S3-compatible backend provide a measured protocol that serializes publication with deletion or guarantees recoverable versions across the race. The protocol must survive offline devices, guest Remote pushes, interruption, and provider lifecycle policies without depending on a burlmd-operated service.
