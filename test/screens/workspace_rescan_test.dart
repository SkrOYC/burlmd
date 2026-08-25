import 'dart:async';

import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] standing in for the Core at the rescan level: serves a
/// mutable tree (the stand-in for "the bundle on disk", which a test edits
/// to simulate an external tool writing while the app runs), records Core
/// calls in order, and reports a controllable write-tier status for any open
/// Note so the unflushed-edits guard can be exercised without real drafts.
class _RescanRustApi extends RustApi {
  /// The tree `workspace_tree` currently serves. Tests reassign this to
  /// simulate external writes landing between rescans.
  List<TreeNode> currentTree;

  /// Whether the fake write tier reports unwritten edits for an open Note.
  bool unwrittenEdits = false;
  final Map<String, bool> unwrittenEditsByNote = {};
  final Set<String> restoredDraftIds = {};

  int treeFetches = 0;
  final List<String> calls = [];
  final List<String> blockUpdates = [];
  Completer<NoteState>? reloadGate;
  Completer<void>? closeGate;

  _RescanRustApi(this.currentTree);

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async =>
      const WorkspaceInfo(
        id: 'ws',
        name: 'workspace',
        provider: 'local',
        localPath: '/tmp/workspace',
      );

  @override
  Future<List<TreeNode>> workspaceTree() async {
    treeFetches++;
    return currentTree;
  }

  @override
  NoteWriteStatus noteWriteStatus(String noteId) => NoteWriteStatus(
    lastWrittenAt: null,
    lastError: null,
    hasUnwrittenEdits: unwrittenEditsByNote[noteId] ?? unwrittenEdits,
  );

  @override
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
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
      restoredFromDraft: restoredDraftIds.contains(noteId),
    );
  }

  @override
  Future<NoteState> reloadNote(String noteId) {
    calls.add('reload:$noteId');
    final gate = reloadGate;
    if (gate != null) return gate.future;
    return openNote(noteId);
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
    final gate = closeGate;
    if (gate != null && !gate.isCompleted) await gate.future;
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    blockUpdates.add('$noteId:${blockPath.join(',')}:$newSource');
  }
}

TreeNode _note(String id, String title) =>
    TreeNode.note(id: id, title: title, path: '$title.md');

Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  _RescanRustApi api, {
  required Future<int> Function() reindex,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      rustApiProvider.overrideWithValue(api),
      reindexWorkspaceProvider.overrideWithValue(reindex),
      // The shell now mounts the write-tier surface, whose monitor arms a
      // periodic timer; disable polling here (no fake clock to fire it),
      // matching draft_recovery_test.dart's pattern.
      writeStatusPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WorkspaceScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

TextButton _rescanButton(WidgetTester tester) => tester.widget<TextButton>(
  find.ancestor(
    of: find.text('Rescan workspace'),
    matching: find.byType(TextButton),
  ),
);

void main() {
  testWidgets('rescanning surfaces an externally added note without a restart '
      '(CAP-WS-06 criterion 1)', (tester) async {
    // The bundle on disk starts with one Note; an external tool adds a
    // second one while the app runs.
    final api = _RescanRustApi([_note('a', 'Alpha')]);
    var reindexCalls = 0;
    final gate = Completer<int>();
    var release = false;
    await _pumpShell(
      tester,
      api,
      reindex: () async {
        reindexCalls++;
        // Simulate the external write landing during the reindex walk.
        api.currentTree = [_note('a', 'Alpha'), _note('b', 'Beta')];
        if (!release) return gate.future;
        return 2;
      },
    );

    expect(find.text('Beta'), findsNothing);
    expect(_rescanButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Rescan workspace'));
    await tester.pump();

    // While the reindex round trip is in flight the affordance disables,
    // so a second invocation cannot stack on top of it.
    expect(_rescanButton(tester).onPressed, isNull);

    release = true;
    gate.complete(2);
    await tester.pumpAndSettle();

    // One full-reindex call drove the refresh...
    expect(reindexCalls, 1);
    // ...and the new Note renders with no restart and no further fetch
    // queued behind anything.
    expect(find.text('Beta'), findsOneWidget);
    expect(_rescanButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'the rescan affordance refuses while the open note holds unwritten '
    'edits, but works again once they are written '
    '(CAP-WS-06 criterion 2 / SHEL-E008 STOP)',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha'), _note('b', 'Beta')]);
      var reindexCalls = 0;
      final container = await _pumpShell(
        tester,
        api,
        reindex: () async {
          reindexCalls++;
          return 1;
        },
      );

      // Open a Note through the production navigation path.
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(container.read(activeNoteProvider), isNotNull);
      expect(api.calls, ['open:a']);

      // Clean write tier: an open-but-flushed Note does not block rescan —
      // the guard keys off unwritten edits, not merely any open session.
      api.unwrittenEdits = false;
      await tester.tap(find.text('Rescan workspace'));
      await tester.pumpAndSettle();
      expect(reindexCalls, 1);

      // Now buffer edits that have not reached disk.
      api.unwrittenEdits = true;

      // Switching Notes rebuilds the sidebar, so the affordance is derived
      // fresh against the dirty write tier and becomes unavailable.
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(api.calls, ['open:a', 'close:a', 'open:b']);
      expect(_rescanButton(tester).onPressed, isNull);

      // Invoking the controller directly anyway (the "stale frame slipped
      // past the disabled button" case) is refused: no reindex runs, the
      // tree is not refetched, and the refusal names why.
      final fetchesBeforeRefusal = api.treeFetches;
      await container.read(rescanStateProvider.notifier).run();
      await tester.pumpAndSettle();
      expect(reindexCalls, 1);
      expect(api.treeFetches, fetchesBeforeRefusal);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('unsaved edits'), findsOneWidget);

      // Once the edits are written, the same invocation goes through.
      api.unwrittenEdits = false;
      await container.read(rescanStateProvider.notifier).run();
      await tester.pumpAndSettle();
      expect(reindexCalls, 2);
    },
  );

  testWidgets(
    'a failed reindex surfaces a message naming the failure and the tree '
    'keeps its previous view (CAP-WS-06 criterion 3)',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha')]);
      final failWith = Exception('unreadable file: Notes/Broken.md');
      await _pumpShell(
        tester,
        api,
        reindex: () async {
          // Even though disk now holds two Notes, the reindex fails — and
          // the UI must not show a partial view of what it did read.
          api.currentTree = [_note('a', 'Alpha'), _note('b', 'Beta')];
          throw failWith;
        },
      );

      expect(api.treeFetches, 1);
      await tester.tap(find.text('Rescan workspace'));
      await tester.pumpAndSettle();

      // The failure is named on screen...
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('unreadable file'), findsOneWidget);
      // ...the previous view stands — no partial refresh, no extra fetch...
      expect(api.treeFetches, 1);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      // ...and the affordance recovers for another attempt.
      expect(_rescanButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'a delayed clean rescan blocks typing and navigation, then restores both admissions',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha'), _note('b', 'Beta')]);
      final reindexGate = Completer<int>();
      final container = await _pumpShell(
        tester,
        api,
        reindex: () => reindexGate.future,
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescan workspace'));
      await tester.pump();

      expect(container.read(rescanEditingProvider), 1);
      expect(container.read(editorInputBlockedProvider), isTrue);
      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isFalse,
      );
      container.read(activeNoteProvider.notifier).updateBlock([0], 'blocked');
      expect(api.blockUpdates, isEmpty);
      expect(container.read(selectedNoteIdProvider), 'a');
      expect(container.read(activeNoteProvider)!.metadata.id, 'a');

      reindexGate.complete(2);
      await tester.pumpAndSettle();

      expect(container.read(rescanEditingProvider), 0);
      expect(container.read(editorInputBlockedProvider), isFalse);
      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isTrue,
      );
      await container.read(activeNoteProvider.notifier).open('b');
      container.read(activeNoteProvider.notifier).updateBlock([0], 'retained');
      expect(api.blockUpdates, ['b:0:retained']);
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
    },
  );

  testWidgets(
    'a delayed clean A-to-B switch refuses rescan until B is reconciled, then allows retry',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha'), _note('b', 'Beta')]);
      final closeGate = Completer<void>();
      api.closeGate = closeGate;
      var reindexCalls = 0;
      final container = await _pumpShell(
        tester,
        api,
        reindex: () async {
          reindexCalls++;
          return 2;
        },
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(container.read(noteSwitchingProvider), isTrue);
      expect(_rescanButton(tester).onPressed, isNull);

      await container.read(rescanStateProvider.notifier).run();
      expect(reindexCalls, 0);
      expect(container.read(rescanEditingProvider), 0);
      expect(container.read(rescanStateProvider).refusedReason, isNotNull);

      closeGate.complete();
      await tester.pumpAndSettle();
      expect(container.read(noteSwitchingProvider), isFalse);
      expect(container.read(selectedNoteIdProvider), 'b');
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');

      await container.read(rescanStateProvider.notifier).run();
      await tester.pumpAndSettle();
      expect(reindexCalls, 1);
      expect(container.read(rescanEditingProvider), 0);
    },
  );

  testWidgets(
    'a delayed switch to restored dirty B refuses rescan until its draft is clean',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha'), _note('b', 'Beta')]);
      final closeGate = Completer<void>();
      api
        ..closeGate = closeGate
        ..restoredDraftIds.add('b')
        ..unwrittenEditsByNote['b'] = true;
      var reindexCalls = 0;
      final container = await _pumpShell(
        tester,
        api,
        reindex: () async {
          reindexCalls++;
          return 2;
        },
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await container.read(rescanStateProvider.notifier).run();
      expect(reindexCalls, 0);
      expect(container.read(rescanEditingProvider), 0);

      closeGate.complete();
      await tester.pumpAndSettle();
      expect(container.read(activeNoteProvider)!.metadata.id, 'b');
      expect(container.read(activeNoteProvider)!.restoredFromDraft, isTrue);
      expect(container.read(selectedNoteIdProvider), 'b');

      await container.read(rescanStateProvider.notifier).run();
      expect(reindexCalls, 0);
      expect(
        container.read(rescanStateProvider).refusedReason,
        contains('unsaved edits'),
      );
      expect(container.read(rescanEditingProvider), 0);

      api.unwrittenEditsByNote['b'] = false;
      await container.read(rescanStateProvider.notifier).run();
      await tester.pumpAndSettle();
      expect(reindexCalls, 1);
      expect(container.read(rescanEditingProvider), 0);
    },
  );

  testWidgets(
    'a pending note reload refuses a rescan without opening a second Core boundary',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha')]);
      final reloadGate = Completer<NoteState>();
      api.reloadGate = reloadGate;
      var reindexCalls = 0;
      final container = await _pumpShell(
        tester,
        api,
        reindex: () async {
          reindexCalls++;
          return 1;
        },
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      final reload = container
          .read(activeNoteProvider.notifier)
          .reloadFromDisk();
      await tester.pump();

      expect(container.read(reloadEditingProvider), 1);
      expect(_rescanButton(tester).onPressed, isNull);
      await container.read(rescanStateProvider.notifier).run();
      expect(reindexCalls, 0);
      expect(container.read(rescanStateProvider).refusedReason, isNotNull);
      expect(container.read(rescanEditingProvider), 0);

      reloadGate.complete(
        NoteState(
          ast: const [],
          metadata: const NoteMetadata(
            id: 'a',
            path: 'a.md',
            title: 'Alpha from disk',
            lastModified: 0,
            okfConformant: true,
          ),
          baseRevision: 'disk',
          restoredFromDraft: false,
        ),
      );
      await reload;
      await tester.pump();

      expect(container.read(reloadEditingProvider), 0);
      expect(_rescanButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'a failed rescan releases input and refuses overlapping lifecycle work without a Core call',
    (tester) async {
      final api = _RescanRustApi([_note('a', 'Alpha')]);
      final reindexGate = Completer<int>();
      final container = await _pumpShell(
        tester,
        api,
        reindex: () => reindexGate.future,
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescan workspace'));
      await tester.pump();
      expect(container.read(rescanEditingProvider), 1);

      final lifecycle = await container
          .read(lifecycleActionsProvider)
          .createDirectory('during-rescan');
      expect(lifecycle, isA<LifecycleFailed>());
      expect(api.calls, ['open:a']);
      expect(
        container.read(selectedNoteIdProvider.notifier).select('b'),
        isFalse,
      );

      reindexGate.completeError(Exception('disk unavailable'));
      await tester.pumpAndSettle();

      expect(container.read(rescanEditingProvider), 0);
      expect(container.read(editorInputBlockedProvider), isFalse);
      expect(_rescanButton(tester).onPressed, isNotNull);
      container.read(activeNoteProvider.notifier).updateBlock([
        0,
      ], 'after-error');
      expect(api.blockUpdates, ['a:0:after-error']);
    },
  );
}
