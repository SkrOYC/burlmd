import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
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
  final List<String> wholeNoteReplacements = [];
  final List<String> replacementNoteIds = [];
  final List<BlockRange> deletes = [];
  final List<String> wholeNoteDeletes = [];
  final List<String> deleteNoteIds = [];
  final List<String> copiedNoteIds = [];
  final List<String> wholeNoteCopiedIds = [];
  final List<(List<int>, String)> updates = [];
  Object? operationError;

  late NoteState result;
  late RangeEditCaret caret;
  final Map<String, String> sources = {};

  @override
  RangeEditResult replaceRange(
    String noteId,
    BlockRange range,
    String replacement,
  ) {
    if (operationError case final Object error) throw error;
    replacements.add((range, replacement));
    replacementNoteIds.add(noteId);
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  RangeEditResult replaceWholeNote(String noteId, String replacement) {
    if (operationError case final Object error) throw error;
    wholeNoteReplacements.add(replacement);
    replacementNoteIds.add(noteId);
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  RangeEditResult deleteRange(String noteId, BlockRange range) {
    if (operationError case final Object error) throw error;
    deletes.add(range);
    deleteNoteIds.add(noteId);
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  RangeEditResult deleteWholeNote(String noteId) {
    if (operationError case final Object error) throw error;
    wholeNoteDeletes.add(noteId);
    deleteNoteIds.add(noteId);
    return RangeEditResult(state: result, caret: caret);
  }

  @override
  String copyRangeAsMarkdown(String noteId, BlockRange range) {
    if (operationError case final Object error) throw error;
    copiedNoteIds.add(noteId);
    return 'core markdown';
  }

  @override
  String copyWholeNoteAsMarkdown(String noteId) {
    if (operationError case final Object error) throw error;
    wholeNoteCopiedIds.add(noteId);
    return 'core whole-note markdown';
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String source) {
    updates.add((blockPath, source));
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

AstNode _listWithTwoLeaves() => AstNode.list(
  ordered: false,
  items: [
    AstNode.listItem(content: [_paragraph('first item')]),
    AstNode.listItem(content: [_paragraph('second item')]),
  ],
);

AstNode _blockquoteWithTwoLeaves() => AstNode.blockquote(
  nodes: [_paragraph('first quote'), _paragraph('second quote')],
);

NoteState _note(List<String> blocks, {String id = 'range-note'}) => NoteState(
  ast: [for (final block in blocks) _paragraph(block)],
  metadata: id == _metadata.id
      ? _metadata
      : NoteMetadata(
          id: id,
          path: '$id.md',
          title: id,
          lastModified: 0,
          okfConformant: true,
        ),
  baseRevision: 'head',
  restoredFromDraft: false,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _RangeApi api, {
  List<AstNode>? ast,
}) async {
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(
        () => _FixedNoteController(
          ast == null
              ? _note(['first block', 'middle block', 'tail block'])
              : NoteState(
                  ast: ast,
                  metadata: _metadata,
                  baseRevision: 'head',
                  restoredFromDraft: false,
                ),
        ),
      ),
      rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Editor()),
      ),
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

Offset _caretPoint(WidgetTester tester, String probe, int utf16Offset) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(probe),
  );
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  final caret = paragraph.getOffsetForCaret(
    TextPosition(offset: utf16Offset),
    Rect.zero,
  );
  return paragraph.localToGlobal(caret + Offset(0, paragraph.size.height / 2));
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

Future<void> _selectAcrossLeaves(
  WidgetTester tester,
  String firstLeaf,
  String secondLeaf,
) async {
  final first = _box(tester, firstLeaf);
  final second = _box(tester, secondLeaf);
  final gesture = await tester.startGesture(
    first.topLeft + Offset(2 * 14 + 7, first.height / 2),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(second.topLeft + Offset(4 * 14 + 7, second.height / 2));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _selectWithinLeaf(WidgetTester tester, String text) async {
  final box = _box(tester, text);
  final gesture = await tester.startGesture(
    box.topLeft + Offset(2 * 14 + 7, box.height / 2),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(box.topLeft + Offset(6 * 14 + 7, box.height / 2));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _performMacOSSelector(WidgetTester tester, String selector) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.textInput.name,
          SystemChannels.textInput.codec.encodeMethodCall(
            MethodCall('TextInputClient.performSelectors', <dynamic>[
              -1,
              <String>[selector],
            ]),
          ),
          (_) {},
        );

/// Tests own the platform clipboard boundary so Action paste/copy never waits
/// on a desktop host clipboard implementation.
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

void main() {
  testWidgets('a multi-leaf list selection activates direct range input for '
      'type, delete, paste, and cut', (tester) async {
    final operations = <String>['type', 'delete', 'paste', 'cut'];

    for (final operation in operations) {
      final api = _RangeApi()
        ..result = _note(['$operation result'])
        ..caret = RangeEditCaret.block(
          blockPath: Uint64List.fromList(const [0]),
          sourceOffsetUtf16: BigInt.zero,
        )
        ..sources['0'] = '$operation result\n';
      await _pump(tester, api, ast: [_listWithTwoLeaves()]);
      await _selectAcrossLeaves(tester, 'first item', 'second item');

      final area = tester.element(find.byType(SelectionArea));
      switch (operation) {
        case 'type':
          tester.testTextInput.enterText('typed');
        case 'delete':
          Actions.invoke(area, const DeleteCharacterIntent(forward: true));
        case 'paste':
          _mockClipboard(tester, 'pasted');
          Actions.invoke(
            area,
            const PasteTextIntent(SelectionChangedCause.keyboard),
          );
        case 'cut':
          _mockClipboard(tester);
          Actions.invoke(
            area,
            const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          );
      }
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        api.replacements.length,
        operation == 'type' || operation == 'paste' ? 1 : 0,
        reason: operation,
      );
      expect(
        api.deletes.length,
        operation == 'delete' || operation == 'cut' ? 1 : 0,
        reason: operation,
      );
      expect(
        api.copiedNoteIds.length,
        operation == 'cut' ? 1 : 0,
        reason: operation,
      );
      expect(api.updates, isEmpty, reason: operation);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a multi-leaf blockquote selection activates direct range '
      'input while both endpoints remain in its top-level Block', (
    tester,
  ) async {
    final api = _RangeApi()
      ..result = _note(['quote result'])
      ..caret = RangeEditCaret.block(
        blockPath: Uint64List.fromList(const [0]),
        sourceOffsetUtf16: BigInt.zero,
      )
      ..sources['0'] = 'quote result\n';
    await _pump(tester, api, ast: [_blockquoteWithTwoLeaves()]);
    await _selectAcrossLeaves(tester, 'first quote', 'second quote');

    final range = tester
        .state<EditorState>(find.byType(Editor))
        .debugSelectedRange();
    expect(range?.startPath, Uint64List.fromList(const [0]));
    expect(range?.endPath, Uint64List.fromList(const [0]));

    tester.testTextInput.enterText('quoted');
    await tester.pump();
    await tester.pump();

    expect(api.replacements, hasLength(1));
    expect(api.replacements.single.$2, 'quoted');
    expect(api.deletes, isEmpty);
    expect(api.updates, isEmpty);
  });

  testWidgets('a selection within one rendered leaf does not claim range '
      'editing merely because its top-level Block is a container', (
    tester,
  ) async {
    final api = _RangeApi()
      ..result = _note(['unexpected'])
      ..caret = RangeEditCaret.phantom(insertionIndex: BigInt.zero);
    await _pump(tester, api, ast: [_listWithTwoLeaves()]);
    await _selectWithinLeaf(tester, 'first item');

    tester.testTextInput.enterText('must not replace');
    Actions.invoke(
      tester.element(find.byType(SelectionArea)),
      const DeleteCharacterIntent(forward: true),
    );
    await tester.pump();
    await tester.pump();

    expect(api.replacements, isEmpty);
    expect(api.deletes, isEmpty);
    expect(api.updates, isEmpty);
  });

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

  testWidgets('exact forward and reverse Block-boundary endpoints retain '
      'their collapsed edge in the Core range', (tester) async {
    final cases =
        <
          (
            String name,
            Offset Function(WidgetTester tester) start,
            Offset Function(WidgetTester tester) end,
            int startOffset,
            int endOffset,
          )
        >[
          (
            'forward',
            (tester) =>
                _caretPoint(tester, 'first block', 'first block'.length),
            (tester) => _caretPoint(tester, 'middle block', 3),
            'first block'.length,
            3,
          ),
          (
            'reverse',
            (tester) => _caretPoint(tester, 'middle block', 3),
            (tester) =>
                _caretPoint(tester, 'first block', 'first block'.length),
            'first block'.length,
            3,
          ),
        ];

    for (final testCase in cases) {
      final (name, start, end, startOffset, endOffset) = testCase;
      final api = _RangeApi()
        ..result = _note(['$name result'])
        ..caret = RangeEditCaret.block(
          blockPath: Uint64List.fromList(const [0]),
          sourceOffsetUtf16: BigInt.zero,
        )
        ..sources['0'] = '$name result\n';
      await _pump(tester, api);

      final gesture = await tester.startGesture(
        start(tester),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(end(tester));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final selected = tester
          .state<EditorState>(find.byType(Editor))
          .debugSelectedRange();
      expect(selected?.startPath, Uint64List.fromList(const [0]), reason: name);
      expect(selected?.endPath, Uint64List.fromList(const [1]), reason: name);

      tester.testTextInput.enterText(name);
      await tester.pump();
      await tester.pump();

      expect(api.replacements, hasLength(1), reason: name);
      final (range, replacement) = api.replacements.single;
      expect(replacement, name);
      expect(range.startPath, Uint64List.fromList(const [0]));
      expect(range.startOffset, BigInt.from(startOffset));
      expect(range.endPath, Uint64List.fromList(const [1]));
      expect(range.endOffset, BigInt.from(endOffset));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('exact forward and reverse container-leaf boundaries activate '
      'range input with their collapsed edge retained', (tester) async {
    final cases = <(String, List<AstNode>, String, String)>[
      ('list', [_listWithTwoLeaves()], 'first item', 'second item'),
      (
        'blockquote',
        [_blockquoteWithTwoLeaves()],
        'first quote',
        'second quote',
      ),
    ];

    for (final (containerName, ast, firstLeaf, secondLeaf) in cases) {
      final firstLength = firstLeaf.length;
      for (final reverse in [false, true]) {
        final api = _RangeApi()
          ..result = _note(['$containerName result'])
          ..caret = RangeEditCaret.block(
            blockPath: Uint64List.fromList(const [0]),
            sourceOffsetUtf16: BigInt.zero,
          )
          ..sources['0'] = '$containerName result\n';
        await _pump(tester, api, ast: ast);

        final start = reverse
            ? _caretPoint(tester, secondLeaf, 3)
            : _caretPoint(tester, firstLeaf, firstLength);
        final end = reverse
            ? _caretPoint(tester, firstLeaf, firstLength)
            : _caretPoint(tester, secondLeaf, 3);
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final range = tester
            .state<EditorState>(find.byType(Editor))
            .debugSelectedRange();
        expect(range?.startPath, Uint64List.fromList(const [0]));
        expect(range?.endPath, Uint64List.fromList(const [0]));

        tester.testTextInput.enterText(reverse ? 'reverse' : 'forward');
        await tester.pump();
        await tester.pump();

        expect(api.replacements, hasLength(1));
        expect(api.replacements.single.$2, reverse ? 'reverse' : 'forward');
        expect(api.deletes, isEmpty);
        expect(api.updates, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('retryable range operation failures keep the Note mounted and '
      'show a localized dismissible status', (tester) async {
    final operations = <(String, Future<void> Function(WidgetTester))>[
      (
        'replace',
        (tester) async {
          tester.testTextInput.enterText('replacement');
        },
      ),
      (
        'delete',
        (tester) async {
          Actions.invoke(
            tester.element(find.byType(SelectionArea)),
            const DeleteCharacterIntent(forward: true),
          );
        },
      ),
      (
        'copy',
        (tester) async {
          Actions.invoke(
            tester.element(find.byType(SelectionArea)),
            CopySelectionTextIntent.copy,
          );
        },
      ),
    ];

    for (final (name, run) in operations) {
      final api = _RangeApi()
        ..operationError = StateError('$name refused')
        ..result = _note(['unused'])
        ..caret = RangeEditCaret.phantom(insertionIndex: BigInt.zero);
      final container = await _pump(tester, api);
      await _selectAcrossBlocks(tester);

      await run(tester);
      await tester.pump();
      await tester.pump();

      expect(find.text('first block'), findsOneWidget, reason: name);
      expect(find.byType(SnackBar), findsOneWidget, reason: name);
      expect(
        find.textContaining('Could not complete the editor operation'),
        findsOneWidget,
        reason: name,
      );
      expect(
        find.textContaining('$name refused'),
        findsOneWidget,
        reason: name,
      );
      expect(container.read(activeNoteProvider), isNotNull, reason: name);
      expect(container.read(editorErrorProvider), isNull, reason: name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('production delete Actions send one atomic delete and adopt '
      'the Core caret', (tester) async {
    final actions = <(String, Intent)>[
      ('forward character', const DeleteCharacterIntent(forward: true)),
      ('backward character', const DeleteCharacterIntent(forward: false)),
      ('next word', const DeleteToNextWordBoundaryIntent(forward: true)),
      ('line break', const DeleteToLineBreakIntent(forward: true)),
    ];

    for (final (name, intent) in actions) {
      final api = _RangeApi()
        ..result = _note(['returned $name'])
        ..caret = RangeEditCaret.block(
          blockPath: Uint64List.fromList(const [0]),
          sourceOffsetUtf16: BigInt.from(3),
        )
        ..sources['0'] = 'returned $name\n';
      await _pump(tester, api);
      await _selectAcrossBlocks(tester);

      Actions.invoke(tester.element(find.byType(SelectionArea)), intent);
      await tester.pump();
      await tester.pump();

      expect(api.deletes, hasLength(1), reason: name);
      expect(api.deleteNoteIds, ['range-note'], reason: name);
      expect(api.replacements, isEmpty, reason: name);
      expect(api.updates, isEmpty, reason: name);
      final field = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (widget) => widget is EditableText && !widget.readOnly,
        ),
      );
      expect(field.controller.selection.baseOffset, 3, reason: name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a macOS delete selector reaches the range deletion Action', (
    tester,
  ) async {
    final api = _RangeApi()
      ..result = _note(['selector result'])
      ..caret = RangeEditCaret.block(
        blockPath: Uint64List.fromList(const [0]),
        sourceOffsetUtf16: BigInt.zero,
      )
      ..sources['0'] = 'selector result\n';
    await _pump(tester, api);
    await _selectAcrossBlocks(tester);

    await _performMacOSSelector(tester, 'deleteForward:');
    await tester.pump();
    await tester.pump();

    expect(api.deletes, hasLength(1));
    expect(api.deleteNoteIds, ['range-note']);
    expect(api.replacements, isEmpty);
    expect(api.updates, isEmpty);
  });

  testWidgets('PasteTextIntent reaches one replacement and adopts the Core '
      'caret without per-Block updates', (tester) async {
    final api = _RangeApi()
      ..result = _note(['pasted result'])
      ..caret = RangeEditCaret.block(
        blockPath: Uint64List.fromList(const [0]),
        sourceOffsetUtf16: BigInt.from(4),
      )
      ..sources['0'] = 'pasted result\n';
    await _pump(tester, api);
    await _selectAcrossBlocks(tester);
    _mockClipboard(tester, 'from clipboard');

    Actions.invoke(
      tester.element(find.byType(SelectionArea)),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.replacements, hasLength(1));
    expect(api.replacementNoteIds, ['range-note']);
    expect(api.replacements.single.$2, 'from clipboard');
    expect(api.deletes, isEmpty);
    expect(api.updates, isEmpty);
    final field = tester.widget<EditableText>(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && !widget.readOnly,
      ),
    );
    expect(field.controller.selection.baseOffset, 4);
  });

  testWidgets('CopySelectionTextIntent.copy and cut use Core Markdown; cut '
      'deletes exactly once', (tester) async {
    final api = _RangeApi()
      ..result = _note(['cut result'])
      ..caret = RangeEditCaret.block(
        blockPath: Uint64List.fromList(const [0]),
        sourceOffsetUtf16: BigInt.zero,
      )
      ..sources['0'] = 'cut result\n';
    await _pump(tester, api);
    await _selectAcrossBlocks(tester);
    final clipboard = _mockClipboard(tester);

    Actions.invoke(
      tester.element(find.byType(SelectionArea)),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();
    await tester.pump();
    expect(api.copiedNoteIds, ['range-note']);
    expect(api.deletes, isEmpty);
    expect(api.replacements, isEmpty);
    expect(api.updates, isEmpty);
    expect(clipboard.value, 'core markdown');

    Actions.invoke(
      tester.element(find.byType(SelectionArea)),
      const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.copiedNoteIds, ['range-note', 'range-note']);
    expect(api.deletes, hasLength(1));
    expect(api.deleteNoteIds, ['range-note']);
    expect(api.replacements, isEmpty);
    expect(api.updates, isEmpty);
    expect(clipboard.value, 'core markdown');
  });

  testWidgets('Select All uses the Core whole-Note boundary for terminal '
      'empty renderings across copy, delete, cut, and replacement', (
    tester,
  ) async {
    final fixtures = <(String, List<AstNode>)>[
      ('sole thematic break', [const AstNode.thematicBreak()]),
      (
        'terminal thematic break',
        [_paragraph('before the rule'), const AstNode.thematicBreak()],
      ),
      ('sole empty fenced code Block', [AstNode.codeBlock(code: '')]),
      (
        'terminal empty fenced code Block',
        [_paragraph('before the fence'), AstNode.codeBlock(code: '')],
      ),
    ];
    const operations = <String>['copy', 'delete', 'cut', 'replace'];

    for (final (fixtureName, ast) in fixtures) {
      for (final operation in operations) {
        final api = _RangeApi()
          ..result = _note(['replacement result'])
          ..caret = RangeEditCaret.block(
            blockPath: Uint64List.fromList(const [0]),
            sourceOffsetUtf16: BigInt.zero,
          )
          ..sources['0'] = 'replacement result\n';
        await _pump(tester, api, ast: ast);
        final area = tester.element(find.byType(SelectionArea));
        final clipboard = _mockClipboard(tester, 'pasted replacement');

        Actions.invoke(
          area,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        expect(
          tester.state<EditorState>(find.byType(Editor)).debugWholeNoteSelected,
          isTrue,
          reason: '$fixtureName must create an editable whole-Note target',
        );

        switch (operation) {
          case 'copy':
            Actions.invoke(area, CopySelectionTextIntent.copy);
          case 'delete':
            Actions.invoke(area, const DeleteCharacterIntent(forward: true));
          case 'cut':
            Actions.invoke(
              area,
              const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
            );
          case 'replace':
            tester.testTextInput.enterText('typed replacement');
        }
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(api.copiedNoteIds, isEmpty, reason: '$fixtureName $operation');
        expect(api.replacements, isEmpty, reason: '$fixtureName $operation');
        expect(api.deletes, isEmpty, reason: '$fixtureName $operation');
        expect(
          api.wholeNoteCopiedIds,
          operation == 'copy' || operation == 'cut' ? ['range-note'] : isEmpty,
          reason: '$fixtureName $operation',
        );
        expect(
          api.wholeNoteDeletes,
          operation == 'delete' || operation == 'cut'
              ? ['range-note']
              : isEmpty,
          reason: '$fixtureName $operation',
        );
        expect(
          api.wholeNoteReplacements,
          operation == 'replace' ? ['typed replacement'] : isEmpty,
          reason: '$fixtureName $operation',
        );
        if (operation == 'copy' || operation == 'cut') {
          expect(clipboard.value, 'core whole-note markdown');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('a provider state or Note transition immediately revokes the '
      'old proxy and whole-note selection before rebuild', (tester) async {
    final api = _RangeApi()
      ..result = _note(['unexpected'])
      ..caret = RangeEditCaret.phantom(insertionIndex: BigInt.zero);
    final container = await _pump(tester, api);
    final area = tester.element(find.byType(SelectionArea));
    await _selectAcrossBlocks(tester);
    _mockClipboard(tester, 'stale paste');

    // Select All is a second range authority. Its old marker must disappear
    // synchronously along with the live SelectionArea proxy.
    Actions.invoke(
      area,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    container.read(activeNoteProvider.notifier).state = _note([
      'first block',
      'middle block',
      'tail block',
    ], id: 'new-note');
    tester.testTextInput.enterText('stale type');
    Actions.invoke(area, const PasteTextIntent(SelectionChangedCause.keyboard));
    Actions.invoke(area, const DeleteCharacterIntent(forward: true));
    Actions.invoke(area, CopySelectionTextIntent.copy);
    await tester.pump();
    await tester.pump();

    expect(api.replacements, isEmpty);
    expect(api.deletes, isEmpty);
    expect(api.copiedNoteIds, isEmpty);
    expect(api.updates, isEmpty);
    expect(
      tester.state<EditorState>(find.byType(Editor)).debugSelectedRange(),
      isNull,
    );
    expect(container.read(activeNoteProvider)!.metadata.id, 'new-note');

    // The same identity check also rejects an external state replacement for
    // the same Note id: an old range may not edit a new provider snapshot.
    await _selectAcrossBlocks(tester);
    container.read(activeNoteProvider.notifier).state = _note([
      'first block',
      'middle block',
      'tail block',
    ], id: 'new-note');
    tester.testTextInput.enterText('stale same-id type');
    Actions.invoke(area, const DeleteCharacterIntent(forward: false));
    await tester.pump();
    await tester.pump();
    expect(api.replacements, isEmpty);
    expect(api.deletes, isEmpty);
    expect(api.updates, isEmpty);
  });
}
