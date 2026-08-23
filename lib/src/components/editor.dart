import 'dart:io';

import 'package:burlmd/src/components/block_editor.dart';
import 'package:burlmd/src/components/block_view.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// path, its fetched source text, and the clicked caret offset — selection
/// coordinates, which ADR-006 decision 4 sanctions as ephemeral UI state.
class Editor extends ConsumerStatefulWidget {
  const Editor({super.key});

  @override
  ConsumerState<Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<Editor> {
  /// The currently promoted Block, or null while every Block renders
  /// formatted.
  _Focus? _focused;

  @override
  void initState() {
    super.initState();
    if (Platform.environment.containsKey('BURLMD_SMOKE_F002')) {
      _runSmokePromote();
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
      return const SizedBox.shrink();
    }
    // A different Note opened while a Block was focused: drop focus rather
    // than carry the edit session across. Refetching by path would be wrong
    // here — a same-indexed Block in the new Note is not the Block the user
    // was editing, and silently retargeting focus at it would point the
    // buffered keystrokes of one Note at another's source row.
    if (_focused != null && _focused!.noteId != note.metadata.id) {
      _focused = null;
    }
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
    return ListView.builder(
      itemCount: note.ast.length,
      itemBuilder: (context, i) => _buildEntry(note, i),
    );
  }

  Widget _buildEntry(NoteState note, int index) {
    final path = [index];
    // One stable wrapper per entry so tests (and the layout) can address a
    // Block's slot regardless of which presentation currently fills it.
    return KeyedSubtree(
      key: ValueKey('entry-$index'),
      child: _buildEntryInner(note, path, index),
    );
  }

  Widget _buildEntryInner(NoteState note, List<int> path, int index) {
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
    return BlockView(
      key: ValueKey('block-$index'),
      node: note.ast[index],
      blockPath: path,
      onFocusRequested: _promote,
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
