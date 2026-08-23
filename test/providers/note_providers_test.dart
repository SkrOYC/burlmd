import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SwitchingRustApi extends RustApi {
  _SwitchingRustApi({this.warningOnClose = false, this.failFirstOpenOf});

  final bool warningOnClose;
  final String? failFirstOpenOf;
  final List<String> calls = [];
  var _hasFailedOpen = false;

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
    if (warningOnClose) {
      throw const CloseNoteWarning('version-history recording was unavailable');
    }
  }

  @override
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
    if (noteId == failFirstOpenOf && !_hasFailedOpen) {
      _hasFailedOpen = true;
      throw StateError('the incoming Note is temporarily unavailable');
    }
    return NoteState(
      ast: const [],
      metadata: NoteMetadata(
        id: noteId,
        path: '$noteId.md',
        title: noteId,
        lastModified: 0,
        okfConformant: true,
      ),
      baseRevision: 'head',
      restoredFromDraft: false,
    );
  }
}

ProviderContainer _containerFor(_SwitchingRustApi api) {
  final container = ProviderContainer(
    overrides: [rustApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'a completed close warning continues to the selected Note without restoring the dead session',
    () async {
      final api = _SwitchingRustApi(warningOnClose: true);
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.open('a');
      container.read(selectedNoteIdProvider.notifier).select('b');
      await controller.open('b');

      expect(api.calls, ['open:a', 'close:a', 'open:b']);
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(container.read(editorErrorProvider), isNull);
      expect(container.read(noteCloseFailureProvider), isA<CloseNoteWarning>());
    },
  );

  test(
    'an incoming open failure re-arms a same-Note selection for retry',
    () async {
      final api = _SwitchingRustApi(failFirstOpenOf: 'b');
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);
      final selections = <String?>[];
      container.listen<String?>(
        selectedNoteIdProvider,
        (_, next) => selections.add(next),
      );

      await controller.open('a');
      container.read(selectedNoteIdProvider.notifier).select('b');
      await controller.open('b');

      expect(api.calls, ['open:a', 'close:a', 'open:b']);
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(container.read(editorErrorProvider), isA<StateError>());

      // [SelectedNoteId.select] re-emits an explicit same-Note tap, so the
      // production tree listener has a state transition that drives this
      // same call again.
      container.read(selectedNoteIdProvider.notifier).select('b');
      expect(selections.sublist(selections.length - 2), [null, 'b']);
      await controller.open('b');

      expect(api.calls, ['open:a', 'close:a', 'open:b', 'open:b']);
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(container.read(editorErrorProvider), isNull);
    },
  );

  test(
    'shared selection and direct opens are refused during lifecycle work, then recover without divergence',
    () async {
      final api = _SwitchingRustApi();
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.open('a');
      container.read(selectedNoteIdProvider.notifier).select('a');
      container.read(lifecycleEditingProvider.notifier).begin();

      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isFalse,
      );
      await controller.open('b');
      expect(container.read(selectedNoteIdProvider), 'a');
      expect(container.read(activeNoteProvider)!.metadata.id, 'a');
      expect(api.calls, ['open:a']);

      container.read(lifecycleEditingProvider.notifier).end();
      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isTrue,
      );
      await controller.open('b');
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(api.calls, ['open:a', 'close:a', 'open:b']);
    },
  );
}
