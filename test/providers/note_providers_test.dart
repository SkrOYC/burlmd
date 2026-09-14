import 'dart:async';

import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
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
  final Map<String, Object> closeErrors = {};
  final Completer<void>? closeGate;
  final Map<String, Completer<void>> closeNoteGates = {};
  var closesInFlight = 0;
  var maxClosesInFlight = 0;
  Completer<NoteState>? reloadGate;
  final Map<String, Completer<NoteState>> openNoteGates = {};
  Object? reloadError;
  var _hasFailedOpen = false;

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
    closesInFlight++;
    maxClosesInFlight = maxClosesInFlight > closesInFlight
        ? maxClosesInFlight
        : closesInFlight;
    try {
      final perNoteGate = closeNoteGates[noteId];
      if (perNoteGate != null && !perNoteGate.isCompleted) {
        await perNoteGate.future;
      }
      final gate = closeGate;
      if (gate != null && !gate.isCompleted) await gate.future;
      if (warningOnClose) {
        throw const CloseNoteWarning(
          'version-history recording was unavailable',
        );
      }
      final error = closeErrors[noteId];
      if (error != null) throw error;
    } finally {
      closesInFlight--;
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
  group('serialized Note close coordinator', () {
    Future<void> openTabs(
      ProviderContainer container,
      Iterable<String> ids,
    ) async {
      final controller = container.read(activeNoteProvider.notifier);
      for (final id in ids) {
        await controller.openAsTab(id);
      }
    }

    test(
      'batch result sequences retain input order and stop on the first terminal non-clean result',
      () async {
        for (final scenario
            in <
              ({
                String name,
                Map<String, Object> errors,
                List<String> expectedClosed,
                List<String> expectedOpen,
              })
            >[
              (
                name: 'all clean',
                errors: const {},
                expectedClosed: ['a', 'b', 'c'],
                expectedOpen: const [],
              ),
              (
                name: 'retired-session warning',
                errors: const {'b': CloseNoteWarning('cleanup warning')},
                expectedClosed: ['a', 'b'],
                expectedOpen: ['c'],
              ),
              (
                name: 'close refusal',
                errors: {'b': StateError('disk unavailable')},
                expectedClosed: ['a', 'b'],
                expectedOpen: ['b', 'c'],
              ),
            ]) {
          final api = _SwitchingRustApi()..closeErrors.addAll(scenario.errors);
          final container = _containerFor(api);
          await openTabs(container, ['a', 'b', 'c']);

          final completedCleanly = await container
              .read(activeNoteProvider.notifier)
              .closeAllTabs();

          expect(
            completedCleanly,
            scenario.name == 'all clean',
            reason: scenario.name,
          );
          expect(
            api.calls.where((call) => call.startsWith('close:')).toList(),
            scenario.expectedClosed.map((id) => 'close:$id').toList(),
            reason: scenario.name,
          );
          expect(api.maxClosesInFlight, 1, reason: scenario.name);
          expect(
            container
                .read(openNoteSessionsProvider)
                .map((note) => note.metadata.id)
                .toList(),
            scenario.expectedOpen,
            reason: scenario.name,
          );
        }
      },
    );

    test(
      'a warning retires the outgoing tab and permits only a standalone Note replacement',
      () async {
        final api = _SwitchingRustApi()
          ..closeErrors['a'] = const CloseNoteWarning('cleanup warning');
        final container = _containerFor(api);
        final controller = container.read(activeNoteProvider.notifier);

        await controller.open('a');
        await controller.open('b');

        expect(api.calls, ['open:a', 'close:a', 'open:b']);
        expect(container.read(activeNoteProvider)!.metadata.id, 'b');
        expect(
          container
              .read(openNoteSessionsProvider)
              .map((note) => note.metadata.id),
          ['b'],
        );
        expect(api.maxClosesInFlight, 1);
      },
    );

    test(
      'the batch includes retained Core sessions but never treats snapshot retry hints as Core sessions',
      () async {
        final api = _SwitchingRustApi()
          ..closeErrors['retained'] = StateError('close refused');
        final container = _containerFor(api);
        await openTabs(container, ['a']);
        container
            .read(retainedCoreSessionIdsProvider.notifier)
            .retain('retained');
        container
            .read(workspaceSessionProvider.notifier)
            .addOpenNoteId('snapshot-retry-hint');

        final completedCleanly = await container
            .read(activeNoteProvider.notifier)
            .closeAllTabs();

        expect(completedCleanly, isFalse);
        expect(api.calls.where((call) => call.startsWith('close:')).toList(), [
          'close:a',
          'close:retained',
        ]);
        expect(container.read(retainedCoreSessionIdsProvider), {'retained'});
        expect(
          container
              .read(workspaceSessionProvider)
              .openNoteIds
              .contains('snapshot-retry-hint'),
          isTrue,
        );
      },
    );

    test(
      'concurrent close entry requests never overlap Core close calls',
      () async {
        final firstClose = Completer<void>();
        final api = _SwitchingRustApi()..closeNoteGates['a'] = firstClose;
        final container = _containerFor(api);
        await openTabs(container, ['a', 'b']);
        final controller = container.read(activeNoteProvider.notifier);

        final closeA = controller.closeTab('a');
        await Future<void>.delayed(Duration.zero);
        final closeB = controller.closeTab('b');
        await Future<void>.delayed(Duration.zero);

        expect(api.calls.where((call) => call.startsWith('close:')), [
          'close:a',
        ]);
        expect(api.maxClosesInFlight, 1);
        firstClose.complete();
        expect(await closeA, isTrue);
        expect(await closeB, isTrue);
        expect(api.calls.where((call) => call.startsWith('close:')), [
          'close:a',
          'close:b',
        ]);
        expect(api.maxClosesInFlight, 1);
      },
    );

    test(
      'wide close operations proceed only after an entirely clean batch',
      () async {
        for (final entryPoint in <Future<bool> Function(NoteController)>[
          (controller) => controller.closeAllForWorkspaceTransition(),
          (controller) => controller.closeAllForOrderlyShutdown(),
        ]) {
          for (final warning in [false, true]) {
            final api = _SwitchingRustApi();
            if (warning) {
              api.closeErrors['a'] = const CloseNoteWarning('cleanup warning');
            }
            final container = _containerFor(api);
            await openTabs(container, ['a', 'b']);

            final canContinue = await entryPoint(
              container.read(activeNoteProvider.notifier),
            );

            expect(canContinue, isNot(warning));
            expect(
              api.calls.where((call) => call.startsWith('close:')).toList(),
              warning ? ['close:a'] : ['close:a', 'close:b'],
            );
          }
        }
      },
    );
  });

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
      // B's reply created a Core session even though C had already won.
      // Retire that superseded session instead of leaking its draft/timers.
      expect(api.calls, ['open:a', 'open:b', 'close:b', 'open:c']);
      expect(
        container
            .read(openNoteSessionsProvider)
            .map((note) => note.metadata.id),
        ['a', 'c'],
      );
    },
  );

  test(
    'a delayed restore cannot replace a newer Core-backed tab or orphan its own session',
    () async {
      final restored = Completer<NoteState>();
      final api = _SwitchingRustApi()..openNoteGates['a'] = restored;
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      final restore = controller.restoreOpenNotes(
        openNoteIds: const ['a'],
        activeNoteId: 'a',
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['open:a']);

      // The shell is already interactive while the asynchronous restore is
      // waiting on Core, so a normal tab open can arrive in this gap.
      final openB = controller.openAsTab('b');
      restored.complete(
        const NoteState(
          ast: [],
          metadata: NoteMetadata(
            id: 'a',
            path: 'a.md',
            title: 'a',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'head',
          restoredFromDraft: false,
        ),
      );
      await Future.wait([restore, openB]);

      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(
        container
            .read(openNoteSessionsProvider)
            .map((note) => note.metadata.id),
        ['b'],
      );
      expect(container.read(workspaceSessionProvider).openNoteIds, ['b']);
      expect(container.read(workspaceSessionProvider).activeNoteId, 'b');
      expect(api.calls, ['open:a', 'close:a', 'open:b']);
    },
  );

  test('a close refusal preserves a superseded tab Core still owns', () async {
    final b = Completer<NoteState>();
    final api = _SwitchingRustApi()
      ..openNoteGates['b'] = b
      ..closeErrors['b'] = const AppError.ioError('temporary close failure');
    final container = _containerFor(api);
    final controller = container.read(activeNoteProvider.notifier);

    await controller.openAsTab('a');
    final openB = controller.openAsTab('b');
    await Future<void>.delayed(Duration.zero);
    final openC = controller.openAsTab('c');
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
      container.read(openNoteSessionsProvider).map((note) => note.metadata.id),
      ['a', 'b', 'c'],
    );
    expect(container.read(workspaceSessionProvider).openNoteIds, [
      'a',
      'b',
      'c',
    ]);
    expect(api.calls, ['open:a', 'open:b', 'close:b', 'open:c']);
  });

  test(
    'a close refusal preserves a stale restore tab while a newer tab stays active',
    () async {
      final restored = Completer<NoteState>();
      final api = _SwitchingRustApi()
        ..openNoteGates['a'] = restored
        ..closeErrors['a'] = const AppError.ioError('temporary close failure');
      final container = _containerFor(api);
      final controller = container.read(activeNoteProvider.notifier);

      final restore = controller.restoreOpenNotes(
        openNoteIds: const ['a'],
        activeNoteId: 'a',
      );
      await Future<void>.delayed(Duration.zero);
      final openB = controller.openAsTab('b');
      restored.complete(
        const NoteState(
          ast: [],
          metadata: NoteMetadata(
            id: 'a',
            path: 'a.md',
            title: 'a',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'head',
          restoredFromDraft: false,
        ),
      );
      await Future.wait([restore, openB]);

      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(
        container
            .read(openNoteSessionsProvider)
            .map((note) => note.metadata.id),
        ['a', 'b'],
      );
      expect(container.read(workspaceSessionProvider).openNoteIds, ['a', 'b']);
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
