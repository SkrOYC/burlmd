import 'dart:ui';

import 'package:burlmd/src/design/burl_motion.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Local-only visual proof surface. The shell mounts this only when its
/// `BURLMD_VISUAL_FIXTURE` gate is enabled; it has no providers or FFI calls.
class VisualParityFixture extends StatefulWidget {
  const VisualParityFixture({super.key});

  @override
  State<VisualParityFixture> createState() => _VisualParityFixtureState();
}

/// Deterministic reference composition used only by the visual-fixture build.
/// It keeps the reference content inside desktop shell chrome rather than
/// replacing the application with a standalone story surface.
///
/// This is test-only prototype data, not the production application. Its
/// English fixture and sample strings intentionally remain literal so the
/// reference screenshots stay deterministic across system locales.
/// `Personal Vault` is immutable authoritative prototype sample data, not
/// production Workspace terminology.
class FixtureReferenceShell extends StatefulWidget {
  const FixtureReferenceShell({super.key, this.captureController});

  /// Optional command bridge for the normal-app visual-capture target.
  ///
  /// Leaving this null is the ordinary fixture path and produces precisely the
  /// same widget tree and visual output as before.
  final FixtureCaptureController? captureController;

  @override
  State<FixtureReferenceShell> createState() => _FixtureReferenceShellV2State();
}

/// Public, lifecycle-safe command bridge for deterministic fixture captures.
///
/// The controller deliberately owns no presentation state. It attaches to a
/// mounted [FixtureReferenceShell] and delegates each command to that shell's
/// existing interaction state. This lets a normal Flutter application target
/// drive the capture matrix without synthesising pointer or keyboard input.
class FixtureCaptureController {
  _FixtureReferenceShellV2State? _state;
  Map<String, Object?> _lastResponse = const <String, Object?>{
    'command': 'detached',
    'visibleMarkerKey': null,
    'visibleMarkerText': null,
    'selectedState': <String, Object?>{},
    'settled': false,
  };

  /// Whether a mounted reference shell currently owns this controller.
  bool get isAttached => _state != null;

  /// The latest JSON-safe response, retained after a shell is disposed.
  Map<String, Object?> get currentState =>
      Map<String, Object?>.unmodifiable(_lastResponse);

  /// Runs a named fixture command and returns a JSON-safe capture report.
  ///
  /// Commands use lower camel case by convention. Hyphenated and underscored
  /// spellings are accepted for transport clients. Mutating commands schedule
  /// a frame; issue `settle` after them when an anchored capture is required.
  Future<Map<String, Object?>> execute(
    String command, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final state = _state;
    if (state == null || !state.mounted) {
      throw StateError('FixtureCaptureController is not attached to a shell.');
    }
    final response = await state._executeCaptureCommand(command, arguments);
    _lastResponse = Map<String, Object?>.unmodifiable(response);
    return Map<String, Object?>.unmodifiable(response);
  }

  void _attach(_FixtureReferenceShellV2State state) {
    final existing = _state;
    if (existing != null && !identical(existing, state)) {
      throw StateError(
        'FixtureCaptureController cannot attach to more than one shell.',
      );
    }
    _state = state;
    _lastResponse = const <String, Object?>{
      'command': 'attached',
      'visibleMarkerKey': null,
      'visibleMarkerText': null,
      'selectedState': <String, Object?>{},
      'settled': false,
    };
  }

  void _detach(_FixtureReferenceShellV2State state) {
    if (identical(_state, state)) {
      _lastResponse = Map<String, Object?>.unmodifiable(<String, Object?>{
        ..._lastResponse,
        'command': 'detached',
        'settled': false,
      });
      _state = null;
    }
  }
}

const _searchResults = <(String, String, String)>[
  (
    'Sourdough Focaccia with Rosemary & Sea Salt',
    'Kitchen & Recipes/sourdough-focaccia.md',
    '# Sourdough Focaccia with Rosemary & Sea Salt',
  ),
  (
    'Weekly Review: August 2026 (W34)',
    'Journal & Daily Logs/2026-w34-review.md',
    '- Tested new flour blend on [[sourdough-focaccia]] with 82% hydration; crumb texture was the...',
  ),
];

const _snapshots = <(String, String, String)>[
  ('9a31f0e', '5 mins ago', 'Add baker percentage table and coil fold timings'),
  (
    '4c88b21',
    '2 hours ago',
    'Adjust hydration from 78% to 82% after testing new flour',
  ),
  ('2e19a45', 'Yesterday', 'Initial sourdough focaccia recipe notes'),
];

class _FixtureShellControl extends StatelessWidget {
  const _FixtureShellControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FixtureDiffLine extends StatelessWidget {
  const _FixtureDiffLine(this.text, this.added);
  final String text;
  final bool added;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: added ? const Color(0xff103027) : const Color(0xff3b1521),
      border: Border.all(
        color: added ? const Color(0xff22c55e) : const Color(0xffef4444),
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: added ? const Color(0xff86efac) : const Color(0xfffda4af),
      ),
    ),
  );
}

class _FixtureDot extends StatelessWidget {
  const _FixtureDot(this.color);
  final int color;
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
  );
}

/// The capture shell uses one small local model rather than independent story
/// panels.  It mirrors the prototype's selection/theme/editor transitions but
/// intentionally does not reach the production provider graph.
class _FixtureReferenceShellV2State extends State<FixtureReferenceShell> {
  // Calibrated from the live Linux compositor. These must stay explicit: the
  // widget-test font intentionally has different line metrics.
  static const _wideDocumentTop = 26.0;
  static const _narrowDocumentTop = 15.0;
  static const _widePreTableRhythm = 38.0;
  // V11 keeps the narrow table anchor fixed while allowing the heading's
  // prototype breathing room to grow independently.
  static const _narrowPreTableRhythm = 68.0;
  static const _renderedPostQuoteRhythm = 17.0;
  static const _narrowPostQuoteRhythm = 23.0;
  static const _renderedPostTableRhythm = 50.0;
  static const _methodToTasksRhythm = 32.0;
  static const _taskRowAdvance = 34.0;
  static const _narrowPaintLift = 0.0;
  static const _rawIntroLift = -6.0;
  static const _rawIntroHeight = 97.0;
  static const _rawPreQuoteRhythm = 18.0;
  var _dark = true;
  var _note = _FixtureNote.focaccia;
  String? _overlay;
  String? _rawBlock;
  var _suggestionOpen = true;
  var _codeCopied = false;
  var _linkHovered = false;
  var _linkCapturePinned = false;
  var _searchScope = 'All';
  var _searchResult = _searchResults.first.$1;
  var _focusMode = false;
  var _syncState = 'pendingSuggestions';
  var _snapshot = '9a31f0e';
  var _treeMenuOpen = false;
  var _captureSettled = true;
  final _noteScrollController = ScrollController();
  final _searchController = TextEditingController(text: 'sourdough');
  final _searchFocusNode = FocusNode(debugLabel: 'fixture-search-input');
  final _syncFocusNode = FocusNode(debugLabel: 'fixture-sync-state-driver');
  final _linkLayer = LayerLink();
  final _linkPopoverCaptureKey = GlobalKey();
  final _captureAnchors = <String, GlobalKey>{
    'suggestion': GlobalKey(),
    'code-rendered': GlobalKey(),
    'code-raw': GlobalKey(),
    'link-hover': GlobalKey(),
  };
  var _positionGeneration = 0;
  var _consecutiveStableCaptureFrames = 0;
  var _tabs = <_FixtureNote>[
    _FixtureNote.focaccia,
    _FixtureNote.homelab,
    _FixtureNote.kyoto,
  ];

  @override
  void initState() {
    super.initState();
    widget.captureController?._attach(this);
  }

  @override
  void didUpdateWidget(covariant FixtureReferenceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.captureController, widget.captureController)) {
      return;
    }
    oldWidget.captureController?._detach(this);
    widget.captureController?._attach(this);
  }

  @override
  void dispose() {
    widget.captureController?._detach(this);
    _noteScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _syncFocusNode.dispose();
    super.dispose();
  }

  void _setSyncStateFromDigit(LogicalKeyboardKey key) {
    const states = [
      'localOnly',
      'connectedIdle',
      'syncing',
      'offline',
      'pendingSuggestions',
      'authRequired',
      'syncError',
      'externalChanged',
    ];
    final digit = switch (key) {
      LogicalKeyboardKey.digit1 => 0,
      LogicalKeyboardKey.digit2 => 1,
      LogicalKeyboardKey.digit3 => 2,
      LogicalKeyboardKey.digit4 => 3,
      LogicalKeyboardKey.digit5 => 4,
      LogicalKeyboardKey.digit6 => 5,
      LogicalKeyboardKey.digit7 => 6,
      LogicalKeyboardKey.digit8 => 7,
      _ => -1,
    };
    if (digit >= 0) setState(() => _syncState = states[digit]);
  }

  void _openSync() {
    _openOverlay('sync');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFocusNode.requestFocus();
    });
  }

  void _openSearch() {
    _collapseSearchSelection();
    _openOverlay('search');
  }

  void _collapseSearchSelection() {
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
    _searchFocusNode.unfocus();
  }

  void _openOverlay(String value) => setState(() {
    _overlay = value;
    _treeMenuOpen = false;
    _captureSettled = false;
  });

  void _openPreferences() => _openOverlay('preferences');

  void _openHistory() => _openOverlay('history');

  void _openDeleteDialog() => _openOverlay('delete');

  /// The prototype records these four surfaces at deliberately different
  /// vertical positions. Keeping those positions local to the fixture makes
  /// captures reproducible without changing the production editor's scroll.
  void _anchorCapture(String id, {required double alignment}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetTop = _captureAnchorTop(id);
      if (targetTop != null) _positionCaptureRect(id, targetTop);
    });
  }

  void _positionCaptureRect(String id, double targetTop, [int pass = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_noteScrollController.hasClients) return;
      final context = _captureAnchors[id]?.currentContext;
      final renderBox = context?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) return;
      final delta = renderBox.localToGlobal(Offset.zero).dy - targetTop;
      if (delta.abs() <= 1 || pass >= 3) return;
      final position = _noteScrollController.position;
      _noteScrollController.jumpTo(
        (_noteScrollController.offset + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      _positionGeneration++;
      _positionCaptureRect(id, targetTop, pass + 1);
    });
  }

  void _showRawBlock(String id) {
    setState(() {
      _rawBlock = id;
      _codeCopied = false;
      _captureSettled = false;
    });
    if (id == 'homelab-code') {
      _anchorCapture('code-raw', alignment: .333);
    }
  }

  void _select(_FixtureNote value) {
    setState(() {
      _note = value;
      _treeMenuOpen = false;
      if (value == _FixtureNote.recovered) {
        _tabs = [
          _FixtureNote.focaccia,
          _FixtureNote.homelab,
          _FixtureNote.recovered,
        ];
      } else {
        _tabs = [
          _FixtureNote.focaccia,
          _FixtureNote.homelab,
          _FixtureNote.kyoto,
        ];
      }
      _rawBlock = null;
      _suggestionOpen = value == _FixtureNote.focaccia;
      _linkHovered = false;
      _linkCapturePinned = false;
      _captureSettled = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _noteScrollController.hasClients) {
        _noteScrollController.jumpTo(0);
      }
    });
    if (value == _FixtureNote.homelab) {
      _anchorCapture('code-rendered', alignment: .333);
    }
  }

  void _closeOverlay() => setState(() {
    _overlay = null;
    _treeMenuOpen = false;
    _captureSettled = false;
  });

  Future<Map<String, Object?>> _executeCaptureCommand(
    String command,
    Map<String, Object?> arguments,
  ) async {
    final normalized = command.replaceAll(RegExp('[-_\\s]'), '').toLowerCase();
    switch (normalized) {
      case 'reset' || 'resetrendereddarktop':
        _resetRenderedDarkTop();
      case 'selectlight' || 'light':
        _setDark(false);
      case 'selectdark' || 'dark':
        _setDark(true);
      case 'openpreferences':
        _openPreferences();
      case 'opensearch':
        _openSearch();
      case 'opensync':
        _openSync();
      case 'openhistory':
        _openHistory();
      case 'opendelete' || 'opendeletedialog' || 'authenticdeletedialog':
        _showAuthenticDeleteDialog();
      case 'close' || 'closeoverlay':
        _closeOverlay();
      case 'setsearchquery':
        _setSearchQuery(_requiredString(arguments, 'query'));
      case 'setsearchscope':
        _setSearchScope(_requiredString(arguments, 'scope'));
      case 'setsearchresult':
        _setSearchResult(_requiredString(arguments, 'result'));
      case 'setsyncstate':
        _setSyncState(_requiredString(arguments, 'state'));
      case 'sethistorysnapshot' || 'historysnapshot':
        _setHistorySnapshot(_requiredString(arguments, 'snapshot'));
      case 'showfocacciarendered' || 'focacciarendered':
        _showFocacciaRendered();
      case 'showfocacciaraw' || 'focacciaraw':
        _showFocacciaRaw();
      case 'showfocacciasuggestion' || 'focacciasuggestion':
        _showFocacciaSuggestion();
      case 'selecthomelabrendered' || 'homelabrendered':
        _showHomelabRendered();
      case 'selecthomelabraw' || 'homelabraw':
        _showHomelabRaw();
      case 'copyhomelabcode' || 'homelabcopy':
        _copyHomelabCode();
      case 'pinlinkhover' || 'pinlinkpopover' || 'linkhover':
        _pinLinkHover();
      case 'selectrecoveredpopover' || 'recoveredpopover':
        _selectRecoveredPopover();
      case 'resizeready' || 'shellsize' || 'currentshellsize':
        break;
      case 'positionanchor' || 'positionanchors':
        _positionRequestedAnchor(arguments);
      case 'settle':
        await _settleCapture();
      default:
        throw ArgumentError.value(
          command,
          'command',
          'Unknown fixture command',
        );
    }
    return _captureResponse(command, settled: _captureSettled);
  }

  String _requiredString(Map<String, Object?> arguments, String name) {
    final value = arguments[name];
    if (value is String && value.isNotEmpty) return value;
    throw ArgumentError.value(value, name, 'Expected a non-empty string');
  }

  void _setDark(bool value) => setState(() {
    _dark = value;
    _captureSettled = false;
  });

  void _setSearchQuery(String query) => setState(() {
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _searchFocusNode.unfocus();
    _captureSettled = false;
  });

  void _setSearchScope(String scope) {
    if (!const {'All', 'Titles', 'Content'}.contains(scope)) {
      throw ArgumentError.value(scope, 'scope', 'Unsupported search scope');
    }
    setState(() {
      _searchScope = scope;
      _captureSettled = false;
    });
  }

  void _setSearchResult(String result) {
    if (!_searchResults.any((entry) => entry.$1 == result)) {
      throw ArgumentError.value(result, 'result', 'Unknown search result');
    }
    setState(() {
      _searchResult = result;
      _captureSettled = false;
    });
  }

  void _setSyncState(String state) {
    if (!_syncStates.containsKey(state)) {
      throw ArgumentError.value(state, 'state', 'Unknown sync state');
    }
    setState(() {
      _syncState = state;
      _captureSettled = false;
    });
  }

  void _setHistorySnapshot(String snapshot) {
    if (!_snapshots.any((entry) => entry.$1 == snapshot)) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'Unknown history snapshot',
      );
    }
    setState(() {
      _snapshot = snapshot;
      _captureSettled = false;
    });
  }

  void _resetRenderedDarkTop() {
    _select(_FixtureNote.focaccia);
    setState(() {
      _dark = true;
      _overlay = null;
      _rawBlock = null;
      _suggestionOpen = false;
      _codeCopied = false;
      _linkHovered = false;
      _linkCapturePinned = false;
      _treeMenuOpen = false;
      _captureSettled = false;
    });
    _scrollToTop();
  }

  void _showFocacciaRendered() => _resetRenderedDarkTop();

  void _showFocacciaRaw() {
    _resetRenderedDarkTop();
    _showRawBlock('intro');
  }

  void _showFocacciaSuggestion() {
    _select(_FixtureNote.focaccia);
    setState(() {
      _overlay = null;
      _rawBlock = null;
      _suggestionOpen = true;
      _codeCopied = false;
      _captureSettled = false;
    });
    _anchorCapture('suggestion', alignment: .486);
  }

  void _showHomelabRendered() {
    _select(_FixtureNote.homelab);
    setState(() {
      _rawBlock = null;
      _codeCopied = false;
      _captureSettled = false;
    });
    _anchorCapture('code-rendered', alignment: .333);
  }

  void _showHomelabRaw() {
    _showHomelabRendered();
    _showRawBlock('homelab-code');
  }

  void _copyHomelabCode() {
    _showHomelabRendered();
    _markHomelabCodeCopied();
  }

  void _markHomelabCodeCopied() {
    setState(() {
      _codeCopied = true;
      _captureSettled = false;
    });
  }

  void _pinLinkHover() {
    _showFocacciaSuggestion();
    setState(() {
      _linkHovered = true;
      _linkCapturePinned = true;
      _captureSettled = false;
    });
    _anchorCapture('link-hover', alignment: .97);
  }

  void _selectRecoveredPopover() {
    _select(_FixtureNote.recovered);
    setState(() {
      _overlay = null;
      _captureSettled = false;
    });
    _scrollToTop();
  }

  void _showAuthenticDeleteDialog() {
    _resetRenderedDarkTop();
    _openDeleteDialog();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _noteScrollController.hasClients) {
        _noteScrollController.jumpTo(0);
      }
    });
  }

  void _positionRequestedAnchor(Map<String, Object?> arguments) {
    final id = arguments['id'] as String? ?? _activeCaptureAnchor;
    if (id == null || !_captureAnchors.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown capture anchor');
    }
    final target = arguments['top'];
    final targetTop = target is num ? target.toDouble() : _captureAnchorTop(id);
    if (targetTop == null) {
      throw ArgumentError.value(id, 'id', 'No capture target for anchor');
    }
    _captureSettled = false;
    _positionCaptureRect(id, targetTop);
  }

  String? get _activeCaptureAnchor => switch (_note) {
    _FixtureNote.focaccia when _linkHovered => 'link-hover',
    _FixtureNote.focaccia when _suggestionOpen => 'suggestion',
    _FixtureNote.homelab when _rawBlock == 'homelab-code' => 'code-raw',
    _FixtureNote.homelab => 'code-rendered',
    _ => null,
  };

  double? _captureAnchorTop(String id) => switch (id) {
    'suggestion' => 450,
    'code-rendered' => 465,
    'code-raw' => 447,
    'link-hover' => 797,
    _ => null,
  };

  Future<void> _settleCapture() async {
    const requiredStableFrames = 3;
    const maximumFrames = 24;
    _captureSettled = false;
    _consecutiveStableCaptureFrames = 0;

    for (var frame = 0; frame < maximumFrames; frame++) {
      if (!mounted) {
        throw StateError('Fixture shell detached while capture was settling.');
      }
      final id = _activeCaptureAnchor;
      final targetTop = id == null ? null : _captureAnchorTop(id);
      // The controller owns this measured loop. UI interaction still uses
      // [_positionCaptureRect], but a normal Flutter Driver request needs an
      // explicit frame/measure/correct cycle rather than queued callbacks.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError(
          'Timed out waiting for fixture capture frame $frame.',
        ),
      );

      final geometry = _captureGeometry;
      if (id != null && targetTop != null) {
        final targetRect = _captureRectFor(_captureAnchors[id]!);
        if (targetRect == null || !_noteScrollController.hasClients) {
          _consecutiveStableCaptureFrames = 0;
          continue;
        }
        final delta = targetRect.top - targetTop;
        if (delta.abs() > 1) {
          final position = _noteScrollController.position;
          _noteScrollController.jumpTo(
            (_noteScrollController.offset + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          _positionGeneration++;
          _consecutiveStableCaptureFrames = 0;
          continue;
        }
      }
      final inTolerance = geometry['inTolerance'] == true;
      _consecutiveStableCaptureFrames = inTolerance
          ? _consecutiveStableCaptureFrames + 1
          : 0;
      if (_consecutiveStableCaptureFrames >= requiredStableFrames) {
        _captureSettled = true;
        return;
      }
    }

    _captureSettled = false;
    throw StateError(
      'Fixture capture did not reach three stable frames within ±1px: '
      '$_captureGeometry',
    );
  }

  Rect? _captureRectFor(GlobalKey key) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;
    return renderBox.localToGlobal(Offset.zero) & renderBox.size;
  }

  Map<String, Object?> _rectJson(Rect? rect) => <String, Object?>{
    'left': rect?.left,
    'top': rect?.top,
    'width': rect?.width,
    'height': rect?.height,
  };

  Map<String, Object?> get _captureGeometry {
    final id = _activeCaptureAnchor;
    final targetTop = id == null ? null : _captureAnchorTop(id);
    final targetRect = id == null
        ? null
        : _captureRectFor(_captureAnchors[id]!);
    final popoverRect = id == 'link-hover'
        ? _captureRectFor(_linkPopoverCaptureKey)
        : null;
    final anchorInTolerance = targetTop == null
        ? true
        : targetRect != null && (targetRect.top - targetTop).abs() <= 1;
    final popoverInTolerance = id != 'link-hover'
        ? true
        : popoverRect != null && (popoverRect.top - 823).abs() <= 1;
    final position = _noteScrollController.hasClients
        ? _noteScrollController.position
        : null;
    return <String, Object?>{
      'anchorId': id,
      'targetTop': targetTop,
      'targetRect': _rectJson(targetRect),
      'popoverTargetTop': id == 'link-hover' ? 823.0 : null,
      'popoverRect': id == 'link-hover' ? _rectJson(popoverRect) : null,
      'inTolerance': anchorInTolerance && popoverInTolerance,
      'scroll': <String, Object?>{
        'offset': position?.pixels ?? 0.0,
        'min': position?.minScrollExtent ?? 0.0,
        'max': position?.maxScrollExtent ?? 0.0,
      },
      'positionGeneration': _positionGeneration,
      'consecutiveStableFrames': _consecutiveStableCaptureFrames,
    };
  }

  Map<String, Object?> _captureResponse(
    String command, {
    required bool settled,
  }) {
    final marker = _captureMarker;
    final size = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    final geometry = _captureGeometry;
    return <String, Object?>{
      'command': command,
      'visibleMarkerKey': marker.$1,
      'visibleMarkerText': marker.$2,
      'visibleMarker': <String, Object?>{'key': marker.$1, 'text': marker.$2},
      'selectedState': <String, Object?>{
        'theme': _dark ? 'dark' : 'light',
        'note': _note.name,
        'overlay': _overlay,
        'rawBlock': _rawBlock,
        'suggestionOpen': _suggestionOpen,
        'linkPopoverPinned': _linkCapturePinned,
        'searchQuery': _searchController.text,
        'searchScope': _searchScope,
        'searchResult': _searchResult,
        'syncState': _syncState,
        'historySnapshot': _snapshot,
      },
      'shellSize': <String, double>{'width': size.width, 'height': size.height},
      // Keep these fields top-level for the normal-app driver while retaining
      // the complete diagnostic object for capture artefacts.
      'targetRect': geometry['targetRect'],
      'documentScroll': geometry['scroll'],
      'positionGeneration': geometry['positionGeneration'],
      'captureGeometry': geometry,
      'settled': settled,
    };
  }

  (String, String) get _captureMarker {
    final overlay = _overlay;
    if (overlay != null) {
      return switch (overlay) {
        'preferences' => ('fixture-preferences-drawer', 'Editor Preferences'),
        'search' => ('fixture-search-palette', _searchController.text),
        'sync' => (
          'fixture-sync-state-$_syncState',
          _syncStates[_syncState]!.$1,
        ),
        'history' => ('fixture-history-drawer', 'Git History'),
        _ => (
          'fixture-delete-dialog',
          'Delete “Sourdough Focaccia with Rosemary & Sea Salt”?',
        ),
      };
    }
    if (_rawBlock != null) {
      return ('fixture-raw-$_rawBlock', _rawBlock!);
    }
    if (_linkHovered) {
      return ('fixture-link-popover', 'Open Note: cold-brew-ratio');
    }
    if (_suggestionOpen && _note == _FixtureNote.focaccia) {
      return ('fixture-suggestion-block', 'Incoming edit');
    }
    return switch (_note) {
      _FixtureNote.focaccia => (
        'fixture-focaccia-h1',
        'Sourdough Focaccia with Rosemary & Sea Salt',
      ),
      _FixtureNote.homelab => (
        'fixture-code-rendered',
        'Homelab Architecture & Local Services Setup',
      ),
      _FixtureNote.kyoto => (
        'fixture-kyoto-h1',
        'Kyoto & Tokyo Autumn Itinerary 2026',
      ),
      _FixtureNote.recovered => (
        'fixture-note-recovered',
        'Cold Brew Ratio & Immersion Guide',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _dark ? Brightness.dark : Brightness.light;
    final colors = _dark ? BurlColors.dark : BurlColors.light;
    final wide = MediaQuery.sizeOf(context).width > 480;
    return Theme(
      data: buildBurlPrototypeFixtureTheme(brightness),
      child: Material(
        key: const ValueKey('fixture-reference-shell'),
        color: colors.app,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                _navigator(colors, width: wide ? 288 : 256, compact: !wide),
                Expanded(child: _editor(colors, wide: wide)),
              ],
            ),
            if (_overlay != null) _overlaySurface(colors),
          ],
        ),
      ),
    );
  }

  Widget _navigator(
    BurlColors c, {
    required double width,
    required bool compact,
  }) => SizedBox(
    key: const ValueKey('fixture-navigator'),
    width: width,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.borderSubtle)),
      ),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(8, 8, 8, 12)
            : const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              SizedBox(
                key: const ValueKey('fixture-narrow-workspace-header'),
                height: 36,
                child: Row(
                  children: [
                    _FixtureDot(0xffec6a5f),
                    const SizedBox(width: 6),
                    _FixtureDot(0xfff4bf4f),
                    const SizedBox(width: 6),
                    _FixtureDot(0xff61c554),
                    const SizedBox(width: 10),
                    Container(
                      key: const ValueKey('fixture-narrow-workspace-badge'),
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xffe5e2d9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'P',
                        style: TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff141416),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Personal Vault',
                        key: ValueKey('fixture-vault'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      LucideIcons.chevron_left,
                      key: ValueKey('fixture-narrow-collapse'),
                      size: 14,
                      color: Color(0xffa1a1aa),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('fixture-narrow-search-frame'),
                width: 240,
                height: 32,
                child: GestureDetector(
                  key: const ValueKey('fixture-shell-search'),
                  onTap: _openSearch,
                  child: TextField(
                    key: const ValueKey('fixture-sidebar-search'),
                    readOnly: true,
                    onTap: _openSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(LucideIcons.search, size: 15),
                      hintText: 'Search notes...',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
            ] else ...[
              Row(
                children: [
                  _FixtureDot(0xffec6a5f),
                  SizedBox(width: 6),
                  _FixtureDot(0xfff4bf4f),
                  SizedBox(width: 6),
                  _FixtureDot(0xff61c554),
                  SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Personal Vault',
                      key: ValueKey('fixture-vault'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Transform.translate(
                offset: const Offset(-2, 0),
                child: SizedBox(
                  height: 39,
                  child: GestureDetector(
                    key: const ValueKey('fixture-shell-search'),
                    onTap: _openSearch,
                    child: TextField(
                      key: const ValueKey('fixture-sidebar-search'),
                      readOnly: true,
                      onTap: _openSearch,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(LucideIcons.search, size: 15),
                        hintText: 'Search notes',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                if (compact) ...[
                  const Icon(
                    LucideIcons.chevron_down,
                    key: ValueKey('fixture-narrow-directories-chevron'),
                    size: 14,
                    color: Color(0xffa1a1aa),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    'DIRECTORIES',
                    key: const ValueKey('fixture-sidebar-directories'),
                    style: _shellCaption(),
                  ),
                ),
                const Icon(LucideIcons.file_plus, size: 14),
                const SizedBox(width: 6),
                const Icon(LucideIcons.folder_plus, size: 14),
              ],
            ),
            const SizedBox(height: 10),
            _FixtureDirectoryRow(c, 'Notes', 0, compact: compact),
            if (compact)
              _FixtureDirectoryLane(
                surfaceKey: const ValueKey('fixture-directory-notes-lane'),
                colors: c,
                topInset: 11,
                child: const Text(
                  'Empty directory',
                  key: ValueKey('fixture-directory-notes-empty'),
                  style: TextStyle(
                    fontFamily: burlPrototypeMonoFontFamily,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xff71717a),
                  ),
                ),
              ),
            if (compact) const SizedBox(height: 12),
            _FixtureDirectoryRow(c, 'Kitchen & Recipes', 2, compact: compact),
            _fixtureDirectoryChild(
              compact: compact,
              colors: c,
              laneKey: 'fixture-directory-kitchen-lane',
              child: _FixtureNoteRow(
                key: const ValueKey('fixture-navigator-focaccia'),
                note: _FixtureNote.focaccia,
                selected: _note == _FixtureNote.focaccia,
                onTap: () => _select(_FixtureNote.focaccia),
                onSecondaryTap: () => setState(() => _treeMenuOpen = true),
                colors: c,
                compact: compact,
              ),
            ),
            _fixtureDirectoryChild(
              compact: compact,
              colors: c,
              child: _FixtureNoteRow(
                key: const ValueKey('fixture-navigator-recovered'),
                note: _FixtureNote.recovered,
                selected: _note == _FixtureNote.recovered,
                onTap: () => _select(_FixtureNote.recovered),
                colors: c,
                compact: compact,
              ),
            ),
            if (_treeMenuOpen)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Material(
                  color: c.surfaceRaised,
                  child: TextButton.icon(
                    key: const ValueKey('fixture-tree-delete'),
                    onPressed: _openDeleteDialog,
                    icon: const Icon(LucideIcons.trash_2, size: 14),
                    label: const Text('Delete Note'),
                  ),
                ),
              ),
            if (compact) const SizedBox(height: 7),
            _FixtureDirectoryRow(c, 'Technology & Setup', 1, compact: compact),
            _fixtureDirectoryChild(
              compact: compact,
              colors: c,
              laneKey: 'fixture-directory-technology-lane',
              child: _FixtureNoteRow(
                key: const ValueKey('fixture-navigator-homelab'),
                note: _FixtureNote.homelab,
                selected: _note == _FixtureNote.homelab,
                onTap: () => _select(_FixtureNote.homelab),
                colors: c,
                compact: compact,
              ),
            ),
            if (compact) const SizedBox(height: 4),
            _FixtureDirectoryRow(
              c,
              'Travel & Itineraries',
              1,
              compact: compact,
            ),
            _fixtureDirectoryChild(
              compact: compact,
              colors: c,
              laneKey: 'fixture-directory-travel-lane',
              child: _FixtureNoteRow(
                key: const ValueKey('fixture-navigator-kyoto'),
                note: _FixtureNote.kyoto,
                selected: _note == _FixtureNote.kyoto,
                onTap: () => _select(_FixtureNote.kyoto),
                colors: c,
                compact: compact,
              ),
            ),
            if (compact) const SizedBox(height: 4),
            _FixtureDirectoryRow(
              c,
              'Reading & Book Notes',
              1,
              compact: compact,
              expanded: false,
            ),
            if (compact) const SizedBox(height: 8),
            _FixtureDirectoryRow(
              c,
              'Journal & Daily Logs',
              1,
              compact: compact,
              expanded: false,
            ),
            const Spacer(),
            if (compact) ...[
              Transform.translate(
                key: const ValueKey('fixture-narrow-footer-translation'),
                offset: const Offset(0, 1),
                child: Column(
                  children: [
                    _FixtureFooterCard(
                      surfaceKey: const ValueKey(
                        'fixture-narrow-footer-design-system',
                      ),
                      icon: LucideIcons.layers,
                      label: 'Design System Specimen',
                      trailing: 'View',
                      height: 27,
                      onTap: () {},
                    ),
                    const SizedBox(height: 7),
                    _FixtureFooterCard(
                      surfaceKey: const ValueKey('fixture-narrow-footer-sync'),
                      icon: LucideIcons.git_pull_request,
                      label: '1 Review',
                      trailing: 'main',
                      review: true,
                      height: 28,
                      onTap: _openSync,
                    ),
                  ],
                ),
              ),
            ] else ...[
              _FixtureShellControl(
                key: const ValueKey('fixture-shell-design-system'),
                icon: LucideIcons.layers,
                label: 'Design System Specimen',
                onTap: () {},
              ),
              _FixtureShellControl(
                key: const ValueKey('fixture-shell-sync'),
                icon: LucideIcons.refresh_cw,
                label: '1 Review',
                onTap: _openSync,
              ),
            ],
            if (compact)
              Transform.translate(
                key: const ValueKey('fixture-narrow-utility-translation'),
                offset: const Offset(0, 8),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('fixture-shell-preferences'),
                        onPressed: _openPreferences,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(LucideIcons.settings, size: 14),
                        label: const Text(
                          'Preferences',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        key: const ValueKey('fixture-narrow-sun'),
                        width: 28,
                        height: 28,
                        child: IconButton(
                          key: const ValueKey('fixture-narrow-sun-button'),
                          tooltip: 'Light theme',
                          onPressed: () {},
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(LucideIcons.sun, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Local',
                      key: const ValueKey('fixture-sidebar-local-main'),
                      style: _monospace(c),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('fixture-shell-preferences'),
                    onPressed: _openPreferences,
                    icon: const Icon(LucideIcons.settings, size: 14),
                    label: const Text('Preferences'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  // ignore: unused_element
  Widget _compactRail(BurlColors c) => SizedBox(
    width: 48,
    child: ColoredBox(
      color: c.sidebar,
      child: Column(
        children: [
          IconButton(
            key: const ValueKey('fixture-shell-search'),
            tooltip: 'Open search',
            onPressed: _openSearch,
            icon: const Icon(LucideIcons.search, size: 16),
          ),
          IconButton(
            key: const ValueKey('fixture-shell-preferences'),
            tooltip: 'Open preferences',
            onPressed: _openPreferences,
            icon: const Icon(LucideIcons.settings, size: 16),
          ),
        ],
      ),
    ),
  );

  Widget _fixtureDirectoryChild({
    required bool compact,
    required BurlColors colors,
    required Widget child,
    String? laneKey,
  }) => compact
      ? _FixtureDirectoryLane(
          surfaceKey: laneKey == null ? UniqueKey() : ValueKey(laneKey),
          colors: colors,
          child: child,
        )
      : Padding(padding: const EdgeInsets.only(left: 16), child: child);

  Widget _editor(BurlColors c, {required bool wide}) {
    final metadata = _note.metadata;
    return Column(
      children: [
        Container(
          key: const ValueKey('fixture-tab-strip'),
          height: 36,
          color: wide ? c.surfaceRaised : const Color(0xff121214),
          child: Row(
            children: [
              Expanded(
                key: const ValueKey('fixture-tab-viewport'),
                child: ClipRect(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final note in _tabs)
                          _FixtureSelectableTab(
                            key: ValueKey('fixture-tab-${note.name}'),
                            label: note.shortLabel,
                            selected: note == _note,
                            onTap: () => _select(note),
                            colors: c,
                            compact: !wide,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: wide ? 48 : 38,
                height: 36,
                child: IconButton(
                  key: const ValueKey('fixture-tab-new'),
                  tooltip: 'New note',
                  onPressed: () {},
                  constraints: BoxConstraints.tightFor(
                    width: wide ? 48 : 38,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.plus, size: 15),
                ),
              ),
            ],
          ),
        ),
        Container(
          key: const ValueKey('fixture-metadata'),
          height: wide ? 48 : 47,
          padding: wide
              ? const EdgeInsets.symmetric(horizontal: 28)
              : const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: wide
              ? null
              : const BoxDecoration(
                  color: Color(0xff151517),
                  border: Border(bottom: BorderSide(color: Color(0xff27272b))),
                ),
          child: wide
              ? ClipRect(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.folder, size: 14, color: c.textMuted),
                        const SizedBox(width: 5),
                        Text(
                          metadata.$1,
                          key: ValueKey('fixture-metadata-folder'),
                          style: TextStyle(
                            fontFamily: burlPrototypeMonoFontFamily,
                            fontSize: 12,
                            height: 16 / 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xffa3a3a3),
                            fontVariations: const [FontVariation('wght', 400)],
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          LucideIcons.chevron_right,
                          size: 12,
                          color: Color(0xffa3a3a3),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          key: const ValueKey('fixture-metadata-filename'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: _box(c),
                          child: Text(metadata.$2, style: _metadataMono()),
                        ),
                        IconButton(
                          key: const ValueKey('fixture-metadata-copy'),
                          tooltip: 'Copy filename',
                          onPressed: () {},
                          icon: const Icon(LucideIcons.copy, size: 13),
                        ),
                        const Text(
                          '•',
                          key: ValueKey('fixture-metadata-separator'),
                          style: TextStyle(fontSize: 11),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          LucideIcons.clock,
                          key: ValueKey('fixture-metadata-clock'),
                          size: 13,
                        ),
                        if (_note == _FixtureNote.recovered) ...[
                          Container(
                            key: const ValueKey('fixture-metadata-draft'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: _box(c),
                            child: const Text(
                              'Draft',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          metadata.$3,
                          key: const ValueKey('fixture-metadata-words'),
                          style: _metadataMono(),
                        ),
                        const SizedBox(width: 5),
                        const Text('•', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 5),
                        Text(
                          metadata.$4,
                          key: const ValueKey('fixture-metadata-time'),
                          style: _metadataMono(),
                        ),
                        if (_note == _FixtureNote.focaccia) ...[
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('fixture-metadata-suggestion'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: _box(c),
                            child: const Text(
                              '1 Suggestion',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('fixture-shell-history'),
                          onPressed: _openHistory,
                          icon: const Icon(LucideIcons.clock_3, size: 13),
                          label: const Text('History'),
                        ),
                      ],
                    ),
                  ),
                )
              : _narrowMetadata(c, metadata),
        ),
        Expanded(
          child: Theme(
            data: buildBurlPrototypeFixtureTheme(
              _dark ? Brightness.dark : Brightness.light,
            ),
            child: ColoredBox(
              key: const ValueKey('fixture-editor-underlay'),
              color: _dark
                  ? (wide ? BurlColors.dark.editor : const Color(0xff151517))
                  : BurlColors.light.editor,
              child: Stack(
                children: [
                  Center(
                    child: Transform.translate(
                      offset: Offset(wide ? -3 : 1, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 648),
                        child: DefaultTextStyle.merge(
                          // The prototype uses the platform sans face with a
                          // 14px/21px reading rhythm; don't inherit compact
                          // chrome typography into document blocks.
                          style: TextStyle(
                            fontFamily: burlPrototypeSansFontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.65,
                            color: _dark
                                ? const Color(0xffd4d4d4)
                                : const Color(0xff1e1e1c),
                            fontVariations: const [
                              FontVariation('wght', 400),
                              FontVariation('wdth', 100),
                            ],
                          ),
                          child: ListView(
                            controller: _noteScrollController,
                            key: ValueKey('fixture-note-${_note.name}'),
                            // Capture commands position the authentic keyed
                            // blocks directly. Retain the offscreen anchors
                            // only while a controller is attached; ordinary
                            // fixture rendering keeps Flutter's default cache.
                            scrollCacheExtent: widget.captureController == null
                                ? null
                                : const ScrollCacheExtent.pixels(5000),
                            padding: EdgeInsets.fromLTRB(
                              wide ? 32 : 24,
                              0,
                              wide ? 32 : 24,
                              80,
                            ),
                            children: [
                              ..._noteBlocks(c, wide: wide),
                              // Reserve permits the lower capture anchors to
                              // settle without clamping at maxScrollExtent.
                              const SizedBox(height: 400),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_linkHovered)
                    CompositedTransformFollower(
                      link: _linkLayer,
                      targetAnchor: Alignment.topLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: const Offset(-3, 26),
                      showWhenUnlinked: false,
                      child: Material(
                        color: Colors.transparent,
                        child: KeyedSubtree(
                          key: _linkPopoverCaptureKey,
                          child: _openNotePopover(
                            c,
                            key: const ValueKey('fixture-link-popover'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrowMetadata(
    BurlColors c,
    (String, String, String, String) metadata,
  ) => Row(
    children: [
      Icon(LucideIcons.folder, size: 13, color: c.textMuted),
      const SizedBox(width: 4),
      const Icon(
        LucideIcons.chevron_right,
        key: ValueKey('fixture-narrow-metadata-chevron'),
        size: 13,
        color: Color(0xffa1a1aa),
      ),
      const Spacer(),
      if (_note == _FixtureNote.focaccia) ...[
        const SizedBox(width: 4),
        SizedBox(
          key: const ValueKey('fixture-metadata-suggestion'),
          width: 36,
          height: 24,
          child: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xff2a2318),
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 24),
              maximumSize: const Size(36, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Color(0xff4a3d28)),
            ),
            child: Icon(
              LucideIcons.git_pull_request,
              size: 13,
              color: const Color(0xffe0c9a6),
            ),
          ),
        ),
      ],
      const SizedBox(width: 4),
      SizedBox(
        width: 80,
        height: 26,
        child: OutlinedButton.icon(
          key: const ValueKey('fixture-shell-history'),
          onPressed: _openHistory,
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xff1e1e22),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(80, 26),
            maximumSize: const Size(80, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: Color(0xff2e2e35)),
          ),
          icon: const Icon(LucideIcons.clock_3, size: 12),
          label: const Text(
            'History',
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    ],
  );

  List<Widget> _noteBlocks(BurlColors c, {required bool wide}) =>
      switch (_note) {
        _FixtureNote.focaccia => _focacciaBlocks(c, wide: wide),
        _FixtureNote.homelab => _homelabBlocks(c),
        _FixtureNote.kyoto => _kyotoBlocks(c),
        _FixtureNote.recovered => _recoveredBlocks(c, wide: wide),
      };

  Widget _openNotePopover(BurlColors c, {required Key key}) => SizedBox(
    width: 229,
    height: 30,
    child: Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff141417),
        border: Border.all(color: const Color(0xff27272b)),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const Icon(
              LucideIcons.link_2,
              key: ValueKey('fixture-link-popover-icon'),
              size: 14,
              color: Color(0xffa3d1a9),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  key: const ValueKey('fixture-link-popover-label'),
                  const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Open Note: ',
                        style: TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontFamilyFallback: burlPrototypeMonoFallback,
                          fontSize: 12,
                          height: 4 / 3,
                          fontWeight: FontWeight.w400,
                          color: Color(0xffe5e5e5),
                          fontVariations: [FontVariation('wght', 400)],
                        ),
                      ),
                      TextSpan(
                        text: 'cold-brew-ratio',
                        style: TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontFamilyFallback: burlPrototypeMonoFallback,
                          fontSize: 12,
                          height: 4 / 3,
                          fontWeight: FontWeight.w700,
                          color: Color(0xffe5e5e5),
                          fontVariations: [FontVariation('wght', 700)],
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _kyotoBlocks(BurlColors c) => const [
    Text(
      'Kyoto & Tokyo Autumn Itinerary 2026',
      key: ValueKey('fixture-kyoto-h1'),
      style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w700),
    ),
    SizedBox(height: 18),
    Text(
      'Detailed travel itinerary and walking routes for the November autumn foliage (*koyo*) season. Curated for historic temple gardens, artisan kissaten coffee houses, pottery markets, and quiet neighborhood exploration.',
      style: TextStyle(fontSize: 15, height: 1.65),
    ),
  ];

  List<Widget> _focacciaBlocks(BurlColors c, {required bool wide}) => [
    SizedBox(
      height: (wide ? _wideDocumentTop : _narrowDocumentTop) + (wide ? 21 : 19),
    ),
    Transform.translate(
      offset: Offset(0, wide ? -6 : _narrowPaintLift),
      child: Text(
        // The narrow prototype explicitly composes this as four lines. This
        // avoids platform fallback metrics changing the reference wrap.
        wide
            ? 'Sourdough Focaccia with Rosemary & Sea Salt'
            : 'Sourdough\nFocaccia with\nRosemary & Sea\nSalt',
        key: const ValueKey('fixture-focaccia-h1'),
        softWrap: wide,
        maxLines: wide ? null : 4,
        style: TextStyle(
          fontSize: wide ? 30 : 24,
          height: wide ? 1.2 : 32 / 24,
          fontWeight: FontWeight.w700,
          letterSpacing: wide ? -.79 : -.60,
          color: _dark ? const Color(0xfff5f5f5) : const Color(0xff1e1e1c),
          fontFamily: burlPrototypeSansFontFamily,
          fontVariations: const [
            FontVariation('wght', 700),
            FontVariation('wdth', 100),
          ],
        ),
      ),
    ),
    // Paint the rule at the prototype position without changing document flow.
    Transform.translate(
      offset: Offset(0, wide ? -10 : -4),
      child: Divider(
        key: const ValueKey('fixture-focaccia-h1-divider'),
        height: 29,
        color: _dark ? c.borderSubtle : const Color(0xff8e8b82),
      ),
    ),
    SizedBox(height: wide ? 10 : 22),
    Transform.translate(
      // _sourceOrText already provides the shared -5px intro paint lift.
      // Narrow needs a further (-2, -6) paint correction only.
      offset: Offset(wide ? 0 : -2, wide ? 0 : -6),
      child: _sourceOrText(
        c,
        'intro',
        'An artisanal high-hydration (82%) overnight sourdough focaccia featuring a golden extra virgin olive oil crust, honeycomb crumb pockets, and fresh garden rosemary.',
        Text(
          'An artisanal high-hydration (82%) overnight sourdough focaccia featuring a golden extra virgin olive oil crust, honeycomb crumb pockets, and fresh garden rosemary.',
          key: const ValueKey('fixture-focaccia-intro'),
          style: TextStyle(
            fontFamily: burlPrototypeSansFontFamily,
            fontSize: 15,
            height: 24.75 / 15,
            letterSpacing: wide ? .45 : 0,
            color: _dark ? const Color(0xffd4d4d4) : const Color(0xff1e1e1c),
            fontVariations: const [
              FontVariation('wght', 400),
              FontVariation('wdth', 100),
            ],
          ),
        ),
      ),
    ),
    SizedBox(
      height: _rawBlock == 'intro' ? _rawPreQuoteRhythm : (wide ? 50 : 36),
    ),
    Transform.translate(
      // The desktop box is already at the reference position; narrow keeps
      // its independent paint correction.
      offset: Offset(0, wide ? -24 : -22),
      child: SizedBox(
        width: wide ? null : 170,
        height: wide ? 54 : null,
        child: Transform(
          alignment: Alignment.topLeft,
          transform: Matrix4.identity(),
          child: Container(
            key: const ValueKey('fixture-focaccia-quote'),
            padding: EdgeInsets.only(left: 14, bottom: wide ? 0 : 6),
            decoration: BoxDecoration(
              color: _dark ? null : const Color(0xfff7f5ee),
              border: Border(left: BorderSide(color: c.accent, width: 2)),
            ),
            child: SizedBox(
              key: const ValueKey('fixture-focaccia-quote-text'),
              width: wide ? null : 135,
              child: Text(
                '“Good bread takes time. The slow cold fermentation in the refrigerator develops deep lactic sweetness and bubbly alveoli structure.”',
                style: TextStyle(
                  fontFamily: burlPrototypeSansFontFamily,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  height: 22.75 / 14,
                  letterSpacing: 0,
                  color: _dark
                      ? const Color(0xffd4d4d4)
                      : const Color(0xff5a5852),
                  fontVariations: const [
                    FontVariation('wght', 400),
                    FontVariation('wdth', 100),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    SizedBox(height: wide ? _renderedPostQuoteRhythm : _narrowPostQuoteRhythm),
    _focacciaHeading(c, "Baker's Percentages & Ingredients", wide: wide),
    SizedBox(height: wide ? _widePreTableRhythm : _narrowPreTableRhythm),
    _focacciaTable(c),
    const SizedBox(height: _renderedPostTableRhythm),
    _focacciaHeading(
      c,
      'Method & Proofing Schedule',
      wide: wide,
      key: const ValueKey('fixture-focaccia-method'),
    ),
    const SizedBox(height: _methodToTasksRhythm),
    for (final task in const [
      (
        'Mix flour and water for a 45-minute autolyse at room temperature',
        true,
      ),
      ('Inoculate active starter and fold in fine sea salt', true),
      (
        'Perform 4 sets of coil folds every 30 minutes until silky windowpane',
        true,
      ),
      ('Transfer to oiled tin for 16-hour cold retard in refrigerator', false),
      (
        'Generously dimple dough with olive oil and bake on preheated stone',
        false,
      ),
    ])
      SizedBox(
        height: _taskRowAdvance,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.$2 ? LucideIcons.square_check_big : LucideIcons.square,
                size: 17,
                color: task.$2 ? c.accent : c.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  task.$1,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.625,
                    decoration: task.$2 ? TextDecoration.lineThrough : null,
                    color: _dark
                        ? (task.$2 ? c.textMuted : null)
                        : (task.$2
                              ? const Color(0xff8e8b82)
                              : const Color(0xff1e1e1c)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    const SizedBox(height: 16),
    if (_suggestionOpen)
      _suggestion(c)
    else
      _sourceOrText(
        c,
        'bake',
        'Bake at 220°C for 28 minutes on the center oven rack until golden brown.',
        const Text(
          'Bake at 220°C for 28 minutes on the center oven rack until golden brown.',
          style: TextStyle(fontSize: 15, height: 1.65),
        ),
      ),
    const Divider(height: 40),
    RichText(
      key: const ValueKey('fixture-footer-rich-text'),
      text: TextSpan(
        style: TextStyle(
          fontFamily: burlPrototypeSansFontFamily,
          fontSize: 15,
          height: 1.65,
          color: _dark ? const Color(0xffd4d4d4) : const Color(0xff1e1e1c),
          fontVariations: const [FontVariation('wght', 400)],
        ),
        children: [
          const TextSpan(text: 'Pairs exceptionally well with '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _captureAnchor(
              'link-hover',
              CompositedTransformTarget(
                link: _linkLayer,
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _linkHovered = true;
                      _linkCapturePinned = true;
                    });
                    _anchorCapture('link-hover', alignment: .97);
                  },
                  onExit: (_) {
                    if (!_linkCapturePinned) {
                      setState(() => _linkHovered = false);
                    }
                  },
                  child: GestureDetector(
                    key: const ValueKey('fixture-link-normal'),
                    onTap: () {
                      setState(() {
                        _linkHovered = !_linkHovered;
                        _linkCapturePinned = _linkHovered;
                      });
                      if (_linkHovered) {
                        _anchorCapture('link-hover', alignment: .97);
                      }
                    },
                    child: SizedBox(
                      width: 126,
                      height: 25,
                      child: Transform.translate(
                        key: const ValueKey('fixture-link-anchor-paint'),
                        offset: const Offset(-5, -6),
                        child: Container(
                          key: const ValueKey('fixture-link-hover-surface'),
                          decoration: BoxDecoration(
                            color: _linkHovered
                                ? const Color(0xff1c261e)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.link_2,
                                key: ValueKey('fixture-link-anchor-icon'),
                                size: 12,
                                color: Color(0xffa3d1a9),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'cold-brew-ratio',
                                  key: const ValueKey(
                                    'fixture-link-anchor-label',
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontFamily: burlPrototypeSansFontFamily,
                                    fontSize: 15,
                                    height: 24.75 / 15,
                                    fontWeight: FontWeight.w500,
                                    color: _linkHovered
                                        ? const Color(0xffffffff)
                                        : const Color(0xffa3d1a9),
                                    decoration: TextDecoration.underline,
                                    fontVariations: const [
                                      FontVariation('wght', 500),
                                      FontVariation('wdth', 100),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const TextSpan(
            text:
                ' in the morning or as sandwich bread\nfor weekend picnics. Logged in ',
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(
              key: const ValueKey('fixture-weekly-review-link'),
              width: 119,
              height: 25,
              child: const Text(
                'weekly-review',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: burlPrototypeSansFontFamily,
                  fontSize: 15,
                  height: 24.75 / 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xffa3d1a9),
                  decoration: TextDecoration.underline,
                  fontVariations: [
                    FontVariation('wght', 500),
                    FontVariation('wdth', 100),
                  ],
                ),
              ),
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    ),
  ];

  List<Widget> _homelabBlocks(BurlColors c) => [
    // Keep the Homelab title aligned to the normal-host reference baseline.
    const SizedBox(height: 43),
    _sourceOrText(
      c,
      'homelab-title',
      '# Homelab Architecture & Local Services Setup',
      const Text(
        'Homelab Architecture & Local Services Setup',
        key: ValueKey('fixture-homelab-h1'),
        style: TextStyle(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    const SizedBox(height: 28),
    const Text(
      'Architecture notes and configuration guide for my low-power mini PC cluster running Proxmox VE, Tailscale mesh networking, automated ZFS dataset snapshots, and containerized private services.',
      key: ValueKey('fixture-homelab-intro'),
      style: TextStyle(fontSize: 14, height: 1.5),
    ),
    const SizedBox(height: 20),
    const Text(
      'Network Topology & Reverse Proxy',
      key: ValueKey('fixture-homelab-network-heading'),
      style: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 17),
    const Text(
      'Split-horizon DNS handles local resolution via Pi-hole. All internal web services resolve via `.internal` domains authenticated with automated wildcard SSL certificates through Cloudflare DNS-01 challenges.',
      key: ValueKey('fixture-homelab-network-prose'),
      style: TextStyle(fontSize: 14, height: 1.5),
    ),
    const SizedBox(height: 16),
    _sourceOrText(c, 'homelab-code', _caddyYaml, _codeBlock(c, _caddyYaml)),
    const SizedBox(height: 24),
    const Text(
      'Storage & Backup Strategy',
      style: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700),
    ),
  ];

  List<Widget> _recoveredBlocks(BurlColors c, {required bool wide}) => [
    SizedBox(height: (wide ? _wideDocumentTop : _narrowDocumentTop) + 16),
    Text(
      'Cold Brew Ratio & Immersion Guide (Recovered Draft)',
      key: ValueKey('fixture-recovered-h1'),
      style: TextStyle(
        fontSize: wide ? 30 : 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -.75,
      ),
    ),
    Divider(height: 19, color: c.borderSubtle),
    const SizedBox(height: 18),
    const Text(
      'Draft notes on brewing a sweet, low-acidity cold brew concentrate with rich chocolate and stone-fruit notes using a 1:5 brew ratio steeped at 4°C for 18 hours.',
      style: TextStyle(fontSize: 14, height: 1.5),
    ),
    const SizedBox(height: 18),
    const SizedBox(height: 21),
    for (final task in const [
      ('Coarsely grind 200g washed Ethiopian single-origin beans', true),
      (
        'Combine with 1000g cold filtered water in Mason jar and gentle stir',
        true,
      ),
      ('Steep in refrigerator for 18 hours', false),
      (
        'Double-strain through stainless mesh and paper filter; dilute 1:1 with ice',
        false,
      ),
    ])
      SizedBox(
        height: _taskRowAdvance,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.$2 ? LucideIcons.square_check_big : LucideIcons.square,
                key: ValueKey('fixture-recovered-task-${task.$1}'),
                size: 17,
                color: task.$2 ? c.accent : c.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  task.$1,
                  style: const TextStyle(fontSize: 15, height: 1.625),
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  Widget _captureAnchor(String id, Widget child) => KeyedSubtree(
    key: ValueKey('fixture-anchor-$id'),
    child: KeyedSubtree(key: _captureAnchors[id], child: child),
  );

  Widget _sourceOrText(
    BurlColors c,
    String id,
    String source,
    Widget rendered,
  ) {
    final raw = _rawBlock == id;
    final block = raw
        ? SizedBox(
            width: id == 'homelab-code' ? 584 : null,
            height: id == 'homelab-code' ? 416 : null,
            child: Container(
              key: ValueKey('fixture-raw-$id'),
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: 415,
                    child: ColoredBox(
                      key: ValueKey('fixture-raw-fill'),
                      color: Color(0xff1e1e20),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 2,
                    height: 415,
                    child: ColoredBox(
                      key: const ValueKey('fixture-raw-border'),
                      color: c.accent,
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      key: const ValueKey('fixture-raw-editor-inset'),
                      // Preserve the editor's available height while lifting
                      // the raw paint one pixel to the prototype baseline.
                      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
                      child: ClipRect(
                        child: Transform.scale(
                          key: const ValueKey('fixture-raw-ink-scale'),
                          alignment: Alignment.topLeft,
                          scaleY: 367 / 370,
                          // The transform is paint-only: selection, caret, and hit
                          // testing remain in the unscaled editable coordinate space.
                          transformHitTests: false,
                          child: TextField(
                            key: ValueKey('fixture-raw-input-$id'),
                            controller: TextEditingController(text: source),
                            expands: id == 'homelab-code',
                            maxLines: null,
                            minLines: null,
                            scrollPadding: EdgeInsets.zero,
                            textAlignVertical: TextAlignVertical.top,
                            // Keep the requested 14px / 1.625 source style while the
                            // forced strut removes the three surplus pixels across the
                            // full raw run without moving its editor rectangle.
                            strutStyle: const StrutStyle(
                              fontFamily: burlPrototypeMonoFontFamily,
                              fontSize: 14,
                              // V13 interpolation: 1.6000 paints 354px and 1.6125
                              // paints 370px, so 1.6102 targets the 367px reference.
                              height: 1.6102,
                              forceStrutHeight: true,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                              filled: false,
                            ),
                            style: const TextStyle(
                              fontFamily: burlPrototypeMonoFontFamily,
                              fontFamilyFallback: burlPrototypeMonoFallback,
                              fontSize: 14,
                              height: 1.625,
                              // The prototype's Linux face is fractionally tighter than
                              // Flutter's editable glyph run; preserve its 368px ink
                              // width without touching the measured editor rectangle.
                              letterSpacing: -.02,
                              color: Color(0xfff5f5f5),
                            ),
                            onSubmitted: (_) =>
                                setState(() => _rawBlock = null),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : GestureDetector(
            onTap: () => _showRawBlock(id),
            // The measured reference raises the rendered intro ink while its
            // line box still reserves the normal prose rhythm.
            child: id == 'intro'
                ? Transform.translate(
                    offset: const Offset(0, -5),
                    child: rendered,
                  )
                : rendered,
          );
    if (id == 'intro' && raw) {
      return SizedBox(
        height: _rawIntroHeight,
        child: Transform.translate(
          offset: const Offset(0, _rawIntroLift),
          child: block,
        ),
      );
    }
    if (id != 'homelab-code') return block;
    if (raw) {
      return Column(
        children: [
          // This controller-only counterpart to the title shift keeps raw
          // source geometry at the normal-host y=447 capture target without
          // changing the controller-null fixture.
          SizedBox(height: widget.captureController == null ? 56 : 57),
          _captureAnchor('code-raw', block),
        ],
      );
    }
    return Column(
      children: [
        // This controller-only counterpart to the title shift keeps rendered
        // code at its measured capture baseline without changing the ordinary
        // fixture document.
        if (widget.captureController != null) const SizedBox(height: 74),
        _captureAnchor('code-rendered', block),
      ],
    );
  }

  Widget _suggestion(BurlColors c) => _captureAnchor(
    'suggestion',
    GestureDetector(
      key: const ValueKey('fixture-suggestion-block'),
      onTap: () => _anchorCapture('suggestion', alignment: .486),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final outerWidth = constraints.maxWidth >= 584
              ? 584.0
              : constraints.maxWidth;
          final exact = outerWidth == 584;
          final compactActionWidth = (outerWidth - 161).clamp(0.0, 88.0);
          return SizedBox(
            width: outerWidth,
            height: 263,
            child: Container(
              decoration: _box(c),
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 18,
                      width: 12,
                      height: 12,
                      child: Icon(
                        LucideIcons.git_pull_request,
                        key: const ValueKey('fixture-suggestion-git-pull-icon'),
                        size: 12,
                        color: c.accent,
                      ),
                    ),
                    Positioned(
                      left: 32,
                      top: 16,
                      right: 116,
                      height: 18,
                      child: Text(
                        'Incoming edit  ·  maya@home-network (Remote origin/main)',
                        key: const ValueKey('fixture-suggestion-header'),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontFamilyFallback: burlPrototypeMonoFallback,
                          fontSize: 11,
                          height: 1.625,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      width: 93,
                      height: 18,
                      child: FittedBox(
                        alignment: Alignment.centerRight,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Today at 19:42',
                          key: const ValueKey('fixture-suggestion-timestamp'),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontFamily: burlPrototypeMonoFontFamily,
                            fontFamilyFallback: burlPrototypeMonoFallback,
                            fontSize: 11,
                            height: 1.625,
                            color: c.textMuted,
                          ),
                        ),
                      ),
                    ),
                    _suggestionDiffLane(
                      key: const ValueKey('fixture-suggestion-removed'),
                      top: 40,
                      height: 66,
                      width: exact ? 550 : null,
                      right: exact ? null : 16,
                      added: false,
                      text:
                          '- Bake at 220°C for 28 minutes on the center oven rack until golden brown.',
                      colors: c,
                    ),
                    _suggestionDiffLane(
                      key: const ValueKey('fixture-suggestion-added'),
                      top: 114,
                      height: 87,
                      width: exact ? 550 : null,
                      right: exact ? null : 16,
                      added: true,
                      text:
                          '+ Preheat baking steel at 235°C for 45 minutes. Bake on bottom rack for 22 minutes with a water steam tray, then 3 minutes under top broiler for bubbly blistered crust.',
                      colors: c,
                    ),
                    Positioned(
                      left: 16,
                      top: 216,
                      width: 119,
                      height: 28,
                      child: _suggestionAction(
                        key: const ValueKey('fixture-suggestion-accept'),
                        label: 'Accept Incoming',
                        filled: true,
                        colors: c,
                        onPressed: () =>
                            setState(() => _suggestionOpen = false),
                      ),
                    ),
                    Positioned(
                      left: 144,
                      top: 216,
                      width: exact ? 88 : compactActionWidth,
                      height: 29,
                      child: _suggestionAction(
                        key: const ValueKey('fixture-suggestion-keep-local'),
                        label: 'Keep Local',
                        colors: c,
                        onPressed: () =>
                            setState(() => _suggestionOpen = false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _suggestionDiffLane({
    required Key key,
    required double top,
    required double height,
    double? width,
    double? right,
    required bool added,
    required String text,
    required BurlColors colors,
  }) => Positioned(
    left: 16,
    top: top,
    width: width,
    right: right,
    height: height,
    child: Container(
      key: key,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: added ? colors.diffAddBackground : colors.diffDeleteBackground,
        border: Border(
          left: BorderSide(
            color: added ? colors.diffAddBorder : colors.diffDeleteBorder,
            width: 4,
          ),
        ),
      ),
      child: ClipRect(
        child: Text(
          text,
          maxLines: added ? 4 : 2,
          overflow: TextOverflow.clip,
          softWrap: true,
          style: TextStyle(
            fontFamily: burlPrototypeMonoFontFamily,
            fontFamilyFallback: burlPrototypeMonoFallback,
            fontSize: 13,
            height: 1.625,
            color: added ? const Color(0xff86efac) : const Color(0xfffda4af),
          ),
        ),
      ),
    ),
  );

  Widget _suggestionAction({
    required Key key,
    required String label,
    required BurlColors colors,
    required VoidCallback onPressed,
    bool filled = false,
  }) => TextButton(
    key: key,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      backgroundColor: filled ? colors.textPrimary : Colors.transparent,
      foregroundColor: filled ? colors.editor : colors.textSecondary,
      padding: EdgeInsets.zero,
      minimumSize: const Size.fromHeight(1),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: filled ? BorderSide.none : BorderSide(color: colors.borderStrong),
      ),
      textStyle: const TextStyle(
        fontFamily: burlPrototypeSansFontFamily,
        fontFamilyFallback: burlPrototypeSansFallback,
        fontSize: 12,
        height: 1,
      ),
    ),
    child: Text(label, maxLines: 1, overflow: TextOverflow.clip),
  );

  // Kept as source reference while the capture uses fixed-height table rows.
  // ignore: unused_element
  Widget _focacciaTableLegacy(BurlColors c) => Container(
    key: const ValueKey('fixture-focaccia-table'),
    decoration: _box(c),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
      ),
      child: Table(
        columnWidths: const <int, TableColumnWidth>{
          0: FixedColumnWidth(208),
          1: FixedColumnWidth(90),
          2: FixedColumnWidth(86),
          3: FixedColumnWidth(200),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: c.borderSubtle),
        ),
        children: const [
          TableRow(
            children: [
              Padding(padding: EdgeInsets.all(8), child: Text('Ingredient')),
              Padding(padding: EdgeInsets.all(8), child: Text('Weight (g)')),
              Padding(padding: EdgeInsets.all(8), child: Text("Baker's %")),
              Padding(padding: EdgeInsets.all(8), child: Text('Notes')),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Bread Flour (12.7% protein)'),
              ),
              Padding(padding: EdgeInsets.all(8), child: Text('500g')),
              Padding(padding: EdgeInsets.all(8), child: Text('100%')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('High-protein unbleached flour'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Lukewarm Water (28°C)'),
              ),
              Padding(padding: EdgeInsets.all(8), child: Text('410g')),
              Padding(padding: EdgeInsets.all(8), child: Text('82%')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Filtered non-chlorinated'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Active Sourdough Starter'),
              ),
              Padding(padding: EdgeInsets.all(8), child: Text('100g')),
              Padding(padding: EdgeInsets.all(8), child: Text('20%')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Fed 1:1:1 at peak bubbly rise'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(padding: EdgeInsets.all(8), child: Text('Fine Sea Salt')),
              Padding(padding: EdgeInsets.all(8), child: Text('10g')),
              Padding(padding: EdgeInsets.all(8), child: Text('2.0%')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Dissolved during autolyse'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Extra Virgin Olive Oil'),
              ),
              Padding(padding: EdgeInsets.all(8), child: Text('35g')),
              Padding(padding: EdgeInsets.all(8), child: Text('7.0%')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Cold-pressed Greek Koroneiki'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Fresh Rosemary & Maldon Salt'),
              ),
              Padding(padding: EdgeInsets.all(8), child: Text('To taste')),
              Padding(padding: EdgeInsets.all(8), child: Text('—')),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Picked fresh from balcony'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _focacciaHeading(
    BurlColors c,
    String label, {
    required bool wide,
    Key? key,
  }) => Transform.translate(
    // Keep the heading's allocated line box stable; only the narrow paint is
    // aligned to the prototype's glyph bounds.
    offset: wide ? Offset.zero : const Offset(-2, 0),
    child: Transform(
      alignment: Alignment.topLeft,
      transform: Matrix4.identity(),
      child: Text(
        label,
        key: key,
        style: TextStyle(
          fontFamily: burlPrototypeSansFontFamily,
          fontSize: wide ? 20 : 18,
          height: wide ? 1.4 : 28 / 18,
          fontWeight: FontWeight.w600,
          letterSpacing: wide ? -.5 : -.45,
          color: _dark ? const Color(0xffe5e5e5) : const Color(0xff1e1e1c),
          fontVariations: const [
            FontVariation('wght', 600),
            FontVariation('wdth', 100),
          ],
        ),
      ),
    ),
  );

  Widget _focacciaTable(BurlColors c) => Container(
    key: const ValueKey('fixture-focaccia-table'),
    decoration: BoxDecoration(
      color: _dark ? c.sidebar : const Color(0xfff7f5ee),
      border: Border.all(
        color: _dark ? c.borderSubtle : const Color(0xff8e8b82),
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(208),
        1: FixedColumnWidth(90),
        2: FixedColumnWidth(86),
        3: FixedColumnWidth(200),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: _dark ? c.borderSubtle : const Color(0xff8e8b82),
        ),
      ),
      children: [
        _fixtureTableRow(
          'Ingredient',
          'Weight (g)',
          "Baker's %",
          'Notes',
          header: true,
        ),
        _fixtureTableRow(
          'Bread Flour (12.7% protein)',
          '500g',
          '100%',
          'High-protein unbleached flour',
        ),
        _fixtureTableRow(
          'Lukewarm Water (28°C)',
          '410g',
          '82%',
          'Filtered non-chlorinated',
        ),
        _fixtureTableRow(
          'Active Sourdough Starter',
          '100g',
          '20%',
          'Fed 1:1:1 at peak bubbly rise',
        ),
        _fixtureTableRow(
          'Fine Sea Salt',
          '10g',
          '2.0%',
          'Dissolved during autolyse',
        ),
        _fixtureTableRow(
          'Extra Virgin Olive Oil',
          '35g',
          '7.0%',
          'Cold-pressed Greek Koroneiki',
        ),
        _fixtureTableRow(
          'Fresh Rosemary & Maldon Salt',
          'To taste',
          '—',
          'Picked fresh from balcony',
        ),
      ],
    ),
  );

  TableRow _fixtureTableRow(
    String ingredient,
    String weight,
    String percentage,
    String notes, {
    bool header = false,
  }) => TableRow(
    children: [
      for (final value in [ingredient, weight, percentage, notes])
        SizedBox(
          height: header ? 32 : 33,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: burlPrototypeSansFontFamily,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                color: _dark
                    ? (header
                          ? const Color(0xffe5e5e5)
                          : const Color(0xffd4d4d4))
                    : (header
                          ? const Color(0xff1e1e1c)
                          : const Color(0xff5a5852)),
                fontVariations: [
                  FontVariation('wght', header ? 700 : 400),
                  const FontVariation('wdth', 100),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _codeBlock(BurlColors c, String source) => SizedBox(
    width: 584,
    height: 357,
    child: DecoratedBox(
      key: const ValueKey('fixture-code-rendered'),
      decoration: _box(c),
      child: ClipRect(
        child: Column(
          children: [
            SizedBox(
              key: const ValueKey('fixture-code-header'),
              height: 27,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.borderSubtle)),
                ),
                child: Stack(
                  children: [
                    const Positioned(
                      left: 12,
                      top: 6,
                      child: Text(
                        'yaml',
                        key: ValueKey('fixture-code-language'),
                        style: TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontFamilyFallback: burlPrototypeMonoFallback,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      width: 64,
                      height: 27,
                      child: TextButton(
                        key: const ValueKey('fixture-code-copy'),
                        onPressed: _markHomelabCodeCopied,
                        style: TextButton.styleFrom(
                          foregroundColor: c.textMuted,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(64, 27),
                          maximumSize: const Size(64, 27),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontFamily: burlPrototypeSansFontFamily,
                            fontFamilyFallback: burlPrototypeSansFallback,
                            fontSize: 12,
                            height: 1,
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Icon(
                                _codeCopied
                                    ? LucideIcons.copy_check
                                    : LucideIcons.copy,
                                key: const ValueKey('fixture-code-copy-icon'),
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(_codeCopied ? 'Copied' : 'Copy'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              key: const ValueKey('fixture-code-body'),
              height: 330,
              child: ClipRect(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 560,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        source
                            .replaceFirst(RegExp(r'^```[^\n]*\n'), '')
                            .replaceFirst(RegExp(r'\n```$'), ''),
                        key: const ValueKey('fixture-homelab-yaml'),
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontFamily: burlPrototypeMonoFontFamily,
                          fontFamilyFallback: burlPrototypeMonoFallback,
                          fontSize: 12.5,
                          height: 1.625,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _overlaySurface(BurlColors c) => Positioned.fill(
    key: const ValueKey('fixture-overlay-surface'),
    child: Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          SizedBox.expand(
            child: GestureDetector(
              key: const ValueKey('fixture-overlay-scrim'),
              onTap: _closeOverlay,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: const SizedBox.expand(
                  child: ColoredBox(color: Color(0x80000000)),
                ),
              ),
            ),
          ),
          switch (_overlay) {
            'preferences' => _preferences(c),
            'search' => _search(c),
            'sync' => _sync(c),
            'history' => _history(c),
            _ => _delete(c),
          },
        ],
      ),
    ),
  );

  Widget _fixturePanel({
    required Key key,
    required Alignment alignment,
    required double width,
    required Widget child,
    Color? panelColor,
    Color? panelBorder,
  }) => Align(
    alignment: alignment,
    child: BurlScaleFadeEntrance(
      child: Material(
        key: key,
        color: panelColor ?? cForPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color:
                panelBorder ??
                (_dark
                    ? BurlColors.dark.borderSubtle
                    : BurlColors.light.borderSubtle),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
  Color get cForPanel =>
      _dark ? BurlColors.dark.editor : BurlColors.light.editor;

  Widget _preferences(BurlColors c) => _fixturePanel(
    key: const ValueKey('fixture-preferences-drawer'),
    alignment: Alignment.centerRight,
    width: 448,
    panelColor: const Color(0xff18181b),
    panelBorder: const Color(0xff27272a),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            MediaQuery.sizeOf(context).width >= 900
            ? _preferenceMatrix(c)
            : _preferencesFlow(c),
      ),
    ),
  );

  /// The desktop reference is a fixed 1440×900 capture. These slots are
  /// deliberately explicit rather than grid-derived so browser/engine font
  /// metrics cannot move a card by a pixel and invalidate the comparison.
  Widget _preferenceMatrix(BurlColors c) => SizedBox(
    height: double.infinity,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _overlayHeader(
            c,
            'Editor Preferences',
            LucideIcons.settings,
            background: const Color(0xff141416),
          ),
        ),
        _preferenceCaption(c, 'Appearance Theme', 76),
        _preferenceCaption(c, 'Base Reading Size', 180),
        _preferenceCaption(c, 'Prose Line Measure', 310),
        _preferenceCaption(c, 'Desktop Platform Chrome', 485),
        _preferenceCaption(c, 'Editor Features', 567),
        _preferenceSlot(
          c,
          label: 'Appearance Theme',
          index: 0,
          value: 'Washi Paper\nLight Mode',
          selected: !_dark,
          left: 21,
          top: 102,
          width: 200,
          height: 55,
          onTap: () => _setDark(false),
        ),
        _preferenceSlot(
          c,
          label: 'Appearance Theme',
          index: 1,
          value: 'Sumi Ink\nDark Mode',
          selected: _dark,
          left: 229,
          top: 102,
          width: 199,
          height: 55,
          onTap: () => _setDark(true),
        ),
        ..._preferenceMatrixSlots(
          c,
          label: 'Base Reading Size',
          values: const [
            'Compact (14px)',
            'Standard (16px)',
            'Comfortable (18px)',
            'Large (20px)',
          ],
          rowTops: const [206, 250],
          columns: 2,
          widths: const [200, 199],
          heights: const [36, 37],
          selected: 1,
        ),
        ..._preferenceMatrixSlots(
          c,
          label: 'Prose Line Measure',
          values: const [
            '55ch (Narrow reading)',
            '65ch (Standard prose)',
            '75ch (Wide / Technical)',
            '85ch (Code & Tables)',
            'Full Width',
          ],
          rowTops: const [336, 380, 425],
          columns: 2,
          widths: const [200, 199],
          heights: const [36, 37, 37],
          selected: 1,
        ),
        ..._preferenceMatrixSlots(
          c,
          label: 'Desktop Platform Chrome',
          values: const ['Macos', 'Linux', 'Minimal'],
          rowTops: const [510],
          columns: 3,
          widths: const [130, 131, 130],
          heights: const [33],
          selected: 0,
        ),
        Positioned(
          left: 21,
          top: 592,
          width: 407,
          height: 55,
          child: _preferenceFocusMode(c),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _overlayFooter(
            c,
            const Text('Preferences saved locally'),
            'Done',
            'fixture-preferences-done',
            fixedHeight: 52,
            actionSize: const Size(60, 28),
            actionBackground: const Color(0xffe4e4e7),
            actionForeground: const Color(0xff18181b),
          ),
        ),
      ],
    ),
  );

  Positioned _preferenceCaption(BurlColors c, String label, double top) =>
      Positioned(
        left: 20,
        top: top,
        child: Text(
          label.toUpperCase(),
          key: ValueKey(
            'fixture-preferences-section-${label.replaceAll(' ', '-')}',
          ),
          style: _caption(c),
        ),
      );

  List<Widget> _preferenceMatrixSlots(
    BurlColors c, {
    required String label,
    required List<String> values,
    required List<double> rowTops,
    required int columns,
    required List<double> widths,
    required List<double> heights,
    required int selected,
  }) => [
    for (var index = 0; index < values.length; index++)
      _preferenceSlot(
        c,
        label: label,
        index: index,
        value: values[index],
        selected: index == selected,
        left: columns == 3
            ? const [21.0, 159.0, 298.0][index]
            : 21 + (index % columns) * 208,
        top: rowTops[index ~/ columns],
        width: widths[index % columns],
        height: heights[index ~/ columns],
      ),
  ];

  Widget _preferenceSlot(
    BurlColors c, {
    required String label,
    required int index,
    required String value,
    required bool selected,
    required double left,
    required double top,
    required double width,
    required double height,
    VoidCallback? onTap,
  }) => Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: InkWell(
      key: ValueKey('fixture-preferences-${label.replaceAll(' ', '-')}-$index'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff222227) : const Color(0xff141417),
          border: Border.all(
            color: selected ? const Color(0xffa1a1aa) : const Color(0xff27272a),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: burlPrototypeSansFontFamily,
                  fontFamilyFallback: burlPrototypeSansFallback,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? c.textPrimary : c.textSecondary,
                  fontVariations: [FontVariation('wght', selected ? 500 : 400)],
                ),
              ),
            ),
            if (selected) Icon(LucideIcons.check, size: 14, color: c.accent),
          ],
        ),
      ),
    ),
  );

  Widget _preferencesFlow(BurlColors c) => SizedBox(
    height: double.infinity,
    child: Column(
      children: [
        _overlayHeader(c, 'Editor Preferences', LucideIcons.settings),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _preferenceCards(
                c,
                'Appearance Theme',
                ['Washi Paper\nLight Mode', 'Sumi Ink\nDark Mode'],
                _dark ? 1 : 0,
                onTap: (v) => setState(() => _dark = v == 1),
              ),
              _preferenceCards(c, 'Base Reading Size', [
                'Compact (14px)',
                'Standard (16px)',
                'Comfortable (18px)',
                'Large (20px)',
              ], 1),
              _preferenceCards(c, 'Prose Line Measure', [
                '55ch (Narrow reading)',
                '65ch (Standard prose)',
                '75ch (Wide / Technical)',
                '85ch (Code & Tables)',
                'Full Width',
              ], 1),
              _preferenceCards(
                c,
                'Desktop Platform Chrome',
                ['Macos', 'Linux', 'Minimal'],
                0,
                cols: 3,
              ),
              Text('EDITOR FEATURES', style: _caption(c)),
              const SizedBox(height: 9),
              _preferenceFocusMode(c),
            ],
          ),
        ),
        _overlayFooter(
          c,
          const Text('Preferences saved locally'),
          'Done',
          'fixture-preferences-done',
        ),
      ],
    ),
  );

  Widget _preferenceFocusMode(BurlColors c) => GestureDetector(
    key: const ValueKey('fixture-preferences-focus-mode'),
    onTap: () => setState(() => _focusMode = !_focusMode),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _dark ? const Color(0xff141417) : const Color(0xffffffff),
        border: Border.all(color: c.borderSubtle),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Focus Mode (Zen)',
                  style: TextStyle(
                    fontFamily: burlPrototypeSansFontFamily,
                    fontFamilyFallback: burlPrototypeSansFallback,
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dim non-active blocks when editing',
                  style: TextStyle(
                    fontFamily: burlPrototypeSansFontFamily,
                    fontFamilyFallback: burlPrototypeSansFallback,
                    fontSize: 10,
                    height: 1,
                    color: c.textMuted,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('fixture-preferences-focus-toggle'),
            onTap: () => setState(() => _focusMode = !_focusMode),
            child: AnimatedContainer(
              duration: BurlMotion.duration(context, BurlMotion.chrome),
              curve: BurlMotion.enterCurve,
              width: 36,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _focusMode
                    ? (_dark
                          ? const Color(0xff86a789)
                          : const Color(0xff3f5b46))
                    : (_dark
                          ? const Color(0xff3f3f46)
                          : const Color(0xffd4d4d4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: BurlMotion.duration(context, BurlMotion.chrome),
                curve: BurlMotion.enterCurve,
                alignment: _focusMode
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _preferenceCards(
    BurlColors c,
    String label,
    List<String> labels,
    int selected, {
    int cols = 2,
    ValueChanged<int>? onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _caption(c)),
        const SizedBox(height: 7),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: cols == 3 ? 2.8 : 3.7,
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                key: ValueKey(
                  'fixture-preferences-${label.replaceAll(' ', '-')}-$i',
                ),
                onTap: () => onTap?.call(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: _box(c, selected: i == selected),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[i],
                          style: const TextStyle(fontSize: 11, height: 1.15),
                        ),
                      ),
                      if (i == selected)
                        Icon(LucideIcons.check, size: 14, color: c.accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _search(BurlColors c) => _fixturePanel(
    key: const ValueKey('fixture-search-palette'),
    // The source palette has only the two `sourdough` hits. Keep its top
    // edge fixed at the prototype's 108px while the shorter panel hugs them.
    alignment: const Alignment(0, -.6732),
    width: 672,
    panelColor: const Color(0xff18181c),
    panelBorder: const Color(0xff2b2b32),
    child: SizedBox(
      height: 239,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            key: const ValueKey('fixture-search-header'),
            height: 45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(LucideIcons.search, size: 16, color: c.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    // TextField adds Material's cursor, strut, and touch
                    // target padding. The prototype is a bare browser input:
                    // an EditableText gives us that exact transparent field
                    // while retaining a real controller and keyboard input.
                    child: Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: SizedBox(
                        height: 20,
                        child: EditableText(
                          key: const ValueKey('fixture-search-input'),
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: TextStyle(
                            fontFamily: burlPrototypeSansFontFamily,
                            fontFamilyFallback: burlPrototypeSansFallback,
                            fontSize: 14,
                            height: 20 / 14,
                            color: c.textPrimary,
                            fontVariations: const [FontVariation('wght', 400)],
                          ),
                          cursorColor: c.accent,
                          backgroundCursorColor: Colors.transparent,
                          selectionColor: c.accentSubtle,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    key: const ValueKey('fixture-search-escape-keycap'),
                    width: 36,
                    height: 21,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _dark
                          ? const Color(0xff222228)
                          : const Color(0xffefece6),
                      border: Border.all(
                        color: _dark
                            ? const Color(0xff31313a)
                            : const Color(0xffdedad1),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ESC',
                      style: TextStyle(
                        fontFamily: burlPrototypeMonoFontFamily,
                        fontFamilyFallback: burlPrototypeMonoFallback,
                        fontSize: 10,
                        height: 1,
                        color: c.textMuted,
                        fontVariations: const [FontVariation('wght', 400)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 45,
            right: 0,
            height: 39,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xff2b2b32)),
                  bottom: BorderSide(color: Color(0xff2b2b32)),
                ),
              ),
              child: Row(
                children: [
                  Text('Scope:', style: _searchScopeStyle(c)),
                  const SizedBox(width: 9),
                  for (final s in ['All', 'Titles', 'Content'])
                    InkWell(
                      key: ValueKey('fixture-search-scope-$s'),
                      onTap: () => _setSearchScope(s),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: s == _searchScope
                              ? const Color(0xff222c24)
                              : Colors.transparent,
                          border: Border.all(
                            color: s == _searchScope
                                ? const Color(0xff3a563e)
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(s, style: _searchScopeStyle(c)),
                      ),
                    ),
                  const Spacer(),
                  Transform.translate(
                    offset: const Offset(-2, -2),
                    child: Text(
                      '2 matches',
                      key: const ValueKey('fixture-search-density'),
                      style: _searchScopeStyle(c),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 84,
            right: 0,
            height: 121,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (final (index, r) in _searchResults.indexed) ...[
                    SizedBox(
                      height: 50,
                      child: _fixtureSearchResult(
                        c,
                        r.$1,
                        r.$2,
                        r.$3,
                        r.$1 == _searchResult,
                      ),
                    ),
                    if (index != _searchResults.length - 1)
                      const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 205,
            right: 0,
            height: 34,
            child: _overlayFooter(
              c,
              const Text('↑↓ Navigate   ↵ Open Note'),
              'Local Workspace',
              'fixture-search-close',
              label: true,
              fixedHeight: 34,
              background: const Color(0xff141417),
              borderColor: const Color(0xff2b2b32),
              contentOffset: const Offset(-9, -1),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fixtureSearchResult(
    BurlColors c,
    String title,
    String path,
    String excerpt,
    bool selected,
  ) => Container(
    key: ValueKey('fixture-search-result-$title'),
    margin: selected ? const EdgeInsets.symmetric(horizontal: 1) : null,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: selected ? const Color(0xff25252c) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            LucideIcons.file_text,
            size: 14,
            color: selected ? c.accent : const Color(0xffa1a1aa),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: burlPrototypeSansFontFamily,
                        fontFamilyFallback: burlPrototypeSansFallback,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 16 / 12,
                        letterSpacing: -.25,
                        color: selected
                            ? const Color(0xffe8e6df)
                            : const Color(0xffd4d4d4),
                        fontVariations: [FontVariation('wght', 500)],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 185,
                    child: Text(
                      path,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: burlPrototypeMonoFontFamily,
                        fontFamilyFallback: burlPrototypeMonoFallback,
                        fontSize: 10,
                        height: 1.5,
                        color: Color(0xffa3a3a3),
                        fontVariations: [FontVariation('wght', 400)],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 0),
              Transform.translate(
                offset: const Offset(0, 2),
                child: Text(
                  excerpt,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: burlPrototypeMonoFontFamily,
                    fontFamilyFallback: burlPrototypeMonoFallback,
                    fontSize: 11,
                    height: 1.5,
                    color: Color(0xffa3a3a3),
                    fontVariations: [FontVariation('wght', 400)],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              LucideIcons.corner_down_left,
              size: 14,
              color: c.accent,
            ),
          ),
      ],
    ),
  );

  Widget _sync(BurlColors c) {
    final states = _syncStates;
    final state = states[_syncState]!;
    return _fixturePanel(
      key: const ValueKey('fixture-sync-inspector'),
      alignment: Alignment.center,
      width: 384,
      panelColor: const Color(0xff18181b),
      panelBorder: const Color(0xff2a2a30),
      child: SizedBox(
        height: 328,
        child: KeyboardListener(
          focusNode: _syncFocusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) _setSyncStateFromDigit(event.logicalKey);
          },
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: 47,
                child: _overlayHeader(
                  c,
                  'Sync & Storage',
                  null,
                  fixedHeight: 47,
                  background: const Color(0xff141416),
                ),
              ),
              Positioned(
                left: 17,
                top: 64,
                width: 350,
                height: 38,
                child: Container(
                  key: ValueKey('fixture-sync-state-$_syncState'),
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xff141416),
                    border: Border.all(color: const Color(0xff2a2a30)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        state.$3,
                        size: 15,
                        color: _syncStateColor(c, _syncState),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.$1,
                          style: TextStyle(
                            fontFamily: burlPrototypeSansFontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                            fontVariations: [FontVariation('wght', 500)],
                          ),
                        ),
                      ),
                      Text('main', style: _monospace(c)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 17,
                top: 114,
                width: 350,
                height: 18,
                child: Text(
                  state.$2,
                  key: ValueKey('fixture-sync-description-$_syncState'),
                  style: TextStyle(
                    fontFamily: burlPrototypeSansFontFamily,
                    fontSize: 11,
                    height: 18 / 11,
                    color: c.textSecondary,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
              ),
              Positioned(
                left: 17,
                top: 144,
                width: 350,
                height: 57,
                child: Container(
                  key: const ValueKey('fixture-sync-origin-details'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xff141416),
                    border: Border.all(color: const Color(0xff2a2a30)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Path: ~/Notes/Personal-Vault\nOrigin: git@github.com:alex/personal-notes.git',
                    style: TextStyle(
                      fontFamily: burlPrototypeMonoFontFamily,
                      fontFamilyFallback: burlPrototypeMonoFallback,
                      fontSize: 11,
                      height: 14.67 / 11,
                      color: c.textSecondary,
                      fontVariations: const [FontVariation('wght', 400)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 17,
                top: 216,
                child: Text('SIMULATION STATE', style: _caption(c)),
              ),
              Positioned(
                left: 17,
                top: 234,
                width: 350,
                height: 30,
                child: Container(
                  key: const ValueKey('fixture-sync-state-picker'),
                  width: double.infinity,
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: _dark
                        ? const Color(0xff141416)
                        : const Color(0xffffffff),
                    border: Border.all(color: const Color(0xff2a2a30)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('fixture-sync-state-dropdown'),
                      isDense: true,
                      isExpanded: true,
                      value: _syncState,
                      style: TextStyle(
                        fontFamily: burlPrototypeSansFontFamily,
                        fontFamilyFallback: burlPrototypeSansFallback,
                        fontSize: 12,
                        height: 1,
                        color: c.textPrimary,
                        fontVariations: const [FontVariation('wght', 400)],
                      ),
                      icon: Icon(
                        LucideIcons.chevron_down,
                        size: 14,
                        color: c.textMuted,
                      ),
                      items: [
                        for (final item in states.entries)
                          DropdownMenuItem(
                            value: item.key,
                            child: Text(
                              item.value.$1,
                              key: ValueKey('fixture-sync-option-${item.key}'),
                              style: TextStyle(
                                fontFamily: burlPrototypeSansFontFamily,
                                fontFamilyFallback: burlPrototypeSansFallback,
                                fontSize: 12,
                                height: 1,
                                color: c.textPrimary,
                                fontVariations: const [
                                  FontVariation('wght', 400),
                                ],
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) => _setSyncState(value!),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 1,
                right: 1,
                top: 280,
                height: 47,
                child: _syncFooter(c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncFooter(BurlColors c) => Container(
    decoration: const BoxDecoration(
      color: Color(0xff141416),
      border: Border(top: BorderSide(color: Color(0xff2a2a30))),
    ),
    child: Stack(
      children: [
        Positioned(
          left: 16,
          top: 11,
          width: 93,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xff1e1e22),
              border: Border.all(color: const Color(0xff2e2e35)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.refresh_cw,
                    size: 12,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Sync Now',
                    style: TextStyle(
                      fontFamily: burlPrototypeSansFontFamily,
                      fontFamilyFallback: burlPrototypeSansFallback,
                      fontSize: 11,
                      height: 1,
                      color: c.textSecondary,
                      fontVariations: const [FontVariation('wght', 400)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 11,
          width: 52,
          height: 24,
          child: GestureDetector(
            key: const ValueKey('fixture-sync-done'),
            onTap: _closeOverlay,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xffe5e2d9),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontFamily: burlPrototypeSansFontFamily,
                  fontFamilyFallback: burlPrototypeSansFallback,
                  fontSize: 11,
                  height: 1,
                  color: Color(0xff161619),
                  fontVariations: [FontVariation('wght', 400)],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Color _syncStateColor(BurlColors c, String state) => switch (state) {
    'connectedIdle' => c.accent,
    'pendingSuggestions' => c.review,
    _ => c.textSecondary,
  };

  Widget _history(BurlColors c) => _fixturePanel(
    key: const ValueKey('fixture-history-drawer'),
    alignment: Alignment.centerRight,
    width: 576,
    panelColor: const Color(0xff18181b),
    panelBorder: const Color(0xff2a2a30),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            MediaQuery.sizeOf(context).width >= 900
            ? _historyMatrix(c)
            : _historyFlow(c),
      ),
    ),
  );

  Widget _historyMatrix(BurlColors c) => SizedBox(
    height: double.infinity,
    child: Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              const SizedBox(
                width: 224,
                child: ColoredBox(color: Color(0xff141416)),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _overlayHeader(
            c,
            'Git History',
            LucideIcons.clock_3,
            subtitle: 'Kitchen & Recipes/sourdough-focaccia.md',
            fixedHeight: 62,
            background: const Color(0xff141416),
          ),
        ),
        Positioned(
          left: 9,
          top: 77,
          child: Text('3 SNAPSHOTS', style: _caption(c)),
        ),
        for (final (index, snapshot) in _snapshots.indexed)
          _historySnapshotSlot(
            c,
            snapshot,
            top: const [97.0, 192.0, 288.0][index],
            height: const [89.0, 90.0, 90.0][index],
          ),
        Positioned(
          left: 241,
          top: 97,
          width: 319,
          height: 99,
          child: Container(
            key: const ValueKey('fixture-history-snapshot-details'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff141416),
              border: Border.all(color: const Color(0xff2a2a30)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _historyDetailRow(c, 'Commit:', _snapshot, accent: true),
                const SizedBox(height: 2),
                _historyDetailRow(c, 'Author:', 'You (local)'),
                const SizedBox(height: 2),
                _historyDetailRow(c, 'Date:', '5 mins ago'),
                const SizedBox(height: 2),
                Text(
                  'Status: HEAD',
                  style: TextStyle(
                    fontFamily: burlPrototypeMonoFontFamily,
                    fontFamilyFallback: burlPrototypeMonoFallback,
                    fontSize: 10.5,
                    height: 1,
                    color: c.textMuted,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
                const Spacer(),
                Container(height: 1, color: const Color(0xff27272a)),
                const SizedBox(height: 5),
                Text(
                  '“Add baker percentage table and coil fold timings”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: burlPrototypeSansFontFamily,
                    fontFamilyFallback: burlPrototypeSansFallback,
                    fontSize: 11,
                    height: 1,
                    color: c.textSecondary,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 241,
          top: 210,
          child: Text('WORKING TREE COMPARISON', style: _caption(c)),
        ),
        Positioned(
          left: 241,
          top: 230,
          width: 319,
          height: 92,
          child: Container(
            key: const ValueKey('fixture-history-diff'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff141416),
              border: Border.all(color: const Color(0xff2a2a30)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Column(
              children: [
                SizedBox(
                  height: 31,
                  child: _FixtureDiffLine(
                    '-  1 revised block in working copy',
                    false,
                  ),
                ),
                SizedBox(height: 4),
                SizedBox(
                  height: 31,
                  child: _FixtureDiffLine(
                    '+  2 saved blocks in local Git tree',
                    true,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 241,
          top: 347,
          width: 319,
          height: 34,
          child: _historyRestoreButton(c, width: 319),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _overlayFooter(
            c,
            const Text(
              'Stored in .git/',
              style: TextStyle(
                fontFamily: burlPrototypeMonoFontFamily,
                fontSize: 11,
              ),
            ),
            'Done',
            'fixture-history-done',
            fixedHeight: 45,
            actionSize: const Size(53, 24),
            background: const Color(0xff141416),
            actionBackground: const Color(0xffe5e2d9),
            actionForeground: const Color(0xff161619),
          ),
        ),
      ],
    ),
  );

  Widget _historyDetailRow(
    BurlColors c,
    String label,
    String value, {
    bool accent = false,
  }) => Row(
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: burlPrototypeMonoFontFamily,
          fontFamilyFallback: burlPrototypeMonoFallback,
          fontSize: 10.5,
          height: 1,
          color: c.textMuted,
          fontVariations: const [FontVariation('wght', 400)],
        ),
      ),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontFamily: burlPrototypeMonoFontFamily,
          fontFamilyFallback: burlPrototypeMonoFallback,
          fontSize: 10.5,
          height: 1,
          color: accent ? c.accent : c.textPrimary,
          fontVariations: const [FontVariation('wght', 500)],
        ),
      ),
    ],
  );

  Widget _historySnapshotSlot(
    BurlColors c,
    (String, String, String) snapshot, {
    required double top,
    required double height,
  }) => Positioned(
    left: 9,
    top: top,
    width: 207,
    height: height,
    child: GestureDetector(
      key: ValueKey('fixture-history-snapshot-${snapshot.$1}'),
      onTap: () => _setHistorySnapshot(snapshot.$1),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _snapshot == snapshot.$1
              ? const Color(0xff222228)
              : const Color(0xff18181c),
          border: Border.all(
            color: _snapshot == snapshot.$1
                ? const Color(0xffa3a3a3)
                : const Color(0xff2a2a30),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontFamily: burlPrototypeSansFontFamily,
            fontFamilyFallback: burlPrototypeSansFallback,
            fontSize: 10.5,
            height: 1.22,
            color: _snapshot == snapshot.$1 ? c.textPrimary : c.textSecondary,
            fontVariations: const [FontVariation('wght', 400)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot.$1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: burlPrototypeMonoFontFamily,
                        fontFamilyFallback: burlPrototypeMonoFallback,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                        fontVariations: const [FontVariation('wght', 600)],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(snapshot.$2),
                ],
              ),
              const SizedBox(height: 4),
              Text(snapshot.$3, maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(
                children: [
                  Text('You (local)', style: _monospace(c)),
                  if (snapshot.$1 == _snapshots.first.$1) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text('HEAD', style: _monospace(c)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _historyFlow(BurlColors c) => SizedBox(
    height: double.infinity,
    child: Column(
      children: [
        _overlayHeader(
          c,
          'Git History',
          LucideIcons.clock_3,
          subtitle: 'Kitchen & Recipes/sourdough-focaccia.md',
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 224,
                child: Container(
                  color: c.surfaceRaised,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('3 SNAPSHOTS', style: _caption(c)),
                      for (final v in _snapshots)
                        InkWell(
                          key: ValueKey('fixture-history-snapshot-${v.$1}'),
                          onTap: () => setState(() => _snapshot = v.$1),
                          child: Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(7),
                            decoration: _box(c, selected: _snapshot == v.$1),
                            child: Text(
                              '${v.$1}\n${v.$3}\n${v.$2}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: const ValueKey('fixture-history-snapshot-details'),
                        padding: const EdgeInsets.all(10),
                        decoration: _box(c),
                        child: Text(
                          'Commit: $_snapshot\nAuthor: You (local)\nDate: 5 mins ago\nStatus: HEAD\n\n“Add baker percentage table and coil fold timings”',
                          style: _monospace(c, height: 1.55),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('WORKING TREE COMPARISON', style: _caption(c)),
                      const SizedBox(height: 6),
                      Container(
                        key: const ValueKey('fixture-history-diff'),
                        padding: const EdgeInsets.all(10),
                        decoration: _box(c),
                        child: const Column(
                          children: [
                            _FixtureDiffLine(
                              '-  1 revised block in working copy',
                              false,
                            ),
                            SizedBox(height: 8),
                            _FixtureDiffLine(
                              '+  2 saved blocks in local Git tree',
                              true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      _historyRestoreButton(c, width: double.infinity),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _overlayFooter(
          c,
          const Text(
            'Stored in .git/',
            style: TextStyle(
              fontFamily: burlPrototypeMonoFontFamily,
              fontSize: 11,
            ),
          ),
          'Done',
          'fixture-history-done',
        ),
      ],
    ),
  );

  Widget _historyRestoreButton(BurlColors c, {required double width}) =>
      GestureDetector(
        key: const ValueKey('fixture-history-restore'),
        onTap: () {},
        child: Container(
          width: width,
          height: 34,
          decoration: BoxDecoration(
            color: _dark ? const Color(0xff141416) : const Color(0xffffffff),
            border: Border.all(
              color: _dark ? const Color(0xff2a2a30) : c.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.rotate_ccw, size: 14, color: c.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Restore Note to Snapshot $_snapshot',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: burlPrototypeSansFontFamily,
                    fontFamilyFallback: burlPrototypeSansFallback,
                    fontSize: 11,
                    height: 1,
                    color: c.textSecondary,
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _delete(BurlColors c) => _fixturePanel(
    key: const ValueKey('fixture-delete-dialog'),
    alignment: Alignment.center,
    width: 384,
    panelBorder: const Color(0xff2a2a30),
    child: SizedBox(
      height: 210,
      child: Stack(
        children: [
          Positioned(
            left: 17,
            top: 17.4,
            width: 320,
            height: 40,
            child: Text(
              'Delete “Sourdough Focaccia with Rosemary & Sea Salt”?',
              style: const TextStyle(
                fontFamily: burlPrototypeSansFontFamily,
                fontFamilyFallback: burlPrototypeSansFallback,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w500,
                color: Color(0xffe4e4e7),
                fontVariations: [FontVariation('wght', 500)],
              ),
            ),
          ),
          Positioned(
            left: 17,
            top: 59.4,
            width: 350,
            height: 16.5,
            child: Text(
              'Kitchen & Recipes/sourdough-focaccia.md',
              key: const ValueKey('fixture-delete-path'),
              style: TextStyle(
                fontFamily: burlPrototypeMonoFontFamily,
                fontFamilyFallback: burlPrototypeMonoFallback,
                fontSize: 11,
                height: 16.5 / 11,
                letterSpacing: 0,
                color: const Color(0xffa1a1a1),
                fontVariations: const [FontVariation('wght', 400)],
              ),
            ),
          ),
          Positioned(
            left: 17,
            top: 92,
            width: 350,
            height: 58,
            child: Container(
              key: const ValueKey('fixture-delete-git-explainer'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xff141416),
                border: Border.all(color: const Color(0xff2a2a30)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 2),
                    child: SizedBox(
                      key: const ValueKey('fixture-delete-warning-shield'),
                      width: 14,
                      height: 14,
                      child: Icon(
                        LucideIcons.shield_check,
                        size: 14,
                        color: c.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Transform.translate(
                      offset: Offset(0, -1),
                      child: Text(
                        'This note will be removed from your active workspace, but prior revisions remain safely recorded in local Git history.',
                        style: TextStyle(
                          fontFamily: burlPrototypeSansFontFamily,
                          fontFamilyFallback: burlPrototypeSansFallback,
                          fontSize: 11,
                          height: 1.625,
                          letterSpacing: -.33,
                          color: Color(0xffd4d4d4),
                          fontVariations: [FontVariation('wght', 400)],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 158,
            height: 51,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xff141416),
                border: Border(top: BorderSide(color: Color(0xff2a2a30))),
              ),
            ),
          ),
          Positioned(
            left: 219,
            top: 171,
            width: 62,
            height: 26,
            child: GestureDetector(
              key: const ValueKey('fixture-delete-cancel'),
              onTap: _closeOverlay,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _dark
                      ? const Color(0xff1e1e22)
                      : const Color(0xffffffff),
                  border: Border.all(
                    color: _dark
                        ? const Color(0xff2e2e35)
                        : const Color(0xffe4e1d8),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Transform.translate(
                  offset: const Offset(1, 0),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: burlPrototypeSansFontFamily,
                      fontFamilyFallback: burlPrototypeSansFallback,
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -.35,
                      color: _dark ? const Color(0xffd4d4d8) : c.textSecondary,
                      fontVariations: const [FontVariation('wght', 400)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 289,
            top: 172,
            width: 78,
            height: 24,
            child: GestureDetector(
              key: const ValueKey('fixture-delete-confirm'),
              onTap: _closeOverlay,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xffec003f),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      top: 5,
                      child: SizedBox(
                        key: const ValueKey('fixture-delete-trash-slot'),
                        width: 14,
                        height: 14,
                        child: const Icon(
                          LucideIcons.trash_2,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 31,
                      top: 4,
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: burlPrototypeSansFontFamily,
                          fontFamilyFallback: burlPrototypeSansFallback,
                          fontSize: 12,
                          height: 16 / 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -.15,
                          color: Colors.white,
                          fontVariations: [FontVariation('wght', 400)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _overlayHeader(
    BurlColors c,
    String title,
    IconData? icon, {
    String? subtitle,
    double? fixedHeight,
    Color? background,
  }) => Container(
    height: fixedHeight,
    padding: EdgeInsets.symmetric(
      horizontal: 20,
      vertical: fixedHeight == null ? 14 : 0,
    ),
    decoration: BoxDecoration(
      color: background ?? c.sidebar,
      border: Border(bottom: BorderSide(color: c.borderSubtle)),
    ),
    child: Row(
      children: [
        if (icon != null) Icon(icon, size: 16, color: c.accent),
        if (icon != null) const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) Text(subtitle, style: _monospace(c)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close $title',
          onPressed: _closeOverlay,
          icon: const Icon(LucideIcons.x, size: 16),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
        ),
      ],
    ),
  );
  Widget _overlayFooter(
    BurlColors c,
    Widget left,
    String action,
    String key, {
    bool label = false,
    (String, VoidCallback)? secondary,
    double? fixedHeight,
    Size? actionSize,
    Color? background,
    Color? borderColor,
    Color? actionBackground,
    Color? actionForeground,
    Offset contentOffset = Offset.zero,
  }) => Container(
    height: fixedHeight,
    padding: EdgeInsets.symmetric(
      horizontal: 20,
      vertical: fixedHeight == null ? 11 : 0,
    ),
    decoration: BoxDecoration(
      color: background ?? c.sidebar,
      border: Border(top: BorderSide(color: borderColor ?? c.borderSubtle)),
    ),
    child: Transform.translate(
      offset: contentOffset,
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(
              style: TextStyle(
                color: c.textMuted,
                fontSize: 11,
                fontFamily: burlPrototypeMonoFontFamily,
              ),
              child: left,
            ),
          ),
          if (secondary != null)
            OutlinedButton(onPressed: secondary.$2, child: Text(secondary.$1)),
          const SizedBox(width: 8),
          label
              ? GestureDetector(
                  key: ValueKey(key),
                  onTap: _closeOverlay,
                  child: Text(action, style: _monospace(c)),
                )
              : GestureDetector(
                  key: ValueKey(key),
                  onTap: _closeOverlay,
                  child: Container(
                    width: actionSize?.width,
                    height: actionSize?.height,
                    padding: actionSize == null
                        ? const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          )
                        : EdgeInsets.zero,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          actionBackground ??
                          (action == 'Delete'
                              ? const Color(0xffec003f)
                              : c.textPrimary),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      action,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontFamily: burlPrototypeSansFontFamily,
                        fontFamilyFallback: burlPrototypeSansFallback,
                        fontSize: 11,
                        height: 1,
                        color: actionForeground ?? c.editor,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    ),
  );
  TextStyle _shellCaption() => const TextStyle(
    fontFamily: burlPrototypeSansFontFamily,
    fontFamilyFallback: burlPrototypeSansFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .6,
    color: Color(0xffa1a1aa),
    fontVariations: [FontVariation('wght', 600)],
  );

  TextStyle _searchScopeStyle(BurlColors c) => TextStyle(
    fontFamily: burlPrototypeSansFontFamily,
    fontFamilyFallback: burlPrototypeSansFallback,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w400,
    color: c.textMuted,
    fontVariations: const [FontVariation('wght', 400)],
  );

  TextStyle _metadataMono() => const TextStyle(
    fontFamily: burlPrototypeMonoFontFamily,
    fontFamilyFallback: burlPrototypeMonoFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    color: Color(0xffa3a3a3),
    fontVariations: [FontVariation('wght', 400)],
  );

  TextStyle _caption(BurlColors c) => TextStyle(
    fontFamily: burlPrototypeSansFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
    color: c.textMuted,
    fontVariations: const [
      FontVariation('wght', 600),
      FontVariation('wdth', 100),
    ],
  );
  TextStyle _monospace(BurlColors c, {double height = 1}) => TextStyle(
    fontSize: 10.5,
    fontFamily: burlPrototypeMonoFontFamily,
    height: height,
    color: c.textMuted,
    fontVariations: const [FontVariation('wght', 400)],
  );
  BoxDecoration _box(BurlColors c, {bool selected = false}) => BoxDecoration(
    color: selected ? const Color(0xff222227) : const Color(0xff141417),
    border: Border.all(color: selected ? c.textSecondary : c.borderSubtle),
    borderRadius: BorderRadius.circular(6),
  );
}

enum _FixtureNote { focaccia, homelab, kyoto, recovered }

extension on _FixtureNote {
  String get title => switch (this) {
    _FixtureNote.focaccia => 'Sourdough Focaccia with Rosemary & Sea Salt',
    _FixtureNote.homelab => 'Homelab Architecture & Local Services',
    _FixtureNote.kyoto => 'Kyoto & Tokyo Autumn Itinerary 2026',
    _FixtureNote.recovered => 'Cold Brew Ratio & Immersion Guide',
  };
  String get shortLabel => switch (this) {
    _FixtureNote.focaccia => 'sourdough-focaccia.md',
    _FixtureNote.homelab => 'homelab-architecture.md',
    _FixtureNote.kyoto => 'kyoto-autumn-itinerary.md',
    _FixtureNote.recovered => 'cold-brew-ratio.md',
  };
  (String, String, String, String) get metadata => switch (this) {
    _FixtureNote.focaccia => (
      'Kitchen & Recipes',
      'sourdough-focaccia.md',
      '540 words',
      '5 mins ago',
    ),
    _FixtureNote.homelab => (
      'Technology & Setup',
      'homelab-architecture.md',
      '680 words',
      '3 hours ago',
    ),
    _FixtureNote.kyoto => (
      'Travel & Itineraries',
      'kyoto-autumn-itinerary.md',
      '720 words',
      'Yesterday',
    ),
    _FixtureNote.recovered => (
      'Kitchen & Recipes',
      'cold-brew-ratio.md',
      '260 words',
      'Unsaved draft recovered',
    ),
  };
}

class _FixtureDirectoryRow extends StatelessWidget {
  const _FixtureDirectoryRow(
    this.colors,
    this.label,
    this.count, {
    this.expanded = true,
    this.compact = false,
  });
  final BurlColors colors;
  final String label;
  final int count;
  final bool expanded;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('fixture-directory-row-$label'),
    padding: EdgeInsets.symmetric(
      vertical: compact ? 2 : 3,
      horizontal: compact ? 8 : 4,
    ),
    child: Row(
      children: [
        Icon(
          expanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
          size: 14,
          color: const Color(0xffa1a1aa),
        ),
        const SizedBox(width: 6),
        Icon(
          expanded ? LucideIcons.folder_open : LucideIcons.folder,
          size: 14,
          color: const Color(0xffa1a1aa),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: burlPrototypeSansFontFamily,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
              color: Color(0xffd4d4d4),
              fontVariations: [FontVariation('wght', 500)],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!compact)
          Text(
            '$count',
            key: ValueKey('fixture-directory-count-$label'),
            style: TextStyle(
              fontFamily: burlPrototypeMonoFontFamily,
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
      ],
    ),
  );
}

class _FixtureNoteRow extends StatelessWidget {
  const _FixtureNoteRow({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
    required this.colors,
    this.compact = false,
    this.onSecondaryTap,
  });
  final _FixtureNote note;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final BurlColors colors;
  final bool compact;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTap: onSecondaryTap,
    child: InkWell(
      onTap: onTap,
      child: Container(
        key: ValueKey('fixture-note-row-${note.name}'),
        padding: compact
            ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (compact ? const Color(0xff2a2a30) : colors.hover)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.file_text, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note.title,
                style: TextStyle(
                  fontFamily: burlPrototypeSansFontFamily,
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected
                      ? const Color(0xffe8e6df)
                      : const Color(0xffa3a3a3),
                  fontVariations: [
                    FontVariation('wght', selected ? 500 : 400),
                    const FontVariation('wdth', 100),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (note == _FixtureNote.recovered)
              Container(
                key: const ValueKey('fixture-recovered-badge'),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.review,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FixtureDirectoryLane extends StatelessWidget {
  const _FixtureDirectoryLane({
    required this.surfaceKey,
    required this.colors,
    required this.child,
    this.topInset = 0,
  });

  final Key surfaceKey;
  final BurlColors colors;
  final Widget child;
  final double topInset;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 12),
    child: DecoratedBox(
      key: surfaceKey,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xff27272b))),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: 10, top: topInset),
        child: child,
      ),
    ),
  );
}

class _FixtureFooterCard extends StatelessWidget {
  const _FixtureFooterCard({
    required this.surfaceKey,
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onTap,
    this.height = 32,
    this.review = false,
  });

  final Key surfaceKey;
  final IconData icon;
  final String label;
  final String trailing;
  final VoidCallback onTap;
  final double height;
  final bool review;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 239,
    height: height,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          key: surfaceKey,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: review ? const Color(0xff2a2318) : const Color(0xff1c1c20),
            border: Border.all(
              color: review ? const Color(0xff4a3d28) : const Color(0xff2e2e35),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: review
                    ? const Color(0xffe0c9a6)
                    : const Color(0xff86a789),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: review
                        ? burlPrototypeMonoFontFamily
                        : burlPrototypeSansFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xffd4d4d4),
                  ),
                ),
              ),
              Text(
                trailing,
                style: TextStyle(
                  fontFamily: burlPrototypeMonoFontFamily,
                  fontSize: review ? 11 : 10,
                  fontWeight: review ? FontWeight.w500 : FontWeight.w400,
                  color: review
                      ? const Color(0x99e0c9a6)
                      : const Color(0xff71717a),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FixtureSelectableTab extends StatelessWidget {
  const _FixtureSelectableTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.compact,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final BurlColors colors;
  final bool compact;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      key: ValueKey('fixture-tab-surface-$label'),
      width: switch (label) {
        'sourdough-focaccia.md' => 228,
        'homelab-architecture.md' => 227,
        _ => 240,
      },
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: selected && compact
            ? const Color(0xff151517)
            : selected
            ? colors.editor
            : Colors.transparent,
        border: Border(
          top: BorderSide(
            color: selected ? colors.accent : Colors.transparent,
            width: 2,
          ),
          right: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.file_text,
            size: 14,
            color: selected ? colors.accent : colors.textMuted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 15.333 / 11.5,
                fontFamily: burlPrototypeMonoFontFamily,
                fontFamilyFallback: burlPrototypeMonoFallback,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: -.2875,
                color: selected
                    ? const Color(0xffffffff)
                    : const Color(0xffa3a3a3),
                fontVariations: [FontVariation('wght', selected ? 500 : 400)],
              ),
            ),
          ),
          if (label == 'sourdough-focaccia.md')
            Container(
              key: const ValueKey('fixture-tab-dirty'),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.review,
                shape: BoxShape.circle,
              ),
            ),
          if (selected)
            IconButton(
              key: ValueKey('fixture-tab-close-$label'),
              tooltip: 'Close $label',
              onPressed: () {},
              icon: const Icon(LucideIcons.x, size: 13),
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    ),
  );
}

const _caddyYaml =
    '```yaml\n# Docker Compose: Core Reverse Proxy & DNS\nservices:\n  caddy-proxy:\n    image: caddy:2-alpine\n    container_name: caddy\n    restart: unless-stopped\n    ports:\n      - "80:80"\n      - "443:443"\n    volumes:\n      - ./Caddyfile:/etc/caddy/Caddyfile:ro\n      - /var/data/caddy/data:/data\n      - /var/data/caddy/config:/config\n    environment:\n      - CLOUDFLARE_API_TOKEN=\${CF_DNS_TOKEN}\n```';
const _syncStates = <String, (String, String, IconData)>{
  'localOnly': (
    'Local Only',
    'Local files on disk without remote origin.',
    LucideIcons.hard_drive,
  ),
  'connectedIdle': (
    'In Sync',
    'All notes match the remote Git repository.',
    LucideIcons.check,
  ),
  'syncing': (
    'Syncing',
    'Synchronizing with remote repository.',
    LucideIcons.refresh_cw,
  ),
  'offline': (
    'Offline',
    'Working locally; will sync when reconnected.',
    LucideIcons.wifi_off,
  ),
  'pendingSuggestions': (
    '1 Pending Suggestion',
    'Remote change ready for in-line block review.',
    LucideIcons.git_pull_request,
  ),
  'authRequired': (
    'Auth Required',
    'SSH key or token required.',
    LucideIcons.lock,
  ),
  'syncError': (
    'Unreachable',
    'Unable to connect to remote repository.',
    LucideIcons.circle_alert,
  ),
  'externalChanged': (
    'External Changes',
    'Files on disk updated externally.',
    LucideIcons.file_code,
  ),
};

class _VisualParityFixtureState extends State<VisualParityFixture> {
  var _story = 'note';
  var _resolved = false;
  var _copied = false;
  var _taskChecked = false;
  var _linkHovered = false;
  var _linkFocused = false;
  var _searchQuery = '';
  var _scope = 'All';
  var _deleted = false;
  var _recoveryDismissed = false;
  var _statusVariant = 'error';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<BurlColors>() ?? BurlColors.light;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: c.editor,
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final story in [
                  'note',
                  'raw',
                  'suggestion',
                  'search',
                  'delete',
                  'recovery',
                  'status',
                ])
                  TextButton(
                    key: ValueKey('fixture-story-$story'),
                    onPressed: () => setState(() => _story = story),
                    child: Text(story),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              switchInCurve: const Cubic(0.16, 1, .3, 1),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .98, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Padding(
                key: ValueKey('fixture-panel-$_story'),
                padding: const EdgeInsets.all(24),
                child: switch (_story) {
                  'note' => _note(c),
                  'raw' => _raw(c),
                  'suggestion' => _suggestion(c),
                  'search' => _search(c),
                  'delete' => _delete(c),
                  'recovery' => _recovery(c),
                  _ => _status(c),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(BurlColors c) => ListView(
    children: [
      Text(
        'Sourdough starter',
        style: TextStyle(
          fontSize: 24,
          height: 1.25,
          fontWeight: FontWeight.bold,
          color: c.textPrimary,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'A quiet record of flour, water, and time.',
        style: TextStyle(fontSize: 15, color: c.textPrimary),
      ),
      Container(
        key: const ValueKey('fixture-quote'),
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: c.accentSubtle,
          border: Border(left: BorderSide(color: c.accent, width: 2)),
        ),
        child: Text(
          'Feed what you want to keep.',
          style: TextStyle(fontStyle: FontStyle.italic, color: c.textSecondary),
        ),
      ),
      Row(
        children: [
          Checkbox(
            key: const ValueKey('fixture-task-toggle'),
            value: _taskChecked,
            onChanged: (value) => setState(() => _taskChecked = value ?? false),
          ),
          Text(
            'Refresh starter',
            key: ValueKey(
              'fixture-task-${_taskChecked ? 'checked' : 'unchecked'}',
            ),
          ),
        ],
      ),
      Table(
        key: const ValueKey('fixture-table'),
        border: TableBorder.all(color: c.borderSubtle),
        children: const [
          TableRow(
            children: [
              Padding(
                key: ValueKey('fixture-table-header-flour'),
                padding: EdgeInsets.all(4),
                child: Text('Flour'),
              ),
              Padding(
                key: ValueKey('fixture-table-header-water'),
                padding: EdgeInsets.all(4),
                child: Text('Water'),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                key: ValueKey('fixture-table-cell-flour'),
                padding: EdgeInsets.all(4),
                child: Text('100g'),
              ),
              Padding(
                key: ValueKey('fixture-table-cell-water'),
                padding: EdgeInsets.all(4),
                child: Text('100g'),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      FocusableActionDetector(
        key: const ValueKey('fixture-link-focus'),
        onShowFocusHighlight: (value) => setState(() => _linkFocused = value),
        onShowHoverHighlight: (value) => setState(() => _linkHovered = value),
        child: MouseRegion(
          onEnter: (_) => setState(() => _linkHovered = true),
          onExit: (_) => setState(() => _linkHovered = false),
          child: AnimatedContainer(
            key: const ValueKey('fixture-link-hover'),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _linkHovered || _linkFocused
                  ? c.accentSubtle
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: _linkFocused ? Border.all(color: c.accentBorder) : null,
            ),
            child: InkWell(
              key: const ValueKey('fixture-link-normal'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  key: ValueKey('fixture-link-popover'),
                  content: Text('Kitchen notes'),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.link_2, size: 13, color: c.accent),
                  const SizedBox(width: 4),
                  Text('Kitchen notes', style: TextStyle(color: c.accent)),
                ],
              ),
            ),
          ),
        ),
      ),
      Text(
        'Missing note',
        key: const ValueKey('fixture-link-missing'),
        style: TextStyle(
          color: c.syncError,
          decoration: TextDecoration.underline,
        ),
      ),
      Container(
        key: const ValueKey('fixture-code'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.borderSubtle),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: const ValueKey('fixture-code-header'),
              children: [
                Text(
                  'bash',
                  key: const ValueKey('fixture-code-language'),
                  style: TextStyle(
                    fontFamily: burlPrototypeMonoFontFamily,
                    color: c.textMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('fixture-code-copy'),
                  tooltip: _copied ? 'Code copied' : 'Copy code',
                  icon: Icon(
                    _copied ? LucideIcons.check : LucideIcons.copy,
                    size: 15,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: 'bake --slow'),
                    );
                    setState(() => _copied = true);
                  },
                ),
              ],
            ),
            Text(
              'bake --slow',
              key: ValueKey('fixture-code-${_copied ? 'copied' : 'source'}'),
              style: TextStyle(fontFamily: burlPrototypeMonoFontFamily),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _raw(BurlColors c) => Container(
    key: const ValueKey('fixture-raw-block'),
    color: c.focusedBlock,
    foregroundDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.accent, width: 3)),
    ),
    child: const Text('**Sourdough starter**'),
  );
  Widget _suggestion(BurlColors c) => _resolved
      ? Column(
          children: [
            Text(
              'Suggestion resolved',
              key: const ValueKey('fixture-suggestion-resolved'),
            ),
            TextButton(
              key: const ValueKey('fixture-suggestion-reset'),
              onPressed: () => setState(() => _resolved = false),
              child: const Text('Reset'),
            ),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Incoming edit', style: TextStyle(color: c.textSecondary)),
            Container(
              color: c.diffDeleteBackground,
              child: const Text('- Feed every day'),
            ),
            Container(
              color: c.diffAddBackground,
              child: const Text('+ Feed twice daily'),
            ),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('fixture-suggestion-accept'),
                  onPressed: () => setState(() => _resolved = true),
                  child: const Text('Accept'),
                ),
                TextButton(
                  key: const ValueKey('fixture-suggestion-keep-local'),
                  onPressed: () => setState(() => _resolved = true),
                  child: const Text('Keep local'),
                ),
              ],
            ),
          ],
        );
  Widget _search(BurlColors c) {
    final matches = _searchQuery == 'error'
        ? const <String>[]
        : ['Sourdough starter']
              .where(
                (note) =>
                    _searchQuery.isEmpty ||
                    note.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ValueKey('fixture-search-input'),
          autofocus: true,
          decoration: InputDecoration(hintText: 'Search notes'),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          children: [
            for (final s in ['All', 'Titles', 'Content'])
              ChoiceChip(
                key: ValueKey('fixture-search-scope-$s'),
                label: Text(s),
                selected: _scope == s,
                onSelected: (_) => setState(() => _scope = s),
              ),
          ],
        ),
        if (_searchQuery == 'error')
          TextButton(
            key: const ValueKey('fixture-search-retry'),
            onPressed: () => setState(() => _searchQuery = ''),
            child: const Text('Retry'),
          )
        else if (matches.isEmpty)
          const Text(
            'No matching notes',
            key: ValueKey('fixture-search-no-match'),
          )
        else
          ListTile(
            key: const ValueKey('fixture-search-result'),
            title: Text('Sourdough starter'),
            subtitle: Text('notes / kitchen'),
            trailing: Icon(LucideIcons.corner_down_left, size: 14),
          ),
        TextButton(
          key: const ValueKey('fixture-search-reset'),
          onPressed: () => setState(() => _searchQuery = ''),
          child: const Text('Reset'),
        ),
        Text(
          '↑↓ Navigate  ·  ↵ Open note',
          style: TextStyle(
            color: c.textMuted,
            fontFamily: burlPrototypeMonoFontFamily,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _delete(BurlColors c) => _deleted
      ? Column(
          children: [
            const Text('Deleted', key: ValueKey('fixture-delete-resolved')),
            TextButton(
              key: const ValueKey('fixture-delete-reset'),
              onPressed: () => setState(() => _deleted = false),
              child: const Text('Reset'),
            ),
          ],
        )
      : AlertDialog(
          key: const ValueKey('fixture-delete-dialog'),
          title: const Text('Delete note "Sourdough starter"?'),
          content: const Text(
            'Deleted content remains recoverable from local version history.',
          ),
          actions: [
            TextButton(
              key: const ValueKey('fixture-delete-cancel'),
              onPressed: () => setState(() => _deleted = true),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('fixture-delete-confirm'),
              onPressed: () => setState(() => _deleted = true),
              child: const Text('Delete'),
            ),
          ],
        );
  Widget _recovery(BurlColors c) => _recoveryDismissed
      ? TextButton(
          key: const ValueKey('fixture-recovery-reset'),
          onPressed: () => setState(() => _recoveryDismissed = false),
          child: const Text('Reset recovery'),
        )
      : ListTile(
          key: const ValueKey('fixture-recovery'),
          leading: Icon(LucideIcons.rotate_ccw_clock, color: c.review),
          title: const Text('Recovered drafts'),
          subtitle: const Text('Unsaved changes were recovered.'),
          onTap: () => setState(() => _recoveryDismissed = true),
          trailing: IconButton(
            key: const ValueKey('fixture-recovery-dismiss'),
            tooltip: 'Dismiss recovered drafts',
            icon: const Icon(LucideIcons.x),
            onPressed: () => setState(() => _recoveryDismissed = true),
          ),
        );
  Widget _status(BurlColors c) => Column(
    children: [
      Wrap(
        children: [
          for (final value in ['saving', 'saved', 'error', 'recovered'])
            TextButton(
              key: ValueKey('fixture-status-$value'),
              onPressed: () => setState(() => _statusVariant = value),
              child: Text(value),
            ),
        ],
      ),
      Container(
        key: ValueKey('fixture-status-$_statusVariant'),
        padding: const EdgeInsets.all(12),
        color: _statusVariant == 'error' ? c.reviewSubtle : c.accentSubtle,
        child: Text(
          _statusVariant == 'error'
              ? 'Your latest edit could not be saved yet.'
              : _statusVariant,
        ),
      ),
      TextButton(
        key: const ValueKey('fixture-status-reset'),
        onPressed: () => setState(() => _statusVariant = 'error'),
        child: const Text('Reset'),
      ),
    ],
  );
}
