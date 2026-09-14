import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The text currently typed into the search surface (`SHEL-E006`).
///
/// Ephemeral UI state, not Note content (`tech-spec/guidelines.md`) —
/// exactly what a small [Notifier] may hold. Watching it re-runs
/// [searchResultsProvider] per keystroke, but each run is one indexed Core
/// round trip (`search_notes`, bm25-ranked), not client-side filtering, so
/// the sub-100ms constraint holds without debouncing.
class SearchQuery extends Notifier<String> {
  @override
  String build() => ref.watch(workspaceSessionProvider).searchQuery;

  void set(String query) =>
      ref.read(workspaceSessionProvider.notifier).setSearchQuery(query);

  void clear() => set('');
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// The ranked hits for [searchQueryProvider], served by the Core's full-text
/// index — `notes_fts` MATCH with `snippet()` and bm25 ordering all happen
/// Rust-side (CAP-FIND-01); nothing is filtered client-side.
///
/// The family parameter **is** the result limit. The Core takes it as a
/// parameter precisely so the surface controls it (WSPC-D009 removed the old
/// hardcoded cap of 50), so it flows in from the widget's own parameter
/// rather than being fixed here — hardcoding it anywhere on this side would
/// reintroduce the silent truncation the contract deleted.
///
/// A blank query returns an empty list without touching the Core at all:
/// there is nothing to match against, and the empty list renders as the
/// panel's initial hint state rather than as a failure.
///
/// Family-keyed on `limit` (not on the query) because the limit belongs to
/// the surface's configuration while the query is watched state; a change of
/// either rebuilds the provider.
final searchResultsProvider = FutureProvider.autoDispose
    .family<List<NoteMetadata>, int>((ref, limit) async {
      final query = ref.watch(searchQueryProvider).trim();
      if (query.isEmpty) return const [];
      return ref.watch(rustApiProvider).searchNotes(query, limit);
    });

/// One Core-owned title-prefix request for the keyboard title-jump surface.
///
/// This request retains the entered query verbatim. Core owns title matching,
/// including the contract's prefix-only rule, so Presentation neither trims
/// nor filters a nonempty query. An empty field has no candidate to request.
typedef TitleJumpRequest = ({String query, int limit});

final titleJumpResultsProvider = FutureProvider.autoDispose
    .family<List<NoteMetadata>, TitleJumpRequest>((ref, request) async {
      if (request.query.isEmpty) return const [];
      return ref
          .watch(rustApiProvider)
          .findNotesByTitle(request.query, request.limit);
    });

/// Core-derived Notes that link to an open Note.
///
/// The note id keys this provider, so an inbound-link response for a former
/// active Note cannot become the visible response for a later active Note.
final backlinksProvider = FutureProvider.autoDispose
    .family<List<NoteMetadata>, String>(
      (ref, noteId) => ref.watch(rustApiProvider).backlinks(noteId),
    );
