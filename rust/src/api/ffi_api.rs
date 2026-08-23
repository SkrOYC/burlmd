use flutter_rust_bridge::frb;

// AST types are owned by the `markdown` domain module (parsing is what
// produces and shapes them); re-exported here so they cross the FFI
// boundary FRB scans (`rust_input: crate::api`) without `markdown`
// having to depend back on this module for its own output types. `AppError`
// is re-exported the same way, from a shared leaf module, so `db` and
// `security` can report failures without depending upward on `api`.
// `NoteMetadata`/`NoteState` are re-exported from `draft` — this module's own
// job is just the thin `#[frb]` wrappers below, not the draft-state domain
// logic.
pub use crate::draft::{NoteMetadata, NoteState};
pub use crate::error::AppError;
pub use crate::markdown::{AstNode, InlineElement, TextRun};
// `WorkspaceInfo` is owned by the `workspace` domain module for the same
// reason the types above are owned by `draft`/`markdown`: `workspace::bootstrap`
// is where the bootstrap logic actually lives (tested directly against an
// injected `Connection`), and this module's own job is the thin `#[frb]`
// wrappers below.
pub use crate::workspace::WorkspaceInfo;
// Same reason again for the persistence tier: `workspace::persist` owns
// ADR-008's machinery and the type it reports through, and the `#[frb]`
// functions below are wrappers over it.
pub use crate::workspace::NoteWriteStatus;
// Same reason again for the lifecycle domain: `workspace::lifecycle` owns the
// atomic create/rename/move/delete machinery and the two shapes it reports
// through, and the `#[frb]` functions below are wrappers over it.
pub use crate::workspace::{IdRemap, LifecycleEffects};
// `LinkCompletion` and `TreeNode` are owned by `index::query` (WSPC-D009),
// the discovery-domain module, for the same reason as every re-export above:
// the logic that fills them lives there, tested directly against an injected
// `Connection`, and this module's own job is the thin `#[frb]` wrappers below.
pub use crate::index::query::{LinkCompletion, TreeNode};

/// Opens the local Workspace, creating and initializing it if absent
/// (ADR-005 decision 1): creates the directory, initializes a Git repository
/// in place, and writes a `workspaces` row with `provider = "local"`. Root
/// key generation and opening the encrypted index both happen as a side
/// effect of `db::connection::connection()` below, on first use in this
/// process — see `security::keyring::get_or_create_root_key`.
///
/// Requires no credential, no provider, and no network — this is the call
/// that makes the Local-First Mandate in `prd/constraints.md` literally true
/// (CAP-WS-01). `path` is `None` to use the default location specified in
/// `guidelines.md`.
///
/// Establishes the active Workspace on success (ADR-005 decision 7,
/// WSPC-D004 review finding #3): every later Note-level call is implicitly
/// scoped to whichever Workspace was most recently opened by this function
/// or [`open_workspace`], via `db::connection::active_workspace_id`.
#[frb]
pub async fn open_or_create_local_workspace(
    path: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    // No `with_connection` wrapper here on purpose: bootstrap initializes a
    // repository, sweeps the bundle and reads every Note in it, and holding the
    // process-wide connection mutex across all three is what `SPK-WSPC-D001`
    // §6.2.7 forbids. The bootstrap acquires the connection itself, for its
    // statements only.
    let info = crate::workspace::bootstrap::open_or_create_local_workspace(path)?;
    crate::db::connection::set_active_workspace_id(info.id.clone())?;
    Ok(info)
}

/// Opens an existing Workspace directory that this application did not
/// create, including one populated by another tool (CAP-WS-05). Converges on
/// the same post-conditions as [`open_or_create_local_workspace`] — see
/// `workspace::bootstrap`'s module documentation and ADR-005 decision 8,
/// including establishing the active Workspace on success.
#[frb]
pub async fn open_workspace(path: String) -> Result<WorkspaceInfo, AppError> {
    // See [`open_or_create_local_workspace`] on why the connection is not held
    // across this call.
    let info = crate::workspace::bootstrap::open_workspace(path)?;
    crate::db::connection::set_active_workspace_id(info.id.clone())?;
    Ok(info)
}

/// Full rebuild of `notes`, `notes_fts`, `fts_mapping`, `links` and
/// `directories` for the active Workspace from the bundle on disk. Returns
/// the number of Notes indexed.
///
/// The index is derived state and is always discardable
/// (`data-models/schema.sql`). This closes Epic C deferred item 3:
/// `SyncDeps::default().reindex` in `rust/src/sync/scheduler.rs` is a
/// documented no-op because no re-index function existed anywhere in the
/// crate; one exists now, and wiring the scheduler's hook to it is the only
/// remaining step (deferred there by that ticket's scope, not by this one).
///
/// Per `architecture/risks.md` risk 3 this is **not** the routine path for
/// keeping the index current — `index::incremental::index_note` is. It exists
/// for first open, post-merge reconciliation, and recovery.
///
/// **Two phases, and only the second holds the connection.** The walk reads and
/// parses every Note in the Workspace; running it inside the `with_connection`
/// closure held the process-wide mutex — the one a keystroke's own tier 1 draft
/// write waits on — for the whole of it, which `SPK-WSPC-D001` §6.2.7 forbids.
/// `scan_bundle` derives the rows with nothing held; `write_scanned_bundle` is
/// SQL only.
///
/// **Both phases run under the lifecycle lock**, because splitting them opened
/// an O(bundle) window between the snapshot and the write. A `rename_note`
/// completing inside it has already moved the file and rewritten its rows, but
/// the scan in flight was taken before the move — so the write phase reinstates
/// the old concept id, drops the new one, and leaves the index naming a file
/// that no longer exists. `write_scanned_bundle` is one transaction, so the two
/// never interleave *mid-write*; what needed serializing is scan-against-write,
/// which is what a lock spanning both gives.
///
/// The order holds: this is the topmost of `workspace::persist`'s four locks,
/// and the only other lock either phase takes is the connection, which is the
/// bottom one — `scan_bundle` walks the filesystem with nothing held at all
/// (`index::scan`'s own documentation on why it must not run inside a
/// connection closure), and `write_scanned_bundle` takes the connection
/// beneath this. Nothing here reaches back up.
///
/// The lock is **not reentrant**, so the ticket that finally wires
/// `SyncDeps::reindex` to this must dispatch it from the scheduler rather than
/// from inside a lifecycle operation. Nothing does today: `bootstrap::converge`
/// runs its own scan-and-rebuild and does not route through here.
#[frb]
pub async fn reindex_workspace() -> Result<u32, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::persist::with_lifecycle_lock(&workspace, || {
        let scanned = crate::index::scan::scan_bundle(workspace.root())?;
        crate::db::connection::with_connection(|conn| {
            crate::index::scan::write_scanned_bundle(conn, workspace.id(), &scanned)
        })
    })
}

/// Opens a Note by concept id, restoring an unflushed draft if one exists
/// (ADR-008 tier 1's crash recovery).
///
/// Replaces the previous `open_note(path)` entry point and the
/// `open_note_by_id(note_id)` the pre-v1.1.0 contract also named but never
/// implemented: under ADR-004 a Note's identity is unambiguous, so there is
/// exactly one open-a-Note entry point, and it is this one — a concept id,
/// never a filesystem path and never a `workspace_id` (the active Workspace
/// is always whichever `open_or_create_local_workspace`/`open_workspace` most
/// recently established).
///
/// `workspace::persist::open_note` is what this delegates to, and it already
/// carries the two obligations that mattered here: it rejects a concept id
/// that escapes the Workspace root (a lexical `../` check plus a
/// canonicalized containment check for a path that exists), and it parses
/// with the Note's real bundle-relative containing directory rather than an
/// empty one, so a Link inside a nested Note resolves against its own
/// directory instead of the bundle root.
///
/// `async` per the contract, though the body below runs to completion
/// synchronously with no `.await` — see `search_notes`'s comment on the same
/// point.
#[frb]
pub async fn open_note(note_id: String) -> Result<NoteState, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    let (_, state) = crate::workspace::persist::open_note(&workspace, &note_id)?;
    Ok(state)
}

/// Forces ADR-008 tier 2 immediately: writes the Note's working source to its
/// file atomically and returns the new `base_revision`.
///
/// The debounce that normally triggers tier 2 lives in the Core, not the UI —
/// this is the explicit-flush escape hatch used by `close_note`, by application
/// shutdown, and by tests. It takes no revision token: the Core holds one per
/// open Note and replaces it after every successful write, so any token the UI
/// still held would be stale by construction.
#[frb]
pub async fn flush_note(note_id: String) -> Result<String, AppError> {
    open_session(&note_id)?.flush()
}

/// Status of the write tier for one open Note (ADR-008). Never fails: a Note
/// that is not open reports no error and no unwritten edits.
///
/// **Not open and not readable are different answers.** The default is what a
/// Note nobody has opened reports, and reporting it for a session whose state
/// lock is *poisoned* — a panic left a mutator part-way through, so what the
/// buffer holds and whether it reached disk are both unknown — told the UI the
/// Note was clean and its work safe, which is the one thing this poll exists to
/// contradict. Only [`AppError::NotFound`], which is what `open_session` raises
/// for a Note with no session, means "not open"; every other failure is carried
/// out in `last_error`, alongside `has_unwritten_edits = true`, because nothing
/// can establish that the buffer reached disk.
#[frb(sync)]
pub fn note_write_status(note_id: String) -> NoteWriteStatus {
    let status = match open_session(&note_id) {
        Err(AppError::NotFound(_)) => return NoteWriteStatus::default(),
        Err(unreadable) => Err(unreadable),
        Ok(session) => session.write_status(),
    };
    status.unwrap_or_else(|error| NoteWriteStatus {
        last_written_at: None,
        last_error: Some(error),
        has_unwritten_edits: true,
    })
}

/// Discards the buffered edits and re-reads the Note from disk, returning a
/// state with `restored_from_draft = false`.
///
/// This is the other half of `RevisionMismatch` and the only exit from it:
/// `open_note` restores the draft in preference to disk and tier 2 leaves that
/// row in place when it fails, so a reopen would return the buffer that just
/// lost the comparison and fail again on every tick. It **destroys unwritten
/// work by design**, so the UI must confirm first.
#[frb]
pub async fn reload_note(note_id: String) -> Result<NoteState, AppError> {
    open_session(&note_id)?.reload()
}

/// Tier 3: flushes any pending write, makes one Git commit covering this
/// editing session for this Note alone, clears the `drafts` row, and notifies
/// the sync scheduler — which has existed since Epic C with no caller.
///
/// Must also run on application quit and when switching away from a Note, or
/// the session reaches disk but never enters version history.
#[frb]
pub async fn close_note(note_id: String) -> Result<(), AppError> {
    open_session(&note_id)?.close()
}

/// Notes with an unflushed draft from a previous session, for surfacing
/// recovered work on startup (CAP-WS-03).
#[frb]
pub async fn pending_drafts() -> Result<Vec<NoteMetadata>, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::persist::pending_drafts(&workspace)
}

// ---------------------------------------------------------------------------
// Note & Directory lifecycle (CAP-LIFE-01 .. CAP-LIFE-06)
//
// Because OKF identity is positional (ADR-004), rename and move change a
// Note's concept id — so each rewrites the file, its index rows, every inbound
// Link, every affected `drafts` row and every affected open session in one
// operation that either completes or changes nothing
// (`architecture/risks.md` risk 8). `workspace::lifecycle` is where that lives
// and where it is tested; these are thin wrappers over it.
// ---------------------------------------------------------------------------

/// Creates a Note in `directory_path` (empty string for the bundle root) with
/// an OKF-conformant frontmatter block, and **opens it**: the returned state is
/// the state of an open Note, so the working source, span map and recorded
/// revision are all established before this returns and `note_write_status`
/// reports on it immediately.
///
/// The filename is the title **verbatim** plus `.md`
/// (`data-models/okf-bundle.md`) — no slugification, because CAP-GRAPH-04's
/// create-on-follow has to invert the derivation. A collision, or a title
/// deriving to a reserved OKF filename, returns `PathUnavailable` rather than
/// silently disambiguating.
#[frb]
pub async fn create_note(directory_path: String, title: String) -> Result<NoteState, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::create_note(&workspace, &directory_path, &title)
}

/// Deletes a Note and commits the deletion, so it stays recoverable from local
/// version history (CAP-LIFE-04). Clears the `drafts` row and the `notes_fts`
/// row explicitly — neither is reached by the `notes` cascade, and the FTS row
/// must go first or it is stranded permanently (`data-models/schema.sql`).
#[frb]
pub async fn delete_note(note_id: String) -> Result<(), AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::delete_note(&workspace, &note_id)
}

/// Renames a Note, rewriting its frontmatter `title`, its filename, and every
/// inbound Link that targets it (CAP-LIFE-02).
///
/// This changes the Note's concept id: the returned state carries the new one
/// and callers must not retain the old. The returned `LifecycleEffects` names
/// every *other* Note whose bytes moved, which the caller must reload — an open
/// one still holds an `InlineElement::Link` carrying the old `target_id`.
#[frb]
pub async fn rename_note(
    note_id: String,
    new_title: String,
) -> Result<(NoteState, LifecycleEffects), AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::rename_note(&workspace, &note_id, &new_title)
}

/// Moves a Note to another Directory, rewriting every inbound Link
/// (CAP-LIFE-03). Changes the Note's id, as `rename_note` does. Returns
/// `PathUnavailable` when the destination already holds a Note of that
/// filename, or when the destination path does not exist.
#[frb]
pub async fn move_note(
    note_id: String,
    new_directory_path: String,
) -> Result<(NoteState, LifecycleEffects), AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::move_note(&workspace, &note_id, &new_directory_path)
}

/// Creates a Directory, including intermediate levels (CAP-LIFE-05). An empty
/// Directory has no file to represent it, so it exists in the `directories`
/// table until it holds a Note — and makes no commit, since Git tracks no
/// empty directory.
#[frb]
pub async fn create_directory(path: String) -> Result<(), AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::create_directory(&workspace, &path)
}

/// Renames a Directory, moving its contents and rewriting inbound Links to
/// every Note beneath it (CAP-LIFE-06). The Notes holding rewritten Links are
/// **not** confined to that subtree, which is why both halves of
/// `LifecycleEffects` are populated here.
#[frb]
pub async fn rename_directory(
    path: String,
    new_name: String,
) -> Result<LifecycleEffects, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::rename_directory(&workspace, &path, &new_name)
}

/// Deletes a Directory and everything beneath it, in one commit (CAP-LIFE-06).
/// Returns the concept ids of every Note removed, so a caller with one of them
/// open can close it rather than discovering it is gone on next access.
#[frb]
pub async fn delete_directory(path: String) -> Result<Vec<String>, AppError> {
    let workspace = crate::workspace::persist::Workspace::active()?;
    crate::workspace::lifecycle::delete_directory(&workspace, &path)
}

/// The open session for `note_id`, or `NotFound` when the Note is not open.
///
/// Kept private: which Notes are open is Core-side state, and the contract
/// exposes it only through the functions above.
fn open_session(note_id: &str) -> Result<crate::workspace::persist::NoteSession, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::workspace::persist::lookup(&workspace_id, note_id)?
        .ok_or_else(|| AppError::NotFound(format!("no open Note with id {note_id}")))
}

// ---------------------------------------------------------------------------
// Editing (ADR-006, ADR-007)
//
// `update_block` is the per-keystroke call and the only one that does not
// parse: it substitutes text, adjusts spans arithmetically, writes the draft
// row, and returns nothing. Every other mutator below reparses the working
// source, rebuilds the span map, and returns the whole new state.
// `commit_block` is the one exception in both directions: it reparses but
// writes nothing, because `update_block` already put the text it reparses
// into both the working source and the draft row. See `contracts/ffi_api.rs`'s
// Editing section header for the reasoning in full.
// ---------------------------------------------------------------------------

/// The raw Markdown source of one Block, for populating the editable field
/// when it takes focus (ADR-006 decision 2). Includes the Block's own
/// delimiters and its terminating newline — whatever this hands the UI must
/// come back to `update_block` unmodified in the untouched portion, or the
/// next `commit_block` reparses a working source missing the separator that
/// kept this Block distinct from its neighbor, and the two silently merge.
#[frb(sync)]
pub fn get_block_source(note_id: String, block_path: Vec<usize>) -> Result<String, AppError> {
    open_session(&note_id)?.block_source(&block_path)
}

/// One pointer-resolved raw-source caret. Both fields use Flutter UTF-16 code
/// units: `block_path` is the actual editable leaf, and `caret_offset` is an
/// offset into that leaf's raw Markdown source. The input path to
/// [`resolve_block_caret`] is top-level only, so Dart never infers a nested
/// path from widget layout or Markdown punctuation.
#[frb]
pub struct BlockCaret {
    pub block_path: Vec<usize>,
    pub caret_offset: usize,
}

/// Authoritative result of a structural edit that keeps the raw editor open.
/// The Core reparses before returning, then names the editable leaf and
/// Flutter UTF-16 caret in that resulting tree; Presentation never predicts
/// a sibling path from the tree shape it just invalidated.
#[frb]
pub struct StructuralEdit {
    pub state: NoteState,
    pub block_path: Vec<usize>,
    pub caret_offset: usize,
}

/// Resolves a rendered pointer position synchronously through the Core span
/// map. `top_level_path` contains exactly one top-level Block index and
/// `rendered_utf16_offset` is Flutter's `TextPosition.offset` in the Core's
/// canonical rendered string for that Block. Invalid offsets (including one
/// splitting a surrogate pair) return `ParseError` rather than silently
/// rounding to a different character.
#[frb(sync)]
pub fn resolve_block_caret(
    note_id: String,
    top_level_path: Vec<usize>,
    rendered_utf16_offset: usize,
) -> Result<BlockCaret, AppError> {
    let (block_path, caret_offset) =
        open_session(&note_id)?.resolve_block_caret(&top_level_path, rendered_utf16_offset)?;
    Ok(BlockCaret {
        block_path,
        caret_offset,
    })
}

/// The per-keystroke call (ADR-007 decision 4, ADR-008 tier 1): substitutes
/// `new_source` into the Note's working source over the focused Block's
/// span, adjusts the span map arithmetically, and writes the draft row. Does
/// **not** parse and returns nothing — the reparse belongs to `commit_block`,
/// which is what keeps this call cheap enough to stay off the frame-budget
/// critical path.
#[frb(sync)]
pub fn update_block(
    note_id: String,
    block_path: Vec<usize>,
    new_source: String,
) -> Result<(), AppError> {
    open_session(&note_id)?.update_block(&block_path, &new_source)
}

/// Reparses the Note's working source and rebuilds the span map when the
/// focused Block loses focus (ADR-007 decision 1). Performs no splice —
/// `update_block` already substituted the text this reparses, so splicing it
/// again here would duplicate it (ADR-008 decision 2's failure mode). Writes
/// no draft row either, for the matching reason: `update_block` already wrote
/// whatever this reparses, and tier 2 clears the row on a successful write.
#[frb(sync)]
pub fn commit_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    open_session(&note_id)?.commit_block(&block_path)
}

/// Inserts a new Block at `block_path`, shifting subsequent Blocks down.
#[frb(sync)]
pub fn insert_block(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.insert_block(&block_path, source)
}

#[frb(sync)]
pub fn delete_block(note_id: String, block_path: Vec<usize>) -> Result<NoteState, AppError> {
    open_session(&note_id)?.delete_block(&block_path)
}

/// Splits a Block at a Flutter **UTF-16** offset into its source -- pressing
/// Enter mid-Block (CAP-EDIT-03). The focused Block displays raw source under
/// ADR-006, so the caret position the UI reports is an offset into the Block's
/// source rather than into its rendered text. A surrogate interior is refused;
/// Core converts valid UTF-16 boundaries to its internal byte spans.
#[frb(sync)]
pub fn split_block(
    note_id: String,
    block_path: Vec<usize>,
    offset: usize,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.split_block(&block_path, offset)
}

/// Merges a Block into its predecessor -- Backspace at offset 0
/// (CAP-EDIT-03). A no-op on the first Block.
#[frb(sync)]
pub fn merge_block_with_previous(
    note_id: String,
    block_path: Vec<usize>,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.merge_block_with_previous(&block_path)
}

/// Continues after an editable leaf, returning Core's post-reparse focus
/// target. Core, rather than Flutter's widget-path shape, inspects the AST:
/// a leaf in a List gets a sibling ListItem; every other leaf gets an
/// independent Block after its top-level container (so a Blockquote leaf exits
/// the quote).
#[frb(sync)]
pub fn continue_block_after(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
) -> Result<StructuralEdit, AppError> {
    let (state, block_path) = open_session(&note_id)?.continue_block_after(&block_path, &source)?;
    Ok(StructuralEdit {
        state,
        block_path,
        caret_offset: source.encode_utf16().count(),
    })
}

/// A selection spanning one or more unfocused Blocks, expressed as character
/// offsets into each Block's **rendered** text (ADR-006 decision 3). A caller
/// must blur and commit any focused Block, then establish a fresh rendered
/// selection before calling a range operation; this API never accepts raw
/// focused-field offsets or a range over an uncommitted span map. See
/// `contracts/ffi_api.rs` for the per-`AstNode`-variant definition of
/// "rendered text" these offsets are into.
#[frb]
pub struct BlockRange {
    pub start_path: Vec<usize>,
    pub start_offset: usize,
    pub end_path: Vec<usize>,
    pub end_offset: usize,
}

/// A pure change of ownership. `BlockRange` is `markdown::spans::RenderedRange`'s
/// FFI-boundary twin and the two carry the same four fields for exactly that
/// reason — see that type's own documentation.
impl From<BlockRange> for crate::markdown::RenderedRange {
    fn from(range: BlockRange) -> Self {
        crate::markdown::RenderedRange::new(
            range.start_path,
            range.start_offset,
            range.end_path,
            range.end_offset,
        )
    }
}

/// Markdown for a multi-Block selection (CAP-EDIT-04), executed Core-side
/// because the Core owns both the AST and the source text; reproducing it in
/// Dart would mean a second serializer.
#[frb(sync)]
pub fn copy_range_as_markdown(note_id: String, range: BlockRange) -> Result<String, AppError> {
    open_session(&note_id)?.copy_range_as_markdown(&range.into())
}

#[frb(sync)]
pub fn delete_range(note_id: String, range: BlockRange) -> Result<NoteState, AppError> {
    open_session(&note_id)?.delete_range(&range.into())
}

/// Replaces a multi-Block selection with text -- typing over a selection that
/// crosses Blocks. The caller must re-derive caret position from the
/// returned state rather than reusing anything passed in.
#[frb(sync)]
pub fn replace_range(
    note_id: String,
    range: BlockRange,
    replacement: String,
) -> Result<NoteState, AppError> {
    open_session(&note_id)?.replace_range(&range.into(), &replacement)
}

/// FTS5's bare `MATCH` syntax is a full query language (boolean operators,
/// `column:` filters, `-token` exclusion, `"phrase"` grouping, ...), so
/// passing raw user input straight to `MATCH` throws a syntax error on
/// perfectly ordinary searches — a hyphenated word, a colon, unbalanced
/// quotes. Quoting the *whole* query as one phrase would dodge that (FTS5's
/// own escaping rule: double any embedded `"`), but it also silently changes
/// what a "search my notes" box means: a phrase match requires every term to
/// appear adjacent and in that exact order, whereas users expect a multi-word
/// query to match notes containing all the terms, in any order. Quoting each
/// whitespace-split token *separately* instead keeps FTS5's implicit AND
/// across terms (its default when tokens aren't otherwise joined by an
/// operator) while still neutralizing the syntax footguns, since no operator
/// character can survive inside its own quoted token. A query with no tokens
/// at all (empty or whitespace-only input) produces an empty string here;
/// callers should treat that as "no results" rather than pass it to `MATCH`.
fn fts5_phrase_query(query: &str) -> String {
    query
        .split_whitespace()
        .map(|token| format!("\"{}\"", token.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(" ")
}

/// The search query itself, factored out of [`search_notes_impl`] so that
/// `index::scan`'s query-plan test asserts against the statement production
/// actually runs. WSPC-D005 carries a criterion on this plan — it must drive
/// from `notes_fts`, reach `fts_mapping` through `idx_fts_mapping_rowid`, and
/// contain no AUTOMATIC COVERING INDEX step — and a test holding its own copy
/// of the SQL would keep passing after the real query drifted away from it.
///
/// Parameters: `?1` is the FTS5 `MATCH` expression (see
/// [`fts5_phrase_query`]), `?2` the Workspace id.
///
/// Both joins are `CROSS JOIN`, which in SQLite is not a different join —
/// it is the documented way to pin the outer table and stop the planner
/// reordering. It is load-bearing here, and measured: with plain `JOIN`, a
/// Workspace of 10 or 200 Notes plans as `SCAN notes` → `SEARCH fts_mapping`
/// → `SCAN notes_fts VIRTUAL TABLE`, i.e. it re-runs the full-text match once
/// per Note — the catastrophic plan `data-models/schema.sql` distinguishes
/// from the merely-wasteful automatic-covering-index one. It happens to pick
/// the right order at 1000 Notes, which is exactly why WSPC-D005's criterion
/// is stated against the plan rather than a timing: the corpus size at which
/// the timing test runs is the size at which the defect hides. Pinned, the
/// plan is `SCAN notes_fts` → `SEARCH fts_mapping USING idx_fts_mapping_rowid`
/// → `SEARCH n USING sqlite_autoindex_notes_1`, at every corpus size, with and
/// without table statistics, and the `ORDER BY rank` temp b-tree disappears
/// with it because FTS5 already returns rows in rank order.
pub(crate) const SEARCH_NOTES_SQL: &str = "SELECT n.id, n.okf_conformant, n.path, n.title, \
            n.last_modified, snippet(notes_fts, 1, '', '', '…', 8) AS snippet \
     FROM notes_fts \
     CROSS JOIN fts_mapping ON fts_mapping.fts_rowid = notes_fts.rowid \
     CROSS JOIN notes n ON n.workspace_id = fts_mapping.workspace_id \
                        AND n.id = fts_mapping.note_id \
     WHERE notes_fts MATCH ?1 AND fts_mapping.workspace_id = ?2 \
     ORDER BY rank";

/// Full-text search over all indexed notes, ordered by FTS5 relevance
/// (bm25, best match first). `notes_fts` only carries `(title, content)`;
/// `fts_mapping` is the `(workspace_id, note_id)` <-> `fts_rowid` join table
/// maintained alongside it, used here to recover the owning `notes` row per
/// hit.
///
/// Scoped to `workspace_id` (WSPC-D004 review finding #4): `WSPC-D004`
/// brought `notes` and `fts_mapping` onto the composite `(workspace_id, id)`
/// key `data-models/schema.sql` specifies, so joining `fts_mapping` to
/// `notes` on `note_id` alone — and filtering by nothing at all — became a
/// cross-Workspace hazard the moment a second Workspace's rows exist in the
/// same index (ADR-005 decision 7: the index accumulates rows for every
/// Workspace ever opened, CAP-WS-05). It was also, independently, a full
/// scan of `fts_mapping` on every search rather than a lookup through its
/// primary key.
///
/// `SEARCH_NOTES_SQL` deliberately carries no `LIMIT` of its own — this is
/// the fix `WSPC-D009` makes for the hardcoded cap of 50 that used to sit at
/// the end of that constant and silently truncate with no signal to the
/// caller (`architecture/flows/flow-search.md`). The `limit` argument is
/// bound as `?3` on a copy of the statement with `LIMIT ?3` appended, kept
/// out of the shared constant so `index::scan`'s query-plan test — which
/// asserts against `SEARCH_NOTES_SQL` by name and is out of this ticket's
/// scope — keeps exercising the same base query this function actually runs.
fn search_notes_impl(
    conn: &rusqlite::Connection,
    query: &str,
    workspace_id: &str,
    limit: u32,
) -> Result<Vec<NoteMetadata>, AppError> {
    let fts_query = fts5_phrase_query(query);
    if fts_query.is_empty() {
        return Ok(Vec::new());
    }

    let sql = format!("{SEARCH_NOTES_SQL} LIMIT ?3");
    let mut stmt = conn.prepare(&sql)?;

    let rows = stmt.query_map(rusqlite::params![fts_query, workspace_id, limit], |row| {
        Ok(NoteMetadata {
            id: row.get(0)?,
            okf_conformant: row.get(1)?,
            path: row.get(2)?,
            title: row.get(3)?,
            last_modified: row.get(4)?,
            snippet: row.get(5)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

// `async` per the TechSpec FFI contract, even though `guidelines.md`'s Rust
// section otherwise prefers synchronous local-index queries: the body below
// runs to completion synchronously (a blocking mutex lock, then the query)
// with no `.await` inside it, so this doesn't yield to an executor — the
// `async` marker only affects how FRB dispatches the call across the
// boundary, not this function's own execution.
/// Full-text search within the active Workspace (CAP-FIND-01), bm25-ranked.
///
/// `limit` is SQL `LIMIT`, so **`limit == 0` returns no results** — it is not
/// read as "unlimited". `contracts/ffi_api.rs` introduces the parameter purely
/// to replace a hardcoded cap of 50 that "silently truncated with no signal to
/// the caller" and asserts no lower bound, so zero is a coherent request
/// answered literally rather than an error or an implicit "all rows".
#[frb]
pub async fn search_notes(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        search_notes_impl(conn, &query, &workspace_id, limit)
    })
}

/// Title-prefix jump (CAP-FIND-02). `limit` carries [`search_notes`]'
/// semantics, including `0` returning no results.
#[frb]
pub async fn find_notes_by_title(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::find_notes_by_title_impl(conn, &workspace_id, &query, limit)
    })
}

/// Candidates for the completion triggered by `[[` (CAP-GRAPH-02). The
/// trigger is a UI affordance; what gets inserted is `LinkCompletion::insert_text`,
/// built Core-side. `limit` carries [`search_notes`]' semantics, including `0`
/// returning no candidates.
#[frb]
pub async fn link_completions(query: String, limit: u32) -> Result<Vec<LinkCompletion>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::link_completions_impl(conn, &workspace_id, &query, limit)
    })
}

/// Notes linking *to* this one (CAP-GRAPH-05).
#[frb]
pub async fn backlinks(note_id: String) -> Result<Vec<NoteMetadata>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::backlinks_impl(conn, &workspace_id, &note_id)
    })
}

/// The Directory tree for the sidebar, Directories before Notes, each level
/// sorted by name.
#[frb]
pub async fn workspace_tree() -> Result<Vec<TreeNode>, AppError> {
    let workspace_id = crate::db::connection::active_workspace_id()?;
    crate::db::connection::with_connection(|conn| {
        crate::index::query::workspace_tree_impl(conn, &workspace_id)
    })
}

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::*;

    // These exercise `search_notes_impl` directly against an in-memory,
    // unencrypted connection rather than through the `search_notes` FFI
    // wrapper and the process-wide `db::connection::connection()` singleton:
    // the singleton is lazily initialized once per test binary, so routing
    // through it here would make tests order-dependent on which one opens
    // (and fixes the path of) the shared connection first. Encryption itself
    // is already covered by `db::connection`'s own tests; these tests are
    // only responsible for the SQL logic.
    fn seeded_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        crate::db::connection::init_schema(&conn).unwrap();
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES ('ws', 'Test Workspace', 'local', NULL, '/tmp/ws')",
            [],
        )
        .unwrap();
        conn
    }

    // WSPC-D004 brought `db/schema.sql` in line with `data-models/schema.sql`:
    // `notes.content_hash` and `fts_mapping.workspace_id` are both now
    // `NOT NULL`, where the pre-existing fixture below inserted into neither.
    // A throwaway, deterministic-per-call hash stands in for the real
    // content hash `WSPC-D005`'s indexer will compute; nothing in this
    // module's own tests inspects its value.
    fn seed_note(conn: &Connection, id: &str, title: &str, content: &str, last_modified: i64) {
        conn.execute(
            "INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash) \
             VALUES (?1, 'ws', ?2, ?3, ?4, ?5)",
            rusqlite::params![
                id,
                format!("{id}.md"),
                title,
                last_modified,
                format!("hash-{id}")
            ],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO notes_fts (title, content) VALUES (?1, ?2)",
            rusqlite::params![title, content],
        )
        .unwrap();
        let fts_rowid = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO fts_mapping (workspace_id, note_id, fts_rowid) VALUES ('ws', ?1, ?2)",
            rusqlite::params![id, fts_rowid],
        )
        .unwrap();
    }

    #[test]
    fn search_notes_finds_a_match_via_fts5_and_returns_its_metadata() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        seed_note(
            &conn,
            "note-2",
            "Trip Planning",
            "Book flights to Rome",
            2000,
        );

        let results = search_notes_impl(&conn, "milk", "ws", 50).unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "note-1");
        assert_eq!(results[0].title, "Grocery List");
        assert_eq!(results[0].last_modified, 1000);
        assert!(results[0].snippet.as_deref().unwrap().contains("milk"));
    }

    #[test]
    fn search_notes_returns_no_results_for_a_non_matching_query() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        let results = search_notes_impl(&conn, "spaceship", "ws", 50).unwrap();

        assert!(results.is_empty());
    }

    #[test]
    fn search_notes_does_not_choke_on_fts5_syntax_characters_in_ordinary_queries() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        // Each of these is a bare `MATCH` syntax error without phrase-quoting
        // (hyphen is an exclusion operator, `:` introduces a column filter,
        // parens group a boolean expression, and an unmatched `"` is an
        // unterminated string) — none of them should ever surface as an
        // AppError to a user just typing an ordinary search.
        for query in ["note-1", "budget:2024", "hello (world", "\"unbalanced"] {
            search_notes_impl(&conn, query, "ws", 50).unwrap();
        }
    }

    #[test]
    fn search_notes_matches_notes_containing_every_query_term_in_any_order() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        seed_note(
            &conn,
            "note-2",
            "Reordered",
            "bread and milk, in that order",
            2000,
        );
        seed_note(&conn, "note-3", "Missing a term", "Buy milk only", 3000);

        let results = search_notes_impl(&conn, "milk bread", "ws", 50).unwrap();

        // A multi-word query is an implicit AND across per-token quoted
        // phrases (not one exact-phrase match), so word order shouldn't
        // matter — both note-1 and note-2 contain "milk" and "bread"
        // somewhere, note-3 doesn't contain "bread" at all.
        let ids: std::collections::HashSet<_> = results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, std::collections::HashSet::from(["note-1", "note-2"]));
    }

    #[test]
    fn search_notes_returns_nothing_for_an_empty_or_whitespace_only_query() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);

        assert!(search_notes_impl(&conn, "", "ws", 50).unwrap().is_empty());
        assert!(search_notes_impl(&conn, "   ", "ws", 50)
            .unwrap()
            .is_empty());
    }

    /// Gherkin: given an indexed Workspace, a full-text search run with a
    /// limit returns at most that many results, ranked best match first.
    #[test]
    fn search_notes_returns_at_most_the_caller_supplied_limit() {
        let conn = seeded_db();
        seed_note(&conn, "note-1", "One", "shared token alpha", 1000);
        seed_note(&conn, "note-2", "Two", "shared token beta", 2000);
        seed_note(&conn, "note-3", "Three", "shared token gamma", 3000);

        let results = search_notes_impl(&conn, "shared", "ws", 2).unwrap();

        assert_eq!(
            results.len(),
            2,
            "at most the caller's limit, not a hardcoded cap of 50"
        );
    }

    /// Gherkin (ranking half of the same criterion): with a limit smaller
    /// than the number of matches, the surviving result is the best match —
    /// bm25 rewards the Note whose content repeats the query term, so a
    /// limit of 1 must keep it over a Note mentioning the term only once.
    #[test]
    fn search_notes_ranks_the_better_match_first_under_a_tight_limit() {
        let conn = seeded_db();
        seed_note(&conn, "weak", "Weak Match", "distinctiveterm once", 1000);
        seed_note(
            &conn,
            "strong",
            "Strong Match",
            "distinctiveterm distinctiveterm distinctiveterm repeated",
            2000,
        );

        let results = search_notes_impl(&conn, "distinctiveterm", "ws", 1).unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(
            results[0].id, "strong",
            "bm25 ranks the note repeating the term ahead of the one mentioning it once"
        );
    }

    /// WSPC-D004 review finding #4: `notes`/`fts_mapping` moved onto a
    /// composite `(workspace_id, id)` key, so a search unscoped by
    /// `workspace_id` could return — or, worse, silently prefer — a hit from
    /// a Workspace other than the active one the moment two Workspaces'
    /// rows coexist in the index (ADR-005 decision 7). Two Workspaces here
    /// deliberately reuse the same `note_id` ("note-1"), which is exactly
    /// the collision a concept id being unique only within its own bundle
    /// permits.
    #[test]
    fn search_notes_does_not_return_a_match_from_a_different_workspace() {
        let conn = seeded_db();
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES ('other-ws', 'Other Workspace', 'local', NULL, '/tmp/other-ws')",
            [],
        )
        .unwrap();
        seed_note(&conn, "note-1", "Grocery List", "Buy milk and bread", 1000);
        conn.execute(
            "INSERT INTO notes (id, workspace_id, path, title, last_modified, content_hash) \
             VALUES ('note-1', 'other-ws', 'note-1.md', 'Also Milk', 1000, 'hash-other')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO notes_fts (title, content) VALUES ('Also Milk', 'Buy milk too')",
            [],
        )
        .unwrap();
        let other_fts_rowid = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO fts_mapping (workspace_id, note_id, fts_rowid) \
             VALUES ('other-ws', 'note-1', ?1)",
            [other_fts_rowid],
        )
        .unwrap();

        let results = search_notes_impl(&conn, "milk", "ws", 50).unwrap();

        assert_eq!(
            results.len(),
            1,
            "only the active Workspace's match may be returned"
        );
        // The title is what distinguishes the two rows now that `NoteMetadata`
        // carries no `workspace_id`: both Workspaces hold a `note-1`, which is
        // exactly the collision a concept id being unique only within its own
        // bundle permits.
        assert_eq!(results[0].title, "Grocery List");
    }

    // -- WSPC-D008: the editing FFI surface ---------------------------------
    //
    // Every function under test here — `get_block_source`, `update_block`,
    // `commit_block`, `split_block`, `merge_block_with_previous`,
    // `copy_range_as_markdown` — is a thin delegation onto `NoteSession`, so
    // these tests exercise the session directly through the same
    // `Workspace::for_test` seam `workspace::persist`'s own tests use, rather
    // than through the real `#[frb]` wrapper. Going through the wrapper would
    // mean routing through `db::connection::active_workspace_id`, which is
    // process-wide singleton state shared with `db::connection`'s own tests
    // (see that module's `active_workspace_id_reports_the_id_a_bootstrap_call_established`);
    // nothing here should race that. `open_session`'s delegation itself —
    // "call this one-line function with these arguments" — is checked by the
    // compiler at the `#[frb]` boundary: a wrong argument order or a wrong
    // return type does not compile.
    use std::sync::atomic::{AtomicU32, Ordering as AtomicOrdering};
    use std::time::Duration;

    use tempfile::TempDir;

    use crate::workspace::persist::{self, NoteSession, Workspace};

    struct EditingFixture {
        // Held for its `Drop` impl, which removes the temp directory; never
        // read directly.
        #[allow(dead_code)]
        dir: TempDir,
        workspace: std::sync::Arc<Workspace>,
    }

    impl EditingFixture {
        fn root(&self) -> std::path::PathBuf {
            self.dir.path().join("bundle")
        }

        fn write(&self, relative: &str, contents: &str) {
            let path = self.root().join(relative);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, contents).unwrap();
        }

        fn open(&self, note_id: &str) -> NoteSession {
            persist::open_note(&self.workspace, note_id).unwrap().0
        }
    }

    fn editing_fixture() -> EditingFixture {
        static NEXT_WORKSPACE: AtomicU32 = AtomicU32::new(0);

        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("bundle");
        std::fs::create_dir_all(&root).unwrap();
        crate::git::operations::init_repo(&root).unwrap();

        let key = [0x7bu8; 32]; // throwaway, never the real Keychain entry
        let conn = crate::db::connection::open_encrypted_db_with_key(
            &dir.path().join("index.sqlite3"),
            &key,
        )
        .unwrap();
        crate::db::connection::init_schema(&conn).unwrap();

        let workspace_id = format!(
            "ffi-editing-ws-{}",
            NEXT_WORKSPACE.fetch_add(1, AtomicOrdering::SeqCst)
        );
        conn.execute(
            "INSERT INTO workspaces (id, name, provider, remote_url, local_path) \
             VALUES (?1, 'Test Workspace', 'local', NULL, ?2)",
            rusqlite::params![workspace_id, root.to_string_lossy()],
        )
        .unwrap();

        // An interval no test here waits out: every scenario fires the tiers
        // (or none at all) explicitly.
        let workspace = Workspace::for_test(conn, workspace_id, root, Duration::from_secs(3600));
        EditingFixture { dir, workspace }
    }

    fn note_source(title: &str, body: &str) -> String {
        format!("---\ntype: Note\ntitle: {title}\n---\n\n{body}\n")
    }

    /// TDD order 1: `get_block_source` returns the raw Block source
    /// *including its terminating newline*, and feeding that text back into
    /// `update_block` unmodified must round-trip through `commit_block`
    /// without the two paragraphs silently merging — the D007 warning that
    /// whatever `get_block_source` hands back must come back verbatim.
    #[test]
    fn block_source_includes_the_terminating_newline_and_round_trips_without_merging() {
        let f = editing_fixture();
        f.write(
            "a.md",
            &note_source("A", "First paragraph.\n\nSecond paragraph."),
        );
        let session = f.open("a");

        let source = session.block_source(&[0]).unwrap();
        assert!(
            source.ends_with('\n'),
            "a Block's own source must include its terminating newline, got {source:?}"
        );
        assert_eq!(source, "First paragraph.\n");

        session.update_block(&[0], &source).unwrap();
        let state = session.commit_block(&[0]).unwrap();

        assert_eq!(
            state.ast.len(),
            2,
            "feeding get_block_source's own text back into update_block \
             verbatim must not merge the two paragraphs into one"
        );
    }

    /// TDD order 2: `update_block` writes the draft row but performs no
    /// parse — the AST held by the session (and the type system: `Result<(),
    /// AppError>` carries none back) is untouched until `commit_block` runs.
    #[test]
    fn update_block_writes_the_draft_row_and_does_not_reparse() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "Original text."));
        let session = f.open("a");
        let before = session.note_state().unwrap();
        assert!(!session.write_status().unwrap().has_unwritten_edits);

        session
            .update_block(&[0], "Rewritten, longer text.\n")
            .unwrap();

        assert!(
            session.write_status().unwrap().has_unwritten_edits,
            "update_block must write the draft row"
        );
        let after = session.note_state().unwrap();
        assert_eq!(
            after.ast, before.ast,
            "update_block must not reparse or rebuild the AST — that is \
             commit_block's job"
        );
        assert_eq!(
            after.base_revision, before.base_revision,
            "update_block must not touch the file on disk"
        );
    }

    /// TDD order 3: `commit_block` reparses the working source `update_block`
    /// already substituted into, and performs no second substitution — the
    /// typed text appears exactly once.
    #[test]
    fn commit_block_reparses_without_a_second_substitution() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "plain text"));
        let session = f.open("a");

        session.update_block(&[0], "- now a list\n").unwrap();
        let state = session.commit_block(&[0]).unwrap();

        assert!(
            matches!(state.ast[0], AstNode::List { .. }),
            "commit_block must reparse: the structural shape change only \
             appears after it, got {:?}",
            state.ast[0]
        );
        let source = session.working_source().unwrap();
        assert_eq!(
            source.matches("now a list").count(),
            1,
            "commit_block must not splice update_block's text in a second time"
        );
    }

    /// TDD order 4 (first half): splitting a Block at an offset produces two
    /// Blocks whose combined text reproduces the original — split introduces
    /// exactly one new separating newline, which is stripped from both sides
    /// before comparing so the check is about content, not formatting.
    #[test]
    fn splitting_a_block_produces_two_blocks_whose_combined_source_equals_the_original() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "helloworld"));
        let session = f.open("a");
        let original = session.block_source(&[0]).unwrap();

        let state = session.split_block(&[0], 5).unwrap();

        assert_eq!(state.ast.len(), 2, "a split must produce two Blocks");
        let first = session.block_source(&[0]).unwrap();
        let second = session.block_source(&[1]).unwrap();
        assert_eq!(
            format!("{first}{second}").replace('\n', ""),
            original.replace('\n', ""),
            "splitting must not lose or duplicate any of the original \
             Block's text"
        );
    }

    /// TDD order 4 (second half): merging the first Block with its
    /// (nonexistent) predecessor is a no-op and returns the unchanged state.
    #[test]
    fn merging_the_first_block_with_its_predecessor_is_a_no_op() {
        let f = editing_fixture();
        f.write("a.md", &note_source("A", "first\n\nsecond"));
        let session = f.open("a");
        let before = session.note_state().unwrap();

        let after = session.merge_block_with_previous(&[0]).unwrap();

        assert_eq!(
            after, before,
            "there is no predecessor of the first Block, so this must be a \
             no-op returning the unchanged state"
        );
    }

    /// TDD order 5: a selection spanning three Blocks, copied as Markdown,
    /// reproduces the selected content across all three.
    #[test]
    fn copying_a_range_across_three_blocks_reproduces_all_three() {
        let f = editing_fixture();
        f.write(
            "a.md",
            &note_source("A", "first block\n\nsecond block\n\nthird block"),
        );
        let session = f.open("a");
        let state = session.note_state().unwrap();
        assert_eq!(state.ast.len(), 3);

        let end_offset = crate::markdown::rendered_text(&state.ast[2])
            .chars()
            .count();
        let range = crate::markdown::RenderedRange::new(vec![0], 0, vec![2], end_offset);

        let copied = session.copy_range_as_markdown(&range).unwrap();

        assert!(copied.contains("first block"));
        assert!(copied.contains("second block"));
        assert!(copied.contains("third block"));
    }

    /// `BlockRange` (the FFI-boundary type) converts to `RenderedRange` (the
    /// Core-side type `copy_range_as_markdown`/`delete_range`/`replace_range`
    /// actually resolve against) by pure field mapping — no reinterpretation.
    #[test]
    fn block_range_converts_to_rendered_range_by_pure_field_mapping() {
        let range = BlockRange {
            start_path: vec![0],
            start_offset: 3,
            end_path: vec![1, 2],
            end_offset: 9,
        };

        let converted: crate::markdown::RenderedRange = range.into();

        assert_eq!(converted.start_path, vec![0]);
        assert_eq!(converted.start_offset, 3);
        assert_eq!(converted.end_path, vec![1, 2]);
        assert_eq!(converted.end_offset, 9);
    }

    // -- WSPC-D008 review finding #1: wrapper-layer coverage -----------------
    //
    // Every test above this point drives `NoteSession` directly through
    // `Workspace::for_test`, which proves the *delegation targets* behave
    // correctly but not that each `#[frb]` function in this file actually
    // calls the one it claims to: `commit_block`, `delete_block`,
    // `insert_block`, `merge_block_with_previous` and `split_block` all
    // share the shape `(note_id: String, block_path: Vec<usize>) ->
    // Result<NoteState, AppError>`, and `reload_note` shares its return type
    // with `NoteSession::note_state` (though not `NoteSession::reload`'s own
    // signature — both take `&self` and return `Result<NoteState, AppError>`).
    // A one-line body swapped for a sibling's compiles, and every test above
    // this line still passes, because none of them go through this file's
    // own `open_session`-based wiring at all. The tests below do: each drives
    // the real `#[frb]` function through a real bootstrap, a real
    // `open_note`, and asserts the one effect that a swap with a
    // same-shaped sibling would break.
    //
    // This is also the one place in this file that touches the process-wide
    // `db::connection::ACTIVE_WORKSPACE`/`DB` singletons rather than an
    // injected `Workspace` — `Workspace::active()`, which `open_note` and
    // `pending_drafts` both call, is hardcoded to `DbHandle::Process` and has
    // no test seam, so proving *those two* wrappers work at all requires the
    // real singleton. That first touch also reaches the real OS Keychain via
    // `open_encrypted_db` (`open_encrypted_db_with_key`'s test-key injection
    // has no equivalent on that path) — `security::keyring`'s own tests and
    // `api::auth`'s already establish that this works reliably inside this
    // project's `devenv` shell, warmed up once per test binary by the `ctor`
    // in `api::auth`'s test module. `db::connection::WORKSPACE_TEST_LOCK`
    // (paired with `ENV_LOCK` while `BURLMD_DB_PATH` is set) is what keeps
    // these tests, `db::connection`'s own
    // `active_workspace_id_reports_the_id_a_bootstrap_call_established`, and
    // any later addition from racing the one process-wide `ACTIVE_WORKSPACE`
    // cell.

    /// Runs a `#[frb] async fn` from this crate to completion, synchronously.
    ///
    /// Not a general-purpose executor — a proof of the claim every `async`
    /// wrapper in this file already documents (see `search_notes`'s own
    /// comment): the body never actually yields, so `async` only affects how
    /// FRB dispatches the call across the boundary. This polls once with a
    /// no-op waker and panics if the future is not immediately ready, rather
    /// than silently blocking on an executor these tests have no need for.
    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        let mut future = std::pin::pin!(future);
        let waker = std::task::Waker::noop();
        let mut cx = std::task::Context::from_waker(waker);
        match future.as_mut().poll(&mut cx) {
            std::task::Poll::Ready(value) => value,
            std::task::Poll::Pending => panic!(
                "a WSPC-D008 wrapper-layer test's future did not resolve on \
                 its first poll; every #[frb] async fn in this crate is \
                 documented to run to completion synchronously"
            ),
        }
    }

    struct WrapperWorkspace {
        // Held for its `Drop` impl; never read directly.
        #[allow(dead_code)]
        dir: TempDir,
        root: std::path::PathBuf,
    }

    /// Bootstraps a real local Workspace through the actual `#[frb]` entry
    /// point — not `workspace::bootstrap`'s `_impl` function against an
    /// injected connection — so it establishes the active Workspace exactly
    /// as production does, through `db::connection::set_active_workspace_id`
    /// against the real singleton. Callers must hold `ENV_LOCK` then
    /// `WORKSPACE_TEST_LOCK` for their whole test body before calling this.
    fn wrapper_bootstrap() -> WrapperWorkspace {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("bundle");
        block_on(open_or_create_local_workspace(Some(
            root.to_string_lossy().to_string(),
        )))
        .unwrap();
        WrapperWorkspace { dir, root }
    }

    fn wrapper_write_note(root: &std::path::Path, relative: &str, contents: &str) {
        let path = root.join(relative);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(path, contents).unwrap();
    }

    /// Holds every lock a wrapper-layer test needs and, on drop, resets the
    /// process-wide `ACTIVE_WORKSPACE` cell back to unset — `while still
    /// holding WORKSPACE_TEST_LOCK`, since a struct's own `Drop::drop` runs
    /// before its fields' do, and the lock guards are fields here. Without
    /// this, the first wrapper-layer test to run leaves `ACTIVE_WORKSPACE`
    /// set to its own Workspace id when it finishes (success *or* panic —
    /// this runs during unwinding too), and
    /// `db::connection::tests::active_workspace_id_reports_the_id_a_bootstrap_call_established`'s
    /// opening assertion — "no Workspace has been established yet" — fails
    /// against a value one of these tests left behind. The lock alone only
    /// prevents two tests observing `ACTIVE_WORKSPACE` *at the same instant*;
    /// it does not clear what a finished test leaves in it, which is the gap
    /// this closes.
    struct WrapperGuards {
        _db_path: crate::db::connection::EnvVarGuard,
        _db_dir: TempDir,
        _workspace_lock: std::sync::MutexGuard<'static, ()>,
        _env_lock: std::sync::MutexGuard<'static, ()>,
    }

    impl Drop for WrapperGuards {
        fn drop(&mut self) {
            crate::db::connection::clear_active_workspace_id_for_test();
        }
    }

    /// Acquires the locks every wrapper-layer test needs and points
    /// `BURLMD_DB_PATH` at a fresh temporary file — load-bearing only for
    /// whichever test in the binary is first to touch the process-wide `DB`
    /// singleton, since it is a `OnceLock` and every later touch reuses the
    /// connection (and Keychain entry) the first one opened.
    ///
    /// Recovers from a poisoned lock rather than panicking on one: a prior
    /// test failing while it held `ENV_LOCK`/`WORKSPACE_TEST_LOCK` is an
    /// unrelated bug this test should not also report as its own failure —
    /// `()` carries no invariant a poisoned lock could have left broken.
    fn wrapper_guards() -> WrapperGuards {
        let env_lock = crate::db::connection::ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let workspace_lock = crate::db::connection::WORKSPACE_TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let db_dir = tempfile::tempdir().unwrap();
        let db_path = crate::db::connection::EnvVarGuard::set(
            "BURLMD_DB_PATH",
            db_dir.path().join("index.sqlite3").as_os_str(),
        );
        WrapperGuards {
            _db_path: db_path,
            _db_dir: db_dir,
            _workspace_lock: workspace_lock,
            _env_lock: env_lock,
        }
    }

    /// Drives `open_note`, `get_block_source`, `update_block`,
    /// `commit_block` and `note_write_status` through the real `#[frb]`
    /// functions. The load-bearing assertion is on `commit_block`: it must
    /// leave the edited Block *present*, with `update_block`'s own text —
    /// which is exactly what a mis-wiring onto `delete_block` (identical
    /// signature) would break, since that would remove the Block instead.
    #[test]
    fn wrapper_layer_open_get_update_and_commit_go_through_the_real_session() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(&ws.root, "flow.md", &note_source("Flow", "Alpha.\n\nBeta."));

        let opened = block_on(open_note("flow".to_string())).unwrap();
        assert_eq!(opened.ast.len(), 2, "open_note must parse both paragraphs");
        assert_eq!(opened.metadata.title, "Flow");

        let source = get_block_source("flow".to_string(), vec![0]).unwrap();
        assert_eq!(
            source, "Alpha.\n",
            "get_block_source must return the raw Block source verbatim"
        );

        assert!(!note_write_status("flow".to_string()).has_unwritten_edits);
        update_block("flow".to_string(), vec![0], "Alpha, revised.\n".to_string()).unwrap();
        assert!(
            note_write_status("flow".to_string()).has_unwritten_edits,
            "update_block must write the draft row through the real session"
        );

        let committed = commit_block("flow".to_string(), vec![0]).unwrap();
        assert_eq!(
            committed.ast.len(),
            2,
            "commit_block must reparse in place — the edited Block must \
             still be present, not removed, which is what a mis-wiring onto \
             delete_block (an identical signature) would do instead"
        );
        assert_eq!(
            get_block_source("flow".to_string(), vec![0]).unwrap(),
            "Alpha, revised.\n",
            "commit_block must reflect update_block's own edit, not discard it"
        );
    }

    /// `insert_block`, `delete_block`, `split_block` and
    /// `merge_block_with_previous` all share the signature `(note_id,
    /// block_path) -> Result<NoteState, AppError>`, so only an observable
    /// effect distinguishes a correct wiring from a mis-wiring onto a
    /// sibling. Each assertion below is the one a swap within this group
    /// would break.
    #[test]
    fn wrapper_layer_insert_delete_split_and_merge_have_distinct_observable_effects() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(&ws.root, "flow.md", &note_source("Flow", "Alpha.\n\nBeta."));
        block_on(open_note("flow".to_string())).unwrap();

        // insert_block grows the Note by one Block, inserted before the
        // Block at the given path — here, before "Beta.", into the blank-line
        // gap the original "Alpha.\n\nBeta." already carries, so the result
        // is three well-separated paragraphs rather than one run-on Block.
        let inserted = insert_block("flow".to_string(), vec![1], "Gamma.".to_string()).unwrap();
        assert_eq!(inserted.ast.len(), 3, "insert_block must add a Block");

        // delete_block shrinks it back — the opposite of insert_block, and
        // the one direction commit_block must never take. "Gamma." is now
        // at [1], where insert_block just put it.
        let deleted = delete_block("flow".to_string(), vec![1]).unwrap();
        assert_eq!(
            deleted.ast.len(),
            2,
            "delete_block must remove the Block at the given path"
        );

        // split_block also grows the Note by one, but by dividing an
        // existing Block rather than appending a new one — the combined text
        // of the two halves must still hold everything the original held.
        let split = split_block("flow".to_string(), vec![1], 2).unwrap();
        assert_eq!(
            split.ast.len(),
            3,
            "split_block must produce one more Block"
        );
        let first_half = get_block_source("flow".to_string(), vec![1]).unwrap();
        let second_half = get_block_source("flow".to_string(), vec![2]).unwrap();
        assert_eq!(
            format!("{first_half}{second_half}").replace('\n', ""),
            "Beta.",
            "split_block must not lose or duplicate the Block's text"
        );

        // merge_block_with_previous on the *first* Block has no predecessor
        // regardless of what split_block just did to the Blocks after it, so
        // it must be a no-op — the one case in this group that does not
        // mutate at all.
        let before = block_on(open_note("flow".to_string())).unwrap();
        let merged = merge_block_with_previous("flow".to_string(), vec![0]).unwrap();
        assert_eq!(
            merged, before,
            "merging the first Block with its predecessor must be a no-op"
        );
    }

    /// Drives `copy_range_as_markdown`, `delete_range`, `replace_range` and
    /// `flush_note` through the real `#[frb]` functions.
    #[test]
    fn wrapper_layer_range_operations_and_flush_go_through_the_real_session() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(
            &ws.root,
            "ranges.md",
            &note_source("Ranges", "First block.\n\nSecond block.\n\nThird block."),
        );
        let state = block_on(open_note("ranges".to_string())).unwrap();
        assert_eq!(state.ast.len(), 3);

        let last_len = crate::markdown::rendered_text(&state.ast[2])
            .chars()
            .count();
        let whole = BlockRange {
            start_path: vec![0],
            start_offset: 0,
            end_path: vec![2],
            end_offset: last_len,
        };
        let copied = copy_range_as_markdown("ranges".to_string(), whole).unwrap();
        assert!(copied.contains("First block."));
        assert!(copied.contains("Second block."));
        assert!(copied.contains("Third block."));

        let second_and_third = BlockRange {
            start_path: vec![1],
            start_offset: 0,
            end_path: vec![2],
            end_offset: last_len,
        };
        let after_delete = delete_range("ranges".to_string(), second_and_third).unwrap();
        assert_eq!(
            after_delete.ast.len(),
            1,
            "delete_range must remove every Block the range spans"
        );

        let remaining_len = crate::markdown::rendered_text(&after_delete.ast[0])
            .chars()
            .count();
        let whole_remaining = BlockRange {
            start_path: vec![0],
            start_offset: 0,
            end_path: vec![0],
            end_offset: remaining_len,
        };
        let after_replace = replace_range(
            "ranges".to_string(),
            whole_remaining,
            "Replaced content.".to_string(),
        )
        .unwrap();
        assert_eq!(after_replace.ast.len(), 1);
        assert_eq!(
            get_block_source("ranges".to_string(), vec![0]).unwrap(),
            "Replaced content.\n",
            "replace_range must substitute the replacement text"
        );

        let revision = block_on(flush_note("ranges".to_string())).unwrap();
        assert!(!revision.is_empty());
        let written = std::fs::read_to_string(ws.root.join("ranges.md")).unwrap();
        assert!(
            written.contains("Replaced content."),
            "flush_note must write the working source to disk"
        );
        assert!(
            !note_write_status("ranges".to_string()).has_unwritten_edits,
            "flush_note must clear the unwritten-edits flag"
        );
    }

    /// The RevisionMismatch escape hatch: `reload_note` must re-read the
    /// file from disk, not merely return the session's current cached state.
    /// `NoteSession::note_state` shares `reload`'s exact signature — `(&self)
    /// -> Result<NoteState, AppError>` — and would pass every other test in
    /// this file if `reload_note` were mis-wired onto it, since neither the
    /// returned type nor the `Ok`/`Err` shape would differ from the correct
    /// wiring on the *first* call. Only re-reading disk, and only re-reading
    /// it after something else changed the file, tells the two apart.
    #[test]
    fn wrapper_layer_reload_note_recovers_from_a_revision_mismatch() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(
            &ws.root,
            "reload.md",
            &note_source("Reload", "Original content."),
        );
        block_on(open_note("reload".to_string())).unwrap();
        block_on(flush_note("reload".to_string())).unwrap();

        // Something other than this session changes the file on disk —
        // exactly the case risk 6's OCC check exists to catch.
        wrapper_write_note(
            &ws.root,
            "reload.md",
            &note_source("Reload", "Externally changed content."),
        );

        let mismatch = block_on(flush_note("reload".to_string()));
        assert!(
            matches!(mismatch, Err(AppError::RevisionMismatch(_))),
            "a write against a stale baseline must be refused, got {mismatch:?}"
        );

        let reloaded = block_on(reload_note("reload".to_string())).unwrap();
        assert!(
            !reloaded.restored_from_draft,
            "a reload is not a restored draft"
        );
        assert_eq!(
            get_block_source("reload".to_string(), vec![0]).unwrap(),
            "Externally changed content.\n",
            "reload_note must reflect what is actually on disk now, not the \
             session's stale cached state — this is what a mis-wiring onto \
             NoteSession::note_state would fail to do"
        );

        // The baseline must have moved with the reload, or every future
        // write on this session repeats the same mismatch forever.
        let flushed_again = block_on(flush_note("reload".to_string()));
        assert!(
            flushed_again.is_ok(),
            "the write tier must succeed once the baseline matches disk \
             again, got {flushed_again:?}"
        );
    }

    /// `close_note` ends the session (a later status poll reports the
    /// not-open default) and `pending_drafts` reports — then, once closed,
    /// stops reporting — a Note carrying an unflushed draft.
    #[test]
    fn wrapper_layer_close_note_ends_the_session_and_pending_drafts_reports_unflushed_work() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(&ws.root, "closer.md", &note_source("Closer", "Unedited."));
        wrapper_write_note(&ws.root, "pending.md", &note_source("Pending", "Original."));
        // `pending_drafts` joins `drafts` against `notes`, so each Note needs
        // an indexed row before a draft on it is reachable through that join
        // — bootstrap already indexed the (empty) bundle before these files
        // existed.
        block_on(reindex_workspace()).unwrap();
        block_on(open_note("closer".to_string())).unwrap();
        block_on(open_note("pending".to_string())).unwrap();
        update_block(
            "pending".to_string(),
            vec![0],
            "Edited, unflushed.\n".to_string(),
        )
        .unwrap();

        let pending = block_on(pending_drafts()).unwrap();
        assert!(
            pending.iter().any(|note| note.id == "pending"),
            "pending_drafts must report the Note carrying an unflushed draft"
        );
        assert!(
            !pending.iter().any(|note| note.id == "closer"),
            "pending_drafts must not report a Note with no unflushed edits"
        );

        block_on(close_note("closer".to_string())).unwrap();
        let status_after_close = note_write_status("closer".to_string());
        assert!(
            !status_after_close.has_unwritten_edits && status_after_close.last_written_at.is_none(),
            "note_write_status for a closed Note must report the not-open \
             default, proving the session actually ended"
        );

        block_on(close_note("pending".to_string())).unwrap();
        let pending_after_close = block_on(pending_drafts()).unwrap();
        assert!(
            !pending_after_close.iter().any(|note| note.id == "pending"),
            "closing a Note must flush and clear its draft row"
        );
    }

    /// A full rebuild cannot run inside a lifecycle operation, which is what
    /// stops it reinstating the rows a concurrent rename has just retired.
    ///
    /// The race this closes: `reindex_workspace` walks and parses the whole
    /// bundle with nothing held, then writes the derived rows. A `rename_note`
    /// that completes inside that O(bundle) window has already moved the file
    /// and rewritten its index rows — but the snapshot in flight was taken
    /// before the move, so the write phase puts the *old* concept id back and
    /// drops the new one. The index then names a file that no longer exists and
    /// omits the one that does, until something reindexes again.
    ///
    /// Driven through the lock itself for the reason
    /// `workspace::persist`'s `an_open_cannot_run_inside_a_lifecycle_operation`
    /// gives: holding it is exactly the condition a lifecycle operation
    /// establishes, and "makes no progress until it is released" is what
    /// serialization means here. The sleep can only weaken the observation,
    /// never fail it spuriously.
    #[test]
    fn wrapper_layer_reindex_cannot_run_inside_a_lifecycle_operation() {
        use std::sync::atomic::AtomicBool;
        use std::sync::Arc;

        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(&ws.root, "indexed.md", &note_source("Indexed", "Alpha."));

        let workspace = crate::workspace::persist::Workspace::active().unwrap();
        let reindexed = Arc::new(AtomicBool::new(false));
        let entered = Arc::new(AtomicBool::new(false));

        let waiter = crate::workspace::persist::with_lifecycle_lock(&workspace, || {
            let reindexed_by_waiter = Arc::clone(&reindexed);
            let entered_by_waiter = Arc::clone(&entered);
            let waiter = std::thread::spawn(move || {
                entered_by_waiter.store(true, AtomicOrdering::SeqCst);
                block_on(reindex_workspace()).expect("the bundle is on disk");
                reindexed_by_waiter.store(true, AtomicOrdering::SeqCst);
            });

            while !entered.load(AtomicOrdering::SeqCst) {
                std::thread::yield_now();
            }
            std::thread::sleep(Duration::from_millis(100));
            assert!(
                !reindexed.load(AtomicOrdering::SeqCst),
                "reindex_workspace completed while a lifecycle operation held \
                 the lock, so a rename finishing inside its scan window can \
                 still have its rows overwritten from the stale snapshot"
            );
            Ok(waiter)
        })
        .unwrap();

        waiter.join().unwrap();
        assert!(
            reindexed.load(AtomicOrdering::SeqCst),
            "the rebuild never completed once the lock was released"
        );
        assert!(
            !block_on(workspace_tree()).unwrap().is_empty(),
            "the rebuild must have written the rows it walked"
        );
    }

    /// A session whose state lock is poisoned is reported as broken, not as
    /// clean.
    ///
    /// The defect this pins: the whole poll collapsed onto `unwrap_or_default()`,
    /// so a session that could not be read at all returned the same value as a
    /// Note nobody had opened — no error, no unwritten edits, `last_written_at`
    /// unset. The UI polls this to learn that tier 2 is in trouble, and for the
    /// one state where the Core cannot say anything about the user's work it was
    /// told everything was fine.
    #[test]
    fn wrapper_layer_note_write_status_reports_a_broken_session_rather_than_a_clean_one() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();
        wrapper_write_note(&ws.root, "broken.md", &note_source("Broken", "Alpha."));
        block_on(open_note("broken".to_string())).unwrap();

        let workspace = crate::workspace::persist::Workspace::active().unwrap();
        let session = crate::workspace::persist::lookup(workspace.id(), "broken")
            .unwrap()
            .expect("the Note is open");
        session.poison_state_for_test();

        let status = note_write_status("broken".to_string());

        assert!(
            status.last_error.is_some(),
            "a session that cannot be read must report why, not report clean"
        );
        assert!(
            status.has_unwritten_edits,
            "nothing can establish that a broken session's buffer reached disk"
        );
        assert_ne!(
            status,
            NoteWriteStatus::default(),
            "a broken session must be distinguishable from a Note that is not open"
        );
    }

    /// Drives all seven `WSPC-D006` lifecycle wrappers through the real
    /// `#[frb]` functions, the real active-Workspace singleton and a real
    /// bundle.
    ///
    /// The same mis-wiring hazard the editing wrappers above have:
    /// `rename_note` and `move_note` share the signature `(String, String) ->
    /// Result<(NoteState, LifecycleEffects), AppError>`, and `create_directory`
    /// shares `(String) -> Result<(), AppError>` with `delete_note`. Each
    /// assertion below is the one a swap within its group would break — a
    /// rename that changed the directory instead of the filename, or a delete
    /// that created.
    #[test]
    fn wrapper_layer_lifecycle_creates_renames_moves_and_deletes() {
        let _guards = wrapper_guards();
        let ws = wrapper_bootstrap();

        block_on(create_directory("projects".to_string())).unwrap();
        let created = block_on(create_note(
            "projects".to_string(),
            "Meeting Notes".to_string(),
        ))
        .unwrap();
        assert_eq!(created.metadata.id, "projects/Meeting Notes");
        assert!(ws.root.join("projects/Meeting Notes.md").is_file());

        // A source Note holding an inbound Link, so the rename has an edge to
        // sweep rather than passing vacuously. The title contains a space, per
        // this ticket's second acceptance criterion.
        wrapper_write_note(
            &ws.root,
            "src.md",
            &note_source("src", "see [Meeting Notes](</projects/Meeting Notes.md>)"),
        );
        block_on(reindex_workspace()).unwrap();

        let (renamed, effects) = block_on(rename_note(
            "projects/Meeting Notes".to_string(),
            "Standup Notes".to_string(),
        ))
        .unwrap();
        assert_eq!(
            renamed.metadata.id, "projects/Standup Notes",
            "rename_note must change the filename and leave the Directory alone"
        );
        assert_eq!(
            effects.rewritten,
            vec!["src".to_string()],
            "the source Note whose bytes moved must be reported so the shell reloads it"
        );
        assert!(std::fs::read_to_string(ws.root.join("src.md"))
            .unwrap()
            .contains("</projects/Standup Notes.md>"));

        let (moved, _) = block_on(move_note(
            "projects/Standup Notes".to_string(),
            String::new(),
        ))
        .unwrap();
        assert_eq!(
            moved.metadata.id, "Standup Notes",
            "move_note must change the Directory and leave the filename alone"
        );

        block_on(create_note("projects".to_string(), "Kept".to_string())).unwrap();
        let dir_effects = block_on(rename_directory(
            "projects".to_string(),
            "archive".to_string(),
        ))
        .unwrap();
        assert_eq!(
            dir_effects.remapped,
            vec![IdRemap {
                old_id: "projects/Kept".to_string(),
                new_id: "archive/Kept".to_string(),
            }],
            "rename_directory must report the ids it remapped underneath the caller"
        );

        let removed = block_on(delete_directory("archive".to_string())).unwrap();
        assert_eq!(removed, vec!["archive/Kept".to_string()]);
        assert!(!ws.root.join("archive").exists());

        block_on(delete_note("Standup Notes".to_string())).unwrap();
        assert!(
            !ws.root.join("Standup Notes.md").exists(),
            "delete_note must remove the file, where create_directory — the \
             same signature — would have created one"
        );
    }

    /// Slices `source` to everything before its own `#[cfg(test)] mod
    /// tests { ... }` block. `include_str!` reads a whole file, this test
    /// module included, so an unscoped scan is self-referential: a needle
    /// that spells out the pattern it looks for would match its own line
    /// and inflate a count, and a backward signature-hunting walk could
    /// wander into test helper functions that happen to share a return
    /// type with production code. Every scan below runs over this
    /// production-only slice instead, for every file it looks at.
    fn production_source(source: &str) -> &str {
        source
            .split_once("\nmod tests {")
            .map_or(source, |(before, _)| before)
    }

    /// Names every function in `source` whose signature both returns
    /// `Result<NoteState, AppError>` and takes neither a `Vec<usize>`
    /// (a `block_path`) nor a `BlockRange` (a `range`) parameter — the
    /// shape shared by a whole-Note entry point (`open_note`,
    /// `reload_note`) as opposed to one of the per-Block or per-range
    /// mutators (`commit_block`, `insert_block`, `delete_block`,
    /// `split_block`, `merge_block_with_previous`, `delete_range`,
    /// `replace_range`), which all share the same return type but always
    /// name one of those two parameter shapes.
    fn note_state_opening_signature_names(source: &str) -> Vec<String> {
        let lines: Vec<&str> = source.lines().collect();
        let mut names = Vec::new();
        for (i, line) in lines.iter().enumerate() {
            if !line.contains("-> Result<NoteState, AppError>") {
                continue;
            }
            let mut start = i;
            while start > 0
                && !lines[start].trim_start().starts_with("pub fn ")
                && !lines[start].trim_start().starts_with("pub async fn ")
            {
                start -= 1;
            }
            let signature = lines[start..=i].join(" ");
            if signature.contains("Vec<usize>") || signature.contains("BlockRange") {
                continue;
            }
            let after_fn = signature
                .split_once("pub async fn ")
                .or_else(|| signature.split_once("pub fn "))
                .map(|(_, rest)| rest)
                .unwrap_or(&signature);
            let name = after_fn.split('(').next().unwrap_or(after_fn).trim();
            names.push(name.to_string());
        }
        names
    }

    /// TDD order 6 (surface conformance): `open_note` accepts a concept id,
    /// it is the *only* open-a-Note entry point (whether a sibling reuses
    /// the `open_note` name, like a reintroduced `open_note_by_id`, or
    /// invents a new one), and no function anywhere FRB scans
    /// (`rust_input: crate::api`, i.e. this file plus `api::auth` and
    /// `api::simple`) takes an owned `workspace_id` parameter — the active
    /// Workspace is always resolved Core-side.
    ///
    /// Verified by scanning each file's own production source rather than
    /// by runtime reflection: Rust has no introspection over a module's
    /// public function signatures, and `#[frb]` erases to an ordinary
    /// `pub fn`/`pub async fn` the compiler does not tag distinctly. An
    /// explicit assertion over the `#[frb]` surface's own source text is
    /// the form `WSPC-D008`'s STOP condition on this point names as the
    /// fallback when a compile-time check is not practical.
    #[test]
    fn the_ffi_surface_has_one_concept_id_open_entry_point_and_no_function_takes_a_workspace_id() {
        let ffi_api_source = production_source(include_str!("ffi_api.rs"));
        let auth_source = production_source(include_str!("auth.rs"));
        let simple_source = production_source(include_str!("simple.rs"));

        assert_eq!(
            ffi_api_source.matches("fn open_note").count(),
            1,
            "there must be exactly one open-a-Note entry point, and no \
             sibling named e.g. open_note_by_id or open_note_at_path"
        );
        assert!(
            ffi_api_source.contains("pub async fn open_note(note_id: String)"),
            "open_note must take a concept id named note_id, not a path or a \
             workspace_id"
        );

        // A second, differently-named entry point — one that doesn't even
        // contain "open_note" as a substring, so the name-based check
        // above would miss it entirely — would still share this shape:
        // returning Result<NoteState, AppError> while taking neither a
        // block_path nor a range.
        //
        // Three functions on this boundary legitimately have it, and no
        // fourth may be added without amending the contract. `open_note`
        // and `reload_note` are the two the previous revision named.
        // `create_note` is the third and is not an exception to the rule
        // above but an instance of it: `contracts/ffi_api.rs` specifies that
        // it creates the file *and opens it*, precisely so that the first
        // `update_block` after a creation substitutes into a buffer that was
        // established rather than into nothing. It is still not a second way
        // to open an **existing** Note — it fails with `PathUnavailable` when
        // the path is taken — which is what the rule protects. Every other
        // same-shaped function is one of the per-Block or per-range mutators,
        // which always name a block_path or range parameter.
        let mut opener_shaped_names = note_state_opening_signature_names(ffi_api_source);
        opener_shaped_names.sort();
        assert_eq!(
            opener_shaped_names,
            vec![
                "create_note".to_string(),
                "open_note".to_string(),
                "reload_note".to_string()
            ],
            "the only functions that may return Result<NoteState, AppError> \
             while taking neither a block_path (Vec<usize>) nor a range \
             (BlockRange) are open_note, reload_note and create_note — any \
             other name here is an undocumented additional entry point"
        );

        for (file, source) in [
            ("ffi_api.rs", ffi_api_source),
            ("auth.rs", auth_source),
            ("simple.rs", simple_source),
        ] {
            for line in source.lines() {
                let Some(at) = line.find("workspace_id:") else {
                    continue;
                };
                let after = line[at + "workspace_id:".len()..].trim_start();
                assert!(
                    after.starts_with("&str"),
                    "{file}: no exposed function may take a workspace_id \
                     parameter in an owned/typed form (String, \
                     Option<String>, ...) — the active Workspace is always \
                     resolved Core-side. Only a private *_impl helper's \
                     borrowed `&str` parameter is allowed. Offending line: \
                     {line:?}"
                );
            }
        }
    }
}
