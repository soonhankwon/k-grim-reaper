"""Guard the English release text sources; test fixtures remain unchanged."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
paths = list((root / 'game/scripts').rglob('*.gd'))
paths += [root / 'game/project.godot', root / 'game/data/content/catalog.json', root / 'scripts/package.py']
paths += list((root / 'game/data/presentation').glob('*.json'))
paths += list((root / 'content/source').glob('*.csv'))
paths += [root / 'game/tests/fixtures/arang-english.json', root / 'game/tests/fixtures/arang-story-english.json']
paths += [root / 'game/tests/arang_experiment_setup.gd', root / 'game/tests/arang_experiment_launcher.gd']
found = []
for path in paths:
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        # The internal project identifier preserves the existing user:// directory.
        # The visible window title is set to English by Main.
        if path.name == 'project.godot' and line.startswith('config/name='):
            continue
        if re.search(r'[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]', line):
            found.append(f'{path.relative_to(root)}:{number}')
if found:
    raise SystemExit('Non-English Hangul in release text: ' + ', '.join(found))
print('RELEASE LANGUAGE: PASS — visible shipping text is English')
