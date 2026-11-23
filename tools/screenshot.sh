#!/usr/bin/env bash
# Renders the game (Compatibility renderer, close to Mobile) and saves a PNG (or a lossless WebP for out.webp) — lets you (or Claude, in a headless
# session) check visuals without a device.
#   tools/screenshot.sh [out.png] [dev hooks...]
#   tools/screenshot.sh build/bed.png --interact=bed --delay=5
#   tools/screenshot.sh build/portrait.png --resolution=720x1280   (window size, default 1280x720)
# Uses xvfb-run automatically when there is no display (CI, containers).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-build/screenshot.png}"; shift || true
mkdir -p "$(dirname "$ROOT/$OUT")"
case "$OUT" in /*) ABS="$OUT" ;; *) ABS="$ROOT/$OUT" ;; esac
RES="1280x720"
HOOKS=()
for arg in "$@"; do
  case "$arg" in
    --resolution=*) RES="${arg#--resolution=}" ;;
    *) HOOKS+=("$arg") ;;
  esac
done
CMD=("$ROOT/tools/godot.sh" --path "$ROOT" --resolution "$RES" --rendering-method gl_compatibility -- "--screenshot=$ABS" "${HOOKS[@]}")
if [[ -z "${DISPLAY:-}" && "$(uname -s)" == "Linux" ]]; then
  xvfb-run -a -s "-screen 0 ${RES}x24" "${CMD[@]}"
else
  "${CMD[@]}"
fi
