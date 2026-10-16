#!/usr/bin/env python3
"""Package pinned corresponding sources separately from the runtime installer."""
import hashlib, json, os, pathlib, plistlib, subprocess, tempfile, zipfile
root = pathlib.Path(__file__).resolve().parent.parent
repo = pathlib.Path(os.environ.get('DANTE_SOURCE_REPO', str(root))).resolve()
lock = json.loads((root/'packaging/source-lock.json').read_text())
version = plistlib.loads((root/'packaging/Info.plist').read_bytes())['CFBundleShortVersionString']
output = root/f'dist/Dante-Live-{version}-corresponding-source.zip'
output.parent.mkdir(exist_ok=True)
def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()
def sha(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
manifest = {'version': version, 'archives': []}
with tempfile.TemporaryDirectory(prefix='dante-source-') as temporary:
    temp = pathlib.Path(temporary)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
        def add(path, name, **metadata):
            archive.write(path, name)
            manifest['archives'].append(dict(archive=name, sha256=sha(path), **metadata))
        def tree(path, name, commit, url, exclude_agent_files=False):
            if git(path, 'rev-parse', 'HEAD') != commit:
                raise SystemExit('Source revision mismatch: '+name)
            if git(path, 'status', '--porcelain', '--untracked-files=no'):
                raise SystemExit('Tracked source modifications: '+name)
            files = git(path, 'ls-files').splitlines()
            forbidden = {'AGENTS.md', 'CLAUDE.md', 'MEMORY.md', '.env'}
            omitted = [f for f in files if pathlib.PurePosixPath(f).name in forbidden]
            if omitted and not exclude_agent_files:
                raise SystemExit('Internal or environment file in source: '+name)
            tar = temp/(name.replace('/', '-')+'.tar.gz')
            subprocess.run(['git','-C',str(path),'archive','--format=tar.gz',
                            '-o',str(tar),commit,'--','.',*[':(exclude)'+f for f in omitted]],check=True)
            add(tar, 'sources/'+tar.name, extract_to=name, commit=commit, url=url, omitted_agent_files=omitted)
            # Export gitlinks as distinct archives; no Git database or credentials.
            for entry in git(path, 'ls-tree', '-r', 'HEAD').splitlines():
                info, filename = entry.split('\t',1)
                mode, kind, revision = info.split()
                if mode == '160000':
                    child = path/filename
                    if (child/'.git').exists():
                        tree(child, name+'/'+filename, revision, git(child,'remote','get-url','origin'))
                    elif name != 'obs-studio':
                        raise SystemExit('Missing submodule: '+name+'/'+filename)
                    # OBS browser/websocket are excluded from the shipped runtime.
        tree(repo, 'dante-live', git(repo,'rev-parse','HEAD'), 'https://github.com/dantetesta/dante-live')
        for name, commit, url in [
            ('obs-studio','ba2f32bdf791005443988a4955e963663e16b1ed','https://github.com/obsproject/obs-studio'),
            ('obs-deps',lock['obs_deps_commit'],'https://github.com/obsproject/obs-deps'),
            ('simde','71fd833d9666141edcd1d3c109a80e228303d8d7','https://github.com/simd-everywhere/simde')]:
            tree(root/'vendor'/name,name,commit,url)
        sparkle = json.loads((root/'packaging/sparkle-lock.json').read_text())
        tree(root/'vendor/sparkle-source', 'Sparkle', sparkle['source_commit'], 'https://github.com/sparkle-project/Sparkle')
        guests = json.loads((root/'packaging/guests-lock.json').read_text())
        tree(root/'vendor/cloudflared-source','cloudflared',guests['tunnel']['source_commit'],'https://github.com/cloudflare/cloudflared',exclude_agent_files=True)
        webrtc = guests['webrtc']
        path = root/'vendor/corresponding-source'/('webrtc-'+webrtc['source_commit']+'.tar.gz')
        if not path.exists():
            import urllib.request
            urllib.request.urlretrieve(webrtc['source_url'],path)
        if sha(path)!=webrtc['source_sha256']:raise SystemExit('WebRTC source digest mismatch')
        add(path,'sources/'+path.name,extract_to='webrtc',commit=webrtc['source_commit'],url=webrtc['source_url'])
        for record in lock['components']:
            name=record['name']; base=root/'vendor/corresponding-source'
            if 'git_commit' in record:
                tree(base/name,name,record['git_commit'],record['url'])
            else:
                path=base/(name+'-'+record['url'].split('/')[-1])
                if sha(path)!=record['sha256']: raise SystemExit('Source digest mismatch: '+name)
                add(path,'sources/'+path.name,extract_to=name,version=record['version'],url=record['url'])
        archive.write(root/'packaging/SOURCE-ACQUISITION.txt','BUILD-SOURCES.txt')
        archive.write(root/'packaging/source-lock.json','source-lock.json')
        archive.write(root/'packaging/guests-lock.json','guests-lock.json')
        archive.writestr('SOURCE-MANIFEST.json', json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(output) as check:
    if check.testzip(): raise SystemExit('Source ZIP integrity failure')
print(f'{output}: {len(manifest["archives"])} verified source archives; SHA-256 {sha(output)}')
