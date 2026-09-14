import 'dart:async';

import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/api/ffi_api.dart' as ffi;
import 'package:burlmd/src/rust/draft.dart';
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
  final session = ref.read(workspaceSessionProvider.notifier);
  final bootstrap = session._beginWorkspaceBootstrap();
  final api = ref.watch(rustApiProvider);
  try {
    // Snapshot calls are scoped to Core's active Workspace. Finish every save
    // admitted for the current scope before this call can change that scope.
    await session._drainSnapshotWrites(bootstrap);
    if (!ref.mounted || !session._isCurrentWorkspaceBootstrap(bootstrap)) {
      throw StateError('Workspace bootstrap was superseded.');
    }

    final workspace = await api.openOrCreateLocalWorkspace();
    if (!ref.mounted || !session._isCurrentWorkspaceBootstrap(bootstrap)) {
      return workspace;
    }
    session._completeWorkspaceBootstrap(bootstrap, workspace);
    return workspace;
  } catch (_) {
    session._failWorkspaceBootstrap(bootstrap);
    rethrow;
  }
});

/// Core-owned presentation state. These saved identifiers are never Note
/// sessions: a later workflow may ask Core to open them, but the sidecar does
/// not establish writable Note authority.
class WorkspaceSessionState {
  const WorkspaceSessionState({
    required this.openNoteIds,
    required this.activeNoteId,
    required this.expandedDirectoryIds,
    required this.searchQuery,
    required this.syncPresentation,
  });

  const WorkspaceSessionState.empty()
    : openNoteIds = const [],
      activeNoteId = null,
      expandedDirectoryIds = const {},
      searchQuery = '',
      syncPresentation = SessionSyncPresentation.local;

  final List<String> openNoteIds;
  final String? activeNoteId;
  final Set<String> expandedDirectoryIds;
  final String searchQuery;
  final SessionSyncPresentation syncPresentation;

  factory WorkspaceSessionState.fromSnapshot(
    ActiveWorkspaceSessionSnapshot snapshot,
  ) => WorkspaceSessionState(
    openNoteIds: List.unmodifiable(snapshot.openNoteIds),
    activeNoteId: snapshot.activeNoteId,
    expandedDirectoryIds: Set.unmodifiable(snapshot.expandedDirectoryIds),
    searchQuery: snapshot.searchQuery,
    syncPresentation: snapshot.syncPresentation,
  );

  ActiveWorkspaceSessionSnapshot toSnapshot() => ActiveWorkspaceSessionSnapshot(
    openNoteIds: List.of(openNoteIds),
    activeNoteId: activeNoteId,
    expandedDirectoryIds: expandedDirectoryIds.toList(),
    searchQuery: searchQuery,
    syncPresentation: syncPresentation,
  );

  WorkspaceSessionState copyWith({
    List<String>? openNoteIds,
    String? activeNoteId,
    bool clearActiveNoteId = false,
    Set<String>? expandedDirectoryIds,
    String? searchQuery,
    SessionSyncPresentation? syncPresentation,
  }) => WorkspaceSessionState(
    openNoteIds: openNoteIds ?? this.openNoteIds,
    activeNoteId: clearActiveNoteId
        ? null
        : (activeNoteId ?? this.activeNoteId),
    expandedDirectoryIds: expandedDirectoryIds ?? this.expandedDirectoryIds,
    searchQuery: searchQuery ?? this.searchQuery,
    syncPresentation: syncPresentation ?? this.syncPresentation,
  );
}

/// The session sidecar is presentation state, but a Core/transport failure is
/// still actionable: the shell reports it without making the Workspace
/// unavailable. The Workspace identity and generation keep an older failure
/// from being shown after Core has selected another Workspace.
enum WorkspaceSessionOperation { load, save }

class WorkspaceSessionFailure {
  const WorkspaceSessionFailure({
    required this.operation,
    required this.error,
    required this.workspaceId,
    required this.scopeGeneration,
  });

  final WorkspaceSessionOperation operation;
  final Object error;
  final String workspaceId;
  final int scopeGeneration;

  String get message => switch (operation) {
    WorkspaceSessionOperation.load =>
      'Could not restore workspace session: $error',
    WorkspaceSessionOperation.save =>
      'Could not save workspace session: $error',
  };
}

class WorkspaceSessionFailures extends Notifier<WorkspaceSessionFailure?> {
  @override
  WorkspaceSessionFailure? build() => null;

  void report(WorkspaceSessionFailure failure) => state = failure;

  void clear() => state = null;
}

final workspaceSessionFailureProvider =
    NotifierProvider<WorkspaceSessionFailures, WorkspaceSessionFailure?>(
      WorkspaceSessionFailures.new,
    );

class WorkspaceSession extends Notifier<WorkspaceSessionState> {
  Future<void> _writes = Future<void>.value();
  String? _workspaceId;
  var _scopeGeneration = 0;
  var _bootstrapGeneration = 0;
  int? _activeBootstrapGeneration;
  var _savePendingDuringBootstrap = false;
  var _restored = false;
  int? _snapshotSavingDisabledScopeGeneration;

  @override
  WorkspaceSessionState build() => const WorkspaceSessionState.empty();

  /// Starts a transition that could cause Core to select a different
  /// Workspace. Saves already admitted for the current Workspace must settle
  /// before that transition enters Core.
  _WorkspaceBootstrap _beginWorkspaceBootstrap() {
    final bootstrap = _WorkspaceBootstrap(++_bootstrapGeneration);
    _activeBootstrapGeneration = bootstrap.generation;
    return bootstrap;
  }

  bool _isCurrentWorkspaceBootstrap(_WorkspaceBootstrap bootstrap) =>
      _activeBootstrapGeneration == bootstrap.generation;

  Future<void> _drainSnapshotWrites(_WorkspaceBootstrap bootstrap) async {
    if (!_isCurrentWorkspaceBootstrap(bootstrap)) return;
    await _writes;
  }

  /// Makes [workspace] the sole presentation-state scope. A same-identity
  /// refresh retains already-restored user state; a different Workspace first
  /// exposes the writable empty state until its Core snapshot arrives.
  void _completeWorkspaceBootstrap(
    _WorkspaceBootstrap bootstrap,
    WorkspaceInfo workspace,
  ) {
    if (!_isCurrentWorkspaceBootstrap(bootstrap)) return;
    _activeBootstrapGeneration = null;

    final savePending = _savePendingDuringBootstrap;
    _savePendingDuringBootstrap = false;
    if (_workspaceId != workspace.id) {
      _workspaceId = workspace.id;
      _scopeGeneration++;
      _restored = false;
      _snapshotSavingDisabledScopeGeneration = null;
      ref.read(workspaceSessionFailureProvider.notifier).clear();
      state = const WorkspaceSessionState.empty();
      return;
    }
    if (savePending && _restored) _enqueueSave();
  }

  /// Leaves the current scope intact when bootstrap fails. A UI change that
  /// happened while Core was unavailable is persisted once that failure ends.
  void _failWorkspaceBootstrap(_WorkspaceBootstrap bootstrap) {
    if (!_isCurrentWorkspaceBootstrap(bootstrap)) return;
    _activeBootstrapGeneration = null;
    final savePending = _savePendingDuringBootstrap;
    _savePendingDuringBootstrap = false;
    if (savePending && _restored) _enqueueSave();
  }

  int? _restoreScopeFor(String workspaceId) {
    if (_activeBootstrapGeneration != null || _workspaceId != workspaceId) {
      return null;
    }
    return _scopeGeneration;
  }

  bool _isCurrentWorkspaceScope(String workspaceId, int scopeGeneration) =>
      _workspaceId == workspaceId && _scopeGeneration == scopeGeneration;

  void _reportFailure({
    required WorkspaceSessionOperation operation,
    required Object error,
    required String workspaceId,
    required int scopeGeneration,
  }) {
    if (!_isCurrentWorkspaceScope(workspaceId, scopeGeneration)) return;
    ref
        .read(workspaceSessionFailureProvider.notifier)
        .report(
          WorkspaceSessionFailure(
            operation: operation,
            error: error,
            workspaceId: workspaceId,
            scopeGeneration: scopeGeneration,
          ),
        );
  }

  /// Restores once for this exact Workspace generation. Core's safe fallback
  /// is already represented by an empty snapshot; transport failures use
  /// [restoreAfterLoadFailure] so they cannot authorize a durable overwrite.
  bool restore(
    ActiveWorkspaceSessionSnapshot snapshot, {
    required String workspaceId,
    required int scopeGeneration,
  }) {
    if (_activeBootstrapGeneration != null ||
        _workspaceId != workspaceId ||
        _scopeGeneration != scopeGeneration ||
        _restored) {
      return false;
    }
    state = WorkspaceSessionState.fromSnapshot(snapshot);
    _restored = true;
    return true;
  }

  /// Core returns an empty snapshot only after it has safely handled invalid
  /// on-disk bytes. A Dart-side FFI/transport failure has no such guarantee,
  /// so keep the Workspace usable in memory without admitting a save that
  /// could overwrite the unread durable snapshot.
  bool restoreAfterLoadFailure({
    required String workspaceId,
    required int scopeGeneration,
  }) {
    if (_activeBootstrapGeneration != null ||
        !_isCurrentWorkspaceScope(workspaceId, scopeGeneration) ||
        _restored) {
      return false;
    }
    state = const WorkspaceSessionState.empty();
    _restored = true;
    _snapshotSavingDisabledScopeGeneration = scopeGeneration;
    return true;
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) return;
    state = state.copyWith(searchQuery: query);
    _scheduleSave();
  }

  void toggleDirectory(String directoryId) {
    final expanded = {...state.expandedDirectoryIds};
    if (!expanded.remove(directoryId)) expanded.add(directoryId);
    state = state.copyWith(expandedDirectoryIds: Set.unmodifiable(expanded));
    _scheduleSave();
  }

  void setActiveNoteId(String? noteId) {
    if (state.activeNoteId == noteId) return;
    if (noteId == null) {
      final previous = state.activeNoteId;
      state = state.copyWith(
        openNoteIds: previous == null
            ? state.openNoteIds
            : state.openNoteIds.where((id) => id != previous).toList(),
        clearActiveNoteId: true,
      );
    } else {
      final open = state.openNoteIds.contains(noteId)
          ? state.openNoteIds
          : [...state.openNoteIds, noteId];
      state = state.copyWith(openNoteIds: open, activeNoteId: noteId);
    }
    _scheduleSave();
  }

  /// Rekeys only identities that Core's lifecycle result proved equivalent.
  void rekeyOpenNoteId({required String oldNoteId, required String newNoteId}) {
    if (oldNoteId == newNoteId) return;
    final ids = <String>[];
    for (final id in state.openNoteIds) {
      final replacement = id == oldNoteId ? newNoteId : id;
      if (!ids.contains(replacement)) ids.add(replacement);
    }
    final active = state.activeNoteId == oldNoteId
        ? newNoteId
        : state.activeNoteId;
    state = state.copyWith(openNoteIds: ids, activeNoteId: active);
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_restored) return;
    if (_activeBootstrapGeneration != null) {
      _savePendingDuringBootstrap = true;
      return;
    }
    _enqueueSave();
  }

  void _enqueueSave() {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;
    final scopeGeneration = _scopeGeneration;
    if (_snapshotSavingDisabledScopeGeneration == scopeGeneration) return;
    final snapshot = state.toSnapshot();
    // Capture the app-side API seam when the state change is admitted. The
    // queued task must not look it up after a Workspace transition.
    final api = ref.read(rustApiProvider);
    _writes = _writes.then((_) async {
      if (!_isCurrentWorkspaceScope(workspaceId, scopeGeneration)) {
        return;
      }
      try {
        await api.saveActiveWorkspaceSessionSnapshot(snapshot);
      } catch (error) {
        _reportFailure(
          operation: WorkspaceSessionOperation.save,
          error: error,
          workspaceId: workspaceId,
          scopeGeneration: scopeGeneration,
        );
      }
    });
  }
}

class _WorkspaceBootstrap {
  const _WorkspaceBootstrap(this.generation);

  final int generation;
}

final workspaceSessionProvider =
    NotifierProvider<WorkspaceSession, WorkspaceSessionState>(
      WorkspaceSession.new,
    );

/// Sidecar restore is independent of Workspace bootstrap: an optional session
/// read cannot make a valid Workspace unavailable. Core already returns an
/// empty default for invalid durable bytes; a transport failure instead keeps
/// the app-side state empty and pauses writes for that restore scope.
final workspaceSessionSnapshotProvider =
    FutureProvider.autoDispose<WorkspaceSessionState>((ref) async {
      final api = ref.watch(rustApiProvider);
      final workspace = await ref.watch(workspaceProvider.future);
      if (!ref.mounted) return const WorkspaceSessionState.empty();

      final controller = ref.read(workspaceSessionProvider.notifier);
      final scopeGeneration = controller._restoreScopeFor(workspace.id);
      if (scopeGeneration == null) return ref.read(workspaceSessionProvider);

      try {
        final snapshot = await api.loadActiveWorkspaceSessionSnapshot();
        if (!ref.mounted) return const WorkspaceSessionState.empty();
        controller.restore(
          snapshot,
          workspaceId: workspace.id,
          scopeGeneration: scopeGeneration,
        );
      } catch (error) {
        if (!ref.mounted) return const WorkspaceSessionState.empty();
        controller.restoreAfterLoadFailure(
          workspaceId: workspace.id,
          scopeGeneration: scopeGeneration,
        );
        controller._reportFailure(
          operation: WorkspaceSessionOperation.load,
          error: error,
          workspaceId: workspace.id,
          scopeGeneration: scopeGeneration,
        );
      }
      return ref.read(workspaceSessionProvider);
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

/// Number of full-workspace rescans that currently own the Core's indexing
/// boundary. This is a count instead of a boolean so an eventual nested
/// caller cannot reopen editor input while an outer rescan is still settling.
final rescanEditingProvider = NotifierProvider<RescanEditing, int>(
  RescanEditing.new,
);

class RescanEditing extends Notifier<int> {
  @override
  int build() => 0;

  void begin() => state++;

  void end() {
    assert(state > 0, 'Rescan editing gate released without an owner.');
    if (state > 0) state--;
  }
}

/// Whether ordinary note selection is unsafe because a source-replacing
/// operation is settling. This deliberately excludes [noteSwitchingProvider]:
/// selection requests already admitted before a switch are serialized by
/// [NoteController], while reload, lifecycle and rescan work can invalidate
/// the selected Note itself.
final noteSelectionBlockedProvider = Provider<bool>(
  (ref) =>
      ref.watch(reloadEditingProvider) > 0 ||
      ref.watch(lifecycleEditingProvider) > 0 ||
      ref.watch(rescanEditingProvider) > 0,
);

/// The concept id of the Note currently selected in the tree, or `null`
/// when nothing is selected. This is the shared selection admission seam
/// every navigation producer uses before the editor opens the Note.
///
/// Selection coordinates are ephemeral UI state, not Note content
/// (`tech-spec/guidelines.md`) — exactly what this small [Notifier] holds.
class SelectedNoteId extends Notifier<String?> {
  @override
  String? build() => null;

  /// Selects [noteId], re-emitting an explicit tap of the already-selected
  /// Note. This makes an incoming `open_note` failure retryable: its selected
  /// id intentionally stays visible while the editor shows the failure, and a
  /// second tap must produce a new listener event rather than silently doing
  /// nothing because the identifier is equal.
  bool select(String noteId) {
    // A stale callback can arrive before a disabled row has rebuilt. Keeping
    // this check at the shared seam prevents Search, recovered drafts,
    // keyboard commands, and future producers from leaving the highlight on
    // a Note that the editor is forbidden to mount.
    if (ref.read(noteSelectionBlockedProvider)) return false;
    _publish(noteId);
    return true;
  }

  /// Publishes a selection that the lifecycle coordinator has already
  /// admitted. Lifecycle-created or rekeyed Notes must be able to update the
  /// shared highlight while the ordinary navigation gate remains closed.
  void selectForLifecycle(String noteId) => _publish(noteId);

  void _publish(String noteId) {
    if (state == noteId) state = null;
    state = noteId;
  }

  /// Clears the selection — the close-in-the-editor half of deleting a Note
  /// (`SHEL-E005`). Setting rather than a null-taking parameter keeps
  /// [select] honest; only deletion and directory deletion have a reason to
  /// unselect.
  void clear() => state = null;
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

/// -- Recovered drafts and write-tier visibility (`SHEL-E007`) --------------

/// Notes carrying an unflushed draft from a previous session (`pending_drafts`,
/// CAP-WS-03), fetched once per startup for the recovered-work surface: the
/// user must be told work was recovered, not silently find a Note in an
/// unexpected state. Re-fetched if invalidated (e.g. after a rescan).
final pendingDraftsProvider = FutureProvider.autoDispose<List<NoteMetadata>>(
  (ref) => ref.watch(rustApiProvider).pendingDrafts(),
);

/// The concept ids whose recovery notices the user has dismissed.
///
/// Dismissal hides **only the notice** — it never touches the Core and never
/// discards the draft row or the recovered content (SHEL-E007's STOP
/// condition), which is why this is plain UI state rather than a Core call.
class DismissedRecoveries extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(String noteId) => state = {...state, noteId};
}

final dismissedRecoveriesProvider =
    NotifierProvider<DismissedRecoveries, Set<String>>(DismissedRecoveries.new);

/// How often the open Note's write tier is polled in production. Overridable
/// per scope: widget tests override [writeStatusPollIntervalProvider] with
/// `null` so the monitor never arms its periodic timer (there is no fake
/// clock to fire it) and drive [WriteTierMonitor.poll] explicitly instead —
/// which is also what makes the persistence criteria deterministically
/// testable, poll by poll.
const writeStatusPollInterval = Duration(seconds: 2);

/// The interval the active [WriteTierMonitor] polls at; `null` disables
/// periodic polling entirely.
final writeStatusPollIntervalProvider = Provider<Duration?>(
  (ref) => writeStatusPollInterval,
);

/// How many consecutive failed polls the monitor tolerates before it stops
/// presenting its last-known status as trustworthy. Below the threshold a
/// failed poll is treated as transient and the previous status keeps
/// standing; at or above it, no status can be believed anymore.
const writeStatusFailureThreshold = 3;

/// What the write-tier surface renders for the currently open Note: the
/// last successfully polled [status], plus how many polls in a row have
/// failed to produce an answer at all.
///
/// The separate failure count exists because of SHEL-E007's STOP risk: a
/// failing *write* is surfaced through [NoteWriteStatus.lastError], but a
/// failing *poll* surfaces into nothing — if every poll from the very first
/// build onward threw, the user would keep typing into a buffer nothing can
/// verify, with no signal anywhere. Counting consecutive failures lets the
/// monitor distinguish "one flaky read, keep last-known standing" (the
/// rationale that forbids clearing on error) from "the answer channel itself
/// is down" ([statusUnavailable]).
class WriteTierSurface {
  const WriteTierSurface({this.status, this.pollsFailed = 0});

  /// Nothing is open, or polling has not produced an answer yet.
  static const idle = WriteTierSurface();

  /// The last status successfully read from `note_write_status`, or `null`
  /// when no poll has ever succeeded for this Note.
  final NoteWriteStatus? status;

  /// Consecutive polls whose `note_write_status` round trip itself threw.
  final int pollsFailed;

  /// True once [pollsFailed] reaches [writeStatusFailureThreshold]: the
  /// monitor can no longer vouch for [status] (if any) and says so rather
  /// than silently presenting stale data.
  bool get statusUnavailable => pollsFailed >= writeStatusFailureThreshold;
}

/// Polls `note_write_status` (ADR-008) for whichever Note is currently open.
///
/// A poll rather than a stream because tier 2's routine trigger is a
/// Core-owned idle timer with no caller to return an error to — without
/// something polling, `RevisionMismatch`, `DiskFull` and `IoError` are raised
/// into nothing while the user keeps typing into a buffer nothing can
/// persist (SHEL-E007's second STOP condition).
///
/// Watching [activeNoteProvider] re-runs [build] on every open/close/reload,
/// so the status is always about the Note actually on screen and a fresh
/// read happens immediately when it changes; a periodic timer keeps the
/// surface current between user actions. A poll round that itself throws
/// leaves the last known status standing — clearing it would unsurface a
/// failure that may still be real — but consecutive failures accumulate in
/// [WriteTierSurface.pollsFailed] until the monitor declares the write
/// status unavailable instead of pretending the old answer is current.
class WriteTierMonitor extends Notifier<WriteTierSurface> {
  Timer? _timer;

  int _consecutiveFailures = 0;

  @override
  WriteTierSurface build() {
    final open = ref.watch(activeNoteProvider);
    _stopTimer();
    ref.onDispose(_stopTimer);
    // Every rebuild starts a fresh observation window for the newly opened
    // Note; the failure streak belongs to one Note's polling history.
    _consecutiveFailures = 0;
    if (open == null) return WriteTierSurface.idle;
    final interval = ref.watch(writeStatusPollIntervalProvider);
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => poll());
    }
    try {
      return WriteTierSurface(
        status: ref.read(rustApiProvider).noteWriteStatus(open.metadata.id),
      );
    } catch (_) {
      // First read failed: report no status yet rather than a fabricated
      // one, but publish the failure count so escalation accounting stays
      // honest — returning `idle` (pollsFailed 0) would understate the
      // streak by one and delay [statusUnavailable] past the threshold.
      _consecutiveFailures = 1;
      return WriteTierSurface(pollsFailed: _consecutiveFailures);
    }
  }

  /// One explicit poll of the open Note's write tier. Also invoked by the
  /// periodic timer; exposed publicly so tests drive polls deterministically.
  void poll() {
    final open = ref.read(activeNoteProvider);
    if (open == null) {
      state = WriteTierSurface.idle;
      return;
    }
    try {
      final status = ref
          .read(rustApiProvider)
          .noteWriteStatus(open.metadata.id);
      _consecutiveFailures = 0;
      state = WriteTierSurface(status: status);
    } catch (_) {
      _consecutiveFailures++;
      // Keep the last known status standing for now; past the threshold,
      // say plainly that the status cannot be determined.
      state = WriteTierSurface(
        status: state.status,
        pollsFailed: _consecutiveFailures,
      );
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final writeTierMonitorProvider =
    NotifierProvider.autoDispose<WriteTierMonitor, WriteTierSurface>(
      WriteTierMonitor.new,
    );
