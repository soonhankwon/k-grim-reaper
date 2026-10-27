"""Invalid Sheets CSV must not overwrite the published story JSON."""
from pathlib import Path
import csv
import hashlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
source = root / 'content/source/story.csv'
target = root / 'game/data/presentation/story.json'
original = hashlib.sha256(target.read_bytes()).digest()
with source.open(encoding='utf-8', newline='') as f:
    reader = csv.DictReader(f)
    headers, rows = reader.fieldnames, list(reader)
with tempfile.TemporaryDirectory(dir=root / 'build') as directory:
    path = Path(directory) / 'invalid.csv'
    variants = []
    duplicate = [dict(row) for row in rows]
    duplicate[1]['id'] = duplicate[0]['id']
    variants.append(duplicate)
    descending = [dict(row) for row in rows]
    descending[2]['min_completed'] = '0'
    variants.append(descending)
    missing = [dict(row) for row in rows]
    missing[1]['text'] = ''
    variants.append(missing)
    for bad in variants:
        with path.open('w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            writer.writerows(bad)
        result = subprocess.run([sys.executable, str(root / 'scripts/import-story.py'), str(path)], capture_output=True, text=True)
        if result.returncode == 0 or hashlib.sha256(target.read_bytes()).digest() != original:
            raise SystemExit('Invalid story CSV was accepted or published story changed')
print('STORY IMPORT: invalid CSV preserves existing story')
