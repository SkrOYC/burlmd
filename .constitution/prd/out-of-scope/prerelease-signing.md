---
decision: deferred
date: 2026-08-26
---
# Prerelease signing and notarization

**Context:** Direct distribution can add platform trust signing before the product reaches stability.

**Decision:** Deferred during `0.x`.

**Reason:** The user chose to defer signing until the product is stable. Prereleases must identify the unsigned status and provide accurate installation guidance.

**Consequences:** Signing and notarization become release-blocking when the user declares the first stable release. Earlier Tasks must not treat signing credentials as available.
