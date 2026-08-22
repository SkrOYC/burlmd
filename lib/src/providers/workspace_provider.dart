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
/// surface current between user actions. State is `null` while no Note is
/// open. A poll round that itself throws leaves the last known status
/// standing — clearing it would unsurface a failure that may still be real.
class WriteTierMonitor extends Notifier<NoteWriteStatus?> {
  Timer? _timer;

  @override
  NoteWriteStatus? build() {
    final open = ref.watch(activeNoteProvider);
    _stopTimer();
    ref.onDispose(_stopTimer);
    if (open == null) return null;
    final interval = ref.watch(writeStatusPollIntervalProvider);
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => poll());
    }
    try {
      return ref.read(rustApiProvider).noteWriteStatus(open.metadata.id);
    } catch (_) {
      // First read failed: report nothing yet rather than a fabricated
      // status, but keep the timer running so later polls can surface one.
      return null;
    }
  }

  /// One explicit poll of the open Note's write tier. Also invoked by the
  /// periodic timer; exposed publicly so tests drive polls deterministically.
  void poll() {
    final open = ref.read(activeNoteProvider);
    if (open == null) {
      state = null;
      return;
    }
    try {
      state = ref.read(rustApiProvider).noteWriteStatus(open.metadata.id);
    } catch (_) {
      // Keep the last known status standing; see the class comment.
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final writeTierMonitorProvider =
    NotifierProvider.autoDispose<WriteTierMonitor, NoteWriteStatus?>(
      WriteTierMonitor.new,
    );
