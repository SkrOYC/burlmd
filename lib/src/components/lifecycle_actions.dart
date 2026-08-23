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
  const LifecycleCompleted(this.detail, {this.warning});

  final String detail;
  final LifecycleWarning? warning;
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
  LifecycleActions(this._ref);

  final Ref _ref;

  /// The tail of the presentation-side lifecycle queue.
  ///
  /// Core serializes its own mutations, but Presentation also owns the
  /// returned-state adoption which rekeys the active editor and reloads
  /// rewritten Notes. Starting a second action while the first is awaiting
  /// that adoption used to advance its generation early, turning the first
  /// action's authoritative result into a no-op. Keep one action admitted at
  /// a time so Core completion order and presentation settlement order are
  /// identical.
  Future<void>? _pendingAction;

  RustApi get _api => _ref.read(rustApiProvider);

  /// Creates a Note in `directoryPath` (empty string for the bundle root).
  /// The Core creates the file **and opens it**, so the returned state is an
  /// open Note; publishing its id through the selection seam routes the shell
  /// through the ordinary open path, which first closes any outgoing Note
  /// through the commit tier and then adopts the already-open created session
  /// (`open_note`'s fast path) — "opens for editing" without a second open.
  Future<LifecycleOutcome> createNote(String directoryPath, String title) =>
      _guard((operation) async {
        final result = await _api.createNote(directoryPath, title);
        final created = _requiredState(result, 'create');
        _ref.invalidate(workspaceTreeProvider);
        await _settleCreatedNote(operation, created);
        return LifecycleCompleted(
          'Created "${created.metadata.title}"',
          // The warning belongs to this completed Core operation, rather
          // than to whichever Note won a later navigation race. Returning it
          // even when the created session could not be adopted lets the
          // initiating surface report it exactly once.
          warning: result.warning,
        );
      });

  /// Creates the exact Core-resolved target for create-on-follow and waits
  /// for the created session to become the active editor Note before returning
  /// its terminal warning to the link surface.
  Future<LifecycleOutcome> createLinkTarget(String targetId) =>
      _guard((operation) async {
        final result = await _api.createLinkTarget(targetId);
        final created = _requiredState(result, 'create linked note');
        _ref.invalidate(workspaceTreeProvider);
        await _settleCreatedNote(operation, created);
        return LifecycleCompleted(
          'Created "${created.metadata.title}"',
          warning: result.warning,
        );
      });

  /// Renames a Note. The returned state carries the new concept id; when the
  /// renamed Note was open, it is adopted directly (before the selection is
  /// republished — see [_adopt]) so the editor never holds the dead id.
  Future<LifecycleOutcome> renameNote(String noteId, String newTitle) =>
      _guard((operation) async {
        final result = await _api.renameNote(noteId, newTitle);
        final state = _requiredState(result, 'rename');
        _ref.invalidate(workspaceTreeProvider);
        await _settleEffects(
          invokedNoteId: noteId,
          returnedState: state,
          effects: result.effects,
          operation: operation,
        );
        return LifecycleCompleted(
          'Renamed to "${state.metadata.title}"',
          warning: result.warning,
        );
      });

  /// Moves a Note to another Directory. Same identity semantics as
  /// [renameNote]: the returned state carries the new id.
  Future<LifecycleOutcome> moveNote(
    String noteId,
    String newDirectoryPath,
  ) => _guard((operation) async {
    final result = await _api.moveNote(noteId, newDirectoryPath);
    final state = _requiredState(result, 'move');
    _ref.invalidate(workspaceTreeProvider);
    await _settleEffects(
      invokedNoteId: noteId,
      returnedState: state,
      effects: result.effects,
      operation: operation,
    );
    return LifecycleCompleted(
      'Moved to ${newDirectoryPath.isEmpty ? 'the workspace root' : newDirectoryPath}',
      warning: result.warning,
    );
  });

  /// Deletes a Note after the caller has confirmed with the user. When the
  /// deleted Note was the open one, the editor closes it instead of keeping
  /// it mounted against a removed file.
  Future<LifecycleOutcome> deleteNote(String noteId) =>
      _guard((operation) async {
        final result = await _api.deleteNote(noteId);
        _ref.invalidate(workspaceTreeProvider);
        if (!_isExpectedSession(
          operation,
          operation.active,
          operation.selectedId,
        )) {
          return LifecycleCompleted('Deleted', warning: result.warning);
        }
        for (final removed in result.removed) {
          _closeIfOpen(removed);
        }
        return LifecycleCompleted('Deleted', warning: result.warning);
      });

  /// Creates a Directory, intermediate levels included.
  Future<LifecycleOutcome> createDirectory(String path) => _guard((_) async {
    final result = await _api.createDirectory(path);
    _ref.invalidate(workspaceTreeProvider);
    return LifecycleCompleted(
      'Created directory $path',
      warning: result.warning,
    );
  });

  /// Renames a Directory. Every Note beneath it gets a new concept id; an
  /// open one re-anchors through `effects.remapped`, and open Notes anywhere
  /// in the bundle that held inbound Links into the subtree reload through
  /// `effects.rewritten`.
  Future<LifecycleOutcome> renameDirectory(String path, String newName) =>
      _guard((operation) async {
        final result = await _api.renameDirectory(path, newName);
        _ref.invalidate(workspaceTreeProvider);
        await _settleEffects(
          invokedNoteId: null,
          effects: result.effects,
          operation: operation,
        );
        return LifecycleCompleted(
          'Renamed to "$newName"',
          warning: result.warning,
        );
      });

  /// Deletes a Directory and everything beneath it, after the caller has
  /// confirmed with the user. The Core returns every removed Note's concept
  /// id precisely so a caller holding one open can close it.
  Future<LifecycleOutcome> deleteDirectory(String path) => _guard((
    operation,
  ) async {
    final result = await _api.deleteDirectory(path);
    _ref.invalidate(workspaceTreeProvider);
    if (!_isExpectedSession(
      operation,
      operation.active,
      operation.selectedId,
    )) {
      return LifecycleCompleted('Deleted directory', warning: result.warning);
    }
    for (final noteId in result.removed) {
      _closeIfOpen(noteId);
    }
    return LifecycleCompleted('Deleted directory', warning: result.warning);
  });

  // -- internals ------------------------------------------------------------

  NoteState _requiredState(LifecycleResult result, String operation) {
    final state = result.state;
    if (state != null) return state;
    throw StateError(
      'Core $operation result omitted its authoritative Note state.',
    );
  }

  /// Settles a Core-created session before Presentation treats creation as
  /// complete. Selection stays on the prior Note while [openForLifecycle]
  /// runs, avoiding the normal listener's fire-and-forget open path. A newer
  /// lifecycle generation or user selection wins without this create
  /// replacing it or reporting its terminal warning.
  Future<bool> _settleCreatedNote(
    _LifecycleOperation operation,
    NoteState created,
  ) async {
    if (!_isExpectedSession(
      operation,
      operation.active,
      operation.selectedId,
    )) {
      await _retireUnadoptedCreatedSession(created.metadata.id);
      return false;
    }
    final opened = await _ref
        .read(activeNoteProvider.notifier)
        .openForLifecycle(created.metadata.id);
    if (!_isCurrentOperation(operation) ||
        _ref.read(selectedNoteIdProvider) != operation.selectedId) {
      await _retireUnadoptedCreatedSession(created.metadata.id);
      return false;
    }
    if (!opened) {
      await _retireUnadoptedCreatedSession(created.metadata.id);
      throw StateError(
        'Core could not open the Note it created for this lifecycle action.',
      );
    }
    _ref.read(selectedNoteIdProvider.notifier).select(created.metadata.id);
    return true;
  }

  /// `create_note` and `create_link_target` open a Core session before
  /// returning it. When a stale request cannot publish that session as the
  /// active editor Note, it must still be retired through tier 3; otherwise
  /// an invisible session survives without a later navigation path to close
  /// it. A terminal close warning is intentionally non-fatal: Core has
  /// already retired the session, so retrying here would address a dead id.
  Future<void> _retireUnadoptedCreatedSession(String noteId) async {
    try {
      await _api.closeNote(noteId);
    } on CloseNoteWarning catch (warning) {
      // The create result retains its own lifecycle warning, while this
      // independently terminal close warning uses the existing one-shot
      // status seam. Its listener acknowledges before displaying, so a stale
      // create cannot leak a session or replay this warning on a rebuild.
      _ref.read(noteCloseFailureProvider.notifier).report(warning);
    }
  }

  bool _isCurrentOperation(_LifecycleOperation operation) =>
      _ref.mounted &&
      _ref.read(lifecycleGenerationProvider) == operation.generation;

  /// Runs `action`, translating what the Core threw into the outcome shapes:
  /// `PathUnavailable` becomes [LifecycleRefused] carrying the Core's own
  /// message — reported to the user verbatim, never retried client-side with
  /// a disambiguated name (the STOP condition) — and everything else becomes
  /// [LifecycleFailed] so no boundary error is swallowed.
  Future<LifecycleOutcome> _guard(
    Future<LifecycleOutcome> Function(_LifecycleOperation operation) action,
  ) {
    final editing = _ref.read(lifecycleEditingProvider.notifier);
    // Reserve the shared gate at submission time, including while this
    // request waits behind an admitted action. That blocks both editing and
    // sidebar navigation from racing an old-id rekey. The generation is
    // deliberately allocated only when the request reaches the queue head:
    // a queued future must not invalidate the action still settling ahead of
    // it.
    editing.begin();
    final previous = _pendingAction;
    final Future<LifecycleOutcome> queued;
    late final Future<void> tail;
    // Preserve the synchronous admission of the queue head: FFI calls start
    // immediately after the gate closes, while later requests defer both
    // their generation and their Core call until the predecessor settles.
    queued = previous == null
        ? _runQueuedAction(action, editing)
        : previous.then((_) => _runQueuedAction(action, editing));
    tail = queued.then<void>((_) {}, onError: (_, _) {});
    _pendingAction = tail;
    tail.whenComplete(() {
      if (identical(_pendingAction, tail)) _pendingAction = null;
    });
    return queued;
  }

  Future<LifecycleOutcome> _runQueuedAction(
    Future<LifecycleOutcome> Function(_LifecycleOperation operation) action,
    LifecycleEditing editing,
  ) async {
    try {
      if (!_ref.mounted) {
        return LifecycleFailed(
          StateError('Lifecycle action outlived its ProviderContainer.'),
        );
      }
      final operation = _LifecycleOperation(
        generation: _ref.read(lifecycleGenerationProvider.notifier).next(),
        active: _ref.read(activeNoteProvider),
        selectedId: _ref.read(selectedNoteIdProvider),
      );
      try {
        return await action(operation);
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
    } finally {
      // An outstanding FFI Future may settle after its ProviderContainer has
      // been disposed. The gate belongs to that container, so do not write a
      // retired notifier while unwinding its operation.
      if (_ref.mounted) editing.end();
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
    required _LifecycleOperation operation,
  }) async {
    if (!_isExpectedSession(
      operation,
      operation.active,
      operation.selectedId,
    )) {
      return;
    }
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
        final reanchored = await _openForExpectedSession(
          operation,
          expectedActive: operation.active,
          expectedSelectedId: operation.selectedId,
          noteId: remap.newId,
        );
        if (reanchored == null) return;
        _ref.read(activeNoteProvider.notifier).adopt(reanchored);
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
      final expectedActive = _ref.read(activeNoteProvider);
      final expectedSelectedId = _ref.read(selectedNoteIdProvider);
      final rewritten = await _openForExpectedSession(
        operation,
        expectedActive: expectedActive,
        expectedSelectedId: expectedSelectedId,
        noteId: openAfter,
      );
      if (rewritten == null) return;
      _ref.read(activeNoteProvider.notifier).adopt(rewritten);
    }
  }

  /// An awaited post-lifecycle fetch may not outlive the operation and
  /// session it was issued for. Stale success and stale failure both become
  /// no-ops; neither may resurrect a removed Note nor obscure a newer action.
  Future<NoteState?> _openForExpectedSession(
    _LifecycleOperation operation, {
    required NoteState? expectedActive,
    required String? expectedSelectedId,
    required String noteId,
  }) async {
    if (!_isExpectedSession(operation, expectedActive, expectedSelectedId)) {
      return null;
    }
    try {
      final opened = await _api.openNote(noteId);
      return _isExpectedSession(operation, expectedActive, expectedSelectedId)
          ? opened
          : null;
    } catch (_) {
      if (!_isExpectedSession(operation, expectedActive, expectedSelectedId)) {
        return null;
      }
      rethrow;
    }
  }

  bool _isExpectedSession(
    _LifecycleOperation operation,
    NoteState? expectedActive,
    String? expectedSelectedId,
  ) =>
      _ref.mounted &&
      _ref.read(lifecycleGenerationProvider) == operation.generation &&
      identical(_ref.read(activeNoteProvider), expectedActive) &&
      _ref.read(selectedNoteIdProvider) == expectedSelectedId;

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

class _LifecycleOperation {
  const _LifecycleOperation({
    required this.generation,
    required this.active,
    required this.selectedId,
  });

  final int generation;
  final NoteState? active;
  final String? selectedId;
}
