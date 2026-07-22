import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    await tester.pumpWidget(MaterialApp(home: Editor(ast: ast)));

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    // Text.rich wraps the given span in its own TextSpan(children: [...]),
    // so the tree is: richText.text -> [our paragraph span] -> [our inline span].
    final paragraphSpan =
        (richText.text as TextSpan).children!.first as TextSpan;
    final span = paragraphSpan.children!.first as TextSpan;
    expect(span.text, 'hello');
    expect(span.style?.fontWeight, FontWeight.bold);
  });
}
