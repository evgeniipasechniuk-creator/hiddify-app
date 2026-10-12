"""Apply public changes only to the verified Hiddify core 4.0.4 source."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def apply(target: Path, overlay: Path) -> None:
    manifest = json.loads((overlay / 'manifest.json').read_text())
    revision = subprocess.check_output(['git', '-C', str(target), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != manifest['base_revision']:
        raise ValueError('Core source version does not match the reviewed base')
    for item in manifest['files']:
        relative = Path(item['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe overlay path')
        destination = target / relative
        expected = item['before_sha256']
        if expected is None:
            if destination.exists():
                raise ValueError(f'New file already exists: {relative}')
        elif not destination.is_file() or hashlib.sha256(destination.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Base file differs: {relative}')
        if hashlib.sha256((overlay / relative).read_bytes()).hexdigest() != item['after_sha256']:
            raise ValueError(f'Overlay file differs: {relative}')
    for item in manifest['files']:
        destination = target / item['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes((overlay / item['path']).read_bytes())


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    apply(Path(sys.argv[1]).resolve(), root / 'core-overlay')
    print('Verified core overlay applied')
