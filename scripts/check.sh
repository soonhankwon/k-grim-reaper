#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

python3 "$PROJECT_ROOT/scripts/check-architecture.py"

verify_log() {
  python3 - "$1" "${2:-}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(errors='replace')
if 'SCRIPT ERROR:' in text or 'ERROR:' in text or (sys.argv[2] and sys.argv[2] not in text):
    raise SystemExit('Godot validation failed; inspect ' + sys.argv[1])
PY
}

run_suite() {
  "$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --quit-after 1800 \
    --script "$1" --log-file "$PROJECT_ROOT/build/logs/$2"
  verify_log "$PROJECT_ROOT/build/logs/$2" "$3"
}

"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --editor --import --quit \
  --log-file "$PROJECT_ROOT/build/logs/import.log"
verify_log "$PROJECT_ROOT/build/logs/import.log"
run_suite tests/content_tests.gd content-tests.log 'CONTENT TESTS:'
python3 "$PROJECT_ROOT/scripts/check-content-import.py" "$GODOT_BIN"
run_suite tests/test_runner.gd tests.log 'RULE TESTS:'
run_suite tests/cascade_tests.gd cascade-tests.log 'CASCADE TESTS:'
run_suite tests/playback_tests.gd playback-tests.log 'PLAYBACK TESTS:'
run_suite tests/ui_smoke.gd ui-smoke.log 'UI SMOKE: PASS'
