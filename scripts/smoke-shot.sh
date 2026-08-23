#!/usr/bin/env bash
#
# SHEL-E001 — Manual-QA smoke harness.
#
# Builds the Rust native library in release mode (the generated
# flutter_rust_bridge loader in lib/src/rust/frb_generated.dart resolves it
# from rust/target/release/, a path the debug bundle does not populate),
# builds and launches the Flutter desktop app on Linux/Wayland, waits for the
# window to actually render, captures a full-screen screenshot with grim to
# .qa/<name>.png, and terminates the application.
#
# Exits non-zero and writes no screenshot if any build step fails or the
# application fails to start/render. Render detection compares raw pixels
# (grim -t ppm) against a pre-launch baseline: two baseline captures taken one
# second apart measure the desktop's own animation noise floor (clocks, panel
# widgets), and the app counts as rendered only once the per-pixel difference
# count exceeds several times that noise floor. A naive byte-compare of PNGs
# fires on the very first poll because background animations always differ.
# grim is Wayland-only tooling provisioned in devenv.nix; see
# .constitution/tech-spec/guidelines.md.

set -euo pipefail

usage() {
  echo "usage: $0 <name>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
NAME="$1"
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "smoke-shot: invalid name '$NAME' (allowed: letters, digits, . _ -)" >&2
  exit 64
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QA_DIR="${BURLMD_SMOKE_SHOT_DIR:-$REPO_ROOT/.qa}"
SHOT="$QA_DIR/$NAME.png"

RENDER_TIMEOUT=60         # seconds allowed for the window to appear
SETTLE_SECONDS=3      # grace after first sign of rendering
POLL_INTERVAL=0.5

APP_BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
APP_BIN="$APP_BUNDLE/burlmd"

cd "$REPO_ROOT"
mkdir -p "$QA_DIR"

# Drop any screenshot left by an earlier run up front, so a failed run can
# never leave a stale .qa/<name>.png behind.
rm -f "$SHOT"

APP_PID=""
READY_FILE=""
NOISE_A="$(mktemp /tmp/smoke-shot-noise-a.XXXXXX.ppm)"
NOISE_B="$(mktemp /tmp/smoke-shot-noise-b.XXXXXX.ppm)"
CANDIDATE="$(mktemp /tmp/smoke-shot-candidate.XXXXXX.ppm)"

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$APP_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  rm -f "$NOISE_A" "$NOISE_B" "$CANDIDATE"
  [[ -z "$READY_FILE" ]] || rm -f "$READY_FILE"
}
trap cleanup EXIT

fail() {
  echo "smoke-shot: FAILED: $*" >&2
  exit 1
}

deadline() { echo $(( $(date +%s) + $1 )); }
timed_out() { (( $(date +%s) >= $1 )); }

# Byte offset of the first pixel byte of a binary PPM (P6) file. The header
# is three newline-terminated records — "P6", "<w> <h>", "<maxval>" — and the
# awk sums each record's length plus its newline over NR = 1..3, so the value
# printed at NR == 3 lands just past the maxval line's \n: exactly where the
# raw RGB bytes begin.
ppm_pixel_offset() {
  head -c 64 "$1" | awk 'BEGIN { RS = "\n" } NR < 4 { off += length($0) + 1 }
    NR == 3 { print off + 0; exit }'
}

# Count pixels whose RGB bytes differ between two same-size raw PPM captures.
# Prints the count; prints nothing if either file cannot be parsed.
count_diff_pixels() {
  local off_a off_b
  off_a="$(ppm_pixel_offset "$1")"
  off_b="$(ppm_pixel_offset "$2")"
  [[ -n "$off_a" && -n "$off_b" && "$off_a" -gt 0 && "$off_a" -eq "$off_b" ]] || return 0
  paste -d ' ' \
    <(od -An -v -tu1 -j "$off_a" "$1") \
    <(od -An -v -tu1 -j "$off_a" "$2") \
    | awk '{ half = NF / 2
      for (i = 1; i <= half; i++) if ($(i) != $(i + half)) changed++
    } END { print changed + 0 }'
}

echo "[smoke-shot] building rust native library (release)..."
(cd rust && cargo build --release) || fail "cargo build --release failed"

echo "[smoke-shot] building flutter desktop app (linux release)..."
flutter build linux --release || fail "flutter build linux --release failed"

[[ -x "$APP_BIN" ]] || fail "app binary not found at $APP_BIN after build"

# Baseline of the screen before the app exists, so "rendered" means "something
# substantial was drawn", not merely "grim succeeded". Two captures one second
# apart measure how many pixels the desktop itself animates (clocks, panels);
# the render threshold is a multiple of that noise floor plus an absolute
# minimum, so small background animations can never fake a window appearing.
grim -t ppm "$NOISE_A" >/dev/null 2>&1 \
  || fail "grim could not capture the screen (is this a Wayland session?)"
sleep 1
grim -t ppm "$NOISE_B" >/dev/null 2>&1 \
  || fail "second grim baseline capture failed"
noise_pixels="$(count_diff_pixels "$NOISE_A" "$NOISE_B")"
DIFF_THRESHOLD=$(( noise_pixels * 3 + 20000 ))
echo "[smoke-shot] desktop noise floor: ${noise_pixels} px; render threshold: ${DIFF_THRESHOLD} px"

echo "[smoke-shot] launching $APP_BIN..."
# No separate "did it start" wait exists here, deliberately: `kill -0` on a
# freshly backgrounded PID succeeds immediately whether or not exec worked,
# so such a loop would detect nothing. A process that dies at startup is
# caught by the render loop below, whose first `kill -0` fails and reports
# the exit status.
#
# Scenario staging (EDIT-F002): the app can build a demo Note through the
# Core when launched with a BURLMD_SMOKE_* variable (e.g.
# BURLMD_SMOKE_F002=1 stages a focused raw-source Block among formatted
# neighbors). Any such variable the caller exports is forwarded explicitly
# here, so the hook is visible in this file rather than relying on silent
# environment inheritance.
SCENARIO_ENV=()
while IFS='=' read -r entry; do
  SCENARIO_ENV+=("$entry")
done < <(env | grep '^BURLMD_SMOKE')
if [[ "${BURLMD_SMOKE_F002:-}" == "1" ]]; then
  READY_FILE="$(mktemp /tmp/burlmd-f002-ready.XXXXXX)"
  rm -f "$READY_FILE"
  SCENARIO_ENV+=("BURLMD_SMOKE_READY_FILE=$READY_FILE")
fi
if (( ${#SCENARIO_ENV[@]} > 0 )); then
  echo "[smoke-shot] staging scenario env: ${SCENARIO_ENV[*]}"
  env "${SCENARIO_ENV[@]}" "$APP_BIN" &
else
  "$APP_BIN" &
fi
APP_PID=$!

echo "[smoke-shot] waiting for the window to render..."
RENDER_DEADLINE="$(deadline "$RENDER_TIMEOUT")"
rendered=0
while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" && APP_EXIT=0 || APP_EXIT=$?
    fail "application exited before rendering (exit status ${APP_EXIT})"
  fi
  if grim -t ppm "$CANDIDATE" >/dev/null 2>&1; then
    diff_pixels="$(count_diff_pixels "$NOISE_A" "$CANDIDATE")"
    if [[ -n "$diff_pixels" && "$diff_pixels" -ge "$DIFF_THRESHOLD" ]]; then
      rendered=1
      break
    fi
  fi
  timed_out "$RENDER_DEADLINE" \
    && fail "window did not appear within ${RENDER_TIMEOUT}s"
  sleep "$POLL_INTERVAL"
done

echo "[smoke-shot] window detected; letting the UI settle ${SETTLE_SECONDS}s..."
sleep "$SETTLE_SECONDS"

if ! kill -0 "$APP_PID" 2>/dev/null; then
  fail "application exited during settle period"
fi

if [[ "${BURLMD_SMOKE_F002:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F002 scenario never reached focused raw-source readiness"
  [[ "$(<"$READY_FILE")" == "f002-focused-raw-source" ]] \
    || fail "F002 scenario readiness marker was invalid"
fi

grim "$SHOT" >/dev/null 2>&1 || fail "final grim capture failed"
chmod u+w "$SHOT" 2>/dev/null || true

echo "[smoke-shot] screenshot written to $SHOT"
