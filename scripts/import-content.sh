#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
CONTENT_SOURCE="${1:-$PROJECT_ROOT/content/source}"
if [[ "$CONTENT_SOURCE" != /* ]]; then
  CONTENT_SOURCE="$PWD/$CONTENT_SOURCE"
fi
shift $(( $# > 0 ? 1 : 0 ))
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --editor --import --quit \
  --log-file "$PROJECT_ROOT/build/logs/content-import-editor.log"
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --script tools/import_content.gd \
  --log-file "$PROJECT_ROOT/build/logs/content-import.log" -- "$CONTENT_SOURCE" "$@"
