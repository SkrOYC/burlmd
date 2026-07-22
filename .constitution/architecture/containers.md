# Logical Containers

## 1. Presentation Container
- **Logical Type:** UI Client (Flutter)
- **Responsibility:** Captures user input and renders the hybrid Markdown editor interface based on state provided by the Core Engine. It is strictly stateless and maintains no persistent data of its own.
- **Inputs / Outputs:** Receives structured Abstract Syntax Trees (AST) and search results; outputs keystrokes, block modifications, and interaction events.
- **Depends on:** Core Engine.

## 2. Core Engine
- **Logical Type:** Application Logic, State Manager, & Crypto Boundary
- **Responsibility:** Manages the active "draft" state of open notes, parses raw Markdown into structured ASTs, handles inline conflict resolution logic, encrypts/decrypts data flowing to the Local Repository, and acts as the bridge (via FFI) to the Presentation Container.
- **Inputs / Outputs:** Receives UI events; outputs ASTs. Reads/writes encrypted payloads to Local Repository. Retrieves keys from Secure Storage.
- **Depends on:** Local Repository, Sync Manager, Secure Storage.

## 3. Local Repository (Index & Storage)
- **Logical Type:** Storage Boundary
- **Responsibility:** Persists the Open Knowledge Format (OKF) directory tree and maintains an application-level-encrypted (SQLCipher) search index for graph relationships and full-text queries. The raw OKF directory tree itself is not independently encrypted by this container — it relies on OS-level Full Disk Encryption (see `prd/constraints.md`), so that native Git merge tooling can still operate on plaintext files.
- **Inputs / Outputs:** Receives finalized encrypted document commits and search queries; outputs queried encrypted documents.
- **Depends on:** None (Self-contained).

## 4. Sync Manager
- **Logical Type:** Background Worker / Scheduler
- **Responsibility:** Handles asynchronous communication with the Remote Repository. It pulls encrypted data from the remote (or encrypts plain remote data if BYOG), pushes local commits, and manages OAuth tokens.
- **Inputs / Outputs:** Reads commits from the Local Repository; pushes commits to the Remote Repository.
- **Depends on:** Local Repository, Remote Repository, Secure Storage.

## 5. Secure Storage (OS Boundary)
- **Logical Type:** Hardware/OS Boundary
- **Responsibility:** Safely stores OAuth refresh tokens and the AES-256 root encryption key for the Local Repository.
- **Inputs / Outputs:** Receives tokens/keys for storage; outputs tokens/keys upon authentication challenge.
- **Depends on:** Host OS (Keychain/Keystore).
