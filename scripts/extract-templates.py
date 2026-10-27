"""Extract only the pinned Windows templates from an official Godot TPZ archive."""
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
expected = (root / '.godot-version').read_text().strip()
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 scripts/extract-templates.py /path/to/export_templates.tpz')
with zipfile.ZipFile(sys.argv[1]) as archive:
    actual = archive.read('templates/version.txt').decode().strip()
    if actual != expected:
        raise SystemExit(f'Template version mismatch: expected {expected}, got {actual}')
    destination = root / '.tools/templates'
    destination.mkdir(parents=True, exist_ok=True)
    for name in ('version.txt', 'windows_debug_x86_64.exe', 'windows_release_x86_64.exe'):
        (destination / name).write_bytes(archive.read('templates/' + name))
print(f'Windows templates ready: {expected}')
