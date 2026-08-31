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
SMOKE_STATE_DIR=""
SMOKE_HOME=""
SMOKE_DATA_HOME=""
SMOKE_DB_PATH=""
SMOKE_WORKSPACE=""
SMOKE_NONCE=""
SMOKE_NONCE_FILE=""
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
  # The smoke state directory is created with this exact /tmp prefix below.
  # Keep cleanup limited to that validated, per-run directory: the harness
  # must never remove a caller-selected HOME, XDG directory, or database.
  if [[ -n "$SMOKE_STATE_DIR" && -d "$SMOKE_STATE_DIR" && "$SMOKE_STATE_DIR" == /tmp/burlmd-smoke-state.* ]]; then
    rm -rf -- "$SMOKE_STATE_DIR"
  fi
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
# Every smoke process gets a new, private home, XDG data tree, index database,
# and default Workspace. Scenario staging creates/deletes fixture Notes, so the
# app requires this exact canonical tree plus a per-run nonce capability before
# F002--F007 can run. A copied BURLMD_SMOKE_ISOLATED=1 is deliberately useless.
# Use a fixed absolute mktemp template and validate its result before any
# recursive cleanup is ever allowed to target it.
SMOKE_STATE_DIR="$(mktemp -d /tmp/burlmd-smoke-state.XXXXXX)" \
  || fail "could not create an isolated smoke state directory"
[[ -d "$SMOKE_STATE_DIR" && "$SMOKE_STATE_DIR" == /tmp/burlmd-smoke-state.* ]] \
  || fail "isolated smoke state directory failed validation"
SMOKE_HOME="$SMOKE_STATE_DIR/home"
SMOKE_DATA_HOME="$SMOKE_STATE_DIR/data"
SMOKE_DB_PATH="$SMOKE_DATA_HOME/burlmd/index.sqlite3"
SMOKE_WORKSPACE="$SMOKE_DATA_HOME/burlmd/workspace"
SMOKE_NONCE_FILE="$SMOKE_STATE_DIR/.burlmd-smoke-nonce"
READY_FILE="$SMOKE_STATE_DIR/.burlmd-smoke-ready"
mkdir -p -- "$SMOKE_HOME" "$SMOKE_WORKSPACE" \
  || fail "could not initialize isolated smoke state"
touch -- "$SMOKE_DB_PATH" || fail "could not initialize isolated smoke database"
touch -- "$READY_FILE" || fail "could not initialize smoke readiness marker"
SMOKE_NONCE="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
[[ "$SMOKE_NONCE" =~ ^[a-f0-9]{64}$ ]] || fail "could not generate smoke nonce"
(umask 077 && printf '%s\n' "$SMOKE_NONCE" > "$SMOKE_NONCE_FILE") \
  || fail "could not write smoke nonce capability"

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
# environment inheritance. Do not forward caller-supplied isolation-contract
# keys: the values below are the only authoritative per-run capability.
SCENARIO_ENV=()
for scenario_var in \
  BURLMD_SMOKE_F001 BURLMD_SMOKE_F001_FOCUSED_INDEX \
  BURLMD_SMOKE_F002 BURLMD_SMOKE_F003 BURLMD_SMOKE_F004 \
  BURLMD_SMOKE_F005 BURLMD_SMOKE_F006 BURLMD_SMOKE_F007 \
  BURLMD_SMOKE_TABS_G004; do
  if [[ -v "$scenario_var" ]]; then
    SCENARIO_ENV+=("$scenario_var=${!scenario_var}")
  fi
done
if (( ${#SCENARIO_ENV[@]} > 0 )); then
  echo "[smoke-shot] staging scenario env: ${SCENARIO_ENV[*]}"
fi
# The app validates all of these paths by canonical resolution before Rust
# initializes. The Workspace path is the Core's XDG default; it is explicit so
# a direct launch cannot substitute a real default Workspace by stealth.
env "${SCENARIO_ENV[@]}" \
  "BURLMD_SMOKE_ISOLATED=1" \
  "BURLMD_SMOKE_ROOT=$SMOKE_STATE_DIR" \
  "BURLMD_SMOKE_NONCE=$SMOKE_NONCE" \
  "BURLMD_SMOKE_NONCE_FILE=$SMOKE_NONCE_FILE" \
  "BURLMD_SMOKE_WORKSPACE=$SMOKE_WORKSPACE" \
  "BURLMD_SMOKE_READY_FILE=$READY_FILE" \
  "HOME=$SMOKE_HOME" \
  "XDG_DATA_HOME=$SMOKE_DATA_HOME" \
  "BURLMD_DB_PATH=$SMOKE_DB_PATH" \
  "$APP_BIN" &
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

if [[ "${BURLMD_SMOKE_F003:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F003 scenario never reached heterogeneous cross-block selection readiness"
  [[ "$(<"$READY_FILE")" == "f003-heterogeneous-cross-block-selection" ]] \
    || fail "F003 scenario readiness marker was invalid"
fi

if [[ "${BURLMD_SMOKE_F004:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F004 scenario never reached the promoted-plus-phantom readiness state"
  [[ "$(<"$READY_FILE")" == "f004-promoted-phantom" ]] \
    || fail "F004 scenario readiness marker was invalid"
fi

if [[ "${BURLMD_SMOKE_F005:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F005 scenario never reached the focused emphasis-shortcut readiness state"
  [[ "$(<"$READY_FILE")" == "f005-focused-emphasis-shortcut" ]] \
    || fail "F005 scenario readiness marker was invalid"
fi

if [[ "${BURLMD_SMOKE_F006:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F006 scenario never accepted a completion and followed a rendered Link"
  [[ "$(<"$READY_FILE")" == "f006-completion-accepted-and-internal-link-followed" ]] \
    || fail "F006 scenario readiness marker was invalid"
fi

if [[ "${BURLMD_SMOKE_F007:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "F007 scenario never completed type input, Action paste, and Action delete to the phantom caret"
  [[ "$(<"$READY_FILE")" == "f007-type-input-paste-action-delete-action-core-caret-phantom" ]] \
    || fail "F007 scenario readiness marker was invalid"
fi

if [[ "${BURLMD_SMOKE_TABS_G004:-}" == "1" ]]; then
  [[ -s "$READY_FILE" ]] || fail "TABS-G004 scenario never staged Core-backed sessions"
  [[ "$(<"$READY_FILE")" == "tabs-g004-core-sessions" ]] \
    || fail "TABS-G004 scenario readiness marker was invalid"
fi

grim "$SHOT" >/dev/null 2>&1 || fail "final grim capture failed"
chmod u+w "$SHOT" 2>/dev/null || true

echo "[smoke-shot] screenshot written to $SHOT"
