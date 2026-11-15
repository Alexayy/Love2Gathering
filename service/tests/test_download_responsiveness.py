"""Real temporary SQLite plans; never a user's cache or a remote transfer."""
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from http.client import IncompleteRead
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import downloads
from downloads import DownloadManager
from catalog import Catalog
from storage import Storage

JPEG=b'\xff\xd8'+b'local-complete-fixture'*10+b'\xff\xd9'


def card(identifier,name=None,oracle=None,faces=False):
    row={'object':'card','id':identifier,'oracle_id':oracle or identifier,'name':name or identifier,
         'type_line':'Creature','legalities':{'modern':'legal'},'lang':'en','color_identity':[],
         'image_uris':{kind:'https://cards.scryfall.io/'+kind+'/'+identifier+'.jpg'for kind in('normal','large','art_crop')}}
    if faces:
        row.pop('image_uris');row['card_faces']=[{'name':row['name']+' front','image_uris':card(identifier+'-front')['image_uris']},{'name':row['name']+' back','image_uris':card(identifier+'-back')['image_uris']}]
    return row


class DownloadResponsivenessTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='love2gathering-download-responsive-')
        self.root=Path(self.temp.name);self.source=self.root/'cards.jsonl';self.write([card('one')])
        self.storage=Storage(self.root/'data',self.root/'empty-bundled')
        self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.urls=[];self.managers=[]
        self.fetcher=SimpleNamespace(image=self.image)
        self.manager=self.new_manager()

    def tearDown(self):
        for manager in self.managers:manager.close()
        self.storage.close_images()
        self.temp.cleanup()

    def image(self,url):self.urls.append(url);return JPEG
    def write(self,records):self.source.write_text('\n'.join(json.dumps(row)for row in records)+'\n')
    def new_manager(self):
        value=DownloadManager(self.catalog,self.storage,fetcher_factory=lambda:self.fetcher,disk_usage=lambda _:SimpleNamespace(free=30*1024**3));self.managers.append(value);return value
    def wait(self,manager=None):
        manager=manager or self.manager;end=time.monotonic()+10
        while time.monotonic()<end:
            result=manager.status()
            if result['state']in('ready','completed','cancelled','paused','error')and not(manager.thread and manager.thread.is_alive()):return result
            time.sleep(.005)
        self.fail('Timed out: '+str(manager.status()))
    def scan(self):
        self.manager.scan({});result=self.wait();self.assertEqual(result['state'],'ready',result);return result

    def owned(self):
        return self.storage.save_deck({'id':'owned','name':'Owned deck','format':'Modern','coverCard':'Cover',
            'main':[{'name':'Forest','count':10},{'name':'Chosen Hero','count':1},{'name':'Cover','count':1}],
            'sideboard':[],'commander':[],
            'printingSelections':[{'name':'Chosen Hero','zone':'main','count':1,'printingId':'chosen'}]})

    def priority_source(self):
        self.write([card('unrelated'),card('forest-default','Forest','forest-oracle'),
                    card('forest-alt','Forest','forest-oracle'),card('cover','Cover'),
                    card('chosen-default','Chosen Hero','hero-oracle'),card('chosen','Chosen Hero','hero-oracle',faces=True)])
        self.catalog.ensure();self.assertEqual(self.catalog.status()['state'],'ready')

    def test_resumed_plan_yields_sql_writer_before_all_cache_checks_finish(self):
        self.write([card('printing-'+str(i))for i in range(20)]);self.scan()
        between=threading.Event();release=threading.Event();original=self.manager._requested_stop
        def pause_between(state):
            if state.get('phase')=='cache_check'and state.get('checkedImages')==4:
                between.set();release.wait(4)
            return original(state)
        try:
            with patch.object(downloads,'PLAN_BATCH_LIMIT',4),patch.object(self.manager,'_requested_stop',pause_between),ThreadPoolExecutor(max_workers=1)as executor:
                self.manager.control('start');self.assertTrue(between.wait(3),'Cache checks did not yield before completing the plan')
                saved=executor.submit(self.storage.save_settings,{'sfxEnabled':False})
                self.assertFalse(saved.result(timeout=.7)['sfxEnabled'])
                self.assertFalse(self.storage.settings()['sfxEnabled'])
                status=self.manager.status();self.assertEqual(status['state'],'downloading')
                self.assertEqual(self.urls,[],'No transfer may start until plan checking is complete')
                self.manager.control('pause');release.set();self.assertEqual(self.wait()['state'],'paused')
        finally:release.set()

    def test_one_whole_plan_transaction_reproduces_settings_writer_blocking(self):
        self.scan();held=threading.Event();release=threading.Event()
        def monolithic_old_shape():
            with self.storage.connection(write=True)as c:
                c.create_function('held_plan_row',1,lambda value:(held.set(),release.wait(3),value)[2])
                c.execute("CREATE TEMP TRIGGER slow_plan BEFORE UPDATE OF existing_key ON image_download_items BEGIN SELECT held_plan_row(NEW.ordinal); END")
                self.manager._refresh_cached(c,self.manager.status()['jobId'])
        with ThreadPoolExecutor(max_workers=2)as executor:
            checking=executor.submit(monolithic_old_shape);self.assertTrue(held.wait(2))
            save=executor.submit(self.storage.save_settings,{'sfxEnabled':False})
            try:
                with self.assertRaises(FutureTimeout):save.result(timeout=.15)
            finally:release.set()
            checking.result(timeout=3);self.assertFalse(save.result(timeout=3)['sfxEnabled'])

    def test_idle_manager_startup_does_not_wait_for_an_image_writer(self):
        executor=ThreadPoolExecutor(max_workers=1)
        try:
            with self.storage.connection(write=True)as c:
                c.execute("INSERT INTO art_cache VALUES('held-0-normal.jpg',?,'image/jpeg','{}',0)",(JPEG,))
                reopened=executor.submit(self.new_manager)
                self.assertEqual(reopened.result(timeout=.7).status()['state'],'idle')
        finally:executor.shutdown(wait=True)

    def test_exact_selected_faces_cover_and_one_default_come_before_other_reprints(self):
        self.priority_source();before=self.owned();self.scan();self.manager.control('start');result=self.wait()
        self.assertEqual(result['state'],'completed',result)
        self.assertEqual(self.storage.get_deck('owned')['printingSelections'],before['printingSelections'])
        # All four exact selected face/kind images outrank the cover/defaults.
        self.assertEqual(set(self.urls[:4]),set(card('chosen',faces=True)['card_faces'][0]['image_uris'][k]for k in('normal','art_crop'))|set(card('chosen',faces=True)['card_faces'][1]['image_uris'][k]for k in('normal','art_crop')))
        pos=lambda identifier:min(i for i,url in enumerate(self.urls)if '/'+identifier+'.jpg'in url)
        self.assertLess(pos('cover'),pos('forest-default'))
        self.assertLess(pos('forest-default'),pos('forest-alt'))
        self.assertLess(pos('chosen-default'),pos('forest-alt'))
        self.assertGreater(result['priorityImages'],0)

    def test_cached_selected_faces_are_not_fetched_even_when_they_are_prioritized(self):
        self.priority_source();self.owned()
        for job in downloads._cli.image_jobs(card('chosen',faces=True)):
            self.storage.save_art(job['key'],JPEG,job['metadata'])
        self.scan();self.manager.control('start');result=self.wait();self.assertEqual(result['state'],'completed',result)
        selected_urls={job['url']for job in downloads._cli.image_jobs(card('chosen',faces=True))}
        self.assertTrue(selected_urls.isdisjoint(self.urls))
        self.assertEqual(result['scan']['cached'],4)

    def test_resume_recomputes_priority_for_current_decks_without_altering_lists(self):
        self.priority_source();self.owned();self.scan();self.storage.delete_deck('owned')
        self.manager.control('start');result=self.wait();self.assertEqual(result['state'],'completed',result)
        self.assertEqual(result['prioritizedCards'],0);self.assertEqual(result['priorityImages'],0)
        self.assertEqual(self.urls[0],card('unrelated')['image_uris']['normal'])

    def test_existing_saved_plan_adds_priority_without_losing_rows_or_cached_images(self):
        self.scan();state=self.manager.status();job=state['jobId']
        self.storage.save_art('retained-0-normal.jpg',JPEG)
        with self.storage.connection(write=True)as c:
            c.execute('ALTER TABLE image_download_items RENAME TO old_plan')
            c.execute("CREATE TABLE image_download_items(job_id TEXT NOT NULL,cache_key TEXT NOT NULL,ordinal INTEGER NOT NULL,url TEXT NOT NULL,kind TEXT NOT NULL,metadata TEXT NOT NULL,existing_key TEXT,mirror TEXT,mirror_bytes INTEGER NOT NULL DEFAULT0,status TEXT NOT NULL DEFAULT'pending',PRIMARY KEY(job_id,cache_key))".replace('DEFAULT0','DEFAULT 0'))
            c.execute('INSERT INTO image_download_items SELECT job_id,cache_key,ordinal,url,kind,metadata,existing_key,mirror,mirror_bytes,status FROM old_plan')
            c.execute('DROP TABLE old_plan')
        reopened=self.new_manager()
        self.assertEqual(reopened.status()['jobId'],job)
        with self.storage.connection()as c:
            self.assertIn('priority',{row['name']for row in c.execute('PRAGMA table_info(image_download_items)')})
            self.assertEqual(c.execute('SELECT count(*)FROM image_download_items').fetchone()[0],2)
        reopened.control('resume');self.assertEqual(self.wait(reopened)['state'],'completed')
        self.assertEqual(self.storage.get_art('retained-0-normal.jpg'),JPEG)

    def test_cli_reuses_large_scan_for_normal_without_duplicate_sql_or_network(self):
        self.storage.save_art('one-0-large.jpg',JPEG,{'printingId':'one','oracleId':'one','kind':'large','face':0})
        result=downloads._cli.download(self.source,None,self.storage,self.fetcher,limit=1)
        self.assertEqual((result['cached'],result['downloaded']),(1,0));self.assertEqual(self.urls,[])
        self.assertIsNone(self.storage.get_art('one-0-normal.jpg'))

    def test_cli_shared_url_reuse_keeps_each_printing_metadata_independent(self):
        first=card('one');second=card('two');second['image_uris']=first['image_uris'];self.write([first,second])
        result=downloads._cli.download(self.source,None,self.storage,self.fetcher)
        self.assertEqual((result['downloaded'],result['reused']),(2,2));self.assertEqual(len(self.urls),2)
        with self.storage.connection()as c:
            metadata=json.loads(c.execute("SELECT metadata FROM art_cache WHERE cache_key='two-0-normal.jpg'").fetchone()[0])
        self.assertEqual(metadata['printingId'],'two');self.assertEqual(metadata['oracleId'],'two')
        self.urls.clear();again=downloads._cli.download(self.source,None,self.storage,self.fetcher)
        self.assertEqual((again['downloaded'],again['cached']),(0,4));self.assertEqual(self.urls,[])


class ImageTransportTest(unittest.TestCase):
    class Response:
        def __init__(self,data=JPEG,*,status=200,headers=None,broken=False):
            self.data=data;self.status=status;self.reason='fixture';self.headers=headers or{};self.length=len(data);self.closed=False;self.broken=broken
        def read(self,amount):
            if self.broken:raise IncompleteRead(b'partial',20)
            data=self.data[:amount];self.data=self.data[amount:];self.length=len(self.data)
            if not self.length:self.closed=True
            return data
        def close(self):self.closed=True
        def isclosed(self):return self.closed

    def factory(self,responses):
        connections=[]
        class Connection:
            def __init__(self,*args,**kw):self.args,self.options=args,kw;self.closed=False;self.requests=[];connections.append(self)
            def request(self,*args,**kw):self.requests.append((args,kw))
            def getresponse(self):return responses.pop(0)
            def close(self):self.closed=True
        return Connection,connections

    def fetcher(self,responses):
        factory,connections=self.factory(responses);sleeps=[]
        with patch.object(downloads._cli,'getproxies',return_value={}):
            fetcher=downloads._cli.Fetcher(connection_factory=factory,sleep=sleeps.append,monotonic=lambda:10)
        return fetcher,connections,sleeps

    def test_two_images_reuse_one_validated_tls_connection_and_keep_pacing(self):
        fetcher,connections,sleeps=self.fetcher([self.Response(),self.Response()])
        try:
            self.assertEqual(fetcher.image('https://cards.scryfall.io/one.jpg'),JPEG)
            self.assertEqual(fetcher.image('https://cards.scryfall.io/two.jpg?size=normal'),JPEG)
            self.assertEqual(len(connections),1);self.assertEqual(len(connections[0].requests),2)
            self.assertEqual(connections[0].args,('cards.scryfall.io',443))
            self.assertTrue(connections[0].options['context'].check_hostname)
            self.assertTrue(any(value>=.14 for value in sleeps))
            headers=connections[0].requests[0][1]['headers'];self.assertEqual(headers['Accept'],'image/jpeg');self.assertEqual(headers['Connection'],'keep-alive')
        finally:fetcher.close()
        self.assertTrue(connections[0].closed)

    def test_partial_transfer_and_temporary_error_reconnect_with_bounded_retry(self):
        fetcher,connections,sleeps=self.fetcher([self.Response(broken=True),self.Response(status=503),self.Response()])
        self.assertEqual(fetcher.image('https://cards.scryfall.io/one.jpg'),JPEG)
        self.assertEqual(len(connections),3);self.assertTrue(all(c.closed for c in connections[:-1]));fetcher.close()
        self.assertGreaterEqual(sleeps.count(1),2)

    def test_two_rate_limit_signals_stop_without_extra_requests(self):
        fetcher,connections,sleeps=self.fetcher([self.Response(status=429,headers={'Retry-After':'11'}),self.Response(status=429)])
        with self.assertRaises(HTTPError):fetcher.image('https://cards.scryfall.io/one.jpg')
        self.assertEqual(len(connections),2);self.assertTrue(all(c.closed for c in connections));self.assertIn(11,sleeps)

    def test_redirect_host_bounds_unread_body_and_proxy_routing_are_preserved(self):
        fetcher,connections,_=self.fetcher([self.Response(status=302,headers={'Location':'https://example.com/evil.jpg'})])
        with self.assertRaises(ValueError):fetcher.image('https://cards.scryfall.io/one.jpg')
        self.assertEqual(len(connections),1);self.assertTrue(connections[0].closed)
        fetcher,connections,_=self.fetcher([self.Response(b'\xff\xd8'+b'x'*(downloads._cli.MAX_IMAGE+30)+b'\xff\xd9'),self.Response()])
        with self.assertRaises(ValueError):fetcher.image('https://cards.scryfall.io/one.jpg')
        self.assertTrue(connections[0].closed)
        self.assertEqual(fetcher.image('https://cards.scryfall.io/two.jpg'),JPEG);self.assertEqual(len(connections),2);fetcher.close()
        with patch.object(downloads._cli,'getproxies',return_value={'https':'http://proxy.example'}),patch.object(downloads._cli,'proxy_bypass',return_value=False):
            proxied=downloads._cli.Fetcher()
        self.assertFalse(proxied.persistent_images,'Configured proxy routing must retain the existing proxy-aware transport');proxied.close()


if __name__=='__main__':unittest.main()
