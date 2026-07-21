# Non-Functional Constraints

## Performance
- **Search Latency:** Full-text search and title filtering must return results in under 100 milliseconds.
- **UI Responsiveness:** Writing and formatting interactions must execute in under 16 milliseconds (60fps) to maintain a seamless hybrid editor feel.

## Reliability
- **Local-First Mandate:** The application must be 100% functional when completely disconnected from the internet. Reads, writes, searches, and link traversals must resolve locally.
- **Non-Blocking Sync:** Background synchronization must never block the main UI thread or interrupt the user's editing flow.

## Security & Sovereignty
- **Decentralized Storage:** User data is stored exclusively in the user's designated remote repository (e.g., GitHub). The application backend must not act as a central storage broker for note content.
- **At-Rest Encryption (Local):** The system relies on iOS/Android Data Protection (Full Disk Encryption) for raw Markdown files on disk to allow native Git merge capabilities. The SQLite search index, which aggregates all knowledge, must be explicitly encrypted via `sqlcipher`. The database encryption key must reside in the secure hardware enclave (OS Keychain/Keystore).
- **Data Portability:** Despite local encryption, the system must provide an easy "Export Workspace" function that decrypts all files into standard, parseable Open Knowledge Format (OKF) Markdown on disk.

## Privacy
- **Zero Content Telemetry:** The application must not collect, transmit, or analyze the contents of the user's Notes for analytics, telemetry, or diagnostic purposes.
