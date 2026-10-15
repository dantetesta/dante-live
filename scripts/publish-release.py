#!/usr/bin/env python3
"""Publish a prepared, versioned DMG + sources; update the current README button."""
import argparse, hashlib, json, pathlib, plistlib, re, shutil, subprocess, tempfile
parser=argparse.ArgumentParser()
parser.add_argument('--dmg',type=pathlib.Path,required=True)
parser.add_argument('--source',type=pathlib.Path,required=True)
parser.add_argument('--notes',type=pathlib.Path,required=True)
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent
repo='dantetesta/dante-live'
def run(*cmd): return subprocess.check_output(cmd,cwd=root,text=True).strip()
def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
version=plistlib.loads((root/'packaging/Info.plist').read_bytes())['CFBundleShortVersionString']
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version): raise SystemExit('Invalid version')
if run('git','branch','--show-current')!='main' or run('git','status','--porcelain'):
    raise SystemExit('Publish only from clean public main checkout')
if run('git','remote','get-url','origin').removesuffix('.git') not in (
    'https://github.com/'+repo, 'git@github.com:'+repo): raise SystemExit('Unexpected public origin')
head=run('git','rev-parse','HEAD')
if run('git','ls-remote','origin','refs/heads/main').split()[0]!=head:
    raise SystemExit('Push reviewed public source before release')
if version not in args.dmg.name or version not in args.source.name:
    raise SystemExit('Asset filenames must match the source version')
subprocess.run(['hdiutil','verify',str(args.dmg.resolve())],check=True)
# The source archive must contain this exact public source commit.
import zipfile
with zipfile.ZipFile(args.source) as bundle:
    if bundle.testzip(): raise SystemExit('Invalid source ZIP')
    manifest=json.loads(bundle.read('SOURCE-MANIFEST.json'))
    if manifest['version']!=version or not any(x.get('extract_to')=='dante-live' and x.get('commit')==head for x in manifest['archives']):
        raise SystemExit('Source archive does not match public HEAD')
tag='v'+version
with tempfile.TemporaryDirectory(prefix='dante-release-') as tmp:
    stage=pathlib.Path(tmp)
    dmg=stage/f'Dante-Live-{version}-macOS-universal.dmg'
    shutil.copyfile(args.dmg,dmg)
    source=stage/args.source.name; shutil.copyfile(args.source,source)
    sums=stage/'SHA256SUMS.txt'
    expected={p.name:digest(p) for p in (dmg,source)}
    sums.write_text(''.join(f'{sha}  {name}\n' for name,sha in expected.items()))
    expected[sums.name]=digest(sums)
    # Sign and validate the actual DMG before publishing any assets. The feed stays local until upload verification.
    import importlib.util
    spec=importlib.util.spec_from_file_location('dante_update_feed',root/'packaging/update-feed.py')
    updater=importlib.util.module_from_spec(spec);spec.loader.exec_module(updater)
    prepared_feed=stage/'updates'
    updater.prepare(dmg,args.notes,prepared_feed,root=root)
    # Existing tags/releases are never overwritten. Failures leave a reviewable draft.
    subprocess.run(['gh','release','create',tag,str(dmg),str(source),str(sums),
        '-R',repo,'--target',head,'--draft','--prerelease',
        '--title',f'Dante Live {version} — macOS (experimental)',
        '--notes-file',str(args.notes.resolve())],check=True,cwd=root)
    # A draft has no published tag URL yet; resolve it through the authenticated list.
    releases=json.loads(run('gh','api',f'repos/{repo}/releases?per_page=100'))
    matches=[r for r in releases if r['tag_name']==tag and r['draft'] and r['target_commitish']==head]
    if len(matches)!=1: raise SystemExit('Cannot uniquely identify the uploaded draft')
    metadata=matches[0]
    actual={a['name']:a.get('digest') for a in metadata['assets']}
    if actual!={name:'sha256:'+sha for name,sha in expected.items()}:
        raise SystemExit('Uploaded asset digests differ; release remains draft')
    run('gh','api','--method','PATCH',f'repos/{repo}/releases/{metadata["id"]}',
        '-F','draft=false','-F','prerelease=true')
    # Publish a new catalog only after immutable release assets have matching digests.
    for source_file in prepared_feed.rglob('*'):
        if source_file.is_file():
            target=root/'updates'/source_file.relative_to(prepared_feed)
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source_file,target)
url=f'https://github.com/{repo}/releases/download/{tag}/Dante-Live-{version}-macOS-universal.dmg'
readme=root/'README.md'
text=readme.read_text()
start='<!-- current-download:start -->'; end='<!-- current-download:end -->'
button=f"""<!-- current-download:start -->
[![Baixar Dante Live para Mac](https://img.shields.io/badge/BAIXAR_PARA_MAC-v{version}-18B7C7?style=for-the-badge&logo=apple&logoColor=white)]({url})

**macOS 14+ · Apple Silicon e Intel · Universal 2**
Versão experimental **{version}**. Assinado com Developer ID e notarizado pela Apple. [Notas e fontes](https://github.com/{repo}/releases/tag/{tag}).
<!-- current-download:end -->"""
if start not in text or end not in text: raise SystemExit('Missing README download markers')
text=text[:text.index(start)]+button+text[text.index(end)+len(end):]
readme.write_text(text)
if run('git','status','--porcelain','README.md','updates'):
    run('git','add','README.md','updates'); run('git','commit','-m',f'release: signed update catalog and changelog {version}'); run('git','push','origin','main')
print('Published '+url)
