"""Exact card-art profile persistence and public room identity boundaries."""
import copy
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from profiles import normalize_profile
from rooms import Member
from server import make_handler
from storage import Storage

ORACLE='11111111-1111-4111-8111-111111111111'
PRINTING='22222222-2222-4222-8222-222222222222'
SECOND='33333333-3333-4333-8333-333333333333'
SECOND_ORACLE='44444444-4444-4444-8444-444444444444'


class ProfilesTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        raw={'object':'card','id':PRINTING,'oracle_id':ORACLE,'name':'Test Illustration','type_line':'Creature — Angel','lang':'en','set':'tst','set_name':'Test set','collector_number':'1','colors':['W'],'color_identity':['W'],'legalities':{},'image_uris':{'art_crop':'https://cards.scryfall.io/art_crop/a.jpg'}}
        second=dict(raw,id=SECOND,oracle_id=SECOND_ORACLE,name='Front // Back',card_faces=[{'name':'Front','image_uris':{'art_crop':'https://cards.scryfall.io/art_crop/front.jpg'}},{'name':'Back','image_uris':{'art_crop':'https://cards.scryfall.io/art_crop/back.jpg'}}])
        self.source=self.root/'cards.jsonl';self.source.write_text(json.dumps(raw)+'\n'+json.dumps(second)+'\n')
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure();self.assertEqual(self.catalog.status()['state'],'ready',self.catalog.status())
        self.storage=Storage(self.root/'saves',self.root/'bundled')
        self.ref={'oracleId':ORACLE,'printingId':PRINTING,'face':0,'name':'Ignored forged label'}
        self.server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(self.catalog,self.storage));self.worker=threading.Thread(target=self.server.serve_forever,daemon=True);self.worker.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.worker.join();self.temp.cleanup()
    def request(self,body=None):
        request=Request('http://127.0.0.1:'+str(self.server.server_port)+'/profile',data=None if body is None else json.dumps(body).encode(),method='GET'if body is None else'PUT',headers={'Content-Type':'application/json'})
        with urlopen(request)as response:return json.load(response)
    def test_default_profile_does_not_invent_life(self):
        self.assertEqual(self.request(),{'name':'Planeswalker','avatar':None,'playmat':None})
        self.assertNotIn('life',self.storage.profile())
    def test_exact_printing_face_name_persist_across_storage_restart(self):
        result=self.request({'name':'Čarobnjak','avatar':self.ref,'playmat':{'oracleId':SECOND_ORACLE,'printingId':SECOND,'face':1}})
        self.assertEqual(result['avatar']['name'],'Test Illustration');self.assertEqual(result['playmat']['name'],'Back')
        self.assertEqual(result,Storage(self.storage.root,self.root/'bundled').profile())
        self.assertEqual(result['playmat']['printingId'],SECOND);self.assertEqual(result['playmat']['face'],1)
    def test_reject_arbitrary_urls_life_extra_fields_and_invalid_bounds(self):
        for invalid in ({'name':'X','life':999},{'name':'X','hp':1},{'name':'X','avatar':{'url':'https://example.com/a.jpg'}},{'name':'X','playmat':dict(self.ref,face=True)},{'name':'X','avatar':dict(self.ref,face=10)},{'name':'X','avatar':dict(self.ref,printingId='https://example.com')},{'name':'X\nY'},{'name':'X'*81}):
            with self.subTest(invalid=invalid):
                with self.assertRaises(HTTPError)as error:self.request(invalid)
                self.assertEqual(error.exception.code,400)
        self.assertEqual(self.storage.profile()['name'],'Planeswalker')
    def test_reject_unknown_printing_face_or_oracle_without_overwriting(self):
        saved=self.request({'name':'Saved','avatar':self.ref})
        for ref in (dict(self.ref,face=1),dict(self.ref,oracleId=SECOND),dict(self.ref,printingId=ORACLE)):
            with self.assertRaises(HTTPError):self.request({'name':'Should not save','avatar':ref})
            self.assertEqual(self.storage.profile(),saved)
    def test_existing_identity_and_name_can_survive_unavailable_catalog(self):
        saved=self.request({'name':'Saved','avatar':self.ref})
        changed=copy.deepcopy(saved);changed['name']='Offline name'
        self.assertEqual(self.storage.save_profile(changed,None)['avatar'],saved['avatar'])
        with self.assertRaises(ValueError):self.storage.save_profile({'name':'X','avatar':dict(self.ref,printingId=SECOND,face=1)},None)
    def test_clear_reference_and_preserve_unrelated_user_data(self):
        self.storage.save_settings({'masterVolume':.3});self.request({'name':'X','avatar':self.ref,'playmat':self.ref})
        self.assertIsNone(self.request({'name':'X'})['avatar']);self.assertEqual(self.storage.settings()['masterVolume'],.3)
    def test_public_room_member_profile_is_bounded_and_independent(self):
        value={'name':'Guest profile','avatar':self.ref};member=Member('Legacy name',options={'profile':value})
        self.assertEqual(member.name,'Guest profile');value['name']='Mutated';self.assertEqual(member.profile['name'],'Guest profile')
        self.assertEqual(member.profile['avatar']['printingId'],PRINTING)
        with self.assertRaises(ValueError):normalize_profile({'name':'X','life':100})
        with self.assertRaises(Exception):Member('X',options={'profile':{'name':'X','avatar':dict(self.ref,url='https://example.com')}})


if __name__=='__main__':unittest.main()
