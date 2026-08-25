import 'dart:convert';
import 'dart:io';

import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/src/screens/workspace.dart';
import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run with `--dart-define=BURLMD_VISUAL_FIXTURE=true`. This deterministic
/// UI-only fixture uses the application's public RustApi seam rather than
/// starting the native Core, so the production shell can run without a local
/// workspace.
class _ShellFixtureApi extends RustApi {
  const _ShellFixtureApi();

  @override
  Future<WorkspaceInfo> openOrCreateLocalWorkspace({String? path}) async =>
      const WorkspaceInfo(
        id: 'driver-workspace',
        name: 'Driver workspace',
        provider: 'local',
        localPath: '/tmp/burlmd-driver-workspace',
      );

  @override
  Future<List<TreeNode>> workspaceTree() async => [
    TreeNode.note(
      id: 'driver-note',
      title: 'Driver Note',
      path: 'Driver Note.md',
    ),
  ];

  @override
  Future<List<NoteMetadata>> pendingDrafts() async => const [];

  @override
  NoteWriteStatus noteWriteStatus(String noteId) =>
      const NoteWriteStatus(hasUnwrittenEdits: false);

  @override
  Future<NoteState> openNote(String noteId) async => NoteState(
    ast: const <AstNode>[],
    metadata: const NoteMetadata(
      id: 'driver-note',
      path: 'Driver Note.md',
      title: 'Driver Note',
      lastModified: 0,
      okfConformant: true,
    ),
    baseRevision: 'driver',
    restoredFromDraft: false,
  );

  @override
  Future<List<NoteMetadata>> searchNotes(String query, int limit) async =>
      const [];
}

const _externalCaptureEnabled = bool.fromEnvironment('BURLMD_EXTERNAL_CAPTURE');
const _externalCaptureDirectory = '/tmp/burlmd-proof';
const _externalCaptureReadyPath =
    '$_externalCaptureDirectory/burlmd-capture-ready.json';
const _externalCaptureAckPath =
    '$_externalCaptureDirectory/burlmd-capture-ack.json';
const _externalCaptureTimeout = Duration(seconds: 90);
const _externalCaptureCompositorDelay = Duration(milliseconds: 250);
var _externalCaptureSequence = 0;
Size? _externalCaptureViewport;

List<String> _expectedVisibleText(String name) => switch (name) {
  'bootstrap' ||
  'reference-wide-dark-shell' ||
  'reference-note-rendered' ||
  'reference-note-raw' ||
  'reference-narrow-dark-shell' => ['Sourdough Focaccia', 'Personal Vault'],
  'reference-wide-light-shell' => ['Sourdough'],
  'reference-preferences-dark' => ['Preferences'],
  'reference-search-results' => ['sourdough', '2 matches'],
  'reference-history' => ['Git History', 'HEAD'],
  'reference-delete-confirmation' => ['Delete “Sourdough Focaccia'],
  'reference-suggestion' => ['Incoming edit'],
  'reference-code-rendered' || 'reference-code-raw' => ['yaml'],
  'reference-link-hover' => ['cold-brew-ratio'],
  'reference-recovery-badge-note' => ['Recovered'],
  'reference-sync-local-only' => ['Local only', 'SIMULATION STATE'],
  'reference-sync-connected-idle' => ['Connected', 'SIMULATION STATE'],
  'reference-sync-syncing' => ['Syncing', 'SIMULATION STATE'],
  'reference-sync-offline' => ['Offline', 'SIMULATION STATE'],
  'reference-sync-pending-suggestions' => ['Pending', 'SIMULATION STATE'],
  'reference-sync-auth-required' => ['Authentication', 'SIMULATION STATE'],
  'reference-sync-sync-error' => ['Sync error', 'SIMULATION STATE'],
  'reference-sync-external-changed' => ['External', 'SIMULATION STATE'],
  _ => [name],
};

bool _sameViewport(Size first, Size second) =>
    first.width == second.width && first.height == second.height;

Future<void> _presentExternalCaptureFrame(
  WidgetTester tester,
  Size viewport,
) async {
  if (!_externalCaptureEnabled) return;

  // Keep the live-test binding's crosshair outside the app client. This does
  // not alter the fixture state, including an already-open link popover.
  final pointer = await tester.startGesture(
    const Offset(-10000, -10000),
    kind: PointerDeviceKind.mouse,
  );
  await pointer.up();
  final deadline = DateTime.now().add(_externalCaptureTimeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (_sameViewport(tester.view.physicalSize, viewport)) {
      await tester.pumpAndSettle();
      await Future<void>.delayed(_externalCaptureCompositorDelay);
      await tester.pump();
      if (_sameViewport(tester.view.physicalSize, viewport)) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Flutter did not present ${viewport.width.toInt()}x${viewport.height.toInt()} '
    'before the external capture timeout.',
  );
}

Future<void> _publishExternalReady({
  required String phase,
  required String name,
  required Size viewport,
  required int sequence,
  required String visibleMarker,
  required List<String> expectedVisibleText,
  required bool viewSizePresented,
}) async {
  final directory = Directory(_externalCaptureDirectory);
  await directory.create(recursive: true);
  final ready = File(_externalCaptureReadyPath);
  final temporary = File('${ready.path}.$sequence.$phase.tmp');
  final payload = <String, Object>{
    'phase': phase,
    'captureName': name,
    'width': viewport.width.toInt(),
    'height': viewport.height.toInt(),
    'sequence': sequence,
    'visibleAssertionMarker': visibleMarker,
    'expectedVisibleText': expectedVisibleText,
    'markerVisible': true,
    'appFramePresented': viewSizePresented,
    'viewSizePresented': viewSizePresented,
  };
  await temporary.writeAsString(jsonEncode(payload), flush: true);
  await temporary.rename(ready.path);
}

Future<void> _waitForExternalAcknowledgement({
  required String phase,
  required String name,
  required Size viewport,
  required int sequence,
}) async {
  final acknowledgement = File(_externalCaptureAckPath);
  final deadline = DateTime.now().add(_externalCaptureTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await acknowledgement.exists()) {
      try {
        final decoded = jsonDecode(await acknowledgement.readAsString());
        if (decoded is Map<String, dynamic> &&
            decoded['phase'] == phase &&
            decoded['captureName'] == name &&
            decoded['sequence'] == sequence &&
            decoded['width'] == viewport.width.toInt() &&
            decoded['height'] == viewport.height.toInt()) {
          return;
        }
      } on FormatException {
        // The capture worker can be replacing the acknowledgement atomically.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'Timed out waiting for $phase at $_externalCaptureAckPath for $name '
    '(sequence $sequence, ${viewport.width.toInt()}x${viewport.height.toInt()}).',
  );
}

Future<void> _prepareExternalCapture({
  required WidgetTester tester,
  required String name,
  required Size viewport,
  required String visibleMarker,
}) async {
  if (!_externalCaptureEnabled) return;

  expect(
    find.byKey(ValueKey(visibleMarker)),
    findsOneWidget,
    reason: 'Expected visible capture marker $visibleMarker for $name.',
  );
  final sequence = _externalCaptureSequence++;
  if (_externalCaptureViewport == null ||
      !_sameViewport(_externalCaptureViewport!, viewport)) {
    await _publishExternalReady(
      phase: 'resize-ready',
      name: name,
      viewport: viewport,
      sequence: sequence,
      visibleMarker: visibleMarker,
      expectedVisibleText: _expectedVisibleText(name),
      viewSizePresented: false,
    );
    await _waitForExternalAcknowledgement(
      phase: 'resize-ack',
      name: name,
      viewport: viewport,
      sequence: sequence,
    );
    _externalCaptureViewport = viewport;
  }
  await _presentExternalCaptureFrame(tester, viewport);
  await _publishExternalReady(
    phase: 'capture-ready',
    name: name,
    viewport: viewport,
    sequence: sequence,
    visibleMarker: visibleMarker,
    expectedVisibleText: _expectedVisibleText(name),
    viewSizePresented: true,
  );
  await _waitForExternalAcknowledgement(
    phase: 'capture-ack',
    name: name,
    viewport: viewport,
    sequence: sequence,
  );
}

Future<void> _prepareExternalCaptureBootstrap(
  WidgetTester tester,
  Size viewport,
) => _prepareExternalCapture(
  tester: tester,
  name: 'bootstrap',
  viewport: viewport,
  visibleMarker: 'fixture-reference-shell',
);

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  Size viewport,
  String visibleMarker,
) async {
  await _prepareExternalCapture(
    tester: tester,
    name: name,
    viewport: viewport,
    visibleMarker: visibleMarker,
  );
  binding.reportData ??= <String, dynamic>{};
  final captures =
      binding.reportData!.putIfAbsent(
            'fixtureCaptureManifest',
            () => <Map<String, String>>[],
          )
          as List<Map<String, String>>;
  captures.add({
    'name': name,
    'viewport': '${viewport.width.toInt()}x${viewport.height.toInt()}',
    'viewSizePresented': 'true',
  });
  binding.reportData!['fixtureCaptureManifest'] = captures;

  // Linux screenshot support is embedder-dependent and the desktop driver has
  // no integration_test transport. Keep the entire named capture matrix in
  // report data while exercising the states, and let supported platforms emit
  // the corresponding screenshot bytes below.
  if (defaultTargetPlatform == TargetPlatform.linux) {
    binding.reportData!['screenshotSupport'] =
        'Unavailable on this Linux embedder; named visual flow completed.';
    return;
  }

  try {
    await binding.takeScreenshot(name);
  } on MissingPluginException {
    // Desktop screenshot support is embedder-dependent. The interaction and
    // assertion still run, and supported runners add bytes to reportData.
    binding.reportData!['screenshotSupport'] =
        'Unavailable on this Linux embedder; visual flow completed.';
  }
}

Finder _fixtureNoteScrollable(String note) => find.descendant(
  of: find.byKey(ValueKey('fixture-note-$note')),
  matching: find.byType(Scrollable),
);

Future<void> _resetFixtureNoteScroll(WidgetTester tester, String note) async {
  final scrollable = _fixtureNoteScrollable(note);
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.minScrollExtent);
  await tester.pumpAndSettle();
  expect(state.position.pixels, 0);
}

Map<String, num> _rectReport(Rect rect) => <String, num>{
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'width': rect.width,
  'height': rect.height,
};

void _expectFixtureTop(WidgetTester tester, Finder marker, double target) {
  expect(
    tester.getRect(marker).top,
    closeTo(target, 1),
    reason: 'fixture capture marker must be positioned at y=$target',
  );
}

Future<void> _stabilizeFixtureAnchor(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required FixtureCaptureController controller,
  required String state,
  required String note,
  required Map<Finder, double> targets,
}) async {
  final pendingSettle = controller.execute('settle');
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump();
  }
  final controllerResponse = await pendingSettle;
  expect(controllerResponse['settled'], isTrue);
  final controllerGeometry = controllerResponse['captureGeometry']! as Map;
  expect(controllerGeometry['consecutiveStableFrames'], 3);
  expect(
    (controllerGeometry['targetRect']! as Map)['top'],
    closeTo(targets.values.first, 1),
  );
  if (targets.length > 1) {
    expect(
      (controllerGeometry['popoverRect']! as Map)['top'],
      closeTo(targets.values.elementAt(1), 1),
    );
  }
  List<double>? previous;
  var consecutiveStableFrames = 0;
  var frames = 0;
  while (frames < 16 && consecutiveStableFrames < 3) {
    await tester.pump();
    frames += 1;
    final sample = <double>[
      for (final marker in targets.keys) tester.getRect(marker).top,
      tester
          .state<ScrollableState>(_fixtureNoteScrollable(note).first)
          .position
          .pixels,
    ];
    if (previous != null &&
        List.generate(
          sample.length,
          (index) => (sample[index] - previous![index]).abs() <= 1,
        ).every((stable) => stable)) {
      consecutiveStableFrames += 1;
    } else {
      consecutiveStableFrames = 0;
    }
    previous = sample;
  }
  expect(consecutiveStableFrames, 3, reason: '$state anchor must settle');
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await tester.pump();
  for (final entry in targets.entries) {
    _expectFixtureTop(tester, entry.key, entry.value);
  }
  binding.reportData ??= <String, dynamic>{};
  final reports =
      binding.reportData!.putIfAbsent(
            'fixtureAnchorStabilization',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  reports.add({
    'state': state,
    'frames': frames,
    'consecutiveStableFrames': consecutiveStableFrames,
    'outerScrollOffset': previous!.last,
    'controllerAnchorId': controllerGeometry['anchorId'],
    'controllerStableFrames': controllerGeometry['consecutiveStableFrames'],
  });
  // ignore: avoid_print
  print('fixture anchor stabilization ${jsonEncode(reports.last)}');
}

void _reportFixtureCaptureRects(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String state,
  required Map<String, Finder> markers,
  String? note,
}) {
  final rects = <String, Map<String, num>>{};
  for (final entry in markers.entries) {
    expect(entry.value, findsOneWidget, reason: '${entry.key} is visible');
    rects[entry.key] = _rectReport(tester.getRect(entry.value));
  }
  final report = <String, dynamic>{'state': state, 'rects': rects};
  if (note != null) {
    final position = tester
        .state<ScrollableState>(_fixtureNoteScrollable(note).first)
        .position;
    report['outerScrollOffset'] = position.pixels;
    report['outerScrollMinExtent'] = position.minScrollExtent;
    report['outerScrollMaxExtent'] = position.maxScrollExtent;
  }
  binding.reportData ??= <String, dynamic>{};
  final reports =
      binding.reportData!.putIfAbsent(
            'fixtureCaptureRects',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  reports.add(report);
  binding.reportData!['fixtureCaptureRects'] = reports;
  // ignore: avoid_print
  print('fixture capture rects ${jsonEncode(report)}');
}

Future<void> _reportFixtureScrollProbes(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String state,
  required String note,
  required Map<String, Finder> markers,
}) async {
  final scrollable = _fixtureNoteScrollable(note);
  final probes = <String, Map<String, dynamic>>{};
  for (final entry in markers.entries) {
    await tester.scrollUntilVisible(entry.value, 250, scrollable: scrollable);
    await tester.ensureVisible(entry.value);
    await tester.pump();
    expect(entry.value, findsOneWidget, reason: '${entry.key} is probeable');
    probes[entry.key] = <String, dynamic>{
      ..._rectReport(tester.getRect(entry.value)),
      'outerScrollOffset': tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels,
    };
  }
  await _resetFixtureNoteScroll(tester, note);
  final report = <String, dynamic>{'state': state, 'probes': probes};
  binding.reportData ??= <String, dynamic>{};
  final reports =
      binding.reportData!.putIfAbsent(
            'fixtureScrollProbes',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  reports.add(report);
  binding.reportData!['fixtureScrollProbes'] = reports;
  // ignore: avoid_print
  print('fixture scroll probes ${jsonEncode(report)}');
}

Future<void> _assertAndReportFixtureGeometry(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String state,
  required bool narrow,
}) async {
  await _resetFixtureNoteScroll(tester, 'focaccia');
  final h1 = find.byKey(const ValueKey('fixture-focaccia-h1'));
  final divider = find.byKey(const ValueKey('fixture-focaccia-h1-divider'));
  final table = find.byKey(const ValueKey('fixture-focaccia-table'));
  final method = find.byKey(const ValueKey('fixture-focaccia-method'));
  final canvas = find.byKey(const ValueKey('fixture-note-focaccia'));
  final scrollable = _fixtureNoteScrollable('focaccia');
  late final Map<String, dynamic> tableReport;
  late final double tableTopAtZero;
  if (narrow && table.evaluate().isEmpty) {
    await tester.scrollUntilVisible(table, 300, scrollable: scrollable);
    await tester.ensureVisible(table);
    await tester.pump();
    final probeOffset = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    final probeRect = tester.getRect(table);
    tableTopAtZero = probeRect.top + probeOffset;
    tableReport = <String, dynamic>{
      ..._rectReport(probeRect),
      'documentTopAtZero': tableTopAtZero,
      'probeScrollOffset': probeOffset,
    };
    await _resetFixtureNoteScroll(tester, 'focaccia');
  } else {
    final tableRect = tester.getRect(table);
    tableTopAtZero = tableRect.top;
    tableReport = _rectReport(tableRect);
  }
  final scrollOffset = tester
      .state<ScrollableState>(scrollable)
      .position
      .pixels;
  final report = <String, dynamic>{
    'state': state,
    'scrollOffset': scrollOffset,
    'h1TopLeft': <String, num>{
      'x': tester.getTopLeft(h1).dx,
      'y': tester.getTopLeft(h1).dy,
    },
    'h1': _rectReport(tester.getRect(h1)),
    'h1Divider': _rectReport(tester.getRect(divider)),
    'table': tableReport,
    'editorCanvas': _rectReport(tester.getRect(canvas)),
  };
  if (!narrow) {
    report['method'] = _rectReport(tester.getRect(method));
  }
  binding.reportData ??= <String, dynamic>{};
  final reports =
      binding.reportData!.putIfAbsent(
            'fixtureGeometry',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  reports.add(report);
  binding.reportData!['fixtureGeometry'] = reports;
  // This appears in the integration driver output as well as reportData.
  // ignore: avoid_print
  print('fixture geometry ${jsonEncode(report)}');

  expect(scrollOffset, 0);
  final h1Top = tester.getRect(h1).top;
  expect(h1Top, inInclusiveRange(narrow ? 117 : 125, narrow ? 130 : 137));
  if (narrow) {
    // The narrow reference keeps the complete table below the viewport while
    // preserving the note's top-of-document scroll position. The table is
    // lazily mounted, so this is its probe-derived document coordinate.
    expect(tableTopAtZero, inInclusiveRange(823, 825));
  } else {
    expect(tableTopAtZero, inInclusiveRange(470, 488));
    expect(tester.getRect(method).top, inInclusiveRange(750, 782));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_externalCaptureEnabled) {
    // Flutter 3.44.3's fullyLive policy permits the compositor to present
    // scheduled frames between bounded test pumps and handshake publication.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    assert(
      binding.framePolicy == LiveTestWidgetsFlutterBindingFramePolicy.fullyLive,
    );
  }

  testWidgets('drives every mounted reference-shell state', (tester) async {
    const wideViewport = Size(1440, 900);
    const narrowViewport = Size(480, 820);
    tester.view.physicalSize = wideViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        rustApiProvider.overrideWithValue(const _ShellFixtureApi()),
        writeStatusPollIntervalProvider.overrideWithValue(null),
      ],
    );
    final fixtureController = FixtureCaptureController();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: WorkspaceScreen(fixtureCaptureController: fixtureController),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixtureController.isAttached, isTrue);
    Future<void> captureWide(String name, String visibleMarker) async {
      expect(tester.view.physicalSize, wideViewport);
      await _capture(binding, tester, name, wideViewport, visibleMarker);
    }

    Future<void> prepareRenderedFocacciaUnderlay() async {
      for (final closeControl in [
        const ValueKey('fixture-preferences-done'),
        const ValueKey('fixture-search-close'),
        const ValueKey('fixture-sync-done'),
        const ValueKey('fixture-history-done'),
        const ValueKey('fixture-delete-cancel'),
      ]) {
        final control = find.byKey(closeControl);
        if (control.evaluate().isNotEmpty) {
          await tester.tap(control);
          await tester.pumpAndSettle();
        }
      }

      // Use the same mounted tab path a user takes. Selecting Focaccia resets
      // its fixture state; accepting its suggestion leaves a rendered note as
      // the neutral overlay underlay.
      await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
      await tester.pumpAndSettle();
      final suggestion = find.byKey(const ValueKey('fixture-suggestion-block'));
      await tester.scrollUntilVisible(
        suggestion,
        300,
        scrollable: _fixtureNoteScrollable('focaccia'),
      );
      final focacciaPosition = tester
          .state<ScrollableState>(_fixtureNoteScrollable('focaccia'))
          .position;
      focacciaPosition.jumpTo(focacciaPosition.maxScrollExtent);
      await tester.pump();
      final acceptSuggestion = find.byKey(
        const ValueKey('fixture-suggestion-accept'),
      );
      await tester.ensureVisible(acceptSuggestion);
      await tester.tap(acceptSuggestion);
      await tester.pumpAndSettle();
      await _resetFixtureNoteScroll(tester, 'focaccia');

      expect(find.byKey(const ValueKey('fixture-focaccia-h1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fixture-focaccia-intro')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fixture-raw-intro')), findsNothing);
      expect(
        find.byKey(const ValueKey('fixture-raw-homelab-code')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('fixture-code-rendered')), findsNothing);
      expect(find.byKey(const ValueKey('fixture-link-popover')), findsNothing);
      expect(
        tester
            .state<ScrollableState>(_fixtureNoteScrollable('focaccia'))
            .position
            .pixels,
        0,
      );
    }

    // The fixture remains mounted through the production WorkspaceScreen and
    // desktop shell rather than a retired standalone fixture route.
    final shell = find.byKey(const ValueKey('fixture-reference-shell'));
    expect(shell, findsOneWidget);
    expect(Theme.of(tester.element(shell)).brightness, Brightness.dark);
    await _prepareExternalCaptureBootstrap(tester, wideViewport);
    await _assertAndReportFixtureGeometry(
      binding,
      tester,
      state: 'reference-wide-dark-shell',
      narrow: false,
    );
    await captureWide('reference-wide-dark-shell', 'fixture-reference-shell');
    expect(find.byKey(const ValueKey('fixture-note-focaccia')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-focaccia-h1')), findsOneWidget);
    await _assertAndReportFixtureGeometry(
      binding,
      tester,
      state: 'reference-note-rendered',
      narrow: false,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-note-rendered-detail',
      markers: {
        'h1LogicalInkProxy': find.byKey(const ValueKey('fixture-focaccia-h1')),
        'dividerRule': find.byKey(
          const ValueKey('fixture-focaccia-h1-divider'),
        ),
        'intro': find.byKey(const ValueKey('fixture-focaccia-intro')),
        'quoteOuter': find.byKey(const ValueKey('fixture-focaccia-quote')),
        'ingredientsH2': find.text("Baker's Percentages & Ingredients"),
        'table': find.byKey(const ValueKey('fixture-focaccia-table')),
        'methodH2': find.byKey(const ValueKey('fixture-focaccia-method')),
      },
      note: 'focaccia',
    );
    await captureWide('reference-note-rendered', 'fixture-focaccia-h1');
    await _reportFixtureScrollProbes(
      binding,
      tester,
      state: 'reference-note-rendered-task-rows',
      note: 'focaccia',
      markers: {
        'taskMix': find.text(
          'Mix flour and water for a 45-minute autolyse at room temperature',
        ),
        'taskSalt': find.text(
          'Inoculate active starter and fold in fine sea salt',
        ),
        'taskFolds': find.text(
          'Perform 4 sets of coil folds every 30 minutes until silky windowpane',
        ),
        'taskRetard': find.text(
          'Transfer to oiled tin for 16-hour cold retard in refrigerator',
        ),
        'taskBake': find.text(
          'Generously dimple dough with olive oil and bake on preheated stone',
        ),
      },
    );

    // Preferences switch deterministically between both supported themes.
    await prepareRenderedFocacciaUnderlay();
    await tester.tap(find.byKey(const ValueKey('fixture-shell-preferences')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-preferences-drawer')),
      findsOneWidget,
    );
    expect(Theme.of(tester.element(shell)).brightness, Brightness.dark);
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-preferences-dark',
      markers: {
        'preferencesDrawer': find.byKey(
          const ValueKey('fixture-preferences-drawer'),
        ),
        'focusMode': find.byKey(
          const ValueKey('fixture-preferences-focus-mode'),
        ),
        'footer': find.byKey(const ValueKey('fixture-preferences-done')),
      },
    );
    await captureWide(
      'reference-preferences-dark',
      'fixture-preferences-drawer',
    );
    await tester.tap(
      find.byKey(const ValueKey('fixture-preferences-Appearance-Theme-0')),
    );
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(shell)).brightness, Brightness.light);
    await tester.tap(find.byKey(const ValueKey('fixture-preferences-done')));
    await tester.pumpAndSettle();
    await captureWide('reference-wide-light-shell', 'fixture-reference-shell');
    await tester.tap(find.byKey(const ValueKey('fixture-shell-preferences')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fixture-preferences-Appearance-Theme-1')),
    );
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(shell)).brightness, Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('fixture-preferences-done')));
    await tester.pumpAndSettle();

    // Focaccia exposes its rendered and raw block forms and suggestion reset.
    final focacciaIntro = find.byKey(const ValueKey('fixture-focaccia-intro'));
    expect(focacciaIntro, findsOneWidget);
    await tester.tap(focacciaIntro);
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-raw-intro')), findsOneWidget);
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-note-raw-detail',
      markers: {
        'rawOuter': find.byKey(const ValueKey('fixture-raw-intro')),
        'rawEditor': find.byKey(const ValueKey('fixture-raw-input-intro')),
      },
      note: 'focaccia',
    );
    await captureWide('reference-note-raw', 'fixture-raw-intro');
    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
    await tester.pumpAndSettle();
    expect(focacciaIntro, findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('fixture-note-focaccia')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('fixture-suggestion-accept')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-suggestion-accept')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('fixture-navigator-recovered')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      300,
      scrollable: _fixtureNoteScrollable('focaccia'),
    );
    expect(
      find.byKey(const ValueKey('fixture-suggestion-block')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('fixture-suggestion-block')));
    await tester.pumpAndSettle();
    await _stabilizeFixtureAnchor(
      binding,
      tester,
      controller: fixtureController,
      state: 'reference-suggestion',
      note: 'focaccia',
      targets: {find.byKey(const ValueKey('fixture-anchor-suggestion')): 450},
    );
    _expectFixtureTop(
      tester,
      find.byKey(const ValueKey('fixture-anchor-suggestion')),
      450,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-suggestion',
      markers: {
        'suggestionAnchor': find.byKey(
          const ValueKey('fixture-anchor-suggestion'),
        ),
        'suggestionBlock': find.byKey(
          const ValueKey('fixture-suggestion-block'),
        ),
        'removedLane': find.byKey(const ValueKey('fixture-suggestion-removed')),
        'addedLane': find.byKey(const ValueKey('fixture-suggestion-added')),
        'gitPullIcon': find.byKey(
          const ValueKey('fixture-suggestion-git-pull-icon'),
        ),
        'header': find.byKey(const ValueKey('fixture-suggestion-header')),
        'accept': find.byKey(const ValueKey('fixture-suggestion-accept')),
        'keepLocal': find.byKey(
          const ValueKey('fixture-suggestion-keep-local'),
        ),
      },
      note: 'focaccia',
    );
    await captureWide('reference-suggestion', 'fixture-suggestion-block');

    // Search remains an editable, scoped reference palette with static results.
    await prepareRenderedFocacciaUnderlay();
    await tester.tap(find.byKey(const ValueKey('fixture-shell-search')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-search-palette')),
      findsOneWidget,
    );
    final searchInput = find.byKey(const ValueKey('fixture-search-input'));
    for (final scope in ['Titles', 'Content']) {
      await tester.tap(find.byKey(ValueKey('fixture-search-scope-$scope')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(ValueKey('fixture-search-scope-$scope')),
          matching: find.text(scope),
        ),
        findsOneWidget,
      );
    }
    await tester.enterText(searchInput, 'sourdough');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-search-scope-All')));
    await tester.pump();
    final allScope = find.descendant(
      of: find.byKey(const ValueKey('fixture-search-scope-All')),
      matching: find.byType(Container),
    );
    final allScopeDecoration =
        tester.widget<Container>(allScope).decoration! as BoxDecoration;
    expect(allScopeDecoration.color, const Color(0xff222c24));
    expect(
      tester.widget<EditableText>(searchInput).controller.text,
      'sourdough',
    );
    expect(
      find.text('Sourdough Focaccia with Rosemary & Sea Salt'),
      findsWidgets,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-search-results',
      markers: {
        'searchPanel': find.byKey(const ValueKey('fixture-search-palette')),
        'headerInput': searchInput,
        'density': find.byKey(const ValueKey('fixture-search-density')),
      },
    );
    await captureWide('reference-search-results', 'fixture-search-palette');
    await tester.tap(find.byKey(const ValueKey('fixture-search-close')));
    await tester.pumpAndSettle();

    // Every simulated sync state is selectable in the mounted inspector.
    await prepareRenderedFocacciaUnderlay();
    await tester.tap(find.byKey(const ValueKey('fixture-shell-sync')));
    await tester.pumpAndSettle();
    final syncListener = find.descendant(
      of: find.byKey(const ValueKey('fixture-sync-inspector')),
      matching: find.byType(KeyboardListener),
    );
    expect(
      tester.widget<KeyboardListener>(syncListener).focusNode.hasFocus,
      isTrue,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-sync-local-only',
      markers: {
        'syncPanel': find.byKey(const ValueKey('fixture-sync-inspector')),
        'header': find.text('Sync & Storage'),
        'description': find.byKey(
          const ValueKey('fixture-sync-description-pendingSuggestions'),
        ),
        'internalSelector': find.byKey(
          const ValueKey('fixture-sync-state-picker'),
        ),
        'footer': find.byKey(const ValueKey('fixture-sync-done')),
      },
    );
    for (final (state, captureName, key) in [
      ('localOnly', 'reference-sync-local-only', LogicalKeyboardKey.digit1),
      (
        'connectedIdle',
        'reference-sync-connected-idle',
        LogicalKeyboardKey.digit2,
      ),
      ('syncing', 'reference-sync-syncing', LogicalKeyboardKey.digit3),
      ('offline', 'reference-sync-offline', LogicalKeyboardKey.digit4),
      (
        'pendingSuggestions',
        'reference-sync-pending-suggestions',
        LogicalKeyboardKey.digit5,
      ),
      (
        'authRequired',
        'reference-sync-auth-required',
        LogicalKeyboardKey.digit6,
      ),
      ('syncError', 'reference-sync-sync-error', LogicalKeyboardKey.digit7),
      (
        'externalChanged',
        'reference-sync-external-changed',
        LogicalKeyboardKey.digit8,
      ),
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(find.byKey(ValueKey('fixture-sync-state-$state')), findsOneWidget);
      await captureWide(captureName, 'fixture-sync-state-$state');
    }
    await tester.tap(find.byKey(const ValueKey('fixture-sync-done')));
    await tester.pumpAndSettle();

    // Each history snapshot updates the mounted comparison detail.
    await prepareRenderedFocacciaUnderlay();
    await tester.tap(find.byKey(const ValueKey('fixture-shell-history')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-history-drawer')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fixture-history-snapshot-details')),
        matching: find.text('9a31f0e'),
      ),
      findsOneWidget,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-history',
      markers: {
        'historyDrawer': find.byKey(const ValueKey('fixture-history-drawer')),
        'snapshotDetails': find.byKey(
          const ValueKey('fixture-history-snapshot-details'),
        ),
        'footer': find.byKey(const ValueKey('fixture-history-done')),
        'diff': find.byKey(const ValueKey('fixture-history-diff')),
        'restore': find.byKey(const ValueKey('fixture-history-restore')),
      },
    );
    await captureWide('reference-history', 'fixture-history-drawer');
    for (final hash in ['9a31f0e', '4c88b21', '2e19a45']) {
      await tester.tap(find.byKey(ValueKey('fixture-history-snapshot-$hash')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fixture-history-snapshot-details')),
          matching: find.text(hash),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('fixture-history-done')));
    await tester.pumpAndSettle();

    // Delete is reached by the visible tree row's secondary-click menu.
    await prepareRenderedFocacciaUnderlay();
    await tester.tap(
      find.byKey(const ValueKey('fixture-navigator-focaccia')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-tree-delete')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fixture-tree-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-delete-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-delete-path')), findsOneWidget);
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-delete-confirmation',
      markers: {
        'deleteDialog': find.byKey(const ValueKey('fixture-delete-dialog')),
        'path': find.byKey(const ValueKey('fixture-delete-path')),
        'gitExplainer': find.byKey(
          const ValueKey('fixture-delete-git-explainer'),
        ),
        'cancel': find.byKey(const ValueKey('fixture-delete-cancel')),
        'confirm': find.byKey(const ValueKey('fixture-delete-confirm')),
      },
    );
    await captureWide('reference-delete-confirmation', 'fixture-delete-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-delete-dialog')), findsNothing);

    // All three fixture notes remain selectable; Homelab exposes code modes.
    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-note-homelab')), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-homelab-yaml')), findsOneWidget);
    await _stabilizeFixtureAnchor(
      binding,
      tester,
      controller: fixtureController,
      state: 'reference-code-rendered',
      note: 'homelab',
      targets: {
        find.byKey(const ValueKey('fixture-anchor-code-rendered')): 465,
      },
    );
    _expectFixtureTop(
      tester,
      find.byKey(const ValueKey('fixture-anchor-code-rendered')),
      465,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-code-rendered',
      markers: {
        'codeRenderedAnchor': find.byKey(
          const ValueKey('fixture-anchor-code-rendered'),
        ),
        'codeRendered': find.byKey(const ValueKey('fixture-code-rendered')),
        'codeHeader': find.byKey(const ValueKey('fixture-code-header')),
        'codeBody': find.byKey(const ValueKey('fixture-code-body')),
        'bodyTextOrigin': find.byKey(const ValueKey('fixture-homelab-yaml')),
        'copy': find.byKey(const ValueKey('fixture-code-copy')),
        'copyIcon': find.byKey(const ValueKey('fixture-code-copy-icon')),
      },
      note: 'homelab',
    );
    await captureWide('reference-code-rendered', 'fixture-code-rendered');
    await tester.tap(find.byKey(const ValueKey('fixture-code-copy')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('fixture-code-rendered')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-raw-homelab-code')),
      findsOneWidget,
    );
    await _stabilizeFixtureAnchor(
      binding,
      tester,
      controller: fixtureController,
      state: 'reference-code-raw',
      note: 'homelab',
      targets: {find.byKey(const ValueKey('fixture-anchor-code-raw')): 447},
    );
    _expectFixtureTop(
      tester,
      find.byKey(const ValueKey('fixture-anchor-code-raw')),
      447,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-code-raw',
      markers: {
        'codeRawAnchor': find.byKey(const ValueKey('fixture-anchor-code-raw')),
        'codeRaw': find.byKey(const ValueKey('fixture-raw-homelab-code')),
        'rawEditor': find.byKey(
          const ValueKey('fixture-raw-input-homelab-code'),
        ),
      },
      note: 'homelab',
    );
    await captureWide('reference-code-raw', 'fixture-raw-homelab-code');
    await tester.tap(find.byKey(const ValueKey('fixture-navigator-recovered')));
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
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsNothing);
    expect(
      find.byKey(const ValueKey('fixture-recovery-link-popover')),
      findsNothing,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-recovery-badge-note-detail',
      markers: {
        'recoveredH1': find.byKey(const ValueKey('fixture-recovered-h1')),
        'taskGrind': find.byKey(
          const ValueKey(
            'fixture-recovered-task-Coarsely grind 200g washed Ethiopian single-origin beans',
          ),
        ),
        'taskCombine': find.byKey(
          const ValueKey(
            'fixture-recovered-task-Combine with 1000g cold filtered water in Mason jar and gentle stir',
          ),
        ),
        'taskSteep': find.byKey(
          const ValueKey(
            'fixture-recovered-task-Steep in refrigerator for 18 hours',
          ),
        ),
        'taskStrain': find.byKey(
          const ValueKey(
            'fixture-recovered-task-Double-strain through stainless mesh and paper filter; dilute 1:1 with ice',
          ),
        ),
      },
      note: 'recovered',
    );
    await captureWide(
      'reference-recovery-badge-note',
      'fixture-note-recovered',
    );

    // Hovering Focaccia's actual link surface presents the link popover.
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
    await tester.ensureVisible(link);
    await tester.pump();
    final mouse = await tester.startGesture(
      Offset.zero,
      pointer: tester.nextPointer,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(tester.getCenter(link));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsOneWidget);
    // Retain the popover state after the real mouse hover has been asserted,
    // then return the pointer off-canvas before the external capture signal.
    await mouse.moveTo(const Offset(-10000, -10000));
    await mouse.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-link-popover')), findsOneWidget);
    await _stabilizeFixtureAnchor(
      binding,
      tester,
      controller: fixtureController,
      state: 'reference-link-hover',
      note: 'focaccia',
      targets: {
        find.byKey(const ValueKey('fixture-anchor-link-hover')): 797,
        find.byKey(const ValueKey('fixture-link-popover')): 823,
      },
    );
    _expectFixtureTop(
      tester,
      find.byKey(const ValueKey('fixture-anchor-link-hover')),
      797,
    );
    _expectFixtureTop(
      tester,
      find.byKey(const ValueKey('fixture-link-popover')),
      823,
    );
    _reportFixtureCaptureRects(
      binding,
      tester,
      state: 'reference-link-hover',
      markers: {
        'linkHoverAnchor': find.byKey(
          const ValueKey('fixture-anchor-link-hover'),
        ),
        'link': link,
        'anchorIcon': find.byKey(const ValueKey('fixture-link-anchor-icon')),
        'popover': find.byKey(const ValueKey('fixture-link-popover')),
        'popoverIcon': find.byKey(const ValueKey('fixture-link-popover-icon')),
      },
      note: 'focaccia',
    );
    await captureWide('reference-link-hover', 'fixture-link-popover');

    // Compact chrome must still build cleanly at the reference mobile size.
    await tester.tap(find.byKey(const ValueKey('fixture-tab-homelab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixture-tab-focaccia')));
    await tester.pumpAndSettle();
    final focacciaHeading = find.byKey(const ValueKey('fixture-focaccia-h1'));
    await tester.ensureVisible(focacciaHeading);
    await tester.pump();
    expect(focacciaHeading, findsOneWidget);
    tester.view.physicalSize = narrowViewport;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fixture-reference-shell')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(tester.view.physicalSize, narrowViewport);
    await _assertAndReportFixtureGeometry(
      binding,
      tester,
      state: 'reference-narrow-dark-shell',
      narrow: true,
    );
    await _capture(
      binding,
      tester,
      'reference-narrow-dark-shell',
      narrowViewport,
      'fixture-focaccia-h1',
    );
  });
}
