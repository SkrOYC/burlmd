import 'package:burlmd/src/rust/api/auth.dart' as auth_ffi;
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/index/query.dart';
import 'package:burlmd/src/rust/workspace/bootstrap.dart' as bootstrap_ffi;
import 'package:burlmd/src/rust/workspace/lifecycle.dart';
import 'package:burlmd/src/rust/workspace/persist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

export 'package:burlmd/src/rust/api/auth.dart' show OAuthFlowStart;
export 'package:burlmd/src/rust/api/ffi_api.dart'
    show
        BlockCaret,
        BlockRange,
        RangeEditCaret,
        RangeEditCaret_Block,
        RangeEditCaret_Phantom,
        RangeEditResult,
        StructuralEdit;
export 'package:burlmd/src/rust/index/query.dart'
    show
        LinkCompletion,
        LinkCompletionKind_Existing,
        LinkCompletionKind_ProspectiveGhost,
        LinkTargetResolution,
        LinkTargetResolution_Existing,
        LinkTargetResolution_Missing,
        TreeNode;
export 'package:burlmd/src/rust/workspace/bootstrap.dart' show WorkspaceInfo;
export 'package:burlmd/src/rust/workspace/lifecycle.dart'
    show
        IdRemap,
        LifecycleEffects,
        LifecycleResult,
        LifecycleWarning,
        LifecycleWarningStage;
export 'package:burlmd/src/rust/workspace/persist.dart' show NoteWriteStatus;
export 'package:burlmd/src/rust/workspace/persist.dart'
    show StructuralEditInsertionSlot;

/// Thin, app-owned wrapper around the generated FRB free functions. This is
/// the seam application code depends on instead of importing `ffi_api.dart`
/// functions directly, so tests can override `rustApiProvider` without
/// needing FRB's own `RustLib.initMock()` machinery, and without touching
/// `RustLib.instance.api`, which flutter_rust_bridge marks `@internal`.
///
/// Lands the editing half of the wrapper surface (`WSPC-D008`) in full, not
/// only the members whose signature changed: `openNote`/`updateBlock` are
/// repaired here (the previous `openNote(path)` and the AST-based
/// `updateBlock` are both gone, replaced by the contract's concept-id
/// `open_note` and source-text `update_block`), and `saveNote` — which the
/// contract deletes outright in favour of `flushNote` — is removed rather
/// than repaired.
///
/// `WSPC-D006` adds the seven lifecycle wrappers (`createNote`, `renameNote`,
/// `moveNote`, `deleteNote`, `createDirectory`, `renameDirectory`,
/// `deleteDirectory`) at the bottom, on the rule that a wrapper ships with the
/// function it wraps: they could not land with the editing half above, which
/// does not depend on `WSPC-D006` and would have left `ffi.createNote` and
/// friends unresolved at its own `dart analyze` gate.
class RustApi {
  const RustApi();

  /// Opens the local Workspace, creating and initializing it if absent
  /// (`WSPC-D004`, ADR-005 decision 1): no credential, no provider, and no
  /// network. Establishes the active Workspace on success, so every later
  /// Note-level call is implicitly scoped to it. Idempotent per the Core
  /// contract — on restart the existing repository, Workspace row and root
  /// key are reused rather than recreated.
  Future<bootstrap_ffi.WorkspaceInfo> openOrCreateLocalWorkspace({
    String? path,
  }) => ffi.openOrCreateLocalWorkspace(path: path);

  /// Opens a Note by concept id, restoring an unflushed draft if one exists
  /// (ADR-008 tier 1's crash recovery, CAP-WS-03).
  Future<NoteState> openNote(String noteId) => ffi.openNote(noteId: noteId);

  /// Forces ADR-008 tier 2 immediately: writes the Note's working source to
  /// its file atomically and returns the new `baseRevision`. Not the routine
  /// path — the Core's own idle timer is — but the explicit-flush escape
  /// hatch used on close, on shutdown, and by tests.
  Future<String> flushNote(String noteId) => ffi.flushNote(noteId: noteId);

  /// The state of the write tier for one open Note, polled by the UI since
  /// tier 2's routine trigger is a Core-owned idle timer with no caller to
  /// report a failure to otherwise. Never fails: a Note that is not open
  /// reports no error and no unwritten edits.
  NoteWriteStatus noteWriteStatus(String noteId) =>
      ffi.noteWriteStatus(noteId: noteId);

  /// Discards buffered edits and re-reads the Note from disk — the only exit
  /// from a `RevisionMismatch`. Destroys unwritten work by design, so the
  /// caller must confirm with the user first.
  Future<NoteState> reloadNote(String noteId) => ffi.reloadNote(noteId: noteId);

  /// Tier 3: flushes any pending write, makes one Git commit covering this
  /// editing session, clears the draft row, and notifies the sync scheduler.
  /// Must also run on application quit and when switching away from a Note.
  ///
  /// A post-close Core warning is represented as [CloseNoteWarning]. Unlike
  /// other errors it means the session was already retired; callers must not
  /// restore a writable snapshot for it. Keeping the method's `Future<void>`
  /// shape preserves the focused test doubles that model ordinary successful
  /// closes without an FRB dependency.
  Future<void> closeNote(String noteId) async {
    final result = await ffi.closeNote(noteId: noteId);
    if (result.warning case final String warning) {
      throw CloseNoteWarning(warning);
    }
  }

  /// Notes with an unflushed draft from a previous session, for surfacing
  /// recovered work on startup (CAP-WS-03).
  Future<List<NoteMetadata>> pendingDrafts() => ffi.pendingDrafts();

  /// The raw Markdown source of one Block, including its delimiters and
  /// terminating newline, for populating the editable field on focus
  /// (ADR-006 decision 2).
  String getBlockSource(String noteId, List<int> blockPath) =>
      ffi.getBlockSource(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
      );

  /// Resolves a pointer coordinate in a top-level formatted Block through the
  /// Core span map. [renderedUtf16Offset] and [BlockCaret.caretOffset] are
  /// Flutter UTF-16 code-unit offsets; the returned path always names the
  /// actual editable leaf, including inside list and quote containers.
  ffi.BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int renderedUtf16Offset,
  ) => ffi.resolveBlockCaret(
    noteId: noteId,
    topLevelPath: Uint64List.fromList(topLevelPath),
    renderedUtf16Offset: BigInt.from(renderedUtf16Offset),
  );

  /// The per-keystroke call (ADR-007 decision 4, ADR-008 tier 1): buffers
  /// `newSource` into the Note's working source and writes the draft row.
  /// Deliberately cheap — it does not parse and returns nothing, unlike the
  /// AST-based signature this replaces.
  void updateBlock(String noteId, List<int> blockPath, String newSource) =>
      ffi.updateBlock(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
        newSource: newSource,
      );

  /// Reparses the Note's working source and rebuilds the span map when the
  /// focused Block loses focus (ADR-007 decision 1). The returned state is
  /// authoritative — a splice can change a Block's node shape, so the caller
  /// must re-derive focus from it rather than reuse `blockPath`.
  NoteState commitBlock(String noteId, List<int> blockPath) => ffi.commitBlock(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
  );

  /// Inserts a new Block at `blockPath`, shifting subsequent Blocks down.
  NoteState insertBlock(String noteId, List<int> blockPath, String source) =>
      ffi.insertBlock(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
        source: source,
      );

  NoteState deleteBlock(String noteId, List<int> blockPath) => ffi.deleteBlock(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
  );

  /// Splits a Block at a **source UTF-16** offset — pressing Enter mid-Block.
  /// [source] is Flutter's raw field coordinate space; Core maps it through a
  /// live reparse and returns the authoritative second-half focus.
  ffi.StructuralEdit splitBlock(
    String noteId,
    List<int> blockPath,
    String source,
    int offset,
  ) => ffi.splitBlock(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
    source: source,
    offset: BigInt.from(offset),
  );

  /// Atomically deletes a non-collapsed raw-field selection and splits at its
  /// earlier UTF-16 endpoint. Core validates the replacement, split, and
  /// returned focus before it installs state or writes the draft row.
  ffi.StructuralEdit replaceSelectionAndSplitBlock(
    String noteId,
    List<int> blockPath,
    String source,
    int selectionBase,
    int selectionExtent,
  ) => ffi.replaceSelectionAndSplitBlock(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
    source: source,
    selectionBase: BigInt.from(selectionBase),
    selectionExtent: BigInt.from(selectionExtent),
  );

  /// Materializes a Core-returned opaque editor slot at its authoritative
  /// structural location, rather than continuing after an unrelated sibling.
  ffi.StructuralEdit continueBlockAtInsertionSlot(
    String noteId,
    StructuralEditInsertionSlot insertionSlot,
    String source,
  ) => ffi.continueBlockAtInsertionSlot(
    noteId: noteId,
    insertionSlot: insertionSlot,
    source: source,
  );

  /// Merges a Block into its predecessor — Backspace at offset 0
  /// (CAP-EDIT-03), returning Core's reparsed predecessor leaf and caret.
  ffi.StructuralEdit mergeBlockWithPrevious(
    String noteId,
    List<int> blockPath,
  ) => ffi.mergeBlockWithPrevious(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
  );

  /// Continues after a real editable leaf. Core inspects the AST to preserve a
  /// List or exit another container, then returns the actual post-reparse
  /// focus target.
  ffi.StructuralEdit continueBlockAfter(
    String noteId,
    List<int> blockPath,
    String source,
  ) => ffi.continueBlockAfter(
    noteId: noteId,
    blockPath: Uint64List.fromList(blockPath),
    source: source,
  );

  /// Markdown for a multi-Block selection (CAP-EDIT-04), executed Core-side
  /// because the Core owns both the AST and the source text.
  String copyRangeAsMarkdown(String noteId, ffi.BlockRange range) =>
      ffi.copyRangeAsMarkdown(noteId: noteId, range: range);

  /// Core-derived Markdown for the whole rendered Note. Unlike a
  /// [BlockRange], this has no synthetic rendered endpoint, so an empty
  /// terminal rendering still contributes its source.
  String copyWholeNoteAsMarkdown(String noteId) =>
      ffi.copyWholeNoteAsMarkdown(noteId: noteId);

  ffi.RangeEditResult deleteRange(String noteId, ffi.BlockRange range) =>
      ffi.deleteRange(noteId: noteId, range: range);

  ffi.RangeEditResult deleteWholeNote(String noteId) =>
      ffi.deleteWholeNote(noteId: noteId);

  /// Replaces a multi-Block selection with text — typing over a selection
  /// that crosses Blocks. The caller must re-derive caret position from the
  /// returned state and caret.
  ffi.RangeEditResult replaceRange(
    String noteId,
    ffi.BlockRange range,
    String replacement,
  ) => ffi.replaceRange(noteId: noteId, range: range, replacement: replacement);

  ffi.RangeEditResult replaceWholeNote(String noteId, String replacement) =>
      ffi.replaceWholeNote(noteId: noteId, replacement: replacement);

  /// Full-text search within the active Workspace (CAP-FIND-01), bm25-ranked
  /// and capped at `limit` — the caller-supplied cap that replaces the
  /// hardcoded truncation `WSPC-D009` removes.
  Future<List<NoteMetadata>> searchNotes(String query, int limit) =>
      ffi.searchNotes(query: query, limit: limit);

  /// Title-prefix jump (CAP-FIND-02).
  Future<List<NoteMetadata>> findNotesByTitle(String query, int limit) =>
      ffi.findNotesByTitle(query: query, limit: limit);

  /// Candidates for the in-editor Link completion triggered by `[[`
  /// (CAP-GRAPH-02). Each result's `insertText` is already a bundle-absolute,
  /// escaped Markdown link built Core-side — the UI splices it verbatim and
  /// must not construct or repair a link target itself.
  Future<List<LinkCompletion>> linkCompletions(
    String noteId,
    String query,
    int limit,
  ) => ffi.linkCompletions(
    noteId: noteId,
    query: query,
    limit: switch (limit) {
      < 0 => 0,
      > 10 => 10,
      _ => limit,
    },
  );

  /// Resolves an internal Link at activation time. The returned sealed shape
  /// is Core-derived; callers must not infer state from an AST render flag.
  Future<LinkTargetResolution> resolveLinkTarget(String targetId) =>
      ffi.resolveLinkTarget(targetId: targetId);

  /// Creates only the exact target identity Core re-resolves from a Link.
  Future<LifecycleResult> createLinkTarget(String targetId) =>
      ffi.createLinkTarget(targetId: targetId);

  /// Notes linking *to* `noteId` (CAP-GRAPH-05).
  Future<List<NoteMetadata>> backlinks(String noteId) =>
      ffi.backlinks(noteId: noteId);

  /// The Workspace tree for the sidebar (CAP-GRAPH-01): Directories before
  /// Notes at each level, each group sorted by name.
  Future<List<TreeNode>> workspaceTree() => ffi.workspaceTree();

  // -- Note and Directory lifecycle (WSPC-D006) ---------------------------
  //
  // Because OKF identity is positional, `renameNote`, `moveNote` and
  // `renameDirectory` change concept ids. Callers must not retain an id
  // across one of these calls: the returned `NoteState` carries the new id,
  // and `LifecycleEffects` names every *other* Note the operation touched.
  // Both of its lists oblige the caller to reload the Note — `remapped`
  // because the id it holds is dead, and `rewritten` because the bytes moved
  // underneath an unchanged id, so an open Block still holds a Link carrying
  // the old target.

  /// Creates a Note in `directoryPath` (empty string for the bundle root)
  /// with a conformant frontmatter block and **opens it**. The authoritative
  /// [LifecycleResult] carries that state and any post-publication warning.
  ///
  /// The filename is the title verbatim plus `.md`, with no slugification. A
  /// collision, or a title deriving to a reserved OKF filename, throws
  /// `PathUnavailable`; the UI must surface that rather than retrying with a
  /// disambiguated name.
  Future<LifecycleResult> createNote(String directoryPath, String title) =>
      ffi.createNote(directoryPath: directoryPath, title: title);

  /// Renames a Note, rewriting its frontmatter title, its filename and every
  /// inbound Link, atomically (CAP-LIFE-02).
  Future<LifecycleResult> renameNote(String noteId, String newTitle) =>
      ffi.renameNote(noteId: noteId, newTitle: newTitle);

  /// Moves a Note to another Directory, rewriting every inbound Link
  /// (CAP-LIFE-03). Changes the Note's concept id, as [renameNote] does.
  Future<LifecycleResult> moveNote(String noteId, String newDirectoryPath) =>
      ffi.moveNote(noteId: noteId, newDirectoryPath: newDirectoryPath);

  /// Deletes a Note and commits the deletion, so it stays recoverable from
  /// local version history (CAP-LIFE-04).
  Future<LifecycleResult> deleteNote(String noteId) =>
      ffi.deleteNote(noteId: noteId);

  /// Creates a Directory, including intermediate levels (CAP-LIFE-05).
  Future<LifecycleResult> createDirectory(String path) =>
      ffi.createDirectory(path: path);

  /// Renames a Directory, moving its contents and rewriting inbound Links to
  /// every Note beneath it (CAP-LIFE-06). The Notes holding rewritten Links
  /// are not confined to the renamed subtree.
  Future<LifecycleResult> renameDirectory(String path, String newName) =>
      ffi.renameDirectory(path: path, newName: newName);

  /// Deletes a Directory and everything beneath it, in one commit
  /// (CAP-LIFE-06), returning the concept ids of every Note removed so a
  /// caller holding one open can close it.
  Future<LifecycleResult> deleteDirectory(String path) =>
      ffi.deleteDirectory(path: path);

  /// Starts an OAuth PKCE flow (SYNC-C002): Core generates the PKCE
  /// verifier/challenge and `state`, and returns the full authorize URL for
  /// the UI to open in the system browser. `redirectUri` must be the
  /// loopback URL the caller is already listening on.
  auth_ffi.OAuthFlowStart beginOAuthFlow(String provider, String redirectUri) =>
      auth_ffi.beginOauthFlow(provider: provider, redirectUri: redirectUri);

  /// Exchanges the authorization code captured from the loopback redirect
  /// for tokens (via PKCE) and returns a Workspace ID. The access/refresh
  /// tokens themselves never cross this boundary — Core stores them
  /// directly in the OS Keychain.
  Future<String> authenticateWorkspace(
    String provider,
    String authCode,
    String codeVerifier,
  ) => auth_ffi.authenticateWorkspace(
    provider: provider,
    authCode: authCode,
    codeVerifier: codeVerifier,
  );
}

/// A close completed Core-side but reported an incomplete post-close stage.
///
/// This is intentionally separate from an FFI error. A true close refusal
/// leaves the session live and retryable; this warning says Core deregistered
/// it after safely writing its Note, so Presentation must continue switching
/// rather than re-enable an editor aimed at a dead session.
class CloseNoteWarning implements Exception {
  const CloseNoteWarning(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Injects the Rust API surface into the widget tree. `RustLib.init()` must
/// already have completed (awaited in `main()`) before any widget first
/// reads this provider.
final rustApiProvider = Provider<RustApi>((ref) => const RustApi());
