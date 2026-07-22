import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';

/// Renders a parsed Markdown AST as read-only Flutter widgets, so users see
/// formatted text (bold, headings, lists, ...) instead of raw markup.
/// Stateless regarding note content: `ast` is the sole input, supplied by a
/// caller reading note state from a Riverpod provider — this widget never
/// stores or owns content itself.
class Editor extends StatelessWidget {
  const Editor({super.key, required this.ast});

  final List<AstNode> ast;

  @override
  Widget build(BuildContext context) =>
      ListView(children: [for (final node in ast) renderBlock(node)]);
}

Widget renderBlock(AstNode node) => switch (node) {
  AstNode_Heading(:final level, :final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
    style: TextStyle(fontSize: 28 - (level * 2), fontWeight: FontWeight.bold),
  ),
  AstNode_Paragraph(:final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
  ),
  AstNode_List(:final items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items.map(renderBlock).toList(),
  ),
  AstNode_ListItem(:final content, :final checked) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      checked != null
          ? Checkbox(value: checked, onChanged: null)
          : const Padding(padding: EdgeInsets.only(right: 4), child: Text('•')),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content.map(renderBlock).toList(),
        ),
      ),
    ],
  ),
  AstNode_Blockquote(:final nodes) => Container(
    padding: const EdgeInsets.only(left: 12),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(width: 3, color: Colors.grey)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes.map(renderBlock).toList(),
    ),
  ),
  AstNode_CodeBlock(:final code) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    color: Colors.black87,
    child: Text(
      code,
      style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
    ),
  ),
  AstNode_ThematicBreak() => const Divider(),
  AstNode_Image(:final altText, :final urlOrPath) => Image.asset(
    urlOrPath,
    semanticLabel: altText,
    errorBuilder: (_, _, _) => Text('[image: $altText]'),
  ),
  // Suggestions represent a pending Git conflict awaiting user resolution;
  // a full margin-suggestion UI is out of scope here, so only the local
  // (current-device) branch renders for now.
  AstNode_Suggestion(:final localContent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: localContent.map(renderBlock).toList(),
  ),
};

TextSpan renderInline(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) => TextSpan(
    text: field0.content,
    style: TextStyle(
      fontWeight: field0.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: field0.italic ? FontStyle.italic : FontStyle.normal,
      decoration: field0.strikethrough
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      fontFamily: field0.code ? 'monospace' : null,
    ),
  ),
  InlineElement_Link(:final content) => TextSpan(
    style: const TextStyle(
      color: Colors.blue,
      decoration: TextDecoration.underline,
    ),
    children: content.map(renderInline).toList(),
  ),
  InlineElement_ExternalLink(:final content) => TextSpan(
    style: const TextStyle(
      color: Colors.blue,
      decoration: TextDecoration.underline,
    ),
    children: content.map(renderInline).toList(),
  ),
};
