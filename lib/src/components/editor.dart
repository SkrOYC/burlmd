import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
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

  /// A context inside the [SelectionArea], captured during build; lets the
  /// smoke hook invoke select-all the way the keyboard shortcut does.
  BuildContext? _areaContext;

  @override
  void initState() {
    super.initState();
    if (Platform.environment.containsKey('BURLMD_SMOKE_F002')) {
      _runSmokePromote();
    }
    if (Platform.environment.containsKey('BURLMD_SMOKE_F003')) {
      unawaited(_runSmokeF003());
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
    return Actions(
      actions: <Type, Action<Intent>>{CopySelectionTextIntent: _copyAction},
      child: SelectionArea(
        child: Builder(
          builder: (areaContext) {
            // Captured for the smoke hook's select-all invocation; reading
            // it during build keeps it current across rebuilds.
            _areaContext = areaContext;
            return ListView.builder(
              itemCount: note.ast.length,
              itemBuilder: (context, i) => _buildEntry(context, note, i),
            );
          },
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
    if (focused != null && _pathEquals(focused.path, path)) {
      // blockContainer replicates the Block's container decoration around
      // the promoted field (SPK-EDIT-F001 §3b): the dark pane under a code
      // Block's white ink, the blockquote border/padding, the list marker
      // column — the same builder the unfocused render uses, so neither
      // path can drift from the other.
      return blockContainer(
        note.ast[index],
        BlockEditor(
          key: ValueKey('edit-$index'),
          noteId: note.metadata.id,
          blockPath: path,
          source: focused.source,
          initialCaret: focused.caret,
          style: blockTextStyle(note.ast[index]),
          resyncToken: focused.resyncToken,
          onFocusLost: _handleFieldBlur,
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

  /// Promotes [blockPath] to the raw editable field with the caret at
  /// [caret] — the source offset the user clicked, resolved by [BlockView].
  void _promote(List<int> blockPath, int caret) {
    if (_focused != null && _pathEquals(_focused!.path, blockPath)) return;
    // Moving focus between Blocks commits the outgoing one first: its last
    // buffered text must reach the working source before anything else
    // reads the Note, and blur is the commit point (ADR-006, ADR-008).
    if (_focused != null) _commitFocused();
    final note = ref.read(activeNoteProvider);
    if (note == null || blockPath.first >= note.ast.length) return;
    try {
      final source = ref
          .read(rustApiProvider)
          .getBlockSource(note.metadata.id, blockPath);
      setState(() {
        _focused = _Focus(
          noteId: note.metadata.id,
          path: blockPath,
          source: source,
          caret: caret,
          lastSeenState: note,
        );
      });
    } catch (error) {
      ref.read(editorErrorProvider.notifier).report(error);
    }
  }

  /// Blur handler from the promoted field: commits unless focus already
  /// moved elsewhere (in which case [_promote]'s commit already ran).
  void _handleFieldBlur(List<int> blockPath) {
    if (_focused == null || !_pathEquals(_focused!.path, blockPath)) return;
    _commitFocused();
  }

  /// Commits the focused Block through `commit_block`: the Core reparses its
  /// working source, rebuilds the span map, and returns the authoritative
  /// state, which is adopted wholesale. Focus is then cleared rather than
  /// re-targeted from the retained path — the returned AST may have reshaped
  /// the edited Block (a paragraph retyped to begin with `- ` becomes a
  /// list), so nothing survives the commit except the returned state
  /// itself.
  void _commitFocused() {
    final focused = _focused;
    if (focused == null) return;
    setState(() => _focused = null);
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
  /// with rendered offsets into each endpoint Block, or null when there is
  /// no uncollapsed cross-Block selection right now. Per-Block offsets are
  /// mapped from painted text onto the Core's canonical rendered string via
  /// [blockCoreRenderedOffset].
  BlockRange? selectedBlockRange() {
    final note = ref.read(activeNoteProvider);
    if (note == null) return null;
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
    }
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
  });

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
}

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
