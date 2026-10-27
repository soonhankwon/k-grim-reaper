"""A rejected offline import must not replace the last valid runtime catalog."""
from pathlib import Path
import hashlib
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
catalog = root / 'game/data/content/catalog.json'
before = hashlib.sha256(catalog.read_bytes()).hexdigest()
invalid = root / 'build/invalid-content.json'
invalid.write_text('{"schema_version":999}\n')
result = subprocess.run([
    sys.argv[1], '--headless', '--path', str(root / 'game'),
    '--script', 'tools/import_content.gd', '--', str(invalid)
], capture_output=True, text=True, timeout=30)
if result.returncode != 1 or 'schema_version' not in result.stderr:
    raise SystemExit('Import did not reject invalid schema cleanly: ' + result.stdout + result.stderr)
if hashlib.sha256(catalog.read_bytes()).hexdigest() != before:
    raise SystemExit('Rejected import modified the runtime catalog.')
print('CONTENT IMPORT: rejected input preserves catalog')
