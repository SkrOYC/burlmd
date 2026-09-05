# Tasks interview record — delegated dependency rulings

**Date:** 2026-09-04
**Target:** Tasks
**Mode:** Evolution within the ongoing structured-constitution Realign

This record is limited to decisions already delegated by the user. On 2026-09-04, the user proposed discarding or postponing the constitution work and said, “Your call.” The lead chose to complete the structured realignment. After two pull-request review passes exposed the remaining executable-graph contradictions, the lead applied that delegation to OD-09 and OD-10. The interview framework says to take the framework recommendation when the user delegates a decision. These rulings therefore require no further question.

No Stage 4 files change in this interview. The next Tasks Evolution pass applies these rulings, assigns any new epic and ticket identifiers, rewrites the epic graph, and renders the critical path.

## Evidence considered

- `.constitution/research/tranche-sequence.md` already authorizes the partial Epic M bootstrap as `BURL-M015` followed by `BURL-M003`, then a separate evidence pull request that completes `BURL-M003`. It explicitly says this tranche does not complete Epic M.
- The `.constitution/tasks/epics/EPIC-M-quality-releases.yaml` file makes M a dependency-free root because every later epic needs the managed-validation matrix. The file also contains release and quality tickets whose original prerequisites point back to completed product work. Keeping both directions in one epic cannot represent the true ordering without a cycle.
- The Stage 4 contract permits cross-epic ordering only through epic dependencies. Ticket dependencies remain inside their own epic, so a validator-compliant replan must cut the graph where the direction reverses.
- The `.constitution/tasks/epics/EPIC-I-assets-object-store.yaml` file keeps Object identity and retention upstream in `BURL-I007`. The `BURL-I011`, `BURL-I012`, and `BURL-I013` lifecycle operations require the complete Remote-ref authority from `BURL-L010`. The `.constitution/tasks/epics/EPIC-L-sync-reconciliation.yaml` file defines that authority. `BURL-I010` depends on all three lifecycle operations, so it cannot remain in Epic I after they move downstream.
- The rendered critical path is a seven-epic serial chain. Validation passes because the migration records the reverse dependencies in OD-09 and OD-10 instead of encoding them. Closing these decisions retires those interim omissions for the next Tasks plan.

## Delegated rulings

### OD-09 — split CI bootstrap from downstream release and quality work

Adopt the recommendation: *Split Epic M into a CI bootstrap epic and a release-gate epic.*

For executable planning, Epic M retains only `BURL-M015` and `BURL-M003`, in that order, matching the authorized CI bootstrap tranche. Every remaining current Epic M ticket moves to a later downstream release-and-quality epic. That later epic must depend on the product epics required by the dropped historical edges, so nightly meters, diagnostics, migration, packaging, installed-candidate gates, updates, and publication cannot start merely because the CI bootstrap exists.

This is planned release work, not an out-of-band issue. Stage 4 owns the added epic's identifier and the corresponding ticket identifier migration. Stage 4 also owns dependencies, scope, estimates, the changelog entry, and the rendered critical path.

### OD-10 — keep Object authority upstream and cut lifecycle reconciliation after L010

Adopt the recommended direction: *Epic I remains upstream, and the Object Store lifecycle work moves downstream of `BURL-L010`.*

The direction of authority remains unchanged. Epic I establishes Object identity and Protected State retention. Epic L consumes that foundation and implements complete Remote-ref enumeration in `BURL-L010`.

The implementation cut is more precise than placing the moved tickets directly into the Epic L file. Preserving all historical prerequisites without a cycle requires a downstream lifecycle-reconciliation epic that depends on Epic L. It carries `BURL-I011`, `BURL-I012`, and `BURL-I013` after `BURL-L010`. It also carries `BURL-I010`, whose dependency list consumes all three. Epic I remains upstream, and the added cut follows L's complete Remote-ref authority.

Stage 4 must preserve the moved tickets' existing upstream prerequisites, scope, and acceptance obligations when it assigns new identifiers. This interview settles the dependency direction and cut; it does not rename or rewrite the task artifacts.

## Historical and deferred register handling

- OD-03 remains closed with its original 2026-08-21 ruling and evidence. That ruling records the user's preference at that time for parallel design and synchronization tracks. The `.constitution/research/tranche-sequence.md` file and the OD-09 and OD-10 rulings supersede it for executable whole-epic scheduling.
- OD-07 and OD-08 remain open and unchanged. Their references resolve to the `BURL-M*` tickets and `SPK-BURL-M001`. Stage 4 must change them to the prospective O identifiers only after the downstream replan creates those artifacts.
- The migration-time interim assumptions on OD-09 and OD-10 are retired by these rulings and removed from the live register.

## Stage 4 handoff

Run a Tasks Evolution replan that applies both cuts together. Preserve the authorized named-tranche sequence. Keep M as the `BURL-M015` and `BURL-M003` bootstrap. Add the lifecycle-reconciliation cut after L and the release-and-quality cut after its product prerequisites. Migrate identifiers and register references atomically, then render and validate the graph. Until that pass creates the replacement artifacts, OD-07 and OD-08 keep their M references.
