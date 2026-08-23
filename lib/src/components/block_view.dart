import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, RenderParagraph, RenderProxyBox, SelectionRegistrar;
import 'package:flutter/services.dart';

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
/// - List items own their marker columns. This keeps every sibling marker at
///   the same x-coordinate, while a nested List naturally starts inside its
///   parent's body column.
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
  _ => child,
};

/// Holds a promoted raw editor to the formatted Block's measured footprint.
///
/// Markdown punctuation is intentionally visible in the focused field, so at
/// a soft-wrap boundary its source can take one more line than the formatted
/// output (for example, `**bold**` versus bold). Letting that extra line
/// resize the ListView entry moves every following Block, violating
/// CAP-EDIT-01 even though the two paths share identical font metrics. The
/// invisible formatted baseline supplies the authoritative height and wrap
/// width; the raw field fills that viewport and scrolls when its source needs
/// more space. [SelectionContainer.disabled] is essential: this baseline is
/// layout-only while a Block is focused and must not rejoin the surrounding
/// SelectionArea.
Widget blockPromotionSlot(AstNode node, Widget editor) => Stack(
  children: [
    SelectionContainer.disabled(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(opacity: 0, child: renderBlock(node)),
        ),
      ),
    ),
    Positioned.fill(child: editor),
  ],
);

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

/// The formatted variant used by an unfocused [BlockView].  Only internal
/// links become WidgetSpans; all non-link text stays in the normal RichText
/// flow, preserving its measured layout and the existing selection broker.
Widget _renderBlockForView(
  AstNode node,
  TextSpan Function(String targetId, bool exists, List<InlineElement> content)
  linkSpan,
) => switch (node) {
  AstNode_Heading(:final content) => Text.rich(
    TextSpan(children: _interactiveInlines(content, linkSpan)),
    style: blockTextStyle(node),
  ),
  AstNode_Paragraph(:final content) => Text.rich(
    TextSpan(children: _interactiveInlines(content, linkSpan)),
    style: blockTextStyle(node),
  ),
  AstNode_List(:final ordered, :final items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, item) in items.indexed)
        switch (item) {
          AstNode_ListItem(:final content, :final checked) =>
            _renderListItemForView(
              content,
              checked,
              ordered ? '${index + 1}.' : '•',
              linkSpan,
            ),
          _ => _renderBlockForView(item, linkSpan),
        },
    ],
  ),
  AstNode_ListItem(:final content, :final checked) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _markerWidget(checked, '•'),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content
              .map((child) => _renderBlockForView(child, linkSpan))
              .toList(),
        ),
      ),
    ],
  ),
  AstNode_Blockquote(:final nodes) => blockContainer(
    node,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes
          .map((child) => _renderBlockForView(child, linkSpan))
          .toList(),
    ),
  ),
  AstNode_Suggestion(:final localContent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: localContent
        .map((child) => _renderBlockForView(child, linkSpan))
        .toList(),
  ),
  _ => renderBlock(node),
};

List<InlineSpan> _interactiveInlines(
  List<InlineElement> elements,
  TextSpan Function(String targetId, bool exists, List<InlineElement> content)
  linkSpan,
) => [
  for (final element in elements)
    switch (element) {
      InlineElement_Link(:final targetId, :final exists, :final content) =>
        linkSpan(targetId, exists, content),
      _ => renderInline(element),
    },
];

/// Renders a top-level container while replacing exactly one descendant leaf
/// with its raw editor. The container's siblings, marker/border decoration,
/// and layout remain the normal formatted rendering; only Core's resolved
/// leaf path may become editable.
Widget renderBlockWithFocusedLeaf(
  AstNode node,
  List<int> relativeLeafPath,
  Widget Function(AstNode leaf) buildEditor, {
  Widget Function(AstNode node)? renderUnfocused,
}) {
  final renderSibling = renderUnfocused ?? renderBlock;
  if (relativeLeafPath.isEmpty) {
    final editor = buildEditor(node);
    return switch (node) {
      AstNode_CodeBlock() => blockPromotionSlot(
        node,
        blockContainer(node, editor),
      ),
      _ => blockPromotionSlot(node, editor),
    };
  }
  final childIndex = relativeLeafPath.first;
  final remaining = relativeLeafPath.sublist(1);
  return switch (node) {
    AstNode_List(:final ordered, :final items)
        when childIndex >= 0 && childIndex < items.length =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, item) in items.indexed)
            index == childIndex
                ? switch (item) {
                    AstNode_ListItem(:final content, :final checked) =>
                      _renderFocusedListItem(
                        content,
                        checked,
                        ordered ? '${index + 1}.' : '•',
                        remaining,
                        buildEditor,
                        renderUnfocused: renderUnfocused,
                      ),
                    _ => renderBlockWithFocusedLeaf(
                      item,
                      remaining,
                      buildEditor,
                      renderUnfocused: renderUnfocused,
                    ),
                  }
                : switch (item) {
                    AstNode_ListItem(:final content, :final checked) =>
                      _renderListItemWith(
                        content,
                        checked,
                        ordered ? '${index + 1}.' : '•',
                        renderSibling,
                      ),
                    _ => renderSibling(item),
                  },
        ],
      ),
    AstNode_ListItem(:final content, :final checked)
        when childIndex >= 0 && childIndex < content.length =>
      _renderFocusedListItem(
        content,
        checked,
        '•',
        relativeLeafPath,
        buildEditor,
        renderUnfocused: renderUnfocused,
      ),
    AstNode_Blockquote(:final nodes)
        when childIndex >= 0 && childIndex < nodes.length =>
      blockContainer(
        node,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, child) in nodes.indexed)
              index == childIndex
                  ? renderBlockWithFocusedLeaf(
                      child,
                      remaining,
                      buildEditor,
                      renderUnfocused: renderUnfocused,
                    )
                  : renderSibling(child),
          ],
        ),
      ),
    AstNode_Suggestion(:final localContent)
        when childIndex >= 0 && childIndex < localContent.length =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, child) in localContent.indexed)
            index == childIndex
                ? renderBlockWithFocusedLeaf(
                    child,
                    remaining,
                    buildEditor,
                    renderUnfocused: renderUnfocused,
                  )
                : renderSibling(child),
        ],
      ),
    _ => renderSibling(node),
  };
}

Widget _renderFocusedListItem(
  List<AstNode> content,
  bool? checked,
  String marker,
  List<int> relativeLeafPath,
  Widget Function(AstNode leaf) buildEditor, {
  Widget Function(AstNode node)? renderUnfocused,
}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _markerWidget(checked, marker),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, child) in content.indexed)
            index == relativeLeafPath.first
                ? renderBlockWithFocusedLeaf(
                    child,
                    relativeLeafPath.sublist(1),
                    buildEditor,
                    renderUnfocused: renderUnfocused,
                  )
                : (renderUnfocused ?? renderBlock)(child),
        ],
      ),
    ),
  ],
);

Widget _renderListItem(List<AstNode> content, bool? checked, String marker) =>
    _renderListItemWith(content, checked, marker, renderBlock);

Widget _renderListItemWith(
  List<AstNode> content,
  bool? checked,
  String marker,
  Widget Function(AstNode node) renderChild,
) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _markerWidget(checked, marker),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content.map(renderChild).toList(),
      ),
    ),
  ],
);

Widget _renderListItemForView(
  List<AstNode> content,
  bool? checked,
  String marker,
  TextSpan Function(String targetId, bool exists, List<InlineElement> content)
  linkSpan,
) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _markerWidget(checked, marker),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content
            .map((child) => _renderBlockForView(child, linkSpan))
            .toList(),
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
// Clicked-position → canonical rendered-coordinate mapping
// ---------------------------------------------------------------------------

/// One selectable text leaf of a Block's rendered output, in paint order:
/// its rendered string and where it begins in the Core's canonical rendered
/// string of the top-level Block. Core, not Dart, resolves source and leaf.
class _LeafText {
  const _LeafText(
    this.rendered, {
    required this.corePrefix,
    required this.coreWidth,
    this.leadingDecorationWidth = 0,
  });

  final String rendered;

  /// Start and width of this leaf's contribution to the Core's canonical
  /// rendered string of the Block — the per-variant definition the contract
  /// fixes in the `BlockRange` docs (paragraphs/headings: concatenated runs;
  /// recursive containers joined with '\n'; code verbatim; thematic break:
  /// empty). Decoration the widget paints as text but no `AstNode` field
  /// contains — list bullets, ordered numbers, task checkboxes — occupies
  /// ZERO width here, because the definition deliberately does not model it;
  /// a selection over such decoration resolves to the boundary it sits on.
  final int corePrefix;
  final int coreWidth;

  /// UTF-16 width of painted text that comes before this leaf's Core-rendered
  /// contribution. Image fallbacks visibly include `[image: `, while the
  /// Core contract intentionally defines Image rendered text as `alt_text`.
  /// Mapping that decoration here keeps the selectable leaf faithful to both.
  final int leadingDecorationWidth;
}

/// Flattens [node]'s rendered text leaves in paint order, aligning with the
/// `RenderParagraph`s [BlockView] collects from its subtree — including the
/// pseudo-leaves for textual list markers, which are painted as `Text`
/// widgets but belong to no AST leaf. Task markers are a [Checkbox], not a
/// [RenderParagraph], so they deliberately have no pseudo-leaf: otherwise the
/// paragraph index and this mapping diverge for every checked task item.
List<_LeafText> _blockLeaves(AstNode node) => _leaves(node, 0);

/// The rendered-leaf indexes that remain selectable while [relativeLeafPath]
/// is replaced by a raw editor. They stay in the top-level Block's canonical
/// rendered coordinate system; only Core resolves that rendered coordinate to
/// a source offset.
List<int> blockUnfocusedLeafIndices(AstNode node, List<int> relativeLeafPath) {
  final focusedNode = _nodeAtPath(node, relativeLeafPath);
  if (focusedNode == null) {
    return List<int>.generate(_blockLeaves(node).length, (index) => index);
  }
  final focusedStart = _leafPrefixForPath(node, relativeLeafPath);
  final focusedEnd = focusedStart + _blockLeaves(focusedNode).length;
  return [
    for (var index = 0; index < _blockLeaves(node).length; index++)
      if (index < focusedStart || index >= focusedEnd) index,
  ];
}

int blockRenderedLeafCount(AstNode node) => _blockLeaves(node).length;

AstNode? _nodeAtPath(AstNode node, List<int> path) {
  if (path.isEmpty) return node;
  final index = path.first;
  final remaining = path.sublist(1);
  return switch (node) {
    AstNode_List(:final items) when index >= 0 && index < items.length =>
      _nodeAtPath(items[index], remaining),
    AstNode_ListItem(:final content)
        when index >= 0 && index < content.length =>
      _nodeAtPath(content[index], remaining),
    AstNode_Blockquote(:final nodes) when index >= 0 && index < nodes.length =>
      _nodeAtPath(nodes[index], remaining),
    AstNode_Suggestion(:final localContent)
        when index >= 0 && index < localContent.length =>
      _nodeAtPath(localContent[index], remaining),
    _ => null,
  };
}

int _leafPrefixForPath(AstNode node, List<int> path) {
  if (path.isEmpty) return 0;
  final index = path.first;
  final remaining = path.sublist(1);
  return switch (node) {
    AstNode_List(:final items) when index >= 0 && index < items.length =>
      _leafCountBefore(items, index) +
          _leafPrefixForPath(items[index], remaining),
    AstNode_ListItem(:final content, :final checked)
        when index >= 0 && index < content.length =>
      (checked == null ? 1 : 0) +
          _leafCountBefore(content, index) +
          _leafPrefixForPath(content[index], remaining),
    AstNode_Blockquote(:final nodes) when index >= 0 && index < nodes.length =>
      _leafCountBefore(nodes, index) +
          _leafPrefixForPath(nodes[index], remaining),
    AstNode_Suggestion(:final localContent)
        when index >= 0 && index < localContent.length =>
      _leafCountBefore(localContent, index) +
          _leafPrefixForPath(localContent[index], remaining),
    _ => 0,
  };
}

int _leafCountBefore(List<AstNode> nodes, int end) =>
    nodes.take(end).fold(0, (count, node) => count + _blockLeaves(node).length);

List<_LeafText> _leaves(AstNode node, int corePrefix) => switch (node) {
  AstNode_Paragraph(:final content) => [
    _LeafText(
      _inlineRendered(content),
      corePrefix: corePrefix,
      // A paragraph's canonical rendered text IS its painted text.
      coreWidth: _inlineRenderedLengthAll(content),
    ),
  ],
  AstNode_Heading(:final content) => [
    _LeafText(
      _inlineRendered(content),
      // The '#' prefix is raw-source structure, not rendered text.
      corePrefix: corePrefix,
      coreWidth: _inlineRenderedLengthAll(content),
    ),
  ],
  AstNode_List(:final ordered, :final items) => [
    for (final (index, item) in items.indexed)
      ...switch (item) {
        AstNode_ListItem listItem => _listItemLeaves(
          listItem,
          ordered,
          index,
          // The List's children are joined with a single '\n' in the
          // canonical string, so each sibling's start accumulates the
          // previous ones' lengths plus that separator.
          _siblingCoreStart(items, index, corePrefix),
        ),
        _ => _leaves(item, _siblingCoreStart(items, index, corePrefix)),
      },
  ],
  // A ListItem reached outside of a List mirrors renderBlock's fallback.
  AstNode_ListItem item => _listItemLeaves(item, false, 0, corePrefix),
  AstNode_Blockquote(:final nodes) => [
    for (final (index, child) in nodes.indexed)
      ..._leaves(child, _siblingCoreStart(nodes, index, corePrefix)),
  ],
  AstNode_CodeBlock(:final code) => [
    _LeafText(
      code,
      // Canonical text is `code` verbatim — not the fence, not the
      // language — which is exactly what the unfocused render paints.
      corePrefix: corePrefix,
      coreWidth: code.length,
    ),
  ],
  AstNode_Suggestion(:final localContent) => [
    for (final (index, child) in localContent.indexed)
      ..._leaves(child, _siblingCoreStart(localContent, index, corePrefix)),
  ],
  AstNode_Image(:final altText) => [
    _LeafText(
      '[image: $altText]',
      corePrefix: corePrefix,
      coreWidth: altText.length,
      leadingDecorationWidth: '[image: '.length,
    ),
  ],
  // ThematicBreak has no selectable text (the contract gives it the empty
  // rendered string), so it contributes no leaves; a click on it focuses at
  // source offset 0.
  _ => const [],
};

/// Where sibling [index] of [siblings] starts in the parent's canonical
/// rendered string: children concatenate in order, joined with one '\n'.
int _siblingCoreStart(List<AstNode> siblings, int index, int parentStart) {
  var start = parentStart;
  for (var i = 0; i < index; i++) {
    start += _coreRenderedLength(siblings[i]) + 1;
  }
  return start;
}

/// The length of [node]'s canonical rendered text, per the contract's
/// per-variant definition (`BlockRange` docs): paragraphs/headings are their
/// concatenated run contents (descending into links); recursive containers
/// join children with a single '\n'; CodeBlock is `code` verbatim; Image is
/// its alt text; ThematicBreak is empty.
int _coreRenderedLength(AstNode node) => switch (node) {
  AstNode_Paragraph(:final content) ||
  AstNode_Heading(:final content) => _inlineRenderedLengthAll(content),
  AstNode_CodeBlock(:final code) => code.length,
  AstNode_Image(:final altText) => altText.length,
  AstNode_ThematicBreak() => 0,
  AstNode_List(:final items) => _joinedCoreLength(items),
  AstNode_ListItem(:final content) => _joinedCoreLength(content),
  AstNode_Blockquote(:final nodes) => _joinedCoreLength(nodes),
  AstNode_Suggestion(:final localContent) => _joinedCoreLength(localContent),
};

/// The UTF-16 width of [node]'s Core-defined rendered text. This is the
/// endpoint width for a whole-Block `BlockRange`, including an unmounted lazy
/// ListView entry selected through the editor-level Select All action.
int blockCoreRenderedLength(AstNode node) => _coreRenderedLength(node);

int _joinedCoreLength(List<AstNode> nodes) {
  var total = 0;
  for (final (index, child) in nodes.indexed) {
    total += (index == 0 ? 0 : 1) + _coreRenderedLength(child);
  }
  return total;
}

List<_LeafText> _listItemLeaves(
  AstNode_ListItem item,
  bool ordered,
  int index,
  int corePrefix,
) {
  final marker = ordered ? '${index + 1}. ' : '- ';
  final check = switch (item.checked) {
    null => '',
    true => '[x] ',
    false => '[ ] ',
  };
  return [
    // A normal marker is a Text/RenderParagraph and must have a matching
    // zero-width pseudo-leaf. A task marker is a Checkbox RenderObject, which
    // BlockView never collects as a text paragraph, so omitting it keeps the
    // logical leaves and rendered objects one-to-one.
    if (item.checked == null)
      _LeafText('$marker$check', corePrefix: corePrefix, coreWidth: 0),
    for (final (childIndex, child) in item.content.indexed)
      ..._leaves(
        child,
        _siblingCoreStart(item.content, childIndex, corePrefix),
      ),
  ];
}

/// Maps a selection position — an index into [node]'s painted text leaves
/// plus a Flutter UTF-16 offset within that leaf — into the Core's canonical
/// rendered string of the Block, the UTF-16 offset space [BlockRange]
/// is expressed in (ADR-007 decision 8: the Core resolves those to source
/// offsets for splicing; the UI must map its selection ONTO this space,
/// never the reverse). Offsets inside decoration the definition does not
/// model — list markers — collapse onto the boundary they decorate.
int blockCoreRenderedOffset(
  AstNode node, {
  required int leafIndex,
  required int renderedOffset,
}) {
  final leaves = _blockLeaves(node);
  if (leafIndex < 0 || leafIndex >= leaves.length) return 0;
  final leaf = leaves[leafIndex];
  final coreOffset = (renderedOffset - leaf.leadingDecorationWidth).clamp(
    0,
    leaf.coreWidth,
  );
  return leaf.corePrefix + coreOffset;
}

String _inlineRendered(List<InlineElement> elements) =>
    elements.map(_inlineRenderedOne).join();

String _inlineRenderedOne(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) => field0.content,
  InlineElement_Link(:final content) => _inlineRendered(content),
  InlineElement_ExternalLink(:final content) => _inlineRendered(content),
};

class _InternalLink {
  const _InternalLink({
    required this.targetId,
    required this.exists,
    required this.title,
  });

  final String targetId;
  final bool exists;
  final String title;
}

List<_InternalLink> _internalLinks(AstNode node) => switch (node) {
  AstNode_Paragraph(:final content) ||
  AstNode_Heading(:final content) => _internalLinksInInlines(content),
  AstNode_List(:final items) => [
    for (final item in items) ..._internalLinks(item),
  ],
  AstNode_ListItem(:final content) => [
    for (final child in content) ..._internalLinks(child),
  ],
  AstNode_Blockquote(:final nodes) => [
    for (final child in nodes) ..._internalLinks(child),
  ],
  AstNode_Suggestion(:final localContent) => [
    for (final child in localContent) ..._internalLinks(child),
  ],
  _ => const [],
};

/// Links in the rendered siblings of a raw-focused leaf. Raw Markdown is an
/// editable source field, not an activation surface, so only the siblings
/// that still paint formatted Link text receive recognizers and keyboard
/// targets.
List<_InternalLink> _internalLinksOutsideFocusedPath(
  AstNode node,
  List<int> relativeLeafPath,
) {
  final focusedNode = _nodeAtPath(node, relativeLeafPath);
  if (focusedNode == null) return _internalLinks(node);
  final all = _internalLinks(node);
  final start = _internalLinkPrefixForPath(node, relativeLeafPath);
  final end = start + _internalLinks(focusedNode).length;
  return [
    for (final (index, link) in all.indexed)
      if (index < start || index >= end) link,
  ];
}

int _internalLinkPrefixForPath(AstNode node, List<int> path) {
  if (path.isEmpty) return 0;
  final index = path.first;
  final remaining = path.sublist(1);
  return switch (node) {
    AstNode_List(:final items) when index >= 0 && index < items.length =>
      _internalLinkCountBefore(items, index) +
          _internalLinkPrefixForPath(items[index], remaining),
    AstNode_ListItem(:final content)
        when index >= 0 && index < content.length =>
      _internalLinkCountBefore(content, index) +
          _internalLinkPrefixForPath(content[index], remaining),
    AstNode_Blockquote(:final nodes) when index >= 0 && index < nodes.length =>
      _internalLinkCountBefore(nodes, index) +
          _internalLinkPrefixForPath(nodes[index], remaining),
    AstNode_Suggestion(:final localContent)
        when index >= 0 && index < localContent.length =>
      _internalLinkCountBefore(localContent, index) +
          _internalLinkPrefixForPath(localContent[index], remaining),
    _ => 0,
  };
}

int _internalLinkCountBefore(List<AstNode> nodes, int end) => nodes
    .take(end)
    .fold(0, (count, node) => count + _internalLinks(node).length);

List<_InternalLink> _internalLinksInInlines(List<InlineElement> elements) => [
  for (final element in elements)
    if (element case InlineElement_Link(
      :final targetId,
      :final exists,
      :final content,
    ))
      _InternalLink(
        targetId: targetId,
        exists: exists,
        title: _inlineRendered(content),
      ),
];

int _inlineRenderedLength(InlineElement element) => switch (element) {
  InlineElement_Text(:final field0) => field0.content.length,
  InlineElement_Link(:final content) => _inlineRendered(content).length,
  InlineElement_ExternalLink(:final content) => _inlineRendered(content).length,
};

int _inlineRenderedLengthAll(List<InlineElement> elements) =>
    elements.fold(0, (sum, element) => sum + _inlineRenderedLength(element));

// ---------------------------------------------------------------------------
// The unfocused Block surface
// ---------------------------------------------------------------------------

/// One Block's unfocused presentation: its formatted rendering wrapped in a
/// tap detector that promotes it to the raw editable field (`EDIT-F002`,
/// ADR-006 decision 2). On tap the clicked position is resolved through the
/// painted `RenderParagraph`s — real rendered geometry, not widget-property
/// guesses — mapped to Core's canonical rendered UTF-16 offset and handed to
/// the parent ([Editor]), which asks Core for the raw caret and leaf path.
class BlockView extends StatefulWidget {
  const BlockView({
    super.key,
    required this.node,
    required this.blockPath,
    required this.onFocusRequested,
    this.onLinkActivated,
    this.focusedLeafPath,
    this.buildFocusedEditor,
    this.selectionRegistrar,
    this.recognizerFactory = TapGestureRecognizer.new,
  }) : assert(
         (focusedLeafPath == null) == (buildFocusedEditor == null),
         'A focused path and its editor builder must be supplied together.',
       );

  final AstNode node;
  final List<int> blockPath;
  final void Function(List<int> topLevelPath, int renderedUtf16Offset)
  onFocusRequested;
  final void Function(String targetId)? onLinkActivated;

  /// The one Core-resolved descendant leaf promoted to raw editing. The
  /// surrounding [BlockView] remains mounted so its other leaves retain the
  /// same pointer, keyboard, selection, and Link behaviour.
  final List<int>? focusedLeafPath;
  final Widget Function(AstNode leaf)? buildFocusedEditor;

  /// When non-null, this Block's painted text registers with it instead of
  /// directly with the enclosing [SelectionArea]'s registrar (`EDIT-F003`):
  /// a pass-through that lets the parent [Editor] know exactly which
  /// selectables belong to THIS Block and read their per-Block selection
  /// offsets, without the region knowing anything about Blocks. The
  /// forwarding preserves the region's own registration unchanged.
  final SelectionRegistrar? selectionRegistrar;

  /// Creates recognizers for rendered internal Links. Exposed for lifecycle
  /// tests so they can observe that stale recognizers are disposed.
  @visibleForTesting
  final TapGestureRecognizer Function() recognizerFactory;

  @override
  State<BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends State<BlockView> {
  // A target ID is not sufficient here: one Block may paint the same internal
  // Link more than once. The occurrence keeps each visual Link's semantics
  // geometry independent while retaining a recognizer across unrelated
  // sibling insertions/removals.
  final Map<_LinkRecognizerIdentity, TapGestureRecognizer> _linkRecognizers =
      {};
  final Map<_LinkRecognizerIdentity, FocusNode> _linkFocusNodes = {};
  final GlobalKey _textSurfaceKey = GlobalKey();
  List<_LinkSemanticBox> _linkSemanticBoxes = const [];
  int _linkSemanticsGeneration = 0;

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    for (final focusNode in _linkFocusNodes.values) {
      focusNode
        ..removeListener(_onLinkFocusChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pruneLinkRecognizers();
  }

  void _pruneLinkRecognizers() {
    final activeIdentities = widget.onLinkActivated == null
        ? const <_LinkRecognizerIdentity>{}
        : _linkIdentities(_activeLinks()).toSet();
    final obsoleteIdentities = _linkRecognizers.keys
        .where((identity) => !activeIdentities.contains(identity))
        .toList();
    for (final identity in obsoleteIdentities) {
      _linkRecognizers.remove(identity)!.dispose();
      final focusNode = _linkFocusNodes.remove(identity);
      if (focusNode != null) {
        focusNode
          ..removeListener(_onLinkFocusChanged)
          ..dispose();
      }
    }
  }

  TapGestureRecognizer _recognizerFor(_LinkRecognizerIdentity identity) =>
      _linkRecognizers.putIfAbsent(
        identity,
        () =>
            widget.recognizerFactory()
              ..onTap = () => widget.onLinkActivated?.call(identity.targetId),
      );

  FocusNode _focusNodeFor(_LinkRecognizerIdentity identity) =>
      _linkFocusNodes.putIfAbsent(identity, () {
        final focusNode = FocusNode(
          debugLabel:
              'internal-link-${identity.targetId}-${identity.occurrence}',
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onLinkActivated?.call(identity.targetId);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        );
        focusNode.addListener(_onLinkFocusChanged);
        return focusNode;
      });

  void _onLinkFocusChanged() {
    if (mounted) setState(() {});
  }

  List<_InternalLink> _activeLinks() {
    final focusedLeafPath = widget.focusedLeafPath;
    return focusedLeafPath == null
        ? _internalLinks(widget.node)
        : _internalLinksOutsideFocusedPath(widget.node, focusedLeafPath);
  }

  @override
  Widget build(BuildContext context) {
    final onLinkActivated = widget.onLinkActivated;
    final l10n = AppLocalizations.of(context);
    final links = _activeLinks();
    final linkIdentities = _linkIdentities(links);
    var renderedLinkIndex = 0;
    Widget renderInteractive(AstNode node) =>
        onLinkActivated == null || l10n == null
        ? renderBlock(node)
        : _renderBlockForView(node, (targetId, exists, content) {
            final identity = linkIdentities[renderedLinkIndex++];
            assert(identity.targetId == targetId);
            return TextSpan(
              style: TextStyle(
                color: exists ? Colors.blue : Colors.deepOrange,
                decoration: TextDecoration.underline,
                decorationStyle: exists
                    ? TextDecorationStyle.solid
                    : TextDecorationStyle.dotted,
              ),
              // Keep the Link's real nested spans. Flattening this to [title]
              // discarded bold/italic/strike/code styling and changed the
              // SelectableRegion's rendered-text shape.
              children: _linkContentWithRecognizer(
                content,
                _recognizerFor(identity),
              ),
            );
          });
    final focusedLeafPath = widget.focusedLeafPath;
    final buildFocusedEditor = widget.buildFocusedEditor;
    Widget child = focusedLeafPath == null
        ? renderInteractive(widget.node)
        : renderBlockWithFocusedLeaf(
            widget.node,
            focusedLeafPath,
            buildFocusedEditor!,
            renderUnfocused: renderInteractive,
          );
    if (widget.selectionRegistrar != null) {
      child = SelectionRegistrarScope(
        registrar: widget.selectionRegistrar!,
        child: child,
      );
    }
    _scheduleLinkSemanticsLayout(links, linkIdentities, l10n);
    return Focus(
      canRequestFocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          // A focused Block always promotes. Links have their own focus
          // targets below; Block Enter must never silently follow the first
          // Link it happens to contain.
          widget.onFocusRequested(widget.blockPath, 0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        focusable: true,
        child: GestureDetector(
          key: _textSurfaceKey,
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapUp(context, details),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Stack(
              children: [
                child,
                if (onLinkActivated != null && l10n != null)
                  for (final (linkIndex, identity) in linkIdentities.indexed)
                    for (final (boxIndex, semanticBox)
                        in _linkSemanticBoxes
                            .where((box) => box.identity == identity)
                            .indexed)
                      _InternalLinkSemanticTarget(
                        key: ValueKey(
                          boxIndex == 0
                              ? 'internal-link-focus-'
                                    '$linkIndex-${links[linkIndex].targetId}'
                              : 'internal-link-semantics-'
                                    '${semanticBox.identity.targetId}-'
                                    '${semanticBox.identity.occurrence}-$boxIndex',
                        ),
                        rect: semanticBox.rect,
                        label: semanticBox.label,
                        focusNode: boxIndex == 0
                            ? _focusNodeFor(identity)
                            : null,
                        order: linkIndex + 1,
                        focused: _focusNodeFor(identity).hasFocus,
                        onActivated: () =>
                            onLinkActivated.call(semanticBox.identity.targetId),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTapUp(BuildContext context, TapUpDetails details) {
    final renderObject = _textSurfaceKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      widget.onFocusRequested(widget.blockPath, 0);
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
      widget.onFocusRequested(
        widget.blockPath,
        blockCoreRenderedOffset(
          widget.node,
          leafIndex: index,
          renderedOffset: position.offset,
        ),
      );
      return;
    }
    // No text leaf under the pointer (a thematic break's rule, whitespace
    // beside a short line): promote with the caret at the Block's start.
    widget.onFocusRequested(widget.blockPath, 0);
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

  /// Measures the text glyphs after layout, so semantics hits exactly the
  /// rendered Link runs rather than the entire Block stack. A wrapped Link
  /// produces one target for each painted line box; that avoids making the
  /// whitespace between its lines an accidental activation target.
  void _scheduleLinkSemanticsLayout(
    List<_InternalLink> links,
    List<_LinkRecognizerIdentity> identities,
    AppLocalizations? l10n,
  ) {
    final generation = ++_linkSemanticsGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _linkSemanticsGeneration) return;
      final surface = _textSurfaceKey.currentContext?.findRenderObject();
      if (surface == null || l10n == null || links.isEmpty) {
        if (_linkSemanticBoxes.isNotEmpty) {
          setState(() => _linkSemanticBoxes = const []);
        }
        return;
      }
      final recognizerIdentities =
          <TapGestureRecognizer, _LinkRecognizerIdentity>{
            for (final entry in _linkRecognizers.entries)
              entry.value: entry.key,
          };
      final labels = <_LinkRecognizerIdentity, String>{
        for (final (index, link) in links.indexed)
          identities[index]: link.exists
              ? l10n.internalLinkExisting(link.title)
              : l10n.internalLinkMissing(link.title),
      };
      final paragraphs = <RenderParagraph>[];
      _collectParagraphs(surface, paragraphs);
      final boxesByIdentity = <_LinkRecognizerIdentity, List<Rect>>{};
      for (final paragraph in paragraphs) {
        for (final range in _linkTextRanges(
          paragraph.text,
          recognizerIdentities,
        )) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
          );
          for (final box in boxes) {
            final rect = MatrixUtils.transformRect(
              paragraph.getTransformTo(surface),
              box.toRect(),
            );
            boxesByIdentity.putIfAbsent(range.identity, () => []).add(rect);
          }
        }
      }
      final measured = <_LinkSemanticBox>[
        for (final identity in identities)
          for (final rect in _mergeAdjacentTextBoxes(
            boxesByIdentity[identity] ?? const [],
          ))
            _LinkSemanticBox(identity, labels[identity]!, rect),
      ];
      if (!_sameSemanticBoxes(_linkSemanticBoxes, measured)) {
        setState(() => _linkSemanticBoxes = measured);
      }
    });
  }
}

typedef _LinkRecognizerIdentity = ({String targetId, int occurrence});

List<_LinkRecognizerIdentity> _linkIdentities(List<_InternalLink> links) {
  final occurrences = <String, int>{};
  return [
    for (final link in links)
      (
        targetId: link.targetId,
        occurrence: occurrences.update(
          link.targetId,
          (count) => count + 1,
          ifAbsent: () => 0,
        ),
      ),
  ];
}

class _LinkTextRange {
  const _LinkTextRange(this.identity, this.start, this.end);

  final _LinkRecognizerIdentity identity;
  final int start;
  final int end;
}

List<_LinkTextRange> _linkTextRanges(
  InlineSpan root,
  Map<TapGestureRecognizer, _LinkRecognizerIdentity> recognizerIdentities,
) {
  final ranges = <_LinkTextRange>[];
  var offset = 0;

  void visit(InlineSpan span, [_LinkRecognizerIdentity? inheritedIdentity]) {
    switch (span) {
      case TextSpan(:final text, :final children, :final recognizer):
        final identity = recognizer is TapGestureRecognizer
            ? recognizerIdentities[recognizer] ?? inheritedIdentity
            : inheritedIdentity;
        if (text case final text? when text.isNotEmpty) {
          if (identity != null) {
            ranges.add(_LinkTextRange(identity, offset, offset + text.length));
          }
          offset += text.length;
        }
        for (final child in children ?? const <InlineSpan>[]) {
          visit(child, identity);
        }
      default:
        // A placeholder is one UTF-16 code unit in RenderParagraph's text.
        offset += span.toPlainText().length;
    }
  }

  visit(root);
  return ranges;
}

List<Rect> _mergeAdjacentTextBoxes(List<Rect> boxes) {
  if (boxes.length < 2) return boxes;
  final sorted = [...boxes]
    ..sort(
      (left, right) => switch (left.top.compareTo(right.top)) {
        0 => left.left.compareTo(right.left),
        final comparison => comparison,
      },
    );
  final merged = <Rect>[];
  for (final box in sorted) {
    final previous = merged.isEmpty ? null : merged.last;
    if (previous != null &&
        (previous.overlaps(box) ||
            (previous.top == box.top &&
                previous.bottom == box.bottom &&
                box.left <= previous.right + 0.5))) {
      merged
        ..removeLast()
        ..add(previous.expandToInclude(box));
    } else {
      merged.add(box);
    }
  }
  return merged;
}

class _LinkSemanticBox {
  const _LinkSemanticBox(this.identity, this.label, this.rect);

  final _LinkRecognizerIdentity identity;
  final String label;
  final Rect rect;
}

bool _sameSemanticBoxes(
  List<_LinkSemanticBox> first,
  List<_LinkSemanticBox> second,
) =>
    first.length == second.length &&
    Iterable<int>.generate(first.length).every(
      (index) =>
          first[index].identity == second[index].identity &&
          first[index].label == second[index].label &&
          first[index].rect == second[index].rect,
    );

/// Applies an internal Link's recognizer to its painted leaves, instead of an
/// empty wrapper span. Flutter's [TextSpan] hit testing visits the leaves; a
/// recognizer on each leaf preserves every nested style while making the same
/// visual text the pointer target.
List<TextSpan> _linkContentWithRecognizer(
  List<InlineElement> content,
  TapGestureRecognizer recognizer,
) => [
  for (final element in content)
    switch (element) {
      InlineElement_Text(:final field0) => TextSpan(
        text: field0.content,
        recognizer: recognizer,
        style: TextStyle(
          fontWeight: field0.bold ? FontWeight.bold : null,
          fontStyle: field0.italic ? FontStyle.italic : null,
          decoration: field0.strikethrough ? TextDecoration.lineThrough : null,
          fontFamily: field0.code ? 'monospace' : null,
        ),
      ),
      InlineElement_Link(:final content) ||
      InlineElement_ExternalLink(:final content) => TextSpan(
        recognizer: recognizer,
        children: _linkContentWithRecognizer(content, recognizer),
      ),
    },
];

/// Semantics overlay for one physical Link text box. Its custom render proxy
/// opts out of pointer hit testing, preserving TextSpan recognizers and text
/// selection beneath it while retaining [Semantics.onTap] for assistive input.
/// The first box hosts the Link's focus node, so keyboard focus, its label,
/// action, focus semantics, and visible focus indication all occupy real
/// painted glyph geometry. Wrapped boxes share the focused state and outline.
class _InternalLinkSemanticTarget extends StatelessWidget {
  const _InternalLinkSemanticTarget({
    super.key,
    required this.rect,
    required this.label,
    required this.focusNode,
    required this.order,
    required this.focused,
    required this.onActivated,
  });

  final Rect rect;
  final String label;
  final FocusNode? focusNode;
  final int order;
  final bool focused;
  final VoidCallback onActivated;

  @override
  Widget build(BuildContext context) {
    final target = _PassThroughPointer(
      child: Semantics(
        container: true,
        button: true,
        focusable: true,
        focused: focused,
        label: label,
        onTap: onActivated,
        child: DecoratedBox(
          decoration: focused
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : const BoxDecoration(),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return Positioned.fromRect(
      rect: rect,
      child: focusNode == null
          ? target
          : FocusTraversalOrder(
              order: NumericFocusOrder(order.toDouble()),
              child: Focus.withExternalFocusNode(
                focusNode: focusNode!,
                includeSemantics: false,
                child: target,
              ),
            ),
    );
  }
}

class _PassThroughPointer extends SingleChildRenderObjectWidget {
  const _PassThroughPointer({super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _PassThroughPointerRenderBox();
}

class _PassThroughPointerRenderBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}
