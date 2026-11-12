#!/usr/bin/env bash
# Perf stress test: grows a huge station (StressLayout) and prints a frame-time report.
#   tools/stress.sh [modules=80] [seconds=10] [extra dev hooks...]
#   tools/stress.sh 200 15 --view=station --focus=wreck_core
#   RENDERER=mobile tools/stress.sh   # the game's renderer (needs a GPU); default gl_compatibility
# Uses xvfb-run (software GL, so absolute numbers are pessimistic) when there is no display.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES="${1:-80}"; shift || true
SECONDS_="${1:-10}"; shift || true
METHOD="gl_compatibility"
[[ "${RENDERER:-}" == "mobile" ]] && METHOD="mobile"
CMD=("$ROOT/tools/godot.sh" --path "$ROOT" --resolution 1280x720 --rendering-method "$METHOD" --disable-vsync --max-fps 0
  -- --story=off --layout=stress "--modules=$MODULES" "--perf=$SECONDS_" "$@")
if [[ -z "${DISPLAY:-}" && "$(uname -s)" == "Linux" ]]; then
  CMD=(xvfb-run -a -s "-screen 0 1280x720x24" "${CMD[@]}")
fi
# Report lines as they come; errors/warnings counted once each at the end (they can spam per frame).
"${CMD[@]}" 2>&1 | awk '
  /^(STRESS|PERF):/ { print; fflush(); next }
  /^(ERROR|WARNING|SCRIPT ERROR):/ { if (!($0 in seen)) order[++n] = $0; seen[$0]++ }
  END { for (i = 1; i <= n; i++) printf "%6dx %s\n", seen[order[i]], order[i] }'

