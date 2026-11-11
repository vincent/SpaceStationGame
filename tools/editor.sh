#!/usr/bin/env bash
# Opens the project in the pinned Godot editor.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/tools/godot.sh" --editor --path "$ROOT" "$@"
