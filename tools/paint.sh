#!/usr/bin/env bash
# Camera-projection painting for one module (prototype, see tools/paint/*.py).
# Usage: tools/paint.sh <module_id> [--yaws=0,90,180,270] [--n=4] [--model=google/gemini-2.5-flash-image]
#                       [--size=2K] [--skip-ai] [--dry-run] [--pick=closed:K,cut:K,interior:K]
#                       [--variants=default,derelict] [--parts-pass=1]
# The camera is fixed, so each module direction (yaw 0/90/180/270) is painted separately:
#   per direction:
#     1. render   game-camera passes from art/modules/build/<id>.blend, lossless WebP (Blender)
#     2. ai       N paint-over candidates per view via OpenRouter                (OPENROUTER_API_KEY, or .env)
#     3. align    snap to geometry, score, pick, write <id>_paint_<yaw>.webp atlas (OpenCV)
#   then once:
#     4. project  one UV set per direction + palette fallback, export <id>.glb   (Blender)
#     5. new_module.py (art_paint_path, texture imports) + tools/import.sh
# --skip-ai reuses art/paint/<id>/y<yaw>/cand/*.webp (hand-edit a candidate, then re-run with --skip-ai).
# Only renders, cand/ and json are committed; aligned/, contact_*.jpg, paint_*.webp are local (gitignored)
# and rebuilt by --skip-ai. The game atlas is assets/models/modules/<id>_paint_<yaw>.webp.
# --pick applies to every direction listed in --yaws (use with a single direction).
# --variants: one painting set per module state, same projection (e.g. the wreck: default = repaired,
#   derelict = before repair; files <id>_paint_<yaw>[_<variant>].webp). Prompt notes: art/paint/<id>/notes.txt
# --parts-pass=0: hull views include the upgrade parts (bakes made before the parts pass, e.g. crew_pod).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:?usage: tools/paint.sh <module_id> [options]}"; shift
if [[ -z "${BLENDER:-}" ]]; then
  BLENDER="$(ls -d "$HOME"/Downloads/blender-*/blender 2>/dev/null | sort -V | tail -1 || true)"
  BLENDER="${BLENDER:-$(command -v blender || true)}"
fi
if [[ -z "${OPENROUTER_API_KEY:-}" && -f "$ROOT/.env" ]]; then   # .env is gitignored
  OPENROUTER_API_KEY="$(sed -n 's/^OPENROUTER_API_KEY=//p' "$ROOT/.env" | tail -1 | tr -d "\"'\r")"
  export OPENROUTER_API_KEY
fi
PY="$ROOT/tools/paint/.venv/bin/python"
[[ -x "$PY" ]] || { echo "Create the venv: python3 -m venv tools/paint/.venv && tools/paint/.venv/bin/pip install opencv-python-headless numpy requests" >&2; exit 1; }
SKIP_AI=0; AI_ARGS=(); AL_ARGS=(); BL_ARGS=(); YAWS="0,90,180,270"; VARIANTS="default"
for a in "$@"; do
  case "$a" in
    --skip-ai) SKIP_AI=1 ;;
    --pick=*|--max-flow=*) AL_ARGS+=("$a") ;;
    --yaws=*) YAWS="${a#--yaws=}" ;;
    --variants=*) VARIANTS="${a#--variants=}" ;;
    --res=*|--parts-pass=*) BL_ARGS+=("$a") ;;
    *) AI_ARGS+=("$a") ;;
  esac
done
BLEND="$ROOT/art/modules/build/$ID.blend"
[[ -f "$BLEND" ]] || { echo "Missing $BLEND: build the module first (tools/art.sh $ID)" >&2; exit 1; }
cd "$ROOT"
run_blender() { "$BLENDER" -b "$BLEND" --python-exit-code 1 -P tools/paint/paint_blender.py -- "$@" 2>&1 \
  | grep -E "^(PAINT|Error|Traceback|  File|    |[A-Za-z]+Error)" || true; return "${PIPESTATUS[0]}"; }
for Y in ${YAWS//,/ }; do
  echo "PAINT ===== $ID yaw $Y"
  run_blender render --module="$ID" --yaw="$Y" "${BL_ARGS[@]}"
  for V in ${VARIANTS//,/ }; do
    [[ $SKIP_AI == 1 ]] || "$PY" tools/paint/paint_ai.py "$ID" --yaw="$Y" --variant="$V" "${AI_ARGS[@]}"
    "$PY" tools/paint/paint_align.py "$ID" --yaw="$Y" --variant="$V" "${AL_ARGS[@]}"
  done
done
run_blender project --module="$ID"
python3 tools/new_module.py "$ID" >/dev/null
[[ -n "${PAINT_NO_IMPORT:-}" ]] || tools/import.sh   # parallel runs: import once at the end
