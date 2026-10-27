#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_GODOT_VERSION="$(cat "$PROJECT_ROOT/.godot-version")"
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot4)"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  else
    echo 'Godot를 찾을 수 없습니다. GODOT_BIN에 실행 파일 경로를 지정하세요.' >&2
    exit 1
  fi
fi
ACTUAL_GODOT_VERSION="$("$GODOT_BIN" --version)"
case "$ACTUAL_GODOT_VERSION" in
  "$EXPECTED_GODOT_VERSION"|"$EXPECTED_GODOT_VERSION".*) ;;
  *) echo "Godot 버전 불일치: 필요 $EXPECTED_GODOT_VERSION, 현재 $ACTUAL_GODOT_VERSION" >&2; exit 1 ;;
esac
mkdir -p "$PROJECT_ROOT/build/logs"
