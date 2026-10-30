#!/usr/bin/env python3
"""Validate and publish display-only story scenes without changing game saves."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
source = root / 'content/source/arang-scenes.json'
target = root / 'game/data/presentation/arang-scenes.json'
fields = {'discovery', 'approach', 'approach_left', 'approach_packed', 'listen', 'fight_carried', 'fight_stashed', 'fight_left'}
try:
    doc = json.loads(source.read_text(encoding='utf-8'))
    if not isinstance(doc, dict) or not doc or len(doc) > 100:
        raise ValueError('expected scene IDs')
    for key, entry in doc.items():
        if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', key) or not isinstance(entry, dict) or set(entry) != fields:
            raise ValueError('invalid scene entry: ' + str(key))
        if any(not isinstance(v, str) or not v.strip() or len(v) > 2000 for v in entry.values()):
            raise ValueError('invalid scene text: ' + key)
    if args.check:
        if json.loads(target.read_text(encoding='utf-8')) != doc:
            raise ValueError('scene source and runtime differ')
    else:
        name = None
        try:
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=target.parent, delete=False) as file:
                name = file.name
                json.dump(doc, file, ensure_ascii=False, indent=2)
                file.write('\n')
            os.replace(name, target)
        finally:
            if name and os.path.exists(name): os.unlink(name)
    print('ARANG SCENES IMPORT: PASS')
except (OSError, ValueError, json.JSONDecodeError) as exc:
    raise SystemExit('ARANG SCENES IMPORT: FAIL — ' + str(exc))
