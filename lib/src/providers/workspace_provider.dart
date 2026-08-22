import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active Workspace (`SHEL-E002`): opened on first read by driving the
/// Core's open-or-create bootstrap path (`WSPC-D004`) — no credential and no
/// network required. The Core contract makes this call idempotent, so a
/// restart reuses the existing repository, Workspace row and root key rather
/// than recreating them.
///
/// Auth state governs synchronization only (CAP-WS-01); nothing about opening
/// or navigating the Workspace reads it. Refreshing the view after an
/// external change is `ref.invalidate` territory (`SHEL-E008`).
final workspaceProvider = FutureProvider.autoDispose<WorkspaceInfo>((
  ref,
) async {
  return ref.watch(rustApiProvider).openOrCreateLocalWorkspace();
});

/// The Workspace's Directory/Note hierarchy (`WSPC-D009`'s single-call
/// contract), fetched in one `workspace_tree()` round trip for the sidebar
/// (`SHEL-E003`). Directories before Notes at each level, sorted by name,
/// with empty Directories included — all Core-guaranteed properties of this
/// one call.
///
/// Expansion is *not* modeled here: expanding or collapsing a Directory
/// filters what the already-fetched tree renders and must not re-run this
/// query. Only lifecycle operations and rescans (`SHEL-E008`) invalidate it.
final workspaceTreeProvider = FutureProvider.autoDispose<List<TreeNode>>((
  ref,
) async {
  return ref.watch(rustApiProvider).workspaceTree();
});

/// The concept id of the Note currently selected in the tree, or `null`
/// when nothing is selected. This is the seam `SHEL-E004` consumes to mount
/// the editor for the selected Note — the tree writes it on selection so
/// navigation needs no rework when the editor arrives.
///
/// Selection coordinates are ephemeral UI state, not Note content
/// (`tech-spec/guidelines.md`) — exactly what this small [Notifier] holds.
class SelectedNoteId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String noteId) => state = noteId;
}

final selectedNoteIdProvider = NotifierProvider<SelectedNoteId, String?>(
  SelectedNoteId.new,
);

/// The Core's full-reindex entry point (`reindex_workspace`, CAP-WS-06):
/// rebuilds `notes`, `notes_fts`, `fts_mapping`, `links` and `directories`
/// for the active Workspace from the bundle on disk and returns the number
/// of Notes indexed. This is what a user-invokable rescan (`SHEL-E008`)
/// drives so externally added Notes become visible without a restart.
///
/// Modeled as a function-valued provider rather than a new [RustApi] wrapper
/// member because that wrapper file sits outside SHEL-E008's in-scope set;
/// tests override this provider exactly as they override [rustApiProvider].
final reindexWorkspaceProvider = Provider<Future<int> Function()>(
  (ref) => ffi.reindexWorkspace,
);
