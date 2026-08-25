import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The full-text search surface (`SHEL-E006`): a query field above the
/// Workspace-scoped, bm25-ranked hit list served by the Core's index.
///
/// The results come from [searchResultsProvider] — one indexed round trip
/// per keystroke, never client-side filtering. Selecting a hit publishes its
/// concept id to [selectedNoteIdProvider], the same seam the tree
/// (`SHEL-E003`) writes and the editor pane (`SHEL-E004`) consumes to open a
/// Note, so search-driven navigation needs no second open path.
///
/// [resultLimit] is required and is passed through to the Core verbatim:
/// `search_notes` takes the cap as a parameter precisely so the surface
/// controls it, and hardcoding it here would reintroduce the silent
/// truncation WSPC-D009 removed.
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({
    super.key,
    required this.resultLimit,
    this.onNoteSelected,
    this.onResultSelected,
    this.onDismiss,
  });

  /// How many hits the Core may return for one query. Caller-supplied so
  /// each surface that embeds the panel decides its own cap.
  final int resultLimit;

  /// Invoked when the user selects a result, in addition to the provider
  /// update — the same dual seam [WorkspaceTree] offers.
  ///
  /// Standing dual-seam API kept for headless/embedded consumers and tests:
  /// production mounts drive selection purely through
  /// [selectedNoteIdProvider].
  final ValueChanged<String>? onNoteSelected;

  /// Lets an embedding transient surface (for example, the command palette)
  /// close itself after this panel has successfully published selection.
  final VoidCallback? onResultSelected;

  /// Closes an embedding transient surface when Escape is pressed.
  final VoidCallback? onDismiss;

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _inputFocusNode = FocusNode(debugLabel: 'search-panel-input');
  int _selectedIndex = 0;

  @override
  void dispose() {
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider(widget.resultLimit));
    final selectionBlocked = ref.watch(noteSelectionBlockedProvider);
    final colors = _colors(context);
    _inputFocusNode.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _inputFocusNode.unfocus();
        widget.onDismiss?.call();
        return widget.onDismiss == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    return Material(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Focus(
              onKeyEvent: (_, event) {
                final hits = results.value ?? const <NoteMetadata>[];
                if (event is! KeyDownEvent || hits.isEmpty) {
                  return KeyEventResult.ignored;
                }
                final selectedIndex = _selectedIndex.clamp(0, hits.length - 1);
                switch (event.logicalKey) {
                  case LogicalKeyboardKey.arrowDown:
                    setState(
                      () => _selectedIndex = (selectedIndex + 1) % hits.length,
                    );
                    return KeyEventResult.handled;
                  case LogicalKeyboardKey.arrowUp:
                    setState(
                      () => _selectedIndex =
                          (selectedIndex - 1 + hits.length) % hits.length,
                    );
                    return KeyEventResult.handled;
                  case LogicalKeyboardKey.enter ||
                      LogicalKeyboardKey.numpadEnter:
                    if (!selectionBlocked) {
                      final hit = hits[selectedIndex];
                      final selected = ref
                          .read(selectedNoteIdProvider.notifier)
                          .select(hit.id);
                      if (selected) {
                        widget.onNoteSelected?.call(hit.id);
                        widget.onResultSelected?.call();
                      }
                    }
                    return KeyEventResult.handled;
                  case LogicalKeyboardKey.escape:
                    _inputFocusNode.unfocus();
                    widget.onDismiss?.call();
                    return widget.onDismiss == null
                        ? KeyEventResult.ignored
                        : KeyEventResult.handled;
                  default:
                    return KeyEventResult.ignored;
                }
              },
              child: TextField(
                key: const ValueKey('search-panel-input'),
                focusNode: _inputFocusNode,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 16,
                    color: colors.textMuted,
                    semanticLabel: 'Search',
                  ),
                  hintText: 'Search notes',
                  isDense: true,
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _selectedIndex = 0);
                  ref.read(searchQueryProvider.notifier).set(value);
                },
              ),
            ),
          ),
          Expanded(
            // Riverpod 3 parks a failed load in a loading-with-error value
            // while its automatic retry backoff runs; keying the error branch
            // on `when(error:)` alone would flash the failure for one frame.
            // The flow's error state stands until results actually return.
            child: (results.hasError && results.value == null)
                ? _SearchErrorState(
                    error: results.error!,
                    onRetry: () => ref.invalidate(
                      searchResultsProvider(widget.resultLimit),
                    ),
                  )
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _SearchErrorState(
                      error: error,
                      onRetry: () => ref.invalidate(
                        searchResultsProvider(widget.resultLimit),
                      ),
                    ),
                    data: (hits) {
                      if (ref.read(searchQueryProvider).trim().isEmpty) {
                        return const _EmptyState(
                          key: ValueKey('search-empty'),
                          message: 'Type to search your notes',
                        );
                      }
                      if (hits.isEmpty) {
                        return const _EmptyState(
                          key: ValueKey('search-no-match'),
                          message: 'No matching notes',
                        );
                      }
                      final selectedIndex = _selectedIndex.clamp(
                        0,
                        hits.length - 1,
                      );
                      void select(NoteMetadata hit) {
                        if (selectionBlocked) return;
                        final selected = ref
                            .read(selectedNoteIdProvider.notifier)
                            .select(hit.id);
                        if (selected) {
                          widget.onNoteSelected?.call(hit.id);
                          widget.onResultSelected?.call();
                        }
                      }

                      return Focus(
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          switch (event.logicalKey) {
                            case LogicalKeyboardKey.arrowDown:
                              setState(
                                () => _selectedIndex =
                                    (selectedIndex + 1) % hits.length,
                              );
                              return KeyEventResult.handled;
                            case LogicalKeyboardKey.arrowUp:
                              setState(
                                () => _selectedIndex =
                                    (selectedIndex - 1 + hits.length) %
                                    hits.length,
                              );
                              return KeyEventResult.handled;
                            case LogicalKeyboardKey.enter ||
                                LogicalKeyboardKey.numpadEnter:
                              select(hits[selectedIndex]);
                              return KeyEventResult.handled;
                            case LogicalKeyboardKey.escape:
                              _inputFocusNode.unfocus();
                              return KeyEventResult.handled;
                            default:
                              return KeyEventResult.ignored;
                          }
                        },
                        child: ListView.builder(
                          key: const ValueKey('search-results-list'),
                          itemCount: hits.length,
                          itemBuilder: (context, index) => _ResultRow(
                            hit: hits[index],
                            selected: index == selectedIndex,
                            onTap: selectionBlocked
                                ? null
                                : () => select(hits[index]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The no-matches (and not-yet-typed) state. Deliberately calm text rather
/// than an error presentation: a query matching nothing is an ordinary
/// outcome of searching, not a failure.
class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.45),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// A genuine Core failure (flow-search.md's "index unavailable or
/// unreadable" branch): rendered distinctly from the calm empty states, with
/// a retry for a transient hiccup and a pointer to the shell's rescan
/// affordance, whose full reindex (`CAP-WS-06`) is what rebuilds a broken
/// index. The panel does not drive the reindex itself — the rescan action in
/// the sidebar owns that seam and its open-edits guard.
class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.circle_alert,
                  size: 16,
                  color: colors.syncError,
                  semanticLabel: 'Error',
                ),
                const SizedBox(width: 8),
                const Flexible(child: Text('Search failed')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('search-retry'),
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refresh_cw, size: 15),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 4),
            Text(
              'If this keeps happening, run "Rescan workspace" to rebuild '
              'the search index.',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One ranked hit: the Note's title above the Core-built snippet, which
/// already carries the matched context (`snippet(notes_fts, ...)` runs
/// Rust-side). Selection reuses the tree's selection seam.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.hit,
    required this.selected,
    required this.onTap,
  });

  final NoteMetadata hit;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return KeyedSubtree(
      key: ValueKey('search-result-${hit.id}'),
      child: Material(
        key: selected ? const ValueKey('search-active-row') : null,
        color: colors.sidebar,
        child: ListTile(
          selected: selected,
          selectedTileColor: colors.accentSubtle,
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 1,
          ),
          leading: Icon(
            LucideIcons.file_text,
            size: 15,
            color: colors.accent,
            semanticLabel: 'Note',
          ),
          title: Text(
            hit.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: hit.snippet == null
              ? null
              : Text(
                  hit.snippet!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
          hoverColor: colors.hover,
          onTap: onTap,
        ),
      ),
    );
  }
}

BurlColors _colors(BuildContext context) =>
    Theme.of(context).extension<BurlColors>() ??
    (Theme.of(context).brightness == Brightness.dark
        ? BurlColors.dark
        : BurlColors.light);
