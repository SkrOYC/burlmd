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

/// Whether ordinary note selection is unsafe because a Workspace mutation is
/// settling. This deliberately excludes [noteSwitchingProvider]: selection
/// requests already admitted before a switch are serialized by
/// [NoteController], while lifecycle and rescan work can invalidate the
/// selected Note itself.
final noteSelectionBlockedProvider = Provider<bool>(
  (ref) =>
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
