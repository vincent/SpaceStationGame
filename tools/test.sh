#!/usr/bin/env bash
# Runs the GUT test suite headless. Extra args go to GUT, e.g.
#   tools/test.sh -gselect=test_inventory      # one file
#   tools/test.sh -gunit_test_name=merge       # tests whose name contains "merge"
# JUnit report: build/test-results.xml
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/tools/import.sh"
mkdir -p "$ROOT/build"
"$ROOT/tools/godot.sh" --headless --path "$ROOT" -s res://addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json "$@"
