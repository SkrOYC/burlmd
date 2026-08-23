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

/// A one-shot close refusal for an otherwise still-open Note session.
///
/// Unlike an open failure, a close refusal leaves the old Core session valid
/// and retryable. [Editor] acknowledges this value after showing its
/// dismissible status message, preventing stale errors on later rebuilds.
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
/// The old state remains available solely so a failed close can restore that
/// session, but it no longer grants edit authority once switching begins.
final noteSwitchingProvider = NotifierProvider<NoteSwitching, bool>(
  NoteSwitching.new,
);

class NoteSwitching extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool switching) => state = switching;
}

/// Holds the currently open note's state. UI widgets must stay stateless
/// regarding note content and read it from this provider rather than
/// caching it themselves.
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
  /// history. A close that fails aborts the switch: opening the new Note
  /// on top of an uncommitted session would bury the failure. On that
  /// abort [selectedNoteIdProvider] is rolled back to the Note that is
  /// still open, so the tree highlight never names a Note the Core refused
  /// to reach — and the listener it fires re-enters this method only to hit
  /// the already-open fast path below, leaving the reported failure up.
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
  Future<void> open(String noteId) {
    final ticket = ++_openRequests;
    final previous = _pendingOpen ?? Future<void>.value();
    late final Future<void> mine;
    mine = () async {
      await previous;
      try {
        await _openExclusive(ticket, noteId);
      } finally {
        // Drop the chain once the tail catches up so completed work can be
        // collected instead of growing an unbounded await chain.
        if (identical(_pendingOpen, mine)) _pendingOpen = null;
      }
    }();
    _pendingOpen = mine;
    return mine;
  }

  /// The tail of the serialized [open] chain, or `null` when no switch is
  /// in flight or queued. Every request awaits this before touching the
  /// Core, which is what makes close-before-open orderable.
  Future<void>? _pendingOpen;

  /// Monotonic count of [open] requests. A queued request whose ticket no
  /// longer equals the newest one was superseded while waiting and must do
  /// nothing.
  int _openRequests = 0;

  Future<void> _openExclusive(int ticket, String noteId) async {
    // A newer selection arrived while this one sat in the queue: skip it
    // entirely rather than churning closes/opens for Notes the user has
    // already navigated past.
    if (ticket != _openRequests) return;
    final api = ref.read(rustApiProvider);
    final current = state;
    if (current != null && current.metadata.id == noteId) {
      // Already the open Note. Most commonly the rollback path above:
      // re-running the open would succeed and clear the error surface
      // explaining why the aborted switch failed, so treat it as done.
      return;
    }
    var switching = false;
    if (current != null) {
      // Revoke the old editor before awaiting the close. The old provider
      // value remains only to restore it when this close itself refuses.
      switching = true;
      ref.read(noteSwitchingProvider.notifier).set(true);
      try {
        await api.closeNote(current.metadata.id);
      } catch (error) {
        ref.read(noteSwitchingProvider.notifier).set(false);
        // Closing refused, so the old session remains Core-valid and can be
        // edited again. It is a nonfatal one-shot outcome, not the persistent
        // no-session error panel used for a failed open.
        ref.read(editorErrorProvider.notifier).report(null);
        ref.read(noteCloseFailureProvider.notifier).report(error);
        // The switch aborts with the old Note still open; point the tree
        // back at it so the selection highlight matches what the editor
        // actually shows. The error stays surfaced above.
        ref.read(selectedNoteIdProvider.notifier).select(current.metadata.id);
        return;
      }
    }
    try {
      state = await api.openNote(noteId);
      // A successful open clears any earlier failure so the surface
      // reflects the present, not the last thing that went wrong — both
      // surfaces: the old Note's keystroke-write failure belongs to a
      // session that just ended.
      ref.read(editorErrorProvider.notifier).report(null);
      ref.read(noteCloseFailureProvider.notifier).acknowledge();
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
          ref.read(selectedNoteIdProvider.notifier).select(stillOpen);
        }
      }
    } finally {
      if (switching) ref.read(noteSwitchingProvider.notifier).set(false);
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
  /// open/close/reload below.
  void updateBlock(List<int> blockPath, String source) {
    // A queued platform callback may arrive before the read-only rebuild
    // paints, so the switching state is the authority boundary.
    if (ref.read(noteSwitchingProvider)) return;
    final current = state;
    if (current == null) return;
    try {
      ref
          .read(rustApiProvider)
          .updateBlock(current.metadata.id, blockPath, source);
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    } catch (error) {
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
    }
  }

  /// Adopts `newState` as the open Note's state without any Core round trip
  /// (`SHEL-E005`). This is the re-anchor path for identity-changing
  /// lifecycle operations — rename, move, containing-directory rename: the
  /// Core carries the open session forward under the new concept id (working
  /// source, span map, recorded revision), so closing and reopening would
  /// address a dead identifier and fail. The returned post-operation state is
  /// authoritative; adopting it directly keeps the editor anchored to the
  /// same live session under its new id.
  void adopt(NoteState newState) {
    state = newState;
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
    state = null;
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
    final current = state;
    if (current == null) return;
    try {
      final reloaded = await ref
          .read(rustApiProvider)
          .reloadNote(current.metadata.id);
      state = reloaded;
      ref.read(editorErrorProvider.notifier).report(null);
      // The reload replaced the buffer whose write was failing.
      ref.read(keystrokeWriteFailureProvider.notifier).report(null);
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
