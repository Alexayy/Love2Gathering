"""Real isolated HTTP/SQL: editions preserve identities, quantities and cache isolation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from server import make_handler


class CardPrintingsTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        forest={'object':'card','id':'forest-a','oracle_id':'forest','name':'Forest','lang':'en','set':'thb','set_name':'Theros Beyond Death','collector_number':'254','artist':'Artist Alpha','released_at':'2020-01-24','type_line':'Basic Land — Forest','colors':[],'color_identity':['G'],'legalities':{'modern':'legal','commander':'legal'},'image_uris':{'normal':'https://cards.scryfall.io/normal/forest-a.jpg','art_crop':'https://cards.scryfall.io/art_crop/forest-a.jpg'}}
        forest_b=dict(forest,id='forest-b',set='mom',set_name='March of the Machine',artist='Artist Beta',collector_number='281',released_at='2023-04-21',frame_effects=['extendedart'],image_uris={'normal':'https://cards.scryfall.io/normal/forest-b.jpg','art_crop':'https://cards.scryfall.io/art_crop/forest-b.jpg'})
        commander=dict(forest,id='rin-a',oracle_id='rin',name='Rin and Seri, Inseparable',type_line='Legendary Creature — Dog Cat',colors=['R','G','W'],color_identity=['R','G','W'],power='4',toughness='4',set='m21',set_name='Core Set 2021')
        alt=dict(commander,id='rin-b',set='sld',set_name='Secret Lair Drop',collector_number='2000',frame_effects=['showcase'],border_color='borderless')
        other=dict(forest,id='plains',oracle_id='plains',name='Plains',type_line='Basic Land — Plains',color_identity=['W'])
        self.source=self.root/'cards.jsonl';self.source.write_text('\n'.join(json.dumps(c)for c in (forest,forest_b,commander,alt,other)))
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure();self.assertEqual(self.catalog.status()['state'],'ready')
        self.storage=Storage(self.root/'data',self.root/'bundled',cache_dir=self.root/'cache')
        self.handler=make_handler(self.catalog,self.storage);self.server=ThreadingHTTPServer(('127.0.0.1',0),self.handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.url='http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.handler.close_managers();self.temp.cleanup()

    def request(self,path,body=None,binary=False):
        request=Request(self.url+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with urlopen(request,timeout=5)as response:return response.read()if binary else json.load(response)

    @staticmethod
    def deck():return {'id':'forest-deck','name':'Forest test','format':'Modern','main':[{'name':'Forest','count':60}],'printingSelections':[{'name':'Forest','zone':'main','count':60,'printingId':'forest-b'}]}

    def test_bounded_same_oracle_pages_filters_and_treatments(self):
        first=self.request('/printings?name=Forest&limit=1')
        self.assertEqual((first['total'],len(first['items'])),(2,1));self.assertEqual(first['items'][0]['printing_id'],'forest-b')
        self.assertTrue(first['items'][0]['printingExact']);self.assertEqual({x['code']for x in first['sets']},{'thb','mom'})
        self.assertEqual(self.request('/printings?name=Forest&offset=1&limit=1')['items'][0]['printing_id'],'forest-a')
        self.assertEqual(self.request('/printings?name=Forest&set=thb')['total'],1)
        self.assertEqual(self.request('/printings?name=Forest&q=beta')['items'][0]['printing_id'],'forest-b')
        self.assertEqual(self.request('/printings?name=Forest&variant=extended')['total'],1)
        self.assertEqual(self.request('/printings?name=Forest&variant=showcase')['total'],0)

    def test_unknown_cards_and_invalid_filters_are_not_unbounded_searches(self):
        for path in ('/printings?name=Unknown','/printings?name=Forest&limit=500','/printings?name=Forest&offset=-1','/printings?name=Forest&variant=guess'):
            with self.assertRaises(HTTPError):self.request(path)

    def test_exact_choice_survives_sql_restart_copy_and_preserves_counts(self):
        saved=self.request('/decks',self.deck())
        self.assertEqual(saved['main'],[{'name':'Forest','count':60}]);choice=saved['printingSelections'][0]
        self.assertEqual((choice['printingId'],choice['set'],choice['collectorNumber']),('forest-b','mom','281'))
        again=Storage(self.root/'data',self.root/'bundled',cache_dir=self.root/'cache')
        self.assertEqual(again.get_deck(saved['id'])['printingSelections'],saved['printingSelections'])
        copied=again.copy_deck(saved['id']);self.assertEqual(copied['printingSelections'],saved['printingSelections'])
        self.assertNotEqual(copied['id'],saved['id'])

    def test_commander_alternate_art_keeps_commander_identity_and_eligibility(self):
        deck=self.deck();deck.update(format='Commander',main=[{'name':'Forest','count':99}],commander=[{'name':'Rin and Seri, Inseparable','count':1}],printingSelections=[{'name':'Rin and Seri, Inseparable','zone':'commander','count':1,'printingId':'rin-b'}])
        saved=self.request('/decks',deck)
        self.assertEqual(saved['commander'],deck['commander']);self.assertEqual(saved['printingSelections'][0]['printingId'],'rin-b')
        self.assertTrue(saved['validation']['playable'])

    def test_wrong_card_zone_and_excess_printed_quantities_are_named_errors(self):
        for change,code in (({'printingId':'plains'},'printing_identity'),({'zone':'sideboard'},'printing_card'),({'count':61},'printing_count')):
            deck=self.deck();deck['printingSelections'][0].update(change)
            with self.assertRaises(HTTPError)as error:self.request('/decks',deck)
            self.assertEqual(error.exception.code,422)
            result=json.load(error.exception);self.assertIn(code,{e['code']for e in result['validation']['errors']})
            self.assertIn('Forest',result['error'])
        self.assertIsNone(self.storage.get_deck('forest-deck'))

    def test_missing_exact_image_never_uses_another_cached_printing(self):
        self.storage.save_art('forest-a-0-normal.jpg',b'\xff\xd8different',{'oracleId':'forest','printingId':'forest-a','face':0,'kind':'normal'})
        with patch.object(self.handler,'download_art',side_effect=AssertionError('No implicit download')):
            with self.assertRaises(HTTPError)as error:self.request('/art/forest?printing=forest-b&exact=1',binary=True)
            self.assertEqual(error.exception.code,404)
            self.assertEqual(self.request('/art/forest?printing=forest-b',binary=True),b'\xff\xd8different')

    @unittest.skipUnless(shutil.which('love'),'Headless LÖVE is required for the real asynchronous builder queue')
    def test_frontend_queued_mutations_sync_printing_counts_before_http_validation(self):
        root=Path(__file__).resolve().parents[2];runtime=self.root/'headless-love';runtime.mkdir()
        (runtime/'conf.lua').write_text("function love.conf(t)t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.joystick=false;t.modules.physics=false;t.console=true end\n")
        (runtime/'app').symlink_to(root/'app',target_is_directory=True)
        (runtime/'lib').symlink_to(root/'lib',target_is_directory=True)
        shutil.copyfile(root/'tests/card_printings_queue.lua',runtime/'main.lua')
        result=subprocess.run([shutil.which('love'),str(runtime)],env={**os.environ,'LOVE2GATHERING_QUEUE_TEST_ROOT':str(root),'LOVE2GATHERING_CATALOG_PORT':str(self.server.server_port),'LOVE2GATHERING_ENGINE_PORT':'17562','LOVE2GATHERING_ROOM_PORT':'17563','SDL_VIDEODRIVER':'dummy'},capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
        self.assertIn('PRINTING QUEUE COMPLETE',result.stdout)
        self.assertIsNone(self.storage.get_deck('queue-fixture'))


if __name__=='__main__':unittest.main()
