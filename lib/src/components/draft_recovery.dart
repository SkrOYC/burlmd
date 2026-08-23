import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The recovered-draft surface (`SHEL-E007`): every Note the Core reports as
/// carrying an unflushed draft from a previous session is listed here so the
/// user knows work was recovered rather than silently finding a Note in an
/// unexpected state.
///
/// Selecting an entry publishes the Note's id through the existing selection
/// seam (`selectedNoteIdProvider`); the shell's editor-pane listener drives
/// [NoteController.open] from it — the single open path navigation uses.
/// `open_note` itself restores the draft in preference to disk, so what
/// renders is the drafted content and `NoteState.restoredFromDraft` carries
/// where it came from.
///
/// Dismissing an entry hides **only the notice**: the draft row, the
/// recovered content and this list's underlying data are untouched
/// (SHEL-E007's first STOP condition). The list reappears for a Note until
/// its session is properly closed — dismissal is UI state
/// ([dismissedRecoveriesProvider]), not a Core mutation.
class RecoveredDraftsPanel extends ConsumerWidget {
  const RecoveredDraftsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(pendingDraftsProvider);
    final dismissed = ref.watch(dismissedRecoveriesProvider);
    final selectionBlocked = ref.watch(noteSelectionBlockedProvider);
    final surfaced =
        drafts.value?.where((note) => !dismissed.contains(note.id)).toList() ??
        const [];
    if (surfaced.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.history, semanticLabel: 'Recovered'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recovered drafts',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        for (final note in surfaced)
          ListTile(
            key: ValueKey('recovered-${note.id}'),
            title: Text(note.title),
            subtitle: const Text(
              'Unsaved changes were recovered from a previous session.',
            ),
            onTap: selectionBlocked ? null : () => _open(ref, note.id),
            trailing: IconButton(
              tooltip: 'Dismiss notice',
              icon: const Icon(Icons.close),
              onPressed: () => ref
                  .read(dismissedRecoveriesProvider.notifier)
                  .dismiss(note.id),
            ),
          ),
      ],
    );
  }

  void _open(WidgetRef ref, String noteId) {
    // Publish only. Driving `activeNoteProvider.open()` here as well would
    // issue a second, redundant open alongside the shell listener that the
    // same publication already triggers.
    ref.read(selectedNoteIdProvider.notifier).select(noteId);
  }
}

/// The write-tier surface (`SHEL-E007`): renders whatever
/// [writeTierMonitorProvider] last polled for the open Note.
///
/// A `RevisionMismatch` shows the failure and offers a **reload** — never a
/// retry or a reopen, because the file changed underneath the draft:
/// retrying would overwrite it, and reopening (`open_note`) would restore
/// the surviving draft and reproduce the mismatch on the next tick. The
/// offer therefore drives `reload_note` (through
/// [NoteController.reloadFromDisk]) behind a confirmation that says plainly
/// that reloading discards buffered text — the only prompt in the
/// application that destroys unwritten work.
///
/// Every other failure (`DiskFull`, `IoError`, …) persists across polls
/// until the status actually clears, because each subsequent write fails
/// the same way until it is resolved; showing it once would hide exactly
/// the condition the user must fix.
class WriteTierNotice extends ConsumerWidget {
  const WriteTierNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A refused per-keystroke write (`update_block` tier 1). Surfaced here,
    // above the editor, rather than through [editorErrorProvider]: the
    // flow's contract is that the user never loses sight of their text
    // because of a transient write hiccup — the draft row holds the edit,
    // the buffer keeps rendering, and this notice names what happened.
    // Core's polled `note_write_status` cannot carry it (`lastError`
    // records tier-2 failures only), so the Dart side publishes it
    // directly. Cleared by the next successful keystroke or a note
    // switch/reload.
    final keystrokeFailure = ref.watch(keystrokeWriteFailureProvider);
    if (keystrokeFailure != null) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                semanticLabel: 'Edit not saved yet',
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your latest edit could not be saved yet ($keystrokeFailure). '
                  'Your text is still here; saving retries automatically.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final surface = ref.watch(writeTierMonitorProvider);
    // The poll channel itself is down: after several consecutive failed
    // polls no status — not even a previously good one — can be trusted, so
    // say so rather than silently presenting stale data (SHEL-E007's STOP
    // risk of write failures surfacing into nothing). The monitor keeps
    // retrying on its own; there is no user action that fixes polling.
    if (surface.statusUnavailable) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                semanticLabel: 'Write status unavailable',
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'The note\'s save status cannot be checked right now. '
                  'Your latest edits may not be written to disk yet; '
                  'checking continues automatically.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final error = surface.status?.lastError;
    if (error == null) return const SizedBox.shrink();

    final message = switch (error) {
      AppError_RevisionMismatch() =>
        'This note changed on disk while you were editing '
            '(revision mismatch), so your latest text could not be written.',
      AppError_DiskFull() =>
        'The disk is full. Changes cannot be saved until space is freed.',
      _ => 'Writing the note failed: $error',
    };

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  semanticLabel: 'Write failure',
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            if (error is AppError_RevisionMismatch) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('reload-offer'),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload from disk'),
                  onPressed: () => _confirmAndReload(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Offers the reload with the one warning that matters stated plainly:
  /// `reload_note` destroys unwritten work by design. Until the user
  /// chooses, their buffered text stays reachable — cancelling leaves the
  /// buffer and the surfaced failure exactly as they are.
  Future<void> _confirmAndReload(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reload from disk?'),
        content: const Text(
          'Reloading discards your buffered text — everything you have '
          'typed that was not written to disk. The file changed while you '
          'were editing, so reloading cannot keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard and reload'),
          ),
        ],
      ),
    );
    // The dialog awaited: the workspace (and this notice with it) may have
    // unmounted while it was open — e.g. the Note closed underneath. Using
    // the element's providers after unmount would throw, so guard first.
    if (confirmed != true || !context.mounted) return;
    await ref.read(activeNoteProvider.notifier).reloadFromDisk();
  }
}
