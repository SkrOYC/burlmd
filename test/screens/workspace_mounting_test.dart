import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/design/burl_motion.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] standing in for the Core at the shell level, with the
/// recovery and search surfaces' calls faked so the mounted wiring can be
/// exercised without the compiled Rust dylib.
class _MountingRustApi extends RustApi {
  _MountingRustApi(this.tree);

  final List<TreeNode> tree;
  List<AstNode> ast = const [];
  final Map<String, String> sources = {};

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
      ast: ast,
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
  String getBlockSource(String noteId, List<int> blockPath) =>
      sources[blockPath.join('/')] ?? '';

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
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    sources[blockPath.join('/')] = newSource;
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) => NoteState(
    ast: ast,
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
  _MountingRustApi api, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: const WorkspaceScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

ValueNotifier<String?> _captureClipboard(WidgetTester tester) {
  final clipboard = ValueNotifier<String?>(null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = call.arguments as Map<Object?, Object?>?;
        clipboard.value = data?['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    clipboard.dispose();
  });
  return clipboard;
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
    await tester.tap(find.byTooltip('Dismiss notice'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered drafts'), findsNothing);
    expect(api.calls.where((c) => !c.startsWith('search:')), isEmpty);
  });

  testWidgets('a clean startup shows no recovery notice', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    expect(find.text('Recovered drafts'), findsNothing);
  });

  testWidgets('the workspace shell offers no emulated platform chrome', (
    tester,
  ) async {
    await _pumpShell(tester, _MountingRustApi([_treeNode('a', 'Alpha')]));

    expect(find.byKey(const Key('platform-chrome-macos')), findsNothing);
    expect(find.byKey(const Key('platform-chrome-linux')), findsNothing);
    expect(find.byKey(const Key('platform-chrome-minimal')), findsNothing);
    expect(
      find.byKey(const Key('preferences-platform-chrome-macos')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('preferences-platform-chrome-linux')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('preferences-platform-chrome-minimal')),
      findsNothing,
    );
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
    expect(container.read(writeTierMonitorProvider).status, isNull);
    expect(container.read(writeTierMonitorProvider).statusUnavailable, isFalse);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // Opening a Note arms the monitor — polling actually happens now that
    // the shell watches it, instead of failures being raised into nothing.
    expect(container.read(writeTierMonitorProvider).status, isNotNull);
    expect(
      container.read(writeTierMonitorProvider).status?.lastError,
      isA<AppError_DiskFull>(),
    );

    // And the failure is visible where the user is looking: directly above
    // the editor pane.
    expect(find.textContaining('disk is full'), findsOneWidget);
  });

  testWidgets('rail and compact tiers open and dismiss the overlay navigator', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-open-navigator')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-open-navigator')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('workspace-modal-focus-scope')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(700, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigator-scrim')), findsNothing);

    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-open-navigator')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('navigator entrance has measurable mid- and end-motion states', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);
    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell-open-navigator')));
    await tester.pump();
    expect(find.byType(BurlScaleFadeEntrance), findsOneWidget);

    // The entrance schedules its target after its initial mounted frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(BurlScaleFadeEntrance),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, greaterThan(.98));
    expect(scale.scale.value, lessThan(1));

    await tester.pump(const Duration(milliseconds: 60));
    final settled = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(BurlScaleFadeEntrance),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(settled.scale.value, closeTo(1, .001));
  });

  testWidgets('rail settings opens preferences instead of the navigator', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);
    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shell-rail-preferences')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preferences-drawer')), findsOneWidget);
    expect(find.byKey(const Key('shell-navigator-overlay')), findsNothing);
  });

  testWidgets('reduced motion opens the navigator at its final position', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(api),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const WorkspaceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell-open-navigator')));
    await tester.pump();
    final entrance = tester.widget<BurlScaleFadeEntrance>(
      find.byType(BurlScaleFadeEntrance),
    );
    expect(entrance.duration, BurlMotion.drawer);
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(BurlScaleFadeEntrance),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.duration, Duration.zero);
    expect(opacity.opacity, 1);
  });

  testWidgets('shell dialogs share the strict 0/60/120 scale-fade contract', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    for (final surface in [
      (const ValueKey('shell-search'), const ValueKey('search-close')),
      (
        const ValueKey('shell-preferences'),
        const ValueKey('preferences-close'),
      ),
      (const ValueKey('shell-history'), const ValueKey('history-close')),
      (const ValueKey('shell-sync'), const ValueKey('sync-close')),
    ]) {
      await tester.tap(find.byKey(surface.$1));
      await tester.pump();
      final entrance = find.byType(BurlScaleFadeEntrance).last;
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .descendant(of: entrance, matching: find.byType(AnimatedOpacity))
            .first,
      );
      expect(opacity.opacity, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.widget<ScaleTransition>(
        find
            .descendant(of: entrance, matching: find.byType(ScaleTransition))
            .first,
      );
      expect(mid.scale.value, greaterThan(.98));
      expect(mid.scale.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(mid.scale.value, closeTo(1, .001));
      await tester.tap(find.byKey(surface.$2));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('reduced motion makes every shell dialog final and interactive', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api, disableAnimations: true);
    for (final surface in [
      (const ValueKey('shell-search'), const ValueKey('search-close')),
      (
        const ValueKey('shell-preferences'),
        const ValueKey('preferences-close'),
      ),
      (const ValueKey('shell-history'), const ValueKey('history-close')),
      (const ValueKey('shell-sync'), const ValueKey('sync-close')),
    ]) {
      await tester.tap(find.byKey(surface.$1));
      await tester.pump();
      final entrance = find.byType(BurlScaleFadeEntrance).last;
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .descendant(of: entrance, matching: find.byType(AnimatedOpacity))
            .first,
      );
      final scale = tester.widget<AnimatedScale>(
        find
            .descendant(of: entrance, matching: find.byType(AnimatedScale))
            .first,
      );
      expect(opacity.duration, Duration.zero);
      expect(opacity.opacity, 1);
      expect(scale.duration, Duration.zero);
      expect(scale.scale, 1);
      await tester.tap(find.byKey(surface.$2));
      await tester.pump();
    }
  });

  testWidgets(
    'global shortcuts open surfaces and Escape dismisses the top one',
    (tester) async {
      final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
      await _pumpShell(tester, api);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-palette')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-palette')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-drawer')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preferences-drawer')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preferences-drawer')), findsNothing);
    },
  );

  testWidgets('workspace overlays move and retain focus inside the modal', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-search')),
        matching: find.text('Ctrl+K'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('shell-sync')));
    await tester.pumpAndSettle();
    final overlay = find.byKey(const ValueKey('sync-inspector'));
    final scopeFinder = find.byKey(
      const ValueKey('workspace-modal-focus-scope'),
    );
    expect(scopeFinder, findsOneWidget);
    expect(
      find.descendant(of: overlay, matching: find.byType(ModalBarrier)),
      findsOneWidget,
    );
    final scope = FocusScope.of(tester.element(scopeFinder));
    expect(scope.hasFocus, isTrue);
    expect(FocusManager.instance.primaryFocus!.ancestors, contains(scope));

    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus!.ancestors, contains(scope));
    }
    await tester.tap(find.byKey(const ValueKey('sync-close')));
    await tester.pumpAndSettle();

    for (final surface in [
      (
        const Key('shell-search'),
        const ValueKey('shell-search-overlay'),
        const ValueKey('search-close'),
      ),
      (
        const Key('shell-preferences'),
        const ValueKey('preferences-overlay'),
        const ValueKey('preferences-close'),
      ),
      (
        const Key('shell-history'),
        const ValueKey('history-overlay'),
        const ValueKey('history-close'),
      ),
    ]) {
      await tester.tap(find.byKey(surface.$1));
      await tester.pumpAndSettle();
      final modal = find.byKey(surface.$2);
      expect(
        find.byKey(const ValueKey('workspace-modal-focus-scope')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: modal, matching: find.byType(ModalBarrier)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(surface.$3));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('workspace search shortcut label follows the platform', (
    tester,
  ) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await _pumpShell(tester, _MountingRustApi([_treeNode('a', 'Alpha')]));
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-search')),
        matching: find.text('⌘K'),
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
    await tester.pump();
  });

  testWidgets('early shell shortcuts preserve a primary-focused raw editor', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')])
      ..ast = [
        AstNode.paragraph(
          content: [
            InlineElement.text(
              const TextRun(
                content: 'draft',
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
              ),
            ),
          ],
        ),
      ]
      ..sources['0'] = 'draft';
    await _pumpShell(tester, api);
    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promote-block-0')));
    await tester.pump();
    final raw = find.byKey(const ValueKey('raw-editor-0'));
    expect(raw, findsOneWidget);
    await tester.enterText(raw, 'retained draft');

    Future<void> sendPrimary(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> refocusRawEditor() async {
      if (raw.evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('promote-block-0')));
        await tester.pump();
      }
      await tester.tap(raw);
    }

    await sendPrimary(LogicalKeyboardKey.keyK);
    expect(find.byKey(const ValueKey('search-palette')), findsOneWidget);
    expect(raw, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await refocusRawEditor();
    await sendPrimary(LogicalKeyboardKey.keyH);
    expect(find.byKey(const ValueKey('history-drawer')), findsOneWidget);
    expect(raw, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await refocusRawEditor();
    await sendPrimary(LogicalKeyboardKey.comma);
    expect(find.byKey(const ValueKey('preferences-drawer')), findsOneWidget);
    expect(raw, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await refocusRawEditor();
    await sendPrimary(LogicalKeyboardKey.keyW);
    expect(raw, findsOneWidget);
    await tester.enterText(raw, 'ordinary typing');
    expect(tester.widget<EditableText>(raw).controller.text, 'ordinary typing');
  });

  testWidgets('focus mode snaps paint without moving a block when reduced', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')])
      ..ast = [
        AstNode.paragraph(
          content: [
            InlineElement.text(
              const TextRun(
                content: 'first',
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
              ),
            ),
          ],
        ),
        AstNode.paragraph(
          content: [
            InlineElement.text(
              const TextRun(
                content: 'second',
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
              ),
            ),
          ],
        ),
      ]
      ..sources['0'] = 'first'
      ..sources['1'] = 'second';
    await _pumpShell(tester, api, disableAnimations: true);
    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shell-preferences')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preferences-focus-mode')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('preferences-drawer')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('preferences-focus-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preferences-done')));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(const ValueKey('entry-1')));
    await tester.tap(find.byKey(const ValueKey('promote-block-1')));
    await tester.pump();
    final dimmedOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('entry-0')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(dimmedOpacity.duration, Duration.zero);
    expect(dimmedOpacity.opacity, 0.35);
    expect(tester.getRect(find.byKey(const ValueKey('entry-1'))), before);
  });

  testWidgets('preferences update the in-session theme choice', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    final container = await _pumpShell(tester, api);

    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preferences-drawer')), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      container.read(burlPreferencesProvider).theme,
      BurlThemePreference.dark,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      container.read(burlPreferencesProvider).theme,
      BurlThemePreference.light,
    );

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(
      container.read(burlPreferencesProvider).theme,
      BurlThemePreference.system,
    );
  });

  testWidgets('production sync and history remain honest without Core data', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    await tester.tap(find.byKey(const ValueKey('shell-sync')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-state-select')), findsNothing);
    expect(
      find.text('Path: /tmp/workspace\nRemote: Not configured'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sync-now')),
        matching: find.text('Rescan workspace'),
      ),
      findsOneWidget,
    );
    expect(find.text('main'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shell-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-unavailable')), findsOneWidget);
  });

  testWidgets('the editor shell renders bounded visual tabs and keeps note '
      'selection on the production provider seam', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    final container = await _pumpShell(tester, api);

    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.text('Welcome.md'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-add-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Untitled 1.md'), findsOneWidget);

    // Tree selection still drives `selectedNoteIdProvider` and the existing
    // open path; tabs merely reflect that real selected Note once it opens.
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(container.read(selectedNoteIdProvider), 'a');
    expect(api.calls, contains('open:a'));
    expect(find.byKey(const Key('shell-tab-a')), findsOneWidget);
    expect(find.text('Welcome.md'), findsNothing);

    // Closing an active Note remains intentionally deferred until it can use
    // the lifecycle-aware close/flush path; the provider-owned tab persists.
    await tester.tap(find.byTooltip('Close a.md'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-tab-a')), findsOneWidget);
  });

  testWidgets('the production shell exposes no visual-fixture route', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    expect(
      find.byKey(const ValueKey('shell-open-visual-fixture')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('visual-parity-fixture-route')),
      findsNothing,
    );
  });

  testWidgets('a focused tab opens its context menu with Shift+F10', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    await tester.tap(find.byKey(const Key('shell-tab-visual-welcome')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-others')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-all')), findsOneWidget);
  });

  testWidgets('a focused note tab selects with Enter and Space', (
    tester,
  ) async {
    final api = _MountingRustApi([
      _treeNode('a', 'Alpha'),
      _treeNode('b', 'Beta'),
    ]);
    final container = await _pumpShell(tester, api);

    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-b')));
    await tester.pumpAndSettle();

    final alphaTab = find.byKey(const Key('shell-tab-a'));
    Focus.of(tester.element(alphaTab)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(selectedNoteIdProvider), 'a');
    expect(api.calls, contains('open:a'));

    final betaTab = find.byKey(const Key('shell-tab-b'));
    Focus.of(tester.element(betaTab)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(container.read(selectedNoteIdProvider), 'b');
    expect(api.calls, contains('open:b'));
  });

  testWidgets(
    'the search palette close affordance retains its shell callback',
    (tester) async {
      final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
      await _pumpShell(tester, api);

      await tester.tap(find.byTooltip('Search notes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-palette')), findsOneWidget);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-palette')), findsNothing);
    },
  );

  testWidgets('the metadata bar uses active Note metadata and provides copy '
      'feedback', (tester) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')])
      ..ast = [
        AstNode.paragraph(
          content: const [
            InlineElement.text(
              TextRun(
                content: 'Three useful words',
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
              ),
            ),
          ],
        ),
      ];
    final clipboard = _captureClipboard(tester);
    await _pumpShell(tester, api);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-filename-chip')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-filename-chip')),
        matching: find.text('a.md'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Modified recently'), findsOneWidget);
    expect(find.textContaining('3 words'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-copy-path')));
    await tester.pumpAndSettle();
    expect(clipboard.value, 'a.md');
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('narrow layout hides metadata detail and clamps preferences', (
    tester,
  ) async {
    final api = _MountingRustApi([_treeNode('a', 'Alpha')]);
    await _pumpShell(tester, api);

    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('History'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('preferences-drawer'))).width,
      420,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fixture stories use the strict 0/60/120 scale-fade transition', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VisualParityFixture()));
    await tester.tap(find.byKey(const ValueKey('fixture-story-raw')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.widget<ScaleTransition>(
      find.byType(ScaleTransition).last,
    );
    expect(mid.scale.value, greaterThan(.98));
    expect(mid.scale.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(mid.scale.value, closeTo(1, .001));
  });

  testWidgets('fixture story switch is immediate with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const VisualParityFixture(),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('fixture-story-raw')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-raw-block')), findsOneWidget);
  });

  testWidgets('reduced sync spinner is stopped and invariant', (tester) async {
    const turns = AlwaysStoppedAnimation<double>(.25);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const BurlSyncSpinner(
              turns: turns,
              child: Icon(Icons.refresh),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sync-spinner-stopped')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-spinner')), findsNothing);
    final before = tester.getTopLeft(find.byIcon(Icons.refresh));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getTopLeft(find.byIcon(Icons.refresh)), before);
  });
}
