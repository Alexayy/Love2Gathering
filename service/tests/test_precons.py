"""Immutable product browsing, user-owned copies and bounded acquisition fixtures."""
import gzip
import hashlib
from http.server import ThreadingHTTPServer
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request,urlopen

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'service'))
from catalog import Catalog
from precons import normalize_deck
from server import make_handler
from storage import Storage
from replays import encode,now

def raw_deck(name='Commander product',kind='Commander Deck',cards=None):
    main=cards or [{'name':'Forest','count':99,'colorIdentity':['G'],'setCode':'TST','number':'1'}]
    commander=[{'name':'Commander','count':1,'colorIdentity':['G'],'setCode':'TST','number':'2'}] if kind in ('Commander Deck','Secret Lair Commander') else []
    return {'name':name,'type':'Secret Lair Drop'if kind=='Secret Lair Commander'else kind,'code':'TST','releaseDate':'2001-01-01','source':'https://magic.wizards.com/en/news/test-source','mainBoard':main,'sideBoard':[],'commander':commander,'displayCommander':commander}


class PreconsTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.bundled=self.root/'bundled';self.bundled.mkdir()
        self.starter={'id':'included','name':'Curated starter','format':'Modern','coverCard':'Forest','main':[{'name':'Forest','count':60}],'sideboard':[],'commander':[]}
        self.original=json.dumps(self.starter);(self.bundled/'included.json').write_text(self.original)
        raws=[raw_deck(),raw_deck('Historical theme','Theme Deck',[{'name':'Forest','count':60,'colorIdentity':['G']}]),raw_deck('Ordinary drop','Secret Lair Drop',[{'name':'Forest','count':4}]),raw_deck('Secret Lair Commander','Secret Lair Commander'),raw_deck('Jumpstart packet','Jumpstart',[{'name':'Forest','count':20}]),raw_deck('Illegal archival list','Theme Deck',[{'name':'Unknown old card','count':1},{'name':'Forest','count':59}])]
        self.decks=[normalize_deck(raw,'fixture-'+str(i),{'TST':'Test expansion'},{'date':'2026-11-14','version':'fixture'}) for i,raw in enumerate(raws)]
        destination=self.bundled/'preconstructed/catalog.jsonl.gz';destination.parent.mkdir();self.precon_source=destination
        with gzip.open(destination,'wt')as out:
            out.write(json.dumps({'_meta':{'schema':1,'snapshotDate':'2026-11-14','totalSourceRecords':len(self.decks)}})+'\n')
            for deck in self.decks:out.write(json.dumps(deck)+'\n')
        base={'object':'card','lang':'en','set':'tst','set_name':'Test expansion','colors':[],'color_identity':['G'],'mana_cost':'','oracle_text':'','legalities':{fmt:'legal'for fmt in('modern','standard','pioneer','commander')},'image_uris':{}}
        forest=dict(base,id='forest-print',oracle_id='forest',name='Forest',type_line='Basic Land — Forest',collector_number='1')
        commander=dict(base,id='commander-print',oracle_id='commander',name='Commander',type_line='Legendary Creature — Elf',collector_number='2',power='2',toughness='2')
        source=self.root/'cards.jsonl';source.write_text(json.dumps(forest)+'\n'+json.dumps(commander))
        self.catalog=Catalog(source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.store=Storage(self.root/'saves',self.bundled)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(self.catalog,self.store));self.worker=threading.Thread(target=self.server.serve_forever,daemon=True);self.worker.start()
        self.url='http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.worker.join();self.temp.cleanup()

    def request(self,path,body=None,method=None):
        req=Request(self.url+path,data=None if body is None else json.dumps(body).encode(),method=method,headers={'Content-Type':'application/json'})
        try:
            with urlopen(req)as response:return response.status,json.load(response)
        except HTTPError as exc:return exc.code,json.load(exc)

    def test_my_starter_and_precon_collections_are_distinct_and_bounded(self):
        self.assertEqual(self.request('/decks?origin=user')[1]['decks'],[])
        starters=self.request('/decks?origin=starter')[1]['decks'];self.assertEqual(starters[0]['id'],'starter-included');self.assertTrue(starters[0]['readOnly'])
        self.assertEqual(self.request('/decks')[1]['decks'][0]['id'],'included','Legacy lobby route was renamed')
        page=self.request('/precons?limit=1')[1];self.assertEqual((page['total'],len(page['decks'])),(4,1));self.assertNotIn('main',page['decks'][0])
        self.assertEqual(self.request('/precons?category=packet')[1]['total'],1);self.assertEqual(self.request('/precons?category=collection')[1]['total'],1)
        self.assertEqual(self.request('/precons?q=%25')[1]['total'],0)
        stats=self.request('/precons/stats')[1];self.assertEqual((stats['totalSourceRecords'],stats['deckCount'],stats['packetCount'],stats['withheldCollectionCount']),(6,4,1,1))
        self.assertIn('Jumpstart',[row['id']for row in stats['formats']]);self.assertEqual(stats['sets'][0]['count'],5)
        self.assertEqual(self.request('/precons?set=tst&type=Commander%20Deck')[1]['total'],1)
        self.assertEqual(self.request('/precons?limit=1&offset=1')[1]['offset'],1)
        with self.assertRaises(ValueError):self.store.precons(limit=61)
        self.assertEqual(self.request('/decks/included/fork',[])[0],400)

    def test_historical_format_filter_never_claims_current_standard_legality(self):
        historical=normalize_deck(raw_deck('Release-era Standard','Challenger Deck',[{'name':'Forest','count':60}]),'historical-standard',{'TST':'Test expansion'},{'date':'2026-11-14'})
        with gzip.open(self.precon_source,'at')as f:f.write(json.dumps(historical)+'\n')
        page=self.request('/precons?format=Standard')[1]
        self.assertEqual(page['total'],1);self.assertEqual(page['decks'][0]['format'],'Archive')
        self.assertEqual(page['decks'][0]['historicalFormat'],'Standard');self.assertFalse(page['decks'][0]['playable'])
        self.assertIn(historical['id'],[deck['id']for deck in self.request('/precons?format=Archive')[1]['decks']])
        self.assertEqual(self.request('/precons?format=Commander')[1]['total'],2)

    def test_edits_to_bundled_or_starter_alias_fork_new_user_ids(self):
        for identity in ('included','starter-included'):
            changed=dict(self.starter,id=identity,name='Owned edit '+identity)
            code,saved=self.request('/decks/'+identity,changed,'PUT');self.assertEqual(code,200,saved)
            self.assertNotEqual(saved['id'],identity);self.assertEqual(saved['origin'],'user');self.assertEqual(saved['collection'],'mine')
            self.assertEqual(saved['sourceDeck']['id'],identity)
            self.assertEqual(saved['main'],self.starter['main'])
        self.assertEqual((self.bundled/'included.json').read_text(),self.original)
        self.assertEqual(self.store.get_deck('starter-included')['name'],'Curated starter')
        self.assertEqual(len(self.store.list_decks('user')),2)

    def test_legacy_owned_override_survives_and_cannot_shadow_starter_source(self):
        owned=dict(self.starter,name='Existing owned override')
        with self.store.connection(write=True)as c:c.execute("INSERT INTO decks VALUES (?,'user',?,?)",('included',encode(owned),now()))
        self.assertEqual(self.store.get_deck('included')['name'],'Existing owned override')
        self.assertEqual(self.store.get_deck('starter-included')['name'],'Curated starter')
        code,saved=self.request('/decks/included',dict(owned,name='Edited owned'),'PUT');self.assertEqual(code,200);self.assertEqual(saved['id'],'included')
        self.assertEqual(len(self.store.list_decks('user')),1)
        self.store.delete_deck('included');self.assertIsNone(self.store.get_deck('included'))
        self.assertEqual(self.store.list_decks('starter')[0]['name'],'Curated starter','Old hidden selection erased its immutable source')

    def test_precon_details_and_valid_copy_preserve_original_and_all_quantities(self):
        source=self.decks[0];before=self.request('/precons/'+source['id'])[1]
        code,result=self.request('/decks/'+source['id']+'/fork',{'name':'My Commander copy'})
        self.assertEqual(code,201,result);self.assertTrue(result['saved']);copy=result['deck'];self.assertEqual(copy['origin'],'user')
        self.assertEqual(copy['main'],source['main']);self.assertEqual(copy['commander'],source['commander']);self.assertNotEqual(copy['id'],source['id'])
        self.assertEqual(self.request('/precons/'+source['id'])[1],before)
        self.assertEqual(self.request('/decks?origin=user')[1]['decks'][0]['id'],copy['id'])

    def test_actual_description_survives_product_details_and_owned_copy_verbatim(self):
        raw=raw_deck();raw['description']='Build a board of creatures, then attack together.\nČuvaj odgovor za važan trenutak.'
        source=normalize_deck(raw,'fixture-0',{'TST':'Test expansion'},{'date':'2026-11-14'})
        with gzip.open(self.precon_source,'at',encoding='utf-8')as f:f.write(json.dumps(source,ensure_ascii=False)+'\n')
        detail=self.request('/precons/'+source['id'])[1]
        self.assertEqual(detail['description'],raw['description'])
        self.assertEqual(detail['main'],self.decks[0]['main']);self.assertEqual(detail['counts'],self.decks[0]['counts'])
        code,result=self.request('/decks/'+source['id']+'/fork',{})
        self.assertEqual(code,201,result);self.assertEqual(result['deck']['description'],raw['description'])
        self.assertEqual(self.store.get_deck(result['deck']['id'])['description'],raw['description'])

    def test_archive_copy_requires_chosen_format_and_invalid_copy_is_unsaved_named_repair(self):
        archive=self.decks[1]
        self.assertEqual(self.request('/decks/'+archive['id']+'/fork',{})[0],400)
        code,copy=self.request('/decks/'+archive['id']+'/fork',{'format':'Modern'});self.assertEqual(code,201,copy)
        self.assertEqual(copy['deck']['format'],'Modern');self.assertTrue(copy['saved'])
        before=len(self.store.list_decks('user'));illegal=self.decks[-1]
        code,result=self.request('/decks/'+illegal['id']+'/fork',{'format':'Modern'})
        self.assertEqual(code,422,result);self.assertFalse(result['saved']);self.assertIn('Unknown old card',result['error'])
        self.assertEqual(result['deck']['main'],illegal['main']);self.assertNotEqual(result['deck']['id'],illegal['id'])
        self.assertEqual(len(self.store.list_decks('user')),before)

    def test_source_update_rollback_never_resets_owned_decks(self):
        owned=self.store.save_deck(dict(self.starter,id='mine',name='Persisted user'))
        original=self.precon_source.read_bytes()
        with gzip.open(self.precon_source,'wt')as f:f.write('{invalid JSON}\n')
        with self.assertRaises(ValueError):self.store.precons()
        with self.store.connection()as c:self.assertEqual(c.execute('SELECT count(*) FROM preconstructed WHERE active=1').fetchone()[0],6)
        self.precon_source.write_bytes(original)
        again=Storage(self.store.root,self.bundled);self.assertEqual(again.get_deck(owned['id'])['name'],'Persisted user');self.assertEqual(again.precon_stats()['totalSourceRecords'],6)

    def test_applied_presentation_settings_are_typed_and_persisted(self):
        expected={'titleFontFamily':'Beleren','skybox':'Galaxy','skyboxBrightness':.32,'playmatOpacity':.88,'counterStyle':'Dice','cursorStyle':'Kenney','keywordReminders':True}
        for key,value in expected.items():self.assertEqual(self.store.settings()[key],value)
        chosen={'titleFontFamily':'Application font','skybox':'Nebula','skyboxBrightness':.8,'playmatOpacity':0,'counterStyle':'Text','cursorStyle':'Kenney','keywordReminders':False}
        self.store.save_settings(chosen);again=Storage(self.store.root,self.bundled)
        for key,value in chosen.items():self.assertEqual(again.settings()[key],value)
        for invalid in ({'titleFontFamily':'guess'},{'skybox':'URL'},{'skyboxBrightness':1.1},{'playmatOpacity':-1},{'counterStyle':'Emoji'},{'cursorStyle':True},{'keywordReminders':'true'}):
            with self.assertRaises(ValueError):self.store.save_settings(invalid)


class ProductDescriptionTest(unittest.TestCase):
    def test_description_bounds_preserve_text_and_empty_value_without_guessing_strategy(self):
        raw=raw_deck();metadata={'date':'2026-11-14'}
        for description in ('','x'*20000):
            self.assertEqual(normalize_deck(dict(raw,description=description),'description-fixture',{'TST':'Test'},metadata)['description'],description)
        for description in (False,[],{},1,'x'*20001):
            with self.subTest(description_type=type(description).__name__),self.assertRaisesRegex(ValueError,'description'):
                normalize_deck(dict(raw,description=description),'description-fixture',{'TST':'Test'},metadata)
        fallback=normalize_deck(dict(raw,strategy='Undocumented field must not be presented as an official description'),'description-fixture',{'TST':'Test'},metadata)
        self.assertEqual(fallback['description'],'Commander Deck — Test; original product list, current legality unverified.')


class PackagedPreconsTest(unittest.TestCase):
    def test_actual_packaged_snapshot_has_complete_provider_coverage_and_real_commanders(self):
        source=ROOT/'decks/preconstructed/catalog.jsonl.gz';manifest=json.loads((source.parent/'manifest.json').read_text());counts={};names={};total=0
        with gzip.open(source,'rt',encoding='utf-8')as stream:
            header=json.loads(next(stream))['_meta'];self.assertEqual(header['sha256'],manifest['sha256'])
            for line in stream:
                deck=json.loads(line);total+=1;counts[deck['category']]=counts.get(deck['category'],0)+1;names[deck['name']]=deck
        self.assertEqual(total,manifest['totalSourceRecords']);self.assertEqual(counts,manifest['categories']);self.assertGreater(counts['deck'],1100)
        self.assertGreater(counts['packet'],500);self.assertGreater(counts['collection'],1000)
        angels=names['Calling All Angels'];self.assertEqual((angels['format'],angels['faceCommander'],angels['counts']['main'],angels['counts']['commander']),('Commander','Giada, Font of Hope',99,1));self.assertEqual(angels['colorIdentity'],['W'])
        self.assertEqual(next(e['count']for e in angels['main']if e['name']=='Plains'),32)
        self.assertEqual(angels['source']['originalURL'],'https://magic.wizards.com/en/news/announcements/foundations-commander-decklists')
        self.assertEqual(names['Raining Cats and Dogs']['category'],'deck');self.assertEqual(names['From Cute to Brute']['category'],'deck')
        self.assertTrue((source.parent/'LICENSE-MTGJSON.txt').is_file())


class AcquisitionTest(unittest.TestCase):
    def setUp(self):
        spec=importlib.util.spec_from_file_location('sync_precons',ROOT/'scripts/sync-precons.py');self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def test_completed_partial_archive_resumes_offline_without_network(self):
        data=b'owned compressed archive fixture';partial=self.root/'AllDeckFiles.tar.xz.part';partial.write_bytes(data)
        with patch.object(self.module,'urlopen',side_effect=AssertionError('Offline means no network')):
            path=self.module.archive_file(self.root,hashlib.sha256(data).hexdigest(),offline=True)
        self.assertEqual(path.read_bytes(),data);self.assertFalse(partial.exists())
    def test_incomplete_bulk_never_replaces_previous_prepared_catalog(self):
        target=self.root/'catalog.jsonl.gz';target.write_bytes(b'previous generated source');archive=self.root/'fixture.tar.xz'
        wrapped=json.dumps({'meta':{'date':'2026-11-14'},'data':raw_deck()}).encode()
        with tarfile.open(archive,'w:xz')as tar:
            info=tarfile.TarInfo('../../fixture.json');info.size=len(wrapped);tar.addfile(info,io.BytesIO(wrapped))
        index={'meta':{'date':'2026-11-14','version':'fixture'},'data':[{'fileName':'fixture'},{'fileName':'missing'}]}
        with self.assertRaisesRegex(ValueError,'incomplete'):self.module.prepare(archive,index,{'data':[{'code':'TST','name':'Test'}]},target,'0'*64)
        self.assertEqual(target.read_bytes(),b'previous generated source');self.assertFalse((self.root/'catalog.jsonl.gz.records.part').exists());self.assertFalse((self.root.parent/'fixture.json').exists())
    def test_interrupted_archive_resumes_only_committed_bytes_and_verifies_digest(self):
        data=b'prefix-rest-of-official-archive';partial=self.root/'AllDeckFiles.tar.xz.part';partial.write_bytes(b'prefix-')
        class Response(io.BytesIO):
            status=206
            def __init__(self,payload,offset,fail=False):super().__init__(payload);self.headers={'Content-Range':'bytes '+str(offset)+'-'+str(len(data)-1)+'/'+str(len(data))};self.fail=fail;self.calls=0
            def read(self,n=-1):
                self.calls+=1
                if self.fail and self.calls==2:raise OSError('Interrupted owned transfer fixture')
                return super().read(5 if self.fail else n)
        requests=[]
        def fetch(request,timeout):
            requests.append(request);offset=int(request.get_header('Range').split('=')[1].split('-')[0]);return Response(data[offset:],offset,len(requests)==1)
        with patch.object(self.module,'urlopen',side_effect=fetch),patch.object(self.module.time,'sleep'):
            target=self.module.archive_file(self.root,hashlib.sha256(data).hexdigest())
        self.assertEqual(target.read_bytes(),data);self.assertEqual([r.get_header('Range')for r in requests],['bytes=7-','bytes=12-'])
        self.assertFalse(partial.exists())
    def test_range_rejection_restarts_owned_partial_without_overwriting_prior_archive(self):
        data=b'current official archive';target=self.root/'AllDeckFiles.tar.xz';target.write_bytes(b'old archive backup until successful replacement')
        (self.root/'AllDeckFiles.tar.xz.part').write_bytes(b'stale oversized partial')
        class Response(io.BytesIO):status=200;headers={}
        requests=[]
        def fetch(request,timeout):
            requests.append(request)
            if len(requests)==1:raise HTTPError(request.full_url,416,'fixture range rejection',{},None)
            self.assertEqual(target.read_bytes(),b'old archive backup until successful replacement');return Response(data)
        with patch.object(self.module,'urlopen',side_effect=fetch),patch.object(self.module.time,'sleep'):
            result=self.module.archive_file(self.root,hashlib.sha256(data).hexdigest())
        self.assertEqual(result.read_bytes(),data);self.assertIsNone(requests[1].get_header('Range'))


if __name__=='__main__':unittest.main()
