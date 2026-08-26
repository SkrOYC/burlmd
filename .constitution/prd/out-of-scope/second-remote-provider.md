# Second Remote provider

**Context:** CAP-SYNC-09 proposed matching Remote behavior through another hosting provider.

**Decision:** Deferred.

**Reason:** The reference private-Remote connection must pass authorization, provisioning, synchronization, reconciliation, detachment, Consolidation, and release verification before a second provider expands the matrix. The deferred capability remains technology-neutral.

**Consequences:** Architecture and Tasks must preserve a provider boundary but must not schedule a second provider. A Product Requirements Evolution pass can restore CAP-SYNC-09 after the reference provider passes the complete release matrix.
