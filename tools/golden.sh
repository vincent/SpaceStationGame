#!/usr/bin/env bash
# Golden-image tests. The fixed camera makes renders stable, so canonical
# scenes are rendered and compared with the stored goldens in tests/goldens/.
#   tools/golden.sh             render + compare (exit 1 on any mismatch)
#   tools/golden.sh --update    render + overwrite the goldens (do it on purpose!)
#   tools/golden.sh room_view   only the named scene(s)
# Rendering uses Mesa's software rasterizer (llvmpipe) so pixels match across
# machines and CI. Diffs of failures land in build/golden/<name>.diff.png.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDENS="$ROOT/tests/goldens"
OUT="$ROOT/build/golden"
UPDATE=0
ONLY=()
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    *) ONLY+=("$arg") ;;
  esac
done

# name | dev hooks (see DebugOverlay._run_cli_commands)
SCENES=(
  "station_closed|--view=station"
  "cut_open|--power=wreck_core --focus=wreck_core"
  "room_view|--focus=capsule"
  "exploded|--focus=capsule --explode"
  "night|--power=all --focus=capsule --time=23"
)

export LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$OUT" "$GOLDENS"
"$ROOT/tools/import.sh" >/dev/null
FAILED=0
for entry in "${SCENES[@]}"; do
  name="${entry%%|*}"
  hooks="${entry#*|}"
  if [[ ${#ONLY[@]} -gt 0 && ! " ${ONLY[*]} " =~ " $name " ]]; then continue; fi
  # shellcheck disable=SC2086
  "$ROOT/tools/screenshot.sh" "build/golden/$name.png" --freeze --delay=4 $hooks >/dev/null 2>&1 || true
  if [[ ! -f "$OUT/$name.png" ]]; then
    echo "❌ $name: render failed"; FAILED=1; continue
  fi
  if [[ $UPDATE -eq 1 ]]; then
    cp "$OUT/$name.png" "$GOLDENS/$name.png"
    echo "📸 $name: golden updated"
    continue
  fi
  if [[ ! -f "$GOLDENS/$name.png" ]]; then
    echo "❌ $name: no golden (run tools/golden.sh --update $name)"; FAILED=1; continue
  fi
  if result="$("$ROOT/tools/godot.sh" --headless --path "$ROOT" -s res://tools/image_diff.gd -- \
      "$GOLDENS/$name.png" "$OUT/$name.png" "$OUT/$name.diff.png" 2>&1 | grep -E "^(OK|FAIL)")"; then
    echo "✅ $name: $result"
  else
    echo "❌ $name: ${result:-compare failed} (see build/golden/$name.diff.png)"; FAILED=1
  fi
done
exit $FAILED
