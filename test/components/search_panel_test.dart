import 'package:burlmd/src/components/search_panel.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RustApi] whose `searchNotes` never touches FFI. It records every
/// (query, limit) pair so tests can prove both that the raw query reaches
/// the Core untouched (no client-side filtering or rewriting) and that the
/// result limit arrives from the surface's parameter, not a hardcoded value.
class _StubRustApi extends RustApi {
  _StubRustApi(this.resultsByQuery);

  /// Query -> canned hits; an unlisted query yields no matches.
  final Map<String, List<NoteMetadata>> resultsByQuery;
  final List<(String query, int limit)> calls = [];

  @override
  Future<List<NoteMetadata>> searchNotes(String query, int limit) async {
    calls.add((query, limit));
    return resultsByQuery[query] ?? const [];
  }
}

/// A [RustApi] whose `searchNotes` always throws — the flow-search.md
/// "index unavailable or unreadable" branch.
class _FailingSearchApi extends _StubRustApi {
  _FailingSearchApi() : super(const {});

  @override
  Future<List<NoteMetadata>> searchNotes(String query, int limit) async {
    calls.add((query, limit));
    throw Exception('search index unavailable');
  }
}

NoteMetadata hit(
  String id,
  String title, {
  String? snippet = '…matched text…',
}) => NoteMetadata(
  id: id,
  path: '$id.md',
  title: title,
  lastModified: 0,
  snippet: snippet,
  okfConformant: true,
);

Future<ProviderContainer> _pumpPanel(
  WidgetTester tester,
  _StubRustApi api, {
  int resultLimit = 10,
  ValueChanged<String>? onNoteSelected,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return SizedBox(
                width: 300,
                child: SearchPanel(
                  resultLimit: resultLimit,
                  onNoteSelected: onNoteSelected,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a matching note appears in the results with its snippet', (
    WidgetTester tester,
  ) async {
    const query = 'fermentation';
    final api = _StubRustApi({
      query: [hit('n-1', 'Koji & Miso', snippet: '…the fermentation window…')],
    });
    await _pumpPanel(tester, api);
    expect(find.text('Koji & Miso'), findsNothing);

    await _type(tester, query);

    // The matched Note renders with the Core-built snippet beneath it.
    expect(find.text('Koji & Miso'), findsOneWidget);
    expect(find.textContaining('fermentation window'), findsOneWidget);

    // The query crossed to the Core verbatim — ranked index hits, not a
    // client-side filter — and the surface's own limit travelled with it.
    expect(api.calls, [(query, 10)]);
  });

  testWidgets('the result limit is the surface parameter, not a constant', (
    WidgetTester tester,
  ) async {
    final api = _StubRustApi({});
    await _pumpPanel(tester, api, resultLimit: 7);

    await _type(tester, 'anything');

    // The Core receives exactly the cap this panel was constructed with:
    // search_notes takes it as a parameter precisely so the surface
    // controls it (WSPC-D009 removed the hardcoded truncation).
    expect(api.calls.single.$2, 7);
  });

  testWidgets('selecting a result opens the corresponding note via the '
      'existing selection seam', (WidgetTester tester) async {
    const query = 'ledger';
    final api = _StubRustApi({
      query: [hit('n-ledger', 'The Ledger')],
    });
    String? callbackId;
    final container = await _pumpPanel(
      tester,
      api,
      onNoteSelected: (id) => callbackId = id,
    );

    await _type(tester, query);
    await tester.tap(find.text('The Ledger'));
    await tester.pumpAndSettle();

    // Both halves of the seam SHEL-E004's editor pane consumes: the
    // provider state it listens on, and the widget callback.
    expect(container.read(selectedNoteIdProvider), 'n-ledger');
    expect(callbackId, 'n-ledger');
  });

  testWidgets('a query matching nothing shows the empty state, not an error', (
    WidgetTester tester,
  ) async {
    final api = _StubRustApi({});
    await _pumpPanel(tester, api);

    await _type(tester, 'zzz-no-such-note');

    expect(find.text('No matching notes'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('punctuation in the query surfaces results without an error', (
    WidgetTester tester,
  ) async {
    // Hyphens and parentheses are FTS5 MATCH syntax when raw; the Core
    // quotes each token before it reaches the index, so from this side they
    // are just characters. The fake answers as the Core does: hits, not an
    // exception.
    const query = '(well-known) terms';
    final api = _StubRustApi({
      query: [hit('n-1', 'Glossary', snippet: '…well-known terms listed…')],
    });
    await _pumpPanel(tester, api);

    await _type(tester, query);

    expect(find.text('Glossary'), findsOneWidget);
    expect(find.textContaining('Search failed'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);

    // The punctuation reached the Core verbatim for it to neutralize —
    // nothing on this side rewrote or filtered it.
    expect(api.calls.single.$1, query);
  });

  testWidgets('a Core failure renders a distinct error state with recovery '
      'affordances (flow-search.md: index unavailable)', (
    WidgetTester tester,
  ) async {
    final api = _FailingSearchApi();
    await _pumpPanel(tester, api);

    await _type(tester, 'anything');

    // Not the calm empty states: a named failure, verbatim from the Core.
    expect(find.text('Search failed'), findsOneWidget);
    expect(find.textContaining('index unavailable'), findsOneWidget);

    // The immediate affordance re-runs the query against whatever the
    // index now answers. (Riverpod's automatic retry backoff also keeps
    // re-firing the failed provider in the background, so an exact count
    // is not stable — what matters is that the tap forced a refetch well
    // beyond the initial attempt, without waiting out that backoff.)
    final callsBeforeRetry = api.calls.length;
    await tester.tap(find.byKey(const ValueKey('search-retry')));
    // Two pumps: one to rebuild on the invalidated provider, one for its
    // failed round trip to land back in the error state.
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, greaterThan(callsBeforeRetry));

    // And the durable one points at the shell's rescan seam — the full
    // reindex is what rebuilds a broken index (CAP-WS-06).
    expect(find.textContaining('Rescan workspace'), findsOneWidget);
  });

  testWidgets('a blank query asks the Core nothing and shows the hint', (
    WidgetTester tester,
  ) async {
    final api = _StubRustApi({});
    await _pumpPanel(tester, api);

    expect(find.text('Type to search your notes'), findsOneWidget);
    expect(api.calls, isEmpty);

    // Whitespace-only is still blank: trimmed before the Core sees it.
    await _type(tester, '   ');
    expect(api.calls, isEmpty);
    expect(find.text('Type to search your notes'), findsOneWidget);
  });
}
