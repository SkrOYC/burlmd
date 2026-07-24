//! OAuth web flow (ticket SYNC-C002): PKCE generation, GitHub authorize-URL
//! construction, and authorization-code-for-token exchange, with the
//! resulting tokens stored via the OS Keychain (`keyring`, same "service"
//! bucket as `security::keyring`) and never returned across the FFI
//! boundary to Dart.
//!
//! ## Verified against GitHub's current OAuth documentation
//! Checked 2026-07-24 against
//! <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps>,
//! corroborated by
//! <https://docs.github.com/en/apps/oauth-apps/maintaining-oauth-apps/troubleshooting-oauth-app-access-token-request-errors>,
//! <https://docs.github.com/en/apps/oauth-apps/maintaining-oauth-apps/troubleshooting-authorization-request-errors>,
//! and <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app>.
//!
//! - **Authorize endpoint:** `GET https://github.com/login/oauth/authorize`.
//!   `client_id` is "Required"; `redirect_uri`, `scope`, `state`,
//!   `code_challenge`, and `code_challenge_method` are all "Strongly
//!   recommended". `code_challenge_method` "Must be `S256` - the `plain`
//!   code challenge method is not supported".
//! - **Token endpoint:** `POST https://github.com/login/oauth/access_token`,
//!   with `Accept: application/json` for a JSON (rather than the default
//!   form-encoded) response body. `client_id`, `client_secret`, and `code`
//!   are "Required"; `redirect_uri` and `code_verifier` are "Strongly
//!   recommended" (`code_verifier` is "Required if `code_challenge` was sent
//!   during the user authorization" step, which this module always does).
//! - **`client_secret` is required even with PKCE.** The ticket's design
//!   assumed PKCE on a public client eliminates the need for a client
//!   secret — true for a generic RFC 8252 native-app PKCE flow, but GitHub's
//!   own docs contradict it here: the access-token parameter table lists
//!   `client_secret` as "Required" with no PKCE exception, for both classic
//!   OAuth Apps and GitHub Apps alike, and a wrong/missing secret fails with
//!   `incorrect_client_credentials` regardless of `code_verifier` being
//!   correct. PKCE is additive defense-in-depth against authorization-code
//!   interception on GitHub's implementation, not a substitute for the
//!   secret. Handled below by reading an *optional* secret from
//!   `BURLMD_GITHUB_CLIENT_SECRET` at runtime — never hardcoded, never
//!   committed — see "Deferred configuration" below.
//! - **Success response** (JSON): `{"access_token": "...", "token_type":
//!   "bearer", "scope": "..."}`. `expires_in` / `refresh_token` /
//!   `refresh_token_expires_in` are only present for a GitHub App that has
//!   opted into "Expire user access tokens" (default lifetime 8 hours,
//!   refresh token 6 months); they are absent entirely for a non-expiring
//!   configuration. All three are modeled as optional here for exactly that
//!   reason.
//! - **Failure response** (JSON): `{"error": "bad_verification_code",
//!   "error_description": "The code passed is incorrect or expired.",
//!   "error_uri": "..."}`. GitHub's docs document this JSON shape but are
//!   silent on which HTTP status accompanies it; GitHub's real, observed
//!   behavior is to report it via the `error` field on an otherwise-200
//!   response rather than a 4xx status, so [`exchange_code_for_token`]
//!   checks the body for an `error` field before falling back to a plain
//!   HTTP-status check. Mapped to [`AppError::OAuthError`].
//! - **Redirect-side errors** (query params on the loopback redirect,
//!   handled by the Dart UI before any of this module runs): `error=
//!   access_denied` ("The user has denied your application access."),
//!   `error=redirect_uri_mismatch`, `error=application_suspended`, each
//!   alongside an `error_description`.
//! - **Loopback redirect URIs:** "The optional `redirect_uri` parameter can
//!   also be used for loopback URLs, which is useful for native
//!   applications running on a desktop computer" — the host (excluding
//!   sub-domains) and port must match exactly what's registered, and RFC
//!   8252 (echoed by GitHub's own docs) recommends the loopback literal
//!   `127.0.0.1` over `localhost`. The Dart side binds an ephemeral port and
//!   passes the resulting `http://127.0.0.1:<port>/callback` in as
//!   `redirect_uri` to [`begin_oauth_flow`].
//!
//! ## Fixed-signature consequence
//! `authenticate_workspace`'s signature is dictated by
//! `tech-spec/contracts/ffi_api.rs` and takes no `redirect_uri` parameter.
//! Since `redirect_uri` is only "Strongly recommended" (not required) on the
//! token exchange, this implementation omits it from the exchange request
//! entirely rather than growing the contract to carry it through.
//!
//! ## Deferred configuration
//! No GitHub OAuth App/GitHub App is registered for this project yet.
//! `BURLMD_GITHUB_CLIENT_ID` / `BURLMD_GITHUB_CLIENT_SECRET` read the real
//! values at runtime; until a real app is registered and those are set,
//! [`begin_oauth_flow`] produces an authorize URL with an obviously-invalid
//! placeholder client id, and [`authenticate_workspace`] will fail the real
//! exchange against GitHub (loudly, via `AppError::OAuthError`/
//! `NetworkError`) rather than silently using a fake credential.

use std::sync::OnceLock;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::error::AppError;

const CLIENT_ID_ENV_VAR: &str = "BURLMD_GITHUB_CLIENT_ID";
const CLIENT_SECRET_ENV_VAR: &str = "BURLMD_GITHUB_CLIENT_SECRET";

/// No GitHub OAuth App is registered for this project yet. This placeholder
/// is deliberately not a plausible-looking id (real GitHub client ids are
/// `Iv1.<16 hex chars>` or `Ov23li<...>` style strings), so a deployment
/// that forgets to set `BURLMD_GITHUB_CLIENT_ID` fails loudly against the
/// real GitHub API instead of silently authorizing against nothing.
const CLIENT_ID_PLACEHOLDER: &str = "REPLACE_WITH_REGISTERED_GITHUB_OAUTH_CLIENT_ID";

/// The scope requested for the GitHub OAuth flow. `repo` grants the access
/// SYNC-C001's clone/push/pull operations need against private and public
/// repositories alike; revisit if a narrower scope (e.g. public-repo-only)
/// becomes desirable once real users exist.
const GITHUB_SCOPE: &str = "repo";

const KEYCHAIN_SERVICE: &str = "com.burlmd.app";
const ACCESS_TOKEN_ACCOUNT: &str = "github_access_token";
const REFRESH_TOKEN_ACCOUNT: &str = "github_refresh_token";
const ACCESS_TOKEN_EXPIRES_AT_ACCOUNT: &str = "github_access_token_expires_at";
const REFRESH_TOKEN_EXPIRES_AT_ACCOUNT: &str = "github_refresh_token_expires_at";

fn github_client_id() -> String {
    std::env::var(CLIENT_ID_ENV_VAR).unwrap_or_else(|_| CLIENT_ID_PLACEHOLDER.to_string())
}

/// See the module doc comment: GitHub requires `client_secret` on the token
/// exchange even with PKCE. Unlike the client id, no placeholder default is
/// compiled in — an absent env var means no `client_secret` is sent at all
/// (the exchange then fails against real GitHub with
/// `incorrect_client_credentials`, a correct and loud failure) rather than
/// a fake secret literal ever existing in source.
fn github_client_secret() -> Option<Zeroizing<String>> {
    std::env::var(CLIENT_SECRET_ENV_VAR)
        .ok()
        .map(Zeroizing::new)
}

/// The GitHub OAuth endpoints this module talks to. Injectable so tests can
/// point every call at a local mock HTTP server instead of the real
/// network.
///
/// Not `pub`, and deliberately given no `impl Default`/other well-known
/// public-std-trait impl: FRB's `rust_input: crate::api` scans every
/// struct/impl syntactically reachable under `crate::api`, and (confirmed
/// empirically) treats *any* impl of a public std trait — `Default`,
/// in an earlier version of this module — as exposing that method to Dart
/// regardless of the struct's own visibility, unlike plain non-`pub`
/// functions/structs, which it correctly leaves out of the generated
/// bindings. A plain constructor function ([`default_github_endpoints`])
/// sidesteps that trap entirely.
struct GitHubOAuthEndpoints {
    authorize_url: String,
    token_url: String,
    user_url: String,
}

fn default_github_endpoints() -> GitHubOAuthEndpoints {
    GitHubOAuthEndpoints {
        authorize_url: "https://github.com/login/oauth/authorize".to_string(),
        token_url: "https://github.com/login/oauth/access_token".to_string(),
        user_url: "https://api.github.com/user".to_string(),
    }
}

fn real_endpoints() -> &'static GitHubOAuthEndpoints {
    static ENDPOINTS: OnceLock<GitHubOAuthEndpoints> = OnceLock::new();
    ENDPOINTS.get_or_init(default_github_endpoints)
}

// ---------------------------------------------------------------------------
// PKCE (RFC 7636)
// ---------------------------------------------------------------------------

struct PkceChallenge {
    verifier: Zeroizing<String>,
    challenge: String,
}

/// Generates a fresh PKCE `code_verifier`/`code_challenge` pair. The
/// verifier is 32 CSPRNG bytes, base64url-encoded without padding (RFC
/// 7636 section 4.1's own recommended construction), which always yields
/// exactly 43 characters — squarely inside the RFC's required 43-128
/// character range, using only characters from its `unreserved` charset
/// (base64url's alphabet, `A-Za-z0-9-_`, is a strict subset of it).
fn generate_pkce() -> Result<PkceChallenge, AppError> {
    let verifier = random_url_safe_token()?;
    let challenge = s256_code_challenge(&verifier);
    Ok(PkceChallenge {
        verifier,
        challenge,
    })
}

/// RFC 7636 section 4.2: `code_challenge = BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))`.
fn s256_code_challenge(verifier: &str) -> String {
    let digest = Sha256::digest(verifier.as_bytes());
    URL_SAFE_NO_PAD.encode(digest)
}

/// A CSPRNG-backed, base64url (no padding) random token, used for both the
/// PKCE verifier and the OAuth `state` parameter.
fn random_url_safe_token() -> Result<Zeroizing<String>, AppError> {
    let mut bytes = Zeroizing::new([0u8; 32]);
    getrandom::fill(&mut *bytes)
        .map_err(|e| AppError::CryptoError(format!("OS CSPRNG failure: {e}")))?;
    Ok(Zeroizing::new(URL_SAFE_NO_PAD.encode(*bytes)))
}

fn build_authorize_url(
    endpoints: &GitHubOAuthEndpoints,
    client_id: &str,
    redirect_uri: &str,
    scope: &str,
    state: &str,
    code_challenge: &str,
) -> Result<String, AppError> {
    let mut url = url::Url::parse(&endpoints.authorize_url)
        .map_err(|e| AppError::OAuthError(format!("invalid authorize endpoint: {e}")))?;
    url.query_pairs_mut()
        .append_pair("client_id", client_id)
        .append_pair("redirect_uri", redirect_uri)
        .append_pair("scope", scope)
        .append_pair("state", state)
        .append_pair("code_challenge", code_challenge)
        .append_pair("code_challenge_method", "S256");
    Ok(url.to_string())
}

/// Both FFI entry points below (`begin_oauth_flow_impl`/
/// `authenticate_workspace_impl`) only support the `"github"` provider
/// today; centralizing the guard keeps the check and its error message in
/// exactly one place instead of two verbatim copies.
fn ensure_supported_provider(provider: &str) -> Result<(), AppError> {
    if provider != "github" {
        return Err(AppError::OAuthError(format!(
            "unsupported OAuth provider: {provider}"
        )));
    }
    Ok(())
}

fn begin_oauth_flow_impl(
    provider: &str,
    redirect_uri: &str,
    endpoints: &GitHubOAuthEndpoints,
    client_id: &str,
) -> Result<OAuthFlowStart, AppError> {
    ensure_supported_provider(provider)?;
    let pkce = generate_pkce()?;
    let state = random_url_safe_token()?;
    let authorize_url = build_authorize_url(
        endpoints,
        client_id,
        redirect_uri,
        GITHUB_SCOPE,
        &state,
        &pkce.challenge,
    )?;
    Ok(OAuthFlowStart {
        authorize_url,
        code_verifier: pkce.verifier.to_string(),
        state: state.to_string(),
    })
}

// ---------------------------------------------------------------------------
// Token exchange
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize)]
struct RawTokenResponse {
    access_token: String,
    #[serde(default)]
    expires_in: Option<i64>,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    refresh_token_expires_in: Option<i64>,
}

#[derive(serde::Deserialize)]
struct RawTokenError {
    error: String,
    #[serde(default)]
    error_description: Option<String>,
}

#[derive(serde::Deserialize)]
struct RawGitHubUser {
    login: String,
}

/// Tokens as exchanged from GitHub, ready to be persisted by
/// [`store_tokens_in_keyring`]. Every secret field is wrapped in
/// `Zeroizing` (mirroring `security::keyring`'s discipline for the root AES
/// key) so it is wiped from memory on drop. This must never cross the FFI
/// boundary at all — the Gherkin's whole point — and, being a plain
/// private struct with no well-known-std-trait impl, isn't reachable from
/// any `pub` item FRB's scanner would expose (see `GitHubOAuthEndpoints`'s
/// doc comment for the trap this avoids).
struct OAuthTokens {
    access_token: Zeroizing<String>,
    refresh_token: Option<Zeroizing<String>>,
    access_token_expires_at: Option<i64>,
    refresh_token_expires_at: Option<i64>,
}

/// Hand-implemented (rather than `#[derive(Debug)]`) so a stray `{:?}` in a
/// panic message, test failure, or future log line can never print the raw
/// token — same redaction discipline as `git::operations::GitCredentials`.
impl std::fmt::Debug for OAuthTokens {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OAuthTokens")
            .field("access_token", &"***")
            .field("refresh_token", &self.refresh_token.as_ref().map(|_| "***"))
            .field("access_token_expires_at", &self.access_token_expires_at)
            .field("refresh_token_expires_at", &self.refresh_token_expires_at)
            .finish()
    }
}

fn current_unix_time() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Exchanges an authorization `code` for tokens via `POST
/// {endpoints.token_url}` (PKCE `code_verifier`, optional `client_secret`
/// per the module doc comment). Never logs or returns the raw response body
/// on success; on failure the body is either GitHub's own `error_description`
/// or a status-code summary, neither of which contains token material.
fn exchange_code_for_token(
    endpoints: &GitHubOAuthEndpoints,
    client_id: &str,
    client_secret: Option<&str>,
    code: &str,
    code_verifier: &str,
) -> Result<OAuthTokens, AppError> {
    let client = reqwest::blocking::Client::new();
    let mut form: Vec<(&str, &str)> = vec![
        ("client_id", client_id),
        ("code", code),
        ("code_verifier", code_verifier),
    ];
    if let Some(secret) = client_secret {
        form.push(("client_secret", secret));
    }

    let response = client
        .post(&endpoints.token_url)
        .header(reqwest::header::ACCEPT, "application/json")
        .form(&form)
        .send()
        .map_err(|e| AppError::NetworkError(format!("token exchange request failed: {e}")))?;

    let status = response.status();
    let body = Zeroizing::new(response.text().map_err(|e| {
        AppError::NetworkError(format!("reading token exchange response failed: {e}"))
    })?);

    // GitHub reports token-exchange failures (e.g. `bad_verification_code`)
    // via an `error` field in the JSON body rather than (necessarily) a
    // non-2xx HTTP status (see the module doc comment) — check for that
    // shape before falling back to a plain status check.
    if let Ok(err) = serde_json::from_str::<RawTokenError>(&body) {
        return Err(AppError::OAuthError(
            err.error_description.unwrap_or(err.error),
        ));
    }
    if !status.is_success() {
        return Err(AppError::NetworkError(format!(
            "token exchange failed with HTTP {status}"
        )));
    }

    let raw: RawTokenResponse = serde_json::from_str(&body)
        .map_err(|e| AppError::OAuthError(format!("unexpected token response shape: {e}")))?;

    let now = current_unix_time();
    Ok(OAuthTokens {
        access_token: Zeroizing::new(raw.access_token),
        refresh_token: raw.refresh_token.map(Zeroizing::new),
        access_token_expires_at: raw.expires_in.map(|secs| now + secs),
        refresh_token_expires_at: raw.refresh_token_expires_in.map(|secs| now + secs),
    })
}

/// `GET {endpoints.user_url}` with the freshly-exchanged access token, used
/// only to recover the authenticated GitHub login as a stable, non-secret
/// workspace id (see `authenticate_workspace_impl`'s doc comment for why).
fn fetch_github_login(
    endpoints: &GitHubOAuthEndpoints,
    access_token: &str,
) -> Result<String, AppError> {
    let client = reqwest::blocking::Client::new();
    let response = client
        .get(&endpoints.user_url)
        .bearer_auth(access_token)
        // Required by the GitHub REST API for every request, unrelated to OAuth.
        .header(reqwest::header::USER_AGENT, "burlmd-app")
        .header(reqwest::header::ACCEPT, "application/vnd.github+json")
        .send()
        .map_err(|e| AppError::NetworkError(format!("fetching GitHub user failed: {e}")))?;

    if !response.status().is_success() {
        return Err(AppError::NetworkError(format!(
            "fetching GitHub user failed with HTTP {}",
            response.status()
        )));
    }

    let user: RawGitHubUser = response
        .json()
        .map_err(|e| AppError::OAuthError(format!("unexpected /user response shape: {e}")))?;
    Ok(user.login)
}

// ---------------------------------------------------------------------------
// Token storage
// ---------------------------------------------------------------------------

/// Persists `tokens` under `service`'s OS Keychain entries (via `keyring`,
/// same "service" bucket — `com.burlmd.app` in production — that
/// `security::keyring` uses for the root AES key, under distinct "account"
/// keys so the two never collide).
///
/// Takes `service` as a parameter (rather than being a method on some
/// `KeyringTokenStore` struct) so `authenticate_workspace_impl` can accept
/// this as a plain `impl Fn(&OAuthTokens) -> Result<(), AppError>` closure
/// parameter — a storage seam for testing without the real OS keychain
/// (mirrors the split `db::connection::open_encrypted_db`/
/// `open_encrypted_db_with_key` already uses to keep DB tests hermetic) —
/// without introducing a local trait. A local trait plus an impl of it
/// turned out to be exactly the shape FRB's `rust_input: crate::api`
/// scanner (confirmed empirically) exposes to Dart regardless of `pub`,
/// the same trap `GitHubOAuthEndpoints`'s doc comment describes for
/// well-known std trait impls; a bare function has no such risk, since
/// non-`pub` free functions are correctly left out of the generated
/// bindings (see the `ffi_api.rs`/`simple.rs` precedent: `search_notes_impl`,
/// `save_note_impl`, etc.).
fn store_tokens_in_keyring(service: &str, tokens: &OAuthTokens) -> Result<(), AppError> {
    set_or_delete(
        service,
        ACCESS_TOKEN_ACCOUNT,
        Some(tokens.access_token.as_str()),
    )?;
    set_or_delete(
        service,
        REFRESH_TOKEN_ACCOUNT,
        tokens.refresh_token.as_ref().map(|t| t.as_str()),
    )?;
    set_or_delete(
        service,
        ACCESS_TOKEN_EXPIRES_AT_ACCOUNT,
        tokens
            .access_token_expires_at
            .map(|t| t.to_string())
            .as_deref(),
    )?;
    set_or_delete(
        service,
        REFRESH_TOKEN_EXPIRES_AT_ACCOUNT,
        tokens
            .refresh_token_expires_at
            .map(|t| t.to_string())
            .as_deref(),
    )?;
    Ok(())
}

/// Wraps `keyring::Entry::new` to ride out a narrow startup race in
/// `keyring` 4.1.5's lazy default-store initialization
/// (`v1::Entry::new`'s `SET_CREDENTIAL_STORE` compare-exchange): if two
/// threads call `Entry::new` for the very first time in the process at
/// nearly the same instant, the loser can observe `NoDefaultStore` even
/// though the winner is already mid-flight and will finish registering the
/// store a few milliseconds later — confirmed empirically here (this
/// module's keyring tests plus `security::keyring`'s pass reliably under
/// `cargo test -- --test-threads=1`, but intermittently hit
/// `NoDefaultStore` under the default parallel runner). Retrying a few
/// times with a short sleep rides out that window without weakening
/// anything once the store is actually up; any error other than
/// `NoDefaultStore` still surfaces on the first attempt.
fn new_keyring_entry(service: &str, account: &str) -> Result<keyring::Entry, AppError> {
    const ATTEMPTS: u32 = 5;
    for attempt in 0..ATTEMPTS {
        match keyring::Entry::new(service, account) {
            Ok(entry) => return Ok(entry),
            Err(keyring::Error::NoDefaultStore) if attempt + 1 < ATTEMPTS => {
                std::thread::sleep(std::time::Duration::from_millis(
                    10 * u64::from(attempt + 1),
                ));
            }
            Err(e) => return Err(e.into()),
        }
    }
    unreachable!("loop above always returns by the last attempt")
}

/// Sets `account`'s secret to `value`, or deletes it (tolerating "already
/// absent") when `value` is `None` — keeps a stale refresh token/expiry
/// from a previous, differently-configured login from lingering when the
/// current exchange doesn't return one.
fn set_or_delete(service: &str, account: &str, value: Option<&str>) -> Result<(), AppError> {
    let entry = new_keyring_entry(service, account)?;
    match value {
        Some(v) => entry.set_password(v)?,
        None => match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(e) => return Err(e.into()),
        },
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

/// Exchanges `auth_code` for tokens, stores them, and returns a stable,
/// non-secret workspace id.
///
/// Epic A/B's `schema.sql` models `workspaces.id` as an opaque `TEXT
/// PRIMARY KEY` ("UUID" in its comment) with no existing code path that
/// actually mints one — `db::connection`/`api::simple` only ever seed or
/// reference workspace ids as pre-existing test fixtures. Absent an
/// established minting scheme to stay consistent with, the authenticated
/// GitHub login (e.g. `"octocat"`) is used directly as the workspace id:
/// it's already stable and non-secret (exactly what `AppError`-free
/// `Ok(String)` needs to carry back across the FFI boundary per the
/// contract), unique per GitHub account, and avoids inventing a second,
/// disconnected id space this ticket has no mandate to wire into `schema.sql`.
fn authenticate_workspace_impl(
    provider: &str,
    auth_code: &str,
    code_verifier: &str,
    endpoints: &GitHubOAuthEndpoints,
    client_id: &str,
    client_secret: Option<&str>,
    store: impl FnOnce(&OAuthTokens) -> Result<(), AppError>,
) -> Result<String, AppError> {
    ensure_supported_provider(provider)?;
    let tokens = exchange_code_for_token(
        endpoints,
        client_id,
        client_secret,
        auth_code,
        code_verifier,
    )?;
    let login = fetch_github_login(endpoints, tokens.access_token.as_str())?;
    store(&tokens)?;
    Ok(login)
}

// ---------------------------------------------------------------------------
// FFI surface
// ---------------------------------------------------------------------------

/// Returned by [`begin_oauth_flow`]: everything the UI needs to drive the
/// browser leg of the flow and later call `authenticate_workspace`. Beyond
/// the contract in `tech-spec/contracts/ffi_api.rs` — added here because
/// PKCE verifier/challenge/state generation, and authorize-URL construction,
/// must happen Core-side (the client secret analog here is the verifier:
/// generating it in Dart would mean trusting the UI layer with a value the
/// Core alone should mint and later check), while opening the system
/// browser and running the loopback redirect listener can only happen
/// UI-side (Rust has no notion of "the system browser" or a Flutter-visible
/// window to redirect back to).
#[frb]
pub struct OAuthFlowStart {
    pub authorize_url: String,
    pub code_verifier: String,
    pub state: String,
}

/// Starts a GitHub OAuth PKCE flow: generates the verifier/challenge/state
/// and returns the full authorize URL for the UI to open in the system
/// browser. `redirect_uri` must be the loopback URL (e.g.
/// `http://127.0.0.1:PORT/callback`) the UI is already listening on — see
/// the module doc comment on loopback redirect rules. Pure computation, no
/// network I/O, so this is `#[frb(sync)]` per `guidelines.md`'s preference
/// for synchronous FFI calls where nothing actually needs to yield.
#[frb(sync)]
pub fn begin_oauth_flow(
    provider: String,
    redirect_uri: String,
) -> Result<OAuthFlowStart, AppError> {
    begin_oauth_flow_impl(
        &provider,
        &redirect_uri,
        real_endpoints(),
        &github_client_id(),
    )
}

/// Exchanges `auth_code` (captured by the UI from the loopback redirect)
/// for tokens via PKCE, stores them in the OS Keychain, and returns a
/// Workspace ID. `async` per the fixed `tech-spec/contracts/ffi_api.rs`
/// signature; the body still runs synchronously to completion (blocking
/// HTTP calls, no `.await`), per `guidelines.md`'s rule that the `async`
/// marker here only affects FRB's dispatch, not this function's own
/// execution. The access/refresh tokens themselves never appear in this
/// function's `Ok` value or anywhere else that crosses the FFI boundary —
/// only the non-secret workspace id does.
#[frb]
pub async fn authenticate_workspace(
    provider: String,
    auth_code: String,
    code_verifier: String,
) -> Result<String, AppError> {
    authenticate_workspace_impl(
        &provider,
        &auth_code,
        &code_verifier,
        real_endpoints(),
        &github_client_id(),
        github_client_secret().as_ref().map(|s| s.as_str()),
        |tokens| store_tokens_in_keyring(KEYCHAIN_SERVICE, tokens),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};

    /// Runs once, before `cargo test`'s harness spawns any worker thread
    /// (a `ctor` runs at binary load time, ahead of `main`), so it always
    /// wins `keyring` 4.1.5's first-call race (see `new_keyring_entry`'s
    /// doc comment) deterministically instead of relying on retries alone.
    /// Without this, this module's keyring tests plus
    /// `security::keyring`'s own test — now running concurrently in the
    /// same test binary — intermittently observed `NoDefaultStore` under
    /// the default parallel test runner.
    #[ctor::ctor(unsafe)]
    fn warm_up_keyring_default_store() {
        let _ = keyring::Entry::new("com.burlmd.app.test-warmup", "warmup");
    }

    // -----------------------------------------------------------------
    // PKCE
    // -----------------------------------------------------------------

    #[test]
    fn random_url_safe_token_has_rfc7636_verifier_length_and_charset() {
        let token = random_url_safe_token().unwrap();
        assert_eq!(
            token.len(),
            43,
            "32 CSPRNG bytes base64url-encoded without padding must be 43 chars"
        );
        assert!(
            token.chars().all(|c| c.is_ascii_alphanumeric()
                || c == '-'
                || c == '_'
                || c == '.'
                || c == '~'),
            "verifier must only contain RFC 7636 `unreserved` characters, got: {}",
            *token
        );
    }

    #[test]
    fn random_url_safe_token_is_not_constant_across_calls() {
        let a = random_url_safe_token().unwrap();
        let b = random_url_safe_token().unwrap();
        assert_ne!(*a, *b, "two draws from the CSPRNG must not collide");
    }

    /// RFC 7636 Appendix B's worked example: a known verifier and its
    /// expected S256 challenge, straight from the spec text
    /// (<https://www.rfc-editor.org/rfc/rfc7636#appendix-B>) — cross-checked
    /// independently via `printf '%s' <verifier> | openssl dgst -sha256
    /// -binary | openssl base64 -A | tr '+/' '-_' | tr -d '='`, which
    /// reproduces the same `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`.
    #[test]
    fn s256_code_challenge_matches_rfc7636_appendix_b_known_vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        let expected_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

        assert_eq!(s256_code_challenge(verifier), expected_challenge);
    }

    #[test]
    fn generate_pkce_produces_a_verifier_and_a_matching_challenge() {
        let pkce = generate_pkce().unwrap();
        assert_eq!(s256_code_challenge(&pkce.verifier), pkce.challenge);
    }

    // -----------------------------------------------------------------
    // Authorize URL construction
    // -----------------------------------------------------------------

    #[test]
    fn build_authorize_url_includes_client_id_pkce_and_state_params() {
        let endpoints = default_github_endpoints();
        let url = build_authorize_url(
            &endpoints,
            "test-client-id",
            "http://127.0.0.1:54321/callback",
            "repo",
            "test-state",
            "test-challenge",
        )
        .unwrap();

        let parsed = url::Url::parse(&url).unwrap();
        assert_eq!(parsed.host_str(), Some("github.com"));
        assert_eq!(parsed.path(), "/login/oauth/authorize");

        let params: HashMap<String, String> = parsed.query_pairs().into_owned().collect();
        assert_eq!(params.get("client_id").unwrap(), "test-client-id");
        assert_eq!(
            params.get("redirect_uri").unwrap(),
            "http://127.0.0.1:54321/callback"
        );
        assert_eq!(params.get("scope").unwrap(), "repo");
        assert_eq!(params.get("state").unwrap(), "test-state");
        assert_eq!(params.get("code_challenge").unwrap(), "test-challenge");
        // "Must be S256 - the plain code challenge method is not supported."
        assert_eq!(params.get("code_challenge_method").unwrap(), "S256");
    }

    #[test]
    fn begin_oauth_flow_impl_round_trips_its_own_verifier_into_the_challenge() {
        let endpoints = default_github_endpoints();
        let start =
            begin_oauth_flow_impl("github", "http://127.0.0.1:1/callback", &endpoints, "cid")
                .unwrap();

        let parsed = url::Url::parse(&start.authorize_url).unwrap();
        let params: HashMap<String, String> = parsed.query_pairs().into_owned().collect();
        assert_eq!(
            params.get("code_challenge").unwrap(),
            &s256_code_challenge(&start.code_verifier)
        );
        assert_eq!(params.get("state").unwrap(), &start.state);
    }

    #[test]
    fn begin_oauth_flow_impl_rejects_an_unsupported_provider() {
        let endpoints = default_github_endpoints();
        let result =
            begin_oauth_flow_impl("gitlab", "http://127.0.0.1:1/callback", &endpoints, "cid");
        assert!(matches!(result, Err(AppError::OAuthError(_))));
    }

    // -----------------------------------------------------------------
    // Mock HTTP server for token-exchange / user-fetch tests
    // -----------------------------------------------------------------

    /// A minimal, hand-rolled HTTP/1.1 server (std `TcpListener` only, no
    /// server crate) that replies to `responses.len()` requests in order
    /// with canned `(status, content_type, body)` tuples, and records the
    /// raw request text of each so tests can assert on what was sent (e.g.
    /// that `client_secret` was/wasn't included in the form body).
    struct MockServer {
        base_url: String,
        requests: Arc<Mutex<Vec<String>>>,
        handle: Option<std::thread::JoinHandle<()>>,
    }

    impl MockServer {
        fn start(responses: Vec<(u16, &'static str, String)>) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = listener.local_addr().unwrap().port();
            let requests = Arc::new(Mutex::new(Vec::new()));
            let requests_clone = Arc::clone(&requests);

            let handle = std::thread::spawn(move || {
                for (status, content_type, body) in responses {
                    let (mut stream, _) = match listener.accept() {
                        Ok(s) => s,
                        Err(_) => return,
                    };
                    let mut buf = [0u8; 8192];
                    let mut request = String::new();
                    if let Ok(n) = stream.read(&mut buf) {
                        request.push_str(&String::from_utf8_lossy(&buf[..n]));
                    }
                    requests_clone.lock().unwrap().push(request);

                    let reason = match status {
                        200 => "OK",
                        400 => "Bad Request",
                        401 => "Unauthorized",
                        _ => "Error",
                    };
                    let response = format!(
                        "HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len(),
                    );
                    let _ = stream.write_all(response.as_bytes());
                    let _ = stream.flush();
                }
            });

            Self {
                base_url: format!("http://127.0.0.1:{port}"),
                requests,
                handle: Some(handle),
            }
        }

        fn requests(&self) -> Vec<String> {
            self.requests.lock().unwrap().clone()
        }
    }

    impl Drop for MockServer {
        fn drop(&mut self) {
            if let Some(handle) = self.handle.take() {
                let _ = handle.join();
            }
        }
    }

    fn endpoints_for(server: &MockServer) -> GitHubOAuthEndpoints {
        GitHubOAuthEndpoints {
            authorize_url: format!("{}/login/oauth/authorize", server.base_url),
            token_url: format!("{}/login/oauth/access_token", server.base_url),
            user_url: format!("{}/user", server.base_url),
        }
    }

    // -----------------------------------------------------------------
    // Token exchange
    // -----------------------------------------------------------------

    #[test]
    fn exchange_code_for_token_parses_a_successful_response_with_expiry() {
        let body = r#"{"access_token":"gho_test123","token_type":"bearer","scope":"repo","expires_in":28800,"refresh_token":"ghr_test456","refresh_token_expires_in":15811200}"#;
        let server = MockServer::start(vec![(200, "application/json", body.to_string())]);
        let endpoints = endpoints_for(&server);

        let before = current_unix_time();
        let tokens =
            exchange_code_for_token(&endpoints, "cid", Some("csecret"), "auth-code", "verifier")
                .unwrap();
        let after = current_unix_time();

        assert_eq!(tokens.access_token.as_str(), "gho_test123");
        assert_eq!(
            tokens.refresh_token.as_deref().map(|s| s.as_str()),
            Some("ghr_test456")
        );
        let expires_at = tokens.access_token_expires_at.unwrap();
        assert!(expires_at >= before + 28800 && expires_at <= after + 28800);
    }

    #[test]
    fn exchange_code_for_token_treats_missing_expiry_fields_as_a_non_expiring_token() {
        let body = r#"{"access_token":"gho_test123","token_type":"bearer","scope":"repo"}"#;
        let server = MockServer::start(vec![(200, "application/json", body.to_string())]);
        let endpoints = endpoints_for(&server);

        let tokens =
            exchange_code_for_token(&endpoints, "cid", None, "auth-code", "verifier").unwrap();

        assert_eq!(tokens.access_token.as_str(), "gho_test123");
        assert!(tokens.refresh_token.is_none());
        assert!(tokens.access_token_expires_at.is_none());
        assert!(tokens.refresh_token_expires_at.is_none());
    }

    #[test]
    fn exchange_code_for_token_maps_bad_verification_code_to_oauth_error() {
        let body = r#"{"error":"bad_verification_code","error_description":"The code passed is incorrect or expired.","error_uri":"https://docs.github.com/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"}"#;
        let server = MockServer::start(vec![(200, "application/json", body.to_string())]);
        let endpoints = endpoints_for(&server);

        let result =
            exchange_code_for_token(&endpoints, "cid", Some("csecret"), "bad-code", "verifier");

        match result {
            Err(AppError::OAuthError(msg)) => {
                assert!(msg.contains("incorrect or expired"), "got: {msg}");
            }
            other => panic!("expected AppError::OAuthError, got {other:?}"),
        }
    }

    #[test]
    fn exchange_code_for_token_maps_a_non_2xx_non_error_body_response_to_network_error() {
        let server = MockServer::start(vec![(
            503,
            "text/plain",
            "upstream unavailable".to_string(),
        )]);
        let endpoints = endpoints_for(&server);

        let result =
            exchange_code_for_token(&endpoints, "cid", Some("csecret"), "code", "verifier");

        assert!(matches!(result, Err(AppError::NetworkError(_))));
    }

    #[test]
    fn exchange_code_for_token_sends_client_secret_only_when_present() {
        let body = r#"{"access_token":"gho_a","token_type":"bearer","scope":"repo"}"#;

        let with_secret = MockServer::start(vec![(200, "application/json", body.to_string())]);
        exchange_code_for_token(
            &endpoints_for(&with_secret),
            "cid",
            Some("super-secret"),
            "code",
            "verifier",
        )
        .unwrap();
        let sent = with_secret.requests();
        assert!(
            sent[0].contains("client_secret=super-secret"),
            "got: {}",
            sent[0]
        );

        let without_secret = MockServer::start(vec![(200, "application/json", body.to_string())]);
        exchange_code_for_token(
            &endpoints_for(&without_secret),
            "cid",
            None,
            "code",
            "verifier",
        )
        .unwrap();
        let sent = without_secret.requests();
        assert!(!sent[0].contains("client_secret"), "got: {}", sent[0]);
    }

    #[test]
    fn exchange_code_for_token_sends_the_code_verifier_in_the_form_body() {
        let body = r#"{"access_token":"gho_a","token_type":"bearer","scope":"repo"}"#;
        let server = MockServer::start(vec![(200, "application/json", body.to_string())]);
        exchange_code_for_token(
            &endpoints_for(&server),
            "cid",
            None,
            "the-auth-code",
            "the-code-verifier",
        )
        .unwrap();

        let sent = server.requests();
        assert!(
            sent[0].contains("code_verifier=the-code-verifier"),
            "got: {}",
            sent[0]
        );
        assert!(sent[0].contains("code=the-auth-code"), "got: {}", sent[0]);
    }

    // -----------------------------------------------------------------
    // In-memory TokenStore fake + full orchestration
    // -----------------------------------------------------------------

    #[derive(Clone)]
    struct StoredForAssertions {
        access_token: String,
        refresh_token: Option<String>,
        access_token_expires_at: Option<i64>,
        refresh_token_expires_at: Option<i64>,
    }

    #[derive(Default)]
    struct InMemoryTokenStore {
        stored: Mutex<Option<StoredForAssertions>>,
    }

    impl InMemoryTokenStore {
        fn store(&self, tokens: &OAuthTokens) -> Result<(), AppError> {
            *self.stored.lock().unwrap() = Some(StoredForAssertions {
                access_token: tokens.access_token.to_string(),
                refresh_token: tokens.refresh_token.as_ref().map(|t| t.to_string()),
                access_token_expires_at: tokens.access_token_expires_at,
                refresh_token_expires_at: tokens.refresh_token_expires_at,
            });
            Ok(())
        }
    }

    #[test]
    fn authenticate_workspace_impl_stores_tokens_and_returns_the_github_login_as_workspace_id() {
        let token_body = r#"{"access_token":"gho_test123","token_type":"bearer","scope":"repo"}"#;
        let user_body = r#"{"login":"octocat"}"#;
        let server = MockServer::start(vec![
            (200, "application/json", token_body.to_string()),
            (200, "application/json", user_body.to_string()),
        ]);
        let endpoints = endpoints_for(&server);
        let store = InMemoryTokenStore::default();

        let workspace_id = authenticate_workspace_impl(
            "github",
            "auth-code",
            "verifier",
            &endpoints,
            "cid",
            Some("csecret"),
            |t| store.store(t),
        )
        .unwrap();

        assert_eq!(workspace_id, "octocat");
        let stored = store.stored.lock().unwrap().clone().unwrap();
        assert_eq!(stored.access_token, "gho_test123");
        assert!(stored.refresh_token.is_none());
        assert!(stored.access_token_expires_at.is_none());
        assert!(stored.refresh_token_expires_at.is_none());
    }

    #[test]
    fn authenticate_workspace_impl_rejects_an_unsupported_provider_without_any_network_call() {
        let endpoints = GitHubOAuthEndpoints {
            authorize_url: "http://127.0.0.1:1/authorize".to_string(),
            token_url: "http://127.0.0.1:1/token".to_string(),
            user_url: "http://127.0.0.1:1/user".to_string(),
        };
        let store = InMemoryTokenStore::default();

        let result = authenticate_workspace_impl(
            "gitlab",
            "auth-code",
            "verifier",
            &endpoints,
            "cid",
            None,
            |t| store.store(t),
        );

        assert!(matches!(result, Err(AppError::OAuthError(_))));
        assert!(store.stored.lock().unwrap().is_none());
    }

    #[test]
    fn authenticate_workspace_impl_does_not_store_anything_when_the_exchange_fails() {
        let body = r#"{"error":"bad_verification_code","error_description":"The code passed is incorrect or expired."}"#;
        let server = MockServer::start(vec![(200, "application/json", body.to_string())]);
        let endpoints = endpoints_for(&server);
        let store = InMemoryTokenStore::default();

        let result = authenticate_workspace_impl(
            "github",
            "bad-code",
            "verifier",
            &endpoints,
            "cid",
            Some("csecret"),
            |t| store.store(t),
        );

        assert!(matches!(result, Err(AppError::OAuthError(_))));
        assert!(store.stored.lock().unwrap().is_none());
    }

    // -----------------------------------------------------------------
    // `store_tokens_in_keyring` against the real OS keychain
    // -----------------------------------------------------------------

    // Distinct, clearly-scoped service names (mirrors `security::keyring`'s
    // test pattern) so these never touch the real app's shipped Keychain
    // entries, always clean up after themselves, and — crucially, since
    // `cargo test` runs test functions in parallel threads by default —
    // never share a service with each other. Each test gets its own
    // constant rather than one shared `TEST_SERVICE`: two tests hammering
    // the same OS keychain entries concurrently is the same class of bug
    // `git::operations`'s tests avoid via per-test `tempdir()`s.
    const ROUND_TRIP_TEST_SERVICE: &str = "com.burlmd.app.test-api-auth-c002-roundtrip";
    const CLEARS_STALE_TEST_SERVICE: &str = "com.burlmd.app.test-api-auth-c002-clears-stale";

    fn cleanup_test_entries(service: &str) {
        for account in [
            ACCESS_TOKEN_ACCOUNT,
            REFRESH_TOKEN_ACCOUNT,
            ACCESS_TOKEN_EXPIRES_AT_ACCOUNT,
            REFRESH_TOKEN_EXPIRES_AT_ACCOUNT,
        ] {
            if let Ok(entry) = new_keyring_entry(service, account) {
                let _ = entry.delete_credential();
            }
        }
    }

    #[test]
    fn keyring_token_store_round_trips_tokens_through_the_real_os_keychain() {
        let test_service = ROUND_TRIP_TEST_SERVICE;
        cleanup_test_entries(test_service);

        let tokens = OAuthTokens {
            access_token: Zeroizing::new("gho_roundtrip".to_string()),
            refresh_token: Some(Zeroizing::new("ghr_roundtrip".to_string())),
            access_token_expires_at: Some(1_800_000_000),
            refresh_token_expires_at: Some(1_900_000_000),
        };

        store_tokens_in_keyring(test_service, &tokens).unwrap();

        assert_eq!(
            new_keyring_entry(test_service, ACCESS_TOKEN_ACCOUNT)
                .unwrap()
                .get_password()
                .unwrap(),
            "gho_roundtrip"
        );
        assert_eq!(
            new_keyring_entry(test_service, REFRESH_TOKEN_ACCOUNT)
                .unwrap()
                .get_password()
                .unwrap(),
            "ghr_roundtrip"
        );
        assert_eq!(
            new_keyring_entry(test_service, ACCESS_TOKEN_EXPIRES_AT_ACCOUNT)
                .unwrap()
                .get_password()
                .unwrap(),
            "1800000000"
        );

        cleanup_test_entries(test_service);
    }

    #[test]
    fn keyring_token_store_clears_a_stale_refresh_token_when_a_later_login_has_none() {
        let test_service = CLEARS_STALE_TEST_SERVICE;
        cleanup_test_entries(test_service);

        store_tokens_in_keyring(
            test_service,
            &OAuthTokens {
                access_token: Zeroizing::new("gho_first".to_string()),
                refresh_token: Some(Zeroizing::new("ghr_first".to_string())),
                access_token_expires_at: None,
                refresh_token_expires_at: None,
            },
        )
        .unwrap();

        store_tokens_in_keyring(
            test_service,
            &OAuthTokens {
                access_token: Zeroizing::new("gho_second".to_string()),
                refresh_token: None,
                access_token_expires_at: None,
                refresh_token_expires_at: None,
            },
        )
        .unwrap();

        let result = new_keyring_entry(test_service, REFRESH_TOKEN_ACCOUNT)
            .unwrap()
            .get_password();
        assert!(
            matches!(result, Err(keyring::Error::NoEntry)),
            "stale refresh token must be cleared, got: {result:?}"
        );

        cleanup_test_entries(test_service);
    }
}
