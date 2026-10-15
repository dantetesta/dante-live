#!/usr/bin/env python3
"""The exact Universal2 SDK archive pinned by OBS32.2.2 CMakePresets.json."""
import hashlib, pathlib, tarfile, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
archive = root/'vendor/macos-deps-2026-07-15-universal.tar.xz'
expected = '4ecb4c598dfa853168df6c2a0c4e0ffec8495a81fbd1ba051ef88ecd5e0f7e53'
url = 'https://github.com/obsproject/obs-deps/releases/download/2026-07-15/'+archive.name
if not archive.exists(): urllib.request.urlretrieve(url,archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected: raise SystemExit('Build dependency checksum mismatch')
destination = root/'vendor/obs-deps-universal'
if not (destination/'include/mbedtls/mbedtls_config.h').exists():
    with tarfile.open(archive) as package: package.extractall(destination,filter='data')
print('Verified pinned Universal2 build dependencies')
