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
    /// The `state` returned on the OAuth redirect did not match the value
    /// minted for the `flow_id`, or the `flow_id` is unknown or already
    /// consumed. Distinct from `OAuthError` because it is a CSRF signal, not
    /// a provider failure, and no token request is made when it is raised.
    OAuthStateMismatch,
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

/// Opens an existing Workspace directory that this application did not create,
/// including one populated by another tool (CAP-WS-05). Files with absent or
/// unparseable frontmatter are indexed with `okf_conformant = 0` rather than
/// rejected, and no Note in the directory is modified or repaired.
///
/// Converges on the same post-conditions as `open_or_create_local_workspace` —
/// index initialized, root key present, `workspaces` row written, bundle
/// indexed, **repository present** — because `flow-workspace-bootstrap.md`
/// requires every bootstrap path to, so that no later code has to ask which
/// one produced the Workspace it is holding.
///
/// That last post-condition means it **initializes a repository when the
/// directory has none**, and adopts existing history when it has one
/// (ADR-005 decision 8). Tier 3 commits on every Note close, so adopting
/// without one would leave CAP-WS-02 unsatisfiable and `close_note` failing on
/// the routine path.
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
    /// False when the file has no frontmatter, when it does not parse, or
    /// when it parses without a non-empty `type` — the first two of OKF §11's
    /// three conformance conditions, the second of which an implementation
    /// that only tries to parse will miss. (§11's third condition constrains
    /// the structure of `index.md` and `log.md` when present; burlmd writes
    /// neither, per ADR-004 decision 6.) Such a file is still fully usable; the flag exists so
    /// the UI can offer to bring it into conformance (CAP-PORT-03).
    pub okf_conformant: bool,
}

/// Creates a Note in `directory_path` (empty string for the bundle root) with
/// an OKF-conformant frontmatter block (`type: Note`, `title`), and **opens
/// it**: the returned `NoteState` is a state of an open Note, so the working
/// source buffer, the span map and the recorded revision are all established
/// before this returns, and `note_write_status` reports on it immediately.
/// Stated because the alternative reading — create the file, return a state,
/// register nothing — leaves the first `update_block` substituting into a
/// buffer that was never established. `SHEL-E005` has a new Note "open for
/// editing" the moment it is created.
///
/// The filename is derived from `title` by the rule in
/// `data-models/okf-bundle.md` — verbatim, plus `.md`, with no slugification,
/// because CAP-GRAPH-04's create-on-follow has to invert it; a collision, or a title deriving to a reserved
/// filename, returns `PathUnavailable` rather than silently disambiguating.
#[frb]
pub async fn create_note(directory_path: String, title: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Deletes a Note and commits the deletion, so it stays recoverable from
/// local version history (CAP-LIFE-04).
/// Two cleanups the `notes` row's own cascade does not perform, both in the
/// same transaction:
///
/// - The `drafts` row, which carries no foreign key at all and would otherwise
///   outlive the Note it belongs to.
/// - The `notes_fts` row, which must be deleted **before** the `notes` row.
///   Deleting `notes` cascades `fts_mapping` away, and that mapping is the
///   only pointer to the FTS rowid, so afterwards the row is unreachable and
///   undeletable — leaving the deleted Note's full text searchable in the
///   encrypted index indefinitely. See `data-models/schema.sql`.
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
/// Returns `PathUnavailable` on the same terms as `create_note`: when the
/// filename derived from `new_title` is already taken, or derives to a
/// reserved OKF filename. Renaming is not a weaker check than creating.
///
/// **This writes Note bytes, which makes it an exception to the single-writer
/// rule** in ADR-007 decision 1 — and it writes *more than one Note*. It
/// rewrites the renamed Note's frontmatter `title` and filename, and it
/// rewrites the inbound Link in **every source Note that points at it**
/// (CAP-LIFE-02, risk 8). Each of those files has its own possible open state
/// and its own possible draft row, and all of them must be carried forward in
/// the same transaction. Three obligations, applied to every affected Note and
/// not only the renamed one:
///
/// - The **working source** of any open affected Note gets the same
///   substitution the file got — the frontmatter `title` for the renamed Note,
///   the rewritten Link target for each source Note. Skip it and the next
///   tier 2 write, which copies the buffer verbatim, silently reverts the
///   change. For a source Note that means reverting to a Link pointing at a
///   dead concept id: exactly the silent partial-rewrite graph corruption
///   risk 8 exists to prevent, arriving *after* the atomic rename that was
///   supposed to make it impossible.
/// - The **span map** of each is adjusted for the delta, or discarded and
///   rebuilt.
/// - The **recorded revision** of each is re-recorded from its post-rewrite
///   file. Skip it and that Note's next tier 2 write raises
///   `RevisionMismatch` against this application's own rewrite — reported to
///   the user through `note_write_status` as "the file changed underneath the
///   draft", on a routine rename. `flush_note` states the rule this breaks:
///   only a change the Core did not make should raise it.
///
/// **Draft rows of affected Notes are rewritten too**, not merely re-keyed.
/// A source Note with an unflushed draft holds the old Link text, and
/// `open_note` parses the draft in preference to disk — so leaving it produces
/// the same reversion one session later. `WSPC-D006` owns this.
///
/// A Note that links to *itself* is both cases at once and gets both
/// substitutions.
///
/// Refusing while any affected Note is open would also be a defensible answer.
/// It is not the one taken, because `SHEL-E005` makes renaming an open Note a
/// criterion-backed workflow, `prd/capabilities.md` treats renaming as routine
/// during writing, and the set of *source* Notes is not something the user can
/// see in order to close them first.
///
/// Also rewrites `notes.title` and the Note's `notes_fts` title row, which is
/// what full-text search matches titles against.
#[frb]
pub async fn rename_note(
    note_id: String,
    new_title: String,
) -> Result<(NoteState, LifecycleEffects), AppError> {
    unimplemented!()
}

/// Moves a Note to another Directory, rewriting every inbound Link
/// (CAP-LIFE-03). Changes the Note's id, as `rename_note` does.
/// Returns `PathUnavailable` when the destination already holds a Note of
/// that filename, or when the destination path does not exist.
///
/// Carries the same obligations as `rename_note` for every affected Note,
/// minus the frontmatter substitution on the moved Note itself: a move changes
/// its concept id and location but not its bytes, so its working source is
/// untouched while its recorded revision and open-note cache key move with it.
/// The **source Notes are affected identically to a rename** — their inbound
/// Links are rewritten, so their buffers, spans, revisions and draft rows all
/// need carrying forward.
///
/// `rename_directory` inherits all of it for every Note beneath the directory,
/// and note that the source Notes needing rewrites are *not* confined to that
/// subtree — anything anywhere in the bundle may link into it.
#[frb]
pub async fn move_note(
    note_id: String,
    new_directory_path: String,
) -> Result<(NoteState, LifecycleEffects), AppError> {
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

/// What a lifecycle operation changed, beyond the Note it was invoked on.
///
/// Every rename and move rewrites two disjoint sets of Notes, and the caller
/// has to act differently on each:
///
/// - `remapped` — Notes whose **concept id** changed. An open one is holding a
///   dead identifier and must re-anchor to the new id.
/// - `rewritten` — Notes whose **bytes** changed because an inbound Link in
///   them was rewritten. Their ids are unchanged, so nothing looks wrong, and
///   that is the problem: an open one still holds an `InlineElement::Link`
///   carrying the *old* `target_id`. Following it reaches nothing, and under
///   CAP-GRAPH-04 the create-on-follow path would then **recreate the concept
///   the rename just removed** — risk 8's silent graph degradation, arriving
///   through the surface built to traverse the graph. Worse, if the Block
///   holding that Link is focused, the UI's editable field still contains the
///   pre-rewrite source, so the next `update_block` substitutes it back into
///   the working source and reverts the rewrite from a buffer the Core does not
///   own.
///
/// The caller must reload any open Note appearing in either list. The Core
/// carries its own state forward (see `rename_note`); this is the half the
/// Core cannot reach.
#[frb]
pub struct LifecycleEffects {
    pub remapped: Vec<IdRemap>,
    pub rewritten: Vec<String>,
}

/// Renames a Directory, moving its contents and rewriting inbound Links to
/// every Note beneath it (CAP-LIFE-06). Returns `LifecycleEffects` for the
/// same reason `rename_note` does: positional identity means the caller's
/// existing ids are now stale, and separately the Notes holding rewritten
/// Links are not confined to the renamed subtree — anything anywhere in the
/// bundle may link into it.
#[frb]
pub async fn rename_directory(
    path: String,
    new_name: String,
) -> Result<LifecycleEffects, AppError> {
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
    /// Markdown link with an angle-bracket-wrapped destination,
    /// `[text](</dir/note.md>)` (ADR-004 decision 5, OKF section 6.1) -- the
    /// `[[` sequence is a UI trigger only and is never stored.
    ///
    /// The brackets are not optional and not cosmetic. Filenames derive from
    /// titles verbatim (`data-models/okf-bundle.md`), so a multi-word title
    /// yields a path containing spaces, and CommonMark forbids a *bare* link
    /// destination from containing one -- `[a](/Meeting Notes.md)` parses as
    /// paragraph text, not as a link, so no `Link` event reaches this enum at
    /// all. Verified against `pulldown-cmark` 0.12.2.
    Link {
        /// The target's OKF concept id: unescape `\\`, `\<` and `\>`, then
        /// strip the leading `/` and trailing `.md`. The parser has already
        /// removed the angle brackets, so `dest_url` never contains them.
        /// Always present, even when nothing matches it.
        target_id: String,
        /// False for a ghost Link -- a Link to a Note not yet created, which
        /// OKF section 6.1 requires consumers to tolerate and which
        /// CAP-GRAPH-04 makes a feature. The UI renders these distinctly and
        /// creates the Note on follow.
        ///
        /// Resolving this requires the index, not the parser: it is whether
        /// `target_id` matches a `notes` row. `WSPC-D003` declares the field
        /// and cannot fill it — it is upstream of the indexer — so
        /// `WSPC-D005` populates it and carries the criterion.
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
    /// Content hash of the on-disk file (ADR-007 decision 7), replacing the
    /// `notes.last_modified` comparison that could never match the
    /// placeholder `open_note` returned and so made every save fail.
    ///
    /// **Not an input.** The Core holds this value and compares it itself
    /// before every tier 2 write; see `flush_note`. It is exposed for display
    /// and diagnostics only, and no function on this boundary accepts it
    /// back.
    pub base_revision: String,
    /// True when a draft was restored from the `drafts` table rather than
    /// read from disk -- i.e. the previous session ended without tier 2
    /// flushing (ADR-008, CAP-WS-03).
    pub restored_from_draft: bool,
}

// ---------------------------------------------------------------------------
// Editing (ADR-006, ADR-007)
//
// Two kinds of call, and the distinction is load-bearing for the frame
// budget.
//
// **Every mutating call below writes the Note's working source and its draft
// row.** That is the tier 1 obligation in ADR-008 decision 1, and it belongs to
// all of them, not only to `update_block`: a split, a merge, a Block insertion
// and a range replace are each triggered by a discrete user action with no
// preceding `update_block`, so if they skipped the draft write the edit would
// live only in memory until the ~1s tier 2 timer fired. A kill in that window
// loses it, which CAP-WS-03 and `architecture/resilience.md`'s SQLite Draft
// Persistence guarantee both forbid — and it would make "no draft row" mean
// "nothing unwritten" falsely, which is the under-reporting direction of the
// invariant tier 2's draft-clearing establishes.
//
// What distinguishes the calls is **parsing**, not writing:
//
//   - `update_block` is the per-keystroke call and is the only one that does
//     NOT parse. It substitutes text, adjusts spans arithmetically, writes the
//     draft row, and returns nothing.
//   - Every other mutating call reparses the working source, rebuilds the span
//     map, and returns the whole new state. Each is triggered by a discrete
//     user action (Enter, Backspace, a range edit), not by typing, which is
//     what keeps the reparse off the per-keystroke path.
//   - `commit_block` is the one exception in both directions: it reparses but
//     writes nothing, because the text it reparses is already in the working
//     source and already in the draft row, put there by `update_block`.
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
/// Substitutes the text into the Note's working source — one buffer per open
/// Note holding its full current text, the same thing `drafts.raw_markdown`
/// persists — then moves the edited Block's span **end** by the byte delta and
/// shifts every later span by that same delta. Both halves matter: the edited
/// span is resized rather than shifted, and a rule covering only later spans
/// would leave the next splice replacing too little and duplicating the typed
/// bytes. See ADR-008 decision 2, which works the case through. No parse
/// happens here; `commit_block` reparses on blur and rebuilds the map.
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

/// Commits the focused Block: reparses the Note's working source, rebuilds the
/// span map from that parse, and returns the new state (ADR-007 decision 1).
///
/// It performs no splice. `update_block` already substituted the text and
/// adjusted the spans, so splicing "the buffered source over that Block's
/// span" here would re-apply an edit the working source already contains — the
/// duplication ADR-008 decision 2 works through. For *this* text there is
/// exactly one writer, and it is `update_block`, not this call.
///
/// That is narrower than it once read here. An earlier revision generalised it
/// to "there is exactly one writer of the working source" full stop, which is
/// false for six of the eight mutators: `insert_block`, `delete_block`,
/// `split_block`, `merge_block_with_previous`, `delete_range` and
/// `replace_range` are each triggered by a discrete user action with no
/// preceding `update_block`, so each necessarily writes. The rule that does
/// hold generally is in the section header: every mutating call writes the
/// working source and the draft row, and this one is the exception because its
/// input is already in both.
///
/// Called when the Block loses focus, not on every keystroke. This is where
/// the reparse cost lands: off the typing path, and *separate from* the tier 2
/// file write, which is on its own idle timer and may not have fired yet. A
/// commit updates the AST and the span map; it touches neither the file nor
/// the draft row.
///
/// It leaves the draft row alone deliberately. `update_block` already wrote
/// whatever this commit reparses, and tier 2 *clears* the row on a successful
/// write (ADR-008 decision 1) so that a row present means work not yet on
/// disk. Writing one here would re-create a row byte-identical to the file
/// whenever a Block is blurred with no intervening keystrokes — which a kill
/// before `close_note` then reports as recovered work that was never lost.
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
/// (CAP-EDIT-03). `offset` is an offset into the Block's **source** text, not
/// its rendered text: this is only ever called on the focused Block, which
/// under ADR-006 displays raw source, so the caret position the UI reports is
/// already a source offset. `merge_block_with_previous` needs no such note
/// because offset 0 is the same position in both spaces.
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

/// A selection spanning one or more Blocks (ADR-006 decision 3).
///
/// Offsets are character offsets into each Block's **rendered text**, defined
/// as the in-order concatenation of the `TextRun.content` values reachable
/// from that Block's `AstNode`, descending into `Link`/`ExternalLink`
/// `content`. That definition is what makes the number well-defined: it is a
/// pure function of the `AstNode` both sides already hold, not of whatever
/// the widget laid out, so the Core reproduces the same string the UI
/// selected in without the UI describing its geometry.
///
/// Resolving these to the source offsets a splice needs requires an
/// inline-granularity rendered→source map, which the Core builds during the
/// same parse — see ADR-007 decision 8. It is Core-side state under rule 3
/// like every other span, and this is the one place a Block-granularity map
/// is not sufficient.
///
/// Contrast `split_block`, whose `offset` is a **source** offset. The two
/// conventions differ because the Blocks differ: a range spans unfocused
/// Blocks, which the user sees rendered, while a split happens in the focused
/// Block, which the user sees as raw source.
///
/// **Open: the drag-outward anchor.** ADR-006 accepts that a selection may
/// begin inside the focused Block and extend past it, and for that one
/// endpoint the "unfocused, therefore rendered" justification does not hold —
/// a focused Block displays raw source, so the offset the widget reports is a
/// source offset. Whether the case is reachable at all depends on something
/// Flutter's documentation is silent about (whether an `EditableText`
/// participates in an enclosing `SelectableRegion`), so it is assigned to
/// `EDIT-F001`, which has both presentations in front of it, rather than
/// guessed at here.
///
/// That assignment also covers the harder variant: a range whose **interior**
/// contains the focused Block. It fails the rendered-offset rule for the same
/// reason, and additionally its inline span map is deliberately stale between
/// `update_block` and `commit_block` (ADR-008 decision 2) — while
/// `delete_range` and `replace_range` splice using exactly that map. The
/// likely resolution is that a range operation blurs first and dispatches
/// after, which dissolves both cases at once; that is cheap, and it is what
/// `EDIT-F001` should confirm rather than what `EDIT-F003` should discover.
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

/// Forces tier 2 immediately: writes the Note's working source to the file
/// atomically (temp file plus rename). Returns the new `base_revision`.
///
/// It writes that buffer verbatim and splices nothing — `update_block` already
/// substituted the text and adjusted the spans, and having two writers of the
/// working source is what produced the duplication ADR-008 decision 2
/// records.
///
/// **The debounce that normally triggers tier 2 lives in the Core, not the
/// UI.** This function is the explicit-flush escape hatch — used by
/// `close_note`, by application shutdown, and by tests — not the routine
/// path. The UI is not required to call it at all.
///
/// It deliberately takes no `expected_base_revision`. The Core holds a
/// current revision per open Note, initialised to the on-disk hash at
/// `open_note` and **replaced by the hash of what it just wrote** after every
/// successful write. Each write compares the file on disk against that value
/// and rejects with `RevisionMismatch` on a mismatch — the Optimistic
/// Concurrency Control in `architecture/risks.md` risk 6, now guarding file
/// content rather than a database column.
///
/// The re-recording is not an implementation detail. The tier 2 timer fires
/// repeatedly within one editing session, so a baseline pinned to open time
/// would make every write after the first fail against **this application's
/// own previous write** — turning `RevisionMismatch` from an external-change
/// signal into a guaranteed second-write failure. Only a change the Core did
/// not make should raise it.
///
/// Requiring the token from the caller would be wrong for the same underlying
/// reason, one layer up: a Core-owned idle timer advances the revision without
/// the UI observing it, so any token the UI still held from `open_note` would
/// be stale by construction. That is structurally the defect ADR-007
/// decision 7 exists to fix. `NoteState.base_revision` remains exposed for
/// display and diagnostics; it is not an input.
#[frb]
pub async fn flush_note(note_id: String) -> Result<String, AppError> {
    unimplemented!()
}

/// The state of the write tier for one open Note, polled by the UI.
///
/// This exists because tier 2's routine trigger is a **Core-owned idle
/// timer**, so when its write fails there is no caller to return the error
/// to. Without a poll, `RevisionMismatch` — which is the entirety of risk 6's
/// mitigation — is raised into nothing, and so are `DiskFull` and `IoError`
/// from the same path. The user would keep typing into a buffer nothing can
/// persist, in an application that deliberately shows no save control so that
/// they trust it. A specified control with nowhere to be acted on is the
/// shape this contract already removed once, in the OAuth `state`.
///
/// A poll rather than a stream, matching the `sync_status` precedent: the UI
/// is already rebuilding on its own cadence, and a failure that persists for
/// one frame is not materially different from one reported instantly.
#[frb]
pub struct NoteWriteStatus {
    /// Unix timestamp of the last successful tier 2 write, if any.
    pub last_written_at: Option<i64>,
    /// Set when the most recent write attempt failed. Cleared by the next
    /// success. `RevisionMismatch` here means the file changed underneath the
    /// draft and the user must be offered a reload rather than a retry.
    pub last_error: Option<AppError>,
    /// True when edits are buffered that no successful write has yet covered.
    pub has_unwritten_edits: bool,
}

/// Status of the write tier for one open Note (ADR-008). Never fails: a Note
/// that is not open reports no error and no unwritten edits.
#[frb(sync)]
pub fn note_write_status(note_id: String) -> NoteWriteStatus {
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
    /// Markdown form with the destination angle-bracket wrapped and `\\`, `\<`
    /// and `\>` escaped inside it, per `data-models/okf-bundle.md`.
    /// Constructed Core-side so the UI never assembles a link target and
    /// cannot produce a non-conformant one -- which is only true if the Core
    /// applies the wrapping, since the ordinary multi-word title produces a
    /// path with a space in it and the unwrapped form of that is not a link.
    /// `EDIT-F006`'s STOP forbids the UI from repairing it afterwards.
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
    /// Opaque handle for this in-flight authorization. The verifier and
    /// `state` are retained Core-side against it and never cross this
    /// boundary; the UI passes this back to `authenticate_workspace` along
    /// with what the redirect delivered.
    pub flow_id: String,
}

/// Generates the PKCE verifier, challenge and state Core-side and returns the
/// authorize URL for the UI to open in the system browser.
///
/// The split is deliberate: generating cryptographic material belongs on the
/// Core side, while only the UI can open a browser and run the loopback
/// listener. `redirect_uri` is the loopback URL the UI is already listening
/// on.
///
/// **The Core retains the verifier and `state` against `flow_id` and performs
/// the CSRF comparison itself** (RFC 6749 §10.12), in `authenticate_workspace`.
/// An earlier revision of this contract returned both values to the UI and
/// declared the comparison a UI obligation. That was withdrawn: the check had
/// no enforcement point, no ticket owned it, and a UI that simply skipped it
/// would lose the protection with nothing able to detect the omission — the
/// same "generated but never compared" shape the flow diagram itself had.
///
/// The trade-off originally cited against this — that it makes the Core
/// stateful across the browser leg — does not survive scrutiny. The flow was
/// already stateful across that leg; the state was merely parked in the
/// Presentation Container, which is the less trustworthy of the two places to
/// keep a secret and the only one that cannot enforce anything with it.
/// Holding it Core-side moves nothing except who can check it.
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
/// Returns `OAuthStateMismatch` — before any request to the token endpoint —
/// when `returned_state` does not equal the value minted for `flow_id`, or
/// when `flow_id` is unknown or already consumed. A `flow_id` is single-use.
#[frb]
pub async fn authenticate_workspace(
    flow_id: String,
    auth_code: String,
    returned_state: String,
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
///
/// This is a mutator, and the tier 1 obligation stated in the editing section
/// header applies to it in full: it writes the Note's working source, writes
/// the draft row, and reparses. Stated here because that header's "every
/// mutating call below" reads as scoping to the editing section it introduces,
/// not to every remaining line of this file -- so a mutator living in the
/// conflict surface is not obviously covered by it. Without this sentence,
/// `resolve_suggestion` is the one mutator for which "no draft row means
/// nothing unwritten" is unestablished, and that invariant is what the whole
/// tiering rests on. ADR-008 decision 1's enumeration names it for the same
/// reason.
#[frb(sync)]
pub fn resolve_suggestion(
    note_id: String,
    block_path: Vec<usize>,
    choice: SuggestionChoice,
) -> Result<NoteState, AppError> {
    unimplemented!()
}
