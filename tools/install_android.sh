#!/usr/bin/env bash
# Installs and launches the debug APK on a USB-connected phone (enable
# Developer options > USB debugging first). Requires adb (Android platform-tools).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="${1:-$ROOT/build/android/SpaceStationTycoon-debug.apk}"
adb install -r "$APK"
adb shell monkey -p com.spacestationtycoon.game -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched. Logs: adb logcat -s godot"
