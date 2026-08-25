import 'package:flutter_test/flutter_test.dart';

import '../test_driver/visual_capture_driver.dart' as protocol;

void main() {
  group('normal-app visual capture protocol', () {
    test('maps all 22 reference-manifest surfaces in order', () {
      expect(protocol.visualCaptureSpecs, hasLength(22));
      expect(
        protocol.visualCaptureSpecs.map((spec) => spec.name),
        orderedEquals(<String>[
          'reference-wide-dark-shell',
          'reference-note-rendered',
          'reference-wide-light-shell',
          'reference-search-results',
          'reference-preferences-dark',
          'reference-sync-local-only',
          'reference-sync-connected-idle',
          'reference-sync-syncing',
          'reference-sync-offline',
          'reference-sync-pending-suggestions',
          'reference-sync-auth-required',
          'reference-sync-sync-error',
          'reference-sync-external-changed',
          'reference-history',
          'reference-delete-confirmation',
          'reference-note-raw',
          'reference-suggestion',
          'reference-code-rendered',
          'reference-code-raw',
          'reference-link-hover',
          'reference-recovery-badge-note',
          'reference-narrow-dark-shell',
        ]),
      );
      expect(
        protocol.visualCaptureSpecs.last.viewport,
        const protocol.VisualCaptureViewport(480, 820),
      );
      expect(
        protocol.visualCaptureSpecs
            .take(protocol.visualCaptureSpecs.length - 1)
            .every(
              (spec) =>
                  spec.viewport ==
                  const protocol.VisualCaptureViewport(1440, 900),
            ),
        isTrue,
      );
    });

    test('keeps the search capture on the prototype two-match state', () {
      final search = protocol.visualCaptureSpecs.firstWhere(
        (spec) => spec.name == 'reference-search-results',
      );

      expect(search.expectedVisibleText, ['sourdough', '2 matches']);
      expect(search.expectedState['searchQuery'], 'sourdough');
      expect(search.expectedState['searchScope'], 'All');
    });

    test('ready JSON distinguishes resize and capture presentation state', () {
      final viewport = const protocol.VisualCaptureViewport(1440, 900);
      final resize = protocol.visualCaptureReadyJson(
        phase: 'resize-ready',
        captureName: 'bootstrap',
        viewport: viewport,
        sequence: 0,
        visibleMarker: 'fixture-focaccia-h1',
        expectedVisibleText: const ['Sourdough Focaccia'],
        markerVisible: true,
        appFramePresented: false,
        viewSizePresented: false,
      );
      final capture = protocol.visualCaptureReadyJson(
        phase: 'capture-ready',
        captureName: 'reference-wide-dark-shell',
        viewport: viewport,
        sequence: 1,
        visibleMarker: 'fixture-focaccia-h1',
        expectedVisibleText: const ['Sourdough Focaccia'],
        markerVisible: true,
        appFramePresented: true,
        viewSizePresented: true,
      );

      expect(resize['sequence'], 0);
      expect(resize['appFramePresented'], isFalse);
      expect(resize['viewSizePresented'], isFalse);
      expect(capture['sequence'], 1);
      expect(capture['appFramePresented'], isTrue);
      expect(capture['viewSizePresented'], isTrue);
      expect(capture['expectedVisibleText'], ['Sourdough Focaccia']);
    });

    test(
      'acknowledgements match every identity field and reject stale data',
      () {
        const viewport = protocol.VisualCaptureViewport(480, 820);
        final acknowledgement = <String, Object?>{
          'phase': 'capture-ack',
          'captureName': 'reference-narrow-dark-shell',
          'width': 480,
          'height': 820,
          'sequence': 22,
        };

        expect(
          protocol.visualCaptureAckMatches(
            acknowledgement,
            phase: 'capture-ack',
            captureName: 'reference-narrow-dark-shell',
            viewport: viewport,
            sequence: 22,
          ),
          isTrue,
        );
        for (final stale in <Map<String, Object?>>[
          {...acknowledgement, 'phase': 'resize-ack'},
          {...acknowledgement, 'captureName': 'reference-wide-dark-shell'},
          {...acknowledgement, 'width': 1440},
          {...acknowledgement, 'height': 900},
          {...acknowledgement, 'sequence': 21},
        ]) {
          expect(
            protocol.visualCaptureAckMatches(
              stale,
              phase: 'capture-ack',
              captureName: 'reference-narrow-dark-shell',
              viewport: viewport,
              sequence: 22,
            ),
            isFalse,
          );
        }
      },
    );

    test('geometry telemetry requires stable anchored controller evidence', () {
      final suggestion = protocol.visualCaptureSpecs.firstWhere(
        (spec) => spec.name == 'reference-suggestion',
      );
      final response = _geometryResponse(
        anchorId: 'suggestion',
        targetTop: 450,
      );

      expect(
        protocol.visualCaptureGeometryFailure(suggestion, response),
        isNull,
      );
      final unstable = <String, Object?>{
        ...response,
        'captureGeometry': <String, Object?>{
          ...(response['captureGeometry'] as Map<String, Object?>),
          'consecutiveStableFrames': 2,
        },
      };
      expect(
        protocol.visualCaptureGeometryFailure(suggestion, unstable),
        contains('consecutiveStableFrames'),
      );
    });

    test('link geometry rejects an out-of-tolerance popover or scroll', () {
      final link = protocol.visualCaptureSpecs.firstWhere(
        (spec) => spec.name == 'reference-link-hover',
      );
      final response = _geometryResponse(
        anchorId: 'link-hover',
        targetTop: 797,
        popoverTop: 823,
      );
      expect(protocol.visualCaptureGeometryFailure(link, response), isNull);

      final badPopover = <String, Object?>{
        ...response,
        'captureGeometry': <String, Object?>{
          ...(response['captureGeometry'] as Map<String, Object?>),
          'popoverRect': _rect(826),
        },
      };
      expect(
        protocol.visualCaptureGeometryFailure(link, badPopover),
        contains('popoverRect.top'),
      );
      final badScroll = <String, Object?>{
        ...response,
        'documentScroll': <String, Object?>{
          'offset': 1002.0,
          'min': 0.0,
          'max': 1000.0,
        },
      };
      expect(
        protocol.visualCaptureGeometryFailure(link, badScroll),
        contains('outside'),
      );
    });
  });
}

Map<String, Object?> _geometryResponse({
  required String anchorId,
  required double targetTop,
  double? popoverTop,
}) {
  final targetRect = _rect(targetTop);
  final scroll = <String, Object?>{'offset': 400.0, 'min': 0.0, 'max': 1000.0};
  return <String, Object?>{
    'targetRect': targetRect,
    'documentScroll': scroll,
    'positionGeneration': 4,
    'captureGeometry': <String, Object?>{
      'anchorId': anchorId,
      'targetRect': targetRect,
      'popoverRect': popoverTop == null ? null : _rect(popoverTop),
      'inTolerance': true,
      'scroll': scroll,
      'consecutiveStableFrames': 3,
    },
  };
}

Map<String, Object?> _rect(double top) => <String, Object?>{
  'left': 100.0,
  'top': top,
  'width': 200.0,
  'height': 50.0,
};
