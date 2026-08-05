use flutter_rust_bridge::frb;

use crate::markdown::AstNode;

/// The Core Engine's active-draft-state domain: `NoteState`/`NoteMetadata`,
/// the shapes every open-Note call crosses the FFI boundary with. Owned by
/// this module rather than `api::ffi_api` per `architecture/containers.md`'s
/// Core Engine responsibility ("manages the active draft state of open
/// notes"), which is a distinct concern from the FFI bridge —
/// `api::ffi_api` re-exports these types, keeping its own `#[frb]` functions
/// as thin wrappers over `workspace::persist::NoteSession`, which is where
/// the actual per-Note state and its keystroke-level mutation logic live
/// (ADR-008's tiers). This module carried both the cache and a
/// `set_node_at_path` AST mutator through Epic B and into `WSPC-D007`, back
/// when `update_block` mutated an in-memory AST directly; `WSPC-D008`
/// replaces that call with the contract's source-text version, which writes
/// through the session and its draft row instead, and removes both — a
/// single-slot cache keyed by nothing was never going to survive more than
/// one open Note at a time, which `workspace::persist`'s session registry
/// already does not share.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteMetadata {
    /// OKF concept id: the bundle-relative path with `.md` removed.
    ///
    /// Carries no `workspace_id` alongside it, per the contract's rule 2:
    /// exactly one Workspace is active at a time and the Core owns which one
    /// (ADR-005 decision 7), so every row crossing this boundary belongs to
    /// it and a qualifier the UI could neither choose nor check was only ever
    /// a second source of truth for something the Core already knows.
    pub id: String,
    /// The same path with `.md` retained.
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    /// Populated by search results only.
    pub snippet: Option<String>,
    /// False when the file has no frontmatter, when it does not parse, or when
    /// it parses without a non-empty `type` — OKF §11's first two conformance
    /// conditions, the second of which an implementation that only tries to
    /// parse will miss. Such a file is still fully usable; the flag exists so
    /// the UI can offer to bring it into conformance (CAP-PORT-03).
    pub okf_conformant: bool,
}

#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    /// Content hash of the on-disk file (ADR-007 decision 7).
    ///
    /// **Not an input.** The Core holds this value and compares it itself
    /// before every tier 2 write, replacing it with the hash of what it just
    /// wrote after each success — see `workspace::persist`. It is exposed for
    /// display and diagnostics only, and no function on this boundary takes
    /// it back.
    pub base_revision: String,
    /// True when the working source was restored from the `drafts` table
    /// rather than read from disk — i.e. a previous session ended without
    /// tier 2 flushing (ADR-008 tier 1, CAP-WS-03).
    pub restored_from_draft: bool,
}
