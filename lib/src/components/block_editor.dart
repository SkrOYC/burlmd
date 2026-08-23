import 'dart:async';
import 'dart:math' as math;

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
    required this.onCommitEligibilityChanged,
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

  /// Publishes whether the parent may replace this focus session. A
  /// composition conflict leaves the local text intentionally unresolved, so
  /// the parent must not commit or unmount this field in response to a
  /// separate promotion or structural request.
  final void Function(int focusToken, bool canCommit)
  onCommitEligibilityChanged;

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
  final void Function(String source, int caret)? onEnter;

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
  _PendingResync? _pendingResync;
  String _lastSettledText = '';
  String? _compositionBaseText;
  bool _pendingResolutionScheduled = false;
  bool _hasResyncConflict = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.source);
    _controller.selection = _initialSelection(
      widget.source,
      widget.initialCaret,
    );
    _lastSettledText = widget.source;
    _controller.addListener(_onEditingValueChanged);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resyncToken == oldWidget.resyncToken) return;
    // An overlapping rewrite has no lossless automatic resolution. Keep its
    // two versions isolated until this field is replaced by the surrounding
    // lifecycle unmount; another arbitrary source must not silently discard
    // the text the user is being asked to copy before leaving the note.
    if (_hasResyncConflict) return;
    // An external change to provider state (a lifecycle rewrite adopting
    // rewritten Links, a reload) refetched this Block's source; adopt it,
    // but never stomp a live IME composition — Flutter would raise the
    // composing region out from under the platform input connection, losing
    // or duplicating exactly the characters the composition criterion
    // forbids losing. The in-flight composition completes into the field
    // first, and the next resync picks up whatever the Core then holds.
    if (_controller.value.composing != TextRange.empty) {
      // The token is part of the pending value, rather than a separate flag:
      // a second lifecycle rewrite while the IME is still live supersedes the
      // first one. In particular, a latest source equal to the live field
      // must still replace an older, divergent pending source.
      final pending = _pendingResync;
      if (pending == null || widget.resyncToken > pending.token) {
        _pendingResync = _PendingResync(
          source: widget.source,
          token: widget.resyncToken,
          base: _compositionBaseText ?? _lastSettledText,
        );
      }
      return;
    }
    if (widget.source == _controller.text) {
      _clearPendingResync();
      _lastSettledText = widget.source;
      return;
    }
    _applyExternalResync(widget.source);
  }

  void _applyExternalResync(String source) {
    if (source != _controller.text) {
      final caret = _controller.selection.baseOffset;
      _controller.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(
          offset: caret.clamp(0, source.length),
        ),
      );
    }
    _lastSettledText = source;
    _clearPendingResync();
  }

  /// [EditableText.onChanged] is deliberately insufficient here: in Flutter
  /// 3.44.3 it fires only when the text changes, whereas an IME can end a
  /// composition by changing only [TextEditingValue.composing]. Observe the
  /// controller so a deferred resync is resolved at the real composition
  /// boundary, before a following keystroke can consume a stale source.
  void _onEditingValueChanged() {
    final value = _controller.value;
    if (value.composing != TextRange.empty) {
      _compositionBaseText ??= _lastSettledText;
      return;
    }
    if (_pendingResync == null || _pendingResolutionScheduled) return;
    _pendingResolutionScheduled = true;
    scheduleMicrotask(() {
      _pendingResolutionScheduled = false;
      if (mounted && _controller.value.composing == TextRange.empty) {
        _resolvePendingResync();
      }
    });
  }

  void _resolvePendingResync() {
    final pending = _pendingResync;
    if (pending == null) return;

    final local = _controller.text;
    final merged = _rebaseComposition(
      base: pending.base,
      local: local,
      external: pending.source,
    );
    _clearPendingResync();

    if (merged == null) {
      // Neither side can be discarded safely. Keep the user's exact field
      // text in place and decline all later writes until a surrounding
      // lifecycle action gives this session a fresh source. This is an
      // explicit conflict state, not an implicit last-writer-wins overwrite:
      // it protects both the external Core rewrite and the IME result.
      _hasResyncConflict = true;
      // The parent owns all paths that can replace this field (promotion,
      // blur commit, and structural edits), so it needs this narrow bit of
      // session state as well as this widget's local write suppression.
      // This is synchronous while mounted; deferred resync resolution above
      // checks [mounted] before it can reach here.
      widget.onCommitEligibilityChanged(widget.focusToken, false);
      ref
          .read(keystrokeWriteFailureProvider.notifier)
          .report(
            StateError(
              'An external rewrite overlaps the active text composition. '
              'The edit remains in the field; copy it before leaving the '
              'note.',
            ),
          );
      return;
    }

    if (merged != local) {
      final caret = _controller.selection.baseOffset;
      _controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(
          offset: caret.clamp(0, merged.length),
        ),
      );
      _bufferSource(merged);
    }
    _lastSettledText = merged;
  }

  void _clearPendingResync() {
    _pendingResync = null;
    _compositionBaseText = null;
  }

  /// Applies the one contiguous local edit made from [base] to [external].
  /// The edit is accepted only when the two edits are disjoint (or already
  /// identical), which is the boundary at which reordering is provably
  /// avoidable. Overlapping rewrites are left to the explicit conflict path
  /// above rather than guessing which bytes to overwrite.
  String? _rebaseComposition({
    required String base,
    required String local,
    required String external,
  }) {
    if (local == external || local == base) return external;
    if (external == base) return local;

    final localChange = _TextChange.between(base, local);
    final externalChange = _TextChange.between(base, external);
    if (localChange == externalChange) return external;

    if (localChange.end <= externalChange.start &&
        !(localChange.isInsertionAtSameOffsetAs(externalChange))) {
      return external.replaceRange(
        localChange.start,
        localChange.end,
        localChange.replacement,
      );
    }
    if (externalChange.end <= localChange.start &&
        !(localChange.isInsertionAtSameOffsetAs(externalChange))) {
      final offsetDelta =
          externalChange.replacement.length -
          (externalChange.end - externalChange.start);
      return external.replaceRange(
        localChange.start + offsetDelta,
        localChange.end + offsetDelta,
        localChange.replacement,
      );
    }
    return null;
  }

  void _bufferSource(String source) {
    ref.read(activeNoteProvider.notifier).updateBlock(widget.blockPath, source);
  }

  @override
  void dispose() {
    _controller.removeListener(_onEditingValueChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && !_hasResyncConflict) {
      widget.onFocusLost(widget.focusToken);
    }
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
      widget.onEnter!(
        _controller.text,
        selection.baseOffset.clamp(0, _controller.text.length),
      );
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
          final composing = _controller.value.composing;
          if (widget.phantom) {
            // The empty phantom Block has no `block_path` to buffer into:
            // CommonMark has no empty paragraph, so there is nothing the
            // Core holds yet. The first typed character BECOMES the Block —
            // the parent calls `insert_block` with it and re-derives focus
            // from the returned state (`EDIT-F004`).
            widget.onPhantomInsert?.call(text);
            return;
          }
          if (_hasResyncConflict) return;
          // The Block's raw source text, not a reconstructed AstNode — this
          // is the per-keystroke buffering call (`update_block`, ADR-007
          // decision 4): no parse, no AST round trip, draft-row write only.
          // Refusals surface through keystrokeWriteFailureProvider beside the
          // content, never by replacing it (flow-edit-note.md).
          // A deferred composition resync is resolved by the controller
          // listener, including a composing-only completion. Do not race it
          // here by replaying the stale external source over this input.
          if (_pendingResync != null && composing == TextRange.empty) return;
          _bufferSource(text);
          if (composing == TextRange.empty) _lastSettledText = text;
        },
      ),
    ),
  );
}

class _PendingResync {
  const _PendingResync({
    required this.source,
    required this.token,
    required this.base,
  });

  final String source;
  final int token;
  final String base;
}

class _TextChange {
  const _TextChange({
    required this.start,
    required this.end,
    required this.replacement,
  });

  factory _TextChange.between(String before, String after) {
    var start = 0;
    final sharedLength = math.min(before.length, after.length);
    while (start < sharedLength &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }

    var beforeEnd = before.length;
    var afterEnd = after.length;
    while (beforeEnd > start &&
        afterEnd > start &&
        before.codeUnitAt(beforeEnd - 1) == after.codeUnitAt(afterEnd - 1)) {
      beforeEnd--;
      afterEnd--;
    }
    return _TextChange(
      start: start,
      end: beforeEnd,
      replacement: after.substring(start, afterEnd),
    );
  }

  final int start;
  final int end;
  final String replacement;

  bool get isInsertion => start == end;

  bool isInsertionAtSameOffsetAs(_TextChange other) =>
      isInsertion && other.isInsertion && start == other.start;

  @override
  bool operator ==(Object other) =>
      other is _TextChange &&
      start == other.start &&
      end == other.end &&
      replacement == other.replacement;

  @override
  int get hashCode => Object.hash(start, end, replacement);
}
