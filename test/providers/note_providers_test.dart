import 'dart:async';

import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SwitchingRustApi extends RustApi {
  _SwitchingRustApi({
    this.warningOnClose = false,
    this.failFirstOpenOf,
    this.closeGate,
  });

  final bool warningOnClose;
  final String? failFirstOpenOf;
  final List<String> calls = [];
  final List<String> blockUpdates = [];
  final Completer<void>? closeGate;
  Completer<NoteState>? reloadGate;
  final Map<String, Completer<NoteState>> openNoteGates = {};
  Object? reloadError;
  var _hasFailedOpen = false;

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
    final gate = closeGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (warningOnClose) {
      throw const CloseNoteWarning('version-history recording was unavailable');
    }
  }

  @override
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
    final gate = openNoteGates[noteId];
    if (gate != null) return gate.future;
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
    'an admission change during a delayed close releases switching before later navigation and editing',
    () async {
      final closeGate = Completer<void>();
      final api = _SwitchingRustApi(closeGate: closeGate);
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.open('a');
      container.read(selectedNoteIdProvider.notifier).select('b');
      final switching = controller.open('b');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(noteSwitchingProvider), isTrue);
      expect(container.read(editorInputBlockedProvider), isTrue);

      // This models a lifecycle action claiming the replacement boundary
      // while Core is still closing A. The stale switch must retire A without
      // leaving its admission gate held forever.
      container.read(lifecycleAdmissionProvider.notifier).next();
      closeGate.complete();
      await switching;

      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(noteSwitchingProvider), isFalse);
      expect(container.read(editorInputBlockedProvider), isFalse);

      container.read(selectedNoteIdProvider.notifier).select('a');
      await controller.open('a');
      controller.updateBlock([0], 'editable after stale switch');
      expect(container.read(activeNoteProvider)!.metadata.id, 'a');
      expect(api.blockUpdates, ['a:0:editable after stale switch']);
    },
  );

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
    'a later tab selection wins when its Core result returns before an earlier selection',
    () async {
      final b = Completer<NoteState>();
      final c = Completer<NoteState>();
      final api = _SwitchingRustApi()
        ..openNoteGates['b'] = b
        ..openNoteGates['c'] = c;
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      await controller.openAsTab('a');
      final openB = controller.openAsTab('b');
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['open:a', 'open:b']);

      final openC = controller.openAsTab('c');
      // C's Core reply is ready first. The request may be held behind B for
      // serialization, but B must never mount over this newer selection.
      c.complete(
        const NoteState(
          ast: [],
          metadata: NoteMetadata(
            id: 'c',
            path: 'c.md',
            title: 'c',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'head',
          restoredFromDraft: false,
        ),
      );
      b.complete(
        const NoteState(
          ast: [],
          metadata: NoteMetadata(
            id: 'b',
            path: 'b.md',
            title: 'b',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'head',
          restoredFromDraft: false,
        ),
      );
      await Future.wait([openB, openC]);

      expect(container.read(activeNoteProvider)!.metadata.id, 'c');
      expect(
        container
            .read(openNoteSessionsProvider)
            .map((note) => note.metadata.id),
        ['a', 'c'],
      );
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
