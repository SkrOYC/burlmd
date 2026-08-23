import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/components/link_completion.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/index/query.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompletionApi extends RustApi {
  _CompletionApi(this.reply);

  FutureOr<List<LinkCompletion>> Function(String query) reply;
  final List<(String, int)> calls = [];

  @override
  Future<List<LinkCompletion>> linkCompletions(
    String noteId,
    String query,
    int limit,
  ) async {
    calls.add((query, limit));
    return reply(query);
  }
}

class _TrackingTapGestureRecognizer extends TapGestureRecognizer {
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

LinkCompletion _existing(String title) => LinkCompletion(
  kind: LinkCompletionKind.existing(noteId: 'notes/$title'),
  title: title,
  insertText: '[$title](</notes/$title.md>)',
);

LinkCompletion _ghost(String title) => LinkCompletion(
  kind: LinkCompletionKind.prospectiveGhost(targetId: 'notes/$title'),
  title: title,
  insertText: '[$title](</notes/$title.md>)',
);

Future<void> _pumpCompletion(
  WidgetTester tester, {
  required _CompletionApi api,
  required TextEditingController controller,
  required FocusNode focusNode,
  required GlobalKey<LinkCompletionState> key,
  required void Function(String, TextSelection) onAccepted,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Focus(
            focusNode: focusNode,
            child: LinkCompletionPopup(
              key: key,
              noteId: 'source',
              controller: controller,
              focusNode: focusNode,
              onAccepted: onAccepted,
            ),
          ),
        ),
      ),
    ),
  );
  focusNode.requestFocus();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('link completion grammar', () {
    test(
      'accepts only a collapsed caret after the last unmatched same-line trigger',
      () {
        final valid = TextEditingValue(
          text: 'before [[plan',
          selection: const TextSelection.collapsed(offset: 13),
        );
        expect(linkCompletionSnapshot(valid)?.query, 'plan');
        expect(
          linkCompletionSnapshot(
            valid.copyWith(
              selection: const TextSelection(baseOffset: 1, extentOffset: 3),
            ),
          ),
          isNull,
        );
        for (final source in ['[[plan]]', '[[one\nnext', '[[plan\nnext']) {
          expect(
            linkCompletionSnapshot(
              TextEditingValue(
                text: source,
                selection: TextSelection.collapsed(offset: source.length),
              ),
            ),
            isNull,
            reason: source,
          );
        }
      },
    );
  });

  testWidgets(
    'renders at most ten Core candidates and distinguishes a prospective ghost',
    (tester) async {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: '[[p',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final key = GlobalKey<LinkCompletionState>();
      final api = _CompletionApi(
        (_) => [
          ...List.generate(9, (index) => _existing('note $index')),
          _ghost('proposal'),
        ],
      );
      await _pumpCompletion(
        tester,
        api: api,
        controller: controller,
        focusNode: focusNode,
        key: key,
        onAccepted: (_, _) {},
      );
      expect(api.calls, [('p', 10)]);
      expect(key.currentState!.candidateCount, 10);
    },
  );

  testWidgets(
    'rejects an immutable stale response and pointer acceptance replaces exactly the trigger',
    (tester) async {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x [[plan',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final gate = Completer<List<LinkCompletion>>();
      var requests = 0;
      final api = _CompletionApi(
        (_) => requests++ == 0 ? gate.future : const [],
      );
      String? accepted;
      await _pumpCompletion(
        tester,
        api: api,
        controller: controller,
        focusNode: focusNode,
        key: GlobalKey<LinkCompletionState>(),
        onAccepted: (source, _) => accepted = source,
      );
      controller.value = const TextEditingValue(
        text: 'x [[plans',
        selection: TextSelection.collapsed(offset: 9),
      );
      gate.complete([_existing('plan')]);
      await tester.pump();
      expect(find.text('plan'), findsNothing);
      expect(accepted, isNull);

      final freshApi = _CompletionApi((_) => [_existing('plan')]);
      await _pumpCompletion(
        tester,
        api: freshApi,
        controller: controller,
        focusNode: focusNode,
        key: GlobalKey<LinkCompletionState>(),
        onAccepted: (source, _) => accepted = source,
      );
      await tester.tap(find.byKey(const ValueKey('link-completion-0')));
      await tester.pump();
      expect(accepted, 'x [plan](</notes/plan.md>)');
      expect(accepted, isNot(contains('[[')));
    },
  );

  testWidgets(
    'arrow navigation, Enter, and Escape use the same candidate interaction',
    (tester) async {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: '[[p',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final key = GlobalKey<LinkCompletionState>();
      String? accepted;
      await _pumpCompletion(
        tester,
        api: _CompletionApi((_) => [_existing('first'), _ghost('second')]),
        controller: controller,
        focusNode: focusNode,
        key: key,
        onAccepted: (source, _) => accepted = source,
      );
      expect(
        key.currentState!.handleKeyEvent(
          const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.arrowDown,
            logicalKey: LogicalKeyboardKey.arrowDown,
          ),
        ),
        isTrue,
      );
      expect(
        key.currentState!.handleKeyEvent(
          const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
          ),
        ),
        isTrue,
      );
      expect(accepted, contains('second'));
      expect(key.currentState!.isOpen, isFalse);
    },
  );

  testWidgets(
    'an OverlayPortal completion escapes its single-line editor slot and pointer accepts it',
    (tester) async {
      final node = AstNode.paragraph(content: [_plainText('[[plan')]);
      final api = _CompletionApi((_) => [_existing('plan')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('single-line-editor-slot'),
                  width: 240,
                  height: 21,
                  child: BlockEditor(
                    noteId: 'source',
                    blockPath: const [0],
                    source: '[[plan',
                    initialCaret: 6,
                    style: blockTextStyle(node),
                    focusToken: 1,
                    onFocusLost: (_) {},
                    onCommitEligibilityChanged: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final option = find.byKey(const ValueKey('link-completion-0'));
      expect(find.byType(OverlayPortal), findsOneWidget);
      expect(option, findsOneWidget);
      expect(
        tester.getRect(option).top,
        greaterThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('single-line-editor-slot')))
              .bottom,
        ),
      );

      await tester.tap(option);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '[plan](</notes/plan.md>)',
      );
    },
  );

  testWidgets(
    'a failed current completion query closes only the popup, keeps the raw '
    'field usable, and shows a localized status',
    (tester) async {
      final api = _CompletionApi(
        (query) => query == 'p'
            ? [_existing('plan')]
            : Future<List<LinkCompletion>>.error(
                StateError('derived index unavailable'),
              ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BlockEditor(
                noteId: 'source',
                blockPath: const [0],
                source: '[[p',
                initialCaret: 3,
                style: const TextStyle(fontSize: 16),
                focusToken: 1,
                onFocusLost: (_) {},
                onCommitEligibilityChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('link-completion-0')), findsOneWidget);

      final field = find.byType(EditableText);
      await tester.enterText(field, '[[pl');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('link-completion-0')), findsNothing);
      expect(
        tester
            .container(of: find.byType(BlockEditor))
            .read(editorErrorProvider),
        isNull,
      );
      expect(
        find.text(
          'Could not complete the editor operation: '
          'Bad state: derived index unavailable',
        ),
        findsOneWidget,
      );

      await tester.enterText(field, '[[plan');
      await tester.pump();
      expect(tester.widget<EditableText>(field).controller.text, '[[plan');
    },
  );

  testWidgets('a stale completion failure stays silent after a newer query '
      'has rendered', (tester) async {
    final stale = Completer<List<LinkCompletion>>();
    final fresh = Completer<List<LinkCompletion>>();
    var requests = 0;
    final api = _CompletionApi(
      (_) => requests++ == 0 ? stale.future : fresh.future,
    );
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: '[[p',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final key = GlobalKey<LinkCompletionState>();
    await _pumpCompletion(
      tester,
      api: api,
      controller: controller,
      focusNode: focusNode,
      key: key,
      onAccepted: (_, _) {},
    );

    controller.value = const TextEditingValue(
      text: '[[pl',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    fresh.complete([_existing('plan')]);
    await tester.pump();
    expect(key.currentState!.candidateCount, 1);

    stale.completeError(StateError('stale index failure'));
    await tester.pump();

    expect(key.currentState!.candidateCount, 1);
    expect(find.textContaining('stale index failure'), findsNothing);
  });

  testWidgets(
    'an Enter repeat after completion acceptance does not trigger structural Enter',
    (tester) async {
      final structuralEnters = <(String, int)>[];
      final api = _CompletionApi((_) => [_existing('plan')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BlockEditor(
                noteId: 'source',
                blockPath: const [0],
                source: '[[p',
                initialCaret: 3,
                style: const TextStyle(fontSize: 16),
                focusToken: 1,
                onFocusLost: (_) {},
                onCommitEligibilityChanged: (_, _) {},
                onEnter: (source, caret) =>
                    structuralEnters.add((source, caret)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('link-completion-0')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(structuralEnters, isEmpty);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '[plan](</notes/plan.md>)',
      );
    },
  );

  testWidgets(
    'internal Links preserve nested styling, have ordered keyboard stops, and do not steal Block Enter',
    (tester) async {
      final calls = <String>[];
      final promotions = <List<int>>[];
      final node = AstNode.paragraph(
        content: [
          _plainText('Before '),
          InlineElement.link(
            targetId: 'projects/plan',
            exists: false,
            content: [
              InlineElement.text(
                const TextRun(
                  content: 'Bold italic',
                  bold: true,
                  italic: true,
                  strikethrough: false,
                  code: false,
                ),
              ),
            ],
          ),
          _plainText(' then '),
          InlineElement.link(
            targetId: 'projects/second',
            exists: true,
            content: [
              InlineElement.text(
                const TextRun(
                  content: 'code strike',
                  bold: false,
                  italic: false,
                  strikethrough: true,
                  code: true,
                ),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BlockView(
              node: node,
              blockPath: const [0],
              onFocusRequested: (path, _) => promotions.add(path),
              onLinkActivated: calls.add,
            ),
          ),
        ),
      );
      expect(find.byType(RichText), findsOneWidget);

      final outer =
          tester.widget<RichText>(find.byType(RichText)).text as TextSpan;
      final root = outer.children!.single as TextSpan;
      final firstLink = root.children![1] as TextSpan;
      final firstRun = firstLink.children!.single as TextSpan;
      final secondLink = root.children![3] as TextSpan;
      final secondRun = secondLink.children!.single as TextSpan;
      expect(firstRun.style!.fontWeight, FontWeight.bold);
      expect(firstRun.style!.fontStyle, FontStyle.italic);
      expect(secondRun.style!.fontFamily, 'monospace');
      expect(secondRun.style!.decoration, TextDecoration.lineThrough);
      expect(root.toPlainText(), 'Before Bold italic then code strike');

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Open missing linked note Bold italic'),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel('Open linked note code strike'),
        findsWidgets,
      );
      semantics.dispose();

      // Block focus is the first stop. Its Enter remains the structural
      // promotion command even when the Block contains Links.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(promotions, [
        const [0],
      ]);
      expect(calls, isEmpty);

      // Subsequent ordered stops are individual Links, not a synthetic
      // first-Link action. Their keyboard and pointer paths converge.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, ['projects/plan', 'projects/second']);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      final secondStart = 'Before Bold italic then '.length;
      final secondLinkBox = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: secondStart,
              extentOffset: secondStart + 'code strike'.length,
            ),
          )
          .first
          .toRect();
      await tester.tapAt(paragraph.localToGlobal(secondLinkBox.center));
      await tester.pump();
      expect(promotions, [
        const [0],
      ]);
      expect(calls, ['projects/plan', 'projects/second', 'projects/second']);
    },
  );

  testWidgets('renderBlock keeps multi-item list sibling markers aligned', (
    tester,
  ) async {
    AstNode list(bool ordered, List<AstNode> items) =>
        AstNode.list(ordered: ordered, items: items);
    AstNode item(String text, {bool? checked}) =>
        AstNode.listItem(checked: checked, content: [_plainParagraph(text)]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              renderBlock(list(false, [item('alpha'), item('beta')])),
              renderBlock(list(true, [item('one'), item('two')])),
              renderBlock(
                list(false, [
                  item('unchecked', checked: false),
                  item('checked', checked: true),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    _expectAlignedMarkerX(tester, find.text('•'), 2);
    final orderedXs = [
      tester.getTopLeft(find.text('1.')).dx,
      tester.getTopLeft(find.text('2.')).dx,
    ];
    expect(orderedXs.last, orderedXs.first);
    _expectAlignedMarkerX(tester, find.byType(Checkbox), 2);
  });

  testWidgets('BlockView prunes obsolete link recognizers after an update', (
    tester,
  ) async {
    final calls = <String>[];
    final created = <_TrackingTapGestureRecognizer>[];
    AstNode links(String first, String second) => AstNode.paragraph(
      content: [
        InlineElement.link(
          targetId: first,
          exists: true,
          content: [_plainText(first)],
        ),
        _plainText(' and '),
        InlineElement.link(
          targetId: second,
          exists: true,
          content: [_plainText(second)],
        ),
      ],
    );
    Widget build(AstNode node) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlockView(
          key: const ValueKey('recognizer-lifecycle'),
          node: node,
          blockPath: const [0],
          onFocusRequested: (_, _) {},
          onLinkActivated: calls.add,
          recognizerFactory: () {
            final recognizer = _TrackingTapGestureRecognizer();
            created.add(recognizer);
            return recognizer;
          },
        ),
      ),
    );

    await tester.pumpWidget(build(links('obsolete', 'retained')));
    expect(created, hasLength(2));
    final obsolete = created[0];
    final retained = created[1];

    await tester.pumpWidget(build(links('retained', 'new')));

    expect(obsolete.disposed, isTrue);
    expect(retained.disposed, isFalse);
    expect(created, hasLength(3));
    expect(_linkRecognizers(tester), contains(same(retained)));
    expect(_linkRecognizers(tester), contains(same(created[2])));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final retainedBox = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: 'retained'.length),
        )
        .single
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(retainedBox.center));
    await tester.pump();
    expect(calls, ['retained']);
  });
}

InlineElement _plainText(String content) => InlineElement.text(
  TextRun(
    content: content,
    bold: false,
    italic: false,
    strikethrough: false,
    code: false,
  ),
);

AstNode _plainParagraph(String content) =>
    AstNode.paragraph(content: [_plainText(content)]);

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

List<TapGestureRecognizer> _linkRecognizers(WidgetTester tester) {
  final recognizers = <TapGestureRecognizer>[];
  void visit(InlineSpan span) {
    if (span case TextSpan(:final recognizer, :final children)) {
      if (recognizer case TapGestureRecognizer()) recognizers.add(recognizer);
      for (final child in children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  final root = tester.widget<RichText>(find.byType(RichText)).text;
  visit(root);
  return recognizers;
}
