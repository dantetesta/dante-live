#!/usr/bin/env python3
"""Prepare a signed Sparkle appcast. Publication occurs only after release assets are verified."""
import argparse, base64, datetime, email.utils, hashlib, json, os, pathlib, plistlib, re, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parent.parent
REPOSITORY = 'https://github.com/dantetesta/dante-live'
ACCOUNT = 'com.dantetesta.DanteLive.updates'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
def tools(root=ROOT):
    lock = json.loads((root/'packaging/sparkle-lock.json').read_text())
    return pathlib.Path(os.environ.get('DANTE_SPARKLE_TOOLS', str(root/'vendor'/('sparkle-'+lock['version'])/'bin')))
def run(*args): return subprocess.check_output([str(x) for x in args], text=True).strip()
def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()
def validate_record(record):
    version = record['version']; build = record['build']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not isinstance(build, int) or build < 1: raise ValueError('Invalid release version/build')
    if record['url'] != f'{REPOSITORY}/releases/download/v{version}/Dante-Live-{version}-macOS-universal.dmg': raise ValueError('Unexpected download origin/path')
    if record['minimumSystemVersion'] != '14.0' or record['architectures'] != ['arm64','x86_64']: raise ValueError('Incompatible release')
    if not isinstance(record['length'], int) or record['length'] <= 0: raise ValueError('Invalid download length')
    if len(base64.b64decode(record['signature'], validate=True)) != 64 or not re.fullmatch(r'[a-f0-9]{64}', record['sha256']): raise ValueError('Invalid signature/digest')
    if not record['changelog'].strip() or len(record['changelog']) > 100_000: raise ValueError('Missing/oversized release notes')
    datetime.datetime.fromisoformat(record['publishedAt'])
def appcast(records):
    builds = set(); versions = set()
    rss = ET.Element('rss', {'version':'2.0'}); channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Dante Live — atualizações para Mac'
    ET.SubElement(channel, 'link').text = REPOSITORY+'/releases'
    ET.SubElement(channel, 'language').text = 'pt-BR'
    for record in sorted(records, key=lambda r:r['build'], reverse=True):
        validate_record(record)
        if record['build'] in builds or record['version'] in versions: raise ValueError('Duplicate version/build')
        builds.add(record['build']); versions.add(record['version'])
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = 'Dante Live '+record['version']
        ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.fromisoformat(record['publishedAt']))
        for key, value in [('version', str(record['build'])), ('shortVersionString',record['version']), ('minimumSystemVersion',record['minimumSystemVersion']), ('fullReleaseNotesLink', REPOSITORY+'/releases')]:
            ET.SubElement(item, '{'+SPARKLE+'}'+key).text = value
        ET.SubElement(item, 'description', {'{'+SPARKLE+'}format':'markdown'}).text = record['changelog']
        ET.SubElement(item, 'enclosure', {'url':record['url'], 'length':str(record['length']), 'type':'application/octet-stream', '{'+SPARKLE+'}edSignature':record['signature']})
    ET.indent(rss)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)+b'\n'
def prepare(dmg, notes, destination, root=ROOT):
    info = plistlib.loads((root/'packaging/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']; build = int(info['CFBundleVersion'])
    sdk = tools(root)
    if run(sdk/'generate_keys', '--account', ACCOUNT, '-p') != info['SUPublicEDKey']: raise ValueError('Signing key does not match the embedded public key')
    # Inspect the actual image, not only filenames or the current source plist.
    with tempfile.TemporaryDirectory(prefix='dante-update-audit-') as temporary:
        mount = pathlib.Path(temporary)/'mounted'; mount.mkdir()
        subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(dmg.resolve())],check=True,stdout=subprocess.DEVNULL)
        try:
            app = mount/'Dante Live.app'
            packaged = plistlib.loads((app/'Contents/Info.plist').read_bytes())
            for key in ('CFBundleIdentifier','CFBundleVersion','CFBundleShortVersionString','SUPublicEDKey','SUFeedURL','SURequireSignedFeed','SUVerifyUpdateBeforeExtraction'):
                if packaged.get(key) != info[key]: raise ValueError('Packaged update mismatch: '+key)
            if set(run('lipo','-archs',app/'Contents/MacOS/DanteLive').split()) != {'arm64','x86_64'}: raise ValueError('Update must be Universal 2')
            subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        finally: subprocess.run(['hdiutil','detach',str(mount)],check=True,stdout=subprocess.DEVNULL)
    signature = run(sdk/'sign_update','--account',ACCOUNT,'-p',dmg)
    subprocess.run([str(sdk/'sign_update'),'--account',ACCOUNT,'--verify',str(dmg),signature],check=True,stdout=subprocess.DEVNULL)
    record = dict(version=version,build=build,url=f'{REPOSITORY}/releases/download/v{version}/Dante-Live-{version}-macOS-universal.dmg',length=dmg.stat().st_size,sha256=digest(dmg),signature=signature,minimumSystemVersion='14.0',architectures=['arm64','x86_64'],publishedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),changelog=notes.read_text())
    validate_record(record)
    previous = root/'updates'
    records = [json.loads(p.read_text()) for p in (previous/'releases').glob('*.json')]
    if any(r['version']==version or r['build']>=build for r in records): raise ValueError('Release version/build must advance; existing releases are immutable')
    destination.mkdir(parents=True,exist_ok=True)
    for name in ['releases','changelogs']: (destination/name).mkdir(exist_ok=True)
    for record_path in (previous/'releases').glob('*.json'): shutil.copy2(record_path,destination/'releases'/record_path.name)
    for changelog in (previous/'changelogs').glob('*.md'): shutil.copy2(changelog,destination/'changelogs'/changelog.name)
    (destination/'releases'/f'{version}.json').write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n')
    (destination/'changelogs'/f'{version}.md').write_text(record['changelog'])
    feed = destination/'appcast.xml'; feed.write_bytes(appcast(records+[record]))
    subprocess.run([str(sdk/'sign_update'),'--account',ACCOUNT,str(feed)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run([str(sdk/'sign_update'),'--account',ACCOUNT,'--verify',str(feed)],check=True,stdout=subprocess.DEVNULL)
    return record
if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--dmg',type=pathlib.Path,required=True);parser.add_argument('--notes',type=pathlib.Path,required=True);parser.add_argument('--output',type=pathlib.Path,required=True);args=parser.parse_args()
    record=prepare(args.dmg,args.notes,args.output)
    print('Signed update prepared: '+record['version']+' build '+str(record['build']))
