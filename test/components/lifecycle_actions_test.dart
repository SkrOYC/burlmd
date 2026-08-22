import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  (NoteState, LifecycleEffects)? renameNoteResult;
  Object? renameNoteError;
  (NoteState, LifecycleEffects)? moveNoteResult;
  Object? moveNoteError;
  Object? deleteNoteError;
  Object? createDirectoryError;
  LifecycleEffects? renameDirectoryResult;
  Object? renameDirectoryError;
  List<String>? deleteDirectoryResult;

  /// What `open_note` returns per id — for already-open Notes the live
  /// session state (post-rewrite, post-remap), which is exactly what the
  /// production re-anchor and rewritten-reload paths fetch.
  Map<String, NoteState> openStates = {};

  /// The last source text `update_block` received — the "next keystroke"
  /// probe for the focus-refresh criterion.
  String? lastUpdateBlockSource;

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    calls.add('updateBlock:$noteId');
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
    return openStates[noteId]!;
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('closeNote:$noteId');
  }

  @override
  Future<NoteState> createNote(String directoryPath, String title) async {
    calls.add('createNote:$directoryPath:$title');
    final error = createNoteError;
    if (error != null) throw error;
    return createNoteResult!;
  }

  @override
  Future<(NoteState, LifecycleEffects)> renameNote(
    String noteId,
    String newTitle,
  ) async {
    calls.add('renameNote:$noteId:$newTitle');
    final error = renameNoteError;
    if (error != null) throw error;
    return renameNoteResult!;
  }

  @override
  Future<(NoteState, LifecycleEffects)> moveNote(
    String noteId,
    String newDirectoryPath,
  ) async {
    calls.add('moveNote:$noteId:$newDirectoryPath');
    final error = moveNoteError;
    if (error != null) throw error;
    return moveNoteResult!;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    calls.add('deleteNote:$noteId');
    final error = deleteNoteError;
    if (error != null) throw error;
  }

  @override
  Future<void> createDirectory(String path) async {
    calls.add('createDirectory:$path');
    final error = createDirectoryError;
    if (error != null) throw error;
  }

  @override
  Future<LifecycleEffects> renameDirectory(String path, String newName) async {
    calls.add('renameDirectory:$path:$newName');
    final error = renameDirectoryError;
    if (error != null) throw error;
    return renameDirectoryResult!;
  }

  @override
  Future<List<String>> deleteDirectory(String path) async {
    calls.add('deleteDirectory:$path');
    return deleteDirectoryResult ?? const [];
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

Future<void> _pumpTree(WidgetTester tester, _LifecycleApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 300, child: WorkspaceTree())),
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
    // failure this criterion exists to prevent.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('see [[A]] old target'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stale edit');
    await tester.pumpAndSettle();
    expect(api.lastUpdateBlockSource, 'stale edit');

    await container.read(lifecycleActionsProvider).renameNote('a', 'A renamed');
    await tester.pumpAndSettle();

    // The reload happened because `rewritten` named B — not because anything
    // looked wrong.
    expect(api.openNoteCalls, ['b']);

    // The editable field was refreshed from the returned state: it now shows
    // the rewritten source, so the NEXT keystroke goes out based on the
    // Core's post-rewrite bytes rather than substituting the old ones back.
    expect(find.text('see [[A]] new target'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'see [[A]] new target +1');
    await tester.pumpAndSettle();
    expect(api.lastUpdateBlockSource, 'see [[A]] new target +1');
    expect(api.lastUpdateBlockSource, isNot(contains('old target')));
  });
}

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
