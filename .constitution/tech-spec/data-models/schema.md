# Local encrypted index schema

## Authority

The code-owned `rust/src/db/schema.sql` file is authoritative for delivered SQLCipher database tables (`workspaces`, `notes`, `links`, `notes_fts`, `fts_mapping`, `drafts`, `directories`). The historical duplicate `.constitution/tech-spec/data-models/schema.sql` file has been removed (preserved in Git history) to ensure that the code-owned schema remains the single source of truth for database definitions.

Every ticket that modifies database tables or migrations owns `rust/src/db/schema.sql` and its integration tests in Rust.

## Forward schema gates

Forward tables for local assets, object storage, Git reconciliation, and diagnostics remain provisional and are gated behind their respective research outcomes: canonical document representation and path models depend on SPK-BURL-H001, local asset and object storage models depend on SPK-BURL-I001, and Git reconciliation analysis depends on SPK-BURL-L001. Those forward tables must not be added to `rust/src/db/schema.sql` or maintained in a duplicate specification file until reviewed Stage 3 finalization lands.
