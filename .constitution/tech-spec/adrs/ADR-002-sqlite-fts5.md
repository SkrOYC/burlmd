# ADR-002: Local Search via SQLite FTS5

**Status:** Accepted

## Context
The application must provide instant (<100ms) full-text search across thousands of offline notes. Building a pure in-memory Rust search index on every boot is memory-intensive for mobile devices and adds startup latency.

## Decision
We will use SQLite (via `rusqlite`) compiled with the `FTS5` (Full-Text Search) extension to maintain a persistent search index.

## Consequences
- **Positive:** Blazing fast search that executes entirely on disk/page cache without loading all notes into RAM.
- **Positive:** Persistent index means zero indexing delay on application startup.
- **Negative:** The Core Engine must meticulously keep the FTS5 virtual table synchronized with the raw Markdown files on disk whenever a commit occurs or upstream changes are pulled.
