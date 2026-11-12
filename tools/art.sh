#!/usr/bin/env bash
# Builds one module of the Blender module kit (art/kit/, specs in art/modules/).
# Usage: tools/art.sh <module_id> [--render] [--no-export]
# Needs Blender >= 4.2: set BLENDER=/path/to/blender, else the newest
# ~/Downloads/blender-*/blender, else `blender` on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:?usage: tools/art.sh <module_id> [--render] [--no-export]}"
shift
if [[ -z "${BLENDER:-}" ]]; then
  BLENDER="$(ls -d "$HOME"/Downloads/blender-*/blender 2>/dev/null | sort -V | tail -1 || true)"
  BLENDER="${BLENDER:-$(command -v blender || true)}"
fi
[[ -x "$BLENDER" ]] || { echo "Blender not found; set BLENDER=/path/to/blender" >&2; exit 1; }
VER="$("$BLENDER" --version 2>/dev/null | head -1 | awk '{print $2}')"
if [[ "$(printf '%s\n4.2\n' "$VER" | sort -V | head -1)" != "4.2" ]]; then
  echo "Blender $VER is too old (needs >= 4.2); set BLENDER=/path/to/blender" >&2
  exit 1
fi
cd "$ROOT"
"$BLENDER" -b --factory-startup --python-exit-code 1 --python art/kit/run.py -- --module="$ID" "$@" 2>&1 \
  | grep -E "^(KIT|Error|Traceback|  File|    |[A-Za-z]+Error)" || true
exit "${PIPESTATUS[0]}"
