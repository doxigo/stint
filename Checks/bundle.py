import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='teamwork-bundle-checks-') as tmp:
    root = Path(tmp)
    shutil.copy2('bundle.sh', root / 'bundle.sh')
    (root / 'Resources').mkdir()
    (root / 'Resources/AppIcon.icns').write_bytes(b'fixture')
    (root / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'fixture'}))
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    stub = bin_dir / 'stub'
    stub.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open('calls', 'a') as out: out.write(name + ' ' + ' '.join(sys.argv[1:]) + '\\n')
if name == 'xcode-select': print('/fixture/Xcode.app/Contents/Developer')
if name == 'swift':
    pathlib.Path('.build/release').mkdir(parents=True, exist_ok=True)
    pathlib.Path('.build/release/TeamworkTimer').write_text('fixture')
if name == 'ditto': pathlib.Path(sys.argv[-1]).write_text('archive')
if name == 'hdiutil': pathlib.Path(sys.argv[-1]).write_text('disk image')
if name == 'xcrun' and 'notarytool' in sys.argv and os.environ.get('FAIL_NOTARY'): sys.exit(1)
''')
    stub.chmod(0o755)
    for name in ['xcode-select', 'swift', 'codesign', 'ditto', 'xcrun', 'security', 'hdiutil']:
        (bin_dir / name).symlink_to(stub)
    env = {key: value for key, value in os.environ.items()
           if key not in ['SIGNING_IDENTITY', 'NOTARY_PROFILE', 'NOTARY_KEYCHAIN', 'FAIL_NOTARY', 'TEAMWORK_CLIENT_ID', 'TEAMWORK_CLIENT_SECRET']}
    env.update(PATH=str(bin_dir) + os.pathsep + env['PATH'], CI='true')
    for identity, profile in [('', ''), ('ad-hoc', 'profile'), ('Developer ID Application: Fixture (TEST)', '')]:
        run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, SIGNING_IDENTITY=identity, NOTARY_PROFILE=profile), capture_output=True)
        assert run.returncode != 0, 'missing/invalid signing credentials must fail'
        assert not (root / '.build').exists(), 'signing preflight must run before building'
    built = root / 'build/Stint.app/Contents/Info.plist'
    run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, UNSIGNED_RELEASE='1', TEAMWORK_CLIENT_ID='id "x"'), capture_output=True)
    assert run.returncode == 0, run.stderr.decode()
    info = plistlib.loads(built.read_bytes())
    assert info.get('TeamworkClientID') == 'id "x"' and 'TeamworkClientSecret' not in info, 'a built-in client ID goes into the built app'
    assert 'TeamworkClientID' not in plistlib.loads((root / 'Info.plist').read_bytes()), 'the source Info.plist is left alone'
    (root / 'calls').unlink()
    run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, UNSIGNED_RELEASE='1', TEAMWORK_CLIENT_ID='id', TEAMWORK_CLIENT_SECRET='s'), capture_output=True)
    assert run.returncode == 0, run.stderr.decode()
    assert plistlib.loads(built.read_bytes()).get('TeamworkClientSecret') == 's', 'a built-in client secret goes in when CI has one'
    (root / 'calls').unlink()
    run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, UNSIGNED_RELEASE='1'), capture_output=True)
    assert run.returncode == 0, run.stderr.decode()
    assert 'TeamworkClientID' not in plistlib.loads(built.read_bytes()), 'no built-in client without the secret'
    calls = (root / 'calls').read_text()
    assert 'codesign --force --sign -' in calls, 'explicit unsigned release is ad-hoc signed'
    assert 'notarytool' not in calls and 'stapler' not in calls, 'unsigned release never claims notarization'
    assert (root / 'build/Stint.dmg').exists(), 'unsigned release produces the disk image'
    (root / 'calls').unlink()
    env.update(SIGNING_IDENTITY='Developer ID Application: Fixture (TEST)', NOTARY_PROFILE='profile')
    run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, FAIL_NOTARY='1'), capture_output=True)
    assert run.returncode != 0, 'notarization rejection must fail the build'
    calls = (root / 'calls').read_text()
    assert 'stapler staple' not in calls, 'rejected builds must not be stapled'
    (root / 'calls').unlink()
    run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=env, capture_output=True)
    assert run.returncode == 0, run.stderr.decode()
    calls = (root / 'calls').read_text().splitlines()
    assert any('--options runtime --timestamp' in line for line in calls)
    assert any('codesign --verify --deep --strict' in line for line in calls)
    image = next(i for i, line in enumerate(calls) if line.startswith('hdiutil create'))
    signed = next(i for i, line in enumerate(calls) if line.startswith('codesign') and 'Stint.dmg' in line)
    submit = next(i for i, line in enumerate(calls) if 'notarytool submit build/Stint.dmg' in line)
    staple = next(i for i, line in enumerate(calls) if 'stapler staple build/Stint.dmg' in line)
    validate = next(i for i, line in enumerate(calls) if 'stapler validate build/Stint.dmg' in line)
    assert image < signed < submit < staple < validate, 'disk image is signed, then notarized, then stapled'
    assert '--options runtime' in calls[next(i for i, line in enumerate(calls) if line.startswith('codesign --force'))], 'app is signed with the hardened runtime first'
# The app takes its sign-in redirect (appRedirect in Models.swift); the repo never carries a client.
source = plistlib.loads(Path('Info.plist').read_bytes())
assert ['stint'] in [kind.get('CFBundleURLSchemes') for kind in source.get('CFBundleURLTypes', [])], 'Info.plist registers stint://'
assert not any(key.startswith('TeamworkClient') for key in source), 'Info.plist in the repo has no client ID or secret'
print('All release packaging checks passed.')
