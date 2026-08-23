import 'dart:async';

import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  _FakeRustApi();

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

  /// The authoritative state [commitBlock] returns.
  NoteState? commitResult;

  @override
  String getBlockSource(String noteId, List<int> blockPath) =>
      sources[blockPath.join('/')] ??
      (throw Exception('no source for $blockPath'));

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    lastNoteId = noteId;
    lastBlockPath = blockPath;
    lastSource = newSource;
    updateCount++;
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    committedPaths.add(blockPath);
    commitCount++;
    return commitResult ?? (throw Exception('no commit result prepared'));
  }
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

  /// Every open/close call in issue order, as `'open:<id>'` / `'close:<id>'`.
  final List<String> calls = [];

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
    if (failCloseFor.contains(noteId)) throw Exception('close refused');
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
        home: Scaffold(body: Editor(key: ValueKey('editor-${pumpCounter++}'))),
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

void main() {
  // -- CAP-EDIT-01: formatted when unfocused, raw when focused ------------

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
    expect(find.byType(RichText), findsNothing);
    // Promotion itself is not an edit: nothing buffered yet, nothing
    // committed.
    expect(api.updateCount, 0);
    expect(api.commitCount, 0);
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
    // boundary between characters is deterministic: character 6 ('w') starts
    // at 6*14 px into the painted paragraph; tap its middle.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    await tester.tapAt(Offset(6 * 14 + 7, paragraph.size.height / 2));
    await tester.pump();
    await tester.pump();

    expect(_field(tester).controller.selection.baseOffset, 6);
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

  // -- SHEL-E004 ----------------------------------------------------------

  testWidgets('selecting a note in the tree renders its blocks as output', (
    tester,
  ) async {
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
      // And the failure stays visible on the error surface.
      expect(
        '${container.read(editorErrorProvider)}',
        contains('close refused'),
      );
    },
  );

  testWidgets('a failed open of the newly selected note also rolls the tree '
      'selection back to the still-open note', (tester) async {
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

    // B never opened; A is still what the editor shows.
    expect(api.calls, ['open:note-a', 'close:note-a', 'open:note-b']);
    expect(container.read(activeNoteProvider)!.metadata.id, 'note-a');
    // Selection rolled back so the highlight names the note actually
    // shown — same rule as the close-abort branch above.
    expect(container.read(selectedNoteIdProvider), 'note-a');
  });

  testWidgets('a Core error on open surfaces instead of being swallowed', (
    tester,
  ) async {
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
      child: const MaterialApp(home: WorkspaceScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
