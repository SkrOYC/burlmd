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
