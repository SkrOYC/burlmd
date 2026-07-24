# ADR-005: Local-First Workspace with Opt-In Remote

**Status:** Accepted
**Supersedes in part:** the clone-on-login step of `architecture/flows/flow-auth-handshake.md`

## Context
`prd/constraints.md` has carried a Local-First Mandate since v1.0.0: the application "must be 100% functional when completely disconnected from the internet." The capability set contradicted it. OAuth was the only documented path to a Workspace, and `flow-auth-handshake.md` sequenced it as authorize → exchange tokens → store key → **clone repository** → initialize index → ready. There was no branch through that flow that did not involve a Remote.

The shipped implementation followed the flow faithfully, and the result is that `lib/main.dart` gates the entire application behind `LoginScreen` unless `authControllerProvider` reports `AuthStatus.success`. Combined with Epic C's deferred item 1 — no GitHub OAuth App is registered, so `BURLMD_GITHUB_CLIENT_ID`/`BURLMD_GITHUB_CLIENT_SECRET` are unset — the gate cannot currently be passed at all. The application is presently unusable for its stated purpose, and the cause is a specification error rather than a coding error.

`data-models/schema.sql` already anticipated the correct model: `workspaces.provider` is typed `'github', 'gitlab', 'local'`, and the `'local'` value has never been used by any code path.

PRD v1.1.0 resolved this at the product layer with CAP-WS-01 (write on first launch with no account and no network) and a rewritten CAP-SYNC-01 (connect as a deliberate later step). Rejection recorded in `prd/out-of-scope/mandatory-account-on-first-run.md`.

## Decision
1. **A Workspace is local by default.** On first launch the Core Engine resolves a default Workspace directory, creates it if absent, initializes a Git repository in place, inserts a `workspaces` row with `provider = 'local'` and `remote_url = NULL`, and opens the encrypted index. No credential, network call, or provider is involved.
2. **`init`, not `clone`.** Local Workspace creation uses repository initialization. `clone` remains in the design but moves to the connect path and to onboarding an already-remote Workspace on a second device.
3. **The root encryption key is decoupled from authentication.** It is generated on first boot and stored in OS secure storage as an unconditional step of Workspace bootstrap, not as a step of the OAuth handshake where `flow-auth-handshake.md` currently places it. The two were only ever adjacent, never causally related.
4. **Connecting is additive and later.** CAP-SYNC-01's connect flow authorizes a provider, provisions or selects a repository, adds it as a remote to the *existing* local repository, and pushes the history that already exists. It never re-homes, re-clones, or discards local state, and `workspaces.provider` transitions from `'local'` to the provider name in place.
5. **No login gate.** Authentication state gates synchronization only. Every editing, search, navigation, and lifecycle capability is reachable with no session.
6. **Session restore replaces re-login.** A `current_session` query reports whether stored credentials exist, so a restart does not re-prompt. This closes Epic C deferred item 4's session-restore half and Epic C deferred item 2's keychain-readback requirement in one contract addition.
7. **Exactly one Workspace is active at a time, and the Core owns which one.** It is established by `open_or_create_local_workspace` or `open_workspace`, and no function in `contracts/ffi_api.rs` takes a `workspace_id` — every call is implicitly scoped to the active Workspace.

   This is stated as a decision rather than left implicit because it is what makes a bare `note_id` well-defined. An OKF concept id is unique within a bundle but **not globally** (OKF §2), so two Workspaces may each hold a `Welcome`; the index accumulates rows for every Workspace ever opened, since CAP-WS-05 makes opening a second one a supported capability. Without an owner for "which Workspace", `open_note("Welcome")` is ambiguous and `backlinks("Welcome")` returns edges from the wrong bundle. The alternative — threading `workspace_id` through every Note-level call — was rejected as redundant given that `prd/out-of-scope/multiple-simultaneous-workspaces.md` already rules out having two open at once.

   The consequence to accept: the Core carries process-wide state that the contract's signatures do not reveal, which is the usual cost of ambient scope. It is consistent with the existing `db::connection` singleton, and it is bounded — the active Workspace changes only through the two functions that open one.

## Consequences
- **Positive:** The Local-First Mandate becomes literally true rather than aspirational, and the application becomes usable at all — which it currently is not.
- **Positive:** GitHub OAuth App registration leaves the critical path entirely. It becomes a parallel, non-blocking concern rather than the sole blocker on writing a single Note.
- **Positive:** Version history exists from the first Note regardless of whether a Remote is ever configured, so CAP-WS-02's durability guarantee does not depend on connectivity. This is what allows the sync epic to be deferred without leaving notes unprotected.
- **Positive:** The `'local'` provider value in `schema.sql` stops being dead vocabulary.
- **Negative:** A new state transition exists that did not before — local-only Workspace becomes connected Workspace — and it must be correct on a repository that already has history. Pushing an existing local history to a freshly provisioned empty remote is the straightforward case; reconciling against a *non-empty* remote is not, and is deliberately excluded (the connect flow provisions a new repository or requires an empty one; adopting a populated remote is CAP-WS-05 territory and separately scoped).
- **Negative:** Two bootstrap paths now exist (initialize local, clone existing) where the specification previously described one. Both must converge on the same post-conditions — index initialized, root key present, `workspaces` row written — or later code will need to ask which path it came from.
- **Neutral:** The default Workspace location becomes a decision with a compatibility surface. Specified in `guidelines.md` rather than here, since moving it later is a user-visible migration.
