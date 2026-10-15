#!/usr/bin/env python3
"""Fetch verified official 32.2.2 Intel runtime into vendor; installed OBS stays untouched."""
import hashlib, json, pathlib, subprocess, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
destination = root / 'vendor/obs-intel/OBS.app'
if destination.exists():
    print(destination)
    raise SystemExit(0)
release = json.load(urllib.request.urlopen('https://api.github.com/repos/obsproject/obs-studio/releases/tags/32.2.2'))
asset = next(a for a in release['assets'] if a['name'] == 'OBS-Studio-32.2.2-macOS-Intel.dmg')
dmg = root / 'vendor' / asset['name']
urllib.request.urlretrieve(asset['browser_download_url'], dmg)
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
if asset.get('digest') != 'sha256:' + digest:
    raise SystemExit('Downloaded runtime does not match GitHub release SHA-256')
mount = root / 'vendor/obs-intel-mount'
mount.mkdir(exist_ok=True)
subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(dmg)],check=True)
try:
    destination.parent.mkdir(exist_ok=True)
    subprocess.run(['ditto',str(mount/'OBS.app'),str(destination)],check=True)
finally:
    subprocess.run(['hdiutil','detach',str(mount)],check=True)
(destination.parent/'origin.json').write_text(json.dumps({'url':asset['browser_download_url'],'sha256':digest,'version':'32.2.2'},indent=2)+'\n')
print(destination)
