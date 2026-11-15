"""Real SQLite metadata cache, detached responses and atomic-index invalidation."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from query_cache import QueryCache

class CatalogCacheTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.source=self.root/'cards.jsonl'
        self.source.write_text(json.dumps({'object':'card','id':'printing-one','oracle_id':'oracle-one','name':'Cached Card','lang':'en','type_line':'Creature','oracle_text':'Flying','color_identity':['W'],'colors':['W'],'set':'one','collector_number':'1','image_uris':{'normal':'https://cards.scryfall.io/fixture.jpg','art_crop':'https://cards.scryfall.io/fixture-art.jpg'},'legalities':{'modern':'legal'},'artist':'Fixture artist','released_at':'2020-01-01'})+'\n')
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.assertTrue(self.catalog.current())
    def tearDown(self):self.tmp.cleanup()
    def test_repeated_reads_do_not_repeat_sql_and_response_mutations_are_detached(self):
        with patch.object(self.catalog,'connect',wraps=self.catalog.connect)as connect:
            first=self.catalog.search('Cached');first['cards'][0]['name']='Changed by consumer';first['cards'].clear()
            for _ in range(20):self.assertEqual(self.catalog.search('Cached')['cards'][0]['name'],'Cached Card')
            self.assertEqual(connect.call_count,1)
        with patch.object(self.catalog,'connect',wraps=self.catalog.connect)as connect:
            a=self.catalog.get(name='Cached Card');a['power']='999'
            self.assertNotEqual(self.catalog.get(name='Cached Card').get('power'),'999')
            self.assertEqual(connect.call_count,1)
    def test_gallery_art_flags_are_not_saved_in_metadata_cache(self):
        page=self.catalog.gallery();page['items'][0]['art_cached']=True
        self.assertNotIn('art_cached',self.catalog.gallery()['items'][0])
    def test_atomically_replaced_index_invalidates_warm_results(self):
        self.assertEqual(self.catalog.search()['cards'][0]['name'],'Cached Card')
        raw=json.loads(self.source.read_text());raw['name']='New snapshot';self.source.write_text(json.dumps(raw)+'\n')
        self.catalog.build()
        self.assertEqual(self.catalog.search()['cards'][0]['name'],'New snapshot')
        self.assertIsNone(self.catalog.get(name='Cached Card'))
    def test_cache_stays_inside_entry_and_byte_bounds(self):
        cache=QueryCache(self.catalog.database,entries=3,max_bytes=150);generation=cache.identity()
        cache.get(b'first',generation)
        for i in range(30):cache.put(str(i).encode(),{'value':'x'*20},generation)
        self.assertLessEqual(len(cache.values),3);self.assertLessEqual(cache.bytes,150)
        cache.put(b'too-large',{'value':'x'*500},generation)
        self.assertFalse(cache.get(b'too-large',generation)[0])
    def test_deck_composition_color_changes_invalidate_its_key(self):
        deck={'main':[{'name':'Cached Card','count':1}],'sideboard':[],'commander':[]}
        self.assertEqual(self.catalog.deck_colors(deck),['W'])
        deck['main']=[];self.assertEqual(self.catalog.deck_colors(deck),[])

if __name__=='__main__':unittest.main()
