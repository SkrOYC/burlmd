import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The last fatal failure the Core returned while opening an active Note, or
/// `null` when the last fatal operation succeeded. `SHEL-E004`'s error
/// surface watches this rather than silently ignoring an unopenable Note.
final editorErrorProvider = NotifierProvider<EditorError, Object?>(
  EditorError.new,
);

/// Holds [editorErrorProvider]'s value. A plain mutable slot: whoever last
/// talked to the Core reports what came back.
class EditorError extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object? error) => state = error;
}

/// A one-shot close status for a Note switch.
///
/// A true refusal leaves the old Core session valid and retryable; a
/// [CloseNoteWarning] says Core already retired it after a safe write but
/// could not finish post-close bookkeeping. [Editor] acknowledges either
/// through its dismissible status message, preventing stale errors on later
/// rebuilds.
final noteCloseFailureProvider = NotifierProvider<NoteCloseFailure, Object?>(
  NoteCloseFailure.new,
);

class NoteCloseFailure extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object error) => state = error;

  void acknowledge() => state = null;
}

/// The last refused per-keystroke write (`update_block`, ADR-008 tier 1), or
/// `null` when the latest keystroke went through. Deliberately **not**
/// [editorErrorProvider]: flow-edit-note.md requires that a failed keystroke
/// write leaves the draft row — and the rendered text the user is typing —
/// exactly where they are, with the failure surfaced beside the content, not
/// instead of it. Replacing the whole Note view here would blank the very
/// buffer the user is mid-keystroke into because of a transient write hiccup.
///
/// Core cannot carry this one: its `note_write_status.lastError` records
/// tier-2 file-write failures only; a failed tier-1 draft-row write returns
/// an error across the boundary without recording it there. So the Dart side
/// surfaces it directly through the same surface state [WriteTierNotice]
/// watches above the editor.
final keystrokeWriteFailureProvider =
    NotifierProvider<KeystrokeWriteFailure, Object?>(KeystrokeWriteFailure.new);

/// Holds [keystrokeWriteFailureProvider]'s value.
class KeystrokeWriteFailure extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object? error) => state = error;
}

/// Whether the outgoing Note is closing before its replacement opens.
///
/// The old state remains available solely so a true close refusal can restore
/// that session, but it no longer grants edit authority once switching begins.
final noteSwitchingProvider = NotifierProvider<NoteSwitching, bool>(
  NoteSwitching.new,
);

class NoteSwitching extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool switching) => state = switching;
}

/// Number of disk reloads that currently own the active Note's source.
///
/// `reload_note` replaces the working source and clears its draft row. Its
/// admission must therefore cover the full FFI round trip, not merely the
/// synchronous check before it starts: a write accepted in that gap could be
/// persisted and then silently replaced by the returned disk state. This is a
/// count rather than a boolean so every admitted owner must release only its
/// own hold.
final reloadEditingProvider = NotifierProvider<ReloadEditing, int>(
  ReloadEditing.new,
);

class ReloadEditing extends Notifier<int> {
  @override
  int build() => 0;

  void begin() => state++;

  void end() {
    assert(state > 0, 'Reload editing gate released without an owner.');
    if (state > 0) state--;
  }
}

/// Number of Core lifecycle operations currently able to replace, re-anchor,
/// rewrite, or remove a Note. It is a count rather than a boolean because a
/// second action can legitimately be submitted while the first is settling;
/// releasing one must not reopen the editor while the other still owns the
/// Core lifecycle boundary.
final lifecycleEditingProvider = NotifierProvider<LifecycleEditing, int>(
  LifecycleEditing.new,
);

/// Advances as a lifecycle action reaches the serialized queue head. Async
/// lifecycle consumers capture it before their own FFI call; the next action
/// invalidates that capture once it becomes authoritative.
final lifecycleGenerationProvider = NotifierProvider<LifecycleGeneration, int>(
  LifecycleGeneration.new,
);

/// Advances at lifecycle admission, before an action waits for an ordinary
/// note switch already in flight. This is distinct from the lifecycle action
/// generation: queued lifecycle work must fence ordinary opens immediately
/// without invalidating the action currently settling ahead of it.
final lifecycleAdmissionProvider = NotifierProvider<LifecycleAdmission, int>(
  LifecycleAdmission.new,
);

class LifecycleGeneration extends Notifier<int> {
  @override
  int build() => 0;

  int next() => state = state + 1;
}

class LifecycleAdmission extends Notifier<int> {
  @override
  int build() => 0;

  int next() => state = state + 1;
}

class LifecycleEditing extends Notifier<int> {
  @override
  int build() => 0;

  void begin() => state++;

  void end() {
    assert(state > 0, 'Lifecycle editing gate released without an owner.');
    if (state > 0) state--;
  }
}

/// The one synchronous provider transition during which [activeNoteProvider]
/// is carrying the *same* Core session to a new concept id.
///
/// The lifecycle gate says that a lifecycle action is in flight; it does not
/// say that the Note replacing the current editor is a rekey of that session.
/// Creation and lifecycle-admitted recovery also replace the active Note while
/// the gate is held. [LifecycleActions] therefore publishes this identity pair
/// immediately before its authoritative re-anchor adoption and clears it
/// immediately afterwards. Consumers must match all three values while
/// handling that provider transition; the token is never navigation state.
class LifecycleFocusRemap {
  const LifecycleFocusRemap({
    required this.generation,
    required this.oldId,
    required this.newId,
  });

  final int generation;
  final String oldId;
  final String newId;

  bool matches({
    required int generation,
    required String oldId,
    required String newId,
  }) =>
      this.generation == generation &&
      this.oldId == oldId &&
      this.newId == newId;
}

/// Ephemeral proof that an active-Note identity change is a lifecycle rekey.
final lifecycleFocusRemapProvider =
    NotifierProvider<LifecycleFocusRemapSignal, LifecycleFocusRemap?>(
      LifecycleFocusRemapSignal.new,
    );

class LifecycleFocusRemapSignal extends Notifier<LifecycleFocusRemap?> {
  @override
  LifecycleFocusRemap? build() => null;

  void publish(LifecycleFocusRemap remap) => state = remap;

  void clear() => state = null;
}

/// The single presentation-side admission rule for every editor mutation.
/// A Note switch retires its outgoing session, while lifecycle work can
/// atomically rewrite, re-anchor, or delete its current source. In either
/// case an input callback arriving between frames must neither reach Core nor
/// remain only in a controller that the authoritative lifecycle result will
/// replace. A disk reload has the same replacement authority for its entire
/// round trip, so it closes this gate before issuing `reload_note`.
final editorInputBlockedProvider = Provider<bool>(
  (ref) =>
      ref.watch(noteSwitchingProvider) ||
      ref.watch(reloadEditingProvider) > 0 ||
      ref.watch(lifecycleEditingProvider) > 0 ||
      ref.watch(rescanEditingProvider) > 0,
);

/// The Core-owned Note sessions represented by tabs. A [NoteState] enters
/// this list only after Core returns it; a snapshot identity never becomes a
/// writable Dart session by itself.
class OpenNoteSessions extends Notifier<List<NoteState>> {
  @override
  List<NoteState> build() => const [];

  NoteState? byId(String noteId) {
    for (final note in state) {
      if (note.metadata.id == noteId) return note;
    }
    return null;
  }

  void replaceAll(List<NoteState> notes) => state = List.unmodifiable(notes);

  void upsert(NoteState note, {String? replacedId}) {
    final id = replacedId ?? note.metadata.id;
    final index = state.indexWhere((candidate) => candidate.metadata.id == id);
    if (index == -1) {
      state = List.unmodifiable([...state, note]);
      return;
    }
    final next = List<NoteState>.of(state)..[index] = note;
    state = List.unmodifiable(next);
  }

  void remove(String noteId) => state = List.unmodifiable(
    state.where((candidate) => candidate.metadata.id != noteId),
  );
}

final openNoteSessionsProvider =
    NotifierProvider<OpenNoteSessions, List<NoteState>>(OpenNoteSessions.new);

/// Holds the active Note state. Tab sessions remain separately in
/// [openNoteSessionsProvider] until their own Core close completes.
class NoteController extends Notifier<NoteState?> {
  @override
  NoteState? build() => null;

  /// Opens the Note addressed by `noteId`, its OKF concept id — not a
  /// filesystem path. `open_note` is `async` at the FFI boundary now
  /// (`WSPC-D008`), so this awaits it rather than assigning synchronously.
  ///
  /// Switching Notes closes the outgoing one through the Core **first**
  /// (`SHEL-E004`'s STOP condition): `close_note` runs tier 3 — flush,
  /// session commit, draft-row clear — so skipping it on a switch would
  /// leave the outgoing session uncommitted and absent from version
  /// history. A close refusal aborts the switch: opening the new Note on top
  /// of an uncommitted session would bury the failure. A post-close warning
  /// is different — its session is gone after a safe write, so switching must
  /// continue and surface the warning nonfatally. On a refusal,
  /// [selectedNoteIdProvider] is rolled back to the Note that is still open,
  /// so the tree highlight never names a Note the Core refused to reach — and
  /// the listener it fires re-enters this method only to hit the already-open
  /// fast path below, leaving the reported failure up.
  ///
  /// Calls are serialized through [_pendingOpen]: `open` reads `state` to
  /// decide whether a close is owed, but assigns `state` only after an FFI
  /// round trip, so two rapid selections racing on the unawaited gap could
  /// each see the same stale outgoing Note — the second would skip the
  /// first's close (losing its commit tier) and the provider could settle
  /// on whichever round trip resolved last rather than the selection the
  /// user actually made last. Chaining every request behind the previous
  /// one makes close/open strictly sequential; a ticket overtaken by a
  /// newer selection ([_openRequests]) returns without acting at all, so
  /// intermediate notes are neither closed nor opened redundantly.
  Future<void> open(String noteId) => _open(noteId);

  /// Opens or selects a tab session without closing the current tab. The shell
  /// uses this instead of [open]'s legacy close-before-open lifecycle path;
  /// only a Core-returned state is admitted to [openNoteSessionsProvider].
  Future<void> openAsTab(String noteId) async {
    if (ref.read(noteSelectionBlockedProvider)) return;
    final sessions = ref.read(openNoteSessionsProvider.notifier);
    final current = state;
    if (current?.metadata.id == noteId) {
      sessions.upsert(current!);
      final snapshot = ref.read(workspaceSessionProvider.notifier);
      snapshot.addOpenNoteId(noteId);
      snapshot.setActiveNoteId(noteId);
      return;
    }
    final existing = sessions.byId(noteId);
    if (existing != null) {
      state = existing;
      ref.read(workspaceSessionProvider.notifier).setActiveNoteId(noteId);
      ref.read(editorErrorProvider.notifier).report(null);
      ref.read(noteCloseFailureProvider.notifier).acknowledge();
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
      return;
    }

    final admission = ref.read(lifecycleAdmissionProvider);
    try {
      final opened = await ref.read(rustApiProvider).openNote(noteId);
      if (!_isOpenAdmissionCurrent(admission, admittedByLifecycle: false)) {
        return;
      }
      sessions.upsert(opened);
      state = opened;
      final snapshot = ref.read(workspaceSessionProvider.notifier);
      snapshot.addOpenNoteId(opened.metadata.id);
      snapshot.setActiveNoteId(opened.metadata.id);
      ref.read(editorErrorProvider.notifier).report(null);
      ref.read(noteCloseFailureProvider.notifier).acknowledge();
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    } catch (error) {
      // Leave the current session untouched. A selected unavailable id is
      // retryable, but it never gets a presentation-created tab or buffer.
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  /// Reopens all snapshot identities one by one through Core. Failed ids are
  /// collected for the screen's single report while later ids still restore.
  Future<List<String>> restoreOpenNotes({
    required Iterable<String> openNoteIds,
    required String? activeNoteId,
  }) async {
    final ids = <String>[];
    final seen = <String>{};
    for (final noteId in [...openNoteIds, ?activeNoteId]) {
      if (seen.add(noteId)) ids.add(noteId);
    }
    final restored = <NoteState>[];
    final unavailable = <String>[];
    final api = ref.read(rustApiProvider);
    for (final noteId in ids) {
      try {
        restored.add(await api.openNote(noteId));
      } catch (_) {
        unavailable.add(noteId);
      }
    }
    if (!ref.mounted) return unavailable;

    ref.read(openNoteSessionsProvider.notifier).replaceAll(restored);
    NoteState? active;
    for (final note in restored) {
      if (note.metadata.id == activeNoteId) {
        active = note;
        break;
      }
    }
    active ??= restored.isEmpty ? null : restored.first;
    state = active;
    ref
        .read(workspaceSessionProvider.notifier)
        .replaceOpenNotes(
          openNoteIds: restored.map((note) => note.metadata.id).toList(),
          activeNoteId: active?.metadata.id,
        );
    ref.read(editorErrorProvider.notifier).report(null);
    ref.read(noteCloseFailureProvider.notifier).acknowledge();
    ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    return unavailable;
  }

  /// Retires one known Core session. Batch close orchestration belongs to the
  /// following CLOSE-G005 ticket; this only handles the individual tab.
  Future<bool> closeTab(String noteId) async {
    if (ref.read(openNoteSessionsProvider.notifier).byId(noteId) == null) {
      return false;
    }
    try {
      await ref.read(rustApiProvider).closeNote(noteId);
    } on CloseNoteWarning catch (warning) {
      ref.read(noteCloseFailureProvider.notifier).report(warning);
    } catch (error) {
      ref.read(noteCloseFailureProvider.notifier).report(error);
      return false;
    }
    ref.read(openNoteSessionsProvider.notifier).remove(noteId);
    ref.read(workspaceSessionProvider.notifier).removeOpenNoteId(noteId);
    if (state?.metadata.id == noteId) {
      state = null;
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    }
    return true;
  }

  Future<void> _open(String noteId, {bool admittedByLifecycle = false}) {
    final ticket = ++_openRequests;
    final previous = _pendingOpen ?? Future<void>.value();
    late final Future<void> mine;
    mine = () async {
      await previous;
      try {
        await _openExclusive(
          ticket,
          noteId,
          admittedByLifecycle: admittedByLifecycle,
        );
      } finally {
        // Drop the chain once the tail catches up so completed work can be
        // collected instead of growing an unbounded await chain.
        if (identical(_pendingOpen, mine)) _pendingOpen = null;
      }
    }();
    _pendingOpen = mine;
    return mine;
  }

  /// Opens a lifecycle-created Note and waits until its Core session is the
  /// active editor session. Unlike ordinary selection, this does not publish
  /// [selectedNoteIdProvider] first: publishing alone starts an unawaited
  /// listener-driven switch, so a lifecycle warning could otherwise surface
  /// before the authoritative Note is mounted. The caller publishes the
  /// selection only after this method reports success.
  Future<bool> openForLifecycle(String noteId) async {
    await _open(noteId, admittedByLifecycle: true);
    return ref.mounted && state?.metadata.id == noteId;
  }

  /// Waits for the selection chain that was already admitted to settle.
  /// Lifecycle actions call this after fencing ordinary open outcomes and
  /// before snapshotting the active Note for an identity-changing operation.
  Future<void> settlePendingOpen() => _pendingOpen ?? Future<void>.value();

  /// The tail of the serialized [open] chain, or `null` when no switch is
  /// in flight or queued. Every request awaits this before touching the
  /// Core, which is what makes close-before-open orderable.
  Future<void>? _pendingOpen;

  /// Monotonic count of [open] requests. A queued request whose ticket no
  /// longer equals the newest one was superseded while waiting and must do
  /// nothing.
  int _openRequests = 0;

  Future<void> _openExclusive(
    int ticket,
    String noteId, {
    required bool admittedByLifecycle,
  }) async {
    // A newer selection arrived while this one sat in the queue: skip it
    // entirely rather than churning closes/opens for Notes the user has
    // already navigated past.
    if (ticket != _openRequests) return;
    if (!admittedByLifecycle && ref.read(noteSelectionBlockedProvider)) {
      return;
    }
    final lifecycleAdmission = ref.read(lifecycleAdmissionProvider);
    final api = ref.read(rustApiProvider);
    final current = state;
    if (current != null && current.metadata.id == noteId) {
      // Already the open Note. Most commonly the rollback path above:
      // re-running the open would succeed and clear the error surface
      // explaining why the aborted switch failed, so treat it as done.
      return;
    }
    var switching = false;
    var closedWithWarning = false;
    try {
      if (current != null) {
        // Revoke the old editor before awaiting the close. The old provider
        // value remains only to restore it when this close itself refuses.
        // Every return after this point remains inside this transaction's
        // cleanup boundary: lifecycle admission can change while closeNote is
        // delayed, and must never leave editor input permanently blocked.
        switching = true;
        ref.read(noteSwitchingProvider.notifier).set(true);
        try {
          await api.closeNote(current.metadata.id);
        } catch (error) {
          if (error is CloseNoteWarning) {
            // Core retired the outgoing session after the bytes were safe, but
            // could not finish commit or draft cleanup. Continue to the selected
            // Note: restoring `current` here would make its raw editor writable
            // against a deregistered session. The Editor consumes this one-shot
            // warning through the same dismissible status surface as a refusal.
            closedWithWarning = true;
            ref.read(editorErrorProvider.notifier).report(null);
            ref.read(noteCloseFailureProvider.notifier).report(error);
          } else {
            // Closing refused, so the old session remains Core-valid and can be
            // edited again. It is a nonfatal one-shot outcome, not the persistent
            // no-session error panel used for a failed open.
            ref.read(editorErrorProvider.notifier).report(null);
            ref.read(noteCloseFailureProvider.notifier).report(error);
            // The switch aborts with the old Note still open; point the tree
            // back at it so the selection highlight matches what the editor
            // actually shows. The error stays surfaced above.
            _restoreSelection(current.metadata.id, admittedByLifecycle);
            return;
          }
        }
        // Core has retired the outgoing session. Until a replacement reaches
        // Core successfully, no active identity is persisted.
        ref.read(workspaceSessionProvider.notifier).setActiveNoteId(null);
        if (!_isOpenAdmissionCurrent(
          lifecycleAdmission,
          admittedByLifecycle: admittedByLifecycle,
        )) {
          // Core accepted the close, but lifecycle work claimed the replacement
          // boundary while it was pending. This snapshot names a retired
          // session, so do not retain it or continue into the selected id.
          state = null;
          ref.read(keystrokeWriteFailureProvider.notifier).report(null);
          return;
        }
      }
      final opened = await api.openNote(noteId);
      if (!_isOpenAdmissionCurrent(
        lifecycleAdmission,
        admittedByLifecycle: admittedByLifecycle,
      )) {
        // Lifecycle work may have deleted, renamed, or rekeyed this target
        // while `open_note` was in flight. Its stale success cannot mount it.
        if (switching) state = null;
        return;
      }
      state = opened;
      // The snapshot records an identity only after Core has actually opened
      // it. It does not create or stand in for this Note session.
      ref
          .read(workspaceSessionProvider.notifier)
          .setActiveNoteId(opened.metadata.id);
      // A successful open clears any earlier failure so the surface
      // reflects the present, not the last thing that went wrong — both
      // surfaces: the old Note's keystroke-write failure belongs to a
      // session that just ended.
      ref.read(editorErrorProvider.notifier).report(null);
      // Keep a post-close warning available for the Editor's dismissible
      // status even though opening the next Note succeeded. A clean close or
      // a first open should clear stale refusal status as before.
      if (!closedWithWarning) {
        ref.read(noteCloseFailureProvider.notifier).acknowledge();
      }
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
      // A failed first open has no session to clean up. After a successful
      // outgoing close, however, the old provider snapshot names a session
      // Core already deregistered and must be cleared rather than restored.
      if (switching) {
        // The outgoing close completed, so retaining its old state as a live
        // editor would target a deregistered Core session.
        state = null;
        ref.read(keystrokeWriteFailureProvider.notifier).report(null);
      } else {
        final stillOpen = state?.metadata.id;
        if (stillOpen != null) {
          _restoreSelection(stillOpen, admittedByLifecycle);
        }
      }
    } finally {
      if (switching) ref.read(noteSwitchingProvider.notifier).set(false);
    }
  }

  bool _isOpenAdmissionCurrent(
    int expectedAdmission, {
    required bool admittedByLifecycle,
  }) =>
      ref.mounted &&
      (admittedByLifecycle || !ref.read(noteSelectionBlockedProvider)) &&
      ref.read(lifecycleAdmissionProvider) == expectedAdmission;

  void _restoreSelection(String noteId, bool admittedByLifecycle) {
    final selection = ref.read(selectedNoteIdProvider.notifier);
    if (admittedByLifecycle) {
      selection.selectForLifecycle(noteId);
    } else {
      selection.select(noteId);
    }
  }

  /// The per-keystroke call (ADR-007 decision 4): buffers `source` — the
  /// Block's raw Markdown text, not an `AstNode` — into the Note's working
  /// source and writes the draft row. `update_block` no longer parses or
  /// returns a `NoteState`, so this does not reassign `state`; reflecting an
  /// edit back into the rendered AST on blur is `commit_block`'s job, which
  /// is `EDIT-F002` territory rather than this ticket's.
  ///
  /// A refusal does **not** reach [editorErrorProvider]. That surface replaces
  /// the Note view wholesale, and flow-edit-note.md forbids exactly that for a
  /// failed keystroke write: the draft row stays in place, the text stays on
  /// screen, and the failure is surfaced *beside* it. It is published through
  /// [keystrokeWriteFailureProvider] — which [WriteTierNotice] renders above
  /// the editor — instead. Only an open failure with no remaining session
  /// reaches [editorErrorProvider]; a close refusal has its retryable status
  /// surface. A subsequent keystroke that succeeds clears the notice, as do
  /// open/close/reload below. The boolean acknowledgement is intentionally
  /// returned to the raw field: only an accepted write may become that
  /// field's settled source or proceed to a structural reparse.
  bool updateBlock(List<int> blockPath, String source) {
    // A queued platform callback may arrive before the read-only rebuild
    // paints, so the shared editor admission state is the authority boundary.
    // Lifecycle work can replace this Note's source just as a switch can
    // retire its session; accepting a write in either window would leave a
    // controller-only edit for the next rebuild to discard.
    if (ref.read(editorInputBlockedProvider)) return false;
    final current = state;
    if (current == null) return false;
    try {
      ref
          .read(rustApiProvider)
          .updateBlock(current.metadata.id, blockPath, source);
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
      return true;
    } catch (error) {
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
      return false;
    }
  }

  /// Adopts `newState` as the open Note's state without any Core round trip
  /// (`SHEL-E005`). This is the re-anchor path for identity-changing
  /// lifecycle operations — rename, move, containing-directory rename: the
  /// Core carries the open session forward under the new concept id (working
  /// source, span map, recorded revision), so closing and reopening would
  /// address a dead identifier and fail. The returned post-operation state is
  /// authoritative; adopting it directly keeps the editor anchored to the
  /// same live session under its new id. Lifecycle re-anchors can supply
  /// [oldId] when the presentation state was cleared before Core returned
  /// the replacement identity.
  void adopt(NoteState newState, {String? oldId}) {
    final previousId = oldId ?? state?.metadata.id;
    state = newState;
    final tabSessions = ref.read(openNoteSessionsProvider.notifier);
    if (previousId != null && tabSessions.byId(previousId) != null) {
      tabSessions.upsert(newState, replacedId: previousId);
    }
    if (previousId != null && previousId != newState.metadata.id) {
      ref
          .read(workspaceSessionProvider.notifier)
          .rekeyOpenNoteId(
            oldNoteId: previousId,
            newNoteId: newState.metadata.id,
          );
    }
  }

  /// Closes the editor without touching the Core (`SHEL-E005`): the Note it
  /// was showing has been deleted, and the deletion already discarded the
  /// session and its draft row Core-side, so sending `close_note` would only
  /// raise `NotFound`. Used when a deletion removes the open Note.
  ///
  /// Also clears [editorErrorProvider]: the deleted Note can no longer be
  /// retried or inspected, so a failure panel left over from it would name
  /// an impossibility. This mirrors what a successful open does.
  void clear() {
    final noteId = state?.metadata.id;
    state = null;
    if (noteId != null &&
        ref.read(openNoteSessionsProvider.notifier).byId(noteId) != null) {
      ref.read(openNoteSessionsProvider.notifier).remove(noteId);
      ref.read(workspaceSessionProvider.notifier).removeOpenNoteId(noteId);
    } else {
      ref.read(workspaceSessionProvider.notifier).setActiveNoteId(null);
    }
    ref.read(noteSwitchingProvider.notifier).set(false);
    ref.read(editorErrorProvider.notifier).report(null);
    ref.read(noteCloseFailureProvider.notifier).acknowledge();
    ref.read(keystrokeWriteFailureProvider.notifier).report(null);
  }

  /// Reloads the currently open Note from disk through `reload_note`
  /// (`SHEL-E007`) — the only exit from a tier-2 `RevisionMismatch`.
  ///
  /// This is deliberately **not** [open]: `open_note` restores the surviving
  /// draft row in preference to disk, so reopening would hand back the very
  /// buffer that lost the revision comparison and reproduce the mismatch on
  /// the next write. `reload_note` destroys unwritten work by design, so the
  /// caller (the recovery surface's confirmation dialog) must already have
  /// warned the user before reaching here. On success the returned disk
  /// state replaces the buffer, which re-renders the editor from disk; a
  /// failed round trip is surfaced through [editorErrorProvider] rather than
  /// silently dropped.
  Future<void> reloadFromDisk() async {
    if (ref.read(editorInputBlockedProvider)) return;
    final current = state;
    if (current == null) return;
    final noteId = current.metadata.id;
    final lifecycleGeneration = ref.read(lifecycleGenerationProvider);
    final editing = ref.read(reloadEditingProvider.notifier);
    // Close the shared editor and navigation admissions before the FFI call.
    // A platform input callback can otherwise write a new draft while this
    // reload is pending, then have that acknowledged write overwritten by the
    // disk state below.
    editing.begin();
    try {
      final reloaded = await ref.read(rustApiProvider).reloadNote(noteId);
      // A lifecycle operation may have renamed, moved, rewritten, or deleted
      // this session while reload_note was pending. Its result is no longer
      // authoritative for the visible Note, even if the id happens to match.
      if (!_isReloadCurrent(current, noteId, lifecycleGeneration)) return;
      state = reloaded;
      final tabs = ref.read(openNoteSessionsProvider.notifier);
      if (tabs.byId(noteId) != null) tabs.upsert(reloaded);
      ref.read(editorErrorProvider.notifier).report(null);
      // The reload replaced the buffer whose write was failing.
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    } catch (error) {
      if (!_isReloadCurrent(current, noteId, lifecycleGeneration)) return;
      ref.read(editorErrorProvider.notifier).report(error);
    } finally {
      // A pending FFI call can outlive ProviderContainer disposal. The
      // container owns this count, so only release it while its notifier is
      // still live; disposal itself retires the whole provider graph.
      if (ref.mounted) editing.end();
    }
  }

  bool _isReloadCurrent(
    NoteState expected,
    String noteId,
    int lifecycleGeneration,
  ) =>
      ref.mounted &&
      ref.read(lifecycleGenerationProvider) == lifecycleGeneration &&
      identical(state, expected) &&
      state?.metadata.id == noteId;
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
