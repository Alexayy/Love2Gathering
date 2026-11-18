"""Explicit private-release authorization through owned catalog HTTP endpoints."""
import json
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from service.tests import test_updates_http as http_fixture

TOKEN = 'ghp_' + 'http_fixture_read_only_1234567890'
OTHER = 'github_pat_' + 'second_http_fixture_1234567890'


class UpdateAuthHTTPTest(unittest.TestCase):
    def setUp(self):
        self.http = http_fixture.UpdateHTTPTest('test_startup_and_status_never_fetch_or_expose_launcher_authorization')
        self.http.setUp()

    def tearDown(self):
        self.http.tearDown()

    def assert_redacted(self, value):
        text = json.dumps(value)
        self.assertNotIn(TOKEN, text)
        self.assertNotIn(OTHER, text)
        self.assertNotIn(self.http.fixture.context['token'], text)

    def authenticate(self, token=TOKEN):
        code, status = self.http.call('/updates/auth', {'token': token})
        self.assertEqual(code, 202, status)
        self.assertEqual(status['authenticated'], bool(token))
        self.assertFalse(status['requiresAuthentication'])
        self.assert_redacted(status)
        return status

    def test_save_and_forget_are_private_persistent_and_make_no_network_request(self):
        self.assertFalse(self.http.fixture.fetch.calls)
        self.assertFalse(self.http.fixture.credentials.path.exists())
        status = self.authenticate()
        self.assertEqual(status['state'], 'idle')
        self.assertEqual(self.http.fixture.credentials.get(), TOKEN)
        self.assertTrue(self.http.fixture.credentials.path.is_file())
        self.assert_redacted(self.http.call('/updates/status')[1])
        self.authenticate('')
        self.assertEqual(self.http.fixture.credentials.get(), '')
        self.assertFalse(self.http.fixture.credentials.path.exists())
        self.assertFalse(self.http.fixture.fetch.calls)
        self.assertEqual(self.http.storage.settings()['musicVolume'], .42)

    def test_invalid_body_origin_and_fetch_site_cannot_save_a_credential(self):
        for body in ({}, [], {'token': TOKEN, 'path': '/tmp/foreign-token'}, {'token': None},
                     {'token': 12}, {'token': TOKEN + '\r\nAuthorization: injected'}, {'token': 'short'}):
            with self.subTest(kind=type(body).__name__):
                code, result = self.http.call('/updates/auth', body)
                self.assertEqual(code, 400); self.assert_redacted(result)
        for headers in ({'Origin': 'https://untrusted.example'}, {'Origin': self.http.base},
                        {'Sec-Fetch-Site': 'cross-site'}, {'Sec-Fetch-Site': 'same-origin'}, {'Sec-Fetch-Site': 'none'}):
            with self.subTest(headers=headers):
                code, result = self.http.call('/updates/auth', {'token': TOKEN}, headers=headers)
                self.assertEqual(code, 403); self.assert_redacted(result)
        code, result = self.http.call('/updates/auth', {'token': TOKEN}, headers={'Content-Type': 'text/plain'})
        self.assertEqual(code, 400); self.assert_redacted(result)
        self.assertFalse(self.http.fixture.credentials.path.exists())
        self.assertFalse(self.http.fixture.fetch.calls)
        self.assertFalse(self.http.call('/updates/status')[1]['authenticated'])

    def test_unavailable_source_manager_rejects_auth_without_credential_io(self):
        class ForbiddenCredentials:
            def __init__(self): self.calls = []
            def get(self): self.calls.append('get'); raise AssertionError('Unavailable source build read a credential')
            def set(self, _): self.calls.append('set'); raise AssertionError('Unavailable source build wrote a credential')
        guard = ForbiddenCredentials()
        updates = http_fixture.updates
        manager = updates.UpdateManager('', credentials=guard)
        self.assertEqual(manager.status()['state'], 'unavailable')
        self.http.tearDown()
        self.http = http_fixture.UpdateHTTPTest('test_startup_and_status_never_fetch_or_expose_launcher_authorization')
        with patch.object(http_fixture.fixture.updates, 'UpdateManager', return_value=manager):
            self.http.setUp()
        for token in (TOKEN, ''):
            code, result = self.http.call('/updates/auth', {'token': token})
            self.assertEqual(code, 400); self.assertIn('installed release', result['error']); self.assert_redacted(result)
        self.assertEqual(guard.calls, [])
        self.assertFalse(self.http.fixture.fetch.calls)
        self.assertFalse(self.http.fixture.credentials.path.exists())

    def test_private_404_requires_auth_then_metadata_and_assets_use_pinned_api_headers(self):
        updates = http_fixture.updates
        endpoint = updates.API + '/latest'
        self.http.fixture.fetch.contents[endpoint] = HTTPError(endpoint, 404, 'Private repository', {}, None)
        self.assertEqual(self.http.call('/updates/check', {})[0], 202)
        status = self.http.settle('error')
        self.assertTrue(status['requiresAuthentication']); self.assertFalse(status['authenticated'])
        self.assertIn('Contents read access', status['error']); self.assert_redacted(status)
        self.authenticate()
        # A provider response that unexpectedly echoes the supplied token must
        # not send it back to the public status/HTTP candidate representation.
        self.http.fixture.release['body'] = 'Release notes with accidental token echo: ' + TOKEN
        self.http.fixture.save_releases()
        candidate = self.http.available()
        wanted = next(asset for asset in self.http.fixture.release['assets'] if asset['name'] == candidate['assetName'])
        sums = next(asset for asset in self.http.fixture.release['assets'] if asset['name'] == 'SHA256SUMS')
        self.assertEqual([request[0] for request in self.http.fixture.fetch.requests[-2:]], [endpoint, sums['url']])
        self.assertEqual(self.http.fixture.fetch.requests[-2][1], {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json'})
        self.assertEqual(self.http.fixture.fetch.requests[-1][1], {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/octet-stream'})
        self.assertEqual(self.http.call('/updates/download', {'candidateId': candidate['id']})[0], 202)
        status = self.http.settle('ready')
        self.assertEqual(self.http.fixture.fetch.requests[-1], (wanted['url'], {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/octet-stream'}))
        self.assertTrue(all(url.startswith(updates.API) for url, _ in self.http.fixture.fetch.requests))
        self.assert_redacted(status)
        public = json.dumps(status)
        for private in (wanted['url'], sums['url'], '_url', '_asseturl', 'Authorization', 'Bearer '): self.assertNotIn(private, public)
        self.assertFalse(status['requiresAuthentication'])

    def test_busy_check_and_download_reject_token_change_and_forget(self):
        self.authenticate()
        updates = http_fixture.updates
        gate = threading.Event(); self.http.fixture.fetch.gates[updates.API + '/latest'] = gate
        self.assertEqual(self.http.call('/updates/check', {})[0], 202)
        self.assertEqual(self.http.call('/updates/status')[1]['state'], 'checking')
        for token in (OTHER, ''):
            code, result = self.http.call('/updates/auth', {'token': token})
            self.assertEqual(code, 400); self.assert_redacted(result)
        self.assertEqual(self.http.fixture.credentials.get(), TOKEN)
        gate.set(); candidate = self.http.settle('available')['candidate']
        gate = threading.Event(); self.http.fixture.fetch.gates[self.http.manager.candidate['_url']] = gate
        self.assertEqual(self.http.call('/updates/download', {'candidateId': candidate['id']})[0], 202)
        self.assertEqual(self.http.call('/updates/status')[1]['state'], 'downloading')
        for token in (OTHER, ''):
            code, result = self.http.call('/updates/auth', {'token': token})
            self.assertEqual(code, 400); self.assert_redacted(result)
        self.assertEqual(self.http.fixture.credentials.get(), TOKEN)
        gate.set(); self.http.settle('ready')
        self.assertTrue(all(not headers or headers['Authorization'] == 'Bearer ' + TOKEN for _, headers in self.http.fixture.fetch.requests))
        before = len(self.http.fixture.fetch.calls)
        self.authenticate(OTHER)
        self.assertEqual(self.http.fixture.credentials.get(), OTHER)
        self.assertEqual(len(self.http.fixture.fetch.calls), before)
        self.assertIsNone(self.http.call('/updates/status')[1]['candidate'])


if __name__ == '__main__': unittest.main()
