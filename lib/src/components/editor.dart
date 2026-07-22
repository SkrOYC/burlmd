import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders the currently open note's AST as formatted, editable Flutter
/// widgets, so users see actual bold/italic/headings/lists instead of raw
/// markdown syntax. Stateless regarding note content: it reads `ast` from
/// [activeNoteProvider] rather than owning or caching it itself; edits flow
/// back out through the same provider (and, ultimately, the Rust core) so
/// that provider stays the single source of truth.
class Editor extends ConsumerWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(activeNoteProvider);
    if (note == null) return const SizedBox.shrink();
    return ListView(
      children: [
        for (var i = 0; i < note.ast.length; i++)
          _EditableBlock(node: note.ast[i], blockPath: [i]),
      ],
    );
  }
}

/// Wraps a single top-level AST node. Only a single-run Paragraph (exactly
/// one plain-or-styled [InlineElement_Text], no Links) is live-editable via a
/// [TextField] that streams keystrokes straight to `update_block`. A
/// [TextField] can only apply one uniform [TextStyle], so a multi-run
/// paragraph (e.g. plain text followed by a bold word) made editable this way
/// would silently flatten to a single style and lose every distinction a
/// reader relies on — caught visually (a real `flutter run`, not just
/// `flutter test`) when a mixed-run paragraph rendered with no bold/italic/
/// code distinction at all. Multi-run paragraphs and every other block type
/// stay read-only through [renderBlock], which preserves full per-run
/// fidelity via [renderInline]'s `TextSpan` tree — full rich multi-run inline
/// editing (splitting a styled run mid-string while preserving neighboring
/// formatting and cursor position) is materially larger than this ticket's
/// scope.
class _EditableBlock extends ConsumerStatefulWidget {
  const _EditableBlock({required this.node, required this.blockPath});

  final AstNode node;
  final List<int> blockPath;

  @override
  ConsumerState<_EditableBlock> createState() => _EditableBlockState();
}

class _EditableBlockState extends ConsumerState<_EditableBlock> {
  // Held in State (rather than rebuilt every keystroke) so the cursor
  // doesn't jump to the end of the field on every rebuild. This is ephemeral
  // edit-widget presentation state, not note content, so it doesn't violate
  // the "stateless regarding content" rule — the content itself still comes
  // only from `activeNoteProvider`.
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _plainText(widget.node));
  }

  @override
  void didUpdateWidget(covariant _EditableBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter reuses this State for the block at the same list index across
    // rebuilds, so if `activeNoteProvider` ever swaps in a different note
    // (or a future insert_block/delete_block reindexes positions), this
    // node's content can change out from under an already-mounted field.
    // Resync only when the incoming text actually differs from what the
    // field currently shows — on this field's own keystroke round-trip
    // through updateBlock, the echoed-back node already matches, so this
    // guard leaves the cursor alone; it only fires on a genuinely external
    // change.
    final incomingText = _plainText(widget.node);
    if (incomingText != _controller.text) {
      _controller.text = incomingText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.node) {
    AstNode_Paragraph(:final content) when _isSingleTextRun(content) =>
      TextField(
        controller: _controller,
        // Deriving the field's style from the (only) run keeps a single-run
        // paragraph visibly bold/italic/etc. while editable. Safe here
        // specifically because _isSingleTextRun guarantees there is exactly
        // one run — for a multi-run paragraph this same derivation would
        // silently drop every run after the first, so those stay read-only
        // instead (see the class doc comment).
        style: _paragraphStyle(content),
        decoration: const InputDecoration(border: InputBorder.none),
        onChanged: (text) {
          final newNode = AstNode.paragraph(
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
          ref
              .read(activeNoteProvider.notifier)
              .updateBlock(widget.blockPath, newNode);
        },
      ),
    final other => renderBlock(other),
  };
}

// Only called meaningfully for paragraphs _isSingleTextRun accepts (see
// below); for any other node this result is computed but unused, since
// _EditableBlockState.build only reads _controller inside that same guard.
// A single-run paragraph is always exactly one InlineElement_Text, never a
// Link/ExternalLink, so there is no display-text-dropping gap here.
String _plainText(AstNode node) {
  if (node is! AstNode_Paragraph) return '';
  final buffer = StringBuffer();
  for (final inline in node.content) {
    if (inline is InlineElement_Text) buffer.write(inline.field0.content);
  }
  return buffer.toString();
}

/// A paragraph is only safe to make editable via a single-style [TextField]
/// when it has exactly one run and that run is plain text (not a Link) — see
/// the `_EditableBlock` class doc comment for why a multi-run paragraph must
/// stay read-only instead.
bool _isSingleTextRun(List<InlineElement> content) =>
    content.length == 1 && content.single is InlineElement_Text;

/// Derives a single [TextStyle] for an editable paragraph field from its
/// (only, per [_isSingleTextRun]) run's formatting — a `TextField` can't
/// apply per-character rich styling the way [renderInline]'s `TextSpan` tree
/// can.
TextStyle? _paragraphStyle(List<InlineElement> content) {
  for (final inline in content) {
    if (inline is InlineElement_Text) {
      final run = inline.field0;
      return TextStyle(
        fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        decoration: run.strikethrough
            ? TextDecoration.lineThrough
            : TextDecoration.none,
        fontFamily: run.code ? 'monospace' : null,
      );
    }
  }
  return null;
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
