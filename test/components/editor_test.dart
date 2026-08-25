import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, RenderEditable, RenderObject, RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';

/// A [NoteController] whose initial state is fixed at construction, so tests
/// can pump [Editor] against a known AST without going through a real
/// `open_note` FFI call (which needs a real file and the compiled Rust
/// dylib, neither available in a widget test).
class _FixedNoteController extends NoteController {
  _FixedNoteController(this._initial);

  final NoteState _initial;

  @override
  NoteState? build() => _initial;
}

/// A [RustApi] standing in for the Core at the editing surface. Under
/// `EDIT-F002`'s model the Dart side makes three kinds of call:
///
/// - `getBlockSource` when a Block is promoted (populates the editable
///   field) — answered from a canned map keyed by block path.
/// - `update_block`, the per-keystroke buffering call — a spy that records
///   arguments and returns nothing (it parses nothing, exactly like the
///   contract's version).
/// - `commit_block` on blur — records the committed path, counts calls, and
///   returns a caller-supplied authoritative [NoteState].
class _FakeRustApi extends RustApi {
  _FakeRustApi({this.failContainerPaths = false});

  final bool failContainerPaths;
  bool failBlockSource = false;

  String? lastNoteId;
  List<int>? lastBlockPath;
  String? lastSource;
  int updateCount = 0;

  final List<List<int>> committedPaths = [];
  int commitCount = 0;

  /// Raw source returned per block path by [getBlockSource].
  // Keyed by the '/'-joined block path: Dart lists compare by identity, so
  // they cannot be map keys.
  final Map<String, String> sources = {};

  /// Pointer-resolution replies keyed by the top-level path. Tests that do
  /// not care about nesting get the identity leaf and the supplied UTF-16
  /// rendered coordinate, while nested-promotion tests must declare the
  /// Core-owned answer explicitly.
  final Map<String, BlockCaret> resolvedCarets = {};

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int renderedUtf16Offset,
  ) =>
      resolvedCarets[topLevelPath.join('/')] ??
      BlockCaret(
        blockPath: Uint64List.fromList(topLevelPath),
        caretOffset: BigInt.from(renderedUtf16Offset),
      );

  /// The authoritative state [commitBlock] returns.
  NoteState? commitResult;

  @override
  String getBlockSource(String noteId, List<int> blockPath) {
    if (failBlockSource) throw StateError('source hydration refused');
    return sources[blockPath.join('/')] ??
        (throw Exception('no source for $blockPath'));
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    if (failContainerPaths && blockPath.length == 1) {
      throw StateError('Core refuses container paths: $blockPath');
    }
    lastNoteId = noteId;
    lastBlockPath = blockPath;
    lastSource = newSource;
    sources[blockPath.join('/')] = newSource;
    updateCount++;
  }

  StructuralEdit? continuationResult;
  int continuationCount = 0;

  StructuralEdit? slotContinuationResult;
  int slotContinuationCount = 0;

  StructuralEdit? replaceSelectionResult;
  StructuralEdit? splitResult;
  StructuralEdit? mergeResult;

  @override
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> blockPath,
    String source,
  ) {
    continuationCount++;
    final result =
        continuationResult ??
        (throw StateError('no continuation result prepared'));
    sources.putIfAbsent(result.blockPath.join('/'), () => source);
    return result;
  }

  @override
  StructuralEdit continueBlockAtInsertionSlot(
    String noteId,
    StructuralEditInsertionSlot insertionSlot,
    String source,
  ) {
    slotContinuationCount++;
    final result =
        slotContinuationResult ??
        (throw StateError('no slot continuation result prepared'));
    sources.putIfAbsent(result.blockPath.join('/'), () => source);
    return result;
  }

  @override
  StructuralEdit replaceSelectionAndSplitBlock(
    String noteId,
    List<int> blockPath,
    String source,
    int selectionBase,
    int selectionExtent,
  ) =>
      replaceSelectionResult ??
      (throw StateError('no selected Enter result prepared'));

  @override
  StructuralEdit splitBlock(
    String noteId,
    List<int> blockPath,
    String source,
    int offset,
  ) => splitResult ?? (throw StateError('no split result prepared'));

  @override
  StructuralEdit mergeBlockWithPrevious(String noteId, List<int> blockPath) =>
      mergeResult ?? (throw StateError('no merge result prepared'));

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    committedPaths.add(blockPath);
    commitCount++;
    return commitResult ?? (throw Exception('no commit result prepared'));
  }
}

/// Lifecycle-capable editing fake. It keeps the editor tests on the real
/// [LifecycleActions] adoption path, where the focus-remap token is emitted.
class _LifecycleEditorApi extends _FakeRustApi {
  LifecycleResult? createResult;
  LifecycleResult? renameResult;
  LifecycleResult? moveResult;
  LifecycleResult? renameDirectoryResult;
  Completer<void>? createGate;
  final Map<String, NoteState> openStates = {};

  @override
  Future<LifecycleResult> createNote(String directoryPath, String title) async {
    final gate = createGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    return createResult ?? (throw StateError('no create result prepared'));
  }

  @override
  Future<LifecycleResult> renameNote(String noteId, String newTitle) async =>
      renameResult ?? (throw StateError('no rename result prepared'));

  @override
  Future<LifecycleResult> moveNote(
    String noteId,
    String newDirectoryPath,
  ) async => moveResult ?? (throw StateError('no move result prepared'));

  @override
  Future<LifecycleResult> renameDirectory(String path, String newName) async =>
      renameDirectoryResult ??
      (throw StateError('no directory rename result prepared'));

  @override
  Future<NoteState> openNote(String noteId) async =>
      openStates[noteId] ?? (throw StateError('no open state for $noteId'));

  @override
  Future<void> closeNote(String noteId) async {}
}

class _LinkResolutionApi extends _FakeRustApi {
  final Map<String, Completer<LinkTargetResolution>> resolutions = {};
  final List<String> calls = [];
  Object? resolveError;
  Object? createError;
  LifecycleResult? createResult;
  Completer<void>? createGate;

  @override
  Future<LinkTargetResolution> resolveLinkTarget(String targetId) {
    calls.add(targetId);
    if (resolveError case final Object error) return Future.error(error);
    return resolutions[targetId]!.future;
  }

  @override
  Future<LifecycleResult> createLinkTarget(String targetId) async {
    final gate = createGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (createError case final Object error) throw error;
    final result = createResult;
    if (result == null) throw StateError('no create result prepared');
    return result;
  }

  @override
  Future<NoteState> openNote(String noteId) {
    final created = createResult?.state;
    return created != null && created.metadata.id == noteId
        ? Future.value(created)
        : Future.error(StateError('no open state for $noteId'));
  }

  @override
  Future<void> closeNote(String noteId) async {}
}

/// A [RustApi] standing in for the Core at the workspace-shell level:
/// serves a fixed tree, records `open_note`/`close_note` calls in order so
/// the switch criterion ("closed through the Core **before** the new one
/// opens") can be asserted, and can be told to fail opens to exercise the
/// error surface. Everything else falls back to no-op behaviour.
class _ShellRustApi extends RustApi {
  _ShellRustApi(
    this.tree, {
    this.failOpenFor = const {},
    this.failCloseFor = const {},
    this.openGates = const {},
    this.closeGates = const {},
  });

  final List<TreeNode> tree;

  /// Concept ids whose `openNote` throws — the "Core returns an error"
  /// branch of the Gherkin.
  final Set<String> failOpenFor;

  /// Concept ids whose `closeNote` throws — the "switch aborts because the
  /// outgoing close failed" branch.
  final Set<String> failCloseFor;

  /// Per-id gates that park `openNote` until the test releases them, so a
  /// round trip can be held genuinely in flight while the next selection
  /// races in (the interleaving that used to skip close).
  final Map<String, Completer<void>> openGates;
  final Map<String, Completer<void>> closeGates;

  /// Every open/close call in issue order, as `'open:<id>'` / `'close:<id>'`.
  final List<String> calls = [];
  final List<String> updatedSources = [];

  NoteState _stateFor(String noteId) => NoteState(
    ast: [
      AstNode.heading(
        level: 1,
        content: [InlineElement.text(_run('Rendered $noteId'))],
      ),
    ],
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
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
    final gate = openGates[noteId];
    if (gate != null && !gate.isCompleted) await gate.future;
    if (failOpenFor.contains(noteId)) throw Exception('core exploded');
    return _stateFor(noteId);
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
    final gate = closeGates[noteId];
    if (gate != null && !gate.isCompleted) await gate.future;
    if (failCloseFor.contains(noteId)) throw Exception('close refused');
  }

  @override
  String getBlockSource(String noteId, List<int> blockPath) =>
      'Rendered $noteId';

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
    updatedSources.add('$noteId:$newSource');
  }
}

TextRun _run(String text) => TextRun(
  content: text,
  bold: false,
  italic: false,
  strikethrough: false,
  code: false,
);

const _testMetadata = NoteMetadata(
  id: 'test-note',
  path: 'test-note.md',
  title: 'Test Note',
  lastModified: 0,
  okfConformant: true,
);

NoteState _testNoteState(List<AstNode> ast) => NoteState(
  ast: ast,
  metadata: _testMetadata,
  baseRevision: 'head',
  restoredFromDraft: false,
);

NoteState _noteState(String id, List<AstNode> ast) => NoteState(
  ast: ast,
  metadata: NoteMetadata(
    id: id,
    path: '$id.md',
    title: id,
    lastModified: 0,
    okfConformant: true,
  ),
  baseRevision: 'head',
  restoredFromDraft: false,
);

LifecycleResult _lifecycleResult(
  NoteState state, {
  LifecycleEffects effects = const LifecycleEffects(
    remapped: [],
    rewritten: [],
  ),
}) => LifecycleResult(
  state: state,
  effects: effects,
  removed: const [],
  warning: null,
);

InlineElement _plainRun(String text) => InlineElement.text(_run(text));

InlineElement _boldRun(String text) => InlineElement.text(
  TextRun(
    content: text,
    bold: true,
    italic: false,
    strikethrough: false,
    code: false,
  ),
);

AstNode _paragraphOf(List<InlineElement> content) =>
    AstNode.paragraph(content: content);

AstNode _plainParagraph(String text) => _paragraphOf([_plainRun(text)]);

AstNode _linkedParagraph(String title, String targetId) => _paragraphOf([
  InlineElement.link(
    targetId: targetId,
    exists: true,
    content: [_plainRun(title)],
  ),
]);

/// Pumps [Editor] against a fixed AST, optionally overriding
/// [rustApiProvider] with [api] (required by every test that promotes a
/// Block, since promotion talks to the Core synchronously).
/// Monotonic key seed so consecutive `pumpEditor` calls hand Flutter
/// different widget keys (see the comment at the pump site).
var _pumpSeed = 0;

Future<ProviderContainer> pumpEditor(
  WidgetTester tester,
  List<AstNode> ast, {
  RustApi? api,
  bool disableAnimations = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(
        () => _FixedNoteController(_testNoteState(ast)),
      ),
      if (api != null) rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  // A unique key per pump: consecutive pumpEditor calls would otherwise
  // hand Flutter an identical widget tree, which updates the existing
  // elements in place and REUSES the old _EditorState — carrying `_focused`
  // from one test's container into the next test's fresh one. In production
  // the container outlives every Editor, so this is a fixture-only hazard.
  var pumpCounter = _pumpSeed++;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Editor(key: ValueKey('editor-${pumpCounter++}')),
          ),
        ),
      ),
    ),
  );
  return container;
}

/// Promotes a Block by tapping its rendered form, then lets the promoted
/// field's autofocus settle.
Future<void> promoteByTap(WidgetTester tester, Finder what) async {
  await tester.tap(what, warnIfMissed: false);
  await tester.pump();
  await tester.pump();
}

/// Blurs whatever holds primary focus — the user clicking away — which is
/// the commit point under ADR-006.
Future<void> blurFocusedField(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump();
}

/// The raw-field intent tests own Flutter's platform clipboard channel so
/// Paste and Cut exercise the installed framework actions deterministically.
ValueNotifier<String?> _mockClipboard(WidgetTester tester, [String? initial]) {
  final text = ValueNotifier<String?>(initial);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return text.value == null
              ? null
              : <String, String>{'text': text.value!};
        case 'Clipboard.setData':
          final args = call.arguments as Map<Object?, Object?>?;
          text.value = args?['text'] as String?;
          return null;
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    text.dispose();
  });
  return text;
}

Future<void> activateInternalLink(
  WidgetTester tester,
  int index,
  String targetId,
) async {
  // Internal-Link focus and semantics use the painted glyph boxes measured
  // after layout, so wait for the measurement rebuild before locating the
  // physical focus target.
  await tester.pump();
  final target = find.byKey(ValueKey('internal-link-focus-$index-$targetId'));
  Focus.of(
    tester.element(
      find.descendant(of: target, matching: find.byType(Semantics)).first,
    ),
  ).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

EditableText _field(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText).first);

RichText _firstRichText(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first);

/// Matches only WRITABLE editable fields — the promoted Block editor. A bare
/// `find.byType(EditableText)` would false-positive on `SelectableText`'s
/// internal read-only EditableText (used by the error surface).
Finder _writableFields() => find.byWidgetPredicate(
  (widget) => widget is EditableText && !widget.readOnly,
);

/// [EditableText] itself builds a composition callback render object; its
/// [RenderEditable] is a descendant rather than the widget's direct render
/// object. Locate the actual laid-out text surface for wrap measurements.
RenderEditable _renderEditable(WidgetTester tester) {
  RenderEditable? found;
  void visit(RenderObject object) {
    if (object is RenderEditable) {
      found ??= object;
      return;
    }
    object.visitChildren(visit);
  }

  visit(tester.renderObject<RenderObject>(_writableFields()));
  return found!;
}

void _expectAlignedMarkerX(
  WidgetTester tester,
  Finder markerFinder,
  int markerCount,
) {
  expect(markerFinder, findsNWidgets(markerCount));
  final markerXs = [
    for (var index = 0; index < markerCount; index++)
      tester.getTopLeft(markerFinder.at(index)).dx,
  ];
  expect(markerXs.skip(1), everyElement(markerXs.first));
}

void main() {
  // -- CAP-EDIT-01: formatted when unfocused, raw when focused ------------

  testWidgets('interactive multi-item lists keep sibling markers aligned', (
    tester,
  ) async {
    await pumpEditor(tester, [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(
            content: [
              _plainParagraph('outer one'),
              AstNode.list(
                ordered: false,
                items: [
                  AstNode.listItem(content: [_plainParagraph('inner one')]),
                  AstNode.listItem(content: [_plainParagraph('inner two')]),
                ],
              ),
            ],
          ),
          AstNode.listItem(content: [_plainParagraph('outer two')]),
        ],
      ),
      AstNode.list(
        ordered: true,
        items: [
          AstNode.listItem(content: [_plainParagraph('one')]),
          AstNode.listItem(content: [_plainParagraph('two')]),
          AstNode.listItem(content: [_plainParagraph('three')]),
        ],
      ),
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(
            checked: false,
            content: [_plainParagraph('unchecked')],
          ),
          AstNode.listItem(
            checked: true,
            content: [_plainParagraph('checked')],
          ),
        ],
      ),
    ]);

    final bullets = find.text('•');
    // The nested bullets still indent inside the outer item body, while the
    // outer siblings remain peer rows.
    expect(
      tester.getTopLeft(bullets.at(1)).dx,
      greaterThan(tester.getTopLeft(bullets.first).dx),
    );
    expect(
      tester.getTopLeft(bullets.at(3)).dx,
      tester.getTopLeft(bullets.first).dx,
    );
    _expectAlignedMarkerX(tester, find.text('1.'), 1);
    _expectAlignedMarkerX(tester, find.text('2.'), 1);
    _expectAlignedMarkerX(tester, find.text('3.'), 1);
    final orderedXs = [
      tester.getTopLeft(find.text('1.')).dx,
      tester.getTopLeft(find.text('2.')).dx,
      tester.getTopLeft(find.text('3.')).dx,
    ];
    expect(orderedXs.skip(1), everyElement(orderedXs.first));
    _expectAlignedMarkerX(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget.key == const ValueKey('task-checked') ||
            widget.key == const ValueKey('task-unchecked'),
      ),
      2,
    );
  });

  testWidgets('a bold run renders styled with no delimiters while the '
      'paragraph is unfocused', (tester) async {
    await pumpEditor(tester, [
      _paragraphOf([_plainRun('before '), _boldRun('bold')]),
    ]);

    // Live Preview: unfocused Blocks render formatted — no editable field,
    // no delimiter bytes anywhere on screen.
    expect(_writableFields(), findsNothing);
    expect(find.textContaining('**'), findsNothing);

    final wrapperSpan = _firstRichText(tester).text as TextSpan;
    final paragraphSpan = wrapperSpan.children!.first as TextSpan;
    final plainSpan = paragraphSpan.children![0] as TextSpan;
    final boldSpan = paragraphSpan.children![1] as TextSpan;
    expect(plainSpan.text, 'before ');
    expect(boldSpan.text, 'bold');
    expect(boldSpan.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('focusing that paragraph promotes it to its raw Markdown source, '
      'delimiters included', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'before **bold**';
    await pumpEditor(tester, [
      _paragraphOf([_plainRun('before '), _boldRun('bold')]),
    ], api: api);
    expect(find.textContaining('**'), findsNothing);

    await promoteByTap(tester, find.byType(RichText));

    // The whole point of the model: the user sees and types real Markdown.
    expect(_field(tester).controller.text, 'before **bold**');
    // The invisible formatted baseline owns only the promoted slot's layout;
    // it is not painted, hit-testable, semantic, or selectable.
    expect(find.byType(RichText), findsOneWidget);
    // Promotion itself is not an edit: nothing buffered yet, nothing
    // committed.
    expect(api.updateCount, 0);
    expect(api.commitCount, 0);
  });

  testWidgets('a failed promotion keeps the mounted Note readable and shows '
      'a dismissible localized status', (tester) async {
    final api = _FakeRustApi();
    final container = await pumpEditor(tester, [
      _plainParagraph('still readable'),
    ], api: api);

    // The fake has no source for this path, so promotion fails after the
    // rendered Note is already mounted. This must not route through the
    // no-note-only fatal panel.
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    expect(find.text('still readable'), findsOneWidget);
    expect(_writableFields(), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Could not complete the editor operation'),
      findsOneWidget,
    );
    expect(find.textContaining('no source for [0]'), findsOneWidget);
    expect(container.read(editorErrorProvider), isNull);
  });

  testWidgets('a multi-run paragraph keeps each run\'s distinct styling '
      'while rendered', (tester) async {
    await pumpEditor(tester, [
      _paragraphOf([_plainRun('before '), _boldRun('bold')]),
    ]);

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final wrapperSpan = richText.text as TextSpan;
    final paragraphSpan = wrapperSpan.children!.first as TextSpan;
    final firstRun = paragraphSpan.children![0] as TextSpan;
    final secondRun = paragraphSpan.children![1] as TextSpan;

    expect(firstRun.text, 'before ');
    expect(firstRun.style?.fontWeight, isNull);
    expect(secondRun.text, 'bold');
    expect(secondRun.style?.fontWeight, FontWeight.bold);
  });

  // -- CAP-EDIT-02: every Block type is editable ---------------------------

  testWidgets(
    'a heading, a list, a blockquote, a code Block and a thematic break '
    'each display their own raw source and accept edits when focused',
    (tester) async {
      final cases = <(AstNode, String)>[
        (
          AstNode.heading(level: 2, content: [_plainRun('Head two')]),
          '## Head two',
        ),
        (
          AstNode.list(
            ordered: false,
            items: [
              AstNode.listItem(content: [_plainParagraph('item one')]),
            ],
          ),
          '- item one',
        ),
        (
          AstNode.blockquote(nodes: [_plainParagraph('quoted line')]),
          '> quoted line',
        ),
        (
          AstNode.codeBlock(code: 'print(1);\nprint(2);'),
          '```\nprint(1);\nprint(2);\n```',
        ),
        // The last member of the CAP-EDIT-02 Block-type list: renders as a
        // rule unfocused, shows its source focused like any other Block.
        (const AstNode.thematicBreak(), '---'),
      ];

      for (final (node, rawSource) in cases) {
        final api = _FakeRustApi()..sources['0'] = rawSource;
        await pumpEditor(tester, [node], api: api);

        // Thematic breaks render as a rule, not text, until focused.
        if (node is! AstNode_ThematicBreak) {
          expect(_writableFields(), findsNothing);
        }

        await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

        expect(
          _field(tester).controller.text,
          rawSource,
          reason: 'focused $node must show its own raw source',
        );

        await tester.enterText(find.byType(EditableText), 'edited');
        await tester.pump();

        // The edit went to the Core's buffering call against this Block.
        expect(api.lastBlockPath, [0]);
        expect(api.lastSource, 'edited');
      }
    },
  );

  testWidgets('an unfocused thematic break renders as a rule', (tester) async {
    await pumpEditor(tester, [const AstNode.thematicBreak()]);
    expect(find.byType(Divider), findsOneWidget);
    expect(_writableFields(), findsNothing);
  });

  // -- Caret placement -----------------------------------------------------

  testWidgets('the caret is placed at the clicked position, not the start', (
    tester,
  ) async {
    final api = _FakeRustApi()..sources['0'] = 'hello world';
    await pumpEditor(tester, [_plainParagraph('hello world')], api: api);

    // Ahem (the test font) draws every glyph exactly fontSize wide, so the
    // boundary between characters is deterministic. The prose slot is now
    // centered, so derive the global x-coordinate from its render object.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final origin = paragraph.localToGlobal(Offset.zero);
    await tester.tapAt(
      Offset(origin.dx + 6 * 16 + 8, origin.dy + paragraph.size.height / 2),
    );
    await tester.pump();
    await tester.pump();

    expect(_field(tester).controller.selection.baseOffset, 6);
  });

  testWidgets('the selected prose measure centers entries on a wide editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpEditor(tester, [_plainParagraph('measure')]);
    final preferences = container.read(burlPreferencesProvider.notifier);

    preferences.setMeasure(BurlMeasure.wide);
    await tester.pump();
    final wide = tester.getRect(find.byKey(const ValueKey('entry-0')));
    expect(wide.left, 300);
    expect(wide.top, 40);
    expect(wide.width, 600);

    preferences.setMeasure(BurlMeasure.full);
    await tester.pump();
    final full = tester.getRect(find.byKey(const ValueKey('entry-0')));
    expect(full.left, 24);
    expect(full.width, 1152);
  });

  testWidgets('narrow editors retain touch padding while respecting measure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpEditor(tester, [_plainParagraph('narrow')]);
    container
        .read(burlPreferencesProvider.notifier)
        .setMeasure(BurlMeasure.technical);
    await tester.pump();

    final entry = tester.getRect(find.byKey(const ValueKey('entry-0')));
    expect(entry.left, 24);
    expect(entry.top, 32);
    expect(entry.width, 272);
  });

  testWidgets('font-scale preferences update prose and retain focused slots', (
    tester,
  ) async {
    final api = _FakeRustApi()..sources['0'] = 'scaled prose';
    final container = await pumpEditor(tester, [
      _plainParagraph('scaled prose'),
    ], api: api);
    final preferences = container.read(burlPreferencesProvider.notifier);

    for (final scale in BurlFontScale.values) {
      preferences.setFontScale(scale);
      await tester.pump();
      final richText = _firstRichText(tester);
      final root = richText.text as TextSpan;
      expect(root.style?.fontSize, scale.size);
    }

    final before = tester.getRect(find.byKey(const ValueKey('entry-0')));
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final focused = tester.getRect(find.byKey(const ValueKey('entry-0')));
    expect(_field(tester).style.fontSize, BurlFontScale.spacious.size);
    expect(focused, before);
  });

  // -- Typographic stability -----------------------------------------------

  testWidgets('position and size are unchanged across a focus+blur round '
      'trip', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'first **bold** end'
      ..sources['1'] = 'second block'
      ..commitResult = _testNoteState([
        _paragraphOf([
          _plainRun('first '),
          _boldRun('bold'),
          _plainRun(' end'),
        ]),
        _plainParagraph('second block'),
      ]);
    await pumpEditor(tester, [
      _paragraphOf([_plainRun('first '), _boldRun('bold'), _plainRun(' end')]),
      _plainParagraph('second block'),
    ], api: api);

    Rect entryRect() => tester.getRect(find.byKey(const ValueKey('entry-0')));

    final before = entryRect();

    // Focused: the raw field replaces the rendering, in the same slot.
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final focused = entryRect();

    // Blur by focusing the neighbouring Block; the first returns to
    // formatted output through commit_block's returned state.
    await promoteByTap(tester, find.byKey(const ValueKey('block-1')));
    final after = entryRect();

    expect(
      focused.topLeft,
      before.topLeft,
      reason: 'promotion must not move the Block',
    );
    expect(
      focused.size,
      before.size,
      reason:
          'SPK-EDIT-F001 §3b: pinned height/leading distribution make '
          'the two states geometrically identical',
    );
    expect(after, before, reason: 'blur restores the exact pre-focus geometry');
    expect(api.commitCount, 1);
    expect(api.committedPaths.single, [0]);
  });

  testWidgets('raw source may wrap an extra line at a boundary without moving '
      'plain or decorated Block entries', (tester) async {
    // The constrained viewport deliberately exercises real RenderParagraph
    // and RenderEditable line boxes at soft-wrap boundaries. It does not
    // inspect TextStyle properties: the source strings differ by Markdown
    // punctuation, so matching styles alone cannot prove stable geometry.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixtures =
        <(String, AstNode Function(String), String Function(String))>[
          (
            'paragraph',
            (text) => _paragraphOf([_plainRun('$text '), _boldRun('tail')]),
            (text) => '$text **tail**',
          ),
          (
            'heading',
            (text) => AstNode.heading(
              level: 2,
              content: [_plainRun('$text '), _boldRun('tail')],
            ),
            (text) => '## $text **tail**',
          ),
          (
            'decorated list item',
            (text) => AstNode.list(
              ordered: false,
              items: [
                AstNode.listItem(
                  content: [
                    _paragraphOf([_plainRun('$text '), _boldRun('tail')]),
                  ],
                ),
              ],
            ),
            (text) => '- $text **tail**',
          ),
          (
            'decorated blockquote',
            (text) => AstNode.blockquote(
              nodes: [
                _paragraphOf([_plainRun('$text '), _boldRun('tail')]),
              ],
            ),
            (text) => '> $text **tail**',
          ),
          (
            'decorated code block',
            (text) => AstNode.codeBlock(code: text),
            (text) => '```\n$text\n```',
          ),
        ];

    for (final (name, makeNode, makeSource) in fixtures) {
      var witnessedBoundary = false;
      // Each word count moves the same text through a different actual wrap
      // boundary. One must make the raw prefix/delimiters take an extra
      // painted line; the slot must nevertheless retain rendered geometry.
      for (var wordCount = 2; wordCount <= 50; wordCount++) {
        final renderedText = List.filled(wordCount, 'word').join(' ');
        final rawSource = makeSource(renderedText);
        final api = _FakeRustApi()..sources['0'] = rawSource;
        await pumpEditor(tester, [makeNode(renderedText)], api: api);

        final formattedFinder = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains(renderedText),
        );
        final formatted = tester.renderObject<RenderParagraph>(
          formattedFinder.first,
        );
        final formattedLines = formatted
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: renderedText.length),
            )
            .map((box) => box.top)
            .toSet()
            .length;
        final before = tester.getRect(find.byKey(const ValueKey('entry-0')));

        await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
        final raw = _renderEditable(tester);
        final rawLines = raw
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: rawSource.length),
            )
            .map((box) => box.top)
            .toSet()
            .length;

        if (rawLines <= formattedLines) continue;
        witnessedBoundary = true;
        expect(
          tester.getRect(find.byKey(const ValueKey('entry-0'))),
          before,
          reason:
              '$name promotion must keep the formatted slot when raw '
              'Markdown takes an extra rendered line',
        );
        break;
      }
      expect(
        witnessedBoundary,
        isTrue,
        reason:
            '$name fixture must exercise a real raw-vs-rendered wrap boundary',
      );
    }
  });

  // -- Promotion fidelity: container decorations replicated (P1/P2) --------

  testWidgets('a focused code Block keeps its themed pane and readable ink', (
    tester,
  ) async {
    final api = _FakeRustApi()..sources['0'] = '```\nprint(1);\n```';
    await pumpEditor(tester, [AstNode.codeBlock(code: 'print(1);')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    // The themed body the unfocused render draws is the same body containing
    // the promoted field (SPK-EDIT-F001 §3b).
    final body = find.ancestor(
      of: _writableFields(),
      matching: find.byKey(const ValueKey('code-block-body')),
    );
    expect(body, findsOneWidget);
    expect(_field(tester).style.color, const Color(0xff171717));

    // Rendered geometry, not a property guess: the field sits inset by the
    // pane's 12px padding on both axes — exactly where the formatted code
    // text painted before promotion.
    final fieldBox = tester.renderObject<RenderBox>(_writableFields().first);
    final paneBox = tester.renderObject<RenderBox>(body.first);
    expect(
      fieldBox.localToGlobal(Offset.zero) - paneBox.localToGlobal(Offset.zero),
      const Offset(12, 12),
    );
  });

  testWidgets('code header and body retain identical geometry while the raw '
      'caret and copy affordance stay live', (tester) async {
    final clipboard = _mockClipboard(tester);
    final api = _FakeRustApi()..sources['0'] = '```dart\nprint(1);\n```';
    await pumpEditor(tester, [
      const AstNode.codeBlock(language: 'dart', code: 'print(1);'),
    ], api: api);

    final entryBefore = tester.getRect(find.byKey(const ValueKey('entry-0')));
    final headerBefore = tester.getRect(
      find.byKey(const ValueKey('code-block-header')),
    );
    final bodyBefore = tester.getRect(
      find.byKey(const ValueKey('code-block-body')),
    );
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    // Copy is a header action, not a request to promote the code body.
    await tester.tap(find.byKey(const ValueKey('code-block-copy')));
    await tester.pump();
    expect(clipboard.value, 'print(1);');
    expect(find.text('Copied'), findsOneWidget);
    expect(_writableFields(), findsNothing);

    await promoteByTap(tester, find.byKey(const ValueKey('code-block-source')));
    final controller = _field(tester).controller;
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    expect(tester.getRect(find.byKey(const ValueKey('entry-0'))), entryBefore);
    expect(
      tester.getRect(find.byKey(const ValueKey('code-block-header'))),
      headerBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('code-block-body'))),
      bodyBefore,
    );
    expect(find.text('dart'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-block-copy')), findsOneWidget);
    expect(
      find.text('Copied'),
      findsOneWidget,
      reason: 'promotion keeps the authoritative code-slot state mounted',
    );

    await tester.tap(find.byKey(const ValueKey('code-block-copy')));
    await tester.pump();
    expect(_writableFields(), findsOneWidget);
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(tester.getRect(find.byKey(const ValueKey('entry-0'))), entryBefore);

    await tester.pump(const Duration(milliseconds: 1799));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('code copy feedback has no transition under reduced motion', (
    tester,
  ) async {
    _mockClipboard(tester);
    await pumpEditor(tester, [
      const AstNode.codeBlock(language: 'text', code: 'still'),
    ], disableAnimations: true);

    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byKey(const ValueKey('code-block-copy')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);

    final entry = tester.getRect(find.byKey(const ValueKey('entry-0')));
    await tester.tap(find.byKey(const ValueKey('code-block-copy')));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('entry-0'))), entry);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('H1 divider and rhythm remain in the same slot while focused', (
    tester,
  ) async {
    final api = _FakeRustApi()..sources['0'] = '# Title';
    await pumpEditor(tester, [
      AstNode.heading(level: 1, content: [_plainRun('Title')]),
    ], api: api);

    final entry = tester.getRect(find.byKey(const ValueKey('entry-0')));
    final divider = tester.getRect(
      find.byKey(const ValueKey('heading-1-divider')),
    );
    await promoteByTap(tester, find.text('Title'));

    expect(tester.getRect(find.byKey(const ValueKey('entry-0'))), entry);
    expect(
      tester.getRect(find.byKey(const ValueKey('heading-1-divider'))),
      divider,
    );
    expect(_field(tester).controller.text, '# Title');
  });

  testWidgets('task markers are compact and completed task ink is struck', (
    tester,
  ) async {
    await pumpEditor(tester, [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(checked: true, content: [_plainParagraph('done')]),
          AstNode.listItem(checked: false, content: [_plainParagraph('next')]),
        ],
      ),
    ]);

    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const ValueKey('task-checked')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-unchecked')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('task-checked'))),
      const Size.square(16),
    );
    final inheritedStyles = tester.widgetList<DefaultTextStyle>(
      find.ancestor(
        of: find.text('done'),
        matching: find.byType(DefaultTextStyle),
      ),
    );
    expect(
      inheritedStyles.any(
        (style) => style.style.decoration == TextDecoration.lineThrough,
      ),
      isTrue,
    );
  });

  testWidgets('focusing a blockquote preserves its entry geometry while raw '
      'source shows its quote marker', (tester) async {
    final api = _FakeRustApi()..sources['0'] = '> quoted line';
    await pumpEditor(tester, [
      AstNode.blockquote(nodes: [_plainParagraph('quoted line')]),
    ], api: api);

    final before = tester.getRect(find.byKey(const ValueKey('entry-0')));

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final focused = tester.getRect(find.byKey(const ValueKey('entry-0')));

    expect(
      focused.topLeft,
      before.topLeft,
      reason:
          'the raw `> ` marker may shift its glyphs, but not the Block slot',
    );
    expect(
      focused.size,
      before.size,
      reason: 'the promoted quote must retain the formatted entry footprint',
    );
  });

  testWidgets('focusing a list item preserves its entry geometry while raw '
      'source shows its list marker', (tester) async {
    final api = _FakeRustApi()..sources['0'] = '- item one';
    await pumpEditor(tester, [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_plainParagraph('item one')]),
        ],
      ),
    ], api: api);

    final before = tester.getRect(find.byKey(const ValueKey('entry-0')));

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final focused = tester.getRect(find.byKey(const ValueKey('entry-0')));

    expect(
      focused.topLeft,
      before.topLeft,
      reason:
          'the raw `- ` marker may shift its glyphs, but not the Block slot',
    );
    expect(focused.size, before.size);
  });

  testWidgets('a nested list leaf is promoted and edited through its leaf '
      'path, never the Core-refused container path', (tester) async {
    final api = _FakeRustApi(failContainerPaths: true)
      ..sources['0/0/0'] = 'first item'
      ..resolvedCarets['0'] = BlockCaret(
        blockPath: Uint64List.fromList([0, 0, 0]),
        caretOffset: BigInt.from(2),
      );
    await pumpEditor(tester, [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_plainParagraph('first item')]),
          AstNode.listItem(content: [_plainParagraph('formatted sibling')]),
        ],
      ),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    expect(_field(tester).controller.text, 'first item');
    expect(find.text('formatted sibling'), findsOneWidget);
    expect(_field(tester).controller.selection.baseOffset, 2);

    await tester.enterText(find.byType(EditableText), 'edited item');
    await tester.pump();

    expect(api.lastBlockPath, [0, 0, 0]);
    expect(api.lastSource, 'edited item');
  });

  testWidgets('a nested blockquote leaf is promoted through its leaf path', (
    tester,
  ) async {
    final api = _FakeRustApi(failContainerPaths: true)
      ..sources['0/0'] = 'quoted leaf'
      ..resolvedCarets['0'] = BlockCaret(
        blockPath: Uint64List.fromList([0, 0]),
        caretOffset: BigInt.one,
      );
    await pumpEditor(tester, [
      AstNode.blockquote(nodes: [_plainParagraph('quoted leaf')]),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(find.byType(EditableText), 'edited quote');
    await tester.pump();

    expect(api.lastBlockPath, [0, 0]);
    expect(api.lastSource, 'edited quote');
  });

  testWidgets('focused list leaves retain sibling pointer promotion, marker '
      'alignment, and Link activation', (tester) async {
    final list = AstNode.list(
      ordered: false,
      items: [
        AstNode.listItem(content: [_plainParagraph('first item')]),
        AstNode.listItem(content: [_plainParagraph('plain sibling')]),
        AstNode.listItem(
          content: [_linkedParagraph('linked sibling', 'list-target')],
        ),
      ],
    );
    final api = _LinkResolutionApi()
      ..sources['0/0/0'] = 'first item'
      ..sources['0/1/0'] = 'plain sibling'
      ..resolvedCarets['0'] = BlockCaret(
        blockPath: Uint64List.fromList([0, 0, 0]),
        caretOffset: BigInt.zero,
      )
      ..commitResult = _testNoteState([list]);
    api.resolutions['list-target'] = Completer<LinkTargetResolution>()
      ..complete(const LinkTargetResolution_Existing(noteId: 'list-note'));
    final container = await pumpEditor(tester, [list], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    _expectAlignedMarkerX(tester, find.text('•'), 3);
    expect(
      find.byKey(const ValueKey('internal-link-focus-0-list-target')),
      findsOneWidget,
    );

    // The sibling remains in the live BlockView surface, so its own pointer
    // gesture reaches Core for a fresh leaf path in one action.
    api.resolvedCarets['0'] = BlockCaret(
      blockPath: Uint64List.fromList([0, 1, 0]),
      caretOffset: BigInt.one,
    );
    await promoteByTap(tester, find.text('plain sibling'));
    expect(_field(tester).controller.text, 'plain sibling');
    expect(_field(tester).controller.selection.baseOffset, 1);

    // The Link target remains available after another leaf is focused; it
    // resolves at activation time rather than from Dart-owned note data.
    await activateInternalLink(tester, 0, 'list-target');
    expect(container.read(selectedNoteIdProvider), 'list-note');
  });

  testWidgets('focused blockquote leaves retain sibling keyboard promotion '
      'and Link activation', (tester) async {
    final quote = AstNode.blockquote(
      nodes: [
        _plainParagraph('first quote'),
        _linkedParagraph('quoted Link', 'quote-target'),
      ],
    );
    final api = _LinkResolutionApi()
      ..sources['0/0'] = 'first quote'
      ..sources['0/1'] = '[quoted Link](burlmd:quote-target)'
      ..resolvedCarets['0'] = BlockCaret(
        blockPath: Uint64List.fromList([0, 0]),
        caretOffset: BigInt.zero,
      )
      ..commitResult = _testNoteState([quote]);
    api.resolutions['quote-target'] = Completer<LinkTargetResolution>()
      ..complete(const LinkTargetResolution_Existing(noteId: 'quote-note'));
    final container = await pumpEditor(tester, [quote], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    expect(
      find.byKey(const ValueKey('internal-link-focus-0-quote-target')),
      findsOneWidget,
    );

    await activateInternalLink(tester, 0, 'quote-target');
    expect(container.read(selectedNoteIdProvider), 'quote-note');

    api.resolvedCarets['0'] = BlockCaret(
      blockPath: Uint64List.fromList([0, 1]),
      caretOffset: BigInt.one,
    );
    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const ValueKey('block-0')),
              matching: find.byType(Semantics),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(
      _field(tester).controller.text,
      '[quoted Link](burlmd:quote-target)',
    );
    expect(_field(tester).controller.selection.baseOffset, 1);
    expect(
      find.byKey(const ValueKey('internal-link-focus-0-quote-target')),
      findsNothing,
      reason: 'the raw focused source is editable text, not an active Link',
    );
  });

  testWidgets('a task item maps its text hit to the rendered paragraph, not '
      'the checkbox marker', (tester) async {
    final api = _FakeRustApi(failContainerPaths: true)
      ..sources['0/0/0'] = 'task text'
      ..resolvedCarets['0'] = BlockCaret(
        blockPath: Uint64List.fromList([0, 0, 0]),
        caretOffset: BigInt.one,
      );
    await pumpEditor(tester, [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(
            checked: true,
            content: [_plainParagraph('task text')],
          ),
        ],
      ),
    ], api: api);

    expect(find.byKey(const ValueKey('task-checked')), findsOneWidget);
    await promoteByTap(tester, find.text('task text'));

    expect(_field(tester).controller.text, 'task text');
    expect(_field(tester).controller.selection.baseOffset, 1);
  });

  testWidgets('a traversable rendered Block promotes on Enter through the '
      'same Core path as a pointer hit', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'keyboard raw';
    await pumpEditor(tester, [_plainParagraph('keyboard raw')], api: api);

    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const ValueKey('block-0')),
              matching: find.byType(Semantics),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'keyboard raw');
  });

  // -- Blur commits, focus re-derived from the returned state --------------

  testWidgets('editing a paragraph to begin with a list marker reshapes it '
      'on blur, with focus re-derived from the returned state', (tester) async {
    final reshaped = _testNoteState([
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_plainParagraph('now a list')]),
        ],
      ),
    ]);
    final api = _FakeRustApi()
      ..sources['0'] = 'plain words'
      ..commitResult = reshaped;
    final container = await pumpEditor(tester, [
      _plainParagraph('plain words'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(find.byType(EditableText), '- now a list');
    await tester.pump();
    expect(api.lastSource, '- now a list');

    await blurFocusedField(tester);

    // commit_block ran once, against the path that was focused...
    expect(api.commitCount, 1);
    expect(api.committedPaths.single, [0]);
    // ...and the returned state is authoritative: the Block is now a list.
    final adopted = container.read(activeNoteProvider)!;
    expect(identical(adopted, reshaped), isTrue);
    expect(adopted.ast.single, isA<AstNode_List>());
    expect(find.text('•'), findsOneWidget);
    // Focus was re-derived from the returned state — i.e. nothing retained:
    // no field survives the commit.
    expect(_writableFields(), findsNothing);
  });

  testWidgets('typing uses only the buffering call; the reparse waits for '
      'blur', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'start'
      ..commitResult = _testNoteState([_plainParagraph('start typed')]);
    await pumpEditor(tester, [_plainParagraph('start')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    await tester.enterText(find.byType(EditableText), 'start t');
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'start typ');
    await tester.pump();

    // Every keystroke went to `update_block`; no reparsing call fired while
    // focus lasted — that is what keeps the reparse off the typing path.
    expect(api.updateCount, 2);
    expect(api.commitCount, 0);

    await blurFocusedField(tester);
    expect(api.commitCount, 1);
  });

  testWidgets('a focused raw field delegates Delete, Paste, and Cut to '
      'EditableText instead of the cross-Block actions', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'draft';
    await pumpEditor(tester, [_plainParagraph('draft')], api: api);
    final clipboard = _mockClipboard(tester, ' paste ');

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final field = _field(tester);
    field.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 4,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(field.controller.text, 'dt');

    field.controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(field.controller.text, 'd paste t');

    field.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 8,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(field.controller.text, 'dt');
    expect(clipboard.value, ' paste ');
    expect(api.lastSource, 'dt');
  });

  testWidgets('a refused blur commit retains and refocuses the raw field', (
    tester,
  ) async {
    final api = _FakeRustApi()..sources['0'] = 'draft';
    final container = await pumpEditor(tester, [
      _plainParagraph('draft'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields(), 'edited raw source');
    await tester.pump();

    await blurFocusedField(tester);

    expect(api.commitCount, 1);
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'edited raw source');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(container.read(keystrokeWriteFailureProvider), isA<Exception>());
  });

  // -- IME composition survival ---------------------------------------------

  testWidgets('a live IME composition survives an external resync and a '
      'blur commit without loss, duplication or reordering', (tester) async {
    final composed = _testNoteState([
      _paragraphOf([_plainRun('base中')]),
    ]);
    final api = _FakeRustApi()
      ..sources['0'] = 'base'
      ..commitResult = composed;
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    // A marked, not-yet-committed CJK string arrives over the input
    // connection with a live composing range.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // The composing bytes were buffered to the Core as they arrived...
    expect(api.lastSource, 'base中');
    expect(_field(tester).controller.text, 'base中');

    // ...and provider state changing underneath the composition (any
    // external adopt) must NOT stomp the live composing region.
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base'),
    ]);
    await tester.pump();
    expect(
      _field(tester).controller.text,
      'base中',
      reason:
          'a resync during a live composition would discard or '
          'duplicate the composing string',
    );

    // Blur commits; the composition completes into the Block's source via
    // the returned state.
    await blurFocusedField(tester);
    expect(
      container.read(activeNoteProvider)!.ast.single,
      isA<AstNode_Paragraph>(),
    );
    final adoptedParagraph =
        container.read(activeNoteProvider)!.ast.single as AstNode_Paragraph;
    final adoptedText =
        (adoptedParagraph.content.single as InlineElement_Text).field0.content;
    expect(adoptedText, 'base中');

    // Navigating back: the field reopens holding the composed text exactly
    // once — never duplicated, reordered, or silently discarded.
    api.sources['0'] = 'base中';
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    expect('base中'.allMatches(_field(tester).controller.text).length, 1);
    expect(_field(tester).controller.text, 'base中');
  });

  testWidgets('a completed IME composition rebases the latest deferred '
      'resync before the next keystroke', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // This is the old source from the provider event, not the Core's latest
    // working bytes after the composing update. It must not be replayed when
    // the composing range subsequently collapses.
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base'),
    ]);
    await tester.pump();

    // IMEs commonly commit by clearing only `composing`, so this produces no
    // onChanged callback. The controller listener must still settle the
    // deferred source before the next input arrives.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中文',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(_field(tester).controller.text, 'base中文');
    expect(api.lastSource, 'base中文');
  });

  testWidgets('a completed IME composition is buffered when its deferred '
      'Core resync still holds the composition base', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    final updatesBeforeResync = api.updateCount;

    // Simulate a lifecycle refetch racing the composing write. The refetched
    // Core source is the composition base, while the field already holds the
    // completed candidate. Clearing `composing` changes no text, so the
    // controller listener is the only place that can restore those bytes.
    api.sources['0'] = 'base';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base'),
    ]);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(_field(tester).controller.text, 'base中');
    expect(api.lastSource, 'base中');
    expect(
      api.updateCount,
      updatesBeforeResync + 1,
      reason:
          'the successful pending rebase must rewrite Core even when it does '
          'not change the controller value',
    );
  });

  testWidgets('a lifecycle rewrite rebases a gate-held IME composition only '
      'after its authoritative Block source reaches the field', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    final editing = container.read(lifecycleEditingProvider.notifier);
    editing.begin();
    // The platform may finish a candidate after the gate closes but before
    // Flutter paints the read-only rebuild. The provider boundary, rather
    // than the last frame's EditableText configuration, is authoritative.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(_writableFields(), findsNothing);
    api.sources['0'] = 'renamed base';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('renamed base'),
    ]);
    editing.end();
    // TestTextInput correctly rejects platform updates while the previous
    // frame's EditableText is read-only. Pump the release frame first: its
    // BlockEditor update must queue the authoritative source while the marked
    // range remains live; the following composing-only completion then takes
    // the same post-release reconciliation path as a real IME.
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    await tester.pump();

    expect(_field(tester).controller.text, 'renamed base中');
    expect(api.lastSource, 'renamed base中');
    expect(
      container.read(keystrokeWriteFailureProvider),
      isNull,
      reason: 'the disjoint rewrite and IME edit have a deterministic rebase',
    );
  });

  testWidgets('a lifecycle refusal re-admits an IME cancellation after the '
      'gate release without waiting for a widget replacement', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    final editing = container.read(lifecycleEditingProvider.notifier);
    editing.begin();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // A refusal leaves the existing Core session intact. Clearing composing
    // with the original value is a cancellation, so no stale source is
    // buffered and the post-frame fallback must not leave the field stuck.
    editing.end();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();

    expect(_field(tester).controller.text, 'base');
    expect(
      api.lastSource,
      'base',
      reason:
          'the completion callback may restage the unchanged base, but it '
          'must never preserve the cancelled marked candidate',
    );
    expect(_writableFields(), findsOneWidget);
  });

  testWidgets('only the latest external source is rebased with a completed '
      'IME composition', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // Two lifecycle rewrites land while the IME is live. The second one has
    // a disjoint prefix edit, so the composition can be rebased without
    // guessing or losing either side's bytes.
    api.sources['0'] = 'old base';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('old base'),
    ]);
    await tester.pump();
    api.sources['0'] = 'fresh base';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('fresh base'),
    ]);
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(_field(tester).controller.text, 'fresh base中');
    expect(api.lastSource, 'fresh base中');
  });

  testWidgets('an overlapping external rewrite enters an explicit conflict '
      'state without discarding IME or later field input', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'base';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // A distinct insertion at the exact same base offset has no intrinsic
    // ordering with the IME insertion, so neither result may win silently.
    api.sources['0'] = 'base!';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base!'),
    ]);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(_field(tester).controller.text, 'base中');
    expect(container.read(keystrokeWriteFailureProvider), isA<StateError>());

    // The field still accepts the user's next character visually, but does
    // not write its stale branch over Core's divergent rewrite.
    final writesBeforeNextKey = api.updateCount;
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中文',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    expect(_field(tester).controller.text, 'base中文');
    expect(api.updateCount, writesBeforeNextKey);

    // Blurring cannot commit either branch over the other. The field remains
    // available for copying until the user leaves the note deliberately.
    await blurFocusedField(tester);
    expect(api.commitCount, 0);
  });

  testWidgets('a conflicted field survives pointer promotion of another '
      'Block without committing either branch', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'base'
      ..sources['1'] = 'other';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
      _plainParagraph('other'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    api.sources['0'] = 'base!';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base!'),
      _plainParagraph('other'),
    ]);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    final writesAtConflict = api.updateCount;

    await promoteByTap(tester, find.byKey(const ValueKey('block-1')));

    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'base中');
    expect(api.commitCount, 0);
    expect(api.updateCount, writesAtConflict);
    expect(api.sources['0'], 'base!');
    expect(container.read(keystrokeWriteFailureProvider), isA<StateError>());
  });

  testWidgets('a conflicted field survives keyboard promotion of another '
      'rendered Block without committing either branch', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'base'
      ..sources['1'] = 'other';
    final container = await pumpEditor(tester, [
      _plainParagraph('base'),
      _plainParagraph('other'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    api.sources['0'] = 'base!';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('base!'),
      _plainParagraph('other'),
    ]);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    final writesAtConflict = api.updateCount;

    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const ValueKey('block-1')),
              matching: find.byType(Semantics),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'base中');
    expect(api.commitCount, 0);
    expect(api.updateCount, writesAtConflict);
    expect(api.sources['0'], 'base!');
    expect(container.read(keystrokeWriteFailureProvider), isA<StateError>());
  });

  testWidgets('an eligible focused Block still commits before pointer '
      'promotion of another Block', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'first'
      ..sources['1'] = 'second'
      ..commitResult = _testNoteState([
        _plainParagraph('first'),
        _plainParagraph('second'),
      ]);
    await pumpEditor(tester, [
      _plainParagraph('first'),
      _plainParagraph('second'),
    ], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    await promoteByTap(tester, find.byKey(const ValueKey('block-1')));

    expect(api.commitCount, 1);
    expect(api.committedPaths.single, [0]);
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'second');
  });

  // -- Keystroke round trip -------------------------------------------------

  testWidgets(
    'typing in a focused paragraph calls update_block with the raw source '
    'within one frame, and does not itself reparse the note',
    (tester) async {
      final api = _FakeRustApi()
        ..sources['0'] = 'before'
        ..commitResult = _testNoteState([_plainParagraph('after')]);
      final container = await pumpEditor(tester, [
        _plainParagraph('before'),
      ], api: api);

      await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
      await tester.enterText(find.byType(EditableText), 'after');
      await tester.pump(); // exactly one frame — no extra async round trip

      // `update_block` (ADR-007 decision 4) is the per-keystroke call: it
      // takes the Block's raw source text, not a reconstructed AstNode.
      expect(api.lastNoteId, _testMetadata.id);
      expect(api.lastBlockPath, [0]);
      expect(api.lastSource, 'after');
      expect(api.updateCount, 1);

      // The field itself already shows the typed text via its own
      // TextEditingController — that is what the user sees.
      expect(find.text('after'), findsOneWidget);

      // `update_block` performs no parse, so the provider's own note state
      // is left exactly as it was until blur commits.
      final updated = container.read(activeNoteProvider)!;
      final paragraph = updated.ast.single as AstNode_Paragraph;
      final leaf = paragraph.content.single as InlineElement_Text;
      expect(leaf.field0.content, 'before');
    },
  );

  testWidgets('an external state change resyncs the focused field from the '
      'Core once the composition is not live', (tester) async {
    final api = _FakeRustApi()..sources['0'] = 'first';
    final container = await pumpEditor(tester, [
      _plainParagraph('first'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    expect(_field(tester).controller.text, 'first');

    // Swap in different content for the same note without the user typing;
    // the field refetches its source rather than keeping stale bytes whose
    // next keystroke would revert a Core-side rewrite.
    api.sources['0'] = 'second source';
    container.read(activeNoteProvider.notifier).state = _testNoteState([
      _plainParagraph('second'),
    ]);
    await tester.pump();

    expect(
      _field(tester).controller.text,
      'second source',
      reason:
          'the focused field must resync to the externally-swapped note '
          'content instead of keeping the previous stale text',
    );
  });

  testWidgets(
    'multiple phantom updates before a pump reach the returned Core Block',
    (tester) async {
      final materialized = _testNoteState([_plainParagraph('a')]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([0]),
          caretOffset: BigInt.one,
        );
      final container = await pumpEditor(tester, const [], api: api);

      // These are separate platform values in one frame: rebuilding only
      // after the first used to strand `ab`/`abc` in the phantom controller.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(api.continuationCount, 1);
      expect(api.lastBlockPath, [0]);
      expect(api.lastSource, 'abc');

      await tester.pump();
      expect(container.read(activeNoteProvider), same(materialized));
      expect(_field(tester).controller.text, 'abc');
      expect(_field(tester).focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'multiline phantom materialization continues typing in Core’s final leaf',
    (tester) async {
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two😀'),
      ]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from('two😀'.length),
        )
        ..sources['1'] = 'two😀';
      final container = await pumpEditor(tester, const [], api: api);

      await tester.enterText(_writableFields(), 'one\n\ntwo😀');
      await tester.pump();

      expect(container.read(activeNoteProvider), same(materialized));
      expect(_field(tester).controller.text, 'two😀');
      expect(_field(tester).controller.selection.extentOffset, 'two😀'.length);

      await tester.enterText(_writableFields(), 'two😀!');
      await tester.pump();

      expect(api.continuationCount, 1);
      expect(api.lastBlockPath, [1]);
      expect(api.lastSource, 'two😀!');
    },
  );

  testWidgets(
    'same-frame multiline phantom values apply only their final-leaf delta',
    (tester) async {
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two'),
      ]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from(3),
        )
        ..sources['1'] = 'two';
      await pumpEditor(tester, const [], api: api);

      // Both platform values arrive before the materialized field can replace
      // the phantom controller. The second value still contains the whole
      // old multiline source, so sending it directly would duplicate `one`.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntwo',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntwo!',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );

      expect(api.continuationCount, 1);
      expect(api.lastBlockPath, [1]);
      expect(api.lastSource, 'two!');

      await tester.pump();
      expect(_field(tester).controller.text, 'two!');
    },
  );

  testWidgets(
    'same-frame phantom deltas preserve a Unicode leaf before Core’s LF terminator',
    (tester) async {
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two😀'),
      ]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from('two😀'.length),
        )
        // Real Core leaf sources include one structural final line ending.
        ..sources['1'] = 'two😀\n';
      await pumpEditor(tester, const [], api: api);

      // These values all arrive before the phantom field rebuilds. Append,
      // delete, then replace within the final leaf; none may duplicate the
      // preceding materialized paragraph or consume Core's terminal LF.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntwo😀',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntwo😀!',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntwo😀',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\n\ntx😀',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );

      expect(api.continuationCount, 1);
      expect(api.updateCount, 3);
      expect(api.lastBlockPath, [1]);
      expect(api.lastSource, 'tx😀\n');

      await tester.pump();
      expect(_field(tester).controller.text, 'tx😀\n');
      expect(_field(tester).controller.selection.extentOffset, 'tx😀'.length);
    },
  );

  testWidgets(
    'same-frame phantom deltas preserve Core’s CRLF leaf terminator',
    (tester) async {
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two'),
      ]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from(3),
        )
        ..sources['1'] = 'two\r\n';
      await pumpEditor(tester, const [], api: api);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\r\n\r\ntwo',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one\r\n\r\ntwo!',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );

      expect(api.continuationCount, 1);
      expect(api.updateCount, 1);
      expect(api.lastBlockPath, [1]);
      expect(api.lastSource, 'two!\r\n');

      await tester.pump();
      expect(_field(tester).controller.text, 'two!\r\n');
    },
  );

  testWidgets(
    'same-frame phantom deltas preserve Unicode selections, deletions, and replacements',
    (tester) async {
      const initial = 'one\n\ntwo😀';
      const afterDeletion = 'one\n\ntwo';
      const afterReplacement = 'one\n\ntx😀';
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two😀'),
      ]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from('two😀'.length),
        )
        ..sources['1'] = 'two😀';
      await pumpEditor(tester, const [], api: api);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: initial,
          selection: TextSelection(baseOffset: 8, extentOffset: initial.length),
        ),
      );
      // Delete the selected surrogate pair from the final materialized leaf.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: afterDeletion,
          selection: TextSelection.collapsed(offset: afterDeletion.length),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: afterDeletion,
          selection: TextSelection(baseOffset: 6, extentOffset: 8),
        ),
      );
      // Then replace a selected ASCII suffix with a mixed-width value.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: afterReplacement,
          selection: TextSelection.collapsed(offset: afterReplacement.length),
        ),
      );

      expect(api.continuationCount, 1);
      expect(api.lastBlockPath, [1]);
      expect(api.lastSource, 'tx😀');

      await tester.pump();
      expect(_field(tester).controller.text, 'tx😀');
      expect(_field(tester).controller.selection.extentOffset, 'tx😀'.length);
    },
  );

  testWidgets(
    'successful insertion-slot materialization does not raise a stale-slot warning',
    (tester) async {
      final afterSelection = _testNoteState([_plainParagraph('beta')]);
      final materialized = _testNoteState([
        _plainParagraph('one'),
        _plainParagraph('two😀'),
        _plainParagraph('beta'),
      ]);
      final slot = StructuralEditInsertionSlot(
        sourceOffset: BigInt.zero,
        linePrefix: '',
        requiredAfterNewlines: BigInt.zero,
        noteId: _testMetadata.id,
        sourceFingerprint: 'test-slot',
      );
      final api = _FakeRustApi()
        ..sources['0'] = 'alpha'
        ..sources['1'] = 'beta'
        ..replaceSelectionResult = StructuralEdit(
          state: afterSelection,
          blockPath: Uint64List(0),
          caretOffset: BigInt.zero,
          phantomInsertionSlot: slot,
        )
        ..slotContinuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.from('two😀'.length),
        )
        ..sources['1'] = 'two😀';
      final container = await pumpEditor(tester, [
        _plainParagraph('alpha'),
        _plainParagraph('beta'),
      ], api: api);
      await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
      _field(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(_writableFields(), 'one\n\ntwo😀');
      await tester.pump();

      expect(container.read(activeNoteProvider), same(materialized));
      expect(api.slotContinuationCount, 1);
      expect(_field(tester).controller.text, 'two😀');
      expect(
        container.read(keystrokeWriteFailureProvider),
        isNull,
        reason: 'consuming the exact returned slot is not a stale-slot failure',
      );
    },
  );

  testWidgets(
    'a successful phantom mutation cannot be retried when source hydration fails',
    (tester) async {
      final materialized = _testNoteState([_plainParagraph('typed')]);
      final api = _FakeRustApi()
        ..continuationResult = StructuralEdit(
          state: materialized,
          blockPath: Uint64List.fromList([0]),
          caretOffset: BigInt.from(5),
        )
        ..sources['0'] = 'typed';
      final container = await pumpEditor(tester, const [], api: api);
      api.failBlockSource = true;

      await tester.enterText(_writableFields(), 'typed');
      await tester.pump();

      expect(container.read(activeNoteProvider), same(materialized));
      expect(_writableFields(), findsNothing);
      expect(api.continuationCount, 1);
      expect(container.read(keystrokeWriteFailureProvider), isNull);

      api.failBlockSource = false;
      await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
      await tester.enterText(_writableFields(), 'typed!');
      await tester.pump();

      expect(api.continuationCount, 1);
      expect(api.lastBlockPath, [0]);
      expect(api.lastSource, 'typed!');
    },
  );

  testWidgets(
    'successful split hydration failure retires the old field for authoritative rendering',
    (tester) async {
      final splitState = _testNoteState([
        _plainParagraph('al'),
        _plainParagraph('pha'),
      ]);
      final api = _FakeRustApi()
        ..sources['0'] = 'alpha'
        ..splitResult = StructuralEdit(
          state: splitState,
          blockPath: Uint64List.fromList([1]),
          caretOffset: BigInt.zero,
        );
      final container = await pumpEditor(tester, [
        _plainParagraph('alpha'),
      ], api: api);
      await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
      api.failBlockSource = true;
      _field(tester).controller.selection = const TextSelection.collapsed(
        offset: 2,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(container.read(activeNoteProvider), same(splitState));
      expect(_writableFields(), findsNothing);
      expect(container.read(editorErrorProvider), isNull);
      expect(container.read(keystrokeWriteFailureProvider), isNull);
      expect(
        find.textContaining('Could not complete the editor operation'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'successful selected Enter hydration failure retires the old field for authoritative rendering',
    (tester) async {
      final splitState = _testNoteState([_plainParagraph('replacement')]);
      final api = _FakeRustApi()
        ..sources['0'] = 'alpha'
        ..replaceSelectionResult = StructuralEdit(
          state: splitState,
          blockPath: Uint64List.fromList([0]),
          caretOffset: BigInt.zero,
        );
      final container = await pumpEditor(tester, [
        _plainParagraph('alpha'),
      ], api: api);
      await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
      api.failBlockSource = true;
      _field(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(container.read(activeNoteProvider), same(splitState));
      expect(_writableFields(), findsNothing);
      expect(container.read(editorErrorProvider), isNull);
      expect(container.read(keystrokeWriteFailureProvider), isNull);
      expect(
        find.textContaining('Could not complete the editor operation'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'successful merge hydration failure retires the old field for authoritative rendering',
    (tester) async {
      final mergedState = _testNoteState([_plainParagraph('alphabeta')]);
      final api = _FakeRustApi()
        ..sources['0'] = 'alpha'
        ..sources['1'] = 'beta'
        ..mergeResult = StructuralEdit(
          state: mergedState,
          blockPath: Uint64List.fromList([0]),
          caretOffset: BigInt.from(5),
        );
      final container = await pumpEditor(tester, [
        _plainParagraph('alpha'),
        _plainParagraph('beta'),
      ], api: api);
      await promoteByTap(tester, find.byKey(const ValueKey('block-1')));
      api.failBlockSource = true;
      _field(tester).controller.selection = const TextSelection.collapsed(
        offset: 0,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(container.read(activeNoteProvider), same(mergedState));
      expect(_writableFields(), findsNothing);
      expect(container.read(editorErrorProvider), isNull);
      expect(container.read(keystrokeWriteFailureProvider), isNull);
      expect(
        find.textContaining('Could not complete the editor operation'),
        findsOneWidget,
      );
    },
  );

  testWidgets('an empty-note phantom cannot carry live or completed IME text '
      'into a lifecycle-created Note', (tester) async {
    final created = _noteState('Created', const []);
    final createGate = Completer<void>();
    final api = _LifecycleEditorApi()
      ..createGate = createGate
      ..createResult = _lifecycleResult(created)
      ..openStates[created.metadata.id] = created;
    final container = await pumpEditor(tester, const [], api: api);

    expect(_writableFields(), findsOneWidget);
    final create = container
        .read(lifecycleActionsProvider)
        .createNote('', 'Created');

    // Both values arrive after the lifecycle gate closes but before the
    // authoritative created session replaces the empty Note. Neither the
    // live marked text nor its composing-only completion may materialize the
    // phantom under Created's same numerical first-block slot.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'draft中',
        composing: TextRange(start: 5, end: 6),
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'draft中',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    createGate.complete();
    await create;
    await tester.pumpAndSettle();

    expect(container.read(activeNoteProvider), same(created));
    // The new empty Note owns a fresh phantom, not the old controller or its
    // completed IME value.
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, isEmpty);
    expect(api.continuationCount, 0);
    expect(api.updateCount, 0);
  });

  testWidgets('create and lifecycle-admitted recovery replace a focused real '
      'Block instead of rekeying it', (tester) async {
    final old = _noteState('Old', [_plainParagraph('old source')]);
    final created = _noteState('Created', [_plainParagraph('created')]);
    final recovered = _noteState('Recovered', [_plainParagraph('recovered')]);
    final api = _LifecycleEditorApi()
      ..createResult = _lifecycleResult(created)
      ..openStates.addAll({
        created.metadata.id: created,
        recovered.metadata.id: recovered,
      })
      ..sources['0'] = 'old source';
    final container = await pumpEditor(tester, old.ast, api: api);
    container.read(activeNoteProvider.notifier).adopt(old);
    await tester.pump();
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    await container.read(lifecycleActionsProvider).createNote('', 'Created');
    await tester.pumpAndSettle();
    expect(container.read(activeNoteProvider), same(created));
    expect(_writableFields(), findsNothing);
    expect(api.updateCount, 0);

    // Recovery uses the same lifecycle-admitted open mechanism but has no
    // rekey proof. A focused Block in the outgoing created Note is therefore
    // never carried into the recovered session.
    container.read(activeNoteProvider.notifier).adopt(old);
    await tester.pump();
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    final editing = container.read(lifecycleEditingProvider.notifier)..begin();
    await container
        .read(activeNoteProvider.notifier)
        .openForLifecycle(recovered.metadata.id);
    editing.end();
    await tester.pumpAndSettle();
    expect(container.read(activeNoteProvider), same(recovered));
    expect(_writableFields(), findsNothing);
    expect(api.updateCount, 0);
  });

  testWidgets('authoritative rename, move, and directory remaps preserve '
      'focus, but a later navigation clears it', (tester) async {
    final old = _noteState('Old', [_plainParagraph('old source')]);
    final renamed = _noteState('Renamed', [_plainParagraph('renamed source')]);
    final moved = _noteState('Archive/Renamed', [
      _plainParagraph('moved source'),
    ]);
    final directoryRenamed = _noteState('NewArchive/Renamed', [
      _plainParagraph('directory source'),
    ]);
    final unrelated = _noteState('Elsewhere', [_plainParagraph('elsewhere')]);
    final api = _LifecycleEditorApi()
      ..renameResult = _lifecycleResult(renamed)
      ..moveResult = _lifecycleResult(moved)
      ..renameDirectoryResult = _lifecycleResult(
        directoryRenamed,
        effects: const LifecycleEffects(
          remapped: [
            IdRemap(oldId: 'Archive/Renamed', newId: 'NewArchive/Renamed'),
          ],
          rewritten: [],
        ),
      )
      ..openStates[directoryRenamed.metadata.id] = directoryRenamed
      ..sources.addAll({'0': 'old source'});
    final container = await pumpEditor(tester, old.ast, api: api);
    container.read(activeNoteProvider.notifier).adopt(old);
    container.read(selectedNoteIdProvider.notifier).select(old.metadata.id);
    await tester.pump();
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));

    await container.read(lifecycleActionsProvider).renameNote('Old', 'Renamed');
    await tester.pumpAndSettle();
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'old source');

    await container
        .read(lifecycleActionsProvider)
        .moveNote('Renamed', 'Archive');
    await tester.pumpAndSettle();
    expect(_writableFields(), findsOneWidget);

    await container
        .read(lifecycleActionsProvider)
        .renameDirectory('Archive', 'NewArchive');
    await tester.pumpAndSettle();
    expect(_writableFields(), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'post-rekey',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    expect(api.lastNoteId, directoryRenamed.metadata.id);

    // The token was cleared immediately after directory adoption, so this
    // later ordinary navigation cannot accidentally reuse it.
    container.read(activeNoteProvider.notifier).adopt(unrelated);
    await tester.pumpAndSettle();
    expect(_writableFields(), findsNothing);
  });

  testWidgets('stale internal-Link resolutions cannot navigate after a '
      'newer activation or source-Note change', (tester) async {
    final first = Completer<LinkTargetResolution>();
    final second = Completer<LinkTargetResolution>();
    final afterNoteChange = Completer<LinkTargetResolution>();
    final api = _LinkResolutionApi()
      ..resolutions['first'] = first
      ..resolutions['second'] = second
      ..resolutions['after-note-change'] = afterNoteChange;
    final container = await pumpEditor(tester, [
      _paragraphOf([
        InlineElement.link(
          targetId: 'first',
          exists: true,
          content: [_plainRun('First')],
        ),
        _plainRun(' then '),
        InlineElement.link(
          targetId: 'second',
          exists: true,
          content: [_plainRun('Second')],
        ),
      ]),
    ], api: api);
    await tester.pump();

    await activateInternalLink(tester, 0, 'first');
    await activateInternalLink(tester, 1, 'second');
    expect(api.calls, ['first', 'second']);
    first.complete(const LinkTargetResolution_Existing(noteId: 'old-target'));
    await tester.pump();
    expect(container.read(selectedNoteIdProvider), isNull);

    second.complete(
      const LinkTargetResolution_Existing(noteId: 'latest-target'),
    );
    await tester.pump();
    expect(container.read(selectedNoteIdProvider), 'latest-target');

    container.read(activeNoteProvider.notifier).state = NoteState(
      ast: [
        _paragraphOf([
          InlineElement.link(
            targetId: 'after-note-change',
            exists: true,
            content: [_plainRun('Stale')],
          ),
        ]),
      ],
      metadata: const NoteMetadata(
        id: 'origin-note',
        path: 'origin.md',
        title: 'Origin',
        lastModified: 0,
        okfConformant: true,
      ),
      baseRevision: 'head',
      restoredFromDraft: false,
    );
    await tester.pump();
    await activateInternalLink(tester, 0, 'after-note-change');
    container.read(activeNoteProvider.notifier).state = NoteState(
      ast: [_plainParagraph('replacement')],
      metadata: const NoteMetadata(
        id: 'replacement-note',
        path: 'replacement.md',
        title: 'Replacement',
        lastModified: 0,
        okfConformant: true,
      ),
      baseRevision: 'head',
      restoredFromDraft: false,
    );
    await tester.pump();
    afterNoteChange.complete(
      const LinkTargetResolution_Existing(noteId: 'stale-target'),
    );
    await tester.pump();

    expect(container.read(selectedNoteIdProvider), 'latest-target');
  });

  testWidgets('a failed Link resolution keeps the source Note mounted and '
      'reports a dismissible operation failure', (tester) async {
    final api = _LinkResolutionApi()..resolveError = StateError('index busy');
    final container = await pumpEditor(tester, [
      _linkedParagraph('Broken target', 'broken-target'),
    ], api: api);

    await activateInternalLink(tester, 0, 'broken-target');
    await tester.pump();

    expect(container.read(editorErrorProvider), isNull);
    expect(find.text('Broken target'), findsOneWidget);
    expect(
      find.textContaining('Could not complete the linked-note action'),
      findsOneWidget,
    );
  });

  testWidgets('a PathUnavailable link-target create keeps the source Note '
      'mounted and retryable', (tester) async {
    final api = _LinkResolutionApi()
      ..createError = const AppError.pathUnavailable('target already exists');
    api.resolutions['missing-target'] = Completer<LinkTargetResolution>()
      ..complete(
        const LinkTargetResolution_Missing(
          targetId: 'missing-target',
          directoryPath: 'projects',
          title: 'Missing target',
        ),
      );
    final container = await pumpEditor(tester, [
      _linkedParagraph('Missing target', 'missing-target'),
    ], api: api);

    await activateInternalLink(tester, 0, 'missing-target');
    await tester.pump();
    await tester.tap(find.text('Create note'));
    await tester.pump();
    await tester.pump();

    expect(container.read(editorErrorProvider), isNull);
    expect(find.text('Missing target'), findsOneWidget);
    expect(find.textContaining('target already exists'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('internal-link-focus-0-missing-target')),
      findsOneWidget,
    );
  });

  testWidgets('a commit warning after linked-note creation selects the '
      'authoritative session and shows one nonfatal status', (tester) async {
    final created = NoteState(
      ast: [_plainParagraph('created')],
      metadata: NoteMetadata(
        id: 'projects/Missing target',
        path: 'projects/Missing target.md',
        title: 'Missing target',
        lastModified: 0,
        okfConformant: true,
      ),
      baseRevision: 'head',
      restoredFromDraft: false,
    );
    final api = _LinkResolutionApi()
      ..createResult = LifecycleResult(
        state: created,
        effects: const LifecycleEffects(remapped: [], rewritten: []),
        removed: const [],
        warning: const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'commit unavailable',
        ),
      );
    api.resolutions['missing-target'] = Completer<LinkTargetResolution>()
      ..complete(
        const LinkTargetResolution_Missing(
          targetId: 'missing-target',
          directoryPath: 'projects',
          title: 'Missing target',
        ),
      );
    final container = await pumpEditor(tester, [
      _linkedParagraph('Missing target', 'missing-target'),
    ], api: api);

    await activateInternalLink(tester, 0, 'missing-target');
    await tester.pump();
    await tester.tap(find.text('Create note'));
    await tester.pumpAndSettle();

    expect(container.read(selectedNoteIdProvider), created.metadata.id);
    expect(container.read(activeNoteProvider), same(created));
    expect(find.text('created'), findsOneWidget);
    expect(_writableFields(), findsNothing);
    expect(find.textContaining('The change is applied'), findsOneWidget);
  });

  testWidgets('a stale linked-note creation cannot override a newer Note and '
      'still shows its completed Core warning once', (tester) async {
    final gate = Completer<void>();
    final created = _testNoteState([_plainParagraph('created')]);
    final api = _LinkResolutionApi()
      ..createGate = gate
      ..createResult = LifecycleResult(
        state: created,
        effects: const LifecycleEffects(remapped: [], rewritten: []),
        removed: const [],
        warning: const LifecycleWarning(
          stage: LifecycleWarningStage.commit,
          detail: 'stale warning',
        ),
      );
    api.resolutions['missing-target'] = Completer<LinkTargetResolution>()
      ..complete(
        const LinkTargetResolution_Missing(
          targetId: 'missing-target',
          directoryPath: 'projects',
          title: 'Missing target',
        ),
      );
    final container = await pumpEditor(tester, [
      _linkedParagraph('Missing target', 'missing-target'),
    ], api: api);

    await activateInternalLink(tester, 0, 'missing-target');
    await tester.pump();
    await tester.tap(find.text('Create note'));
    await tester.pump();
    final newer = _testNoteState([_plainParagraph('newer')]);
    container.read(activeNoteProvider.notifier).adopt(newer);
    // This directly models an authoritative host replacement. User-facing
    // navigation is rejected while linked-note creation owns lifecycle
    // admission.
    container
        .read(selectedNoteIdProvider.notifier)
        .selectForLifecycle(newer.metadata.id);
    gate.complete();
    await tester.pumpAndSettle();

    expect(container.read(activeNoteProvider), same(newer));
    expect(container.read(selectedNoteIdProvider), newer.metadata.id);
    expect(find.textContaining('stale warning'), findsOneWidget);
  });

  // -- SHEL-E004 ----------------------------------------------------------

  testWidgets('selecting a note in the tree renders its blocks as output', (
    tester,
  ) async {
    _setWideShellViewport(tester);
    final api = _ShellRustApi([
      TreeNode.note(id: 'n1', title: 'Seeded Note', path: 'Seeded.md'),
    ]);
    await _pumpShell(tester, api);

    // Nothing selected yet: the pane shows an affordance, not note content.
    expect(find.text('Select a note to open it'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.tap(find.text('Seeded Note'));
    await tester.pumpAndSettle();

    // The Core was asked to open the selected concept id...
    expect(api.calls, ['open:n1']);
    // ...and the returned Block renders as formatted output (a Heading).
    final richText = tester.widget<RichText>(
      find.text('Rendered n1', findRichText: true),
    );
    final wrapperSpan = richText.text as TextSpan;
    final headingContentSpan = wrapperSpan.children!.first as TextSpan;
    final leafSpan = headingContentSpan.children!.first as TextSpan;
    expect(leafSpan.text, 'Rendered n1');
    // A Heading declares bold styling at the wrapper level.
    expect(wrapperSpan.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('switching notes closes the outgoing one through the Core '
      'before the new one opens', (tester) async {
    final api = _ShellRustApi([]);
    final container = ProviderContainer(
      overrides: [rustApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final controller = container.read(activeNoteProvider.notifier);
    await controller.open('note-a');
    await controller.open('note-b');

    // Order is the whole criterion: close_note runs tier 3 (flush, session
    // commit, draft clear), so it must complete for the outgoing Note
    // before open_note is issued for the next one — otherwise the
    // outgoing session never reaches version history.
    expect(api.calls, ['open:note-a', 'close:note-a', 'open:note-b']);
    expect((container.read(activeNoteProvider)!).metadata.id, 'note-b');
  });

  testWidgets('typing while a gated switch closes and opens cannot mutate the '
      'outgoing Note or survive only in its controller', (tester) async {
    _setWideShellViewport(tester);
    final closeGate = Completer<void>();
    final api = _ShellRustApi(
      [
        TreeNode.note(id: 'note-a', title: 'Note A', path: 'A.md'),
        TreeNode.note(id: 'note-b', title: 'Note B', path: 'B.md'),
      ],
      closeGates: {'note-a': closeGate},
    );
    await _pumpShell(tester, api);

    await tester.tap(find.text('Note A'));
    await tester.pumpAndSettle();
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    expect(_field(tester).controller.text, 'Rendered note-a');

    await tester.tap(find.text('Note B'));
    await tester.pump();
    expect(api.calls, ['open:note-a', 'close:note-a']);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'doomed input',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump();
    expect(api.updatedSources, isEmpty);
    expect(_field(tester).controller.text, 'Rendered note-a');

    closeGate.complete();
    await tester.pumpAndSettle();
    expect(api.calls, ['open:note-a', 'close:note-a', 'open:note-b']);
    expect(find.text('Rendered note-b'), findsOneWidget);
  });

  testWidgets(
    'rapid selections issued before a switch completes still close the '
    'outgoing note exactly once and settle on the last selection',
    (tester) async {
      final gateA = Completer<void>();
      final api = _ShellRustApi([], openGates: {'note-a': gateA});
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final controller = container.read(activeNoteProvider.notifier);
      // Hold A's round trip in flight so B genuinely races it — exactly the
      // tap-A-then-tap-B gap where open(B) used to read a stale state and
      // skip A's still-owed close.
      final first = controller.open('note-a');
      await tester.pump();
      expect(api.calls, ['open:note-a']);

      final second = controller.open('note-b');
      gateA.complete();
      await first;
      await second;

      // Serialized: A is opened, then closed (its commit tier runs), then
      // B opens. Without serialization the close:A step was skipped.
      expect(api.calls, ['open:note-a', 'close:note-a', 'open:note-b']);
      expect(container.read(activeNoteProvider)!.metadata.id, 'note-b');
    },
  );

  testWidgets(
    'a failed outgoing close aborts the switch, rolls the tree selection '
    'back to the still-open note, and keeps the error surfaced',
    (tester) async {
      final api = _ShellRustApi([], failCloseFor: {'note-a'});
      final container = ProviderContainer(
        overrides: [rustApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final controller = container.read(activeNoteProvider.notifier);
      await controller.open('note-a');

      // The tree publishes the new selection, then drives the switch.
      container.read(selectedNoteIdProvider.notifier).select('note-b');
      await controller.open('note-b');

      // The switch aborted at close_note: B never opened.
      expect(api.calls, ['open:note-a', 'close:note-a']);
      expect(container.read(activeNoteProvider)!.metadata.id, 'note-a');
      // Selection rolled back so the tree highlight names the note actually
      // shown in the editor, not the one the Core refused to reach.
      expect(container.read(selectedNoteIdProvider), 'note-a');
      // Close refusal is nonfatal; a mounted Editor consumes its one-shot
      // status. This provider-only controller test leaves that value pending.
      expect(container.read(editorErrorProvider), isNull);
      expect(container.read(noteCloseFailureProvider), isA<Exception>());
    },
  );

  testWidgets('a failed gated close restores the coherent old raw editor', (
    tester,
  ) async {
    _setWideShellViewport(tester);
    final closeGate = Completer<void>();
    final api = _ShellRustApi(
      [
        TreeNode.note(id: 'note-a', title: 'Note A', path: 'A.md'),
        TreeNode.note(id: 'note-b', title: 'Note B', path: 'B.md'),
      ],
      failCloseFor: {'note-a'},
      closeGates: {'note-a': closeGate},
    );
    await _pumpShell(tester, api);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceScreen)),
    );

    await tester.tap(find.text('Note A'));
    await tester.pumpAndSettle();
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields(), 'saved before switch');
    await tester.pump();

    await tester.tap(find.text('Note B'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'doomed input',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump();
    expect(api.updatedSources, ['note-a:saved before switch']);

    closeGate.complete();
    await tester.pumpAndSettle();
    expect(api.calls, ['open:note-a', 'close:note-a']);
    expect(_field(tester).controller.text, 'saved before switch');
    expect(_field(tester).readOnly, isFalse);
    expect(find.textContaining('Could not switch notes'), findsOneWidget);
    expect(find.textContaining('close refused'), findsOneWidget);
    expect(container.read(noteCloseFailureProvider), isNull);
  });

  testWidgets('a failed incoming open leaves no writable snapshot of the '
      'already-closed Note', (tester) async {
    final api = _ShellRustApi([], failOpenFor: {'note-b'});
    final container = ProviderContainer(
      overrides: [rustApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final controller = container.read(activeNoteProvider.notifier);
    await controller.open('note-a');

    // The tree publishes the new selection, then drives the switch; this
    // time it is the incoming open_note that refuses.
    container.read(selectedNoteIdProvider.notifier).select('note-b');
    await controller.open('note-b');

    // B never opened; A was closed successfully, so it must not remain a
    // writable provider snapshot for a deregistered Core session.
    expect(api.calls, ['open:note-a', 'close:note-a', 'open:note-b']);
    expect(container.read(activeNoteProvider), isNull);
    expect(container.read(selectedNoteIdProvider), 'note-b');
  });

  testWidgets('a Core error on open surfaces instead of being swallowed', (
    tester,
  ) async {
    _setWideShellViewport(tester);
    final api = _ShellRustApi(
      [TreeNode.note(id: 'bad', title: 'Broken Note', path: 'Broken.md')],
      failOpenFor: {'bad'},
    );
    await _pumpShell(tester, api);

    await tester.tap(find.text('Broken Note'));
    await tester.pumpAndSettle();

    expect(api.calls, ['open:bad']);
    // The failure the fake Core threw is shown verbatim in the editor's
    // error surface — not raised into nothing.
    expect(find.textContaining('core exploded'), findsOneWidget);
    // And no note content is rendered alongside it — no editable field
    // from the editor's own rendering path.
    expect(_writableFields(), findsNothing);
  });
}

// -- SHEL-E004: mounting the editor and navigating -------------------------

/// Pumps the real [WorkspaceScreen] shell against [_ShellRustApi], so the
/// navigation path under test is the production one: tree selection ->
/// [selectedNoteIdProvider] -> the pane's listener -> [NoteController.open]
/// -> [Editor] rendering.
Future<void> _pumpShell(WidgetTester tester, _ShellRustApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WorkspaceScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The redesigned shell presents its navigator as a rail at the default
/// 800px test surface. These navigation-flow tests exercise the wide-shell
/// tree path, so establish that available width explicitly.
void _setWideShellViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
