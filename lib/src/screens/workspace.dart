import 'dart:async';

import 'package:burlmd/src/components/status_message.dart';
import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:burlmd/src/design/workspace_shell.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application's home surface: a Workspace shell with the Directory
/// tree as its navigation sidebar (`SHEL-E003`) and the editor for the
/// selected Note as its main pane (`SHEL-E004`).
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key, this.fixtureCaptureController});

  /// Test-only bridge for the visual-fixture branch. Production callers leave
  /// this null and retain the ordinary workspace composition.
  final FixtureCaptureController? fixtureCaptureController;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  var _sessionRestoreStarted = false;

  Future<void> _restoreSessionTabs(WorkspaceSessionState snapshot) async {
    final unavailable = await ref
        .read(activeNoteProvider.notifier)
        .restoreOpenNotes(
          openNoteIds: snapshot.openNoteIds,
          activeNoteId: snapshot.activeNoteId,
        );
    if (!mounted) return;

    final activeNoteId = ref.read(activeNoteProvider)?.metadata.id;
    if (activeNoteId != null) {
      // The shell listener only activates the session Core already returned;
      // it does not reopen or construct one from this selection identity.
      ref.read(selectedNoteIdProvider.notifier).select(activeNoteId);
    }
    if (unavailable.isNotEmpty) {
      _showRescanMessage(
        context,
        AppLocalizations.of(
          context,
        )!.workspaceRestoreSavedNotes(unavailable.join(', ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final sessionSnapshot = ref.watch(workspaceSessionSnapshotProvider);
    ref.listen<AsyncValue<WorkspaceSessionState>>(
      workspaceSessionSnapshotProvider,
      (_, next) {
        if (_sessionRestoreStarted) return;
        if (next case AsyncData(:final value)) {
          _sessionRestoreStarted = true;
          unawaited(_restoreSessionTabs(value));
        }
      },
    );
    // Rescan outcomes surface here rather than inside the button widget, so
    // both the failure branch ("names the failure") and the refusal branch
    // of SHEL-E008 report through one SnackBar path on the shell's Scaffold.
    ref.listen<RescanState>(rescanStateProvider, (_, next) {
      final failure = next.failure;
      if (failure != null) {
        _showRescanMessage(context, 'Rescan failed: $failure');
      } else if (next.refusedReason case final reason?) {
        _showRescanMessage(context, reason);
      }
    });

    return Scaffold(
      body: workspace.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          // Soft-wrapped and scrollable so a long error can neither overflow
          // horizontally nor push its siblings off screen.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to open workspace'),
                    const SizedBox(height: 8),
                    Text('$error', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
        data: (info) => sessionSnapshot.isLoading
            ? const Center(child: CircularProgressIndicator())
            : BurlWorkspaceShell(
                workspaceName: info.name,
                workspacePath: info.localPath.isEmpty ? null : info.localPath,
                rescanButton: const WorkspaceRescanButton(),
                onRescan: () => ref.read(rescanStateProvider.notifier).run(),
                fixtureCaptureController: widget.fixtureCaptureController,
              ),
      ),
    );
  }
}

void _showRescanMessage(BuildContext context, String message) {
  showStatusMessage(context, message);
}

/// The state of the latest user-invoked rescan (`SHEL-E008`, CAP-WS-06).
/// [failure] and [refusedReason] are one-shot reports consumed by the
/// screen's listener; a successful rescan leaves them null and the refreshed
/// tree is the only visible outcome.
class RescanState {
  const RescanState({this.running = false, this.failure, this.refusedReason});

  static const idle = RescanState();

  /// A full reindex round trip is in flight; the affordance disables so a
  /// second invocation cannot stack on top of it.
  final bool running;

  /// The error `reindex_workspace` raised, if the last attempt failed.
  final Object? failure;

  /// Why the last attempt was refused without touching the Core, if it was.
  final String? refusedReason;
}

/// Drives CAP-WS-06's explicit refresh: re-derives the shell's view of the
/// Workspace from disk by running the Core's full-reindex call and then
/// invalidating [workspaceTreeProvider], so Notes an external tool added
/// while the application runs appear without a restart.
///
/// The tree is invalidated only **after** the reindex succeeds — a failure
/// must leave the previous view standing rather than show a partial one, so
/// nothing touches the providers until the Core has reported success.
class WorkspaceRescan extends Notifier<RescanState> {
  @override
  RescanState build() => RescanState.idle;

  Future<void> run() async {
    if (state.running) return;

    // A rescan, lifecycle action, or active-note reload can each replace the
    // Core view this operation reads. Refuse stale/direct invocations instead
    // of overlapping their independent admissions.
    // The regular affordance is disabled by the same shared gate, but this
    // direct check protects a stale frame or programmatic caller as well.
    if (ref.read(lifecycleEditingProvider) > 0 ||
        ref.read(reloadEditingProvider) > 0 ||
        ref.read(noteSwitchingProvider)) {
      state = const RescanState(
        refusedReason:
            'Rescan unavailable while workspace changes are in progress.',
      );
      return;
    }

    // STOP condition: rescanning under open sessions can silently discard
    // freshly-written index rows (the recorded transient-drop window), so
    // any open Note whose write tier still holds unwritten edits refuses
    // the rescan outright. A poll that cannot be answered at all counts as
    // dirty — the guard fails closed.
    final openSessions = {
      for (final note in ref.read(openNoteSessionsProvider))
        note.metadata.id: note,
    };
    // Legacy callers can still have an active session without a mounted tab;
    // include it in the same conservative guard until those callers retire.
    final active = ref.read(activeNoteProvider);
    if (active != null) {
      openSessions.putIfAbsent(active.metadata.id, () => active);
    }
    for (final open in openSessions.values) {
      if (!noteHoldsUnwrittenEdits(
        ref.read(rustApiProvider),
        open.metadata.id,
      )) {
        continue;
      }
      state = RescanState(
        refusedReason:
            'Rescan unavailable: "${open.metadata.title}" still has '
            'unsaved edits.',
      );
      return;
    }

    final editing = ref.read(rescanEditingProvider.notifier);
    // Close the shared admission boundary before any async gap. A selection
    // already waiting on open_note observes the generation change and cannot
    // mount a session that the reindex may have invalidated.
    editing.begin();
    ref.read(lifecycleAdmissionProvider.notifier).next();
    state = const RescanState(running: true);
    try {
      await ref.read(activeNoteProvider.notifier).settlePendingOpen();
      if (!ref.mounted) return;
      await ref.read(reindexWorkspaceProvider)();
      if (!ref.mounted) return;
      // A complete index is authoritative for every view derived from it.
      // Keep the old tree visible on failure, but refresh the tree, search,
      // and recovery surfaces together after success.
      ref.invalidate(workspaceTreeProvider);
      ref.invalidate(searchResultsProvider);
      ref.invalidate(pendingDraftsProvider);
      state = RescanState.idle;
    } catch (error) {
      if (ref.mounted) state = RescanState(failure: error);
    } finally {
      // Provider disposal can outlive the FFI future. Never write a retired
      // notifier while unwinding it, and never leave a live container's
      // reference-counted input gate held after either outcome.
      if (ref.mounted) editing.end();
    }
  }

  /// Whether a polled [NoteWriteStatus] indicates the Note still holds
  /// unwritten edits (`note_write_status`, ADR-008): a buffered edit not yet
  /// flushed, or a write-tier failure — which the contract always pairs with
  /// unwritten edits, but checking both keeps the guard conservative.
  static bool indicatesUnwrittenEdits(NoteWriteStatus status) {
    return status.hasUnwrittenEdits || status.lastError != null;
  }

  /// Whether the Core reports `noteId`'s write tier as holding unwritten
  /// edits (`note_write_status`, ADR-008): a buffered edit not yet flushed,
  /// or a write-tier failure — which the contract always pairs with
  /// unwritten edits, but checking both keeps the guard conservative.
  static bool noteHoldsUnwrittenEdits(RustApi api, String noteId) {
    try {
      final status = api.noteWriteStatus(noteId);
      return indicatesUnwrittenEdits(status);
    } catch (_) {
      // The poll itself failed: cleanliness cannot be established, so the
      // only safe answer for a destructive-window operation is "dirty".
      return true;
    }
  }
}

final rescanStateProvider = NotifierProvider<WorkspaceRescan, RescanState>(
  WorkspaceRescan.new,
);

/// The rescan affordance (`SHEL-E008`), placed where navigation lives: the
/// tree surface in the sidebar. Its label states plainly what it does —
/// re-read the Workspace from disk — and it disables while a reindex is in
/// flight or while the open Note holds unwritten edits (the STOP condition).
class WorkspaceRescanButton extends ConsumerWidget {
  const WorkspaceRescanButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rescan = ref.watch(rescanStateProvider);
    // Derived from the write-tier monitor's polled state rather than a
    // synchronous `note_write_status` call here: the monitor already polls
    // every interval while a Note is open and publishes what it saw, so this
    // stays current as edits flush instead of going stale between rebuilds.
    // (The monitor state is null when nothing is open or no poll has landed
    // yet; `run()`'s independent fail-closed check remains the safety net.)
    final status = ref.watch(writeTierMonitorProvider).status;
    final blockedByOpenEdits =
        status != null && WorkspaceRescan.indicatesUnwrittenEdits(status);
    final blocked =
        rescan.running ||
        blockedByOpenEdits ||
        ref.watch(lifecycleEditingProvider) > 0 ||
        ref.watch(reloadEditingProvider) > 0 ||
        ref.watch(noteSwitchingProvider);

    return Tooltip(
      message: 'Re-read the workspace from disk and refresh the note tree',
      child: TextButton.icon(
        onPressed: blocked
            ? null
            : () => ref.read(rescanStateProvider.notifier).run(),
        icon: const Icon(Icons.refresh),
        label: const Text(
          'Rescan workspace',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
