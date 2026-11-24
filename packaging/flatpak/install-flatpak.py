#!/usr/bin/env python3
"""Choose a per-user Flatpak location, preserving unrelated files and saved data."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

APP_ID = 'io.github.Alexayy.Love2Gathering'
MARKER = '.love2gathering-flatpak.json'
HELPER = 'install-flatpak.py'
UPDATE_HELPER = 'update-host.py'
# Recognize the exact pre-release helper used by the first native acceptance.
LEGACY_HELPER_SHA256 = 'd8228689d8ff1d83765519bae485c3dcc2f6e48384872dea59b75d81e74f6727'


def data_home():
    value = os.environ.get('XDG_DATA_HOME', '')
    return Path(value).resolve() if value and Path(value).is_absolute() else Path.home() / '.local/share'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def desktop_string(value):
    return str(value).replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')


def desktop_escape(value):
    # General desktop-string unescaping happens before Exec argument unquoting.
    value = str(value).replace('%', '%%')
    for char in ('\\', '"', '$', '`'):
        value = value.replace(char, '\\' + char)
    return desktop_string('"' + value + '"')


def legacy_wrapper_text(prefix):
    return '#!/bin/sh\nexport FLATPAK_USER_DIR=' + shlex.quote(str(prefix)) + '\nexec flatpak --user run ' + APP_ID + ' "$@"\n'


def wrapper_text(prefix):
    return '#!/bin/sh\nexec python3 ' + shlex.quote(str(prefix / UPDATE_HELPER)) + ' --prefix ' + shlex.quote(str(prefix)) + ' -- "$@"\n'


def desktop_text(prefix):
    return '\n'.join([
        '[Desktop Entry]', 'Version=1.0', 'Type=Application',
        'Name=Love: 2 Gathering (Flatpak)', 'Comment=XMage card game client',
        'Exec=/bin/sh ' + desktop_escape(prefix / 'love2gathering'),
        'Icon=' + desktop_string(prefix / 'exports/share/icons/hicolor/256x256/apps' / (APP_ID + '.png')),
        'Terminal=false', 'Categories=Game;CardGame;',
        'X-Love2Gathering-Managed=1', 'X-Love2Gathering-InstallRoot=' + desktop_string(prefix), '',
    ])


def snapshot(path):
    if path.is_symlink():
        return ('link', os.readlink(path))
    if path.exists():
        if not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('An installer helper path contains an unrelated or oversized file: ' + str(path))
        return ('file', path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
    return None


def selected_prefix(value):
    raw = Path(value).expanduser()
    if not raw.is_absolute() or any(ord(char) < 32 for char in str(raw)):
        raise ValueError('Choose an absolute dedicated installation folder without control characters')
    if raw.is_symlink():
        raise ValueError('The Flatpak installation folder cannot be a symbolic link')
    prefix = raw.parent.resolve() / raw.name
    if prefix in (Path('/'), Path('/usr'), Path('/etc'), Path('/bin'), Path('/lib'), Path.home().resolve(), data_home()):
        raise ValueError('Choose a dedicated Flatpak installation folder')
    if prefix.exists() and not prefix.is_dir():
        raise ValueError('The selected installation path is not a directory')
    if (prefix / 'repo').is_symlink() or (prefix / 'repo/config').is_symlink():
        raise ValueError('The selected repository must not redirect through a symbolic link')
    return prefix


def read_state(prefix):
    path = prefix / MARKER
    value = snapshot(path)
    if value is None:
        return None
    if value[0] != 'file':
        raise ValueError('The installation ownership marker cannot be a symbolic link')
    state = json.loads(value[1].decode('utf-8'))
    if not isinstance(state, dict):
        raise ValueError('Invalid Flatpak installer ownership metadata')
    if state.get('appId') != APP_ID or state.get('prefix') != str(prefix):
        raise ValueError('Installation ownership does not match the chosen folder')
    if state.get('schema', 1) not in (1, 2) or not isinstance(state.get('desktopText'), str):
        raise ValueError('Invalid Flatpak installer ownership metadata')
    files = state.get('files', {})
    if not isinstance(files, dict) or set(files) - {'love2gathering', HELPER, UPDATE_HELPER}:
        raise ValueError('Invalid installer-owned file list')
    if any(not isinstance(value, str) or len(value) != 64 for value in files.values()):
        raise ValueError('Invalid installer-owned file checksum')
    return state


def owned_file(prefix, name, state, value):
    if value is None:
        return True
    if state is None or value[0] != 'file':
        return False
    expected = state.get('files', {}).get(name)
    if expected:
        return digest(value[1]) == expected
    if state.get('schema', 1) == 1:
        if name == 'love2gathering':
            return value[1] == legacy_wrapper_text(prefix).encode('utf-8')
        return digest(value[1]) == LEGACY_HELPER_SHA256
    return False


def resources(prefix):
    return {
        'wrapper': prefix / 'love2gathering', 'helper': prefix / HELPER,
        'updater': prefix / UPDATE_HELPER,
        'marker': prefix / MARKER,
        'desktop': data_home() / 'applications' / (APP_ID + '-local.desktop'),
        'link': Path.home() / '.local/bin/love2gathering-flatpak',
    }


def validate_registration(prefix, paths, state, before):
    for key, name in (('wrapper', 'love2gathering'), ('helper', HELPER), ('updater', UPDATE_HELPER)):
        if not owned_file(prefix, name, state, before[paths[key]]):
            raise ValueError('Refusing to replace an unrelated or modified file: ' + str(paths[key]))
    value = before[paths['link']]
    if value is not None and not (state and value == ('link', str(paths['wrapper']))):
        raise ValueError('An unrelated or dangling love2gathering-flatpak command already exists')
    value = before[paths['desktop']]
    if value is not None and not (state and value[0] == 'file' and value[1] == state['desktopText'].encode('utf-8')):
        raise ValueError('An unrelated or modified application shortcut already exists')


def atomic_file(path, value, mode, previous):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / ('.love2gathering-flatpak-' + uuid.uuid4().hex)
    try:
        with temporary.open('xb') as stream:
            stream.write(value)
        temporary.chmod(mode)
        if previous is None:
            os.link(temporary, path, follow_symlinks=False)
        else:
            os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_link(path, target, previous):
    path.parent.mkdir(parents=True, exist_ok=True)
    if previous is None:
        path.symlink_to(target)
        return
    temporary = path.parent / ('.love2gathering-flatpak-link-' + uuid.uuid4().hex)
    try:
        temporary.symlink_to(target);os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def register(prefix, paths, before, source_dir=None):
    source_dir=Path(source_dir)if source_dir is not None else Path(__file__).resolve().parent
    wrapper = wrapper_text(prefix).encode('utf-8')
    helper = (source_dir/HELPER).read_bytes()
    updater = (source_dir/UPDATE_HELPER).read_bytes()
    text = desktop_text(prefix)
    state = {'schema': 2, 'appId': APP_ID, 'prefix': str(prefix), 'desktopText': text,
             'files': {'love2gathering': digest(wrapper), HELPER: digest(helper), UPDATE_HELPER: digest(updater)}}
    writes = []
    try:
        for key, value, mode in [('wrapper', wrapper, 0o755), ('helper', helper, 0o755), ('updater', updater, 0o755), ('desktop', text.encode('utf-8'), 0o644)]:
            path = paths[key]
            atomic_file(path, value, mode, before[path]);writes.append((path, snapshot(path)))
        path = paths['link'];atomic_link(path, str(paths['wrapper']), before[path]);writes.append((path, snapshot(path)))
        path = paths['marker'];atomic_file(path, (json.dumps(state, indent=2) + '\n').encode('utf-8'), 0o600, before[path]);writes.append((path, snapshot(path)))
    except Exception:
        # Restore only writes still matching our version. A concurrent user edit
        # is retained rather than overwritten during rollback.
        for path, installed in reversed(writes):
            if snapshot(path) != installed:
                continue
            previous = before[path]
            if previous is None:
                path.unlink()
            elif previous[0] == 'link':
                atomic_link(path, previous[1], installed)
            else:
                atomic_file(path, previous[1], previous[2], installed)
        raise


def import_verified_bundle(flatpak, prefix, bundle, env):
    # Import verifies the native bundle without retiring the working deployment.
    # Flatpak 1.14's local-bundle path ignores --or-update and can reject even
    # --reinstall, so an existing ref is updated from this verified local commit.
    result = subprocess.run([flatpak, 'build-import-bundle',
                             str(prefix / 'repo'), str(bundle.resolve())],
                            env=dict(env, LC_ALL='C'), capture_output=True, text=True, check=True)
    matches = re.findall(r'^Importing (app/\S+) \(([0-9a-f]{64})\)\s*$', result.stdout, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('The bundle import did not report one verified application commit')
    ref, commit = matches[0]
    parts = ref.split('/')
    if len(parts) != 4 or parts[:2] != ['app', APP_ID] or not all(parts[2:]):
        raise ValueError('The selected bundle is not a Love2Gathering application')
    return ref, commit


def enable_owned_bundle_origin(prefix, ref, run):
    origin = run('info', '--show-origin', ref, capture=True).stdout.strip()
    if origin != 'love2gathering-origin':
        raise ValueError('The installed app uses another source. Choose a dedicated Flatpak folder instead of changing a shared remote.')
    rows = run('list', '--columns=ref,origin', capture=True).stdout.splitlines()
    owners = []
    for row in rows:
        values = row.split()
        if len(values) == 2 and values[1] == origin:
            owners.append(values[0])
    if not owners or any(not (value[4:] if value.startswith('app/') else value).startswith(APP_ID + '/') for value in owners):
        raise ValueError('The bundle source is shared with another application; its configuration was preserved.')
    remotes = run('remotes', '--show-disabled', '--columns=name,url', capture=True).stdout.splitlines()
    url = None
    for row in remotes:
        values = row.split(None, 1)
        if values and values[0] == origin:
            url = values[1] if len(values) > 1 else ''
    local_url = (prefix / 'repo').as_uri()
    if url not in ('', local_url):
        raise ValueError('The bundle source URL was changed outside this installer; it was preserved.')
    # Empty-URL bundle origins are disabled in Flatpak 1.14. An encoded local
    # URL enables a normal pinned-commit update; --no-pull ignores the requested
    # commit on that version. Only this exclusive application origin is changed.
    run('remote-modify', '--url=' + local_url, '--enable', origin)


def choose_prefix():
    if os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
        for command, args in [('zenity', ['--file-selection', '--directory', '--title=Choose a dedicated Flatpak installation folder']), ('kdialog', ['--getexistingdirectory', str(Path.home()), '--title', 'Choose a dedicated Flatpak installation folder'])]:
            program = shutil.which(command)
            if program:
                result = subprocess.run([program, *args], capture_output=True, text=True)
                return Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else None
    if sys.stdin.isatty():
        return Path(input('Flatpak folder [~/.local/share/Love2Gathering-flatpak]: ').strip() or '~/.local/share/Love2Gathering-flatpak')
    raise ValueError('Provide --prefix /mnt/Games/Flatpak when no folder chooser is available')


@contextmanager
def operation_lock():
    path = Path(tempfile.gettempdir()) / ('love2gathering-flatpak-installer-' + str(os.getuid()) + '.lock')
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if os.fstat(fd).st_uid != os.getuid():
            raise ValueError('Installer lock belongs to another user')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another Flatpak installer is running; finish it first') from None
        yield
    finally:
        os.close(fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', nargs='?', type=Path, help='Local .flatpak bundle')
    parser.add_argument('--prefix', type=Path, help='Chosen dedicated Flatpak directory, for example /mnt/Games/Flatpak')
    parser.add_argument('--uninstall', action='store_true', help='Remove this app and unchanged owned shortcuts; keep saved data and repository')
    args = parser.parse_args(argv)
    flatpak = shutil.which('flatpak')
    if not flatpak:
        raise ValueError('Install Flatpak using your distribution package manager first')
    selected = args.prefix if args.prefix is not None else choose_prefix()
    if selected is None:
        print('Installation cancelled; no files changed.')
        return 1
    prefix = selected_prefix(selected)
    paths = resources(prefix)
    env = dict(os.environ, FLATPAK_USER_DIR=str(prefix))

    def run(*items, capture=False):
        return subprocess.run([flatpak, '--user', *items], env=env, check=True,
                              capture_output=capture, text=capture)

    with operation_lock():
        state = read_state(prefix)
        before = {path: snapshot(path) for path in paths.values()}
        if args.uninstall:
            if state is None:
                raise ValueError('This is not a recognized installer-owned Flatpak folder')
            run('uninstall', '--assumeyes', APP_ID)
            preserved = []
            for key, name in [('wrapper', 'love2gathering'), ('helper', HELPER), ('updater', UPDATE_HELPER)]:
                path = paths[key];value = snapshot(path)
                if value is not None:
                    if owned_file(prefix, name, state, value):path.unlink()
                    else:preserved.append(str(path))
            path = paths['link']
            if snapshot(path) == ('link', str(paths['wrapper'])):path.unlink()
            path = paths['desktop'];value = snapshot(path)
            if value is not None:
                if value[0] == 'file' and value[1] == state['desktopText'].encode('utf-8'):path.unlink()
                else:preserved.append(str(path))
            if snapshot(paths['marker']) == before[paths['marker']]:paths['marker'].unlink()
            if preserved:print('Preserved changed/unrelated files: ' + ', '.join(preserved))
            print('Application removed. Saved data, image cache and the Flatpak repository were retained.')
            return 0
        bundle = args.bundle or next(Path(__file__).resolve().parent.glob('Love2Gathering-*-x86_64.flatpak'), None)
        if bundle is None or not bundle.is_file():
            raise ValueError('Provide the downloaded .flatpak bundle')
        if prefix.exists() and any(prefix.iterdir()) and state is None and not (prefix / 'repo/config').is_file():
            raise ValueError('The selected folder contains unrelated files; choose an empty or existing Flatpak installation')
        validate_registration(prefix, paths, state, before)
        prefix.mkdir(parents=True, exist_ok=True)
        run('remote-add', '--if-not-exists', 'flathub', 'https://flathub.org/repo/flathub.flatpakrepo')
        ref, commit = import_verified_bundle(flatpak, prefix, bundle, env)
        installed = run('list', '--app', '--columns=ref', capture=True).stdout.splitlines()
        if ref[4:] in [(value.strip()[4:] if value.strip().startswith('app/') else value.strip()) for value in installed]:
            current = run('info', '--show-commit', ref, capture=True).stdout.strip()
            if current != commit:
                enable_owned_bundle_origin(prefix, ref, run)
                run('update', '--assumeyes', '--noninteractive', '--commit=' + commit, ref)
        else:
            run('install', '--assumeyes', '--noninteractive', str(bundle.resolve()))
        deployed = run('info', '--show-commit', ref, capture=True).stdout.strip()
        if deployed != commit:
            raise ValueError('The deployed application does not match the verified bundle commit; shortcuts were not changed')
        if any(snapshot(path) != previous for path, previous in before.items()):
            raise ValueError('Installer helper files changed during Flatpak installation; they were preserved. Run this helper again to register shortcuts.')
        # A complete new bundle can refresh the host coordinator as well. The
        # native deployment/commit has already been checked above; no external
        # helper URL or user file is trusted as an executable source.
        source_dir=None
        location=Path(run('info','--show-location',ref,capture=True).stdout.strip())
        if location.is_absolute()and location.is_dir():
            location=location.resolve();owned=(prefix/'app'/APP_ID).resolve()
            tools=location/'files/share/Love2Gathering/host-tools'
            if owned in location.parents and tools.resolve()==tools and all((tools/name).is_file()and not(tools/name).is_symlink()for name in(HELPER,UPDATE_HELPER)):
                source_dir=tools
        register(prefix, paths, before, source_dir)
        print('Installed in ' + str(prefix) + '. Open Love: 2 Gathering (Flatpak) from the application menu.')
        return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr);raise SystemExit(1)
