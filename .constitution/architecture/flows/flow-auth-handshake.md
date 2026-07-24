# Execution Flow: OAuth Handshake & Remote Connection

**Maps to PRD Capability:** CAP-SYNC-01 (connect an existing local Workspace to a Remote by authorizing a provider, provisioning a new private repository or selecting one already owned, after which existing local history is published to it).

This flow is **opt-in and never a precondition to use.** A Workspace already exists, already holds Notes, and already has version history before any of this runs — see `flow-workspace-bootstrap.md`. Nothing here is required to create, read, edit, search, or organize a Note.

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant Local as Local Repository
    participant OS as Secure Storage (Keychain)
    participant OAuth as OAuth Provider
    participant Remote as Remote Repository

    Note over UI,Remote: Precondition: a local Workspace exists and is in use.

    UI->>Core: Begin OAuth flow (provider, loopback redirect_uri)
    Core->>Core: Generate PKCE verifier, challenge, state
    Core->>Core: Retain verifier + state against a flow id
    Core-->>UI: Authorize URL + flow id

    UI->>OAuth: User authorizes via system browser
    OAuth-->>UI: Redirect to loopback with auth code + state
    UI->>Core: Flow id + auth code + returned state

    Core->>Core: Compare returned state to the one retained for that flow id
    alt State does not match, or flow id unknown/consumed
        Core-->>UI: OAuthStateMismatch; flow terminates here
    else State matches
        Core->>OAuth: Exchange code for tokens (PKCE)
        OAuth-->>Core: Access / refresh tokens
        Core->>OS: Store tokens securely
        OS-->>Core: OK
        Core-->>UI: SessionState (authenticated)
    end

    UI->>Core: Connect Remote (provider, repository?)
    alt No repository named
        Core->>Remote: Provision new private repository
        Remote-->>Core: Repository URL
    else Existing repository named
        Core->>Remote: Verify repository is empty
        Remote-->>Core: OK
    end

    Core->>Local: Add remote to existing repository
    Core->>Remote: Push existing local history
    Remote-->>Core: OK
    Core->>Core: Update workspaces.provider and remote_url in place
    Core-->>UI: WorkspaceInfo (connected)
```

## What changed, and why

The previous version of this flow sequenced authorization → token exchange → key generation → **clone repository** → initialize index → "Login Successful, Workspace Ready". Four defects, all corrected above:

1. **It cloned.** There was no branch through the flow that did not involve a Remote, which made a network round trip a precondition to writing the first word and contradicted the Local-First Mandate outright. The implementation followed it faithfully, which is why `lib/main.dart` gates the whole application behind a login screen. Replaced by initialization in `flow-workspace-bootstrap.md`, with `clone` retained only for onboarding an already-remote Workspace onto a second device.
2. **It owned the encryption key.** Moved to bootstrap, where it belongs — the key protects the local index, which has no relationship to whether a Remote exists.
3. **It generated a `state` parameter and never checked it.** The value was minted, handed to the UI, and then dropped: the redirect came back and the code was exchanged without any comparison. A CSRF parameter that is generated but never compared is decoration — it is exactly as protective as omitting it, while reading in review as though the protection exists. The comparison is now an explicit step, and failing it terminates the flow before the token exchange rather than after.

   The first attempt at this fix put the comparison in the Core lane while `contracts/ffi_api.rs` still declared it a *UI* obligation and `authenticate_workspace` still took no `state` — two documents specifying the same control in mutually exclusive places, which is the failure mode that produced the original defect. Resolved by giving the Core the check outright: it retains the verifier and `state` against a single-use flow id and neither value crosses the boundary. The trade-off originally cited for keeping them UI-side — Core statefulness across the browser leg — was illusory, since the flow was already stateful across that leg with the state merely parked in the container that cannot enforce anything with it.
4. **It never distinguished "provision" from "connect".** `prd/capabilities.md` said OAuth would "provision or connect" a Workspace without defining either. Both branches are now explicit, and adopting a *non-empty* remote is deliberately excluded — that is a Workspace-adoption problem (CAP-WS-05), not a connection problem, and merging two populated histories is a materially different operation.

## Session persistence

Tokens live in OS secure storage and are read back via a session query on startup. Without that readback a restart re-prompts for authorization even when a valid token is already stored, which is the state the implementation is in today (Epic C deferred items 2 and 4).

## Failure posture

Every failure in this flow degrades to a local-only Workspace with no capability loss. An expired or revoked credential pauses synchronization and prompts for re-authorization; it never blocks editing (CAP-SYNC-05).
