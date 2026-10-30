# 먹선·컷신·소리 — 연출 시안 0.21.0

전투의 값 판정과 저장을 변경하지 않고, 확정된 이벤트를 `ActionQueue`가 재생하는 동안 화면과 소리를 표시한다. 기존 아이템·적·콘텐츠 밸런스와 콘텐츠 해시는 바꾸지 않는다. 본편에서는 아랑, 별도 무저장 실험에서는 야광귀의 등장 장면을 확인할 수 있다.

- **등장**: `battle_started` 이벤트에서 한지 배경과 레터박스, 인물의 슬라이드, 한 글자씩 나타나는 영어 이명과 붉은 인장을 약 2.4초간 표시한다. 스틸컷 위에는 건너뛰기 버튼이 있다. 연출이 끝나거나 건너뛰면 이미 확정된 전투 상태가 표시된다.
- **회상**: 아랑 사건을 마치는 `event_continue`에서 대숲 정물 화면을 은장도 방향으로 천천히 확대하고 자막과 바람 소리를 표시한다. 현재 1스테이지에는 2스테이지 지도가 연결되어 있지 않아 완료 화면으로 이어진다.
- **전환과 턴**: 등장·회상 스틸컷의 앞뒤에 먹물이 번지는 셰이더를 적용한다. 턴 시작 이벤트에는 짧은 붉은 인장과 떨림이 표시된다. 이것이 모든 화면 이동에 적용된 공통 전환은 아니다.
- **처치**: 적에게 가한 실제 체력 피해가 적 체력을 0으로 만든 이벤트에 먹선과 픽셀 파편, 노이즈 기반 알파 디졸브를 적용한다. 충돌 직후 재생 Tween만 0.06초 멈추며 전역 시간이나 판정은 멈추지 않는다. 현재 게임에 치명타 판정은 없으므로 일반 치명타 연출은 없다.
- **한기와 시선**: 새 한기 지점이 준비되면 해당 칸의 서리 선이 테두리를 따라 나타난다. 야광귀 실험에서는 표적 이벤트에 맞춰 붉은 곡선이 야광귀와 표적을 연결하고, 강탈되면 사라진다. 색상뿐 아니라 기존 `!` 표식과 텍스트도 유지한다.
- **소리**: 직접 합성한 짧은 피격음·방어음·북 인장음·바람·배치 스냅 시안을 사용한다. 게임 왼쪽 아래 버튼으로 소리를 끌 수 있다. 설정은 현재 실행 동안만 유지된다. 오디오 믹싱·실기기 음량 검수는 남아 있다.

## 안전한 재생과 자료

`BattleSession.submit()`이 판정·저장·커밋한 뒤 기존 이벤트마다 `CombatEventCommand`를 실행한다. 커맨드가 생성한 Tween이 진행도·타격 시점·짧은 정지 시간을 소유한다. `SceneCinematics`, `RoadView`, 보드와 소리는 표시 스냅샷·이벤트만 소비한다. 건너뛰기·재시작·타임아웃·장면 종료 시 Tween을 취소하고 컷신·서리 진행·소리를 초기화한다. 이어하기는 저장된 최종 상태만 표시하고 컷신이나 판정을 다시 실행하지 않는다.

등장 이명과 회상 이미지·자막·초점은 `game/data/presentation/cinematics.json`에 둔다. 아이템 정의나 판정에 특정 보스 ID를 넣지 않는다. 사진형 비디오나 새 싱글톤 없이 현재 게임 화면에 붙은 재생용 뷰를 재사용한다. 오디오 원본은 `game/assets/audio/`, 재생산 스크립트는 `scripts/generate-sfx.py`다. 외부 음원 샘플을 사용하지 않았다.

먹·얼음·불티·엽전 파편은 64×64 공유 아틀라스를 쓰는 GPU 파티클이다. 서리는 현재 코드로 그리는 시안이며 4방향 서리 스프라이트 시트는 아직 없다. 화면 흔들림은 화면 전체가 아니라 턴 인장의 작은 움직임이다. 배경 스틸컷은 카메라 노드가 아니라 텍스처를 이동·확대한다. 외부 플레이어의 연출 피로, Windows 실기기, 실제 스피커/헤드폰 음량은 검증하지 않았다.

## 공유 파티클 아틀라스

`game/assets/visuals/vfx-particles-v1.png`는 투명 64×64 텍스처이며 위쪽 16×16 칸 네 개에 먹·얼음·불·엽전 조각을 담는다. `game/tools/generate_vfx_atlas.gd`의 사각 픽셀 정의로 재생산할 수 있다. 적 처치에는 먹, 새 한기에는 얼음, 혼백등의 방어에는 불티, 보상 확정에는 엽전 조각을 사용한다. 기존 엽전 아이템의 방어에도 엽전 조각을 지정했으나 현재 본편에서 해당 아이템은 획득할 수 없다. 아이템이나 보상 후보를 추가하지 않았다.

`GPUParticles2D`는 고정 시드와 일회성 방출을 사용하며 자체 시간 배율을 0으로 유지한다. 각 이벤트의 연출이 진행도를 전달할 때만 파티클 처리 시간을 요청한다. 따라서 0.06초 정지 중에는 진행하지 않고, 건너뛰기·재시작 시 표시와 시간 상태를 초기화한다. 연속 이벤트에서는 이전 파편을 지운 뒤 다시 시작한다. GPU 파티클은 시각 효과이며 판정과 저장에는 사용하지 않는다. 관련 동작: [Godot GPUParticles2D 문서](https://docs.godotengine.org/en/latest/classes/class_gpuparticles2d.html).

## 아랑 회상 스틸컷

내장 이미지 생성기로 기존 `arang-bamboo-v1.png`를 스타일 참고로 사용했다. 결과는 `game/assets/visuals/arang-memory-v1.png`에 보관한다. 프롬프트:

“Use case: stylized-concept. Asset type: a single wide 2D retro pixel-art narrative still for a Korean Joseon folklore game; reference image establishes the muted ink palette and pixel art style only. In a dark bamboo grove at night, a few subtle dark vermilion stains on earth lead to one small Korean silver ornamental dagger lying near the lower-right center; the blade catches a faint cold light. Bamboo stalks fade into desaturated ink-blue mist with deep quiet negative space and a low flat ground. Solemn, respectful and suggestive, no bodies, no violence, no people. Strong angular woodcut ink contours, crisp restrained retro pixel clusters, desaturated background and localized subtle highlights; suitable for a slow camera zoom. No text, no frame, no UI, no watermark, no photorealism.”

연출별 프로필·효과 ID·발동 조건·위치는 `game/data/presentation/vfx.json`에서 정의하고, `VfxPlayer`는 표시 이벤트와 스냅샷을 읽어 단일 방출기를 재설정한다. 이 파일은 전투 콘텐츠와 별도의 시각 설정이며 콘텐츠 해시나 저장 상태를 바꾸지 않는다.

자동 검사는 `game/tests/vfx_tests.gd`, `game/tests/cinematics_tests.gd`와 `bash scripts/check.sh`, 실제 화면 캡처는 `game/tests/cinematics_capture.gd`를 사용한다.

## QA 반영: 공격·방어 연출과 영문 서체

일반 체력 피해에도 먹선·밝은 사선·파편과 0.035초의 재생 정지를 적용한다. 치명적인 적 처치는 기존 0.06초를 사용한다. 방어 증가와 흡수 피해는 청록 방패 문양과 별도 방어음을 표시한다. 숫자는 캐릭터 위에 그려 실제 표시 스냅샷과 같은 시점에 나타난다. 표시는 Action Queue의 진행도에 종속되며 판정이나 저장을 수정하지 않는다. 일반 피격·방어·완전 차단과 건너뛰기 검사는 `game/tests/qa_improvements_tests.gd`에 있다.

출시 UI·콘텐츠·사연과 오류 문구는 영어를 사용한다. 본문은 Galmuri14, 버튼과 주요 제목은 Galmuri11 Bold를 사용하고 누락 글리프에는 Noto Sans KR을 대체 폰트로 둔다. Galmuri는 Lee Minseo의 SIL OFL 1.1 폰트이며 출처와 라이선스는 `THIRD_PARTY_NOTICES.md`에 수록한다. 실제 영어 문안의 원어민 검수와 Windows 실행 검증은 남았다.
