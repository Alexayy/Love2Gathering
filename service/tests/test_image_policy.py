"""On-demand is a durable local cache policy, not a live image stream."""
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from server import make_handler
from storage import Storage
from http.server import ThreadingHTTPServer


class ImagePolicyTests(unittest.TestCase):
    def test_budget_and_source_persist_without_unbounded_settings(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-policy-') as tmp:
            root = Path(tmp)
            store = Storage(root/'data', root/'bundled')
            self.assertEqual(store.settings()['artworkMemoryMiB'], 256)
            store.save_settings({'localArtworkOnly': False, 'artworkMemoryMiB': 512})
            saved = Storage(root/'data', root/'bundled').settings()
            self.assertFalse(saved['localArtworkOnly'])
            self.assertEqual(saved['artworkMemoryMiB'], 512)
            for invalid in (True, 0, 1024, '512'):
                with self.assertRaises(ValueError):
                    store.save_settings({'artworkMemoryMiB': invalid})
            self.assertEqual(store.settings()['artworkMemoryMiB'], 512)

    def test_cache_only_miss_then_on_demand_fetches_once_and_survives_reopen(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-policy-http-') as tmp:
            root = Path(tmp)
            printing, oracle = '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'
            source = root/'cards.jsonl'
            source.write_text(json.dumps({'object':'card','id':printing,'oracle_id':oracle,'name':'Cache Fixture','lang':'en','type_line':'Instant','legalities':{'modern':'legal'},'set':'tst','image_uris':{'normal':'https://cards.scryfall.io/normal/fixture.jpg'}})+'\n')
            catalog = Catalog(source, root/'catalog.sqlite'); catalog.ensure()
            store = Storage(root/'data', root/'bundled')
            handler = make_handler(catalog, store)
            calls = []
            data = b'\xff\xd8isolated-http-cache-fixture\xff\xd9'
            def fetch(_self, url):
                calls.append(url)
                return data
            handler.download_art = fetch
            server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            base = 'http://127.0.0.1:'+str(server.server_port)
            path = '/art/'+oracle+'?printing='+printing+'&kind=normal&exact=1'
            try:
                with self.assertRaises(HTTPError) as missing:
                    urlopen(base+path+'&network=0', timeout=3)
                self.assertEqual(missing.exception.code, 404)
                self.assertEqual(calls, [])
                store.save_settings({'localArtworkOnly': False})
                with urlopen(base+path, timeout=3) as response:
                    self.assertEqual(response.read(), data)
                self.assertEqual(len(calls), 1)
                with urlopen(base+path+'&network=0', timeout=3) as response:
                    self.assertEqual(response.read(), data)
                reopened = Storage(root/'data', root/'bundled')
                self.assertEqual(reopened.local_art(printing, oracle, aliases=False)[0], data)
                reopened.save_settings({'localArtworkOnly': True})
                with urlopen(base+path, timeout=3) as response:
                    self.assertEqual(response.read(), data)
                self.assertEqual(len(calls), 1, 'A saved image must never be fetched again merely because a view reopens')
            finally:
                server.shutdown(); server.server_close(); thread.join(3)
                self.assertFalse(thread.is_alive())


if __name__ == '__main__':
    unittest.main()
