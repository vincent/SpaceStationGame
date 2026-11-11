#!/usr/bin/env bash
# Runs the game in a window. Extra args after "--" go to the game's dev hooks
# (see DebugOverlay._run_cli_commands), e.g.
#   tools/run.sh -- --debug-panel --walls=down
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/tools/godot.sh" --path "$ROOT" "$@"
