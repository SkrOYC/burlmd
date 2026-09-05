---
id: ADR-0009
status: superseded
superseded_by: ADR-0017
date: 2026-08-21
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-009: Provider-Neutral Git Hosting Seam, GitHub First

**Status:** Superseded by ADR-017 for the current phase

## Context
Earlier planning named GitHub and GitLab together. PRD v1.3.2 now limits this phase to a complete private GitHub lifecycle and defers every second provider until that lifecycle works. ADR-017 also replaces the assumed PKCE redirect flow with GitHub App device flow.

Architecture v2.1.1 makes the seam precise. Provider (`BND-14`) owns authorization, eligible private-Remote selection or provisioning, and location. Remote (`BND-20`) owns authenticated history and ref exchange. Object Store (`BND-21`) owns Object bytes through the separate `BND-11` coordinator. ADR-017 supersedes any language that assigned Git transfer to a provider module.

## Decision
1. **`connect_remote(provider, ...)` is a registry dispatch, not a branch.** Each provider supplies authorization, token storage naming, repository provisioning and eligibility checks, and HTTPS Remote location construction. The `BND-10` sync machinery fetches from and pushes to `BND-20`; Provider never owns history exchange.
2. **GitHub implements the surface first**, as the proven case. A second provider is deferred until the private GitHub lifecycle works; its implementation may adjust the surface *once*, before a third provider could exist.
3. **Adding a provider must be additive:** a new module plus a registry entry. No function signature in `contracts/ffi_api.rs` changes, no existing provider's module is edited, and no caller branches on provider identity beyond registry lookup.
4. **Provider differences live inside their modules.** Scopes, API endpoints, rate limits, and error mapping are that module's private affair; the contract's types describe outcomes (`SessionState`, `WorkspaceInfo`), never vendor payloads.

## Consequences
- **Positive:** The seam costs almost nothing now — both target providers speak OAuth 2.0 PKCE over Git-HTTPS, and the existing CLI-based push/pull split already treats hosting as interchangeable.
- **Positive:** GitLab arrives as integration work rather than architectural work, which is what P1-behind-GitHub sequencing requires.
- **Negative:** A provider whose model genuinely diverges (self-hosted instances, non-OAuth auth) will strain the "additive only" rule; that strain is the signal to revisit this ADR rather than to special-case at call sites.
- **Neutral:** The registry starts with exactly two intended entries. Abstraction for imagined third providers is explicitly not built.
