import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show SelectedContentRange, Selectable, SelectionRegistrar;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

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
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(editorErrorProvider);
    // The Core refused an operation on the active Note (an open failed, or a
    // close on switch aborted it). Surfaced here rather than swallowed:
    // before SHEL-E004 this widget had no error surface at all, so every
    // such failure was invisible to the user. A refused *keystroke* write is
    // deliberately NOT routed here — it would blank the text the user is
    // typing; WriteTierNotice surfaces it above the editor instead.
    if (error != null) return _ErrorSurface(message: '$error');
    final note = ref.watch(activeNoteProvider);
    if (note == null) {
      _focused = null;
      _selectionBrokers.clear();
      return const SizedBox.shrink();
    }
    // A different Note opened while a Block was focused: drop focus rather
    // than carry the edit session across. Refetching by path would be wrong
    // here — a same-indexed Block in the new Note is not the Block the user
    // was editing, and silently retargeting focus at it would point the
    // buffered keystrokes of one Note at another's source row.
    if (_focused != null && _focused!.noteId != note.metadata.id) {
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
    final phantomAnchor = note.ast.isEmpty && focusedForSlot?.isPhantom != true
        ? 0
        : math.min((focusedForSlot?.path.first ?? -1) + 1, note.ast.length);
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: _copyAction,
        SelectAllTextIntent: _selectAllAction,
      },
      child: Listener(
        onPointerDown: (_) {
          _wholeNoteSelectedId = null;
          if (_focused == null) _requiresFreshRenderedSelection = false;
        },
        child: SelectionArea(
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
    // A phantom's path names its anchor slot (the index a new Block would
    // splice into), which can coincide numerically with a real Block's
    // index — so the phantom must never satisfy this early-out; the
    // `isPhantom` guard keeps the two identities apart.
    if (focused != null &&
        !focused.isPhantom &&
        _pathStartsWith(focused.path, path)) {
      return renderBlockWithFocusedLeaf(
        note.ast[index],
        focused.path.sublist(path.length),
        (leaf) => BlockEditor(
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
        ),
      );
    }
    // Unfocused Blocks join the shared selection region through their own
    // pass-through registrar, so this container knows exactly which painted
    // selectables belong to THIS Block (`EDIT-F003`). While a Block IS
    // focused, its field does not register with the region at all
    // (SPK-EDIT-F001 §3c), which is what keeps a focused endpoint impossible.
    final broker = _selectionBrokers.putIfAbsent(
      index,
      _BlockSelectionBroker.new,
    );
    broker.parent = SelectionContainer.maybeOf(context);
    return BlockView(
      key: ValueKey('block-$index'),
      node: note.ast[index],
      blockPath: path,
      onFocusRequested: _promote,
      selectionRegistrar: broker,
    );
  }

  /// Promotes the Core-resolved editable leaf for a top-level rendered
  /// coordinate. Flutter never estimates source punctuation or nested paths.
  void _promote(List<int> topLevelPath, int renderedUtf16Offset) {
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
    // Moving focus between Blocks commits the outgoing one first: its last
    // buffered text must reach the working source before anything else
    // reads the Note, and blur is the commit point (ADR-006, ADR-008).
    if (_focused != null) _commitFocused();
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
      ref.read(editorErrorProvider.notifier).report(error);
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

  /// Commits the focused Block through `commit_block`: the Core reparses its
  /// working source, rebuilds the span map, and returns the authoritative
  /// state, which is adopted wholesale. Focus is then cleared rather than
  /// re-targeted from the retained path — the returned AST may have reshaped
  /// the edited Block (a paragraph retyped to begin with `- ` becomes a
  /// list), so nothing survives the commit except the returned state
  /// itself.
  void _commitFocused() {
    final focused = _focused;
    if (focused == null || !focused.canCommit) return;
    setState(() {
      _focused = null;
      // Do not retain a range that crossed the field while it was focused.
      // `commit_block` reparses its source and this empty broker set requires
      // a fresh rendered SelectionArea gesture before a range can be sent to
      // the Core (ADR-006 / SPK-EDIT-F001).
      _selectionBrokers.clear();
      _wholeNoteSelectedId = null;
    });
    if (focused.isPhantom) {
      // The sanctioned phantom Block is UI-side caret state ONLY (`EDIT-F004`):
      // CommonMark has no empty paragraph, so there is nothing to commit and
      // no `block_path` to address. Focus leaving it without anything typed
      // simply discards it; the Note is unchanged.
      return;
    }
    final note = ref.read(activeNoteProvider);
    if (note == null) return;
    try {
      final newState = ref
          .read(rustApiProvider)
          .commitBlock(note.metadata.id, focused.path);
      ref.read(activeNoteProvider.notifier).adopt(newState);
    } catch (error) {
      // A failed blur commit leaves the Core's working source holding
      // whatever `update_block` already buffered; surfacing beside the
      // content beats discarding it. The next successful open clears this.
      ref.read(keystrokeWriteFailureProvider.notifier).report(error);
    }
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
            committedState,
            blockPath,
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
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  /// Resolves the real continuation anchor after [commitBlock] reparses a
  /// buffered edit. Prefer the same address only when it remains an editable
  /// leaf in Core's returned AST; otherwise let Core resolve the end of its
  /// top-level Block, which is exactly where Enter was pressed.
  List<int> _rederiveContinuationPath(
    RustApi api,
    String noteId,
    NoteState state,
    List<int> previousPath,
  ) {
    final paths = _leafPaths(state.ast);
    if (paths.any((path) => _pathEquals(path, previousPath))) {
      return List<int>.from(previousPath);
    }
    final topLevelIndex = previousPath.first;
    if (topLevelIndex >= state.ast.length) {
      throw StateError('Committed Block no longer has a top-level anchor.');
    }
    return api
        .resolveBlockCaret(noteId, [
          topLevelIndex,
        ], blockCoreRenderedLength(state.ast[topLevelIndex]))
        .blockPath
        .map((part) => part.toInt())
        .toList();
  }

  /// The settled first text typed into the empty phantom Block: [text]
  /// BECOMES the new Block's `continue_block_after` source. The returned state
  /// is adopted, the Block's real source is fetched against the returned path,
  /// and focus converts to an ordinary editing session over it — subsequent
  /// keystrokes then flow through `update_block` like any other Block.
  void _handlePhantomInsert(String text) {
    final focused = _focused;
    final note = ref.read(activeNoteProvider);
    if (note == null) return;
    // Two legitimate entry points: an Enter-created phantom holding focus
    // (its path names the anchor slot it will splice into — possibly
    // MID-document, when Enter was pressed at the end of a non-final
    // Block), or the empty Note's ever-present first line, where no focus
    // session exists yet.
    if (focused != null && (!focused.canCommit || !focused.isPhantom)) return;
    if (focused == null && note.ast.isNotEmpty) return;
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
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  /// Backspace pressed at source offset 0 of [blockPath]. The first Block
  /// has no predecessor, so nothing changes; any other Block merges into the
  /// one above it through `merge_block_with_previous`. Core reparses and
  /// returns the predecessor leaf and raw-source UTF-16 join offset, rather
  /// than asking Flutter to predict either from a tree it just invalidated.
  void _handleBackspaceAtStart(List<int> blockPath) {
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
      ref.read(editorErrorProvider.notifier).report(error);
    }
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

  /// Reads the region's current selection and expresses it as a [BlockRange]
  /// with Flutter UTF-16 rendered offsets into each endpoint Block, or null
  /// when there is no uncollapsed cross-Block selection right now. Per-Block offsets are
  /// mapped from painted text onto the Core's canonical rendered string via
  /// [blockCoreRenderedOffset].
  BlockRange? selectedBlockRange() {
    if (_requiresFreshRenderedSelection) return null;
    final note = ref.read(activeNoteProvider);
    if (note == null) return null;
    if (_wholeNoteSelectedId == note.metadata.id && note.ast.isNotEmpty) {
      return BlockRange(
        startPath: Uint64List.fromList(const [0]),
        startOffset: BigInt.zero,
        endPath: Uint64List.fromList([note.ast.length - 1]),
        endOffset: BigInt.from(blockCoreRenderedLength(note.ast.last)),
      );
    }
    int? startIndex;
    int? endIndex;
    var startOffset = 0;
    var endOffset = 0;
    for (var index = 0; index < note.ast.length; index++) {
      final broker = _selectionBrokers[index];
      if (broker == null || broker.selectables.isEmpty) continue;
      final node = note.ast[index];
      int? low;
      int? high;
      // Selectables register in paint order, which is the order of
      // [node]'s text leaves in block_view.dart's leaf model.
      for (var leaf = 0; leaf < broker.selectables.length; leaf++) {
        final SelectedContentRange? selection = broker.selectables[leaf]
            .getSelection();
        if (selection == null || selection.startOffset == selection.endOffset) {
          continue;
        }
        final mappedLow = blockCoreRenderedOffset(
          node,
          leafIndex: leaf,
          renderedOffset: math.min(selection.startOffset, selection.endOffset),
        );
        final mappedHigh = blockCoreRenderedOffset(
          node,
          leafIndex: leaf,
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
    if (startIndex == null || endIndex == null) return null;
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
    if (note == null || note.ast.isEmpty) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(intent);
    }
    _wholeNoteSelectedId = note.metadata.id;
    // Keep Flutter's native region selection for currently mounted blocks, so
    // Select All remains visibly highlighted without forcing ListView to build
    // a long Note just to represent an interaction Core already owns.
    // ignore: invalid_use_of_protected_member
    return fallback?.invoke(intent);
  }

  /// Entry point of [_CopyRangeAsMarkdownAction]. [fallback] is whatever
  /// default copy behaviour was being invoked — the focused field's own
  /// raw-source copy, or the region's no-op when nothing is selected.
  Object? handleCopyRequest(Action<CopySelectionTextIntent>? fallback) {
    // While a Block holds focus its selection belongs to the platform field
    // (raw source text), and no cross-Block selection can exist (SPK-EDIT-F001
    // §4b): fall through to the default so the focused Block behaves normally.
    if (_focused != null) {
      // ignore: invalid_use_of_protected_member
      return fallback?.invoke(CopySelectionTextIntent.copy);
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
      ref.read(editorErrorProvider.notifier).report(error);
    }
    return null;
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
}

/// Monotonic source of [_Focus.token] values.
int _nextFocusToken = 0;

/// The editor's error surface (`SHEL-E004`): a persistent, readable panel
/// naming what the Core reported, shown in place of note content until the
/// next successful open clears [editorErrorProvider]. Scrollable and
/// soft-wrapped so even a long Rust-side message can neither overflow nor
/// clip. Public because other components surface Core errors through the
/// same panel.
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

  /// This Block's selectables in paint order — which is the order of the
  /// Block's text leaves in block_view.dart's leaf model.
  final List<Selectable> selectables = [];

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
      _state.handleCopyRequest(callingAction);
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
