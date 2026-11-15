"""Explicit local ZIP preview/import through real isolated HTTP controls."""
import json
from pathlib import Path
import sys
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_image_packs as fixtures
from downloads import image_job_lock
from server import make_handler


class ImagePackHttpTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.ImagePackTests()
        self.fixture.setUp()
        self.fixture.manager.close()
        self.handler = make_handler(self.fixture.catalog, self.fixture.store)
        self.fixture.manager = self.handler.image_packs
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), self.handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.base = 'http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(3)
        self.handler.close_managers(); self.fixture.tearDown()
        self.assertFalse(self.thread.is_alive())

    def request(self, path, value=None, headers=None):
        request = Request(self.base+'/storage/image-packs/'+path,
                          data=json.dumps(value).encode() if value is not None else None,
                          headers={'Content-Type':'application/json', **(headers or {})})
        try: response = urlopen(request, timeout=3)
        except HTTPError as response:
            return response.code, json.loads(response.read())
        with response:
            return response.status, json.loads(response.read())

    def test_preview_never_installs_then_explicit_import_is_available_offline(self):
        archive = self.fixture.pack()
        code, state = self.request('inspect', {'path':str(archive)})
        self.assertEqual(code, 202)
        ready = self.fixture.wait(); self.assertEqual(ready['state'], 'ready')
        self.assertIsNone(self.fixture.store.get_art('first-0-normal.jpg'))
        code, state = self.request('status'); self.assertEqual((code, state['missing']), (200, 2))
        code, state = self.request('install', {'jobId':ready['jobId']}); self.assertEqual(code, 202)
        self.assertEqual(self.fixture.wait()['installed'], 2)
        with urlopen(self.base+'/art/oracle-first?printing=first&exact=1&network=0', timeout=3) as response:
            self.assertEqual(response.read(), fixtures.JPEG)

    def test_origin_body_and_job_guards_reject_unreviewed_actions(self):
        self.assertEqual(self.request('inspect', {'path':str(self.fixture.pack())}, {'Origin':'https://example.invalid'})[0], 403)
        self.assertEqual(self.request('inspect', {'path':'/tmp/irrelevant', 'extra':True})[0], 400)
        self.assertEqual(self.request('install', {'jobId':'unreviewed'})[0], 409)
        self.assertIsNone(self.fixture.store.get_art('first-0-normal.jpg'))

    def test_bulk_job_allows_read_only_preview_but_fences_import(self):
        archive = self.fixture.pack()
        with image_job_lock(self.fixture.store.root, blocking=False):
            self.assertEqual(self.request('inspect', {'path':str(archive)})[0], 202)
            ready = self.fixture.wait(); self.assertEqual(ready['state'], 'ready')
            code, body = self.request('install', {'jobId':ready['jobId']})
            self.assertEqual(code, 409); self.assertIn('Pause', body['error'])
        self.assertIsNone(self.fixture.store.get_art('first-0-normal.jpg'))


if __name__ == '__main__': unittest.main()
