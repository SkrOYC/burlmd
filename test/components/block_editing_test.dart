import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [NoteController] whose initial state is fixed at construction, so tests
/// can pump [Editor] against a known AST without a real `open_note` FFI call.
class _FixedNoteController extends NoteController {
  _FixedNoteController(this._initial);

  final NoteState _initial;

  @override
  NoteState? build() => _initial;
}

/// A [RustApi] standing in for the Core's structural editing surface
/// (`EDIT-F004`). It models the working source as a plain list of Block
/// sources and mutates it exactly the way the contract says each mutator
/// does — `insert_block` shifts subsequent Blocks down, `split_block`
/// divides one Block at a source offset into two, `merge_block_with_previous`
/// concatenates onto the predecessor and removes the Block — so every
/// returned [NoteState] is a faithful "authoritative state" the UI must
/// re-derive focus from. Every call is recorded so tests can assert both
/// what reached the Core and what never did.
class _CoreFake extends RustApi {
  _CoreFake(this.blocks);

  /// The Core's working source: one raw-source string per Block.
  final List<String> blocks;

  /// Every structural call in issue order, e.g. `'insert:1:x'`,
  /// `'split:0:5'`, `'merge:2'`, `'commit'`. `update_block` is counted
  /// separately because it is the per-keystroke path, not a discrete action.
  final List<String> calls = [];

  int updateCount = 0;
  List<int>? lastUpdatePath;
  String? lastUpdateSource;

  static const _meta = NoteMetadata(
    id: 'f004-note',
    path: 'f004-note.md',
    title: 'F004 note',
    lastModified: 0,
    okfConformant: true,
  );

  /// The authoritative post-operation state, rebuilt from the mutated
  /// working source like a Core reparse would.
  NoteState get state => NoteState(
    ast: [for (final block in blocks) _paragraph(block)],
    metadata: _meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  @override
  String getBlockSource(String noteId, List<int> blockPath) {
    if (blockPath.first >= blocks.length) {
      throw Exception('no block at $blockPath');
    }
    return blocks[blockPath.first];
  }

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    updateCount++;
    lastUpdatePath = blockPath;
    lastUpdateSource = newSource;
    // The contract: `update_block` substitutes the text into the Note's
    // working source (without parsing). The next reparse-producing call
    // returns a state that includes it.
    blocks[blockPath.first] = newSource;
  }

  @override
  NoteState insertBlock(String noteId, List<int> blockPath, String source) {
    calls.add('insert:${blockPath.first}:$source');
    blocks.insert(blockPath.first, source);
    return state;
  }

  @override
  NoteState splitBlock(String noteId, List<int> blockPath, int offset) {
    calls.add('split:${blockPath.first}:$offset');
    final block = blocks[blockPath.first];
    blocks[blockPath.first] = block.substring(0, offset);
    blocks.insert(blockPath.first + 1, block.substring(offset));
    return state;
  }

  @override
  NoteState mergeBlockWithPrevious(String noteId, List<int> blockPath) {
    calls.add('merge:${blockPath.first}');
    blocks[blockPath.first - 1] =
        blocks[blockPath.first - 1] + blocks[blockPath.first];
    blocks.removeAt(blockPath.first);
    return state;
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    calls.add('commit');
    return state;
  }
}

TextRun _run(String text) => TextRun(
  content: text,
  bold: false,
  italic: false,
  strikethrough: false,
  code: false,
);

AstNode _paragraph(String text) =>
    AstNode.paragraph(content: [InlineElement.text(_run(text))]);

/// Plain text of a paragraph Block in an adopted [NoteState].
String blockText(AstNode node) => switch (node) {
  AstNode_Paragraph(:final content) =>
    content
        .map(
          (e) => switch (e) {
            InlineElement_Text(:final field0) => field0.content,
            _ => throw StateError('unexpected inline element in fixture'),
          },
        )
        .join(),
  _ => throw StateError('fixture expected paragraphs only'),
};

var _pumpSeed = 0;

Future<ProviderContainer> pumpEditor(
  WidgetTester tester,
  List<AstNode> ast, {
  RustApi? api,
}) async {
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(
        () => _FixedNoteController(
          NoteState(
            ast: ast,
            metadata: const NoteMetadata(
              id: 'f004-note',
              path: 'f004-note.md',
              title: 'F004 note',
              lastModified: 0,
              okfConformant: true,
            ),
            baseRevision: 'head',
            restoredFromDraft: false,
          ),
        ),
      ),
      if (api != null) rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: Editor(key: ValueKey('editor-${_pumpSeed++}'))),
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

Finder _writableFields() => find.byWidgetPredicate(
  (widget) => widget is EditableText && !widget.readOnly,
);

EditableText _field(WidgetTester tester) =>
    tester.widget<EditableText>(_writableFields().first);

/// Moves the focused field's caret to [offset], the way a click or arrow key
/// would.
Future<void> placeCaret(WidgetTester tester, int offset) async {
  _field(tester).controller.selection = TextSelection.collapsed(offset: offset);
  await tester.pump();
}

/// Presses a hardware key against the focused field.
Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  // -- CAP-EDIT-03: Enter at end starts an uncommitted empty Block ---------

  testWidgets('Enter at the end of a Block starts a new empty Block holding '
      'focus, held as UI-side caret position rather than committed to the '
      'Core', (tester) async {
    final api = _CoreFake(['first', 'second']);
    await pumpEditor(tester, [
      _paragraph('first'),
      _paragraph('second'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // A new empty editable Block exists and holds focus...
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, '');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    // ...but CommonMark has no empty paragraph: nothing reached the Core.
    expect(api.calls.where((c) => c.startsWith('insert')), isEmpty);
    expect(api.updateCount, 0);
    expect(api.calls.where((c) => c == 'commit'), isEmpty);
    // The adopted state is untouched — the phantom lives UI-side only.
    expect(api.blocks, ['first', 'second']);
  });

  testWidgets('the first character typed in the new empty Block goes through '
      'insert_block; subsequent keystrokes go through update_block against '
      'the returned path', (tester) async {
    final api = _CoreFake(['first']);
    await pumpEditor(tester, [_paragraph('first')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    await tester.enterText(_writableFields().first, 'x');
    await tester.pump();

    // insert_block carried the character itself, not an empty Block first.
    expect(api.calls.where((c) => c.startsWith('insert')), ['insert:1:x']);
    // The returned state is authoritative: the Note gained the Block.
    expect(api.blocks, ['first', 'x']);

    await tester.enterText(_writableFields().first, 'xy');
    await tester.pump();

    // Later keystrokes address the RETURNED path through the buffering call.
    expect(api.updateCount, 1);
    expect(api.lastUpdatePath, [1]);
    expect(api.lastUpdateSource, 'xy');
    expect(
      api.calls.where((c) => c.startsWith('insert')),
      ['insert:1:x'],
      reason: 'exactly one insert_block, on the first character only',
    );
    expect(_field(tester).controller.text, 'xy');
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('focus leaving the empty Block without typing inserts nothing '
      'and leaves the Note unchanged', (tester) async {
    final api = _CoreFake(['first', 'second']);
    await pumpEditor(tester, [
      _paragraph('first'),
      _paragraph('second'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(_writableFields(), findsOneWidget);

    // Click away: the user abandoned the empty Block.
    await tester.tap(
      find.byKey(const ValueKey('block-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();

    expect(
      api.calls.where((c) => c.startsWith('insert')),
      isEmpty,
      reason: 'nothing typed, so nothing inserted',
    );
    expect(api.blocks, [
      'first',
      'second',
    ], reason: 'the Note is byte-for-byte unchanged');
  });

  // -- CAP-EDIT-03: Enter mid-Block splits at the caret --------------------

  testWidgets('Enter in the middle of a Block splits it at the caret and the '
      'combined sources equal the original', (tester) async {
    final api = _CoreFake(['hello world']);
    await pumpEditor(tester, [_paragraph('hello world')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 5);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // The split went through the Core at the caret's source offset...
    expect(api.calls.where((c) => c.startsWith('split')), ['split:0:5']);
    // ...the returned state is authoritative...
    expect(api.blocks, ['hello', ' world']);
    // ...and the combined sources equal the original.
    expect(api.blocks.join(), 'hello world');

    // Focus re-derived from the returned state: second half, caret at start.
    expect(_field(tester).controller.text, ' world');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(_field(tester).controller.selection.baseOffset, 0);
  });

  // -- CAP-EDIT-03: Backspace at start merges / no-ops ---------------------

  testWidgets('Backspace at the start of a non-first Block merges it into '
      'its predecessor with the caret at the join', (tester) async {
    final api = _CoreFake(['alpha', 'beta']);
    await pumpEditor(tester, [
      _paragraph('alpha'),
      _paragraph('beta'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-1')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    expect(api.calls.where((c) => c.startsWith('merge')), ['merge:1']);
    expect(api.blocks, ['alphabeta']);

    // Caret sits at the join: where 'alpha' ends inside the merged Block.
    expect(_field(tester).controller.text, 'alphabeta');
    expect(_field(tester).controller.selection.baseOffset, 'alpha'.length);
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('Backspace at the start of the first Block changes nothing', (
    tester,
  ) async {
    final api = _CoreFake(['alpha']);
    await pumpEditor(tester, [_paragraph('alpha')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    // No merge reached the Core and the Note is untouched.
    expect(api.calls.where((c) => c.startsWith('merge')), isEmpty);
    expect(api.blocks, ['alpha']);
    expect(_field(tester).controller.text, 'alpha');
    expect(_field(tester).controller.selection.baseOffset, 0);
  });

  // -- CAP-EDIT-03: composing a fresh Note by typing -----------------------

  testWidgets('a new empty Note: typed text and Enter produce the expected '
      'Blocks in order', (tester) async {
    final api = _CoreFake([]);
    await pumpEditor(tester, [], api: api);

    // An empty Note offers its first editable line straight away.
    expect(_writableFields(), findsOneWidget);

    await tester.enterText(_writableFields().first, 'a');
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('insert')), ['insert:0:a']);

    await tester.enterText(_writableFields().first, 'alpha');
    await tester.pump();
    expect(api.lastUpdatePath, [0]);
    expect(api.lastUpdateSource, 'alpha');

    // Enter at the end starts the next empty Block (UI-side until typed).
    await placeCaret(tester, 'alpha'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    await tester.enterText(_writableFields().first, 'b');
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('insert')), [
      'insert:0:a',
      'insert:1:b',
    ]);

    await tester.enterText(_writableFields().first, 'beta');
    await tester.pump();
    expect(api.lastUpdatePath, [1]);
    expect(api.lastUpdateSource, 'beta');

    await placeCaret(tester, 'beta'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // The Note contains the expected Blocks, in order — read from the Core's
    // working source, which every call went through. (The provider's AST
    // still holds the last reparse; no blur happened, so no reparse was due.)
    expect(api.blocks, ['alpha', 'beta']);
    // And the session ends in the same state Enter always leaves: an empty
    // Block holding focus, still uncommitted.
    expect(_field(tester).controller.text, '');
    expect(api.calls.where((c) => c == 'commit'), isEmpty);
  });
}
