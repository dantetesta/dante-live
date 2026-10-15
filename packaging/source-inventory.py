#!/usr/bin/env python3
"""Pinned source acquisition inventory. Default is read-only, no source downloads."""
import hashlib, json, pathlib, re, subprocess, sys, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
deps = root/'vendor/obs-deps'
expected = '8683107a02300923abe4f293920f4b5edc8cb624'
if subprocess.check_output(['git','-C',str(deps),'rev-parse','HEAD'],text=True).strip() != expected:
    raise SystemExit('obs-deps commit differs from pinned recipe')
names = ['deps.ffmpeg/'+name+'.zsh' for name in (
    '20-libpng','20-opus','30-libogg','30-libvorbis','30-libvpx','40-aom','40-x264',
    '50-libtheora','60-lame','60-mbedtls','60-srt','70-librist','99-ffmpeg')]
names += ['deps.macos/'+name+'.zsh' for name in ('10-speexdsp','30-jansson','60-freetype','70-rnnoise','80-uthash')]
records = []
for name in names:
    path = deps/name
    source = path.read_text()
    def field(key):
        direct = re.search(r'^local '+key+r'=(.+)$',source,re.M)
        if direct: return direct.group(1).strip().strip("\"'")
        plural = 'hashes' if key == 'hash' else key+'s'
        array = re.search(r'local -A '+plural+r'=\((.*?)\)',source,re.S)
        if array:
            match = re.search(r'^\s*macos\s+([^\n]+)',array.group(1),re.M)
            if match: return match.group(1).strip().strip("\"'")
        raise SystemExit('Cannot resolve '+key+' in '+name)
    revision = field('hash')
    kind = 'git_commit'
    if revision.startswith('${0:a:h}/'):
        checksum = path.parent/revision.removeprefix('${0:a:h}/')
        revision = checksum.read_text().strip().split()[0]
        kind = 'sha256'
    if not re.fullmatch('[a-f0-9]{40}' if kind == 'git_commit' else '[a-f0-9]{64}',revision):
        raise SystemExit('Invalid fixed hash for '+name)
    records.append({'name':field('name'),'version':field('version'),'url':field('url'),
                    kind:revision,'recipe':name,'recipe_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
manifest = {'status':'pinned source acquisition; full dependency rebuild not performed','obs_deps_commit':expected,'components':records}
(root/'packaging/source-lock.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Pinned {len(records)} source components; full static closure still requires binary/build verification.')
if '--download' not in sys.argv: raise SystemExit(0)
destination = root/'vendor/corresponding-source'
destination.mkdir(exist_ok=True)
for record in records:
    target = destination/record['name']
    if 'git_commit' in record:
        if not target.exists():
            subprocess.run(['git','init',str(target)],check=True)
            subprocess.run(['git','-C',str(target),'remote','add','origin',record['url']],check=True)
            subprocess.run(['git','-C',str(target),'fetch','--depth','1','origin',record['git_commit']],check=True)
            subprocess.run(['git','-C',str(target),'checkout','--detach','FETCH_HEAD'],check=True)
        actual = subprocess.check_output(['git','-C',str(target),'rev-parse','HEAD'],text=True).strip()
        if actual != record['git_commit']: raise SystemExit('Existing source commit differs: '+str(target))
        subprocess.run(['git','-C',str(target),'submodule','update','--init','--recursive'],check=True)
    else:
        target = destination/(record['name']+'-'+record['url'].split('/')[-1])
        if not target.exists(): urllib.request.urlretrieve(record['url'],target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != record['sha256']:
            raise SystemExit('Source checksum mismatch: '+str(target))
    print('Verified '+record['name'])
