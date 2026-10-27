#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

TEMPLATE_DIR="$PROJECT_ROOT/.tools/templates"
if [[ ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" || ! -f "$TEMPLATE_DIR/windows_debug_x86_64.exe" || ! -f "$TEMPLATE_DIR/version.txt" ]]; then
  echo 'Windows 템플릿이 없습니다. README의 내보내기 준비 절차를 실행하세요.' >&2
  exit 1
fi
if [[ "$(cat "$TEMPLATE_DIR/version.txt")" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo '내보내기 템플릿과 엔진 버전이 다릅니다.' >&2
  exit 1
fi
bash "$PROJECT_ROOT/scripts/check.sh"
mkdir -p "$PROJECT_ROOT/build/windows"
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --export-release 'Windows Desktop' \
  "$PROJECT_ROOT/build/windows/JeoseungBundle.exe" \
  --log-file "$PROJECT_ROOT/build/logs/windows-export.log"
# A standalone pack catches omitted JSON/schema files without requiring Windows.
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" --export-pack 'Windows Desktop' \
  "$PROJECT_ROOT/build/content-smoke.pck" --log-file "$PROJECT_ROOT/build/logs/content-export.log"
mkdir -p "$PROJECT_ROOT/build/export-runtime"
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/build/export-runtime" \
  --main-pack "$PROJECT_ROOT/build/content-smoke.pck" --quit-after 1800 \
  --script "$PROJECT_ROOT/game/tests/export_content_smoke.gd" \
  --log-file "$PROJECT_ROOT/build/logs/export-content-smoke.log"
python3 - "$PROJECT_ROOT/build/logs/export-content-smoke.log" <<'PYLOG'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
if 'ERROR:' in text or 'EXPORT CONTENT: PASS' not in text:
    raise SystemExit('Exported content validation failed.')
PYLOG
python3 "$PROJECT_ROOT/scripts/package.py"
