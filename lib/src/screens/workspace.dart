import 'package:burlmd/src/components/draft_recovery.dart';
import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/search_panel.dart';
import 'package:burlmd/src/components/status_message.dart';
import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The application's home surface: a Workspace shell with the Directory
/// tree as its navigation sidebar (`SHEL-E003`) and the editor for the
/// selected Note as its main pane (`SHEL-E004`).
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
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
      appBar: AppBar(title: const Text('burlmd')),
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
        data: (info) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      info.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        // Expanded so a narrow sidebar constrains the
                        // button's label instead of overflowing the row.
                        const Expanded(child: _RescanButton()),
                        // The search affordance (`SHEL-E006`): toggles the
                        // panel section below the tree. It sits where
                        // navigation lives, like the rescan action.
                        IconButton(
                          tooltip: 'Search notes',
                          isSelected: ref.watch(searchSectionOpenProvider),
                          selectedIcon: const Icon(Icons.search),
                          icon: const Icon(Icons.search_outlined),
                          onPressed: () => ref
                              .read(searchSectionOpenProvider.notifier)
                              .toggle(),
                        ),
                      ],
                    ),
                  ),
                  // Recovered-draft notices (`SHEL-E007`) surface above the
                  // tree so recovered work is announced at startup; the
                  // panel collapses to nothing when nothing was recovered.
                  const RecoveredDraftsPanel(),
                  const Expanded(child: WorkspaceTree()),
                  // The search surface itself (`SHEL-E006`): a fixed-height
                  // section under the tree, shown only while toggled. Its
                  // result limit belongs to this surface, not to the panel
                  // or the Core.
                  if (ref.watch(searchSectionOpenProvider))
                    const SizedBox(
                      height: 280,
                      child: SearchPanel(resultLimit: 25),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: _EditorPane()),
          ],
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

    // Rescan and lifecycle actions both rewrite the Workspace's Core view.
    // The regular affordance is disabled by the same shared gate, but this
    // direct check protects a stale frame or programmatic caller as well.
    if (ref.read(lifecycleEditingProvider) > 0) {
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
    final open = ref.read(activeNoteProvider);
    if (open != null &&
        noteHoldsUnwrittenEdits(ref.read(rustApiProvider), open.metadata.id)) {
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
class _RescanButton extends ConsumerWidget {
  const _RescanButton();

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
        ref.watch(lifecycleEditingProvider) > 0;

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

/// The shell's main pane (`SHEL-E004`): the editor for whichever Note the
/// tree has selected. Selection is published by [WorkspaceTree] through
/// [selectedNoteIdProvider]; this pane reacts to it by driving
/// [NoteController.open], which closes the outgoing Note through the Core
/// before opening the new one, so navigation alone keeps every editing
/// session committed to version history.
class _EditorPane extends ConsumerWidget {
  const _EditorPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedNoteIdProvider);
    // Side effect lives in a listener, not in build's body: selection
    // changes fire exactly once per change, so no rebuild can re-issue an
    // open for a Note already being opened.
    ref.listen<String?>(selectedNoteIdProvider, (_, next) {
      if (next != null) ref.read(activeNoteProvider.notifier).open(next);
    });
    if (selectedId == null) {
      return const Center(child: Text('Select a note to open it'));
    }
    // The write-tier notice (`SHEL-E007`) rides above the editor pane for
    // whichever Note is open. Watching it here also *arms* polling: the
    // monitor's periodic timer exists only while something watches it, and
    // without an armed poller a write failure would be raised into nothing
    // while the user keeps typing into a buffer nothing can persist.
    return const Column(
      children: [
        WriteTierNotice(),
        Expanded(child: Editor()),
      ],
    );
  }
}

/// Whether the sidebar's search section is expanded (the mount point of
/// `SHEL-E006`'s [SearchPanel]). Ephemeral UI state, not Note content.
class SearchSectionOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final searchSectionOpenProvider = NotifierProvider<SearchSectionOpen, bool>(
  SearchSectionOpen.new,
);
