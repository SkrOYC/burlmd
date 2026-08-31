import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionSnapshotRustApi extends RustApi {
  _SessionSnapshotRustApi(this.snapshot);

  final ActiveWorkspaceSessionSnapshot snapshot;
  final List<ActiveWorkspaceSessionSnapshot> savedSnapshots = [];
  var openNoteCalls = 0;

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async =>
      const WorkspaceInfo(
        id: 'workspace-a',
        name: 'Workspace A',
        provider: 'local',
        localPath: '/tmp/workspace-a',
      );

  @override
  Future<ActiveWorkspaceSessionSnapshot>
  loadActiveWorkspaceSessionSnapshot() async => snapshot;

  @override
  Future<void> saveActiveWorkspaceSessionSnapshot(
    ActiveWorkspaceSessionSnapshot snapshot,
  ) async {
    savedSnapshots.add(snapshot);
  }

  @override
  Future<Never> openNote(String noteId) async {
    openNoteCalls++;
    throw StateError('session snapshot restore must not open a Note session');
  }
}

void main() {
  test(
    'restores search, expansion, open identities, and active identity from Core without Note content',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['inbox/today', 'projects/state'],
          activeNoteId: 'projects/state',
          expandedDirectoryIds: ['inbox', 'projects'],
          searchQuery: 'durable session',
          syncPresentation: SessionSyncPresentation.connected,
        ),
      );
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final restored = await container.read(
        workspaceSessionSnapshotProvider.future,
      );

      expect(restored.openNoteIds, ['inbox/today', 'projects/state']);
      expect(restored.activeNoteId, 'projects/state');
      expect(restored.expandedDirectoryIds, {'inbox', 'projects'});
      expect(restored.searchQuery, 'durable session');
      expect(restored.syncPresentation, SessionSyncPresentation.connected);
      expect(container.read(searchQueryProvider), 'durable session');
      expect(api.openNoteCalls, 0);
      expect(api.savedSnapshots, isEmpty);
    },
  );

  test(
    'persists search and expansion as snapshot fields without opening Notes',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSessionSnapshotProvider.future);

      container.read(searchQueryProvider.notifier).set('roadmap');
      container
          .read(workspaceSessionProvider.notifier)
          .toggleDirectory('plans');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.openNoteCalls, 0);
      expect(api.savedSnapshots, hasLength(2));
      expect(api.savedSnapshots.last.searchQuery, 'roadmap');
      expect(api.savedSnapshots.last.expandedDirectoryIds, ['plans']);
      expect(api.savedSnapshots.last.openNoteIds, isEmpty);
    },
  );
}
