# 저승 보따리

초보 한국 저승사자가 퇴마 도구와 망자의 유품을 함께 꾸리는 인벤토리 퍼즐 로그라이트. Godot 기반으로 Steam에 먼저 출시하고, 출시 반응을 확인한 뒤 iOS/Android 이식을 판단한다. 1인 파트타임 개발을 전제로 한다.

현재 버전은 **0.10.0 유품 사건 프로토타입**이다. 기존 아이템 12종 중 7개를 가지고 시작해, 첫 두 전투 후 후보 3개 중 1개를 보상으로 고른다. 선택한 보상을 보따리에 시험 배치하고 확정한 뒤 다음 길목으로 이동한다. 전투·보상·배치가 확정될 때 자동 저장하고 다음 실행에서 이어간다. 아이템·효과·보상 후보는 CSV/JSON으로 관리한다. 전투 판정과 Action Queue 재생을 분리하며, 재생 중에는 다음 행동과 배치를 잠근다. 현재 단계에 맞는 길잡이가 배치·전투·보상·경로 선택을 안내한다. 첫 출장의 짧은 사연은 길목 진행에 따라 단계적으로 기록된다. 첫 보상 뒤 유품을 챙기거나 남겨두는 사건을 만나며, 두 번째 만남에서 당시 보따리에 유품을 넣었는지에 따라 반응이 달라진다. 이어서 두 길 중 하나를 선택하면 나머지 두 적의 순서가 바뀐다. 배경·캐릭터·아이템에는 정적인 레트로 픽셀 시안을 적용했다. 최종 아트·애니메이션·사운드와 추가 사연 선택지는 후속 단계다.

## 실행

1. **Godot 4.7.2 stable** 표준 버전을 준비한다. GDScript 프로젝트이므로 .NET 버전은 필요 없다.
2. [game/project.godot](game/project.godot)을 가져오고 **F5**로 실행한다.
3. macOS/Linux에서는 저장소 루트에서 `bash scripts/run.sh`로도 실행할 수 있다.

다른 위치에 설치했다면 `GODOT_BIN='/설치/경로/Godot' bash scripts/run.sh`로 경로를 지정한다. 스크립트는 `.godot-version`과 엔진 버전이 맞는지 검사한다. Windows에서는 Godot 편집기로 실행하거나 아래 ZIP을 풀고 EXE를 실행한다.

- 로컬 Windows 패키지: `build/JeoseungBundle-prototype-0.10.0-windows.zip`
- 로그: `build/logs/`
- 개발 환경: macOS arm64, Compatibility 렌더러, 1280×720 기준.
- Windows x86_64 교차 내보내기는 가능하다. **Windows 실기기 실행은 아직 미검증**이다.

## 조작과 첫 플레이

| 조작 | 기능 |
|---|---|
| 유품 사건에서 챙기기 → 배치 → 확정 / 그 자리에 두기 | 다음 만남의 반응 선택 |
| 상단 사연 버튼 / 화면 가운데 사연 카드 | 현재까지 확인한 사연 열기 |
| 상단 길잡이 버튼 | 현재 단계 안내 열기·닫기 |
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
| 승리 후 아래 보상 카드 클릭 | 후보 1개를 선택. 보관대에 시험 배치할 물건이 생김 |
| 선택한 보상을 보따리에 배치 → 보상 확정 | 해당 물건을 획득. 다음 길목 이동 가능 |
| 다른 보상 카드 / 보상 받지 않기 | 확정 전 후보 변경 / 보상 건너뛰기 |
| 첫 보상 후 갈림길 카드 | 다음 적과 행동을 비교해 경로 선택 |
| 게임 종료 후 재실행 | 마지막으로 확정된 상태 자동 이어하기 |

봉인부를 사인검 옆으로 옮기면 공격이 **6 → 8**, 옥가락지를 혼백등 옆으로 옮기면 가호가 **0 → 4**로 바뀐다. 상하좌우만 인접으로 계산한다. 배치 미리보기와 선택한 물건의 상세 정보에서 결과와 원인을 확인할 수 있다.

매 턴 기력은 3이며 각 물건은 한 번만 사용할 수 있다. 전투 중에는 배치를 잠근다. 전투 승리 시 체력을 최대 4 회복한다. 첫 보상은 오라·짚신·작은 동경, 두 번째 보상은 적패지·남겨진 엽전·작은 약과 중 하나다. 후보는 고정된 데이터이며 재추첨하지 않는다. 마지막 길목은 추가 보상 없이 인도를 마친다.

보상이 차지할 공간은 기존 물건을 꺼내 확보할 수 있다. 확정 전 후보를 바꾸면 시험 중인 보상만 교체하고 기존 물건의 재배치는 유지한다. 후보 변경·확정·건너뛰기는 배치 되돌리기의 경계다. 확정 후에는 다른 후보로 바꿀 수 없다. 현재 보관대의 기존 물건은 다음 전투에도 유지하며, 판매·버리기·보관대 용량 제한은 아직 없다. 자세한 상태 계약은 [보상 흐름](docs/reward-flow.md)에 있다.

저장은 `user://saves/run.json`과 이전 정상본에 남는다. 연출 중 종료해도 이미 확정된 결과로 이어지며, 저장 실패 시 해당 행동은 적용하지 않는다. 저장이 손상되면 이전 정상본을 시도하고 최근 행동이 누락될 수 있음을 알린다. 저장 버전이나 콘텐츠가 바뀌면 자동 혼합하지 않으며, 기존 파일을 보관한 뒤 새로 시작할 수 있다. 경로·복구·잠금 주의사항은 [저장 시스템](docs/save-system.md)에 있다.

사연은 진행 상태를 읽기만 하므로 기존 저장을 바꾸지 않는다. 단계별 문구는 `content/source/story.csv`에서 편집하고 `python3 scripts/import-story.py`로 반영한다. [사연 데이터와 표시](docs/story-flow.md)

## 밸런싱 데이터 반영

`outputs/data-driven-content/balance-template.xlsx`를 Google Sheets로 가져와 수치를 조정한다. 각 데이터 탭을 CSV로 내려받아 `content/source/`에 놓는다.

```bash
bash scripts/import-content.sh
bash scripts/check.sh
```

아이템 수치·태그·형태·비용·횟수·효과 조합과 적 의도·초기 배치를 코드 수정 없이 바꿀 수 있다. 지원하는 효과 어휘와 새 아이템 추가 절차는 [데이터 파이프라인](docs/data-pipeline.md)에 있다.

동일한 기존 콘텐츠의 0.6 저장은 원래 길목 순서를 유지하며 이어진다. 그 밖에 콘텐츠 데이터를 바꾸면 저장 당시의 콘텐츠 해시가 달라진다. 기존 런을 자동으로 이전하지 않으므로, 게임에서 기존 파일을 보관한 뒤 새 런을 시작하거나 해당 저장과 일치하는 콘텐츠를 사용한다.

## 검사와 Windows 빌드

```bash
bash scripts/check.sh
```

구조 경계, 리소스 가져오기, 콘텐츠 스키마·복합 효과, 기존 규칙, 연쇄 효과, Action Queue·취소, 보상·저장 트랜잭션, 별도 프로세스 이어하기와 길잡이 포함 UI 통합 검사를 순서대로 실행한다. 실패하면 0이 아닌 종료 코드를 반환한다. UI 검사는 보드·보관대 드래그·회전 취소·직접 사용·보상 확정·저장 복구·1024×576/720p/1080p 컨트롤 경계를 확인한다. 실제 운영체제에서의 마우스·키보드·화면 배율 검증은 별도다.

Windows 빌드에는 Python 3와 같은 버전의 공식 export template가 필요하다. [Godot 4.7.2 공식 다운로드](https://godotengine.org/download/archive/4.7.2-stable/)에서 `export_templates.tpz`를 준비한 뒤 실행한다.

```bash
python3 scripts/extract-templates.py /다운로드/경로/export_templates.tpz
bash scripts/export-windows.sh
```

`extract-templates.py`는 버전을 확인한 뒤 Windows x86_64 템플릿 두 개만 `.tools/templates/`에 추출한다. 빌드 스크립트는 검사를 통과한 뒤 PCK를 포함한 EXE와 라이선스·조작 안내를 묶어 ZIP으로 만든다. 업로드·Steam 등록·공개는 수행하지 않는다. 이 작업 환경에는 템플릿이 준비되어 있다.

`.tools/`, `build/`, `game/.godot/`는 Git에서 제외한다. 원본 글꼴·라이선스·Resource·Godot UID는 관리 대상이다. 원격 저장소는 [soonhankwon/k-grim-reaper](https://github.com/soonhankwon/k-grim-reaper)다. 로컬 작업본 스냅샷은 `build/source-snapshot-0.10.0-2026-10-27.zip`에 별도로 보관한다.

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
- [유품 사건](docs/event-flow.md): 선택·배치·후속 반응·저장과 데이터 계약.
- [사연 데이터와 표시](docs/story-flow.md): 첫 인도 사연, CSV 가져오기와 기록 공개 기준.
- [첫 플레이 길잡이](docs/first-play-guide.md): 단계별 안내·표시 우선순위·검증.
- [경로 흐름](docs/route-flow.md): 갈림길 선택·저장 이전·데이터 계약.
- [아트 참고](docs/art-reference.md): 실제 게임 화면 참고와 현재 픽셀 시안의 범위.
- [보상 흐름](docs/reward-flow.md): 후보 선택·시험 배치·확정·건너뛰기와 상태 전환.
- [저장 시스템](docs/save-system.md): 자동 저장·복구·콘텐츠 호환과 저장 실패 처리.
- [UI 구성](docs/ui-layout.md): 참고 화면, 배치·전투 조작, 표현 규칙.
- [전투 아키텍처](docs/combat-architecture.md): 순수 판정, 원자적 커밋, 순차 재생, 연쇄·취소·복구 규칙.
- [개발 플랜](docs/development-plan.md): 마일스톤과 완료 기준.
- [개발 진행 기록](docs/progress.md): 구현 범위, 검증 근거, 다음 작업.
- [프로토타입 플레이 테스트](docs/prototype-playtest.md): Windows 확인과 M2 외부 관찰 양식.
- [게임 설계](docs/game-design-v0.1.md): 이야기·규칙·아트·PC와 후속 모바일 방향.
- [저승사자 참고](docs/lore-reference.md): 전승과 창작의 구분.
- [외부 자원 고지](THIRD_PARTY_NOTICES.md).
