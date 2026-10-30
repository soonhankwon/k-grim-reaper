# 민화·목판화 픽셀 아트 방향 — 시안 v1

민화의 선명한 색면과 책가도 구성, 목판화의 먹선, 수묵화의 여백을 조선풍 저승 인벤토리 퍼즐의 화면 언어로 사용한다. 이 문서는 제작 가설이며 최종 에셋 승인이나 역사적 복식 재현의 근거가 아니다. 기존 소지품과 복식은 [참고 노트](lore-reference.md)를 별도로 확인한다.

## 목판화 UI 시안

갈림길 카드에는 기존 적 아틀스의 초상, 체력, 다음 행동의 검·방패·회복 아이콘과 수치를 표시한다. 반격 조건과 횟수 제한도 카드 안에 남기며, 긴 내용은 스크롤·툴팁으로 확인한다. `game/data/presentation/route-art.json`이 경로 ID와 대숲·연못 실루엣을 연결하고, 정의되지 않은 경로에는 중립 배경을 사용한다. 그림과 아이콘은 표시 전용이며 경로 선택·전투 규칙이나 저장 해시를 바꾸지 않는다.

보따리, 이야기·안내·선택 창에 먹선, 나뭇결과 금속 못을 표현한 32×32 텍스처의 9패치를 사용한다. 조각 패턴은 코드에서 결정적으로 생성하며 가운데와 변은 타일링한다. 버튼은 나무 현판, 주요 행동은 붉은 옻칠 현판으로 구분한다. 마우스와 키보드 포커스의 짧은 탄성은 취소 가능한 Action Queue 명령이 소유한다.

화면은 1280×720 논리 뷰포트에 그린다. 본문 글자 크기와 여백은 기존 레이아웃을 따른다. 시작 화면과 게임 UI는 가독성을 위해 안티앨리어싱된 Noto Sans KR을 사용한다. 기존 픽셀 글꼴과 라이선스는 `game/assets/fonts/`에 보존한다.

뷰포트는 16:9 비율을 유지하며 창에 맞춰 소수 배율로 확대·축소한다. 1024×576, 1280×720, 1920×1080 창에서 각각 0.8배, 1배, 1.5배로 표시하며, 비율이 다른 창에는 필요한 만큼만 여백을 둔다. 창 크기별 버튼·드래그·스크롤 좌표는 자동 검사하며 실제 사용자 가독성 및 Windows 실기기 검증은 별도다.

기존 12개 아이템은 칸당 32×32px 크기의 `items-360-v1.png`로, 기존 차사와 적은 75×66px 전투 표시 영역에 맞춘 `actors-360-v1.png`로 정리했다. 원본 그림의 영역을 nearest 방식으로 축소한 시안이므로 수작업 픽셀 정리와 제한 팔레트 검증을 완료했다는 뜻은 아니다. 원본과 변환 도구 `game/tools/bake_items_360.gd`, `game/tools/bake_actors_360.gd`를 보존한다. 이벤트·보스 컷신의 확대 일러스트와 별도 실험 에셋은 기존 원본을 사용한다.

## 화면의 명도 계층

1. 원경·중경: 청묵과 어두운 갈색 실루엣, 넓은 안개 여백. 배경 팔레트는 우선 HSV 채도 15% 이하를 목표로 정하되 어두운 색에서 판독되는지 실제로 확인한다. 도깨비불·청사초롱 등 소수의 국소 조명만 쓴다.
2. 보따리·슬롯: 어두운 배경보다 밝은 천·한지·목재 중간 명도. 아이템이 닿는 격자선은 분명하게 두고 빈 칸의 장식은 억제한다.
3. 아이템·핵심 정보: 배경보다 대비가 높은 한지색, 주홍, 옥색, 금빛을 사용한다. 같은 역할의 색은 절제하고 대상·설명은 색 외의 형태와 글로도 전달한다.
4. 인물·적: 보따리보다 조용하지만 배경과 구별되는 실루엣. 갓·도포와 혼령의 외곽을 작은 화면에서 확인한다.

후보 색은 먹선 `#161b20`, 청묵 `#252a30`, 안개 `#394047`, 한지 `#c9b79b`, 주홍 `#b64e3b`, 옥색 `#56a99a`, 금색 `#d7aa62`다. 출발점이며 전체 24~32색과 실제 대비는 기준 에셋을 만든 뒤 조정한다. 조명·안개가 격자·문자와 겹쳐 정보를 숨기지 않게 한다.

## 스프라이트와 구도

- 32×32 단일 칸을 우선 기준으로 잡고, 다칸은 32px 배수 캔버스와 같은 픽셀 밀도를 사용한다. 먼저 검은 실루엣만으로 구분한 뒤 내부 색면을 그린다.
- 공통 먹색의 1px 선을 기반으로 바깥 선이나 꺾이는 부분에 선택적으로 2px 이상의 판화 같은 무게를 준다. 모든 선에 노이즈를 넣지 않고 손잡이·구멍 등은 뭉개지지 않도록 한다.
- 보따리의 실제 5×4 격자는 정면으로 유지한다. 책가도의 선반·서랍 모티프나 평면적 시점은 화면 주변, 보상과 상점의 구도에 활용한다. 보상·상점용 별도 일러스트는 아직 제작하지 않았다.
- 한 화면에 주인공·기존 적 1종·기존 아이템 6개·배경·보따리를 맞춰 비교한다. 720p/1080p와 최소 창, 흑백 및 실루엣에서도 격자와 아이템 종류가 읽히는지 확인한다. 인지 시간 목표는 사용자 실험 전 확정하지 않는다.

## 이번 작업과 남은 일

`art-source/concepts/minhwa-woodcut-screen-v1.png`는 내장 이미지 생성기로 만든 **분위기·명도 검토용 한 장**이다. 픽셀 격자·정확한 5×4 칸·기존 인물과 물건의 실루엣 및 화면 UI는 보장하지 않는다. 독립 32×32 원본이나 잘라서 쓸 아틀스가 아니다. 특히 그림 속 낫·인물·격자 칸 수는 현재 콘텐츠와 다를 수 있으며 게임 규칙을 바꾸지 않는다. 생성 프롬프트의 핵심: "Joseon minhwa and Korean woodblock pixel-art game screen; dark desaturated ink-wash background, centered cloth inventory, six high-contrast recognizable items, novice grim reaper and pale spirit, no text".

0.12.0에는 이 방향을 반영해 새 수묵 산길 배경, 기존 아이템 12종과 기존 차사·적 세 명의 이미지 아틀스를 실제 게임에 연결했다. 보따리의 틀·슬롯도 한지와 먹빛 계열로 조정했다. `build/turn-preview-screen.png`는 실제 Godot 렌더 결과다. 이전 이미지는 저장소에 보관하고 출시 패키지에서 제외한다.

이미지 생성 결과물은 고해상도 비트맵으로 nearest 필터를 사용한다. 엄밀한 32px 픽셀 격자·24~32색 팔레트·배경 채도 15% 준수 또는 애니메이션 제작을 보장하지 않으며 최종 에셋 승인이 아니다. 앞으로 편집 가능한 저해상도 원본으로 정리하고 실루엣·광원·팔레트와 제작 시간을 확인한다. 외부 플레이어의 판독성과 Windows 렌더는 아직 검증하지 않았다.

## 제작 원본과 프롬프트

내장 이미지 생성기를 사용했다. 원본은 게임에서 직접 사용하는 `game/assets/visuals/afterlife-ink-v2.png`, `items-minhwa-v2.png`, `actors-woodcut-v2.png`다. 아틀스는 코드를 통해 분리 표시하며 원본을 잘라 저장하지 않았다. 캐릭터는 기존 `actors-retro-v1.png`를 입력으로 사용해 네 인물의 위치·정체성을 유지했다. 사용한 프롬프트:

- 배경: "Use case: stylized-concept. Asset type: actual 2D game background texture ONLY, landscape 16:9, original pixel art for a Korean Joseon afterlife inventory puzzle. One single continuous dark atmospheric Joseon mountain pass at night with distant silhouettes of tiled hanok roofs and rocky hills in layers of low saturation charcoal ink, charcoal blue-grey, dark gray-brown. Pixel-cluster ink wash mist and large quiet negative space across the center; faint teal goblin fire near the far sides only, subtle black woodcut edges. Everything must stay dark with limited muted contrast so foreground UI and icons are easily readable. Crisp large pixel blocks and restricted palette, very minimal dithering, no gradients, no photorealism, no painterly look. Scene should have a low flat quiet dark ground line near the bottom for sprites in front. No giant moon, no characters, no objects in foreground, no inventory, no text, no symbols, no UI, no frame, no watermark. This is a single original in-game scenery image, not a screenshot or concept sheet."
- 아이템: "Use case: stylized-concept. Asset type: production sprite atlas for an original Joseon Korean grim reaper inventory game. 12 separate isolated item pixel sprites on a genuinely TRANSPARENT background, arranged in a strictly regular 4 column by 3 row grid with equal sized cells and generous transparent margins; exactly one object centered in each cell, no objects crossing cell boundaries, no text, no grid, no labels, no drop shadows. Keep each object fully separated with clear empty transparent space between neighbors. Grid order: top row 1 long ceremonial straight sword vertically upright tip down, 2 narrow parchment talisman with red seal, 3 traditional small lantern with cyan glow, 4 jade circular ring; middle row 5 black Joseon gat hat, 6 traditional brass handbell, 7 round honey yakgwa pastry, 8 curled hemp rope; bottom row 9 straw sandals pair, 10 red-edged official document scroll, 11 small bundle of square-hole brass coins, 12 round Korean bronze hand mirror. Each object recognizable from silhouette, visible thick ink-dark woodcut pixel outline, flat bold color shapes, restrained folk-art crimson jade old gold parchment, consistent angular pixel cluster density. Pure crisp retro pixel art drawn as 32x32 style icons, no smooth brushwork, no blur, no 3D, no photorealism, no background."
- 인물: "Use case: style-transfer. Edit target: this 2x2 sheet of four existing Korean pixel game characters. Preserve the exact identity and quadrant of each existing character: top left novice grim reaper in Joseon gat and dark blue robe carrying a paper scroll facing right; top right small pale hooded mask spirit with red trailing ribbon facing left; bottom left straw-rope bundle spirit with red wooden mask and twine body facing left; bottom right dark armored sentinel with black gat/helmet, one cyan glowing eye, red straps and a tall dark staff or polearm facing left. Do not change a straw rope creature into a lantern or the armored sentinel into a ghost. Replace the pixel art with a cohesive woodcut and Joseon folk painting interpretation: dark ink outlines, restricted parchment jade vermilion and brown, strong legible silhouettes, authentic 16-bit 2D crisp angular pixel clusters, no smooth painterly detail, same four separate characters only. Equal 2 by 2 quadrant layout with generous empty transparent padding between all figures, full body visible, genuinely transparent background, no text, no scenery, no borders, no shadows."

## 0.14.0 아랑 스테이지 제작 기록

내장 이미지 생성기를 사용해 기존 아틀스·수묵 배경을 참조 이미지로 제공했다. 게임이 사용하는 생성 결과는 `game/assets/visuals/arang-actors-v1.png`, `arang-office-v1.png`, `arang-bamboo-v1.png`이며 아틀스 영역과 대면별 배경은 `game/data/presentation/retro-art.json`에서 연결한다. 포졸과 아랑은 원본 한 장에서 투명 여백을 포함한 영역으로 읽는다. 차사는 기존 그림을 좌우 반전해 두 인물이 서로 마주본다.

생성 프롬프트:

- 인물: “Use case: stylized-concept. Asset type: 2D game enemy sprite sheet. Input image is a style reference only. Create exactly TWO separate full-body enemy sprites on a genuine transparent background, side by side, generously spaced and not touching: left a frightened Joseon-era constable spirit (포졸), blue-black uniform and small traditional military hat, gripping a short spear; right Arang (아랑), dignified young Korean woman ghost in ivory hanbok with long black hair, a subtle red sash, luminous pale cyan ghostly hem. Both face LEFT, no frames, no ground, no text. Match the reference's consistent retro pixel art scale, solid angular ink-black woodcut outline, restrained palette of ink navy, ivory, muted rust red, small teal accents. Clear silhouette; game-ready flat sprites, no perspective, no blur, no antialiasing, no extra characters. Respectful portrait, no gore.”
- 관아: “Use case: stylized-concept. Asset type: wide pixel art in-game background. Input image is style and value hierarchy reference. Reimagine as a nighttime Joseon magistrate's office (동헌) interior: aged dark wooden floor, paper sliding doors, timber beams, a tiny dim blue lantern at the edge. Wide composition, dark desaturated blue ink and charcoal brown, ink wash mist and empty center, light focal details only at far edges, low contrast so a bright inventory UI overlays the center. 2D retro pixel art, crisp angular pixel clusters, Korean woodcut and minhwa sensibility, quiet ghostly suspense, no people, no interface, no text, no bright moon or central lamp.”
- 대숲: “Use case: stylized-concept. Asset type: wide pixel art in-game background. Input image is style and value hierarchy reference. Reimagine as a Joseon-era Miryang bamboo grove at night (죽림): layered dark bamboo silhouettes and fog, faint paper lantern on a distant path at an edge, no buildings, no people. Wide composition, empty center, dark desaturated blue ink and charcoal brown, quiet restrained local lights at far edges, low contrast so bright inventory UI overlays the center. Match reference's retro 2D pixel art, crisp angular pixel clusters, Korean woodcut and ink-wash sensibility; no gradients, no text, no UI, no bright moon.”

원본은 고해상도 생성 결과를 nearest 필터로 표시한 정적 시안이다. 엄밀한 32px 격자와 한정 팔레트, 픽셀 단위 수작업·애니메이션·사운드, Windows 실기기 검증은 아직 필요하다. `build/arang-stage-office.png`와 `build/arang-stage-boss.png`는 Godot 실제 화면에서 확인한 캡처다.

## 야광귀 시제품 — 겨울 마을·야광귀·체

내장 이미지 생성기를 사용했고 기존 아랑 배경, 아랑 캐릭터 아틀스, 아이템 아틀스를 각각 스타일 참고 자료로 제공했다. 원본을 그대로 `game/assets/visuals/yagwang-winter-v1.png`, `yagwang-boss-v1.png`, `yagwang-sieve-v1.png`에 보관하며 마지막 두 그림은 투명 알파를 유지한다. 시제품 카탈로그의 이미지 경로로 연결하며 출시 패키지에는 포함하지 않는다. `build/yagwang-battle-screen.png`는 실제 Godot 전투 화면이다.

사용한 프롬프트:

- 배경: “Use case: stylized-concept. Asset type: actual 2D game background. Input image: style, color hierarchy and composition reference only. Create one original wide landscape pixel-art game background of a snow-covered traditional Joseon thatched-roof village courtyard at night on Lunar New Year's Eve. Dark blue-black ink and gray-brown muted shadows, low-contrast snow in layered silhouettes, fog and quiet empty center for inventory UI. Huts, wooden porches and shed silhouettes at far edges; one tiny warm lantern on one far edge, minimal snowflakes. Low flat dark ground for combat sprites. The foreground gameplay UI is NOT part of the image. Crisp coherent retro pixel clusters, Joseon woodcut and folk-painting look matching the reference. Restrained colors, no huge moon, no characters, no interface, no text, no watermark.”
- 야광귀: “Use case: stylized-concept. Asset type: a single full-body 2D boss sprite for an original Korean folklore game. Input image: style reference only, do not repeat either character. Create one fearsome but non-gory Yagwanggwi shoe-stealing goblin, a lanky one-eyed Korean winter spirit with a small blue goblin flame above its head, elongated limbs, charcoal ink body and a few traditional straw shoes tied around its waist. It faces LEFT toward the player, recognizable in a small 150 x 130 pixel battle area, strong clear silhouette, centered isolated full body with generous transparent margins; entire figure visible, no ground. Match reference style: Joseon retro pixel sprite, thick angular dark woodcut outlines, flat colored pixel clusters, restrained ochre red teal and blue-grey, no anti-aliased smooth painting, no text, no other character, no border. Genuinely transparent background.”
- 체: “Use case: stylized-concept. Asset type: one 2D inventory item sprite for a Korean Joseon folklore game. Input image: style reference only, do not reproduce other objects. Create exactly ONE old traditional Korean hand sieve, a ROUND oak wooden hoop with fine criss-cross woven horsehair mesh showing clearly countable small square holes, front view slightly tilted, with small red fabric tie, immediately recognizable at small icon size. Match reference items: strongly ink-dark woodcut outline, golden brown wood, parchment straw tones with restrained red accent, crisp retro pixel clusters; centered single full item, generous transparent margins, no hands, no ground, no other objects, no grid, no labels, no text. Genuine transparent background.”

고해상도 생성 비트맵을 nearest 필터로 표시하는 시안이며, 엄밀한 16/32px 격자·한정 팔레트·완성된 움직임이나 역사적 복식 고증을 보장하지 않는다. Windows 실기기와 외부 플레이어의 판독성은 미검증이다.
