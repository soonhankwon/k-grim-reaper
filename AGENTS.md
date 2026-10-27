# 프로젝트 작업 규칙

<!-- postman-cli:installation:start -->
Postman CLI is installed on this device, and can be used for API Engineering work.
<!-- postman-cli:installation:end -->

## 전투 상태와 연출의 경계

- 변경 전에 `docs/combat-architecture.md`를 읽는다. 게임에서의 전투 명령 진입점은 `BattleSession.submit()` 하나다.
- `CombatSimulator`와 `InventoryRules`는 값 데이터만 계산한다. Node, SceneTree, Tween, 타이머, 신호, 시간·전역 난수, UI 참조를 넣지 않는다.
- 연쇄 효과는 순수 판정의 FIFO에서 처리하고 원인 ID가 있는 이벤트로 기록한다. 신호 콜백이나 아이템 노드에서 다른 효과를 직접 발동하지 않는다.
- 판정은 복사본에서 끝까지 수행하고 성공 결과만 한 번 커밋한다. 재생이 전투 상태를 수정하거나 다시 판정해서는 안 된다.
- UI는 `display_snapshot()`을 읽는다. `state_snapshot()`은 저장·디버그·검증 용도다. 최종 체력·소모 결과를 연출 전에 화면에 섞어 표시하지 않는다.
- 시간 흐름은 `ActionQueue`와 `ActionCommand`가 소유한다. 런타임 스크립트에 `await` 체인을 추가하지 않는다. `execute()`는 즉시 반환하고, 완료는 `finish()`로 알리며, `cancel()`에서 소유한 Tween 등을 정리한다.
- 새 연출은 즉시 완료·완료 누락·중복 완료·건너뛰기·재시작·장면 종료에 안전해야 한다. 새 트리거는 결정적 순서, 행동당 횟수, 연쇄 상한, 사망 시점을 함께 검증한다.
- 변경 후 `bash scripts/check.sh`를 실행한다. 경계 검사를 우회하거나 완화해 통과시키지 말고, 의도한 설계 변경이면 문서와 관련 검증을 함께 수정한다.

현재 에셋·적·아이템 수를 임의로 늘리지 않는다. 테스트용 반사 피해·반응 방어는 출시 콘텐츠의 추가와 구분한다.

## 콘텐츠와 엔진의 경계

- 콘텐츠 변경 전에 `docs/data-pipeline.md`를 읽는다. 수치·효과 조합·태그·초기 배치·적 의도는 `content/source/`와 검증된 `game/data/content/catalog.json`에 둔다.
- `ItemData`와 `EffectUnit`은 필드만 가진다. 함수·신호·Callable을 추가하지 않는다.
- `EffectApplier`와 `GridRules`도 순수 값 계산이다. 아이템 ID·이름·특정 태그를 코드 조건에 넣지 않는다.
- 새 수치나 기존 효과의 조합에는 엔진 분기를 추가하지 않는다. 새 연산/트리거를 도입할 때만 스키마·엔진·문서·검증을 함께 수정한다.
- 밸런싱은 CSV 원본 수정 → `bash scripts/import-content.sh` → `bash scripts/check.sh` 순서로 반영한다. JSON 입력도 같은 로더를 통과해야 한다.
- 회귀 테스트의 고정 밸런스는 `game/tests/fixtures/baseline.json`이다. 출시 수치 변경을 통과시키기 위해 이 픽스처를 함께 고치지 않는다. 출시 카탈로그 검증과 고정 규칙 검증을 구분한다.
