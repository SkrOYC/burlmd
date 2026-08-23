import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

/// Formatted rendering for one Block, shared by every state a Block can be
/// in (`EDIT-F002`, CAP-EDIT-01): unfocused Blocks render through
/// [renderBlock], and the focused Block's editable field consumes the same
/// [blockTextStyle] factory this file uses, so promotion between the two
/// presentations cannot drift typographically.
///
/// The property table this enforces comes from `SPK-EDIT-F001` §3b: font
/// size/family/weight per Block type, an **explicit** `TextStyle.height`
/// (the sharpest trap — `Text.rich` inherits `DefaultTextStyle`'s height
/// while `EditableText` reads its style literally, so an implicit height
/// differs between the states by construction), leading distribution pinned
/// to even on the editable field, replicated container padding/decoration,
/// and the same layout slot/wrap width. Measured rendered geometry in the
/// Spike showed pixel-identical height, line count and first-line position
/// across both states once these were pinned.

/// The single [TextStyle] for a Block's base presentation, consumed by BOTH
/// paths — the formatted `Text.rich` in [renderBlock] and the promoted raw
/// editable field in `block_editor.dart`. Every metric-pertinent property is
/// explicit (never null-inherit): the field consults no `DefaultTextStyle`,
/// so anything left implicit here would silently differ between the two
/// states. That includes color: a bare `EditableText` has no ancestor style
/// to inherit from and paints null-color text white — invisible on the
/// pane's light background — so the ink color both presentations share is
/// pinned here to match what the formatted path's theme inheritance already
/// produced (Material's light-scheme on-surface ink).
const Color _blockInk = Color(0xff1c1b1f);

TextStyle blockTextStyle(AstNode node) => switch (node) {
  // Headings scale by level exactly as the read-only path always did, but
  // now with an explicit height so the promoted field matches.
  AstNode_Heading(:final level) => TextStyle(
    fontSize: (28 - level * 2).toDouble(),
    fontWeight: FontWeight.bold,
    height: 1.3,
    color: _blockInk,
  ),
  // A focused code Block shows its fence lines too, in the same monospace
  // face the rendered form uses.
  AstNode_CodeBlock() => const TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.4,
    color: Colors.white,
  ),
  // Everything else — paragraphs, list-item bodies, quote bodies, the raw
  // source of a focused thematic break — shares the body style.
  _ => const TextStyle(fontSize: 14, height: 1.45, color: _blockInk),
};

/// The container decoration around a Block's text surface, shared by BOTH
/// presentations (`SPK-EDIT-F001` §3b, "replicate the exact container widget
/// around the promoted field"): [child] is either the formatted rendering of
/// the Block's content (unfocused, via [renderBlock]) or the promoted raw
/// editable field (focused, via `editor.dart`). Because one builder draws the
/// decoration for both states, they cannot drift.
///
/// - CodeBlock: the dark pane + 8px padding the white monospace ink needs —
///   without it a focused code Block paints white glyphs on the light pane.
/// - Blockquote: the 3px grey left border + 12px left padding — without them
///   the quoted glyphs jump horizontally when the Block gains focus.
/// - List: the first item's marker column — without it the item body shifts
///   left by the marker's width on promotion. [renderBlock] draws markers for
///   any further items itself, so each unfocused item keeps its own.
///
/// Heading and Paragraph paint no container on either path, so [child] is
/// returned as-is; ThematicBreak's rule-to-`---` change is intrinsic content
/// movement CAP-EDIT-01 sanctions (`SPK-EDIT-F001` §4), not decoration drift.
Widget blockContainer(AstNode node, Widget child) => switch (node) {
  AstNode_CodeBlock() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    color: Colors.black87,
    child: child,
  ),
  AstNode_Blockquote() => Container(
    padding: const EdgeInsets.only(left: 12),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(width: 3, color: Colors.grey)),
    ),
    child: child,
  ),
  AstNode_List(:final ordered, :final items) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _markerWidget(switch (items.firstOrNull) {
        AstNode_ListItem(:final checked) => checked,
        _ => null,
      }, ordered ? '1.' : '•'),
      Expanded(child: child),
    ],
  ),
  _ => child,
};

/// One list marker cell: a checkbox for task items, otherwise the marker
/// glyph with the same right padding both paths must draw.
Widget _markerWidget(bool? checked, String marker) => checked != null
    ? Checkbox(value: checked, onChanged: null)
    : Padding(padding: const EdgeInsets.only(right: 4), child: Text(marker));

/// Renders one Block formatted (read-only). Moved verbatim from
/// `editor.dart` by `EDIT-F002` so both presentations live beside the style
/// factory and container builder they must agree on; the Paragraph/Heading
/// branches now take their outer style from [blockTextStyle] instead of
/// ad-hoc literals so the two paths cannot diverge, and every decorated type
/// routes through [blockContainer], which the focused path reuses unchanged.
Widget renderBlock(AstNode node) => switch (node) {
  AstNode_Heading(:final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
    style: blockTextStyle(node),
  ),
  AstNode_Paragraph(:final content) => Text.rich(
    TextSpan(children: content.map(renderInline).toList()),
    style: blockTextStyle(node),
  ),
  // The first item's marker is drawn once by blockContainer (so the focused
  // field sits in the same marker row); every further item carries its own.
  AstNode_List(:final ordered, :final items) => blockContainer(
    node,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in items.indexed)
          switch (item) {
            AstNode_ListItem(:final content, :final checked) when index > 0 =>
              _renderListItem(
                content,
                checked,
                ordered ? '${index + 1}.' : '•',
              ),
            AstNode_ListItem(:final content) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.map(renderBlock).toList(),
            ),
            _ => renderBlock(item),
          },
      ],
    ),
  ),
  // A ListItem reached outside of a List (not produced by the parser today,
  // but a reachable case for the exhaustiveness check) falls back to an
  // unordered bullet marker.
  AstNode_ListItem(:final content, :final checked) => _renderListItem(
    content,
    checked,
    '•',
  ),
  AstNode_Blockquote(:final nodes) => blockContainer(
    node,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes.map(renderBlock).toList(),
    ),
  ),
  AstNode_CodeBlock(:final code) => blockContainer(
    node,
    Text(code, style: blockTextStyle(node)),
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

Widget _renderListItem(List<AstNode> content, bool? checked, String marker) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _markerWidget(checked, marker),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content.map(renderBlock).toList(),
          ),
        ),
      ],
    );

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
  InlineElement_Link(:final content) => _renderLinkSpan(content),
  InlineElement_ExternalLink(:final content) => _renderLinkSpan(content),
};

/// Internal-link and external-link runs render identically today (both a
/// blue underline around their nested inline content) — a future ticket may
/// want to distinguish them (e.g. an external-link icon), at which point
/// this shared helper splits back into two.
TextSpan _renderLinkSpan(List<InlineElement> content) => TextSpan(
  style: const TextStyle(
    color: Colors.blue,
    decoration: TextDecoration.underline,
  ),
  children: content.map(renderInline).toList(),
);

// ---------------------------------------------------------------------------
// Clicked-position → source-offset mapping
//
// Promoting a Block places the caret where the user clicked (CAP-EDIT-01),
// but the click lands in *rendered* space while the editable field holds
// *raw source*. This section converts between them. It is a Dart-side
// approximation built purely from what the AST already carries — delimiter
// widths for styled runs and structural prefixes (heading hashes, list
// markers, quote markers, code fences) — never from laid-out geometry, which
// SPK-EDIT-F001 identified as the dangerous version of this problem. The
// authoritative rendered→source resolution is Core-side (ADR-007 decision 8)
// and is what EDIT-F003's range operations will use; this mapping only needs
// to be right for plain runs (where it is exact — identity) and reasonable
// elsewhere, because a caret a delimiter or two off is corrected by the very
// next keystroke round trip through `update_block`.
// ---------------------------------------------------------------------------

/// One selectable text leaf of a Block's rendered output, in paint order:
/// its rendered string, the number of raw-source bytes preceding it inside
/// the Block (structural prefixes — heading hashes, list markers, quote
/// markers, opening fences), and a function mapping a rendered offset within
/// the leaf to a source offset relative to the leaf's own start.
class _LeafText {
  const _LeafText(this.rendered, this.sourcePrefix, this.mapOffset);

  final String rendered;
  final int sourcePrefix;
  final int Function(int renderedOffset) mapOffset;
}

/// Flattens [node]'s rendered text leaves in paint order, aligning with the
/// `RenderParagraph`s [BlockView] collects from its subtree — including the
/// pseudo-leaves for list markers, which are painted as `Text` widgets but
/// belong to no AST leaf.
List<_LeafText> _blockLeaves(AstNode node, [int sourcePrefix = 0]) =>
    switch (node) {
      AstNode_Paragraph(:final content) => [
        _LeafText(
          _inlineRendered(content),
          sourcePrefix,
          (off) => _inlineSourceOffset(content, off),
        ),
      ],
      AstNode_Heading(:final level, :final content) => [
        _LeafText(
          _inlineRendered(content),
          sourcePrefix + '${'#' * level} '.length,
          (off) => _inlineSourceOffset(content, off),
        ),
      ],
      AstNode_List(:final ordered, :final items) => [
        for (final (index, item) in items.indexed)
          ...switch (item) {
            AstNode_ListItem listItem => _listItemLeaves(
              listItem,
              ordered,
              index,
              sourcePrefix,
            ),
            _ => _blockLeaves(item, sourcePrefix),
          },
      ],
      // A ListItem reached outside of a List mirrors renderBlock's fallback.
      AstNode_ListItem item => _listItemLeaves(item, false, 0, sourcePrefix),
      AstNode_Blockquote(:final nodes) => [
        for (final child in nodes) ..._blockLeaves(child, sourcePrefix + 2),
      ],
      AstNode_CodeBlock(:final language, :final code) => [
        _LeafText(
          code,
          sourcePrefix + '```${language ?? ''}\n'.length,
          (off) => off.clamp(0, code.length),
        ),
      ],
      AstNode_Suggestion(:final localContent) => [
        for (final child in localContent) ..._blockLeaves(child, sourcePrefix),
      ],
      // ThematicBreak and Image hold no selectable text (the contract gives
      // ThematicBreak the empty rendered string), so they contribute no
      // leaves; a click anywhere on them focuses at source offset 0.
      _ => const [],
    };

List<_LeafText> _listItemLeaves(
  AstNode_ListItem item,
  bool ordered,
  int index,
  int sourcePrefix,
) {
  final marker = ordered ? '${index + 1}. ' : '- ';
  final check = switch (item.checked) {
    null => '',
    true => '[x] ',
    false => '[ ] ',
  };
  return [
    // The painted marker row itself: clicking the bullet lands before the
    // item's first content character.
    _LeafText(
      '$marker$check',
      sourcePrefix,
      (off) => off.clamp(0, marker.length),
    ),
    for (final child in item.content)
      ..._blockLeaves(child, sourcePrefix + marker.length + check.length),
  ];
}

/// Converts a click — expressed as an index into [node]'s painted text
/// leaves plus a rendered-character offset within that leaf — into a source
/// offset into the Block's raw Markdown.
int blockSourceOffsetForTap(
  AstNode node, {
  required int leafIndex,
  required int renderedOffset,
}) {
  final leaves = _blockLeaves(node);
  if (leafIndex < 0 || leafIndex >= leaves.length) return 0;
  final leaf = leaves[leafIndex];
  return leaf.sourcePrefix +
      leaf.mapOffset(renderedOffset.clamp(0, leaf.rendered.length));
}

String _inlineRendered(List<InlineElement> elements) =>
    elements.map(_inlineRenderedOne).join();

String _inlineRenderedOne(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) => field0.content,
  InlineElement_Link(:final content) => _inlineRendered(content),
  InlineElement_ExternalLink(:final content) => _inlineRendered(content),
};

int _inlineRenderedLength(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) => field0.content.length,
  InlineElement_Link(:final content) => _inlineRendered(content).length,
  InlineElement_ExternalLink(:final content) => _inlineRendered(content).length,
};

int _openingDelimiters(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) =>
    (field0.bold ? 2 : 0) +
        (field0.italic ? 1 : 0) +
        (field0.strikethrough ? 2 : 0) +
        (field0.code ? 1 : 0),
  InlineElement_Link() || InlineElement_ExternalLink() => 1, // '['
};

/// Total source bytes an inline element occupies: its rendered length plus
/// both delimiter pairs. A link's destination bytes are not derivable from
/// what the AST carries, so they are estimated from `targetId` (rendered as
/// the bundle-absolute `<​/path.md>` form per ADR-004 decision 5); the
/// estimate is documented as approximate and only ever shifts a caret past a
/// link, never any Core-side resolution (ADR-007 decision 8).
int _inlineSourceLength(InlineElement element) => switch (element) {
  InlineElement_Text() =>
    _openingDelimiters(element) +
        _inlineRenderedLength(element) +
        _openingDelimiters(element),
  InlineElement_Link(:final targetId, :final content) =>
    1 +
        _inlineSourceLengthAll(content) +
        ']('.length +
        1 +
        '/'.length +
        targetId.length +
        '.md'.length +
        1 +
        1,
  InlineElement_ExternalLink(:final url, :final content) =>
    1 + _inlineSourceLengthAll(content) + ']('.length + url.length + 1,
};

int _inlineSourceLengthAll(List<InlineElement> elements) =>
    elements.fold(0, (sum, element) => sum + _inlineSourceLength(element));

/// Maps a rendered offset within a run sequence to a source offset relative
/// to the sequence's start. Offsets landing strictly inside an element whose
/// interior is not interpolable (code spans, entities, link targets —
/// ADR-007 decision 8's atomic class) resolve to that element's boundaries,
/// mirroring the Core-side rule at UI granularity.
int _inlineSourceOffset(List<InlineElement> elements, int renderedOffset) {
  var source = 0;
  var consumed = 0;
  for (final element in elements) {
    final renderedLength = _inlineRenderedLength(element);
    if (renderedOffset <= consumed + renderedLength) {
      final local = renderedOffset - consumed;
      return switch (element) {
        InlineElement_Text(:final field0) =>
          source +
              _openingDelimiters(element) +
              local.clamp(0, field0.content.length),
        InlineElement_Link(:final content) ||
        InlineElement_ExternalLink(:final content) =>
          source +
              _openingDelimiters(element) +
              _inlineSourceOffset(content, local),
      };
    }
    consumed += renderedLength;
    source += _inlineSourceLength(element);
  }
  return source;
}

// ---------------------------------------------------------------------------
// The unfocused Block surface
// ---------------------------------------------------------------------------

/// One Block's unfocused presentation: its formatted rendering wrapped in a
/// tap detector that promotes it to the raw editable field (`EDIT-F002`,
/// ADR-006 decision 2). On tap the clicked position is resolved through the
/// painted `RenderParagraph`s — real rendered geometry, not widget-property
/// guesses — mapped to a raw-source offset, and handed to the parent
/// ([Editor]), which owns focus as ephemeral UI state.
class BlockView extends StatelessWidget {
  const BlockView({
    super.key,
    required this.node,
    required this.blockPath,
    required this.onFocusRequested,
  });

  final AstNode node;
  final List<int> blockPath;
  final void Function(List<int> blockPath, int caretSourceOffset)
  onFocusRequested;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (details) => _handleTapUp(context, details),
    child: renderBlock(node),
  );

  void _handleTapUp(BuildContext context, TapUpDetails details) {
    final renderObject = context.findRenderObject();
    if (renderObject == null) {
      onFocusRequested(blockPath, 0);
      return;
    }
    final paragraphs = <RenderParagraph>[];
    _collectParagraphs(renderObject, paragraphs);
    for (final (index, box) in paragraphs.indexed) {
      final globalBounds = MatrixUtils.transformRect(
        box.getTransformTo(null),
        box.paintBounds,
      );
      if (!globalBounds.contains(details.globalPosition)) continue;
      final local = box.globalToLocal(details.globalPosition);
      final position = box.getPositionForOffset(local);
      onFocusRequested(
        blockPath,
        blockSourceOffsetForTap(
          node,
          leafIndex: index,
          renderedOffset: position.offset,
        ),
      );
      return;
    }
    // No text leaf under the pointer (a thematic break's rule, whitespace
    // beside a short line): promote with the caret at the Block's start.
    onFocusRequested(blockPath, 0);
  }

  /// Collects the painted text paragraphs beneath [object] in child order,
  /// which is paint order for every layout this file produces.
  static void _collectParagraphs(
    RenderObject object,
    List<RenderParagraph> out,
  ) {
    if (object is RenderParagraph) {
      out.add(object);
      return;
    }
    object.visitChildren((child) => _collectParagraphs(child, out));
  }
}
