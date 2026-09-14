import 'dart:async';

import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/components/note_navigation_panel.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NavigationRustApi extends RustApi {
  _NavigationRustApi({
    this.titleResults = const {},
    this.backlinkResults = const {},
  });

  final Map<String, List<NoteMetadata>> titleResults;
  final Map<String, List<NoteMetadata>> backlinkResults;
  final List<(String query, int limit)> titleCalls = [];
  final List<String> backlinkCalls = [];
  final Map<String, Completer<List<NoteMetadata>>> titleGates = {};
  Object? titleError;
  Object? backlinkError;

  @override
  Future<List<NoteMetadata>> findNotesByTitle(String query, int limit) async {
    titleCalls.add((query, limit));
    final gate = titleGates[query];
    if (gate != null) return gate.future;
    final error = titleError;
    if (error != null) throw error;
    return titleResults[query] ?? const [];
  }

  @override
  Future<List<NoteMetadata>> backlinks(String noteId) async {
    backlinkCalls.add(noteId);
    final error = backlinkError;
    if (error != null) throw error;
    return backlinkResults[noteId] ?? const [];
  }
}

NoteMetadata _note(String id, String title) => NoteMetadata(
  id: id,
  path: '$id.md',
  title: title,
  lastModified: 0,
  okfConformant: true,
);

Future<ProviderContainer> _pumpPanel(
  WidgetTester tester,
  _NavigationRustApi api, {
  String? backlinksForNoteId,
  ValueChanged<String>? onResultSelected,
  VoidCallback? onDismiss,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rustApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return SizedBox(
                width: 360,
                child: NoteNavigationPanel(
                  backlinksForNoteId: backlinksForNoteId,
                  onResultSelected: onResultSelected,
                  onDismiss: onDismiss,
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

void main() {
  testWidgets('a keyboard title jump sends the raw prefix to Core and selects '
      'the highlighted Core candidate', (tester) async {
    final api = _NavigationRustApi(
      titleResults: {
        'Pro': [_note('project-plan', 'Project plan')],
      },
    );
    String? callbackId;
    final container = await _pumpPanel(
      tester,
      api,
      onResultSelected: (id) => callbackId = id,
    );

    await tester.enterText(find.byType(TextField), 'Pro');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(api.titleCalls, [('Pro', 25)]);
    expect(container.read(selectedNoteIdProvider), 'project-plan');
    expect(callbackId, 'project-plan');
  });

  testWidgets('a backlink can be activated using ArrowDown and Enter', (
    tester,
  ) async {
    final api = _NavigationRustApi(
      backlinkResults: {
        'open-note': [_note('inbound-note', 'Inbound note')],
      },
    );
    final container = await _pumpPanel(
      tester,
      api,
      backlinksForNoteId: 'open-note',
    );

    expect(api.backlinkCalls, ['open-note']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(container.read(selectedNoteIdProvider), 'inbound-note');
  });

  testWidgets('a lifecycle admission refuses keyboard navigation', (
    tester,
  ) async {
    final api = _NavigationRustApi(
      titleResults: {
        'Pro': [_note('project-plan', 'Project plan')],
      },
    );
    final container = await _pumpPanel(tester, api);

    await tester.enterText(find.byType(TextField), 'Pro');
    await tester.pumpAndSettle();
    container.read(lifecycleEditingProvider.notifier).begin();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(container.read(selectedNoteIdProvider), isNull);
  });

  testWidgets('empty title and backlink responses are calm, distinct states', (
    tester,
  ) async {
    final api = _NavigationRustApi();
    await _pumpPanel(tester, api, backlinksForNoteId: 'open-note');

    expect(find.text('Type a title prefix to find a note'), findsOneWidget);
    expect(find.text('No notes link here'), findsOneWidget);
    expect(api.titleCalls, isEmpty);
  });

  testWidgets('Escape dismisses an embedding surface with no candidates', (
    tester,
  ) async {
    var dismissed = 0;
    await _pumpPanel(
      tester,
      _NavigationRustApi(),
      onDismiss: () => dismissed++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(dismissed, 1);
  });

  testWidgets(
    'a retrying Core title failure stays visible and its keyboard retry recovers',
    (tester) async {
      final api = _NavigationRustApi(
        titleResults: {
          'Pro': [_note('project-plan', 'Project plan')],
        },
      )..titleError = AppError.databaseError('title index offline');
      await _pumpPanel(tester, api);

      await tester.enterText(find.byType(TextField), 'Pro');
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load notes'), findsOneWidget);
      expect(find.textContaining('title index offline'), findsOneWidget);
      expect(find.text('No notes match this title'), findsNothing);

      api.titleError = null;
      final retry = find.byKey(const ValueKey('note-navigation-title-retry'));
      await tester.ensureVisible(retry);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Project plan'), findsOneWidget);
    },
  );

  testWidgets(
    'a retrying Core backlink failure stays visible and its keyboard retry recovers',
    (tester) async {
      final api = _NavigationRustApi(
        backlinkResults: {
          'open-note': [_note('inbound-note', 'Inbound note')],
        },
      )..backlinkError = AppError.databaseError('backlink index offline');
      await _pumpPanel(tester, api, backlinksForNoteId: 'open-note');

      await tester.pump();

      expect(find.text('Could not load notes'), findsOneWidget);
      expect(find.textContaining('backlink index offline'), findsOneWidget);
      expect(find.text('No notes link here'), findsNothing);

      api.backlinkError = null;
      final retry = find.byKey(
        const ValueKey('note-navigation-backlinks-retry'),
      );
      await tester.ensureVisible(retry);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Inbound note'), findsOneWidget);
    },
  );

  testWidgets('a completed earlier prefix never replaces the latest response', (
    tester,
  ) async {
    final api = _NavigationRustApi();
    final earlier = Completer<List<NoteMetadata>>();
    final latest = Completer<List<NoteMetadata>>();
    api.titleGates['P'] = earlier;
    api.titleGates['Pr'] = latest;
    await _pumpPanel(tester, api);

    await tester.enterText(find.byType(TextField), 'P');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Pr');
    await tester.pump();

    latest.complete([_note('project', 'Project')]);
    await tester.pumpAndSettle();
    earlier.complete([_note('personal', 'Personal')]);
    await tester.pumpAndSettle();

    expect(find.text('Project'), findsOneWidget);
    expect(find.text('Personal'), findsNothing);
  });

  testWidgets('keyboard title navigation keeps the selected row in view', (
    tester,
  ) async {
    final hits = List.generate(
      25,
      (index) => _note('result-$index', 'Result $index'),
    );
    final api = _NavigationRustApi(titleResults: {'Result': hits});
    await _pumpPanel(tester, api);

    await tester.enterText(find.byType(TextField), 'Result');
    await tester.pumpAndSettle();
    void expectSelectedInViewport(int index) {
      final selected = find.byKey(
        ValueKey('note-navigation-title-result-$index'),
      );
      final viewport = find.byKey(const ValueKey('note-navigation-results'));
      final selectedRect = tester.getRect(selected);
      final viewportRect = tester.getRect(viewport);
      expect(selectedRect.top, greaterThanOrEqualTo(viewportRect.top));
      expect(selectedRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
    }

    for (var index = 0; index < 20; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expectSelectedInViewport(20);

    for (var index = 20; index > 0; index--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expectSelectedInViewport(0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expectSelectedInViewport(24);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expectSelectedInViewport(0);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'note-navigation-input',
    );
  });
}
