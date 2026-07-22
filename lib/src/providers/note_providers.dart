import 'package:burlmd/src/rust/api/ffi_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the currently open note's state. UI widgets must stay stateless
/// regarding note content and read it from this provider rather than
/// caching it themselves.
class NoteController extends Notifier<NoteState?> {
  @override
  NoteState? build() => null;

  void open(String path) {
    state = openNote(path: path);
  }
}

final activeNoteProvider = NotifierProvider<NoteController, NoteState?>(
  NoteController.new,
);
