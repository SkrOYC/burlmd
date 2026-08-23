import 'package:burlmd/src/providers/note_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

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
    required this.focusToken,
    required this.onFocusLost,
    this.resyncToken = 0,
    this.phantom = false,
    this.onEnter,
    this.onBackspaceAtStart,
    this.onPhantomInsert,
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
  /// formatted from the returned state — unless [focusToken] no longer names
  /// the parent's current focus session, in which case this field is a stale
  /// generation being replaced (a phantom converting to a real Block, a
  /// split's second half) and the blur must commit nothing.
  final void Function(int focusToken) onFocusLost;

  /// Identifies the focus session this field belongs to (`EDIT-F004`). The
  /// parent mints a fresh token for every `_Focus` generation; echoing it
  /// back through [onFocusLost] lets the parent tell "the user blurred this
  /// field" from "this field was replaced by a newer generation", which a
  /// path comparison alone cannot distinguish when both share a path.
  final int focusToken;

  /// Enter pressed in this field (`EDIT-F004`, CAP-EDIT-03): the caret's
  /// source offset at press time. The parent decides between splitting the
  /// Block mid-text and opening an empty phantom Block at its end. Only
  /// fired for a collapsed selection; a non-collapsed selection lets the
  /// platform delete it first.
  final void Function(int caret)? onEnter;

  /// Backspace pressed with a collapsed caret at source offset 0
  /// (`EDIT-F004`, CAP-EDIT-03): the parent merges this Block into its
  /// predecessor, or no-ops on the first Block.
  final VoidCallback? onBackspaceAtStart;

  /// A character was typed while this field is the empty phantom Block
  /// (`EDIT-F004`): the full field text, which becomes the new Block's
  /// `insert_block` source. When non-null, [phantom] must be true.
  final void Function(String text)? onPhantomInsert;

  /// This field represents a not-yet-existing empty Block — the sanctioned
  /// UI-side caret position CommonMark cannot represent (`EDIT-F004`). While
  /// true, keystrokes do NOT go to `update_block` (there is no `block_path`
  /// to address); the first typed character routes through [onPhantomInsert]
  /// instead.
  final bool phantom;

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
    if (!_focusNode.hasFocus) widget.onFocusLost(widget.focusToken);
  }

  /// Intercepts the two structural keys before the text-editing shortcuts
  /// see them (`EDIT-F004`): this Focus sits between the editable field's
  /// node and `DefaultTextEditingShortcuts`, so returning
  /// [KeyEventResult.handled] here prevents Enter from inserting a newline
  /// byte and Backspace-at-start from deleting into this Block alone —
  /// both become Core structural operations decided by the parent.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final selection = _controller.selection;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // A non-collapsed selection is the platform's to delete first; the
      // user pressing Enter again then hits the collapsed path below.
      if (!selection.isCollapsed || widget.onEnter == null) {
        return KeyEventResult.ignored;
      }
      widget.onEnter!(selection.baseOffset.clamp(0, _controller.text.length));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        selection.isCollapsed &&
        selection.baseOffset == 0 &&
        widget.onBackspaceAtStart != null) {
      widget.onBackspaceAtStart!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    // The key-event intercept sits directly above the field so Enter and
    // Backspace-at-start reach [_handleKeyEvent] before any text-editing
    // shortcut (`EDIT-F004`).
    child: Focus(
      onKeyEvent: _handleKeyEvent,
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
          if (widget.phantom) {
            // The empty phantom Block has no `block_path` to buffer into:
            // CommonMark has no empty paragraph, so there is nothing the
            // Core holds yet. The first typed character BECOMES the Block —
            // the parent calls `insert_block` with it and re-derives focus
            // from the returned state (`EDIT-F004`).
            widget.onPhantomInsert?.call(text);
            return;
          }
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
    ),
  );
}
