#!/usr/bin/env bash
# Captures the README screenshots in docs/images from a demo build: made-up meetings in a temp folder, an in-memory
# Keychain, and its own bundle ID (Sources/GrokNotes/Demo), so real data, settings, and the Keychain are untouched.
# Needs Screen Recording permission for the app running this script (Terminal, or your editor).
# Usage: ./scripts/take-screenshots.sh [scene ...]   scenes: home notes notes-dark transcript meeting-ask ask
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs/images"
APP="build/demo/GrokNola.app"
TMP_ROOT="${TMPDIR:-/tmp}"
DEMO_DIR="${TMP_ROOT%/}/groknola-demo"
SCENES=("$@")
[ ${#SCENES[@]} -gt 0 ] || SCENES=(notes notes-dark home transcript meeting-ask ask)

GROKNOLA_DEMO=1 ./scripts/build-app.sh
mkdir -p "$OUT"

capture() {
  local name="$1" scene="${1%-dark}" appearance=light
  [ "$scene" = "$name" ] || appearance=dark
  rm -f "$DEMO_DIR/window-id"
  # Launched through `open` so macOS makes it the active app and the window is captured in its focused state.
  open -n -a "$PWD/$APP" --env GROKNOLA_DEMO_SCENE="$scene" --env GROKNOLA_DEMO_APPEARANCE="$appearance" --env TMPDIR="$TMP_ROOT"
  for _ in $(seq 1 60); do
    [ -s "$DEMO_DIR/window-id" ] && break
    sleep 0.5
  done
  if [ ! -s "$DEMO_DIR/window-id" ]; then
    pkill -f "$APP/Contents/MacOS/GrokNotes" || true
    echo "error: the demo app did not open the $name scene." >&2
    return 1
  fi
  screencapture -x -l "$(cat "$DEMO_DIR/window-id")" "$OUT/$name.png"
  pkill -f "$APP/Contents/MacOS/GrokNotes" || true
  while pgrep -f "$APP/Contents/MacOS/GrokNotes" >/dev/null; do sleep 0.2; done
  sips -Z 2000 "$OUT/$name.png" >/dev/null
  echo "Saved $OUT/$name.png"
}

for scene in "${SCENES[@]}"; do
  capture "$scene"
done
