#!/usr/bin/env bash
# Lints GDScript with gdtoolkit (pip install "gdtoolkit==4.*"). Config: gdlintrc
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v gdlint >/dev/null; then
  echo "gdlint not found. Install with: pip install 'gdtoolkit==4.*'" >&2
  exit 1
fi
cd "$ROOT" && gdlint src tests
