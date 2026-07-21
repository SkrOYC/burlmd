# Non-Functional Constraints

## Performance
- **Search Latency:** Full-text search and title filtering must return results in under 100 milliseconds.
- **UI Responsiveness:** Writing and formatting interactions must execute in under 16 milliseconds (60fps) to maintain a seamless hybrid editor feel.

## Reliability
- **Local-First Mandate:** The application must be 100% functional when completely disconnected from the internet. Reads, writes, searches, and link traversals must resolve locally.
- **Non-Blocking Sync:** Background synchronization must never block the main UI thread or interrupt the user's editing flow.

## Security & Sovereignty
- **Decentralized Storage:** User data is stored exclusively in the user's designated remote repository (e.g., GitHub). The application backend must not act as a central storage broker for note content.
- **At-Rest Encryption (Local):** Because the remote Git host might be secure, but mobile devices can be lost/stolen, all local Markdown files and local SQLite indexes must be encrypted (e.g., AES-256). The encryption keys must reside in the secure hardware enclave (OS Keychain/Keystore).
- **Data Portability:** Despite local encryption, the system must provide an easy "Export Workspace" function that decrypts all files into standard, parseable Open Knowledge Format (OKF) Markdown on disk.

## Privacy
- **Zero Content Telemetry:** The application must not collect, transmit, or analyze the contents of the user's Notes for analytics, telemetry, or diagnostic purposes.
