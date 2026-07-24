import 'package:burlmd/src/rust/api/auth.dart' as auth_ffi;
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

export 'package:burlmd/src/rust/api/auth.dart' show OAuthFlowStart;

/// Thin, app-owned wrapper around the generated FRB free functions. This is
/// the seam application code depends on instead of importing `ffi_api.dart`
/// functions directly, so tests can override `rustApiProvider` without
/// needing FRB's own `RustLib.initMock()` machinery, and without touching
/// `RustLib.instance.api`, which flutter_rust_bridge marks `@internal`.
class RustApi {
  const RustApi();

  NoteState openNote(String path) => ffi.openNote(path: path);

  Future<List<NoteMetadata>> searchNotes(String query) =>
      ffi.searchNotes(query: query);

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
