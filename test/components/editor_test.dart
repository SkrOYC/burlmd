import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/api/ffi_api.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
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

/// A [RustApi] whose `updateBlock` never touches the real FFI: it just
/// echoes the edited node back as a single-element AST, which is enough to
/// prove the Dart-side round trip (keystroke -> provider update) is
/// synchronous, without needing the compiled Rust dylib loaded in a widget
/// test.
class _FakeRustApi extends RustApi {
  const _FakeRustApi();

  @override
  NoteState updateBlock(String noteId, List<int> blockPath, AstNode newNode) =>
      NoteState(ast: [newNode], metadata: _testMetadata, baseRevision: 'head');
}

const _testMetadata = NoteMetadata(
  id: 'test-note',
  workspaceId: 'ws',
  path: 'test-note.md',
  title: 'Test Note',
  lastModified: 0,
);

NoteState _testNoteState(List<AstNode> ast) =>
    NoteState(ast: ast, metadata: _testMetadata, baseRevision: 'head');

Future<void> pumpEditor(WidgetTester tester, List<AstNode> ast) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeNoteProvider.overrideWith(
            () => _FixedNoteController(_testNoteState(ast)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: Editor())),
      ),
    );

AstNode _paragraphOf(String text) => AstNode.paragraph(
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
);

void main() {
  testWidgets('renders a bold TextRun as bold text', (tester) async {
    final ast = [
      AstNode.paragraph(
        content: [
          InlineElement.text(
            const TextRun(
              content: 'hello',
              bold: true,
              italic: false,
              strikethrough: false,
              code: false,
            ),
          ),
        ],
      ),
    ];

    await pumpEditor(tester, ast);

    // Paragraphs render as an editable TextField (UIDB-B007), so the bold
    // run's own styling is visible via the field's underlying EditableText
    // rather than a plain RichText painted directly by Editor.
    final editableText = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(editableText.controller.text, 'hello');
    expect(editableText.style.fontWeight, FontWeight.bold);
  });

  testWidgets('a non-bold TextRun inside a Heading still inherits bold', (
    tester,
  ) async {
    final ast = [
      AstNode.heading(
        level: 1,
        content: [
          InlineElement.text(
            const TextRun(
              content: 'Title',
              bold: false,
              italic: false,
              strikethrough: false,
              code: false,
            ),
          ),
        ],
      ),
    ];

    await pumpEditor(tester, ast);

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    // richText.text is the wrapper Text.rich itself creates, carrying the
    // `style:` we passed to Text.rich (the Heading's bold). Our own heading-
    // content span sits one level down, and the leaf inline span another
    // level down still.
    final wrapperSpan = richText.text as TextSpan;
    final headingContentSpan = wrapperSpan.children!.first as TextSpan;
    final leafSpan = headingContentSpan.children!.first as TextSpan;

    expect(
      wrapperSpan.style?.fontWeight,
      FontWeight.bold,
      reason: 'the Heading itself declares bold styling',
    );
    expect(
      leafSpan.style?.fontWeight,
      isNull,
      reason:
          'a non-bold leaf run must leave fontWeight unset so it inherits '
          'the ancestor Heading style, rather than forcing FontWeight.normal '
          'and overriding it',
    );
  });

  testWidgets('an ordered list numbers its items instead of bulleting them', (
    tester,
  ) async {
    AstNode item(String text) =>
        AstNode.listItem(content: [_paragraphOf(text)]);
    final ast = [
      AstNode.list(ordered: true, items: [item('first'), item('second')]),
    ];

    await pumpEditor(tester, ast);

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('•'), findsNothing);
  });

  testWidgets('typing in a paragraph updates the note state within one frame', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        activeNoteProvider.overrideWith(
          () => _FixedNoteController(_testNoteState([_paragraphOf('before')])),
        ),
        rustApiProvider.overrideWithValue(const _FakeRustApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: Editor())),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'after');
    await tester.pump(); // exactly one frame — no extra async round trip

    final updated = container.read(activeNoteProvider);
    final paragraph = updated!.ast.single as AstNode_Paragraph;
    final leaf = paragraph.content.single as InlineElement_Text;
    expect(leaf.field0.content, 'after');
  });

  testWidgets(
    'swapping to a different note resyncs an untouched, reused field',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          activeNoteProvider.overrideWith(
            () => _FixedNoteController(_testNoteState([_paragraphOf('first')])),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Editor())),
        ),
      );
      expect(find.text('first'), findsOneWidget);

      // Swap in a different note's content without the user having typed
      // anything into the still-mounted field at this same list index.
      container.read(activeNoteProvider.notifier).state = _testNoteState([
        _paragraphOf('second'),
      ]);
      await tester.pump();

      expect(
        find.text('second'),
        findsOneWidget,
        reason:
            'the reused field must resync to the externally-swapped note '
            'content instead of keeping the previous note\'s stale text',
      );
      expect(find.text('first'), findsNothing);
    },
  );
}
