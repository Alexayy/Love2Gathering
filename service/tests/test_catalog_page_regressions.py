"""Retained 100k metadata, exact-edition cache and connection regressions."""
from contextlib import contextmanager
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from deck_printings import printings


class CatalogPageRegressionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='love2gathering-catalog-page-regressions-')
        cls.root=Path(cls.temporary.name);cls.source=cls.root/'seed.jsonl';cls.database=cls.root/'catalog.sqlite'
        cls.source.write_text(json.dumps({'object':'card','id':'seed-printing','oracle_id':'seed','name':'Seed','lang':'en'})+'\n')
        catalog=Catalog(cls.source,cls.database);catalog.ensure()
        if catalog.status()['state']!='ready':raise AssertionError(catalog.status())
        # These population pragmas apply only to a disposable test index.
        # Production storage durability and read-only metadata are unchanged.
        c=sqlite3.connect(cls.database);c.execute('PRAGMA journal_mode=OFF');c.execute('PRAGMA synchronous=OFF')
        c.execute('DELETE FROM cards');c.execute('DELETE FROM card_sets')
        rules='Generated fixture oracle text. '*16
        def cards():
            for index in range(100000):
                name='Swamp'if index==99999 else f'Card {index:06}'
                color='B'if index%2 else'G'
                card={'id':f'oracle-{index:06}','printing_id':f'printing-{index:06}','name':name,'oracle_text':rules,'type_line':'Basic Land — Swamp'if name=='Swamp'else'Creature','set':'tst','set_name':'Test','collector_number':str(index),'released_at':'2024-01-01','artist':'Fixture artist','card_faces':[],'colors':[color],'color_identity':[color],'image_uris':{},'legalities':{'commander':'legal','modern':'legal'if index%2==0 else'not_legal','standard':'legal'if index%10000==0 else'not_legal'}}
                yield(card['id'],name,(name+' '+rules).casefold(),card['type_line'].casefold(),color,card['legalities']['modern'],card['legalities']['standard'],'not_legal','legal',12,json.dumps(card,separators=(',',':')))
        c.executemany('INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?)',cards())
        swamp=json.loads(c.execute("SELECT payload FROM cards WHERE name='Swamp'").fetchone()[0])
        def editions():
            for index in range(1000):
                card=dict(swamp,printing_id=f'swamp-{index:04}',set=f't{index%20:02}',set_name='Edition '+str(index%20),collector_number=str(index),released_at=f'{2000+index%25}-01-01',artist='Artist '+('Copper','Silver','Gold','Iron','Metal')[index%5],frame_effects=['extendedart']if index%7==0 else[],border_color='borderless'if index%11==0 else'black')
                yield(card['id'],card['set'],card['set_name'],card['printing_id'],card['collector_number'],'{}','[]',json.dumps(card,separators=(',',':')))
        c.executemany('INSERT INTO card_sets VALUES (?,?,?,?,?,?,?,?)',editions());c.commit();c.close()

    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()

    def setUp(self):self.catalog=Catalog(self.source,self.database)

    def test_default_builder_page_uses_name_index_and_reads_only_selected_payloads(self):
        original=self.catalog.connect;steps={'baseline':0,'identities':0};statements=[]
        with original()as c:
            c.set_progress_handler(lambda:steps.__setitem__('baseline',steps['baseline']+100)or 0,100)
            began=time.monotonic()
            expected=[json.loads(row[0])['id']for row in c.execute("SELECT payload FROM cards WHERE commander IN ('legal','restricted') ORDER BY name COLLATE NOCASE LIMIT 24")]
            baseline_seconds=time.monotonic()-began
        @contextmanager
        def observed():
            with original()as c:
                current={'sql':''}
                def progress():
                    if current['sql'].startswith('SELECT id FROM cards INDEXED BY cards_name'):steps['identities']+=100
                    return 0
                c.set_progress_handler(progress,100)
                class Proxy:
                    def execute(_self,sql,*args):current['sql']=sql;statements.append(sql);return c.execute(sql,*args)
                yield Proxy()
        began=time.monotonic()
        with patch.object(self.catalog,'connect',observed):page=self.catalog.search(format_name='commander',limit=24)
        optimized_seconds=time.monotonic()-began
        self.assertEqual(page['total'],100000);self.assertEqual([item['id']for item in page['cards']],expected)
        self.assertLess(steps['identities'],3000,'The unfiltered opening page stops after its requested identities')
        self.assertGreater(steps['baseline'],100000,'The former payload sort exercises the whole fixture')
        self.assertFalse(any('payload'in sql and'ORDER BY'in sql for sql in statements),'Unselected JSON must not travel through the page sorter')
        with original()as c:
            plan=' '.join(str(tuple(row))for row in c.execute("EXPLAIN QUERY PLAN SELECT id FROM cards INDEXED BY cards_name WHERE commander IN ('legal','restricted') ORDER BY name COLLATE NOCASE LIMIT 24"))
        self.assertIn('cards_name',plan);self.assertNotIn('TEMP B-TREE',plan)
        print(f'\n100k metadata builder: old={baseline_seconds:.4f}s new={optimized_seconds:.4f}s; page VM steps={steps["identities"]}, old VM steps={steps["baseline"]}')

    def test_filters_offsets_and_other_orderings_keep_the_same_page(self):
        orders=(('name','name COLLATE NOCASE'),('color',"CASE WHEN colors='' THEN 0 WHEN length(colors)>1 THEN 6 ELSE instr('WUBRG',colors) END, colors, name COLLATE NOCASE"),('set',"json_extract(payload,'$.set') COLLATE NOCASE, name COLLATE NOCASE"))
        for sort,order in orders:
            with self.subTest(sort=sort):
                with self.catalog.connect()as c:expected=[row[0]for row in c.execute("SELECT id FROM cards WHERE modern IN ('legal','restricted') ORDER BY "+order+' LIMIT 3 OFFSET 17')]
                page=self.catalog.search(format_name='modern',limit=3,offset=17,sort=sort)
                self.assertEqual(page['total'],50000);self.assertEqual([item['id']for item in page['cards']],expected)
        page=self.catalog.search(query='Card 00000',format_name='commander',limit=60)
        self.assertEqual(page['total'],10);self.assertEqual(len(page['cards']),10)
        self.assertEqual(self.catalog.search(query='No such card')['cards'],[])

    def test_sparse_format_and_empty_pages_keep_selective_work(self):
        original=self.catalog.connect;statements=[]
        @contextmanager
        def observed():
            with original()as c:
                c.set_trace_callback(statements.append);yield c
        with patch.object(self.catalog,'connect',observed):
            page=self.catalog.search(format_name='standard',limit=24)
            self.assertEqual(page['total'],10);self.assertEqual(len(page['cards']),10)
            self.assertFalse(any('INDEXED BY cards_name'in sql for sql in statements),'A tiny legal result keeps its selective format index')
            statements.clear();empty=self.catalog.search(format_name='standard',limit=24,offset=10)
            self.assertEqual(empty['cards'],[])
            self.assertFalse(any(sql.startswith('SELECT id')for sql in statements),'A known empty page needs no identity or payload scan')

    def test_swamp_editions_are_bounded_cached_detached_and_exact(self):
        with patch.object(self.catalog,'connect',wraps=self.catalog.connect)as connect:
            began=time.monotonic();first=printings(self.catalog,'Swamp',limit=12);cold=time.monotonic()-began
            self.assertEqual((first['total'],len(first['items']),len(first['sets'])),(1000,12,20))
            selected=first['items'][0]['printing_id'];first['items'][0]['name']='Consumer mutation';first['sets'].clear()
            began=time.monotonic();again=printings(self.catalog,'Swamp',limit=12);warm=time.monotonic()-began
            self.assertEqual(connect.call_count,2,'Only the original card identity and printing page need SQL')
        self.assertEqual(again['items'][0]['printing_id'],selected);self.assertEqual(again['items'][0]['name'],'Swamp');self.assertEqual(len(again['sets']),20)
        self.assertTrue(all(item['id']=='oracle-099999'and item['printingExact']and item['printingResolved']for item in again['items']))
        next_page=printings(self.catalog,'Swamp',limit=12,offset=12)
        self.assertTrue({item['printing_id']for item in again['items']}.isdisjoint(item['printing_id']for item in next_page['items']))
        filtered=printings(self.catalog,'Swamp',query='gold',variant='extended',limit=60)
        self.assertTrue(filtered['items']);self.assertTrue(all(item['artist']=='Artist Gold'and'extendedart'in item['frame_effects']for item in filtered['items']))
        print(f'\n1000 Swamp editions in 100k metadata index: cold={cold:.4f}s cached={warm:.6f}s')

    def test_metadata_connections_close_at_success_and_exception_boundaries(self):
        with self.catalog.connect()as success:self.assertEqual(success.execute('SELECT 1').fetchone()[0],1)
        with self.assertRaises(sqlite3.ProgrammingError):success.execute('SELECT 1')
        with self.assertRaisesRegex(ValueError,'fixture'):
            with self.catalog.connect()as failure:raise ValueError('fixture')
        with self.assertRaises(sqlite3.ProgrammingError):failure.execute('SELECT 1')

    def test_printing_cache_is_invalidated_by_an_atomic_metadata_replacement(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-printing-generation-')as name:
            root=Path(name);source=root/'source.jsonl'
            raw={'object':'card','id':'exact','oracle_id':'oracle','name':'Exact card','lang':'en','set':'one','set_name':'First edition','artist':'First artist'}
            source.write_text(json.dumps(raw)+'\n');catalog=Catalog(source,root/'catalog.sqlite');catalog.ensure()
            self.assertEqual(printings(catalog,'Exact card')['items'][0]['artist'],'First artist')
            raw['artist']='Updated artist';source.write_text(json.dumps(raw)+'\n');catalog.build()
            self.assertEqual(printings(catalog,'Exact card')['items'][0]['artist'],'Updated artist')


if __name__=='__main__':unittest.main()
