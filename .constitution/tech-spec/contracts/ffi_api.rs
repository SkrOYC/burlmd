// Raw Rust interface contract exposed to Flutter via flutter_rust_bridge.
// This defines the exact shapes passing over the FFI boundary.
//
// Governing decisions: ADR-004 (OKF v0.2 conformance), ADR-005 (local-first
// Workspace), ADR-006 (raw-on-focus editing), ADR-007 (span-preserving source
// splicing), ADR-008 (four-tier persistence).
//
// Three contract-wide rules, not repeated per function:
//
//   1. A Note is addressed by its OKF concept id -- its bundle-relative path
//      with `.md` removed (OKF v0.2 SPEC.md section 2). Never by a UUID, and
//      never by an absolute filesystem path.
//   2. **Exactly one Workspace is active at a time, and the Core owns which.**
//      No call below takes a `workspace_id`: the active Workspace is
//      established by `open_or_create_local_workspace` or `open_workspace`
//      and every subsequent call is implicitly scoped to it. This is
//      load-bearing rather than cosmetic. A concept id is unique within a
//      bundle but NOT globally (`data-models/schema.sql`), so two Workspaces
//      may each hold a `Welcome`; a bare `note_id` is only unambiguous
//      because the Core supplies the Workspace. The index still stores
//      `workspace_id` on every row -- it accumulates rows for every Workspace
//      ever opened (CAP-WS-05) -- and every query filters on the active one.
//      Concurrent Workspaces are out of scope by product decision; see
//      `prd/out-of-scope/multiple-simultaneous-workspaces.md` and ADR-005
//      decision 7.
//   3. Source spans are Core-side state keyed by `block_path`. They never
//      appear on `AstNode` and never cross this boundary. A byte offset into
//      a file the Presentation Container does not own, cannot read and must
//      not write is meaningless to it (ADR-007 decision 3).

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
    Directory {
        name: String,
        path: String,
        children: Vec<TreeNode>,
    },
    Note {
        id: String,
        title: String,
        path: String,
    },
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
pub async fn open_or_create_local_workspace(
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
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
pub async fn reindex_workspace() -> Result<u32, AppError> {
    unimplemented!()
}

/// The Directory tree for the sidebar, Directories before Notes, each level
/// sorted by name.
#[frb]
pub async fn workspace_tree() -> Result<Vec<TreeNode>, AppError> {
    unimplemented!()
}

/// Copies the bundle to `destination` (CAP-PORT-02). Cheap by construction:
/// the live Workspace is already conformant plaintext OKF (CAP-PORT-01), so
/// this is a tree copy plus a conformance check, not a decrypt-and-transform
/// pipeline. `.git/` is excluded.
#[frb]
pub async fn export_workspace(destination: String) -> Result<(), AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Note & Directory lifecycle (CAP-LIFE-01 .. CAP-LIFE-06)
// ---------------------------------------------------------------------------

#[frb]
pub struct NoteMetadata {
    /// OKF concept id: bundle-relative path, `.md` removed. Unambiguous
    /// without a Workspace qualifier, per rule 2 above: every row returned
    /// across this boundary belongs to the one active Workspace.
    pub id: String,
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
pub async fn create_note(directory_path: String, title: String) -> Result<NoteState, AppError> {
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
pub async fn create_directory(path: String) -> Result<(), AppError> {
    unimplemented!()
}

/// One Note whose concept id changed as a side effect of an operation on its
/// containing Directory. Renaming a Directory changes the id of every Note
/// beneath it, so a caller holding an open Note from that subtree would
/// otherwise be left with a dead id and no way to learn the new one.
#[frb]
pub struct IdRemap {
    pub old_id: String,
    pub new_id: String,
}

/// Renames a Directory, moving its contents and rewriting inbound Links to
/// every Note beneath it (CAP-LIFE-06). Returns the id remapping for every
/// affected Note, for the same reason `rename_note` returns the new state:
/// positional identity means the caller's existing ids are now stale.
#[frb]
pub async fn rename_directory(path: String, new_name: String) -> Result<Vec<IdRemap>, AppError> {
    unimplemented!()
}

/// Deletes a Directory and everything beneath it, in one commit (CAP-LIFE-06).
/// Returns the concept ids of every Note removed, so a caller with one of them
/// open can close it rather than discovering it is gone on next access.
#[frb]
pub async fn delete_directory(path: String) -> Result<Vec<String>, AppError> {
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
    ExternalLink {
        url: String,
        content: Vec<InlineElement>,
    },
}

#[frb]
pub enum AstNode {
    Heading {
        level: u8,
        content: Vec<InlineElement>,
    },
    Paragraph {
        content: Vec<InlineElement>,
    },
    List {
        ordered: bool,
        items: Vec<AstNode>,
    },
    ListItem {
        content: Vec<AstNode>,
        checked: Option<bool>,
    },
    Blockquote {
        nodes: Vec<AstNode>,
    },
    CodeBlock {
        language: Option<String>,
        code: String,
    },
    ThematicBreak,
    Image {
        alt_text: String,
        url_or_path: String,
    },

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
// Two tiers, and the distinction is load-bearing for the frame budget.
//
// `update_block` is the per-keystroke call: it buffers text and writes a
// draft row, returns nothing, and never parses. Every OTHER mutating call
// below commits a splice into the file's source text and reparses, returning
// the whole new state -- and each is triggered by a discrete user action
// (blur, Enter, Backspace, a range edit), not by typing.
//
// `block_path` is an index path into the AST and is NOT stable across a
// reparsing call: a splice can change a Block's node shape (a paragraph
// becoming a list). Callers must re-derive focus from the returned state
// rather than retaining a path across such a mutation.
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

/// Records the focused Block's current source text. This is the per-keystroke
/// call, and it is deliberately cheap: it substitutes the text into the
/// in-memory note source and writes the resulting `drafts` row (ADR-008
/// tier 1). It does **not parse**, does not touch the file on disk, and does
/// not return an AST.
///
/// The distinction that matters is parse, not splice. A byte substitution
/// into a buffer is O(file) memcpy at worst and carries no correctness risk;
/// a parse is what costs, and what the span map depends on. `drafts`
/// stores the full note source (`schema.sql`), so producing that row
/// necessarily involves substituting this Block's text into it.
///
/// Takes source text, not an `AstNode` -- the prior AST-based signature
/// required reconstructing Markdown from a tree, which needed a canonical
/// form nothing ever specified and would have rewritten unedited regions in
/// violation of the Edit Fidelity constraint.
///
/// Returning nothing is what keeps the 16ms budget reachable. While a Block
/// is focused it displays raw source the UI already holds -- the text the
/// user just typed -- and no other Block's rendering can change, so there is
/// nothing for a per-keystroke AST to tell the caller. Reparsing here would
/// put an O(file) parse plus a full-AST FFI payload on every keystroke of a
/// `#[frb(sync)]` call, which is exactly what ADR-007, ADR-008 and
/// `architecture/risks.md` risk 7 all claim the tiering avoids.
#[frb(sync)]
pub fn update_block(
    note_id: String,
    block_path: Vec<usize>,
    new_source: String,
) -> Result<(), AppError> {
    unimplemented!()
}

/// Commits the focused Block: splices its buffered source over that Block's
/// span, reparses, and returns the new state (ADR-007 decision 1).
///
/// Called when the Block loses focus, not on every keystroke. This is where
/// the reparse cost lands, alongside the tier 2 write, off the typing path.
///
/// A splice can change a Block's node shape -- a paragraph gaining a leading
/// list marker reparses as a list -- so the returned state is authoritative
/// and the caller must re-derive focus from it rather than reusing the
/// `block_path` it passed in.
#[frb(sync)]
pub fn commit_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Inserts a new Block at `block_path`, shifting subsequent Blocks down.
#[frb(sync)]
pub fn insert_block(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Splits a Block at a character offset -- pressing Enter mid-Block
/// (CAP-EDIT-03).
#[frb(sync)]
pub fn split_block(
    note_id: String,
    block_path: Vec<usize>,
    offset: usize,
) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Merges a Block into its predecessor -- pressing Backspace at offset 0
/// (CAP-EDIT-03). A no-op on the first Block.
#[frb(sync)]
pub fn merge_block_with_previous(
    note_id: String,
    block_path: Vec<usize>,
) -> Result<NoteState, AppError> {
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
pub fn replace_range(
    note_id: String,
    range: BlockRange,
    replacement: String,
) -> Result<NoteState, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Persistence (ADR-008)
// ---------------------------------------------------------------------------

/// Forces tier 2 immediately: splices pending edits into the file and writes
/// it atomically (temp file plus rename). Returns the new `base_revision`.
///
/// **The debounce that normally triggers tier 2 lives in the Core, not the
/// UI.** This function is the explicit-flush escape hatch — used by
/// `close_note`, by application shutdown, and by tests — not the routine
/// path. The UI is not required to call it at all.
///
/// It deliberately takes no `expected_base_revision`. The Core recorded the
/// on-disk hash when the Note was opened and compares against that, rejecting
/// with `RevisionMismatch` if the file changed underneath the draft — the
/// Optimistic Concurrency Control in `architecture/risks.md` risk 6, now
/// guarding file content rather than a database column.
///
/// Requiring the token from the caller would be actively wrong here: a
/// Core-owned idle timer writes the file and advances the revision without
/// the UI observing it, so any token the UI still held from `open_note` would
/// be stale and every subsequent call would fail deterministically. That is
/// structurally the same defect ADR-007 decision 7 exists to fix, one layer
/// up. `NoteState.base_revision` remains exposed for display and diagnostics;
/// it is not an input.
#[frb]
pub async fn flush_note(note_id: String) -> Result<String, AppError> {
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
pub async fn pending_drafts() -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Discovery & the knowledge graph
// ---------------------------------------------------------------------------

/// Full-text search within one Workspace (CAP-FIND-01), bm25-ranked.
///
/// Scoped to the active Workspace, closing a real gap: the shipped signature
/// had no Workspace filter at all despite the capability being scoped to "all
/// Notes in their Workspace". The filter is applied Core-side rather than
/// taken as a parameter, per rule 2 above. `limit` replaces the hardcoded cap
/// of 50, which silently truncated with no signal to the caller.
#[frb]
pub async fn search_notes(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// Title-prefix jump (CAP-FIND-02).
#[frb]
pub async fn find_notes_by_title(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
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
pub async fn link_completions(query: String, limit: u32) -> Result<Vec<LinkCompletion>, AppError> {
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
/// The split is deliberate: generating cryptographic material belongs on the
/// Core side, while only the UI can open a browser and run the loopback
/// listener. `redirect_uri` is the loopback URL the UI is already listening
/// on.
///
/// **The Core does not validate either value.** It mints the verifier and
/// forwards it to the token endpoint on the UI's behalf; it mints `state` and
/// never sees it again. Comparing the `state` returned on the redirect
/// against the one issued here — the CSRF check required by RFC 6749 §10.12 —
/// is therefore a **UI obligation**, and a UI that skips it silently loses
/// that protection with nothing in the Core able to detect the omission.
/// Retaining the pair Core-side keyed by a flow id would move the check
/// behind this boundary; that is deliberately not done here, because it would
/// make the Core stateful across the browser leg for one comparison, and it
/// is recorded as an accepted trade-off rather than an oversight.
#[frb(sync)]
pub fn begin_oauth_flow(
    provider: String,
    redirect_uri: String,
) -> Result<OAuthFlowStart, AppError> {
    unimplemented!()
}

/// Exchanges the authorization code and stores the resulting tokens in OS
/// secure storage. Establishes a session only -- it does not clone, create,
/// or attach a Workspace. Under ADR-005 the Workspace already exists locally
/// before any of this is called.
#[frb]
pub async fn authenticate_workspace(
    provider: String,
    auth_code: String,
    code_verifier: String,
) -> Result<SessionState, AppError> {
    unimplemented!()
}

/// Attaches a Remote to an existing local Workspace and publishes its
/// history (CAP-SYNC-01). Provisions a new private repository when
/// `repository` is `None`, otherwise adopts the named one, which must be
/// empty. Updates `workspaces.provider` and `remote_url` in place; never
/// re-clones or discards local state.
#[frb]
pub async fn connect_remote(
    provider: String,
    repository: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
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
pub async fn notes_with_conflicts() -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// Replaces a `Suggestion` node with the chosen resolution, splicing clean
/// Markdown with no conflict markers over its span.
#[frb(sync)]
pub fn resolve_suggestion(
    note_id: String,
    block_path: Vec<usize>,
    choice: SuggestionChoice,
) -> Result<NoteState, AppError> {
    unimplemented!()
}
