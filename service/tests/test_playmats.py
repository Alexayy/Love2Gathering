import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from playmats import lookup_playmat

class PlaymatTest(unittest.TestCase):
    def test_exact_cached_full_art_and_seed_reuse_without_network(self):
        with tempfile.TemporaryDirectory()as folder:
            root=Path(folder);source=root/'cards.jsonl'
            records=[{'object':'card','id':ident,'oracle_id':'forest-oracle','name':'Forest','lang':'en','type_line':'Basic Land — Forest','full_art':True,'set':'tst','legalities':{'modern':'legal'},'image_uris':{'art_crop':'https://cards.scryfall.io/art_crop/'+ident+'.jpg'}}for ident in('forest-a','forest-b')]
            source.write_text('\n'.join(json.dumps(r)for r in records))
            catalog=Catalog(source,root/'catalog.sqlite');catalog.ensure();storage=Storage(root/'saves',root/'decks')
            storage.save_art('forest-b-0-art_crop.jpg',b'\xff\xd8full-art\xff\xd9',{'kind':'art_crop','printingId':'forest-b','oracleId':'forest-oracle'})
            entries=[{'name':'Forest','oracleId':'forest-oracle','printingId':row['id'],'face':0,'fullArt':True}for row in records]
            with patch('playmats._lands',return_value={'Forest':entries}):
                first=lookup_playmat(catalog,storage,'Forest','bot-1');second=lookup_playmat(catalog,storage,'Forest','bot-1')
                self.assertTrue(first['cached']);self.assertTrue(first['fullArt']);self.assertEqual(first,second)
                self.assertEqual(first['reference']['printingId'],'forest-b');self.assertEqual(first['card']['printing_id'],'forest-b')
                with self.assertRaises(ValueError):lookup_playmat(catalog,storage,'Lightning Bolt')
    def test_packaged_pool_contains_only_exact_full_art_basics(self):
        data=json.loads((Path(__file__).resolve().parents[2]/'assets/card-art/full-art-basics.json').read_text())
        self.assertEqual(set(data['lands']),{'Plains','Island','Swamp','Mountain','Forest','Wastes'})
        for name,entries in data['lands'].items():
            self.assertGreater(len(entries),0);self.assertLessEqual(len(entries),96)
            self.assertTrue(all(e['name']==name and e['fullArt']is True and e['printingId']and e['oracleId']for e in entries))
