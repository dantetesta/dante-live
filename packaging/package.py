#!/usr/bin/env python3
"""Clean runtime DMG stage + separate explicitly requested GPL source preparation."""
import os, pathlib, plistlib, shutil, zipfile
root = pathlib.Path(__file__).resolve().parent.parent
build = root/os.environ.get('DANTE_BUILD_DIR','build')
stage = build/'distribution-stage'
if stage.exists(): shutil.rmtree(stage)
stage.mkdir()
shutil.copytree(build/'Dante Live.app',stage/'Dante Live.app',symlinks=True)
(stage/'Applications').symlink_to('/Applications', target_is_directory=True)
(root/'dist').mkdir(exist_ok=True)
for path in stage.rglob('*'):
    name = path.name.lower()
    if name in ('agents.md','claude.md','memory.md','.env','.ds_store','.git') or path.suffix.lower() in ('.md','.log','.bak','.sqlite','.db'):
        raise SystemExit(f'Forbidden runtime artifact {path}')
    if any(s in name for s in ('credential','cookies','private-key','handoff')):
        raise SystemExit(f'Sensitive runtime filename {path}')
manifest = '\n'.join(str(p.relative_to(stage)) for p in sorted(stage.rglob('*')) if p.is_file())+'\n'
(build/'package-manifest.txt').write_text(manifest)
# This explicit source deliverable is separate from the end-user runtime image.
# Positive local allowlist, with tracked upstream source; never capture .git, build,
# user settings, credentials, caches, or the entire project directory.
version = plistlib.loads((build/'Dante Live.app/Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
assert all(c.isdigit() or c == '.' for c in version)
archive = root/f'dist/Dante-Live-{version}-source-preparation.zip'
allowed = []
for directory in ('Sources','scripts','packaging'):
    for path in (root/directory).rglob('*'):
        if path.is_file() and path.suffix in ('.swift','.h','.mm','.m','.c','.cpp','.sh','.py','.plist','.txt','.json','.patch'):
            allowed.append(path)
if (root/'LICENSE').is_file(): allowed.append(root/'LICENSE')
allowed.append(root/'packaging/assets/DanteLive.png')
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as output:
    for path in allowed: output.write(path,path.relative_to(root))
    output.write(root/'vendor/obs-studio/COPYING','OBS-COPYING')
    output.writestr('SOURCE-PREPARATION.txt',
        'Local source preparation, not complete corresponding source for public redistribution.\n'
        'Run scripts/fetch-reference.sh to retrieve pinned OBS 32.2.2 source.\n'
        'Runtime dependency exact revisions, full sources/build recipes and license texts\n'
        'must be gathered before public binary distribution. No secrets included.\n')
with zipfile.ZipFile(archive) as check:
    failure = check.testzip()
    if failure: raise SystemExit(f'ZIP integrity failure: {failure}')
print(f'Clean DMG stage: {stage}; {len(manifest.splitlines())} files.')
print(f'Source preparation ZIP verified: {archive}')
