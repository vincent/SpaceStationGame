#!/usr/bin/env bash
# Renders the game (Compatibility renderer, close to Mobile) and saves a PNG — lets you (or Claude, in a headless
# session) check visuals without a device.
#   tools/screenshot.sh [out.png] [dev hooks...]
#   tools/screenshot.sh build/bed.png --interact=bed --delay=5
# Uses xvfb-run automatically when there is no display (CI, containers).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-build/screenshot.png}"; shift || true
mkdir -p "$(dirname "$ROOT/$OUT")"
case "$OUT" in /*) ABS="$OUT" ;; *) ABS="$ROOT/$OUT" ;; esac
CMD=("$ROOT/tools/godot.sh" --path "$ROOT" --resolution 1280x720 --rendering-method gl_compatibility -- "--screenshot=$ABS" "$@")
if [[ -z "${DISPLAY:-}" && "$(uname -s)" == "Linux" ]]; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${CMD[@]}"
else
  "${CMD[@]}"
fi
