# ADR-009: Provider-Neutral Git Hosting Seam, GitHub First

**Status:** Accepted

## Context
Operator intent names GitHub and GitLab, and the realignment interview made GitLab required scope at P1 while sequencing it behind a proven GitHub surface (rulings Q3 and B5). `workspaces.provider` has carried a provider value since the schema existed, but nothing constrains what "adding a provider" touches — the risk is a connect path that ossifies around one vendor's API shapes and makes the second provider a rewrite.

## Decision
1. **`connect_remote(provider, ...)` is a registry dispatch, not a branch.** Each provider supplies one module implementing a small surface: OAuth authorization (PKCE), token storage naming, repository provisioning, repository emptiness verification, and HTTPS remote URL construction. The sync machinery itself — fetch, merge, push — is already provider-agnostic because it speaks Git.
2. **GitHub implements the surface first**, as the proven case. GitLab (CAP-SYNC-09) is the second consumer, landing in a later wave per B5; its implementation may adjust the surface *once*, before a third provider could exist.
3. **Adding a provider must be additive:** a new module plus a registry entry. No function signature in `contracts/ffi_api.rs` changes, no existing provider's module is edited, and no caller branches on provider identity beyond registry lookup.
4. **Provider differences live inside their modules.** Scopes, API endpoints, rate limits, and error mapping are that module's private affair; the contract's types describe outcomes (`SessionState`, `WorkspaceInfo`), never vendor payloads.

## Consequences
- **Positive:** The seam costs almost nothing now — both target providers speak OAuth 2.0 PKCE over Git-HTTPS, and the existing CLI-based push/pull split already treats hosting as interchangeable.
- **Positive:** GitLab arrives as integration work rather than architectural work, which is what P1-behind-GitHub sequencing requires.
- **Negative:** A provider whose model genuinely diverges (self-hosted instances, non-OAuth auth) will strain the "additive only" rule; that strain is the signal to revisit this ADR rather than to special-case at call sites.
- **Neutral:** The registry starts with exactly two intended entries. Abstraction for imagined third providers is explicitly not built.
