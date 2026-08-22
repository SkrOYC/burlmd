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
# application fails to start/render. grim is Wayland-only tooling provisioned
# in devenv.nix; see .constitution/tech-spec/guidelines.md.

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
QA_DIR="$REPO_ROOT/.qa"
SHOT="$QA_DIR/$NAME.png"

START_TIMEOUT=180     # seconds allowed for both builds + launch
RENDER_TIMEOUT=60     # seconds allowed for the window to appear
SETTLE_SECONDS=3      # grace after first sign of rendering
POLL_INTERVAL=0.5

APP_BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
APP_BIN="$APP_BUNDLE/burlmd"

cd "$REPO_ROOT"
mkdir -p "$QA_DIR"

APP_PID=""
BASELINE="$(mktemp /tmp/smoke-shot-baseline.XXXXXX.png)"
CANDIDATE="$(mktemp /tmp/smoke-shot-candidate.XXXXXX.png)"

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$APP_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  rm -f "$BASELINE" "$CANDIDATE"
}
trap cleanup EXIT

fail() {
  echo "smoke-shot: FAILED: $*" >&2
  exit 1
}

deadline() { echo $(( $(date +%s) + $1 )); }
timed_out() { (( $(date +%s) >= $1 )); }

echo "[smoke-shot] building rust native library (release)..."
(cd rust && cargo build --release) || fail "cargo build --release failed"

echo "[smoke-shot] building flutter desktop app (linux release)..."
flutter build linux --release || fail "flutter build linux --release failed"

[[ -x "$APP_BIN" ]] || fail "app binary not found at $APP_BIN after build"

# Baseline of the screen before the app exists, so "rendered" means "something
# new was drawn", not merely "grim succeeded".
grim "$BASELINE" >/dev/null 2>&1 \
  || fail "grim could not capture the screen (is this a Wayland session?)"

echo "[smoke-shot] launching $APP_BIN..."
"$APP_BIN" &
APP_PID=$!

START_DEADLINE="$(deadline "$START_TIMEOUT")"
until kill -0 "$APP_PID" 2>/dev/null; do
  timed_out "$START_DEADLINE" && fail "app process never started"
  sleep "$POLL_INTERVAL"
done

echo "[smoke-shot] waiting for the window to render..."
RENDER_DEADLINE="$(deadline "$RENDER_TIMEOUT")"
rendered=0
while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" || true
    fail "application exited before rendering (exit status recorded above)"
  fi
  if grim "$CANDIDATE" >/dev/null 2>&1; then
    if ! cmp -s "$BASELINE" "$CANDIDATE"; then
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

grim "$CANDIDATE" >/dev/null 2>&1 || fail "final grim capture failed"
mv "$CANDIDATE" "$SHOT"
chmod u+w "$SHOT" 2>/dev/null || true

echo "[smoke-shot] screenshot written to $SHOT"
