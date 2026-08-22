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
  final ValueChanged<String>? onNoteSelected;

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider(widget.resultLimit));

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
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            // A genuine Core failure is surfaced, never swallowed (the
            // SHEL-E004 rule). Punctuation-heavy queries are not in that
            // class: the Core quotes every token before MATCH, so they come
            // back as results or an empty list, never as an exception.
            error: (error, _) => _EmptyState(message: 'Search failed: $error'),
            data: (hits) {
              if (ref.read(searchQueryProvider).trim().isEmpty) {
                return const _EmptyState(message: 'Type to search your notes');
              }
              if (hits.isEmpty) {
                return const _EmptyState(message: 'No matching notes');
              }
              return ListView(
                children: [
                  for (final hit in hits)
                    _ResultRow(
                      hit: hit,
                      onTap: () {
                        ref
                            .read(selectedNoteIdProvider.notifier)
                            .select(hit.id);
                        widget.onNoteSelected?.call(hit.id);
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

/// One ranked hit: the Note's title above the Core-built snippet, which
/// already carries the matched context (`snippet(notes_fts, ...)` runs
/// Rust-side). Selection reuses the tree's selection seam.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onTap});

  final NoteMetadata hit;
  final VoidCallback onTap;

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
