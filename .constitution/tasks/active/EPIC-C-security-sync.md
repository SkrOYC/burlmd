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
