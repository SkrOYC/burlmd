import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] standing in for the Core at the shell level, with the
/// recovery and search surfaces' calls faked so the mounted wiring can be
/// exercised without the compiled Rust dylib.
class _MountingRustApi extends RustApi {
  _MountingRustApi(this.tree);

  final List<TreeNode> tree;

  /// What `pending_drafts` reports on startup.
  List<NoteMetadata> drafts = const [];

  /// What every `note_write_status` poll reports until a test changes it.
  NoteWriteStatus status = const NoteWriteStatus(hasUnwrittenEdits: false);

  /// What `search_notes` returns, with the query/limit it was issued with.
  List<NoteMetadata> searchResult = const [];
  String? searchQuery;
  int? searchLimit;

  /// Every open/close/search call in issue order.
  final List<String> calls = [];

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async =>
      const WorkspaceInfo(
        id: 'ws',
        name: 'workspace',
        provider: 'local',
        localPath: '/tmp/workspace',
      );

  @override
  Future<List<TreeNode>> workspaceTree() async => tree;

  @override
  Future<List<NoteMetadata>> pendingDrafts() async => drafts;

  @override
  NoteWriteStatus noteWriteStatus(String noteId) => status;

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

  @override
  Future<List<NoteMetadata>> searchNotes(String query, int limit) async {
    calls.add('search:$query:$limit');
    searchQuery = query;
    searchLimit = limit;
    return searchResult;
  }
}

TreeNode _treeNode(String id, String title) =>
    TreeNode.note(id: id, title: title, path: '$title.md');

NoteMetadata _metadata(String id, String title, {String? snippet}) =>
    NoteMetadata(
      id: id,
      path: '$id.md',
      title: title,
      lastModified: 0,
      snippet: snippet,
      okfConformant: true,
    );

Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  _MountingRustApi api,
) async {
  final container = ProviderContainer(
    overrides: [
      rustApiProvider.overrideWithValue(api),
      // No periodic timer in tests (there is no fake clock to fire it); the
      // monitor's *armed* state is still observable through its built state.
      writeStatusPollIntervalProvider.overrideWithValue(null),
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

void main() {
  testWidgets('the sidebar search affordance opens the search panel, passes '
      'its result limit to the Core, and a selected hit opens its note', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    api.searchResult = [
      _metadata('hit-1', 'Hit Note', snippet: '…matched text…'),
    ];
    final container = await _pumpShell(tester, api);

    // The panel is not on screen until the affordance is used…
    expect(find.text('Search notes'), findsNothing);

    await tester.tap(find.byTooltip('Search notes'));
    await tester.pumpAndSettle();

    // …and now the panel renders in the sidebar.
    expect(find.text('Search notes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'matched');
    await tester.pumpAndSettle();

    // The surface's own cap reached the Core as the parameter — the limit
    // belongs to the surface, never hardcoded in the UI layer below it.
    expect(api.searchQuery, 'matched');
    expect(api.searchLimit, 25);

    // Selecting a hit publishes through the same selection seam the tree
    // uses, which opens the Note through the production navigation path.
    expect(find.text('Hit Note'), findsOneWidget);
    await tester.tap(find.text('Hit Note'));
    await tester.pumpAndSettle();
    expect(container.read(selectedNoteIdProvider), 'hit-1');
    expect(api.calls.contains('open:hit-1'), isTrue);
  });

  testWidgets('drafts left by a previous session are listed above the tree '
      'on startup, and dismissing hides only the notice', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')])
      ..drafts = [_metadata('n-crash', 'Crash Journal')];

    await _pumpShell(tester, api);

    expect(find.text('Recovered drafts'), findsOneWidget);
    expect(find.text('Crash Journal'), findsOneWidget);

    // Dismissal hides the notice without touching the Core — no close, no
    // reopen, no draft discard (SHEL-E007's first STOP condition).
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Recovered drafts'), findsNothing);
    expect(api.calls.where((c) => !c.startsWith('search:')), isEmpty);
  });

  testWidgets('a clean startup shows no recovery notice', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    expect(find.text('Recovered drafts'), findsNothing);
  });

  testWidgets('a write-tier failure on the open note surfaces above the '
      'editor, and the write-tier monitor is armed while the shell is up', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')])
      ..status = const NoteWriteStatus(
        lastError: AppError.diskFull(),
        hasUnwrittenEdits: true,
      );

    final container = await _pumpShell(tester, api);

    // With no Note open there is nothing to poll: the monitor is idle.
    expect(container.read(writeTierMonitorProvider), isNull);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // Opening a Note arms the monitor — polling actually happens now that
    // the shell watches it, instead of failures being raised into nothing.
    expect(container.read(writeTierMonitorProvider), isNotNull);
    expect(
      container.read(writeTierMonitorProvider)?.lastError,
      isA<AppError_DiskFull>(),
    );

    // And the failure is visible where the user is looking: directly above
    // the editor pane.
    expect(find.textContaining('disk is full'), findsOneWidget);
  });
}
