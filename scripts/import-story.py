#!/usr/bin/env python3
"""Validate a Sheets-exported story CSV and atomically publish presentation JSON."""
from pathlib import Path
import argparse
import csv
import json
import os
import re
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('source', nargs='?', type=Path, default=root / 'content/source/story.csv')
parser.add_argument('--check', action='store_true', help='compare without changing the game file')
args = parser.parse_args()
fields = ['id', 'min_completed', 'title', 'teaser', 'text']
try:
    with args.source.open(encoding='utf-8-sig', newline='') as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != fields:
            raise ValueError('CSV header must be ' + ','.join(fields))
        entries = []
        ids = set()
        previous = -1
        for row in reader:
            if None in row or any(value is None for value in row.values()):
                raise ValueError('CSV row has an incorrect column count')
            if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', row['id']) or row['id'] in ids:
                raise ValueError('story IDs must be unique lowercase identifiers')
            if not re.fullmatch(r'0|[1-9][0-9]*', row['min_completed']):
                raise ValueError('min_completed must be a nonnegative integer')
            completed = int(row['min_completed'])
            if completed > 64 or completed < previous:
                raise ValueError('min_completed must be ordered and at most 64')
            for key, limit in [('title', 48), ('teaser', 80), ('text', 1000)]:
                if not row[key].strip() or len(row[key]) > limit:
                    raise ValueError(f'{key} must be nonempty and at most {limit} characters')
            entries.append({'id': row['id'], 'min_completed': completed, 'title': row['title'], 'teaser': row['teaser'], 'text': row['text']})
            ids.add(row['id'])
            previous = completed
            if len(entries) > 100:
                raise ValueError('at most 100 story entries')
        if not entries or entries[0]['min_completed'] != 0:
            raise ValueError('the first story entry must be available at the start')
    content = {'schema_version': 1, 'entries': entries}
    target = root / 'game/data/presentation/story.json'
    if args.check:
        if json.loads(target.read_text(encoding='utf-8')) != content:
            raise ValueError('story CSV and game JSON differ')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmpname = None
        try:
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=target.parent, delete=False) as temp:
                tmpname = temp.name
                json.dump(content, temp, ensure_ascii=False, indent=2)
                temp.write('\n')
            os.replace(tmpname, target)
        finally:
            if tmpname and os.path.exists(tmpname): os.unlink(tmpname)
    print(f'STORY IMPORT: PASS — {len(entries)} entries')
except (OSError, ValueError, csv.Error, json.JSONDecodeError) as exc:
    raise SystemExit(f'STORY IMPORT: FAIL — {exc}')
