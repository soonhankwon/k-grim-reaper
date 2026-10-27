# 저승 보따리

초보 한국 저승사자가 퇴마 도구와 망자의 유품을 함께 꾸리는 인벤토리 퍼즐 로그라이트. Godot 기반으로 Steam에 먼저 출시하고, 출시 반응을 확인한 뒤 iOS/Android 이식을 판단한다. 1인 파트타임 개발을 전제로 한다.

현재 버전은 **0.4.0 데이터 기반 프로토타입**이다. 아이템과 효과는 CSV/JSON으로 관리하며, 공통 효과 엔진이 이를 실행한다. 상단 보따리·하단 전투 무대·우측 턴 종료 구도와 아이템 직접 클릭 사용을 적용했다. 전투 판정과 Action Queue 재생을 분리하며, 재생 중에는 다음 행동과 배치를 잠근다. 5×4 보따리, 아이템 12종, 인접 효과, 세 길목의 턴제 전투를 플레이할 수 있다. 최종 픽셀 에셋·사운드·경로·스토리·저장은 후속 단계다. 종료하면 진행이 초기화된다.

## 실행

1. **Godot 4.7.2 stable** 표준 버전을 준비한다. GDScript 프로젝트이므로 .NET 버전은 필요 없다.
2. [game/project.godot](game/project.godot)을 가져오고 **F5**로 실행한다.
3. macOS/Linux에서는 저장소 루트에서 `bash scripts/run.sh`로도 실행할 수 있다.

다른 위치에 설치했다면 `GODOT_BIN='/설치/경로/Godot' bash scripts/run.sh`로 경로를 지정한다. 스크립트는 `.godot-version`과 엔진 버전이 맞는지 검사한다. Windows에서는 Godot 편집기로 실행하거나 아래 ZIP을 풀고 EXE를 실행한다.

- 로컬 Windows 패키지: `build/JeoseungBundle-prototype-0.4.0-windows.zip`
- 로그: `build/logs/`
- 개발 환경: macOS arm64, Compatibility 렌더러, 1280×720 기준.
- Windows x86_64 교차 내보내기는 가능하다. **Windows 실기기 실행은 아직 미검증**이다.

## 조작과 첫 플레이

| 조작 | 기능 |
|---|---|
| 보따리 물건 클릭 → 빈칸 클릭 | 선택한 물건 배치 |
| 보따리 안에서 드래그 | 잡은 칸을 기준으로 이동 |
| 보관대에서 드래그 / 클릭 → 빈칸 클릭 | 보관한 물건 넣기 |
| 물건 위에 마우스 올리기 | 상세 효과·인접 보너스 확인 |
| R / 회전 버튼 | 90° 회전 미리보기, 클릭해서 확정 |
| Esc / 보드 우클릭 | 선택·이동·회전 취소 |
| Ctrl+Z / 되돌리기 버튼 | 최근 배치 복구, 최대 30회 |
| 전투 시작 → 보따리 물건 클릭 | 클릭한 아이템 즉시 사용 |
| 연출 건너뛰기 | 확정된 결과로 화면을 맞추고 다음 입력 허용 |
| 턴 종료 | 가호 적용 → 적 의도 실행 → 기력·사용 횟수 회복 |

봉인부를 사인검 옆으로 옮기면 공격이 **6 → 8**, 옥가락지를 혼백등 옆으로 옮기면 가호가 **0 → 4**로 바뀐다. 상하좌우만 인접으로 계산한다. 배치 미리보기와 선택한 물건의 상세 정보에서 결과와 원인을 확인할 수 있다.

매 턴 기력은 3이며 각 물건은 한 번만 사용할 수 있다. 전투 중에는 배치를 잠근다. 전투 승리 시 체력을 최대 4 회복하며 다음 길목 전 자유롭게 정리할 수 있다. 현재는 보상 선택 대신 이 고정 보상으로 짧은 연속 전투를 검증한다.

## 밸런싱 데이터 반영

`outputs/data-driven-content/balance-template.xlsx`를 Google Sheets로 가져와 수치를 조정한다. 각 데이터 탭을 CSV로 내려받아 `content/source/`에 놓는다.

```bash
bash scripts/import-content.sh
bash scripts/check.sh
```

아이템 수치·태그·형태·비용·횟수·효과 조합과 적 의도·초기 배치를 코드 수정 없이 바꿀 수 있다. 지원하는 효과 어휘와 새 아이템 추가 절차는 [데이터 파이프라인](docs/data-pipeline.md)에 있다.

## 검사와 Windows 빌드

```bash
bash scripts/check.sh
```

구조 경계, 리소스 가져오기, 콘텐츠 스키마·복합 효과, 기존 규칙, 연쇄 효과, Action Queue·취소, UI 통합 검사를 순서대로 실행한다. 실패하면 0이 아닌 종료 코드를 반환한다. UI 검사는 보드·보관대 드래그·회전 취소·직접 사용·연속 클릭 잠금·소모 표시·1024×576/720p/1080p 설명 창과 컨트롤 경계를 확인한다. 실제 운영체제에서의 마우스·키보드·화면 배율 검증은 별도다.

Windows 빌드에는 Python 3와 같은 버전의 공식 export template가 필요하다. [Godot 4.7.2 공식 다운로드](https://godotengine.org/download/archive/4.7.2-stable/)에서 `export_templates.tpz`를 준비한 뒤 실행한다.

```bash
python3 scripts/extract-templates.py /다운로드/경로/export_templates.tpz
bash scripts/export-windows.sh
```

`extract-templates.py`는 버전을 확인한 뒤 Windows x86_64 템플릿 두 개만 `.tools/templates/`에 추출한다. 빌드 스크립트는 검사를 통과한 뒤 PCK를 포함한 EXE와 라이선스·조작 안내를 묶어 ZIP으로 만든다. 업로드·Steam 등록·공개는 수행하지 않는다. 이 작업 환경에는 템플릿이 준비되어 있다.

`.tools/`, `build/`, `game/.godot/`는 Git에서 제외한다. 원본 글꼴·라이선스·Resource·Godot UID는 관리 대상이다. 원격 저장소는 [soonhankwon/k-grim-reaper](https://github.com/soonhankwon/k-grim-reaper)다. 로컬 작업본 스냅샷은 `build/source-snapshot-0.4.0-2026-10-27.zip`에 별도로 보관한다.

## 구조

```text
game/scripts/core/  점유·회전·인접 효과·전투 상태 (UI와 분리)
game/scripts/application/ 전투 명령 진입점·입력 잠금
game/scripts/playback/    Action Queue·명령·Tween·표시 상태
game/scripts/ui/    입력·가방/전투 레이아웃·공통 픽셀 아이콘
game/scripts/content/    순수 데이터 Resource·검증·값 변환
game/data/content/       런타임 JSON·스키마
content/source/          기획 원본 CSV·시각 데이터
outputs/data-driven-content/  Google Sheets 가져오기용 밸런싱 템플릿
game/scenes/        시작 화면
game/tests/         규칙 및 UI 통합 검사
game/assets/fonts/ 한국어 글꼴과 이용 조건
scripts/           실행·검사·내보내기·패키지 도구
docs/              설계·진행·테스트 기록
```

## 문서

- [데이터 파이프라인](docs/data-pipeline.md): Google Sheets·CSV/JSON, 효과 조합, 검증, 기존 밸런스와 테스트 분리.
- [UI 구성](docs/ui-layout.md): 참고 화면, 배치·전투 조작, 표현 규칙.
- [전투 아키텍처](docs/combat-architecture.md): 순수 판정, 원자적 커밋, 순차 재생, 연쇄·취소·복구 규칙.
- [개발 플랜](docs/development-plan.md): 마일스톤과 완료 기준.
- [개발 진행 기록](docs/progress.md): 구현 범위, 검증 근거, 다음 작업.
- [프로토타입 플레이 테스트](docs/prototype-playtest.md): Windows 확인과 M2 외부 관찰 양식.
- [게임 설계](docs/game-design-v0.1.md): 이야기·규칙·아트·PC와 후속 모바일 방향.
- [저승사자 참고](docs/lore-reference.md): 전승과 창작의 구분.
- [외부 자원 고지](THIRD_PARTY_NOTICES.md).
