import 'dart:async';

import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionSnapshotRustApi extends RustApi {
  _SessionSnapshotRustApi(this.snapshot);

  final ActiveWorkspaceSessionSnapshot snapshot;
  final List<ActiveWorkspaceSessionSnapshot> savedSnapshots = [];
  Object? loadError;
  Object? saveError;
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
    final error = loadError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<void> saveActiveWorkspaceSessionSnapshot(
    ActiveWorkspaceSessionSnapshot snapshot,
  ) async {
    final error = saveError;
    if (error != null) throw error;
    savedSnapshots.add(snapshot);
  }

  @override
  Future<Never> openNote(String noteId) async {
    openNoteCalls++;
    throw StateError('restoring presentation state must not open a Note');
  }
}

class _SnapshotLoadRequest {
  _SnapshotLoadRequest(this.workspaceId);

  final String workspaceId;
  final completer = Completer<ActiveWorkspaceSessionSnapshot>();
}

class _SnapshotSaveRequest {
  _SnapshotSaveRequest({required this.workspaceId, required this.snapshot});

  final String workspaceId;
  final ActiveWorkspaceSessionSnapshot snapshot;
  final completer = Completer<void>();
}

class _ScopedSessionSnapshotRustApi extends RustApi {
  _ScopedSessionSnapshotRustApi(this._workspaceSequence);

  final List<WorkspaceInfo> _workspaceSequence;
  final loadRequests = <_SnapshotLoadRequest>[];
  final saveRequests = <_SnapshotSaveRequest>[];
  final _loadSignals = <Completer<_SnapshotLoadRequest>>[];
  final _saveSignals = <Completer<_SnapshotSaveRequest>>[];
  var openCalls = 0;
  late WorkspaceInfo _activeWorkspace;

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async {
    final index = openCalls < _workspaceSequence.length
        ? openCalls
        : _workspaceSequence.length - 1;
    final workspace = _workspaceSequence[index];
    openCalls++;
    _activeWorkspace = workspace;
    return workspace;
  }

  @override
  Future<ActiveWorkspaceSessionSnapshot> loadActiveWorkspaceSessionSnapshot() {
    final request = _SnapshotLoadRequest(_activeWorkspace.id);
    final index = loadRequests.length;
    loadRequests.add(request);
    if (index < _loadSignals.length && !_loadSignals[index].isCompleted) {
      _loadSignals[index].complete(request);
    }
    return request.completer.future;
  }

  @override
  Future<void> saveActiveWorkspaceSessionSnapshot(
    ActiveWorkspaceSessionSnapshot snapshot,
  ) {
    final request = _SnapshotSaveRequest(
      workspaceId: _activeWorkspace.id,
      snapshot: snapshot,
    );
    final index = saveRequests.length;
    saveRequests.add(request);
    if (index < _saveSignals.length && !_saveSignals[index].isCompleted) {
      _saveSignals[index].complete(request);
    }
    return request.completer.future;
  }

  Future<_SnapshotLoadRequest> loadRequestAt(int index) {
    if (index < loadRequests.length) return Future.value(loadRequests[index]);
    while (_loadSignals.length <= index) {
      _loadSignals.add(Completer<_SnapshotLoadRequest>());
    }
    return _loadSignals[index].future;
  }

  Future<_SnapshotSaveRequest> saveRequestAt(int index) {
    if (index < saveRequests.length) return Future.value(saveRequests[index]);
    while (_saveSignals.length <= index) {
      _saveSignals.add(Completer<_SnapshotSaveRequest>());
    }
    return _saveSignals[index].future;
  }
}

const _workspaceA = WorkspaceInfo(
  id: 'workspace-a',
  name: 'Workspace A',
  provider: 'local',
  localPath: '/tmp/workspace-a',
);

const _workspaceB = WorkspaceInfo(
  id: 'workspace-b',
  name: 'Workspace B',
  provider: 'local',
  localPath: '/tmp/workspace-b',
);

void main() {
  test(
    'restores only presentation state without opening a Note session',
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
      expect(container.read(searchQueryProvider), 'durable session');
      expect(api.openNoteCalls, 0);
      expect(api.savedSnapshots, isEmpty);
    },
  );

  test('persists search and expansion fields without Note content', () async {
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
    container.read(workspaceSessionProvider.notifier).toggleDirectory('plans');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(api.openNoteCalls, 0);
    expect(api.savedSnapshots, hasLength(2));
    expect(api.savedSnapshots.last.searchQuery, 'roadmap');
    expect(api.savedSnapshots.last.expandedDirectoryIds, ['plans']);
    expect(api.savedSnapshots.last.openNoteIds, isEmpty);
  });

  test(
    'load failure is reported and does not overwrite an unread snapshot',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['stale'],
          activeNoteId: 'stale',
          expandedDirectoryIds: ['stale-directory'],
          searchQuery: 'stale',
          syncPresentation: SessionSyncPresentation.connected,
        ),
      )..loadError = StateError('sidecar unavailable');
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final restored = await container.read(
        workspaceSessionSnapshotProvider.future,
      );
      expect(restored, isA<WorkspaceSessionState>());
      expect(restored.openNoteIds, isEmpty);
      expect(restored.activeNoteId, isNull);
      expect(restored.expandedDirectoryIds, isEmpty);
      final failure = container.read(workspaceSessionFailureProvider);
      expect(failure?.operation, WorkspaceSessionOperation.load);
      expect(failure?.error, isA<StateError>());
      container.read(searchQueryProvider.notifier).set('user change');
      await Future<void>.delayed(Duration.zero);
      expect(api.savedSnapshots, isEmpty);
    },
  );

  test(
    'save failure is reported while the in-memory session remains usable',
    () async {
      final api = _SessionSnapshotRustApi(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      )..saveError = StateError('sidecar write unavailable');
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSessionSnapshotProvider.future);

      container.read(searchQueryProvider.notifier).set('user change');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(workspaceSessionProvider).searchQuery,
        'user change',
      );
      final failure = container.read(workspaceSessionFailureProvider);
      expect(failure?.operation, WorkspaceSessionOperation.save);
      expect(failure?.error, isA<StateError>());
    },
  );

  test(
    'an orderly persistence drain writes the current snapshot and rejects an unresolved save failure',
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
      final session = container.read(workspaceSessionProvider.notifier);

      session.setActiveNoteId('restart-me');
      await session.flushPendingWrites();
      expect(api.savedSnapshots.last.openNoteIds, ['restart-me']);
      expect(api.savedSnapshots.last.activeNoteId, 'restart-me');

      api.saveError = StateError('sidecar write unavailable');
      await expectLater(session.flushPendingWrites(), throwsStateError);
      expect(
        container.read(workspaceSessionFailureProvider)?.operation,
        WorkspaceSessionOperation.save,
      );
    },
  );

  test(
    'a persistence drain waits for a save admitted while its first save is pending',
    () async {
      final api = _ScopedSessionSnapshotRustApi([_workspaceA]);
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        workspaceSessionProvider,
        (_, _) {},
      );
      addTearDown(sessionSubscription.close);

      final restored = container.read(workspaceSessionSnapshotProvider.future);
      final load = await api.loadRequestAt(0);
      load.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await restored;
      final session = container.read(workspaceSessionProvider.notifier);
      session.setSearchQuery('first');
      final firstSave = await api.saveRequestAt(0);

      final draining = session.flushPendingWrites();
      session.setSearchQuery('second');
      firstSave.completer.complete();
      final drainSave = await api.saveRequestAt(1);
      expect(drainSave.snapshot.searchQuery, 'first');
      drainSave.completer.complete();
      final laterSave = await api.saveRequestAt(2);
      expect(laterSave.snapshot.searchQuery, 'second');

      var drained = false;
      draining.whenComplete(() => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      laterSave.completer.complete();
      await draining;
      expect(drained, isTrue);
    },
  );

  test('an opened active Note is saved in the open-ID list', () async {
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

    container.read(workspaceSessionProvider.notifier).setActiveNoteId('today');
    await Future<void>.delayed(Duration.zero);

    expect(api.savedSnapshots.single.openNoteIds, ['today']);
    expect(api.savedSnapshots.single.activeNoteId, 'today');
  });

  test('a lifecycle-proven rekey replaces stale session identities', () async {
    final api = _SessionSnapshotRustApi(
      const ActiveWorkspaceSessionSnapshot(
        openNoteIds: ['old', 'new'],
        activeNoteId: 'old',
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

    container
        .read(workspaceSessionProvider.notifier)
        .rekeyOpenNoteId(oldNoteId: 'old', newNoteId: 'new');
    await Future<void>.delayed(Duration.zero);

    expect(api.savedSnapshots.single.openNoteIds, ['new']);
    expect(api.savedSnapshots.single.activeNoteId, 'new');
  });

  test(
    'a delayed restore for Workspace A cannot replace Workspace B state',
    () async {
      final api = _ScopedSessionSnapshotRustApi([_workspaceA, _workspaceB]);
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        workspaceSessionProvider,
        (_, _) {},
      );
      addTearDown(sessionSubscription.close);

      final workspaceAFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final workspaceALoad = await api.loadRequestAt(0);
      expect(workspaceALoad.workspaceId, _workspaceA.id);

      container.invalidate(workspaceProvider);
      container.invalidate(workspaceSessionSnapshotProvider);
      final workspaceBFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final workspaceBLoad = await api.loadRequestAt(1);
      expect(workspaceBLoad.workspaceId, _workspaceB.id);
      workspaceBLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['workspace-b/note'],
          activeNoteId: 'workspace-b/note',
          expandedDirectoryIds: ['workspace-b/directory'],
          searchQuery: 'Workspace B only',
          syncPresentation: SessionSyncPresentation.connected,
        ),
      );
      await workspaceBFuture;

      workspaceALoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: ['workspace-a/note'],
          activeNoteId: 'workspace-a/note',
          expandedDirectoryIds: ['workspace-a/directory'],
          searchQuery: 'stale Workspace A',
          syncPresentation: SessionSyncPresentation.paused,
        ),
      );
      await workspaceAFuture;

      final state = container.read(workspaceSessionProvider);
      expect(state.openNoteIds, ['workspace-b/note']);
      expect(state.activeNoteId, 'workspace-b/note');
      expect(state.expandedDirectoryIds, {'workspace-b/directory'});
      expect(state.searchQuery, 'Workspace B only');
      expect(state.syncPresentation, SessionSyncPresentation.connected);
    },
  );

  test(
    'a stale Workspace A load failure is not reported for Workspace B',
    () async {
      final api = _ScopedSessionSnapshotRustApi([_workspaceA, _workspaceB]);
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        workspaceSessionProvider,
        (_, _) {},
      );
      addTearDown(sessionSubscription.close);

      final workspaceAFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final workspaceALoad = await api.loadRequestAt(0);

      container.invalidate(workspaceProvider);
      container.invalidate(workspaceSessionSnapshotProvider);
      final workspaceBFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final workspaceBLoad = await api.loadRequestAt(1);
      workspaceBLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: 'Workspace B snapshot',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await workspaceBFuture;

      workspaceALoad.completer.completeError(
        StateError('Workspace A unavailable'),
      );
      await workspaceAFuture;

      expect(container.read(workspaceSessionFailureProvider), isNull);
      expect(
        container.read(workspaceSessionProvider).searchQuery,
        'Workspace B snapshot',
      );
    },
  );

  test(
    'refreshing the same Workspace does not replace restored user state',
    () async {
      final api = _ScopedSessionSnapshotRustApi([_workspaceA, _workspaceA]);
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        workspaceSessionProvider,
        (_, _) {},
      );
      addTearDown(sessionSubscription.close);

      final initialFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final initialLoad = await api.loadRequestAt(0);
      initialLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: 'saved Workspace A state',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await initialFuture;

      container
          .read(workspaceSessionProvider.notifier)
          .setSearchQuery('newer in-memory Workspace A state');
      final save = await api.saveRequestAt(0);
      save.completer.complete();

      container.invalidate(workspaceProvider);
      container.invalidate(workspaceSessionSnapshotProvider);
      final refreshFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final refreshedLoad = await api.loadRequestAt(1);
      refreshedLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: 'stale Core reload',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await refreshFuture;

      expect(
        container.read(workspaceSessionProvider).searchQuery,
        'newer in-memory Workspace A state',
      );
    },
  );

  test(
    'queued Workspace A saves drain before Workspace B becomes active',
    () async {
      final api = _ScopedSessionSnapshotRustApi([_workspaceA, _workspaceB]);
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        workspaceSessionProvider,
        (_, _) {},
      );
      addTearDown(sessionSubscription.close);

      final initialFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      final initialLoad = await api.loadRequestAt(0);
      initialLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: '',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await initialFuture;

      final session = container.read(workspaceSessionProvider.notifier);
      session.setSearchQuery('first Workspace A save');
      final firstSave = await api.saveRequestAt(0);
      expect(firstSave.workspaceId, _workspaceA.id);
      session.toggleDirectory('queued Workspace A directory');

      container.invalidate(workspaceProvider);
      container.invalidate(workspaceSessionSnapshotProvider);
      final workspaceBFuture = container.read(
        workspaceSessionSnapshotProvider.future,
      );
      expect(api.openCalls, 1);

      firstSave.completer.complete();
      final queuedSave = await api.saveRequestAt(1);
      expect(queuedSave.workspaceId, _workspaceA.id);
      queuedSave.completer.complete();

      final workspaceBLoad = await api.loadRequestAt(1);
      expect(workspaceBLoad.workspaceId, _workspaceB.id);
      workspaceBLoad.completer.complete(
        const ActiveWorkspaceSessionSnapshot(
          openNoteIds: [],
          expandedDirectoryIds: [],
          searchQuery: 'Workspace B snapshot',
          syncPresentation: SessionSyncPresentation.local,
        ),
      );
      await workspaceBFuture;

      expect(
        api.saveRequests.map((request) => request.workspaceId),
        everyElement(_workspaceA.id),
      );
      expect(
        container.read(workspaceSessionProvider).searchQuery,
        'Workspace B snapshot',
      );
    },
  );
}
