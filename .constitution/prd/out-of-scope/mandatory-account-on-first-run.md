# Out of Scope: Mandatory Account or Provider Authorization on First Run

**Status:** Rejected (was implicitly P0 through v1.0.1)
**Superseded by:** CAP-WS-01 (local Workspace on first launch), CAP-SYNC-01 (connect as an opt-in step)

## The rejected concept
Requiring the user to authorize a hosting provider before the application becomes usable, so that every Workspace is provisioned from or connected to a Remote at creation time. Under this model the first screen is an authorization prompt and no Note can be written until it succeeds.

## Why it was in the PRD
The original capability set stated that users "authenticate via an OAuth provider ... to automatically provision or connect their Workspace," and the auth flow was written as authorize → exchange credentials → **clone repository** → initialize index → ready. There was no path through that flow that did not involve a Remote, and "provision or connect" was never disambiguated. The shipped implementation followed it literally and gated the entire application behind a login screen.

## Why it was rejected
1. **It directly contradicted an existing constraint.** The Local-First Mandate requires the application be "100% functional when completely disconnected from the internet." A network handshake before the first keystroke is not a partial violation of that; it inverts it.
2. **It made an external dependency load-bearing for all use.** With no provider application registered, the gate cannot be passed at all — so an unrelated piece of external configuration became the sole blocker on writing a single Note.
3. **It confused durability with sync.** The instinct behind the gate was that notes should be backed up. But local version history (CAP-WS-02) already provides recoverability from the first Note; a Remote adds *off-machine* durability and *multi-device* access. Those are real benefits, and neither requires being a precondition.
4. **It contradicted data sovereignty.** A product whose premise is that the user owns their data should not require a third party's permission to start producing it.

## What replaced it
A Workspace is local by default and fully functional forever in that state. Connecting to a Remote is a deliberate later action that publishes the existing local history upward.

## Conditions that would reopen this
None foreseen. Even a future hosted or team offering would attach a Remote to a Workspace that already exists locally, rather than making the Remote the origin of it.
