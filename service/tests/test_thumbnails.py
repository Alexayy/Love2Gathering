"""Derived images and priority under contention; owned stores and no network."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from io import BytesIO
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import thumbnails
from catalog import Catalog
from image_io import ImageIO,ImageIOCancelled
from server import make_handler
from storage import Storage


def jpeg(color='teal',size=(672,936)):
    from PIL import Image
    result=BytesIO();Image.new('RGB',size,color).save(result,'JPEG');return result.getvalue()


@unittest.skipUnless(thumbnails.AVAILABLE,'JPEG-enabled Pillow is optional for source installs')
class ThumbnailTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='love2gathering-thumbnails-');self.root=Path(self.temp.name);self.stores=[]
    def tearDown(self):
        for store in self.stores:store.close_images()
        self.temp.cleanup()
    def store(self,split=False):
        p=self.root/str(len(self.stores));store=Storage(p/'data',p/'bundled',p/'images'if split else None);store.enable_thumbnails();self.stores.append(store);return store
    def save(self,store,data=None,key='printing-0-normal.jpg',**metadata):
        data=jpeg()if data is None else data;value=dict(printingId='printing',oracleId='oracle',face=0,kind='normal');value.update(metadata);store.save_art(key,data,value);return data
    def test_generated_once_reused_after_restart_and_source_bytes_unchanged(self):
        store=self.store();data=jpeg()
        with patch('thumbnails.jpeg_thumbnail',wraps=thumbnails.jpeg_thumbnail)as decode:
            self.save(store,data);self.assertTrue(store.flush_thumbnails());self.assertEqual(decode.call_count,1)
            for _ in range(10):self.assertEqual(store.local_art('printing','oracle',variant='thumb')[2]['_imageVariant'],'thumb')
            self.save(store,data,source='same-content-new-metadata');self.assertTrue(store.flush_thumbnails());self.assertEqual(decode.call_count,1)
            reopened=Storage(store.root,store.bundled);reopened.enable_thumbnails();self.stores.append(reopened);reopened.queue_thumbnail('printing-0-normal.jpg');self.assertTrue(reopened.flush_thumbnails());self.assertEqual(decode.call_count,1)
            self.assertEqual(reopened.local_art('printing','oracle')[0],data)
            result=reopened.local_art('printing','oracle',variant='thumb');self.assertEqual(result[2]['source'],'same-content-new-metadata')
            from PIL import Image
            with Image.open(BytesIO(result[0]))as image:self.assertEqual(image.size,(256,357))
    def test_generation_never_blocks_foreground_and_only_returns_original_until_ready(self):
        store=self.store();entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail
        def held(content):entered.set();release.wait(3);return real(content)
        try:
            with patch('thumbnails.jpeg_thumbnail',held):
                data=self.save(store);self.assertTrue(entered.wait(2));start=time.monotonic()
                local=store.local_art('printing','oracle',aliases=False,variant='thumb')
                self.assertLess(time.monotonic()-start,.4);self.assertEqual(local[0],data);self.assertTrue(local[2]['_thumbPending'])
                release.set();self.assertTrue(store.flush_thumbnails());self.assertEqual(store.local_art('printing','oracle',variant='thumb')[2]['_imageVariant'],'thumb')
        finally:release.set()
    def test_replacement_race_cannot_publish_old_derivative(self):
        store=self.store();entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail;calls=[]
        def held(content):
            calls.append(content)
            if len(calls)==1:entered.set();release.wait(3)
            return real(content)
        try:
            with patch('thumbnails.jpeg_thumbnail',held):
                old=self.save(store,jpeg('red'));self.assertTrue(entered.wait(2));new=self.save(store,jpeg('blue'));release.set();self.assertTrue(store.flush_thumbnails())
                from PIL import Image
                result=store.local_art('printing','oracle',variant='thumb')
                with Image.open(BytesIO(result[0]))as image:self.assertGreater(image.getpixel((0,0))[2],200)
                with store.connection()as c:self.assertEqual(c.execute('SELECT source_digest FROM art_thumbnails').fetchone()[0],hashlib.sha256(new).hexdigest())
                self.assertEqual(store.local_art('printing','oracle')[0],new);self.assertNotEqual(old,new)
        finally:release.set()
    def test_purge_fence_and_split_cache_cascades_no_thumbnail_resurrection(self):
        for split in (False,True):
            store=self.store(split);entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail
            def held(content):entered.set();release.wait(3);return real(content)
            try:
                with patch('thumbnails.jpeg_thumbnail',held):
                    self.save(store);self.assertTrue(entered.wait(2));store.purge_storage(['full_cards']);release.set();self.assertTrue(store.flush_thumbnails())
                    self.assertIsNone(store.local_art('printing','oracle',variant='thumb'))
                    with store.connection()as c:
                        self.assertEqual(c.execute('SELECT count(*)FROM '+store.image_table('art_thumbnails')).fetchone()[0],0)
                        self.assertEqual(c.execute('SELECT count(*)FROM '+store.image_table('art_sources')).fetchone()[0],0)
                    if split:
                        with sqlite3.connect(store.database)as c:self.assertIsNone(c.execute("SELECT name FROM sqlite_master WHERE name='art_thumbnails'").fetchone())
            finally:release.set()
    def test_face_kind_and_printing_never_alias_exact_thumbnails(self):
        store=self.store()
        self.save(store,jpeg('red'),key='printing-0-normal.jpg')
        self.save(store,jpeg('blue'),key='printing-1-art_crop.jpg',face=1,kind='art_crop')
        self.save(store,jpeg('green'),key='other-0-normal.jpg',printingId='other')
        self.assertTrue(store.flush_thumbnails())
        local=store.local_art('printing','oracle',face=1,kind='art_crop',aliases=False,variant='thumb')
        self.assertEqual((local[1],local[2]['printingId'],local[2]['face'],local[2]['kind']),('printing-1-art_crop.jpg','printing',1,'art_crop'))
        self.assertIsNone(store.local_art('missing','oracle',aliases=False,variant='thumb'))
        self.assertIsNone(store.local_art('printing','oracle',face=1,kind='normal',aliases=False,variant='thumb'))
    def test_older_writer_update_replace_delete_invalidates_with_foreign_keys_off(self):
        for split in(False,True):
            store=self.store(split);key='printing-0-normal.jpg';red=self.save(store,jpeg('red'));self.assertTrue(store.flush_thumbnails())
            def counts():
                with store.connection()as c:return[c.execute('SELECT count(*)FROM '+store.image_table(name)).fetchone()[0]for name in('art_sources','art_thumbnails')]
            with sqlite3.connect(store.cache_database)as raw:
                raw.execute('PRAGMA foreign_keys=OFF');self.assertEqual(raw.execute('PRAGMA foreign_keys').fetchone()[0],0)
                raw.execute('UPDATE art_cache SET content=? WHERE cache_key=?',(red,key))
            self.assertEqual(counts(),[1,1],'An identical source must reuse its already generated thumbnail')
            blue=jpeg('blue')
            for replace,data in((False,blue),(True,red)):
                with sqlite3.connect(store.cache_database)as raw:
                    raw.execute('PRAGMA foreign_keys=OFF')
                    if replace:raw.execute('INSERT OR REPLACE INTO art_cache VALUES(?,?,?,?,?)',(key,data,'image/jpeg',json.dumps(dict(printingId='printing',oracleId='oracle',face=0,kind='normal')),123))
                    else:raw.execute('UPDATE art_cache SET content=? WHERE cache_key=?',(data,key))
                self.assertEqual(counts(),[0,0],'An older writer must not leave a valid-looking stale digest/thumbnail')
                result=store.local_art('printing','oracle',aliases=False,variant='thumb');self.assertEqual(result[0],data);self.assertTrue(result[2]['_thumbPending'])
                self.assertTrue(store.flush_thumbnails());self.assertEqual(counts(),[1,1]);self.assertEqual(store.local_art('printing','oracle')[0],data)
            with sqlite3.connect(store.cache_database)as raw:
                raw.execute('PRAGMA foreign_keys=OFF');raw.execute('DELETE FROM art_cache WHERE cache_key=?',(key,))
            self.assertEqual(counts(),[0,0]);self.assertIsNone(store.local_art('printing','oracle',variant='thumb'))
    def test_absent_pillow_and_bad_jpeg_stop_pending_retry(self):
        store=self.store()
        with patch('thumbnails.AVAILABLE',False):
            data=self.save(store);self.assertTrue(store.flush_thumbnails());result=store.local_art('printing','oracle',variant='thumb')
            self.assertEqual(result[0],data);self.assertTrue(result[2]['_thumbUnavailable']);self.assertFalse(result[2]['_thumbPending'])
        self.save(store,b'\xff\xd8invalid-jpeg\xff\xd9');self.assertTrue(store.flush_thumbnails())
        result=store.local_art('printing','oracle',variant='thumb');self.assertTrue(result[2]['_thumbUnavailable']);self.assertFalse(result[2]['_thumbPending'])
        failures=store.thumbnails.status()['failed'];time.sleep(.05);store.queue_thumbnail('printing-0-normal.jpg');self.assertEqual(store.thumbnails.status()['failed'],failures)
    def test_queue_is_bounded_and_close_retires_worker(self):
        store=self.store();entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail
        def held(content):entered.set();release.wait(3);return real(content)
        try:
            with patch('thumbnails.jpeg_thumbnail',held):
                data=self.save(store);self.assertTrue(entered.wait(2))
                for index in range(80):self.save(store,data,key='p'+str(index)+'-0-normal.jpg')
                status=store.thumbnails.status();self.assertLessEqual(status['pending'],64);self.assertGreater(status['dropped'],0)
                release.set();store.close_images();self.assertFalse(store.thumbnails.status()['workerAlive']);self.assertEqual(store.thumbnails.status()['pending'],0)
        finally:release.set()
    def test_relocation_fence_never_commits_a_waiting_derivative(self):
        store=self.store();entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail
        def held(content):entered.set();release.wait(3);return real(content)
        try:
            with patch('thumbnails.jpeg_thumbnail',held):
                self.save(store);self.assertTrue(entered.wait(2));store.relocation_active.set();release.set();self.assertTrue(store.flush_thumbnails());store.close_images()
                with sqlite3.connect(store.database)as c:self.assertEqual(c.execute('SELECT count(*)FROM art_thumbnails').fetchone()[0],0)
        finally:release.set();store.relocation_active.clear()


class ImagePriorityTests(unittest.TestCase):
    def test_standalone_background_process_yields_to_desktop_foreground(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-cross-process-io-')as tmp:
            root=Path(tmp);io=ImageIO(root)
            code='import sys;from pathlib import Path;sys.path.insert(0,sys.argv[1]);from image_io import ImageIO\np=Path(sys.argv[2]);io=ImageIO(p)\nwith io.background():\n io.checkpoint();(p/"passed").write_text("done")\n'
            child=None
            try:
                with io.foreground(selected=True):
                    child=subprocess.Popen([sys.executable,'-c',code,str(Path(__file__).resolve().parents[1]),str(root)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                    time.sleep(.1);self.assertIsNone(child.poll());self.assertFalse((root/'passed').exists())
                stdout,stderr=child.communicate(timeout=3);self.assertEqual(child.returncode,0,stderr);self.assertTrue((root/'passed').is_file())
            finally:
                if child is not None and child.poll()is None:child.kill();child.communicate(timeout=3)
    def test_selected_precedes_foreground_and_bulk_and_background_yields(self):
        io=ImageIO();order=[];errors=[]
        def run(name,priority):
            try:
                with io.background()if priority==2 else io.foreground(priority==0):
                    with io.operation(timeout=2):order.append(name)
            except Exception as exc:errors.append(exc)
        with io.operation():
            threads=[threading.Thread(target=run,args=value)for value in [('bulk',2),('normal',1),('selected',0)]]
            for thread in threads:thread.start()
            until=time.monotonic()+1
            while io.status()['waiting']<3 and time.monotonic()<until:time.sleep(.002)
        for thread in threads:thread.join(2);self.assertFalse(thread.is_alive())
        self.assertFalse(errors);self.assertEqual(order,['selected','normal','bulk']);self.assertEqual(io.status()['maxConcurrentDiskOperations'],1)
    def test_background_checkpoint_cancellation_and_foreground_timeout(self):
        io=ImageIO();cancel=threading.Event();out=[]
        def waiting():
            try:
                with io.background(cancel):io.checkpoint()
            except ImageIOCancelled:out.append('cancelled')
        with io.foreground():
            thread=threading.Thread(target=waiting);thread.start();time.sleep(.03);cancel.set();thread.join(1)
        self.assertEqual(out,['cancelled']);self.assertGreater(io.status()['backgroundYields'],0)


@unittest.skipUnless(thumbnails.AVAILABLE,'JPEG-enabled Pillow is optional for source installs')
class ThumbnailHTTPTests(unittest.TestCase):
    def test_real_http_fallback_ready_exact_identity_and_selected_force_fetch(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-thumbnail-http-')as tmp:
            root=Path(tmp);printing='11111111-1111-4111-8111-111111111111';other='33333333-3333-4333-8333-333333333333';oracle='22222222-2222-4222-8222-222222222222'
            source=root/'cards.jsonl';source.write_text(''.join(json.dumps(dict(object='card',id=p,oracle_id=oracle,name='Thumbnail Fixture',lang='en',set='tst',type_line='Instant',legalities={'modern':'legal'},image_uris={'normal':'https://cards.scryfall.io/normal/'+p+'.jpg','art_crop':'https://cards.scryfall.io/art_crop/'+p+'.jpg'}))+'\n'for p in(printing,other)))
            catalog=Catalog(source,root/'catalog.sqlite');catalog.ensure();store=Storage(root/'data',root/'decks');handler=make_handler(catalog,store);calls=[];data=jpeg()
            handler.download_art=lambda _,url:(calls.append(url)or data)
            server=ThreadingHTTPServer(('127.0.0.1',0),handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start();base='http://127.0.0.1:'+str(server.server_port)
            entered=threading.Event();release=threading.Event();real=thumbnails.jpeg_thumbnail
            def held(content):entered.set();release.wait(3);return real(content)
            try:
                with patch('thumbnails.jpeg_thumbnail',held):
                    store.save_art(printing+'-0-normal.jpg',data,{'printingId':printing,'oracleId':oracle,'face':0,'kind':'normal'});self.assertTrue(entered.wait(2))
                    path='/art/'+oracle+'?printing='+printing+'&exact=1&kind=normal&variant=thumb&network=0'
                    with urlopen(base+path,timeout=3)as response:self.assertEqual(response.read(),data);self.assertEqual(response.headers['X-Love2Gathering-Art-Variant'],'original');self.assertEqual(response.headers['X-Love2Gathering-Thumb-Pending'],'1')
                    release.set();self.assertTrue(store.flush_thumbnails())
                    with urlopen(base+path,timeout=3)as response:self.assertNotEqual(response.read(),data);self.assertEqual(response.headers['X-Love2Gathering-Art-Variant'],'thumb');self.assertEqual(response.headers['X-Love2Gathering-Art-Key'],printing+'-0-normal.jpg')
                missing='/gallery/art/'+other+'?kind=normal&network=0'
                with self.assertRaises(HTTPError)as error:urlopen(base+missing,timeout=3)
                self.assertEqual(error.exception.code,404);self.assertEqual(calls,[])
                selected='/gallery/art/'+other+'?kind=normal&network=1&priority=selected'
                with urlopen(base+selected,timeout=3)as response:self.assertEqual(response.read(),data)
                with urlopen(base+selected,timeout=3)as response:self.assertEqual(response.read(),data)
                self.assertEqual(len(calls),1)
                with urlopen(base+'/health',timeout=3)as response:self.assertEqual(json.load(response)['apiVersion'],14)
            finally:
                release.set();server.shutdown();server.server_close();thread.join(3);handler.close_managers();self.assertFalse(thread.is_alive())


if __name__=='__main__':unittest.main()
