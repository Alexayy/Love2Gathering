#!/usr/bin/env python3
"""Validate this build and publish a complete, initially private development release.

Only the final CI step needs GH_TOKEN. No git push, recursive or otherwise, is used.
--prepare-only performs the same local validation without contacting GitHub.
"""
from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile

REPOSITORY = 'Alexayy/Love2Gathering'
ENGINE_REVISION = 'd9b266fc981024873ac7ec5f90ee7121a060725e'
APP_ID = 'io.github.Alexayy.Love2Gathering'
MARKER = b'__LOVE2GATHERING_ARCHIVE__\n'


class ReleaseError(RuntimeError):
    pass


class NotFound(ReleaseError):
    pass


def checked_file(path: Path) -> Path:
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ReleaseError(f'Required regular, nonempty file is missing: {path}')
    return path


def digest(path: Path, offset: int = 0) -> str:
    with checked_file(path).open('rb') as source:
        source.seek(offset)
        return hashlib.file_digest(source, 'sha256').hexdigest()


def read_json(path: Path) -> dict:
    checked_file(path)
    if path.stat().st_size > 4 * 1024 * 1024:
        raise ReleaseError(f'JSON report is too large: {path.name}')
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (ValueError, UnicodeError) as exc:
        raise ReleaseError(f'Invalid JSON report: {path.name}') from exc
    if not isinstance(value, dict):
        raise ReleaseError(f'Expected a JSON object: {path.name}')
    return value


def write_atomic(path: Path, content: str) -> None:
    if path.is_symlink():
        raise ReleaseError(f'Refusing generated output symlink: {path.name}')
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                     prefix='.' + path.name + '.', delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    temporary.replace(path)


def version_value(value: str) -> str:
    if not re.fullmatch(r'[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(?:\.[0-9]{1,10})?', value):
        raise ReleaseError('Version must be YYYY.MM.DD or YYYY.MM.DD.BUILD')
    try:
        date(*(int(part) for part in value.split('.')[:3]))
    except ValueError as exc:
        raise ReleaseError('Version contains an invalid date') from exc
    return value


def package_names(version: str) -> list[str]:
    prefix = f'Love2Gathering-{version}'
    return [prefix + ending for ending in (
        '-linux-amd64.deb', '-linux-x86_64.rpm', '-linux-x86_64.run',
        '-linux-x86_64.tar.xz', '-windows-x64-setup.exe', '-x86_64.flatpak')]


def validate_magic(path: Path) -> None:
    with checked_file(path).open('rb') as stream:
        header = stream.read(4096)
        if path.name.endswith('.deb'):
            valid = header.startswith(b'!<arch>\n')
        elif path.name.endswith('.rpm'):
            valid = header.startswith(b'\xed\xab\xee\xdb')
        elif path.name.endswith('.tar.xz'):
            valid = header.startswith(b'\xfd7zXZ\x00')
        elif path.name.endswith('.run'):
            valid = header.startswith(b'#!/bin/sh\n') and b'\n' + MARKER in header
        elif path.name.endswith('.exe'):
            valid = header.startswith(b'MZ') and len(header) >= 64
            if valid:
                offset = struct.unpack_from('<I', header, 0x3c)[0]
                valid = 64 <= offset <= path.stat().st_size - 4
                if valid:
                    stream.seek(offset)
                    valid = stream.read(4) == b'PE\x00\x00'
        elif path.name.endswith('.flatpak'):
            valid = header.startswith(b'flatpak\x00') and APP_ID.encode() in header
        else:
            valid = False
    if not valid:
        raise ReleaseError(f'Incorrect package signature: {path.name}')


def instructions(version: str, tag: str) -> str:
    prefix = f'Love2Gathering-{version}'
    return f'''# Install Love: 2 Gathering {version}

Development build from `{tag}`. These packages include the pinned XMage bridge,
card metadata and Java runtime. Card images/art and your saved games stay in your
chosen data/cache folders; bulk image downloads are optional.

## Linux: choose the application folder

Install LÖVE 11.5 and Python 3.10 or newer using your distribution, then run:

```sh
chmod +x {prefix}-linux-x86_64.run
./{prefix}-linux-x86_64.run --prefix /mnt/Games/Love2Gathering
```

The installer creates a per-user launcher, desktop entry and menu shortcut.
Choose a writable directory and run as your own user. The `.tar.xz` contains the
same application files; after extraction run `sh install.sh --prefix /mnt/Games/Love2Gathering`.

## Debian / Ubuntu and Fedora / RPM distributions

```sh
sudo apt install ./{prefix}-linux-amd64.deb
# or, on an RPM distribution:
sudo dnf install ./{prefix}-linux-x86_64.rpm
```

DEB/RPM packages use their distribution's managed installation location. Use the
`.run` installer above when you need an arbitrary folder such as `/mnt/Games`.

## Flatpak: choose an installation location

Install Flatpak and Python 3, keep `install-flatpak.py` beside the bundle, then:

```sh
python3 install-flatpak.py {prefix}-x86_64.flatpak --prefix /mnt/Games/Love2Gathering-flatpak
```

The helper sets up the named Flatpak installation and its required runtime. Run
`python3 install-flatpak.py --help` for installation/uninstallation options. A
standard Flatpak install is also possible with `flatpak install --user ./{prefix}-x86_64.flatpak`.
Flatpak still uses sandbox-managed paths for saves and cache.

## Windows x64

Run `{prefix}-windows-x64-setup.exe` and choose the installation folder. It bundles
LÖVE, Python and Java, and adds Start menu shortcuts. Windows builds are unsigned;
Windows may display its normal publisher prompt. A native Windows gameplay test
is separate from Linux cross-build and package validation.

## Data, integrity and provenance

Existing saves are preserved. Data/cache paths and optional image downloads are
configured inside Settings. Uninstalling the application does not purge saves.
`SHA256SUMS` lists all release file hashes; on Linux verify with
`sha256sum --check SHA256SUMS` after downloading every listed file. Runtime and
metadata provenance reports and `release-manifest.json` identify this build.
'''


def prepare(dist: Path, version: str, tag: str, commit: str, metadata_report: Path) -> list[Path]:
    version_value(version)
    if not re.fullmatch(r'[a-f0-9]{40}', commit):
        raise ReleaseError('Commit must be a full lowercase commit SHA')
    if not re.fullmatch(r'development-[0-9]+-[0-9]+-' + commit[:12], tag):
        raise ReleaseError('Tag must be development-RUN_NUMBER-RUN_ATTEMPT-SHA12 for this commit')
    if dist.is_symlink() or not dist.is_dir():
        raise ReleaseError('Distribution directory must be an existing real directory')
    release = read_json(dist / 'stage/common/Love2Gathering/release.json')
    expected = {'applicationId': APP_ID, 'version': version, 'sourceRevision': commit,
                'engineRevision': ENGINE_REVISION, 'includesUserData': False}
    if any(release.get(key) != value for key, value in expected.items()):
        raise ReleaseError('Common payload provenance does not match this version/commit/pinned engine')
    packages = [checked_file(dist / name) for name in package_names(version)]
    for path in packages:
        validate_magic(path)
    installer, archive = packages[2:4]
    with installer.open('rb') as stream:
        header = stream.read(4096)
    archive_offset = header.index(b'\n' + MARKER) + 1 + len(MARKER)
    if digest(installer, archive_offset) != digest(archive):
        raise ReleaseError('The self-extracting installer must contain exactly this tar.xz archive')
    helper = checked_file(dist / 'install-flatpak.py')
    if b'argparse' not in helper.read_bytes() or APP_ID.encode() not in helper.read_bytes():
        raise ReleaseError('Unexpected Flatpak installation helper')
    runtime_paths = [dist / 'windows-runtime-provenance.json', dist / 'flatpak-native-provenance.json']
    windows, flatpak = (read_json(path) for path in runtime_paths)
    for component in ('love', 'python', 'java'):
        value = windows.get(component, {})
        if not isinstance(value, dict) or not re.fullmatch(r'[a-f0-9]{64}', str(value.get('sha256', ''))):
            raise ReleaseError('Incomplete Windows runtime provenance')
    for provenance,platform in((windows,'windows-cp313'),(flatpak,'flatpak-cp313')):
        value=provenance.get('pillow',{})
        if not isinstance(value,dict)or value.get('platform')!=platform or not re.fullmatch(r'[a-f0-9]{64}',str(value.get('sha256','')))or not value.get('version')or value.get('includesNativeCode')is not True or value.get('includesLicenses')is not True:
            raise ReleaseError('Incomplete packaged Pillow runtime provenance')
    if not isinstance(flatpak.get('love'), dict) or not re.fullmatch(
            r'[a-f0-9]{64}', str(flatpak['love'].get('sha256', ''))) or not flatpak.get('libraries'):
        raise ReleaseError('Incomplete Flatpak runtime provenance')
    metadata = read_json(metadata_report)
    if (metadata.get('version') != 1 or metadata.get('metadataOnly') is not True
            or metadata.get('bulkType') not in ('default_cards', 'all_cards')
            or not isinstance(metadata.get('cards'), int) or metadata['cards'] < 10000
            or not isinstance(metadata.get('bytes'), int) or metadata['bytes'] <= 0
            or not re.fullmatch(r'[a-f0-9]{64}', str(metadata.get('sha256', '')))):
        raise ReleaseError('Incomplete metadata-only source provenance')
    metadata_target = dist / 'metadata-provenance.json'
    write_atomic(metadata_target, json.dumps(metadata, indent=2) + '\n')
    guide = dist / 'INSTALL.md'
    write_atomic(guide, instructions(version, tag))
    primary = packages + [helper] + runtime_paths + [metadata_target, guide]
    entries = [{'name': path.name, 'bytes': path.stat().st_size, 'sha256': digest(path)} for path in primary]
    manifest = dist / 'release-manifest.json'
    write_atomic(manifest, json.dumps({'version': version, 'tag': tag, 'repository': REPOSITORY,
        'commit': commit, 'engineRevision': ENGINE_REVISION, 'includesUserData': False,
        'assets': entries}, indent=2) + '\n')
    primary.append(manifest)
    checksum = dist / 'SHA256SUMS'
    write_atomic(checksum, ''.join(f'{digest(path)}  {path.name}\n' for path in primary))
    return primary + [checksum]


class GitHub:
    """All authentication stays in gh's environment; commands contain no secrets."""
    def command(self, *arguments: str) -> str:
        result = subprocess.run(['gh', *arguments], text=True, capture_output=True, check=False)
        if result.returncode:
            if re.search(r'\bHTTP 404\b', result.stderr):
                raise NotFound('GitHub object does not exist')
            raise ReleaseError('GitHub command failed: ' + ' '.join(arguments[:3]) + '\n' + result.stderr.strip())
        return result.stdout

    def api(self, path: str, *arguments: str):
        try:
            return json.loads(self.command('api', path, *arguments))
        except ValueError as exc:
            raise ReleaseError('GitHub returned invalid JSON') from exc


def get_release(gh: GitHub, tag: str):
    try:
        return gh.api(f'repos/{REPOSITORY}/releases/tags/{tag}')
    except NotFound:
        # REST's tag endpoint does not find a draft's pending tag. This is the
        # same GraphQL-ID -> REST lookup used by cli/cli release/shared/fetch.go.
        owner, name = REPOSITORY.split('/')
        query = ('query($owner:String!,$repo:String!,$tag:String!){repository(owner:$owner,name:$repo)'
                 '{release(tagName:$tag){databaseId}}}')
        response = gh.api('graphql', '-f', 'query=' + query, '-f', 'owner=' + owner,
                         '-f', 'repo=' + name, '-f', 'tag=' + tag)
        if response.get('errors'):
            raise ReleaseError('Could not look up a draft release')
        repository = response.get('data', {}).get('repository')
        if not isinstance(repository, dict):
            raise ReleaseError('Repository was not accessible during draft lookup')
        release = repository.get('release')
        if release is None:
            return None
        if not isinstance(release, dict) or not isinstance(release.get('databaseId'), int):
            raise ReleaseError('Invalid draft release identity')
        return gh.api(f'repos/{REPOSITORY}/releases/{release["databaseId"]}')


def verify_tag(gh: GitHub, tag: str, commit: str, *, required: bool) -> None:
    try:
        ref = gh.api(f'repos/{REPOSITORY}/git/ref/tags/{tag}')
    except NotFound:
        if required:
            raise ReleaseError('Release tag was not created')
        return
    obj = ref.get('object', {})
    for _ in range(8):
        if obj.get('type') == 'commit' and obj.get('sha') == commit:
            return
        if obj.get('type') != 'tag' or not re.fullmatch(r'[a-f0-9]{40}', str(obj.get('sha', ''))):
            break
        obj = gh.api(f'repos/{REPOSITORY}/git/tags/{obj["sha"]}').get('object', {})
    raise ReleaseError('Existing tag does not point to this exact commit')


def verify_draft(release, tag: str, commit: str) -> None:
    if (not isinstance(release, dict) or release.get('draft') is not True
            or release.get('prerelease') is not True or release.get('tag_name') != tag
            or release.get('target_commitish') != commit
            or not isinstance(release.get('id'), int)):
        raise ReleaseError('Refusing to modify a published or unrelated release')


def remote_assets(gh: GitHub, release_id: int) -> list[dict]:
    values = gh.api(f'repos/{REPOSITORY}/releases/{release_id}/assets?per_page=100')
    if not isinstance(values, list):
        raise ReleaseError('Invalid release asset response')
    return values


def verify_assets(assets: list[dict], files: list[Path], *, complete: bool) -> None:
    local = {path.name: path for path in files}
    seen = set()
    for value in assets:
        name = value.get('name')
        if name not in local or name in seen:
            raise ReleaseError('Unexpected or duplicate asset in the release; refusing to publish')
        seen.add(name)
        if complete:
            path = local[name]
            if value.get('size') != path.stat().st_size or value.get('state') != 'uploaded':
                raise ReleaseError('An uploaded release asset is missing or incomplete: ' + name)
            if value.get('digest') and value['digest'] != 'sha256:' + digest(path):
                raise ReleaseError('An uploaded release asset has a mismatched hash: ' + name)
    if complete and seen != set(local):
        raise ReleaseError('Not every expected release asset was uploaded')


def publish(gh: GitHub, files: list[Path], version: str, tag: str, commit: str) -> str:
    release = get_release(gh, tag)
    if release is not None:
        verify_draft(release, tag, commit)
    # A draft may only have a pending tag. GitHub creates that ref when it is
    # published; existing refs must still match before any mutation.
    verify_tag(gh, tag, commit, required=False)
    if release is None:
        with tempfile.TemporaryDirectory(prefix='love2gathering-release-') as temporary:
            notes = Path(temporary) / 'notes.md'
            notes.write_text(f'Development build **{version}** from `{commit}`.\n\n'
                'Download the installer for your platform and read INSTALL.md. '
                'SHA256SUMS and provenance reports accompany all packages.\n\n'
                f'XMage remains pinned at `{ENGINE_REVISION}`. No user data is included.\n', encoding='utf-8')
            gh.command('release', 'create', tag, '--repo', REPOSITORY, '--draft', '--prerelease',
                       '--target', commit, '--title', 'Development ' + version, '--notes-file', str(notes))
        release = get_release(gh, tag)
        verify_draft(release, tag, commit)
        verify_tag(gh, tag, commit, required=False)
    verify_assets(remote_assets(gh, release['id']), files, complete=False)
    for path in files:
        # Refuse uploads if somebody published the draft during this job.
        verify_draft(get_release(gh, tag), tag, commit)
        gh.command('release', 'upload', tag, str(path), '--repo', REPOSITORY, '--clobber')
    release = get_release(gh, tag)
    verify_draft(release, tag, commit)
    verify_tag(gh, tag, commit, required=False)
    verify_assets(remote_assets(gh, release['id']), files, complete=True)
    gh.command('release', 'edit', tag, '--repo', REPOSITORY, '--draft=false', '--prerelease', '--latest=false')
    published = get_release(gh, tag)
    if (not isinstance(published, dict) or published.get('draft') is not False
            or published.get('prerelease') is not True or published.get('target_commitish') != commit):
        raise ReleaseError('Could not verify final published prerelease state')
    verify_tag(gh, tag, commit, required=True)
    return published.get('html_url', f'https://github.com/{REPOSITORY}/releases/tag/{tag}')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--metadata-report', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args(argv)
    try:
        if os.environ.get('GITHUB_REPOSITORY', REPOSITORY) != REPOSITORY:
            raise ReleaseError('This publisher is restricted to ' + REPOSITORY)
        files = prepare(args.dist, args.version, args.tag, args.commit, args.metadata_report)
        print(f'Validated {len(files)} release assets for {args.version}')
        if not args.prepare_only:
            if not os.environ.get('GH_TOKEN'):
                raise ReleaseError('GH_TOKEN is required only for the final publishing step')
            print(publish(GitHub(), files, args.version, args.tag, args.commit))
    except (ReleaseError, OSError, subprocess.SubprocessError) as exc:
        parser.exit(1, 'Release aborted: ' + str(exc) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
