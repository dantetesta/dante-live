#!/usr/bin/env python3
"""Fetch the pinned Sparkle SDK; embed only the non-sandboxed runtime."""
import argparse, hashlib, json, os, pathlib, shutil, tarfile, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
lock = json.loads((root/'packaging/sparkle-lock.json').read_text())
base = root/'vendor'/('sparkle-'+lock['version'])
parser = argparse.ArgumentParser(); parser.add_argument('--embed', action='store_true'); args = parser.parse_args()
base.mkdir(parents=True, exist_ok=True)
archive = base/('Sparkle-'+lock['version']+'.tar.xz')
if not archive.exists():
    temporary = archive.with_suffix('.download')
    urllib.request.urlretrieve(lock['url'], temporary)
    temporary.replace(archive)
with archive.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != lock['sha256']:
        raise SystemExit('Sparkle archive digest mismatch')
if not (base/'Sparkle.framework').exists():
    with tarfile.open(archive) as source:
        source.extractall(base, filter='data')
if args.embed:
    app = root/os.environ.get('DANTE_BUILD_DIR', 'build')/'Dante Live.app'
    target = app/'Contents/Frameworks/Sparkle.framework'
    if target.exists(): shutil.rmtree(target)
    shutil.copytree(base/'Sparkle.framework', target, symlinks=True)
    # Dante is not sandboxed; these services and SDK headers are not runtime dependencies.
    for path in sorted(target.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.name in ('Headers','PrivateHeaders','Modules','XPCServices','_CodeSignature'):
            if path.is_symlink(): path.unlink()
            elif path.is_dir(): shutil.rmtree(path)
    shutil.copy2(base/'LICENSE', app/'Contents/Resources/Licenses/Sparkle-LICENSE.txt')
print('Sparkle '+lock['version']+' verified'+(' and embedded' if args.embed else ''))
