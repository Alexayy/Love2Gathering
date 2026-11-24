"""Actual owned catalog HTTP endpoints with an injected isolated update manager."""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from storage_locations import StorageLocations
import server
import updates
from service.tests import test_updates as fixture


class UpdateHTTPTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixture.UpdateTest('test_explicit_check_binds_full_package_name_channel_size_and_checksum')
        self.fixture.setUp()
        self.manager = self.fixture.manager
        root = self.fixture.directory
        source = root / 'cards.jsonl'
        source.write_text(json.dumps({'object': 'card', 'id': 'fixture-printing', 'oracle_id': 'fixture-oracle',
                                      'name': 'Forest', 'lang': 'en', 'set': 'tst', 'type_line': 'Basic Land — Forest'}) + '\n')
        self.catalog = Catalog(source, root / 'catalog.sqlite'); self.catalog.ensure()
        self.storage = Storage(root / 'user-data', root / 'bundled', cache_dir=root / 'user-cache')
        self.storage.save_settings({'musicVolume': .42})
        self.locations = StorageLocations(self.storage, environ={'LOVE2GATHERING_CONFIG_DIR': str(root / 'config')})
        with patch.object(server, 'UpdateManager', return_value=self.manager) as factory:
            self.handler = server.make_handler(self.catalog, self.storage, location_manager=self.locations)
            factory.assert_called_once_with()
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), self.handler)
        self.server.daemon_threads = True
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True); self.worker.start()
        self.base = 'http://127.0.0.1:' + str(self.server.server_port)

    def tearDown(self):
        for gate in self.fixture.fetch.gates.values(): gate.set()
        if self.manager.thread: self.manager.thread.join(5)
        self.server.shutdown(); self.server.server_close(); self.worker.join(2)
        self.handler.close_managers()
        self.fixture.tearDown()

    def call(self, path, body=None, *, headers=None, raw=None):
        head = {'Content-Type': 'application/json'}
        head.update(headers or {})
        data = raw if raw is not None else json.dumps(body).encode() if body is not None else None
        request = Request(self.base + path, data=data, headers=head)
        try:
            with urlopen(request, timeout=3) as response: return response.status, json.load(response)
        except HTTPError as error:
            return error.code, json.load(error)

    def settle(self, expected):
        self.fixture.settle(self.manager)
        code, status = self.call('/updates/status')
        self.assertEqual(code, 200); self.assertEqual(status['state'], expected, status)
        return status

    def available(self):
        code, _ = self.call('/updates/check', {})
        self.assertEqual(code, 202)
        return self.settle('available')['candidate']

    def test_startup_and_status_never_fetch_or_expose_launcher_authorization(self):
        code, status = self.call('/updates/status')
        self.assertEqual(code, 200); self.assertEqual(status['state'], 'idle')
        self.assertFalse(self.fixture.fetch.calls)
        self.assertNotIn(self.fixture.context['token'], json.dumps(status))
        self.assertNotIn('requestPath', status); self.assertNotIn('workDirectory', status)
        self.assertFalse((self.fixture.session / 'updates').exists())

    def test_check_and_download_return_while_network_job_is_blocked_and_status_stays_responsive(self):
        gate = threading.Event(); self.fixture.fetch.gates[updates.API + '/latest'] = gate
        started = time.monotonic(); code, status = self.call('/updates/check', {})
        self.assertLess(time.monotonic() - started, .7)
        self.assertEqual(code, 202); self.assertEqual(status['state'], 'checking')
        thread = self.manager.thread
        self.assertEqual(self.call('/updates/status')[1]['state'], 'checking')
        self.assertEqual(self.call('/updates/check', {})[1]['state'], 'checking')
        self.assertIs(self.manager.thread, thread)
        gate.set(); candidate = self.settle('available')['candidate']
        gate = threading.Event(); self.fixture.fetch.gates[self.manager.candidate['_url']] = gate
        started = time.monotonic(); code, status = self.call('/updates/download', {'candidateId': candidate['id']})
        self.assertLess(time.monotonic() - started, .7)
        self.assertEqual(code, 202); self.assertEqual(status['state'], 'downloading')
        thread = self.manager.thread
        self.assertEqual(self.call('/updates/status')[1]['state'], 'downloading')
        self.call('/updates/download', {'candidateId': candidate['id']}); self.call('/updates/check', {})
        self.assertIs(self.manager.thread, thread)
        gate.set(); self.settle('ready')

    def test_exact_post_bodies_prevent_arbitrary_paths_urls_and_commands(self):
        cases = [('/updates/check', {'url': 'https://example.com/evil'}), ('/updates/check', []),
                 ('/updates/check', {'channel': 'stable'}), ('/updates/download', {'installerPath': '/tmp/evil.run'}),
                 ('/updates/download', {'candidateId': 'anything', 'path': '/tmp/evil.run'}),
                 ('/updates/apply', {'candidateId': 'anything', 'root': '/etc'}),
                 ('/updates/apply', {'candidateId': 'anything', 'command': 'shell command'}),
                 ('/updates/apply', []), ('/updates/apply', {})]
        for path, body in cases:
            with self.subTest(path=path, body=body): self.assertEqual(self.call(path, body)[0], 400)
        self.assertFalse(self.fixture.fetch.calls)
        self.assertFalse((self.fixture.session / 'update-request.json').exists())

    def test_origin_and_fetch_site_cannot_invoke_update_actions(self):
        for path, body in (('/updates/check', {}), ('/updates/download', {'candidateId': 'x'}), ('/updates/apply', {'candidateId': 'x'})):
            for headers in ({'Origin': 'https://untrusted.example'}, {'Origin': self.base},
                            {'Sec-Fetch-Site': 'cross-site'}, {'Sec-Fetch-Site': 'same-origin'}, {'Sec-Fetch-Site': 'none'}):
                with self.subTest(path=path, headers=headers): self.assertEqual(self.call(path, body, headers=headers)[0], 403)
        self.assertFalse(self.fixture.fetch.calls)

    def test_wrong_content_type_malformed_json_and_wrong_method_are_rejected(self):
        self.assertEqual(self.call('/updates/check', {}, headers={'Content-Type': 'text/plain'})[0], 400)
        self.assertEqual(self.call('/updates/check', raw=b'{broken')[0], 400)
        self.assertEqual(self.call('/updates/check', raw=b'null')[0], 400)
        self.assertEqual(self.call('/updates/check')[0], 404)
        self.assertFalse(self.fixture.fetch.calls)

    def test_only_current_verified_candidate_can_write_trusted_handoff(self):
        candidate = self.available()
        for identifier in ('../evil.exe', '/tmp/arbitrary.run', 'f' * 64, None):
            with self.subTest(identifier=identifier):
                self.assertEqual(self.call('/updates/download', {'candidateId': identifier})[0], 400)
                self.assertEqual(self.call('/updates/apply', {'candidateId': identifier})[0], 400)
        self.assertEqual(self.call('/updates/apply', {'candidateId': candidate['id']})[0], 400)
        self.assertEqual(self.call('/updates/download', {'candidateId': candidate['id']})[0], 202)
        self.settle('ready')
        code, status = self.call('/updates/apply', {'candidateId': candidate['id']})
        self.assertEqual(code, 202); self.assertEqual(status['state'], 'apply_requested')
        job = json.loads((self.fixture.session / 'update-request.json').read_text())
        self.assertEqual(job['root'], self.fixture.context['root'])
        self.assertEqual(job['token'], self.fixture.context['token'])
        self.assertEqual(job['checksum'], candidate['checksum'])
        self.assertEqual(Path(job['installerPath']).read_bytes(), self.fixture.package)
        self.assertEqual(self.storage.settings()['musicVolume'], .42)

    def test_fresh_check_retires_stale_candidate_id(self):
        old = self.available()
        self.fixture.release = self.fixture.release_for(value='2026.11.16.9'); self.fixture.publish()
        self.assertEqual(self.call('/updates/check', {})[0], 202); self.settle('idle')
        self.assertEqual(self.call('/updates/download', {'candidateId': old['id']})[0], 400)
        self.assertFalse((self.fixture.session / 'updates').exists())


if __name__ == '__main__':
    unittest.main()
