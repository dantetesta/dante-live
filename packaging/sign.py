#!/usr/bin/env python3
import os, pathlib, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
app = root/os.environ.get('DANTE_BUILD_DIR','build')/'Dante Live.app'
main_executable = app/'Contents/MacOS/DanteLive'
def sign(path, extra=()):
    subprocess.run(['codesign','--force','--sign','-','--timestamp=none',*extra,str(path)],check=True)
for p in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    # Signing the app's principal executable directly may cause codesign to
    # validate its enclosing bundle before the nested plugins are signed.
    # The final app signature signs it with the application entitlements.
    if p == main_executable: continue
    if p.is_file() and not p.is_symlink():
        with p.open('rb') as stream: magic = stream.read(4)
        if magic in (b'\xfe\xed\xfa\xce',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf'): sign(p)
for p in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if p.is_dir() and not p.is_symlink() and p.suffix in ('.framework','.plugin','.app'): sign(p)
sign(app,('--entitlements',str(root/'packaging/entitlements.plist')))
