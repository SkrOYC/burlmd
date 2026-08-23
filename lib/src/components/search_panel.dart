import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider(widget.resultLimit));
    final selectionBlocked = ref.watch(noteSelectionBlockedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, semanticLabel: 'Search'),
              hintText: 'Search notes',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                ref.read(searchQueryProvider.notifier).set(value),
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
                  onRetry: () =>
                      ref.invalidate(searchResultsProvider(widget.resultLimit)),
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
                        message: 'Type to search your notes',
                      );
                    }
                    if (hits.isEmpty) {
                      return const _EmptyState(message: 'No matching notes');
                    }
                    return ListView(
                      children: [
                        for (final hit in hits)
                          _ResultRow(
                            hit: hit,
                            onTap: selectionBlocked
                                ? null
                                : () {
                                    final selected = ref
                                        .read(selectedNoteIdProvider.notifier)
                                        .select(hit.id);
                                    if (selected) {
                                      widget.onNoteSelected?.call(hit.id);
                                    }
                                  },
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The no-matches (and not-yet-typed) state. Deliberately calm text rather
/// than an error presentation: a query matching nothing is an ordinary
/// outcome of searching, not a failure.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error_outline, semanticLabel: 'Error'),
                SizedBox(width: 8),
                Flexible(child: Text('Search failed')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('search-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 4),
            Text(
              'If this keeps happening, run "Rescan workspace" to rebuild '
              'the search index.',
              style: Theme.of(context).textTheme.bodySmall,
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
  const _ResultRow({required this.hit, required this.onTap});

  final NoteMetadata hit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.description, semanticLabel: 'Note'),
      title: Text(hit.title, overflow: TextOverflow.ellipsis),
      subtitle: hit.snippet == null
          ? null
          : Text(hit.snippet!, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
