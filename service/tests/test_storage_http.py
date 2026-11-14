"""Real local HTTP controls against isolated SQLite and a bounded image source."""
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request,urlopen
from urllib.error import HTTPError

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from server import make_handler
from maintenance import operation_lock


class StorageHttpTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.source=self.root/'cards.jsonl'
        raw={'object':'card','id':'storage-printing','oracle_id':'storage-oracle','name':'Storage Card','lang':'en','type_line':'Creature','oracle_text':'','colors':['W'],'color_identity':['W'],'set':'tst','set_name':'Test','legalities':{'modern':'legal'},'image_uris':{kind:'https://cards.scryfall.io/'+kind+'/storage.jpg'for kind in('normal','large','art_crop')}}
        self.source.write_text(json.dumps(raw)+'\n')
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.storage=Storage(self.root/'saves',self.root/'bundled')
        self.handler=make_handler(self.catalog,self.storage)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),self.handler);self.server.daemon_threads=True
        self.worker=threading.Thread(target=self.server.serve_forever,daemon=True);self.worker.start()
        self.base='http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.handler.close_managers();self.server.shutdown();self.server.server_close();self.worker.join();self.tmp.cleanup()

    def request(self,path,body=None,headers=None):
        request=Request(self.base+path,data=None if body is None else json.dumps(body).encode(),headers=headers or({'Content-Type':'application/json'}if body is not None else{}),method='GET'if body is None else'POST')
        with urlopen(request,timeout=3)as response:return json.load(response)

    def wait(self,fn,label):
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            value=fn()
            if value:return value
            time.sleep(.015)
        self.fail('Timed out: '+label)

    def usage(self):
        return self.wait(lambda:(lambda s:s if s.get('stats')and not s.get('scanning')else None)(self.request('/storage/status')),'storage stats')

    def test_mounted_identity_and_no_download_side_effect_from_status(self):
        health=self.request('/health');self.assertEqual(health['apiVersion'],8)
        self.assertEqual(health['storage']['dataDirectory'],str(self.storage.root))
        status=self.request('/downloads/status');self.assertEqual(status['state'],'idle')
        self.assertEqual(self.usage()['dataDirectory'],str(self.storage.root))
        self.assertEqual(self.storage.artwork_summary()['cachedImages'],0)

    def test_browser_requests_and_untyped_destructive_bodies_are_rejected(self):
        for path,body in(('/storage/purge',{'categories':['replays']}),('/storage/compact',{}),('/downloads/scan',{}),('/downloads/control',{'command':'start'})):
            with self.subTest(path=path):
                with self.assertRaises(HTTPError)as exc:self.request(path,body,{'Content-Type':'application/json','Origin':'https://untrusted.example'})
                self.assertEqual(exc.exception.code,403)
                with self.assertRaises(HTTPError)as exc:self.request(path,body,{'Content-Type':'text/plain'})
                self.assertEqual(exc.exception.code,400)
        self.assertEqual(self.request('/downloads/status')['state'],'idle')

    def test_health_and_progress_remain_available_while_database_is_exclusive(self):
        with operation_lock(self.storage.root,exclusive=True,blocking=False):
            started=time.monotonic()
            health=self.request('/health')
            self.assertTrue(health['ready']);self.assertTrue(health['storage']['maintenanceBusy'])
            self.assertEqual(health['storage']['dataDirectory'],str(self.storage.root))
            self.assertTrue(self.request('/downloads/status')['maintenanceBusy'])
            self.assertIn('operation',self.request('/storage/status'))
            for path in('/art/cache-info','/gallery/art/storage-printing'):
                with self.assertRaises(HTTPError)as exc:self.request(path)
                self.assertEqual(exc.exception.code,409)
            self.assertLess(time.monotonic()-started,1.5)

    def test_explicit_scan_then_download_uses_only_missing_images(self):
        image=b'\xff\xd8bounded-fixture\xff\xd9';fetched=[]
        class Fetcher:
            def image(self,url):fetched.append(url);return image
        self.handler.downloads.fetcher_factory=Fetcher
        self.storage.save_art('storage-printing-0-normal.jpg',image,{'printingId':'storage-printing','oracleId':'storage-oracle','face':0,'kind':'normal'})
        self.request('/downloads/scan',{'fullSize':'normal','kinds':['normal','art_crop'],'mirrors':False})
        ready=self.wait(lambda:(lambda s:s if s['state']=='ready'else None)(self.request('/downloads/status')),'scan')
        self.assertEqual((ready['scan']['total'],ready['scan']['cached'],ready['scan']['missing']),(2,1,1));self.assertFalse(fetched)
        self.assertGreater(ready['scan']['estimatedDownloadBytes'],0);self.assertIn('estimate',ready['scan']['estimateBasis'].lower())
        self.request('/downloads/control',{'command':'start'})
        complete=self.wait(lambda:(lambda s:s if s['state']=='completed'else None)(self.request('/downloads/status')),'download')
        self.assertEqual(complete['downloaded'],1);self.assertEqual(len(fetched),1)
        self.assertFalse((self.storage.root/'image-library').exists())

    def test_purge_deletes_only_selected_cache_and_invalidates_old_plan(self):
        image=b'\xff\xd8cache-fixture\xff\xd9'
        for kind in('normal','art_crop'):self.storage.save_art('storage-printing-0-'+kind+'.jpg',image,{'printingId':'storage-printing','oracleId':'storage-oracle','face':0,'kind':kind})
        self.request('/downloads/scan',{'kinds':['normal','art_crop']})
        self.wait(lambda:self.request('/downloads/status')['state']=='ready','scan')
        self.usage();self.request('/storage/purge',{'categories':['full_cards']})
        done=self.wait(lambda:(lambda s:s if(s.get('operation')or{}).get('state')in('completed','failed')else None)(self.request('/storage/status')),'purge')
        self.assertEqual(done['operation']['state'],'completed',done)
        self.assertIsNone(self.storage.get_art('storage-printing-0-normal.jpg'));self.assertEqual(self.storage.get_art('storage-printing-0-art_crop.jpg'),image)
        self.assertFalse(self.request('/downloads/status')['scanValid'])
        with self.assertRaises(HTTPError)as exc:self.request('/downloads/control',{'command':'start'})
        self.assertEqual(exc.exception.code,409)
