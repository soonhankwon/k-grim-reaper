#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

python3 "$PROJECT_ROOT/scripts/check-architecture.py"
python3 "$PROJECT_ROOT/scripts/check-release-language.py"
python3 "$PROJECT_ROOT/scripts/import-story.py" --check
python3 "$PROJECT_ROOT/scripts/import-arang-scenes.py" --check
python3 "$PROJECT_ROOT/scripts/check-story-import.py"

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
run_suite tests/turn_preview_tests.gd turn-preview-tests.log 'TURN PREVIEW TESTS:'
run_suite tests/diagonal_tests.gd diagonal-tests.log 'DIAGONAL TESTS:'
run_suite tests/multiplier_tests.gd multiplier-tests.log 'MULTIPLIER TESTS:'
run_suite tests/synergy_tests.gd synergy-tests.log 'SYNERGY TESTS:'
run_suite tests/synergy_presentation_tests.gd synergy-presentation-tests.log 'SYNERGY PRESENTATION:'
run_suite tests/art_atlas_tests.gd art-atlas-tests.log 'ART ATLAS TESTS:'
run_suite tests/bitmap_font_tests.gd bitmap-font-tests.log 'BITMAP FONT:'
run_suite tests/pixel_360_font_tests.gd pixel-360-font-tests.log 'PIXEL 360 FONT:'
run_suite tests/pixel_viewport_tests.gd pixel-viewport-tests.log 'PIXEL VIEWPORT:'
run_suite tests/playback_tests.gd playback-tests.log 'PLAYBACK TESTS:'
run_suite tests/feedback_tests.gd feedback-tests.log 'FEEDBACK TESTS:'
run_suite tests/qa_improvements_tests.gd qa-improvements-tests.log 'QA IMPROVEMENTS:'
run_suite tests/woodcut_ui_tests.gd woodcut-ui-tests.log 'WOODCUT UI:'
run_suite tests/interaction_feedback_tests.gd interaction-feedback-tests.log 'INTERACTION FEEDBACK:'
run_suite tests/cinematics_tests.gd cinematics-tests.log 'CINEMATICS TESTS:'
run_suite tests/vfx_tests.gd vfx-tests.log 'VFX TESTS:'
run_suite tests/space_experiment_tests.gd space-experiment-tests.log 'SPACE EXPERIMENT TESTS:'
run_suite tests/reward_tests.gd reward-tests.log 'REWARD TESTS:'
run_suite tests/save_tests.gd save-tests.log 'SAVE TESTS:'
run_suite tests/route_tests.gd route-tests.log 'ROUTE TESTS:'
run_suite tests/route_card_tests.gd route-card-tests.log 'ROUTE CARDS:'
run_suite tests/event_tests.gd event-tests.log 'EVENT TESTS:'
run_suite tests/arang_experiment_tests.gd arang-experiment-tests.log 'ARANG EXPERIMENT TESTS:'
run_suite tests/arang_english_ui_tests.gd arang-english-ui.log 'ARANG ENGLISH UI:'
run_suite tests/start_and_next_stage_tests.gd start-next-stage.log 'START AND NEXT STAGE:'
run_suite tests/resolution_save_tests.gd resolution-save-tests.log 'RESOLUTION SAVE TESTS:'
run_suite tests/stage_one_ui_tests.gd stage-one-ui-tests.log 'STAGE ONE UI:'
run_suite tests/hazard_tests.gd hazard-tests.log 'HAZARD TESTS:'
run_suite tests/production_synergy_tests.gd production-synergy-tests.log 'PRODUCTION SYNERGY TESTS:'
run_suite tests/yagwang_experiment_tests.gd yagwang-tests.log 'YAGWANG TESTS:'
mkdir -p "$PROJECT_ROOT/build/save-process"
PROCESS_DIR="$(mktemp -d "$PROJECT_ROOT/build/save-process/run.XXXXXXXX")"
PROCESS_SLOT="$PROCESS_DIR/run.json"
for STEP in write read; do
  if [[ "$STEP" == "write" ]]; then MARKER="WRITE"; else MARKER="READ"; fi
  "$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --quit-after 1800 \
    --script tests/save_process_smoke.gd --log-file "$PROJECT_ROOT/build/logs/save-process-$STEP.log" \
    -- "$PROCESS_SLOT" "$STEP" fixture
  verify_log "$PROJECT_ROOT/build/logs/save-process-$STEP.log" "SAVE PROCESS $MARKER: PASS"
done
run_suite tests/ui_smoke.gd ui-smoke.log 'UI SMOKE: PASS'
run_suite tests/reward_ui_smoke.gd reward-ui.log 'REWARD UI: PASS'
run_suite tests/save_ui_smoke.gd save-ui.log 'SAVE UI: PASS'
run_suite tests/route_ui_smoke.gd route-ui.log 'ROUTE UI: PASS'
run_suite tests/guide_ui_smoke.gd guide-ui.log 'GUIDE UI: PASS'
run_suite tests/story_ui_smoke.gd story-ui.log 'STORY UI: PASS'
run_suite tests/event_ui_smoke.gd event-ui.log 'EVENT UI: PASS'
