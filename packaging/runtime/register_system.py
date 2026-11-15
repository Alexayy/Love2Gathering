#!/usr/bin/env python3
"""RPM relocation-aware menu/link registration; never touches user storage."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile

HERE = Path(__file__).resolve().parent
APP_ID = 'io.github.Alexayy.Love2Gathering'


def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:stream.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('register', 'unregister'))
    parser.add_argument('prefix', type=Path)
    parser.add_argument('--root', type=Path, default=Path('/'), help=argparse.SUPPRESS)
    args = parser.parse_args()
    prefix = args.prefix.resolve()
    if any(ord(char) < 32 for char in str(prefix)):parser.error('Invalid prefix')
    registry = args.root / 'var/lib/love2gathering/package-integration.json'
    link = args.root / 'usr/bin/love2gathering'
    menu = args.root / ('usr/share/applications/' + APP_ID + '.desktop')
    try:previous = json.loads(registry.read_text())
    except FileNotFoundError:previous = {}
    target = str(prefix / 'love2gathering')
    if args.action == 'unregister':
        if previous.get('prefix') != str(prefix):return
        if link.is_symlink() and os.readlink(link) == target:link.unlink()
        if menu.is_file() and not menu.is_symlink() and hashlib.sha256(menu.read_bytes()).hexdigest() == previous.get('desktopSha256'):menu.unlink()
        registry.unlink()
        return
    if link.exists() or link.is_symlink():
        allowed = {target, str(Path(previous['prefix']) / 'love2gathering') if previous.get('prefix') else target}
        if not link.is_symlink() or os.readlink(link) not in allowed:raise SystemExit('Existing unrelated launcher was preserved: ' + str(link))
    if menu.exists() and (not previous.get('desktopSha256') or hashlib.sha256(menu.read_bytes()).hexdigest() != previous['desktopSha256']):
        raise SystemExit('Existing changed desktop entry was preserved: ' + str(menu))
    support = HERE / 'installer_support.py'
    if not support.is_file():support = HERE.parent / 'linux/installer.py'
    spec = importlib.util.spec_from_file_location('love2gathering_installer_support', support)
    module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    content = module.desktop_entry(prefix)
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name('.love2gathering-package-link')
    if temporary.is_symlink():temporary.unlink()
    temporary.symlink_to(target);os.replace(temporary, link)
    atomic(menu, content)
    atomic(registry, json.dumps({'prefix': str(prefix), 'desktopSha256': hashlib.sha256(content.encode()).hexdigest()}, indent=2) + '\n')


if __name__ == '__main__':main()
