# Provisional Forward Data Models

## Status

These are required physical model families. The device-preference and Workspace-session contracts are specified for the Epic G production exceptions. Names, columns, serialization formats, hashes, and migration versions for the remaining families remain blocked by the Spikes named below. Research Tasks must not modify `schema.sql` to guess them.

## Canonical Core state

The final model must define one Workspace tree containing Directory, Note, and Local Asset Store entries. Each open Note owns one coherent document revision: original source, canonical extended AST, exact source ranges, editable identities, conformance state, draft state, and the on-disk revision used for optimistic concurrency. SPK-AST-H001 chooses the standards foundation; SPK-PATH-H002 chooses path identity. Render projections and derived index rows are disposable views of this state.

## Device and Workspace application state

Device preferences use one versioned JSON file in Platform application-support data. The file is not part of a Workspace, Git history, or `schema.sql`. The persistence layer replaces it atomically by writing a temporary file and renaming it. Unknown `schema_version` values or corrupt bytes produce in-memory defaults, isolate the corrupt file, and do not crash the application. Version 1 defines `schema_version`, `theme`, `font_scale`, `measure`, `focus_mode`, and `update_notifications` in `device-preferences.schema.json`. `platform_chrome` must not appear because SHELL-G001 removes that preference. When `update_notifications` is true, burlmd checks for and notifies the Writer about compatible higher `0.x` releases under UPDATE-M010. When it is false, burlmd does not check.

The Core owns each versioned Workspace session snapshot. The JSON representation, or an equivalent Core format, is outside Note files, Git history, and `schema.sql` derived-index tables. Snapshot storage is partitioned by Workspace ID. The persistence layer replaces a snapshot atomically by writing a temporary file and renaming it. Corrupt bytes produce an empty default session for only the affected Workspace, isolate the corrupt bytes, and do not crash the application. A snapshot contains no Note body, credential, or device preference. Version 1 in `workspace-session-snapshot.schema.json` defines `schema_version`, `workspace_id`, `open_note_ids` in restore order, `active_note_id`, `expanded_directory_ids`, `search_query`, and presentation-only `sync_presentation`. The closed v1 `sync_presentation` values are `local`, `connected`, and `paused`. A later value requires a schema-version bump and does not define a Git reconciliation state machine.

## Conformance and external-change state

Preflight and live observation require durable or reconstructable records for excluded paths, last-known-good Note revisions, preserved external bytes, and pending External Change Decisions. These states are separate from Git reconciliation and never generate Suggestion nodes. Final schemas depend on the canonical path and document decisions.

## Assets and objects

The final asset model must define:

- a canonical content identity and hash-derived local filename;
- a small textual manifest committed with Notes that contains only immutable identity, content hash, byte-derived media facts, and remote-key facts;
- device-local hydration status, verification status and time, cache-use time, and retry state outside the canonical manifest;
- S3-compatible endpoint, region, bucket, prefix, and addressing-style configuration without secrets;
- protected-state reachability evidence, last-used time, deletion eligibility, and incomplete-check reasons;
- pending Asset Decisions containing both candidates without choosing one implicitly.

SPK-ASSET-I001 settles the concrete representation. No result may make the manifest, object store, or derived index override a conforming AST reference as authority for active use.

## Git reconciliation

The final model must persist enough typed analysis state to resume or safely abandon a reconciliation: exact base/local/incoming identities, affected paths and Git stages, content Suggestions, Lifecycle Decisions, Asset Decisions, preserved candidates, and an expiry/revalidation token. SPK-GIT-L001 settles which Git outputs populate that model. Working-tree marker text isn't an identity or completeness proof.

## Release metadata

The final release contract must identify version, source revision, platform, architecture, artifact kind, checksum, minimum runtime, signature state, feature-matrix result, and GitHub Release URL. SPK-PKG-M001 settles the Linux runtime values and construction inputs. Signing remains explicitly absent during `0.x`.
