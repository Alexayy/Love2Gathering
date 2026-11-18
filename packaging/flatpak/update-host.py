#!/usr/bin/env python3
"""Host-side update coordination for one exact installer-owned Flatpak prefix.

The application gets a private request file, not host execution permission. Only
after its owned flatpak-run process exits does this host helper verify the job,
delegate to the existing folder installer, verify deployment, and restart it.
"""
import argparse
from datetime import date, datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile

APP_ID = 'io.github.Alexayy.Love2Gathering'
APP_ROOT = '/app/share/Love2Gathering'
MARKER = '.love2gathering-flatpak.json'
HELPER = 'install-flatpak.py'
UPDATER = 'update-host.py'


def document(path, maximum=2 * 1024 * 1024):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise ValueError('Invalid Flatpak update document')
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError('Flatpak update document must be an object')
    return value


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()


def atomic_json(path, value):
    path = Path(path); temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', prefix='.host-update-', dir=path.parent, delete=False) as target:
            temporary = Path(target.name); json.dump(value, target, separators=(',', ':')); target.flush(); os.fsync(target.fileno())
        temporary.replace(path)
    finally:
        if temporary: temporary.unlink(missing_ok=True)


def identity(value):
    version, channel, revision, tag = (value.get(key) for key in ('version', 'channel', 'revision', 'tag'))
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]{0,4}', version):
        raise ValueError('A four-part Flatpak release version is required')
    parts = tuple(map(int, version.split('.'))); date(*parts[:3])
    if parts[3] > 65535 or channel not in ('stable', 'development') or not isinstance(revision, str) or not re.fullmatch('[a-f0-9]{40}', revision):
        raise ValueError('Invalid Flatpak release identity')
    expected = 'v' + version if channel == 'stable' else 'DEV-' + version + '-[1-9][0-9]{0,4}-' + revision[:12]
    if not isinstance(tag, str) or not re.fullmatch(re.escape(expected) if channel == 'stable' else re.escape('DEV-' + version) + r'-[1-9][0-9]{0,4}-' + revision[:12], tag):
        raise ValueError('Flatpak tag does not match its release channel and commit')
    return parts


def owned_installer(prefix):
    prefix = Path(prefix)
    if not prefix.is_absolute() or prefix.is_symlink() or prefix.resolve() != prefix:
        raise ValueError('Invalid Flatpak installation folder')
    state = document(prefix / MARKER)
    if state.get('appId') != APP_ID or state.get('prefix') != str(prefix) or not isinstance(state.get('files'), dict):
        raise ValueError('The Flatpak installation is not owned by this helper')
    for name in (HELPER, UPDATER):
        path = prefix / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 2 * 1024 * 1024 or state['files'].get(name) != digest(path):
            raise ValueError('A Flatpak host helper was changed; it was preserved')
    spec = importlib.util.spec_from_file_location('love2gathering_owned_flatpak_installer', prefix / HELPER)
    module = importlib.util.module_from_spec(spec); previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True; spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    paths = module.resources(prefix)
    module.validate_registration(prefix, paths, module.read_state(prefix), {path: module.snapshot(path) for path in paths.values()})
    return module


def deployment(flatpak, prefix, env, *, run=subprocess.run):
    def info(flag):
        return run([flatpak, '--user', 'info', flag, APP_ID], env=env, check=True, capture_output=True, text=True).stdout.strip()
    location = Path(info('--show-location'))
    if not location.is_absolute() or not location.is_dir(): raise ValueError('Native Flatpak deployment location is unavailable')
    location = location.resolve(); owned = (Path(prefix) / 'app' / APP_ID).resolve()
    if owned not in location.parents: raise ValueError('Native Flatpak deployment belongs to another installation')
    commit, ref = info('--show-commit'), info('--show-ref')
    if not re.fullmatch('[a-f0-9]{64}', commit) or ref != 'app/' + APP_ID + '/x86_64/stable':
        raise ValueError('Native Flatpak deployment has an unexpected identity')
    app = location / 'files/share/Love2Gathering'
    if app.resolve() != app: raise ValueError('Native Flatpak application metadata redirects outside its deployment')
    release = document(app / 'release.json', 32 * 1024)
    if release.get('applicationId') != APP_ID: raise ValueError('Native deployment is not Love2Gathering')
    value = dict(version=release.get('version'), channel=release.get('channel'), revision=release.get('sourceRevision'),
                 tag=release.get('tag'), builtAtUTC=release.get('builtAtUTC'), commit=commit, ref=ref, location=str(location))
    identity(value)
    return value


def context_for(installed, session):
    value = {key: installed[key] for key in ('version', 'channel', 'revision', 'tag', 'builtAtUTC')}
    value.update(schema=1, token=secrets.token_urlsafe(40), root=APP_ROOT, method='flatpak', externalHost=True,
                 requestPath=str(session / 'update-request.json'), workDirectory=str(session / 'updates'))
    atomic_json(session / 'update-context.json', value)
    return value


def validate_job(context, job):
    if type(job.get('schema')) is not int or job['schema'] != 1:
        raise ValueError('Unsupported Flatpak update request')
    for key in ('token', 'root', 'method', 'channel'):
        if not isinstance(job.get(key), str) or not secrets.compare_digest(job[key], context[key]):
            raise ValueError('Flatpak update request does not belong to this launch')
    if job['method'] != 'flatpak' or job['root'] != APP_ROOT or identity(job) <= identity(context):
        raise ValueError('Flatpak update must be newer and use this installation channel')
    name = 'Love2Gathering-' + job['version'] + '-x86_64.flatpak'
    installer = Path(job.get('installerPath', '')); work = Path(context['workDirectory'])
    if not installer.is_absolute() or installer.parent != work or installer.resolve() != installer or work.is_symlink() or installer.name != name:
        raise ValueError('Invalid staged Flatpak bundle path')
    size = job.get('expectedSize'); checksum = job.get('checksum')
    if type(size) is not int or not 0 < size <= 8 * 1024 ** 3 or not isinstance(checksum, str) or not re.fullmatch('[a-f0-9]{64}', checksum):
        raise ValueError('Invalid Flatpak bundle size or checksum')
    candidate = hashlib.sha256((job['tag'] + '\n' + name + '\n' + str(size) + '\n' + checksum).encode()).hexdigest()
    if job.get('candidateId') != candidate: raise ValueError('Flatpak candidate identity changed')
    info = installer.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size != size or digest(installer) != checksum:
        raise ValueError('Flatpak bundle changed; download it again')
    return installer


def coordinate(prefix, args=(), *, run=subprocess.run, spawn=subprocess.Popen, which=shutil.which, session_base=None, maximum_updates=4):
    prefix = Path(prefix)
    if not prefix.is_absolute() or prefix.is_symlink() or prefix.resolve() != prefix:
        raise ValueError('Choose the exact owned Flatpak installation folder')
    helper = owned_installer(prefix)
    flatpak = which('flatpak')
    if not flatpak: raise ValueError('The host Flatpak runtime is unavailable')
    env = dict(os.environ, FLATPAK_USER_DIR=str(prefix), PYTHONDONTWRITEBYTECODE='1')
    env.pop('LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT', None); env.pop('LOVE2GATHERING_UPDATE_CONTEXT', None)
    base = Path(session_base) if session_base else Path.home() / '.var/app' / APP_ID / 'data/love2gathering/runtime'
    if not base.is_absolute() or base.is_symlink() or base.resolve() != base or prefix == base or prefix in base.parents:
        raise ValueError('Host update sessions must remain outside the Flatpak installation')
    base.mkdir(parents=True, exist_ok=True)
    for _ in range(maximum_updates + 1):
        session = Path(tempfile.mkdtemp(prefix='host-update-', dir=base)); context = None
        try:
            installed = deployment(flatpak, prefix, env, run=run)
            context = context_for(installed, session)
        except (ValueError, OSError, subprocess.CalledProcessError) as error:
            # Old/non-release deployments can still launch normally. They do
            # not receive host-update authorization from missing metadata.
            print('Automatic Flatpak update is unavailable: ' + str(error), file=sys.stderr)
        command = [flatpak, '--user', 'run']
        if context: command.append('--env=LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT=' + str(session / 'update-context.json'))
        command.extend([APP_ID, *args])
        child = spawn(command, env=env)
        code = child.wait()
        request = session / 'update-request.json'
        if code or not context or not request.exists(): return code
        try:
            job = document(request); installer = validate_job(context, job)
            current = deployment(flatpak, prefix, env, run=run)
            if any(current[key] != installed[key] for key in ('version', 'revision', 'tag', 'channel', 'commit')):
                raise ValueError('The Flatpak installation changed while the application was open; reopen it before updating')
            helper = owned_installer(prefix)
            with helper.operation_lock():
                ref, commit = helper.import_verified_bundle(flatpak, prefix, installer, env)
            # The existing helper owns repository origin checks, native update,
            # registration rollback, user modifications and preservation rules.
            run([sys.executable, str(prefix / HELPER), str(installer), '--prefix', str(prefix)], env=env, check=True)
            actual = deployment(flatpak, prefix, env, run=run)
            if actual['commit'] != commit or actual['ref'] != ref or any(actual[key] != job[key] for key in ('version', 'revision', 'tag', 'channel')):
                raise ValueError('The active Flatpak deployment does not match the verified selected release')
            request.rename(session / 'update-request.accepted.json')
            atomic_json(session / 'update-result.json', dict(state='installed', version=job['version'], commit=commit, prefix=str(prefix)))
        except Exception as error:
            atomic_json(session / 'update-result.json', dict(state='error', message=str(error)))
            raise
    raise ValueError('Too many consecutive Flatpak updates; reopen the application')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('arguments', nargs=argparse.REMAINDER); args = parser.parse_args(argv)
    arguments = args.arguments[1:] if args.arguments[:1] == ['--'] else args.arguments
    return coordinate(args.prefix, arguments)


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print('Flatpak update was not installed: ' + str(error), file=sys.stderr); raise SystemExit(1)
