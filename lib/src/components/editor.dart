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
    final error = ref.watch(editorErrorProvider);
    // The Core refused an operation on the active Note (open failed, a close
    // on switch aborted it, or update_block rejected an edit). Surfaced here
    // rather than swallowed: before SHEL-E004 this widget had no error
    // surface at all, so every such failure was invisible to the user.
    if (error != null) return _ErrorSurface(message: '$error');
    final note = ref.watch(activeNoteProvider);
    if (note == null) return const SizedBox.shrink();
    // ListView.builder rather than a `children:` list, so only the blocks
    // actually scrolled into view get built — a note with hundreds of blocks
    // shouldn't rebuild every one of them on every keystroke just because
    // `update_block` returns the full AST (see architecture/risks.md #1/#3).
    return ListView.builder(
      itemCount: note.ast.length,
      itemBuilder: (context, i) => _buildBlock(note.ast[i], [i]),
    );
  }
}

/// Only a single-run Paragraph (exactly one plain-or-styled
/// [InlineElement_Text], no Links) is live-editable via [_EditableParagraph];
/// every other node — multi-run paragraphs included — renders read-only via
/// [renderBlock]. A [TextField] can only apply one uniform [TextStyle], so a
/// multi-run paragraph (e.g. plain text followed by a bold word) made
/// editable this way would silently flatten to a single style and lose every
/// distinction a reader relies on — caught visually (a real `flutter run`,
/// not just `flutter test`) when a mixed-run paragraph rendered with no
/// bold/italic/code distinction at all. Dispatching here (rather than inside
/// a stateful wrapper every block passes through) keeps the
/// [TextEditingController] lifecycle — and the cursor-preserving `State` it
/// requires — confined to blocks that actually need it, instead of every
/// block on every note allocating and disposing one on each keystroke
/// rebuild (see `architecture/risks.md` #1/#3). Full rich multi-run inline
/// editing (splitting a styled run mid-string while preserving neighboring
/// formatting and cursor position) is materially larger than this ticket's
/// scope.
Widget _buildBlock(AstNode node, List<int> blockPath) => switch (node) {
  AstNode_Paragraph(:final content) when _isSingleTextRun(content) =>
    _EditableParagraph(content: content, blockPath: blockPath),
  _ => renderBlock(node),
};

/// A paragraph is only safe to make editable via a single-style [TextField]
/// when it has exactly one run and that run is plain text (not a Link) — see
/// [_buildBlock]'s doc comment for why a multi-run paragraph must stay
/// read-only instead.
bool _isSingleTextRun(List<InlineElement> content) =>
    content.length == 1 && content.single is InlineElement_Text;

/// A live-editable single-run paragraph. `content` is guaranteed by
/// [_buildBlock]'s [_isSingleTextRun] guard to be exactly one
/// [InlineElement_Text] run, never a Link.
class _EditableParagraph extends ConsumerStatefulWidget {
  const _EditableParagraph({required this.content, required this.blockPath});

  final List<InlineElement> content;
  final List<int> blockPath;

  @override
  ConsumerState<_EditableParagraph> createState() => _EditableParagraphState();
}

class _EditableParagraphState extends ConsumerState<_EditableParagraph> {
  // Held in State (rather than rebuilt every keystroke) so the cursor
  // doesn't jump to the end of the field on every rebuild. This is ephemeral
  // edit-widget presentation state, not note content, so it doesn't violate
  // the "stateless regarding content" rule — the content itself still comes
  // only from `activeNoteProvider`.
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _singleRunText(widget.content));
  }

  @override
  void didUpdateWidget(covariant _EditableParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter reuses this State for the block at the same list index across
    // rebuilds. `updateBlock` no longer writes this field's own keystrokes
    // back into `activeNoteProvider`'s state (see the notifier's doc
    // comment), so typing here never itself triggers a rebuild — but any
    // *other* reason `activeNoteProvider`'s state changes (switching notes,
    // a future insert_block/delete_block reindexing positions, a
    // reload/commit) rebuilds `Editor` and hands every visible block a
    // freshly decoded, structurally new `content` object, even for blocks
    // whose text didn't actually change. Resync only when the incoming text
    // actually differs from what the field currently shows, so an edit
    // elsewhere in the note can't reset this field's cursor to the end of
    // unrelated, unchanged text; it only overwrites the field on a
    // genuinely external content change.
    final incomingText = _singleRunText(widget.content);
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
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    // Deriving the field's style from the (only) run keeps a single-run
    // paragraph visibly bold/italic/etc. while editable.
    style: _paragraphStyle(widget.content),
    decoration: const InputDecoration(border: InputBorder.none),
    onChanged: (text) {
      // The Block's raw source text, not a reconstructed AstNode — WSPC-D008
      // replaces the AST-based `update_block` with the contract's
      // source-text version (ADR-007 decision 4).
      //
      // EDIT-F002 is now load-bearing for *correctness*, not only for looks,
      // and the reason is that this field is populated from the rendered
      // inline run rather than from `get_block_source`. `**bold**` reaches
      // the controller as `bold`, so the first keystroke sends a Block source
      // with the delimiters already gone. Under WSPC-D008 that no longer stops
      // at a redraw: `update_block` splices the text into the Note's working
      // source, ADR-008 tier 1 writes it to the draft row, and tier 2's idle
      // timer writes that to the file — so the formatting is dropped from the
      // user's Markdown on disk, not merely from this frame. Raw-on-focus
      // editing (EDIT-F002), which populates the field from `get_block_source`
      // and hands the delimiters back verbatim, is what closes it. Fixing it
      // here would mean threading the Note's id into this widget and
      // re-deriving the field's text and its resync comparison from the Core,
      // which is that ticket's work rather than a line of it. And the deferred
      // surface is wider than "unstyled": `updateBlock` is `#[frb(sync)]` and
      // therefore throws synchronously on every refusal the Core can raise —
      // an unaddressable or container `block_path`, a conflicted Note, a failed
      // draft write. Those refusals ARE caught and reported, though:
      // `NoteController.updateBlock` funnels them into [editorErrorProvider],
      // which [Editor]'s build renders as the persistent error surface
      // (`SHEL-E004`), so a refused keystroke is visible to the user rather
      // than silently dropped.
      ref.read(activeNoteProvider.notifier).updateBlock(widget.blockPath, text);
    },
  );
}

/// The editor's error surface (`SHEL-E004`): a persistent, readable panel
/// naming what the Core reported, shown in place of note content until the
/// next successful open clears [editorErrorProvider]. Scrollable and
/// soft-wrapped so even a long Rust-side message can neither overflow nor
/// clip.
class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, semanticLabel: 'Error'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Something went wrong talking to the note core',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(message),
            ],
          ),
        ),
      ),
    ),
  );
}

String _singleRunText(List<InlineElement> content) =>
    (content.single as InlineElement_Text).field0.content;

/// Derives a single [TextStyle] for an editable paragraph field from its
/// (only, per [_isSingleTextRun]) run's formatting — a `TextField` can't
/// apply per-character rich styling the way [renderInline]'s `TextSpan` tree
/// can.
TextStyle _paragraphStyle(List<InlineElement> content) {
  final run = (content.single as InlineElement_Text).field0;
  return TextStyle(
    fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
    decoration: run.strikethrough
        ? TextDecoration.lineThrough
        : TextDecoration.none,
    fontFamily: run.code ? 'monospace' : null,
  );
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
