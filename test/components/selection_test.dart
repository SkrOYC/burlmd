import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// CAP-EDIT-04 (`EDIT-F003`): cross-Block selection over ONE region, with
/// copy produced by the Core (`copy_range_as_markdown`) rather than
/// serialized in Dart.
///
/// Method note (`SPK-EDIT-F001` §5): assertions read real interaction
/// outcomes — actual pointer drags through a live [SelectionArea], real
/// clipboard traffic captured at the platform-channel boundary, and the
/// [BlockRange] the fake Core actually received — never widget-property
/// guesses about what the selection "should" be.

/// A [NoteController] whose initial state is fixed at construction, so
/// tests can pump [Editor] against a known AST without a real FFI round
/// trip (same fixture device as `editor_test.dart`).
class _FixedNoteController extends NoteController {
  _FixedNoteController(this._initial);

  final NoteState _initial;

  @override
  NoteState? build() => _initial;
}

/// A [RustApi] standing in for the Core at the range-operation surface.
/// `copy_range_as_markdown` is recorded and answered with a canned string,
/// so every clipboard assertion proves the Markdown came FROM the Core —
/// if any Dart code serialized Markdown instead, the clipboard would not
/// carry this marker.
class _FakeRustApi extends RustApi {
  /// The Markdown [copyRangeAsMarkdown] returns — a marker no Dart-side
  /// serializer could produce by accident.
  static const coreMarkdown = '::CORE-SERIALIZED-MARKDOWN::';

  final List<BlockRange> copyRequests = [];

  /// Raw source returned per block path by [getBlockSource].
  final Map<String, String> sources = {};

  /// The authoritative state [commitBlock] returns on blur.
  NoteState? commitResult;

  @override
  String copyRangeAsMarkdown(String noteId, BlockRange range) {
    copyRequests.add(range);
    return coreMarkdown;
  }

  @override
  String getBlockSource(String noteId, List<int> blockPath) =>
      sources[blockPath.join('/')] ??
      (throw Exception('no source for $blockPath'));

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) =>
      commitResult ?? (throw Exception('no commit result prepared'));
}

TextRun _run(String text) => TextRun(
  content: text,
  bold: false,
  italic: false,
  strikethrough: false,
  code: false,
);

InlineElement _plainRun(String text) => InlineElement.text(_run(text));

AstNode _plainParagraph(String text) =>
    AstNode.paragraph(content: [_plainRun(text)]);

const _testMetadata = NoteMetadata(
  id: 'test-note',
  path: 'test-note.md',
  title: 'Test Note',
  lastModified: 0,
  okfConformant: true,
);

NoteState _note(List<AstNode> ast) => NoteState(
  ast: ast,
  metadata: _testMetadata,
  baseRevision: 'head',
  restoredFromDraft: false,
);

var _pumpSeed = 0;

Future<ProviderContainer> pumpEditor(
  WidgetTester tester,
  List<AstNode> ast, {
  RustApi? api,
}) async {
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(() => _FixedNoteController(_note(ast))),
      if (api != null) rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  var pumpCounter = _pumpSeed++;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: Editor(key: ValueKey('editor-$pumpCounter'))),
      ),
    ),
  );
  return container;
}

/// The painted text box of the Block whose rendered text contains [probe],
/// in global coordinates. Under the Ahem test font every glyph is exactly
/// its fontSize wide, so character boundaries are deterministic.
Rect _textBox(WidgetTester tester, String probe) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(probe),
  );
  final box = tester.renderObject<RenderBox>(finder.first);
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Drags with a mouse pointer from [start] to [end] in several increments —
/// a real drag-selection gesture through the live [SelectionArea].
Future<void> dragSelect(WidgetTester tester, Offset start, Offset end) async {
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  // Let the pointer-down settle before moving: with a Scrollable under the
  // region, moves arriving in the same frame as the down never engage the
  // region's drag recognizer.
  await tester.pump();
  const steps = 15.0;
  final delta = (end - start) / steps;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(delta);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Presses Ctrl+C (and Ctrl+A variants) as real hardware key events, so the
/// shortcut resolves from whatever actually holds primary focus — the same
/// path a user's keystroke takes.
Future<void> pressWithControl(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.sendKeyDownEvent(key);
  await tester.pump();
  await tester.sendKeyUpEvent(key);
  await tester.pump();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Captures clipboard writes at the platform-channel boundary.
void mockClipboard(WidgetTester tester, void Function(String text) onData) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>?;
        onData((args?['text'] as String?) ?? '');
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}

/// Field-wise matcher for a [BlockRange]: the generated `==` compares the
/// `Uint64List` path fields by identity, which never holds across instances.
Matcher _matchesRange(
  int startIndex,
  int startOffset,
  int endIndex,
  int endOffset,
) => isA<BlockRange>()
    .having((r) => r.startPath.map((e) => e.toInt()).toList(), 'startPath', [
      startIndex,
    ])
    .having((r) => r.startOffset, 'startOffset', BigInt.from(startOffset))
    .having((r) => r.endPath.map((e) => e.toInt()).toList(), 'endPath', [
      endIndex,
    ])
    .having((r) => r.endOffset, 'endOffset', BigInt.from(endOffset));

void main() {
  testWidgets('dragging from within the first Block to within the third '
      'spans all three Blocks with a visible selection', (tester) async {
    final api = _FakeRustApi();
    await pumpEditor(tester, [
      _plainParagraph('first block words'),
      _plainParagraph('second block words'),
      _plainParagraph('third block words'),
    ], api: api);

    final first = _textBox(tester, 'first block');
    final third = _textBox(tester, 'third block');
    // Character 4 of the first Block, character 5 of the third.
    await dragSelect(
      tester,
      first.topLeft + Offset(4 * 14 + 7, first.height / 2),
      third.topLeft + Offset(5 * 14 + 7, third.height / 2),
    );
    await tester.pumpAndSettle();

    // Visible selection, read from rendered state (SPK-EDIT-F001 §5): the
    // region's registered per-Block selectables report an uncollapsed
    // selection — exactly the state that drives highlight painting — and it
    // spans from Block 0 into Block 2.
    final editor = tester.state<EditorState>(find.byType(Editor));
    expect(
      editor.debugSelectedRange(),
      _matchesRange(0, 4, 2, 5),
      reason: 'a spanning selection must be live across all three Blocks',
    );

    // And the span really covers all three: the Core was asked for a range
    // whose endpoints sit in Block 0 and Block 2, so the middle Block is
    // interior to the selection rather than skipped as a hole.
    var clipboard = '';
    mockClipboard(tester, (text) => clipboard = text);
    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(api.copyRequests.single, _matchesRange(0, 4, 2, 5));
    expect(clipboard, _FakeRustApi.coreMarkdown);
  });

  testWidgets('copying a selection spanning three Blocks puts Core-produced '
      'Markdown for all three on the clipboard', (tester) async {
    final api = _FakeRustApi();
    await pumpEditor(tester, [
      _plainParagraph('first block words'),
      _plainParagraph('second block words'),
      _plainParagraph('third block words'),
    ], api: api);

    var clipboard = '';
    mockClipboard(tester, (text) => clipboard = text);

    final first = _textBox(tester, 'first block');
    final third = _textBox(tester, 'third block');
    await dragSelect(
      tester,
      first.topLeft + Offset(4 * 14 + 7, first.height / 2),
      third.topLeft + Offset(5 * 14 + 7, third.height / 2),
    );
    await tester.pumpAndSettle();

    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    // Exactly one Core round trip, carrying the selection as a BlockRange
    // with RENDERED offsets into Blocks 0 and 2.
    expect(api.copyRequests, hasLength(1));
    expect(api.copyRequests.single, _matchesRange(0, 4, 2, 5));

    // The clipboard holds what the CORE returned — the marker constant —
    // proving nothing was serialized in Dart.
    expect(clipboard, _FakeRustApi.coreMarkdown);
  });

  testWidgets('a heterogeneous selection — code block, list, paragraph — '
      'copies with per-variant rendered offsets', (tester) async {
    // The REQUIRED fixture: rendered-text offsets are defined per AstNode
    // variant (contract, BlockRange docs); three paragraphs would exercise
    // exactly one of those definitions.
    final api = _FakeRustApi();
    await pumpEditor(tester, [
      // Variant: CodeBlock — rendered text is `code` verbatim (no fence).
      AstNode.codeBlock(code: 'print(1);\nprint(2);'),
      // Variant: List/ListItem — children joined recursively with '\n'.
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_plainParagraph('alpha item')]),
          AstNode.listItem(content: [_plainParagraph('beta item')]),
        ],
      ),
      // Variant: Paragraph — concatenated runs, delimiters invisible.
      AstNode.paragraph(
        content: [
          _plainRun('A closing '),
          InlineElement.text(
            const TextRun(
              content: 'paragraph',
              bold: true,
              italic: false,
              strikethrough: false,
              code: false,
            ),
          ),
          _plainRun(' here'),
        ],
      ),
    ], api: api);

    var clipboard = '';
    mockClipboard(tester, (text) => clipboard = text);

    final code = _textBox(tester, 'print(1)');
    final para = _textBox(tester, 'closing');
    // Start inside the CODE variant (char 3 of the monospace ink, which maps
    // identically into the Core's verbatim definition), end inside the
    // PARAGRAPH variant (char 12 of 'A closing paragraph here', i.e. inside
    // the bold run's rendered text).
    await dragSelect(
      tester,
      // Mid-height of the code box would land on line 2 ('print(2);'); pin
      // the point to the middle of line 1 so the offset is deterministic.
      code.topLeft + const Offset(3 * 13 + 6.5, 14),
      para.topLeft + Offset(12 * 14 + 7, para.height / 2),
    );
    await tester.pumpAndSettle();

    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(api.copyRequests, hasLength(1));
    expect(
      api.copyRequests.single,
      _matchesRange(0, 3, 2, 12),
      reason:
          'the code Block contributes its verbatim-code offset and the '
          'paragraph its concatenated-run offset; the List sits between '
          'the endpoints and is covered by construction',
    );
    expect(clipboard, _FakeRustApi.coreMarkdown);
  });

  testWidgets('select-all selects the whole Note', (tester) async {
    final api = _FakeRustApi();
    await pumpEditor(tester, [
      _plainParagraph('first block words'),
      _plainParagraph('second block words'),
      _plainParagraph('third block words'),
    ], api: api);

    var clipboard = '';
    mockClipboard(tester, (text) => clipboard = text);

    // Give the region focus the way a user does — a small drag inside the
    // first Block — then invoke select-all through the keyboard shortcut.
    final first = _textBox(tester, 'first block');
    await dragSelect(
      tester,
      first.topLeft + Offset(2 * 14 + 7, first.height / 2),
      first.topLeft + Offset(6 * 14 + 7, first.height / 2),
    );
    await tester.pumpAndSettle();

    await pressWithControl(tester, LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(api.copyRequests, hasLength(1));
    expect(
      api.copyRequests.single,
      _matchesRange(0, 0, 2, 'third block words'.length),
      reason: 'select-all must cover every Block of the Note end to end',
    );
    expect(clipboard, _FakeRustApi.coreMarkdown);
  });

  testWidgets('a focused Block\'s internal text selection still copies '
      'normally, without consulting the Core range API', (tester) async {
    final api = _FakeRustApi()
      ..sources['0'] = 'hello world'
      ..commitResult = _note([_plainParagraph('hello world')]);
    final container = await pumpEditor(tester, [
      _plainParagraph('hello world'),
    ], api: api);

    var clipboard = '';
    mockClipboard(tester, (text) => clipboard = text);

    // Promote the Block (tap-to-focus, EDIT-F002) and select part of its raw
    // source the way a user would.
    await tester.tap(find.byKey(const ValueKey('block-0')), warnIfMissed: true);
    await tester.pump();
    await tester.pump();

    final field = tester.widget<EditableText>(
      find.byWidgetPredicate((w) => w is EditableText && !w.readOnly),
    );
    field.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();

    expect(container.read(activeNoteProvider), isNotNull);
    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    // The field copied its own RAW SOURCE slice — normal field behaviour —
    // and the Core's range API was never consulted.
    expect(clipboard, 'hello');
    expect(api.copyRequests, isEmpty);
  });
}
