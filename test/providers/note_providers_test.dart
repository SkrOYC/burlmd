import 'dart:async';

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
  final List<String> blockUpdates = [];
  Completer<NoteState>? reloadGate;
  Object? reloadError;
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

  @override
  Future<NoteState> reloadNote(String noteId) async {
    calls.add('reload:$noteId');
    final gate = reloadGate;
    if (gate != null) return gate.future;
    final error = reloadError;
    if (error != null) throw error;
    return NoteState(
      ast: const [],
      metadata: NoteMetadata(
        id: noteId,
        path: '$noteId.md',
        title: '$noteId reloaded',
        lastModified: 0,
        okfConformant: true,
      ),
      baseRevision: 'head',
      restoredFromDraft: false,
    );
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    blockUpdates.add('$noteId:${blockPath.join(',')}:$newSource');
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

  test(
    'a pending disk reload blocks writes and navigation until its replacement is adopted',
    () async {
      final api = _SwitchingRustApi();
      final reload = Completer<NoteState>();
      api.reloadGate = reload;
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.open('a');
      container.read(selectedNoteIdProvider.notifier).select('a');
      final pending = controller.reloadFromDisk();

      expect(container.read(reloadEditingProvider), 1);
      expect(container.read(editorInputBlockedProvider), isTrue);
      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isFalse,
      );
      controller.updateBlock([0], 'must not reach Core');
      await controller.open('b');
      expect(api.blockUpdates, isEmpty);
      expect(container.read(selectedNoteIdProvider), 'a');
      expect(container.read(activeNoteProvider)!.metadata.id, 'a');

      reload.complete(
        NoteState(
          ast: const [],
          metadata: const NoteMetadata(
            id: 'a',
            path: 'a.md',
            title: 'disk source',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'disk-head',
          restoredFromDraft: false,
        ),
      );
      await pending;

      expect(container.read(reloadEditingProvider), 0);
      expect(container.read(editorInputBlockedProvider), isFalse);
      expect(container.read(activeNoteProvider)!.metadata.title, 'disk source');
      expect(container.read(editorErrorProvider), isNull);
    },
  );

  test(
    'a failed disk reload releases its admissions without clearing the Note',
    () async {
      final api = _SwitchingRustApi()..reloadError = StateError('disk offline');
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.open('a');
      final before = container.read(activeNoteProvider);
      await controller.reloadFromDisk();

      expect(container.read(reloadEditingProvider), 0);
      expect(container.read(editorInputBlockedProvider), isFalse);
      expect(container.read(activeNoteProvider), same(before));
      expect(container.read(editorErrorProvider), isA<StateError>());
      controller.updateBlock([0], 'editable after failure');
      expect(api.blockUpdates, ['a:0:editable after failure']);
    },
  );
}
