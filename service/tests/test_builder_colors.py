"""Identity filtering uses isolated metadata; it never decides runtime legality."""
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from server import make_handler
from storage import Storage


class BuilderColorTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.source=self.root/'cards.jsonl'
        specs={'White':'W','Black':'B','Green':'G','Red':'R','Orzhov':'WB','Abzan':'BGW','Sultai':'UBG','Four Color':'WUBG','Five Color':'WUBRG','Colorless':'','Plains':'W','Hybrid':'WB'}
        records=[]
        for index,(name,identity)in enumerate(specs.items()):
            records.append({'object':'card','id':'printing-'+str(index),'oracle_id':'oracle-'+str(index),'name':name,'lang':'en','type_line':'Basic Land — Plains'if name=='Plains'else'Creature','mana_cost':'{W/B}'if name=='Hybrid'else'','colors':[]if name in('Plains','Colorless')else list(identity),'color_identity':list(identity),'set':'tst','set_name':'Test','legalities':{'modern':'legal','commander':'legal'},'image_uris':{}})
        self.source.write_text('\n'.join(json.dumps(item)for item in records))
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure()
        assert self.catalog.status()['state']=='ready'
        self.storage=Storage(self.root/'saves',self.root/'bundled')
        self.handler=make_handler(self.catalog,self.storage)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),self.handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.base='http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.handler.close_managers();self.thread.join();self.tmp.cleanup()

    def names(self,colors,mode):
        return{card['name']for card in self.catalog.search(color=colors,color_mode=mode)['cards']}

    def test_any_selected_colors_are_a_union_of_color_identities(self):
        self.assertEqual(self.names('W','any'),{'White','Orzhov','Abzan','Four Color','Five Color','Plains','Hybrid'})
        self.assertEqual(self.names('WB','any'),self.names('W','any')|self.names('B','any'))
        self.assertEqual(self.names('WBG','any'),self.names('W','any')|self.names('B','any')|self.names('G','any'))
        self.assertNotIn('Red',self.names('WBG','any'));self.assertNotIn('Colorless',self.names('WBG','any'))

    def test_exact_identity_excludes_subsets_supersets_and_other_shards(self):
        self.assertEqual(self.names('WBG','exact'),{'Abzan'})
        self.assertEqual(self.names('GBWW','exact'),{'Abzan'},'Identity is a set, independent of snapshot/query order')
        self.assertEqual(self.names('WB','exact'),{'Orzhov','Hybrid'})
        self.assertEqual(self.names('W','exact'),{'White','Plains'},'Basic land mana identity must be retained')
        self.assertEqual(self.names('C','exact'),{'Colorless'})
        self.assertEqual(self.names('C','any'),{'Colorless'})

    def test_legacy_classic_search_and_bounded_sorting_remain_available(self):
        self.assertEqual(self.names('WB','legacy'),{'Orzhov','Abzan','Four Color','Five Color','Hybrid'})
        result=self.catalog.search(format_name='modern',color='WBG',color_mode='any',limit=2,offset=1,sort='color',set_code='tst')
        self.assertEqual(result['total'],10);self.assertEqual(len(result['cards']),2)
        for colors,mode in(('WBC','any'),('WU','invalid'),('purple','exact')):
            with self.subTest(colors=colors,mode=mode),self.assertRaises(ValueError):self.names(colors,mode)

    def test_actual_http_passes_mode_and_rejects_invalid_requests(self):
        with urlopen(self.base+'/cards?color=WBG&colorMode=exact')as response:data=json.load(response)
        self.assertEqual([card['name']for card in data['cards']],['Abzan'])
        with urlopen(self.base+'/cards?color=WB&colorMode=any')as response:data=json.load(response)
        self.assertEqual({card['name']for card in data['cards']},self.names('WB','any'))
        with self.assertRaises(HTTPError)as exc:urlopen(self.base+'/cards?color=WB&colorMode=invalid')
        self.assertEqual(exc.exception.code,400)
