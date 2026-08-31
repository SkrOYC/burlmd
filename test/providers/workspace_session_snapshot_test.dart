import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionSnapshotRustApi extends RustApi {
  _SessionSnapshotRustApi(this.snapshot);

  final ActiveWorkspaceSessionSnapshot snapshot;
  final List<ActiveWorkspaceSessionSnapshot> savedSnapshots = [];
  Object? snapshotLoadError;
  NoteState? openedNote;
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
  loadActiveWorkspaceSessionSnapshot() async {
    final error = snapshotLoadError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<void> saveActiveWorkspaceSessionSnapshot(
    ActiveWorkspaceSessionSnapshot snapshot,
  ) async {
    savedSnapshots.add(snapshot);
  }

  @override
  Future<NoteState> openNote(String noteId) async {
    openNoteCalls++;
    final note = openedNote;
    if (note != null && note.metadata.id == noteId) return note;
    throw StateError('session snapshot restore must not open a Note session');
  }
}

NoteState _noteState(String id) => NoteState(
  ast: const [],
  metadata: NoteMetadata(
    id: id,
    path: '$id.md',
    title: id,
    lastModified: 0,
    okfConformant: true,
  ),
  baseRevision: 'revision-$id',
  restoredFromDraft: false,
);

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
    'a failed load enters the writable default and a stale retry cannot replace user state',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['stale'],
          activeNoteId: 'stale',
          expandedDirectoryIds: ['stale-directory'],
          searchQuery: 'stale search',
          syncPresentation: SessionSyncPresentation.connected,
        ),
      )..snapshotLoadError = StateError('session sidecar unavailable');
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final fallback = await container.read(
        workspaceSessionSnapshotProvider.future,
      );
      expect(fallback.openNoteIds, isEmpty);
      expect(fallback.activeNoteId, isNull);
      expect(fallback.expandedDirectoryIds, isEmpty);
      expect(fallback.searchQuery, isEmpty);
      expect(fallback.syncPresentation, SessionSyncPresentation.local);
      expect(
        container.read(workspaceSessionRestoreErrorProvider),
        isA<StateError>(),
      );

      container
          .read(workspaceSessionProvider.notifier)
          .setSearchQuery('user session change');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(api.savedSnapshots.single.searchQuery, 'user session change');

      api.snapshotLoadError = null;
      container.invalidate(workspaceSessionSnapshotProvider);
      await container.read(workspaceSessionSnapshotProvider.future);

      final retained = container.read(workspaceSessionProvider);
      expect(retained.searchQuery, 'user session change');
      expect(retained.openNoteIds, isEmpty);
      expect(retained.activeNoteId, isNull);
      expect(api.savedSnapshots, hasLength(1));
    },
  );

  test(
    'adopting a renamed Note rekeys the persisted session identities',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['inbox/today', 'projects/old', 'projects/future'],
          activeNoteId: 'projects/old',
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      )..openedNote = _noteState('projects/old');
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSessionSnapshotProvider.future);

      await container.read(activeNoteProvider.notifier).open('projects/old');
      container
          .read(activeNoteProvider.notifier)
          .adopt(_noteState('archive/renamed'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.savedSnapshots, hasLength(1));
      expect(api.savedSnapshots.single.openNoteIds, [
        'inbox/today',
        'archive/renamed',
        'projects/future',
      ]);
      expect(api.savedSnapshots.single.activeNoteId, 'archive/renamed');
      expect(
        api.savedSnapshots.single.openNoteIds,
        isNot(contains('projects/old')),
      );
    },
  );

  test(
    'adopting a renamed Note appends the new identity when the old one is absent',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['inbox/today'],
          activeNoteId: 'projects/old',
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      )..openedNote = _noteState('projects/old');
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSessionSnapshotProvider.future);

      await container.read(activeNoteProvider.notifier).open('projects/old');
      container
          .read(activeNoteProvider.notifier)
          .adopt(_noteState('archive/renamed'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.savedSnapshots, hasLength(1));
      expect(api.savedSnapshots.single.openNoteIds, [
        'inbox/today',
        'archive/renamed',
      ]);
      expect(api.savedSnapshots.single.activeNoteId, 'archive/renamed');
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
