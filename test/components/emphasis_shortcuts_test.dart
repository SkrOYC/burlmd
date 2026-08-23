import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedNoteController extends NoteController {
  _FixedNoteController(this._initial);

  final NoteState _initial;

  @override
  NoteState? build() => _initial;
}

class _UpdateSpyApi extends RustApi {
  int updateCount = 0;
  String? source;
  String? workingSource;

  @override
  void updateBlock(String noteId, List<int> blockPath, String newSource) {
    updateCount++;
    source = newSource;
    workingSource = newSource;
  }
}

NoteState _note(String text) => NoteState(
  ast: [
    AstNode.paragraph(
      content: [
        InlineElement.text(
          TextRun(
            content: text,
            bold: false,
            italic: false,
            strikethrough: false,
            code: false,
          ),
        ),
      ],
    ),
  ],
  metadata: const NoteMetadata(
    id: 'emphasis-note',
    path: 'emphasis-note.md',
    title: 'Emphasis note',
    lastModified: 0,
    okfConformant: true,
  ),
  baseRevision: 'head',
  restoredFromDraft: false,
);

Future<_UpdateSpyApi> _pumpBlockEditor(
  WidgetTester tester, {
  required String source,
  bool phantom = false,
  void Function(String source, int caret)? onEnter,
  VoidCallback? onBackspaceAtStart,
}) async {
  final api = _UpdateSpyApi();
  final container = ProviderContainer(
    overrides: [
      activeNoteProvider.overrideWith(
        () => _FixedNoteController(_note(source)),
      ),
      rustApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: BlockEditor(
            noteId: 'emphasis-note',
            blockPath: const [0],
            source: source,
            initialCaret: 0,
            style: const TextStyle(fontSize: 16),
            focusToken: 1,
            onFocusLost: (_) {},
            onCommitEligibilityChanged: (_, _) {},
            phantom: phantom,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return api;
}

EditableText _field(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText));

TextEditingValue _value(String text, int base, int extent) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: base, extentOffset: extent),
);

Future<void> _primaryShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool repeat = false,
}) async {
  final primary = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  if (repeat) await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(primary);
  await tester.pump();
}

void main() {
  group('applyInlineEmphasis', () {
    for (final (name, delimiter) in const [
      ('bold', '**'),
      ('italic', '*'),
      ('inline code', '`'),
      ('strikethrough', '~~'),
    ]) {
      test('$name wraps and unwraps forward and reversed selections', () {
        final wrapped = applyInlineEmphasis(
          _value('before word after', 7, 11),
          delimiter: delimiter,
        );
        expect(
          wrapped.text,
          'before $delimiter'
          'word'
          '$delimiter after',
        );
        expect(
          wrapped.selection,
          TextSelection(
            baseOffset: 7 + delimiter.length,
            extentOffset: 11 + delimiter.length,
          ),
        );

        final unwrapped = applyInlineEmphasis(wrapped, delimiter: delimiter);
        expect(unwrapped.text, 'before word after');
        expect(
          unwrapped.selection,
          const TextSelection(baseOffset: 7, extentOffset: 11),
        );

        final reverseWrapped = applyInlineEmphasis(
          _value('before word after', 11, 7),
          delimiter: delimiter,
        );
        expect(reverseWrapped.text, wrapped.text);
        expect(
          reverseWrapped.selection,
          TextSelection(
            baseOffset: 11 + delimiter.length,
            extentOffset: 7 + delimiter.length,
          ),
        );

        final reverseUnwrapped = applyInlineEmphasis(
          reverseWrapped,
          delimiter: delimiter,
        );
        expect(reverseUnwrapped.text, 'before word after');
        expect(
          reverseUnwrapped.selection,
          const TextSelection(baseOffset: 11, extentOffset: 7),
        );
      });

      test('$name unwraps a selection of the entire delimited run', () {
        final source =
            '$delimiter'
            'word'
            '$delimiter';
        final unwrapped = applyInlineEmphasis(
          _value(source, source.length, 0),
          delimiter: delimiter,
        );
        expect(unwrapped.text, 'word');
        expect(
          unwrapped.selection,
          const TextSelection(baseOffset: 4, extentOffset: 0),
        );
      });

      test('$name inserts a paired delimiter around a collapsed caret', () {
        final inserted = applyInlineEmphasis(
          _value('word', 2, 2),
          delimiter: delimiter,
        );
        expect(
          inserted.text,
          'wo$delimiter$delimiter'
          'rd',
        );
        expect(
          inserted.selection,
          TextSelection.collapsed(offset: 2 + delimiter.length),
        );
      });
    }

    test('italic composes with strong runs instead of unwrapping one star', () {
      final composed = applyInlineEmphasis(
        _value('**word**', 2, 6),
        delimiter: '*',
      );

      expect(composed.text, '***word***');
      expect(
        composed.selection,
        const TextSelection(baseOffset: 3, extentOffset: 7),
      );

      final unwrapped = applyInlineEmphasis(composed, delimiter: '*');
      expect(unwrapped.text, '**word**');
      expect(
        unwrapped.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );

      final reversed = applyInlineEmphasis(
        _value('**word**', 6, 2),
        delimiter: '*',
      );
      expect(reversed.text, '***word***');
      expect(
        reversed.selection,
        const TextSelection(baseOffset: 7, extentOffset: 3),
      );
    });

    group('inline code follows CommonMark code-span delimiters', () {
      test('chooses a delimiter longer than every selected backtick run', () {
        final singleRun = applyInlineEmphasis(
          _value('a`b', 0, 3),
          delimiter: '`',
        );
        expect(singleRun.text, '``a`b``');
        expect(
          singleRun.selection,
          const TextSelection(baseOffset: 2, extentOffset: 5),
        );

        final multipleRun = applyInlineEmphasis(
          _value('a``b', 0, 4),
          delimiter: '`',
        );
        expect(multipleRun.text, '```a``b```');
        expect(
          multipleRun.selection,
          const TextSelection(baseOffset: 3, extentOffset: 7),
        );
      });

      test(
        'protects edge backticks and spaces from code-span normalization',
        () {
          // CommonMark strips exactly one space from both ends of a non-space
          // code span. The added space here is therefore syntax, not content.
          final leadingBacktick = applyInlineEmphasis(
            _value('`edge', 0, 5),
            delimiter: '`',
          );
          expect(leadingBacktick.text, '`` `edge ``');
          expect(
            leadingBacktick.selection,
            const TextSelection(baseOffset: 3, extentOffset: 8),
          );

          final trailingBacktick = applyInlineEmphasis(
            _value('edge`', 0, 5),
            delimiter: '`',
          );
          expect(trailingBacktick.text, '`` edge` ``');
          expect(
            trailingBacktick.selection,
            const TextSelection(baseOffset: 3, extentOffset: 8),
          );

          final edgeSpaces = applyInlineEmphasis(
            _value(' word ', 0, 6),
            delimiter: '`',
          );
          expect(edgeSpaces.text, '`  word  `');
          expect(
            edgeSpaces.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );

          // The CommonMark all-spaces exception preserves those spaces, so no
          // extra padding is required or correct.
          final allSpaces = applyInlineEmphasis(
            _value('   ', 0, 3),
            delimiter: '`',
          );
          expect(allSpaces.text, '`   `');
          expect(
            allSpaces.selection,
            const TextSelection(baseOffset: 1, extentOffset: 4),
          );
        },
      );

      test(
        'unwraps valid multi-backtick spans and their protecting spaces',
        () {
          final wrapped = applyInlineEmphasis(
            _value('``edge`', 0, 7),
            delimiter: '`',
          );
          final unwrapped = applyInlineEmphasis(wrapped, delimiter: '`');
          expect(unwrapped.text, '``edge`');
          expect(
            unwrapped.selection,
            const TextSelection(baseOffset: 0, extentOffset: 7),
          );

          final fullRun = applyInlineEmphasis(
            _value('`` `thing` ``', 13, 0),
            delimiter: '`',
          );
          expect(fullRun.text, '`thing`');
          expect(
            fullRun.selection,
            const TextSelection(baseOffset: 7, extentOffset: 0),
          );
        },
      );

      test('preserves UTF-16 offsets and keeps the empty-caret template', () {
        final wrapped = applyInlineEmphasis(
          _value('a🙂`b', 1, 4),
          delimiter: '`',
        );
        expect(wrapped.text, 'a`` 🙂` ``b');
        expect(
          wrapped.selection,
          const TextSelection(baseOffset: 4, extentOffset: 7),
        );

        final empty = applyInlineEmphasis(_value('word', 2, 2), delimiter: '`');
        expect(empty.text, 'wo``rd');
        expect(empty.selection, const TextSelection.collapsed(offset: 3));
      });

      test(
        'leaves multiline source untouched because CommonMark normalizes it',
        () {
          final original = _value('first\nsecond', 0, 12);
          expect(applyInlineEmphasis(original, delimiter: '`'), original);
        },
      );
    });
  });

  testWidgets(
    'Control shortcuts buffer exactly one raw-source update and keep focus',
    (tester) async {
      final api = await _pumpBlockEditor(tester, source: 'word');
      _field(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await _primaryShortcut(tester, LogicalKeyboardKey.keyB);

      expect(_field(tester).controller.text, '**word**');
      expect(
        _field(tester).controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(_field(tester).focusNode.hasFocus, isTrue);
      expect(api.updateCount, 1);
      expect(api.source, '**word**');
    },
  );

  testWidgets('italic shortcut composes with bold and toggles back cleanly', (
    tester,
  ) async {
    final api = await _pumpBlockEditor(tester, source: '**word**');
    _field(tester).controller.selection = const TextSelection(
      baseOffset: 2,
      extentOffset: 6,
    );

    await _primaryShortcut(tester, LogicalKeyboardKey.keyI);
    expect(_field(tester).controller.text, '***word***');
    expect(
      _field(tester).controller.selection,
      const TextSelection(baseOffset: 3, extentOffset: 7),
    );
    expect(api.updateCount, 1);

    await _primaryShortcut(tester, LogicalKeyboardKey.keyI);
    expect(_field(tester).controller.text, '**word**');
    expect(
      _field(tester).controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 6),
    );
    expect(api.updateCount, 2);
  });

  testWidgets('platform Meta is primary on macOS and Control is not', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final api = await _pumpBlockEditor(tester, source: 'word');
      _field(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(_field(tester).controller.text, 'word');

      await _primaryShortcut(tester, LogicalKeyboardKey.keyI);
      expect(_field(tester).controller.text, '*word*');
      expect(api.updateCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('live IME composition leaves structural Enter and Backspace to '
      'EditableText, including an empty phantom', (tester) async {
    var realEnters = 0;
    var realBackspaces = 0;
    await _pumpBlockEditor(
      tester,
      source: 'word',
      onEnter: (_, _) => realEnters++,
      onBackspaceAtStart: () => realBackspaces++,
    );

    // Marked text with its caret at the start is exactly the state that
    // would otherwise look like a structural Backspace-at-start.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'word',
        composing: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(realEnters, 0);
    expect(realBackspaces, 0);

    var phantomEnters = 0;
    var phantomBackspaces = 0;
    await _pumpBlockEditor(
      tester,
      source: '',
      phantom: true,
      onEnter: (_, _) => phantomEnters++,
      onBackspaceAtStart: () => phantomBackspaces++,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中',
        composing: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(phantomEnters, 0);
    expect(phantomBackspaces, 0);
  });

  testWidgets('Shift is required only for strikethrough and Alt is ignored', (
    tester,
  ) async {
    final api = await _pumpBlockEditor(tester, source: 'word');
    _field(tester).controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );

    await _primaryShortcut(tester, LogicalKeyboardKey.keyX, shift: true);
    expect(_field(tester).controller.text, '~~word~~');

    _field(tester).controller.value = _value('word', 0, 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_field(tester).controller.text, 'word');
    expect(api.updateCount, 1);
  });

  testWidgets('a live composing range is a complete shortcut no-op', (
    tester,
  ) async {
    final api = await _pumpBlockEditor(tester, source: 'word');
    final composing = TextEditingValue(
      text: 'word',
      selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      composing: const TextRange(start: 0, end: 4),
    );
    _field(tester).controller.value = composing;

    await _primaryShortcut(tester, LogicalKeyboardKey.keyE);

    expect(_field(tester).controller.value, composing);
    expect(api.updateCount, 0);
    expect(_field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('a phantom after its predecessor consumes emphasis without '
      'materializing or buffering it', (tester) async {
    final api = _UpdateSpyApi();
    var phantomInsertions = 0;
    final container = ProviderContainer(
      overrides: [
        activeNoteProvider.overrideWith(
          () => _FixedNoteController(_note('predecessor')),
        ),
        rustApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BlockEditor(
              noteId: 'emphasis-note',
              // This is the phantom positioned after the real predecessor at
              // index zero; it is not an addressable Core Block.
              blockPath: const [1],
              source: '',
              initialCaret: 0,
              style: const TextStyle(fontSize: 16),
              focusToken: 1,
              phantom: true,
              onPhantomInsert: (_) {
                phantomInsertions++;
                return true;
              },
              onFocusLost: (_) {},
              onCommitEligibilityChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = _field(tester).controller.value;

    await _primaryShortcut(tester, LogicalKeyboardKey.keyB);

    expect(_field(tester).controller.value, before);
    expect(phantomInsertions, 0);
    expect(api.updateCount, 0);
    expect(api.workingSource, isNull);
  });

  testWidgets('an overlapping resync conflict consumes emphasis without '
      'changing either branch or its surfaced error', (tester) async {
    final api = _UpdateSpyApi()..workingSource = 'base';
    final revisions = ValueNotifier<(String, int)>(('base', 0));
    addTearDown(revisions.dispose);
    final container = ProviderContainer(
      overrides: [
        activeNoteProvider.overrideWith(
          () => _FixedNoteController(_note('base')),
        ),
        rustApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<(String, int)>(
              valueListenable: revisions,
              builder: (context, revision, child) => BlockEditor(
                noteId: 'emphasis-note',
                blockPath: const [0],
                source: revision.$1,
                initialCaret: 0,
                resyncToken: revision.$2,
                style: const TextStyle(fontSize: 16),
                focusToken: 1,
                onFocusLost: (_) {},
                onCommitEligibilityChanged: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        composing: TextRange(start: 4, end: 5),
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    // This is the same-position external insertion that cannot be ordered
    // against the composing input, producing BlockEditor's real conflict.
    api.workingSource = 'base!';
    revisions.value = ('base!', 1);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base中',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    final before = _field(tester).controller.value;
    final error = container.read(keystrokeWriteFailureProvider);
    final writesAtConflict = api.updateCount;
    expect(error, isA<StateError>());

    await _primaryShortcut(tester, LogicalKeyboardKey.keyB);

    expect(_field(tester).controller.value, before);
    expect(api.updateCount, writesAtConflict);
    expect(api.workingSource, 'base!');
    expect(container.read(keystrokeWriteFailureProvider), same(error));
  });

  testWidgets('a repeated shortcut does not unwrap its initial edit', (
    tester,
  ) async {
    final api = await _pumpBlockEditor(tester, source: 'word');
    _field(tester).controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );

    await _primaryShortcut(tester, LogicalKeyboardKey.keyB, repeat: true);

    expect(_field(tester).controller.text, '**word**');
    expect(api.updateCount, 1);
  });
}
