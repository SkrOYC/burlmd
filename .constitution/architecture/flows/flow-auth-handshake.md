# Execution Flow: OAuth Handshake & Encryption Setup

**Maps to PRD Capability:** Users can authenticate via an OAuth provider... All local data is encrypted at rest. (Epic: Seamless Synchronization & Security, P0)

```mermaid
sequenceDiagram
    participant UI as Presentation Container
    participant Core as Core Engine
    participant OS as Secure Storage (Keychain)
    participant OAuth as OAuth Provider (GitHub)
    participant Remote as Remote Repository

    UI->>Core: Initiate Login (Provider: GitHub)
    Core->>UI: Return OAuth URL
    UI->>OAuth: User authorizes app via Browser
    OAuth-->>UI: Redirect with Auth Code
    UI->>Core: Pass Auth Code
    
    Core->>OAuth: Exchange Code for Access/Refresh Tokens
    OAuth-->>Core: Tokens
    
    Core->>OS: Store OAuth Tokens securely
    OS-->>Core: OK
    
    Core->>Core: Generate local AES-256 Root Key
    Core->>OS: Store Root Key securely
    OS-->>Core: OK
    
    Core->>Remote: Clone repository using Access Token
    Remote-->>Core: Encrypted or Plaintext Git Repo
    
    Core->>Core: Initialize Encrypted Local SQLite Index
    Core-->>UI: Login Successful, Workspace Ready
```
