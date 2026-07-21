# Logical Risks & Technical Debt

## 1. FFI Serialization Overhead
- **Risk:** Passing the entire markdown AST tree back and forth across the FFI boundary on every block edit could violate the 16ms frame budget, causing UI stutter.
- **Mitigation:** Rely on `flutter_rust_bridge` (v2)'s high-performance SSE (Simple Serialization Engine) which minimizes overhead. If latency persists for enormous files, refactor the FFI boundary to stream differential AST updates (only the modified node) instead of the entire tree.

## 2. Sync Worker Battery Drain
- **Risk:** A continuous background Sync Manager polling or pushing frequently on mobile devices will cause excessive battery consumption.
- **Mitigation:** The Sync Manager must be logically debounced, only triggering pushes after a defined period of inactivity or utilizing OS-level background task scheduling APIs to batch network requests.

## 3. Large Repository Indexing Latency
- **Risk:** For power users with thousands of notes, performing a full logical re-index of the graph (Links and OKF hierarchy) upon initial device clone could lock up the Core Engine for seconds or minutes.
- **Mitigation:** The Local Repository must be designed to perform incremental indexing, updating only the files that changed in the latest pulled commits rather than rescanning the entire directory tree.
## 6. Optimistic Concurrency Control for Background Sync
- **Risk:** The background Sync Manager pulls remote changes and overwrites the local file while the user is actively editing a dirty AST draft in memory. When the user saves, the draft blindly overwrites the file, destroying the remote changes and Git conflict markers.
- **Mitigation:** The Core Engine must implement Optimistic Concurrency Control (OCC). `save_note` will require an `expected_base_revision` (e.g., file hash or last-modified timestamp). If the on-disk file was modified by background sync while the draft was active, the save is rejected, and the Core Engine forces the UI to reload the file and render the newly injected Git conflict markers.
