import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The last failure the Core returned across the boundary while opening,
/// closing or editing the active Note, or `null` when the last operation
/// succeeded. `SHEL-E004`'s error surface: [Editor] watches this and shows
/// the failure to the user rather than silently ignoring it — before this
/// ticket the editor had no error surface at all and every Core refusal
/// (an unopenable Note, a failed draft write under `update_block`) was
/// raised into nothing.
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
    if (current != null) {
      try {
        await api.closeNote(current.metadata.id);
      } catch (error) {
        ref.read(editorErrorProvider.notifier).report(error);
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
      // reflects the present, not the last thing that went wrong.
      ref.read(editorErrorProvider.notifier).report(null);
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  /// The per-keystroke call (ADR-007 decision 4): buffers `source` — the
  /// Block's raw Markdown text, not an `AstNode` — into the Note's working
  /// source and writes the draft row. `update_block` no longer parses or
  /// returns a `NoteState`, so this does not reassign `state`; reflecting an
  /// edit back into the rendered AST on blur is `commit_block`'s job, which
  /// is `EDIT-F002` territory rather than this ticket's.
  ///
  /// `update_block` is `#[frb(sync)]` and therefore throws synchronously on
  /// every Core refusal — an unaddressable Block path, a failed draft write.
  /// Those are surfaced through [editorErrorProvider] instead of being
  /// raised into an empty callback stack (`SHEL-E004`: errors crossing the
  /// boundary are never swallowed).
  void updateBlock(List<int> blockPath, String source) {
    final current = state;
    if (current == null) return;
    try {
      ref
          .read(rustApiProvider)
          .updateBlock(current.metadata.id, blockPath, source);
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
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
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
