import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/components/link_completion.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/index/query.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
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
    'an internal Link is distinct and pointer/keyboard activation share its callback',
    (tester) async {
      final calls = <String>[];
      final node = AstNode.paragraph(
        content: [
          InlineElement.link(
            targetId: 'projects/plan',
            exists: false,
            content: [
              InlineElement.text(
                const TextRun(
                  content: 'Plan',
                  bold: false,
                  italic: false,
                  strikethrough: false,
                  code: false,
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
              onFocusRequested: (_, _) {},
              onLinkActivated: calls.add,
            ),
          ),
        ),
      );
      expect(find.byType(RichText), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, ['projects/plan']);
      await tester.tap(find.byType(RichText));
      await tester.pump();
      expect(calls, ['projects/plan', 'projects/plan']);
    },
  );
}
