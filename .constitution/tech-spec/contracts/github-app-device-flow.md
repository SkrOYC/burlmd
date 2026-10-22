# GitHub App device-flow contract

## Status

ADR-017 and this companion are the active decision and field-level contract. The legacy `github-app-device-flow.toml` file has been removed (preserved in Git history) and isn't implementation authority. BURL-K001 creates the code-owned artifact at the sidecar's `artifact_path` and reports compatibility drift. Only a reviewed Stage 3 pass updates the sidecar or protocol contract after implementation evidence settles it.

## Protocol pins

GitHub REST requests use `https://api.github.com`, `Accept: application/vnd.github+json`, and `X-GitHub-Api-Version: 2026-03-10`. The version and headers were checked against current official GitHub documentation on October 14, 2026. OAuth endpoint requests set `Accept: application/json` and don't send the REST API version header.

Device authorization sends `POST https://github.com/login/device/code` with only `client_id`. A successful response contains `device_code`, `user_code`, `verification_uri`, `expires_in`, and `interval`.

Polling sends `POST https://github.com/login/oauth/access_token` with `client_id`, `device_code`, and `grant_type=urn:ietf:params:oauth:grant-type:device_code`. It never polls faster than `interval`; `slow_down` adds five seconds. Success requires `access_token`, `expires_in`, `refresh_token`, `refresh_token_expires_in`, an empty `scope`, and bearer `token_type`.

`authorization_pending` and `slow_down` are retry states. `access_denied` is terminal for the attempt. `expired_token`, `token_expired`, and `bad_verification_code` discard the code and can start a new device flow. `unverified_user_email` requires Writer action before restart. `unsupported_grant_type`, `incorrect_client_credentials`, `incorrect_device_code`, and `device_flow_disabled` are typed configuration or protocol refusals.

Refresh sends `POST https://github.com/login/oauth/access_token` with `client_id`, `grant_type=refresh_token`, and the current refresh token. Success requires the same complete token pair and lifetime fields as authorization. A partial or malformed response never replaces the stored pair.

## Public state

Presentation can receive a verification URI, user code, absolute expiry, minimum polling interval, and a typed authorization state. It never receives the device code, access token, refresh token, Git credential, installation credential, or secure-storage locator.

The authorization state distinguishes pending, slowed polling, approved, denied, expired, cancelled, email verification required, and configuration or protocol refusal. Cancellation stops polling and preserves the local Workspace. Approval doesn't attach or publish a Workspace by itself.

## Credential state

Core stores one access and refresh token pair with both expiries in Platform secure storage. Rotation is serialized and atomic: a partial response or storage failure preserves the preceding complete pair. Core refreshes before known expiry or after one authenticated `401 Unauthorized` response, then retries the original operation once. A second authenticated `401 Unauthorized` response requires authorization without another retry.

Provider credentials cross no Dart, Workspace, Git configuration, remote URL, diagnostics, or evidence boundary. Git receives an ephemeral credential for one process invocation only.

## Repository eligibility

Provider responses identify the installation and candidate repository without becoming history authority. A provisioned repository is private, empty, and covered by the installation. An existing repository is private and either empty or the exact Remote that the Workspace previously published. Reachable `.github/workflows/**` history refuses publication while local use remains available.

Consolidation is deferred and the first synchronization milestone offers no Consolidation UI. If workflow-bearing history blocks connection, the application explains that the Writer can manually transfer Notes and Assets into a fresh conforming Workspace. It doesn't modify workflow history or request Workflows permission.

## Live verification boundary

BURL-K001 through BURL-K003 use the real application, Core, secure-storage path, and HTTP client against a protocol-faithful synthetic Provider. That fixture proves the contract's requests, polling, states, token handling, and repository outcomes without a fake Rust API. It doesn't prove GitHub compatibility or browser authorization.

Real-provider acceptance follows after K implementation exists. N011 setup uses burlmd's device flow with a dedicated test installation, private repositories, synthetic Notes, and separately scoped Object Store resources. A pasted personal access token, inherited GitHub CLI session, or automated browser action cannot substitute. The Writer controls browser approval before the autonomous synchronization wave. The wave plan names the resources and permitted creation, mutation, and cleanup without recording secrets.

## Verification anchor

[GitHub App user access tokens through device flow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token-for-a-github-app) was checked on October 14, 2026.
