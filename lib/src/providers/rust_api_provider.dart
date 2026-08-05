import 'package:burlmd/src/rust/api/auth.dart' as auth_ffi;
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/index/query.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

export 'package:burlmd/src/rust/api/auth.dart' show OAuthFlowStart;
export 'package:burlmd/src/rust/index/query.dart' show LinkCompletion, TreeNode;

/// Thin, app-owned wrapper around the generated FRB free functions. This is
/// the seam application code depends on instead of importing `ffi_api.dart`
/// functions directly, so tests can override `rustApiProvider` without
/// needing FRB's own `RustLib.initMock()` machinery, and without touching
/// `RustLib.instance.api`, which flutter_rust_bridge marks `@internal`.
class RustApi {
  const RustApi();

  NoteState openNote(String path) => ffi.openNote(path: path);

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

  void saveNote(String noteId, String expectedBaseRevision) =>
      ffi.saveNote(noteId: noteId, expectedBaseRevision: expectedBaseRevision);

  NoteState updateBlock(String noteId, List<int> blockPath, AstNode newNode) =>
      ffi.updateBlock(
        noteId: noteId,
        blockPath: Uint64List.fromList(blockPath),
        newNode: newNode,
      );

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
