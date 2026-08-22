import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/src/screens/workspace.dart';
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

/// A [RustApi] whose `updateBlock` never touches the real FFI. `update_block`
/// is the per-keystroke call (ADR-007 decision 4): it buffers raw source
/// text into the Note's working source and writes the draft row, returning
/// nothing and reparsing nothing. This fake is therefore a spy rather than a
/// stand-in that echoes a reparsed state back — recording the arguments it
/// was called with is enough to prove the Dart-side round trip (keystroke ->
/// `RustApi.updateBlock`) fires with the right Block path and raw text,
/// without needing the compiled Rust dylib loaded in a widget test.
class _FakeRustApi extends RustApi {
  _FakeRustApi();

  String? lastNoteId;
  List<int>? lastBlockPath;
  String? lastSource;

  @override
  void updateBlock(String noteId, List<int> blockPath, String source) {
    lastNoteId = noteId;
    lastBlockPath = blockPath;
    lastSource = source;
  }
}

/// A [RustApi] standing in for the Core at the workspace-shell level:
/// serves a fixed tree, records `open_note`/`close_note` calls in order so
/// the switch criterion ("closed through the Core **before** the new one
/// opens") can be asserted, and can be told to fail opens to exercise the
/// error surface. Everything else falls back to no-op behaviour.
class _ShellRustApi extends RustApi {
  _ShellRustApi(this.tree, {this.failOpenFor = const {}});

  final List<TreeNode> tree;

  /// Concept ids whose `openNote` throws — the "Core returns an error"
  /// branch of the Gherkin.
  final Set<String> failOpenFor;

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
    if (failOpenFor.contains(noteId)) throw Exception('core exploded');
    return _stateFor(noteId);
  }

  @override
  Future<void> closeNote(String noteId) async {
    calls.add('close:$noteId');
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

  testWidgets(
    'a multi-run paragraph stays read-only and keeps each run\'s distinct '
    'styling, instead of collapsing to one TextField style',
    (tester) async {
      final ast = [
        AstNode.paragraph(
          content: [
            InlineElement.text(
              const TextRun(
                content: 'before ',
                bold: false,
                italic: false,
                strikethrough: false,
                code: false,
              ),
            ),
            InlineElement.text(
              const TextRun(
                content: 'bold',
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

      // A single TextField can only carry one uniform style, so a multi-run
      // paragraph must render read-only instead of silently flattening to
      // the first run's style and dropping the rest (the bug this test
      // guards: caught via an actual `flutter run`, not a prior test, since
      // every other test here only ever builds single-run paragraphs).
      expect(find.byType(TextField), findsNothing);

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final wrapperSpan = richText.text as TextSpan;
      final paragraphSpan = wrapperSpan.children!.first as TextSpan;
      final firstRun = paragraphSpan.children![0] as TextSpan;
      final secondRun = paragraphSpan.children![1] as TextSpan;

      expect(firstRun.text, 'before ');
      expect(firstRun.style?.fontWeight, isNull);
      expect(secondRun.text, 'bold');
      expect(secondRun.style?.fontWeight, FontWeight.bold);
    },
  );

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

  testWidgets(
    'typing in a paragraph calls update_block with the raw source text '
    'within one frame, and does not itself reparse the note',
    (tester) async {
      final fakeApi = _FakeRustApi();
      final container = ProviderContainer(
        overrides: [
          activeNoteProvider.overrideWith(
            () =>
                _FixedNoteController(_testNoteState([_paragraphOf('before')])),
          ),
          rustApiProvider.overrideWithValue(fakeApi),
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

      // `update_block` (ADR-007 decision 4) is the per-keystroke call: it
      // takes the Block's raw source text, not a reconstructed AstNode, and
      // this is what proves the field's keystroke reaches it with the right
      // arguments.
      expect(fakeApi.lastNoteId, _testMetadata.id);
      expect(fakeApi.lastBlockPath, [0]);
      expect(fakeApi.lastSource, 'after');

      // The field itself already shows the typed text via its own
      // TextEditingController — that is what the user sees.
      expect(find.text('after'), findsOneWidget);

      // `update_block` returns nothing and performs no parse (that is
      // `commit_block`'s job, on blur — EDIT-F002 territory, not wired up
      // here), so the provider's own note state is left exactly as it was.
      final updated = container.read(activeNoteProvider);
      final paragraph = updated!.ast.single as AstNode_Paragraph;
      final leaf = paragraph.content.single as InlineElement_Text;
      expect(leaf.field0.content, 'before');
    },
  );

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
    expect(find.byType(TextField), findsNothing);
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
