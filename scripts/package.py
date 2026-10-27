"""Package the Windows prototype and its notices; never uploads or publishes."""
from pathlib import Path
import json
import re
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
folder = root / 'build/windows'
version = re.search(r'config/version="([^"]+)"', (root / 'game/project.godot').read_text()).group(1)
content = json.loads((root / 'game/data/content/catalog.json').read_text())
if not (folder / 'JeoseungBundle.exe').is_file():
    raise SystemExit('Export the Windows executable first.')
licenses = folder / 'LICENSES'
licenses.mkdir(exist_ok=True)
shutil.copy2(root / 'game/assets/fonts/OFL.txt', licenses / 'NotoSansKR-OFL.txt')
shutil.copy2(root / 'game/licenses/Godot-LICENSE.txt', licenses / 'Godot-LICENSE.txt')
shutil.copy2(root / 'game/licenses/Godot-COPYRIGHT.txt', licenses / 'Godot-COPYRIGHT.txt')
notices = (root / 'THIRD_PARTY_NOTICES.md').read_text()
notices = notices.replace('game/licenses/', 'LICENSES/').replace('game/assets/fonts/OFL.txt', 'LICENSES/NotoSansKR-OFL.txt')
(folder / 'THIRD_PARTY_NOTICES.md').write_text(notices, encoding='utf-8')
(folder / 'README-KO.txt').write_text(f'''저승 보따리 — 첫 인도 / 데이터 기반 프로토타입 {version}

ZIP 전체를 같은 폴더에 풀고 JeoseungBundle.exe를 실행하세요.
Godot 설치는 필요하지 않습니다. Windows x86_64용입니다.
이 빌드는 macOS에서 교차 내보내기했으며 Windows 실기기 실행은 미검증입니다.

화면 위쪽 보따리에서 물건을 정리하고 아래쪽 전투 무대에서 상태를 확인합니다.
오른쪽 길잡이는 현재 단계의 조작을 설명합니다. 상단 길잡이 버튼으로 숨기거나 다시 열 수 있습니다.
화면 가운데 사연 카드 또는 상단 사연 버튼으로 지금까지의 기록을 확인합니다.
물건을 선택하고 빈칸을 클릭하거나 보따리 안에서 드래그합니다.
R: 회전 미리보기 / Esc 또는 보드 우클릭: 취소 / Ctrl+Z: 배치 되돌리기
보관대 물건은 보따리로 드래그하거나 클릭한 뒤 빈칸에 놓습니다. 전투 중에는 배치를 바꿀 수 없습니다.
전투 시작 후 보따리 안 물건을 클릭하면 바로 사용합니다.
물건 위에 마우스를 올리면 상세 효과를 확인합니다. 우측 버튼으로 턴을 끝냅니다.
행동 결과는 순서대로 재생됩니다. 재생 중에는 다음 입력이 잠기며, 연출 건너뛰기를 사용할 수 있습니다.
기력과 턴당 사용 횟수는 콘텐츠 데이터에 따릅니다. 턴 종료 시 적이 예고한 행동을 합니다.
봉인부를 검 옆에, 옥가락지를 혼백등 옆에 놓고 수치 변화를 살펴보세요.
첫 두 전투 후에는 보상 후보를 선택해 보따리에 배치하고 보상 확정을 누르세요.
확정 전에는 후보 변경과 보상 받지 않기가 가능합니다. 다음 길목에서 획득한 물건을 사용할 수 있습니다.
첫 보상 이후 길가의 유품을 챙기거나 두고 갈 수 있습니다. 챙기려면 보따리에 넣고 확정하세요.
다음 만남에 유품을 보따리에 가지고 있으면 다른 반응과 체력 회복을 얻습니다.
이어지는 갈림길에서 두 경로의 다음 적과 행동을 비교해 선택합니다.

{len(content['items'])}개 아이템 정의와 {len(content['encounters'])}개 길목으로 배치·전투 규칙을 검증하는 연습용 빌드입니다.
진행은 자동 저장되며 다음 실행에서 마지막으로 확정된 상태를 이어갑니다.
콘텐츠가 바뀐 저장은 자동으로 혼합하지 않습니다. 안내에 따라 기존 파일을 보관하고 새로 시작할 수 있습니다.
레트로 픽셀 아트는 정적인 시안입니다. 최종 아트·애니메이션·음향·사연은 아직 없습니다.
오류를 기록할 때 화면 크기, 아이템 배치, 누른 순서와 스크린샷을 남겨 주세요.
''', encoding='utf-8')
destination = root / f'build/JeoseungBundle-prototype-{version}-windows.zip'
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(folder.rglob('*')):
        if path.is_file():
            archive.write(path, Path('JeoseungBundle') / path.relative_to(folder))
print(f'Windows package: {destination}')
