# Epic C: Security & Sync

#### SYNC-C001 Implement Git Operations (gix)
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** UIDB-B004
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/git/operations.rs`
- **Description:** Implement programmatic Git `clone`, `commit`, `push`, and `pull` operations against the local Workspace directory using `gix` (or shelling out to the `git` CLI if `gix` currently lacks robust working tree merge conflict generation).
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a local directory with changes
When the commit function is called
Then `gix` successfully creates a Git commit in the local `.git` index
```

##### SYNC-C001 Deviations & Justifications
- **Touched Files:**
  - `rust/src/git/operations.rs` (in scope) — `clone_repo`, `commit_all`, `push`, `pull`, and the `GitCredentials` auth wiring point.
  - `rust/src/git/mod.rs` (new) — declares `pub mod operations;`; `git/` already existed as a directory name in `guidelines.md`'s documented layout but had no `mod.rs` yet.
  - `rust/src/lib.rs` — added `pub mod git;` so the new module is reachable; every other top-level module (`api`, `db`, `markdown`, `security`) is wired the same way, so this follows existing convention rather than deviating from it.
  - `rust/Cargo.toml` / `rust/Cargo.lock` — added `gix = "0.86.0"` with `default-features = false` and an explicit feature list (`max-performance-safe`, `sha1`, `blob-diff`, `revision`, `index`, `excludes`, `worktree-mutation`, `credentials`, `interrupt`, `tree-editor`, `blocking-network-client`, `blocking-http-transport-reqwest-rust-tls`) — the minimal set covering clone (with HTTPS transport, for eventual GitHub remotes), commit/tree-editing, and index read/write, verified by `cargo check` against gix 0.86.0.
  - `.constitution/tech-spec/stack.md` — corrected the "Git Implementation" line to describe the verified gix/git-CLI hybrid instead of just "`gix` (gitoxide)".
  - `.constitution/tech-spec/changelog.md` — new `v1.0.3` entry recording the same correction with its justification.
- **Justification:** The ticket's scope line names only `rust/src/git/operations.rs`, but a new module cannot compile or be reachable without `mod.rs` + a `lib.rs` wire-up, and a new crate dependency cannot exist without `Cargo.toml`/`Cargo.lock` changes — these are mechanical consequences of the in-scope file existing at all, not scope creep. The `stack.md`/`changelog.md` edits are required by the "Spec honesty" rule: this ticket's actual, verified design is a gix/git-CLI hybrid (gix has no push support at all, and its merge support does not yet cover commits — see the capability findings in `rust/src/git/operations.rs`'s module doc comment), which is materially different from the stack's original single-word "`gix` (gitoxide)" claim.

#### SYNC-C002 Implement OAuth Handshake
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** UIDB-B005
- **Category:** Security
- **Scope (In-Scope Files):**
  - `lib/src/screens/login.dart`
  - `rust/src/api/auth.rs`
- **Description:** Build the OAuth web flow in Flutter to capture a GitHub authorization code, pass it to Rust, exchange it for tokens via PKCE, and store them via `keyring`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the Login screen
When the user completes the OAuth flow
Then the Access Token is securely stored in the OS Keychain by Rust
```

#### SYNC-C003 Background Sync Manager Scheduler
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** SYNC-C001, SYNC-C002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/sync/scheduler.rs`
- **Description:** Implement a debounced background worker in Rust that calls the `gix` push/pull operations automatically every X minutes or after explicitly saving.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given active local commits
When 5 seconds of inactivity pass
Then the background worker automatically pushes to the Remote Repo
```
