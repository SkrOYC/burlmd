import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
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
/// does — `continue_block_after` inserts after the anchor, `split_block`
/// divides one Block at a source offset into two, `merge_block_with_previous`
/// concatenates onto the predecessor and removes the Block — so every
/// returned [NoteState] is a faithful "authoritative state" the UI must
/// re-derive focus from. Every call is recorded so tests can assert both
/// what reached the Core and what never did.
class _CoreFake extends RustApi {
  /// Seeds follow the documented contract (`rust_api_provider.dart`): each
  /// Block source includes its delimiters and TERMINATING NEWLINE — exactly
  /// what `getBlockSource` hands back and what `update_block` buffers.
  _CoreFake(this.blocks);

  /// The Core's working source: one raw-source string per Block.
  final List<String> blocks;

  /// Every structural call in issue order, e.g. `'continue:1:x'`,
  /// `'split:0:5'`, `'merge:2'`, `'commit'`. `update_block` is counted
  /// separately because it is the per-keystroke path, not a discrete action.
  final List<String> calls = [];

  int updateCount = 0;
  List<int>? lastUpdatePath;
  String? lastUpdateSource;
  Object? mergeFailure;
  Object? splitFailure;
  Object? continueFailure;

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
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int renderedUtf16Offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList(topLevelPath),
    caretOffset: BigInt.from(renderedUtf16Offset),
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
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> blockPath,
    String source,
  ) {
    final index = blocks.isEmpty ? 0 : blockPath.first + 1;
    calls.add('continue:$index:$source');
    final failure = continueFailure;
    if (failure != null) throw failure;
    blocks.insert(index, source);
    return StructuralEdit(
      state: state,
      blockPath: Uint64List.fromList([index]),
      caretOffset: BigInt.from(source.length),
    );
  }

  @override
  StructuralEdit splitBlock(
    String noteId,
    List<int> blockPath,
    String source,
    int offset,
  ) {
    calls.add('split:${blockPath.first}:$offset');
    final failure = splitFailure;
    if (failure != null) throw failure;
    final block = blocks[blockPath.first];
    if (source != block) {
      throw StateError('split source must be the focused raw field');
    }
    blocks[blockPath.first] = block.substring(0, offset);
    blocks.insert(blockPath.first + 1, block.substring(offset));
    return StructuralEdit(
      state: state,
      blockPath: Uint64List.fromList([blockPath.first + 1]),
      caretOffset: BigInt.zero,
    );
  }

  @override
  StructuralEdit mergeBlockWithPrevious(String noteId, List<int> blockPath) {
    calls.add('merge:${blockPath.first}');
    final failure = mergeFailure;
    if (failure != null) throw failure;
    // The Core splices out the gap between the two Blocks — the
    // predecessor's terminating newline and any blank line between them —
    // so the join is content-to-content.
    final previous = blocks[blockPath.first - 1];
    final stripped = previous.endsWith('\n')
        ? previous.substring(0, previous.length - 1)
        : previous;
    blocks[blockPath.first - 1] = stripped + blocks[blockPath.first];
    blocks.removeAt(blockPath.first);
    return StructuralEdit(
      state: state,
      blockPath: Uint64List.fromList([blockPath.first - 1]),
      caretOffset: BigInt.from(stripped.codeUnits.length),
    );
  }

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    calls.add('commit');
    return state;
  }
}

/// Reparse fixture: the buffered leaf becomes two top-level Blocks, while a
/// later source region remains unchanged. Core's returned AST is the only
/// authority the editor may use to position the continuation phantom.
class _TopLevelSplitCommitFake extends _CoreFake {
  _TopLevelSplitCommitFake() : super(['leaf\n', 'tail\n']);

  @override
  NoteState commitBlock(String noteId, List<int> blockPath) {
    calls.add('commit');
    blocks
      ..clear()
      ..addAll(['A\n', 'B\n', 'tail\n']);
    return state;
  }
}

/// Full structural-path fixture for nested List regressions. It deliberately
/// rejects a top-level substitute for a leaf address.
class _NestedListFake extends RustApi {
  final calls = <String>[];
  List<int> promotedPath = [0, 0, 0];
  final sources = <String, String>{'0/0/0': 'alpha', '0/1/0': 'beta'};

  NoteState _state(int itemCount) => NoteState(
    ast: [
      AstNode.list(
        ordered: false,
        items: [
          for (var i = 0; i < itemCount; i++)
            AstNode.listItem(
              content: [
                _paragraph(
                  i == 0
                      ? 'alpha'
                      : i == 1
                      ? 'middle'
                      : 'beta',
                ),
              ],
            ),
        ],
      ),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  NoteState get _mergedState => NoteState(
    ast: [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_paragraph('alphabeta')]),
        ],
      ),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList(promotedPath),
    caretOffset: BigInt.zero,
  );

  @override
  String getBlockSource(String noteId, List<int> path) =>
      sources[path.join('/')]!;

  @override
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> path,
    String source,
  ) {
    calls.add('continue:${path.join('/')}:$source');
    sources['0/1/0'] = source;
    sources['0/2/0'] = 'beta';
    return StructuralEdit(
      state: _state(3),
      blockPath: Uint64List.fromList([0, 1, 0]),
      caretOffset: BigInt.from(source.length),
    );
  }

  @override
  StructuralEdit mergeBlockWithPrevious(String noteId, List<int> path) {
    calls.add('merge:${path.join('/')}');
    sources['0/0/0'] = 'alphabeta';
    sources.remove('0/1/0');
    return StructuralEdit(
      state: _mergedState,
      blockPath: Uint64List.fromList([0, 0, 0]),
      caretOffset: BigInt.from('alpha'.codeUnits.length),
    );
  }

  @override
  void updateBlock(String noteId, List<int> path, String source) {
    if (path.length != 3) {
      throw StateError('container write requested at $path');
    }
    sources[path.join('/')] = source;
  }
}

/// A quoted list fixture: both continuation and merge must preserve the quote
/// container and use Core's returned nested leaf rather than a guessed path.
class _QuotedListFake extends RustApi {
  final calls = <String>[];
  List<int> promotedPath = [0, 0, 0, 0];
  final sources = <String, String>{'0/0/0/0': 'alpha', '0/0/1/0': 'beta'};

  NoteState _state(List<String> values) => NoteState(
    ast: [
      AstNode.blockquote(
        nodes: [
          AstNode.list(
            ordered: false,
            items: [
              for (final value in values)
                AstNode.listItem(content: [_paragraph(value)]),
            ],
          ),
        ],
      ),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList(promotedPath),
    caretOffset: BigInt.zero,
  );

  @override
  String getBlockSource(String noteId, List<int> path) =>
      sources[path.join('/')]!;

  @override
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> path,
    String source,
  ) {
    calls.add('continue:${path.join('/')}:$source');
    if (path.join('/') != '0/0/0/0') {
      throw StateError('quoted-list continuation must use the leaf path');
    }
    sources
      ..['0/0/1/0'] = source
      ..['0/0/2/0'] = 'beta';
    return StructuralEdit(
      state: _state(['alpha', source, 'beta']),
      blockPath: Uint64List.fromList([0, 0, 1, 0]),
      caretOffset: BigInt.from(source.length),
    );
  }

  @override
  StructuralEdit mergeBlockWithPrevious(String noteId, List<int> path) {
    calls.add('merge:${path.join('/')}');
    if (path.join('/') != '0/0/1/0') {
      throw StateError('quoted-list merge must use the second item leaf path');
    }
    sources
      ..['0/0/0/0'] = 'alphabeta'
      ..remove('0/0/1/0');
    return StructuralEdit(
      state: _state(['alphabeta']),
      blockPath: Uint64List.fromList([0, 0, 0, 0]),
      caretOffset: BigInt.from('alpha'.length),
    );
  }
}

/// Models the one deliberate stale view between [RustApi.updateBlock] and a
/// structural reparse: the editor still holds a paragraph AST while the Core
/// working source has become a List. Enter must send the retained leaf path to
/// Core, which resolves it against that live source and returns the new list
/// sibling path.
class _LiveShapeListFake extends RustApi {
  final calls = <String>[];
  var workingSource = 'plain\n';
  final sources = <String, String>{'0': 'plain\n'};

  NoteState get continuedState => NoteState(
    ast: [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_paragraph('item')]),
          AstNode.listItem(content: [_paragraph('next')]),
        ],
      ),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  NoteState get committedListState => NoteState(
    ast: [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_paragraph('item')]),
        ],
      ),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  NoteState get splitState => NoteState(
    ast: [
      AstNode.list(
        ordered: false,
        items: [
          AstNode.listItem(content: [_paragraph('alpha')]),
        ],
      ),
      _paragraph('beta'),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList(
      workingSource == '- item\n' ? [0, 0, 0] : [0],
    ),
    caretOffset: BigInt.zero,
  );

  @override
  String getBlockSource(String noteId, List<int> path) {
    final source = sources[path.join('/')];
    if (source == null) {
      throw StateError('no source at $path');
    }
    return source;
  }

  @override
  void updateBlock(String noteId, List<int> path, String source) {
    calls.add('update:${path.join('/')}:$source');
    if (path.join('/') != '0') {
      throw StateError('the stale paragraph leaf must remain the edit address');
    }
    workingSource = source;
    sources['0'] = source;
  }

  @override
  NoteState commitBlock(String noteId, List<int> path) {
    calls.add('commit:${path.join('/')}');
    if (workingSource == '- item\n') {
      sources
        ..remove('0')
        ..['0/0/0'] = 'item';
      return committedListState;
    }
    return NoteState(
      ast: [_paragraph(workingSource)],
      metadata: _CoreFake._meta,
      baseRevision: 'head',
      restoredFromDraft: false,
    );
  }

  @override
  StructuralEdit splitBlock(
    String noteId,
    List<int> path,
    String source,
    int offset,
  ) {
    calls.add('split:${path.join('/')}:$offset:$source');
    if (path.join('/') != '0' || source != '- alpha beta\n' || offset != 7) {
      throw StateError('split must retain the stale raw field coordinate');
    }
    workingSource = '- alpha\n\n beta\n';
    sources
      ..remove('0')
      ..['0/0/0'] = 'alpha'
      ..['1'] = 'beta\n';
    return StructuralEdit(
      state: splitState,
      blockPath: Uint64List.fromList([1]),
      caretOffset: BigInt.zero,
    );
  }

  @override
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> path,
    String source,
  ) {
    calls.add('continue:${path.join('/')}:$source');
    if (path.join('/') != '0/0/0' || workingSource != '- item\n') {
      throw StateError(
        'Core must receive its reparsed leaf path and live source',
      );
    }
    workingSource = '- item\n- $source\n';
    sources
      ..remove('0')
      ..['0/0/0'] = 'item'
      ..['0/1/0'] = source;
    return StructuralEdit(
      state: continuedState,
      blockPath: Uint64List.fromList([0, 1, 0]),
      caretOffset: BigInt.from(source.codeUnits.length),
    );
  }
}

/// A quote fixture whose editable leaves are distinct from its container.
/// It deliberately exposes only the generic continuation API: a list-only
/// dispatch or a container write fails before it can hide a wrong path.
class _NestedBlockquoteFake extends RustApi {
  final calls = <String>[];
  final sources = <String, String>{'0/0': '> alpha\n', '1': 'middle\n'};

  NoteState get state => NoteState(
    ast: [
      AstNode.blockquote(nodes: [_paragraph('alpha')]),
      _paragraph('middle'),
      _paragraph('beta'),
    ],
    metadata: _CoreFake._meta,
    baseRevision: 'head',
    restoredFromDraft: false,
  );

  @override
  BlockCaret resolveBlockCaret(
    String noteId,
    List<int> topLevelPath,
    int offset,
  ) => BlockCaret(
    blockPath: Uint64List.fromList([0, 0]),
    caretOffset: BigInt.zero,
  );

  @override
  String getBlockSource(String noteId, List<int> path) {
    final source = sources[path.join('/')];
    if (source == null) {
      throw StateError('container source requested at $path');
    }
    return source;
  }

  @override
  StructuralEdit continueBlockAfter(
    String noteId,
    List<int> path,
    String source,
  ) {
    if (path.join('/') != '0/0') {
      throw StateError('continuation must receive the quote leaf, got $path');
    }
    calls.add('continue:${path.join('/')}:$source');
    sources['1'] = '$source\n';
    return StructuralEdit(
      state: state,
      blockPath: Uint64List.fromList([1]),
      caretOffset: BigInt.from(source.length),
    );
  }

  @override
  void updateBlock(String noteId, List<int> path, String source) {
    if (path.join('/') == '0') {
      throw StateError('container write requested at $path');
    }
    sources[path.join('/')] = source;
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
    final api = _CoreFake(['first\n', 'second\n']);
    await pumpEditor(tester, [
      _paragraph('first'),
      _paragraph('second'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // A new empty editable Block exists and holds focus...
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, '');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    // ...but CommonMark has no empty paragraph: nothing reached the Core.
    expect(api.calls.where((c) => c.startsWith('continue')), isEmpty);
    expect(api.updateCount, 0);
    expect(api.calls.where((c) => c == 'commit'), isEmpty);
    // The adopted state is untouched — the phantom lives UI-side only.
    expect(api.blocks, ['first\n', 'second\n']);
  });

  testWidgets('the first character typed in the new empty Block goes through '
      'continue_block_after; subsequent keystrokes go through update_block against '
      'the returned path', (tester) async {
    final api = _CoreFake(['first\n']);
    await pumpEditor(tester, [_paragraph('first')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    await tester.enterText(_writableFields().first, 'x');
    await tester.pump();

    // continue_block_after carried the character itself, not an empty Block first.
    expect(api.calls.where((c) => c.startsWith('continue')), ['continue:1:x']);
    // The returned state is authoritative: the Note gained the Block.
    expect(api.blocks, ['first\n', 'x']);

    await tester.enterText(_writableFields().first, 'xy');
    await tester.pump();

    // Later keystrokes address the RETURNED path through the buffering call.
    expect(api.updateCount, 1);
    expect(api.lastUpdatePath, [1]);
    expect(api.lastUpdateSource, 'xy');
    expect(
      api.calls.where((c) => c.startsWith('continue')),
      ['continue:1:x'],
      reason: 'exactly one continue_block_after, on the first character only',
    );
    expect(_field(tester).controller.text, 'xy');
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('a refused phantom insertion keeps its text visible and retries '
      'on the next edit', (tester) async {
    final api = _CoreFake(['first\n'])
      ..continueFailure = const AppError.parseError('continuation refused');
    final container = await pumpEditor(tester, [_paragraph('first')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'x');
    await tester.pump();

    expect(_field(tester).controller.text, 'x');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(
      container.read(keystrokeWriteFailureProvider),
      isA<AppError_ParseError>(),
    );
    expect(container.read(editorErrorProvider), isNull);

    api.continueFailure = null;
    await tester.enterText(_writableFields().first, 'xy');
    await tester.pump();

    expect(api.calls.where((call) => call.startsWith('continue')), [
      'continue:1:x',
      'continue:1:xy',
    ]);
    expect(api.blocks, ['first\n', 'xy']);
    expect(_field(tester).controller.text, 'xy');
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('focus leaving the empty Block without typing continues nothing '
      'and leaves the Note unchanged', (tester) async {
    final api = _CoreFake(['first\n', 'second\n']);
    await pumpEditor(tester, [
      _paragraph('first'),
      _paragraph('second'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first\n'.length);
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
      api.calls.where((c) => c.startsWith('continue')),
      isEmpty,
      reason: 'nothing typed, so no continuation',
    );
    expect(api.blocks, [
      'first\n',
      'second\n',
    ], reason: 'the Note is byte-for-byte unchanged');
  });

  testWidgets('abandoning a phantom commits the preceding edited Block once '
      'before it can render formatted', (tester) async {
    final api = _CoreFake(['first\n', 'second\n']);
    final container = await pumpEditor(tester, [
      _paragraph('first'),
      _paragraph('second'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields().first, 'first revised\n');
    await placeCaret(tester, 'first revised\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.calls.where((call) => call == 'commit'), ['commit']);
    expect(
      blockText(container.read(activeNoteProvider)!.ast.first),
      'first revised\n',
    );

    // Blur the still-empty phantom. It owns no Block, so it cannot replay the
    // preceding commit or replace the newly adopted AST with stale state.
    await tester.tap(
      find.byKey(const ValueKey('block-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();

    expect(api.calls.where((call) => call == 'commit'), ['commit']);
    expect(
      blockText(container.read(activeNoteProvider)!.ast.first),
      'first revised\n',
    );
    expect(api.calls.where((call) => call.startsWith('continue')), isEmpty);
  });

  testWidgets('a composing first input in an empty Note stays local until '
      'composition completes, then continues once with all text', (
    tester,
  ) async {
    final api = _CoreFake([]);
    await pumpEditor(tester, [], api: api);
    final initialController = _field(tester).controller;

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        composing: TextRange(start: 0, end: 2),
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(
      api.calls,
      isEmpty,
      reason: 'a live phantom composition is UI-local',
    );
    expect(identical(_field(tester).controller, initialController), isTrue);
    expect(_field(tester).controller.text, '中文');
    expect(_field(tester).focusNode.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(api.calls, ['continue:0:中文']);
    expect(_field(tester).controller.text, '中文');
    expect(_field(tester).controller.selection.baseOffset, 2);
    expect(api.updateCount, 0);
  });

  testWidgets('a composing first input in an Enter-created phantom stays '
      'local until composition completes, then continues once', (tester) async {
    final api = _CoreFake(['first\n']);
    await pumpEditor(tester, [_paragraph('first')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'first\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    final initialController = _field(tester).controller;

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '漢字',
        composing: TextRange(start: 0, end: 2),
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(api.calls, isEmpty);
    expect(identical(_field(tester).controller, initialController), isTrue);
    expect(_field(tester).controller.text, '漢字');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '漢字',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(api.calls, ['continue:1:漢字']);
    expect(_field(tester).controller.text, '漢字');
    expect(_field(tester).controller.selection.baseOffset, 2);
    expect(api.updateCount, 0);
  });

  // -- CAP-EDIT-03: Enter mid-Block splits at the caret --------------------

  testWidgets('Enter in the middle of a Block splits it at the caret and the '
      'combined sources equal the original', (tester) async {
    final api = _CoreFake(['hello world\n']);
    await pumpEditor(tester, [_paragraph('hello world')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 5);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // The split went through the Core at the caret's source offset...
    expect(api.calls.where((c) => c.startsWith('split')), ['split:0:5']);
    // ...the returned state is authoritative...
    expect(api.blocks, ['hello', ' world\n']);
    // ...and the combined sources equal the original, terminating newline
    // included.
    expect(api.blocks.join(), 'hello world\n');

    // Focus re-derived from the returned state: second half, caret at start.
    expect(_field(tester).controller.text, ' world\n');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(_field(tester).controller.selection.baseOffset, 0);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'Enter deletes a ${reverse ? 'reversed' : 'forward'} multiline raw '
      'selection through Core before splitting at its resulting caret',
      (tester) async {
        const selected = '**remove\nthis**';
        const source = 'alpha $selected omega\n';
        final api = _CoreFake([source]);
        await pumpEditor(tester, [
          _paragraph('alpha remove this omega'),
        ], api: api);

        await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
        const start = 'alpha '.length;
        const end = start + selected.length;
        _field(tester).controller.selection = TextSelection(
          baseOffset: reverse ? end : start,
          extentOffset: reverse ? start : end,
        );
        await pressKey(tester, LogicalKeyboardKey.enter);

        expect(api.updateCount, 1);
        expect(api.lastUpdateSource, 'alpha  omega\n');
        expect(api.calls.where((call) => call.startsWith('split')), [
          'split:0:$start',
        ]);
        expect(api.blocks, ['alpha ', ' omega\n']);
        expect(
          _field(tester).controller.text,
          ' omega\n',
          reason: 'the authoritative split result replaces the raw field',
        );
        expect(
          _field(tester).controller.selection,
          const TextSelection.collapsed(offset: 0),
        );
      },
    );
  }

  testWidgets('a refused selected-Enter split keeps the original raw range '
      'visible and retries its Core replacement before splitting', (
    tester,
  ) async {
    const selected = '**remove**';
    const source = 'alpha $selected omega\n';
    final api = _CoreFake([source])
      ..splitFailure = const AppError.parseError('split refused');
    final container = await pumpEditor(tester, [
      _paragraph('alpha remove omega'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    const start = 'alpha '.length;
    _field(tester).controller.selection = const TextSelection(
      baseOffset: start,
      extentOffset: start + selected.length,
    );
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.updateCount, 1);
    expect(api.lastUpdateSource, 'alpha  omega\n');
    expect(api.calls.where((call) => call.startsWith('split')), [
      'split:0:$start',
    ]);
    expect(_field(tester).controller.text, source);
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(
      container.read(keystrokeWriteFailureProvider),
      isA<AppError_ParseError>(),
    );

    api.splitFailure = null;
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.updateCount, 2, reason: 'retry replaces the same raw range');
    expect(api.calls.where((call) => call.startsWith('split')), [
      'split:0:$start',
      'split:0:$start',
    ]);
    expect(api.blocks, ['alpha ', ' omega\n']);
    expect(_field(tester).controller.text, ' omega\n');
  });

  testWidgets('Enter classifies the live field value, not its stale promoted '
      'source', (tester) async {
    final api = _CoreFake(['a']);
    await pumpEditor(tester, [_paragraph('a')], api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields().first, 'abc');
    await placeCaret(tester, 1);
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.calls.where((call) => call.startsWith('split')), ['split:0:1']);
  });

  testWidgets('a refused Enter split retains the raw field and focus with a '
      'nonfatal notice', (tester) async {
    final api = _CoreFake(['alpha beta\n'])
      ..splitFailure = const AppError.parseError('split refused');
    final container = await pumpEditor(tester, [
      _paragraph('alpha beta'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'alpha'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.calls.where((call) => call.startsWith('split')), ['split:0:5']);
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, 'alpha beta\n');
    expect(_field(tester).focusNode.hasFocus, isTrue);
    expect(
      container.read(keystrokeWriteFailureProvider),
      isA<AppError_ParseError>(),
    );
    expect(container.read(editorErrorProvider), isNull);
  });

  // -- CAP-EDIT-03: Backspace at start merges / no-ops ---------------------

  testWidgets('Backspace at the start of a non-first Block merges it into '
      'its predecessor with the caret at the join', (tester) async {
    final api = _CoreFake(['alpha\n', 'beta\n']);
    await pumpEditor(tester, [
      _paragraph('alpha'),
      _paragraph('beta'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-1')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    expect(api.calls.where((c) => c.startsWith('merge')), ['merge:1']);
    expect(api.blocks, ['alphabeta\n']);

    // Caret sits at the join: where 'alpha' ends inside the merged Block.
    expect(_field(tester).controller.text, 'alphabeta\n');
    expect(_field(tester).controller.selection.baseOffset, 'alpha'.length);
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'a refused Backspace merge across preserved raw HTML and reference '
    'definitions keeps the focused field mounted with a nonfatal notice',
    (tester) async {
      final api =
          _CoreFake([
              '<span>preserved raw HTML</span>\n',
              '[preserved]: /reference-definition\n',
            ])
            ..mergeFailure = const AppError.parseError(
              'cannot merge preserved raw HTML with a reference definition',
            );
      final container = await pumpEditor(tester, [
        _paragraph('preserved raw HTML'),
        _paragraph('preserved'),
      ], api: api);

      await promoteByTap(tester, find.byKey(const ValueKey('block-1')));
      await placeCaret(tester, 0);
      await pressKey(tester, LogicalKeyboardKey.backspace);

      expect(api.calls.where((c) => c.startsWith('merge')), ['merge:1']);
      expect(_writableFields(), findsOneWidget);
      expect(
        _field(tester).controller.text,
        '[preserved]: /reference-definition\n',
      );
      expect(_field(tester).focusNode.hasFocus, isTrue);
      expect(
        container.read(keystrokeWriteFailureProvider),
        isA<AppError_ParseError>(),
      );
      expect(container.read(editorErrorProvider), isNull);
    },
  );

  testWidgets('Backspace at the start of the first Block changes nothing', (
    tester,
  ) async {
    final api = _CoreFake(['alpha\n']);
    await pumpEditor(tester, [_paragraph('alpha')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    // No merge reached the Core and the Note is untouched.
    expect(api.calls.where((c) => c.startsWith('merge')), isEmpty);
    expect(api.blocks, ['alpha\n']);
    expect(_field(tester).controller.text, 'alpha\n');
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
    expect(api.calls.where((c) => c.startsWith('continue')), ['continue:0:a']);

    await tester.enterText(_writableFields().first, 'alpha');
    await tester.pump();
    expect(api.lastUpdatePath, [0]);
    expect(api.lastUpdateSource, 'alpha');

    // Enter at the end starts the next empty Block (UI-side until typed).
    await placeCaret(tester, 'alpha'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    await tester.enterText(_writableFields().first, 'b');
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('continue')), [
      'continue:0:a',
      'continue:1:b',
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
    expect(api.calls.where((c) => c == 'commit'), ['commit', 'commit']);
  });

  // -- Regression (P0): Enter at end of a NON-final Block ------------------

  testWidgets('Enter at the end of a NON-final Block opens the phantom after '
      'it and typing reaches the Core without losing text', (tester) async {
    final api = _CoreFake(['one\n', 'two\n', 'three\n']);
    await pumpEditor(tester, [
      _paragraph('one'),
      _paragraph('two'),
      _paragraph('three'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'one\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // The phantom opened mid-document — between Blocks 0 and 1.
    expect(_writableFields(), findsOneWidget);
    expect(_field(tester).controller.text, '');

    await tester.enterText(_writableFields().first, 'x');
    await tester.pump();

    // The first keystroke reached Core's continuation boundary at index 1,
    // shifting the later Blocks down — nothing was swallowed.
    expect(api.calls.where((c) => c.startsWith('continue')), ['continue:1:x']);
    expect(api.blocks, ['one\n', 'x', 'two\n', 'three\n']);

    await tester.enterText(_writableFields().first, 'xy');
    await tester.pump();

    // Subsequent keystrokes flow through update_block against the returned
    // path; the text typed before is still there.
    expect(api.updateCount, 1);
    expect(api.lastUpdatePath, [1]);
    expect(api.lastUpdateSource, 'xy');
    expect(api.blocks, ['one\n', 'xy', 'two\n', 'three\n']);
    expect(_field(tester).controller.text, 'xy');
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  // -- Regression (P2): the phantom renders under its owning Block ---------

  /// The `entry-*` keys of the rendered list items in paint order — the
  /// document's visual Block/phantom sequence.
  List<String> entryOrder(WidgetTester tester) => tester
      .widgetList(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith('entry-'),
        ),
      )
      .map((widget) => (widget.key as ValueKey<String>).value)
      .toList();

  testWidgets('the phantom renders directly beneath the Block Enter was '
      'pressed in, not at the bottom of the Note', (tester) async {
    final api = _CoreFake(['one\n', 'two\n', 'three\n']);
    await pumpEditor(tester, [
      _paragraph('one'),
      _paragraph('two'),
      _paragraph('three'),
    ], api: api);

    expect(entryOrder(tester), ['entry-0', 'entry-1', 'entry-2']);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'one\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);

    // The phantom sits between Blocks 0 and 1 — where Core continuation will
    // splice it — with the untouched Blocks still below it in view order.
    expect(entryOrder(tester), [
      'entry-0',
      'entry-phantom',
      'entry-1',
      'entry-2',
    ]);
  });

  testWidgets('Enter at a nested list leaf continues the List through Core '
      'and focuses its returned leaf path', (tester) async {
    final api = _NestedListFake();
    await pumpEditor(tester, api._state(2).ast, api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'alpha'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'middle');
    await tester.pump();

    expect(api.calls, ['continue:0/0/0:middle']);
    expect(_field(tester).controller.text, 'middle');
    expect(_field(tester).controller.selection.baseOffset, 'middle'.length);
  });

  testWidgets('Enter at the end of a live-edited paragraph-to-list source '
      'uses Core’s returned list sibling path', (tester) async {
    final api = _LiveShapeListFake();
    await pumpEditor(tester, [_paragraph('plain')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields().first, '- item\n');
    await tester.pump();
    await placeCaret(tester, '- item\n'.codeUnits.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'next');
    await tester.pump();

    expect(api.calls, ['update:0:- item\n', 'commit:0', 'continue:0/0/0:next']);
    expect(api.workingSource, '- item\n- next\n');
    expect(_field(tester).controller.text, 'next');
    expect(_field(tester).controller.selection.baseOffset, 'next'.length);
  });

  testWidgets('Enter after commit reparses one leaf into top-level Blocks '
      'anchors the phantom after the entire emitted source region', (
    tester,
  ) async {
    final api = _TopLevelSplitCommitFake();
    await pumpEditor(tester, [
      _paragraph('leaf'),
      _paragraph('tail\n'),
    ], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields().first, 'A\n\nB\n');
    await tester.pump();
    await placeCaret(tester, 'A\n\nB\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'x');
    await tester.pump();

    expect(api.calls, ['commit', 'continue:2:x']);
    expect(api.blocks, ['A\n', 'B\n', 'x', 'tail\n']);
    expect(_field(tester).controller.text, 'x');
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('Enter mid-source after a paragraph became a List uses Core’s '
      'authoritative split leaf instead of predicting a stale successor', (
    tester,
  ) async {
    final api = _LiveShapeListFake();
    await pumpEditor(tester, [_paragraph('plain')], api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await tester.enterText(_writableFields().first, '- alpha beta\n');
    await tester.pump();
    await placeCaret(tester, 7);
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(api.calls, ['update:0:- alpha beta\n', 'split:0:7:- alpha beta\n']);
    expect(api.workingSource, '- alpha\n\n beta\n');
    expect(_field(tester).controller.text, 'beta\n');
    expect(_field(tester).controller.selection.baseOffset, 0);
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('Enter at a nested blockquote leaf lets Core exit the quote and '
      'focus its returned top-level leaf', (tester) async {
    final api = _NestedBlockquoteFake();
    await pumpEditor(tester, api.state.ast, api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, '> alpha\n'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'middle');
    await tester.pump();

    expect(api.calls, ['continue:0/0:middle']);
    expect(_field(tester).controller.text, 'middle\n');
    expect(_field(tester).controller.selection.baseOffset, 'middle'.length);
  });

  testWidgets('Backspace at a nested second list item calls Core with the '
      'real leaf path and focuses Core’s returned predecessor/caret', (
    tester,
  ) async {
    final api = _NestedListFake()..promotedPath = [0, 1, 0];
    await pumpEditor(tester, api._state(2).ast, api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    expect(api.calls, ['merge:0/1/0']);
    expect(_field(tester).controller.text, 'alphabeta');
    expect(_field(tester).controller.selection.baseOffset, 'alpha'.length);
  });

  testWidgets('quoted-list continuation focuses Core’s returned nested leaf', (
    tester,
  ) async {
    final api = _QuotedListFake();
    await pumpEditor(tester, api._state(['alpha', 'beta']).ast, api: api);

    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 'alpha'.length);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.enterText(_writableFields().first, 'middle');
    await tester.pump();

    expect(api.calls, ['continue:0/0/0/0:middle']);
    expect(_field(tester).controller.text, 'middle');
    expect(_field(tester).controller.selection.baseOffset, 'middle'.length);
  });

  testWidgets('quoted-list Backspace focuses Core’s merged predecessor leaf', (
    tester,
  ) async {
    final api = _QuotedListFake()..promotedPath = [0, 0, 1, 0];
    await pumpEditor(tester, api._state(['alpha', 'beta']).ast, api: api);
    await promoteByTap(tester, find.byKey(const ValueKey('block-0')));
    await placeCaret(tester, 0);
    await pressKey(tester, LogicalKeyboardKey.backspace);

    expect(api.calls, ['merge:0/0/1/0']);
    expect(_field(tester).controller.text, 'alphabeta');
    expect(_field(tester).controller.selection.baseOffset, 'alpha'.length);
  });
}
