import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How one lifecycle action (`SHEL-E005`) ended. The three shapes map onto
/// three different user-facing treatments, and collapsing them into a bool
/// would lose the one the STOP conditions care about: [LifecycleRefused]
/// means the Core itself declined — a `PathUnavailable` collision above all —
/// and the caller must show the Core's reason verbatim and stop. It must
/// never retry with an altered name; the contract specifies the error
/// precisely so the user decides what to do about it.
sealed class LifecycleOutcome {
  const LifecycleOutcome();
}

/// The operation went through. `detail` is a short human-readable summary;
/// the refreshed tree is usually the visible outcome, so surfacing this is
/// optional.
class LifecycleCompleted extends LifecycleOutcome {
  const LifecycleCompleted(this.detail);

  final String detail;
}

/// The Core refused without changing anything — a name collision or reserved
/// filename (`PathUnavailable`) being the canonical case. `reason` carries
/// the Core's own report; the UI shows it as-is.
class LifecycleRefused extends LifecycleOutcome {
  const LifecycleRefused(this.reason);

  final String reason;
}

/// The round trip failed for another reason (IO, database, ...). Surfaced
/// like any other boundary error rather than swallowed.
class LifecycleFailed extends LifecycleOutcome {
  const LifecycleFailed(this.error);

  final Object error;
}

/// Drives Note and Directory creation, rename, move and deletion against the
/// Core's lifecycle surface (`WSPC-D006`), and discharges the two obligations
/// the contract puts on every caller of an identity-changing operation:
///
/// **Re-anchoring.** Because OKF identity is positional, renaming a Note,
/// moving it, or renaming its containing Directory changes its concept id.
/// An open Note holding the old id is holding a dead identifier: the editor
/// must adopt the state the Core returns instead. The Core carries the open
/// session forward under the new id (working source, span map and recorded
/// revision intact), so re-anchoring is a plain state adoption — closing and
/// reopening would address the dead id and fail.
///
/// **Reloading rewritten Notes.** `LifecycleEffects.rewritten` names Notes
/// whose ids did *not* change but whose bytes were rewritten because they
/// held an inbound Link to the renamed target. Nothing about them looks
/// stale, which is exactly why the list exists: an open one still holds an
/// AST carrying the old `target_id`, and if its focused Block is edited, the
/// next `update_block` would substitute the pre-rewrite source back and
/// revert the rename from inside the editor. Each such open Note is fetched
/// fresh through `open_note` — which on an already-open Note returns the live
/// session's current state, rewrite included, with no tier side effects and
/// no loss of unflushed keystrokes — so the editor rebuilds and every
/// editable field resyncs before the next keystroke can undo the Core's work.
///
/// Deletion closes an open victim in the editor rather than leaving it open
/// against a removed file; the Core has already discarded the deleted Note's
/// session and draft row by the time the call returns, so no `close_note` is
/// sent.
class LifecycleActions {
  const LifecycleActions(this._ref);

  final Ref _ref;

  RustApi get _api => _ref.read(rustApiProvider);

  /// Creates a Note in `directoryPath` (empty string for the bundle root).
  /// The Core creates the file **and opens it**, so the returned state is an
  /// open Note; publishing its id through the selection seam routes the shell
  /// through the ordinary open path, which first closes any outgoing Note
  /// through the commit tier and then adopts the already-open created session
  /// (`open_note`'s fast path) — "opens for editing" without a second open.
  Future<LifecycleOutcome> createNote(String directoryPath, String title) =>
      _guard(() async {
        final created = await _api.createNote(directoryPath, title);
        _ref.invalidate(workspaceTreeProvider);
        _ref.read(selectedNoteIdProvider.notifier).select(created.metadata.id);
        return LifecycleCompleted('Created "${created.metadata.title}"');
      });

  /// Renames a Note. The returned state carries the new concept id; when the
  /// renamed Note was open, it is adopted directly (before the selection is
  /// republished — see [_adopt]) so the editor never holds the dead id.
  Future<LifecycleOutcome> renameNote(String noteId, String newTitle) =>
      _guard(() async {
        final (state, effects) = await _api.renameNote(noteId, newTitle);
        _ref.invalidate(workspaceTreeProvider);
        await _settleEffects(
          invokedNoteId: noteId,
          returnedState: state,
          effects: effects,
        );
        return LifecycleCompleted('Renamed to "${state.metadata.title}"');
      });

  /// Moves a Note to another Directory. Same identity semantics as
  /// [renameNote]: the returned state carries the new id.
  Future<LifecycleOutcome> moveNote(
    String noteId,
    String newDirectoryPath,
  ) => _guard(() async {
    final (state, effects) = await _api.moveNote(noteId, newDirectoryPath);
    _ref.invalidate(workspaceTreeProvider);
    await _settleEffects(
      invokedNoteId: noteId,
      returnedState: state,
      effects: effects,
    );
    return LifecycleCompleted(
      'Moved to ${newDirectoryPath.isEmpty ? 'the workspace root' : newDirectoryPath}',
    );
  });

  /// Deletes a Note after the caller has confirmed with the user. When the
  /// deleted Note was the open one, the editor closes it instead of keeping
  /// it mounted against a removed file.
  Future<LifecycleOutcome> deleteNote(String noteId) => _guard(() async {
    await _api.deleteNote(noteId);
    _ref.invalidate(workspaceTreeProvider);
    _closeIfOpen(noteId);
    return const LifecycleCompleted('Deleted');
  });

  /// Creates a Directory, intermediate levels included.
  Future<LifecycleOutcome> createDirectory(String path) => _guard(() async {
    await _api.createDirectory(path);
    _ref.invalidate(workspaceTreeProvider);
    return LifecycleCompleted('Created directory $path');
  });

  /// Renames a Directory. Every Note beneath it gets a new concept id; an
  /// open one re-anchors through `effects.remapped`, and open Notes anywhere
  /// in the bundle that held inbound Links into the subtree reload through
  /// `effects.rewritten`.
  Future<LifecycleOutcome> renameDirectory(String path, String newName) =>
      _guard(() async {
        final effects = await _api.renameDirectory(path, newName);
        _ref.invalidate(workspaceTreeProvider);
        await _settleEffects(invokedNoteId: null, effects: effects);
        return LifecycleCompleted('Renamed to "$newName"');
      });

  /// Deletes a Directory and everything beneath it, after the caller has
  /// confirmed with the user. The Core returns every removed Note's concept
  /// id precisely so a caller holding one open can close it.
  Future<LifecycleOutcome> deleteDirectory(String path) => _guard(() async {
    final removed = await _api.deleteDirectory(path);
    _ref.invalidate(workspaceTreeProvider);
    for (final noteId in removed) {
      _closeIfOpen(noteId);
    }
    return const LifecycleCompleted('Deleted directory');
  });

  // -- internals ------------------------------------------------------------

  /// Runs `action`, translating what the Core threw into the outcome shapes:
  /// `PathUnavailable` becomes [LifecycleRefused] carrying the Core's own
  /// message — reported to the user verbatim, never retried client-side with
  /// a disambiguated name (the STOP condition) — and everything else becomes
  /// [LifecycleFailed] so no boundary error is swallowed.
  Future<LifecycleOutcome> _guard(
    Future<LifecycleOutcome> Function() action,
  ) async {
    try {
      return await action();
    } on AppError catch (error) {
      return switch (error) {
        AppError_PathUnavailable(:final field0) => LifecycleRefused(
          'That name cannot be used: $field0',
        ),
        _ => LifecycleFailed(error),
      };
    } catch (error) {
      return LifecycleFailed(error);
    }
  }

  /// Discharges the contract's caller-side obligations after an operation
  /// that may have changed other Notes besides the invoked one.
  ///
  /// Order is load-bearing when the invoked Note itself was open: the new
  /// state is adopted into [activeNoteProvider] *before* the new id is
  /// published through the selection seam, because the shell's selection
  /// listener drives [NoteController.open], whose already-open fast path
  /// requires the active state to carry the requested id. Publishing first
  /// would send `open` off to close the old — now dead — identifier.
  Future<void> _settleEffects({
    required String? invokedNoteId,
    NoteState? returnedState,
    required LifecycleEffects effects,
  }) async {
    final activeId = _ref.read(activeNoteProvider)?.metadata.id;

    if (returnedState != null &&
        invokedNoteId != null &&
        activeId == invokedNoteId) {
      _ref.read(activeNoteProvider.notifier).adopt(returnedState);
      _ref
          .read(selectedNoteIdProvider.notifier)
          .select(returnedState.metadata.id);
    } else if (activeId != null) {
      // A directory operation remapped the open Note onto a new id. Its
      // Core session was carried forward under that id, so fetching the
      // live state is a plain read — not a close/reopen of a dead id.
      for (final remap in effects.remapped) {
        if (remap.oldId != activeId) continue;
        _ref
            .read(activeNoteProvider.notifier)
            .adopt(await _api.openNote(remap.newId));
        _ref.read(selectedNoteIdProvider.notifier).select(remap.newId);
        break;
      }
    }

    // Rewritten Notes: same id, different bytes underneath the editor. A
    // fresh fetch hands back the session's post-rewrite AST, and replacing
    // the provider state rebuilds the editor, resyncing any focused
    // editable field before the next keystroke substitutes stale source
    // back through update_block.
    final openAfter = _ref.read(activeNoteProvider)?.metadata.id;
    if (openAfter != null && effects.rewritten.contains(openAfter)) {
      _ref
          .read(activeNoteProvider.notifier)
          .adopt(await _api.openNote(openAfter));
    }
  }

  /// Closes `noteId` in the editor if it is the open one: clears both the
  /// active-note state and the selection. No `close_note` crosses the
  /// boundary — the deletion already discarded the session Core-side, and
  /// addressing it again would only raise `NotFound`.
  void _closeIfOpen(String noteId) {
    final active = _ref.read(activeNoteProvider);
    if (active == null || active.metadata.id != noteId) return;
    _ref.read(activeNoteProvider.notifier).clear();
    _ref.read(selectedNoteIdProvider.notifier).clear();
  }
}

final lifecycleActionsProvider = Provider<LifecycleActions>(
  (ref) => LifecycleActions(ref),
);
