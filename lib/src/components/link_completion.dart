import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/status_message.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/index/query.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A non-empty valid composing range belongs to the platform input method.
/// Flutter 3.44.3 documents that an IME owns this provisional text, including
/// during CJK candidate conversion, so completion must not replace it.
bool _hasLiveComposition(TextEditingValue value) =>
    value.isComposingRangeValid && !value.composing.isCollapsed;

/// The immutable part of an open `[[` completion.  It deliberately records
/// the whole source, rather than offsets alone: a same-length edit must be as
/// unable to accept a stale Core response as an obvious insertion is.
class LinkCompletionSnapshot {
  const LinkCompletionSnapshot({
    required this.source,
    required this.triggerStart,
    required this.caret,
    required this.query,
  });

  final String source;
  final int triggerStart;
  final int caret;
  final String query;

  bool matches(TextEditingValue value, bool hasFocus) =>
      hasFocus &&
      !_hasLiveComposition(value) &&
      value.selection.isCollapsed &&
      value.selection.baseOffset == caret &&
      value.text == source;
}

/// Parses the deliberately small completion grammar. The last `[[` must be
/// unmatched *on this line*, so brackets before a newline cannot leak into a
/// later paragraph and a closing `]]` always dismisses the affordance.
LinkCompletionSnapshot? linkCompletionSnapshot(TextEditingValue value) {
  if (_hasLiveComposition(value)) return null;
  if (!value.selection.isCollapsed) return null;
  final caret = value.selection.baseOffset;
  if (caret < 0 || caret > value.text.length) return null;
  final beforeCaret = value.text.substring(0, caret);
  final lineStart = beforeCaret.lastIndexOf('\n') + 1;
  final line = beforeCaret.substring(lineStart);
  final triggerOnLine = line.lastIndexOf('[[');
  if (triggerOnLine < 0) return null;
  // A closing delimiter after that last trigger invalidates it. An earlier
  // trigger is immaterial because the last unmatched trigger wins.
  if (line.substring(triggerOnLine + 2).contains(']]')) return null;
  final triggerStart = lineStart + triggerOnLine;
  return LinkCompletionSnapshot(
    source: value.text,
    triggerStart: triggerStart,
    caret: caret,
    query: value.text.substring(triggerStart + 2, caret),
  );
}

/// Completion popup rendered over a focused [BlockEditor]. It intentionally
/// keeps keyboard focus in the raw field: moving focus into a menu would blur
/// the field and make its own immutable snapshot stale. The active option is
/// instead exposed as focused semantics and arrow/Enter/Escape are forwarded
/// by the editor's focus node via [handleKeyEvent].
class LinkCompletionPopup extends ConsumerStatefulWidget {
  const LinkCompletionPopup({
    super.key,
    required this.noteId,
    required this.controller,
    required this.focusNode,
    required this.onAccepted,
  });

  final String noteId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String source, TextSelection selection) onAccepted;

  @override
  ConsumerState<LinkCompletionPopup> createState() => LinkCompletionState();
}

class LinkCompletionState extends ConsumerState<LinkCompletionPopup> {
  final GlobalKey _surfaceKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  LinkCompletionSnapshot? _snapshot;
  List<core.LinkCompletion> _candidates = const [];
  List<GlobalKey> _candidateKeys = const [];
  int _activeIndex = 0;
  int _generation = 0;
  int _scrollRequest = 0;
  bool _revealTowardsEnd = true;

  bool get isOpen => _snapshot != null && _candidates.isNotEmpty;
  int get candidateCount => _candidates.length;

  @visibleForTesting
  int get activeIndex => _activeIndex;

  @visibleForTesting
  ScrollController get scrollController => _scrollController;

  /// True only once the actual popup surface has been laid out. This keeps the
  /// F006 smoke hook honest: a pending Core response or an offstage widget is
  /// not evidence that a user could see or tap a completion.
  bool get isVisiblyMounted {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize;
  }

  /// QA staging is allowed to invoke the same acceptance path as Enter, but
  /// only after a real candidate list is visibly open.
  bool acceptActiveForSmoke() {
    if (!isVisiblyMounted || !_canAcceptActiveCandidate) return false;
    _acceptActiveCandidate();
    return true;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.focusNode.addListener(_refresh);
    scheduleMicrotask(_refresh);
  }

  @override
  void didUpdateWidget(covariant LinkCompletionPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_refresh);
      widget.focusNode.addListener(_refresh);
    }
    if (oldWidget.noteId != widget.noteId) _dismiss();
  }

  @override
  void dispose() {
    // Invalidate any queued reveal before releasing the controller. The
    // post-frame callback also checks [mounted], so a popup dismissed while a
    // frame is pending cannot touch a disposed ScrollPosition.
    _scrollRequest++;
    _scrollController.dispose();
    widget.controller.removeListener(_refresh);
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final next = linkCompletionSnapshot(widget.controller.value);
    if (next == null || !widget.focusNode.hasFocus) {
      _dismiss();
      return;
    }
    final current = _snapshot;
    if (current != null &&
        current.source == next.source &&
        current.triggerStart == next.triggerStart &&
        current.caret == next.caret) {
      return;
    }
    _snapshot = next;
    _candidates = const [];
    _candidateKeys = const [];
    _activeIndex = 0;
    _scrollRequest++;
    final generation = ++_generation;
    setState(() {});
    unawaited(_load(next, generation));
  }

  Future<void> _load(LinkCompletionSnapshot snapshot, int generation) async {
    try {
      final results = await ref
          .read(rustApiProvider)
          .linkCompletions(widget.noteId, snapshot.query, 10);
      // The Core has its own limit guard; retaining at most ten here protects
      // UI invariants even when an override/fake is less disciplined.
      if (!mounted || generation != _generation) return;
      if (!snapshot.matches(
        widget.controller.value,
        widget.focusNode.hasFocus,
      )) {
        _dismiss();
        return;
      }
      setState(() {
        _candidates = results.take(10).toList(growable: false);
        _candidateKeys = List.generate(
          _candidates.length,
          (_) => GlobalKey(),
          growable: false,
        );
      });
      _scheduleActiveCandidateReveal();
    } catch (error) {
      if (mounted && generation == _generation) {
        // Completion is an optional query over derived index state. Reporting
        // it through editorErrorProvider would replace the active Note, while
        // keystrokeWriteFailureProvider is reserved for failed writes; close
        // this transient affordance and leave the raw field usable instead.
        // A current failure is still actionable, so use the Editor's shared
        // dismissible status surface. A stale request must remain silent:
        // neither an old query nor an old Note may report after input moved
        // on.
        _dismiss();
        showStatusMessage(
          context,
          AppLocalizations.of(context)!.editorOperationFailed('$error'),
        );
      }
    }
  }

  void _dismiss() {
    if (_snapshot == null && _candidates.isEmpty) return;
    _generation++;
    _scrollRequest++;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _candidates = const [];
        _candidateKeys = const [];
        _activeIndex = 0;
      });
    } else {
      _snapshot = null;
      _candidates = const [];
      _candidateKeys = const [];
      _activeIndex = 0;
    }
  }

  /// Returns true only for a command consumed by an open completion. This is
  /// what preserves EDIT-F004's structural Enter behavior when no popup is
  /// visible.
  bool handleKeyEvent(KeyEvent event) {
    // Completion commands must yield to the IME while it owns provisional
    // text. This synchronous check also covers a pointer/key event that lands
    // between a controller update and the popup's next build.
    if (_hasLiveComposition(widget.controller.value)) {
      _dismiss();
      return false;
    }
    if (!isOpen || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveActiveCandidate(1);
        return true;
      case LogicalKeyboardKey.arrowUp:
        _moveActiveCandidate(-1);
        return true;
      case LogicalKeyboardKey.escape:
        _dismiss();
        return true;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        // Active selection changes synchronously, whereas its visual reveal
        // needs the next layout. The immutable input snapshot, rather than
        // paint timing, authorizes this acceptance: a rapid Arrow/Enter pair
        // must commit the logically active current-generation candidate.
        if (_canAcceptActiveCandidate) _acceptActiveCandidate();
        return true;
      default:
        return false;
    }
  }

  void _moveActiveCandidate(int delta) {
    final nextIndex =
        (_activeIndex + delta + _candidates.length) % _candidates.length;
    setState(() {
      _revealTowardsEnd = nextIndex > _activeIndex;
      _activeIndex = nextIndex;
    });
    _scheduleActiveCandidateReveal();
  }

  /// Reveals the selected rendered child after it has been laid out. Candidate
  /// titles are allowed to wrap and honor accessibility scaling, so scroll
  /// offsets must come from the actual child geometry rather than an assumed
  /// fixed row extent. The request token prevents a stale callback from
  /// touching a dismissed or disposed popup.
  void _scheduleActiveCandidateReveal() {
    final request = ++_scrollRequest;
    void reveal(bool afterJump) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != _scrollRequest || !isOpen) return;
        final candidateContext = _candidateKeys[_activeIndex].currentContext;
        if (candidateContext != null) {
          Scrollable.ensureVisible(
            candidateContext,
            alignment: 0,
            duration: Duration.zero,
          );
          return;
        }
        // A variable-height ListView only lays out children near the current
        // viewport. Move to the relevant edge once to materialize the target,
        // then use its rendered context on the following frame. At most ten
        // candidates are retained, so this never scans an unbounded list.
        if (afterJump || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        _scrollController.jumpTo(
          _revealTowardsEnd
              ? position.maxScrollExtent
              : position.minScrollExtent,
        );
        reveal(true);
      });
    }

    reveal(false);
  }

  bool get _canAcceptActiveCandidate {
    final snapshot = _snapshot;
    return snapshot != null &&
        isOpen &&
        snapshot.matches(widget.controller.value, widget.focusNode.hasFocus);
  }

  void _acceptActiveCandidate() => _accept(_candidates[_activeIndex]);

  void _accept(core.LinkCompletion candidate) {
    final snapshot = _snapshot;
    if (snapshot == null ||
        _hasLiveComposition(widget.controller.value) ||
        !snapshot.matches(widget.controller.value, widget.focusNode.hasFocus)) {
      _dismiss();
      return;
    }
    final source = snapshot.source.replaceRange(
      snapshot.triggerStart,
      snapshot.caret,
      candidate.insertText,
    );
    final offset = snapshot.triggerStart + candidate.insertText.length;
    _dismiss();
    widget.onAccepted(source, TextSelection.collapsed(offset: offset));
  }

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      label: l10n.linkCompletionLabel,
      child: Material(
        key: _surfaceKey,
        elevation: 6,
        color: Theme.of(context).colorScheme.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 216),
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: true,
            // Core caps this list at ten entries. Keeping that bounded set
            // laid out gives keyboard reveal a measured child context even
            // when titles have unequal heights.
            scrollCacheExtent: const ScrollCacheExtent.viewport(20),
            itemCount: _candidates.length,
            itemBuilder: (context, index) {
              final candidate = _candidates[index];
              final prospective = switch (candidate.kind) {
                core.LinkCompletionKind_ProspectiveGhost() => true,
                core.LinkCompletionKind_Existing() => false,
              };
              final label = prospective
                  ? l10n.linkCompletionProspective(candidate.title)
                  : l10n.linkCompletionExisting(candidate.title);
              return Semantics(
                key: _candidateKeys[index],
                button: true,
                focused: index == _activeIndex,
                label: label,
                child: InkWell(
                  key: ValueKey('link-completion-$index'),
                  onTap: () => _accept(candidate),
                  child: ListTile(
                    selected: index == _activeIndex,
                    title: Text(candidate.title),
                    trailing: prospective
                        ? Chip(label: Text(l10n.linkCompletionProspectiveBadge))
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
