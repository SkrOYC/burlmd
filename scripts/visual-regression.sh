#!/usr/bin/env bash
#
# Captures a release Linux shell through smoke-shot and checks it against a
# PNG baseline by exact RGB pixel count.

set -euo pipefail

usage() {
  echo "usage: $0 <name> --baseline <png> --max-different-pixels <n>" >&2
  exit 64
}

[[ $# -eq 5 ]] || usage
NAME="$1"
shift
[[ "$1" == "--baseline" ]] || usage
BASELINE="$2"
shift 2
[[ "$1" == "--max-different-pixels" ]] || usage
MAX_DIFFERENT_PIXELS="$2"

[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "visual-regression: invalid name '$NAME'" >&2
  exit 64
}
[[ "$MAX_DIFFERENT_PIXELS" =~ ^[0-9]+$ ]] || {
  echo "visual-regression: max different pixels must be a non-negative integer" >&2
  exit 64
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep the capture location compatible with smoke-shot. Callers can place the
# inspection copy outside the repository with either environment variable.
CAPTURE_DIR="${BURLMD_VISUAL_REGRESSION_DIR:-${BURLMD_SMOKE_SHOT_DIR:-$REPO_ROOT/.qa}}"
SHOT="$CAPTURE_DIR/$NAME.png"

mkdir -p "$CAPTURE_DIR"
CAPTURE_PPM="$(mktemp "$CAPTURE_DIR/.visual-regression-${NAME}.capture.XXXXXX.ppm")"
BASELINE_PPM="$(mktemp "$CAPTURE_DIR/.visual-regression-${NAME}.baseline.XXXXXX.ppm")"
WINDOW_SHOT="$(mktemp "$CAPTURE_DIR/.visual-regression-${NAME}.window.XXXXXX.png")"
SMOKE_PID=""

cleanup() {
  if [[ -n "$SMOKE_PID" ]] && kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
  fi
  rm -f "$CAPTURE_PPM" "$BASELINE_PPM" "$WINDOW_SHOT"
}
trap cleanup EXIT

# Byte offset of the first pixel byte in a binary PPM (P6) file. This matches
# smoke-shot's pixel-diff parsing so both visual gates use the same raw format.
ppm_pixel_offset() {
  head -c 64 "$1" | awk 'BEGIN { RS = "\n" } NR < 4 { off += length($0) + 1 }
    NR == 3 { print off + 0; exit }'
}

# Counts changed RGB triples rather than changed bytes, so the reported value
# is a pixel count. The conversion output is always 8-bit P6 with no comments.
count_diff_pixels() {
  local off_a off_b
  off_a="$(ppm_pixel_offset "$1")"
  off_b="$(ppm_pixel_offset "$2")"
  [[ -n "$off_a" && -n "$off_b" && "$off_a" -gt 0 && "$off_a" -eq "$off_b" ]] || return 0
  paste -d ' ' \
    <(od -An -v -tu1 -w3 -j "$off_a" "$1") \
    <(od -An -v -tu1 -w3 -j "$off_b" "$2") \
    | awk 'NF == 6 { if ($1 != $4 || $2 != $5 || $3 != $6) changed++ }
      END { print changed + 0 }'
}

# grim writes PNGs, while smoke-shot's comparison helper operates on raw PPM.
# Decode the 8-bit non-interlaced PNG formats grim produces without depending
# on an image-conversion package outside the reproducible developer shell.
png_to_ppm() {
  dart /dev/stdin "$1" "$2" <<'DART'
import 'dart:io';
import 'dart:typed_data';

void fail(String message) => throw FormatException('visual-regression: $message');

int paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

void main(List<String> arguments) {
  if (arguments.length != 2) fail('PNG decoder expected input and output paths');
  final input = Uint8List.fromList(File(arguments[0]).readAsBytesSync());
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (input.length < signature.length ||
      !Iterable<int>.generate(signature.length).every((i) => input[i] == signature[i])) {
    fail('not a PNG: ${arguments[0]}');
  }

  var offset = signature.length;
  var width = 0;
  var height = 0;
  var bitDepth = 0;
  var colorType = -1;
  final idat = BytesBuilder(copy: false);
  while (offset + 12 <= input.length) {
    final chunkLength = ByteData.sublistView(input, offset, offset + 4).getUint32(0);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + chunkLength;
    if (chunkEnd + 4 > input.length) fail('truncated PNG chunk');
    final type = String.fromCharCodes(input.sublist(offset + 4, offset + 8));
    final data = input.sublist(chunkStart, chunkEnd);
    if (type == 'IHDR') {
      if (data.length != 13) fail('invalid IHDR');
      final header = ByteData.sublistView(data);
      width = header.getUint32(0);
      height = header.getUint32(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[10] != 0 || data[11] != 0 || data[12] != 0) {
        fail('only non-interlaced, standard-deflate PNGs are supported');
      }
    } else if (type == 'IDAT') {
      idat.add(data);
    } else if (type == 'IEND') {
      break;
    }
    offset = chunkEnd + 4;
  }

  final bytesPerPixel = switch (colorType) {
    0 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => throw FormatException('visual-regression: unsupported PNG color type $colorType'),
  };
  if (width <= 0 || height <= 0 || bitDepth != 8) {
    fail('only non-empty 8-bit PNGs are supported');
  }
  final stride = width * bytesPerPixel;
  final compressed = idat.takeBytes();
  final filtered = Uint8List.fromList(ZLibDecoder().convert(compressed));
  if (filtered.length != height * (stride + 1)) fail('unexpected decompressed PNG length');

  final pixels = Uint8List(height * stride);
  var source = 0;
  for (var row = 0; row < height; row++) {
    final filter = filtered[source++];
    final rowOffset = row * stride;
    for (var column = 0; column < stride; column++) {
      final value = filtered[source++];
      final left = column >= bytesPerPixel ? pixels[rowOffset + column - bytesPerPixel] : 0;
      final above = row == 0 ? 0 : pixels[rowOffset - stride + column];
      final upperLeft = row == 0 || column < bytesPerPixel
          ? 0
          : pixels[rowOffset - stride + column - bytesPerPixel];
      pixels[rowOffset + column] = switch (filter) {
        0 => value,
        1 => (value + left) & 0xff,
        2 => (value + above) & 0xff,
        3 => (value + ((left + above) >> 1)) & 0xff,
        4 => (value + paeth(left, above, upperLeft)) & 0xff,
        _ => throw FormatException('visual-regression: unsupported PNG filter $filter'),
      };
    }
  }

  final ppm = BytesBuilder(copy: false)
    ..add('P6\n$width $height\n255\n'.codeUnits);
  for (var pixel = 0; pixel < width * height; pixel++) {
    final offset = pixel * bytesPerPixel;
    switch (colorType) {
      case 0:
        final gray = pixels[offset];
        ppm.add(<int>[gray, gray, gray]);
      case 2 || 6:
        ppm.add(pixels.sublist(offset, offset + 3));
      case 4:
        final gray = pixels[offset];
        ppm.add(<int>[gray, gray, gray]);
    }
  }
  File(arguments[1]).writeAsBytesSync(ppm.takeBytes());
}
DART
}

# Hyprland exposes the client rectangle, including its host-owned titlebar.
# Capturing that rectangle excludes unrelated desktop-panel pixels (such as a
# clock) while retaining the complete host window chrome under test. When the
# compositor cannot expose a client rectangle, retain smoke-shot's full-screen
# capture as a compatible fallback.
window_geometry() {
  local clients
  clients="$(hyprctl clients -j)" || return 1
  CLIENTS="$clients" dart /dev/stdin <<'DART'
import 'dart:convert';
import 'dart:io';

void main() {
  final clients = jsonDecode(Platform.environment['CLIENTS']!) as List<dynamic>;
  for (final candidate in clients) {
    final client = candidate as Map<String, dynamic>;
    if (client['class'] != 'com.burlmd.burlmd' && client['title'] != 'burlmd') {
      continue;
    }
    final at = client['at'] as List<dynamic>;
    final size = client['size'] as List<dynamic>;
    if (at.length == 2 && size.length == 2 &&
        at.every((value) => value is num) && size.every((value) => value is num)) {
      print('${at[0]},${at[1]} ${size[0]}x${size[1]}');
      return;
    }
  }
  exitCode = 1;
}
DART
}

cd "$REPO_ROOT"
BURLMD_SMOKE_SHOT_DIR="$CAPTURE_DIR" "$REPO_ROOT/scripts/smoke-shot.sh" "$NAME" &
SMOKE_PID=$!
WINDOW_CAPTURED=0
if command -v hyprctl >/dev/null 2>&1; then
  CAPTURE_DEADLINE=$(( $(date +%s) + 60 ))
  while kill -0 "$SMOKE_PID" 2>/dev/null; do
    if GEOMETRY="$(window_geometry 2>/dev/null)"; then
      # Let the visible shell finish its initial provider-driven mount, but
      # capture before smoke-shot terminates the isolated release process.
      sleep 2
      GEOMETRY="$(window_geometry 2>/dev/null)" || break
      if grim -g "$GEOMETRY" "$WINDOW_SHOT"; then
        WINDOW_CAPTURED=1
      else
        echo "visual-regression: grim could not capture client geometry $GEOMETRY" >&2
        exit 1
      fi
      break
    fi
    (( $(date +%s) < CAPTURE_DEADLINE )) || break
    sleep .2
  done
fi
if ! wait "$SMOKE_PID"; then
  exit 1
fi
SMOKE_PID=""
[[ -s "$SHOT" ]] || {
  echo "visual-regression: smoke-shot did not write $SHOT" >&2
  exit 1
}
if (( WINDOW_CAPTURED )); then
  cp "$WINDOW_SHOT" "$SHOT"
fi

if [[ ! -f "$BASELINE" ]]; then
  mkdir -p "$(dirname "$BASELINE")"
  cp "$SHOT" "$BASELINE"
  echo "[visual-regression] baseline established: $BASELINE"
  echo "[visual-regression] capture: $SHOT"
  echo "[visual-regression] different pixels: 0 (new baseline)"
  exit 0
fi

png_to_ppm "$SHOT" "$CAPTURE_PPM"
png_to_ppm "$BASELINE" "$BASELINE_PPM"
DIFFERENT_PIXELS="$(count_diff_pixels "$CAPTURE_PPM" "$BASELINE_PPM")"
[[ -n "$DIFFERENT_PIXELS" ]] || {
  echo "visual-regression: could not compare $SHOT and $BASELINE" >&2
  exit 1
}

echo "[visual-regression] capture: $SHOT"
echo "[visual-regression] baseline: $BASELINE"
echo "[visual-regression] different pixels: $DIFFERENT_PIXELS (maximum: $MAX_DIFFERENT_PIXELS)"

if (( DIFFERENT_PIXELS > MAX_DIFFERENT_PIXELS )); then
  exit 1
fi
