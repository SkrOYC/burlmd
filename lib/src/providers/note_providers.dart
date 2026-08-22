import 'package:burlmd/src/providers/rust_api_provider.dart';
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
  /// on top of an uncommitted session would bury the failure.
  Future<void> open(String noteId) async {
    final api = ref.read(rustApiProvider);
    final current = state;
    if (current != null && current.metadata.id != noteId) {
      try {
        await api.closeNote(current.metadata.id);
      } catch (error) {
        ref.read(editorErrorProvider.notifier).report(error);
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
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
