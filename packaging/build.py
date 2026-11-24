#!/usr/bin/env python3
"""Build explicit runtime payloads and Linux packages; never copy user stores."""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
VERSION = '2026.11.14'
APP_ID = 'io.github.Alexayy.Love2Gathering'
CURATED = ('fonts', 'icons', 'keyrune', 'audio', 'card-backs')
KENNEY = ('ui', 'theme', 'runtime', 'particles', 'sounds')
PROJECT_NOTICES = ('LICENSE', 'CREDITS.md', 'THIRD_PARTY_NOTICES.md')


def release_version(value):
    """A numeric date/build version accepted by every produced package format."""
    if not re.fullmatch(r'[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(?:\.[0-9]{1,10})?', value):
        raise argparse.ArgumentTypeError('Version must be YYYY.MM.DD or YYYY.MM.DD.BUILD')
    from datetime import date
    try:date(*(int(part) for part in value.split('.')[:3]))
    except ValueError as exc:raise argparse.ArgumentTypeError('Version must contain a valid calendar date') from exc
    return value


def run(command, **options):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), check=True, **options)


def copy_tree(source, destination, predicate=None):
    for item in sorted(source.rglob('*')):
        if not item.is_file() or '__pycache__' in item.parts or item.suffix in ('.pyc', '.log'):
            continue
        if predicate and not predicate(item):
            continue
        target = destination / item.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)


def copy_deck_payload(source, destination):
    """Include the one prepared product source, never arbitrary compressed files."""
    catalog = source / 'preconstructed/catalog.jsonl.gz'
    if catalog.is_symlink() or not catalog.is_file() or not catalog.stat().st_size:
        raise SystemExit('Required bundled preconstructed source is missing: ' + str(catalog))
    try:
        # Read through the gzip trailer so a truncated/corrupt tracked snapshot
        # fails the build instead of silently shipping an empty product browser.
        with gzip.open(catalog, 'rb') as stream:
            if not stream.read(1):
                raise ValueError('empty prepared catalog')
            while stream.read(1024 * 1024):
                pass
    except (OSError, EOFError, ValueError) as exc:
        raise SystemExit('Invalid bundled preconstructed source: ' + str(catalog)) from exc
    copy_tree(source, destination, lambda p: p.suffix in ('.json', '.md', '.txt')
              or p.relative_to(source).as_posix() == 'preconstructed/catalog.jsonl.gz')


def copy_bridge(source, destination):
    """System installs must not retain private mktemp permissions from the build."""
    jar = source / 'xmage-bridge-1.0.0.jar'
    try:
        with zipfile.ZipFile(jar) as archive:
            archive.getinfo('love2gathering/EngineBridge.class')
    except (OSError, KeyError, zipfile.BadZipFile) as exc:
        raise SystemExit('The prebuilt bridge is unreadable or lacks EngineBridge; rebuild it before packaging.') from exc
    dependencies = sorted((source / 'lib').glob('*.jar'))
    if not dependencies:
        raise SystemExit('The prebuilt bridge dependency directory is empty.')
    (destination / 'lib').mkdir(parents=True)
    for item in [jar, *dependencies]:
        target = destination / item.relative_to(source)
        shutil.copyfile(item, target)
        target.chmod(0o644)


def asset_paths():
    yield ROOT / 'assets/battlefield/courtyard.jpg'
    for folder in CURATED:
        path = ROOT / 'assets' / folder
        if path.exists():
            yield from (p for p in path.rglob('*') if p.is_file())
    for folder in KENNEY:
        yield from (p for p in (ROOT / 'assets/kenney' / folder).rglob('*') if p.is_file())


def java_home():
    explicit = os.environ.get('JAVA_HOME')
    candidates = ([Path(explicit)] if explicit else []) + sorted((ROOT / '.tools').glob('jdk-*'))
    binary = shutil.which('jlink')
    if binary:
        candidates.insert(1 if explicit else 0, Path(binary).resolve().parents[1])
    for path in candidates:
        if (path / 'bin/jlink').is_file():
            try:release = (path / 'release').read_text()
            except OSError:continue
            if re.search(r'^JAVA_VERSION="21(?:\.|"$)', release, re.M):return path
    raise SystemExit('Java 21 JDK with jlink is required to build the Linux runtime.')


def common_payload(output, source, *, channel='source', branch=None, tag=''):
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    engine = subprocess.check_output(['git', 'rev-parse', 'HEAD:engine/mage'], cwd=ROOT, text=True).strip()
    branch = branch or subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], cwd=ROOT, text=True).strip()
    if channel not in ('source', 'development', 'stable') or not re.fullmatch(r'[A-Za-z0-9._/-]{1,120}', branch):
        raise SystemExit('Invalid build channel or source branch')
    if not re.fullmatch(r'[a-f0-9]{40}', revision) or not re.fullmatch(r'[a-f0-9]{40}', engine):
        raise SystemExit('A complete source and engine revision are required')
    if channel != 'source':
        expected_branch = 'master' if channel == 'stable' else 'development'
        expected_tag = re.escape('v' + VERSION) if channel == 'stable' else re.escape('DEV-' + VERSION) + r'-[1-9][0-9]{0,4}-' + revision[:12]
        if branch != expected_branch or not re.fullmatch(expected_tag, tag):
            raise SystemExit('Release channel, branch and commit-bound tag disagree')
    elif tag:
        raise SystemExit('A source build must not claim a published release tag')
    info = {'version': VERSION, 'channel': channel, 'branch': branch, 'revision': revision, 'tag': tag,
            'builtAtUTC': datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
            'repository': 'https://github.com/Alexayy/Love2Gathering', 'engineRevision': engine}
    target = output / 'stage/common/Love2Gathering'
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    jar = ROOT / 'bridge/target/xmage-bridge-1.0.0.jar'
    if not jar.is_file() or not (ROOT / 'bridge/card-map.json').is_file():
        raise SystemExit('Build the pinned bridge with scripts/build-engine.sh first.')
    if not source.is_file():
        raise SystemExit('Supply --source pointing to an existing card JSONL/JSONL.GZ.')
    frontend = [ROOT / 'main.lua', ROOT / 'conf.lua']
    frontend += list((ROOT / 'app').glob('*.lua'))
    frontend += [p for p in (ROOT / 'lib').rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    frontend += list(asset_paths())
    frontend += [p for p in (ROOT / 'licenses').rglob('*') if p.is_file() and not p.is_symlink()]
    for name in PROJECT_NOTICES:
        path = ROOT / name
        if path.is_file():frontend.append(path)
        elif channel != 'source':raise SystemExit('Required distribution notice is missing: ' + name)
    with zipfile.ZipFile(target / 'app.love', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(set(frontend)):
            archive.write(path, path.relative_to(ROOT).as_posix())
        archive.writestr('build-info.json', json.dumps(info, indent=2) + '\n')
    copy_tree(ROOT / 'service', target / 'service', lambda p: p.parent == ROOT / 'service' and p.suffix == '.py')
    copy_deck_payload(ROOT / 'decks', target / 'decks')
    copy_bridge(ROOT / 'bridge/target', target / 'bridge/target')
    shutil.copy2(ROOT / 'bridge/card-map.json', target / 'bridge/card-map.json')
    (target / 'scripts').mkdir()
    shutil.copy2(ROOT / 'scripts/download-card-images.py', target / 'scripts/download-card-images.py')
    shutil.copy2(ROOT / 'scripts/starter-image-pack.py', target / 'scripts/starter-image-pack.py')
    (target / 'assets/card-art').mkdir(parents=True)
    shutil.copy2(ROOT / 'assets/card-art/full-art-basics.json', target / 'assets/card-art/full-art-basics.json')
    metadata = target / 'assets/all-cards.jsonl.gz'
    if source.suffix == '.gz':
        shutil.copy2(source, metadata)
    else:
        with source.open('rb') as stream, metadata.open('wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=6) as compressed:
                shutil.copyfileobj(stream, compressed, 1024 * 1024)
    shutil.copy2(ROOT / 'packaging/runtime/launcher.py', target / 'launcher.py')
    shutil.copy2(ROOT / 'packaging/runtime/update_handoff.py', target / 'update_handoff.py')
    icon = target / 'share/icons/love2gathering.png'
    icon.parent.mkdir(parents=True)
    shutil.copy2(ROOT / 'assets/icons/thb.png', icon)
    licenses = target / 'licenses'
    licenses.mkdir()
    if (ROOT / 'licenses').is_dir():copy_tree(ROOT / 'licenses', licenses)
    shutil.copy2(ROOT / 'engine/mage/LICENSE.txt', licenses / 'XMage-MIT.txt')
    for name in PROJECT_NOTICES:
        if (ROOT / name).is_file():shutil.copy2(ROOT / name, licenses / name)
    for path in frontend:
        if path.relative_to(ROOT).parts[0] == 'assets' and re.search(r'(?:license|notice|copyright)', path.name, re.I):
            relative = path.relative_to(ROOT / 'assets')
            notice = licenses / 'assets' / relative
            notice.parent.mkdir(parents=True, exist_ok=True);shutil.copy2(path, notice)
    slab = ROOT / 'lib/Slab/init.lua'
    if slab.is_file():
        header = re.search(r'^--\[\[(.*?)--\]\]', slab.read_text(), re.S)
        if header and 'MIT License' in header.group(1):(licenses / 'Slab-MIT.txt').write_text(header.group(1).strip() + '\n')
    for path in ('README.md', 'assets/ASSET_GUIDE.md', 'assets/card-backs/README.md'):
        shutil.copy2(ROOT / path, licenses / Path(path).name.replace('README', 'README-' + Path(path).parent.name))
    for dependency in sorted((target / 'bridge/target/lib').glob('*.jar')):
        with zipfile.ZipFile(dependency) as archive:
            for name in archive.namelist():
                if re.search(r'(?:^|/)(LICENSE|NOTICE|COPYING)(?:[._-][A-Za-z0-9._-]+)?$', name, re.I):
                    safe = re.sub(r'[^A-Za-z0-9._-]', '-', name)
                    (licenses / (dependency.stem + '-' + safe)).write_bytes(archive.read(name))
    release = {'applicationId': APP_ID, 'name': 'Love: 2 Gathering', 'version': VERSION,
               'sourceRevision': revision, 'engineRevision': engine,
               'channel': channel, 'branch': branch, 'tag': tag, 'builtAtUTC': info['builtAtUTC'],
               'metadataSource': source.name, 'includesUserData': False, 'catalogApi': 15,
               'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip())}
    (target / 'release.json').write_text(json.dumps(release, indent=2) + '\n')
    (target / 'love2gathering').write_text('#!/bin/sh\nset -eu\napp_file=$(readlink -f -- "$0")\napp_dir=$(CDPATH= cd -- "$(dirname -- "$app_file")" && pwd)\nexec python3 "$app_dir/launcher.py" "$@"\n')
    (target / 'love2gathering').chmod(0o755)
    seal(target)
    print('Common payload: ' + str(target), flush=True)
    return target


def seal(target):
    # Payloads become root-owned in RPM/DEB. Source/build umasks and atomic
    # mktemp publication must never make their contents private to the builder.
    target.chmod(0o755)
    entries = {}
    for path in sorted(target.rglob('*')):
        if path.is_symlink():
            continue
        if path.is_dir():
            path.chmod(0o755)
        if path.is_file() and not path.is_symlink() and path.name != 'payload-manifest.json':
            path.chmod(0o755 if path.stat().st_mode & 0o111 else 0o644)
            with path.open('rb') as stream:
                entries[path.relative_to(target).as_posix()] = hashlib.file_digest(stream, 'sha256').hexdigest()
    (target / 'payload-manifest.json').write_text(json.dumps({'version': 1, 'files': entries}, indent=2) + '\n')
    (target / 'payload-manifest.json').chmod(0o644)


def linux_payload(output, common):
    target = output / 'stage/linux/Love2Gathering'
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(common, target)
    cache = ROOT / 'build/packaging/java-linux'
    if not cache.is_dir():
        cache.parent.mkdir(parents=True, exist_ok=True)
        run([java_home() / 'bin/jlink', '--add-modules', 'java.se,jdk.httpserver,jdk.unsupported,jdk.crypto.ec,jdk.charsets,jdk.zipfs',
             '--strip-debug', '--no-man-pages', '--no-header-files', '--compress=2', '--output', cache])
    shutil.copytree(cache, target / 'runtime/java')
    shutil.copy2(ROOT / 'packaging/runtime/register_system.py', target / 'register_system.py')
    shutil.copy2(ROOT / 'packaging/linux/installer.py', target / 'installer_support.py')
    seal(target)
    return target


def desktop(prefix):
    return ('[Desktop Entry]\nType=Application\nName=Love: 2 Gathering\nComment=XMage desktop client\n'
            'Exec=' + prefix + '/love2gathering\nIcon=love2gathering\nTerminal=false\nCategories=Game;CardGame;\nStartupNotify=true\n')


def build_deb(output, payload):
    stage = ROOT / 'build/packaging/deb'
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(payload, stage / 'opt/love2gathering', symlinks=True)
    (stage/'opt/love2gathering/update-installation.json').write_text(json.dumps({'method':'deb'})+'\n')
    seal(stage/'opt/love2gathering')
    control = stage / 'DEBIAN';control.mkdir()
    size = sum(p.stat().st_size for p in payload.rglob('*') if p.is_file()) // 1024
    (control / 'control').write_text(f'Package: love2gathering\nVersion: {VERSION}-1\nArchitecture: amd64\nMaintainer: Love2Gathering contributors\nDepends: python3 (>= 3.10), python3-pil (>= 9.1), love (>= 11.5)\nSection: games\nPriority: optional\nInstalled-Size: {size}\nHomepage: https://github.com/Alexayy/Love2Gathering\nDescription: Love: 2 Gathering XMage desktop client\n Native XMage rules, bot practice, private rooms and drafts.\n Includes a Java 21 runtime and card metadata; image downloads are explicit.\n')
    executable = stage / 'usr/bin/love2gathering';executable.parent.mkdir(parents=True)
    executable.symlink_to('/opt/love2gathering/love2gathering')
    menu = stage / ('usr/share/applications/' + APP_ID + '.desktop');menu.parent.mkdir(parents=True)
    menu.write_text(desktop('/opt/love2gathering'))
    icon = stage / 'usr/share/icons/hicolor/256x256/apps/love2gathering.png';icon.parent.mkdir(parents=True)
    shutil.copy2(payload / 'share/icons/love2gathering.png', icon)
    path = output / f'Love2Gathering-{VERSION}-linux-amd64.deb'
    run(['dpkg-deb', '--root-owner-group', '-Zzstd', '-z6', '--build', stage, path])
    return path


def rpm_environment():
    local = ROOT / '.tools/packaging-linux/sysroot'
    binary = shutil.which('rpmbuild') or str(local / 'usr/bin/rpmbuild')
    env = os.environ.copy()
    if str(local) in binary:
        env['LD_LIBRARY_PATH'] = str(local / 'usr/lib/x86_64-linux-gnu')
        env['RPM_CONFIGDIR'] = str(local / 'usr/lib/rpm')
    return binary, env


def build_rpm(output, payload):
    stage = ROOT / 'build/packaging/rpm';stage.mkdir(parents=True, exist_ok=True)
    selected=stage/'payload'
    if selected.exists():shutil.rmtree(selected)
    shutil.copytree(payload,selected,symlinks=True)
    (selected/'update-installation.json').write_text(json.dumps({'method':'rpm'})+'\n')
    seal(selected);payload=selected
    for name in ('BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS', 'tmp'):(stage / name).mkdir(exist_ok=True)
    spec = stage / 'SPECS/love2gathering.spec'
    spec.write_text(f'''Name: love2gathering
Version: {VERSION}
Release: 1
Summary: Love: 2 Gathering XMage desktop client
License: Mixed; see bundled licenses
URL: https://github.com/Alexayy/Love2Gathering
BuildArch: x86_64
Prefix: /opt/love2gathering
AutoReqProv: no
Requires: python3 >= 3.10, python3-pillow >= 9.1, love >= 11.5
%description
Desktop client with native XMage rules, private rooms and drafts.
Includes Java 21 and card metadata. Runtime images are cached separately.
%prep
%build
%install
mkdir -p "%{{buildroot}}/opt/love2gathering"
cp -a "{payload}/." "%{{buildroot}}/opt/love2gathering/"
%post
python3 -B "$RPM_INSTALL_PREFIX/register_system.py" register "$RPM_INSTALL_PREFIX" || :
%preun
if [ "$1" -eq 0 ]; then python3 -B "$RPM_INSTALL_PREFIX/register_system.py" unregister "$RPM_INSTALL_PREFIX" || :; fi
%files
/opt/love2gathering
''')
    binary, env = rpm_environment()
    run([binary, '-bb', '--define', '_topdir ' + str(stage), '--define', '__os_install_post %{nil}',
         '--define', '_tmppath '+str(stage/'tmp'), '--define', '_build_id_links none', '--define', '_binary_payload w6T8.xzdio', spec], env=env)
    source = stage / 'RPMS/x86_64' / f'love2gathering-{VERSION}-1.x86_64.rpm'
    if not source.is_file():raise SystemExit('rpmbuild did not produce the selected release version')
    path = output / f'Love2Gathering-{VERSION}-linux-x86_64.rpm'
    shutil.copy2(source, path)
    return path


def portable(output, payload):
    path = output / f'Love2Gathering-{VERSION}-linux-x86_64.tar.xz'
    with tarfile.open(path, 'w:xz', preset=3) as archive:
        archive.add(payload, arcname='payload', recursive=True)
        for name in ('install.sh', 'installer.py', 'uninstall.sh'):
            archive.add(ROOT / 'packaging/linux' / name, arcname=name)
    stub = '''#!/bin/sh
set -eu
archive_line=$(awk '/^__LOVE2GATHERING_ARCHIVE__$/ { print NR + 1; exit }' "$0")
temporary=$(mktemp -d "${TMPDIR:-/tmp}/love2gathering-installer.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
tail -n +"$archive_line" "$0" | tar -xJ -C "$temporary"
sh "$temporary/install.sh" --payload "$temporary/payload" "$@"
exit $?
__LOVE2GATHERING_ARCHIVE__
'''
    installer = output / f'Love2Gathering-{VERSION}-linux-x86_64.run'
    with installer.open('wb') as stream:
        stream.write(stub.encode())
        with path.open('rb') as archive:shutil.copyfileobj(archive, stream, 1024 * 1024)
    installer.chmod(0o755)
    return [path, installer]


def checksums(output):
    entries = []
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != 'SHA256SUMS':
            with path.open('rb') as stream:digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            entries.append(digest + '  ' + path.name)
    (output / 'SHA256SUMS').write_text('\n'.join(entries) + '\n')


def main():
    global VERSION
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--format', choices=('common', 'linux', 'deb', 'rpm', 'portable', 'all-linux'), default='all-linux')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--source', type=Path, default=next((ROOT / 'assets').glob('all-cards*.jsonl'), ROOT / 'assets/all-cards.jsonl'))
    parser.add_argument('--reuse-common', action='store_true')
    parser.add_argument('--reuse-linux', action='store_true', help='Reuse a previously verified Linux stage')
    parser.add_argument('--version', type=release_version, default=VERSION, help='Shared package/release version (YYYY.MM.DD.BUILD)')
    parser.add_argument('--channel', choices=('source', 'development', 'stable'), default='source')
    parser.add_argument('--branch', help='Exact release source branch, also displayed in About')
    parser.add_argument('--tag', default='', help='Commit-bound release tag, also displayed in About')
    args = parser.parse_args();output = args.output.resolve();output.mkdir(parents=True, exist_ok=True)
    VERSION = args.version
    if platform.machine() not in ('x86_64', 'AMD64') and args.format != 'common':
        parser.error('These native packages target x86_64; use a matching builder.')
    common = output / 'stage/common/Love2Gathering'
    if not args.reuse_common:common = common_payload(output, args.source.resolve(), channel=args.channel, branch=args.branch, tag=args.tag)
    elif json.loads((common / 'release.json').read_text())['version'] != VERSION:
        parser.error('Reused common payload version differs; rebuild it with the selected --version')
    if args.reuse_common and args.channel != 'source':
        identity = json.loads((common / 'release.json').read_text())
        expected = {'channel': args.channel, 'branch': args.branch, 'tag': args.tag}
        if any(identity.get(key) != value for key,value in expected.items()):
            parser.error('Reused common payload release identity differs; rebuild instead of relabelling it')
    if args.format == 'common':return
    payload = output / 'stage/linux/Love2Gathering' if args.reuse_linux else linux_payload(output, common)
    if not payload.is_dir():parser.error('Linux stage is missing; build --format linux first')
    if args.reuse_linux:
        expected = json.loads((common / 'release.json').read_text())
        reused = json.loads((payload / 'release.json').read_text())
        fields = ('version', 'sourceRevision', 'engineRevision', 'channel', 'branch', 'tag')
        if any(reused.get(key) != expected.get(key) for key in fields):
            parser.error('Reused Linux payload release identity differs from common; rebuild instead of relabelling it')
    if args.format == 'linux':return
    products = []
    if args.format in ('deb', 'all-linux'):products.append(build_deb(output, payload))
    if args.format in ('rpm', 'all-linux'):products.append(build_rpm(output, payload))
    if args.format in ('portable', 'all-linux'):products.extend(portable(output, payload))
    checksums(output)
    print(json.dumps({'products': [str(p) for p in products]}, indent=2))


if __name__ == '__main__':main()
