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
shutil.copy2(root / 'game/assets/fonts/Galmuri-OFL.txt', licenses / 'Galmuri-OFL.txt')
shutil.copy2(root / 'game/licenses/Godot-LICENSE.txt', licenses / 'Godot-LICENSE.txt')
shutil.copy2(root / 'game/licenses/Godot-COPYRIGHT.txt', licenses / 'Godot-COPYRIGHT.txt')
notices = (root / 'THIRD_PARTY_NOTICES.md').read_text()
notices = notices.replace('game/licenses/', 'LICENSES/').replace('game/assets/fonts/OFL.txt', 'LICENSES/NotoSansKR-OFL.txt').replace('game/assets/fonts/Galmuri-OFL.txt', 'LICENSES/Galmuri-OFL.txt')
(folder / 'THIRD_PARTY_NOTICES.md').write_text(notices, encoding='utf-8')
(folder / 'README.txt').write_text(f'''Reaper's Bundle — First Delivery / Prototype {version}

Extract the entire ZIP and run JeoseungBundle.exe on Windows x86_64.
This build was cross-exported on macOS and has not yet been tested on Windows.

Drag items into the bag, or select an item and click an empty cell.
R: rotate · Esc/right click: cancel · Ctrl+Z: undo.
During battle, click items to use them, check the enemy's next move, and end your turn.
Use Skip Animation to show the confirmed result immediately. Sound can be toggled at the bottom left.
After the first battle, choose and place a reward or skip it. Investigate the mirror and choose a route.
Bring the mirror to Arang to hear her story, or use attacks to complete the encounter.
Frosted cells add 1 energy to weapons; rearrange your bag before the fight.

The prototype contains {len(content['items'])} item definitions. Progress is saved automatically.
If a save was made with different content, it is preserved; the game can archive it before starting a new run.
The artwork and sounds are provisional. Please report issues with the window size, item layout, and steps taken.
''', encoding='utf-8')
destination = root / f'build/JeoseungBundle-prototype-{version}-windows.zip'
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(folder.rglob('*')):
        if path.is_file() and path.name != 'README-KO.txt':
            archive.write(path, Path('JeoseungBundle') / path.relative_to(folder))
print(f'Windows package: {destination}')
