import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] whose tree query never touches FFI, counting invocations so
/// tests can prove that expanding a Directory does not re-run the Core call
/// (`WSPC-D009`'s single-call contract, `SHEL-E003`'s no-reload criterion).
class _StubRustApi extends RustApi {
  _StubRustApi(this.tree);

  final List<TreeNode> tree;
  int workspaceTreeCalls = 0;

  @override
  Future<List<TreeNode>> workspaceTree() async {
    workspaceTreeCalls++;
    return tree;
  }
}

/// A [RustApi] whose tree query fails on its first call and serves a real
/// tree afterwards — the "index hiccup" flow-workspace-navigation.md's
/// failure path describes.
class _FlakyOnceRustApi extends RustApi {
  int calls = 0;

  @override
  Future<List<TreeNode>> workspaceTree() async {
    calls++;
    if (calls == 1) throw Exception('tree query refused');
    return [
      TreeNode.note(id: 'ok', title: 'Recovered Note', path: 'Recovered.md'),
    ];
  }
}

TreeNode directory(String name, String path, List<TreeNode> children) =>
    TreeNode.directory(name: name, path: path, children: children);

TreeNode note(String id, String title, String path) =>
    TreeNode.note(id: id, title: title, path: path);

Future<void> _pumpTree(
  WidgetTester tester,
  List<TreeNode> root, {
  ValueChanged<String>? onNoteSelected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(_StubRustApi(root))],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: WorkspaceTree(onNoteSelected: onNoteSelected),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('directories sort before notes at each level, both by name', (
    WidgetTester tester,
  ) async {
    // Deliberately unsorted input in both directions and on two levels.
    await _pumpTree(tester, [
      note('zeta', 'Zeta', 'zeta.md'),
      directory('Beta', 'Beta/', []),
      note('alpha', 'Alpha', 'alpha.md'),
      directory('Alpha', 'Alpha/', [
        note('n2', 'inner-b', 'Alpha/inner-b.md'),
        directory('sub', 'Alpha/sub/', []),
        note('n1', 'inner-a', 'Alpha/inner-a.md'),
      ]),
    ]);

    // Collapsed first: root level only.
    List<String> order() => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList();

    expect(order(), ['Alpha', 'Beta', 'Alpha', 'Zeta']);

    // Expanding the nested Directory reveals its own ordering.
    await tester.tap(find.text('Alpha').first);
    await tester.pumpAndSettle();

    expect(order(), [
      'Alpha', // directories first, by name ...
      'sub',
      'inner-a',
      'inner-b', // nested level re-applies the same ordering
      'Beta',
      'Alpha', // ... then notes, by name
      'Zeta',
    ]);
  });

  testWidgets('an empty directory still appears', (WidgetTester tester) async {
    await _pumpTree(tester, [
      directory('Empty', 'Empty/', []),
      note('only', 'Only Note', 'only.md'),
    ]);

    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('Only Note'), findsOneWidget);
  });

  testWidgets(
    'expanding a collapsed directory shows children without a reload',
    (WidgetTester tester) async {
      final api = _StubRustApi([
        directory('Projects', 'Projects/', [
          note('p1', 'Plan', 'Projects/Plan.md'),
        ]),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(body: SizedBox(width: 300, child: WorkspaceTree())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Collapsed: the child is not rendered yet.
      expect(find.text('Plan'), findsNothing);
      expect(api.workspaceTreeCalls, 1);

      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();

      // Children appear from the already-fetched tree — no second Core call.
      expect(find.text('Plan'), findsOneWidget);
      expect(api.workspaceTreeCalls, 1);

      // Collapse again; still no reload.
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      expect(find.text('Plan'), findsNothing);
      expect(api.workspaceTreeCalls, 1);
    },
  );

  testWidgets('selecting a note propagates through the provider layer', (
    WidgetTester tester,
  ) async {
    String? callbackId;
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustApiProvider.overrideWithValue(
            _StubRustApi([
              directory('D', 'D/', [
                note('n-1', 'Target Note', 'D/Target Note.md'),
              ]),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return SizedBox(
                  width: 300,
                  child: WorkspaceTree(onNoteSelected: (id) => callbackId = id),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The parent directory must be expanded before the note is reachable.
    await tester.tap(find.text('D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target Note'));
    await tester.pumpAndSettle();

    // The selection event reaches both seams `SHEL-E004` can consume:
    // the provider state and the widget's callback.
    expect(container.read(selectedNoteIdProvider), 'n-1');
    expect(callbackId, 'n-1');
  });

  testWidgets('the selected-row highlight follows the selection across taps '
      '(E003 review P2 carry-over: build must watch, not read)', (
    WidgetTester tester,
  ) async {
    // Two notes at the bundle root so no expansion is needed.
    await _pumpTree(tester, [
      note('a', 'Note A', 'Note A.md'),
      note('b', 'Note B', 'Note B.md'),
    ]);

    bool rowSelected(String title) => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((tile) => (tile.title! as Text).data == title)
        .selected;

    await tester.tap(find.text('Note A'));
    await tester.pumpAndSettle();
    expect(rowSelected('Note A'), isTrue);
    expect(rowSelected('Note B'), isFalse);

    // The stale-highlight bug this guards against: reading
    // `selectedNoteIdProvider` instead of watching it left Note A marked
    // selected after the second tap.
    await tester.tap(find.text('Note B'));
    await tester.pumpAndSettle();
    expect(rowSelected('Note B'), isTrue);
    expect(rowSelected('Note A'), isFalse);
  });

  testWidgets('a failed tree query shows an error state whose Retry refetches '
      '(flow-workspace-navigation.md failure path)', (
    WidgetTester tester,
  ) async {
    final api = _FlakyOnceRustApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: WorkspaceTree())),
        ),
      ),
    );
    await tester.pump();

    // The failure is named, not swallowed — and it carries the flow's
    // required retry affordance, since a watched autoDispose provider
    // never re-fires after an error on its own.
    expect(find.text('Failed to load workspace tree'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(api.calls, 1);

    await tester.tap(find.byKey(const ValueKey('tree-retry')));
    await tester.pumpAndSettle();

    // The retry re-ran the Core call and the tree recovered in place.
    expect(api.calls, 2);
    expect(find.text('Recovered Note'), findsOneWidget);
    expect(find.text('Failed to load workspace tree'), findsNothing);
  });
}
