#!/usr/bin/env python3
"""Prepare a verified snapshot of the latest stable release for Netlify."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

REPO = 'helson-lin/FanBar'
OUT = Path(os.environ.get('FANBAR_BACKUP_DIR', '/tmp/fanbar-download-backup'))

def latest():
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/releases/latest']))

def main():
    release = latest()
    assets = [a for a in release['assets'] if re.fullmatch(r'FanBar-v?\d[^/]*\.dmg', a['name']) and not re.search(r'-(?:arm64|x86_64)\.dmg$', a['name'])]
    if len(assets) != 1:
        raise RuntimeError('Expected exactly one universal DMG')
    asset = assets[0]
    digest = asset.get('digest', '')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise RuntimeError('Release asset has no valid SHA-256 digest')
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / 'latest.dmg'
    tmp = OUT / 'download.tmp'
    if tmp.exists():
        tmp.unlink()
    subprocess.run(['gh', 'release', 'download', release['tag_name'], '--repo', REPO, '--pattern', asset['name'], '--output', str(tmp)], check=True)
    h = hashlib.sha256()
    with tmp.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    if 'sha256:' + h.hexdigest() != digest or tmp.stat().st_size != asset['size']:
        raise RuntimeError('Downloaded DMG does not match GitHub release digest and size')
    if latest()['id'] != release['id']:
        raise RuntimeError('Latest release changed during download; retry sync')
    tmp.replace(target)
    metadata = {'version': release['tag_name'], 'sha256': h.hexdigest(), 'size': asset['size'], 'source_asset': asset['name']}
    (OUT / 'version.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (OUT / '_headers').write_text('/latest.dmg\n  Cache-Control: public, max-age=300\n  Content-Type: application/octet-stream\n  Content-Disposition: attachment; filename="FanBar.dmg"\n/version.json\n  Cache-Control: public, max-age=60\n')
    print(json.dumps(metadata))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Backup preparation failed: {error}', file=sys.stderr)
        sys.exit(1)
