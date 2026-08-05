import 'package:burlmd/src/rust/api/auth.dart' as auth_ffi;
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/index/query.dart';
import 'package:burlmd/src/rust/workspace/persist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

export 'package:burlmd/src/rust/api/auth.dart' show OAuthFlowStart;
export 'package:burlmd/src/rust/api/ffi_api.dart' show BlockRange;
export 'package:burlmd/src/rust/index/query.dart' show LinkCompletion, TreeNode;

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
/// than repaired. The seven lifecycle wrappers (`createNote`, `renameNote`,
/// ...) are `WSPC-D006`'s: this ticket does not depend on it, so wrapping
/// functions that do not exist yet would leave unresolved identifiers here.
class RustApi {
  const RustApi();

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
  Future<void> closeNote(String noteId) => ffi.closeNote(noteId: noteId);

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

  /// Splits a Block at a **source** character offset — pressing Enter
  /// mid-Block (CAP-EDIT-03).
  NoteState splitBlock(String noteId, List<int> blockPath, int offset) =>
      ffi.splitBlock(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
        offset: BigInt.from(offset),
      );

  /// Merges a Block into its predecessor — Backspace at offset 0
  /// (CAP-EDIT-03). A no-op on the first Block.
  NoteState mergeBlockWithPrevious(String noteId, List<int> blockPath) =>
      ffi.mergeBlockWithPrevious(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
      );

  /// Markdown for a multi-Block selection (CAP-EDIT-04), executed Core-side
  /// because the Core owns both the AST and the source text.
  String copyRangeAsMarkdown(String noteId, ffi.BlockRange range) =>
      ffi.copyRangeAsMarkdown(noteId: noteId, range: range);

  NoteState deleteRange(String noteId, ffi.BlockRange range) =>
      ffi.deleteRange(noteId: noteId, range: range);

  /// Replaces a multi-Block selection with text — typing over a selection
  /// that crosses Blocks. The caller must re-derive caret position from the
  /// returned state.
  NoteState replaceRange(
    String noteId,
    ffi.BlockRange range,
    String replacement,
  ) => ffi.replaceRange(noteId: noteId, range: range, replacement: replacement);

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
  Future<List<LinkCompletion>> linkCompletions(String query, int limit) =>
      ffi.linkCompletions(query: query, limit: limit);

  /// Notes linking *to* `noteId` (CAP-GRAPH-05).
  Future<List<NoteMetadata>> backlinks(String noteId) =>
      ffi.backlinks(noteId: noteId);

  /// The Workspace tree for the sidebar (CAP-GRAPH-01): Directories before
  /// Notes at each level, each group sorted by name.
  Future<List<TreeNode>> workspaceTree() => ffi.workspaceTree();

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

/// Injects the Rust API surface into the widget tree. `RustLib.init()` must
/// already have completed (awaited in `main()`) before any widget first
/// reads this provider.
final rustApiProvider = Provider<RustApi>((ref) => const RustApi());
