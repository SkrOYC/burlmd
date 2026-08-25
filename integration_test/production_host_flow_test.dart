import 'package:burlmd/main.dart' show MyApp;
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton, kSecondaryMouseButton;
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Production-host driver data. It uses the public provider seam while keeping
/// [MyApp]'s real theme and shell composition intact.
class _ProductionHostApi extends RustApi {
  bool searchFails = false;
  final calls = <String>[];
  String starterBody = 'Feed every day.';
  NoteWriteStatus status = const NoteWriteStatus(hasUnwrittenEdits: false);
  final drafts = const [
    NoteMetadata(
      id: 'recovered',
      path: 'Recovered.md',
      title: 'Recovered draft',
      lastModified: 0,
      okfConformant: true,
    ),
  ];

  static const _effects = LifecycleEffects(remapped: [], rewritten: []);

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async =>
      const WorkspaceInfo(
        id: 'production-host',
        name: 'Production host',
        provider: 'local',
        localPath: '/tmp/burlmd-production-host',
      );

  @override
  Future<List<TreeNode>> workspaceTree() async => [
    TreeNode.directory(
      name: 'Kitchen',
      path: 'kitchen',
      children: [
        TreeNode.note(
          id: 'starter',
          title: 'Sourdough starter',
          path: 'kitchen/Sourdough starter.md',
        ),
      ],
    ),
    const TreeNode.directory(name: 'Empty', path: 'empty', children: []),
    TreeNode.note(id: 'inbox', title: 'Inbox', path: 'Inbox.md'),
  ];

  @override
  Future<List<NoteMetadata>> pendingDrafts() async => drafts;

  @override
  NoteWriteStatus noteWriteStatus(String noteId) => status;

  @override
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
    return _noteState(noteId);
  }

  NoteState _noteState(String noteId) => NoteState(
    ast: noteId == 'starter'
        ? [
            AstNode.heading(level: 1, content: [_text('Sourdough starter')]),
            AstNode.paragraph(content: [_text(starterBody)]),
            AstNode.list(
              ordered: false,
              items: [
                AstNode.listItem(
                  content: [
                    AstNode.paragraph(content: [_text('Flour')]),
                  ],
                ),
              ],
            ),
            AstNode.blockquote(
              nodes: [
                AstNode.paragraph(content: [_text('Keep it warm.')]),
              ],
            ),
            const AstNode.codeBlock(language: 'bash', code: 'bake --slow'),
            const AstNode.thematicBreak(),
          ]
        : const <AstNode>[],
    metadata: NoteMetadata(
      id: noteId,
      path: noteId == 'starter'
          ? 'kitchen/Sourdough starter.md'
          : noteId == 'recovered'
          ? 'Recovered.md'
          : 'Inbox.md',
      title: noteId == 'starter'
          ? 'Sourdough starter'
          : noteId == 'recovered'
          ? 'Recovered draft'
          : 'Inbox',
      lastModified: 0,
      okfConformant: true,
    ),
    baseRevision: 'production-host',
    restoredFromDraft: noteId == 'recovered',
  );

  static InlineElement _text(String value) => InlineElement.text(
    TextRun(
      content: value,
      bold: false,
      italic: false,
      strikethrough: false,
      code: false,
    ),
  );

  @override
  String getBlockSource(String noteId, List<int> blockPath) =>
      switch (blockPath.first) {
        0 => '# Sourdough starter',
        1 => starterBody,
        _ => 'fixture source',
      };

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
    calls.add('update:$noteId:${blockPath.join('-')}:$newSource');
    if (noteId == 'starter' && blockPath.first == 1) {
      starterBody = newSource;
    }
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    calls.add('commit:$noteId:${blockPath.join('-')}');
    return _noteState(noteId);
  }

  @override
  Future<NoteState> reloadNote(String noteId) async {
    calls.add('reload:$noteId');
    status = const NoteWriteStatus(hasUnwrittenEdits: false);
    return openNote(noteId);
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
  }

  @override
  Future<List<NoteMetadata>> searchNotes(String query, int limit) async =>
      searchFails
      ? throw StateError('test search index unavailable')
      : query.isEmpty || query == 'none'
      ? const []
      : [
          const NoteMetadata(
            id: 'starter',
            path: 'kitchen/Sourdough starter.md',
            title: 'Sourdough starter',
            lastModified: 0,
            okfConformant: true,
          ),
        ];

  @override
  Future<LifecycleResult> createNote(String directoryPath, String title) async {
    calls.add('create:$directoryPath:$title');
    return LifecycleResult(
      state: await openNote('starter'),
      effects: _effects,
      removed: const [],
    );
  }

  @override
  Future<LifecycleResult> createDirectory(String path) async {
    calls.add('mkdir:$path');
    return const LifecycleResult(effects: _effects, removed: []);
  }

  @override
  Future<LifecycleResult> deleteNote(String noteId) async {
    calls.add('delete:$noteId');
    return LifecycleResult(effects: _effects, removed: [noteId]);
  }

  @override
  Future<LifecycleResult> renameNote(String noteId, String newTitle) async {
    calls.add('rename:$noteId:$newTitle');
    return LifecycleResult(
      state: await openNote(noteId),
      effects: _effects,
      removed: const [],
    );
  }

  @override
  Future<LifecycleResult> moveNote(String noteId, String directoryPath) async {
    calls.add('move:$noteId:$directoryPath');
    return LifecycleResult(
      state: await openNote(noteId),
      effects: _effects,
      removed: const [],
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production host drives real MyApp shell and preferences', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _ProductionHostApi();
    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(api),
        writeStatusPollIntervalProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-root')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recovery-notice-recovered')),
      findsOneWidget,
    );
    api.status = const NoteWriteStatus(
      lastError: AppError.revisionMismatch('external edit'),
      hasUnwrittenEdits: true,
    );
    await tester.tap(find.byKey(const ValueKey('recovered-recovered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reload-offer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reload-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reload-offer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reload-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and reload'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('reload:recovered'));
    await tester.tap(find.byKey(const ValueKey('recovery-dismiss-recovered')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recovery-notice-recovered')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-directory-kitchen')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tree-note-starter')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-starter')));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(container.read(selectedNoteIdProvider), 'starter');
    expect(api.calls, contains('open:starter'));
    expect(container.read(activeNoteProvider)?.metadata.id, 'starter');
    expect(find.byKey(const Key('shell-tab-starter')), findsOneWidget);
    expect(find.text('Sourdough starter'), findsWidgets);
    expect(find.text('Feed every day.'), findsOneWidget);
    expect(find.byKey(const ValueKey('block-0')), findsOneWidget);

    // This is the real supported-AST editor path, not the visual fixture:
    // pointer promotion resolves a Core caret, raw input buffers through the
    // provider, and Escape commits the authoritative fake Core state.
    final initialEntryRect = tester.getRect(
      find.byKey(const ValueKey('entry-1')),
    );
    await tester.tap(find.byKey(const ValueKey('promote-block-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('raw-editor-1')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('entry-1'))),
      initialEntryRect,
    );
    await tester.enterText(
      find.byKey(const ValueKey('raw-editor-1')),
      'Feed twice daily.',
    );
    await tester.pump();
    expect(api.calls, contains('update:starter:1:Feed twice daily.'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('raw-editor-1')), findsNothing);
    expect(api.calls, contains('commit:starter:1'));
    expect(find.text('Feed twice daily.'), findsOneWidget);

    // Focus mode fades only nonfocused entries. Its animation must not resize
    // the promoted block (which would reflow the editor under the caret).
    await tester.tap(find.byKey(const ValueKey('shell-preferences')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preferences-focus-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preferences-done')));
    await tester.pumpAndSettle();
    final focusedEntryRect = tester.getRect(
      find.byKey(const ValueKey('entry-1')),
    );
    final dimmedEntryOpacity = find.ancestor(
      of: find.byKey(const ValueKey('entry-0')),
      matching: find.byType(AnimatedOpacity),
    );
    await tester.tap(find.byKey(const ValueKey('promote-block-1')));
    await tester.pump(const Duration(milliseconds: 75));
    final midFade = tester.widget<FadeTransition>(
      find.descendant(
        of: dimmedEntryOpacity,
        matching: find.byType(FadeTransition),
      ),
    );
    expect(midFade.opacity.value, greaterThan(0.35));
    expect(midFade.opacity.value, lessThan(1));
    expect(
      tester.getRect(find.byKey(const ValueKey('entry-1'))),
      focusedEntryRect,
    );
    await tester.pump(const Duration(milliseconds: 75));
    final endFade = tester.widget<FadeTransition>(
      find.descendant(
        of: dimmedEntryOpacity,
        matching: find.byType(FadeTransition),
      ),
    );
    expect(endFade.opacity.value, closeTo(0.35, 0.001));
    expect(
      tester.getRect(find.byKey(const ValueKey('entry-1'))),
      focusedEntryRect,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    Future<void> focusStarterRaw() async {
      final raw = find.byKey(const ValueKey('raw-editor-1'));
      if (raw.evaluate().isNotEmpty) {
        await tester.tap(raw);
      } else {
        await tester.tap(find.byKey(const ValueKey('promote-block-1')));
      }
      await tester.pump();
      expect(find.byKey(const ValueKey('raw-editor-1')), findsOneWidget);
    }

    void expectRawSource() {
      final rawEditors = tester
          .widgetList<EditableText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is EditableText &&
                  widget.key == const ValueKey('raw-editor-1') &&
                  widget.focusNode.hasFocus,
            ),
          )
          .toList();
      expect(
        rawEditors,
        hasLength(1),
        reason: 'The active raw editor must retain primary focus.',
      );
      final raw = rawEditors.first;
      expect(raw.controller.text, 'Feed twice daily.');
    }

    Future<void> sendPrimary(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // Shell shortcuts must continue to win when the raw field is primary
    // focused. A surface closes with Escape and returns to the exact raw
    // source; the command itself never becomes editor text.
    await focusStarterRaw();
    await sendPrimary(LogicalKeyboardKey.keyK);
    expect(find.byKey(const ValueKey('search-palette')), findsOneWidget);
    expectRawSource();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-palette')), findsNothing);
    expectRawSource();

    await focusStarterRaw();
    await sendPrimary(LogicalKeyboardKey.keyH);
    expect(find.byKey(const ValueKey('history-drawer')), findsOneWidget);
    expectRawSource();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-drawer')), findsNothing);
    expectRawSource();

    await focusStarterRaw();
    await sendPrimary(LogicalKeyboardKey.comma);
    expect(find.byKey(const ValueKey('preferences-drawer')), findsOneWidget);
    expectRawSource();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preferences-drawer')), findsNothing);
    expectRawSource();

    await focusStarterRaw();
    await sendPrimary(LogicalKeyboardKey.keyW);
    expectRawSource();

    await tester.tap(find.byKey(const ValueKey('workspace-tree-note-inbox')));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(container.read(selectedNoteIdProvider), 'inbox');
    expect(api.calls, contains('open:inbox'));
    expect(container.read(activeNoteProvider)?.metadata.id, 'inbox');
    expect(find.byKey(const Key('shell-tab-inbox')), findsOneWidget);
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer();
    final starterTab = find.byKey(const Key('shell-tab-starter'));
    await hover.moveTo(tester.getCenter(starterTab));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shell-tab-close-starter')),
      findsOneWidget,
    );
    await hover.removePointer();
    final secondary = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.addPointer();
    final starterCenter = tester.getCenter(starterTab);
    await secondary.down(starterCenter);
    await secondary.up();
    await secondary.removePointer();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-others')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-others')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shell-add-tab')));
    await tester.pumpAndSettle();
    final untitled = find.textContaining('Untitled').last;
    final middle = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middle.addPointer();
    final untitledCenter = tester.getCenter(untitled);
    await middle.down(untitledCenter);
    await middle.up();
    await middle.removePointer();
    await tester.pumpAndSettle();
    expect(find.textContaining('Untitled'), findsNothing);
    await tester.tap(find.byKey(const Key('shell-copy-path')));
    await tester.pump();
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-directory-actions-kitchen')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tree-context-create-note-kitchen')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lifecycle-text-input')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lifecycle-dialog-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-note-actions-starter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-context-delete-starter')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('delete-confirmation-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('delete-confirmation-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-note-actions-starter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-context-rename-starter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lifecycle-text-input')),
      'Levain',
    );
    await tester.tap(find.byKey(const ValueKey('lifecycle-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('rename:starter:Levain'));

    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-note-actions-starter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-context-move-starter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('kitchen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, contains('move:starter:kitchen'));

    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-note-actions-starter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-context-delete-starter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-confirmation-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('delete:starter'));
    await tester.tap(
      find.byKey(const ValueKey('workspace-tree-directory-kitchen')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tree-note-starter')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('shell-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('search-panel-input')),
      'starter',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-result-starter')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('search-panel-input')),
      'none',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-no-match')), findsOneWidget);
    api.searchFails = true;
    await tester.enterText(
      find.byKey(const ValueKey('search-panel-input')),
      'starter',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-retry')), findsOneWidget);
    api.searchFails = false;
    await tester.tap(find.byKey(const ValueKey('search-retry')));
    await tester.pumpAndSettle();
    final searchResult = find.byKey(const ValueKey('search-result-starter'));
    expect(searchResult, findsOneWidget);
    final searchMouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await searchMouse.addPointer();
    await searchMouse.moveTo(tester.getCenter(searchResult));
    await tester.pump();
    final searchInput = find.byKey(const ValueKey('search-panel-input'));
    await tester.tap(searchInput);
    await tester.pump();
    expect(Focus.of(tester.element(searchInput)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-palette')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('shell-search')));
    await tester.pumpAndSettle();
    final reopenedInput = find.byKey(const ValueKey('search-panel-input'));
    await tester.tap(reopenedInput);
    await tester.pump();
    expect(Focus.of(tester.element(reopenedInput)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-palette')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('shell-preferences')));
    await tester.pumpAndSettle();
    for (final theme in ['dark', 'light', 'system']) {
      await tester.tap(find.byKey(ValueKey('preferences-theme-$theme')));
      await tester.pumpAndSettle();
    }
    for (final scale in BurlFontScale.values) {
      await tester.tap(
        find.byKey(ValueKey('preferences-font-scale-${scale.name}')),
      );
    }
    for (final measure in BurlMeasure.values) {
      await tester.tap(
        find.byKey(ValueKey('preferences-measure-${measure.name}')),
      );
    }
    for (final chrome in BurlPlatformChrome.values) {
      await tester.tap(
        find.byKey(ValueKey('preferences-platform-chrome-${chrome.name}')),
      );
    }
    if (!container.read(burlPreferencesProvider).focusMode) {
      await tester.tap(find.byKey(const ValueKey('preferences-focus-mode')));
      await tester.pumpAndSettle();
    }
    expect(container.read(burlPreferencesProvider).focusMode, isTrue);
    await tester.tap(find.byKey(const ValueKey('preferences-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shell-sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-sidebar-expand')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shell-sidebar-expand')));
    await tester.pumpAndSettle();

    for (final width in [800.0, 480.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-open-navigator')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('navigator-pane')), findsOneWidget);
      await tester.tapAt(Offset(width - 12, 400));
      await tester.pumpAndSettle();
    }

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shell-sync')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-state-select')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shell-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-unavailable')), findsOneWidget);
  });
}
