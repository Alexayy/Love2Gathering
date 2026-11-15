"""Bulk workers yield to selected local images; no external acquisition."""
from contextlib import redirect_stdout
import hashlib
from io import BytesIO, StringIO
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from downloads import DownloadManager,_cli
from image_packs import FORMAT,ImagePacks
from storage import Storage
from thumbnails import AVAILABLE


def jpeg():
    if not AVAILABLE:return b'\xff\xd8isolated-image-fixture\xff\xd9'
    from PIL import Image
    image=Image.new('RGB',(672,936),(70,110,155));output=BytesIO();image.save(output,format='JPEG');return output.getvalue()


class BackgroundImageTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='love2gathering-background-images-')
        self.root=Path(self.temporary.name);self.image=jpeg()
        self.source=self.root/'cards.jsonl'
        raw={'object':'card','id':'printing','oracle_id':'oracle','name':'Fixture','lang':'en','set':'tst',
             'image_uris':{kind:'https://cards.scryfall.io/'+kind+'/fixture.jpg'for kind in('normal','art_crop')}}
        self.source.write_text(json.dumps(raw)+'\n');self.catalog=Catalog(self.source,self.root/'catalog.sqlite');self.catalog.ensure()
        self.store=Storage(self.root/'data',self.root/'bundled');owner=self
        class Fetcher:
            def __init__(self):self.urls=[]
            def image(self,url):self.urls.append(url);return owner.image
            def close(self):pass
        self.fetcher=Fetcher();self.manager=DownloadManager(self.catalog,self.store,fetcher_factory=lambda:self.fetcher)
        self.packs=ImagePacks(self.catalog,self.store)

    def tearDown(self):
        self.manager.close();self.packs.close();self.store.close_images();self.temporary.cleanup()

    def wait(self,manager=None):
        manager=manager or self.manager;deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            if manager.thread and not manager.thread.is_alive():return manager.status()
            time.sleep(.005)
        self.fail('Background image work did not finish: '+repr(manager.status()))

    def scan(self,options=None):
        self.manager.scan(options);state=self.wait();self.assertEqual(state['state'],'ready',state);return state

    def test_scan_yields_while_selected_foreground_requests_need_disk(self):
        with self.store.image_io.foreground(selected=True):
            self.manager.scan()
            time.sleep(.05)
            self.assertTrue(self.manager.thread.is_alive())
            self.assertEqual(self.fetcher.urls,[])
            started=time.monotonic();self.assertTrue(self.store.settings())
            self.assertLess(time.monotonic()-started,.3)
        self.assertEqual(self.wait()['state'],'ready')

    def test_background_transfer_yields_and_requested_pause_is_not_an_error(self):
        self.scan()
        with self.store.image_io.foreground(selected=True):
            self.manager.control('start');time.sleep(.05)
            self.assertEqual(self.fetcher.urls,[])
            self.manager.control('pause');state=self.wait()
        self.assertEqual((state['state'],state['failed']),('paused',0),state)
        self.assertEqual(self.fetcher.urls,[])

    @unittest.skipUnless(AVAILABLE,'Optional Pillow JPEG support is unavailable')
    def test_download_prepares_one_derivative_per_exact_original_and_preserves_saved_exports(self):
        state=self.scan({'mirrors':True});self.assertTrue(state['options']['mirrors'])
        self.manager.control('start');state=self.wait();self.assertEqual(state['state'],'completed',state)
        self.assertTrue(state['options']['mirrors'],'A saved true export choice must not be reset by new defaults')
        self.assertEqual(len(list(self.store.image_library.rglob('*.jpg'))),2)
        self.assertTrue(self.store.flush_thumbnails(3))
        self.assertEqual(self.store.thumbnails.status()['generated'],2)
        with self.store.connection()as connection:
            rows=list(connection.execute('SELECT cache_key,width,height FROM '+self.store.image_table('art_thumbnails')))
        self.assertEqual(len(rows),2);self.assertTrue(all(row['width']<=256 and row['height']<=512 for row in rows))
        self.manager.control('resume');self.assertEqual(self.wait()['state'],'completed')
        self.assertTrue(self.store.flush_thumbnails(2));self.assertEqual(self.store.thumbnails.status()['generated'],2)

    @unittest.skipUnless(AVAILABLE,'Optional Pillow JPEG support is unavailable')
    def test_pack_insert_only_import_queues_derivatives_without_replacing_existing_sources(self):
        entries=[]
        for kind in('normal','art_crop'):
            entries.append({'printingId':'printing','oracleId':'oracle','face':0,'kind':kind,'name':'Fixture',
                            'source':'https://cards.scryfall.io/'+kind+'/fixture.jpg','size':len(self.image),
                            'sha256':hashlib.sha256(self.image).hexdigest(),
                            'path':('art-crops/'if kind=='art_crop'else'full-cards/')+'printing-0-'+kind+'.jpg'})
        path=self.root/'pack.zip'
        with zipfile.ZipFile(path,'w')as archive:
            for entry in entries:archive.writestr(entry['path'],self.image)
            archive.writestr('manifest.json',json.dumps({'format':FORMAT,'version':1,'complete':True,'decks':[{'id':'fixture','name':'Fixture'}],'images':entries,'missing':[]}))
        self.packs.inspect(str(path));preview=self.wait(self.packs)
        self.packs.install(preview['jobId']);result=self.wait(self.packs)
        self.assertEqual((result['state'],result['installed']),('completed',2))
        self.assertTrue(self.store.flush_thumbnails(3));self.assertEqual(self.store.thumbnails.status()['generated'],2)
        self.assertEqual(self.store.get_art('printing-0-normal.jpg'),self.image)

    def test_new_managed_and_cli_jobs_default_to_sql_only_without_overriding_explicit_exports(self):
        self.assertFalse(self.scan()['options']['mirrors'])
        captured=[]
        with patch.object(_cli,'Storage',return_value=self.store),patch.object(_cli,'Fetcher',return_value=self.fetcher),patch.object(_cli,'default_cache_dir',return_value=None),patch.object(_cli,'download',side_effect=lambda *args:(captured.append(args[1])or{'failed':0})),redirect_stdout(StringIO()):
            self.assertEqual(_cli.main(['--metadata',str(self.source),'--data-dir',str(self.store.root)]),0)
            self.assertEqual(_cli.main(['--metadata',str(self.source),'--data-dir',str(self.store.root),'--export-mirrors']),0)
            self.assertEqual(_cli.main(['--metadata',str(self.source),'--data-dir',str(self.store.root),'--sql-only','--output',str(self.store.image_library)]),0)
        self.assertEqual(captured,[None,self.store.image_library,None])


if __name__=='__main__':unittest.main()
