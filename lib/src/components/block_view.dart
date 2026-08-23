import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, SelectionRegistrar;
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

/// Renders a top-level container while replacing exactly one descendant leaf
/// with its raw editor. The container's siblings, marker/border decoration,
/// and layout remain the normal formatted rendering; only Core's resolved
/// leaf path may become editable.
Widget renderBlockWithFocusedLeaf(
  AstNode node,
  List<int> relativeLeafPath,
  Widget Function(AstNode leaf) buildEditor,
) {
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
      blockContainer(
        node,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, item) in items.indexed)
              index == childIndex
                  ? switch (item) {
                      AstNode_ListItem(:final content) when index == 0 =>
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (contentIndex, child) in content.indexed)
                              contentIndex == remaining.first
                                  ? renderBlockWithFocusedLeaf(
                                      child,
                                      remaining.sublist(1),
                                      buildEditor,
                                    )
                                  : renderBlock(child),
                          ],
                        ),
                      AstNode_ListItem(:final content, :final checked) =>
                        _renderFocusedListItem(
                          content,
                          checked,
                          ordered ? '${index + 1}.' : '•',
                          remaining,
                          buildEditor,
                        ),
                      _ => renderBlockWithFocusedLeaf(
                        item,
                        remaining,
                        buildEditor,
                      ),
                    }
                  : switch (item) {
                      AstNode_ListItem(:final content, :final checked)
                          when index > 0 =>
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
    AstNode_ListItem(:final content, :final checked)
        when childIndex >= 0 && childIndex < content.length =>
      _renderFocusedListItem(
        content,
        checked,
        '•',
        relativeLeafPath,
        buildEditor,
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
                  ? renderBlockWithFocusedLeaf(child, remaining, buildEditor)
                  : renderBlock(child),
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
                ? renderBlockWithFocusedLeaf(child, remaining, buildEditor)
                : renderBlock(child),
        ],
      ),
    _ => renderBlock(node),
  };
}

Widget _renderFocusedListItem(
  List<AstNode> content,
  bool? checked,
  String marker,
  List<int> relativeLeafPath,
  Widget Function(AstNode leaf) buildEditor,
) => Row(
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
                  )
                : renderBlock(child),
        ],
      ),
    ),
  ],
);

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
class BlockView extends StatelessWidget {
  const BlockView({
    super.key,
    required this.node,
    required this.blockPath,
    required this.onFocusRequested,
    this.selectionRegistrar,
  });

  final AstNode node;
  final List<int> blockPath;
  final void Function(List<int> topLevelPath, int renderedUtf16Offset)
  onFocusRequested;

  /// When non-null, this Block's painted text registers with it instead of
  /// directly with the enclosing [SelectionArea]'s registrar (`EDIT-F003`):
  /// a pass-through that lets the parent [Editor] know exactly which
  /// selectables belong to THIS Block and read their per-Block selection
  /// offsets, without the region knowing anything about Blocks. The
  /// forwarding preserves the region's own registration unchanged.
  final SelectionRegistrar? selectionRegistrar;

  @override
  Widget build(BuildContext context) {
    Widget child = renderBlock(node);
    if (selectionRegistrar != null) {
      child = SelectionRegistrarScope(
        registrar: selectionRegistrar!,
        child: child,
      );
    }
    return Focus(
      canRequestFocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          // Keyboard promotion uses the same Core-backed top-level coordinate
          // path as a pointer on the rendered Block. It never synthesizes a
          // raw source offset or nested leaf path in Presentation.
          onFocusRequested(blockPath, 0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        focusable: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapUp(context, details),
          child: child,
        ),
      ),
    );
  }

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
        blockCoreRenderedOffset(
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
