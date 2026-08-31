#!/usr/bin/env bash
#
# Captures a release Linux shell through smoke-shot and checks it against a
# PNG baseline by exact RGB pixel count.

set -euo pipefail

usage() {
  echo "usage: $0 <name> --baseline <png> --max-different-pixels <n> [--write-baseline]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage
NAME="$1"
shift
BASELINE=""
MAX_DIFFERENT_PIXELS=""
WRITE_BASELINE=0
CANONICAL_WIDTH=1878
CANONICAL_HEIGHT=989
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline)
      [[ $# -ge 2 && -z "$BASELINE" ]] || usage
      BASELINE="$2"
      shift 2
      ;;
    --max-different-pixels)
      [[ $# -ge 2 && -z "$MAX_DIFFERENT_PIXELS" ]] || usage
      MAX_DIFFERENT_PIXELS="$2"
      shift 2
      ;;
    --write-baseline)
      [[ "$WRITE_BASELINE" -eq 0 ]] || usage
      WRITE_BASELINE=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "visual-regression: invalid name '$NAME'" >&2
  exit 64
}
[[ -n "$BASELINE" ]] || usage
[[ "$MAX_DIFFERENT_PIXELS" =~ ^[0-9]+$ ]] || {
  echo "visual-regression: max different pixels must be a non-negative integer" >&2
  exit 64
}
if [[ ! -f "$BASELINE" && "$WRITE_BASELINE" -eq 0 ]]; then
  echo "visual-regression: baseline does not exist: $BASELINE (use --write-baseline to create it)" >&2
  exit 1
fi
if [[ -d "$BASELINE" ]]; then
  echo "visual-regression: baseline must be a file: $BASELINE" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep the capture location compatible with smoke-shot. Callers can place the
# inspection copy outside the repository with either environment variable.
CAPTURE_DIR="${BURLMD_VISUAL_REGRESSION_DIR:-${BURLMD_SMOKE_SHOT_DIR:-$REPO_ROOT/.qa}}"
SHOT="$CAPTURE_DIR/$NAME.png"

mkdir -p "$CAPTURE_DIR"
CAPTURE_PPM="$(mktemp "$CAPTURE_DIR/.visual-regression-${NAME}.capture.XXXXXX.ppm")"
BASELINE_PPM="$(mktemp "$CAPTURE_DIR/.visual-regression-${NAME}.baseline.XXXXXX.ppm")"
APP_PID_FILE=""
APP_PID_FD=""
VISUAL_RUNTIME_DIR=""
VISUAL_SWAY_CONFIG=""
VISUAL_SWAY_LOG=""
VISUAL_SWAY_SOCKET=""
VISUAL_WAYLAND_DISPLAY=""
COMPOSITOR_PID=""
SMOKE_PID=""

cleanup() {
  if [[ -n "$SMOKE_PID" ]] && kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
  fi
  if [[ -n "$COMPOSITOR_PID" ]] && kill -0 "$COMPOSITOR_PID" 2>/dev/null; then
    kill "$COMPOSITOR_PID" 2>/dev/null || true
    wait "$COMPOSITOR_PID" 2>/dev/null || true
  fi
  if [[ -n "$APP_PID_FD" ]]; then
    exec {APP_PID_FD}>&- || true
  fi
  rm -f "$CAPTURE_PPM" "$BASELINE_PPM"
  if [[ -n "$VISUAL_RUNTIME_DIR" && -d "$VISUAL_RUNTIME_DIR" && "$VISUAL_RUNTIME_DIR" == /tmp/burlmd-visual-wayland.* ]]; then
    rm -rf -- "$VISUAL_RUNTIME_DIR"
  fi
}
trap cleanup EXIT

# Prints width, height, pixel-byte offset, and raw payload length for an
# 8-bit binary PPM (P6). The PNG decoder below writes this exact header form.
ppm_metadata() {
  local file="$1"
  local -a header
  local width height pixel_offset file_size payload_length expected_length

  [[ -r "$file" ]] || {
    echo "visual-regression: cannot read PPM: $file" >&2
    return 1
  }
  mapfile -t header < <(LC_ALL=C head -n 3 "$file")
  [[ "${#header[@]}" -eq 3 && "${header[0]}" == "P6" ]] || {
    echo "visual-regression: invalid PPM header: $file" >&2
    return 1
  }
  [[ "${header[1]}" =~ ^([1-9][0-9]*)[[:space:]]+([1-9][0-9]*)$ && "${header[2]}" == "255" ]] || {
    echo "visual-regression: expected an 8-bit P6 PPM: $file" >&2
    return 1
  }
  width="${BASH_REMATCH[1]}"
  height="${BASH_REMATCH[2]}"
  pixel_offset="$(LC_ALL=C awk 'NR <= 3 { offset += length($0) + 1 }
    NR == 3 { print offset; exit }' "$file")"
  file_size="$(wc -c < "$file")"
  file_size="${file_size//[[:space:]]/}"
  [[ "$pixel_offset" =~ ^[1-9][0-9]*$ && "$file_size" =~ ^[0-9]+$ ]] || {
    echo "visual-regression: could not read PPM size: $file" >&2
    return 1
  }
  (( file_size >= pixel_offset )) || {
    echo "visual-regression: PPM ends before its pixel data: $file" >&2
    return 1
  }
  payload_length=$(( file_size - pixel_offset ))
  expected_length=$(( 10#$width * 10#$height * 3 ))
  (( payload_length == expected_length )) || {
    echo "visual-regression: invalid PPM payload length for $file: $payload_length (expected $expected_length)" >&2
    return 1
  }
  printf '%s %s %s %s\n' "$width" "$height" "$pixel_offset" "$payload_length"
}

# Counts changed RGB triples rather than changed bytes, so the reported value
# is a pixel count. Reject different dimensions or payload lengths before
# comparing so a truncated prefix cannot be reported as an exact match.
count_diff_pixels() {
  local metadata_a metadata_b
  local width_a height_a off_a payload_a width_b height_b off_b payload_b

  metadata_a="$(ppm_metadata "$1")" || return 1
  metadata_b="$(ppm_metadata "$2")" || return 1
  read -r width_a height_a off_a payload_a <<< "$metadata_a"
  read -r width_b height_b off_b payload_b <<< "$metadata_b"
  if [[ "$width_a" != "$width_b" || "$height_a" != "$height_b" ]]; then
    echo "visual-regression: PPM dimensions differ: ${width_a}x${height_a} and ${width_b}x${height_b}" >&2
    return 1
  fi
  if [[ "$payload_a" != "$payload_b" ]]; then
    echo "visual-regression: PPM payload lengths differ: $payload_a and $payload_b" >&2
    return 1
  fi

  paste -d ' ' \
    <(od -An -v -tu1 -w3 -j "$off_a" "$1") \
    <(od -An -v -tu1 -w3 -j "$off_b" "$2") \
    | awk 'NF == 6 { if ($1 != $4 || $2 != $5 || $3 != $6) changed++ }
      END { print changed + 0 }'
}

# Reports the exact number of pixels that remain in the product comparison.
# Keep this predicate in lockstep with isPlatformOwnedPixel in png_to_ppm.
compared_pixel_count() {
  local metadata width height _
  local rounded_corner_radius="$2"
  local titlebar_height="$3"

  metadata="$(ppm_metadata "$1")" || return 1
  read -r width height _ _ <<< "$metadata"
  awk -v width="$width" -v height="$height" -v radius="$rounded_corner_radius" \
    -v titlebar="$titlebar_height" '
      BEGIN {
        for (y = 0; y < height; y++) {
          for (x = 0; x < width; x++) {
            if (y < titlebar) continue
            nearLeft = x < radius
            nearRight = x >= width - radius
            nearTop = y < radius
            nearBottom = y >= height - radius
            if ((nearLeft || nearRight) && (nearTop || nearBottom)) {
              dx = nearLeft ? x - radius : x + 1 - width + radius
              dy = nearTop ? y - radius : y + 1 - height + radius
              if (dx * dx + dy * dy > radius * radius) continue
            }
            compared++
          }
        }
        print compared + 0
      }'
}

# grim writes PNGs, while smoke-shot's comparison helper operates on raw PPM.
# Decode the 8-bit non-interlaced PNG formats grim produces without depending
# on an image-conversion package outside the reproducible developer shell.
png_to_ppm() {
  dart /dev/stdin "$1" "$2" "${3:-0}" "${4:-0}" <<'DART'
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

// Ignores pixels whose square area intersects the compositor-only part of a
// rounded corner. Masking partially external edge pixels prevents compositor
// background colours from entering the product comparison through anti-aliasing.
bool isOutsideRoundedWindow(int x, int y, int width, int height, int radius) {
  if (radius == 0) return false;
  final nearLeft = x < radius;
  final nearRight = x >= width - radius;
  final nearTop = y < radius;
  final nearBottom = y >= height - radius;
  if (!(nearLeft || nearRight) || !(nearTop || nearBottom)) return false;

  // x and y are the outward-most corner of this pixel's square.
  final dx = (nearLeft ? x - radius : x + 1 - width + radius).toDouble();
  final dy = (nearTop ? y - radius : y + 1 - height + radius).toDouble();
  return dx * dx + dy * dy > radius * radius;
}

bool isPlatformOwnedPixel(
  int x,
  int y,
  int width,
  int height,
  int roundedCornerRadius,
  int titlebarHeight,
) =>
    y < titlebarHeight ||
    isOutsideRoundedWindow(x, y, width, height, roundedCornerRadius);

void main(List<String> arguments) {
  if (arguments.length < 2 || arguments.length > 4) {
    fail('PNG decoder expected input, output, optional rounded-corner radius, and optional titlebar height');
  }
  final parsedRoundedCornerRadius = arguments.length >= 3 ? int.tryParse(arguments[2]) : 0;
  final parsedTitlebarHeight = arguments.length == 4 ? int.tryParse(arguments[3]) : 0;
  if (parsedRoundedCornerRadius == null || parsedRoundedCornerRadius < 0) {
    fail('rounded-corner radius must be a non-negative integer');
  }
  if (parsedTitlebarHeight == null || parsedTitlebarHeight < 0) {
    fail('titlebar height must be a non-negative integer');
  }
  final roundedCornerRadius = parsedRoundedCornerRadius!;
  final titlebarHeight = parsedTitlebarHeight!;
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
  if (roundedCornerRadius * 2 > width || roundedCornerRadius * 2 > height) {
    fail('rounded-corner radius exceeds PNG dimensions');
  }
  if (titlebarHeight > height) {
    fail('titlebar height exceeds PNG dimensions');
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
    final x = pixel % width;
    final y = pixel ~/ width;
    if (isPlatformOwnedPixel(
      x,
      y,
      width,
      height,
      roundedCornerRadius,
      titlebarHeight,
    )) {
      ppm.add(<int>[0, 0, 0]);
      continue;
    }
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

# A private Sway compositor is the executable visual-gate display. Its fixed
# headless output has no desktop panels, other clients, or ambient input. The
# only accepted captured client is the exact app PID smoke-shot launched.
sway_client_geometry() {
  local app_pid="$1"
  local tree
  tree="$(XDG_RUNTIME_DIR="$VISUAL_RUNTIME_DIR" WAYLAND_DISPLAY="$VISUAL_WAYLAND_DISPLAY" swaymsg -s "$VISUAL_SWAY_SOCKET" -t get_tree -r)" || return 1
  SWAY_TREE="$tree" APP_PID="$app_pid" dart /dev/stdin <<'DART'
import 'dart:convert';
import 'dart:io';

void main() {
  final root = jsonDecode(Platform.environment['SWAY_TREE']!) as Map<String, dynamic>;
  final appPid = int.tryParse(Platform.environment['APP_PID']!);
  if (appPid == null || appPid <= 0) {
    exitCode = 1;
    return;
  }
  final matches = <Map<String, dynamic>>[];
  void visit(Map<String, dynamic> node) {
    if (node['pid'] == appPid && node['type'] == 'con') matches.add(node);
    for (final key in ['nodes', 'floating_nodes']) {
      final children = node[key];
      if (children is List) {
        for (final child in children) {
          if (child is Map<String, dynamic>) visit(child);
        }
      }
    }
  }
  visit(root);
  if (matches.length != 1) {
    exitCode = 1;
    return;
  }
  final client = matches.single;
  final rect = client['rect'];
  if (rect is! Map<String, dynamic> ||
      rect['x'] is! num || rect['y'] is! num ||
      rect['width'] is! num || rect['height'] is! num) {
    exitCode = 1;
    return;
  }
  print('${rect['x']},${rect['y']} ${rect['width']}x${rect['height']}');
}
DART
}

baseline_dimensions() {
  dart /dev/stdin "$BASELINE" <<'DART'
import 'dart:io';
import 'dart:typed_data';

void main(List<String> arguments) {
  final bytes = File(arguments.single).readAsBytesSync();
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24 ||
      !Iterable<int>.generate(signature.length).every((index) => bytes[index] == signature[index]) ||
      String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    exitCode = 1;
    return;
  }
  final header = ByteData.sublistView(bytes, 16, 24);
  final width = header.getUint32(0);
  final height = header.getUint32(4);
  if (width == 0 || height == 0) {
    exitCode = 1;
    return;
  }
  print('$width $height');
}
DART
}

smoke_app_pid() {
  local app_pid
  [[ "$APP_PID_FD" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -f "/proc/self/fd/$APP_PID_FD" && -O "/proc/self/fd/$APP_PID_FD" ]] || return 1
  app_pid="$(head -n 1 "/proc/self/fd/$APP_PID_FD")" || return 1
  [[ "$app_pid" =~ ^[1-9][0-9]*$ ]] || return 1
  kill -0 "$app_pid" 2>/dev/null || return 1
  printf '%s\n' "$app_pid"
}

has_expected_client_size() {
  local geometry="$1"
  local expected_width="$2"
  local expected_height="$3"
  [[ "$geometry" =~ ^-?[0-9]+,-?[0-9]+[[:space:]]+([1-9][0-9]*)x([1-9][0-9]*)$ ]] || return 1
  [[ "${BASH_REMATCH[1]}" == "$expected_width" && "${BASH_REMATCH[2]}" == "$expected_height" ]]
}

start_private_sway() {
  local width="$1"
  local height="$2"
  local deadline
  local -a display_sockets ipc_sockets

  VISUAL_RUNTIME_DIR="$(mktemp -d /tmp/burlmd-visual-wayland.XXXXXX)" || return 1
  [[ -d "$VISUAL_RUNTIME_DIR" && "$VISUAL_RUNTIME_DIR" == /tmp/burlmd-visual-wayland.* ]] || return 1
  chmod 700 "$VISUAL_RUNTIME_DIR" || return 1
  VISUAL_SWAY_CONFIG="$VISUAL_RUNTIME_DIR/config"
  VISUAL_SWAY_LOG="$VISUAL_RUNTIME_DIR/sway.log"
  printf '%s\n' \
    'xwayland disable' \
    'default_border none' \
    'default_floating_border none' \
    'gaps inner 0' \
    'gaps outer 0' \
    "output HEADLESS-1 mode ${width}x${height}" \
    > "$VISUAL_SWAY_CONFIG" || return 1

  env -u DISPLAY -u WAYLAND_DISPLAY -u SWAYSOCK \
    "XDG_RUNTIME_DIR=$VISUAL_RUNTIME_DIR" \
    'WLR_BACKENDS=headless' \
    'WLR_HEADLESS_OUTPUTS=1' \
    'WLR_RENDERER=pixman' \
    'WLR_LIBINPUT_NO_DEVICES=1' \
    sway -c "$VISUAL_SWAY_CONFIG" > "$VISUAL_SWAY_LOG" 2>&1 &
  COMPOSITOR_PID=$!
  deadline=$(( $(date +%s) + 30 ))
  while kill -0 "$COMPOSITOR_PID" 2>/dev/null; do
    mapfile -t display_sockets < <(find "$VISUAL_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-[0-9]*' -printf '%f\n')
    mapfile -t ipc_sockets < <(find "$VISUAL_RUNTIME_DIR" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -printf '%p\n')
    if [[ "${#display_sockets[@]}" -eq 1 && "${#ipc_sockets[@]}" -eq 1 ]]; then
      VISUAL_WAYLAND_DISPLAY="${display_sockets[0]}"
      VISUAL_SWAY_SOCKET="${ipc_sockets[0]}"
      if XDG_RUNTIME_DIR="$VISUAL_RUNTIME_DIR" WAYLAND_DISPLAY="$VISUAL_WAYLAND_DISPLAY" \
          swaymsg -s "$VISUAL_SWAY_SOCKET" -t get_outputs -r >/dev/null; then
        return 0
      fi
    fi
    (( $(date +%s) < deadline )) || break
    sleep .1
  done
  return 1
}

cd "$REPO_ROOT"
if [[ "$WRITE_BASELINE" -eq 1 ]]; then
  BASELINE_WIDTH="$CANONICAL_WIDTH"
  BASELINE_HEIGHT="$CANONICAL_HEIGHT"
else
  read -r BASELINE_WIDTH BASELINE_HEIGHT <<< "$(baseline_dimensions)" || {
    echo "visual-regression: could not read baseline dimensions from $BASELINE" >&2
    exit 1
  }
  [[ "$BASELINE_WIDTH" =~ ^[1-9][0-9]*$ && "$BASELINE_HEIGHT" =~ ^[1-9][0-9]*$ ]] || {
    echo "visual-regression: invalid baseline dimensions: ${BASELINE_WIDTH:-?}x${BASELINE_HEIGHT:-?}" >&2
    exit 1
  }
  if [[ "$BASELINE_WIDTH" != "$CANONICAL_WIDTH" || "$BASELINE_HEIGHT" != "$CANONICAL_HEIGHT" ]]; then
    echo "visual-regression: baseline must use canonical ${CANONICAL_WIDTH}x${CANONICAL_HEIGHT}, got ${BASELINE_WIDTH}x${BASELINE_HEIGHT}" >&2
    exit 1
  fi
fi
command -v sway >/dev/null 2>&1 || {
  echo "visual-regression: sway is required for the isolated Linux visual gate" >&2
  exit 1
}
if ! start_private_sway "$BASELINE_WIDTH" "$BASELINE_HEIGHT"; then
  echo "visual-regression: could not start the private headless Sway compositor" >&2
  [[ -n "$VISUAL_SWAY_LOG" ]] && sed -n '1,160p' "$VISUAL_SWAY_LOG" >&2 || true
  exit 1
fi
APP_PID_FILE="$(mktemp "$VISUAL_RUNTIME_DIR/.visual-regression-${NAME}.app-pid.XXXXXX")" || {
  echo "visual-regression: could not create the private PID handoff" >&2
  exit 1
}
exec {APP_PID_FD}<> "$APP_PID_FILE" || {
  echo "visual-regression: could not open the private PID handoff" >&2
  exit 1
}

XDG_RUNTIME_DIR="$VISUAL_RUNTIME_DIR" WAYLAND_DISPLAY="$VISUAL_WAYLAND_DISPLAY" \
  SWAYSOCK="$VISUAL_SWAY_SOCKET" GDK_BACKEND=wayland \
  BURLMD_SMOKE_SHOT_DIR="$CAPTURE_DIR" BURLMD_SMOKE_APP_PID_FD="$APP_PID_FD" \
  "$REPO_ROOT/scripts/smoke-shot.sh" "$NAME" &
SMOKE_PID=$!
# GTK's HeaderBar occupies the first 47 rows in this reproducible Linux
# capture. It is host-owned (font AA, close button, and compositor rendering),
# so preserve it in the PNG but exclude it from the product-pixel comparison.
HOST_TITLEBAR_HEIGHT=47
CAPTURE_DEADLINE=$(( $(date +%s) + 60 ))
APP_PID=""
CLIENT_VERIFIED=0
while kill -0 "$SMOKE_PID" 2>/dev/null; do
  if [[ -z "$APP_PID" ]]; then
    APP_PID="$(smoke_app_pid 2>/dev/null || true)"
  fi
  if [[ -n "$APP_PID" ]] && GEOMETRY="$(sway_client_geometry "$APP_PID" 2>/dev/null)" &&
      has_expected_client_size "$GEOMETRY" "$BASELINE_WIDTH" "$BASELINE_HEIGHT"; then
    # Confirm after a compositor tick: a matching PID alone is insufficient if
    # layout changes shrink it before smoke-shot's final screenshot.
    sleep .2
    GEOMETRY="$(sway_client_geometry "$APP_PID" 2>/dev/null)" || break
    if has_expected_client_size "$GEOMETRY" "$BASELINE_WIDTH" "$BASELINE_HEIGHT"; then
      CLIENT_VERIFIED=1
      break
    fi
  fi
  (( $(date +%s) < CAPTURE_DEADLINE )) || break
  sleep .2
done
if (( ! CLIENT_VERIFIED )); then
  echo "visual-regression: did not verify launched PID ${APP_PID:-unknown} at ${BASELINE_WIDTH}x${BASELINE_HEIGHT}" >&2
  exit 1
fi
if ! wait "$SMOKE_PID"; then
  exit 1
fi
SMOKE_PID=""
[[ -s "$SHOT" ]] || {
  echo "visual-regression: smoke-shot did not write $SHOT" >&2
  exit 1
}

if [[ "$WRITE_BASELINE" -eq 1 ]]; then
  mkdir -p "$(dirname "$BASELINE")"
  cp "$SHOT" "$BASELINE"
  echo "[visual-regression] baseline written: $BASELINE"
  echo "[visual-regression] capture: $SHOT"
  echo "[visual-regression] different pixels: 0 (baseline written)"
  exit 0
fi

png_to_ppm "$SHOT" "$CAPTURE_PPM" 0 "$HOST_TITLEBAR_HEIGHT"
png_to_ppm "$BASELINE" "$BASELINE_PPM" 0 "$HOST_TITLEBAR_HEIGHT"
if ! COMPARED_PIXELS="$(compared_pixel_count "$CAPTURE_PPM" 0 "$HOST_TITLEBAR_HEIGHT")"; then
  echo "visual-regression: could not count compared pixels" >&2
  exit 1
fi
if ! DIFFERENT_PIXELS="$(count_diff_pixels "$CAPTURE_PPM" "$BASELINE_PPM")"; then
  echo "visual-regression: could not compare $SHOT and $BASELINE" >&2
  exit 1
fi

echo "[visual-regression] capture: $SHOT"
echo "[visual-regression] baseline: $BASELINE"
echo "[visual-regression] compared pixels: $COMPARED_PIXELS"
echo "[visual-regression] different pixels: $DIFFERENT_PIXELS (maximum: $MAX_DIFFERENT_PIXELS)"

if (( DIFFERENT_PIXELS > MAX_DIFFERENT_PIXELS )); then
  exit 1
fi
