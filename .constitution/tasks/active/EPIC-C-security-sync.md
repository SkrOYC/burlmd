# Epic C: Security & Sync

#### SYNC-C001 Integrate Keychain Root Key
- **Type:** Security
- **Effort:** 3
- **Dependencies:** UIDB-B001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/security/keyring.rs`
- **Verification Command:** `cargo test security::`
- **Description:** Implement Rust `keyring` integration to generate and securely store a 256-bit root AES key in the host OS secure enclave.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a fresh installation
When the app boots
Then a new 256-bit key is generated and stored in the OS Keychain
```

#### SYNC-C002 Encrypt SQLite with SQLCipher
- **Type:** Security
- **Effort:** 5
- **Dependencies:** SYNC-C001, UIDB-B001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/db/connection.rs`
- **Description:** Reconfigure the `rusqlite` initialization to issue `PRAGMA key` using the root key from `SYNC-C001`, encrypting the entire database at rest.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the SQLite initialization
When the database file is written to disk
Then the file is AES-256-GCM encrypted and cannot be opened by standard sqlite3 CLI
```

#### SYNC-C003 AES File Encryption for Markdown
- **Type:** Security
- **Effort:** 3
- **Dependencies:** SYNC-C001
- **Category:** Security
- **Scope (In-Scope Files):**
  - `rust/src/security/crypto.rs`
- **Description:** Build wrapper functions using `aes-gcm` to encrypt and decrypt the raw Markdown file contents before writing them to the local disk.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a raw Markdown string
When it is saved to disk
Then the disk contents are ciphertext
```

#### SYNC-C004 Implement Git Operations (gix)
- **Type:** Feature
- **Effort:** 8
- **Dependencies:** SYNC-C002, UIDB-B002
- **Category:** Correctness
- **Scope (In-Scope Files):**
  - `rust/src/git/operations.rs`
- **Description:** Implement programmatic Git `clone`, `commit`, `push`, and `pull` operations against the local Workspace directory using `gix`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given a local directory with changes
When the commit function is called
Then `gix` successfully creates a Git commit in the local `.git` index
```

#### SYNC-C005 Implement OAuth Handshake
- **Type:** Feature
- **Effort:** 5
- **Dependencies:** UIDB-B003
- **Category:** Security
- **Scope (In-Scope Files):**
  - `lib/src/screens/login.dart`
  - `rust/src/api/auth.rs`
- **Description:** Build the OAuth web flow in Flutter to capture a GitHub authorization code, pass it to Rust, exchange it for tokens, and store them via `keyring`.
- **Acceptance Criteria (Gherkin):**
```gherkin
Given the Login screen
When the user completes the OAuth flow
Then the Access Token is securely stored in the OS Keychain by Rust
```

#### SYNC-C006 Background Sync Manager Scheduler
- **Type:** Feature
- **Effort:** 3
- **Dependencies:** SYNC-C004, SYNC-C005
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
