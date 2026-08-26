# Full history diff viewer

**Context:** A full viewer could compare arbitrary versions across a Note's complete history.

**Decision:** Deferred.

**Reason:** Version listing and confirmed restore satisfy recovery. The external-change comparison surface serves a narrower authority decision and isn't a general history browser.

**Consequences:** Tasks can implement version list and restore, but must not expand the comparison surface into a full history diff viewer without Product Requirements Evolution.
