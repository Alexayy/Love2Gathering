"""Explicit whole-package updates; only the trusted launcher executes installers.

This service checks the fixed project releases and downloads a complete verified
installer into its launcher's private session. It never replaces application
files, executes a process or changes user storage.
"""
from contextlib import closing
from copy import deepcopy
from datetime import date, datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import threading
import time
from urllib.parse import urlsplit
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener


REPOSITORY = 'Alexayy/Love2Gathering'
RELEASE_PAGE = 'https://github.com/' + REPOSITORY + '/releases'
API = 'https://api.github.com/repos/' + REPOSITORY + '/releases'
METHOD_SUFFIX = {'windows-setup': '-windows-x64-setup.exe', 'linux-run': '-linux-x86_64.run',
                 'deb': '-linux-amd64.deb', 'rpm': '-linux-x86_64.rpm', 'flatpak': '-x86_64.flatpak'}
MAX_JSON = 4 * 1024 * 1024
MAX_SUMS = 256 * 1024
MAX_INSTALLER = 8 * 1024 ** 3
DOWNLOAD_SECONDS = 4 * 60 * 60


class UpdateError(ValueError):
    """An invalid/stale update action; no package execution has occurred."""


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{1,5}', value):
        raise UpdateError('A four-part release version is required')
    parts = tuple(map(int, value.split('.')))
    try:
        date(*parts[:3])
    except ValueError as exc:
        raise UpdateError('Invalid release version date') from exc
    if not 1 <= parts[3] <= 65535:
        raise UpdateError('Invalid release build number')
    return parts


def identity(channel, tag, revision):
    if channel not in ('stable', 'development') or not isinstance(revision, str) or not re.fullmatch('[a-f0-9]{40}', revision):
        raise UpdateError('Invalid release channel or revision')
    if not isinstance(tag, str):
        raise UpdateError('Invalid release tag')
    pattern = r'v(.+)' if channel == 'stable' else r'DEV-(.+)-([1-9][0-9]{0,4})-([a-f0-9]{12})'
    match = re.fullmatch(pattern, tag)
    if not match or channel == 'development' and match[3] != revision[:12]:
        raise UpdateError('Release tag does not match its channel and commit')
    value = match[1]
    version(value)
    return value


def utc(value):
    if not isinstance(value, str) or len(value) > 64 or 'T' not in value:
        raise UpdateError('Invalid release timestamp')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError as exc:
        raise UpdateError('Invalid release timestamp') from exc
    if parsed.utcoffset() != timedelta(0):
        raise UpdateError('Release timestamp must use UTC')
    return value


def _https(url):
    parsed = urlsplit(url)
    return parsed.scheme == 'https' and not parsed.username and not parsed.password and not parsed.fragment and parsed.port in (None, 443)


class _ReleaseRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Only GitHub's release CDN may receive the signed installer redirect.
        if not _https(newurl) or urlsplit(newurl).hostname not in (
                'github.com', 'api.github.com', 'release-assets.githubusercontent.com',
                'objects.githubusercontent.com', 'github-releases.githubusercontent.com'):
            raise UpdateError('Release download redirected outside GitHub')
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None:
            # Even an approved release CDN must never receive the user's PAT.
            for collection in (redirected.headers, redirected.unredirected_hdrs):
                for key in list(collection):
                    if key.lower() == 'authorization': collection.pop(key, None)
        return redirected


def fetch(url, *, headers=None):
    values = {'User-Agent': 'Love2Gathering-Updater/1', 'Accept-Encoding': 'identity', 'X-GitHub-Api-Version': '2026-03-10',
              'Accept': 'application/vnd.github+json' if url.startswith(API) else 'application/octet-stream'}
    values.update(headers or {})
    if any(key.lower() == 'authorization' for key in values) and (urlsplit(url).hostname != 'api.github.com' or not url.startswith(API)):
        raise UpdateError('GitHub authorization is restricted to the project API')
    return build_opener(_ReleaseRedirects()).open(Request(url, headers=values), timeout=25)


def _absolute(value, label):
    if not isinstance(value, str) or not value or not Path(value).is_absolute():
        raise UpdateError(label + ' must be an absolute path')
    path = Path(value)
    if path.is_symlink() or path.resolve() != path:
        raise UpdateError(label + ' cannot use symbolic links')
    return path


def _json_file(path, maximum=32 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise UpdateError('Invalid installed update metadata')
    with path.open('rb') as source:
        raw = source.read(maximum + 1)
    if len(raw) > maximum:
        raise UpdateError('Installed update metadata is too large')
    result = json.loads(raw)
    if not isinstance(result, dict):
        raise UpdateError('Installed update metadata must be an object')
    return result


def _read(fetcher, url, maximum):
    with closing(fetcher(url)) as response:
        data = response.read(maximum + 1)
        if len(data) > maximum:
            raise UpdateError('Release metadata exceeds its size limit')
        return data


def _asset(release, name, maximum, authenticated=False):
    assets = release.get('assets')
    if not isinstance(assets, list) or len(assets) > 100:
        raise UpdateError('Invalid release assets')
    matches = [asset for asset in assets if isinstance(asset, dict) and asset.get('name') == name]
    if len(matches) != 1:
        raise UpdateError('Release must contain exactly one ' + name)
    asset = matches[0]
    expected = RELEASE_PAGE + '/download/' + release['tag_name'] + '/' + name
    size = asset.get('size')
    if asset.get('state') != 'uploaded' or type(size) is not int or not 1 <= size <= maximum or asset.get('browser_download_url') != expected:
        raise UpdateError('Invalid or incomplete release asset: ' + name)
    if authenticated:
        identifier = asset.get('id')
        if type(identifier) is not int or not 1 <= identifier <= 2 ** 63 - 1 or asset.get('url') != API + '/assets/' + str(identifier):
            raise UpdateError('Private release asset does not match its project API identity')
    return asset


def checksum(data, filename):
    try:
        text = data.decode('ascii')
    except UnicodeError as exc:
        raise UpdateError('Invalid checksum document') from exc
    found = None
    for line in text.splitlines():
        if not line:
            continue
        match = re.fullmatch(r'([a-fA-F0-9]{64})  ([A-Za-z0-9_.-]{1,180})', line)
        if not match or match[2] in ('.', '..'):
            raise UpdateError('Invalid checksum entry')
        if match[2] == filename:
            if found is not None:
                raise UpdateError('Installer checksum is ambiguous')
            found = match[1].lower()
    if found is None:
        raise UpdateError('Installer is missing its exact checksum entry')
    return found


class UpdateManager:
    def __init__(self, context_path=None, *, fetcher=None, credentials=None):
        self.lock = threading.RLock()
        self.fetch = fetcher or fetch
        self.credentials = credentials
        self._token = ''
        self.requires_authentication = False
        self.context = None
        self.candidate = None
        self.downloaded = None
        self.progress = None
        self.error = None
        self.thread = None
        self.state = 'unavailable'
        raw = context_path if context_path is not None else os.environ.get('LOVE2GATHERING_UPDATE_CONTEXT')
        if not raw:
            return
        try:
            path = _absolute(str(raw), 'Update context')
            context = _json_file(path)
            if type(context.get('schema')) is not int or context['schema'] != 1 or context.get('method') not in METHOD_SUFFIX:
                raise UpdateError('Unsupported installed update context')
            if not isinstance(context.get('token'), str) or not re.fullmatch('[A-Za-z0-9_-]{32,256}', context['token']):
                raise UpdateError('Invalid launcher update authorization')
            installed = identity(context.get('channel'), context.get('tag'), context.get('revision'))
            if installed != context.get('version'):
                raise UpdateError('Installed version and tag disagree')
            root = _absolute(context.get('root'), 'Installed root')
            if not root.is_dir() or (root / '.git').exists():
                raise UpdateError('Updates require an installed release, not a source checkout')
            release = _json_file(root / 'release.json')
            if any(release.get(key) != context.get(key) for key in ('version', 'channel', 'tag')) or release.get('sourceRevision') != context['revision']:
                raise UpdateError('Update context does not match this installed package')
            request = _absolute(context.get('requestPath'), 'Update request')
            work = _absolute(context.get('workDirectory'), 'Update work directory')
            if request != path.parent / 'update-request.json' or work != path.parent / 'updates' or root == path.parent or root in path.parent.parents:
                raise UpdateError('Update handoff must use the private launcher session')
            utc(context.get('builtAtUTC'))
            self.context = dict(context, root=str(root), requestPath=str(request), workDirectory=str(work))
            self.state = 'idle'
            try:
                self._token = self._credentials().get()
            except (ValueError, OSError):
                self.state, self.error, self.requires_authentication = 'error', 'Saved GitHub authorization could not be read. Save a new repository token.', True
        except (ValueError, OSError, TypeError) as exc:
            self.error = str(exc)

    def status(self):
        with self.lock:
            c = self.context
            candidate = {key: value for key, value in self.candidate.items() if not key.startswith('_')} if self.candidate else None
            if candidate and self._token and isinstance(candidate.get('notes'), str):
                candidate['notes'] = candidate['notes'].replace(self._token, '[redacted]')
            return deepcopy(dict(state=self.state, supported=c is not None, method=c['method'] if c else None,
                                 automaticInstall=bool(c and (c['method'] != 'flatpak' or c.get('externalHost') is True)),
                                 authenticated=bool(self._token), requiresAuthentication=self.requires_authentication,
                                 channel=c['channel'] if c else None,
                                 installed={key: c[key] for key in ('version', 'revision', 'tag', 'builtAtUTC')} if c else None,
                                 releasePage=RELEASE_PAGE, candidate=candidate, progress=self.progress, error=self.error))

    def _credentials(self):
        if self.credentials is None:
            from update_credentials import UpdateCredentials
            self.credentials = UpdateCredentials()
        return self.credentials

    def auth(self, token):
        with self.lock:
            if not self.context:
                raise UpdateError('GitHub update authorization requires an installed release')
            if self.state in ('checking', 'downloading', 'apply_requested'):
                raise UpdateError('Wait for the current update operation before changing GitHub authorization')
            from update_credentials import validate_token
            validate_token(token)
            try:
                self._credentials().set(token)
            except (OSError, ValueError) as exc:
                raise UpdateError('GitHub authorization could not be saved in the private user configuration') from exc
            self._token, self.requires_authentication, self.error = token, False, None
            self.candidate, self.progress = None, None
            self.state = 'idle' if self.context else 'unavailable'
            return self.status()

    def _fetch(self, url):
        if not self._token:
            return self.fetch(url)
        if urlsplit(url).hostname != 'api.github.com' or not url.startswith(API):
            raise UpdateError('Authenticated updates require the pinned project API')
        binary = re.fullmatch(re.escape(API) + r'/assets/[1-9][0-9]{0,18}', url) is not None
        return self.fetch(url, headers={'Authorization': 'Bearer ' + self._token,
                                       'Accept': 'application/octet-stream' if binary else 'application/vnd.github+json'})

    def _public_error(self, error):
        if isinstance(error, HTTPError):
            if error.code in (401, 403, 404):
                self.requires_authentication = True
                return 'GitHub requires repository access. Save a GitHub token with Contents read access to Alexayy/Love2Gathering, or retry if access is temporarily rate limited.'
            return 'GitHub update request failed (HTTP ' + str(error.code) + '). Try again later.'
        if isinstance(error, URLError):
            return 'GitHub could not be reached. Check the connection and try again.'
        message = str(error)
        return (message.replace(self._token, '[redacted]') if self._token else message)[:800]

    def _start(self, state, operation):
        with self.lock:
            if not self.context:
                return self.status()
            if self.state in ('checking', 'downloading', 'apply_requested'):
                return self.status()
            self.state, self.error = state, None
            def run():
                try:
                    operation()
                except Exception as exc:
                    with self.lock:
                        self.state, self.error = 'error', self._public_error(exc)
            self.thread = threading.Thread(target=run, name='package-update-' + state, daemon=True)
            self.thread.start()
            return self.status()

    def check(self):
        with self.lock:
            if self.context and self.state not in ('checking', 'downloading', 'apply_requested'):
                self.candidate, self.progress = None, None
            return self._start('checking', self._check)

    def _check(self):
        endpoint = API + '/latest' if self.context['channel'] == 'stable' else API + '?per_page=100'
        releases = json.loads(_read(self._fetch, endpoint, MAX_JSON))
        if self.context['channel'] == 'stable':
            releases = [releases]
        if not isinstance(releases, list) or len(releases) > 100:
            raise UpdateError('Invalid GitHub releases response')
        suitable = []
        for release in releases:
            if not isinstance(release, dict) or release.get('draft') is not False or release.get('prerelease') is not (self.context['channel'] == 'development'):
                continue
            try:
                value = identity(self.context['channel'], release.get('tag_name'), release.get('target_commitish'))
                if version(value) <= version(self.context['version']):
                    continue
                if release.get('html_url') != RELEASE_PAGE + '/tag/' + release['tag_name']:
                    continue
                suitable.append((version(value), value, release))
            except (UpdateError, TypeError):
                continue
        if not suitable:
            with self.lock:
                self.candidate, self.progress, self.state, self.requires_authentication = None, None, 'idle', False
            return
        _, value, release = max(suitable, key=lambda item: item[0])
        name = 'Love2Gathering-' + value + METHOD_SUFFIX[self.context['method']]
        asset = _asset(release, name, MAX_INSTALLER, bool(self._token))
        sums = _asset(release, 'SHA256SUMS', MAX_SUMS, bool(self._token))
        data = _read(self._fetch, sums['url'] if self._token else sums['browser_download_url'], MAX_SUMS)
        if len(data) != sums['size']:
            raise UpdateError('Checksum document size does not match its release')
        digest = checksum(data, name)
        identifier = hashlib.sha256((release['tag_name'] + '\n' + name + '\n' + str(asset['size']) + '\n' + digest).encode()).hexdigest()
        notes = release.get('body') or ''
        if not isinstance(notes, str):
            raise UpdateError('Invalid release notes')
        if self._token: notes = notes.replace(self._token, '[redacted]')
        published = utc(release.get('published_at'))
        candidate = dict(id=identifier, version=value, revision=release['target_commitish'], tag=release['tag_name'],
                         publishedAt=published, releasePage=release['html_url'], assetName=name,
                         expectedSize=asset['size'], checksum=digest, notes=str(notes)[:32000], _url=asset['url'] if self._token else asset['browser_download_url'])
        with self.lock:
            self.candidate, self.progress, self.state, self.requires_authentication = candidate, None, 'available', False

    def download(self, candidate_id):
        with self.lock:
            if not self.context:
                return self.status()
            if not self.candidate or not isinstance(candidate_id, str) or self.candidate['id'] != candidate_id:
                raise UpdateError('This update candidate is no longer current')
            if self.state == 'ready':
                return self.status()
            return self._start('downloading', self._download)

    def _download(self):
        candidate = self.candidate.copy()
        work = Path(self.context['workDirectory'])
        if work.is_symlink():
            raise UpdateError('Update work directory cannot be a symbolic link')
        work.mkdir(mode=0o700, exist_ok=True)
        if work.resolve() != work or not work.is_dir():
            raise UpdateError('Invalid update work directory')
        final = work / candidate['assetName']
        if final.is_symlink():
            raise UpdateError('Installer path cannot be a symbolic link')
        temporary = None
        with self.lock:
            self.progress = dict(downloadedBytes=0, totalBytes=candidate['expectedSize'])
        try:
            with tempfile.NamedTemporaryFile(prefix='.package-', suffix='.partial', dir=work, delete=False) as target:
                temporary = Path(target.name)
                digest, total, started = hashlib.sha256(), 0, time.monotonic()
                with closing(self._fetch(candidate['_url'])) as source:
                    while True:
                        if time.monotonic() - started > DOWNLOAD_SECONDS:
                            raise UpdateError('Installer download exceeded its time limit')
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > candidate['expectedSize']:
                            raise UpdateError('Installer exceeds its advertised size')
                        digest.update(chunk)
                        target.write(chunk)
                        with self.lock:
                            self.progress = dict(downloadedBytes=total, totalBytes=candidate['expectedSize'])
                if total != candidate['expectedSize'] or digest.hexdigest() != candidate['checksum']:
                    raise UpdateError('Installer checksum or size does not match its release')
                target.flush()
                os.fsync(target.fileno())
            temporary.replace(final)
            previous = self.downloaded
            info = final.stat()
            if previous and previous['path'] != str(final):
                old = Path(previous['path'])
                if old.parent == work and not old.is_symlink():
                    old.unlink(missing_ok=True)
            with self.lock:
                self.downloaded = dict(id=candidate['id'], path=str(final), identity=(info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns))
                self.state, self.requires_authentication = 'ready', False
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)

    def apply(self, candidate_id):
        with self.lock:
            if not self.context:
                return self.status()
            if self.state == 'apply_requested' and self.candidate and self.candidate['id'] == candidate_id:
                return self.status()
            if self.state != 'ready' or not self.candidate or self.candidate['id'] != candidate_id or not self.downloaded or self.downloaded['id'] != candidate_id:
                raise UpdateError('Download and verify the current installer before applying it')
            installer = Path(self.downloaded['path'])
            try:
                info = installer.lstat()
            except OSError as exc:
                raise UpdateError('Verified installer is unavailable; download it again') from exc
            if not stat.S_ISREG(info.st_mode) or (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != self.downloaded['identity']:
                raise UpdateError('Verified installer changed; download it again')
            request = Path(self.context['requestPath'])
            if request.exists() or request.is_symlink():
                raise UpdateError('The launcher already has a pending update request')
            job = {key: self.context[key] for key in ('token', 'root', 'method', 'channel')}
            job.update(schema=1, candidateId=candidate_id, installerPath=str(installer), checksum=self.candidate['checksum'],
                       expectedSize=self.candidate['expectedSize'], version=self.candidate['version'], tag=self.candidate['tag'], revision=self.candidate['revision'])
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', prefix='.update-request-', dir=request.parent, delete=False) as target:
                    temporary = Path(target.name)
                    json.dump(job, target, separators=(',', ':'))
                    target.flush()
                    os.fsync(target.fileno())
                temporary.replace(request)
            finally:
                if temporary:
                    temporary.unlink(missing_ok=True)
            self.state = 'apply_requested'
            return self.status()
