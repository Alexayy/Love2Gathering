"""Actual local location APIs and exact offline JPEG after split/restart."""
import json
from pathlib import Path
import sqlite3
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
from storage_locations import StorageLocations,activate_pending


class LocationHttpTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.env={'LOVE2GATHERING_CONFIG_DIR':str(self.root/'config')}
        self.source=self.root/'cards.jsonl';self.source.write_text(json.dumps({'object':'card','id':'printing','oracle_id':'oracle','name':'Storage Test','lang':'en','set':'tst','type_line':'Creature','image_uris':{'normal':'https://cards.scryfall.io/normal.jpg','art_crop':'https://cards.scryfall.io/art.jpg'}})+'\n')
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.storage=Storage(self.root/'old',self.root/'bundled');self.jpeg=b'\xff\xd8test-actual-offline-image\xff\xd9'
        self.storage.save_art('printing-0-normal.jpg',self.jpeg,{'oracleId':'oracle','printingId':'printing','face':0,'kind':'normal'})
        self.body={'databaseDirectory':str(self.root/'new'),'cacheDirectory':str(self.root/'cache')};self.start(self.storage)
    def start(self,storage):
        self.locations=StorageLocations(storage,environ=self.env)
        self.handler=make_handler(self.catalog,storage,location_manager=self.locations)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),self.handler);self.server.daemon_threads=True
        self.worker=threading.Thread(target=self.server.serve_forever,daemon=True);self.worker.start();self.base='http://127.0.0.1:'+str(self.server.server_port)
    def stop(self):
        self.server.shutdown();self.server.server_close();self.handler.close_managers();self.worker.join()
    def tearDown(self):self.stop();self.tmp.cleanup()
    def call(self,path,body=None,origin=None):
        headers={'Content-Type':'application/json'}
        if origin:headers['Origin']=origin
        request=Request(self.base+path,data=None if body is None else json.dumps(body).encode(),headers=headers)
        with urlopen(request,timeout=3)as response:
            return json.load(response)if response.headers.get_content_type()=='application/json'else response.read()
    def ready(self):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            value=self.call('/storage/locations')
            if(value.get('operation')or{}).get('state')in('prepared','error'):break
            time.sleep(.02)
        self.assertEqual(value['operation']['state'],'prepared',value)
        return value
    def test_validate_is_non_destructive_and_browser_cannot_prepare(self):
        self.assertFalse(self.call('/storage/locations')['active']['separateCache'])
        result=self.call('/storage/locations/validate',self.body);self.assertTrue(result['valid']);self.assertTrue(result['originalsPreserved'])
        self.assertFalse((self.root/'new').exists());self.assertFalse((self.root/'cache').exists())
        with self.assertRaises(HTTPError)as exc:self.call('/storage/locations',self.body,'https://untrusted.example')
        self.assertEqual(exc.exception.code,403);self.assertIsNone(self.call('/storage/locations')['operation'])
    def test_prepare_restart_keeps_exact_images_offline_and_isolated(self):
        self.call('/storage/locations',self.body);self.assertTrue(self.ready()['restartRequired'])
        health=self.call('/health');self.assertEqual(health['apiVersion'],11);self.assertTrue(health['storage']['maintenanceBusy'])
        self.stop();activate_pending(self.env)
        self.storage=Storage(self.root/'new',self.root/'bundled',self.root/'cache');self.start(self.storage)
        health=self.call('/health');self.assertTrue(health['storage']['separateCache'])
        self.assertEqual(health['storage']['cacheDirectory'],str(self.root/'cache'))
        self.assertEqual(self.call('/art/oracle?printing=printing&exact=1&network=0'),self.jpeg)
        self.call('/downloads/scan',{'kinds':['normal']})
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            state=self.call('/downloads/status')
            if state['state']=='ready':break
            time.sleep(.02)
        self.assertEqual(state['scan']['cached'],1);self.assertEqual(state['scan']['missing'],0)
        self.assertEqual(state['cacheDirectory'],str(self.root/'cache'))
        with sqlite3.connect(self.root/'old/app.sqlite')as original:self.assertEqual(original.execute('SELECT content FROM art_cache').fetchone()[0],self.jpeg)

if __name__=='__main__':unittest.main()
