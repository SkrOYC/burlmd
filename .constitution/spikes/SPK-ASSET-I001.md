# Spike report: ASSET-I001 Hybrid assets and S3-compatible objects

## Time box

- **Budget:** 3 focused days
- **Clock start / stop:** fill during execution

## Question

- **Decision this spike must produce:** Which S3-compatible client and physical asset/object contract satisfy offline authority, protected reachability, safe retention, and measured image/repository limits?

## Context and objective

- **Triggering upstream file or section:** `.constitution/tech-spec/adrs/ADR-016-hybrid-local-assets-and-s3-compatible-objects.md`
- **Target:** immutable manifest, content identity, Local Asset Store, device-local object state, S3-compatible operations, hydration, and retention
- **Archetype / surface:** System/Native local-first storage with a user-controlled remote object boundary

## Codebase baseline

- **State today:** No production asset/object schema or S3-compatible client exists; images aren't complete user-facing behavior.
- **Discovered constraints:** AST references are authoritative for active use; protected Git/reconciliation states override age; credentials remain in Platform secure storage; local Note work survives Object Store failure. During `0.x`, burlmd can evict verified local cache copies but can't delete authoritative Object Store bytes because Git publication and generic S3-compatible deletion aren't atomic. Reference-profile evidence must come from distinct Linux and macOS hosts whose CPU, cores, memory, storage, graphics, display, power, and thermal facts are captured through system APIs and match the PRD. The hosts exchange only opaque SHA-256-verified handoff bundles.

## Options and trade-offs

- Compare `aws-sdk-s3` 1.144.0 plus `aws-config` 1.11.0 with `object_store` 0.14.1 using identical fixtures and safe protocol endpoints.

## Recommendation

- **Chosen option:** fill during execution
- **Why it fits:** tie the choice to interoperability, operational burden, offline behavior, security, retention correctness, and measured resource costs
- **Rejected options:** fill one evidence-backed line per rejected candidate

## Downstream impact

- **ADRs to write or update:** accept/replace ADR-016 and define final manifest, state, credential, and object-key contracts
- **Tickets unblocked in `tasks/active/`:** STORE-I002, OBJECT-I004, and HEALTH-M004 directly; the remaining Asset/Object tickets, Export, Consolidation, synchronization, and release tickets transitively, including ROTATE-I008, MIGRATE-I011, and DETACH-I012
- **Tickets to add or split:** adapt the planned Asset/Object and history-health tickets when the accepted client, manifest, image limit, or history threshold changes scope
- **Spec edits required:** Product Requirements for OD-06/OD-07; Architecture review if thresholds change flows; final Technical Implementation
