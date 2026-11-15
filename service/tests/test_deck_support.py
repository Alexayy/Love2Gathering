"""Installed-class coverage and cached cover choice; owned SQLite fixtures."""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'service'))
from catalog import Catalog
from deck_covers import cover
from engine_support import EngineSupport
from precons import normalize_deck
from server import make_handler
from storage import Storage
from validation import validate


class DeckSupportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='love2gathering-deck-support-');self.root=Path(self.temp.name)
        bundled=self.root/'bundled';(bundled/'preconstructed').mkdir(parents=True)
        (bundled/'starter.json').write_text(json.dumps({'id':'starter','name':'Starter','format':'Modern','main':[{'name':'Forest','count':60}],'sideboard':[],'commander':[]}))
        products=[]
        for index,names in enumerate((['Forest'],['Forest','Unimplemented card'])):
            raw={'name':'Product '+str(index),'type':'Theme Deck','code':'TST','mainBoard':[{'name':name,'count':1}for name in names]}
            products.append(normalize_deck(raw,'product-'+str(index),{'TST':'Test expansion'},{}))
        self.products=products
        (bundled/'preconstructed/catalog.jsonl.gz').unlink(missing_ok=True)
        self.source=self.root/'products.jsonl';self.source.write_text('\n'.join(json.dumps(row)for row in products)+'\n')
        self.environ=__import__('unittest.mock',fromlist=['patch']).patch.dict('os.environ',{'LOVE2GATHERING_PRECON_SOURCE':str(self.source)})
        self.environ.start();self.store=Storage(self.root/'saves',bundled)
        common={'object':'card','lang':'en','set':'tst','set_name':'Test expansion','colors':[],'color_identity':[],'mana_cost':'','oracle_text':'','image_uris':{},'legalities':{fmt:'legal'for fmt in('modern','standard','pioneer','commander','legacy','vintage','pauper','historic','premodern')}}
        cards=[dict(common,id='forest-print',oracle_id='forest',name='Forest',type_line='Basic Land — Forest',collector_number='1'),dict(common,id='original',oracle_id='cover',name='Anikthea, Hand of Erebos',type_line='Legendary Creature',artist='Original illustrator',collector_number='2'),dict(common,id='alternate',oracle_id='cover',name='Anikthea, Hand of Erebos',type_line='Legendary Creature',artist='Other illustrator',collector_number='3')]
        source=self.root/'cards.jsonl';source.write_text('\n'.join(json.dumps(row)for row in cards))
        self.catalog=Catalog(source,self.root/'catalog.sqlite');self.catalog.ensure();self.support=EngineSupport(self.store);self.server=None

    def tearDown(self):
        if self.server:
            self.server.shutdown();self.server.server_close();self.server.RequestHandlerClass.close_managers();self.thread.join()
        self.support.close();self.store.close_images();self.environ.stop();self.temp.cleanup()

    def registry(self,**changes):
        return dict({'engineRevision':'a'*40,'registryRevision':'b'*64,'names':['Forest','Anikthea, Hand of Erebos','Front'],'splitNameFallback':True,'legalityChecked':False},**changes)

    def ready(self,predicate):
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            value=predicate()
            if value:return value
            time.sleep(.005)
        self.fail('Asynchronous implementation check did not finish: '+json.dumps(self.support.status()))

    def test_unknown_before_registry_then_background_precons_and_owned_status(self):
        self.assertEqual(self.support.for_deck(self.store.get_deck('starter'))['state'],'unknown')
        before=self.dump();self.support.register(self.registry());self.ready(lambda:self.support.status()['state']=='ready')
        okay=self.support.for_id(self.products[0]['id']);missing=self.support.for_id(self.products[1]['id'])
        self.assertEqual(okay['state'],'ready');self.assertTrue(okay['available']);self.assertFalse(okay['legalityChecked'])
        self.assertEqual(missing['state'],'unavailable');self.assertEqual(missing['missingNames'],['Unimplemented card'])
        owned={'id':'owned','main':[{'name':'Forest','count':60}],'sideboard':[],'commander':[]}
        self.support.for_deck(owned);self.ready(lambda:self.support.for_deck(owned)['state']=='ready')
        owned['main'].append({'name':'New missing card','count':1});self.assertEqual(self.support.for_deck(owned)['state'],'checking')
        self.assertEqual(self.ready(lambda:(r if(r:=self.support.for_deck(owned))['state']=='unavailable'else None))['missingNames'],['New missing card'])
        self.assertEqual(self.dump(),before,'Coverage checking changed authoritative user/product SQL data')

    def dump(self):
        with self.store.connection()as c:return list(c.iterdump())

    def test_evicted_summary_result_reloads_and_source_change_rechecks(self):
        self.support.register(self.registry());self.ready(lambda:self.support.status()['state']=='ready')
        identifier=self.products[0]['id'];before=self.support.for_id(identifier)
        with self.support.lock:
            fingerprint=self.support.identities[identifier]
            self.support.results.pop(fingerprint)
            self.support.result_bytes-=self.support.result_sizes.pop(fingerprint)
        self.assertEqual(self.support.for_id(identifier)['state'],'checking')
        self.ready(lambda:self.support.for_id(identifier)['state']=='ready')
        self.store._precon_signature=('changed-fixture-source',)
        current=self.support.status();self.assertGreater(current['generation'],before['generation'])
        self.ready(lambda:self.support.status()['state']=='ready')
        self.assertEqual(self.support.for_id(identifier)['state'],'ready')

    def test_registry_replacement_and_exact_native_split_fallback(self):
        self.support.register(self.registry());deck={'id':'dfc','main':[{'name':'Front // Back','count':1}],'sideboard':[],'commander':[]}
        self.support.for_deck(deck);self.assertTrue(self.ready(lambda:(r if(r:=self.support.for_deck(deck))['state']=='ready'else None))['available'])
        old=self.support.for_deck(deck);self.support.register(self.registry(registryRevision='c'*64,names=['Forest'],splitNameFallback=False))
        value=self.ready(lambda:(r if(r:=self.support.for_deck(deck))['state']=='unavailable'else None))
        self.assertNotEqual(value['registryRevision'],old['registryRevision']);self.assertEqual(value['missingNames'],['Front // Back'])

    def test_registry_bounds_and_same_revision_cannot_be_redefined(self):
        for fields in ({'names':[]},{'names':[None]},{'names':['x\nspoof']},{'engineRevision':'wrong'},{'registryRevision':'wrong'},{'legalityChecked':True}):
            with self.assertRaises(ValueError):self.support.register(self.registry(**fields))
        self.support.register(self.registry())
        with self.assertRaises(ValueError):self.support.register(self.registry(names=['Other']))
        with self.assertRaises(ValueError):self.support.batch(['invalid/id'])
        self.support.close();self.assertFalse(self.support.thread.is_alive())

    def save_image(self,printing,kind='normal'):
        data=(ROOT/'assets/card-backs/classic-magic.jpg').read_bytes()
        self.store.save_art(printing+'-0-'+kind+'.jpg',data,{'printingId':printing,'oracleId':'cover','face':0,'kind':kind})

    def test_normal_scan_fills_missing_art_crop_without_fetch_or_artist_substitution(self):
        self.save_image('original')
        value=cover(self.catalog,self.store,'Anikthea, Hand of Erebos')
        self.assertEqual((value['kind'],value['cached'],value['card']['printing_id']),('normal',True,'original'))
        self.assertTrue(value['card']['printingExact']);self.assertEqual(value['card']['artist'],'Original illustrator')
        self.save_image('alternate','art_crop')
        exact=cover(self.catalog,self.store,'Anikthea, Hand of Erebos','original')
        self.assertEqual((exact['kind'],exact['card']['printing_id']),('normal','original'))
        absent=cover(self.catalog,self.store,'Anikthea, Hand of Erebos','alternate')
        self.assertEqual((absent['kind'],absent['card']['printing_id']),('art_crop','alternate'))

    def test_product_exact_choice_is_resolved_even_from_summary_deck_identity(self):
        self.save_image('original');self.save_image('alternate','art_crop')
        deck={'id':'exact-deck','name':'Exact art','format':'Modern','main':[{'name':'Anikthea, Hand of Erebos','count':1}],'sideboard':[],'commander':[],'printingSelections':[{'name':'Anikthea, Hand of Erebos','zone':'main','count':1,'printingId':'original'}]}
        self.store.save_deck(deck)
        value=cover(self.catalog,self.store,'Anikthea, Hand of Erebos',deck_id='exact-deck')
        self.assertEqual((value['card']['printing_id'],value['kind']),('original','normal'))

    def test_new_format_search_and_partial_preflight_do_not_claim_native_legality(self):
        self.assertEqual(self.catalog.search(format_name='legacy')['total'],2)
        self.assertFalse(self.catalog.search(format_name='legacy')['snapshotFilterAvailable'])
        self.assertTrue(self.catalog.search(format_name='modern')['snapshotFilterAvailable'])
        self.assertEqual(self.catalog.search(format_name='pauper')['total'],2)
        self.assertFalse(self.catalog.search(format_name='therosblock')['snapshotLegalityChecked'])
        self.assertEqual(self.catalog.sets('therosblock')[0]['code'],'tst')
        source={'name':'Freeform','format':'Freeform','main':[{'name':'Anikthea, Hand of Erebos','count':40}],'sideboard':[],'commander':[]}
        deck=self.store.validate_deck(source);result=validate(deck,self.catalog)
        self.assertTrue(result['saveAllowed']);self.assertFalse(result['snapshotLegalityChecked']);self.assertFalse(result['valid']);self.assertTrue(result['nativeValidationRequired'])
        self.assertEqual(deck['format'],'Freeform')
        with self.assertRaises(ValueError):self.store.validate_deck(dict(source,format='Oathbreaker'))
        with self.assertRaises(ValueError):self.store.validate_deck(dict(source,format='Limited'))

    def test_http_registration_is_direct_local_json_and_browsing_is_decorated(self):
        self.server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(self.catalog,self.store));self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();url='http://127.0.0.1:'+str(self.server.server_port)
        def request(path,body=None,headers=None):
            value=Request(url+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json',**(headers or{})})
            try:
                with urlopen(value,timeout=3)as response:return response.status,json.load(response)
            except HTTPError as error:return error.code,json.load(error)
        self.assertEqual(request('/engine-support/registry',self.registry(),{'Origin':'https://other.invalid'})[0],403)
        self.assertEqual(request('/engine-support/registry',self.registry())[0],202)
        self.ready(lambda:request('/engine-support/status')[1]['state']=='ready')
        self.assertIn('engineSupport',request('/precons')[1]['decks'][0]);self.assertIn('engineSupport',request('/decks')[1]['decks'][0])
        self.assertEqual(request('/engine-support/decks',{'ids':[self.products[1]['id']]})[1]['decks'][self.products[1]['id']]['missingNames'],['Unimplemented card'])
        self.assertEqual(request('/health')[1]['apiVersion'],15)


if __name__=='__main__':unittest.main()
