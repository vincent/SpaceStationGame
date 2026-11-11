#!/usr/bin/env bash
# Runs the project's pinned Godot version (see .godot-version), downloading it
# into .godot-bin/ on first use. Set GODOT=/path/to/godot to use your own.
# Usage: tools/godot.sh [godot args...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"

if [[ -n "${GODOT:-}" ]]; then
  exec "$GODOT" "$@"
fi

BIN_DIR="$ROOT/.godot-bin/$VERSION"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  ASSET="Godot_v${VERSION}-stable_linux.x86_64";  EXE="$BIN_DIR/$ASSET" ;;
  Linux-aarch64) ASSET="Godot_v${VERSION}-stable_linux.arm64";   EXE="$BIN_DIR/$ASSET" ;;
  Darwin-*)      ASSET="Godot_v${VERSION}-stable_macos.universal"; EXE="$BIN_DIR/Godot.app/Contents/MacOS/Godot" ;;
  MINGW*|MSYS*|CYGWIN*) ASSET="Godot_v${VERSION}-stable_win64.exe"; EXE="$BIN_DIR/$ASSET" ;;
  *) echo "Unsupported platform $(uname -s)-$(uname -m); set GODOT=/path/to/godot" >&2; exit 1 ;;
esac

if [[ ! -x "$EXE" ]]; then
  echo "Downloading Godot $VERSION ($ASSET)..." >&2
  mkdir -p "$BIN_DIR"
  URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/${ASSET}.zip"
  curl -fsSL -o "$BIN_DIR/godot.zip" "$URL"
  unzip -q -o "$BIN_DIR/godot.zip" -d "$BIN_DIR"
  rm "$BIN_DIR/godot.zip"
  chmod +x "$EXE"
  # Self-contained mode: editor settings and export templates live in
  # .godot-bin/<version>/editor_data instead of your user profile.
  touch "$BIN_DIR/._sc_"
fi

exec "$EXE" "$@"
