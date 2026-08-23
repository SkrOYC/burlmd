import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/index/query.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      value.selection.isCollapsed &&
      value.selection.baseOffset == caret &&
      value.text == source;
}

/// Parses the deliberately small completion grammar. The last `[[` must be
/// unmatched *on this line*, so brackets before a newline cannot leak into a
/// later paragraph and a closing `]]` always dismisses the affordance.
LinkCompletionSnapshot? linkCompletionSnapshot(TextEditingValue value) {
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
  LinkCompletionSnapshot? _snapshot;
  List<core.LinkCompletion> _candidates = const [];
  int _activeIndex = 0;
  int _generation = 0;

  bool get isOpen => _snapshot != null && _candidates.isNotEmpty;
  int get candidateCount => _candidates.length;

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
    if (!isOpen) return false;
    _accept(_candidates[_activeIndex]);
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
    _activeIndex = 0;
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
      setState(() => _candidates = results.take(10).toList(growable: false));
    } catch (error) {
      if (mounted && generation == _generation) {
        ref.read(editorErrorProvider.notifier).report(error);
        _dismiss();
      }
    }
  }

  void _dismiss() {
    if (_snapshot == null && _candidates.isEmpty) return;
    _generation++;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _candidates = const [];
        _activeIndex = 0;
      });
    } else {
      _snapshot = null;
      _candidates = const [];
      _activeIndex = 0;
    }
  }

  /// Returns true only for a command consumed by an open completion. This is
  /// what preserves EDIT-F004's structural Enter behavior when no popup is
  /// visible.
  bool handleKeyEvent(KeyEvent event) {
    if (!isOpen || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _activeIndex = (_activeIndex + 1) % _candidates.length);
        return true;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _activeIndex =
              (_activeIndex - 1 + _candidates.length) % _candidates.length,
        );
        return true;
      case LogicalKeyboardKey.escape:
        _dismiss();
        return true;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _accept(_candidates[_activeIndex]);
        return true;
      default:
        return false;
    }
  }

  void _accept(core.LinkCompletion candidate) {
    final snapshot = _snapshot;
    if (snapshot == null ||
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
            shrinkWrap: true,
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
