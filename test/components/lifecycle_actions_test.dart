import 'dart:async';

import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] standing in for the Core's lifecycle surface. Everything the
/// tests touch is programmable; every call is recorded so tests can assert
/// not only what reached the Core but what *never* did — a dead identifier
/// addressed after a rename, or a second create retrying under an altered
/// name, are failures of absence.
class _LifecycleApi extends RustApi {
  _LifecycleApi({this.tree = const []});

  List<TreeNode> tree;
  int workspaceTreeCalls = 0;

  /// Every lifecycle call in order, as `'name:arg1:arg2'`.
  final List<String> calls = [];

  /// Every `open_note` id in order.
  final List<String> openNoteCalls = [];

  NoteState? createNoteResult;
  Object? createNoteError;
  Completer<void>? createNoteGate;
  (NoteState, LifecycleEffects)? renameNoteResult;
  Object? renameNoteError;
  Completer<void>? renameNoteGate;
  (NoteState, LifecycleEffects)? moveNoteResult;
  Object? moveNoteError;
  Object? deleteNoteError;
  Completer<void>? deleteNoteGate;
  Object? createDirectoryError;
  LifecycleEffects? renameDirectoryResult;
  Object? renameDirectoryError;
  List<String>? deleteDirectoryResult;
  Completer<void>? deleteDirectoryGate;
  LifecycleWarning? lifecycleWarning;
  Object? closeNoteError;

  /// What `open_note` returns per id — for already-open Notes the live
  /// session state (post-rewrite, post-remap), which is exactly what the
  /// production re-anchor and rewritten-reload paths fetch.
  Map<String, NoteState> openStates = {};
  final Map<String, Completer<NoteState>> openNoteGates = {};

  /// A delayed reload lets tests race the disk result against a lifecycle
  /// operation that replaces or removes the session meanwhile.
  Completer<NoteState>? reloadNoteGate;

  /// The last source text `update_block` received — the "next keystroke"
  /// probe for the focus-refresh criterion.
  String? lastUpdateBlockSource;

  /// Every Core session that received a buffered source update. Rekey tests
  /// use this to prove a retained IME field never writes through its old,
  /// dead identity after lifecycle adoption.
  final List<String> updateBlockNoteIds = [];

  /// Staged sources `getBlockSource` returns per `"i,j"` path key, one per
  /// fetch (consumed front-first), letting a test stage distinct pre- and
  /// post-rewrite bytes for successive reads of the same Block.
  final Map<String, List<String>> stagedBlockSources = {};

  /// What [commitBlock] returns; unset means commits are unexpected.
  NoteState? commitBlockResult;

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int renderedUtf16Offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList(topLevelPath),
    caretOffset: BigInt.from(renderedUtf16Offset),
  );

  @override
  String getBlockSource(String noteId, List<int> blockPath) {
    final queue = stagedBlockSources[blockPath.join(',')];
    if (queue == null || queue.isEmpty) {
      throw Exception('no staged block source for $noteId$blockPath');
    }
    return queue.removeAt(0);
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    final result = commitBlockResult;
    if (result == null) {
      throw Exception('unexpected commit_block for $noteId$blockPath');
    }
    return result;
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    calls.add('updateBlock:$noteId');
    updateBlockNoteIds.add(noteId);
    lastUpdateBlockSource = newSource;
  }

  @override
  Future<List<TreeNode>> workspaceTree() async {
    workspaceTreeCalls++;
    return tree;
  }

  @override
  Future<NoteState> openNote(String noteId) async {
    openNoteCalls.add(noteId);
    final gate = openNoteGates[noteId];
    if (gate != null) return gate.future;
    final opened = openStates[noteId];
    if (opened != null) return opened;
    final created = createNoteResult;
    if (created != null && created.metadata.id == noteId) return created;
    throw StateError('no open state for $noteId');
  }

  @override
  Future<NoteState> reloadNote(String noteId) async {
    calls.add('reloadNote:$noteId');
    final gate = reloadNoteGate;
    if (gate != null) return gate.future;
    return openStates[noteId]!;
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('closeNote:$noteId');
    final error = closeNoteError;
    if (error != null) throw error;
  }

  @override
  Future<LifecycleResult> createNote(String directoryPath, String title) async {
    calls.add('createNote:$directoryPath:$title');
    final gate = createNoteGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    final error = createNoteError;
    if (error != null) throw error;
    return lifecycleResult(state: createNoteResult!, warning: lifecycleWarning);
  }

  @override
  Future<LifecycleResult> renameNote(String noteId, String newTitle) async {
    calls.add('renameNote:$noteId:$newTitle');
    final gate = renameNoteGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    final error = renameNoteError;
    if (error != null) throw error;
    final (state, effects) = renameNoteResult!;
    return lifecycleResult(
      state: state,
      effects: effects,
      warning: lifecycleWarning,
    );
  }

  @override
  Future<LifecycleResult> moveNote(
    String noteId,
    String newDirectoryPath,
  ) async {
    calls.add('moveNote:$noteId:$newDirectoryPath');
    final error = moveNoteError;
    if (error != null) throw error;
    final (state, effects) = moveNoteResult!;
    return lifecycleResult(
      state: state,
      effects: effects,
      warning: lifecycleWarning,
    );
  }

  @override
  Future<LifecycleResult> deleteNote(String noteId) async {
    calls.add('deleteNote:$noteId');
    final gate = deleteNoteGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    final error = deleteNoteError;
    if (error != null) throw error;
    return lifecycleResult(removed: [noteId], warning: lifecycleWarning);
  }

  @override
  Future<LifecycleResult> createDirectory(String path) async {
    calls.add('createDirectory:$path');
    final error = createDirectoryError;
    if (error != null) throw error;
    return lifecycleResult(warning: lifecycleWarning);
  }

  @override
  Future<LifecycleResult> renameDirectory(String path, String newName) async {
    calls.add('renameDirectory:$path:$newName');
    final error = renameDirectoryError;
    if (error != null) throw error;
    return lifecycleResult(
      effects: renameDirectoryResult!,
      warning: lifecycleWarning,
    );
  }

  @override
  Future<LifecycleResult> deleteDirectory(String path) async {
    calls.add('deleteDirectory:$path');
    final gate = deleteDirectoryGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    return lifecycleResult(
      removed: deleteDirectoryResult ?? const [],
      warning: lifecycleWarning,
    );
  }
}

TreeNode directory(String name, String path, List<TreeNode> children) =>
    TreeNode.directory(name: name, path: path, children: children);

TreeNode noteNode(String id, String title, String path) =>
    TreeNode.note(id: id, title: title, path: path);

AstNode paragraph(String text) => AstNode.paragraph(
  content: [
    InlineElement.text(
      TextRun(
        content: text,
        bold: false,
        italic: false,
        strikethrough: false,
        code: false,
      ),
    ),
  ],
);

NoteMetadata metadataFor(String id, {String? title}) => NoteMetadata(
  id: id,
  path: '$id.md',
  title: title ?? id,
  lastModified: 0,
  okfConformant: true,
);

NoteState stateFor(String id, {List<AstNode>? ast, String? title}) => NoteState(
  ast: ast ?? [paragraph('body of $id')],
  metadata: metadataFor(id, title: title),
  baseRevision: 'rev-$id',
  restoredFromDraft: false,
);

LifecycleEffects effects({
  List<IdRemap> remapped = const [],
  List<String> rewritten = const [],
}) => LifecycleEffects(remapped: remapped, rewritten: rewritten);

LifecycleResult lifecycleResult({
  NoteState? state,
  LifecycleEffects? effects,
  List<String> removed = const [],
  LifecycleWarning? warning,
}) => LifecycleResult(
  state: state,
  effects: effects ?? const LifecycleEffects(remapped: [], rewritten: []),
  removed: removed,
  warning: warning,
);

Future<void> _pumpTree(WidgetTester tester, _LifecycleApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 300, child: WorkspaceTree()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens a row's overflow menu (via its tooltip) and picks one of its
/// actions.
Future<void> _invokeRowAction(
  WidgetTester tester,
  String rowKindAndName,
  String actionLabel,
) async {
  await tester.tap(find.byTooltip('Actions for $rowKindAndName'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel).last);
  await tester.pumpAndSettle();
}

void main() {
  // -- Logic level: provider orchestration against a fake Core -------------

  group('creation', () {
    testWidgets('publishes the created note through the selection seam and '
        'invalidates the tree', (tester) async {
      final created = stateFor('Projects/New note', title: 'New note');
      final api = _LifecycleApi(tree: [directory('Projects', 'Projects', [])])
        ..createNoteResult = created;
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      addTearDown(container.dispose);
      container.listen(workspaceTreeProvider, (_, _) {});
      expect(api.workspaceTreeCalls, 1);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .createNote('Projects', 'New note');

      expect(outcome, isA<LifecycleCompleted>());
      expect(api.calls, ['createNote:Projects:New note']);
      // The Core opened the created Note; publishing its id is what makes
      // "appears in the tree and opens for editing" true through the same
      // seam navigation uses.
      expect(container.read(selectedNoteIdProvider), created.metadata.id);
      // The tree refetches so the new Note actually appears.
      await container.read(workspaceTreeProvider.future);
      expect(api.workspaceTreeCalls, 2);
    });

    testWidgets('a name collision reports the Core refusal and never retries '
        'under an altered name', (tester) async {
      final api = _LifecycleApi()
        ..createNoteError = AppError.pathUnavailable(
          'Projects/New note.md already exists',
        );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .createNote('Projects', 'New note');

      expect(outcome, isA<LifecycleRefused>());
      expect((outcome as LifecycleRefused).reason, contains('already exists'));
      // Exactly one attempt: no client-side disambiguation ("New note 2").
      expect(api.calls.length, 1);
      expect(container.read(selectedNoteIdProvider), isNull);
    });

    testWidgets('a delayed create cannot overwrite a newer selection', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _LifecycleApi()
        ..createNoteGate = gate
        ..createNoteResult = stateFor('Projects/Created', title: 'Created');
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
      container.read(selectedNoteIdProvider.notifier).select('Old');

      final pending = container
          .read(lifecycleActionsProvider)
          .createNote('Projects', 'Created');
      await tester.pump();
      container.read(activeNoteProvider.notifier).adopt(stateFor('Newer'));
      // This probes an authoritative host-side replacement, not ordinary
      // navigation; lifecycle admission intentionally rejects the latter.
      container
          .read(selectedNoteIdProvider.notifier)
          .selectForLifecycle('Newer');
      gate.complete();
      await pending;

      expect(container.read(activeNoteProvider)!.metadata.id, 'Newer');
      expect(container.read(selectedNoteIdProvider), 'Newer');
    });

    testWidgets('a create warning still publishes its authoritative state', (
      tester,
    ) async {
      final created = stateFor('Projects/Created', title: 'Created');
      final open = Completer<NoteState>();
      final api = _LifecycleApi()
        ..createNoteResult = created
        ..openNoteGates[created.metadata.id] = open
        ..lifecycleWarning = const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'commit unavailable',
        );
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);

      final pending = container
          .read(lifecycleActionsProvider)
          .createNote('Projects', 'Created');
      await tester.pump();

      // The terminal warning cannot escape while the Core-created session is
      // not yet the active editor state.
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(lifecycleEditingProvider), 1);
      open.complete(created);
      final outcome = await pending;

      expect(
        (outcome as LifecycleCompleted).warning,
        same(api.lifecycleWarning),
      );
      expect(container.read(activeNoteProvider), same(created));
      expect(container.read(selectedNoteIdProvider), created.metadata.id);
      expect(container.read(lifecycleEditingProvider), 0);
    });

    testWidgets('an ordinary create warning waits for the created editor '
        'session and retires the old raw field', (tester) async {
      final old = stateFor('Old', ast: [paragraph('old raw source')]);
      final created = stateFor(
        'Projects/Created',
        title: 'Created',
        ast: [paragraph('created source')],
      );
      final api = _LifecycleApi()
        ..createNoteResult = created
        ..openStates = {created.metadata.id: created}
        ..lifecycleWarning = const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'commit unavailable',
        );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(body: Editor()),
              );
            },
          ),
        ),
      );
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(old);
      container.read(selectedNoteIdProvider.notifier).select(old.metadata.id);
      api.stagedBlockSources['0'] = ['old raw source'];
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('block-0')));
      await tester.pumpAndSettle();
      final writable = find.byWidgetPredicate(
        (widget) => widget is EditableText && !widget.readOnly,
      );
      expect(writable, findsOneWidget);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .createNote('Projects', 'Created');
      await tester.pumpAndSettle();
      report(tester.element(find.byType(Scaffold)), outcome);
      await tester.pump();

      expect(container.read(activeNoteProvider), same(created));
      expect(container.read(selectedNoteIdProvider), created.metadata.id);
      expect(find.text('created source'), findsOneWidget);
      expect(writable, findsNothing);
      expect(find.textContaining('The change is applied'), findsOneWidget);
    });
  });

  group('renaming the open note', () {
    testWidgets('re-anchors to the returned id without ever addressing the '
        'dead one', (tester) async {
      final renamed = stateFor('Projects/Renamed', title: 'Renamed');
      final api = _LifecycleApi()
        ..renameNoteResult = (renamed, effects(rewritten: []));
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      // The Note under its old id is what the editor holds when the user
      // invokes rename on it.
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
      container.read(selectedNoteIdProvider.notifier).select('Old');

      final outcome = await container
          .read(lifecycleActionsProvider)
          .renameNote('Old', 'Renamed');

      expect(outcome, isA<LifecycleCompleted>());
      expect(api.calls, ['renameNote:Old:Renamed']);
      // The editor now anchors to the returned state's NEW id, not the old
      // one — and nothing was closed or reopened: the session was carried
      // forward Core-side, so addressing 'Old' again would fail.
      expect(
        container.read(activeNoteProvider)!.metadata.id,
        'Projects/Renamed',
      );
      expect(container.read(selectedNoteIdProvider), 'Projects/Renamed');
      expect(api.openNoteCalls, isEmpty);
      expect(api.calls.where((c) => c.startsWith('closeNote')), isEmpty);
    });

    testWidgets('a terminal commit warning settles the renamed editor before '
        'it reaches presentation', (tester) async {
      final renamed = stateFor('Projects/Renamed', title: 'Renamed');
      final api = _LifecycleApi()
        ..renameNoteResult = (renamed, effects())
        ..lifecycleWarning = const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'injected commit failure',
        );
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
      container.read(selectedNoteIdProvider.notifier).select('Old');

      final outcome = await container
          .read(lifecycleActionsProvider)
          .renameNote('Old', 'Renamed');

      expect(
        (outcome as LifecycleCompleted).warning,
        same(api.lifecycleWarning),
      );
      expect(container.read(activeNoteProvider), same(renamed));
      expect(container.read(selectedNoteIdProvider), 'Projects/Renamed');
      expect(container.read(editorInputBlockedProvider), isFalse);
    });
  });

  group('moving the open note', () {
    testWidgets('re-anchors to the moved identity', (tester) async {
      final moved = stateFor('Archive/Old', title: 'Old');
      final api = _LifecycleApi()..moveNoteResult = (moved, effects());
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
      container.read(selectedNoteIdProvider.notifier).select('Old');

      await container.read(lifecycleActionsProvider).moveNote('Old', 'Archive');

      expect(container.read(activeNoteProvider)!.metadata.id, 'Archive/Old');
      expect(container.read(selectedNoteIdProvider), 'Archive/Old');
      expect(api.openNoteCalls, isEmpty);
    });
  });

  group('settling a selected Note without an open session', () {
    Future<void> leaveIncomingOpenFailed(
      WidgetTester tester,
      ProviderContainer container,
      _LifecycleApi api,
    ) async {
      final controller = container.read(activeNoteProvider.notifier);
      api.openStates['A'] = stateFor('A');
      await controller.open('A');
      container.read(selectedNoteIdProvider.notifier).select('B');
      // B deliberately has no open state. Its incoming open closes A, then
      // leaves selection on B with no mounted Core session.
      await controller.open('B');
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), 'B');
      expect(container.read(editorErrorProvider), isNotNull);
    }

    testWidgets('rename opens the returned identity before publishing its '
        'selection when the selected source Note is not open', (tester) async {
      final returned = stateFor('Renamed/B', title: 'returned metadata');
      final reopened = stateFor('Renamed/B', title: 'opened session');
      final api = _LifecycleApi()
        ..renameNoteResult = (returned, effects())
        ..openStates['Renamed/B'] = reopened;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      await leaveIncomingOpenFailed(tester, container, api);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .renameNote('B', 'Renamed');

      expect(outcome, isA<LifecycleCompleted>());
      // The active state is the actual session returned by open_note, not
      // direct adoption of lifecycle metadata merely because B was selected.
      expect(container.read(activeNoteProvider), same(reopened));
      expect(container.read(selectedNoteIdProvider), 'Renamed/B');
      expect(api.openNoteCalls, ['A', 'B', 'Renamed/B']);
      expect(api.calls, ['closeNote:A', 'renameNote:B:Renamed']);
      expect(container.read(editorErrorProvider), isNull);
    });

    testWidgets('move opens the returned identity before publishing its '
        'selection when the selected source Note is not open', (tester) async {
      final returned = stateFor('Archive/B', title: 'returned metadata');
      final reopened = stateFor('Archive/B', title: 'opened session');
      final api = _LifecycleApi()
        ..moveNoteResult = (returned, effects())
        ..openStates['Archive/B'] = reopened;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      await leaveIncomingOpenFailed(tester, container, api);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .moveNote('B', 'Archive');

      expect(outcome, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), same(reopened));
      expect(container.read(selectedNoteIdProvider), 'Archive/B');
      expect(api.openNoteCalls, ['A', 'B', 'Archive/B']);
      expect(api.calls, ['closeNote:A', 'moveNote:B:Archive']);
      expect(container.read(editorErrorProvider), isNull);
    });

    testWidgets('a failed returned-identity open does not publish a false '
        'selection and a later open can retry the session', (tester) async {
      final returned = stateFor('Renamed/B');
      final retried = stateFor('Renamed/B', title: 'retried session');
      final api = _LifecycleApi()..renameNoteResult = (returned, effects());
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      await leaveIncomingOpenFailed(tester, container, api);

      final outcome = await container
          .read(lifecycleActionsProvider)
          .renameNote('B', 'Renamed');

      expect(outcome, isA<LifecycleFailed>());
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), 'B');
      expect(api.openNoteCalls, ['A', 'B', 'Renamed/B']);

      // The lifecycle gate is released after failure; an explicit retry opens
      // the returned identity and only then makes it the selected Note.
      api.openStates['Renamed/B'] = retried;
      await container.read(activeNoteProvider.notifier).open('Renamed/B');
      container.read(selectedNoteIdProvider.notifier).select('Renamed/B');
      expect(container.read(activeNoteProvider), same(retried));
      expect(container.read(selectedNoteIdProvider), 'Renamed/B');
      expect(api.openNoteCalls, ['A', 'B', 'Renamed/B', 'Renamed/B']);
      expect(container.read(editorErrorProvider), isNull);
    });
  });

  group('reconciling an intercepted selected Note', () {
    Future<({Future<void> openingB})> startInterceptedOpen(
      WidgetTester tester,
      ProviderContainer container,
      _LifecycleApi api,
      Completer<NoteState> delayedB,
    ) async {
      api.openStates['A'] = stateFor('A');
      api.openNoteGates['B'] = delayedB;
      final controller = container.read(activeNoteProvider.notifier);
      await controller.open('A');
      container.read(selectedNoteIdProvider.notifier).select('B');
      final openingB = controller.open('B');
      await tester.pump();
      return (openingB: openingB);
    }

    testWidgets('a successful directory create restores an intercepted '
        'selection and later retires that recovered session', (tester) async {
      final delayedB = Completer<NoteState>();
      final recoveredB = stateFor('B');
      final next = stateFor('C');
      final api = _LifecycleApi()..openStates['C'] = next;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      final intercepted = await startInterceptedOpen(
        tester,
        container,
        api,
        delayedB,
      );

      final creating = container
          .read(lifecycleActionsProvider)
          .createDirectory('Archive');
      delayedB.complete(recoveredB);
      await intercepted.openingB;

      expect(await creating, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), same(recoveredB));
      expect(container.read(selectedNoteIdProvider), 'B');
      // The stale ordinary result cannot mount. The post-action recovery
      // deliberately asks Core for its existing B session once, rather than
      // manufacturing a second local session.
      expect(api.openNoteCalls, ['A', 'B', 'B']);
      expect(api.calls, ['closeNote:A', 'createDirectory:Archive']);

      await container.read(activeNoteProvider.notifier).open('C');
      expect(container.read(activeNoteProvider), same(next));
      expect(api.calls, [
        'closeNote:A',
        'createDirectory:Archive',
        'closeNote:B',
      ]);
    });

    testWidgets('an unrelated Core request error restores an intercepted '
        'selection without replacing the original failure', (tester) async {
      final delayedB = Completer<NoteState>();
      final recoveredB = stateFor('B');
      final next = stateFor('C');
      const failure = AppError.databaseError('database unavailable');
      final api = _LifecycleApi()
        ..createDirectoryError = failure
        ..openStates['C'] = next;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      final intercepted = await startInterceptedOpen(
        tester,
        container,
        api,
        delayedB,
      );

      final creating = container
          .read(lifecycleActionsProvider)
          .createDirectory('Archive');
      delayedB.complete(recoveredB);
      await intercepted.openingB;

      final outcome = await creating;
      expect(outcome, isA<LifecycleFailed>());
      expect((outcome as LifecycleFailed).error, same(failure));
      expect(container.read(activeNoteProvider), same(recoveredB));
      expect(container.read(selectedNoteIdProvider), 'B');
      // B's intercepted result is stale; the lifecycle-admitted retry mounts
      // Core's existing B session once and does not create another session.
      expect(api.openNoteCalls, ['A', 'B', 'B']);
      expect(api.calls, ['closeNote:A', 'createDirectory:Archive']);

      await container.read(activeNoteProvider.notifier).open('C');
      expect(container.read(activeNoteProvider), same(next));
      expect(api.calls, [
        'closeNote:A',
        'createDirectory:Archive',
        'closeNote:B',
      ]);
    });

    testWidgets('an unrelated Note deletion restores an intercepted '
        'selection', (tester) async {
      final delayedB = Completer<NoteState>();
      final recoveredB = stateFor('B');
      final api = _LifecycleApi();
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      final intercepted = await startInterceptedOpen(
        tester,
        container,
        api,
        delayedB,
      );

      final deleting = container
          .read(lifecycleActionsProvider)
          .deleteNote('unrelated');
      delayedB.complete(recoveredB);
      await intercepted.openingB;

      expect(await deleting, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), same(recoveredB));
      expect(container.read(selectedNoteIdProvider), 'B');
      expect(api.openNoteCalls, ['A', 'B', 'B']);
      expect(api.calls, ['closeNote:A', 'deleteNote:unrelated']);
    });

    testWidgets('an unrelated Note rename restores an intercepted selection', (
      tester,
    ) async {
      final delayedB = Completer<NoteState>();
      final recoveredB = stateFor('B');
      final api = _LifecycleApi()
        ..renameNoteResult = (stateFor('Renamed/C'), effects());
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      final intercepted = await startInterceptedOpen(
        tester,
        container,
        api,
        delayedB,
      );

      final renaming = container
          .read(lifecycleActionsProvider)
          .renameNote('C', 'Renamed');
      delayedB.complete(recoveredB);
      await intercepted.openingB;

      expect(await renaming, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), same(recoveredB));
      expect(container.read(selectedNoteIdProvider), 'B');
      expect(api.openNoteCalls, ['A', 'B', 'B']);
      expect(api.calls, ['closeNote:A', 'renameNote:C:Renamed']);
    });

    testWidgets('a failed recovered open remains selected and a later '
        'successful action retries it', (tester) async {
      final api = _LifecycleApi();
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      final controller = container.read(activeNoteProvider.notifier);
      api.openStates['A'] = stateFor('A');
      await controller.open('A');
      container.read(selectedNoteIdProvider.notifier).select('B');
      await controller.open('B');
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), 'B');

      final failed = await container
          .read(lifecycleActionsProvider)
          .createDirectory('First');
      expect(failed, isA<LifecycleFailed>());
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), 'B');

      final recoveredB = stateFor('B');
      api.openStates['B'] = recoveredB;
      final retried = await container
          .read(lifecycleActionsProvider)
          .createDirectory('Second');

      expect(retried, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), same(recoveredB));
      expect(container.read(selectedNoteIdProvider), 'B');
      expect(api.openNoteCalls, ['A', 'B', 'B', 'B']);
      expect(api.calls, [
        'closeNote:A',
        'createDirectory:First',
        'createDirectory:Second',
      ]);
      expect(container.read(editorErrorProvider), isNull);
    });
  });

  group('directory rename', () {
    testWidgets('an open remapped note re-anchors through the NEW id the '
        'Core returns', (tester) async {
      final freshUnderNewId = stateFor('Renamed/Old');
      final api = _LifecycleApi()
        ..renameDirectoryResult = effects(
          remapped: [IdRemap(oldId: 'Projects/Old', newId: 'Renamed/Old')],
        )
        ..openStates = {'Renamed/Old': freshUnderNewId};
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container
          .read(activeNoteProvider.notifier)
          .adopt(stateFor('Projects/Old'));
      container.read(selectedNoteIdProvider.notifier).select('Projects/Old');

      await container
          .read(lifecycleActionsProvider)
          .renameDirectory('Projects', 'Renamed');

      // Re-anchored onto the live session under its new id...
      expect(container.read(activeNoteProvider), same(freshUnderNewId));
      expect(container.read(selectedNoteIdProvider), 'Renamed/Old');
      // ...fetched via the new id only. The dead one is never sent anywhere.
      expect(api.openNoteCalls, ['Renamed/Old']);
      expect(api.calls.where((c) => c.startsWith('closeNote')), isEmpty);
    });

    testWidgets('an open rewritten note reloads although its id did not '
        'change', (tester) async {
      // B lives outside the renamed subtree but links into it; the rewrite
      // touched B's bytes while B's id stayed put.
      final staleB = stateFor('b', ast: [paragraph('see Projects/Old')]);
      final rewrittenB = stateFor('b', ast: [paragraph('see Renamed/Old')]);
      final api = _LifecycleApi()
        ..renameDirectoryResult = effects(rewritten: ['b'])
        ..openStates = {'b': rewrittenB};
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(staleB);
      container.read(selectedNoteIdProvider.notifier).select('b');

      await container
          .read(lifecycleActionsProvider)
          .renameDirectory('Projects', 'Renamed');

      // Nothing about the stale state would have looked wrong — same id,
      // same title — which is why the Core names it explicitly. The editor
      // now holds the post-rewrite AST.
      expect(container.read(activeNoteProvider), same(rewrittenB));
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(api.openNoteCalls, ['b']);
    });

    testWidgets('a terminal directory warning re-anchors a contained editor '
        'before presentation reports it', (tester) async {
      final moved = stateFor('Renamed/Old');
      final api = _LifecycleApi()
        ..renameDirectoryResult = effects(
          remapped: [IdRemap(oldId: 'Projects/Old', newId: 'Renamed/Old')],
        )
        ..openStates = {'Renamed/Old': moved}
        ..lifecycleWarning = const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'injected commit failure',
        );
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container
          .read(activeNoteProvider.notifier)
          .adopt(stateFor('Projects/Old'));
      container.read(selectedNoteIdProvider.notifier).select('Projects/Old');

      final outcome = await container
          .read(lifecycleActionsProvider)
          .renameDirectory('Projects', 'Renamed');

      expect(
        (outcome as LifecycleCompleted).warning,
        same(api.lifecycleWarning),
      );
      expect(container.read(activeNoteProvider), same(moved));
      expect(container.read(selectedNoteIdProvider), 'Renamed/Old');
      expect(container.read(editorInputBlockedProvider), isFalse);
    });

    testWidgets('an overlapping lifecycle action waits for the authoritative '
        'remap to settle before it reaches Core', (tester) async {
      final delayedOpen = Completer<NoteState>();
      final api = _LifecycleApi()
        ..renameDirectoryResult = effects(
          remapped: [IdRemap(oldId: 'Old/Note', newId: 'New/Note')],
        )
        ..openNoteGates['New/Note'] = delayedOpen;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old/Note'));
      container.read(selectedNoteIdProvider.notifier).select('Old/Note');

      final remap = container
          .read(lifecycleActionsProvider)
          .renameDirectory('Old', 'New');
      await tester.pump();
      expect(api.openNoteCalls, ['New/Note']);

      final delete = container
          .read(lifecycleActionsProvider)
          .deleteNote('Old/Note');
      await tester.pump();
      // The second request reserves the same input/navigation gate but does
      // not advance the generation or call Core until the remap has adopted
      // its authoritative state.
      expect(api.calls, ['renameDirectory:Old:New']);
      expect(container.read(lifecycleEditingProvider), 2);

      delayedOpen.complete(stateFor('New/Note'));
      await remap;
      await delete;
      expect(container.read(activeNoteProvider)!.metadata.id, 'New/Note');
      expect(container.read(selectedNoteIdProvider), 'New/Note');
      expect(container.read(lifecycleEditingProvider), 0);
    });

    testWidgets('overlapping remap and re-anchor actions settle in Core '
        'completion order', (tester) async {
      final delayedOpen = Completer<NoteState>();
      final finalState = stateFor('Final/Note');
      final api = _LifecycleApi()
        ..renameDirectoryResult = effects(
          remapped: [IdRemap(oldId: 'Old/Note', newId: 'Middle/Note')],
        )
        ..openNoteGates['Middle/Note'] = delayedOpen
        ..renameNoteResult = (finalState, effects());
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old/Note'));
      container.read(selectedNoteIdProvider.notifier).select('Old/Note');

      final remap = container
          .read(lifecycleActionsProvider)
          .renameDirectory('Old', 'Middle');
      await tester.pump();
      final rename = container
          .read(lifecycleActionsProvider)
          .renameNote('Middle/Note', 'Final');
      await tester.pump();
      expect(api.calls, ['renameDirectory:Old:Middle']);

      delayedOpen.complete(stateFor('Middle/Note'));
      await remap;
      await rename;
      expect(container.read(activeNoteProvider), same(finalState));
      expect(container.read(selectedNoteIdProvider), 'Final/Note');
      expect(container.read(lifecycleEditingProvider), 0);
    });
  });

  testWidgets('a stale created session is retired while its completed Core '
      'warning remains attached to this create outcome', (tester) async {
    final gate = Completer<void>();
    final created = stateFor('Created', title: 'Created');
    final warning = const LifecycleWarning(
      stage: LifecycleWarningStage.commit,
      detail: 'created but Git recording was unavailable',
    );
    final api = _LifecycleApi()
      ..createNoteResult = created
      ..createNoteGate = gate
      ..lifecycleWarning = warning;
    late ProviderContainer container;
    await tester.pumpWidget(_probeHarness(api, (c) => container = c));
    addTearDown(container.dispose);
    container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
    container.read(selectedNoteIdProvider.notifier).select('Old');

    final create = container
        .read(lifecycleActionsProvider)
        .createNote('', 'Created');
    await tester.pump();
    // This probes an authoritative host-side replacement. Ordinary producers
    // are rejected by the shared lifecycle selection admission.
    container
        .read(selectedNoteIdProvider.notifier)
        .selectForLifecycle('Elsewhere');
    gate.complete();

    final outcome = (await create) as LifecycleCompleted;
    expect(api.calls, ['createNote::Created', 'closeNote:Created']);
    expect(outcome.warning, same(warning));
    expect(container.read(activeNoteProvider)!.metadata.id, 'Old');
    expect(container.read(selectedNoteIdProvider), 'Elsewhere');
    expect(container.read(lifecycleEditingProvider), 0);
  });

  testWidgets('a stale created session reports its terminal close warning '
      'once through the one-shot close status', (tester) async {
    final gate = Completer<void>();
    final api = _LifecycleApi()
      ..createNoteResult = stateFor('Created')
      ..createNoteGate = gate
      ..closeNoteError = const CloseNoteWarning('draft cleanup failed');
    late ProviderContainer container;
    await tester.pumpWidget(_probeHarness(api, (c) => container = c));
    addTearDown(container.dispose);
    container.read(activeNoteProvider.notifier).adopt(stateFor('Old'));
    container.read(selectedNoteIdProvider.notifier).select('Old');

    final create = container
        .read(lifecycleActionsProvider)
        .createNote('', 'Created');
    await tester.pump();
    container
        .read(selectedNoteIdProvider.notifier)
        .selectForLifecycle('Elsewhere');
    gate.complete();

    expect(await create, isA<LifecycleCompleted>());
    expect(container.read(noteCloseFailureProvider), isA<CloseNoteWarning>());
    expect(api.calls, ['createNote::Created', 'closeNote:Created']);
  });

  group('deletion', () {
    testWidgets('the deleted open note closes in the editor', (tester) async {
      final api = _LifecycleApi();
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('gone'));
      container.read(selectedNoteIdProvider.notifier).select('gone');

      await container.read(lifecycleActionsProvider).deleteNote('gone');

      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
      // No close_note: deletion already discarded the session Core-side.
      expect(api.calls.where((c) => c.startsWith('closeNote')), isEmpty);
    });

    testWidgets('deleting another note leaves the editor alone', (
      tester,
    ) async {
      final api = _LifecycleApi();
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('kept'));
      container.read(selectedNoteIdProvider.notifier).select('kept');

      await container.read(lifecycleActionsProvider).deleteNote('other');

      expect(container.read(activeNoteProvider)!.metadata.id, 'kept');
      expect(container.read(selectedNoteIdProvider), 'kept');
    });

    testWidgets(
      'a delete waits for an intercepted A to B open and clears B instead of mounting its dead id',
      (tester) async {
        final delayedB = Completer<NoteState>();
        final api = _LifecycleApi()
          ..openStates['A'] = stateFor('A')
          ..openNoteGates['B'] = delayedB;
        late ProviderContainer container;
        await tester.pumpWidget(_probeHarness(api, (c) => container = c));
        addTearDown(container.dispose);
        final controller = container.read(activeNoteProvider.notifier);
        await controller.open('A');
        container.read(selectedNoteIdProvider.notifier).select('B');
        final openingB = controller.open('B');
        await tester.pump();

        final deletingB = container
            .read(lifecycleActionsProvider)
            .deleteNote('B');
        await tester.pump();
        // The lifecycle request owns the UI boundary but must not snapshot A
        // while B's already-issued open is still crossing the FFI boundary.
        expect(api.calls, ['closeNote:A']);
        expect(api.openNoteCalls, ['A', 'B']);
        expect(container.read(lifecycleEditingProvider), 1);

        delayedB.complete(stateFor('B'));
        await openingB;
        expect(await deletingB, isA<LifecycleCompleted>());

        expect(container.read(activeNoteProvider), isNull);
        expect(container.read(selectedNoteIdProvider), isNull);
        expect(api.calls, ['closeNote:A', 'deleteNote:B']);
        expect(api.openNoteCalls, ['A', 'B']);
      },
    );

    testWidgets(
      'a rename reanchors an intercepted A to B open to the returned id',
      (tester) async {
        final delayedB = Completer<NoteState>();
        final renamed = stateFor('Renamed/B');
        final reopened = stateFor('Renamed/B', title: 'opened session');
        final api = _LifecycleApi()
          ..openStates['A'] = stateFor('A')
          ..openNoteGates['B'] = delayedB
          ..openStates['Renamed/B'] = reopened
          ..renameNoteResult = (renamed, effects());
        late ProviderContainer container;
        await tester.pumpWidget(_probeHarness(api, (c) => container = c));
        addTearDown(container.dispose);
        final controller = container.read(activeNoteProvider.notifier);
        await controller.open('A');
        container.read(selectedNoteIdProvider.notifier).select('B');
        final openingB = controller.open('B');
        await tester.pump();

        final renamingB = container
            .read(lifecycleActionsProvider)
            .renameNote('B', 'Renamed');
        delayedB.complete(stateFor('B'));
        await openingB;
        expect(await renamingB, isA<LifecycleCompleted>());

        expect(container.read(activeNoteProvider), same(reopened));
        expect(container.read(selectedNoteIdProvider), 'Renamed/B');
        expect(api.openNoteCalls, ['A', 'B', 'Renamed/B']);
      },
    );

    testWidgets(
      'a refused rename restores the selected B session after it intercepted A to B open',
      (tester) async {
        final delayedB = Completer<NoteState>();
        final restoredB = stateFor('B');
        final api = _LifecycleApi()
          ..openStates['A'] = stateFor('A')
          ..openStates['B'] = restoredB
          ..openNoteGates['B'] = delayedB
          ..renameNoteError = AppError.pathUnavailable('B already exists');
        late ProviderContainer container;
        await tester.pumpWidget(_probeHarness(api, (c) => container = c));
        addTearDown(container.dispose);
        final controller = container.read(activeNoteProvider.notifier);
        await controller.open('A');
        container.read(selectedNoteIdProvider.notifier).select('B');
        final openingB = controller.open('B');
        await tester.pump();

        final renamingB = container
            .read(lifecycleActionsProvider)
            .renameNote('B', 'Renamed');
        delayedB.complete(restoredB);
        await openingB;
        expect(await renamingB, isA<LifecycleRefused>());

        expect(container.read(activeNoteProvider), same(restoredB));
        expect(container.read(selectedNoteIdProvider), 'B');
        // The intercepted result cannot mount; only the post-refusal retry
        // may install B, once Core has confirmed it still exists.
        expect(api.openNoteCalls, ['A', 'B', 'B']);
      },
    );

    testWidgets('a terminal delete warning closes the dead editor instead of '
        'restoring it', (tester) async {
      final api = _LifecycleApi()
        ..lifecycleWarning = const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'injected commit failure',
        );
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('gone'));
      container.read(selectedNoteIdProvider.notifier).select('gone');

      final outcome = await container
          .read(lifecycleActionsProvider)
          .deleteNote('gone');

      expect(
        (outcome as LifecycleCompleted).warning,
        same(api.lifecycleWarning),
      );
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(editorInputBlockedProvider), isFalse);
    });

    testWidgets('deleting a directory closes an open note from inside it', (
      tester,
    ) async {
      final api = _LifecycleApi()..deleteDirectoryResult = ['x', 'inside/old'];
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('inside/old'));
      container.read(selectedNoteIdProvider.notifier).select('inside/old');

      final outcome = await container
          .read(lifecycleActionsProvider)
          .deleteDirectory('inside');

      expect(outcome, isA<LifecycleCompleted>());
      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
    });

    testWidgets('a delayed note delete cannot close a recreated selection', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _LifecycleApi()..deleteNoteGate = gate;
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('gone'));
      container.read(selectedNoteIdProvider.notifier).select('gone');
      final pending = container
          .read(lifecycleActionsProvider)
          .deleteNote('gone');
      await tester.pump();
      final recreated = stateFor('gone', title: 'recreated');
      container.read(activeNoteProvider.notifier).adopt(recreated);
      container.read(selectedNoteIdProvider.notifier).select('gone');
      gate.complete();
      await pending;
      expect(container.read(activeNoteProvider), same(recreated));
      expect(container.read(selectedNoteIdProvider), 'gone');
    });

    testWidgets(
      'a delayed directory delete cannot close a reanchored selection',
      (tester) async {
        final gate = Completer<void>();
        final api = _LifecycleApi()
          ..deleteDirectoryGate = gate
          ..deleteDirectoryResult = ['old/inside'];
        late ProviderContainer container;
        await tester.pumpWidget(_probeHarness(api, (c) => container = c));
        addTearDown(container.dispose);
        container
            .read(activeNoteProvider.notifier)
            .adopt(stateFor('old/inside'));
        container.read(selectedNoteIdProvider.notifier).select('old/inside');
        final pending = container
            .read(lifecycleActionsProvider)
            .deleteDirectory('old');
        await tester.pump();
        final reanchored = stateFor('new/inside');
        container.read(activeNoteProvider.notifier).adopt(reanchored);
        container
            .read(selectedNoteIdProvider.notifier)
            .selectForLifecycle('new/inside');
        gate.complete();
        await pending;
        expect(container.read(activeNoteProvider), same(reanchored));
        expect(container.read(selectedNoteIdProvider), 'new/inside');
      },
    );
  });

  group('reload raced by lifecycle', () {
    Future<ProviderContainer> prepare(
      WidgetTester tester,
      _LifecycleApi api,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(_probeHarness(api, (c) => container = c));
      addTearDown(container.dispose);
      container.read(activeNoteProvider.notifier).adopt(stateFor('Old/Note'));
      container.read(selectedNoteIdProvider.notifier).select('Old/Note');
      return container;
    }

    testWidgets('a delayed reload result cannot overwrite a lifecycle rename', (
      tester,
    ) async {
      final reload = Completer<NoteState>();
      final renamed = stateFor('Renamed/Note');
      final api = _LifecycleApi()
        ..reloadNoteGate = reload
        ..renameNoteResult = (renamed, effects());
      final container = await prepare(tester, api);

      final reloadFuture = container
          .read(activeNoteProvider.notifier)
          .reloadFromDisk();
      await tester.pump();
      await container
          .read(lifecycleActionsProvider)
          .renameNote('Old/Note', 'Renamed');
      reload.complete(stateFor('Old/Note', title: 'stale disk state'));
      await reloadFuture;

      expect(container.read(activeNoteProvider), same(renamed));
      expect(container.read(selectedNoteIdProvider), 'Renamed/Note');
      expect(container.read(editorErrorProvider), isNull);
    });

    testWidgets('a delayed reload result cannot overwrite a lifecycle move', (
      tester,
    ) async {
      final reload = Completer<NoteState>();
      final moved = stateFor('Archive/Note');
      final api = _LifecycleApi()
        ..reloadNoteGate = reload
        ..moveNoteResult = (moved, effects());
      final container = await prepare(tester, api);

      final reloadFuture = container
          .read(activeNoteProvider.notifier)
          .reloadFromDisk();
      await tester.pump();
      await container
          .read(lifecycleActionsProvider)
          .moveNote('Old/Note', 'Archive');
      reload.complete(stateFor('Old/Note', title: 'stale disk state'));
      await reloadFuture;

      expect(container.read(activeNoteProvider), same(moved));
      expect(container.read(selectedNoteIdProvider), 'Archive/Note');
      expect(container.read(editorErrorProvider), isNull);
    });

    testWidgets('a delayed reload error is ignored after lifecycle deletion', (
      tester,
    ) async {
      final reload = Completer<NoteState>();
      final api = _LifecycleApi()..reloadNoteGate = reload;
      final container = await prepare(tester, api);

      final reloadFuture = container
          .read(activeNoteProvider.notifier)
          .reloadFromDisk();
      await tester.pump();
      await container.read(lifecycleActionsProvider).deleteNote('Old/Note');
      reload.completeError(StateError('stale reload failure'));
      await reloadFuture;

      expect(container.read(activeNoteProvider), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(editorErrorProvider), isNull);
    });
  });

  // -- Widget level: the tree surface --------------------------------------

  testWidgets('creating a note from a directory menu shows it in the tree '
      'and selects it', (WidgetTester tester) async {
    final created = stateFor('Projects/New note', title: 'New note');
    final api = _LifecycleApi(tree: [directory('Projects', 'Projects', [])])
      ..createNoteResult = created;
    await _pumpTree(tester, api);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await _invokeRowAction(tester, 'directory Projects', 'New note here');

    // The prompt dialog asks for a title before anything reaches the Core.
    await tester.enterText(find.byType(TextField), 'New note');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(api.calls, ['createNote:Projects:New note']);
    final context = tester.element(find.byType(Scaffold));
    final container = ProviderScope.containerOf(context);
    expect(container.read(selectedNoteIdProvider), created.metadata.id);

    // Simulate the post-invalidation refetch carrying the new Note.
    api.tree = [
      directory('Projects', 'Projects', [
        noteNode(created.metadata.id, 'New note', created.metadata.path),
      ]),
    ];
    container.invalidate(workspaceTreeProvider);
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsOneWidget);
  });

  testWidgets('deletion is offered only behind confirmation, and cancelling '
      'reaches nothing', (WidgetTester tester) async {
    final api = _LifecycleApi(
      tree: [noteNode('doomed', 'Doomed', 'Doomed.md')],
    );
    await _pumpTree(tester, api);

    await _invokeRowAction(tester, 'note Doomed', 'Delete');

    // The confirmation gate appears BEFORE any delete call.
    expect(find.textContaining('Delete note'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('deleteNote')), isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('deleteNote')), isEmpty);

    // Confirming is what releases the call.
    await _invokeRowAction(tester, 'note Doomed', 'Delete');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('deleteNote:doomed'));
  });

  testWidgets('deleting the open note clears a stale editor error along '
      'with the note', (WidgetTester tester) async {
    // The editor pane checks the error surface before the null-note branch,
    // so a failure left over from the doomed note would outlive its deletion
    // unless `clear()` resets it — the deleted note can no longer be
    // retried, so its error panel names an impossibility.
    final api = _LifecycleApi(tree: [noteNode('doomed', 'Doomed', 'Doomed.md')])
      ..openStates = {'doomed': stateFor('doomed', title: 'Doomed')};
    late ProviderContainer container;
    await tester.pumpWidget(_probeHarness(api, (c) => container = c));
    addTearDown(container.dispose);

    final controller = container.read(activeNoteProvider.notifier);
    container
        .read(editorErrorProvider.notifier)
        .report(AppError.pathUnavailable('open refused: Doomed.md'));
    await controller.open('doomed');
    expect(container.read(activeNoteProvider), isNotNull);

    await container.read(lifecycleActionsProvider).deleteNote('doomed');
    await tester.pumpAndSettle();

    expect(container.read(activeNoteProvider), isNull);
    expect(container.read(selectedNoteIdProvider), isNull);
    expect(container.read(editorErrorProvider), isNull);
  });

  testWidgets('directory deletion confirms that contained notes go with it', (
    WidgetTester tester,
  ) async {
    final api = _LifecycleApi(tree: [directory('Projects', 'Projects', [])]);
    await _pumpTree(tester, api);

    await _invokeRowAction(tester, 'directory Projects', 'Delete');
    expect(find.textContaining('Every note inside'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('deleteDirectory')), isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('deleteDirectory')), isEmpty);
  });

  testWidgets('a rejected rename collision is reported verbatim and the '
      'Core is not asked twice', (WidgetTester tester) async {
    final api = _LifecycleApi(tree: [noteNode('n1', 'Original', 'Original.md')])
      ..renameNoteError = AppError.pathUnavailable('Taken.md already exists');
    await _pumpTree(tester, api);

    await _invokeRowAction(tester, 'note Original', 'Rename');
    await tester.enterText(find.byType(TextField), 'Clash');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(api.calls, ['renameNote:n1:Clash']); // one attempt, no retry
    expect(find.textContaining('That name cannot be used'), findsOneWidget);
  });

  testWidgets('a completed lifecycle warning uses the localized dismissible '
      'status instead of a failure outcome', (tester) async {
    final api = _LifecycleApi();
    await _pumpTree(tester, api);

    report(
      tester.element(find.byType(Scaffold)),
      const LifecycleCompleted(
        'Renamed',
        warning: LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'Git index refresh failed',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'The change is applied, but its Git commit failed: '
        'Git index refresh failed',
      ),
      findsOneWidget,
    );
  });

  // -- The focus-refresh semantics (the subtlest clause) --------------------

  testWidgets('renaming A refreshes open note B\'s editable field from the '
      'returned state BEFORE the next keystroke', (WidgetTester tester) async {
    // B holds a Link to A. When A is renamed, the Core rewrites B's bytes;
    // B's own id does not change, so without an explicit reload B's editor
    // keeps the pre-rewrite source — and its next update_block substitutes
    // that back, reverting the rewrite from inside the editor.
    final renamedA = stateFor('a-renamed', title: 'A renamed');
    final staleB = stateFor('b', ast: [paragraph('see [[A]] old target')]);
    final freshB = stateFor('b', ast: [paragraph('see [[A]] new target')]);
    final api = _LifecycleApi()
      ..renameNoteResult = (renamedA, effects(rewritten: ['b']))
      ..openStates = {'b': freshB};

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: Editor()));
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container.read(activeNoteProvider.notifier).adopt(staleB);
    container.read(selectedNoteIdProvider.notifier).select('b');
    await tester.pumpAndSettle();

    // Sanity: the field shows the pre-rewrite source, and typing into it
    // right now would substitute exactly that stale source back — the
    // failure this criterion exists to prevent. Under EDIT-F002's
    // promote-on-focus model the Block is formatted until tapped, so stage
    // its working source and tap it into its editable form first.
    api.stagedBlockSources['0'] = ['see [[A]] old target'];
    await tester.tap(
      find.byKey(const ValueKey('block-0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    // A writable EditableText, not the error surface's read-only
    // SelectableText (which also hosts an internal EditableText).
    EditableText fieldOf(WidgetTester t) => t
        .widgetList<EditableText>(
          find.byWidgetPredicate((w) => w is EditableText && !w.readOnly),
        )
        .single;
    expect(fieldOf(tester).controller.text, 'see [[A]] old target');
    await tester.enterText(find.byType(EditableText), 'stale edit');
    await tester.pumpAndSettle();
    expect(api.lastUpdateBlockSource, 'stale edit');

    // Stage the post-rewrite bytes the resync will refetch once the reload's
    // returned state lands.
    api.stagedBlockSources['0'] = ['see [[A]] new target'];
    await container.read(lifecycleActionsProvider).renameNote('a', 'A renamed');
    await tester.pumpAndSettle();

    // The reload happened because `rewritten` named B — not because anything
    // looked wrong.
    expect(api.openNoteCalls, ['b']);

    // The editable field was refreshed from the returned state: it now shows
    // the rewritten source, so the NEXT keystroke goes out based on the
    // Core's post-rewrite bytes rather than substituting the old ones back.
    expect(fieldOf(tester).controller.text, 'see [[A]] new target');
    await tester.enterText(
      find.byType(EditableText),
      'see [[A]] new target +1',
    );
    await tester.pumpAndSettle();
    expect(api.lastUpdateBlockSource, 'see [[A]] new target +1');
    expect(api.lastUpdateBlockSource, isNot(contains('old target')));
  });

  testWidgets('a gated lifecycle success makes the raw editor read-only '
      'before Core can replace its source', (WidgetTester tester) async {
    final gate = Completer<void>();
    final renamed = stateFor(
      'Renamed',
      title: 'Renamed',
      ast: [paragraph('authoritative replacement')],
    );
    final api = _LifecycleApi()
      ..renameNoteGate = gate
      ..renameNoteResult = (renamed, effects());
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: Editor()));
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor('Old', ast: [paragraph('editable before rename')]));
    container.read(selectedNoteIdProvider.notifier).select('Old');
    api.stagedBlockSources['0'] = ['editable before rename'];
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-0')));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);
    expect(tester.widget<EditableText>(field).readOnly, isFalse);

    final action = container
        .read(lifecycleActionsProvider)
        .renameNote('Old', 'Renamed');
    await tester.pump();
    expect(container.read(editorInputBlockedProvider), isTrue);
    expect(tester.widget<EditableText>(field).readOnly, isTrue);

    // A platform value already queued when the Core admission gate closes is
    // restored to the last Core-backed source rather than becoming an
    // unbuffered controller-only edit that the returned state would discard.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'lost local mutation',
        selection: TextSelection.collapsed(offset: 19),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(field).controller.text,
      'editable before rename',
    );
    expect(api.calls.where((call) => call.startsWith('updateBlock:')), isEmpty);

    gate.complete();
    await action;
    await tester.pumpAndSettle();
    expect(container.read(editorInputBlockedProvider), isFalse);
    expect(container.read(activeNoteProvider), same(renamed));
    expect(find.text('authoritative replacement'), findsOneWidget);
  });

  testWidgets('a refused gated lifecycle restores edit authority without '
      'replaying rejected input', (WidgetTester tester) async {
    final gate = Completer<void>();
    final api = _LifecycleApi()
      ..renameNoteGate = gate
      ..renameNoteError = StateError('rename refused');
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: Editor()));
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor('Old', ast: [paragraph('still editable')]));
    container.read(selectedNoteIdProvider.notifier).select('Old');
    api.stagedBlockSources['0'] = ['still editable'];
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-0')));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);

    final action = container
        .read(lifecycleActionsProvider)
        .renameNote('Old', 'Renamed');
    await tester.pump();
    expect(tester.widget<EditableText>(field).readOnly, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'rejected during lifecycle',
        selection: TextSelection.collapsed(offset: 25),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(field).controller.text,
      'still editable',
    );
    expect(api.calls.where((call) => call.startsWith('updateBlock:')), isEmpty);

    gate.complete();
    expect(await action, isA<LifecycleFailed>());
    await tester.pump();
    expect(container.read(editorInputBlockedProvider), isFalse);
    expect(tester.widget<EditableText>(field).readOnly, isFalse);

    await tester.enterText(field, 'recovered after refusal');
    await tester.pump();
    expect(api.lastUpdateBlockSource, 'recovered after refusal');
  });

  testWidgets('a lifecycle gate preserves and commits a live IME composition '
      'after a refused operation', (WidgetTester tester) async {
    final gate = Completer<void>();
    final api = _LifecycleApi()
      ..renameNoteGate = gate
      ..renameNoteError = StateError('rename refused');
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: Editor()));
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor('Old', ast: [paragraph('base')]));
    container.read(selectedNoteIdProvider.notifier).select('Old');
    api.stagedBlockSources['0'] = ['base'];
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-0')));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);

    final action = container
        .read(lifecycleActionsProvider)
        .renameNote('Old', 'Renamed');
    expect(container.read(editorInputBlockedProvider), isTrue);

    // The platform can deliver marked text after the synchronous provider
    // gate closes but before Flutter paints `readOnly`. It must remain
    // platform-owned until the IME explicitly clears `composing`.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(tester.widget<EditableText>(field).readOnly, isTrue);
    expect(tester.widget<EditableText>(field).controller.text, 'base中');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(tester.widget<EditableText>(field).controller.text, 'base中');
    expect(api.calls.where((call) => call.startsWith('updateBlock:')), isEmpty);

    gate.complete();
    expect(await action, isA<LifecycleFailed>());
    await tester.pump();
    await tester.pump();

    expect(container.read(editorInputBlockedProvider), isFalse);
    expect(tester.widget<EditableText>(field).readOnly, isFalse);
    expect(tester.widget<EditableText>(field).controller.text, 'base中');

    // Flutter's read-only test client deliberately leaves its marked range
    // untouched while the gate is closed. Once the field is writable again,
    // issue the IME's explicit composition-commit value; this is the
    // deterministic widget-test equivalent of the platform finishing marked
    // text after a lifecycle action.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(api.lastUpdateBlockSource, 'base中');
  });

  // -- IME continuity across lifecycle rekeys ------------------------------

  for (final fixture in _rekeyFixtures) {
    for (final completion in _ImeCompletion.values) {
      testWidgets(
        '${fixture.description} keeps a ${completion.description} IME '
        'composition on the carried Core session',
        (tester) async {
          const base = 'cursor base';
          const candidate = '中cursor base';
          const rebased = '中cursor base!';
          final authoritative = completion == _ImeCompletion.live
              ? 'cursor base!'
              : rebased;
          final returned = stateFor(
            fixture.newId,
            ast: [paragraph(authoritative)],
          );
          final api = _LifecycleApi();
          fixture.configure(api, returned);
          late ProviderContainer container;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [rustApiProvider.overrideWithValue(api)],
              child: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: const Scaffold(body: Editor()),
                  );
                },
              ),
            ),
          );
          addTearDown(container.dispose);
          container
              .read(activeNoteProvider.notifier)
              .adopt(stateFor(fixture.oldId, ast: [paragraph(base)]));
          container.read(selectedNoteIdProvider.notifier).select(fixture.oldId);
          api.stagedBlockSources['0'] = [base, authoritative];
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('block-0')));
          await tester.pumpAndSettle();

          final field = find.byWidgetPredicate(
            (widget) => widget is EditableText && !widget.readOnly,
          );
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: candidate,
              composing: TextRange(start: 0, end: 1),
              selection: TextSelection.collapsed(offset: 1),
            ),
          );
          await tester.pump();
          if (completion == _ImeCompletion.completed) {
            tester.testTextInput.updateEditingValue(
              const TextEditingValue(
                text: candidate,
                selection: TextSelection.collapsed(offset: 1),
              ),
            );
            await tester.pump();
          }

          await fixture.invoke(container.read(lifecycleActionsProvider));
          await tester.pump();

          // A rekey retains the exact same raw field and focus. For a live
          // candidate, the field still exposes Flutter's non-empty composing
          // range until the IME explicitly completes it.
          expect(
            container.read(activeNoteProvider)!.metadata.id,
            fixture.newId,
          );
          expect(field, findsOneWidget);
          expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
          expect(
            tester.widget<EditableText>(field).controller.selection,
            const TextSelection.collapsed(offset: 1),
          );
          if (completion == _ImeCompletion.live) {
            expect(
              tester.widget<EditableText>(field).controller.value.composing,
              const TextRange(start: 0, end: 1),
            );
            tester.testTextInput.updateEditingValue(
              const TextEditingValue(
                text: candidate,
                selection: TextSelection.collapsed(offset: 1),
              ),
            );
            await tester.pump();
            await tester.pump();
          }

          expect(tester.widget<EditableText>(field).controller.text, rebased);
          expect(
            tester.widget<EditableText>(field).controller.value.composing,
            TextRange.empty,
          );
          await tester.enterText(field, '$rebased next');
          await tester.pump();
          expect(api.lastUpdateBlockSource, '$rebased next');
          expect(api.updateBlockNoteIds.last, fixture.newId);
          expect(
            api.updateBlockNoteIds.skipWhile((id) => id == fixture.oldId),
            isNot(contains(fixture.oldId)),
            reason: 'no post-rekey update may address the old Core session',
          );
        },
      );
    }
  }

  testWidgets('a lifecycle rekey retains an IME resync conflict for copying', (
    WidgetTester tester,
  ) async {
    const oldId = 'Projects/Note';
    const newId = 'Projects/Renamed';
    final api = _LifecycleApi()
      ..renameNoteResult = (
        stateFor(newId, ast: [paragraph('base!')]),
        effects(),
      );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: Editor()),
            );
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor(oldId, ast: [paragraph('base')]));
    container.read(selectedNoteIdProvider.notifier).select(oldId);
    api.stagedBlockSources['0'] = ['base', 'base!'];
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-0')));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (widget) => widget is EditableText && !widget.readOnly,
    );

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    await container.read(lifecycleActionsProvider).renameNote(oldId, 'Renamed');
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(container.read(activeNoteProvider)!.metadata.id, newId);
    expect(field, findsOneWidget);
    expect(tester.widget<EditableText>(field).controller.text, 'base中');
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(container.read(keystrokeWriteFailureProvider), isA<StateError>());
    expect(api.updateBlockNoteIds, everyElement(oldId));
  });

  testWidgets('ordinary navigation still discards a focused composition', (
    WidgetTester tester,
  ) async {
    final api = _LifecycleApi();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: Editor()),
            );
          },
        ),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor('A', ast: [paragraph('base')]));
    container.read(selectedNoteIdProvider.notifier).select('A');
    api.stagedBlockSources['0'] = ['base'];
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-0')));
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    container
        .read(activeNoteProvider.notifier)
        .adopt(stateFor('B', ast: [paragraph('unrelated note')]));
    container.read(selectedNoteIdProvider.notifier).select('B');
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && !widget.readOnly,
      ),
      findsNothing,
    );
    expect(find.text('unrelated note'), findsOneWidget);
    expect(api.updateBlockNoteIds, ['A']);
  });
}

enum _ImeCompletion {
  live('live'),
  completed('completed');

  const _ImeCompletion(this.description);

  final String description;
}

class _RekeyFixture {
  const _RekeyFixture({
    required this.description,
    required this.oldId,
    required this.newId,
    required this.configure,
    required this.invoke,
  });

  final String description;
  final String oldId;
  final String newId;
  final void Function(_LifecycleApi api, NoteState returned) configure;
  final Future<LifecycleOutcome> Function(LifecycleActions actions) invoke;
}

final _rekeyFixtures = [
  _RekeyFixture(
    description: 'a successful note rename',
    oldId: 'Projects/Note',
    newId: 'Projects/Renamed',
    configure: (api, returned) => api.renameNoteResult = (returned, effects()),
    invoke: (actions) => actions.renameNote('Projects/Note', 'Renamed'),
  ),
  _RekeyFixture(
    description: 'a successful note move',
    oldId: 'Projects/Note',
    newId: 'Archive/Note',
    configure: (api, returned) => api.moveNoteResult = (returned, effects()),
    invoke: (actions) => actions.moveNote('Projects/Note', 'Archive'),
  ),
  _RekeyFixture(
    description: 'a successful containing-directory rename',
    oldId: 'Projects/Note',
    newId: 'Renamed/Note',
    configure: (api, returned) {
      api
        ..renameDirectoryResult = effects(
          remapped: const [
            IdRemap(oldId: 'Projects/Note', newId: 'Renamed/Note'),
          ],
        )
        ..openStates = {'Renamed/Note': returned};
    },
    invoke: (actions) => actions.renameDirectory('Projects', 'Renamed'),
  ),
];

/// Harness exposing the underlying [ProviderContainer] while keeping the
/// overrides in one place.
Widget _probeHarness(_LifecycleApi api, void Function(ProviderContainer) got) =>
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: Consumer(
        builder: (context, ref, _) {
          got(ProviderScope.containerOf(context));
          return const SizedBox.shrink();
        },
      ),
    );
