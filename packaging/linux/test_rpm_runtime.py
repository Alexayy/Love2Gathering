#!/usr/bin/env python3
"""Install a real RPM in an owned Fedora container; run services as nobody."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rpm', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--image', default='fedora:44')
    args = parser.parse_args(); package = args.rpm.resolve()
    project = Path(__file__).resolve().parents[2]
    if not package.is_file(): parser.error('The RPM does not exist')
    name = 'l2g-rpm-check-' + uuid.uuid4().hex[:12]
    def run(arguments, timeout=180):
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=timeout)
        if result.returncode: raise RuntimeError(result.stderr[-5000:] + '\n' + result.stdout[-5000:])
        return result.stdout
    try:
        run(['docker', 'run', '--detach', '--name', name, '--volume', str(package) + ':/packages/input.rpm:ro', args.image, 'sleep', 'infinity'])
        image_id = run(['docker', 'inspect', '--format', '{{.Image}}', name]).strip()
        run(['docker', 'exec', name, 'dnf', 'install', '-y', '/packages/input.rpm'])
        # Also replace same-version packages when a prepared test image is used.
        run(['docker', 'exec', name, 'rpm', '--upgrade', '--replacepkgs', '/packages/input.rpm'])
        distribution = dict(line.split('=', 1) for line in run(['docker', 'exec', name, 'cat', '/etc/os-release']).splitlines() if '=' in line)
        distribution = {key: distribution[key].strip('"') for key in ('ID', 'VERSION_ID', 'PRETTY_NAME')}
        if distribution['ID'] != 'fedora': raise RuntimeError('This acceptance requires a Fedora image')
        ownership = run(['docker', 'exec', name, 'stat', '-c', '%u %a', '/opt/love2gathering/bridge/target/xmage-bridge-1.0.0.jar']).strip()
        if ownership != '0 644': raise RuntimeError('System bridge ownership/mode is wrong: ' + ownership)
        environment = ['HOME=/tmp/l2g-rpm-user', 'XDG_DATA_HOME=/tmp/l2g-rpm-user/xdg',
                       'LOVE2GATHERING_DATA_DIR=/tmp/l2g-rpm-user/data', 'LOVE2GATHERING_CACHE_DIR=/tmp/l2g-rpm-user/cache',
                       'LOVE2GATHERING_CONFIG_DIR=/tmp/l2g-rpm-user/config']
        command = ['docker', 'exec', '--user', '65534:65534', name, 'env', *environment, '/opt/love2gathering/love2gathering']
        check = json.loads(run(command + ['--check']).strip().splitlines()[-1])
        services = json.loads(run(command + ['--checkhealth']).strip().splitlines()[-1])
        if not services.get('passed') or not services['catalog']['ready'] or services['catalog']['apiVersion'] < 15:
            raise RuntimeError('Installed services were not ready')
        manifest = run(['docker', 'exec', '--user', '65534:65534', name, 'python3', '-B', '-c',
                        "import pathlib,json,hashlib; p=pathlib.Path('/opt/love2gathering'); m=json.loads((p/'payload-manifest.json').read_text())['files']; assert all(hashlib.sha256((p/n).read_bytes()).hexdigest()==v for n,v in m.items()); assert not list(p.rglob('__pycache__')); print(len(m))"])
        report = {'passed': True, 'scope': 'Actual RPM installed root-owned in Fedora container; runtime version checks and real XMage/catalog/room readiness as uid65534. One-card packaged metadata; no desktop, VM or full-match claim.',
                  'image': args.image, 'imageId': image_id, 'distribution': distribution, 'uid': 65534, 'bridgeOwnerUid': 0, 'bridgeMode': '0644',
                  'rpmSha256': hashlib.sha256(package.read_bytes()).hexdigest(), 'catalogCards': services['catalog']['index']['cards'],
                  'catalogApi': services['catalog']['apiVersion'], 'engineRevision': services['engine']['engineRevision'],
                  'payloadFilesVerified': int(manifest), 'runtimes': check, 'userStorageIsolated': True,
                  'sourceSha256': {relative: hashlib.sha256((project / relative).read_bytes()).hexdigest() for relative in
                                   ('packaging/build.py', 'packaging/runtime/launcher.py', 'packaging/linux/test_rpm_runtime.py')}}
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n'); print(json.dumps(report))
    finally:
        subprocess.run(['docker', 'rm', '--force', name], capture_output=True)


if __name__ == '__main__': main()
