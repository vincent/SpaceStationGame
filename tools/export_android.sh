#!/usr/bin/env bash
# Exports an Android APK (debug by default).
#   tools/export_android.sh            -> build/android/SpaceStationTycoon.apk (debug)
#   tools/export_android.sh release    -> needs GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD
# Requirements: JDK 17 (JAVA_HOME) and the Android SDK (ANDROID_HOME) with
# build-tools + platform-tools. Export templates are downloaded automatically
# (Linux, self-contained pinned Godot only; otherwise install them from the editor).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-debug}"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"
BIN_DIR="$ROOT/.godot-bin/$VERSION"
DATA_DIR="$BIN_DIR/editor_data"
TEMPLATES="$DATA_DIR/export_templates/${VERSION}.stable"

: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
[[ -n "$ANDROID_HOME" ]] || { echo "Set ANDROID_HOME to your Android SDK." >&2; exit 1; }
: "${JAVA_HOME:=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

"$ROOT/tools/godot.sh" --version >/dev/null   # make sure Godot is downloaded

if [[ -z "${GODOT:-}" ]]; then
  # Export templates (only the Android ones are extracted from the big .tpz).
  if [[ ! -f "$TEMPLATES/android_debug.apk" ]]; then
    echo "Downloading export templates for $VERSION..." >&2
    mkdir -p "$TEMPLATES"
    TPZ="$BIN_DIR/templates.tpz"
    curl -fsSL -o "$TPZ" "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_export_templates.tpz"
    unzip -q -o -j "$TPZ" "templates/android_*" "templates/version.txt" -d "$TEMPLATES"
    rm "$TPZ"
  fi
  # Editor settings for the self-contained Godot (SDK/JDK paths, debug keystore).
  MINOR="$(echo "$VERSION" | cut -d. -f1-2)"
  mkdir -p "$DATA_DIR"
  KEYSTORE="$DATA_DIR/debug.keystore"
  if [[ ! -f "$KEYSTORE" ]]; then
    keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android -keypass android \
      -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" \
      -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
  fi
  cat > "$DATA_DIR/editor_settings-${MINOR}.tres" <<SETTINGS
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
SETTINGS
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
fi

"$ROOT/tools/import.sh"
mkdir -p "$ROOT/build/android"
OUT="$ROOT/build/android/SpaceStationTycoon-${MODE}.apk"
"$ROOT/tools/godot.sh" --headless --path "$ROOT" "--export-${MODE}" "Android" "$OUT"
[[ -f "$OUT" ]] || { echo "❌ Export failed (no APK produced)." >&2; exit 1; }
echo "✅ $OUT"
