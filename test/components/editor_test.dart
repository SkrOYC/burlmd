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

    await tester.pumpWidget(MaterialApp(home: Editor(ast: ast)));

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
    AstNode item(String text) => AstNode.listItem(
      content: [
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
    );
    final ast = [
      AstNode.list(ordered: true, items: [item('first'), item('second')]),
    ];

    await tester.pumpWidget(MaterialApp(home: Editor(ast: ast)));

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('•'), findsNothing);
  });
}
