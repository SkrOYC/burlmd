import 'dart:async';

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

  int treeFetches = 0;
  final List<String> calls = [];

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
    hasUnwrittenEdits: unwrittenEdits,
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
      restoredFromDraft: false,
    );
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
  }
}

TreeNode _note(String id, String title) =>
    TreeNode.note(id: id, title: title, path: '$title.md');

Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  _RescanRustApi api, {
  required Future<int> Function() reindex,
}) async {
  final container = ProviderContainer(
    overrides: [
      rustApiProvider.overrideWithValue(api),
      reindexWorkspaceProvider.overrideWithValue(reindex),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WorkspaceScreen()),
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
}
