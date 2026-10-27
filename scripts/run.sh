#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ ! -f "$PROJECT_ROOT/game/.godot/global_script_class_cache.cfg" ]]; then
  "$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --editor --import --quit \
    --log-file "$PROJECT_ROOT/build/logs/import.log"
fi
exec "$GODOT_BIN" --path "$PROJECT_ROOT/game" \
  --log-file "$PROJECT_ROOT/build/logs/play.log"
