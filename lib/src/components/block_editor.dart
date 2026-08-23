import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:burlmd/src/components/link_completion.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

final _commonMarkWhitespace = RegExp(r'^[\p{Zs}\t\n\f\r]$', unicode: true);
final _commonMarkPunctuation = RegExp(r'^[\p{P}\p{S}]$', unicode: true);

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
    this.onPhantomMaterializedUpdate,
    this.smokeF005 = false,
    this.smokeF006 = false,
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

  /// Enter pressed in this field (`EDIT-F004`, CAP-EDIT-03). The parent owns
  /// both an exact raw-range deletion/replacement and the following structural
  /// split, so a selected raw range never falls through to EditableText's
  /// soft-newline insertion.
  final void Function(String source, TextSelection selection)? onEnter;

  /// Backspace pressed with a collapsed caret at source offset 0
  /// (`EDIT-F004`, CAP-EDIT-03): the parent merges this Block into its
  /// predecessor, or no-ops on the first Block.
  final VoidCallback? onBackspaceAtStart;

  /// A character was typed while this field is the empty phantom Block
  /// (`EDIT-F004`): the full field text, which becomes the new Block's
  /// `insert_block` source. Returns true only after the parent has adopted
  /// Core's returned state and replaced this phantom with the real Block.
  /// Returning false leaves the raw text mounted so the next edit can retry.
  /// When non-null, [phantom] must be true.
  final bool Function(String text)? onPhantomInsert;

  /// Carries complete platform values that arrive after a phantom's first
  /// insertion reaches Core but before Flutter rebuilds this field as the
  /// returned real Block.
  final void Function(String text, TextSelection selection)?
  onPhantomMaterializedUpdate;

  /// This field represents a not-yet-existing empty Block — the sanctioned
  /// UI-side caret position CommonMark cannot represent (`EDIT-F004`). While
  /// true, keystrokes do NOT go to `update_block` (there is no `block_path`
  /// to address); the first typed character routes through [onPhantomInsert]
  /// instead.
  final bool phantom;

  /// QA-only trigger for the F005 smoke fixture. It exercises the same raw
  /// shortcut action after this field has focused and selected its staged
  /// source; it is inert in normal editing.
  final bool smokeF005;

  /// QA-only F006 path: waits for the same valid popup normal typing opens,
  /// accepts it through the same handler as Enter, then blurs to render the
  /// Core-produced Markdown as an internal Link.
  final bool smokeF006;

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
  String? _inputGateCompositionBaseText;
  bool _pendingResolutionScheduled = false;
  bool _inputGateReconciliationScheduled = false;
  bool _hasResyncConflict = false;
  bool _phantomMaterialized = false;
  final OverlayPortalController _completionOverlayController =
      OverlayPortalController();
  final GlobalKey<LinkCompletionState> _completionKey =
      GlobalKey<LinkCompletionState>();

  /// Flutter 3.44.3 exposes [TextEditingValue.isComposingRangeValid], but a
  /// valid collapsed range is not an active composition. Only a non-empty,
  /// valid range is still owned by the IME.
  bool get _hasLiveComposition {
    final value = _controller.value;
    return value.isComposingRangeValid && !value.composing.isCollapsed;
  }

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
    _scheduleCompletionOverlay();
    if (widget.smokeF005) unawaited(_runSmokeF005Shortcut());
    if (widget.smokeF006) unawaited(_runSmokeF006Completion());
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
    // A lifecycle action may publish an authoritative replacement while a
    // platform composition is still finishing. Queue that replacement rather
    // than assigning a controller value: Flutter documents `composing` as
    // IME-owned, and clearing it here loses the marked-text commit. The gate
    // reconciliation below rebases the completed composition against this
    // exact Core source after the action settles.
    if (ref.read(editorInputBlockedProvider) ||
        _inputGateCompositionBaseText != null) {
      _queuePendingResync(
        source: widget.source,
        token: widget.resyncToken,
        base:
            _inputGateCompositionBaseText ??
            _compositionBaseText ??
            _lastSettledText,
      );
      return;
    }
    // An external change to provider state (a lifecycle rewrite adopting
    // rewritten Links, a reload) refetched this Block's source; adopt it,
    // but never stomp a live IME composition — Flutter would raise the
    // composing region out from under the platform input connection, losing
    // or duplicating exactly the characters the composition criterion
    // forbids losing. The in-flight composition completes into the field
    // first, and the next resync picks up whatever the Core then holds.
    if (_hasLiveComposition) {
      // The token is part of the pending value, rather than a separate flag:
      // a second lifecycle rewrite while the IME is still live supersedes the
      // first one. In particular, a latest source equal to the live field
      // must still replace an older, divergent pending source.
      _queuePendingResync(
        source: widget.source,
        token: widget.resyncToken,
        base: _compositionBaseText ?? _lastSettledText,
      );
      return;
    }
    if (widget.source == _controller.text) {
      _clearPendingResync();
      _lastSettledText = widget.source;
      return;
    }
    _applyExternalResync(widget.source);
  }

  void _queuePendingResync({
    required String source,
    required int token,
    required String base,
  }) {
    // The token is part of the pending value, rather than a separate flag:
    // a second external rewrite supersedes the first, even when the latest
    // source matches the field's current text.
    final pending = _pendingResync;
    if (pending == null || token > pending.token) {
      _pendingResync = _PendingResync(source: source, token: token, base: base);
    }
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
    _scheduleCompletionOverlay();
    final value = _controller.value;
    if (ref.read(editorInputBlockedProvider)) {
      // A non-empty marked range is owned by the platform. Do not rewrite the
      // editing value just because a lifecycle action has closed admission:
      // assigning [_lastSettledText] clears the range and discards the IME's
      // eventual commit. Keep its base so that a completed value can be
      // reconciled once the authoritative lifecycle result is known.
      if (_hasLiveComposition) {
        _inputGateCompositionBaseText ??=
            _compositionBaseText ?? _lastSettledText;
        return;
      }
      final compositionBase = _inputGateCompositionBaseText;
      if (compositionBase != null) {
        // Clearing a marked range can mean either commit or cancellation.
        // The base-identical form is an explicit cancellation; any different
        // text is a completed platform value retained until the gate opens.
        if (value.text == compositionBase) {
          _inputGateCompositionBaseText = null;
        }
        return;
      }
      // A platform callback can be queued before the switch's read-only
      // rebuild. Restore Core-backed text rather than leaving input solely in
      // a controller for a session being closed.
      if (value.text != _lastSettledText) {
        _controller.value = TextEditingValue(
          text: _lastSettledText,
          selection: TextSelection.collapsed(
            offset: value.selection.extentOffset.clamp(
              0,
              _lastSettledText.length,
            ),
          ),
        );
      }
      return;
    }
    if (_inputGateCompositionBaseText != null) {
      // The gate may have opened while the IME still held a marked range.
      // Its completion can change only `composing`, so the controller
      // listener (rather than EditableText.onChanged) owns this hand-off.
      if (!_hasLiveComposition && !_inputGateReconciliationScheduled) {
        _reconcileInputGateComposition();
      }
      return;
    }
    if (widget.phantom) {
      // A phantom has no Core Block to update. In particular, do not replace
      // this controller while the platform owns a marked composition: doing
      // so disposes its input connection before the IME can commit the text.
      // The controller listener, rather than onChanged, also observes the
      // common completion event that changes only `composing`.
      if (_phantomMaterialized) {
        widget.onPhantomMaterializedUpdate?.call(value.text, value.selection);
      } else if (!_hasLiveComposition && value.text.isNotEmpty) {
        // The phantom is only materialized once Core has accepted the
        // continuation and its authoritative result has been adopted. A
        // rejected first insertion must leave this raw field retryable.
        _phantomMaterialized =
            widget.onPhantomInsert?.call(value.text) ?? false;
      }
      return;
    }
    if (_hasLiveComposition) {
      _compositionBaseText ??= _lastSettledText;
      return;
    }
    if (_pendingResync == null || _pendingResolutionScheduled) return;
    _pendingResolutionScheduled = true;
    scheduleMicrotask(() {
      _pendingResolutionScheduled = false;
      if (mounted && !_hasLiveComposition) {
        _resolvePendingResync();
      }
    });
  }

  /// Re-admits a composition that began before the lifecycle gate took
  /// effect. A lifecycle refusal restores the same Core session, so the
  /// completed platform value is buffered exactly once. A successful action
  /// may have supplied a new source meanwhile; in that case the existing
  /// contiguous-edit rebase is the only safe way to preserve both changes.
  void _reconcileInputGateComposition() {
    final compositionBase = _inputGateCompositionBaseText;
    if (compositionBase == null || _hasLiveComposition) return;
    _inputGateCompositionBaseText = null;

    // An explicit cancellation restored the original source. It has no local
    // edit to replay, but an authoritative lifecycle source still wins.
    if (_controller.text == compositionBase) {
      if (_pendingResync != null) _resolvePendingResync();
      return;
    }
    if (_pendingResync != null) {
      _resolvePendingResync();
      return;
    }

    _bufferSource(_controller.text);
    _lastSettledText = _controller.text;
    _compositionBaseText = null;
  }

  /// Waits until the frame that reopens the input gate has delivered any
  /// lifecycle-owned replacement to [didUpdateWidget]. A provider listener
  /// runs as soon as its value changes, whereas the parent rebuild that
  /// carries the refetched Block source follows in the frame's build phase.
  /// Replaying a completed IME value synchronously here would therefore write
  /// the old source into a newly rewritten Core session before the child had a
  /// chance to queue that rewrite for the normal lossless rebase.
  ///
  /// A refusal or cancellation has no widget replacement. The post-frame
  /// fallback still runs in that case, so a completed composition is neither
  /// stranded nor discarded.
  void _scheduleInputGateCompositionReconciliation() {
    if (_inputGateReconciliationScheduled) return;
    _inputGateReconciliationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputGateReconciliationScheduled = false;
      if (!mounted || ref.read(editorInputBlockedProvider)) return;
      _reconcileInputGateComposition();
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
    }
    // [pending.source] was fetched from Core for this exact pending resync,
    // so equality is the only proof that the rebased result is already
    // durable there. In particular, a completed composition commonly leaves
    // [merged] equal to the field's local text while Core still holds the
    // composition base; buffering only when the controller changes would
    // silently lose those completed IME bytes.
    if (merged != pending.source) _bufferSource(merged);
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
    // OverlayPortal removes its owned overlay child during unmount. Calling
    // hide here races that teardown in Flutter 3.44.3; blur has already
    // revoked eligibility synchronously, and this disposal path leaves no
    // independently inserted OverlayEntry behind.
    _controller.removeListener(_onEditingValueChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    _scheduleCompletionOverlay();
    if (!_focusNode.hasFocus && !_hasResyncConflict) {
      widget.onFocusLost(widget.focusToken);
    }
  }

  /// Keeps the completion in the route's Overlay, rather than in the fixed
  /// promotion slot.  Flutter 3.44.3's OverlayPortal layout callback supplies
  /// the raw field's current paint transform and width, so scrolling and
  /// resizing keep the popup anchored while neither its height nor hit region
  /// participates in the Block's ListView geometry.
  void _scheduleCompletionOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final eligible =
          _focusNode.hasFocus &&
          linkCompletionSnapshot(_controller.value) != null;
      if (eligible && !_completionOverlayController.isShowing) {
        _completionOverlayController.show();
      } else if (!eligible && _completionOverlayController.isShowing) {
        _completionOverlayController.hide();
      }
    });
  }

  /// Intercepts the two structural keys before the text-editing shortcuts
  /// see them (`EDIT-F004`): this Focus sits between the editable field's
  /// node and `DefaultTextEditingShortcuts`, so returning
  /// [KeyEventResult.handled] here prevents Enter from inserting a newline
  /// byte and Backspace-at-start from deleting into this Block alone —
  /// both become Core structural operations decided by the parent.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (ref.read(editorInputBlockedProvider)) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_completionKey.currentState?.handleKeyEvent(event) ?? false) {
      return KeyEventResult.handled;
    }
    final emphasis = _emphasisShortcutFor(event);
    if (emphasis != null) {
      // A phantom has no Core-backed source span, and a resync conflict has
      // deliberately frozen writes to protect two divergent branches. In both
      // states the shortcut is consumed so EditableText/default actions cannot
      // mutate the local field or materialize/stomp either branch.
      if (widget.phantom || _hasResyncConflict) {
        return KeyEventResult.handled;
      }
      // Holding a shortcut must not turn a wrap into an immediate unwrap.
      // Flutter 3.44.3 guarantees a down followed by zero or more repeat
      // events, so only its first [KeyDownEvent] changes the raw source.
      if (event is KeyDownEvent && !_hasLiveComposition) {
        _applyEmphasis(emphasis);
      }
      // A live composing range is platform-owned. Treating its shortcut as
      // handled prevents the editable field or an ancestor action from
      // changing text, selection, or composing state behind the IME.
      return KeyEventResult.handled;
    }
    // A marked, non-collapsed composing range is owned by the platform IME.
    // In particular, an Enter or Backspace key must reach EditableText rather
    // than being mistaken for a Core split, continuation, or merge. Keep this
    // below completion and emphasis handling: those have their own explicit
    // composition semantics.
    if (_hasLiveComposition) return KeyEventResult.ignored;
    final selection = _controller.selection;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      if (widget.onEnter == null) return KeyEventResult.ignored;
      widget.onEnter!(_controller.text, selection);
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

  /// Returns a shortcut only for the platform-primary combination required
  /// by CAP-EDIT-05. Alt is intentionally never intercepted (including
  /// AltGr), and Shift is accepted only for strikethrough.
  _InlineEmphasis? _emphasisShortcutFor(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final usesMetaPrimary = defaultTargetPlatform == TargetPlatform.macOS;
    final primaryPressed = usesMetaPrimary
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final otherPrimaryPressed = usesMetaPrimary
        ? keyboard.isControlPressed
        : keyboard.isMetaPressed;
    if (!primaryPressed || otherPrimaryPressed || keyboard.isAltPressed) {
      return null;
    }
    final shiftPressed = keyboard.isShiftPressed;
    return switch (event.logicalKey) {
      LogicalKeyboardKey.keyB when !shiftPressed => _InlineEmphasis.bold,
      LogicalKeyboardKey.keyI when !shiftPressed => _InlineEmphasis.italic,
      LogicalKeyboardKey.keyE when !shiftPressed => _InlineEmphasis.code,
      LogicalKeyboardKey.keyX when shiftPressed => _InlineEmphasis.strike,
      _ => null,
    };
  }

  void _applyEmphasis(_InlineEmphasis emphasis) {
    final result = applyInlineEmphasis(
      _controller.value,
      delimiter: emphasis.delimiter,
    );
    if (result == _controller.value) return;
    // Assign one complete editing value so its text and selection advance as
    // one observable edit. The controller listener is deliberately not used
    // for buffering here: [EditableText.onChanged] only reports platform text
    // edits, while this source transformation needs exactly one Core update.
    _controller.value = result;
    _bufferSource(result.text);
    _lastSettledText = result.text;
  }

  /// Applies a Core-provided completion as one controller update and exactly
  /// one buffered Core write.  The popup never constructs a destination; it
  /// supplies only its immutable replacement result.
  void _applyLinkCompletion(String source, TextSelection selection) {
    if (ref.read(editorInputBlockedProvider) ||
        _hasResyncConflict ||
        widget.phantom) {
      return;
    }
    _controller.value = TextEditingValue(text: source, selection: selection);
    _bufferSource(source);
    _lastSettledText = source;
  }

  /// Stages a real focused raw selection, then dispatches the exact source
  /// operation used by a platform-primary shortcut. It exists solely because
  /// the smoke harness launches a release desktop application without a test
  /// binding to synthesize hardware events; readiness is still withheld until
  /// the resulting focused field and selection are visibly correct.
  Future<void> _runSmokeF005Shortcut() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
      if (_focusNode.hasFocus) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || !_focusNode.hasFocus || _hasLiveComposition) return;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _applyEmphasis(_InlineEmphasis.bold);
    unawaited(_writeSmokeF005Readiness(_controller.value));
  }

  Future<void> _runSmokeF006Completion() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
      if (_focusNode.hasFocus &&
          (_completionKey.currentState?.isOpen ?? false) &&
          (_completionKey.currentState?.isVisiblyMounted ?? false)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted ||
        !_focusNode.hasFocus ||
        !(_completionKey.currentState?.isVisiblyMounted ?? false) ||
        !(_completionKey.currentState?.acceptActiveForSmoke() ?? false)) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _focusNode.unfocus();
  }

  Future<void> _writeSmokeF005Readiness(TextEditingValue value) async {
    // Certify only after this focused raw field has painted the command's
    // transformed source and selected inner text. The shell rejects every
    // other window state, including a staged-but-unfocused editor.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_focusNode.hasFocus || _controller.value != value) return;
    // Core block sources retain their terminating newline; selecting the raw
    // Block honestly includes that byte rather than synthesizing a trimmed
    // presentation string for the smoke fixture.
    const inner = 'shortcut target\n';
    final expected = '**$inner**';
    if (value.text != expected ||
        value.selection !=
            TextSelection(baseOffset: 2, extentOffset: inner.length + 2)) {
      return;
    }
    final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
    if (readinessPath == null) return;
    try {
      File(readinessPath).writeAsStringSync('f005-focused-emphasis-shortcut\n');
    } on FileSystemException {
      // The harness turns a missing marker into a failure; the production
      // editor remains unaffected when a QA path cannot be written.
    }
  }

  TextSelection _initialSelection(String source, int caret) =>
      TextSelection.collapsed(offset: caret.clamp(0, source.length));

  @override
  Widget build(BuildContext context) {
    final inputBlocked = ref.watch(editorInputBlockedProvider);
    ref.listen<bool>(editorInputBlockedProvider, (wasBlocked, isBlocked) {
      if (wasBlocked == false && isBlocked && _hasLiveComposition) {
        // The IME candidate can have started before lifecycle work claimed the
        // gate. Preserve its Core-backed base at admission close, because a
        // read-only EditableText need not deliver another marked-value
        // callback while the gate remains held.
        _inputGateCompositionBaseText ??=
            _compositionBaseText ?? _lastSettledText;
      }
      if (wasBlocked == true && !isBlocked) {
        _scheduleInputGateCompositionReconciliation();
      }
    });
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _completionOverlayController,
      overlayChildBuilder: (context, info) {
        final origin = MatrixUtils.transformPoint(
          info.childPaintTransform,
          Offset.zero,
        );
        return Positioned(
          left: origin.dx,
          top: origin.dy + info.childSize.height + 4,
          width: info.childSize.width,
          child: LinkCompletionPopup(
            key: _completionKey,
            noteId: widget.noteId,
            controller: _controller,
            focusNode: _focusNode,
            onAccepted: _applyLinkCompletion,
          ),
        );
      },
      child: DefaultTextHeightBehavior(
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
            readOnly: inputBlocked,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            onChanged: (text) {
              if (inputBlocked) return;
              if (widget.phantom) return;
              if (_hasResyncConflict) return;
              // The Block's raw source text, not a reconstructed AstNode — this
              // is the per-keystroke buffering call (`update_block`, ADR-007
              // decision 4): no parse, no AST round trip, draft-row write only.
              // Refusals surface through keystrokeWriteFailureProvider beside the
              // content, never by replacing it (flow-edit-note.md).
              // A deferred composition resync is resolved by the controller
              // listener, including a composing-only completion. Do not race it
              // here by replaying the stale external source over this input.
              if (_pendingResync != null && !_hasLiveComposition) return;
              _bufferSource(text);
              if (!_hasLiveComposition) _lastSettledText = text;
            },
          ),
        ),
      ),
    );
  }
}

enum _InlineEmphasis {
  bold('**'),
  italic('*'),
  code('`'),
  strike('~~');

  const _InlineEmphasis(this.delimiter);

  final String delimiter;
}

/// Applies the raw-source half of CAP-EDIT-05. This deliberately knows
/// nothing about Markdown AST nodes: the Core receives exactly the selected
/// source with delimiters inserted or removed on the focused Block's span.
///
/// A selected inner run and a selection of its complete delimited run both
/// unwrap. In either direction, the returned selection covers the inner text
/// and preserves whether the original base was before or after its extent.
@visibleForTesting
TextEditingValue applyInlineEmphasis(
  TextEditingValue value, {
  required String delimiter,
}) {
  final selection = value.selection;
  if (!selection.isValid || delimiter.isEmpty) return value;
  if (delimiter == '`') return _applyInlineCode(value);
  final text = value.text;
  final base = selection.baseOffset;
  final extent = selection.extentOffset;
  if (!_isValidUtf16SelectionBoundary(text, base) ||
      !_isValidUtf16SelectionBoundary(text, extent)) {
    return value;
  }
  if (base == extent) {
    final updated = text.replaceRange(base, base, '$delimiter$delimiter');
    return TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: base + delimiter.length),
    );
  }

  final low = math.min(base, extent);
  final high = math.max(base, extent);
  final reversed = base > extent;
  final selected = text.substring(low, high);
  final surroundsInner =
      low >= delimiter.length &&
      high + delimiter.length <= text.length &&
      text.substring(low - delimiter.length, low) == delimiter &&
      text.substring(high, high + delimiter.length) == delimiter;
  final selectsFullRun =
      selected.length >= delimiter.length * 2 &&
      selected.startsWith(delimiter) &&
      selected.endsWith(delimiter);

  final canUnwrap =
      (surroundsInner &&
          _isValidEmphasisDelimiterPair(
            text,
            delimiter: delimiter,
            openingStart: low - delimiter.length,
            closingStart: high,
          ) &&
          (delimiter != '*' || _isOddStarDelimiterPair(text, low - 1, high))) ||
      (selectsFullRun &&
          _isValidEmphasisDelimiterPair(
            text,
            delimiter: delimiter,
            openingStart: low,
            closingStart: high - delimiter.length,
          ) &&
          (delimiter != '*' || _isOddStarDelimiterPair(text, low, high - 1)));

  if ((surroundsInner || selectsFullRun) && canUnwrap) {
    final outerStart = surroundsInner ? low - delimiter.length : low;
    final innerStart = outerStart;
    final innerEnd = surroundsInner
        ? high - delimiter.length
        : high - delimiter.length * 2;
    final updated = text.replaceRange(
      outerStart,
      high + (surroundsInner ? delimiter.length : 0),
      text.substring(
        innerStart + delimiter.length,
        innerEnd + delimiter.length,
      ),
    );
    final selectedStart = outerStart;
    final selectedEnd = selectedStart + (innerEnd - innerStart);
    return TextEditingValue(
      text: updated,
      selection: TextSelection(
        baseOffset: reversed ? selectedEnd : selectedStart,
        extentOffset: reversed ? selectedStart : selectedEnd,
      ),
    );
  }

  // CommonMark 0.31.2 §6.2 permits an asterisk delimiter only when the
  // generated opening and closing runs are respectively left- and
  // right-flanking. Inserting source around ` word ` or punctuation-invalid
  // adjacency would leave literal asterisks, so preserve the selection rather
  // than pretend its shortcut toggled formatting.
  if (!_canWrapWithEmphasisDelimiter(text, low, high, delimiter)) return value;

  final updated = text.replaceRange(low, high, '$delimiter$selected$delimiter');
  return TextEditingValue(
    text: updated,
    selection: TextSelection(
      baseOffset: reversed ? high + delimiter.length : low + delimiter.length,
      extentOffset: reversed ? low + delimiter.length : high + delimiter.length,
    ),
  );
}

/// Applies the code-span variant of CAP-EDIT-05.
///
/// CommonMark code spans require equal, standalone backtick runs. Their
/// contents lose one leading and trailing space when both are present (unless
/// the contents are all spaces), so source text that begins or ends in a
/// backtick or space needs one protecting space on *both* sides. The shortcut
/// chooses a delimiter longer than every selected backtick run, making the
/// transformed source parse back to precisely the selected text.
TextEditingValue _applyInlineCode(TextEditingValue value) {
  final text = value.text;
  final base = value.selection.baseOffset;
  final extent = value.selection.extentOffset;
  // Flutter selection offsets are UTF-16 code-unit offsets. Never turn a
  // malformed range (outside the text or through a surrogate pair) into a
  // different edit by clamping or splitting its character: there is no
  // lossless code-span spelling for that selection.
  if (!_isValidUtf16SelectionBoundary(text, base) ||
      !_isValidUtf16SelectionBoundary(text, extent)) {
    return value;
  }
  if (base == extent) {
    // An empty code span cannot be represented as two adjacent delimiter runs:
    // they form one backtick run. Keep the familiar paired editing placeholder;
    // it becomes a valid span as soon as the user types content between it.
    // At the edge of an existing backtick run, even that template would merge
    // with the outside source. There is no equivalent, collapsed UTF-16 edit
    // that preserves the adjacent literal run, so leave it untouched.
    if (_hasOutsideAdjacentBacktick(text, base, base)) return value;
    const delimiter = '`';
    return TextEditingValue(
      text: text.replaceRange(base, base, '$delimiter$delimiter'),
      selection: TextSelection.collapsed(offset: base + delimiter.length),
    );
  }

  final low = math.min(base, extent);
  final high = math.max(base, extent);
  final reversed = base > extent;
  final selected = text.substring(low, high);
  // CommonMark normalizes every line ending in a code span to a space. There
  // is no code-span delimiter spelling that can preserve the selected source
  // byte-for-byte, so leave a multiline selection unchanged rather than make
  // an irreversible-looking shortcut edit with different parsed content.
  if (selected.contains('\n') || selected.contains('\r')) return value;
  final unwrapped = _codeSpanAroundSelection(text, low, high);
  if (unwrapped != null) {
    return _removeCodeSpan(text, unwrapped, reversed: reversed);
  }

  final fullSpan = _fullCodeSpan(text, low, high);
  if (fullSpan != null) {
    return _removeCodeSpan(text, fullSpan, reversed: reversed);
  }

  // A delimiter next to an outside backtick run cannot be a backtick string
  // (CommonMark 0.31.2 §6.1). Choosing a longer delimiter would still merge
  // the runs, while inserting a separating character would alter unselected
  // source and its rendered text. No-op rather than make an unsafe edit.
  if (_hasOutsideAdjacentBacktick(text, low, high)) return value;

  final delimiter = '`' * (_longestBacktickRun(selected) + 1);
  final padding = _needsCodeSpanPadding(selected) ? ' ' : '';
  final replacement = '$delimiter$padding$selected$padding$delimiter';
  final updated = text.replaceRange(low, high, replacement);
  final selectedStart = low + delimiter.length + padding.length;
  final selectedEnd = selectedStart + selected.length;
  return TextEditingValue(
    text: updated,
    selection: TextSelection(
      baseOffset: reversed ? selectedEnd : selectedStart,
      extentOffset: reversed ? selectedStart : selectedEnd,
    ),
  );
}

/// A span's delimiter runs and the physical contents between them.
class _CodeSpan {
  const _CodeSpan({
    required this.start,
    required this.end,
    required this.contentStart,
    required this.contentEnd,
  });

  final int start;
  final int end;
  final int contentStart;
  final int contentEnd;
}

_CodeSpan? _codeSpanAroundSelection(String text, int low, int high) {
  for (final padded in [false, true]) {
    final openingEnd = low - (padded ? 1 : 0);
    final closingStart = high + (padded ? 1 : 0);
    if (openingEnd < 1 || closingStart >= text.length) continue;
    if (padded && (text[low - 1] != ' ' || text[high] != ' ')) {
      continue;
    }
    final openingLength = _backtickRunEndingAt(text, openingEnd);
    final closingLength = _backtickRunStartingAt(text, closingStart);
    if (openingLength == 0 || openingLength != closingLength) continue;
    final start = openingEnd - openingLength;
    final end = closingStart + closingLength;
    if (!_isStandaloneBacktickRun(text, start, openingEnd) ||
        !_isStandaloneBacktickRun(text, closingStart, end)) {
      continue;
    }
    if (!_isFirstMatchingCodeSpanCloser(
      text,
      openingEnd: openingEnd,
      delimiterLength: openingLength,
      proposedClosingStart: closingStart,
    )) {
      continue;
    }
    return _CodeSpan(
      start: start,
      end: end,
      contentStart: openingEnd,
      contentEnd: closingStart,
    );
  }
  return null;
}

_CodeSpan? _fullCodeSpan(String text, int low, int high) {
  final openingLength = _backtickRunStartingAt(text, low);
  final closingLength = _backtickRunEndingAt(text, high);
  if (openingLength == 0 || openingLength != closingLength) return null;
  final contentStart = low + openingLength;
  final contentEnd = high - closingLength;
  if (contentStart >= contentEnd ||
      !_isStandaloneBacktickRun(text, low, contentStart) ||
      !_isStandaloneBacktickRun(text, contentEnd, high)) {
    return null;
  }
  if (!_isFirstMatchingCodeSpanCloser(
    text,
    openingEnd: contentStart,
    delimiterLength: openingLength,
    proposedClosingStart: contentEnd,
  )) {
    return null;
  }
  return _CodeSpan(
    start: low,
    end: high,
    contentStart: contentStart,
    contentEnd: contentEnd,
  );
}

TextEditingValue _removeCodeSpan(
  String text,
  _CodeSpan span, {
  required bool reversed,
}) {
  final physicalContent = text.substring(span.contentStart, span.contentEnd);
  final content = _normalizedCodeSpanContent(physicalContent);
  final updated = text.replaceRange(span.start, span.end, content);
  final selectedStart = span.start;
  final selectedEnd = selectedStart + content.length;
  return TextEditingValue(
    text: updated,
    selection: TextSelection(
      baseOffset: reversed ? selectedEnd : selectedStart,
      extentOffset: reversed ? selectedStart : selectedEnd,
    ),
  );
}

bool _needsCodeSpanPadding(String selected) =>
    selected.isNotEmpty &&
    !_isAllSpaces(selected) &&
    (selected.startsWith(' ') ||
        selected.endsWith(' ') ||
        selected.startsWith('`') ||
        selected.endsWith('`'));

String _normalizedCodeSpanContent(String content) {
  if (content.length >= 2 &&
      content.startsWith(' ') &&
      content.endsWith(' ') &&
      !_isAllSpaces(content)) {
    return content.substring(1, content.length - 1);
  }
  return content;
}

bool _isAllSpaces(String text) {
  for (var index = 0; index < text.length; index++) {
    if (text[index] != ' ') return false;
  }
  return true;
}

bool _isValidUtf16SelectionBoundary(String text, int offset) {
  if (offset < 0 || offset > text.length) return false;
  if (offset == 0 || offset == text.length) return true;
  return !_isHighSurrogate(text.codeUnitAt(offset - 1)) ||
      !_isLowSurrogate(text.codeUnitAt(offset));
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

bool _hasOutsideAdjacentBacktick(String text, int low, int high) =>
    (low > 0 && text[low - 1] == '`') ||
    (high < text.length && text[high] == '`');

/// Returns whether [proposedClosingStart] is the closer CommonMark reaches
/// first for the opening run that ends at [openingEnd].
bool _isFirstMatchingCodeSpanCloser(
  String text, {
  required int openingEnd,
  required int delimiterLength,
  required int proposedClosingStart,
}) {
  var cursor = openingEnd;
  while (cursor < text.length) {
    if (text[cursor] != '`') {
      cursor++;
      continue;
    }
    final runLength = _backtickRunStartingAt(text, cursor);
    final runEnd = cursor + runLength;
    if (runLength == delimiterLength &&
        _isStandaloneBacktickRun(text, cursor, runEnd)) {
      return cursor == proposedClosingStart;
    }
    cursor = runEnd;
  }
  return false;
}

int _longestBacktickRun(String text) {
  var longest = 0;
  var current = 0;
  for (var index = 0; index < text.length; index++) {
    if (text[index] == '`') {
      current++;
      longest = math.max(longest, current);
    } else {
      current = 0;
    }
  }
  return longest;
}

int _backtickRunEndingAt(String text, int end) {
  var start = end;
  while (start > 0 && text[start - 1] == '`') {
    start--;
  }
  return end - start;
}

int _backtickRunStartingAt(String text, int start) {
  var end = start;
  while (end < text.length && text[end] == '`') {
    end++;
  }
  return end - start;
}

bool _isStandaloneBacktickRun(String text, int start, int end) =>
    start >= 0 &&
    end <= text.length &&
    start < end &&
    (start == 0 || text[start - 1] != '`') &&
    (end == text.length || text[end] != '`');

bool _canWrapWithEmphasisDelimiter(
  String text,
  int low,
  int high,
  String delimiter,
) {
  if (delimiter != '*' && delimiter != '**') return true;
  final updated = text.replaceRange(
    low,
    high,
    '$delimiter${text.substring(low, high)}$delimiter',
  );
  return _isValidEmphasisDelimiterPair(
    updated,
    delimiter: delimiter,
    openingStart: low,
    closingStart: high + delimiter.length,
  );
}

/// Checks the parser-visible delimiter runs rather than merely matching
/// punctuation text. CommonMark treats the beginning/end of a line as
/// whitespace and classifies Unicode `P` and `S` as punctuation.
bool _isValidEmphasisDelimiterPair(
  String text, {
  required String delimiter,
  required int openingStart,
  required int closingStart,
}) {
  if (delimiter != '*' && delimiter != '**') return true;
  final opening = _starRunAt(text, openingStart);
  final closing = _starRunAt(text, closingStart);
  if (opening == null || closing == null || opening.start == closing.start) {
    return false;
  }
  if (_isBackslashEscaped(text, opening.start) ||
      _isBackslashEscaped(text, closing.start)) {
    return false;
  }
  final openingFlanking = _delimiterFlanking(text, opening);
  final closingFlanking = _delimiterFlanking(text, closing);
  if (!openingFlanking.left || !closingFlanking.right) return false;

  // CommonMark rules 9 and 10: an opener/closer pair that can both open and
  // close observes the modulo-three constraint for its complete runs.
  if ((openingFlanking.right || closingFlanking.left) &&
      (opening.length + closing.length) % 3 == 0 &&
      !(opening.length % 3 == 0 && closing.length % 3 == 0)) {
    return false;
  }
  return true;
}

class _StarRun {
  const _StarRun(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

class _DelimiterFlanking {
  const _DelimiterFlanking({required this.left, required this.right});

  final bool left;
  final bool right;
}

_StarRun? _starRunAt(String text, int offset) {
  if (offset < 0 || offset >= text.length || text[offset] != '*') return null;
  var start = offset;
  var end = offset + 1;
  while (start > 0 && text[start - 1] == '*') {
    start--;
  }
  while (end < text.length && text[end] == '*') {
    end++;
  }
  return _StarRun(start, end);
}

_DelimiterFlanking _delimiterFlanking(String text, _StarRun run) {
  final before = _codePointBefore(text, run.start);
  final after = _codePointAt(text, run.end);
  final beforeWhitespace =
      before == null || _commonMarkWhitespace.hasMatch(before);
  final afterWhitespace =
      after == null || _commonMarkWhitespace.hasMatch(after);
  final beforePunctuation =
      before != null && _commonMarkPunctuation.hasMatch(before);
  final afterPunctuation =
      after != null && _commonMarkPunctuation.hasMatch(after);
  return _DelimiterFlanking(
    left:
        !afterWhitespace &&
        (!afterPunctuation || beforeWhitespace || beforePunctuation),
    right:
        !beforeWhitespace &&
        (!beforePunctuation || afterWhitespace || afterPunctuation),
  );
}

String? _codePointBefore(String text, int offset) {
  if (offset == 0) return null;
  final iterator = RuneIterator.at(text, offset);
  return iterator.movePrevious() ? iterator.currentAsString : null;
}

String? _codePointAt(String text, int offset) {
  if (offset == text.length) return null;
  final iterator = RuneIterator.at(text, offset);
  return iterator.moveNext() ? iterator.currentAsString : null;
}

bool _isBackslashEscaped(String text, int offset) {
  var count = 0;
  for (var index = offset - 1; index >= 0 && text[index] == '\\'; index--) {
    count++;
  }
  return count.isOdd;
}

/// A run of two stars is a strong delimiter, not two independent italic
/// delimiters. Odd runs represent a composed strong+italic boundary, so one
/// star can be removed from each side to toggle only the italic layer.
bool _isOddStarDelimiterPair(String text, int opening, int closing) =>
    _starRunLengthAt(text, opening).isOdd &&
    _starRunLengthAt(text, closing).isOdd;

int _starRunLengthAt(String text, int offset) {
  if (offset < 0 || offset >= text.length || text[offset] != '*') return 0;
  var start = offset;
  var end = offset + 1;
  while (start > 0 && text[start - 1] == '*') {
    start--;
  }
  while (end < text.length && text[end] == '*') {
    end++;
  }
  return end - start;
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
