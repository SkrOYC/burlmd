# ADR-017: Private GitHub Remote Through GitHub App Device Flow

**Status:** Accepted for final contract reconciliation
**Supersedes:** ADR-009 and the OAuth redirect contract in `ffi_api.rs`

## Context

This phase supports private GitHub repositories only. GitLab and other providers are deferred until the complete GitHub lifecycle works. A desktop binary cannot safely contain a GitHub App private key or client secret. GitHub documents device flow for desktop applications and permits a GitHub App user access token to authenticate HTTP Git when the App has Contents permission.

## Decision

1. Burlmd uses one registered GitHub App with device flow enabled. The desktop binary contains the public client ID only; it contains no client secret, App private key, installation token minting authority, or callback listener.
2. Core requests a device code, shows GitHub's verification URI and user code, and polls the token endpoint at no less than the returned interval. It handles pending and `slow_down` as retryable states; expiry and denial as terminal authorization outcomes; `bad_verification_code` by restarting device flow; `unverified_user_email` by prompting the Writer to verify their primary email address before restarting; and `unsupported_grant_type`, `incorrect_client_credentials`, `incorrect_device_code`, and `device_flow_disabled` as non-retryable configuration or protocol failures.
3. Expiring user access tokens and refresh tokens are stored only in Platform secure storage. Refresh is serialized and rotates the stored pair atomically. Burlmd refreshes before known access-token expiry or after one authenticated `401`, then retries the failed operation at most once. A second `401` after refresh becomes authentication-required without another retry. Only a definitively rejected or expired refresh token returns to device authorization, without deleting local Workspace state.
4. The GitHub App requests repository Contents read/write for HTTP Git. Private-repository provisioning additionally requires Administration write; the connection UI explains that permission before authorization. Metadata read is implicit. No Workflows or webhook permission is requested. Before first publication and every later push, Core rejects the operation if any commit reachable from a local publication ref contains `.github/workflows/**`. The Writer can use Consolidation to copy Notes and Assets into a clean Workspace without publishing guest automation history.
5. The user access token is used as the HTTP Git credential and for GitHub REST calls. Burlmd verifies the App installation and accessible repository set before attach. A newly provisioned repository is private, empty, and covered by the installation before the first push; if installation coverage isn't present, attach pauses for the user to grant it.
6. Existing repository adoption is limited to a private, empty repository or the exact Remote this Workspace previously published. Public repositories are refused in this phase.
7. Git credentials are supplied ephemerally to the version-locked Git process and never written into a remote URL, Git configuration, diagnostics, or Note repository.
8. Requests use the current pinned GitHub REST API version selected by final Stage 3. Rate limits, offline state, service errors, and authorization expiry preserve credentials unless GitHub definitively rejects them.

## Consequences

- The old PKCE redirect functions and `BURLMD_GITHUB_CLIENT_SECRET` path must be removed, not maintained as a second flow.
- The provider registry isn't built in this phase. The architecture retains a Remote boundary so a later provider remains possible without pretending GitLab is current work.
- Private repository creation needs a high-level Administration permission; selection of an existing repository can avoid invoking that endpoint but doesn't change the App's registered permission set.
- A Workspace with reachable GitHub Actions workflow history remains locally usable but can't connect or synchronize through burlmd. This boundary avoids granting workflow-modification authority for guest automation files.
- Release testing requires a dedicated test installation and private repositories; tokens and repository contents never enter fixtures or logs.

## Verification anchors

- <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app>
- <https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app>
- <https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps>
