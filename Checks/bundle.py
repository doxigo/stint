import os
from pathlib import Path
import shutil
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='teamwork-bundle-checks-') as tmp:
    root = Path(tmp)
    shutil.copy2('bundle.sh', root / 'bundle.sh')
    (root / 'Resources').mkdir()
    (root / 'Resources/AppIcon.icns').write_bytes(b'fixture')
    (root / 'Info.plist').write_text('fixture')
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
if name == 'xcrun' and 'notarytool' in sys.argv and os.environ.get('FAIL_NOTARY'): sys.exit(1)
''')
    stub.chmod(0o755)
    for name in ['xcode-select', 'swift', 'codesign', 'ditto', 'xcrun', 'security']:
        (bin_dir / name).symlink_to(stub)
    env = {key: value for key, value in os.environ.items() if key not in ['SIGNING_IDENTITY', 'NOTARY_PROFILE', 'NOTARY_KEYCHAIN', 'FAIL_NOTARY']}
    env.update(PATH=str(bin_dir) + os.pathsep + env['PATH'], CI='true')
    for identity, profile in [('', ''), ('ad-hoc', 'profile'), ('Developer ID Application: Fixture (TEST)', '')]:
        run = subprocess.run(['sh', 'bundle.sh'], cwd=root, env=dict(env, SIGNING_IDENTITY=identity, NOTARY_PROFILE=profile), capture_output=True)
        assert run.returncode != 0, 'missing/invalid signing credentials must fail'
        assert not (root / '.build').exists(), 'signing preflight must run before building'
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
    submit = next(i for i, line in enumerate(calls) if 'notarytool submit' in line)
    staple = next(i for i, line in enumerate(calls) if 'stapler staple' in line)
    validate = next(i for i, line in enumerate(calls) if 'stapler validate' in line)
    assert submit < staple < validate < len(calls) - 1
    assert calls[-1].startswith('ditto '), 'zip must be recreated after stapling'
print('All release packaging checks passed.')
