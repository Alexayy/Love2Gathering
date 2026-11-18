"""Pinned release selection and isolated complete-installer download/handoff."""
from copy import deepcopy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from urllib.request import urlopen
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import updates
from update_credentials import UpdateCredentials


class Fetch:
    def __init__(self):
        self.contents, self.calls, self.gates, self.requests = {}, [], {}, []

    def __call__(self, url, *, headers=None):
        self.calls.append(url)
        self.requests.append((url, dict(headers or {})))
        if url in self.gates:
            if not self.gates[url].wait(5):
                raise RuntimeError('Fixture gate timed out')
        value = self.contents[url]
        if isinstance(value, Exception):
            raise value
        return io.BytesIO(value)


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.root, self.session = self.directory / 'installed', self.directory / 'session'
        self.root.mkdir(); self.session.mkdir()
        self.context_path = self.session / 'update-context.json'
        self.credentials = UpdateCredentials(self.directory / 'private-config/updater-credentials/github-token')
        self.context = dict(schema=1, token='A' * 48, root=str(self.root), method='linux-run', channel='stable',
                            version='2026.11.17.10', revision='a' * 40, tag='v2026.11.17.10',
                            builtAtUTC='2026-11-17T12:00:00Z', requestPath=str(self.session / 'update-request.json'),
                            workDirectory=str(self.session / 'updates'))
        self.fetch = Fetch()
        self.package = b'#!/bin/sh\n# complete installer fixture\n' + b'payload' * 500
        self.release = self.release_for()
        self.save_context()
        self.publish()
        self.manager = updates.UpdateManager(self.context_path, fetcher=self.fetch, credentials=self.credentials)

    def tearDown(self):
        self.temp.cleanup()

    def release_for(self, value='2026.11.18.11', channel='stable', revision='b' * 40):
        tag = 'v' + value if channel == 'stable' else 'DEV-' + value + '-1-' + revision[:12]
        return dict(tag_name=tag, target_commitish=revision, draft=False, prerelease=channel == 'development',
                    html_url=updates.RELEASE_PAGE + '/tag/' + tag, body='Complete release notes',
                    published_at='2026-11-18T12:00:00Z', assets=[])

    def save_context(self):
        self.context_path.write_text(json.dumps(self.context))
        (self.root / 'release.json').write_text(json.dumps(dict(version=self.context['version'], channel=self.context['channel'],
                                                              tag=self.context['tag'], sourceRevision=self.context['revision'])))

    def publish(self):
        version = updates.identity('development' if self.release['prerelease'] else 'stable', self.release['tag_name'], self.release['target_commitish'])
        names = ['Love2Gathering-' + version + suffix for suffix in updates.METHOD_SUFFIX.values()]
        digest = hashlib.sha256(self.package).hexdigest()
        sums = ''.join(digest + '  ' + name + '\n' for name in names).encode()
        self.release['assets'] = []
        for identifier,name in enumerate(names + ['SHA256SUMS'],1):
            data = sums if name == 'SHA256SUMS' else self.package
            url = updates.RELEASE_PAGE + '/download/' + self.release['tag_name'] + '/' + name
            self.fetch.contents[url] = data
            api = updates.API + '/assets/' + str(identifier)
            self.fetch.contents[api] = data
            self.release['assets'].append(dict(id=identifier, url=api, name=name, size=len(data), state='uploaded', browser_download_url=url))
        self.save_releases()

    def save_releases(self, releases=None):
        self.fetch.contents[updates.API + '/latest'] = json.dumps(self.release).encode()
        self.fetch.contents[updates.API + '?per_page=100'] = json.dumps(releases if releases is not None else [self.release]).encode()

    def settle(self, manager=None):
        manager = manager or self.manager
        if manager.thread:
            manager.thread.join(5)
            self.assertFalse(manager.thread.is_alive(), 'Background update fixture failed to finish')
        return manager.status()

    def available(self):
        self.manager.check()
        status = self.settle()
        self.assertEqual(status['state'], 'available', status)
        return status['candidate']

    def ready(self):
        candidate = self.available()
        self.manager.download(candidate['id'])
        status = self.settle()
        self.assertEqual(status['state'], 'ready', status)
        return candidate

    def test_no_context_is_manual_only_and_performs_no_network_or_writes(self):
        manager = updates.UpdateManager('', fetcher=self.fetch, credentials=self.credentials)
        self.assertEqual(manager.status()['state'], 'unavailable')
        self.assertEqual(manager.status()['releasePage'], updates.RELEASE_PAGE)
        self.assertEqual(manager.check()['state'], 'unavailable')
        self.assertEqual(manager.download('anything')['state'], 'unavailable')
        self.assertEqual(manager.apply('anything')['state'], 'unavailable')
        self.assertFalse((self.session / 'updates').exists())
        self.assertFalse(self.fetch.calls)

    def test_auth_saves_and_forgets_only_explicit_temp_credentials_without_network(self):
        token = 'fixture_read_only_token_for_tests_123456'
        result = self.manager.auth(token)
        self.assertTrue(result['authenticated']); self.assertFalse(result['requiresAuthentication'])
        self.assertNotIn(token, json.dumps(result)); self.assertFalse(self.fetch.calls)
        self.assertEqual(self.credentials.get(), token)
        reopened = updates.UpdateManager(self.context_path, fetcher=self.fetch, credentials=self.credentials)
        self.assertTrue(reopened.status()['authenticated']); self.assertFalse(self.fetch.calls)
        result = self.manager.auth('')
        self.assertFalse(result['authenticated']); self.assertEqual(self.credentials.get(), '')
        self.assertFalse(self.fetch.calls)

    def test_source_checkout_auth_is_rejected_before_any_credential_io(self):
        class NoIO:
            def get(self): raise AssertionError('Source checkout must not read credentials')
            def set(self, value): raise AssertionError('Source checkout must not write credentials')
        manager = updates.UpdateManager('', fetcher=self.fetch, credentials=NoIO())
        with self.assertRaises(updates.UpdateError): manager.auth('fixture_read_only_token_for_tests_123456')
        self.assertFalse(manager.status()['authenticated']); self.assertFalse(self.fetch.calls)

    def test_private_release_assets_use_authenticated_api_ids_without_public_token_or_url(self):
        token = 'fixture_read_only_token_for_tests_123456'
        self.manager.auth(token); self.release['body'] = 'Private notes ' + token; self.save_releases()
        candidate = self.ready()
        self.assertNotIn(token, json.dumps(self.manager.status()))
        self.assertNotIn('_url', candidate); self.assertNotIn('_assetUrl', candidate)
        self.assertEqual(len(self.fetch.requests), 3)
        for url, headers in self.fetch.requests:
            self.assertTrue(url.startswith(updates.API)); self.assertEqual(headers['Authorization'], 'Bearer ' + token)
            self.assertEqual(headers['Accept'], 'application/octet-stream' if '/assets/' in url else 'application/vnd.github+json')
        self.assertEqual(self.fetch.requests[1][0], self.release['assets'][-1]['url'])
        self.assertEqual(self.fetch.requests[2][0], next(asset['url'] for asset in self.release['assets'] if asset['name'] == candidate['assetName']))
        self.assertEqual((self.session / 'updates' / candidate['assetName']).read_bytes(), self.package)

    def test_private_access_denial_requires_authentication_without_echoing_credentials(self):
        token = 'fixture_read_only_token_for_tests_123456'
        for code in (404, 401, 403):
            self.fetch.contents[updates.API + '/latest'] = HTTPError(updates.API + '/latest', code, 'never echo ' + token, {}, None)
            self.manager.check(); result = self.settle()
            self.assertEqual(result['state'], 'error'); self.assertTrue(result['requiresAuthentication'])
            self.assertNotIn(token, json.dumps(result)); self.assertIn('Contents read', result['error'])
        self.manager.auth(token); self.save_releases(); self.assertEqual(self.available()['version'], '2026.11.18.11')
        self.assertFalse(self.manager.status()['requiresAuthentication'])

    def test_credential_changes_are_fenced_during_check_download_and_pending_apply(self):
        token = 'fixture_read_only_token_for_tests_123456'; self.manager.auth(token)
        gate = threading.Event(); self.fetch.gates[updates.API + '/latest'] = gate
        self.manager.check()
        with self.assertRaises(updates.UpdateError): self.manager.auth('')
        self.assertEqual(self.credentials.get(), token); gate.set(); candidate = self.settle()['candidate']
        gate = threading.Event(); self.fetch.gates[self.manager.candidate['_url']] = gate
        self.manager.download(candidate['id'])
        with self.assertRaises(updates.UpdateError): self.manager.auth('another_fixture_read_only_token_123456')
        self.assertEqual(self.credentials.get(), token); gate.set(); self.assertEqual(self.settle()['state'], 'ready')
        self.manager.apply(candidate['id'])
        with self.assertRaises(updates.UpdateError): self.manager.auth('')

    def test_private_asset_urls_are_pinned_and_authenticated_redirects_always_drop_authorization(self):
        from urllib.request import Request
        token = 'fixture_read_only_token_for_tests_123456'; self.manager.auth(token)
        self.release['assets'][-1]['url'] = 'https://api.github.com/repos/other/repo/releases/assets/6'; self.save_releases()
        self.manager.check(); self.assertEqual(self.settle()['state'], 'error')
        self.assertEqual(len(self.fetch.calls), 1)
        handler = updates._ReleaseRedirects()
        request = Request(updates.API + '/assets/1', headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/octet-stream'})
        request.add_unredirected_header('Authorization', 'Bearer ' + token)
        for destination in ('https://release-assets.githubusercontent.com/native-bundle?signature=fixture', updates.API + '/assets/2'):
            redirected = handler.redirect_request(request, None, 302, 'redirect', {}, destination)
            self.assertTrue(all(key.lower() != 'authorization' for key in redirected.headers))
            self.assertTrue(all(key.lower() != 'authorization' for key in redirected.unredirected_hdrs))
        with self.assertRaises(updates.UpdateError): updates.fetch('https://github.com/Alexayy/Love2Gathering', headers={'Authorization': 'Bearer ' + token})
        self.fetch.contents[updates.API + '/latest'] = URLError('failed request contains ' + token)
        self.manager.check(); self.assertNotIn(token, json.dumps(self.settle()))

    def test_explicit_check_binds_full_package_name_channel_size_and_checksum(self):
        self.assertEqual(self.manager.status()['state'], 'idle')
        self.assertFalse(self.fetch.calls)
        candidate = self.available()
        self.assertEqual(candidate['version'], '2026.11.18.11')
        self.assertEqual(candidate['assetName'], 'Love2Gathering-2026.11.18.11-linux-x86_64.run')
        self.assertEqual(candidate['checksum'], hashlib.sha256(self.package).hexdigest())
        self.assertEqual(candidate['expectedSize'], len(self.package))
        self.assertNotIn('_url', candidate)
        self.assertNotIn(self.context['token'], json.dumps(self.manager.status()))
        self.assertEqual(len(self.fetch.calls), 2)
        self.assertFalse((self.session / 'updates').exists())

    def test_every_install_method_selects_its_actual_complete_installer(self):
        for method, suffix in updates.METHOD_SUFFIX.items():
            with self.subTest(method=method):
                self.context['method'] = method
                self.save_context()
                self.manager = updates.UpdateManager(self.context_path, fetcher=self.fetch, credentials=self.credentials)
                self.assertTrue(self.available()['assetName'].endswith(suffix))

    def test_development_ignores_stable_and_requires_commit_bound_tag(self):
        self.context.update(channel='development', tag='DEV-2026.11.17.10-1-' + 'a' * 12)
        self.save_context()
        stable = deepcopy(self.release)
        self.release = self.release_for(channel='development')
        self.publish()
        invalid = deepcopy(self.release); invalid['target_commitish'] = 'f' * 40
        self.save_releases([stable, invalid, self.release])
        self.manager = updates.UpdateManager(self.context_path, fetcher=self.fetch, credentials=self.credentials)
        self.assertEqual(self.available()['tag'], self.release['tag_name'])
        self.assertTrue(self.fetch.calls[0].endswith('?per_page=100'))

    def test_same_or_older_version_never_updates_even_different_commit(self):
        for value in ('2026.11.17.10', '2026.11.16.100'):
            self.release = self.release_for(value)
            self.publish()
            self.manager.check()
            self.assertEqual(self.settle()['state'], 'idle')
            self.assertIsNone(self.manager.status()['candidate'])
        self.assertTrue(all('/download/' not in url for url in self.fetch.calls))

    def test_wrong_channel_draft_bad_tag_and_bad_revision_are_not_offers(self):
        mutations = [dict(prerelease=True), dict(draft=True), dict(tag_name='foreign'),
                     dict(target_commitish='master'), dict(html_url='https://example.com/release')]
        for values in mutations:
            with self.subTest(values=values):
                self.release = self.release_for(); self.release.update(values); self.save_releases()
                self.manager.check()
                self.assertEqual(self.settle()['state'], 'idle')

    def test_missing_duplicate_truncated_or_foreign_installer_asset_fails_closed(self):
        wanted = 'Love2Gathering-2026.11.18.11-linux-x86_64.run'
        for mutation in ('missing', 'duplicate', 'foreign', 'pending', 'oversized'):
            with self.subTest(mutation=mutation):
                self.release = self.release_for(); self.publish()
                asset = next(a for a in self.release['assets'] if a['name'] == wanted)
                if mutation == 'missing': self.release['assets'].remove(asset)
                elif mutation == 'duplicate': self.release['assets'].append(asset.copy())
                elif mutation == 'foreign': asset['browser_download_url'] = 'https://example.com/installer.exe'
                elif mutation == 'pending': asset['state'] = 'new'
                else: asset['size'] = updates.MAX_INSTALLER + 1
                self.save_releases(); self.manager.check()
                self.assertEqual(self.settle()['state'], 'error')
                self.assertIsNone(self.manager.status()['candidate'])

    def test_exact_checksum_filename_is_required_and_duplicates_rejected(self):
        for text in ('f' * 64 + '  other.run\n', 'f' * 64 + '  ../evil.run\n', 'not a checksum\n'):
            with self.subTest(text=text):
                self.release = self.release_for(); self.publish()
                asset = self.release['assets'][-1]
                self.fetch.contents[asset['browser_download_url']] = text.encode(); asset['size'] = len(text)
                self.save_releases(); self.manager.check()
                self.assertEqual(self.settle()['state'], 'error')
        name = 'Love2Gathering-2026.11.18.11-linux-x86_64.run'
        with self.assertRaises(updates.UpdateError):
            updates.checksum((('f' * 64 + '  ' + name + '\n') * 2).encode(), name)

    def test_successful_download_is_stream_verified_and_atomic(self):
        candidate = self.ready()
        folder = self.session / 'updates'
        self.assertEqual(list(folder.iterdir()), [folder / candidate['assetName']])
        self.assertEqual((folder / candidate['assetName']).read_bytes(), self.package)
        self.assertEqual(self.manager.status()['progress'], dict(downloadedBytes=len(self.package), totalBytes=len(self.package)))
        before = len(self.fetch.calls)
        self.assertEqual(self.manager.download(candidate['id'])['state'], 'ready')
        self.assertEqual(len(self.fetch.calls), before)

    def test_corrupt_short_or_excess_download_never_becomes_ready(self):
        candidate = self.available()
        url = self.manager.candidate['_url']
        for data in (b'x' * len(self.package), self.package[:-1], self.package + b'x'):
            with self.subTest(size=len(data)):
                self.fetch.contents[url] = data
                self.manager.download(candidate['id'])
                self.assertEqual(self.settle()['state'], 'error')
                self.assertFalse(list((self.session / 'updates').iterdir()))
                self.assertFalse((self.session / 'update-request.json').exists())

    def test_apply_only_emits_fixed_authorized_supervisor_job_and_preserves_data(self):
        data = self.directory / 'user-data'; data.mkdir(); saved = data / 'app.sqlite'; saved.write_bytes(b'unchanged saves images and replays')
        app = self.root / 'app.love'; app.write_bytes(b'unchanged installed app')
        candidate = self.ready()
        status = self.manager.apply(candidate['id'])
        self.assertEqual(status['state'], 'apply_requested')
        job = json.loads((self.session / 'update-request.json').read_text())
        self.assertEqual(job['token'], self.context['token'])
        self.assertEqual(job['root'], str(self.root))
        self.assertEqual(job['method'], self.context['method'])
        self.assertEqual(job['checksum'], candidate['checksum'])
        self.assertEqual(job['revision'], candidate['revision'])
        self.assertEqual(job['expectedSize'], len(self.package))
        self.assertEqual(job['installerPath'], str(self.session / 'updates' / candidate['assetName']))
        self.assertEqual(saved.read_bytes(), b'unchanged saves images and replays')
        self.assertEqual(app.read_bytes(), b'unchanged installed app')
        self.assertEqual(self.manager.apply(candidate['id'])['state'], 'apply_requested')
        self.assertEqual(self.manager.check()['state'], 'apply_requested')

    def test_wrong_stale_and_unverified_candidate_ids_never_apply(self):
        for value in ('../installer.exe', '/tmp/evil.run', 'f' * 64, None):
            with self.assertRaises(updates.UpdateError): self.manager.download(value)
            with self.assertRaises(updates.UpdateError): self.manager.apply(value)
        candidate = self.available()
        with self.assertRaises(updates.UpdateError): self.manager.apply(candidate['id'])
        self.assertFalse((self.session / 'update-request.json').exists())

    def test_changed_or_symlinked_ready_installer_cannot_apply(self):
        candidate = self.ready()
        target = self.session / 'updates' / candidate['assetName']
        target.write_bytes(b'changed')
        with self.assertRaises(updates.UpdateError): self.manager.apply(candidate['id'])
        target.unlink(); target.symlink_to(self.root / 'release.json')
        with self.assertRaises(updates.UpdateError): self.manager.apply(candidate['id'])
        self.assertFalse((self.session / 'update-request.json').exists())

    def test_existing_handoff_and_late_path_symlinks_are_not_overwritten(self):
        candidate = self.ready()
        request = self.session / 'update-request.json'; request.write_bytes(b'previous pending job')
        with self.assertRaises(updates.UpdateError): self.manager.apply(candidate['id'])
        self.assertEqual(request.read_bytes(), b'previous pending job')
        request.unlink(); request.symlink_to(self.root / 'release.json')
        with self.assertRaises(updates.UpdateError): self.manager.apply(candidate['id'])

    def test_source_checkout_and_mismatched_installed_context_are_manual_only(self):
        for mutation in ('checkout', 'revision', 'method', 'version', 'request', 'work', 'token', 'schema'):
            with self.subTest(mutation=mutation):
                c = self.context.copy()
                if mutation == 'checkout': (self.root / '.git').mkdir()
                elif mutation == 'revision': c['revision'] = 'f' * 40
                elif mutation == 'method': c['method'] = 'arbitrary-shell'
                elif mutation == 'version': c['version'] = '2026.11.17'
                elif mutation == 'request': c['requestPath'] = str(self.root / 'app.love')
                elif mutation == 'work': c['workDirectory'] = str(self.root / 'updates')
                elif mutation == 'token': c['token'] = 'short'
                else: c['schema'] = True
                self.context_path.write_text(json.dumps(c))
                manager = updates.UpdateManager(self.context_path, fetcher=self.fetch, credentials=self.credentials)
                self.assertEqual(manager.check()['state'], 'unavailable')
                self.assertFalse(manager.status()['supported'])
                if mutation == 'checkout': (self.root / '.git').rmdir()
        self.assertFalse(self.fetch.calls)

    def test_symbolic_link_work_directory_cannot_redirect_download_into_user_data(self):
        candidate = self.available()
        data = self.directory / 'user-data'; data.mkdir(); (self.session / 'updates').symlink_to(data, target_is_directory=True)
        self.manager.download(candidate['id'])
        self.assertEqual(self.settle()['state'], 'error')
        self.assertFalse(list(data.iterdir()))

    def test_check_and_download_are_nonblocking_and_single_job(self):
        gate = threading.Event(); self.fetch.gates[updates.API + '/latest'] = gate
        started = time.monotonic(); first = self.manager.check(); thread = self.manager.thread
        self.assertLess(time.monotonic() - started, .5); self.assertEqual(first['state'], 'checking')
        self.manager.check(); self.assertIs(self.manager.thread, thread)
        gate.set(); candidate = self.settle()['candidate']
        gate = threading.Event(); self.fetch.gates[self.manager.candidate['_url']] = gate
        started = time.monotonic(); self.manager.download(candidate['id']); thread = self.manager.thread
        self.assertLess(time.monotonic() - started, .5)
        self.manager.check(); self.manager.download(candidate['id']); self.assertIs(self.manager.thread, thread)
        gate.set(); self.assertEqual(self.settle()['state'], 'ready')

    def test_malformed_oversized_and_failed_metadata_remain_retriable(self):
        endpoint = updates.API + '/latest'
        for data in (b'{broken', b'x' * (updates.MAX_JSON + 1), OSError('offline')):
            self.fetch.contents[endpoint] = data; self.manager.check()
            self.assertEqual(self.settle()['state'], 'error')
        self.save_releases(); self.manager.check(); self.assertEqual(self.settle()['state'], 'available')

    def test_invalid_timestamp_notes_and_untrusted_redirects_are_rejected(self):
        for values in (dict(published_at='yesterday'), dict(published_at='2026-11-18T12:00:00'), dict(body={'not': 'release notes'})):
            self.release = self.release_for(); self.publish(); self.release.update(values); self.save_releases()
            self.manager.check(); self.assertEqual(self.settle()['state'], 'error')
        from urllib.request import Request
        handler = updates._ReleaseRedirects()
        for url in ('http://github.com/unsafe', 'https://example.com/installer', 'https://user:password@github.com/installer'):
            with self.assertRaises(updates.UpdateError):
                handler.redirect_request(Request(updates.API), None, 302, 'redirect', {}, url)


    def test_real_http_short_read_and_server_failure_never_publish_an_installer(self):
        candidate = self.available()
        body = self.package
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                if self.path == '/fail':
                    self.send_error(503); return
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                self.wfile.write(body[:-12]); self.wfile.flush(); self.close_connection = True
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            for endpoint in ('short', 'fail'):
                self.manager.fetch = lambda _: urlopen('http://127.0.0.1:' + str(server.server_port) + '/' + endpoint, timeout=2)
                self.manager.download(candidate['id'])
                self.assertEqual(self.settle()['state'], 'error')
                self.assertFalse(list((self.session / 'updates').iterdir()))
        finally:
            server.shutdown(); server.server_close(); thread.join(2)


if __name__ == '__main__':
    unittest.main()
