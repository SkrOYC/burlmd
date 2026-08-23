import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/components/lifecycle_actions.dart';
import 'package:burlmd/src/components/range_text_input_client.dart';
import 'package:burlmd/src/components/status_message.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        ClearSelectionEvent,
        SelectedContent,
        SelectedContentRange,
        Selectable,
        SelectionRegistrar;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

/// A frozen cross-Block target owned by the editor's input proxy. Ordinary
/// selections retain their public Core [BlockRange] coordinates; Select All
/// is a distinct Core operation because an empty terminal rendering has no
/// rendered offset that can name the end of its source.
sealed class _RangeTarget {
  const _RangeTarget();
}

class _RenderedRangeTarget extends _RangeTarget {
  const _RenderedRangeTarget(this.range);

  final BlockRange range;
}

class _WholeNoteRangeTarget extends _RangeTarget {
  const _WholeNoteRangeTarget();
}

/// Renders the currently open note's AST as Live Preview (`EDIT-F002`,
/// CAP-EDIT-01): every Block renders formatted, except the one holding the
/// caret, which displays its raw Markdown source in an editable field.
///
/// Stateless regarding note content: the AST is read from
/// [activeNoteProvider], keystrokes flow out through `update_block` (the
/// buffering call), and blur flows out through `commit_block`, whose
/// returned state replaces the provider's state and from which focus is
/// re-derived — never retained across a commit, because a splice can change
/// a Block's node shape (a paragraph gaining a leading list marker reparses
/// as a list). The only content-adjacent state held here is the focused
/// path, its fetched source text, and the clicked caret offset. Selection
/// coordinates are ephemeral UI state (`EDIT-F003`, CAP-EDIT-04) and are
/// held by Flutter's [SelectionArea] itself, not by this container at all;
/// this widget reads them only transiently to build a [BlockRange] for a
/// copy request.
class Editor extends ConsumerStatefulWidget {
  const Editor({super.key});

  @override
  ConsumerState<Editor> createState() => EditorState();
}

class EditorState extends ConsumerState<Editor> {
  /// The currently promoted Block, or null while every Block renders
  /// formatted.
  _Focus? _focused;

  /// Set whenever a raw field is promoted. A pointer sequence that began in
  /// that field may blur it while being dragged across rendered content; its
  /// SelectionArea callbacks arrive after blur but still originated in raw
  /// source. No Core range may use that sequence. The next pointer-down that
  /// begins with no focused Block explicitly establishes a fresh rendered
  /// selection epoch.
  bool _requiresFreshRenderedSelection = false;

  /// Per-Block pass-through registrars (`EDIT-F003`): each unfocused Block's
  /// painted text registers with its own broker so this container can read
  /// that Block's selection offsets without the selection system knowing
  /// anything about Blocks. Keyed by block index; entries whose selectables
  /// dispose unregister themselves.
  final Map<int, _BlockSelectionBroker> _selectionBrokers = {};

  /// The direct platform proxy active only for a rendered cross-Block range.
  /// The range itself is frozen in the proxy; a subsequent selection, focus,
  /// source, or Note transition revokes it before any stale callback can edit.
  RangeTextInputClient<_RangeTarget>? _rangeInputClient;
  int _rangeGeneration = 0;
  NoteState? _rangeState;
  String? _rangeNoteId;

  /// A Link resolution is valid only for the Note and activation that started
  /// it. The index call is asynchronous, so an older tap must not navigate a
  /// Note the user has since left (or override a newer Link activation).
  int _linkRequestGeneration = 0;

  /// Overrides the region's default copy with the Core-produced Markdown
  /// path (CAP-EDIT-04); see [_CopyRangeAsMarkdownAction].
  late final Action<CopySelectionTextIntent> _copyAction =
      _CopyRangeAsMarkdownAction(this);

  /// Overrides Flutter's mounted-selectable-only Select All with a
  /// Note-authoritative selection. The native SelectionArea action still
  /// paints every mounted leaf; Core receives the complete Note range when
  /// copy follows, including blocks a lazy ListView has not materialized.
  late final Action<SelectAllTextIntent> _selectAllAction =
      _SelectWholeNoteAction(this);

  late final Action<DeleteCharacterIntent> _deleteCharacterAction =
      _RangeDeleteAction<DeleteCharacterIntent>(this);
  late final Action<DeleteToNextWordBoundaryIntent> _deleteWordAction =
      _RangeDeleteAction<DeleteToNextWordBoundaryIntent>(this);
  late final Action<DeleteToLineBreakIntent> _deleteLineAction =
      _RangeDeleteAction<DeleteToLineBreakIntent>(this);
  late final Action<PasteTextIntent> _pasteAction = _RangePasteAction(this);

  /// The Note for which Select All is currently authoritative. This is UI
  /// interaction state, not retained Note content; a pointer gesture or focus
  /// promotion clears it and returns range resolution to live selectables.
  String? _wholeNoteSelectedId;

  /// A context inside the [SelectionArea], captured during build; lets the
  /// smoke hook invoke select-all the way the keyboard shortcut does.
  BuildContext? _areaContext;

  @override
  void initState() {
    super.initState();
    if (Platform.environment.containsKey('BURLMD_SMOKE_F002')) {
      _runSmokePromote();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F001')) {
      _runSmokeF001();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F003')) {
      unawaited(_runSmokeF003());
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F004')) {
      unawaited(_runSmokeF004());
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F005')) {
      unawaited(_runSmokeF005());
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F006')) {
      unawaited(_runSmokeF006());
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F007')) {
      unawaited(_runSmokeF007());
    }
  }

  @override
  void dispose() {
    _closeRangeInput();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A provider transition can happen before Flutter schedules this widget's
    // rebuild. Listen at the provider boundary so a queued platform callback
    // cannot reuse the old rendered selection against the new Note in that
    // gap. The selection system may retain its own visual range until build;
    // clear both its selectables and the Note-authoritative Select All marker.
    ref.listen<NoteState?>(activeNoteProvider, (previous, next) {
      if (!identical(previous, next)) _invalidateRenderedRange();
    });
    ref.listen<bool>(editorInputBlockedProvider, (_, inputBlocked) {
      if (inputBlocked) _closeRangeInput();
    });
    ref.listen<Object?>(noteCloseFailureProvider, (_, failure) {
      if (failure == null) return;
      final message = AppLocalizations.of(context)!.noteCloseFailed('$failure');
      // Acknowledge before scheduling the UI update so provider changes cannot
      // replay this status on a rebuild. The SnackBar stays dismissible.
      ref.read(noteCloseFailureProvider.notifier).acknowledge();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showStatusMessage(context, message);
      });
    });
    final error = ref.watch(editorErrorProvider);
    final note = ref.watch(activeNoteProvider);
    // An opening failure has no active session to retain, so it owns the pane.
    // A close failure is acknowledged above with a nonfatal SnackBar; its old
    // Core session stays mounted once the switch gate is released. A refused
    // *keystroke* write is deliberately NOT routed here — it would blank the
    // text the user is typing; WriteTierNotice surfaces it above the editor.
    if (error != null && note == null) return _ErrorSurface(message: '$error');
    if (note == null) {
      _invalidateRenderedRange();
      _focused = null;
      return const SizedBox.shrink();
    }
    if (_rangeInputClient != null && !_isRangeStateCurrent()) {
      _invalidateRenderedRange();
    }
    // A different Note opened while a Block was focused: drop focus rather
    // than carry the edit session across. Refetching by path would be wrong
    // here — a same-indexed Block in the new Note is not the Block the user
    // was editing, and silently retargeting focus at it would point the
    // buffered keystrokes of one Note at another's source row.
    if (_focused != null && _focused!.noteId != note.metadata.id) {
      _closeRangeInput();
      _focused = null;
      _selectionBrokers.clear();
    }
    // Brokers past the end of the AST (a commit shrank the Note) are dead
    // weight; their selectables unregister themselves on dispose.
    _selectionBrokers.removeWhere((index, _) => index >= note.ast.length);
    // An external change to provider state while a Block is focused (a
    // lifecycle operation adopting rewritten Links, a reload) refetches that
    // Block's source so the field can never keep pre-rewrite bytes whose
    // next keystroke would revert a Core-side rewrite from a buffer the Core
    // does not own (see LifecycleEffects.rewritten's contract note).
    final focused = _focused; // re-read: the id check above may have cleared it
    if (focused != null && !identical(focused.lastSeenState, note)) {
      _closeRangeInput();
      if (focused.isPhantom) {
        // A phantom Block holds no Core-side source row to refetch
        // (`EDIT-F004`) — it exists nowhere but here. Re-anchor only.
        focused.lastSeenState = note;
      } else {
        try {
          focused.source = ref
              .read(rustApiProvider)
              .getBlockSource(note.metadata.id, focused.path);
          focused.resyncToken++;
          focused.lastSeenState = note;
        } catch (_) {
          // The refetch failed (the path may no longer exist after a
          // structural change). Drop focus rather than edit against a dead
          // path; the failure itself surfaces through the next boundary error
          // report.
          _focused = null;
        }
      }
    }
    // ListView.builder rather than a `children:` list, so only the blocks
    // actually scrolled into view get built — a note with hundreds of blocks
    // shouldn't rebuild every one of them just because a blur-commit returns
    // the full AST (see architecture/risks.md #1/#3).
    //
    // The list sits inside ONE SelectionArea (`EDIT-F003`, CAP-EDIT-04): the
    // unfocused Blocks participate in a single selection region, so a drag
    // can span them and select-all covers the whole Note. Per
    // SPK-EDIT-F001 §3c a focused EditableText does NOT participate in the
    // region at all (verified on Flutter 3.44.3), so a cross-Block selection
    // exists only while no Block holds focus — which is exactly why every
    // `BlockRange` offset is a rendered offset over unfocused Blocks and no
    // focused-endpoint case is needed. The Actions wrapper above the area
    // overrides its default copy with the Core-produced Markdown path.
    //
    // One extra slot while a phantom Block is open (`EDIT-F004`,
    // CAP-EDIT-03): the empty Block Enter created and CommonMark cannot
    // represent. It renders at the phantom's ANCHOR — directly beneath the
    // Block Enter was pressed in, exactly where `continue_block_after` will
    // splice it — not past the whole AST; only a phantom opened after the last
    // Block lands visually at the bottom. An EMPTY Note gets one slot
    // permanently — otherwise there would be nothing to click or type into
    // to start composing.
    final focusedForSlot = _focused;
    final phantomSlot =
        note.ast.isEmpty || (focusedForSlot?.isPhantom ?? false);
    // The phantom's insert index: the slot after its anchor's top-level
    // container. The focus path stays the real leaf for Core continuation;
    // this is presentation-only placement, so a nested leaf still renders its
    // phantom beneath the containing top-level Block.
    final phantomAnchor =
        focusedForSlot?.phantomInsertionIndex ??
        (note.ast.isEmpty && focusedForSlot?.isPhantom != true
            ? 0
            : math.min(
                (focusedForSlot?.path.first ?? -1) + 1,
                note.ast.length,
              ));
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: _copyAction,
        SelectAllTextIntent: _selectAllAction,
        DeleteCharacterIntent: _deleteCharacterAction,
        DeleteToNextWordBoundaryIntent: _deleteWordAction,
        DeleteToLineBreakIntent: _deleteLineAction,
        PasteTextIntent: _pasteAction,
      },
      child: Listener(
        onPointerDown: (_) {
          _closeRangeInput();
          _wholeNoteSelectedId = null;
          if (_focused == null) _requiresFreshRenderedSelection = false;
        },
        child: SelectionArea(
          onSelectionChanged: _handleRenderedSelectionChanged,
          child: Builder(
            builder: (areaContext) {
              // Captured for the smoke hook's select-all invocation; reading
              // it during build keeps it current across rebuilds.
              _areaContext = areaContext;
              return ListView.builder(
                itemCount: note.ast.length + (phantomSlot ? 1 : 0),
                itemBuilder: (context, i) => phantomSlot && i == phantomAnchor
                    ? _buildPhantomEntry(note)
                    // Slots past the phantom shift back by one onto their
                    // real Block index.
                    : _buildEntry(
                        context,
                        note,
                        phantomSlot && i > phantomAnchor ? i - 1 : i,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, NoteState note, int index) {
    final path = [index];
    // One stable wrapper per entry so tests (and the layout) can address a
    // Block's slot regardless of which presentation currently fills it.
    return KeyedSubtree(
      key: ValueKey('entry-$index'),
      child: _buildEntryInner(context, note, path, index),
    );
  }

  Widget _buildEntryInner(
    BuildContext context,
    NoteState note,
    List<int> path,
    int index,
  ) {
    final focused = _focused;
    final broker = _selectionBrokers.putIfAbsent(
      index,
      _BlockSelectionBroker.new,
    );
    broker.parent = SelectionContainer.maybeOf(context);
    // A phantom's path names its anchor slot (the index a new Block would
    // splice into), which can coincide numerically with a real Block's
    // index — so the phantom must never satisfy this early-out; the
    // `isPhantom` guard keeps the two identities apart.
    if (focused != null &&
        !focused.isPhantom &&
        _pathStartsWith(focused.path, path)) {
      final relativeLeafPath = focused.path.sublist(path.length);
      broker.leafIndices = blockUnfocusedLeafIndices(
        note.ast[index],
        relativeLeafPath,
      );
      return BlockView(
        key: ValueKey('block-$index'),
        node: note.ast[index],
        blockPath: path,
        onFocusRequested: _promote,
        onLinkActivated: (targetId) => unawaited(_followInternalLink(targetId)),
        focusedLeafPath: relativeLeafPath,
        buildFocusedEditor: (leaf) => BlockEditor(
          key: ValueKey('edit-${focused.path.join('-')}'),
          noteId: note.metadata.id,
          blockPath: focused.path,
          source: focused.source,
          initialCaret: focused.caret,
          style: blockTextStyle(leaf),
          resyncToken: focused.resyncToken,
          focusToken: focused.token,
          onEnter: (source, caret) =>
              _handleEnterRequested(focused.path, source, caret),
          onBackspaceAtStart: () => _handleBackspaceAtStart(focused.path),
          onFocusLost: _handleFieldBlur,
          onCommitEligibilityChanged: _handleCommitEligibilityChanged,
          smokeF005:
              Platform.environment.containsKey('BURLMD_SMOKE_F005') &&
              note.metadata.title == 'F005 emphasis',
          smokeF006:
              Platform.environment.containsKey('BURLMD_SMOKE_F006') &&
              note.metadata.title == 'F006 link completion',
        ),
        selectionRegistrar: broker,
      );
    }
    // Unfocused Blocks join the shared selection region through their own
    // pass-through registrar, so this container knows exactly which painted
    // selectables belong to THIS Block (`EDIT-F003`). While a Block IS
    // focused, its field does not register with the region at all
    // (SPK-EDIT-F001 §3c), which is what keeps a focused endpoint impossible.
    broker.leafIndices = List<int>.generate(
      blockRenderedLeafCount(note.ast[index]),
      (leafIndex) => leafIndex,
    );
    return BlockView(
      key: ValueKey('block-$index'),
      node: note.ast[index],
      blockPath: path,
      onFocusRequested: _promote,
      onLinkActivated: (targetId) => unawaited(_followInternalLink(targetId)),
      selectionRegistrar: broker,
    );
  }

  /// Follows an internal Link through the Core at activation time. The AST's
  /// `exists` bit never appears here: it is an advisory rendering affordance,
  /// and a stale Note can only be followed safely from this fresh sealed
  /// resolution.
  Future<void> _followInternalLink(String targetId) async {
    if (ref.read(editorInputBlockedProvider)) return;
    final origin = ref.read(activeNoteProvider);
    if (origin == null) return;
    final request = ++_linkRequestGeneration;
    final linkContext = context;
    try {
      final api = ref.read(rustApiProvider);
      final resolution = await api.resolveLinkTarget(targetId);
      if (!linkContext.mounted || !_isCurrentLinkRequest(request, origin)) {
        return;
      }
      switch (resolution) {
        case LinkTargetResolution_Existing(:final noteId):
          ref.read(selectedNoteIdProvider.notifier).select(noteId);
        case LinkTargetResolution_Missing(
          :final targetId,
          :final directoryPath,
          :final title,
        ):
          await _offerCreateLinkedNote(
            linkContext,
            targetId: targetId,
            directoryPath: directoryPath,
            title: title,
            request: request,
            origin: origin,
          );
      }
    } catch (error) {
      if (linkContext.mounted && _isCurrentLinkRequest(request, origin)) {
        _reportLinkOperationFailure(linkContext, error);
      }
    }
  }

  bool _isCurrentLinkRequest(int request, NoteState origin) {
    final current = ref.read(activeNoteProvider);
    return mounted &&
        !ref.read(editorInputBlockedProvider) &&
        request == _linkRequestGeneration &&
        identical(current, origin) &&
        current?.metadata.id == origin.metadata.id;
  }

  Future<void> _offerCreateLinkedNote(
    BuildContext context, {
    required String targetId,
    required String directoryPath,
    required String title,
    required int request,
    required NoteState origin,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.createLinkedNoteTitle),
        content: Text(l10n.createLinkedNoteBody(title, directoryPath)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.createLinkedNoteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.createLinkedNoteConfirm),
          ),
        ],
      ),
    );
    if (accepted != true || !_isCurrentLinkRequest(request, origin)) return;
    try {
      // `targetId` comes only from the fresh Core resolution above. Dart does
      // not derive a title, directory, or replacement identity here. The
      // lifecycle action keeps the editor read-only through the outgoing
      // close and incoming open, so this warning cannot arrive before the
      // authoritative created session is active.
      final outcome = await ref
          .read(lifecycleActionsProvider)
          .createLinkTarget(targetId);
      if (!context.mounted) return;
      switch (outcome) {
        case LifecycleCompleted(:final warning) when warning != null:
          final message = switch (warning.stage) {
            LifecycleWarningStage.commit => l10n.lifecycleCommitWarning(
              warning.detail,
            ),
            LifecycleWarningStage.settlement => l10n.lifecycleSettlementWarning(
              warning.detail,
            ),
          };
          if (context.mounted) showStatusMessage(context, message);
        case LifecycleCompleted():
          return;
        case LifecycleRefused(:final reason)
            when _isCurrentLinkRequest(request, origin):
          _reportLinkOperationFailure(context, StateError(reason));
        case LifecycleFailed(:final error)
            when _isCurrentLinkRequest(request, origin):
          _reportLinkOperationFailure(context, error);
        case LifecycleRefused() || LifecycleFailed():
          return;
      }
    } catch (error) {
      if (context.mounted && _isCurrentLinkRequest(request, origin)) {
        _reportLinkOperationFailure(context, error);
      }
    }
  }

  /// Link resolution and target creation are retryable actions. They do not
  /// invalidate the source Note, so use the dismissible status surface rather
  /// than replacing that Note with the fatal open/close error panel.
  void _reportLinkOperationFailure(BuildContext context, Object error) {
    if (!context.mounted) return;
    showStatusMessage(
      context,
      AppLocalizations.of(context)!.linkOperationFailed('$error'),
    );
  }

  /// Promotes the Core-resolved editable leaf for a top-level rendered
  /// coordinate. Flutter never estimates source punctuation or nested paths.
  void _promote(List<int> topLevelPath, int renderedUtf16Offset) {
    if (ref.read(editorInputBlockedProvider)) return;
    // A phantom focus shares its numeric path with a real Block (both name
    // the same index), so the phantom must never satisfy this early-out —
    // clicking a Block while a phantom is open promotes that Block.
    if (_focused != null &&
        !_focused!.isPhantom &&
        _pathEquals(_focused!.path, topLevelPath)) {
      return;
    }
    // An overlapping IME/external rewrite has no safe automatic winner.
    // Keep the conflicted raw field mounted and its exact local bytes
    // copyable; neither a pointer nor keyboard promotion may erase it by
    // committing or replacing the session. The only recovery is explicit:
    // copy the local branch, then deliberately leave the note rather than
    // silently choosing either version here.
    if (!_canReplaceFocusedSession) return;
    _closeRangeInput();
    // Moving focus between Blocks commits the outgoing one first: its last
    // buffered text must reach the working source before anything else
    // reads the Note, and blur is the commit point (ADR-006, ADR-008).
    if (_focused != null && !_commitFocused()) return;
    final note = ref.read(activeNoteProvider);
    if (note == null ||
        topLevelPath.length != 1 ||
        topLevelPath.first >= note.ast.length) {
      return;
    }
    try {
      final api = ref.read(rustApiProvider);
      final caret = api.resolveBlockCaret(
        note.metadata.id,
        topLevelPath,
        renderedUtf16Offset,
      );
      final path = caret.blockPath.map((part) => part.toInt()).toList();
      final source = api.getBlockSource(note.metadata.id, path);
      setState(() {
        // A SelectionArea can retain its last registered selection while this
        // entry is being replaced. It described the old rendered tree, so it
        // cannot become a BlockRange after promotion; a range must be dragged
        // anew after the next blur+commit cycle.
        _selectionBrokers.clear();
        _requiresFreshRenderedSelection = true;
        _wholeNoteSelectedId = null;
        _focused = _Focus(
          noteId: note.metadata.id,
          path: path,
          source: source,
          caret: caret.caretOffset.toInt(),
          lastSeenState: note,
        );
      });
    } catch (error) {
      _reportEditorOperationFailure(error);
    }
  }

  /// Blur handler from the promoted field: commits unless focus already
  /// moved elsewhere — including the case where this field is a stale
  /// generation being REPLACED (a phantom converting to a real Block after
  /// its first character, a split's second half). A path comparison cannot
  /// tell those apart when both generations share a path, so the field
  /// echoes back the focus-session token it was created with; only a match
  /// against the current session commits.
  void _handleFieldBlur(int focusToken) {
    if (_focused == null || _focused!.token != focusToken) return;
    _invalidateSmokeF002Readiness();
    _invalidateSmokeF005Readiness();
    _commitFocused();
  }

  /// Mirrors [BlockEditor]'s conflict guard at the owner of focus state.
  /// The token prevents a stale, just-disposed field generation from changing
  /// the eligibility of a newer session at the same structural path.
  void _handleCommitEligibilityChanged(int focusToken, bool canCommit) {
    final focused = _focused;
    if (focused == null || focused.token != focusToken) return;
    focused.canCommit = canCommit;
  }

  bool get _canReplaceFocusedSession => _focused?.canCommit ?? true;

  /// A changed SelectionArea value is the sole activation boundary for the
  /// ephemeral proxy. The snapshot is constructed once and retained verbatim;
  /// no lazy-list re-read can silently shorten Select All or retarget an edit.
  ///
  /// A top-level container such as a List or Blockquote can paint several
  /// selectable leaves. A selection crossing those leaves is a range edit
  /// even though both Core endpoints have the same top-level path. The
  /// brokers expose that live, UI-owned extent directly; do not infer it by
  /// parsing Markdown or by treating every noncollapsed single-leaf selection
  /// as a range.
  void _handleRenderedSelectionChanged(SelectedContent? _) {
    if (ref.read(editorInputBlockedProvider)) {
      _closeRangeInput();
      return;
    }
    final target = _selectedRangeTarget();
    if (target == null || !_isRangeInputEligible(target)) {
      _closeRangeInput();
      return;
    }
    _activateRangeInput(target);
  }

  void _activateRangeInput(_RangeTarget target) {
    if (ref.read(editorInputBlockedProvider)) return;
    final existing = _rangeInputClient;
    if (existing != null && _sameRangeTarget(existing.range, target)) return;

    _closeRangeInput();
    final state = ref.read(activeNoteProvider);
    if (state == null) return;
    final noteId = state.metadata.id;
    final generation = ++_rangeGeneration;
    final client = RangeTextInputClient(
      range: target,
      onReplace: (replacement) =>
          _replaceFrozenRange(generation, target, state, noteId, replacement),
      onDelete: () => _deleteFrozenRange(generation, target, state, noteId),
      copyMarkdown: () => _copyFrozenRange(generation, target, state, noteId),
      onError: (error) {
        if (_isLiveRange(generation, target, state, noteId)) {
          _reportEditorOperationFailure(error);
        }
      },
    );
    _rangeInputClient = client;
    _rangeState = state;
    _rangeNoteId = noteId;
    client.attach();
  }

  bool _isRangeInputEligible(_RangeTarget target) => switch (target) {
    _WholeNoteRangeTarget() => true,
    _RenderedRangeTarget(:final range) =>
      range.startPath.length == 1 &&
          range.endPath.length == 1 &&
          (range.startPath.single != range.endPath.single ||
              _selectedLeafCount() > 1),
  };

  /// The selection system, rather than the Markdown tree, is authoritative
  /// about which rendered leaves the user visibly selected. A same-top-level
  /// range is eligible only when that live extent crosses multiple leaves.
  /// A collapsed edge still participates: dragging from exactly the end of
  /// one List or Blockquote leaf into its sibling leaves the origin leaf with
  /// a zero-width [SelectedContentRange], but it remains a real endpoint of
  /// the cross-leaf range.
  int _selectedLeafCount() => _selectionBrokers.values
      .expand((broker) => broker.selectables)
      .where((selectable) => selectable.getSelection() != null)
      .length;

  /// A range edit, copy, or promotion can be refused without invalidating
  /// the Note currently mounted in the editor. Keep that Note available and
  /// report the retryable operation through the shared, dismissible status
  /// surface instead of [editorErrorProvider], whose panel is only visible
  /// when no Note is open.
  void _reportEditorOperationFailure(Object error) {
    if (!mounted) return;
    showStatusMessage(
      context,
      AppLocalizations.of(context)!.editorOperationFailed('$error'),
    );
  }

  static bool _sameRange(BlockRange a, BlockRange b) =>
      a.startPath.length == b.startPath.length &&
      a.endPath.length == b.endPath.length &&
      a.startPath.indexed.every((entry) => entry.$2 == b.startPath[entry.$1]) &&
      a.endPath.indexed.every((entry) => entry.$2 == b.endPath[entry.$1]) &&
      a.startOffset == b.startOffset &&
      a.endOffset == b.endOffset;

  static bool _sameRangeTarget(_RangeTarget a, _RangeTarget b) =>
      switch ((a, b)) {
        (_WholeNoteRangeTarget(), _WholeNoteRangeTarget()) => true,
        (
          _RenderedRangeTarget(:final range),
          _RenderedRangeTarget(range: final rangeB),
        ) =>
          _sameRange(range, rangeB),
        _ => false,
      };

  bool _isLiveRange(
    int generation,
    _RangeTarget target,
    NoteState state,
    String noteId,
  ) =>
      mounted &&
      !ref.read(editorInputBlockedProvider) &&
      generation == _rangeGeneration &&
      _rangeInputClient != null &&
      _sameRangeTarget(_rangeInputClient!.range, target) &&
      _isRangeStateCurrent(state, noteId);

  bool _isRangeStateCurrent([NoteState? state, String? noteId]) {
    final current = ref.read(activeNoteProvider);
    final capturedState = state ?? _rangeState;
    final capturedId = noteId ?? _rangeNoteId;
    return capturedState != null &&
        capturedId != null &&
        identical(current, capturedState) &&
        current?.metadata.id == capturedId;
  }

  void _closeRangeInput() {
    _rangeGeneration++;
    _rangeInputClient?.close();
    _rangeInputClient = null;
    _rangeState = null;
    _rangeNoteId = null;
  }

  /// Revokes both sources of selection authority. This is deliberately safe
  /// before build: old selectables can still be mounted briefly after the
  /// provider changes, but they can no longer recreate a range or Select All
  /// marker for the replacement state.
  void _invalidateRenderedRange() {
    _closeRangeInput();
    _clearRenderedSelection();
    _requiresFreshRenderedSelection = true;
  }

  Future<String> _copyFrozenRange(
    int generation,
    _RangeTarget target,
    NoteState state,
    String noteId,
  ) async {
    if (!_isLiveRange(generation, target, state, noteId)) return '';
    final api = ref.read(rustApiProvider);
    return switch (target) {
      _WholeNoteRangeTarget() => api.copyWholeNoteAsMarkdown(noteId),
      _RenderedRangeTarget(:final range) => api.copyRangeAsMarkdown(
        noteId,
        range,
      ),
    };
  }

  Future<void> _replaceFrozenRange(
    int generation,
    _RangeTarget target,
    NoteState state,
    String noteId,
    String replacement,
  ) async {
    if (!_isLiveRange(generation, target, state, noteId)) return;
    final api = ref.read(rustApiProvider);
    final result = switch (target) {
      _WholeNoteRangeTarget() => api.replaceWholeNote(noteId, replacement),
      _RenderedRangeTarget(:final range) => api.replaceRange(
        noteId,
        range,
        replacement,
      ),
    };
    if (!_isLiveRange(generation, target, state, noteId)) return;
    _adoptRangeResult(result);
  }

  Future<void> _deleteFrozenRange(
    int generation,
    _RangeTarget target,
    NoteState state,
    String noteId,
  ) async {
    if (!_isLiveRange(generation, target, state, noteId)) return;
    final api = ref.read(rustApiProvider);
    final result = switch (target) {
      _WholeNoteRangeTarget() => api.deleteWholeNote(noteId),
      _RenderedRangeTarget(:final range) => api.deleteRange(noteId, range),
    };
    if (!_isLiveRange(generation, target, state, noteId)) return;
    _adoptRangeResult(result);
  }

  /// Applies the Core postcondition by exhaustive caret pattern matching.
  /// Paths and offsets are never derived from the old selected Blocks.
  void _adoptRangeResult(RangeEditResult result) {
    // A successful atomic mutation is already authoritative. Publish it and
    // revoke the frozen platform proxy before attempting optional source
    // hydration: otherwise a failed `get_block_source` would strand the old
    // selection/input client on a mutation that Core has already applied,
    // making a stale platform callback able to replay the operation.
    ref.read(activeNoteProvider.notifier).adopt(result.state);
    _clearRenderedSelection();
    _closeRangeInput();

    final api = ref.read(rustApiProvider);
    try {
      final nextFocus = switch (result.caret) {
        RangeEditCaret_Block(:final blockPath, :final sourceOffsetUtf16) =>
          _Focus(
            noteId: result.state.metadata.id,
            path: blockPath.map((part) => part.toInt()).toList(),
            source: api.getBlockSource(
              result.state.metadata.id,
              blockPath.map((part) => part.toInt()).toList(),
            ),
            caret: sourceOffsetUtf16.toInt(),
            lastSeenState: result.state,
          ),
        RangeEditCaret_Phantom(:final insertionIndex) => _Focus(
          noteId: result.state.metadata.id,
          path: [insertionIndex.toInt()],
          source: '',
          caret: 0,
          lastSeenState: result.state,
          isPhantom: true,
          phantomInsertionIndex: insertionIndex.toInt(),
        ),
      };
      if (mounted) setState(() => _focused = nextFocus);
    } catch (error) {
      // The mutation is durable even when the optional raw-source fetch is
      // unavailable. Fall back to the authoritative rendered state rather
      // than leaving an editable field pointed at an unhydrated path.
      if (mounted) {
        setState(() => _focused = null);
        _reportEditorOperationFailure(error);
      }
    }
  }

  void _clearRenderedSelection() {
    for (final broker in _selectionBrokers.values) {
      for (final selectable in broker.selectables) {
        selectable.dispatchSelectionEvent(const ClearSelectionEvent());
      }
    }
    _selectionBrokers.clear();
    _wholeNoteSelectedId = null;
  }

  /// Commits the focused Block through `commit_block`: the Core reparses its
  /// working source, rebuilds the span map, and returns the authoritative
  /// state, which is adopted wholesale. Focus is then cleared rather than
  /// re-targeted from the retained path — the returned AST may have reshaped
  /// the edited Block (a paragraph retyped to begin with `- ` becomes a
  /// list), so nothing survives the commit except the returned state
  /// itself.
  bool _commitFocused() {
    if (ref.read(editorInputBlockedProvider)) return false;
    final focused = _focused;
    if (focused == null || !focused.canCommit) return false;
    _closeRangeInput();
    if (focused.isPhantom) {
      // The sanctioned phantom Block is UI-side caret state ONLY (`EDIT-F004`):
      // CommonMark has no empty paragraph, so there is nothing to commit and
      // no `block_path` to address. Focus leaving it without anything typed
      // simply discards it; the Note is unchanged.
      _clearFocusedAfterCommit();
      return true;
    }
    final note = ref.read(activeNoteProvider);
    if (note == null) return false;
    try {
      final newState = ref
          .read(rustApiProvider)
          .commitBlock(note.metadata.id, focused.path);
      _clearFocusedAfterCommit();
      ref.read(activeNoteProvider.notifier).adopt(newState);
      return true;
    } catch (error) {
      // A refused commit leaves the Core's working source holding whatever
      // `update_block` already buffered. Keep that exact field mounted and
      // refocus it: clearing focus before the Core accepts would discard the
      // user's only visible raw source. Selection brokers stay untouched, so
      // the fresh-rendered-selection rule remains in force.
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
      _restoreFocusedField(focused);
      return false;
    }
  }

  void _clearFocusedAfterCommit() {
    setState(() {
      _focused = null;
      // Do not retain a range that crossed the field while it was focused.
      // `commit_block` reparses its source and this empty broker set requires
      // a fresh rendered SelectionArea gesture before a range can be sent to
      // the Core (ADR-006 / SPK-EDIT-F001).
      _selectionBrokers.clear();
      _wholeNoteSelectedId = null;
    });
  }

  void _restoreFocusedField(_Focus focused) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_focused, focused)) return;
      FocusNode? fieldFocus;
      void visit(Element element) {
        if (fieldFocus != null) return;
        final widget = element.widget;
        if (widget is EditableText && !widget.readOnly) {
          fieldFocus = widget.focusNode;
          return;
        }
        element.visitChildElements(visit);
      }

      context.visitChildElements(visit);
      fieldFocus?.requestFocus();
    });
  }

  static bool _pathEquals(List<int> a, List<int> b) =>
      a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);

  static bool _pathStartsWith(List<int> path, List<int> prefix) =>
      path.length >= prefix.length &&
      prefix.indexed.every((entry) => path[entry.$1] == entry.$2);

  /// Editable paths are structural addresses, not top-level list indices.
  /// Re-derive them from the Core-returned AST after any reparsing mutator so
  /// a list or quote leaf never becomes a synthetic `[index +/- 1]` path.
  static List<List<int>> _leafPaths(List<AstNode> ast) => [
    for (final (index, node) in ast.indexed) ..._leafPathsIn(node, [index]),
  ];

  static List<List<int>> _leafPathsIn(AstNode node, List<int> path) =>
      switch (node) {
        AstNode_List(:final items) => [
          for (final (index, child) in items.indexed)
            ..._leafPathsIn(child, [...path, index]),
        ],
        AstNode_ListItem(:final content) => [
          for (final (index, child) in content.indexed)
            ..._leafPathsIn(child, [...path, index]),
        ],
        AstNode_Blockquote(:final nodes) => [
          for (final (index, child) in nodes.indexed)
            ..._leafPathsIn(child, [...path, index]),
        ],
        AstNode_Suggestion(:final localContent) => [
          for (final (index, child) in localContent.indexed)
            ..._leafPathsIn(child, [...path, index]),
        ],
        _ => [path],
      };

  static List<int>? _previousLeafPath(NoteState state, List<int> path) {
    final leaves = _leafPaths(state.ast);
    final current = leaves.indexWhere(
      (candidate) => _pathEquals(candidate, path),
    );
    return current > 0 ? leaves[current - 1] : null;
  }

  // -- Block creation, splitting and merging (EDIT-F004, CAP-EDIT-03) ------
  //
  // Every structural change goes through a Core mutator and the returned
  // state is adopted wholesale — the same rule blur-commit already follows.
  // The single sanctioned exception is the empty phantom Block: CommonMark
  // has no empty paragraph, so an empty continuation would leave no
  // `block_path` for the first keystroke to address. It lives as UI-side caret
  // position until the first text arrives, at which point that text is passed
  // to Core's `continue_block_after` boundary.

  /// The phantom Block slot: an empty raw-editable field styled as a
  /// paragraph, rendered at its anchor index — directly beneath the Block
  /// Enter was pressed in ([Editor.build]). Also the permanent first
  /// line of an EMPTY Note, which is the only way composing can begin
  /// there.
  Widget _buildPhantomEntry(NoteState note) {
    final path = _focused?.path ?? const [0];
    const node = AstNode.paragraph(content: []);
    return KeyedSubtree(
      key: const ValueKey('entry-phantom'),
      child: BlockEditor(
        key: const ValueKey('edit-phantom'),
        noteId: note.metadata.id,
        blockPath: path,
        source: '',
        initialCaret: 0,
        style: blockTextStyle(node),
        focusToken: _focused?.token ?? -1,
        phantom: true,
        // Enter in a still-empty phantom cannot be represented in CommonMark
        // (no empty paragraph), so it does nothing; Backspace at its start
        // has nothing behind it. Both are explicit no-ops.
        onEnter: (_, _) {},
        onBackspaceAtStart: () {},
        onPhantomInsert: _handlePhantomInsert,
        onPhantomMaterializedUpdate: _handlePhantomMaterializedUpdate,
        onFocusLost: _handleFieldBlur,
        onCommitEligibilityChanged: _handleCommitEligibilityChanged,
      ),
    );
  }

  /// Enter pressed in the focused Block at source offset [caret]. At the
  /// Block's end this opens the empty phantom Block after it. If the raw field
  /// changed, it first commits and adopts the preceding real Block exactly
  /// once, so abandoning the phantom cannot reveal a stale provider AST.
  /// Mid-Block it splits through `split_block`, adopting the returned state
  /// and re-deriving focus onto the second half with the caret at its start.
  void _handleEnterRequested(List<int> blockPath, String source, int caret) {
    if (ref.read(editorInputBlockedProvider)) return;
    final focused = _focused;
    if (focused == null ||
        !focused.canCommit ||
        focused.isPhantom ||
        !_pathEquals(focused.path, blockPath)) {
      return;
    }
    final note = ref.read(activeNoteProvider);
    if (note == null) return;
    final clamped = caret.clamp(0, source.length);
    // "End of the Block" means only whitespace remains after the caret.
    // Core sources carry a terminating newline (spans.rs `block_source`
    // contract), so this covers caret-at-length AND the caret sitting just
    // before that invisible trailing newline — both are the visual end of
    // the Block. This holds for EVERY Block, not just the last one, so the
    // phantom below must be able to open mid-document.
    if (source.substring(clamped).trim().isEmpty) {
      var committedState = note;
      var continuationPath = List<int>.from(blockPath);
      // `update_block` deliberately leaves the provider AST stale while the
      // field is raw. Before replacing that real field with a phantom, repair
      // it through Core and retain only an address derived from Core state.
      if (source != focused.source) {
        try {
          final api = ref.read(rustApiProvider);
          committedState = api.commitBlock(note.metadata.id, blockPath);
          continuationPath = _rederiveContinuationPath(
            api,
            note.metadata.id,
            note,
            committedState,
            blockPath,
            source,
          );
          ref.read(activeNoteProvider.notifier).adopt(committedState);
        } catch (error) {
          ref.read(keystrokeWriteFailureProvider.notifier).report(error);
          return;
        }
      }
      setState(() {
        _focused = _Focus(
          noteId: focused.noteId,
          // The phantom remembers the editable leaf Enter came from. Core
          // owns the continuation decision: a List leaf gets a sibling item,
          // while a Blockquote leaf exits to a top-level Block. Flutter must
          // not guess from the path's nesting shape.
          path: continuationPath,
          source: '',
          caret: 0,
          lastSeenState: committedState,
          isPhantom: true,
        );
      });
      return;
    }
    try {
      final api = ref.read(rustApiProvider);
      final structural = api.splitBlock(
        note.metadata.id,
        blockPath,
        source,
        clamped,
      );
      final newState = structural.state;
      ref.read(activeNoteProvider.notifier).adopt(newState);
      final secondPath = structural.blockPath
          .map((part) => part.toInt())
          .toList();
      final secondHalf = api.getBlockSource(note.metadata.id, secondPath);
      setState(() {
        _focused = _Focus(
          noteId: note.metadata.id,
          path: secondPath,
          source: secondHalf,
          caret: structural.caretOffset.toInt().clamp(0, secondHalf.length),
          lastSeenState: newState,
        );
      });
    } catch (error) {
      // A split refusal leaves the focused raw source as the only editable
      // representation of this operation. Keep it mounted and surface the
      // failure beside it, just like a refused merge or blur commit.
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
    }
  }

  /// Resolves the real continuation anchor after [commitBlock] reparses a
  /// buffered edit. Retain the old address only when Core still reports that
  /// exact focused raw source there. A path can survive while its old source
  /// region expands into several top-level Blocks, so address survival alone
  /// is not evidence of identity. Otherwise locate the first unchanged
  /// following top-level region from the authoritative pre/post ASTs, then
  /// resolve the end of the region before it through Core. This intentionally
  /// does not inspect or parse Markdown in Dart.
  List<int> _rederiveContinuationPath(
    RustApi api,
    String noteId,
    NoteState previousState,
    NoteState state,
    List<int> previousPath,
    String committedSource,
  ) {
    final paths = _leafPaths(state.ast);
    if (paths.any((path) => _pathEquals(path, previousPath))) {
      // The source comes from Core's current span map, not from a Dart
      // Markdown interpretation. A mismatch means the old numeric path now
      // addresses only one fragment of the focused field's source region.
      final survivingSource = api.getBlockSource(noteId, previousPath);
      if (survivingSource == committedSource) {
        return List<int>.from(previousPath);
      }
    }
    final originalTopLevelIndex = previousPath.first;
    if (originalTopLevelIndex >= previousState.ast.length) {
      throw StateError('Focused Block has no prior top-level region.');
    }
    final followingRegionCount = _unchangedFollowingTopLevelRegionCount(
      previousState.ast,
      state.ast,
      originalTopLevelIndex,
    );
    final topLevelIndex = state.ast.length - followingRegionCount - 1;
    if (topLevelIndex < 0) {
      throw StateError('Committed Block produced no continuation anchor.');
    }
    return api
        .resolveBlockCaret(noteId, [
          topLevelIndex,
        ], blockCoreRenderedLength(state.ast[topLevelIndex]))
        .blockPath
        .map((part) => part.toInt())
        .toList();
  }

  /// Counts the unchanged suffix after the focused top-level region. A
  /// `commit_block` reparses only the working source; later source regions
  /// retain their AST projection, so this is a Core-state identity boundary,
  /// not a Markdown heuristic. The resulting boundary makes the new phantom
  /// follow every top-level Block emitted from the focused raw field.
  static int _unchangedFollowingTopLevelRegionCount(
    List<AstNode> previous,
    List<AstNode> current,
    int focusedTopLevelIndex,
  ) {
    var unchanged = 0;
    var previousIndex = previous.length - 1;
    var currentIndex = current.length - 1;
    while (previousIndex > focusedTopLevelIndex &&
        currentIndex >= 0 &&
        previous[previousIndex] == current[currentIndex]) {
      unchanged++;
      previousIndex--;
      currentIndex--;
    }
    return unchanged;
  }

  /// The settled first text typed into the empty phantom Block: [text]
  /// BECOMES the new Block's `continue_block_after` source. The returned state
  /// is adopted, the Block's real source is fetched against the returned path,
  /// and focus converts to an ordinary editing session over it — subsequent
  /// keystrokes then flow through `update_block` like any other Block.
  bool _handlePhantomInsert(String text) {
    if (ref.read(editorInputBlockedProvider)) return false;
    final focused = _focused;
    final note = ref.read(activeNoteProvider);
    if (note == null) return false;
    // Two legitimate entry points: an Enter-created phantom holding focus
    // (its path names the anchor slot it will splice into — possibly
    // MID-document, when Enter was pressed at the end of a non-final
    // Block), or the empty Note's ever-present first line, where no focus
    // session exists yet.
    if (focused != null && (!focused.canCommit || !focused.isPhantom)) {
      return false;
    }
    if (focused == null && note.ast.isNotEmpty) return false;
    // Empty Notes have no leaf to anchor, so `[0]` is the documented append
    // sentinel. Every non-empty Note retains the actual Core leaf path.
    final insertionPath = focused?.path ?? const [0];
    try {
      final api = ref.read(rustApiProvider);
      final structural = api.continueBlockAfter(
        note.metadata.id,
        insertionPath,
        text,
      );
      final newState = structural.state;
      ref.read(activeNoteProvider.notifier).adopt(newState);
      final insertedPath = structural.blockPath
          .map((part) => part.toInt())
          .toList();
      final source = api.getBlockSource(note.metadata.id, insertedPath);
      setState(() {
        _focused = _Focus(
          noteId: note.metadata.id,
          path: insertedPath,
          source: source,
          caret: structural.caretOffset.toInt().clamp(0, source.length),
          lastSeenState: newState,
        );
      });
      return true;
    } catch (error) {
      // A failed first insertion has no Core Block yet, so this raw phantom
      // is the user's only visible text. Leave it mounted and retryable.
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
      return false;
    }
  }

  /// Completes the handoff from the phantom controller to Core's returned
  /// Block when multiple platform values arrive before Flutter can rebuild.
  void _handlePhantomMaterializedUpdate(String text, TextSelection selection) {
    if (ref.read(editorInputBlockedProvider)) return;
    final focused = _focused;
    final note = ref.read(activeNoteProvider);
    if (focused == null ||
        focused.isPhantom ||
        note == null ||
        focused.noteId != note.metadata.id) {
      return;
    }
    focused.source = text;
    focused.caret = selection.extentOffset.clamp(0, text.length);
    ref.read(activeNoteProvider.notifier).updateBlock(focused.path, text);
  }

  /// Backspace pressed at source offset 0 of [blockPath]. The first Block
  /// has no predecessor, so nothing changes; any other Block merges into the
  /// one above it through `merge_block_with_previous`. Core reparses and
  /// returns the predecessor leaf and raw-source UTF-16 join offset, rather
  /// than asking Flutter to predict either from a tree it just invalidated.
  void _handleBackspaceAtStart(List<int> blockPath) {
    if (ref.read(editorInputBlockedProvider)) return;
    if (!_canReplaceFocusedSession) return;
    final note = ref.read(activeNoteProvider);
    if (note == null) return;
    if (_previousLeafPath(note, blockPath) == null) return;
    try {
      final api = ref.read(rustApiProvider);
      final structural = api.mergeBlockWithPrevious(
        note.metadata.id,
        blockPath,
      );
      final newState = structural.state;
      ref.read(activeNoteProvider.notifier).adopt(newState);
      final mergedPath = structural.blockPath
          .map((part) => part.toInt())
          .toList();
      final merged = api.getBlockSource(note.metadata.id, mergedPath);
      setState(() {
        _focused = _Focus(
          noteId: note.metadata.id,
          path: mergedPath,
          source: merged,
          caret: structural.caretOffset.toInt().clamp(0, merged.length),
          lastSeenState: newState,
        );
      });
    } catch (error) {
      // A merge refusal leaves the currently focused source untouched. Keep
      // that field mounted so the user can revise or copy it, just like a
      // refused per-keystroke write; replacing the whole editor here would
      // discard the only visible representation of the blocked operation.
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
    }
  }

  /// F006's real-app stage. It promotes the Core-staged `[[` source, waits
  /// for [BlockEditor]'s real completion acceptance and blur commit, confirms
  /// the returned AST actually contains a Link, then follows that rendered
  /// link through the same re-resolution callback a pointer/keyboard uses.
  Future<void> _runSmokeF006() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final note = ref.read(activeNoteProvider);
      if (note?.metadata.title == 'F006 link completion' &&
          note!.ast.isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    final staged = ref.read(activeNoteProvider);
    if (staged == null || staged.metadata.title != 'F006 link completion') {
      return;
    }
    _promote([0], blockCoreRenderedLength(staged.ast.first));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final settled = ref.read(activeNoteProvider);
      final targetId = settled == null
          ? null
          : _firstInternalLinkTarget(settled.ast);
      if (_focused == null &&
          settled?.metadata.title == 'F006 link completion' &&
          targetId != null) {
        await _followInternalLink(targetId);
        await WidgetsBinding.instance.endOfFrame;
        final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
        if (readinessPath != null && mounted) {
          try {
            File(readinessPath).writeAsStringSync(
              'f006-completion-accepted-and-internal-link-followed\n',
            );
          } on FileSystemException {
            // The shell requires the marker and will reject this stage.
          }
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  String? _firstInternalLinkTarget(List<AstNode> nodes) {
    for (final node in nodes) {
      final target = switch (node) {
        AstNode_Paragraph(:final content) ||
        AstNode_Heading(:final content) => _firstTargetIn(content),
        AstNode_List(:final items) => _firstInternalLinkTarget(items),
        AstNode_ListItem(:final content) => _firstInternalLinkTarget(content),
        AstNode_Blockquote(:final nodes) => _firstInternalLinkTarget(nodes),
        AstNode_Suggestion(:final localContent) => _firstInternalLinkTarget(
          localContent,
        ),
        _ => null,
      };
      if (target != null) return target;
    }
    return null;
  }

  String? _firstTargetIn(List<InlineElement> content) {
    for (final element in content) {
      if (element case InlineElement_Link(:final targetId)) return targetId;
    }
    return null;
  }

  /// Manual-QA hook for `scripts/smoke-shot.sh f004-block-editing`
  /// (`BURLMD_SMOKE_F004`; the demo Note is staged in `main.dart`). Promotes
  /// the first Block with the caret at its end and presses Enter, so the
  /// screenshot shows CAP-EDIT-03's signature state: the staged Note with a
  /// focused empty phantom immediately below its first Block. Gated behind an
  /// environment variable set only by the QA harness; inert in normal use.
  Future<void> _runSmokeF004() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      if (ref.read(activeNoteProvider)?.ast.isNotEmpty ?? false) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _focused != null) return;
    try {
      final note = ref.read(activeNoteProvider)!;
      _promote([0], blockCoreRenderedLength(note.ast.first));
      await WidgetsBinding.instance.endOfFrame;
      final focused = _focused;
      if (focused == null || focused.isPhantom) {
        throw StateError(
          'F004 smoke could not promote the staged first Block.',
        );
      }
      _handleEnterRequested(
        focused.path,
        focused.source,
        focused.source.length,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!_hasStagedSmokeF004State()) {
        throw StateError(
          'F004 smoke did not reach the promoted-plus-phantom state.',
        );
      }
      final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
      if (readinessPath != null) {
        File(readinessPath).writeAsStringSync('f004-promoted-phantom\n');
      }
    } catch (error) {
      // The shell harness requires the marker above, so this visible error
      // cannot be mistaken for a passing generic window.
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  bool _hasStagedSmokeF004State() {
    final note = ref.read(activeNoteProvider);
    final focused = _focused;
    var hasFocusedEmptyField = false;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is EditableText &&
          !widget.readOnly &&
          widget.focusNode.hasFocus &&
          widget.controller.text.isEmpty) {
        hasFocusedEmptyField = true;
        return;
      }
      element.visitChildElements(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return note?.metadata.title == 'F004 block editing' &&
        note?.ast.length == 3 &&
        focused?.isPhantom == true &&
        focused?.path.isNotEmpty == true &&
        hasFocusedEmptyField;
  }

  // -- BURLMD_SMOKE_F005 ---------------------------------------------------
  //
  // The staging half in main.dart creates the Note; this half promotes its
  // first Block. BlockEditor then selects the staged raw source and performs
  // the same delimiter operation a platform-primary B shortcut uses. The
  // The BlockEditor readiness marker is written only after the focused raw
  // field has painted the delimiter result and its selected inner source.
  Future<void> _runSmokeF005() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      if (ref.read(activeNoteProvider)?.ast.isNotEmpty ?? false) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _focused != null) return;
    try {
      final note = ref.read(activeNoteProvider);
      if (note?.metadata.title != 'F005 emphasis') return;
      _promote([0], 0);
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  void _invalidateSmokeF005Readiness() {
    final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
    if (readinessPath == null) return;
    try {
      File(readinessPath).deleteSync();
    } on FileSystemException {
      // A missing marker is already the required state after blur.
    }
  }

  // -- Cross-Block selection and copy (EDIT-F003, CAP-EDIT-04) -------------
  //
  // Selection COORDINATES live in Flutter's SelectionArea — ephemeral UI
  // state this container never stores. What it does hold is a transient
  // reading of those coordinates, translated into a BlockRange (rendered
  // offsets per the contract) only for the duration of one copy request;
  // the Markdown itself comes back from `copy_range_as_markdown` because
  // the Core alone owns both the AST and the source text (ADR-007 decision
  // 8). Nothing here serializes Markdown in Dart.

  /// Testing/QA hook: the range the container would currently send to the
  /// Core for a copy request — a direct read of the live selection state of
  /// each Block's registered selectables (SPK-EDIT-F001 §5: rendered-state
  /// inspection, not widget-property guesses).
  @visibleForTesting
  BlockRange? debugSelectedRange() => selectedBlockRange();

  /// Whether the frozen target is the Core-owned whole-Note operation rather
  /// than an ordinary rendered [BlockRange].
  @visibleForTesting
  bool get debugWholeNoteSelected =>
      _selectedRangeTarget() is _WholeNoteRangeTarget;

  _RangeTarget? _selectedRangeTarget() {
    if (_requiresFreshRenderedSelection) return null;
    final note = ref.read(activeNoteProvider);
    if (note == null) return null;
    if (_wholeNoteSelectedId == note.metadata.id) {
      return const _WholeNoteRangeTarget();
    }
    final range = selectedBlockRange();
    return range == null ? null : _RenderedRangeTarget(range);
  }

  /// Reads the region's current selection and expresses it as a [BlockRange]
  /// with Flutter UTF-16 rendered offsets into each endpoint Block, or null
  /// when there is no uncollapsed cross-Block selection right now. Per-Block offsets are
  /// mapped from painted text onto the Core's canonical rendered string via
  /// [blockCoreRenderedOffset].
  BlockRange? selectedBlockRange() {
    if (_requiresFreshRenderedSelection) return null;
    final note = ref.read(activeNoteProvider);
    if (note == null) return null;
    int? startIndex;
    int? endIndex;
    var startOffset = 0;
    var endOffset = 0;
    var hasUncollapsedSelection = false;
    for (var index = 0; index < note.ast.length; index++) {
      final broker = _selectionBrokers[index];
      if (broker == null || broker.selectables.isEmpty) continue;
      final node = note.ast[index];
      int? low;
      int? high;
      // Selectables register in paint order, which is the order of
      // [node]'s text leaves in block_view.dart's leaf model.
      for (var leaf = 0; leaf < broker.selectables.length; leaf++) {
        final leafIndex = broker.leafIndices.elementAtOrNull(leaf);
        if (leafIndex == null) continue;
        final SelectedContentRange? selection = broker.selectables[leaf]
            .getSelection();
        if (selection == null) continue;
        hasUncollapsedSelection |= selection.startOffset != selection.endOffset;
        final mappedLow = blockCoreRenderedOffset(
          node,
          leafIndex: leafIndex,
          renderedOffset: math.min(selection.startOffset, selection.endOffset),
        );
        final mappedHigh = blockCoreRenderedOffset(
          node,
          leafIndex: leafIndex,
          renderedOffset: math.max(selection.startOffset, selection.endOffset),
        );
        low = low == null ? mappedLow : math.min(low, mappedLow);
        high = high == null ? mappedHigh : math.max(high, mappedHigh);
      }
      if (low == null || high == null) continue;
      startIndex ??= index;
      if (startIndex == index) startOffset = low;
      endIndex = index;
      endOffset = high;
    }
    if (startIndex == null || endIndex == null || !hasUncollapsedSelection) {
      return null;
    }
    // A collapsed selectable can be a genuine edge of an uncollapsed range:
    // dragging from the exact end of one Block into its neighbour leaves the
    // first selectable collapsed at its end. Retaining those endpoint ranges
    // preserves Core's structural coordinates, while the guard above keeps a
    // lone collapsed caret from becoming a range operation.
    return BlockRange(
      startPath: Uint64List.fromList([startIndex]),
      startOffset: BigInt.from(startOffset),
      endPath: Uint64List.fromList([endIndex]),
      endOffset: BigInt.from(endOffset),
    );
  }

  /// Handles the standard Select All intent at the editor boundary. Flutter's
  /// default SelectionArea action can only enumerate mounted selectables in a
  /// lazy ListView; preserve that action for visible highlights while marking
  /// the complete Note as the range Core will copy.
  Object? handleSelectAllRequest(
    SelectAllTextIntent intent,
    Action<SelectAllTextIntent>? fallback,
  ) {
    if (_focused != null || _requiresFreshRenderedSelection) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(intent);
    }
    final note = ref.read(activeNoteProvider);
    if (note == null) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(intent);
    }
    _wholeNoteSelectedId = note.metadata.id;
    _handleRenderedSelectionChanged(null);
    // Keep Flutter's native region selection for currently mounted blocks, so
    // Select All remains visibly highlighted without forcing ListView to build
    // a long Note just to represent an interaction Core already owns.
    // ignore: invalid_use_of_protected_member
    return fallback?.invoke(intent);
  }

  /// Entry point of [_CopyRangeAsMarkdownAction]. [fallback] is whatever
  /// default copy behaviour was being invoked — the focused field's own
  /// raw-source copy, or the region's no-op when nothing is selected.
  Object? handleCopyRequest(
    CopySelectionTextIntent intent,
    Action<CopySelectionTextIntent>? fallback,
  ) {
    final rangeClient = _rangeInputClient;
    if (rangeClient != null) {
      unawaited(
        intent.collapseSelection
            ? rangeClient.cutSelection()
            : rangeClient.copySelection(),
      );
      return null;
    }
    // While a Block holds focus its selection belongs to the platform field
    // (raw source text), and no cross-Block selection can exist (SPK-EDIT-F001
    // §4b): fall through to the default so the focused Block behaves normally.
    if (_focused != null) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(intent);
    }
    // A pointer sequence that began in a raw field may have blurred it while
    // crossing the surrounding region. It has no valid rendered endpoints;
    // suppress the fallback as well as the Core path so it cannot copy a
    // misleading partial selection. A new rendered pointer-down clears this.
    if (_requiresFreshRenderedSelection) return null;
    final range = selectedBlockRange();
    if (range == null) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(CopySelectionTextIntent.copy);
    }
    final note = ref.read(activeNoteProvider);
    if (note == null) return null;
    try {
      final markdown = ref
          .read(rustApiProvider)
          .copyRangeAsMarkdown(note.metadata.id, range);
      unawaited(Clipboard.setData(ClipboardData(text: markdown)));
    } catch (error) {
      _reportEditorOperationFailure(error);
    }
    return null;
  }

  // -- BURLMD_SMOKE_F007 ---------------------------------------------------
  //
  // The staging half creates two Notes through Core. This QA-only driver
  // supplies explicit complete rendered ranges (rather than relying on screen
  // coordinates), but every mutation still goes through the live production
  // path: type is a `TextInputClient.updateEditingValue`, while paste and
  // delete invoke the editor's installed Actions from the captured
  // SelectionArea context. The final deletion must produce the existing
  // phantom slot; a generic workspace can therefore never certify readiness.
  Future<void> _runSmokeF007() async {
    const typeTitle = 'F007 range type paste';
    const deleteTitle = 'F007 range delete phantom';
    try {
      if (!await _waitForSmokeNote(typeTitle)) {
        return;
      }
      await _smokeActivateWholeRange();
      final typeClient = _rangeInputClient;
      if (typeClient == null) {
        throw StateError('F007 could not attach type proxy.');
      }
      typeClient.updateEditingValue(
        const TextEditingValue(
          text: 'typed\n\nsecond\n\nthird\n\nfourth',
          selection: TextSelection.collapsed(offset: 28),
        ),
      );
      if (!await _waitForSmoke(
        () => _rangeInputClient == null && _focused != null,
      )) {
        throw StateError('F007 type-over did not return a Core caret.');
      }
      final typedState = ref.read(activeNoteProvider);
      if (typedState == null || typedState.ast.length < 2) {
        throw StateError(
          'F007 type-over did not preserve a cross-Block result.',
        );
      }

      _dismissSmokeFocus();
      await _smokeActivateWholeRange();
      await Clipboard.setData(const ClipboardData(text: 'pasted'));
      if (_rangeInputClient == null || _areaContext == null) {
        throw StateError('F007 could not attach paste proxy.');
      }
      Actions.invoke(
        _areaContext!,
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      if (!await _waitForSmoke(
        () => _rangeInputClient == null && _focused != null,
      )) {
        throw StateError('F007 paste did not return a Core caret.');
      }

      final matches = await ref
          .read(rustApiProvider)
          .findNotesByTitle(deleteTitle, 1);
      if (matches.isEmpty) {
        throw StateError('F007 delete fixture is unavailable.');
      }
      ref.read(selectedNoteIdProvider.notifier).select(matches.single.id);
      if (!await _waitForSmokeNote(deleteTitle)) {
        return;
      }
      await _smokeActivateWholeRange();
      if (_rangeInputClient == null || _areaContext == null) {
        throw StateError('F007 could not attach delete proxy.');
      }
      Actions.invoke(_areaContext!, const DeleteCharacterIntent(forward: true));
      if (!await _waitForSmoke(() => _focused?.isPhantom == true)) {
        throw StateError('F007 delete did not return the Core phantom caret.');
      }
      final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
      if (readinessPath != null) {
        File(readinessPath).writeAsStringSync(
          'f007-type-input-paste-action-delete-action-core-caret-phantom\n',
        );
      }
    } catch (error) {
      if (mounted) ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  Future<bool> _waitForSmoke(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ready()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<bool> _waitForSmokeNote(String title) => _waitForSmoke(() {
    final note = ref.read(activeNoteProvider);
    return note?.metadata.title == title && _focused == null;
  });

  void _dismissSmokeFocus() {
    _closeRangeInput();
    if (_focused != null) setState(() => _focused = null);
  }

  Future<void> _smokeActivateWholeRange() async {
    _dismissSmokeFocus();
    await WidgetsBinding.instance.endOfFrame;
    final note = ref.read(activeNoteProvider);
    if (note == null || note.ast.length < 2) {
      throw StateError('F007 needs a rendered cross-Block fixture.');
    }
    _activateRangeInput(
      _RenderedRangeTarget(
        BlockRange(
          startPath: Uint64List.fromList(const [0]),
          startOffset: BigInt.zero,
          endPath: Uint64List.fromList([note.ast.length - 1]),
          endOffset: BigInt.from(blockCoreRenderedLength(note.ast.last)),
        ),
      ),
    );
  }

  // -- BURLMD_SMOKE_F002 ---------------------------------------------------
  //
  // Manual-QA hook for `scripts/smoke-shot.sh f002-live-preview`. The demo
  // Note itself is built and selected by the staging half of this hook in
  // `main.dart` (the Editor only mounts once a Note is selected, so it
  // cannot stage its own Note); this half waits for that Note to finish
  // opening and promotes its first Block mid-text, so the screenshot shows
  // one focused raw-source Block among formatted neighbors — what
  // EDIT-F002's smoke shot must show. Gated behind an environment variable
  // set only by the QA harness; inert in normal use.

  Future<void> _runSmokePromote() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      if (ref.read(activeNoteProvider) != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // Promote the first Block partway through its text once it renders.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted &&
        _focused == null &&
        (ref.read(activeNoteProvider)?.ast.isNotEmpty ?? false)) {
      _promote([0], 'Intro with **bo'.length);
      // Promotion only schedules the editor build. Do not certify the shot
      // until the next frame contains the mounted, active EditableText and
      // its raw Markdown delimiters; a generic formatted Workspace can then
      // never satisfy the shell harness marker.
      final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
      final readyDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (mounted && DateTime.now().isBefore(readyDeadline)) {
        await WidgetsBinding.instance.endOfFrame;
        if (_hasActiveSmokeRawField()) {
          if (readinessPath != null) {
            try {
              File(
                readinessPath,
              ).writeAsStringSync('f002-focused-raw-source\n');
            } on FileSystemException {
              // The marker is QA-only. The shell harness rejects a missing
              // marker; normal editing must not fail if its path is bad.
            }
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  bool _hasActiveSmokeRawField() {
    var activeRawField = false;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is EditableText &&
          !widget.readOnly &&
          widget.focusNode.hasFocus &&
          widget.controller.text.contains('**')) {
        activeRawField = true;
        return;
      }
      element.visitChildElements(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return activeRawField;
  }

  void _invalidateSmokeF002Readiness() {
    final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
    if (readinessPath == null) return;
    try {
      File(readinessPath).deleteSync();
    } on FileSystemException {
      // The marker is only a QA assertion. A missing or inaccessible marker
      // does not alter user editing behaviour; the harness rejects it.
    }
  }

  /// Promotes one production-font wrap-boundary fixture for the F001 visual
  /// evidence. An absent index intentionally leaves all three formatted.
  Future<void> _runSmokeF001() async {
    final index = int.tryParse(
      Platform.environment['BURLMD_SMOKE_F001_FOCUSED_INDEX'] ?? '',
    );
    if (index == null) return;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      final note = ref.read(activeNoteProvider);
      if (note != null && index >= 0 && index < note.ast.length) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _focused == null) _promote([index], 0);
  }

  // -- BURLMD_SMOKE_F003 ---------------------------------------------------
  //
  // Select-all half of the `scripts/smoke-shot.sh f003-selection` hook: the
  // demo Note (code block + list + paragraph — heterogeneous, because
  // BlockRange offsets are defined per AstNode variant) is built and
  // selected by the staging half in `main.dart`, which runs before this
  // editor mounts. Once the Note is open under the SelectionArea, this
  // invokes select-all through the same intent the keyboard shortcut fires,
  // so the screenshot shows one visible highlight spanning every Block.
  // Gated behind an environment variable set only by the QA harness; inert
  // in normal use.

  Future<void> _runSmokeF003() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      if (ref.read(activeNoteProvider) != null && _areaContext != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await WidgetsBinding.instance.endOfFrame;
    final areaContext = _areaContext;
    if (areaContext != null && areaContext.mounted) {
      Actions.invoke(
        areaContext,
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await WidgetsBinding.instance.endOfFrame;
      final note = ref.read(activeNoteProvider);
      final range = selectedBlockRange();
      final isStagedHeterogeneousNote =
          note != null &&
          note.ast.length == 3 &&
          note.ast[0] is AstNode_CodeBlock &&
          note.ast[1] is AstNode_List &&
          note.ast[2] is AstNode_Paragraph;
      final hasWholeStagedRange =
          note != null &&
          range != null &&
          range.startPath.length == 1 &&
          range.startPath.single == BigInt.zero &&
          range.startOffset == BigInt.zero &&
          range.endPath.length == 1 &&
          range.endPath.single == BigInt.from(2) &&
          range.endOffset == BigInt.from(blockCoreRenderedLength(note.ast[2]));
      if (isStagedHeterogeneousNote && hasWholeStagedRange) {
        final readinessPath = Platform.environment['BURLMD_SMOKE_READY_FILE'];
        if (readinessPath != null) {
          try {
            File(
              readinessPath,
            ).writeAsStringSync('f003-heterogeneous-cross-block-selection\n');
          } on FileSystemException {
            // The marker is QA-only. The harness turns a missing one into a
            // deterministic failure without changing normal editing.
          }
        }
      }
    }
  }
}

/// Ephemeral focus state for the promoted Block: which Block, the raw
/// source it was promoted with (refreshed when provider state changes
/// externally), and the clicked caret offset. Selection coordinates are the
/// only Note-adjacent state the Presentation Container holds (ADR-006
/// decision 4); the Note's content itself stays in [activeNoteProvider].
class _Focus {
  _Focus({
    required this.noteId,
    required this.path,
    required this.source,
    required this.caret,
    required this.lastSeenState,
    this.isPhantom = false,
    this.phantomInsertionIndex,
  }) : token = _nextFocusToken++;

  /// Identifies this focus session (`EDIT-F004`). Echoed back by a blurring
  /// field so [_handleFieldBlur] can tell "the user blurred" from "this
  /// field's generation was replaced", which matters when both generations
  /// share a path — a phantom converting to a real Block at the same index.
  final int token;

  /// The Note this focus belongs to. Focus never survives an open-note
  /// switch: paths address Blocks within one Note, and a new Note's
  /// same-indexed Block is a different Block.
  final String noteId;

  final List<int> path;
  String source;
  int caret;

  /// The provider state this focus was established (or last refreshed)
  /// against, used to detect external changes.
  NoteState lastSeenState;

  int resyncToken = 0;

  /// False only after BlockEditor detects an overlapping IME/external resync.
  /// While false, promotion, blur commit, and structural edits are no-ops so
  /// the conflicted raw field remains available for the user to copy.
  bool canCommit = true;

  /// True while this focus names the sanctioned empty phantom Block
  /// (`EDIT-F004`): UI-side caret state only, never committed, never
  /// addressed through `update_block`; its first typed character becomes an
  /// `continue_block_after` source instead.
  final bool isPhantom;

  /// The Core-returned slot for an empty range edit. Enter-created phantoms
  /// still derive their visual anchor from their real predecessor path.
  final int? phantomInsertionIndex;
}

/// Monotonic source of [_Focus.token] values.
int _nextFocusToken = 0;

/// The editor's error surface (`SHEL-E004`): a persistent, readable panel
/// naming what the Core reported when there is no active Note session to
/// retain. Scrollable and soft-wrapped so even a long Rust-side message can
/// neither overflow nor clip. Public because other components surface Core
/// errors through the same panel.
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

/// A pass-through selection registrar, one per Block (`EDIT-F003`): the
/// Block's painted text registers here instead of directly with the
/// [SelectionArea]'s registrar, and every registration is forwarded
/// unchanged — the region's own bookkeeping is untouched. What this buys is
/// a public, per-Block handle on exactly which [Selectable]s belong to that
/// Block and what each one's current selection is ([Selectable.getSelection]),
/// from which [EditorState.selectedBlockRange] builds a `BlockRange`.
class _BlockSelectionBroker implements SelectionRegistrar {
  _BlockSelectionBroker();

  /// The region's registrar (the enclosing `SelectionContainer` delegate),
  /// wired up during build; null while the broker is outside an area.
  SelectionRegistrar? parent;

  /// This Block's selectables in paint order — which is the order of its
  /// unfocused text leaves in block_view.dart's leaf model.
  final List<Selectable> selectables = [];

  /// Maps each registered selectable back to its original rendered-leaf
  /// index. A raw focused leaf has no selectable, so siblings must not be
  /// renumbered onto that leaf's Core-owned rendered coordinate.
  List<int> leafIndices = const [];

  @override
  void add(Selectable selectable) {
    selectables.add(selectable);
    parent?.add(selectable);
  }

  @override
  void remove(Selectable selectable) {
    selectables.remove(selectable);
    parent?.remove(selectable);
  }
}

/// Overrides the selection system's default copy (`CopySelectionTextIntent`)
/// for cross-Block selections (CAP-EDIT-04): the Markdown is fetched from
/// the Core's `copy_range_as_markdown` — the Core owns both the AST and the
/// source text, so a Dart-side serializer is exactly what ADR-007 forbids.
///
/// Registered on an ancestor [Actions] of the [SelectionArea]. The framework
/// invokes it with [callingAction] set to the overridden default (the
/// region's or the focused field's own), so behaviour this ticket does not
/// own falls straight through: a focused Block copying its raw source, and
/// a copy with nothing selected.
class _CopyRangeAsMarkdownAction extends Action<CopySelectionTextIntent> {
  _CopyRangeAsMarkdownAction(this._state);

  final EditorState _state;

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) =>
      _state.handleCopyRequest(intent, callingAction);
}

/// Handles delete intents only while the editor owns a live cross-Block
/// range. Otherwise this ancestor must delegate to EditableText's overridable
/// action so a focused raw field keeps Flutter's normal delete semantics.
class _RangeDeleteAction<T extends Intent> extends Action<T> {
  _RangeDeleteAction(this._state);

  final EditorState _state;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final rangeClient = _state._rangeInputClient;
    if (rangeClient == null) return callingAction?.invoke(intent);
    unawaited(rangeClient.deleteSelection());
    return null;
  }
}

/// Handles paste only for a live cross-Block range. A raw focused field's
/// paste is the framework default, including its controller and selection
/// handling, reached through [callingAction].
class _RangePasteAction extends Action<PasteTextIntent> {
  _RangePasteAction(this._state);

  final EditorState _state;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final rangeClient = _state._rangeInputClient;
    if (rangeClient == null) return callingAction?.invoke(intent);
    unawaited(rangeClient.pasteSelection());
    return null;
  }
}

/// Captures Select All before the lazy SelectionArea action truncates its
/// model to mounted selectables. Its [callingAction] is still invoked so the
/// platform paints selection highlights for the visible part of the Note.
class _SelectWholeNoteAction extends Action<SelectAllTextIntent> {
  _SelectWholeNoteAction(this._state);

  final EditorState _state;

  @override
  Object? invoke(SelectAllTextIntent intent, [BuildContext? context]) =>
      _state.handleSelectAllRequest(intent, callingAction);
}
