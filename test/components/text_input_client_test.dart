import 'dart:async';

import 'package:burlmd/src/components/range_text_input_client.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';

BlockRange _range() => BlockRange(
  startPath: Uint64List.fromList(const [0]),
  startOffset: BigInt.zero,
  endPath: Uint64List.fromList(const [2]),
  endOffset: BigInt.one,
);

Future<void> _pump(WidgetTester tester) =>
    tester.pumpWidget(const MaterialApp(home: SizedBox()));

void main() {
  testWidgets('attaches empty state before show and exposes every ephemeral '
      'TextInputClient value', (tester) async {
    await _pump(tester);
    final client = RangeTextInputClient(
      range: _range(),
      onReplace: (_) async {},
      onDelete: () async {},
      copyMarkdown: () async => 'core markdown',
      onError: (error) => fail('$error'),
    )..attach();
    addTearDown(client.close);

    expect(client.currentTextEditingValue, TextEditingValue.empty);
    expect(client.currentAutofillScope, isNull);
    expect(client.isAttached, isTrue);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      containsAllInOrder([
        'TextInput.setClient',
        'TextInput.setEditingState',
        'TextInput.show',
      ]),
    );
    expect(tester.testTextInput.editingState?['text'], '');

    // Required platform callbacks are intentionally inert for this desktop
    // proxy; this is the narrow protocol seam, not a document mutation test.
    client.performAction(TextInputAction.done);
    client.performPrivateCommand('ignored', const {});
    client.updateFloatingCursor(
      RawFloatingCursorPoint(
        state: FloatingCursorDragState.Update,
        offset: Offset.zero,
      ),
    );
    client.showAutocorrectionPromptRect(0, 0);
  });

  testWidgets('a composing update makes no edit and its collapsed commit '
      'makes exactly one replacement', (tester) async {
    await _pump(tester);
    final replacements = <String>[];
    final client = RangeTextInputClient(
      range: _range(),
      onReplace: (text) async => replacements.add(text),
      onDelete: () async {},
      copyMarkdown: () async => '',
      onError: (error) => fail('$error'),
    )..attach();
    addTearDown(client.close);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '漢字',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(replacements, isEmpty);
    expect(client.currentTextEditingValue.text, '漢字');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '漢字',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(replacements, ['漢字']);
    expect(client.currentTextEditingValue, TextEditingValue.empty);
  });

  testWidgets('closed and stale platform callbacks cannot mutate a range', (
    tester,
  ) async {
    await _pump(tester);
    var replacements = 0;
    final client = RangeTextInputClient(
      range: _range(),
      onReplace: (_) async => replacements++,
      onDelete: () async {},
      copyMarkdown: () async => '',
      onError: (error) => fail('$error'),
    )..attach();

    tester.testTextInput.closeConnection();
    await tester.pump();
    tester.testTextInput.enterText('late');
    await tester.pump();
    expect(replacements, 0);
    expect(client.isAttached, isFalse);
    client.close();
  });

  testWidgets('explicit delete and copy/cut lifecycle never fan out a '
      'mutation', (tester) async {
    await _pump(tester);
    var deletes = 0;
    final gate = Completer<void>();
    final client = RangeTextInputClient(
      range: _range(),
      onReplace: (_) async {},
      onDelete: () async {
        deletes++;
        await gate.future;
      },
      copyMarkdown: () async => 'core markdown',
      onError: (error) => fail('$error'),
    )..attach();
    addTearDown(client.close);

    final first = client.deleteSelection();
    final second = client.deleteSelection();
    expect(deletes, 1);
    gate.complete();
    await first;
    await second;
    expect(deletes, 1);
  });

  testWidgets('a failed Core copy prevents cut deletion', (tester) async {
    await _pump(tester);
    var deletes = 0;
    final client = RangeTextInputClient(
      range: _range(),
      onReplace: (_) async {},
      onDelete: () async => deletes++,
      copyMarkdown: () async => throw StateError('Core copy failed'),
      onError: (_) {},
    )..attach();
    addTearDown(client.close);

    await client.cutSelection();

    expect(deletes, 0);
  });
}
