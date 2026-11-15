#!/usr/bin/env python3
"""Install a release into a chosen folder without moving or deleting user saves."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

APP_ID = 'io.github.Alexayy.Love2Gathering'
MARKER = '.love2gathering-install.json'
DESKTOP_NAME = APP_ID + '.desktop'
MAX_FILES = 50000
MAX_ARCHIVE_BYTES = 4 * 1024 ** 3
RESERVED = {MARKER, '.installer', 'uninstall.sh'}
HERE = Path(__file__).resolve().parent


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def inside(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def clean_relative(value):
    path = PurePosixPath(value)
    if not value or not path.parts or path.is_absolute() or '..' in path.parts or '\\' in value or '\x00' in value:
        raise ValueError('Unsafe package path: ' + repr(value))
    return Path(*path.parts)


def selected_prefix(value):
    raw = Path(value).expanduser()
    if not raw.is_absolute():
        raise ValueError('Choose an absolute installation folder, for example /mnt/Games/Love2Gathering')
    if any(ord(char) < 32 for char in str(raw)):
        raise ValueError('The installation path cannot contain control characters')
    if raw.is_symlink():
        raise ValueError('The installation folder itself cannot be a symbolic link')
    # Resolve the deliberately selected parent, then never follow nested links.
    prefix = raw.parent.resolve() / raw.name
    if prefix in (Path('/'), Path.home().resolve(), data_home()):
        raise ValueError('Choose a dedicated Love2Gathering folder, not a root/home/data directory')
    return prefix


def data_home():
    value = os.environ.get('XDG_DATA_HOME', '')
    return Path(value).resolve() if value and Path(value).is_absolute() else Path.home() / '.local/share'


def quote_desktop(value):
    return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')


def quote_exec(value):
    # Desktop string unescaping precedes Exec argument unquoting. Literal % is
    # doubled so a folder such as Games 100% cannot introduce a field code.
    value = value.replace('%', '%%')
    for char in ('\\', '"', '`', '$'):
        value = value.replace(char, '\\' + char)
    return quote_desktop('"' + value + '"')


def desktop_entry(prefix):
    prefix = Path(prefix)
    return '\n'.join([
        '[Desktop Entry]', 'Version=1.0', 'Type=Application', 'Name=Love: 2 Gathering',
        'Comment=Play Magic with XMage, local bots and private multiplayer rooms',
        # The executable is constant; a selected path containing = is an
        # argument to sh, not an executable name forbidden by the specification.
        'Exec=/bin/sh ' + quote_exec(str(prefix / 'love2gathering')),
        'Icon=' + quote_desktop(str(prefix / 'share/icons/love2gathering.png')),
        'Terminal=false', 'Categories=Game;CardGame;', 'Keywords=MTG;Magic;Commander;XMage;',
        'StartupNotify=true', 'X-Love2Gathering-Managed=1',
        'X-Love2Gathering-InstallRoot=' + quote_desktop(str(prefix)), '',
    ])


def tree_files(root):
    items = []
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if len(items) >= MAX_FILES:
            raise ValueError('Package contains too many files')
        if path.is_symlink():
            target = os.readlink(path)
            if Path(target).is_absolute() or not inside((path.parent / target).resolve(), root.resolve()):
                raise ValueError('Package link leaves its folder: ' + relative)
            items.append({'path': relative, 'kind': 'link', 'target': target})
        elif path.is_file():
            items.append({'path': relative, 'kind': 'file', 'sha256': digest(path)})
        elif not path.is_dir():
            raise ValueError('Package contains an unsupported special file: ' + relative)
    return items


def matches(path, item):
    if item['kind'] == 'link':
        return path.is_symlink() and os.readlink(path) == item['target']
    return not path.is_symlink() and path.is_file() and digest(path) == item['sha256']


def read_marker(prefix):
    path = prefix / MARKER
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('This folder is not an installation owned by this installer: ' + str(prefix))
    result = json.loads(path.read_text(encoding='utf-8'))
    if result.get('appId') != APP_ID or result.get('schema') != 1 or result.get('prefix') != str(prefix):
        raise ValueError('Installation ownership does not match the chosen folder')
    files = result.get('files')
    if not isinstance(files, list) or len(files) > MAX_FILES:
        raise ValueError('Invalid installed-file manifest')
    for item in files:
        clean_relative(item['path'])
        if item.get('kind') not in ('file', 'link'):
            raise ValueError('Invalid installed-file type')
    if len(result.get('directories', [])) > MAX_FILES:
        raise ValueError('Invalid installed-directory manifest')
    for value in result.get('directories', []):
        clean_relative(value)
    return result


def no_link_parents(path, root):
    parent = path.parent
    while parent != root:
        if not inside(parent, root) or parent.is_symlink():
            raise ValueError('Refusing to follow a link in the installation: ' + str(parent))
        parent = parent.parent


def preflight(payload):
    if sys.version_info < (3, 10):
        raise ValueError('Python 3.10 or newer is required')
    executable = payload / 'love2gathering'
    if not executable.is_file() or executable.is_symlink():
        raise ValueError('Release payload is missing its love2gathering launcher')
    if not (payload / 'share/icons/love2gathering.png').is_file():
        raise ValueError('Release payload is missing its application icon')
    love = shutil.which('love')
    if not love:
        raise ValueError('Install LÖVE 11.5 first (the system package is normally named love)')
    version = subprocess.run([love, '--version'], capture_output=True, text=True, timeout=10)
    if version.returncode or not re.search(r'\b11\.5\b', version.stdout + version.stderr):
        raise ValueError('LÖVE 11.5 is required; the installed love command reports another version')
    java = payload / 'runtime/java/bin/java'
    if not java.is_file():
        java = payload / 'runtime/jre/bin/java'  # Older locally assembled payloads.
    if not java.is_file() or not os.access(java, os.X_OK):
        raise ValueError('Release payload is missing its bundled Java runtime')
    version = subprocess.run([str(java), '-version'], capture_output=True, text=True, timeout=10)
    if version.returncode or not re.search(r'(?:version\s+"|openjdk\s+)21(?:[.\s"]|$)', version.stdout + version.stderr):
        raise ValueError('The bundled release requires a working Java 21 runtime')


def integration_paths(desktop_shortcut):
    result = {'menu': data_home() / 'applications' / DESKTOP_NAME,
              'command': Path.home() / '.local/bin/love2gathering'}
    if desktop_shortcut:
        desktop = None
        helper = shutil.which('xdg-user-dir')
        if helper:
            found = subprocess.run([helper, 'DESKTOP'], capture_output=True, text=True, timeout=5)
            value = found.stdout.strip()
            if found.returncode == 0 and value and Path(value).is_absolute():
                desktop = Path(value)
        result['desktop'] = (desktop or Path.home() / 'Desktop') / DESKTOP_NAME
    return result


def owned_desktop(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 65536:
        return False
    text = path.read_text(encoding='utf-8')
    return '\nX-Love2Gathering-Managed=1\n' in text and '\nX-Love2Gathering-InstallRoot=' in text


def check_integrations(paths):
    for key, path in paths.items():
        if not path.exists() and not path.is_symlink():
            continue
        if key == 'command':
            if not path.is_symlink():
                raise ValueError('The command path already contains an unrelated file: ' + str(path))
            candidate = (path.parent / os.readlink(path)).resolve()
            try:
                read_marker(candidate.parent)
            except (ValueError, OSError):
                raise ValueError('The command link belongs to another installation: ' + str(path)) from None
        elif not owned_desktop(path):
            raise ValueError('A desktop entry with this name already belongs to another application: ' + str(path))


def write_integrations(prefix, paths):
    result = []
    for key, path in paths.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if key == 'command':
            temporary = path.parent / ('.love2gathering-link-' + uuid.uuid4().hex)
            temporary.symlink_to(prefix / 'love2gathering')
            os.replace(temporary, path)
            result.append({'kind': 'link', 'path': str(path), 'target': str(prefix / 'love2gathering')})
        else:
            text = desktop_entry(prefix)
            temporary = path.parent / ('.love2gathering-desktop-' + uuid.uuid4().hex)
            temporary.write_text(text, encoding='utf-8')
            temporary.chmod(0o755 if key == 'desktop' else 0o644)
            os.replace(temporary, path)
            result.append({'kind': 'desktop', 'path': str(path), 'sha256': digest(path)})
    helper = shutil.which('update-desktop-database')
    if helper:
        subprocess.run([helper, str(data_home() / 'applications')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    return result


def integration_snapshot(paths):
    values = {}
    for path in paths.values():
        if path.is_symlink():
            values[path] = ('link', os.readlink(path))
        elif path.exists():
            values[path] = ('file', path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
        else:
            values[path] = None
    return values


def restore_integrations(values):
    for path, previous in values.items():
        if path.exists() or path.is_symlink():
            path.unlink()
        if previous is None:
            continue
        if previous[0] == 'link':
            path.symlink_to(previous[1])
        else:
            path.write_bytes(previous[1]);path.chmod(previous[2])


def unpack(archive, destination):
    total = 0
    hard_links = []
    with tarfile.open(archive, 'r:*') as source:
        members = source.getmembers()
        if len(members) > MAX_FILES:
            raise ValueError('Release archive contains too many entries')
        for item in members:
            if item.isdir() and item.name in ('.', './'):
                continue
            relative = clean_relative(item.name)
            target = destination / relative
            no_link_parents(target, destination)
            if item.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.isfile():
                total += item.size
                if total > MAX_ARCHIVE_BYTES:
                    raise ValueError('Release archive exceeds the size bound')
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(item) as incoming, target.open('xb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
                target.chmod(item.mode & 0o755 | 0o600)
            elif item.issym():
                if Path(item.linkname).is_absolute() or not inside((target.parent / item.linkname).resolve(), destination.resolve()):
                    raise ValueError('Archive link leaves the payload')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(item.linkname)
            elif item.islnk():
                hard_links.append((target, destination / clean_relative(item.linkname)))
            else:
                raise ValueError('Release archive contains an unsupported entry: ' + item.name)
        for target, original in hard_links:
            no_link_parents(target, destination);no_link_parents(original, destination)
            if original.is_symlink() or not original.is_file():
                raise ValueError('Archive hard link has no safe regular-file target')
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(original, target, follow_symlinks=False)
    return total


@contextmanager
def payload_directory(args, parent):
    if args.archive:
        with tempfile.TemporaryDirectory(prefix='.love2gathering-unpack-', dir=parent) as temporary:
            root = Path(temporary)
            unpack(args.archive, root)
            if not (root / 'love2gathering').is_file():
                children = list(root.iterdir())
                if len(children) == 1 and children[0].is_dir():
                    root = children[0]
            yield root
    else:
        default = HERE / 'payload'
        if not default.is_dir():
            default = HERE.parents[1] / 'dist/stage/linux/Love2Gathering'
        yield Path(args.payload or default).expanduser().resolve()


def choose_prefix():
    default = Path.home() / 'Applications/Love2Gathering'
    if os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
        for program, args in (
                ('zenity', ['--file-selection', '--directory', '--title=Choose parent folder for Love2Gathering', '--filename=' + str(default.parent) + '/']),
                ('kdialog', ['--getexistingdirectory', str(default.parent), '--title', 'Choose parent folder for Love2Gathering'])):
            executable = shutil.which(program)
            if executable:
                result = subprocess.run([executable, *args], capture_output=True, text=True)
                if result.returncode:
                    raise ValueError('Installation cancelled')
                chosen = Path(result.stdout.strip())
                return chosen if chosen.name == 'Love2Gathering' else chosen / 'Love2Gathering'
    if sys.stdin.isatty():
        value = input('Installation folder [' + str(default) + ']: ').strip()
        return Path(value) if value else default
    raise ValueError('Choose an installation folder with --prefix /mnt/Games/Love2Gathering (or run from a terminal)')


def confirm(message, yes):
    if yes:
        return
    if sys.stdin.isatty():
        if input(message + ' [y/N] ').strip().lower() in ('y', 'yes'):
            return
    elif os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
        for program, args in (('zenity', ['--question', '--text=' + message]), ('kdialog', ['--yesno', message])):
            executable = shutil.which(program)
            if executable:
                if subprocess.run([executable, *args]).returncode == 0:
                    return
                break
    raise ValueError('No installation changes were approved; use --yes for an unattended install')


def install(args):
    prefix = selected_prefix(args.prefix or choose_prefix())
    prefix.parent.mkdir(parents=True, exist_ok=True)
    if prefix.exists() and not prefix.is_dir():
        raise ValueError('The installation path is not a directory')
    previous = read_marker(prefix) if prefix.exists() and any(prefix.iterdir()) else None
    paths = integration_paths(args.desktop_shortcut)
    check_integrations(paths)
    integration_before = integration_snapshot(paths)
    with payload_directory(args, prefix.parent) as payload:
        preflight(payload)
        files = tree_files(payload)
        if any(PurePosixPath(item['path']).parts[0] in RESERVED for item in files):
            raise ValueError('Payload collides with installer-owned files')
        if inside(prefix.resolve(), payload.resolve()) or inside(payload.resolve(), prefix.resolve()):
            raise ValueError('Payload and installation folders must be separate')
        size = sum((payload / item['path']).stat().st_size for item in files if item['kind'] == 'file')
        old_size = sum(path.stat().st_size for path in prefix.rglob('*') if path.is_file() and not path.is_symlink()) if prefix.exists() else 0
        if shutil.disk_usage(prefix.parent).free < size + old_size + 64 * 1024 ** 2:
            raise ValueError('Not enough free space for the release and a safe update copy')
        confirm(('Update' if previous else 'Install') + ' Love2Gathering in ' + str(prefix) + '? User saves and cached images are kept separately.', args.yes)
        stage = Path(tempfile.mkdtemp(prefix='.love2gathering-install-', dir=prefix.parent))
        backup = prefix.parent / ('.love2gathering-before-' + uuid.uuid4().hex)
        installed = False
        integrations_started = False
        try:
            if previous:
                shutil.copytree(prefix, stage, dirs_exist_ok=True, symlinks=True)
                for item in previous['files']:
                    path = stage / clean_relative(item['path']);no_link_parents(path, stage)
                    if matches(path, item):
                        path.unlink()
                for relative in [item['path'] for item in files] + ['.installer/installer.py', 'uninstall.sh']:
                    path = stage / clean_relative(relative);no_link_parents(path, stage)
                    if path.exists() or path.is_symlink():
                        raise ValueError('Update would replace a changed or user-created file; move it aside first: ' + relative)
                (stage / MARKER).unlink()
            shutil.copytree(payload, stage, dirs_exist_ok=True, symlinks=True)
            (stage / '.installer').mkdir(exist_ok=True)
            shutil.copy2(HERE / 'installer.py', stage / '.installer/installer.py')
            shutil.copy2(HERE / 'uninstall.sh', stage / 'uninstall.sh')
            (stage / 'love2gathering').chmod(0o755);(stage / 'uninstall.sh').chmod(0o755)
            all_files = files + [
                {'path': '.installer/installer.py', 'kind': 'file', 'sha256': digest(stage / '.installer/installer.py')},
                {'path': 'uninstall.sh', 'kind': 'file', 'sha256': digest(stage / 'uninstall.sh')},
            ]
            owned_directories = set(previous.get('directories', []) if previous else [])
            for path in payload.rglob('*'):
                if path.is_dir() and not path.is_symlink():
                    relative = path.relative_to(payload).as_posix()
                    if not previous or not (prefix / relative).exists():
                        owned_directories.add(relative)
            owned_directories.add('.installer')
            marker = {'schema': 1, 'appId': APP_ID, 'prefix': str(prefix), 'installedAt': int(time.time()), 'files': all_files, 'directories': sorted(owned_directories), 'integrations': []}
            (stage / MARKER).write_text(json.dumps(marker, indent=2) + '\n', encoding='utf-8')
            if prefix.exists():
                prefix.rename(backup)
            stage.rename(prefix);installed = True
            # A long payload copy must not conceal changes to menu/command files.
            check_integrations(paths)
            if integration_snapshot(paths) != integration_before:
                raise ValueError('A menu shortcut or command link changed during installation; no replacement was made')
            integrations_started = True
            marker['integrations'] = write_integrations(prefix, paths)
            (prefix / MARKER).write_text(json.dumps(marker, indent=2) + '\n', encoding='utf-8')
            if backup.exists():
                shutil.rmtree(backup)
        except Exception:
            if installed:
                shutil.rmtree(prefix)
            if backup.exists():
                backup.rename(prefix)
            if integrations_started:
                restore_integrations(integration_before)
            raise
        finally:
            if stage.exists():
                shutil.rmtree(stage)
    print('Installed in ' + str(prefix))
    print('Menu entry: ' + str(paths['menu']))
    print('Command link: ' + str(paths['command']))
    if str(paths['command'].parent) not in os.environ.get('PATH', '').split(os.pathsep):
        print('Add ' + str(paths['command'].parent) + ' to PATH to use the command from a new terminal.')
    print('Uninstall: ' + str(prefix / 'uninstall.sh') + ' (saves, replays and image cache are preserved)')


def uninstall(args):
    if not args.prefix:
        raise ValueError('Pass --prefix with the installation to remove')
    prefix = selected_prefix(args.prefix)
    marker = read_marker(prefix)
    confirm('Remove installed application files from ' + str(prefix) + '? All saves, replays and cached images are retained.', args.yes)
    preserved = []
    for item in marker['files']:
        path = prefix / clean_relative(item['path']);no_link_parents(path, prefix)
        if matches(path, item):
            path.unlink()
        elif path.exists() or path.is_symlink():
            preserved.append(item['path'])
    expected = integration_paths(True)
    allowed = {str(path) for path in expected.values()}
    for item in marker.get('integrations', []):
        path = Path(item['path'])
        if str(path) not in allowed:
            continue
        if item.get('kind') == 'link':
            if path.is_symlink() and os.readlink(path) == str(prefix / 'love2gathering'):
                path.unlink()
        elif owned_desktop(path) and digest(path) == item.get('sha256'):
            path.unlink()
    (prefix / MARKER).unlink()
    directories = [prefix / clean_relative(value) for value in marker.get('directories', [])]
    for path in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        no_link_parents(path, prefix)
        if path.is_dir() and not path.is_symlink():
            try:
                path.rmdir()
            except OSError:
                pass
    try:
        prefix.rmdir()
    except OSError:
        print('Retained changed/untracked files in ' + str(prefix))
    if preserved:
        print('Preserved changed installed files: ' + ', '.join(preserved))
    print('Application removed. User saves, settings, replays and image caches were not changed.')


@contextmanager
def operation_lock():
    path = Path(tempfile.gettempdir()) / ('love2gathering-installer-' + str(os.getuid()) + '.lock')
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if os.fstat(fd).st_uid != os.getuid():
            raise ValueError('The installer lock belongs to another user')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another Love2Gathering installer is running; finish it first') from None
        yield
    finally:
        os.close(fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', help='Exact installation folder, for example /mnt/Games/Love2Gathering')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--payload', help='Extracted release payload directory')
    source.add_argument('--archive', type=Path, help='Release payload tar.gz/tar.xz archive')
    parser.add_argument('--desktop-shortcut', action='store_true', help='Also add a shortcut in the desktop folder')
    parser.add_argument('--yes', action='store_true', help='Approve the displayed install/update/uninstall operation')
    parser.add_argument('--uninstall', action='store_true', help='Remove only unchanged files owned by this installer')
    args = parser.parse_args(argv)
    try:
        with operation_lock():
            uninstall(args) if args.uninstall else install(args)
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, tarfile.TarError) as error:
        print('Installer: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
