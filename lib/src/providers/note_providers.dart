import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the currently open note's state. UI widgets must stay stateless
/// regarding note content and read it from this provider rather than
/// caching it themselves.
class NoteController extends Notifier<NoteState?> {
  @override
  NoteState? build() => null;

  /// Opens the Note addressed by `noteId`, its OKF concept id — not a
  /// filesystem path. `open_note` is `async` at the FFI boundary now
  /// (`WSPC-D008`), so this awaits it rather than assigning synchronously.
  Future<void> open(String noteId) async {
    state = await ref.read(rustApiProvider).openNote(noteId);
  }

  /// The per-keystroke call (ADR-007 decision 4): buffers `source` — the
  /// Block's raw Markdown text, not an `AstNode` — into the Note's working
  /// source and writes the draft row. `update_block` no longer parses or
  /// returns a `NoteState`, so this does not reassign `state`; reflecting an
  /// edit back into the rendered AST on blur is `commit_block`'s job, which
  /// is `EDIT-F002` territory rather than this ticket's.
  void updateBlock(List<int> blockPath, String source) {
    final current = state;
    if (current == null) return;
    ref
        .read(rustApiProvider)
        .updateBlock(current.metadata.id, blockPath, source);
  }
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
