#!/usr/bin/env bash
# Imports assets and parses every script. Fails if Godot reports any script
# or resource error (Godot itself exits 0 in that case, so we grep).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp)"
"$ROOT/tools/godot.sh" --headless --path "$ROOT" --import 2>&1 | tee "$LOG" >/dev/null || true
if grep -E "SCRIPT ERROR|Parse Error|ERROR:|Failed to load" "$LOG" | grep -v "addons/gut"; then
  echo "❌ Import reported errors (see above)." >&2
  exit 1
fi
echo "✅ Import OK"
