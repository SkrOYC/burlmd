// FORWARD STATUS (TechSpec v1.8.2-provisional): this is the delivered
// brownfield interface, with the Epic G session-restore exception specified.
// It is not otherwise an implementation-ready contract for PRD v1.3.7 and
// Architecture v1.4.15.
// In particular, AstNode is a rendering projection rather than the required
// canonical extended AST; the OAuth redirect flow is superseded by the
// GitHub App device-flow decision; title-verbatim path derivation is under
// OD-05; export predates atomic object-complete export; and asset, monitoring,
// reconciliation-decision, and release surfaces remain absent.
// Research-only Tasks must use contracts/provisional-spikes.toml and must not
// implement or extend this FFI. The named Epic G exceptions may implement
// their specified contracts. FLAKE-M002 and CI-M003 may bootstrap validation
// but may not change this interface. Each remaining production contract waits
// only for its own evidence, final Stage 3 reconciliation, and Stage 4
// adaptation.
//
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

#[frb]
pub enum ExportForm {
    /// A plain directory copy of the bundle, version history excluded.
    Copy,
    /// A single `.okf` archive of the same tree -- the packaged distribution
    /// form OKF §3 itself names. Nothing proprietary inside.
    BundleArchive,
}

/// Exports the Workspace to `destination` (CAP-PORT-02), as a plain bundle
/// copy or as one `.okf` Bundle Archive.
///
/// Cheap by construction: the Workspace is plaintext Markdown on disk at all
/// times, so this is a tree copy plus a conformance check, not a
/// decrypt-and-transform pipeline.
/// `.git/` is excluded.
///
/// Deliberately *not* justified by "the live Workspace is already conformant".
/// CAP-PORT-01 is scoped to Notes this application **creates**, and CAP-WS-05
/// and CAP-PORT-03 make a permanently non-conformant bundle a supported state
/// -- a foreign file with no frontmatter is exported as it is. What makes the
/// copy cheap is the plaintext, not the conformance. The conformance check
/// therefore reports rather than gates: it returns which Notes are
/// non-conformant and copies everything regardless, because refusing to export
/// a Workspace the user is entitled to take elsewhere would invert the
/// capability's purpose.
#[frb]
pub struct ExportReport {
    /// Concept ids of exported Notes found non-conformant. Reported, never gated:
    /// refusing to export a Workspace the user is entitled to take elsewhere would
    /// invert the capability's purpose.
    pub non_conformant: Vec<String>,
    /// Paths that could not be read during the walk. Partial output plus this list
    /// is honest; silent completeness is not.
    pub unreadable: Vec<String>,
}

#[frb]
pub async fn export_workspace(
    destination: String,
    form: ExportForm,
) -> Result<ExportReport, AppError> {
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
/// it**: `LifecycleResult.state` is a state of an open Note, so the working
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
pub async fn create_note(
    directory_path: String,
    title: String,
) -> Result<LifecycleResult, AppError> {
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
pub async fn delete_note(note_id: String) -> Result<LifecycleResult, AppError> {
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
) -> Result<LifecycleResult, AppError> {
    unimplemented!()
}

/// Moves a Note to another Directory, rewriting every inbound Link
/// (CAP-LIFE-03). Changes the Note's id, as `rename_note` does.
/// Returns `PathUnavailable` when the destination already holds a Note,
/// unflushed draft, or live session for that concept id, or when the
/// destination path does not exist.
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
) -> Result<LifecycleResult, AppError> {
    unimplemented!()
}

/// Creates a Directory, including intermediate levels (CAP-LIFE-05). An empty
/// Directory has no file to represent it, so it exists only in the
/// `directories` table until it holds a Note.
#[frb]
pub async fn create_directory(path: String) -> Result<LifecycleResult, AppError> {
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

/// The post-publication stage that has an incomplete record. The closed enum
/// prevents Presentation from extracting a stage from an error sentence.
#[frb]
pub enum LifecycleWarningStage {
    Commit,
    Settlement,
}

/// A nonfatal report accompanying an authoritative lifecycle result.
#[frb]
pub struct LifecycleWarning {
    pub stage: LifecycleWarningStage,
    pub detail: String,
}

/// The non-generic lifecycle result shape FRB transports for every Note and
/// Directory operation. `state` is populated by create, create-on-follow
/// (`create_link_target`), rename, and move.
/// `effects` carries reidentification and rewritten-source effects.
/// `removed` carries every deleted concept id.
///
/// A populated `warning` means the filesystem, index, and session state have
/// already settled. A `Settlement` warning can additionally report an
/// advisory refresh that could not complete while deriving the returned state;
/// the state, effects, and removed IDs remain authoritative. Presentation must
/// first adopt `state`, process `effects`, and clear every `removed` editor,
/// then show one localized, dismissible warning selected by `warning.stage`.
/// It must not restore the prior editor.
/// `Err(AppError)` is reserved for a true refusal before authoritative
/// lifecycle mutation, so Presentation retains the valid prior session.
#[frb]
pub struct LifecycleResult {
    pub state: Option<NoteState>,
    pub effects: LifecycleEffects,
    pub removed: Vec<String>,
    pub warning: Option<LifecycleWarning>,
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
) -> Result<LifecycleResult, AppError> {
    unimplemented!()
}

/// Deletes a Directory and everything beneath it, in one commit (CAP-LIFE-06).
/// Returns the concept ids of every Note removed, so a caller with one of them
/// open can close it rather than discovering it is gone on next access.
#[frb]
pub async fn delete_directory(path: String) -> Result<LifecycleResult, AppError> {
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
        /// The target's OKF concept id: unescape `\\`, `\<`, `\>` and `\&`,
        /// then strip the leading `/` and trailing `.md`. The parser has
        /// already removed the angle brackets, so `dest_url` never contains
        /// them. `&` is in the list because CommonMark decodes HTML entity
        /// references inside a destination and the brackets do not suppress
        /// that -- `</Caf&eacute;.md>` parses back as `/Café.md`, a different
        /// concept id than the one written. Always present, even when nothing
        /// matches it.
        target_id: String,
        /// False for a ghost Link -- a Link to a Note not yet created, which
        /// OKF section 6.1 requires consumers to tolerate and which
        /// CAP-GRAPH-04 makes a feature. The UI renders these distinctly and
        /// creates the Note on follow.
        ///
        /// **Advisory, and only as fresh as the state it came from.** Creating
        /// or deleting a Note flips this field for every inbound Link in every
        /// other Note, by the same mechanism `LifecycleEffects.rewritten`
        /// exists for -- but `create_note` and `delete_note` return no such
        /// list, deliberately: the affected set is every Note holding a ghost
        /// Link to that id, which is unbounded and mostly not open. So the
        /// **follow path must re-resolve against the index rather than trust
        /// this flag.** Without that rule, following a ghost Link to a concept
        /// created moments ago runs create-on-follow into `create_note` and
        /// gets `PathUnavailable` for a Link that resolves perfectly well --
        /// and `SHEL-E005`'s STOP then forbids working around it client-side,
        /// so the user is simply told no. The mirror case returns `NotFound`
        /// instead of the create offer. What the flag is *for* is rendering:
        /// deciding whether to draw a Link distinctly is a per-frame question
        /// where a stale answer costs nothing and re-querying costs a round
        /// trip per Link.
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
// **Every source-mutating call below writes the Note's working source and its
// draft row.** That is the tier 1 obligation in ADR-008 decision 1, and it
// belongs to all of them, not only to `update_block`: a split, a merge, a Block
// insertion and a range replace are each triggered by a discrete user action with no
// preceding `update_block`, so if they skipped the draft write the edit would
// live only in memory until the ~1s tier 2 timer fired. A kill in that window
// loses it, which CAP-WS-03 and `architecture/resilience.md`'s SQLite Draft
// Persistence guarantee both forbid — and it would make "no draft row" mean
// "nothing unwritten" falsely, which is the under-reporting direction of the
// invariant tier 2's draft-clearing establishes.
//
// A source-mutating call obtains its Core edit lease before looking up the open
// session. A lifecycle operation closes admission, drains all already-admitted
// leases, then snapshots/reconciles Notes. Later calls refuse with `ParseError`
// unchanged until that operation settles. The short admission step never waits
// behind lifecycle filesystem or Git work.
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

/// A pointer-resolved raw-source caret for Live Preview promotion.
///
/// `block_path` is the actual editable **leaf** Block path, which may be
/// nested beneath the supplied top-level container. `caret_offset` is an
/// offset into that leaf's raw Markdown source. Both offsets crossing this
/// boundary use Flutter UTF-16 code units — never Rust bytes or Unicode
/// scalar counts. A value splitting a surrogate pair is invalid and returns
/// `ParseError`; it is never rounded to a neighboring scalar.
#[frb]
pub struct BlockCaret {
    pub block_path: Vec<usize>,
    pub caret_offset: usize,
}

/// Resolves a rendered pointer coordinate synchronously through the Core span
/// map for Live Preview promotion (`CAP-EDIT-01`). `top_level_path` contains
/// exactly one top-level Block index. `rendered_utf16_offset` is Flutter's
/// `TextPosition.offset` in that Block's canonical rendered string — the same
/// per-variant string `BlockRange` defines below. The Core returns the leaf
/// path and raw-source UTF-16 caret in [`BlockCaret`], so Presentation never
/// infers Markdown delimiter widths, entity spellings, link destinations, or
/// nested container paths from widget layout.
#[frb(sync)]
pub fn resolve_block_caret(
    note_id: String,
    top_level_path: Vec<usize>,
    rendered_utf16_offset: usize,
) -> Result<BlockCaret, AppError> {
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
/// false for seven of the nine mutators: `insert_block`, `delete_block`,
/// `split_block`, `replace_selection_and_split_block`,
/// `merge_block_with_previous`, `delete_range` and `replace_range` are each
/// triggered by a discrete user action with no preceding `update_block`, so
/// each necessarily writes. The rule that does hold generally is in the
/// section header: every mutating call writes the working source and the draft
/// row, and this one is the exception because its input is already in both.
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

/// Splits a Block at a Flutter UTF-16 offset -- pressing Enter mid-Block
/// (CAP-EDIT-03). `source` and `offset` are the focused raw field's coordinate
/// space, not rendered text or a reparsed leaf's source. Core validates that
/// source against its buffered span, maps the coordinate to the current
/// editable leaf, and rejects an offset inside a surrogate pair rather than
/// rounding it or treating it as a Rust byte offset.
#[frb(sync)]
pub fn split_block(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
    offset: usize,
) -> Result<StructuralEdit, AppError> {
    unimplemented!()
}

/// Replaces a non-collapsed raw-field selection with nothing and splits at
/// the earlier UTF-16 endpoint in one structural transaction. `selection_base`
/// and `selection_extent` may arrive in either direction; Core validates both
/// boundaries, the replacement, post-split parse and returned focus before it
/// installs source/state, advances `edit_seq`, writes the draft, or arms tier
/// 2. Any refusal therefore leaves the field's source, draft and timer exactly
/// as they were, so Presentation retains the original selection for retry.
#[frb(sync)]
pub fn replace_selection_and_split_block(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
    selection_base: usize,
    selection_extent: usize,
) -> Result<StructuralEdit, AppError> {
    unimplemented!()
}

/// The opaque Core-owned insertion position used when a selected Enter removed
/// the entire raw field.
///
/// The slot can be nested in a List or Blockquote. Its fields are transport
/// data, not a Presentation editing model: return it unchanged to
/// `continue_block_at_insertion_slot`. `note_id` and `source_fingerprint`
/// bind it to the exact returned authoritative state; Core refuses a stale
/// capability before it changes source or draft state.
#[frb]
pub struct StructuralEditInsertionSlot {
    /// Byte offset in the exact returned working source, never a Flutter
    /// coordinate. Core validates it again when materializing the slot.
    pub source_offset: usize,
    /// Structural syntax removed with the complete line, such as `"> - "`.
    /// Empty when Core retained the container syntax for untouched siblings.
    pub line_prefix: String,
    /// Number of line endings that must remain after inserted source to retain
    /// the original tight/loose container seam. Core applies this value.
    pub required_after_newlines: usize,
    /// Core identity that owned the returned source. A rename or move changes
    /// it, so Presentation must not rekey this opaque value.
    pub note_id: String,
    /// SHA-256 fingerprint of the returned working source. Any authoritative
    /// rewrite, including a frontmatter-length change, retires this slot.
    pub source_fingerprint: String,
}

/// The Core-owned postcondition of a structural edit that preserves editing
/// focus. `state` is the authoritative reparse result. Ordinarily
/// `block_path` names an editable leaf and `caret_offset` is Flutter UTF-16.
/// When a selected Enter removed the entire raw field,
/// `phantom_insertion_slot` instead names the deleted structural position;
/// `block_path` is empty and Presentation must not substitute a surviving
/// sibling path or infer Markdown markers.
#[frb]
pub struct StructuralEdit {
    pub state: NoteState,
    pub block_path: Vec<usize>,
    pub caret_offset: usize,
    pub phantom_insertion_slot: Option<StructuralEditInsertionSlot>,
}

/// Continues after an editable leaf. The returned [StructuralEdit] is
/// authoritative after reparse: it names the new editable leaf and its UTF-16
/// caret, so Flutter does not infer a path from nested widget layout.
///
/// Core inspects the AST/container context. A leaf in a List receives a
/// sibling ListItem, preserving that List and its marker. Any other leaf gets
/// an independent Block after its top-level ancestor: a Blockquote leaf
/// therefore exits the quote into an adjacent top-level paragraph. `[0]` is
/// the empty-Note sentinel and creates the first top-level Block. Presentation
/// supplies only the actual editable leaf path and source; it must never
/// select a structural behavior from the path length.
///
/// Core derives the returned leaf and UTF-16 caret together from the final
/// editable leaf overlapping the supplied source in the post-splice parse,
/// before it installs or persists structural state. Trailing unaddressable
/// Markdown is preserved but does not retarget that focus. If `source` yields
/// only unaddressable Markdown (for example a reference definition or raw
/// HTML), the call refuses unchanged rather than persisting hidden content and
/// inviting a duplicate retry.
#[frb(sync)]
pub fn continue_block_after(
    note_id: String,
    block_path: Vec<usize>,
    source: String,
) -> Result<StructuralEdit, AppError> {
    unimplemented!()
}

/// Materializes first text in a Core-returned empty editor slot. The opaque
/// slot may be top-level or nested; Core restores its saved marker prefix and
/// tight/loose seam before reparsing. Presentation must use this call for
/// `StructuralEdit::phantom_insertion_slot`, rather than calling
/// `continue_block_after` with an invented leaf path. A stale capability is
/// refused without changing source, draft, or edit state, and Presentation
/// retires its phantom and adopts the returned Note before optional source
/// hydration. A hydration failure leaves rendered state authoritative and must
/// not make the completed materialization retryable.
#[frb(sync)]
pub fn continue_block_at_insertion_slot(
    note_id: String,
    insertion_slot: StructuralEditInsertionSlot,
    source: String,
) -> Result<StructuralEdit, AppError> {
    unimplemented!()
}

/// Merges a Block into its predecessor -- pressing Backspace at offset 0
/// (CAP-EDIT-03). The returned [StructuralEdit] is authoritative after the
/// reparse: it names the predecessor leaf and raw-source UTF-16 caret at the
/// join, so Flutter must not predict either from the pre-merge tree. For a
/// ListItem, Core removes only the newline-and-marker seam and keeps the
/// predecessor marker/container (for example, `- alpha\n- beta\n` becomes
/// `- alphabeta\n` with path `[0, 0, 0]` and caret `5`). A first Block is a
/// no-op and returns that same leaf at caret zero.
#[frb(sync)]
pub fn merge_block_with_previous(
    note_id: String,
    block_path: Vec<usize>,
) -> Result<StructuralEdit, AppError> {
    unimplemented!()
}

/// A selection spanning one or more Blocks (ADR-006 decision 3).
///
/// Offsets are Flutter **UTF-16 code-unit** offsets into each Block's
/// **rendered text**, which is a pure function of that Block's `AstNode` -- of
/// what both sides already hold, not of whatever the widget laid out. Core
/// converts them to its scalar-offset span map and rejects an offset inside a
/// surrogate pair. That makes the number well-defined: the Core reproduces
/// the same string the UI selected without the UI having to describe its
/// geometry.
///
/// It is defined **per variant**, because a rule phrased only over `TextRun`
/// does not cover the nine. Three variants hold no `TextRun` under any
/// reading -- `CodeBlock` holds a bare `String`, `Image` holds two, and
/// `ThematicBreak` holds nothing -- so their rendered text came out empty. A
/// further four (`List`, `ListItem`, `Blockquote`, `Suggestion`) hold
/// `AstNode`s rather than `InlineElement`s, and whether the old word
/// "reachable" was meant to recurse through them was never stated either way.
/// Only `Heading` and `Paragraph` were unambiguous.
///
/// The three hard cases are the damaging ones. A code block's rendered length
/// was zero while the user could see and select through it, so
/// `copy_range_as_markdown` returns the wrong text and `delete_range` splices
/// against an offset space that does not describe the selection -- silent
/// content loss, on the default path, since CAP-EDIT-02 makes code blocks
/// authorable and CAP-EDIT-04 makes selection cross Blocks.
///
///   - `Heading`, `Paragraph`: concatenate the `TextRun.content` values in
///     `content` in order, descending into `Link`/`ExternalLink` `content`.
///   - `List`, `ListItem`, `Blockquote`, `Suggestion`: concatenate the
///     rendered text of each child `AstNode` in order, recursively, joining
///     children with a single `\n`.
///   - `CodeBlock`: the `code` string verbatim. Not the fence, not the
///     language.
///   - `Image`: the `alt_text`. It is what a screen reader and a text
///     selection both see.
///   - `ThematicBreak`: the empty string. It has no selectable text, so a
///     `BlockRange` endpoint may name it only at offset 0; any other offset is
///     out of range.
///
/// **What this deliberately does not model** is decoration the widget draws as
/// text but that no `AstNode` field contains -- a list bullet, an ordered
/// list's `1. `, a code fence's gutter or line numbers. The rendered string is
/// the Core's definition and the UI must map its own selection onto it rather
/// than the reverse, because the alternative is the Core knowing the widget's
/// presentation, which rule 3 exists to prevent. `EDIT-F003` owns proving the
/// two agree, and its criteria must use a fixture containing a code block and
/// a list, not three paragraphs.
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
/// Block, which the user sees as raw source. A range operation is invalid
/// while any Block is focused: the UI must blur first, wait for `commit_block`
/// to return its reparsed authoritative state, and then establish a new
/// rendered selection. This makes a focused endpoint and a focused interior
/// impossible, and ensures the Core never resolves a range against the stale
/// inline span map that exists between `update_block` and `commit_block`.
///
/// **A range covers everything between its two endpoints, including bytes the
/// UI never showed.** A range resolves to two source offsets and the Core
/// slices *between* them, so a selection whose endpoints straddle one of the
/// preserved-but-unaddressable regions — a raw HTML block, a link reference
/// definition, inline HTML; the class `rust/src/markdown/parser.rs` documents —
/// includes that region by construction. `copy_range_as_markdown` therefore
/// yields it, and `delete_range`/`replace_range` therefore destroy it. This is
/// the intended behaviour and the difference from the single-Block mutators,
/// which step over those regions rather than into them: a range is an explicit
/// span the user dragged, not a Block the Core picked. `EDIT-F004` builds the
/// selection UI knowing it, and should decide there whether a selection
/// crossing invisible content warrants a confirmation.
///
/// A `BlockRange` is forward after Presentation normalizes its selection:
/// `start` must resolve at or before `end` in source order. Reverse ranges are
/// rejected with `ParseError` and leave the Note unchanged; Core never swaps
/// endpoints because atomic-run boundary bias is endpoint-specific.
///
/// `EDIT-F001` settled the former drag-outward question on Flutter 3.44.3:
/// a focused `EditableText` does not participate in its enclosing
/// `SelectionArea`. A gesture in the field is field-local; a region drag that
/// crosses it selects around the field and omits its content. The mandatory
/// blur-and-reselect rule above is nevertheless the contract boundary for all
/// range operations, including future delete and replace entry points.
#[frb]
pub struct BlockRange {
    pub start_path: Vec<usize>,
    pub start_offset: usize,
    pub end_path: Vec<usize>,
    pub end_offset: usize,
}

/// Core-owned Select All boundary for the complete rendered Note. This is
/// deliberately represented by separate operations rather than a synthetic
/// [`BlockRange`] endpoint: a terminal `ThematicBreak` or empty `CodeBlock`
/// has rendered length zero, and its valid rendered offset zero names the
/// start—not the end—of its Markdown source. Core derives the source extent
/// from the first through final top-level Block spans; frontmatter remains
/// outside the rendered Note operation. Ordinary `BlockRange` behavior,
/// including UTF-16 validation and reverse-range refusal, is unchanged.
///
/// A whole-Note copy, delete, or replacement is one Core operation. Delete
/// and replacement return the same authoritative [RangeEditResult] caret as
/// their ordinary range equivalents.

/// Markdown for a multi-Block selection (CAP-EDIT-04). Executed Core-side
/// because the Core owns both the AST and the source text; reproducing it in
/// Dart would mean a second serializer.
#[frb(sync)]
pub fn copy_range_as_markdown(note_id: String, range: BlockRange) -> Result<String, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn copy_whole_note_as_markdown(note_id: String) -> Result<String, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_range(note_id: String, range: BlockRange) -> Result<RangeEditResult, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn delete_whole_note(note_id: String) -> Result<RangeEditResult, AppError> {
    unimplemented!()
}

/// Replaces a multi-Block selection with text -- typing or pasting over a
/// selection that crosses Blocks. This and `delete_range` are one atomic Core
/// operation each: one source replacement, reparse, draft-row write, and
/// authoritative caret result. A UI loop over Blocks is forbidden. The
/// operation is shaped to become one undo command when CAP-EDIT-08 lands, but
/// this surface does not implement an undo stack.
/// The caller must apply the returned caret rather than retaining a pre-edit
/// path or deriving one from the replacement length.
#[frb(sync)]
pub fn replace_range(
    note_id: String,
    range: BlockRange,
    replacement: String,
) -> Result<RangeEditResult, AppError> {
    unimplemented!()
}

#[frb(sync)]
pub fn replace_whole_note(
    note_id: String,
    replacement: String,
) -> Result<RangeEditResult, AppError> {
    unimplemented!()
}

/// Authoritative caret location after a range replacement or deletion.
///
/// `Block` names an editable leaf in the returned state. `source_offset_utf16`
/// is an offset in that leaf's raw source, in Flutter UTF-16 code units; it
/// follows `BlockCaret` and `BlockRange`'s surrogate-pair rejection rule.
/// `Phantom` names the empty-editor insertion slot when no editable Block
/// remains. Presentation must materialize it through the existing phantom
/// transition, rather than inventing an empty Block in Dart.
#[frb]
pub enum RangeEditCaret {
    Block {
        block_path: Vec<usize>,
        source_offset_utf16: usize,
    },
    Phantom {
        insertion_index: usize,
    },
}

/// The indivisible result of `delete_range` and `replace_range`.
#[frb]
pub struct RangeEditResult {
    pub state: NoteState,
    pub caret: RangeEditCaret,
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

/// **Discards the buffered edits and re-reads the Note from disk.** Deletes the
/// `drafts` row, reparses the file's current bytes, rebuilds the working source
/// and the span map from them, re-records the revision baseline, and returns
/// the resulting state with `restored_from_draft = false`.
///
/// This is the other half of `RevisionMismatch`, and without it that error has
/// no exit. Every document routes the recovery the same way -- risk 6's
/// residual-risk paragraph, `NoteWriteStatus.last_error` above, and
/// `SHEL-E007`'s criterion all say the user is offered a **reload** -- while
/// earlier revisions of this contract gave the UI nothing to call. The one
/// candidate, `open_note`, is specifically wrong for it: it restores an
/// unflushed draft in preference to disk, and tier 2 deliberately leaves the
/// draft row in place when it fails. So the reload would return the same
/// buffer that just lost the comparison, never show the changed file, and fail
/// again on the next timer tick, forever. `close_note` is not an exit either,
/// since it flushes first and so either raises the same error or overwrites the
/// external change the mismatch existed to protect.
///
/// This is the surface at which the Sync Manager's conflict markers become
/// `AstNode::Suggestion` nodes, because it is the only call that reads bytes
/// this application did not write into a Note that is already open.
///
/// **It destroys unwritten work by design**, which is why it is a separate call
/// and not something the mismatch path does on its own. The UI must confirm,
/// and must offer the user their own text first: `get_block_source` still reads
/// from the pre-reload buffer, and `copy_range_as_markdown` over the whole Note
/// is how a user keeps a copy before accepting the file.
#[frb]
pub async fn reload_note(note_id: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Terminal result from tier 3 for one Note session.
///
/// `warning = None` means the session closed cleanly. A warning means that
/// Core retired the session after it safely wrote the Note, but could not
/// record its Git commit or clear redundant draft bookkeeping. The warning is
/// user-visible, but Dart must not restore the outgoing editor because its
/// Core session no longer exists.
#[frb]
pub struct CloseNoteResult {
    pub warning: Option<String>,
}

/// Tier 3: flushes any pending write, makes one Git commit covering this
/// editing session, clears the `drafts` row, and calls the sync scheduler's
/// `notify_activity()` -- which has existed since Epic C with no caller
/// (deferred item 4).
///
/// Must also run on application quit and when switching away from a Note, or
/// the session is written to disk but never enters version history.
///
/// `Err` is a true refusal. Core keeps the session registered, and Dart keeps
/// the outgoing Note writable after it reports the failure. An `Ok` result
/// always means Core retired the session. If `warning` is present, Dart removes
/// the retired tab and reports the warning rather than restoring a dead
/// session. Dart can continue only one Note-to-Note replacement when no batch,
/// Workspace switch, or orderly shutdown encloses the close. A batch stops with
/// unprocessed tabs preserved, and an enclosing switch or shutdown is canceled.
#[frb]
pub async fn close_note(note_id: String) -> Result<CloseNoteResult, AppError> {
    unimplemented!()
}

/// Notes with an unflushed draft from a previous session, for surfacing
/// recovered work on startup (CAP-WS-03).
#[frb]
pub async fn pending_drafts() -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Workspace session snapshots (STATE-G003)
// ---------------------------------------------------------------------------

/// Defines the saved presentation-only synchronization label.
///
/// This closed set serializes as `local`, `connected`, and `paused` in the
/// session schema. It is not a Git reconciliation state machine. Add a value
/// only with a session-snapshot schema-version bump.
#[frb]
pub enum SessionSyncPresentation {
    Local,
    Connected,
    Paused,
}

/// Carries session state for the active Workspace.
///
/// Core supplies the persisted `schema_version` and `workspace_id`. The FFI
/// never accepts a Workspace ID because rule 2 scopes every call to the active
/// Workspace.
#[frb]
pub struct ActiveWorkspaceSessionSnapshot {
    /// Concept IDs of open Notes, in restore order.
    pub open_note_ids: Vec<String>,
    /// Concept ID of the active Note, or `None` when no Note is active.
    pub active_note_id: Option<String>,
    /// Directory concept IDs or bundle-relative paths used by the tree.
    pub expanded_directory_ids: Vec<String>,
    /// The most recent search-box text. An empty string is valid.
    pub search_query: String,
    /// Presentation-only synchronization state.
    pub sync_presentation: SessionSyncPresentation,
}

/// Loads the active Workspace session snapshot.
///
/// Before restore, Core requires every identity to be valid and nonempty,
/// rejects duplicates, requires the persisted Workspace ID to equal the active
/// Workspace, and requires a non-null active Note ID to occur in the open-Note
/// list. For corrupt bytes, an unsupported later schema version, or any semantic
/// violation, Core quarantines and preserves the original bytes without
/// migration or overwrite and returns the empty session for the active
/// Workspace. It never restores malformed state. A malformed current-version
/// snapshot leaves the normal default path writable after quarantine. After a
/// later-version refusal, Core may write a supported snapshot only at an
/// explicitly safe path isolated from the preserved bytes. The result contains
/// no Note body, credential, or device preference.
#[frb]
pub async fn load_active_workspace_session_snapshot(
) -> Result<ActiveWorkspaceSessionSnapshot, AppError> {
    unimplemented!()
}

/// Saves a session snapshot for the active Workspace.
///
/// Core writes the versioned payload with atomic replace. It determines the
/// Workspace ID and schema version instead of accepting either through FFI. If
/// the normal snapshot path has quarantined unsupported later-version bytes,
/// Core refuses to overwrite it and may save only through the explicitly safe
/// current-format path isolated from those preserved bytes.
#[frb]
pub async fn save_active_workspace_session_snapshot(
    snapshot: ActiveWorkspaceSessionSnapshot,
) -> Result<(), AppError> {
    unimplemented!()
}

/// Clears an isolated invalid current-version snapshot for the active Workspace.
///
/// Core preserves corrupt, schema-invalid, or semantically invalid bytes outside
/// the active session path before it clears that Workspace's snapshot. This
/// call doesn't delete quarantined unsupported later-version bytes and doesn't
/// affect another Workspace.
#[frb]
pub async fn clear_corrupt_active_workspace_session_snapshot() -> Result<(), AppError> {
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
///
/// **Prefix, not substring, and this is a deliberate Stage 3 narrowing of the
/// capability.** CAP-FIND-02 says a user jumps to a Note "by typing part of
/// its title"; this contract and `WSPC-D009`'s implementation both match a
/// leading prefix only, so typing `lait` does not reach `Café au lait`.
/// Prefix is the behaviour of the palettes this affordance is modelled on, and
/// it is the form that *can* be made index-backed later: `title LIKE 'q%'` is
/// the shape SQLite's LIKE optimization can serve from an index on
/// `notes(title)`, whereas a leading wildcard never is. Neither is index-backed
/// today -- `schema.sql` declares no index on `notes(title)`, so the shipped
/// query scans the Workspace's rows, which is sound at current Note counts and
/// is the cost `EPIC-E`'s palette ticket should measure before it goes on the
/// per-keystroke path. Widening to substring match is a PRD/Stage-3 change
/// rather than an implementation detail, since it needs its own index strategy
/// (an FTS or trigram surface), so revisit it there if the narrowing turns out
/// to be the wrong reading of "part of its title".
#[frb]
pub async fn find_notes_by_title(query: String, limit: u32) -> Result<Vec<NoteMetadata>, AppError> {
    unimplemented!()
}

/// Whether a completion targets an indexed Note or is a prospective ghost.
/// The distinction is Core-provided so Presentation can label and announce the
/// create affordance without constructing a target identity itself.
#[frb]
pub enum LinkCompletionKind {
    Existing { note_id: String },
    ProspectiveGhost { target_id: String },
}

/// One candidate for the in-editor Link completion (CAP-GRAPH-02 and the
/// forward-link half of CAP-GRAPH-04).
#[frb]
pub struct LinkCompletion {
    pub kind: LinkCompletionKind,
    pub title: String,
    /// The exact text to splice at the cursor, already in bundle-absolute
    /// Markdown form with the destination angle-bracket wrapped and `\\`,
    /// `\<`, `\>` and `\&` escaped inside it, per
    /// `data-models/okf-bundle.md`.
    /// Constructed Core-side so the UI never assembles a link target and
    /// cannot produce a non-conformant one -- which is only true if the Core
    /// applies the wrapping, since the ordinary multi-word title produces a
    /// path with a space in it and the unwrapped form of that is not a link.
    /// `EDIT-F006`'s STOP forbids the UI from repairing it afterwards.
    /// The link *text* is `title` with every whitespace run folded to a
    /// single space, so it is not always byte-identical to `title`: a title
    /// carrying an interior line terminator -- legal YAML, so reachable from a
    /// foreign bundle -- would otherwise end the paragraph mid-link and splice
    /// as two paragraphs of visible bracket syntax with no `Link` at all.
    /// "Exact text to splice" is the promise; folding is what keeps it.
    pub insert_text: String,
}

/// Candidates for the completion triggered by `[[`. The trigger is a UI
/// affordance; what gets inserted is `insert_text`.
///
/// Completion is eligible only for a **collapsed** caret when the last
/// unmatched `[[` before it is on the same line. Its query is precisely the
/// text after those brackets and before the caret. Any `]]`, newline, focus
/// loss, selection expansion, or source change making that saved trigger
/// snapshot false dismisses the UI list; accepting a stale candidate is
/// forbidden. `note_id` scopes both lookup and ghost derivation to the active
/// Workspace and identifies the current Note's Directory. The caller requests
/// at most 10 candidates and Core clamps a larger `limit` to 10. Existing
/// matches are `LinkCompletionKind::Existing`. If the query is a valid future
/// title in that Directory and the exact target is not already indexed, Core
/// includes one clearly marked `ProspectiveGhost` within the same limit.
/// `query` is a prospective **title**, never a target path: it must satisfy
/// the Note-title rules and therefore rejects separators, dot-path segments,
/// reserved names, and any input that would make the user type a location.
/// Existing title-prefix candidates are still returned for the unmodified
/// query, even when it is invalid as a prospective title. The ghost carries
/// the exact `target_id` and
/// standard-Markdown `insert_text` already derived. The UI replaces exactly
/// the immutable trigger range with this Core-supplied text; it neither
/// constructs nor repairs a link destination.
#[frb]
pub async fn link_completions(
    note_id: String,
    query: String,
    limit: u32,
) -> Result<Vec<LinkCompletion>, AppError> {
    unimplemented!()
}

/// Resolves a rendered internal Link against the index of the active
/// Workspace at activation time (CAP-GRAPH-03 and CAP-GRAPH-04). `exists` in
/// an AST Link is render-only advisory state and is never an input to this
/// decision.
///
/// For `Missing`, Core derives the complete identity fields for display. This
/// avoids a second target-id parser in Dart. Presentation must re-resolve at
/// activation and, only if the result remains `Missing`, call
/// `create_link_target(target_id)` rather than ordinary `create_note`.
#[frb]
pub enum LinkTargetResolution {
    Existing {
        note_id: String,
    },
    Missing {
        target_id: String,
        directory_path: String,
        title: String,
    },
}

#[frb]
pub async fn resolve_link_target(target_id: String) -> Result<LinkTargetResolution, AppError> {
    unimplemented!()
}

/// Creates the Note at the **exact** internal Link identity it carries
/// (CAP-GRAPH-04). The Core derives title and Directory from `target_id`,
/// creates missing parent Directories and the conformant Note atomically, then
/// indexes, opens, and commits it. It refuses a file or path collision rather
/// than silently choosing a different identity, and returns a
/// `LifecycleResult` containing the opened state. A commit-stage failure after
/// publication retains that authoritative Note and session and is a typed
/// warning, not an error. Rollback applies only before publication settles:
/// if final-path publication, indexing, or session registration fails, it
/// removes the Note and only the parent
/// Directories when they remain empty, and directory-index rows this operation
/// created; pre-existing Directories and foreign content are preserved.
///
/// Callers must first invoke `resolve_link_target`: an `Existing` result opens
/// that Note; only a still-`Missing` target reaches this operation.
#[frb]
pub async fn create_link_target(target_id: String) -> Result<LifecycleResult, AppError> {
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
/// empty -- verified per the provider module -- **or a repository this
/// Workspace previously published to** (reconnect after detach: local history
/// must be a descendant of the remote head, which makes re-publishing a plain
/// push). Updates `workspaces.provider` and `remote_url` in place; never
/// re-clones or discards local state.
///
/// **Provider seam (ADR-009):** `provider` names an entry in the provider
/// registry, not a hard-coded branch. GitHub ships first as the proven
/// surface; GitLab (CAP-SYNC-09) is the seam's second consumer and lands
/// behind it. Adding a provider must be additive: one auth/provisioning
/// module plus a registry entry, with no changes to any function in this
/// contract.
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

/// Detaches the Remote from the active Workspace (CAP-SYNC-06): removes the
/// remote from the repository config, flips `workspaces.provider` back to
/// `"local"` and clears `remote_url`, leaving all version history exactly as
/// it was. Unpushed local commits simply remain local commits; reconnecting
/// later re-adds the remote and publishes them then.
///
/// Detach succeeds offline and without credentials -- it is local bookkeeping,
/// not a network call. It is the inverse of `connect_remote`'s attach half
/// and deletes nothing.
#[frb]
pub async fn detach_remote() -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

/// Joins a connected Workspace from a second device (CAP-SYNC-07, ruling Q1):
/// authorize via `begin_oauth_flow` / `authenticate_workspace`, then clone
/// `repository` and make the clone the active Workspace. Unlike
/// `connect_remote`, adopting populated history is the entire point; the
/// destination must be empty or absent because two populated histories never
/// merge (`prd/out-of-scope/history-merge-on-connect.md`). Consolidating a
/// previous local archive into the clone afterward is `plan_consolidation`
/// / `apply_consolidation`'s job.
#[frb]
pub async fn clone_workspace(
    provider: String,
    repository: String,
    /// Directory to clone into; `None` resolves the default location's next
    /// free sibling, since the default is already occupied by this device's
    /// existing Workspace when one exists.
    destination: Option<String>,
) -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

// ---------------------------------------------------------------------------
// Realignment surfaces (2026-08-21) -- declared so no downstream stage invents
// them; each stays `unimplemented!()` until its owning epic lands, exactly as
// `export_workspace` has been since its capability was scoped.
//
// The tier-1 obligation extends here by rule: every content mutator below
// writes the draft row and increments `edit_seq` under the state lock, for
// the same reason `resolve_suggestion` does -- work restored by undo, or
// produced by replace-all, must not live only in memory until the idle timer
// fires. A mutator absent from both ADR-008's enumeration and this banner is
// a defect to raise, not an omission to improvise around.
// ---------------------------------------------------------------------------

#[frb]
pub struct CollisionEntry {
    /// The concept id both sides claim.
    pub concept_id: String,
    /// Title as it stands in the connected Workspace.
    pub local_title: String,
    /// Title as it stood in the source Workspace.
    pub incoming_title: String,
}

#[frb]
pub enum CollisionResolution {
    KeepLocal,
    KeepIncoming,
    /// Keep both: the incoming Note arrives under a renamed identity, and
    /// inbound Links are rewritten per the lifecycle rules.
    KeepBothRenamed {
        new_title: String,
    },
}

/// Plans a guided consolidation from a source Workspace directory
/// (CAP-SYNC-08). Returns the non-conflicting Notes that will migrate and
/// every identity collision requiring an explicit decision. Reads only;
/// neither side is modified by planning.
#[frb]
pub async fn plan_consolidation(
    source_path: String,
) -> Result<(Vec<NoteMetadata>, Vec<CollisionEntry>), AppError> {
    unimplemented!()
}

#[frb]
pub struct CollisionDecision {
    /// Must still collide identically at apply time, else `AppError` -- a
    /// background pull between plan and apply shifts the collision list, and
    /// positional binding would silently misresolve. Keyed by identity so the
    /// Core verifies what the user actually decided on.
    pub concept_id: String,
    pub resolution: CollisionResolution,
}

/// Applies a planned consolidation. Non-conflicting Notes migrate with fresh
/// history ("Import N Notes"); each collision resolves exactly as decided;
/// the source Workspace is never modified. Every decision's `concept_id` must
/// still collide identically at apply time.
#[frb]
pub async fn apply_consolidation(
    source_path: String,
    decisions: Vec<CollisionDecision>,
) -> Result<WorkspaceInfo, AppError> {
    unimplemented!()
}

#[frb]
pub struct NoteVersion {
    /// Opaque version identifier (a commit identity under the history store).
    pub version_id: String,
    pub timestamp: i64,
    /// The session commit message, naming the Note and the nature of the change.
    pub message: String,
}

/// Lists the recorded past versions of one Note, newest first (CAP-HIST-01).
/// One entry per editing session, per the commit granularity decision.
#[frb]
pub async fn list_note_versions(note_id: String) -> Result<Vec<NoteVersion>, AppError> {
    unimplemented!()
}

/// Restores a past version as the Note's current content (CAP-HIST-01).
/// Destructive to unwritten work by design: the UI confirms first, mirroring
/// the recovered-draft confirmation, and routes through the same reload path.
#[frb]
pub async fn restore_note_version(
    note_id: String,
    version_id: String,
) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Reverses the user's most recent content operation in the open Note
/// (CAP-EDIT-08); redo reapplies what undo reversed. Covers splice, Block and
/// range operations; excludes lifecycle renames and anything sync applied
/// (ADR-010). Depth is bounded; at the bound the oldest step falls off.
/// Async like every other mutator that returns a full `NoteState`: an undo
/// over a large Note serializes real payload, and the sync convention is
/// reserved for calls whose return is trivial.
#[frb]
pub async fn undo_note(note_id: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Reapplies the most recently undone operation (CAP-EDIT-08).
#[frb]
pub async fn redo_note(note_id: String) -> Result<NoteState, AppError> {
    unimplemented!()
}

/// Finds every occurrence of `query` inside one Note, including occurrences
/// inside rendered inline structure (CAP-FIND-03). Ranges resolve through the
/// same span map cross-Block selection uses; runs that cannot be addressed
/// interiorly match atomically, per the span-map rule. Individual replacement
/// dispatches through the existing single-range edit operation (`replace_range`)
/// with one of these ranges; only replace-all needs its own surface.
#[frb]
pub async fn find_in_note(note_id: String, query: String) -> Result<Vec<BlockRange>, AppError> {
    unimplemented!()
}

/// Replaces every occurrence of `query` with `replacement` as ONE atomic
/// multi-range operation (CAP-FIND-03), never a sequence of per-range calls:
/// intermediate states would violate the same atomicity rule range editing
/// already establishes.
#[frb]
pub async fn replace_all_in_note(
    note_id: String,
    query: String,
    replacement: String,
) -> Result<NoteState, AppError> {
    unimplemented!()
}

#[frb]
pub struct DiagnosticsBundle {
    /// Recent structured log entries: errors, retries, scheduler decisions,
    /// sweep outcomes. Note content NEVER enters this payload -- the exclusion
    /// is what makes the bundle safe to hand to a third party (CAP-SUP-01,
    /// Zero Content Telemetry).
    pub entries: Vec<String>,
    pub generated_at: i64,
    /// Application version for triage; no user identifiers.
    pub app_version: String,
    /// Index schema version, because schema drift is itself a triage answer.
    pub schema_version: String,
}

/// Produces a redacted diagnostics bundle on demand (CAP-SUP-01). A pure read
/// over the local log channel; nothing is transmitted anywhere by this call.
/// Async because it reads the log file from disk, so the Dart thread never
/// waits on it.
#[frb]
pub async fn collect_diagnostics() -> Result<DiagnosticsBundle, AppError> {
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
