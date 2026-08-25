import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';

void _expectRectNear(WidgetTester tester, Finder finder, Rect expected) {
  final actual = tester.getRect(finder);
  expect(actual.left, closeTo(expected.left, 1));
  expect(actual.top, closeTo(expected.top, 1));
  expect(actual.width, closeTo(expected.width, 1));
  expect(actual.height, closeTo(expected.height, 1));
}

void main() {
  testWidgets('capture controller drives the complete reference matrix', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = FixtureCaptureController();
    await tester.pumpWidget(
      MaterialApp(home: FixtureReferenceShell(captureController: controller)),
    );
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);

    Future<Map<String, Object?>> command(
      String name, [
      Map<String, Object?> arguments = const <String, Object?>{},
    ]) async {
      final response = await controller.execute(name, arguments);
      await tester.pumpAndSettle();
      return response;
    }

    Future<Map<String, Object?>> settle() async {
      final pending = controller.execute('settle');
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump();
      }
      return pending;
    }

    var response = await command('reset-rendered-dark-top');
    expect(response['visibleMarkerKey'], 'fixture-focaccia-h1');
    expect(response['settled'], isFalse);
    expect(response['shellSize'], const <String, double>{
      'width': 1440,
      'height': 900,
    });
    expect(find.byKey(const ValueKey('fixture-raw-intro')), findsNothing);
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsNothing,
    );

    response = await command('select-light');
    expect(
      (response['selectedState']! as Map<String, Object?>)['theme'],
      'light',
    );
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('fixture-reference-shell'))),
      ).brightness,
      Brightness.light,
    );
    response = await command('select-dark');
    expect(
      (response['selectedState']! as Map<String, Object?>)['theme'],
      'dark',
    );

    for (final (name, key) in [
      ('openPreferences', 'fixture-preferences-drawer'),
      ('openSearch', 'fixture-search-palette'),
      ('openSync', 'fixture-sync-state-pendingSuggestions'),
      ('openHistory', 'fixture-history-drawer'),
      ('openDeleteDialog', 'fixture-delete-dialog'),
    ]) {
      response = await command(name);
      expect(response['visibleMarkerKey'], key);
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      await command('close-overlay');
      expect(find.byKey(ValueKey(key)), findsNothing);
    }

    await command('openSearch');
    await command('set_search_query', <String, Object?>{'query': 'focaccia'});
    await command('set-search-scope', <String, Object?>{'scope': 'Titles'});
    response = await command('setSearchResult', <String, Object?>{
      'result': 'Weekly Review: August 2026 (W34)',
    });
    final searchState = response['selectedState']! as Map<String, Object?>;
    expect(searchState['searchQuery'], 'focaccia');
    expect(searchState['searchScope'], 'Titles');
    final commandSearchInput = tester.widget<EditableText>(
      find.byKey(const ValueKey('fixture-search-input')),
    );
    expect(
      commandSearchInput.controller.selection,
      const TextSelection.collapsed(offset: 8),
    );
    expect(commandSearchInput.focusNode.hasFocus, isFalse);
    expect(searchState['searchResult'], 'Weekly Review: August 2026 (W34)');
    final selectedSearch = tester.widget<Container>(
      find.byKey(
        const ValueKey(
          'fixture-search-result-Weekly Review: August 2026 (W34)',
        ),
      ),
    );
    expect(
      (selectedSearch.decoration! as BoxDecoration).color,
      const Color(0xff25252c),
    );
    await command('close');

    await command('open-sync');
    for (final state in [
      'localOnly',
      'connectedIdle',
      'syncing',
      'offline',
      'pendingSuggestions',
      'authRequired',
      'syncError',
      'externalChanged',
    ]) {
      response = await command('setSyncState', <String, Object?>{
        'state': state,
      });
      expect(response['visibleMarkerKey'], 'fixture-sync-state-$state');
      expect(find.byKey(ValueKey('fixture-sync-state-$state')), findsOneWidget);
    }
    await command('close');

    await command('open-history');
    for (final snapshot in ['9a31f0e', '4c88b21', '2e19a45']) {
      response = await command('historySnapshot', <String, Object?>{
        'snapshot': snapshot,
      });
      expect(
        (response['selectedState']! as Map<String, Object?>)['historySnapshot'],
        snapshot,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-history-snapshot-details')),
          matching: find.text(snapshot),
        ),
        findsOneWidget,
      );
    }
    await command('close');

    await command('showFocacciaRendered');
    expect(find.byKey(const ValueKey('fixture-focaccia-h1')), findsOneWidget);
    await command('showFocacciaRaw');
    expect(find.byKey(const ValueKey('fixture-raw-intro')), findsOneWidget);
    await command('showFocacciaSuggestion');
    response = await settle();
    expect(response['settled'], isTrue);
    final suggestionGeometry = response['captureGeometry']! as Map;
    expect(suggestionGeometry['positionGeneration'], greaterThan(0));
    expect(suggestionGeometry['consecutiveStableFrames'], 3);
    expect((suggestionGeometry['targetRect']! as Map)['top'], closeTo(450, 1));
    expect((response['documentScroll']! as Map)['offset'], greaterThan(0));
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsOneWidget,
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-anchor-suggestion')),
      const Rect.fromLTWH(569, 450, 584, 263),
    );

    await command('selectHomelabRendered');
    response = await settle();
    final renderedGeometry = response['captureGeometry']! as Map;
    expect(renderedGeometry['consecutiveStableFrames'], 3);
    expect((renderedGeometry['targetRect']! as Map)['top'], closeTo(465, 1));
    expect(find.byKey(const ValueKey('fixture-code-rendered')), findsOneWidget);
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-anchor-code-rendered')),
      const Rect.fromLTWH(569, 465, 584, 357),
    );
    expect(
      (response['selectedState']! as Map<String, Object?>)['note'],
      'homelab',
    );
    await command('copyHomelabCode');
    expect(find.text('Copied'), findsOneWidget);
    await command('selectHomelabRaw');
    response = await settle();
    final rawGeometry = response['captureGeometry']! as Map;
    expect(rawGeometry['consecutiveStableFrames'], 3);
    expect((rawGeometry['targetRect']! as Map)['top'], closeTo(447, 1));
    expect(
      find.byKey(const ValueKey('fixture-raw-homelab-code')),
      findsOneWidget,
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-anchor-code-raw')),
      const Rect.fromLTWH(569, 447, 584, 416),
    );
    expect(
      (response['documentScroll']! as Map)['offset'],
      lessThanOrEqualTo(216),
      reason:
          'the reduced raw spacer must not scroll the Homelab title farther '
          'above the document viewport than the calibrated capture state',
    );

    response = await command('pinLinkPopover');
    response = await settle();
    final linkGeometry = response['captureGeometry']! as Map;
    expect(linkGeometry['consecutiveStableFrames'], 3);
    expect((linkGeometry['targetRect']! as Map)['top'], closeTo(797, 1));
    expect((linkGeometry['popoverRect']! as Map)['top'], closeTo(823, 1));
    expect(
      (response['selectedState']! as Map<String, Object?>)['suggestionOpen'],
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsOneWidget);
    final linkRect = tester.getRect(
      find.byKey(const ValueKey('fixture-anchor-link-hover')),
    );
    final popoverRect = tester.getRect(
      find.byKey(const ValueKey('fixture-link-popover')),
    );
    expect(linkRect.top, closeTo(797, 1));
    expect(linkRect.size, const Size(126, 25));
    expect(popoverRect.left, closeTo(linkRect.left - 3, 1));
    expect(popoverRect.top, closeTo(linkRect.top + 26, 1));
    expect(popoverRect.size, const Size(229, 30));

    response = await command('selectRecoveredPopover');
    expect(
      find.byKey(const ValueKey('fixture-note-recovered')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsNothing);
    expect(
      find.byKey(const ValueKey('fixture-recovery-link-popover')),
      findsNothing,
    );
    final recoveredState = response['selectedState']! as Map<String, Object?>;
    expect(recoveredState['suggestionOpen'], isFalse);
    expect(recoveredState['linkPopoverPinned'], isFalse);

    response = await command('resize-ready');
    expect(response['shellSize'], const <String, double>{
      'width': 1440,
      'height': 900,
    });
    await command('position-anchor', <String, Object?>{
      'id': 'suggestion',
      'top': 450,
    });
    // A caller can ask for an explicit anchor even when it is not the active
    // capture state; the shell remains valid and the next state settles it.
    await settle();
    expect(controller.currentState['command'], 'settle');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.isAttached, isFalse);
    await expectLater(controller.execute('reset'), throwsA(isA<StateError>()));
  });

  testWidgets('controller settle owns no-pending-frame anchor correction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = FixtureCaptureController();
    await tester.pumpWidget(
      MaterialApp(home: FixtureReferenceShell(captureController: controller)),
    );
    await tester.pumpAndSettle();

    Future<Map<String, Object?>> settleWithoutPendingFrame() async {
      final pending = controller.execute('settle');
      // A Flutter Driver data handler has no WidgetTester pump. This supplies
      // only the frames requested by the controller itself, after it has
      // already started settling from an otherwise idle fixture.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump();
      }
      return pending;
    }

    Future<void> expectMeasuredState(
      String command,
      String anchor,
      double top, {
      double? popoverTop,
    }) async {
      await controller.execute(command);
      final response = await settleWithoutPendingFrame();
      final geometry = response['captureGeometry']! as Map;
      expect(response['settled'], isTrue);
      expect(geometry['anchorId'], anchor);
      expect(geometry['consecutiveStableFrames'], 3);
      expect((geometry['targetRect']! as Map)['top'], closeTo(top, 1));
      expect((geometry['scroll']! as Map).containsKey('offset'), isTrue);
      expect(geometry['positionGeneration'], greaterThanOrEqualTo(0));
      if (popoverTop != null) {
        expect(
          (geometry['popoverRect']! as Map)['top'],
          closeTo(popoverTop, 1),
        );
      }
    }

    await expectMeasuredState('showFocacciaSuggestion', 'suggestion', 450);
    await expectMeasuredState('selectHomelabRendered', 'code-rendered', 465);
    await expectMeasuredState('selectHomelabRaw', 'code-raw', 447);
    await expectMeasuredState(
      'pinLinkPopover',
      'link-hover',
      797,
      popoverTop: 823,
    );
  });

  testWidgets(
    'controller-only code lead preserves natural code capture baselines',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = FixtureCaptureController();
      await tester.pumpWidget(
        MaterialApp(home: FixtureReferenceShell(captureController: controller)),
      );
      await tester.pumpAndSettle();

      Future<Map<String, Object?>> settle() async {
        final pending = controller.execute('settle');
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump();
        }
        return pending;
      }

      Future<void> resetHomelabScroll() async {
        final scrollable = find
            .descendant(
              of: find.byKey(const ValueKey('fixture-note-homelab')),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.minScrollExtent);
        await tester.pump();
        expect(position.pixels, position.minScrollExtent);
      }

      await controller.execute('selectHomelabRendered');
      await tester.pumpAndSettle();
      await resetHomelabScroll();
      final renderedAnchor = find.byKey(
        const ValueKey('fixture-anchor-code-rendered'),
      );
      // At scroll zero the real layout starts below the target; the actual
      // controller correction below must be able to consume that lead.
      expect(tester.getTopLeft(renderedAnchor).dy, greaterThanOrEqualTo(465));

      await controller.execute('position-anchor', <String, Object?>{
        'id': 'code-rendered',
        'top': 465,
      });
      final rendered = await settle();
      expect(rendered['settled'], isTrue);
      expect(
        ((rendered['captureGeometry']! as Map)['targetRect']! as Map)['top'],
        closeTo(465, 1),
      );

      await controller.execute('selectHomelabRaw');
      final raw = await settle();
      expect(raw['settled'], isTrue);
      final rawGeometry = raw['captureGeometry']! as Map;
      expect(rawGeometry['anchorId'], 'code-raw');
      expect(rawGeometry['consecutiveStableFrames'], 3);
      expect((rawGeometry['targetRect']! as Map)['top'], closeTo(447, 1));
    },
  );

  testWidgets('fixture exposes driven internal-link states', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VisualParityFixture()));

    expect(find.byKey(const ValueKey('fixture-link-normal')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-link-hover')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-link-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-code-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-code-language')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fixture-link-normal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsOneWidget);
  });

  testWidgets('reference shell drives deterministic capture overlays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-preferences')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-preferences-drawer')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-preferences-drawer')))
          .width,
      448,
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-preferences-drawer')),
      const Rect.fromLTWH(992, 0, 448, 900),
    );
    // The positioned caption line boxes begin three pixels above the measured
    // prototype glyph tops (79/183/313/488/570 respectively).
    for (final (key, top) in [
      ('Appearance-Theme', 76.0),
      ('Base-Reading-Size', 180.0),
      ('Prose-Line-Measure', 310.0),
      ('Desktop-Platform-Chrome', 485.0),
      ('Editor-Features', 567.0),
    ]) {
      final caption = tester.getTopLeft(
        find.byKey(ValueKey('fixture-preferences-section-$key')),
      );
      expect(caption.dx, closeTo(1012, 1));
      expect(caption.dy, closeTo(top, 1));
    }
    for (final (key, rect) in [
      (
        'fixture-preferences-Appearance-Theme-0',
        const Rect.fromLTWH(1013, 102, 200, 55),
      ),
      (
        'fixture-preferences-Appearance-Theme-1',
        const Rect.fromLTWH(1221, 102, 199, 55),
      ),
      (
        'fixture-preferences-Base-Reading-Size-0',
        const Rect.fromLTWH(1013, 206, 200, 36),
      ),
      (
        'fixture-preferences-Base-Reading-Size-1',
        const Rect.fromLTWH(1221, 206, 199, 36),
      ),
      (
        'fixture-preferences-Base-Reading-Size-2',
        const Rect.fromLTWH(1013, 250, 200, 37),
      ),
      (
        'fixture-preferences-Base-Reading-Size-3',
        const Rect.fromLTWH(1221, 250, 199, 37),
      ),
      (
        'fixture-preferences-Prose-Line-Measure-0',
        const Rect.fromLTWH(1013, 336, 200, 36),
      ),
      (
        'fixture-preferences-Prose-Line-Measure-1',
        const Rect.fromLTWH(1221, 336, 199, 36),
      ),
      (
        'fixture-preferences-Prose-Line-Measure-2',
        const Rect.fromLTWH(1013, 380, 200, 37),
      ),
      (
        'fixture-preferences-Prose-Line-Measure-3',
        const Rect.fromLTWH(1221, 380, 199, 37),
      ),
      (
        'fixture-preferences-Prose-Line-Measure-4',
        const Rect.fromLTWH(1013, 425, 200, 37),
      ),
      (
        'fixture-preferences-Desktop-Platform-Chrome-0',
        const Rect.fromLTWH(1013, 510, 130, 33),
      ),
      (
        'fixture-preferences-Desktop-Platform-Chrome-1',
        const Rect.fromLTWH(1151, 510, 131, 33),
      ),
      (
        'fixture-preferences-Desktop-Platform-Chrome-2',
        const Rect.fromLTWH(1290, 510, 130, 33),
      ),
    ]) {
      _expectRectNear(tester, find.byKey(ValueKey(key)), rect);
    }
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-preferences-focus-mode')),
      const Rect.fromLTWH(1013, 592, 407, 55),
    );
    expect(find.text('Preferences saved locally'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fixture-preferences-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-search')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-search-palette')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-search-palette')))
          .width,
      672,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-search-palette')))
          .height,
      239,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('fixture-search-palette')))
          .dy,
      closeTo(108, .1),
    );
    expect(
      find.byKey(const ValueKey('fixture-search-density')),
      findsOneWidget,
    );
    expect(find.text('2 matches'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'fixture-search-result-Weekly Review: August 2026 (W34)',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'fixture-search-result-Homelab Architecture & Local Services',
        ),
      ),
      findsNothing,
    );
    for (final scope in ['All', 'Titles', 'Content']) {
      await tester.tap(find.byKey(ValueKey('fixture-search-scope-$scope')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('fixture-search-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-sync')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-sync-inspector')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-sync-inspector'))),
      const Size(384, 328),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('fixture-sync-inspector'))),
      const Offset(528, 286),
    );
    expect(find.textContaining('Personal-Vault'), findsOneWidget);
    final syncKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    for (final (index, state) in [
      'localOnly',
      'connectedIdle',
      'syncing',
      'offline',
      'pendingSuggestions',
      'authRequired',
      'syncError',
      'externalChanged',
    ].indexed) {
      await tester.sendKeyDownEvent(syncKeys[index]);
      await tester.sendKeyUpEvent(syncKeys[index]);
      await tester.pump();
      expect(find.byKey(ValueKey('fixture-sync-state-$state')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('fixture-sync-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-history')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-history-drawer')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-history-drawer')))
          .width,
      576,
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-history-drawer')),
      const Rect.fromLTWH(864, 0, 576, 900),
    );
    for (final (key, rect) in [
      (
        'fixture-history-snapshot-9a31f0e',
        const Rect.fromLTWH(873, 97, 207, 89),
      ),
      (
        'fixture-history-snapshot-4c88b21',
        const Rect.fromLTWH(873, 192, 207, 90),
      ),
      (
        'fixture-history-snapshot-2e19a45',
        const Rect.fromLTWH(873, 288, 207, 90),
      ),
    ]) {
      _expectRectNear(tester, find.byKey(ValueKey(key)), rect);
    }
    for (final hash in ['9a31f0e', '4c88b21', '2e19a45']) {
      await tester.tap(find.byKey(ValueKey('fixture-history-snapshot-$hash')));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('fixture-history-diff')), findsOneWidget);
    expect(find.textContaining('Status: HEAD'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-history-restore')))
          .width,
      greaterThan(300),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-history-restore')),
      const Rect.fromLTWH(1105, 347, 319, 34),
    );
    await tester.tap(find.byKey(const ValueKey('fixture-history-done')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('fixture-navigator-focaccia')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-tree-delete')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fixture-delete-path')))
          .data,
      'Kitchen & Recipes/sourdough-focaccia.md',
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-cancel')),
      const Rect.fromLTWH(747, 516, 62, 26),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-confirm')),
      const Rect.fromLTWH(817, 517, 78, 24),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-trash-slot')),
      const Rect.fromLTWH(829, 522, 14, 14),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-warning-shield')),
      const Rect.fromLTWH(556, 450, 14, 14),
    );
    await tester.tap(find.byKey(const ValueKey('fixture-delete-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-delete-dialog')), findsNothing);
  });

  testWidgets('reference shell promotes only the prototype intro paragraph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-navigator'))).width,
      288,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-note-focaccia'))).width,
      648,
    );
    final h1 = tester.widget<Text>(
      find.byKey(const ValueKey('fixture-focaccia-h1')),
    );
    expect(h1.style!.fontSize, 30);
    expect(h1.style!.height, 1.2);
    expect(h1.style!.fontWeight, FontWeight.w700);
    expect(h1.style!.letterSpacing, -.79);
    expect(h1.style!.color, const Color(0xfff5f5f5));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-focaccia-table')))
          .width,
      584,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('fixture-focaccia-table')))
          .height,
      inInclusiveRange(220, 250),
    );
    final table = tester.widget<Table>(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-focaccia-table')),
        matching: find.byType(Table),
      ),
    );
    expect(table.columnWidths, const <int, TableColumnWidth>{
      0: FixedColumnWidth(208),
      1: FixedColumnWidth(90),
      2: FixedColumnWidth(86),
      3: FixedColumnWidth(200),
    });
    expect(
      tester.getRect(find.byKey(const ValueKey('fixture-focaccia-table'))).left,
      569,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('fixture-focaccia-table')))
          .right,
      1153,
    );

    await tester.tap(find.byKey(const ValueKey('fixture-focaccia-intro')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-raw-intro')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-focaccia-h1')), findsOneWidget);
  });

  testWidgets('reference overlay ROI primitives keep measured geometry and input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-search')));
    await tester.pumpAndSettle();
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-search-header')),
      const Rect.fromLTWH(384, 108, 672, 45),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-search-escape-keycap')),
      const Rect.fromLTWH(1004, 120, 36, 21),
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('fixture-search-palette')),
          )
          .color,
      const Color(0xff18181c),
    );
    final selectedSearchRow = tester.widget<Container>(
      find.byKey(
        const ValueKey(
          'fixture-search-result-Sourdough Focaccia with Rosemary & Sea Salt',
        ),
      ),
    );
    final selectedSearchDecoration =
        selectedSearchRow.decoration! as BoxDecoration;
    expect(selectedSearchDecoration.color, const Color(0xff25252c));
    expect(selectedSearchDecoration.borderRadius, BorderRadius.circular(6));
    final selectedSearchTitle = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'fixture-search-result-Sourdough Focaccia with Rosemary & Sea Salt',
          ),
        ),
        matching: find.text('Sourdough Focaccia with Rosemary & Sea Salt'),
      ),
    );
    expect(selectedSearchTitle.style!.letterSpacing, -.25);
    expect(selectedSearchTitle.style!.color, const Color(0xffe8e6df));
    final selectedSearchPath = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'fixture-search-result-Sourdough Focaccia with Rosemary & Sea Salt',
          ),
        ),
        matching: find.text('Kitchen & Recipes/sourdough-focaccia.md'),
      ),
    );
    expect(selectedSearchPath.style!.fontSize, 10);
    expect(selectedSearchPath.style!.height, 1.5);
    expect(selectedSearchPath.style!.color, const Color(0xffa3a3a3));
    final resultIcons = tester.widgetList<Icon>(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'fixture-search-result-Weekly Review: August 2026 (W34)',
          ),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(resultIcons.single.color, const Color(0xffa1a1aa));
    final searchInput = find.byKey(const ValueKey('fixture-search-input'));
    expect(
      tester.widget<EditableText>(searchInput).controller.text,
      'sourdough',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-overlay-surface'))),
      const Size(1440, 900),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-overlay-scrim'))),
      const Size(1440, 900),
    );
    expect(
      tester.widget<EditableText>(searchInput).controller.selection,
      const TextSelection.collapsed(offset: 9),
    );
    expect(
      tester.widget<EditableText>(searchInput).focusNode.hasFocus,
      isFalse,
    );
    await tester.enterText(searchInput, 'focaccia');
    await tester.pump();
    expect(
      tester.widget<EditableText>(searchInput).controller.text,
      'focaccia',
    );
    await tester.tap(find.byKey(const ValueKey('fixture-search-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-sync')));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('fixture-sync-state-picker'));
    final selectorRect = tester.getRect(selector);
    expect(selectorRect.left, closeTo(544, 1));
    expect(selectorRect.width, closeTo(350, 1));
    expect(selectorRect.height, closeTo(30, 1));
    expect(find.byType(DropdownButtonHideUnderline), findsOneWidget);
    final selectDecoration =
        tester.widget<Container>(selector).decoration! as BoxDecoration;
    expect(selectDecoration.color, const Color(0xff141416));
    expect(selectDecoration.border!.top.color, const Color(0xff2a2a30));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('fixture-sync-state-externalChanged')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('fixture-sync-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fixture-shell-preferences')));
    await tester.pumpAndSettle();
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-preferences-focus-mode')),
      const Rect.fromLTWH(1013, 592, 407, 55),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('fixture-preferences-focus-toggle')),
      ),
      const Size(36, 20),
    );
    await tester.tap(
      find.byKey(const ValueKey('fixture-preferences-focus-toggle')),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
      Alignment.centerRight,
    );
    await tester.tap(
      find.byKey(const ValueKey('fixture-preferences-Appearance-Theme-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixture-preferences-done')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('fixture-editor-underlay')),
          )
          .color,
      BurlColors.light.editor,
    );
    final lightQuote = tester.widget<Container>(
      find.byKey(const ValueKey('fixture-focaccia-quote')),
    );
    expect(
      (lightQuote.decoration! as BoxDecoration).color,
      const Color(0xfff7f5ee),
    );
    final lightTable = tester.widget<Container>(
      find.byKey(const ValueKey('fixture-focaccia-table')),
    );
    expect(
      (lightTable.decoration! as BoxDecoration).color,
      const Color(0xfff7f5ee),
    );

    await tester.tap(find.byKey(const ValueKey('fixture-shell-history')));
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('fixture-history-restore'));
    _expectRectNear(tester, restore, const Rect.fromLTWH(1105, 347, 319, 34));
    expect(
      find.descendant(of: restore, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
    final historyDetails = tester.widget<Container>(
      find.byKey(const ValueKey('fixture-history-snapshot-details')),
    );
    final historyDecoration = historyDetails.decoration! as BoxDecoration;
    expect(historyDecoration.color, const Color(0xff141416));
    expect(historyDecoration.border!.top.color, const Color(0xff2a2a30));
    await tester.tap(find.byKey(const ValueKey('fixture-history-done')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('fixture-navigator-focaccia')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-tree-delete')));
    await tester.pumpAndSettle();
    for (final key in [
      const ValueKey('fixture-delete-cancel'),
      const ValueKey('fixture-delete-confirm'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
    }
    final deleteConfirm = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-delete-confirm')),
        matching: find.byType(Container),
      ),
    );
    expect(
      (deleteConfirm.decoration! as BoxDecoration).color,
      const Color(0xffec003f),
    );
    final deleteTitle = tester.widget<Text>(
      find.text('Delete “Sourdough Focaccia with Rosemary & Sea Salt”?'),
    );
    expect(deleteTitle.style!.fontSize, 14);
    expect(deleteTitle.style!.height, 20 / 14);
    expect(deleteTitle.style!.fontWeight, FontWeight.w500);
    expect(deleteTitle.style!.letterSpacing, isNull);
    expect(deleteTitle.style!.color, const Color(0xffe4e4e7));
    _expectRectNear(
      tester,
      find.text('Delete “Sourdough Focaccia with Rosemary & Sea Salt”?'),
      const Rect.fromLTWH(545, 362.4, 320, 40),
    );
    final deletePath = tester.widget<Text>(
      find.byKey(const ValueKey('fixture-delete-path')),
    );
    expect(deletePath.style!.fontSize, 11);
    expect(deletePath.style!.height, 1.5);
    expect(deletePath.style!.letterSpacing, 0);
    expect(deletePath.style!.color, const Color(0xffa1a1a1));
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-path')),
      const Rect.fromLTWH(545, 404.4, 350, 16.5),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-git-explainer')),
      const Rect.fromLTWH(545, 437, 350, 58),
    );
    _expectRectNear(
      tester,
      find.byKey(const ValueKey('fixture-delete-warning-shield')),
      const Rect.fromLTWH(556, 450, 14, 14),
    );
    final deleteExplainer = tester.widget<Container>(
      find.byKey(const ValueKey('fixture-delete-git-explainer')),
    );
    final explainerDecoration = deleteExplainer.decoration! as BoxDecoration;
    expect(explainerDecoration.color, const Color(0xff141416));
    expect(explainerDecoration.border!.top.color, const Color(0xff2a2a30));
    final explainerCopy = tester.widget<Text>(
      find.text(
        'This note will be removed from your active workspace, but prior revisions remain safely recorded in local Git history.',
      ),
    );
    expect(explainerCopy.style!.fontSize, 11);
    expect(explainerCopy.style!.height, 1.625);
    expect(explainerCopy.style!.letterSpacing, -.33);
    expect(explainerCopy.style!.color, const Color(0xffd4d4d4));
    final cancelLabel = tester.widget<Text>(find.text('Cancel'));
    expect(cancelLabel.style!.fontSize, 12);
    expect(cancelLabel.style!.height, 16 / 12);
    expect(cancelLabel.style!.fontWeight, FontWeight.w400);
    expect(cancelLabel.style!.letterSpacing, -.35);
    final deleteLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-delete-confirm')),
        matching: find.text('Delete'),
      ),
    );
    expect(deleteLabel.style!.fontSize, 12);
    expect(deleteLabel.style!.height, 16 / 12);
    expect(deleteLabel.style!.fontWeight, FontWeight.w400);
    expect(deleteLabel.style!.letterSpacing, -.15);
    await tester.tap(find.byKey(const ValueKey('fixture-delete-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('reference shell anchors prototype capture states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    final focacciaScroll = find.descendant(
      of: find.byKey(const ValueKey('fixture-note-focaccia')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      300,
      scrollable: focacciaScroll,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
    );
    await tester.pumpAndSettle();
    final suggestion = tester.getRect(
      find.byKey(const ValueKey('fixture-anchor-suggestion')),
    );
    expect(suggestion.top, greaterThanOrEqualTo(84));

    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    final renderedCode = tester.getRect(
      find.byKey(const ValueKey('fixture-anchor-code-rendered')),
    );
    expect(renderedCode.top, greaterThan(84));
    await tester.tap(find.byKey(const ValueKey('fixture-code-rendered')));
    await tester.pumpAndSettle();
    final rawCode = tester.getRect(
      find.byKey(const ValueKey('fixture-anchor-code-raw')),
    );
    expect(rawCode.top, greaterThan(84));

    await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('fixture-link-normal'));
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('fixture-note-focaccia')),
        matching: find.byType(Scrollable),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(link));
    await tester.pumpAndSettle();
    final popover = tester.getRect(
      find.byKey(const ValueKey('fixture-link-popover')),
    );
    final linkRect = tester.getRect(link);
    expect(linkRect.top, greaterThan(84));
    expect(popover.left, closeTo(linkRect.left - 3, .1));
    expect(popover.top, closeTo(linkRect.top + 26, .1));
  });

  testWidgets('reference shell pins exact suggestion and code interiors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    final focacciaScroll = find.descendant(
      of: find.byKey(const ValueKey('fixture-note-focaccia')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      300,
      scrollable: focacciaScroll,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
    );
    final suggestion = tester.getRect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
    );
    final removedRect = tester.getRect(
      find.byKey(const ValueKey('fixture-suggestion-removed')),
    );
    final addedRect = tester.getRect(
      find.byKey(const ValueKey('fixture-suggestion-added')),
    );
    final acceptRect = tester.getRect(
      find.byKey(const ValueKey('fixture-suggestion-accept')),
    );
    final keepLocalRect = tester.getRect(
      find.byKey(const ValueKey('fixture-suggestion-keep-local')),
    );
    expect(suggestion.width, greaterThan(0));
    expect(suggestion.height, greaterThan(0));
    expect(removedRect.left, greaterThanOrEqualTo(suggestion.left));
    expect(addedRect.top, greaterThan(removedRect.bottom));
    expect(acceptRect.top, greaterThan(addedRect.bottom));
    expect(keepLocalRect.left, greaterThan(acceptRect.right));
    final removed = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-suggestion-removed')),
        matching: find.byType(Text),
      ),
    );
    final added = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-suggestion-added')),
        matching: find.byType(Text),
      ),
    );
    expect(removed.maxLines, 2);
    expect(added.maxLines, 4);
    expect(removed.style!.fontFamily, burlPrototypeMonoFontFamily);
    expect(removed.style!.fontSize, 13);
    expect(removed.style!.height, 1.625);
    expect(added.style!.fontFamily, burlPrototypeMonoFontFamily);
    expect(added.style!.fontSize, 13);
    expect(added.style!.height, 1.625);

    final focacciaPosition = tester
        .state<ScrollableState>(focacciaScroll)
        .position;
    focacciaPosition.jumpTo(focacciaPosition.maxScrollExtent);
    await tester.pump();
    final acceptSuggestion = find.byKey(
      const ValueKey('fixture-suggestion-accept'),
    );
    await tester.ensureVisible(acceptSuggestion);
    await tester.tap(acceptSuggestion);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    final renderedRect = tester.getRect(
      find.byKey(const ValueKey('fixture-code-rendered')),
    );
    final headerRect = tester.getRect(
      find.byKey(const ValueKey('fixture-code-header')),
    );
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey('fixture-code-body')),
    );
    expect(renderedRect.width, greaterThan(0));
    expect(headerRect.left, closeTo(renderedRect.left, 1));
    expect(headerRect.top, closeTo(renderedRect.top, 1));
    expect(headerRect.width, closeTo(renderedRect.width, 1));
    expect(bodyRect.top, closeTo(headerRect.bottom, 1));
    expect(bodyRect.bottom, closeTo(renderedRect.bottom, 1));
    final renderedYaml = tester.widget<Text>(
      find.byKey(const ValueKey('fixture-homelab-yaml')),
    );
    expect(renderedYaml.data, isNot(contains('```')));
    expect(renderedYaml.style!.fontFamily, burlPrototypeMonoFontFamily);
    expect(renderedYaml.style!.fontSize, 12.5);
    expect(renderedYaml.style!.height, 1.625);
    await tester.tap(find.byKey(const ValueKey('fixture-code-copy')));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fixture-code-rendered')));
    await tester.pumpAndSettle();
    final rawOuter = tester.getRect(
      find.byKey(const ValueKey('fixture-raw-homelab-code')),
    );
    final raw = tester.widget<TextField>(
      find.byKey(const ValueKey('fixture-raw-input-homelab-code')),
    );
    expect(raw.controller!.text, startsWith('```yaml'));
    expect(raw.decoration!.contentPadding, EdgeInsets.zero);
    expect(raw.style!.fontFamily, burlPrototypeMonoFontFamily);
    expect(raw.style!.fontSize, 14);
    expect(raw.style!.height, 1.625);
    final rawInput = tester.getRect(
      find.byKey(const ValueKey('fixture-raw-input-homelab-code')),
    );
    expect(rawOuter.width, closeTo(renderedRect.width, 1));
    expect(rawInput.left, greaterThan(rawOuter.left));
    expect(rawInput.top, greaterThan(rawOuter.top));
    expect(rawInput.right, lessThan(rawOuter.right));
    expect(rawInput.bottom, lessThan(rawOuter.bottom));
  });

  testWidgets('reference shell uses measured interior icons and open-note card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    final focacciaScroll = find.descendant(
      of: find.byKey(const ValueKey('fixture-note-focaccia')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      300,
      scrollable: focacciaScroll,
    );
    final suggestionIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('fixture-suggestion-git-pull-icon')),
    );
    expect(suggestionIcon.icon, LucideIcons.git_pull_request);
    expect(suggestionIcon.size, 12);
    expect(suggestionIcon.color, BurlColors.dark.accent);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fixture-suggestion-header')))
          .data,
      isNot(contains('•')),
    );
    expect(find.text('Today at 19:42'), findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.byKey(const ValueKey('fixture-suggestion-timestamp')),
          )
          .didExceedMaxLines,
      isFalse,
    );
    final accept = tester.widget<TextButton>(
      find.byKey(const ValueKey('fixture-suggestion-accept')),
    );
    expect(
      accept.style!.backgroundColor!.resolve(<WidgetState>{}),
      BurlColors.dark.textPrimary,
    );

    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    final yaml = find.byKey(const ValueKey('fixture-homelab-yaml'));
    expect(tester.getTopLeft(yaml).dx, closeTo(581, 1));
    expect(tester.widget<Text>(yaml).textAlign, TextAlign.left);
    final copyIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('fixture-code-copy-icon')),
    );
    expect(copyIcon.icon, LucideIcons.copy);
    expect(copyIcon.size, 12);
    await tester.tap(find.byKey(const ValueKey('fixture-code-rendered')));
    await tester.pumpAndSettle();
    final raw = tester.widget<TextField>(
      find.byKey(const ValueKey('fixture-raw-input-homelab-code')),
    );
    expect(raw.style!.letterSpacing, -.02);
    expect(raw.style!.height, 1.625);
    expect(raw.strutStyle!.fontFamily, burlPrototypeMonoFontFamily);
    expect(raw.strutStyle!.fontSize, 14);
    expect(raw.strutStyle!.height, 1.6102);
    expect(raw.strutStyle!.forceStrutHeight, isTrue);
    expect(
      tester
          .widget<Padding>(
            find.byKey(const ValueKey('fixture-raw-editor-inset')),
          )
          .padding,
      const EdgeInsets.fromLTRB(16, 10, 14, 10),
    );
    expect(raw.style!.color, const Color(0xfff5f5f5));
    final rawFill = find.byKey(const ValueKey('fixture-raw-fill'));
    final rawBorder = find.byKey(const ValueKey('fixture-raw-border'));
    expect(tester.getSize(rawFill), const Size(584, 415));
    expect(tester.getSize(rawBorder), const Size(2, 415));
    expect(tester.widget<ColoredBox>(rawFill).color, const Color(0xff1e1e20));
    final rawInkScale = tester.widget<Transform>(
      find.byKey(const ValueKey('fixture-raw-ink-scale')),
    );
    expect(rawInkScale.alignment, Alignment.topLeft);
    expect(rawInkScale.transform.storage[5], closeTo(367 / 370, .000001));
    expect(rawInkScale.transformHitTests, isFalse);
    final rawInput = find.byKey(
      const ValueKey('fixture-raw-input-homelab-code'),
    );
    await tester.enterText(rawInput, '```yaml\nservices:\n  caddy: true\n```');
    await tester.pump();
    expect(
      tester.widget<TextField>(rawInput).controller!.text,
      '```yaml\nservices:\n  caddy: true\n```',
    );

    await tester.tap(find.byKey(const ValueKey('fixture-navigator-focaccia')));
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('fixture-link-normal'));
    await tester.scrollUntilVisible(link, 300, scrollable: focacciaScroll);
    final footer = find.byKey(const ValueKey('fixture-footer-rich-text'));
    expect(footer, findsOneWidget);
    expect(tester.getSize(footer), const Size(584, 104));
    expect(
      tester.getSize(find.byKey(const ValueKey('fixture-weekly-review-link'))),
      const Size(119, 25),
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    final anchorIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('fixture-link-anchor-icon')),
    );
    expect(anchorIcon.icon, LucideIcons.link_2);
    expect(anchorIcon.size, 12);
    expect(anchorIcon.color, const Color(0xffa3d1a9));
    expect(tester.getSize(link), const Size(126, 25));
    final linkPaint = tester.widget<Transform>(
      find.byKey(const ValueKey('fixture-link-anchor-paint')),
    );
    expect(linkPaint.transform.storage[12], -5);
    expect(linkPaint.transform.storage[13], -6);
    final hoverSurface = tester.widget<Container>(
      find.byKey(const ValueKey('fixture-link-hover-surface')),
    );
    final hoverDecoration = hoverSurface.decoration! as BoxDecoration;
    expect(hoverDecoration.color, const Color(0xff1c261e));
    expect(hoverDecoration.borderRadius, BorderRadius.circular(4));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fixture-link-anchor-label')))
          .style!
          .color,
      const Color(0xffffffff),
    );
    expect(
      find.descendant(of: link, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.byKey(const ValueKey('fixture-link-anchor-label')),
          )
          .didExceedMaxLines,
      isFalse,
    );
    final popover = find.byKey(const ValueKey('fixture-link-popover'));
    expect(tester.getSize(popover), const Size(229, 30));
    final popoverIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('fixture-link-popover-icon')),
    );
    expect(popoverIcon.icon, LucideIcons.link_2);
    expect(popoverIcon.size, 14);
    expect(popoverIcon.color, const Color(0xffa3d1a9));
    final popoverSurface = tester.widget<Container>(popover);
    final popoverDecoration = popoverSurface.decoration! as BoxDecoration;
    expect(popoverDecoration.color, const Color(0xff141417));
    expect(
      popoverDecoration.border,
      Border.all(color: const Color(0xff27272b)),
    );
    expect(popoverDecoration.borderRadius, BorderRadius.circular(4));
    expect(
      popoverSurface.padding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
    expect(
      find.descendant(of: popover, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    final inlinePopoverText = tester.widget<Text>(
      find.descendant(of: popover, matching: find.byType(Text)),
    );
    final spans = (inlinePopoverText.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).style!.fontWeight, FontWeight.w400);
    expect((spans.last as TextSpan).style!.fontWeight, FontWeight.w700);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.byKey(const ValueKey('fixture-link-popover-label')),
          )
          .didExceedMaxLines,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('fixture-navigator-recovered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsNothing);
    expect(
      find.byKey(const ValueKey('fixture-recovery-link-popover')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'fixture-recovered-task-Coarsely grind 200g washed Ethiopian single-origin beans',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tree hierarchy exposes the authentic note context delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fixture-sidebar-search')),
      findsOneWidget,
    );
    expect(find.text('Kitchen & Recipes'), findsWidgets);
    expect(
      find.byKey(const ValueKey('fixture-navigator-kyoto')),
      findsOneWidget,
    );
    expect(find.text('Technology & Setup'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-tab-kyoto')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-tab-recovered')), findsNothing);
    expect(find.byKey(const ValueKey('fixture-tab-new')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fixture-tab-close-sourdough-focaccia.md')),
      findsOneWidget,
    );
    for (final key in [
      'fixture-metadata-folder',
      'fixture-metadata-filename',
      'fixture-metadata-copy',
      'fixture-metadata-separator',
      'fixture-metadata-clock',
      'fixture-metadata-words',
      'fixture-metadata-time',
      'fixture-metadata-suggestion',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('fixture-navigator-homelab')));
    await tester.pump();
    expect(find.text('Technology & Setup'), findsWidgets);
    expect(find.text('680 words'), findsOneWidget);
    expect(find.text('3 hours ago'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fixture-navigator-recovered')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-tab-recovered')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-tab-kyoto')), findsNothing);
    expect(
      find.byKey(const ValueKey('fixture-metadata-draft')),
      findsOneWidget,
    );
    expect(find.text('260 words'), findsOneWidget);
    expect(find.text('Unsaved draft recovered'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('fixture-navigator-focaccia')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-tree-delete')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fixture-tree-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-delete-dialog')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-tree-delete')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('fixture-navigator-focaccia')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-navigator-homelab')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-tree-delete')), findsNothing);
  });

  testWidgets(
    'reference shell has one stateful prototype note and compact chrome',
    (tester) async {
      tester.view.physicalSize = const Size(480, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: FixtureReferenceShell()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fixture-note-focaccia')),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-navigator'))).width,
        256,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-tab-strip'))).width,
        224,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-tab-viewport'))),
        const Size(186, 36),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-tab-new'))),
        const Size(38, 36),
      );
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('fixture-tab-strip')))
            .color,
        const Color(0xff121214),
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('fixture-editor-underlay')),
            )
            .color,
        const Color(0xff151517),
      );
      final narrowMetadata = tester.widget<Container>(
        find.byKey(const ValueKey('fixture-metadata')),
      );
      final narrowMetadataDecoration =
          narrowMetadata.decoration! as BoxDecoration;
      expect(narrowMetadataDecoration.color, const Color(0xff151517));
      expect(
        narrowMetadataDecoration.border,
        const Border(bottom: BorderSide(color: Color(0xff27272b))),
      );
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(
                        const ValueKey(
                          'fixture-tab-surface-sourdough-focaccia.md',
                        ),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        const Color(0xff151517),
      );
      for (final key in [
        'fixture-directory-notes-lane',
        'fixture-directory-kitchen-lane',
        'fixture-directory-technology-lane',
        'fixture-directory-travel-lane',
        'fixture-narrow-footer-design-system',
        'fixture-narrow-footer-sync',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.text('Empty directory'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('1 Review'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fixture-narrow-metadata-breadcrumb')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fixture-narrow-metadata-chevron')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('fixture-narrow-footer-design-system')),
        ),
        const Size(239, 27),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-narrow-workspace-header')),
        const Rect.fromLTWH(8, 8, 240, 36),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-narrow-search-frame')),
        const Rect.fromLTWH(8, 56, 240, 32),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-narrow-footer-design-system')),
        const Rect.fromLTWH(8, 715, 239, 27),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-narrow-footer-sync')),
        const Rect.fromLTWH(8, 749, 239, 28),
      );
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('fixture-narrow-footer-translation')),
            )
            .transform
            .getTranslation()
            .y,
        1,
      );
      expect(find.text('Review changes'), findsNothing);
      expect(find.text('main'), findsOneWidget);
      final syncTrailing = tester.widget<Text>(find.text('main'));
      expect(syncTrailing.style!.fontFamily, burlPrototypeMonoFontFamily);
      expect(syncTrailing.style!.fontSize, 11);
      expect(syncTrailing.style!.fontWeight, FontWeight.w500);
      expect(syncTrailing.style!.color, const Color(0x99e0c9a6));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('fixture-directory-row-Notes')))
            .left,
        8,
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('fixture-directory-kitchen-lane')),
            )
            .left,
        20,
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-directory-row-Notes')),
        const Rect.fromLTWH(8, 139, 240, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-directory-notes-empty')),
        const Rect.fromLTWH(30, 174, 184, 18),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-directory-row-Kitchen & Recipes')),
        const Rect.fromLTWH(8, 204, 240, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-note-row-focaccia')),
        const Rect.fromLTWH(30, 228, 218, 28),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-note-row-recovered')),
        const Rect.fromLTWH(30, 256, 218, 28),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-directory-row-Technology & Setup')),
        const Rect.fromLTWH(8, 291, 240, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-note-row-homelab')),
        const Rect.fromLTWH(30, 315, 218, 28),
      );
      _expectRectNear(
        tester,
        find.byKey(
          const ValueKey('fixture-directory-row-Travel & Itineraries'),
        ),
        const Rect.fromLTWH(8, 347, 240, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-note-row-kyoto')),
        const Rect.fromLTWH(30, 371, 218, 28),
      );
      _expectRectNear(
        tester,
        find.byKey(
          const ValueKey('fixture-directory-row-Reading & Book Notes'),
        ),
        const Rect.fromLTWH(8, 403, 240, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(
          const ValueKey('fixture-directory-row-Journal & Daily Logs'),
        ),
        const Rect.fromLTWH(8, 435, 240, 24),
      );
      for (final label in [
        'Notes',
        'Kitchen & Recipes',
        'Technology & Setup',
        'Travel & Itineraries',
        'Reading & Book Notes',
        'Journal & Daily Logs',
      ]) {
        expect(
          find.byKey(ValueKey('fixture-directory-count-$label')),
          findsNothing,
        );
      }
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const ValueKey('fixture-note-row-focaccia')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        const Color(0xff2a2a30),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('fixture-focaccia-h1'))).left,
        281,
      );
      expect(
        find.byKey(const ValueKey('fixture-narrow-scrollbar-vertical')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fixture-narrow-scrollbar-horizontal')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-metadata')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-metadata-suggestion')),
        const Rect.fromLTWH(352, 47.5, 36, 24),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-shell-history')),
        const Rect.fromLTWH(392, 46.5, 80, 26),
      );
      final narrowSuggestion = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-metadata-suggestion')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(
        narrowSuggestion.style!.backgroundColor!.resolve({}),
        const Color(0xff2a2318),
      );
      expect(
        narrowSuggestion.style!.side!.resolve({}),
        const BorderSide(color: Color(0xff4a3d28)),
      );
      final narrowSuggestionIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-metadata-suggestion')),
          matching: find.byIcon(LucideIcons.git_pull_request),
        ),
      );
      expect(narrowSuggestionIcon.color, const Color(0xffe0c9a6));
      final narrowHistory = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('fixture-shell-history')),
      );
      expect(
        narrowHistory.style!.backgroundColor!.resolve({}),
        const Color(0xff1e1e22),
      );
      expect(
        narrowHistory.style!.side!.resolve({}),
        const BorderSide(color: Color(0xff2e2e35)),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('fixture-focaccia-h1')))
            .height,
        128,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-focaccia-h1'))).width,
        176,
      );
      final narrowH1 = tester.widget<Text>(
        find.byKey(const ValueKey('fixture-focaccia-h1')),
      );
      expect(narrowH1.style!.fontSize, 24);
      expect(narrowH1.style!.height, 32 / 24);
      final narrowIntro = tester.widget<Text>(
        find.byKey(const ValueKey('fixture-focaccia-intro')),
      );
      expect(narrowIntro.style!.height, 24.75 / 15);
      expect(narrowIntro.style!.letterSpacing, 0);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fixture-focaccia-method')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('fixture-note-focaccia')),
          matching: find.byType(Scrollable),
        ),
      );
      final narrowMethod = tester.widget<Text>(
        find.byKey(const ValueKey('fixture-focaccia-method')),
      );
      expect(narrowMethod.style!.letterSpacing, -.45);
      expect(
        tester.getSize(find.byKey(const ValueKey('fixture-focaccia-method'))),
        const Size(176, 84),
      );
      expect(
        find.byKey(const ValueKey('fixture-sidebar-directories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fixture-sidebar-local-main')),
        findsNothing,
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-shell-preferences')),
        const Rect.fromLTWH(8, 792, 155, 16),
      );
      _expectRectNear(
        tester,
        find.byKey(const ValueKey('fixture-narrow-sun')),
        const Rect.fromLTWH(220, 786, 28, 28),
      );
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('fixture-narrow-utility-translation')),
            )
            .transform
            .getTranslation()
            .y,
        8,
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey('fixture-tab-homelab')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fixture-note-homelab')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fixture-homelab-yaml')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('fixture-note-homelab')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const ValueKey('fixture-homelab-yaml')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fixture-homelab-yaml')))
            .data,
        isNot(contains('```')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('fixture-code-rendered')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-code-rendered')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fixture-raw-homelab-code')),
        findsOneWidget,
      );
      final rawCode = tester.widget<TextField>(
        find.byKey(const ValueKey('fixture-raw-input-homelab-code')),
      );
      expect(rawCode.controller!.text, startsWith('```yaml'));

      await tester.tap(
        find.byKey(const ValueKey('fixture-navigator-recovered')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fixture-note-recovered')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fixture-recovered-dot')), findsNothing);
      expect(
        find.byKey(const ValueKey('fixture-recovered-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'fixture-recovered-task-Coarsely grind 200g washed Ethiopian single-origin beans',
          ),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('fixture-tab-focaccia')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fixture-suggestion-block')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('fixture-note-focaccia')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const ValueKey('fixture-suggestion-block')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('fixture-suggestion-keep-local')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('fixture-suggestion-keep-local')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fixture-suggestion-block')),
        findsNothing,
      );
      final link = find.byKey(const ValueKey('fixture-link-normal'));
      await tester.scrollUntilVisible(
        link,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('fixture-note-focaccia')),
          matching: find.byType(Scrollable),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(link));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fixture-link-popover')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('fixture-link-popover')))
            .dy,
        greaterThan(tester.getTopLeft(link).dy),
      );

      await tester.tap(find.byKey(const ValueKey('fixture-shell-preferences')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('fixture-preferences-Appearance-Theme-0')),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('fixture-reference-shell'))),
        ).brightness,
        Brightness.light,
      );
      await tester.tap(
        find.byKey(const ValueKey('fixture-preferences-Appearance-Theme-1')),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('fixture-reference-shell'))),
        ).brightness,
        Brightness.dark,
      );
    },
  );
}
