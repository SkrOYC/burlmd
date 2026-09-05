---
id: ADR-0016
status: proposed
date: 2026-08-26
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-016: Hybrid Local Assets and S3-Compatible Objects

**Status:** Proposed; implementation-blocking Spike
**Decision owner:** SPK-BURL-I001, measured PRD and Architecture review, then final Technical Implementation evolution

## Context

The product requires standard Markdown image paths that work offline and a Writer-controlled S3-compatible Object Store. `BND-06` keeps verified local bytes. `BND-11` owns transfer and privacy verification, and `BND-21` stores external immutable bytes. Git retains Notes and small textual manifests through Remote (`BND-20`); it must not carry binary payload history. Provider (`BND-14`) authorizes and locates that Remote but doesn't transfer or store Objects. The exact content hash, filename, manifest, client library, image limit, and repository-health warning remain evidence-dependent.

## Candidate decision

1. Imported bytes are copied into the bundle-root `assets/objects/` Local Asset Store before a Note references them. Source files outside the Workspace confer no authority after import.
2. Active files use canonical hash-derived names. A small canonical Git-committed manifest contains only immutable identity, content hash, media facts derived from those bytes, and remote-key facts. It doesn't contain hydration state, verification status or time, cache-use time, retry state, credentials, or other mutable device state. Those values belong to Application State and remain rebuildable or device-local. The manifest never becomes a second source of Note references. Core staging and commit operations exclude `assets/objects/**` independently of `.gitignore`, ambient Git configuration, and broad caller pathspecs. Git retains the textual manifest, never binary payload bytes.
3. S3-compatible keys are content-addressed beneath the configured Workspace prefix. Endpoint, region, bucket, prefix, and addressing style are non-secret configuration; credentials stay in Platform secure storage.
4. Connection validation proves authenticated list, read, write, and delete with disposable probe objects and rejects anonymous list, read, write, or delete access. Burlmd doesn't mutate bucket policy or provision accounts.
5. Reachability is derived from the canonical AST across every protected state defined by PRD v1.3.2. Age never overrides protected reachability.
6. A verified `BND-21` Object Store copy permits local cache eviction after 30 unused days when no active Note needs the bytes offline. During `0.x`, burlmd never deletes authoritative Object Store bytes. `BND-20` Git refs and S3-compatible `BND-21` storage can't make publication and deletion atomic. Guest Remote pushes also can't honor a burlmd-only lease.
7. Plain-copy and `.okf` Export hydrate and verify the full referenced object closure before atomically publishing output.

## Evidence required

SPK-BURL-I001 compares the official AWS SDK for Rust with `object_store` using at least AWS S3 and one non-AWS S3-compatible fixture when credentials are safely available; otherwise it must use a protocol-faithful local service and flag cloud compatibility unverified. It measures content identity, deduplication, manifest round trips, decode memory and dimensions, the provisional 25 MiB limit, offline behavior, hydration, protected-history traversal, local cache eviction, and textual repository growth. OD-06 and OD-07 remain open until the measured PRD evolution.

## Consequences

- The asset Spike may use candidate libraries in its isolated manifest only.
- S3-only Workspaces, a burlmd-operated object service, Git LFS, and encrypted remote objects remain outside this phase.
- Detaching the Object Store must preserve required authoritative bytes locally; it cannot strand referenced assets.

## Verification anchors

- <https://docs.rs/aws-sdk-s3/latest/aws_sdk_s3/config/struct.Builder.html>
- <https://docs.rs/object_store/0.14.1/object_store/aws/struct.AmazonS3Builder.html>
