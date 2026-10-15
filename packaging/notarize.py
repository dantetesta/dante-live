#!/usr/bin/env python3
"""Local Developer ID notarization. Credentials remain in the macOS Keychain."""
import argparse, json, os, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MACHO = {b'\xfe\xed\xfa\xce',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf'}

def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True, stderr=subprocess.STDOUT)

def identity(path, hardened=False):
    details = run('codesign','-d','--verbose=4',path)
    team = re.search(r'^TeamIdentifier=(\w+)$',details,re.M)
    if 'Authority=Developer ID Application:' not in details or not team or 'Timestamp=' not in details:
        raise ValueError('Developer ID signature with secure timestamp required: '+str(path))
    if hardened and '(runtime)' not in details:
        raise ValueError('Hardened Runtime required: '+str(path))
    return team.group(1)

def audit_app(app):
    run('codesign','--verify','--deep','--strict',app)
    team = identity(app, hardened=True)
    count = 0
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink(): continue
        with path.open('rb') as stream: magic = stream.read(4)
        if magic in MACHO:
            if identity(path, hardened=True) != team: raise ValueError('Mixed signing teams in '+str(path))
            count += 1
    return count

def validate_ticket(path, kind):
    run('xcrun','stapler','validate',path)
    args = ['spctl','--assess','--verbose=2','--type','execute' if kind == 'app' else 'open']
    if kind == 'dmg': args += ['--context','context:primary-signature']
    result = run(*args,path)
    if 'Notarized Developer ID' not in result: raise ValueError('Gatekeeper did not confirm notarization')

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--app',type=pathlib.Path);group.add_argument('--dmg',type=pathlib.Path)
    args = parser.parse_args();kind = 'app' if args.app else 'dmg';target = (args.app or args.dmg).resolve()
    profile = os.environ.get('DANTE_NOTARY_PROFILE','').strip()
    if not profile: raise SystemExit('Set DANTE_NOTARY_PROFILE to an existing local notarytool Keychain profile')
    os.umask(0o077)
    build = ROOT/os.environ.get('DANTE_BUILD_DIR','build');build.mkdir(parents=True,exist_ok=True)
    if kind == 'app': print('Audited Developer ID components:',audit_app(target),flush=True)
    else:
        signer = os.environ.get('DANTE_SIGN_IDENTITY','').strip()
        if not signer or signer == '-': raise SystemExit('DMG signing requires DANTE_SIGN_IDENTITY')
        run('codesign','--force','--sign',signer,'--timestamp',target)
        identity(target)
    with tempfile.TemporaryDirectory(prefix='dante-notary-') as temporary:
        archive = target
        if kind == 'app':
            archive = pathlib.Path(temporary)/'DanteLive.zip'
            run('ditto','-c','-k','--keepParent',target,archive)
        submission = json.loads(run('xcrun','notarytool','submit',archive,'--keychain-profile',profile,'--output-format','json'))
        identifier = submission['id']
        (build/f'notarization-{kind}-submission.json').write_text(json.dumps(submission,indent=2)+'\n')
        print(f'Submitted {kind} to Apple: {identifier}; waiting for the result.',flush=True)
        try:
            result = json.loads(run('xcrun','notarytool','wait',identifier,'--keychain-profile',profile,'--timeout','30m','--output-format','json'))
        except subprocess.CalledProcessError as error:
            # Keep the submission ID for inspection/recovery; never resubmit blindly.
            (build/f'notarization-{kind}-wait.txt').write_text(error.output)
            raise SystemExit('Notarization wait failed; inspect the saved submission before retrying')
        (build/f'notarization-{kind}-result.json').write_text(json.dumps(result,indent=2)+'\n')
        log = run('xcrun','notarytool','log',identifier,'--keychain-profile',profile)
        (build/f'notarization-{kind}-log.json').write_text(log)
        if result.get('status') != 'Accepted': raise SystemExit('Apple did not accept the package; inspect the local notarization log')
    run('xcrun','stapler','staple',target)
    validate_ticket(target,kind)
    print(f'{kind}: Apple Accepted, ticket stapled, Gatekeeper Notarized Developer ID',flush=True)

if __name__ == '__main__': main()
