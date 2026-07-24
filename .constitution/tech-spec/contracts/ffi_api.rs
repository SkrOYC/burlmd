// Raw Rust interface contract exposed to Flutter via flutter_rust_bridge.
// This defines the exact shapes passing over the FFI boundary.
//
// Governing decisions: ADR-004 (OKF v0.2 conformance), ADR-005 (local-first
// Workspace), ADR-006 (raw-on-focus editing), ADR-007 (span-preserving source
// splicing), ADR-008 (four-tier persistence).
//
// Two contract-wide rules follow from ADR-007 and are not repeated per function:
//
//   1. A Note is addressed by its OKF concept id -- its bundle-relative path
//      with `.md` removed (OKF v0.2 SPEC.md section 2). Never by a UUID, and
//      never by an absolute filesystem path.
//   2. Source spans are Core-side state keyed by `block_path`. They never
//      appear on `AstNode` and never cross this boundary. The UI has no use
//      for byte offsets into a file it does not own, and carrying them would
//      inflate every edit round trip against the 16ms budget in
//      `prd/constraints.md` (see `architecture/risks.md` risk 1).

use flutter_rust_bridge::frb;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[frb]
pub enum AppError {
    DiskFull,
    AuthExpired,
    /// The on-disk file changed underneath an active draft. Carries the
    /// current `base_revision` so the caller can reload rather than guess.
    RevisionMismatch(String),
    GitConflict,
    /// The target path is already occupied, or is a reserved OKF filename
    /// (`index.md` / `log.md`, see ADR-004 decision 6).
    PathUnavailable(String),
    NotFound(String),
    DatabaseError(String),
    CryptoError(String),
    NetworkError(String),
    OAuthError(String),
    IoError(String),
    ParseError(String),
}

// ---------------------------------------------------------------------------
// Workspace
// ---------------------------------------------------------------------------

#[frb]
pub struct WorkspaceInfo {
    pub id: String,
    pub name: String,
    /// `"local"` until the user connects a Remote (CAP-SYNC-01), then the
    /// provider name. Matches `workspaces.provider` in `schema.sql`.
    pub provider: String,
    pub remote_url: Option<String>,
    /// Absolute path to the bundle root on disk.
    pub local_path: String,
}

/// One entry in the Workspace tree (CAP-GRAPH-01). Directories carry their
/// children so the sidebar renders from a single call rather than one call
/// per level.
#[frb]
pub enum TreeNode {
    Directory { name: String, path: String, children: Vec<TreeNode> },
    Note { id: String, title: String, path: String },
}

/// Opens the local Workspace, creating and initializing it if absent
/// (ADR-005 decision 1): creates the directory, initializes a Git repository
/// in place, generates and stores the root key if this is first boot, opens
/// the encrypted index, and writes a `workspaces` row with
/// `provider = "local"`.
///
/// Requires no credential, no provider, and no network -- this is the call
/// that makes the Local-First Mandate in `prd/constraints.md` literally true
/// (CAP-WS-01). `path` is `None` to use the default location specified in
/// `guidelines.md`.
#[frb]
pub async fn open_or_create_local_workspace(path: Option<String>) -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

/// Opens an existing Workspace directory that this application did not
/// create, including one populated by another tool (CAP-WS-05). Files with
/// absent or unparseable frontmatter are indexed with `okf_conformant = 0`
/// rather than rejected.
#[frb]
pub async fn open_workspace(path: String) -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

/// Full rebuild of `notes`, `notes_fts`, `fts_mapping`, `links` and
/// `directories` from the bundle on disk. Returns the number of Notes
/// indexed.
///
/// The index is derived state and is always discardable. This closes Epic C
/// deferred item 3: `SyncDeps::default().reindex` in
/// `rust/src/sync/scheduler.rs` is currently a documented no-op because no
/// re-index function existed anywhere in the crate.
///
/// Per `architecture/risks.md` risk 3 this must not be the routine path for
/// keeping the index current; incremental updates on write are. It exists for
/// first open, post-merge reconciliation, and recovery.
#[frb]
pub async fn reindex_workspace(workspace_id: String) -> Result<u32, AppError> {
    unimplemented!()
}

/// The Directory tree for the sidebar, Directories before Notes, each level
/// sorted by name.
#[frb]
pub async fn workspace_tree(workspace_id: String) -> Result<Vec<TreeNode>, AppError> {
    unimplemented!()
}

/// Copies the bundle to `destination` (CAP-PORT-02). Cheap by construction:
/// the live Workspace is already conformant plaintext OKF (CAP-PORT-01), so
/// this is a tree copy plus a conformance check, not a decrypt-and-transform
/// pipeline. `.git/` is excluded.
#[frb]
pub async fn export_workspace(workspace_id: String, destination: String) -> Result<(), AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Note & Directory lifecycle (CAP-LIFE-01 .. CAP-LIFE-06)
// ---------------------------------------------------------------------------

#[frb]
pub struct NoteMetadata {
    /// OKF concept id: bundle-relative path, `.md` removed.
    pub id: String,
    pub workspace_id: String,
    /// Bundle-relative path, `.md` retained.
    pub path: String,
    pub title: String,
    pub last_modified: i64,
    /// Populated by search results only.
    pub snippet: Option<String>,
    /// False when the file has no frontmatter or it does not parse. Such a
    /// file is still fully usable; the flag exists so the UI can offer to
    /// bring it into conformance (CAP-PORT-03).
    pub okf_conformant: bool,
}

/// Creates a Note in `directory_path` (empty string for the bundle root) with
/// an OKF-conformant frontmatter block (`type: Note`, `title`). The filename
/// is derived from `title`; a collision, or a title deriving to a reserved
/// filename, returns `PathUnavailable` rather than silently disambiguating.
#[frb]
pub async fn create_note(workspace_id: String, directory_path: String, title: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Deletes a Note and commits the deletion, so it stays recoverable from
/// local version history (CAP-LIFE-04).
#[frb]
pub async fn delete_note(note_id: String) -> Result<(), AppError> {
    unimplemented!()
}

/// Renames a Note, rewriting its frontmatter `title`, its filename, and every
/// inbound Link that targets it (CAP-LIFE-02).
///
/// Because OKF identity is positional (SPEC.md section 2), this changes the
/// Note's id. The returned `NoteState` carries the new id; callers must not
/// retain the old one.
#[frb]
pub async fn rename_note(note_id: String, new_title: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Moves a Note to another Directory, rewriting every inbound Link
/// (CAP-LIFE-03). Changes the Note's id, as `rename_note` does.
#[frb]
pub async fn move_note(note_id: String, new_directory_path: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Creates a Directory, including intermediate levels (CAP-LIFE-05). An empty
/// Directory has no file to represent it, so it exists only in the
/// `directories` table until it holds a Note.
#[frb]
pub async fn create_directory(workspace_id: String, path: String) -> Result<(), AppError> {
    unimplemented!()
}

/// Renames a Directory, moving its contents and rewriting inbound Links to
/// every Note beneath it (CAP-LIFE-06).
#[frb]
pub async fn rename_directory(workspace_id: String, path: String, new_name: String) -> Result<(), AppError> {
    unimplemented!()
}

/// Deletes a Directory and everything beneath it, in one commit (CAP-LIFE-06).
#[frb]
pub async fn delete_directory(workspace_id: String, path: String) -> Result<(), AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Abstract Syntax Tree
//
// The AST is a render projection, not the editable representation (ADR-007).
// The UI renders from it and edits through raw source text.
// ---------------------------------------------------------------------------

#[frb]
pub struct TextRun {
    pub content: String,
    pub bold: bool,
    pub italic: bool,
    pub strikethrough: bool,
    pub code: bool,
}

#[frb]
pub enum InlineElement {
    Text(TextRun),
    /// A Link to another Note. On disk this is a standard bundle-absolute
    /// Markdown link, `[text](/dir/note.md)` (ADR-004 decision 5, OKF section
    /// 6.1) -- the `[[` sequence is a UI trigger only and is never stored.
    Link {
        /// The target's OKF concept id, derived by stripping the leading `/`
        /// and trailing `.md`. Always present, even when nothing matches it.
        target_id: String,
        /// False for a ghost Link -- a Link to a Note not yet created, which
        /// OKF section 6.1 requires consumers to tolerate and which
        /// CAP-GRAPH-04 makes a feature. The UI renders these distinctly and
        /// creates the Note on follow.
        exists: bool,
        content: Vec<InlineElement>,
    },
    /// Any link that is not an internal Note reference: has a URL scheme, or
    /// does not end in `.md`.
    ExternalLink { url: String, content: Vec<InlineElement> },
}

#[frb]
pub enum AstNode {
    Heading { level: u8, content: Vec<InlineElement> },
    Paragraph { content: Vec<InlineElement> },
    List { ordered: bool, items: Vec<AstNode> },
    ListItem { content: Vec<AstNode>, checked: Option<bool> },
    Blockquote { nodes: Vec<AstNode> },
    CodeBlock { language: Option<String>, code: String },
    ThematicBreak,
    Image { alt_text: String, url_or_path: String },

    /// A pending conflict the user must resolve, rendered inline as a
    /// Suggestion (CAP-SYNC-04).
    ///
    /// `base_content` is populated only when the merge that produced this
    /// conflict was run with `merge.conflictStyle = diff3`. The `git merge`
    /// default is `merge` style, which emits `<<<<<<<` / `=======` /
    /// `>>>>>>>` with **no** base section -- so the pull path in
    /// `rust/src/git/operations.rs` must set `diff3` explicitly for this
    /// field to ever be `Some`. Without it the field is structurally dead.
    Suggestion {
        base_content: Option<Vec<AstNode>>,
        local_content: Vec<AstNode>,
        incoming_content: Vec<AstNode>,
    },
}

#[frb]
pub struct NoteState {
    pub ast: Vec<AstNode>,
    pub metadata: NoteMetadata,
    /// Content hash of the on-disk file (ADR-007 decision 7). This is the OCC
    /// token: pass it back to `save_note`, which rejects with
    /// `RevisionMismatch` if the file changed underneath the draft. It
    /// replaces the `notes.last_modified` comparison, which could never match
    /// the placeholder `open_note` returned and so made every save fail.
    pub base_revision: String,
    /// True when a draft was restored from the `drafts` table rather than
    /// read from disk -- i.e. the previous session ended without tier 2
    /// flushing (ADR-008, CAP-WS-03).
    pub restored_from_draft: bool,
}

// ---------------------------------------------------------------------------
// Editing (ADR-006, ADR-007)
//
// Every mutating call below commits a splice into the file's source text and
// reparses, returning the whole new state. `block_path` is an index path into
// the AST and is NOT stable across a call: a splice can change a Block's node
// shape (a paragraph becoming a list). Callers must re-derive focus from the
// returned state rather than retaining a path across a mutation.
// ---------------------------------------------------------------------------

/// Opens a Note by concept id, restoring an unflushed draft if one exists.
/// Replaces the previous `open_note(path)` / `open_note_by_id(note_id)` pair,
/// which existed because identity was ambiguous; under ADR-004 it is not.
#[frb]
pub async fn open_note(note_id: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// The raw Markdown source of one Block, for populating the editable field
/// when it takes focus (ADR-006 decision 2). This is what the user sees and
/// types -- `**bold**`, not bold.
#[frb(sync)]
pub fn get_block_source(note_id: String, block_path: Vec<usize>) -> Result<String, AppError> {
    unimplemented!()
}

/// Commits an edit to one Block by splicing `new_source` over that Block's
/// span and reparsing (ADR-007 decision 1).
///
/// Takes source text, not an `AstNode` -- the prior AST-based signature
/// required reconstructing Markdown from a tree, which needed a canonical
/// form nothing ever specified and would have rewritten unedited regions in
/// violation of the Edit Fidelity constraint.
///
/// Also writes tier 1 of ADR-008 (the `drafts` row). It does not write the
/// file; `save_note` does.
#[frb(sync)]
pub fn update_block(note_id: String, block_path: Vec<usize>, new_source: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Inserts a new Block at `block_path`, shifting subsequent Blocks down.
#[frb(sync)]
pub fn insert_block(note_id: String, block_path: Vec<usize>, source: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Splits a Block at a character offset -- pressing Enter mid-Block
/// (CAP-EDIT-03).
#[frb(sync)]
pub fn split_block(note_id: String, block_path: Vec<usize>, offset: usize) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Merges a Block into its predecessor -- pressing Backspace at offset 0
/// (CAP-EDIT-03). A no-op on the first Block.
#[frb(sync)]
pub fn merge_block_with_previous(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// A selection spanning one or more Blocks (ADR-006 decision 3). Offsets are
/// character offsets into each Block's rendered text.
#[frb]
pub struct BlockRange {
    pub start_path: Vec<usize>,
    pub start_offset: usize,
    pub end_path: Vec<usize>,
    pub end_offset: usize,
}

/// Markdown for a multi-Block selection (CAP-EDIT-04). Executed Core-side
/// because the Core owns both the AST and the source text; reproducing it in
/// Dart would mean a second serializer.
#[frb(sync)]
pub fn copy_range_as_markdown(note_id: String, range: BlockRange) -> Result<String, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_range(note_id: String, range: BlockRange) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Replaces a multi-Block selection with text -- typing over a selection that
/// crosses Blocks. The fiddliest interaction in ADR-006; the caller must
/// re-derive caret position from the returned state.
#[frb(sync)]
pub fn replace_range(note_id: String, range: BlockRange, replacement: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Persistence (ADR-008)
// ---------------------------------------------------------------------------

/// Tier 2: splices pending edits into the file and writes it atomically
/// (temp file plus rename). Returns the new `base_revision`.
///
/// Rejects with `RevisionMismatch` when the on-disk content hash no longer
/// matches `expected_base_revision` -- the Optimistic Concurrency Control in
/// `architecture/risks.md` risk 6, now guarding file content rather than only
/// a database column.
#[frb]
pub async fn save_note(note_id: String, expected_base_revision: String) -> Result<String, AppError> {
    unimplemented!()
}

/// Tier 3: flushes any pending write, makes one Git commit covering this
/// editing session, clears the `drafts` row, and calls the sync scheduler's
/// `notify_activity()` -- which has existed since Epic C with no caller
/// (deferred item 4).
///
/// Must also run on application quit and when switching away from a Note, or
/// the session is written to disk but never enters version history.
#[frb]
pub async fn close_note(note_id: String) -> Result<(), AppError> {
    unimplemented!()
}

/// Notes with an unflushed draft from a previous session, for surfacing
/// recovered work on startup (CAP-WS-03).
#[frb]
pub async fn pending_drafts(workspace_id: String) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Discovery & the knowledge graph
// ---------------------------------------------------------------------------

/// Full-text search within one Workspace (CAP-FIND-01), bm25-ranked.
///
/// `workspace_id` closes a real gap: the previous signature had no Workspace
/// filter at all despite the capability being scoped to "all Notes in their
/// Workspace". `limit` replaces the hardcoded cap of 50, which silently
/// truncated with no signal to the caller.
#[frb]
pub async fn search_notes(workspace_id: String, query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// Title-prefix jump (CAP-FIND-02).
#[frb]
pub async fn find_notes_by_title(workspace_id: String, query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// One candidate for the in-editor Link completion (CAP-GRAPH-02).
#[frb]
pub struct LinkCompletion {
    pub note_id: String,
    pub title: String,
    /// The exact text to splice at the cursor, already in bundle-absolute
    /// Markdown form. Constructed Core-side so the UI never assembles a link
    /// target and cannot produce a non-conformant one.
    pub insert_text: String,
}

/// Candidates for the completion triggered by `[[` (CAP-GRAPH-02). The
/// trigger is a UI affordance; what gets inserted is `insert_text`.
#[frb]
pub async fn link_completions(workspace_id: String, query: String, limit: u32) -> Result<Vec<LinkCompletion>, AppError> {
    unimplemented!()
}

/// Notes linking *to* this one (CAP-GRAPH-05). Served by `idx_links_target`
/// in `schema.sql`.
#[frb]
pub async fn backlinks(note_id: String) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Session, Remote & synchronization (CAP-SYNC-01 .. CAP-SYNC-05)
// ---------------------------------------------------------------------------

#[frb]
pub struct SessionState {
    /// True when usable credentials are in OS secure storage. Checked on
    /// startup so a restart does not re-prompt -- closing the half of Epic C
    /// deferred item 4 that made every launch show the login screen even with
    /// a valid stored token.
    pub authenticated: bool,
    pub provider: Option<String>,
    pub account: Option<String>,
}

/// Reads stored credentials back out of OS secure storage. Also closes Epic C
/// deferred item 2: `api::auth` exposed only a private write path, so
/// `SyncScheduler`'s `credentials` dependency could only ever return `None`.
#[frb]
pub async fn current_session() -> Result<SessionState, AppError> {
    unimplemented!()
}

#[frb]
pub struct OAuthFlowStart {
    pub authorize_url: String,
    pub code_verifier: String,
    pub state: String,
}

/// Generates the PKCE verifier, challenge and state Core-side and returns the
/// authorize URL for the UI to open in the system browser.
///
/// The split is deliberate: the UI is not a trusted party to mint the
/// verifier that `authenticate_workspace` later checks the exchange against,
/// while only the UI can open a browser and run the loopback listener.
/// `redirect_uri` is the loopback URL the UI is already listening on.
#[frb(sync)]
pub fn begin_oauth_flow(provider: String, redirect_uri: String) -> Result<OAuthFlowStart, AppError> {
    unimplemented!()
}

/// Exchanges the authorization code and stores the resulting tokens in OS
/// secure storage. Establishes a session only -- it does not clone, create,
/// or attach a Workspace. Under ADR-005 the Workspace already exists locally
/// before any of this is called.
#[frb]
pub async fn authenticate_workspace(provider: String, auth_code: String, code_verifier: String) -> Result<SessionState, AppError> {
    unimplemented!()
}

/// Attaches a Remote to an existing local Workspace and publishes its
/// history (CAP-SYNC-01). Provisions a new private repository when
/// `repository` is `None`, otherwise adopts the named one, which must be
/// empty. Updates `workspaces.provider` and `remote_url` in place; never
/// re-clones or discards local state.
#[frb]
pub async fn connect_remote(workspace_id: String, provider: String, repository: Option<String>) -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

/// Clears stored credentials. The Workspace reverts to local-only operation
/// with every editing capability intact (CAP-SYNC-05).
#[frb]
pub async fn sign_out() -> Result<(), AppError> {
    unimplemented!()
}

#[frb]
pub enum SyncState {
    /// No Remote attached. The resting state of a local-only Workspace, and
    /// not an error.
    NotConnected,
    Idle,
    Syncing,
    Offline,
    AuthExpired,
    /// A merge produced conflicts; some Notes contain `Suggestion` nodes.
    Conflicted,
    Failed(String),
}

#[frb]
pub struct SyncStatus {
    pub state: SyncState,
    pub last_success: Option<i64>,
    pub pending_commits: u32,
}

/// Backs the ambient sync indicator (CAP-SYNC-03). `SyncScheduler` already
/// tracks `status()` and `last_error()` in pure Rust with no `#[frb]`
/// wrapper, so the UI is currently unable to render the "Offline" state
/// `architecture/resilience.md` promises. This is that wrapper.
#[frb(sync)]
pub fn sync_status() -> Result<SyncStatus, AppError> {
    unimplemented!()
}

/// Requests an immediate sync, bypassing the debounce.
#[frb]
pub async fn sync_now() -> Result<SyncStatus, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Conflict resolution (CAP-SYNC-04)
// ---------------------------------------------------------------------------

#[frb]
pub enum SuggestionChoice {
    AcceptLocal,
    AcceptIncoming,
    AcceptBoth,
    /// Hand-authored replacement, as raw Markdown source, consistent with
    /// every other editing entry point under ADR-006.
    Custom(String),
}

/// Notes currently holding unresolved conflict markers, so the UI can list
/// them rather than requiring the user to find them by opening Notes.
#[frb]
pub async fn notes_with_conflicts(workspace_id: String) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// Replaces a `Suggestion` node with the chosen resolution, splicing clean
/// Markdown with no conflict markers over its span.
#[frb(sync)]
pub fn resolve_suggestion(note_id: String, block_path: Vec<usize>, choice: SuggestionChoice) -> Result<NoteState, AppError> {
    unimplemented!()
}
