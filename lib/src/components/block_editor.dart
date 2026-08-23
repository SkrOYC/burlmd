import 'package:burlmd/src/providers/note_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The focused Block's raw editable field (`EDIT-F002`, ADR-006 decision 2):
/// a plain text field over the Block's raw Markdown source — `**bold**`, not
/// bold — which is the whole point of the raw-on-focus model. There is
/// deliberately no run-to-span mapping here, so the Epic B class of defects
/// (a multi-run paragraph collapsing into one flat unstyled field) is
/// structurally impossible.
///
/// Typographic stability is inherited from [blockTextStyle]'s shared style
/// factory via [style], plus two pins this widget applies itself per
/// `SPK-EDIT-F001` §3b: `maxLines: null` soft wrap at the same width the
/// rendered form occupies, and leading distribution pinned to **even**
/// through [DefaultTextHeightBehavior] — `RenderParagraph` defaults to even
/// while `RenderEditable` defaults to proportional, and left implicit that
/// shifts glyphs ~2px vertically between states at equal total height.
///
/// Content rules:
/// - Every keystroke goes to `update_block` through
///   [NoteController.updateBlock] — the Core's buffering call, which writes
///   the draft row without parsing. This widget never holds note content
///   beyond what the platform field already displays, and never calls any
///   reparsing function while focus lasts.
/// - The caret starts at [initialCaret], the source offset the user clicked.
/// - Blur-commit belongs to the parent ([Editor]), notified through
///   [onFocusLost]; the parent re-derives everything from `commit_block`'s
///   returned state, so this widget retains no path across a commit.
class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({
    super.key,
    required this.noteId,
    required this.blockPath,
    required this.source,
    required this.initialCaret,
    required this.style,
    required this.onFocusLost,
    this.resyncToken = 0,
  });

  final String noteId;
  final List<int> blockPath;

  /// The Block's current raw source, from `get_block_source` at promotion
  /// time and refreshed by the parent on an external state change.
  final String source;

  /// Source offset to place the caret at — where the user clicked before
  /// promotion.
  final int initialCaret;

  /// The Block's base style from the shared factory both presentations
  /// consume.
  final TextStyle style;

  /// Bumped by the parent whenever [source] was refetched after an external
  /// change to provider state; lets [State.didUpdateWidget] distinguish "the
  /// note changed underneath us" from an ordinary rebuild of identical
  /// inputs.
  final int resyncToken;

  /// Called when the platform reports the field lost primary focus. The
  /// parent commits the Block through `commit_block` and re-renders it
  /// formatted from the returned state.
  final void Function(List<int> blockPath) onFocusLost;

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  // Held in State so the caret doesn't jump to the end of the field on every
  // rebuild. Ephemeral edit-widget presentation state, not note content.
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.source);
    _controller.selection = _initialSelection(
      widget.source,
      widget.initialCaret,
    );
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resyncToken == oldWidget.resyncToken) return;
    // An external change to provider state (a lifecycle rewrite adopting
    // rewritten Links, a reload) refetched this Block's source; adopt it,
    // but never stomp a live IME composition — Flutter would raise the
    // composing region out from under the platform input connection, losing
    // or duplicating exactly the characters the composition criterion
    // forbids losing. The in-flight composition completes into the field
    // first, and the next resync picks up whatever the Core then holds.
    if (widget.source != _controller.text &&
        _controller.value.composing == TextRange.empty) {
      final caret = _controller.selection.baseOffset;
      _controller.value = TextEditingValue(
        text: widget.source,
        selection: TextSelection.collapsed(
          offset: caret.clamp(0, widget.source.length),
        ),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) widget.onFocusLost(widget.blockPath);
  }

  TextSelection _initialSelection(String source, int caret) =>
      TextSelection.collapsed(offset: caret.clamp(0, source.length));

  @override
  Widget build(BuildContext context) => DefaultTextHeightBehavior(
    // SPK-EDIT-F001 §3b: pin leading distribution to even. RenderParagraph
    // (the formatted path) defaults to even; RenderEditable defaults to
    // proportional — unpinned, glyphs wobble ~2px at every promotion.
    textHeightBehavior: const TextHeightBehavior(
      leadingDistribution: TextLeadingDistribution.even,
    ),
    // A bare EditableText rather than TextField: TextField's InputDecorator
    // imposes a 48px minimum height on the field, which would make every
    // single-line Block visibly grow at promotion — precisely the movement
    // SPK-EDIT-F001 §3b forbids. The decorator adds nothing this editor
    // wants (no label, hint, border or counter), so the field goes straight
    // to the text-painting render object and inherits no minimum.
    child: EditableText(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      style: widget.style,
      cursorColor: Theme.of(context).colorScheme.primary,
      backgroundCursorColor: Colors.grey,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      onChanged: (text) {
        // The Block's raw source text, not a reconstructed AstNode — this
        // is the per-keystroke buffering call (`update_block`, ADR-007
        // decision 4): no parse, no AST round trip, draft-row write only.
        // Refusals surface through keystrokeWriteFailureProvider beside the
        // content, never by replacing it (flow-edit-note.md).
        ref
            .read(activeNoteProvider.notifier)
            .updateBlock(widget.blockPath, text);
      },
    ),
  );
}
