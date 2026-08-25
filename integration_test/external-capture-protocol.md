# External capture protocol

Use this protocol when you run the normal-app Linux fixture driver. The driver
pauses at bootstrap and before every named reference capture. Each sequence
first requests a resize, including consecutive 1440x900 surfaces: this
reasserts the compositor geometry instead of assuming it persisted from the
previous image. After Flutter reports the requested shell size and presents
that surface, the driver requests the capture.

The capture worker focuses, floats, and resizes the Linux client with
`hyprctl`, verifies that `floating: true`, captures the window with `grim`, and
writes an acknowledgement.

## Files

The driver writes the ready JSON file to
`/tmp/burlmd-proof/burlmd-capture-ready.json`. It writes a temporary file and
renames it to this path, so readers don't consume a partial JSON file.

The capture worker writes the acknowledgement JSON file to
`/tmp/burlmd-proof/burlmd-capture-ack.json`. The driver polls this file for up
to 90 seconds. It accepts only an acknowledgement whose phase, capture name,
sequence, width, and height match the ready file.

## Ready phases

The driver publishes one sequence for each capture. It first publishes
`resize-ready` and waits for a matching `resize-ack`. It then polls the
normal-app `FixtureCaptureController` through `FlutterDriver.requestData`
until `shellSize` exactly matches the requested dimensions, waits at least two
presentation intervals, and sends `settle` again. Before both resize-ready and
capture-ready it requires controller telemetry (`targetRect`,
`documentScroll`, `positionGeneration`, and `captureGeometry`) to be finite,
in bounds, and stable across three consecutive responses. Anchored surfaces
also require exact geometry within ±1px: suggestion 450, rendered code 290,
raw code 434, link anchor 797, and link popover 823. Only then does it publish
`capture-ready`; the worker captures only after it receives that phase.

This target deliberately uses neither `testWidgets` nor an
`IntegrationTestWidgetsFlutterBinding`; it is the normal Flutter application
at `lib/visual_capture_main.dart` with the Flutter Driver extension enabled.

The target mounts a test-only deterministic English prototype fixture, not
production `MyApp`. Its literal fixture and sample strings are authoritative
reference data, so they intentionally don't follow the system locale. The
production Linux driver covers localized `MyApp` separately.

The ready file contains the following fields:

```json
{
  "phase": "capture-ready",
  "captureName": "reference-wide-dark-shell",
  "width": 1440,
  "height": 900,
  "sequence": 1,
  "visibleAssertionMarker": "fixture-reference-shell",
  "expectedVisibleText": ["Sourdough Focaccia"],
  "markerVisible": true,
  "appFramePresented": true,
  "viewSizePresented": true
}
```

`captureName` identifies the manifest state. `width` and `height` specify the
normal-app shell viewport in pixels. `sequence` increases for each handshake.
`visibleAssertionMarker` names the Flutter key asserted before the ready file
is written. `markerVisible` confirms that assertion. `appFramePresented`
confirms that the driver settled the widget tree, waited for the compositor,
and pumped the presented frame before it wrote the ready file. Reject a ready
file that doesn't contain both fields set to `true`. `viewSizePresented` is
also `true` only for `capture-ready`.

`expectedVisibleText` is a state-specific OCR gate. Before acknowledging a
capture, the worker must verify every listed string in the client image.

For `resize-ready`, the same fields identify the target view, but `phase` is
`resize-ready`, `appFramePresented` is `false`, and `viewSizePresented` is
`false`. Resize the floating client to the requested dimensions before you
write the acknowledgement. The narrow capture requests `480x820`; the other
21 named captures request `1440x900`.

At startup, the driver sends the same full resize and capture handshake with
`captureName` set to `bootstrap` and `sequence` set to `0`. The 22 manifest
captures then use sequences `1` through `22`, in reference-manifest order.

For the normal-app Linux capture target, run:

```sh
flutter drive --target=lib/visual_capture_main.dart --driver=test_driver/visual_capture_driver.dart -d linux
```

The ready and acknowledgement directory defaults to `/tmp/burlmd-proof`. For
an acknowledgement-only protocol validation that must not touch a capture
artifact set, set `BURLMD_CAPTURE_PROOF_DIRECTORY` to an empty, separate
directory for both the host driver and its worker.

## Acknowledgement JSON

For a resize, write this JSON after you resize and verify the floating client:

```json
{
  "phase": "resize-ack",
  "captureName": "reference-narrow-dark-shell",
  "width": 480,
  "height": 820,
  "sequence": 22
}
```

After saving the image, write this JSON to the acknowledgement path:

```json
{
  "phase": "capture-ack",
  "captureName": "reference-wide-dark-shell",
  "width": 1440,
  "height": 900,
  "sequence": 1
}
```

Use the exact phase, `captureName`, width, height, and `sequence` from the
ready file. The driver removes a stale acknowledgement before every ready
write and accepts only a complete JSON acknowledgement with all five identity
fields matching; stale or partial data never advances the driver.
