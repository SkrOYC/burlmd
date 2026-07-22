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

Widget _renderListItem(List<AstNode> content, bool? checked, String marker) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        checked != null
            ? Checkbox(value: checked, onChanged: null)
            : Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(marker),
              ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content.map(renderBlock).toList(),
          ),
        ),
      ],
    );

Widget renderBlock(AstNode node) => switch (node) {
  AstNode_Heading(:final level, :final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
    style: TextStyle(fontSize: 28 - (level * 2), fontWeight: FontWeight.bold),
  ),
  AstNode_Paragraph(:final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
  ),
  AstNode_List(:final ordered, :final items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, item) in items.indexed)
        switch (item) {
          AstNode_ListItem(:final content, :final checked) => _renderListItem(
            content,
            checked,
            ordered ? '${index + 1}.' : '•',
          ),
          _ => renderBlock(item),
        },
    ],
  ),
  // A ListItem reached outside of a List (not produced by the parser today,
  // but a reachable case for the exhaustiveness check) falls back to an
  // unordered bullet marker.
  AstNode_ListItem(:final content, :final checked) => _renderListItem(
    content,
    checked,
    '•',
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
  // `urlOrPath` is a real filesystem path or URL from the Markdown source,
  // not a Flutter asset-bundle key, so `Image.asset` will not actually load
  // real note images — every one falls through to the alt-text placeholder
  // below. Loading from disk/network (Image.file / Image.network, chosen by
  // scheme) is deferred to a dedicated image-rendering ticket.
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
  // A field left `null` here (rather than an explicit "off" value like
  // FontWeight.normal) inherits from the nearest ancestor TextSpan's style
  // during painting, e.g. a non-bold TextRun inside a Heading still renders
  // bold via the Heading's own span-level style. Setting explicit "off"
  // values would instead unconditionally override — and defeat — that
  // ancestor styling (this previously broke heading bold and link
  // underlines: every leaf run forced its own weight/decoration).
  InlineElement_Text(:final field0) => TextSpan(
    text: field0.content,
    style: TextStyle(
      fontWeight: field0.bold ? FontWeight.bold : null,
      fontStyle: field0.italic ? FontStyle.italic : null,
      decoration: field0.strikethrough ? TextDecoration.lineThrough : null,
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
