"""Filtered metadata pages retain selective SQL plans and substring semantics."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog, CatalogConnection


class MetadataPageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='love2gathering-metadata-pages-')
        self.root = Path(self.temporary.name)
        source = self.root / 'cards.jsonl';cards=[]
        for index in range(48):
            name = ('Plains Guide ' if index % 2 else 'Lightning Adept ') + str(index).zfill(2)
            cards.append({'object':'card','id':f'printing-{index}','oracle_id':f'oracle-{index}',
                          'name':name,'lang':'en','set':'tst' if index%3 else 'alt',
                          'set_name':'Fixture','collector_number':str(index),'type_line':'Creature — Scout',
                          'oracle_text':'Search for a Plains card. Lightning Bolt deals 3 damage. ' + ('Literal 100%_test.' if index==1 else '') + 'Reminder text. '*100,
                          'color_identity':['W'] if index%2 else ['R'],
                          'legalities':{'modern':'legal' if index%4 else 'not_legal','commander':'legal'},
                          'image_uris':{'normal':f'https://cards.scryfall.io/normal/{index}.jpg'}})
        source.write_text('\n'.join(json.dumps(card)for card in cards)+'\n')
        self.catalog=Catalog(source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.selections=[];owner=self
        class ObservedConnection(CatalogConnection):
            def execute(self, sql, parameters=()):
                if sql.startswith('SELECT id FROM cards'):
                    plan=list(sqlite3.Connection.execute(self,'EXPLAIN QUERY PLAN '+sql,parameters))
                    owner.selections.append((sql,[row[3]for row in plan]))
                return super().execute(sql,parameters)
        def connect():
            connection=sqlite3.connect(self.catalog.database.as_uri()+'?mode=ro',uri=True,factory=ObservedConnection)
            connection.row_factory=sqlite3.Row;return connection
        self.observe=patch.object(self.catalog,'connect',connect);self.observe.start()

    def tearDown(self):
        self.observe.stop();self.temporary.cleanup()

    def expected(self, query, format_name, limit, offset):
        parameters=[];clauses=[]
        for token in query.casefold().split():
            clauses.append("search LIKE ? ESCAPE '\\'")
            parameters.append('%'+token.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')+'%')
        if format_name:clauses.append(f"{format_name} IN ('legal','restricted')")
        where=' WHERE '+' AND '.join(clauses)if clauses else''
        with self.catalog.connect()as connection:
            total=connection.execute('SELECT count(*) FROM cards'+where,parameters).fetchone()[0]
            rows=connection.execute('SELECT payload FROM cards'+where+' ORDER BY name COLLATE NOCASE LIMIT ? OFFSET ?',(*parameters,limit,offset))
            return total,[json.loads(row[0])['id']for row in rows]

    def test_all_and_modern_substring_pages_match_legacy_query_without_forced_name_walk(self):
        for query in ('Plains','Lightning','Lightning Bolt','100%_test'):
            for format_name in ('','modern'):
                with self.subTest(query=query,format=format_name):
                    total,expected=self.expected(query,format_name,5,2)
                    result=self.catalog.search(query,format_name,limit=5,offset=2)
                    self.assertEqual((result['total'],[card['id']for card in result['cards']]),(total,expected))
                    if total>2:
                        sql,plan=self.selections[-1]
                        self.assertNotIn('INDEXED BY cards_name',sql,
                                         'A filtered page must not force random alphabetical table lookups')
                        self.assertTrue(sql.startswith('SELECT id FROM cards'))
                        self.assertNotIn('payload',sql,'Only page identities belong in the sorted intermediate result')
                        if format_name:
                            self.assertTrue(any('cards_modern'in detail for detail in plan),plan)

    def test_only_broad_opening_page_gets_the_name_index_override(self):
        self.catalog.search(format_name='modern',limit=5)
        self.assertIn('INDEXED BY cards_name',self.selections[-1][0])
        for options in ({'color':'W'},{'type_name':'creature'},{'set_code':'tst'}):
            with self.subTest(options=options):
                result=self.catalog.search(format_name='modern',limit=5,**options)
                self.assertGreater(result['total'],5)
                self.assertNotIn('INDEXED BY cards_name',self.selections[-1][0])


if __name__=='__main__':unittest.main()
