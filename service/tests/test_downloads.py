"""Managed image jobs use only temporary stores and synthetic complete JPEGs."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from downloads import DownloadManager,image_job_lock,RESERVE_BYTES,SIZE_SAMPLE_LIMIT,_cli
from maintenance import operation_lock
from replays import ConflictError,encode
from storage import Storage

JPEG=b'\xff\xd8'+b'genuine-shape-fixture'*5+b'\xff\xd9'


def card(identifier='first'):
    return {'object':'card','id':identifier,'oracle_id':'oracle-'+identifier,'name':identifier,'artist':'Artist',
            'image_uris':{kind:'https://cards.scryfall.io/'+kind+'/'+identifier+'.jpg'for kind in ('normal','large','art_crop')}}


class Fetcher:
    def __init__(self):self.urls=[]
    def image(self,url):self.urls.append(url);return JPEG


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.source=self.root/'cards.jsonl';self.write([card()])
        self.storage=Storage(self.root/'user',self.root/'empty-decks')
        self.catalog=Catalog(self.source,self.root/'index.sqlite')
        self.fetcher=Fetcher();self.managers=[]
        self.disk=SimpleNamespace(free=20*1024**3)
        self.manager=self.manager_new()

    def tearDown(self):
        for manager in self.managers:manager.close()
        self.storage.close_images()
        self.temp.cleanup()

    def manager_new(self):
        manager=DownloadManager(self.catalog,self.storage,fetcher_factory=lambda:self.fetcher,disk_usage=lambda _:self.disk)
        self.managers.append(manager);return manager

    def write(self,cards):self.source.write_text('\n'.join(json.dumps(v)for v in cards)+'\n')

    def wait(self,manager=None,states=('ready','completed','paused','cancelled','error')):
        manager=manager or self.manager
        limit=time.monotonic()+12
        while time.monotonic()<limit:
            status=manager.status()
            if status['state']in states and not(manager.thread and manager.thread.is_alive()):return status
            time.sleep(.005)
        self.fail('Timed out '+repr(manager.status()))

    def scan(self,**options):self.manager.scan(options);status=self.wait();self.assertEqual(status['state'],'ready',status);return status

    def test_scan_is_offline_counted_and_bytes_are_explicit_estimates(self):
        self.write([card('first'),card('second')])
        self.storage.save_art('first-0-normal.jpg',JPEG,{'kind':'normal'})
        status=self.scan();scan=status['scan']
        self.assertEqual((scan['total'],scan['cached'],scan['missing']),(4,1,3))
        self.assertEqual(scan['byKind']['normal']['meanBytes'],len(JPEG))
        self.assertEqual(scan['byKind']['normal']['sampleCount'],1)
        self.assertGreater(scan['estimatedDownloadBytes'],0)
        self.assertLess(scan['estimatedMinBytes'],scan['estimatedMaxBytes'])
        self.assertIn('estimate',scan['estimateBasis']);self.assertEqual(self.fetcher.urls,[])
        self.assertFalse((self.storage.root/'image-library').exists())

    def test_sql_only_download_resume_and_durable_restart(self):
        self.scan();self.manager.control('start');status=self.wait()
        self.assertEqual(status['state'],'completed',status)
        self.assertEqual(status['processed'],2);self.assertEqual(status['progress'],1)
        self.assertEqual(status['bytesDownloaded'],2*len(JPEG));self.assertEqual(len(self.fetcher.urls),2)
        self.assertEqual(status['imagesAdded'],2)
        self.assertEqual(self.storage.get_art('first-0-art_crop.jpg'),JPEG)
        self.assertFalse((self.storage.root/'image-library').exists())
        reopened=self.manager_new();self.assertEqual(reopened.status()['state'],'completed')
        reopened.control('resume');self.assertEqual(self.wait(reopened)['processed'],2)
        self.assertEqual(len(self.fetcher.urls),2,'A restart reuses committed SQL images')

    def test_exact_printings_remain_independent_but_urls_fetch_once(self):
        second=card('second');second['image_uris']=card()['image_uris']
        self.write([card(),second,card()])
        status=self.scan();self.assertEqual(status['scan']['total'],4)
        self.assertEqual(status['scan']['networkRequests'],2)
        self.manager.control('start');status=self.wait()
        self.assertEqual(status['state'],'completed',status)
        self.assertEqual(len(self.fetcher.urls),2)
        self.assertEqual(status['imagesAdded'],4)
        self.assertEqual(status['imported'],0,'A shared URL is reused SQL data, not a mirror import')
        for printing in ('first','second'):
            for kind in ('normal','art_crop'):self.assertEqual(self.storage.get_art(printing+'-0-'+kind+'.jpg'),JPEG)

    def test_faces_shared_scan_and_large_normal_compatibility(self):
        split=card();split['card_faces']=[{'name':'One'},{'name':'Two'}]
        double=card('double');double.pop('image_uris');double['card_faces']=[card('front'),card('back')]
        self.write([split,double]);self.storage.save_art('first-0-large.jpg',JPEG,{'kind':'large'})
        status=self.scan();self.assertEqual(status['scan']['total'],6)
        self.assertEqual(status['scan']['cached'],1)
        self.manager.control('start');self.assertEqual(self.wait()['state'],'completed')
        self.assertIsNone(self.storage.get_art('first-1-normal.jpg'))
        self.assertEqual(self.storage.get_art('double-1-art_crop.jpg'),JPEG)
        self.assertNotIn(card()['image_uris']['normal'],self.fetcher.urls)

    def test_existing_mirrors_import_and_optional_exports_repair(self):
        path=self.storage.root/'image-library/full-cards/first-0-normal.jpg';path.parent.mkdir(parents=True);path.write_bytes(JPEG)
        self.storage.save_art('first-0-art_crop.jpg',JPEG,{'kind':'art_crop'})
        status=self.scan(mirrors=True)
        self.assertEqual(status['scan']['mirrorCandidates'],1)
        self.assertGreater(status['scan']['estimatedMirrorBytes'],0)
        self.manager.control('start');status=self.wait();self.assertEqual(status['state'],'completed',status)
        self.assertEqual(self.fetcher.urls,[])
        self.assertEqual(self.storage.get_art('first-0-normal.jpg'),JPEG)
        self.assertEqual(status['imagesAdded'],1);self.assertEqual(status['imported'],1)
        crop=self.storage.root/'image-library/art-crops/first-0-art_crop.jpg';self.assertEqual(crop.read_bytes(),JPEG)
        crop.unlink();self.manager.control('resume');self.assertEqual(self.wait()['state'],'completed')
        self.assertEqual(crop.read_bytes(),JPEG);self.assertEqual(self.fetcher.urls,[])

    def test_optional_exports_replace_changed_same_size_mirror_from_authoritative_sql(self):
        for kind in ('normal','art_crop'):
            self.storage.save_art('first-0-'+kind+'.jpg',JPEG,{'kind':kind})
            path=self.storage.root/'image-library'/('art-crops'if kind=='art_crop'else'full-cards')/('first-0-'+kind+'.jpg')
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'X'*len(JPEG))
        self.scan(mirrors=True);self.manager.control('start');status=self.wait();self.assertEqual(status['state'],'completed',status)
        for path in(self.storage.root/'image-library').rglob('*.jpg'):self.assertEqual(path.read_bytes(),JPEG)
        self.assertEqual(self.fetcher.urls,[])

    def test_reserve_pauses_before_network_and_can_resume(self):
        self.scan();self.disk.free=RESERVE_BYTES-1;self.manager.control('start');status=self.wait()
        self.assertEqual(status['state'],'paused');self.assertIn('3 GiB',status['error']);self.assertEqual(self.fetcher.urls,[])
        self.disk.free=20*1024**3;self.manager.control('resume');self.assertEqual(self.wait()['state'],'completed')

    def test_pause_during_network_discards_uncommitted_response(self):
        entered=threading.Event();release=threading.Event()
        def image(url):entered.set();release.wait(5);return JPEG
        self.fetcher.image=image
        self.scan();self.manager.control('start');self.assertTrue(entered.wait(3));self.manager.control('pause');release.set()
        status=self.wait();self.assertEqual(status['state'],'paused')
        self.assertIsNone(self.storage.get_art('first-0-normal.jpg'))
        self.fetcher.image=lambda url:JPEG;self.manager.control('resume');self.assertEqual(self.wait()['state'],'completed')

    def test_other_desktop_can_pause_without_overwriting_request(self):
        entered=threading.Event();release=threading.Event()
        self.fetcher.image=lambda url:(entered.set(),release.wait(5),JPEG)[2]
        self.scan();other=self.manager_new();self.manager.control('start');self.assertTrue(entered.wait(3))
        self.assertEqual(other.status()['state'],'downloading')
        with self.assertRaises(ConflictError):other.scan({})
        other.control('cancel');release.set();self.assertEqual(self.wait()['state'],'cancelled')
        self.assertIsNone(self.storage.get_art('first-0-normal.jpg'))

    def test_crashed_state_recovers_without_autorun_or_repeated_network(self):
        self.scan()
        with self.storage.connection(write=True)as c:
            state=self.manager._state(c);state.update(state='downloading',controlRequest='paused');self.manager._save(state,c)
        reopened=self.manager_new();status=reopened.status();self.assertEqual(status['state'],'paused')
        self.assertEqual(self.fetcher.urls,[])
        reopened.control('resume');self.assertEqual(self.wait(reopened)['state'],'completed')

    def test_purge_generation_invalidates_scan_until_explicit_rescan(self):
        self.scan()
        with self.storage.connection(write=True)as c:c.execute("INSERT INTO meta VALUES('art_purge_generation','1') ON CONFLICT(key)DO UPDATE SET value='1'")
        status=self.manager.status();self.assertFalse(status['scanValid']);self.assertFalse(status['canStart'])
        with self.assertRaisesRegex(ValueError,'purged'):self.manager.control('start')
        self.scan();self.assertTrue(self.manager.status()['scanValid'])

    def test_status_returns_cached_snapshot_while_compaction_holds_exclusive(self):
        self.scan();self.manager.status()
        with operation_lock(self.storage.root,exclusive=True):
            started=time.monotonic();status=self.manager.status();elapsed=time.monotonic()-started
            self.assertLess(elapsed,.3);self.assertTrue(status['maintenanceBusy']);self.assertFalse(status['canStart'])

    def test_size_estimate_samples_at_most_512_cached_blob_headers_per_kind(self):
        with self.storage.connection(write=True)as c:
            c.executemany("INSERT INTO art_cache VALUES(?,?,'image/jpeg','{}',0)",
                          [('cached-'+str(index).zfill(4)+'-0-normal.jpg',JPEG)for index in range(SIZE_SAMPLE_LIMIT+20)])
            c.execute("INSERT INTO art_cache VALUES('decoy-0-artXcrop.jpg',?,'image/jpeg','{}',0)",(JPEG,))
        scan=self.scan()['scan'];sample=scan['byKind']['normal']
        self.assertEqual(sample['sampleCount'],SIZE_SAMPLE_LIMIT)
        self.assertEqual(sample['meanBytes'],len(JPEG))
        self.assertEqual(scan['byKind']['art_crop']['sampleCount'],0,'The underscore in art_crop is literal')
        self.assertIn('sample mean',scan['estimateBasis'])

    def test_scan_and_download_estimates_do_not_hold_the_sqlite_writer(self):
        self.storage.save_art('sample-0-normal.jpg',JPEG,{'kind':'normal'})
        original=self.manager._estimate
        for phase in('scan','download'):
            with self.subTest(phase=phase):
                if phase=='download':self.scan()
                entered=threading.Event();release=threading.Event()
                def blocked_estimate(c,state):
                    def hold(value):
                        entered.set();release.wait(5);return value
                    c.create_function('hold_estimate',1,hold)
                    # Hold a real SQLite BLOB-header read open while the
                    # independent save commits, not merely a Python delay.
                    c.execute('SELECT hold_estimate(length(content))FROM art_cache LIMIT 1').fetchone()
                    return original(c,state)
                with patch.object(self.manager,'_estimate',blocked_estimate),ThreadPoolExecutor(max_workers=1)as executor:
                    if phase=='scan':self.manager.scan({})
                    else:self.manager.control('start')
                    self.assertTrue(entered.wait(3),'Sizing never reached its read')
                    try:
                        writer=executor.submit(self.storage.save_ui_layout,{'whileEstimate':phase})
                        self.assertEqual(writer.result(timeout=1),{'whileEstimate':phase})
                        self.assertEqual(self.storage.ui_layout(),{'whileEstimate':phase})
                        self.manager.control('pause')
                    finally:release.set()
                    status=self.wait()
                    self.assertEqual(status['state'],'paused',status)
                    self.assertEqual(self.fetcher.urls,[],'Pause during sizing prevents network work')

    def test_invalid_options_sources_and_images_are_rejected(self):
        for options in ({'mirrors':'yes'},{'fullSize':'png'},{'kinds':[]},{'kinds':['executable']},{'metadata':'/etc/passwd'}):
            with self.subTest(options=options),self.assertRaises(ValueError):self.manager.scan(options)
        self.scan();self.fetcher.image=lambda url:b'incomplete';self.manager.control('start');status=self.wait()
        self.assertEqual(status['state'],'error');self.assertEqual(status['failed'],1)
        self.assertIsNone(self.storage.get_art('first-0-normal.jpg'))

    def test_cli_sql_only_reserve_and_job_lock(self):
        fetcher=Fetcher();stats=_cli.download(self.source,None,self.storage,fetcher)
        self.assertEqual(stats['downloaded'],2);self.assertFalse((self.storage.root/'image-library').exists())
        with image_job_lock(self.storage.root):
            with self.assertRaises(ValueError),_cli.cli_image_lock(self.storage.root):pass
        self.write([card('missing')])
        with patch.object(_cli.shutil,'disk_usage',return_value=SimpleNamespace(free=1)):
            stats=_cli.download(self.source,None,self.storage,fetcher,reserve_bytes=RESERVE_BYTES)
        self.assertTrue(stats['paused']);self.assertEqual(stats['examined'],1)
        mirror=self.storage.root/'image-library/full-cards/missing-0-normal.jpg'
        mirror.parent.mkdir(parents=True);mirror.write_bytes(JPEG)
        with patch.object(_cli.shutil,'disk_usage',return_value=SimpleNamespace(free=1)):
            stats=_cli.download(self.source,self.storage.root/'image-library',self.storage,fetcher,reserve_bytes=RESERVE_BYTES)
        self.assertTrue(stats['paused']);self.assertIsNone(self.storage.get_art('missing-0-normal.jpg'))


if __name__=='__main__':unittest.main()
