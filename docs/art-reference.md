# 레트로 픽셀 시안과 화면 참고

## 살펴본 게임 화면

- [Backpack Hero 스크린샷과 플레이 화면](https://www.pcgamer.com/heres-a-whole-roguelike-about-inventory-management/): 커다란 칸별 인벤토리를 화면의 주인공으로 두고, 물건 실루엣과 위치 관계를 먼저 읽게 하는 화면 구성을 참고했다. [공식 Steam 페이지](https://store.steampowered.com/app/1970580/Backpack_Hero/)
- [SANABI 플레이 화면](https://gamewith.jp/gamedb/8755/articles/31389): 어두운 바탕과 청록·따뜻한 조명의 대비, 멀리서도 구분되는 형태를 살펴봤다. [공식 Steam 페이지](https://store.steampowered.com/app/1562700/SANABI/)
- [Moonlighter 인벤토리 화면](https://3secondsgameover.com/e/moonlighter_review): 작은 물건도 테두리와 색 덩어리로 구분하는 접근을 참고했다. [공식 Steam 페이지](https://store.steampowered.com/app/606150/Moonlighter/)

위 게임의 이미지나 스프라이트를 프로젝트에 포함하지 않았다. 화면 구성과 읽기 쉬운 실루엣을 분석해 별도의 한국 저승 배경·차사·귀신·도구로 해석했다.

## 현재 적용 범위

배경 하나, 차사와 기존 적 세 명, 기존 물건 12개를 동일한 어두운 남색·비취색·탁한 적갈색 계열의 굵은 레트로 픽셀풍 **AI 생성 정적 시안**으로 제작해 적용했다. Godot에서 nearest 필터로 표시하고, 아틀스 좌표는 `game/data/presentation/retro-art.json`에서 관리한다. 기존 콘텐츠의 아이콘·캐릭터 ID로 대응하며 없는 ID는 이전 도형 표현을 사용한다. 이미지와 판정·저장 데이터는 분리되어 있다.

현재 시안은 픽셀 밀도·외곽선·물건 읽기 쉬움의 출발점이다. 정밀한 픽셀 그리드 통일, 프레임별 수작업 수정, 이동·공격·피격 애니메이션, 이펙트, 접근성 및 실제 플레이어 검증은 남았다. 최종 아트 확정이나 M3 완료를 의미하지 않는다. 실제 화면은 `build/retro-game-screen.png`에서 확인할 수 있다.
