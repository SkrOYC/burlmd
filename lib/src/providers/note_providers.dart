import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the currently open note's state. UI widgets must stay stateless
/// regarding note content and read it from this provider rather than
/// caching it themselves.
class NoteController extends Notifier<NoteState?> {
  @override
  NoteState? build() => null;

  void open(String path) {
    state = ref.read(rustApiProvider).openNote(path);
  }

  void updateBlock(List<int> blockPath, AstNode newNode) {
    final current = state;
    if (current == null) return;
    state = ref
        .read(rustApiProvider)
        .updateBlock(current.metadata.id, blockPath, newNode);
  }
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
