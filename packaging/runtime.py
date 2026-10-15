#!/usr/bin/env python3
"""Copy a positive runtime allowlist and its Mach-O dependency closure; no Qt."""
import hashlib, json, os, pathlib, plistlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = pathlib.Path(os.environ.get('OBS_APP', '/Applications/OBS.app')).resolve()
BUILD = ROOT / os.environ.get('DANTE_BUILD_DIR','build')
APP = BUILD / 'Dante Live.app'
CONTENTS = APP / 'Contents'
FRAMEWORKS = CONTENTS / 'Frameworks'
mode = sys.argv[1] if len(sys.argv) > 1 else 'copy'
def run(*args):
    return subprocess.check_output(args, text=True).strip()
def binary(path):
    if not path.is_file() or path.is_symlink(): return False
    with path.open('rb') as stream: magic = stream.read(4)
    return magic in (b'\xfe\xed\xfa\xce',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf')
def dependencies(path):
    return sorted({x.strip().split(' (')[0] for x in run('otool','-L',str(path)).splitlines() if x.startswith('\t')})
def copy(source, target):
    if target.exists(): return
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir(): shutil.copytree(source,target,symlinks=True)
    else: shutil.copy2(source,target)
def closure():
    done = set()
    while True:
        pending = [p for p in CONTENTS.rglob('*') if p not in done and binary(p)]
        if not pending: break
        for p in pending:
            done.add(p)
            for dep in dependencies(p):
                if any(x in dep for x in ('Qt','Chromium','obs-frontend','obs-scripting')):
                    raise SystemExit(f'Forbidden dependency {dep} in {p}')
                if dep.startswith(('/System/', '/usr/lib/')): continue
                if not dep.startswith('@rpath/'):
                    raise SystemExit(f'Unresolved dependency {dep} in {p}')
                relative = dep.removeprefix('@rpath/')
                component = relative.split('/')[0]
                copy(SOURCE/'Contents/Frameworks'/component,FRAMEWORKS/component)
def prune():
    for p in sorted(CONTENTS.rglob('*'),key=lambda p:len(p.parts),reverse=True):
        if p.name in ('_CodeSignature','Headers','Modules') and p.is_dir() and not p.is_symlink(): shutil.rmtree(p)
        elif p.name in ('embedded.provisionprofile','.DS_Store') or p.suffix in ('.md','.markdown'):
            if p.is_file(): p.unlink()
def audit():
    records = []
    main = CONTENTS/'MacOS/DanteLive'
    required_arches = set(run('lipo','-archs',str(main)).split()) if main.exists() else {'arm64'}
    for p in CONTENTS.rglob('*'):
        if not binary(p): continue
        if any(x in str(p) for x in ('Qt','Chromium','obs-browser','obs-vst','frontend-api')):
            raise SystemExit(f'Forbidden binary: {p}')
        arches = run('lipo','-archs',str(p)).split()
        if p.name != 'libobs-metal.dylib' and not required_arches.issubset(arches):
            raise SystemExit(f'Missing architecture required by app: {p}: {arches}')
        output = run('otool','-l',str(p))
        minimums = [line.split()[1] for line in output.splitlines() if line.strip().startswith('minos ')]
        if any(tuple(map(int,v.split('.')[:2])) > (14,0) for v in minimums):
            raise SystemExit(f'Unsupported deployment target: {p}: {minimums}')
        for dep in dependencies(p):
            if dep.startswith('@rpath/') and not (FRAMEWORKS/dep.removeprefix('@rpath/')).exists():
                raise SystemExit(f'Missing packaged dependency: {p} → {dep}')
            if dep.startswith(('/Applications/','/Users/','/opt/')): raise SystemExit(f'External dependency {p} → {dep}')
        records.append({'path':str(p.relative_to(APP)),'architectures':arches,'minimumOS':minimums})
    (BUILD/'runtime-audit.json').write_text(json.dumps(records,indent=2)+'\n')
    print(f'Audited {len(records)} Mach-O files; dependency closure resolved; no Qt/CEF.')
if mode == 'prepare':
    architectures = os.environ.get('DANTE_ARCHS','arm64 x86_64').split()
    fingerprint = hashlib.sha256()
    for name in ('runtime.py','modules.txt','Info.plist','THIRD-PARTY-NOTICES.txt'):
        fingerprint.update((ROOT/'packaging'/name).read_bytes())
    fingerprint.update(str(SOURCE).encode())
    fingerprint.update(' '.join(architectures).encode())
    # Metadata fingerprints invalidate the copied runtime after upstream replacement;
    # the final dependency/architecture audit still runs on every build.
    for base in (SOURCE/'Contents',ROOT/'vendor/obs-intel/OBS.app/Contents'):
        if base.exists():
            for path in sorted(base.rglob('*')):
                if path.is_file() and not path.is_symlink():
                    stat = path.stat()
                    fingerprint.update(f'{path}:{stat.st_size}:{stat.st_mtime_ns}'.encode())
    stamp = BUILD/'runtime-cache.json'
    expected = fingerprint.hexdigest()
    if stamp.exists() and APP.exists() and json.loads(stamp.read_text()).get('fingerprint') == expected:
        audit()
        print('Reused unchanged isolated runtime bundle.')
        raise SystemExit(0)
    subprocess.run([sys.executable,__file__,'copy'],check=True)
    if 'x86_64' in architectures: subprocess.run([sys.executable,__file__,'merge-intel'],check=True)
    stamp.write_text(json.dumps({'fingerprint':expected,'architectures':architectures})+'\n')
    raise SystemExit(0)
elif mode == 'copy':
    if APP.exists(): shutil.rmtree(APP)
    for directory in ('MacOS','Frameworks','PlugIns','Resources/Licenses'):
        (CONTENTS/directory).mkdir(parents=True,exist_ok=True)
    installed = plistlib.loads((SOURCE/'Contents/Info.plist').read_bytes())
    if installed.get('CFBundleShortVersionString') != '32.2.2': raise SystemExit('Expected OBS runtime 32.2.2')
    for module in (ROOT/'packaging/modules.txt').read_text().splitlines():
        original = SOURCE/'Contents/PlugIns'/f'{module}.plugin'
        destination = CONTENTS/'PlugIns'/f'{module}.plugin'
        if module == 'rtmp-services':
            # The original module starts catalog requests on load. Only its
            # metadata/locales accompany our custom-service-only replacement.
            (destination/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
            copy(original/'Contents/Info.plist',destination/'Contents/Info.plist')
            copy(original/'Contents/Resources/locale',destination/'Contents/Resources/locale')
        else:
            copy(original,destination)
    for lib in ('libobs.framework','libobs-metal.dylib','libobs-opengl.dylib'):
        if (SOURCE/'Contents/Frameworks'/lib).exists(): copy(SOURCE/'Contents/Frameworks'/lib,FRAMEWORKS/lib)
    copy(SOURCE/'Contents/MacOS/obs-ffmpeg-mux',CONTENTS/'MacOS/obs-ffmpeg-mux')
    closure()
    copy(ROOT/'packaging/Info.plist',CONTENTS/'Info.plist')
    copy(ROOT/'vendor/obs-studio/COPYING',CONTENTS/'Resources/Licenses/GPL-2.0.txt')
    copy(ROOT/'vendor/obs-studio/AUTHORS',CONTENTS/'Resources/Licenses/OBS-AUTHORS.txt')
    copy(ROOT/'vendor/simde/COPYING',CONTENTS/'Resources/Licenses/SIMDe-MIT.txt')
    copy(ROOT/'vendor/obs-studio/deps/libcaption/LICENSE.txt',CONTENTS/'Resources/Licenses/libcaption-LICENSE.txt')
    copy(ROOT/'packaging/THIRD-PARTY-NOTICES.txt',CONTENTS/'Resources/Licenses/THIRD-PARTY-NOTICES.txt')
    for name in ('FFmpeg','aom','freetype','jansson','lame','libogg','libpng','librist','libtheora','libvorbis','libvpx','mbedtls','opus','rnnoise','speexdsp','srt','x264'):
        copy(ROOT/'vendor/obs-deps/licenses'/name,CONTENTS/'Resources/Licenses'/name)
    for path in (ROOT/'packaging/licenses').glob('*'):
        if path.is_file(): copy(path,CONTENTS/'Resources/Licenses'/path.name)
    prune()
elif mode == 'merge-intel':
    intel = ROOT/'vendor/obs-intel/OBS.app/Contents'
    if not intel.exists(): raise SystemExit('Run packaging/fetch-intel.py first')
    for p in CONTENTS.rglob('*'):
        if not binary(p): continue
        if p.name == 'libobs-metal.dylib': continue # upstream explicitly arm64 only
        if set(run('lipo','-archs',str(p)).split()) >= {'arm64','x86_64'}: continue
        other = intel/p.relative_to(CONTENTS)
        if not other.exists() or 'x86_64' not in run('lipo','-archs',str(other)):
            raise SystemExit(f'Intel runtime missing: {other}')
        temp = p.with_name(p.name+'.universal')
        subprocess.run(['lipo','-create',str(p),str(other),'-output',str(temp)],check=True)
        temp.replace(p)
    print('Combined arm64 + x86_64 runtime; Metal backend remains arm64-only by upstream design.')
elif mode != 'audit': raise SystemExit('Expected prepare, copy, merge-intel or audit')
audit()
