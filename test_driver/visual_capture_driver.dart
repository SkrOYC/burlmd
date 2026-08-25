import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

/// The external compositor protocol is intentionally host-driven. The normal
/// application target exposes its fixture controller through
/// [FlutterDriver.requestData]; the compositor worker alone resizes and
/// screenshots the Linux client.
///
/// ```sh
/// flutter drive --target=lib/visual_capture_main.dart \
///   --driver=test_driver/visual_capture_driver.dart -d linux
/// ```
const _defaultProofDirectory = '/tmp/burlmd-proof';
final _proofDirectory =
    Platform.environment['BURLMD_CAPTURE_PROOF_DIRECTORY'] ??
    _defaultProofDirectory;
final _readyPath = '$_proofDirectory/burlmd-capture-ready.json';
final _ackPath = '$_proofDirectory/burlmd-capture-ack.json';
const _handshakeTimeout = Duration(seconds: 90);
const _pollInterval = Duration(milliseconds: 50);
const _presentationInterval = Duration(milliseconds: 34);
const _geometryTolerance = 1.0;
const _requiredStableResponses = 3;

/// Immutable viewport used by the host/compositor contract.
class VisualCaptureViewport {
  const VisualCaptureViewport(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is VisualCaptureViewport &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// A controller command in the order needed to reach a capture surface.
class VisualCaptureCommand {
  const VisualCaptureCommand(this.command, [this.arguments = const {}]);

  final String command;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    if (arguments.isNotEmpty) 'arguments': arguments,
  };
}

/// One named, reference-manifest-backed capture.
class VisualCaptureSpec {
  const VisualCaptureSpec({
    required this.name,
    required this.viewport,
    required this.commands,
    required this.visibleMarker,
    required this.expectedVisibleText,
    required this.expectedState,
  });

  final String name;
  final VisualCaptureViewport viewport;
  final List<VisualCaptureCommand> commands;
  final String visibleMarker;
  final List<String> expectedVisibleText;

  /// Relevant controller state reported after settling this surface.
  final Map<String, Object?> expectedState;
}

const _wide = VisualCaptureViewport(1440, 900);
const _narrow = VisualCaptureViewport(480, 820);
const _reset = VisualCaptureCommand('reset');
const _renderedFocaccia = VisualCaptureCommand('focacciaRendered');
const _darkFocacciaState = <String, Object?>{
  'theme': 'dark',
  'note': 'focaccia',
  'overlay': null,
  'rawBlock': null,
  'suggestionOpen': false,
  'linkPopoverPinned': false,
};

/// The 22 reference images in `/tmp/burlmd-proof/reference-manifest.json`, in
/// its authoritative order.
const visualCaptureSpecs = <VisualCaptureSpec>[
  VisualCaptureSpec(
    name: 'reference-wide-dark-shell',
    viewport: _wide,
    commands: [_reset],
    visibleMarker: 'fixture-focaccia-h1',
    expectedVisibleText: ['Sourdough Focaccia'],
    expectedState: _darkFocacciaState,
  ),
  VisualCaptureSpec(
    name: 'reference-note-rendered',
    viewport: _wide,
    commands: [_renderedFocaccia],
    visibleMarker: 'fixture-focaccia-h1',
    expectedVisibleText: ['Sourdough Focaccia'],
    expectedState: _darkFocacciaState,
  ),
  VisualCaptureSpec(
    name: 'reference-wide-light-shell',
    viewport: _wide,
    commands: [_reset, VisualCaptureCommand('light')],
    visibleMarker: 'fixture-focaccia-h1',
    expectedVisibleText: ["Baker's"],
    expectedState: <String, Object?>{
      'theme': 'light',
      'note': 'focaccia',
      'overlay': null,
      'rawBlock': null,
      'suggestionOpen': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-search-results',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSearch'),
      VisualCaptureCommand('setSearchQuery', {'query': 'sourdough'}),
      VisualCaptureCommand('setSearchScope', {'scope': 'All'}),
    ],
    visibleMarker: 'fixture-search-palette',
    expectedVisibleText: ['sourdough', '2 matches'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'search',
      'searchQuery': 'sourdough',
      'searchScope': 'All',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-preferences-dark',
    viewport: _wide,
    commands: [_reset, VisualCaptureCommand('openPreferences')],
    visibleMarker: 'fixture-preferences-drawer',
    expectedVisibleText: ['Preferences'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'preferences',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-local-only',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'localOnly'}),
    ],
    visibleMarker: 'fixture-sync-state-localOnly',
    expectedVisibleText: ['Local only', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'localOnly',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-connected-idle',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'connectedIdle'}),
    ],
    visibleMarker: 'fixture-sync-state-connectedIdle',
    expectedVisibleText: ['Connected', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'connectedIdle',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-syncing',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'syncing'}),
    ],
    visibleMarker: 'fixture-sync-state-syncing',
    expectedVisibleText: ['Syncing', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'syncing',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-offline',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'offline'}),
    ],
    visibleMarker: 'fixture-sync-state-offline',
    expectedVisibleText: ['Offline', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'offline',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-pending-suggestions',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'pendingSuggestions'}),
    ],
    visibleMarker: 'fixture-sync-state-pendingSuggestions',
    expectedVisibleText: ['Pending', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'pendingSuggestions',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-auth-required',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'authRequired'}),
    ],
    visibleMarker: 'fixture-sync-state-authRequired',
    expectedVisibleText: ['Authentication', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'authRequired',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-sync-error',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'syncError'}),
    ],
    visibleMarker: 'fixture-sync-state-syncError',
    expectedVisibleText: ['Sync error', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'syncError',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-sync-external-changed',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openSync'),
      VisualCaptureCommand('setSyncState', {'state': 'externalChanged'}),
    ],
    visibleMarker: 'fixture-sync-state-externalChanged',
    expectedVisibleText: ['External', 'SIMULATION STATE'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'sync',
      'syncState': 'externalChanged',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-history',
    viewport: _wide,
    commands: [
      _reset,
      VisualCaptureCommand('openHistory'),
      VisualCaptureCommand('setHistorySnapshot', {'snapshot': '9a31f0e'}),
    ],
    visibleMarker: 'fixture-history-drawer',
    expectedVisibleText: ['Git History', 'HEAD'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'history',
      'historySnapshot': '9a31f0e',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-delete-confirmation',
    viewport: _wide,
    commands: [_reset, VisualCaptureCommand('authenticDeleteDialog')],
    visibleMarker: 'fixture-delete-dialog',
    expectedVisibleText: ['Delete “Sourdough Focaccia'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': 'delete',
    },
  ),
  VisualCaptureSpec(
    name: 'reference-note-raw',
    viewport: _wide,
    commands: [VisualCaptureCommand('focacciaRaw')],
    visibleMarker: 'fixture-raw-intro',
    expectedVisibleText: ['Sourdough Focaccia'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': null,
      'rawBlock': 'intro',
      'suggestionOpen': false,
      'linkPopoverPinned': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-suggestion',
    viewport: _wide,
    commands: [VisualCaptureCommand('focacciaSuggestion')],
    visibleMarker: 'fixture-suggestion-block',
    expectedVisibleText: ['Incoming edit'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': null,
      'rawBlock': null,
      'suggestionOpen': true,
      'linkPopoverPinned': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-code-rendered',
    viewport: _wide,
    commands: [VisualCaptureCommand('homelabRendered')],
    visibleMarker: 'fixture-code-rendered',
    expectedVisibleText: ['yaml'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'homelab',
      'overlay': null,
      'rawBlock': null,
      'suggestionOpen': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-code-raw',
    viewport: _wide,
    commands: [VisualCaptureCommand('homelabRaw')],
    visibleMarker: 'fixture-raw-homelab-code',
    expectedVisibleText: ['yaml'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'homelab',
      'overlay': null,
      'rawBlock': 'homelab-code',
      'suggestionOpen': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-link-hover',
    viewport: _wide,
    commands: [VisualCaptureCommand('linkHover')],
    visibleMarker: 'fixture-link-popover',
    expectedVisibleText: ['cold-brew-ratio'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'focaccia',
      'overlay': null,
      'rawBlock': null,
      'suggestionOpen': true,
      'linkPopoverPinned': true,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-recovery-badge-note',
    viewport: _wide,
    commands: [VisualCaptureCommand('recoveredPopover')],
    visibleMarker: 'fixture-note-recovered',
    expectedVisibleText: ['Recovered'],
    expectedState: <String, Object?>{
      'theme': 'dark',
      'note': 'recovered',
      'overlay': null,
      'rawBlock': null,
      'suggestionOpen': false,
      'linkPopoverPinned': false,
    },
  ),
  VisualCaptureSpec(
    name: 'reference-narrow-dark-shell',
    viewport: _narrow,
    commands: [_reset],
    visibleMarker: 'fixture-focaccia-h1',
    expectedVisibleText: ['Sourdough Focaccia'],
    expectedState: _darkFocacciaState,
  ),
];

/// Serializes a ready file exactly as the external capture worker consumes it.
Map<String, Object?> visualCaptureReadyJson({
  required String phase,
  required String captureName,
  required VisualCaptureViewport viewport,
  required int sequence,
  required String visibleMarker,
  required List<String> expectedVisibleText,
  required bool markerVisible,
  required bool appFramePresented,
  required bool viewSizePresented,
}) => <String, Object?>{
  'phase': phase,
  'captureName': captureName,
  'width': viewport.width,
  'height': viewport.height,
  'sequence': sequence,
  'visibleAssertionMarker': visibleMarker,
  'expectedVisibleText': expectedVisibleText,
  'markerVisible': markerVisible,
  'appFramePresented': appFramePresented,
  'viewSizePresented': viewSizePresented,
};

/// True only for an acknowledgement matching the exact ready-file identity.
bool visualCaptureAckMatches(
  Object? acknowledgement, {
  required String phase,
  required String captureName,
  required VisualCaptureViewport viewport,
  required int sequence,
}) {
  if (acknowledgement is! Map) return false;
  return acknowledgement['phase'] == phase &&
      acknowledgement['captureName'] == captureName &&
      acknowledgement['width'] == viewport.width &&
      acknowledgement['height'] == viewport.height &&
      acknowledgement['sequence'] == sequence;
}

class _CaptureGeometryExpectation {
  const _CaptureGeometryExpectation({
    required this.anchorId,
    required this.targetTop,
    this.popoverTop,
  });

  final String anchorId;
  final double targetTop;
  final double? popoverTop;
}

_CaptureGeometryExpectation? _geometryExpectationFor(String name) =>
    switch (name) {
      'reference-suggestion' => const _CaptureGeometryExpectation(
        anchorId: 'suggestion',
        targetTop: 450,
      ),
      'reference-code-rendered' => const _CaptureGeometryExpectation(
        anchorId: 'code-rendered',
        targetTop: 465,
      ),
      'reference-code-raw' => const _CaptureGeometryExpectation(
        anchorId: 'code-raw',
        targetTop: 447,
      ),
      'reference-link-hover' => const _CaptureGeometryExpectation(
        anchorId: 'link-hover',
        targetTop: 797,
        popoverTop: 823,
      ),
      _ => null,
    };

/// Returns null only when a controller response contains stable, finite
/// capture telemetry valid for [spec]. Kept public for protocol-only tests.
String? visualCaptureGeometryFailure(
  VisualCaptureSpec spec,
  Map<String, Object?> response,
) {
  final targetRect = response['targetRect'];
  final documentScroll = response['documentScroll'];
  final generation = response['positionGeneration'];
  final captureGeometry = response['captureGeometry'];
  if (targetRect is! Map ||
      documentScroll is! Map ||
      generation is! num ||
      !generation.isFinite ||
      captureGeometry is! Map) {
    return 'missing targetRect/documentScroll/positionGeneration/captureGeometry';
  }
  for (final key in const ['left', 'top', 'width', 'height']) {
    if (!targetRect.containsKey(key)) {
      return 'targetRect is missing $key';
    }
  }
  if (captureGeometry['inTolerance'] != true) {
    return 'captureGeometry.inTolerance was not true';
  }
  final stableFrames = captureGeometry['consecutiveStableFrames'];
  if (stableFrames is! num || stableFrames < _requiredStableResponses) {
    return 'captureGeometry.consecutiveStableFrames was $stableFrames';
  }
  final scroll = captureGeometry['scroll'];
  if (scroll is! Map) return 'captureGeometry.scroll was absent';
  final scrollError = _scrollFailure(documentScroll) ?? _scrollFailure(scroll);
  if (scrollError != null) return scrollError;

  final expectation = _geometryExpectationFor(spec.name);
  if (expectation != null) {
    if (captureGeometry['anchorId'] != expectation.anchorId) {
      return 'captureGeometry.anchorId was ${captureGeometry['anchorId']}';
    }
    final rectError = _rectTopFailure(
      targetRect,
      expectation.targetTop,
      'targetRect.top',
    );
    if (rectError != null) return rectError;
    final geometryTargetRect = captureGeometry['targetRect'];
    final geometryRectError = _rectTopFailure(
      geometryTargetRect,
      expectation.targetTop,
      'captureGeometry.targetRect.top',
    );
    if (geometryRectError != null) return geometryRectError;
    if (expectation.popoverTop case final popoverTop?) {
      final popoverError = _rectTopFailure(
        captureGeometry['popoverRect'],
        popoverTop,
        'captureGeometry.popoverRect.top',
      );
      if (popoverError != null) return popoverError;
    }
  }

  // The current controller does not expose narrow note metrics. If it starts
  // doing so, make them a hard contract rather than silently ignoring them.
  if (spec.name == 'reference-narrow-dark-shell') {
    final narrow =
        response['narrowGeometry'] ?? captureGeometry['narrowGeometry'];
    if (narrow != null) {
      if (narrow is! Map) return 'narrow geometry was not an object';
      final docTop = narrow['docTop'];
      final quoteLines = narrow['quoteLines'];
      if (docTop is! num || (docTop - 824).abs() > _geometryTolerance) {
        return 'narrow docTop was $docTop';
      }
      if (quoteLines != 7) return 'narrow quoteLines was $quoteLines';
    }
  }
  return null;
}

String? _scrollFailure(Map scroll) {
  final offset = scroll['offset'];
  final minimum = scroll['min'];
  final maximum = scroll['max'];
  if (offset is! num ||
      minimum is! num ||
      maximum is! num ||
      !offset.isFinite ||
      !minimum.isFinite ||
      !maximum.isFinite) {
    return 'document scroll was not finite';
  }
  if (minimum > maximum ||
      offset < minimum - _geometryTolerance ||
      offset > maximum + _geometryTolerance) {
    return 'document scroll $offset was outside [$minimum, $maximum]';
  }
  return null;
}

String? _rectTopFailure(Object? rect, double expectedTop, String label) {
  if (rect is! Map) return '$label was absent';
  final top = rect['top'];
  if (top is! num || !top.isFinite) return '$label was not finite';
  if ((top - expectedTop).abs() > _geometryTolerance) {
    return '$label was $top; expected $expectedTop±$_geometryTolerance';
  }
  return null;
}

Future<void> main() async {
  _verifyCaptureMatrix();
  final driver = await FlutterDriver.connect();
  try {
    await driver.waitFor(
      find.byValueKey('fixture-reference-shell'),
      timeout: _handshakeTimeout,
    );
    await driver.waitFor(
      find.byValueKey('fixture-focaccia-h1'),
      timeout: _handshakeTimeout,
    );
    await _runCapture(
      driver,
      const VisualCaptureSpec(
        name: 'bootstrap',
        viewport: _wide,
        commands: [_reset],
        visibleMarker: 'fixture-focaccia-h1',
        expectedVisibleText: ['Sourdough Focaccia'],
        expectedState: _darkFocacciaState,
      ),
      sequence: 0,
    );
    for (var index = 0; index < visualCaptureSpecs.length; index++) {
      await _runCapture(driver, visualCaptureSpecs[index], sequence: index + 1);
    }
  } finally {
    await driver.close();
  }
}

void _verifyCaptureMatrix() {
  if (visualCaptureSpecs.length != 22) {
    throw StateError(
      'Expected 22 reference capture specs, found ${visualCaptureSpecs.length}.',
    );
  }
  final names = <String>{};
  for (final spec in visualCaptureSpecs) {
    if (!names.add(spec.name)) {
      throw StateError('Duplicate reference capture name: ${spec.name}.');
    }
    if (spec.viewport.width <= 0 || spec.viewport.height <= 0) {
      throw StateError('Invalid viewport for ${spec.name}: ${spec.viewport}.');
    }
  }
}

Future<void> _runCapture(
  FlutterDriver driver,
  VisualCaptureSpec spec, {
  required int sequence,
}) async {
  try {
    for (final command in spec.commands) {
      await _sendControllerCommand(driver, command);
    }
    await _settleAndVerify(driver, spec, stage: 'before resize');
    await _waitForStableControllerResponses(
      driver,
      spec,
      stage: 'before resize',
    );
    await _publishReady(
      phase: 'resize-ready',
      spec: spec,
      sequence: sequence,
      markerVisible: true,
      appFramePresented: false,
      viewSizePresented: false,
    );
    await _waitForAcknowledgement(
      phase: 'resize-ack',
      spec: spec,
      sequence: sequence,
    );
    await _waitForShellSize(driver, spec);
    await _waitForPresentationAndSettle(driver, spec);
    await _publishReady(
      phase: 'capture-ready',
      spec: spec,
      sequence: sequence,
      markerVisible: true,
      appFramePresented: true,
      viewSizePresented: true,
    );
    await _waitForAcknowledgement(
      phase: 'capture-ack',
      spec: spec,
      sequence: sequence,
    );
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError(
        'Visual capture ${spec.name} (sequence $sequence, ${spec.viewport}) failed: $error',
      ),
      stackTrace,
    );
  }
}

Future<Map<String, Object?>> _sendControllerCommand(
  FlutterDriver driver,
  VisualCaptureCommand command,
) async {
  final raw = await driver.requestData(jsonEncode(command.toJson()));
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw StateError(
      'Fixture command ${command.command} returned non-object JSON: $raw',
    );
  }
  final response = decoded.cast<String, Object?>();
  final error = response['error'];
  if (error != null) {
    throw StateError('Fixture command ${command.command} failed: $error');
  }
  return response;
}

Future<void> _settleAndVerify(
  FlutterDriver driver,
  VisualCaptureSpec spec, {
  required String stage,
}) async {
  final response = await _sendControllerCommand(
    driver,
    const VisualCaptureCommand('settle'),
  );
  _verifyControllerResponse(response, spec, stage: stage);
}

void _verifyControllerResponse(
  Map<String, Object?> response,
  VisualCaptureSpec spec, {
  required String stage,
}) {
  if (response['settled'] != true) {
    throw StateError('${spec.name} was not settled $stage: $response');
  }
  if (response['visibleMarkerKey'] != spec.visibleMarker) {
    throw StateError(
      '${spec.name} reported marker ${response['visibleMarkerKey']} $stage; expected ${spec.visibleMarker}.',
    );
  }
  final selectedState = response['selectedState'];
  if (selectedState is! Map) {
    throw StateError('${spec.name} did not report selectedState $stage.');
  }
  for (final entry in spec.expectedState.entries) {
    if (selectedState[entry.key] != entry.value) {
      throw StateError(
        '${spec.name} reported selectedState.${entry.key}=${selectedState[entry.key]} $stage; expected ${entry.value}.',
      );
    }
  }
  final geometryFailure = visualCaptureGeometryFailure(spec, response);
  if (geometryFailure != null) {
    throw StateError('${spec.name} geometry failed $stage: $geometryFailure');
  }
}

Future<void> _waitForStableControllerResponses(
  FlutterDriver driver,
  VisualCaptureSpec spec, {
  required String stage,
}) async {
  final deadline = DateTime.now().add(_handshakeTimeout);
  var consecutiveMatches = 0;
  String? previousFingerprint;
  Map<String, Object?>? latest;
  while (DateTime.now().isBefore(deadline)) {
    latest = await _sendControllerCommand(
      driver,
      const VisualCaptureCommand('shellSize'),
    );
    try {
      _verifyControllerResponse(latest, spec, stage: stage);
      final fingerprint = _geometryFingerprint(latest);
      consecutiveMatches = fingerprint == previousFingerprint
          ? consecutiveMatches + 1
          : 1;
      previousFingerprint = fingerprint;
      if (consecutiveMatches >= _requiredStableResponses) return;
    } on StateError {
      consecutiveMatches = 0;
      previousFingerprint = null;
    }
    await Future<void>.delayed(_pollInterval);
  }
  throw StateError(
    '${spec.name} did not provide $_requiredStableResponses consecutive '
    'matching controller geometry responses $stage. Last response: $latest',
  );
}

String _geometryFingerprint(Map<String, Object?> response) {
  final geometry = response['captureGeometry'] as Map;
  final rect = geometry['targetRect'] as Map;
  final popover = geometry['popoverRect'];
  final scroll = geometry['scroll'] as Map;
  return jsonEncode(<String, Object?>{
    'anchorId': geometry['anchorId'],
    'targetTop': rect['top'],
    'popoverTop': popover is Map ? popover['top'] : null,
    'scroll': scroll['offset'],
    'positionGeneration': response['positionGeneration'],
  });
}

Future<void> _waitForShellSize(
  FlutterDriver driver,
  VisualCaptureSpec spec,
) async {
  final deadline = DateTime.now().add(_handshakeTimeout);
  Map<String, Object?>? latest;
  while (DateTime.now().isBefore(deadline)) {
    latest = await _sendControllerCommand(
      driver,
      const VisualCaptureCommand('shellSize'),
    );
    if (_responseReportsViewport(latest, spec.viewport)) {
      return;
    }
    await Future<void>.delayed(_pollInterval);
  }
  throw StateError(
    '${spec.name} did not report shell size ${spec.viewport} within $_handshakeTimeout. Last controller response: $latest',
  );
}

bool _responseReportsViewport(
  Map<String, Object?> response,
  VisualCaptureViewport viewport,
) {
  final size = response['shellSize'];
  if (size is! Map) {
    return false;
  }
  final width = size['width'];
  final height = size['height'];
  return width is num &&
      height is num &&
      width == viewport.width &&
      height == viewport.height;
}

Future<void> _waitForPresentationAndSettle(
  FlutterDriver driver,
  VisualCaptureSpec spec,
) async {
  await Future<void>.delayed(_presentationInterval);
  await Future<void>.delayed(_presentationInterval);
  await _settleAndVerify(driver, spec, stage: 'after resize presentation');
  final sizeResponse = await _sendControllerCommand(
    driver,
    const VisualCaptureCommand('shellSize'),
  );
  if (!_responseReportsViewport(sizeResponse, spec.viewport)) {
    throw StateError(
      '${spec.name} changed size after presentation: expected ${spec.viewport}, got ${sizeResponse['shellSize']}.',
    );
  }
  await _waitForStableControllerResponses(
    driver,
    spec,
    stage: 'after resize presentation',
  );
  // This is deliberately the final driver request before capture-ready. It
  // catches any late scroll/anchor movement after the three-response poll.
  final finalResponse = await _sendControllerCommand(
    driver,
    const VisualCaptureCommand('shellSize'),
  );
  _verifyControllerResponse(
    finalResponse,
    spec,
    stage: 'immediately before capture ready',
  );
}

Future<void> _publishReady({
  required String phase,
  required VisualCaptureSpec spec,
  required int sequence,
  required bool markerVisible,
  required bool appFramePresented,
  required bool viewSizePresented,
}) async {
  final proofDirectory = Directory(_proofDirectory);
  await proofDirectory.create(recursive: true);
  final acknowledgement = File(_ackPath);
  if (await acknowledgement.exists()) {
    await acknowledgement.delete();
  }
  final ready = File(_readyPath);
  final temporary = File(
    '${ready.path}.$pid.$sequence.$phase.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  final payload = visualCaptureReadyJson(
    phase: phase,
    captureName: spec.name,
    viewport: spec.viewport,
    sequence: sequence,
    visibleMarker: spec.visibleMarker,
    expectedVisibleText: spec.expectedVisibleText,
    markerVisible: markerVisible,
    appFramePresented: appFramePresented,
    viewSizePresented: viewSizePresented,
  );
  await temporary.writeAsString(jsonEncode(payload), flush: true);
  await temporary.rename(ready.path);
}

Future<void> _waitForAcknowledgement({
  required String phase,
  required VisualCaptureSpec spec,
  required int sequence,
}) async {
  final acknowledgement = File(_ackPath);
  final deadline = DateTime.now().add(_handshakeTimeout);
  Object? latest;
  while (DateTime.now().isBefore(deadline)) {
    if (await acknowledgement.exists()) {
      try {
        latest = jsonDecode(await acknowledgement.readAsString());
        if (visualCaptureAckMatches(
          latest,
          phase: phase,
          captureName: spec.name,
          viewport: spec.viewport,
          sequence: sequence,
        )) {
          return;
        }
      } on FormatException {
        // The worker replaces acknowledgement files atomically; a short read
        // is stale/partial and never advances the driver.
      }
    }
    await Future<void>.delayed(_pollInterval);
  }
  throw StateError(
    'Timed out waiting for $phase at $_ackPath for ${spec.name} (sequence $sequence, ${spec.viewport}). Last acknowledgement: $latest',
  );
}
