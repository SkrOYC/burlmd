import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';

class _FixedNoteController extends NoteController {
  _FixedNoteController(this.initial);

  final NoteState initial;

  @override
  NoteState? build() => initial;
}

class _RangeApi extends RustApi {
  final List<(BlockRange, String)> replacements = [];
  final List<BlockRange> deletes = [];

  late NoteState result;
  late RangeEditCaret caret;
  final Map<String, String> sources = {};

  @override
  RangeEditResult replaceRange(
    String noteId,
    BlockRange range,
    String replacement,
  ) {
    replacements.add((range, replacement));
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  RangeEditResult deleteRange(String noteId, BlockRange range) {
    deletes.add(range);
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  String getBlockSource(String noteId, List<int> blockPath) =>
      sources[blockPath.join('/')]!;
}

const _metadata = NoteMetadata(
  id: 'range-note',
  path: 'range.md',
  title: 'Range',
  lastModified: 0,
  okfConformant: true,
);

TextRun _run(String text) => TextRun(
  content: text,
  bold: false,
  italic: false,
  strikethrough: false,
  code: false,
);

AstNode _paragraph(String text) =>
    AstNode.paragraph(content: [InlineElement.text(_run(text))]);

NoteState _note(List<String> blocks) => NoteState(
  ast: [for (final block in blocks) _paragraph(block)],
  metadata: _metadata,
  baseRevision: 'head',
  restoredFromDraft: false,
);

Future<ProviderContainer> _pump(WidgetTester tester, _RangeApi api) async {
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(
        () => _FixedNoteController(
          _note(['first block', 'middle block', 'tail block']),
        ),
      ),
      rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Editor())),
    ),
  );
  return container;
}

Rect _box(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
  final renderBox = tester.renderObject<RenderBox>(finder.first);
  return renderBox.localToGlobal(Offset.zero) & renderBox.size;
}

Future<void> _selectAcrossBlocks(WidgetTester tester) async {
  final first = _box(tester, 'first block');
  final tail = _box(tester, 'tail block');
  final gesture = await tester.startGesture(
    first.topLeft + Offset(2 * 14 + 7, first.height / 2),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(tail.topLeft + Offset(4 * 14 + 7, tail.height / 2));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('type-over uses one frozen cross-Block Core replacement and '
      'uses Core returned path and UTF-16 caret', (tester) async {
    final api = _RangeApi()
      ..result = _note(['reshaped'])
      ..caret = RangeEditCaret.block(
        blockPath: Uint64List.fromList(const [0]),
        sourceOffsetUtf16: BigInt.from(2),
      )
      ..sources['0'] = 'reshaped\n';
    await _pump(tester, api);
    await _selectAcrossBlocks(tester);

    tester.testTextInput.enterText('😀');
    await tester.pump();
    await tester.pump();

    expect(api.replacements, hasLength(1));
    final (range, replacement) = api.replacements.single;
    expect(replacement, '😀');
    expect(range.startPath, Uint64List.fromList(const [0]));
    expect(range.endPath, Uint64List.fromList(const [2]));
    final field = tester.widget<EditableText>(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && !widget.readOnly,
      ),
    );
    expect(field.controller.text, 'reshaped\n');
    expect(field.controller.selection.baseOffset, 2);
  });

  testWidgets('DeleteCharacterIntent sends one atomic delete, never an '
      'updateBlock loop', (tester) async {
    final api = _RangeApi()
      ..result = _note([])
      ..caret = RangeEditCaret.phantom(insertionIndex: BigInt.zero);
    final container = await _pump(tester, api);
    await _selectAcrossBlocks(tester);

    Actions.invoke(
      tester.element(find.byType(SelectionArea)),
      const DeleteCharacterIntent(forward: true),
    );
    await tester.pump();
    await tester.pump();

    expect(api.deletes, hasLength(1));
    expect(container.read(activeNoteProvider)!.ast, isEmpty);
    expect(find.byKey(const ValueKey('edit-phantom')), findsOneWidget);
  });
}
