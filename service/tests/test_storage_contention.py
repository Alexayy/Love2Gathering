"""Foreground storage responsiveness against actual isolated SQLite writers."""
from contextlib import contextmanager
import base64
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from urllib.request import Request,urlopen
from urllib.error import HTTPError

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from storage import Storage
from artwork import prefer_cached_card
from catalog import Catalog
from server import make_handler

JPEG=b'\xff\xd8'+b'isolated-image-fixture'*128
# Generated solid32x32 pixels; this fixture never requests remote card art.
VALID_JPEG=base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAgACADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwAooorzz5IKKKKACiiigAooooA//9k=')


class StorageContentionTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='love2gathering-storage-contention-')
        self.root=Path(self.temp.name)
        self.storage=Storage(self.root/'data',self.root/'bundled')

    def tearDown(self):self.temp.cleanup()

    def test_foreground_save_has_a_short_wait_and_never_claims_a_commit(self):
        writer=sqlite3.connect(self.storage.database,isolation_level=None)
        writer.execute('BEGIN IMMEDIATE')
        started=time.monotonic()
        try:
            with self.storage.interactive_access(timeout=.12):
                with self.assertRaises(sqlite3.OperationalError):
                    self.storage.save_settings({'theme':'Ember'})
            elapsed=time.monotonic()-started
            self.assertLess(elapsed,.7,'Foreground save must return busy before an eight-second client timeout')
        finally:writer.execute('ROLLBACK');writer.close()
        self.assertEqual(self.storage.settings()['theme'],'Midnight')
        self.assertEqual(self.storage.save_settings({'theme':'Ember'})['theme'],'Ember')

    def test_wal_reads_remain_available_while_an_image_writer_is_active(self):
        for separate in(False,True):
            with self.subTest(separate=separate):
                store=Storage(self.root/('split'if separate else'combined'),self.root/'bundled',self.root/'images'if separate else None)
                store.save_settings({'theme':'Ocean'});store.save_art('visible-0-normal.jpg',JPEG)
                database=store.cache_database
                writer=sqlite3.connect(database,isolation_level=None);writer.execute('BEGIN IMMEDIATE')
                writer.execute("UPDATE art_cache SET content=? WHERE cache_key='visible-0-normal.jpg'",(b'\xff\xd8uncommitted',))
                began=time.monotonic()
                try:
                    with store.interactive_access(timeout=.4):
                        self.assertEqual(store.settings()['theme'],'Ocean')
                        self.assertEqual(store.get_art('visible-0-normal.jpg'),JPEG)
                    self.assertLess(time.monotonic()-began,.7)
                finally:writer.execute('ROLLBACK');writer.close()

    def test_foreground_scope_is_thread_local_and_restores_background_wait(self):
        timeouts=[]
        def inspect():
            with self.storage.connection()as c:timeouts.append(c.execute('PRAGMA busy_timeout').fetchone()[0])
        with self.storage.interactive_access(timeout=.3):
            with self.storage.connection()as c:self.assertLessEqual(c.execute('PRAGMA busy_timeout').fetchone()[0],300)
            thread=threading.Thread(target=inspect);thread.start();thread.join(2)
            self.assertFalse(thread.is_alive())
        inspect();self.assertEqual(timeouts,[30000,30000])

    def test_split_attach_keeps_the_request_deadline_and_durability(self):
        store=Storage(self.root/'split',self.root/'bundled',self.root/'images')
        with store.interactive_access(timeout=.3):
            with store.connection()as c:
                self.assertLessEqual(c.execute('PRAGMA busy_timeout').fetchone()[0],300)
                self.assertEqual(c.execute('PRAGMA journal_mode').fetchone()[0],'wal')
                self.assertEqual(c.execute('PRAGMA images.journal_mode').fetchone()[0],'wal')
                self.assertEqual(c.execute('PRAGMA synchronous').fetchone()[0],2)
                self.assertEqual(c.execute('PRAGMA images.synchronous').fetchone()[0],2)
        with store.connection()as c:self.assertEqual(c.execute('PRAGMA busy_timeout').fetchone()[0],30000)

    def test_nested_scopes_do_not_extend_the_outer_deadline(self):
        with self.storage.interactive_access(timeout=.08):
            time.sleep(.02)
            with self.storage.interactive_access(timeout=5):
                with self.storage.connection()as c:self.assertLessEqual(c.execute('PRAGMA busy_timeout').fetchone()[0],60)
            time.sleep(.08)
            with self.assertRaises(sqlite3.OperationalError):
                with self.storage.connection():pass
        with self.storage.connection()as c:self.assertEqual(c.execute('PRAGMA busy_timeout').fetchone()[0],30000)

    def test_external_wait_preserves_spent_budget_nested_scopes_and_exceptions(self):
        clock=[10.0]
        with patch('storage.time.monotonic',lambda:clock[0]):
            with self.storage.interactive_access(timeout=3):
                clock[0]+=.75
                with self.storage.external_io():
                    clock[0]+=4
                    with self.storage.external_io():clock[0]+=2
                    self.assertEqual(self.storage._busy_timeout_ms(),2250)
                self.assertEqual(self.storage._busy_timeout_ms(),2250)
                with self.storage.interactive_access(timeout=.5):
                    with self.assertRaisesRegex(ValueError,'external failure'):
                        with self.storage.external_io():
                            clock[0]+=4
                            raise ValueError('external failure')
                    self.assertEqual(self.storage._busy_timeout_ms(),500)
                self.assertEqual(self.storage._busy_timeout_ms(),2250)
                clock[0]+=2.3
                with self.assertRaises(sqlite3.OperationalError):self.storage._busy_timeout_ms()
            self.assertEqual(self.storage._busy_timeout_ms(),30000)
            # A later request receives its own full allowance, rather than a
            # prior request's suspended deadline or a background-only scope.
            with self.storage.external_io():clock[0]+=20
            with self.storage.interactive_access(timeout=1):self.assertEqual(self.storage._busy_timeout_ms(),1000)

    def test_external_wait_does_not_extend_another_threads_foreground_budget(self):
        ready=threading.Event();release=threading.Event();errors=[]
        def inspect():
            try:
                with self.storage.interactive_access(timeout=.05):
                    ready.set();release.wait(1)
                    with self.assertRaises(sqlite3.OperationalError):self.storage._busy_timeout_ms()
            except BaseException as exc:errors.append(exc)
        thread=threading.Thread(target=inspect)
        with self.storage.interactive_access(timeout=.1):
            with self.storage.external_io():
                thread.start();self.assertTrue(ready.wait(1));time.sleep(.08)
                release.set();thread.join(1)
            self.assertGreater(self.storage._busy_timeout_ms(),50)
        self.assertFalse(thread.is_alive());self.assertEqual(errors,[])

    def test_writer_wait_after_external_io_still_uses_only_the_remaining_budget(self):
        writer=sqlite3.connect(self.storage.database,isolation_level=None);writer.execute('BEGIN IMMEDIATE')
        try:
            with self.storage.interactive_access(timeout=.16):
                time.sleep(.04)
                with self.storage.external_io():time.sleep(.08)
                began=time.monotonic()
                with self.assertRaises(sqlite3.OperationalError):self.storage.save_settings({'theme':'Ember'})
                self.assertLess(time.monotonic()-began,.15,'External time must not reset the consumed foreground lock budget')
        finally:writer.execute('ROLLBACK');writer.close()
        self.assertEqual(self.storage.settings()['theme'],'Midnight')

    def test_alias_sort_does_not_read_blobs_until_an_identity_is_selected(self):
        self.storage.save_art('a-large-0-large.jpg',JPEG,{'printingId':'actual-large','oracleId':'oracle','face':0,'kind':'large'})
        self.storage.save_art('z-normal-0-normal.jpg',JPEG+b'normal',{'printingId':'actual-normal','oracleId':'oracle','face':0,'kind':'normal'})
        original=self.storage.connection;queries=[]
        @contextmanager
        def guarded(write=False,**options):
            with original(write,**options)as c:
                current={'sql':''}
                def authorize(action,table,column,*rest):
                    if action==sqlite3.SQLITE_READ and table=='art_cache'and column=='content'and 'ORDER BY'in current['sql'].upper():return sqlite3.SQLITE_DENY
                    return sqlite3.SQLITE_OK
                c.set_authorizer(authorize)
                class Proxy:
                    def execute(self,sql,*args):current['sql']=sql;queries.append(sql);return c.execute(sql,*args)
                yield Proxy()
        with patch.object(self.storage,'connection',guarded):
            image,key,metadata=self.storage.local_art('missing','oracle')
        self.assertEqual((image,key,metadata['printingId']),(JPEG+b'normal','z-normal-0-normal.jpg','actual-normal'))
        self.assertTrue(any('ORDER BY'in sql for sql in queries))

    def test_prefer_cached_card_stops_metadata_decoding_after_first_valid_printing(self):
        for index in range(50):self.storage.save_art(f'printing-{index:02}-0-normal.jpg',JPEG,{'printingId':f'printing-{index:02}','oracleId':'oracle','face':0,'kind':'normal'})
        class Catalog:
            def get(self,identifier,printing_id):return{'id':identifier,'printing_id':printing_id,'name':'Card'}
        original=json.loads;decoded=[]
        def tracked(value,*args,**kwargs):
            if isinstance(value,str)and'"printingId"'in value:decoded.append(value)
            return original(value,*args,**kwargs)
        with patch('artwork.json.loads',side_effect=tracked):
            selected=prefer_cached_card(Catalog(),self.storage,{'id':'oracle','printing_id':'absent','name':'Card'})
        self.assertEqual(selected['printing_id'],'printing-00')
        self.assertTrue(selected['art_cached']);self.assertEqual(len(decoded),1)

    def test_candidate_iterator_releases_connection_on_early_return(self):
        self.storage.save_art('one-0-normal.jpg',JPEG,{'printingId':'one','oracleId':'oracle','face':0,'kind':'normal'})
        active=[];original=self.storage.connection
        @contextmanager
        def counted(write=False):
            with original(write)as c:
                active.append(True)
                try:yield c
                finally:active.pop()
        class Catalog:
            def get(self,**kwargs):return{'id':'oracle','printing_id':'one'}
        with patch.object(self.storage,'connection',counted):
            prefer_cached_card(Catalog(),self.storage,{'id':'oracle','printing_id':'absent'})
            self.assertEqual(active,[])

    def test_actual_http_reads_stay_available_and_busy_save_is_retryable(self):
        source=self.root/'cards.jsonl'
        source.write_text(json.dumps({'object':'card','id':'printing','oracle_id':'oracle','name':'Fixture','lang':'en','type_line':'Instant','oracle_text':'','colors':['R'],'color_identity':['R'],'set':'tst','legalities':{'modern':'legal'},'image_uris':{'normal':'https://cards.scryfall.io/normal/fixture.jpg'}})+'\n')
        catalog=Catalog(source,self.root/'catalog.sqlite');catalog.ensure()
        self.storage.save_art('printing-0-normal.jpg',JPEG,{'oracleId':'oracle','printingId':'printing','face':0,'kind':'normal'})
        handler=make_handler(catalog,self.storage)
        server=ThreadingHTTPServer(('127.0.0.1',0),handler);server.daemon_threads=True
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        base='http://127.0.0.1:'+str(server.server_port)
        writer=sqlite3.connect(self.storage.database,isolation_level=None);writer.execute('BEGIN IMMEDIATE')
        scope=self.storage.interactive_access
        try:
            # Exercise the real route and response, with a deliberately short
            # test deadline rather than sleeping three seconds in every run.
            with patch.object(self.storage,'interactive_access',lambda:scope(.12)):
                began=time.monotonic()
                with urlopen(base+'/settings',timeout=2)as reply:self.assertEqual(json.load(reply)['theme'],'Midnight')
                with urlopen(base+'/profile',timeout=2)as reply:self.assertEqual(json.load(reply)['name'],'Planeswalker')
                with urlopen(base+'/art/oracle?printing=printing&exact=1&network=0',timeout=2)as reply:self.assertEqual(reply.read(),JPEG)
                self.assertLess(time.monotonic()-began,.7)
                request=Request(base+'/settings',data=json.dumps({'theme':'Ember'}).encode(),method='PUT',headers={'Content-Type':'application/json'})
                began=time.monotonic()
                with self.assertRaises(HTTPError)as blocked:urlopen(request,timeout=2)
                self.assertEqual(blocked.exception.code,503)
                self.assertEqual(blocked.exception.headers.get('Retry-After'),'1')
                self.assertTrue(json.load(blocked.exception)['retryable'])
                self.assertLess(time.monotonic()-began,.7)
        finally:
            writer.execute('ROLLBACK');writer.close()
            handler.close_managers();server.shutdown();server.server_close();worker.join(2)
        self.assertEqual(self.storage.settings()['theme'],'Midnight')

    def test_actual_http_slow_external_fetch_can_commit_and_the_next_request_is_local(self):
        source=self.root/'cards.jsonl'
        source.write_text(json.dumps({'object':'card','id':'printing','oracle_id':'oracle','name':'Fixture','lang':'en','type_line':'Instant','oracle_text':'','colors':['R'],'color_identity':['R'],'set':'tst','legalities':{'modern':'legal'},'image_uris':{kind:'https://cards.scryfall.io/'+kind+'/fixture.jpg'for kind in('normal','art_crop')}})+'\n')
        catalog=Catalog(source,self.root/'catalog.sqlite');catalog.ensure()
        handler=make_handler(catalog,self.storage)
        server=ThreadingHTTPServer(('127.0.0.1',0),handler);server.daemon_threads=True
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        base='http://127.0.0.1:'+str(server.server_port);fetches=[]
        def slow_fetch(_handler,url):
            fetches.append(url);time.sleep(3.1);return VALID_JPEG
        try:
            with patch.object(handler,'download_art',slow_fetch):
                for method,kind in(('GET','normal'),('POST','art_crop')):
                    with self.subTest(method=method):
                        def request():
                            if method=='GET':return base+'/art/oracle?printing=printing&exact=1&network=1'
                            return Request(base+'/art/download',data=json.dumps({'printingId':'printing','face':0,'kind':kind}).encode(),method='POST',headers={'Content-Type':'application/json'})
                        before=len(fetches)
                        with urlopen(request(),timeout=5)as reply:
                            self.assertEqual(reply.status,200)
                            if method=='GET':self.assertEqual(reply.read(),VALID_JPEG)
                            else:self.assertTrue(json.load(reply)['downloaded'])
                        self.assertEqual(self.storage.get_art('printing-0-'+kind+'.jpg'),VALID_JPEG)
                        self.assertEqual(len(fetches),before+1)
                        # Even network=1 must prefer this exact locally saved
                        # printing without a second request to the fetcher.
                        with urlopen(request(),timeout=2)as reply:
                            self.assertEqual(reply.status,200)
                            if method=='GET':self.assertEqual(reply.read(),VALID_JPEG)
                            else:self.assertFalse(json.load(reply)['downloaded'])
                        self.assertEqual(len(fetches),before+1)
        finally:
            handler.close_managers();server.shutdown();server.server_close();worker.join(2)
        self.assertFalse(worker.is_alive())


if __name__=='__main__':unittest.main()
