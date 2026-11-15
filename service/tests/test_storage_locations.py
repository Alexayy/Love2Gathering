"""True separate image SQL and restart-safe copies; never user directories."""
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from storage import Storage,ConflictError
from storage_locations import StorageLocations,activate_pending,_atomic_json
from paths import default_data_dir,default_cache_dir,config_file,read_config
from maintenance import operation_lock

JPEG=b'\xff\xd8'+b'x'*(2*1024*1024)+b'\xff\xd9'


class StorageLocationsTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.env={'LOVE2GATHERING_CONFIG_DIR':str(self.root/'config')}
        self.storage=Storage(self.root/'old',self.root/'bundled')
        self.storage.save_settings({'sfxVolume':.35})
        self.storage.save_art('printing-0-normal.jpg',JPEG,{'oracleId':'oracle','printingId':'printing','face':0,'kind':'normal'})
        self.manager=StorageLocations(self.storage,environ=self.env,home=self.root/'home')
        self.body={'databaseDirectory':str(self.root/'new'),'cacheDirectory':str(self.root/'cache')}
    def tearDown(self):self.manager.close();self.storage.close_images();self.tmp.cleanup()
    def ready(self,state='prepared'):
        self.manager.worker.join(timeout=10);value=self.manager.status()
        self.assertEqual(value['operation']['state'],state,value)
        return value
    def prepare(self,body=None):self.manager.prepare(body or self.body);return self.ready()

    def test_legacy_split_preserves_original_settings_and_exact_blobs(self):
        result=self.prepare();self.assertTrue(result['restartRequired'])
        with self.assertRaises(ConflictError):self.storage.settings()
        with sqlite3.connect(self.storage.database)as original:self.assertEqual(original.execute('SELECT content FROM art_cache').fetchone()[0],JPEG)
        self.assertTrue(activate_pending(self.env,self.root/'home'))
        self.assertEqual(default_data_dir(environ=self.env,home=self.root/'home'),self.root/'new')
        self.assertEqual(default_cache_dir(self.root/'new',self.env,self.root/'home'),self.root/'cache')
        active=Storage(self.root/'new',self.root/'bundled',self.root/'cache')
        self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG);self.assertEqual(active.settings()['sfxVolume'],.35)
        with sqlite3.connect(active.database)as c:self.assertIsNone(c.execute("SELECT name FROM sqlite_master WHERE name='art_cache'").fetchone())
        with sqlite3.connect(active.cache_database)as c:self.assertEqual(c.execute('SELECT count(*)FROM art_cache').fetchone()[0],1)
        self.assertLess(active.database.stat().st_size,self.storage.database.stat().st_size)
        self.assertFalse(self.manager.status()['restartRequired'])

    def test_split_drops_disposable_image_tables_from_prepared_application_database(self):
        from thumbnails import AVAILABLE,VERSION,jpeg_thumbnail
        if not AVAILABLE:self.skipTest('Pillow JPEG codec unavailable')
        from PIL import Image
        from io import BytesIO
        import hashlib
        # Keep this fixture deterministic; no worker can race the prepared copy.
        self.storage.close_images()
        output=BytesIO();Image.new('RGB',(488,680),(90,120,70)).save(output,'JPEG')
        original=output.getvalue();small,width,height=jpeg_thumbnail(original)
        key='printing-0-normal.jpg';digest=hashlib.sha256(original).hexdigest()
        self.storage.save_art(key,original,{'oracleId':'oracle','printingId':'printing','face':0,'kind':'normal'})
        with self.storage.connection(write=True)as c:
            c.execute('INSERT OR REPLACE INTO art_thumbnails VALUES(?,?,?,?,?,?,?)',(key,digest,VERSION,width,height,'{}',small))
        self.prepare()
        pending=read_config(self.env,self.root/'home')['pending']
        with sqlite3.connect(pending['preparedDatabase'])as copied:
            tables={r[0]for r in copied.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            self.assertFalse({'art_cache','art_sources','art_thumbnails'}&tables)
        with sqlite3.connect(self.storage.database)as backup:
            self.assertEqual(backup.execute('SELECT content FROM art_cache WHERE cache_key=?',(key,)).fetchone()[0],original)
            self.assertEqual(backup.execute('SELECT content FROM art_thumbnails WHERE cache_key=?',(key,)).fetchone()[0],small)
        with sqlite3.connect(pending['preparedCache'])as cached:
            self.assertEqual(cached.execute('SELECT content FROM art_cache WHERE cache_key=?',(key,)).fetchone()[0],original)
        activate_pending(self.env,self.root/'home')
        active=Storage(self.root/'new',self.root/'bundled',self.root/'cache')
        try:
            active.enable_thumbnails();active.queue_thumbnail(key);self.assertTrue(active.flush_thumbnails(5))
            with active.connection()as c:self.assertEqual(c.execute('SELECT count(*) FROM images.art_thumbnails').fetchone()[0],1)
        finally:active.close_images()

    def test_same_data_directory_keeps_before_backup_and_fences_other_catalogs(self):
        other=Storage(self.storage.root,self.root/'bundled')
        body=dict(self.body,databaseDirectory=str(self.storage.root))
        self.prepare(body);activate_pending(self.env,self.root/'home')
        backups=list(self.storage.root.glob('app.sqlite.before-*'));self.assertEqual(len(backups),1)
        with sqlite3.connect(backups[0])as original:self.assertEqual(original.execute('SELECT content FROM art_cache').fetchone()[0],JPEG)
        with self.assertRaises(ConflictError):other.save_settings({'sfxVolume':.9})
        active=Storage(self.storage.root,self.root/'bundled',self.root/'cache');self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG)

    def test_separate_cache_can_move_independently_and_reuse_unchanged_cache(self):
        self.prepare();activate_pending(self.env,self.root/'home')
        first=Storage(self.root/'new',self.root/'bundled',self.root/'cache')
        second_manager=StorageLocations(first,environ=self.env,home=self.root/'home')
        try:
            second_manager.prepare({'databaseDirectory':str(self.root/'newer'),'cacheDirectory':str(self.root/'cache')});second_manager.worker.join(10)
            self.assertEqual(second_manager.status()['operation']['state'],'prepared')
            pending=read_config(self.env,self.root/'home')['pending'];self.assertIsNone(pending['preparedCache'])
            activate_pending(self.env,self.root/'home')
            active=Storage(self.root/'newer',self.root/'bundled',self.root/'cache');self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG)
        finally:second_manager.close()

    def test_active_recording_and_pending_outbox_are_not_movable(self):
        self.storage.create_replay({'id':'active','name':'test'})
        with self.assertRaises(ConflictError):self.manager.prepare(self.body)
        self.storage.finish_replay('active',{'status':'aborted'})
        with sqlite3.connect(self.storage.root/'replay-outbox.sqlite')as c:
            c.executescript("CREATE TABLE replay_outbox(id TEXT,status TEXT,owner_pid INTEGER,finish TEXT);CREATE TABLE replay_outbox_events(replay_id TEXT);INSERT INTO replay_outbox VALUES('pending','completed',999999,'{}');INSERT INTO replay_outbox_events VALUES('pending')")
        with self.assertRaises(ConflictError):self.manager.prepare(self.body)
        self.assertFalse(config_file(self.env,self.root/'home').exists())

    def test_destination_existing_sql_and_environment_override_are_rejected(self):
        target=Path(self.body['databaseDirectory']);target.mkdir();(target/'app.sqlite').write_bytes(b'keep')
        with self.assertRaises(ValueError):self.manager.validate(self.body)
        self.assertEqual((target/'app.sqlite').read_bytes(),b'keep')
        override=StorageLocations(self.storage,environ=dict(self.env,LOVE2GATHERING_DATA_DIR=str(self.storage.root)),home=self.root/'home')
        with self.assertRaises(ValueError):override.validate(dict(self.body,databaseDirectory=str(self.root/'other')))
        generated=StorageLocations(self.storage,environ=dict(self.env,LOVE2GATHERING_DATA_DIR=str(self.storage.root),LOVE2GATHERING_DATA_DIR_EXPLICIT='0',LOVE2GATHERING_STORAGE_RESOLVED='1'),home=self.root/'home')
        self.assertTrue(generated.validate(dict(self.body,databaseDirectory=str(self.root/'other')))['valid'])
        forced=StorageLocations(self.storage,environ=dict(generated.env,LOVE2GATHERING_DATA_DIR_EXPLICIT='1'),home=self.root/'home')
        with self.assertRaises(ValueError):forced.validate(dict(self.body,databaseDirectory=str(self.root/'other')))

    def test_cancel_during_copy_keeps_original_writable_and_no_pending_config(self):
        entered=threading.Event()
        def slow_copy(source,destination,check,update=None):
            entered.set()
            while True:check();time.sleep(.01)
        with patch('storage_locations._backup',slow_copy):
            self.manager.prepare(self.body);self.assertTrue(entered.wait(2));self.manager.close();self.ready('cancelled')
        self.storage.save_settings({'sfxVolume':.4});self.assertEqual(self.storage.settings()['sfxVolume'],.4)
        self.assertFalse(read_config(self.env,self.root/'home').get('pending'))

    def test_download_lock_rejects_preparation_without_retiring_source(self):
        with operation_lock(self.storage.root,exclusive=True,filename='.image-download.lock'):
            self.manager.prepare(self.body);self.ready('error')
        self.assertEqual(self.storage.get_art('printing-0-normal.jpg'),JPEG)
        self.assertFalse(read_config(self.env,self.root/'home').get('pending'))

    def test_crash_before_retirement_never_activates_stale_snapshot(self):
        staging=self.root/'new/.love2gathering-relocate-incomplete';staging.mkdir(parents=True);(staging/'app.sqlite').write_bytes(b'stale')
        config={'version':1,'pending':{'id':'unretired','sourceDirectory':str(self.storage.root),**self.body,'preparedDatabase':str(staging/'app.sqlite'),'stagingDirectories':[str(staging)]}}
        _atomic_json(config_file(self.env,self.root/'home'),config)
        self.assertFalse(activate_pending(self.env,self.root/'home'));self.assertFalse((self.root/'new/app.sqlite').exists())
        self.assertEqual(self.storage.get_art('printing-0-normal.jpg'),JPEG)

    def test_crash_during_activation_resumes_after_cache_install(self):
        self.prepare()
        import storage_locations
        original=storage_locations._move_preserving_original;calls=[]
        def interrupt(prepared,target,job,**options):
            calls.append(str(target))
            if len(calls)==2:raise RuntimeError('simulated launcher exit')
            return original(prepared,target,job,**options)
        with patch('storage_locations._move_preserving_original',interrupt):
            with self.assertRaises(RuntimeError):activate_pending(self.env,self.root/'home')
        self.assertTrue(activate_pending(self.env,self.root/'home'))
        active=Storage(self.root/'new',self.root/'bundled',self.root/'cache');self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG)

    def test_live_old_engine_requires_matching_relocation_protocol_proof(self):
        from storage_locations import _process_started_ms
        outbox=self.storage.root/'replay-outbox.sqlite'
        with sqlite3.connect(outbox)as c:
            c.executescript("CREATE TABLE replay_outbox(id TEXT,status TEXT,owner_pid INTEGER,finish TEXT);CREATE TABLE replay_outbox_events(replay_id TEXT,sequence INTEGER);CREATE TABLE replay_outbox_control(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
            c.execute("INSERT INTO replay_outbox VALUES('done','completed',?,'{}')",(os.getpid(),))
        with self.assertRaisesRegex(ConflictError,'older running'):self.manager.prepare(self.body)
        with sqlite3.connect(outbox)as c:
            c.execute("INSERT INTO replay_outbox_control VALUES(?,?)",('owner_protocol:'+str(os.getpid()),'1'))
            c.execute("INSERT INTO replay_outbox_control VALUES(?,?)",('owner_started:'+str(os.getpid()),str(_process_started_ms(os.getpid())-10000)))
        with self.assertRaisesRegex(ConflictError,'older running'):self.manager.prepare(self.body)
        with sqlite3.connect(outbox)as c:c.execute('UPDATE replay_outbox_control SET value=? WHERE key=?',(str(_process_started_ms(os.getpid())),'owner_started:'+str(os.getpid())))
        self.prepare();activate_pending(self.env,self.root/'home')
        active=Storage(self.root/'new',self.root/'bundled',self.root/'cache');self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG)
        with sqlite3.connect(active.root/'replay-outbox.sqlite')as c:self.assertEqual(c.execute('SELECT id FROM replay_outbox').fetchone()[0],'done')

    def test_cancel_prepared_copy_restores_original_and_removes_only_staging(self):
        self.prepare();pending=read_config(self.env,self.root/'home')['pending']
        result=self.manager.cancel();self.assertFalse(result['restartRequired'])
        self.assertEqual(result['operation']['state'],'cancelled')
        self.storage.save_settings({'sfxVolume':.8});self.assertEqual(self.storage.get_art('printing-0-normal.jpg'),JPEG)
        self.assertTrue(self.storage.database.exists())
        self.assertTrue(all(not Path(folder).exists()for folder in pending['stagingDirectories']))
        with sqlite3.connect(self.storage.root/'replay-outbox.sqlite')as c:self.assertIsNone(c.execute("SELECT 1 FROM replay_outbox_control WHERE key='relocated'").fetchone())

    def test_late_uncooperative_outbox_writer_cancels_activation_without_losing_row(self):
        self.prepare()
        with sqlite3.connect(self.storage.root/'replay-outbox.sqlite')as c:
            c.executescript("CREATE TABLE replay_outbox(id TEXT,status TEXT,owner_pid INTEGER,finish TEXT);CREATE TABLE replay_outbox_events(replay_id TEXT,sequence INTEGER);INSERT INTO replay_outbox VALUES('late','recording',999999,NULL)")
        self.assertFalse(activate_pending(self.env,self.root/'home'))
        self.assertFalse(read_config(self.env,self.root/'home').get('pending'))
        with sqlite3.connect(self.storage.database)as c:self.assertIsNone(c.execute("SELECT 1 FROM meta WHERE key='storage_relocated_to'").fetchone())
        with sqlite3.connect(self.storage.root/'replay-outbox.sqlite')as c:self.assertEqual(c.execute('SELECT id FROM replay_outbox').fetchone()[0],'late')
        self.assertFalse((self.root/'new/app.sqlite').exists())

    def test_late_foreign_destination_is_never_overwritten_or_renamed(self):
        for index,kind in enumerate(('database','cache')):
            with self.subTest(kind=kind):
                body={'databaseDirectory':str(self.root/('new'+str(index))),'cacheDirectory':str(self.root/('cache'+str(index)))}
                self.prepare(body)
                target=Path(body['databaseDirectory'])/'app.sqlite'if kind=='database'else Path(body['cacheDirectory'])/'images.sqlite'
                with sqlite3.connect(target)as foreign:foreign.execute('CREATE TABLE foreign_data(value TEXT)');foreign.execute("INSERT INTO foreign_data VALUES('keep')")
                self.assertFalse(activate_pending(self.env,self.root/'home'))
                with sqlite3.connect(target)as foreign:self.assertEqual(foreign.execute('SELECT value FROM foreign_data').fetchone()[0],'keep')
                self.assertFalse(list(target.parent.glob(target.name+'.before-*')))
                self.assertEqual(self.storage.get_art('printing-0-normal.jpg'),JPEG)

    def test_partial_activation_requires_exact_installed_job_identity(self):
        import storage_locations
        self.prepare();pending=read_config(self.env,self.root/'home')['pending']
        storage_locations._move_preserving_original(pending['preparedCache'],self.root/'cache/images.sqlite',pending['id'])
        Path(pending['preparedDatabase']).unlink()
        with sqlite3.connect(self.root/'new/app.sqlite')as foreign:foreign.execute('CREATE TABLE foreign_data(value TEXT)');foreign.execute("INSERT INTO foreign_data VALUES('keep')")
        config=read_config(self.env,self.root/'home');config['pending']['activationStarted']=True;_atomic_json(config_file(self.env,self.root/'home'),config)
        with self.assertRaises(ConflictError):activate_pending(self.env,self.root/'home')
        self.assertNotIn('active',read_config(self.env,self.root/'home'))
        with sqlite3.connect(self.root/'new/app.sqlite')as foreign:self.assertEqual(foreign.execute('SELECT value FROM foreign_data').fetchone()[0],'keep')
        with sqlite3.connect(self.storage.database)as original:self.assertEqual(original.execute('SELECT content FROM art_cache').fetchone()[0],JPEG)

    def test_interrupted_no_replace_link_finishes_only_its_matching_copy(self):
        self.prepare();pending=read_config(self.env,self.root/'home')['pending']
        os.link(pending['preparedCache'],self.root/'cache/images.sqlite')
        self.assertTrue(activate_pending(self.env,self.root/'home'))
        active=Storage(self.root/'new',self.root/'bundled',self.root/'cache');self.assertEqual(active.get_art('printing-0-normal.jpg'),JPEG)

    def test_foreign_catalog_cannot_cancel_other_store_and_same_store_can(self):
        same=Storage(self.storage.root,self.root/'bundled')
        other=Storage(self.root/'other',self.root/'bundled')
        self.prepare()
        foreign=StorageLocations(other,environ=self.env,home=self.root/'home');status=foreign.status()
        self.assertTrue(status['foreignPending']);self.assertFalse(status['restartRequired']);self.assertIsNone(status['configured'])
        with self.assertRaises(ConflictError):foreign.cancel()
        self.assertTrue(self.manager.status()['restartRequired'])
        StorageLocations(same,environ=self.env,home=self.root/'home').cancel()
        self.assertEqual(self.storage.settings()['sfxVolume'],.35)
        self.assertEqual(self.manager.status()['operation']['state'],'cancelled')

    def test_missing_runtime_or_overridden_cache_never_creates_empty_sql(self):
        active=Storage(self.root/'split',self.root/'bundled',self.root/'external')
        active.save_art('p-0-normal.jpg',JPEG,{})
        with self.assertRaises(ConflictError):Storage(active.root,self.root/'bundled',self.root/'new-empty-cache')
        self.assertFalse((self.root/'new-empty-cache/images.sqlite').exists())
        os.replace(active.cache_database,active.cache_database.with_suffix('.saved'))
        with self.assertRaises(ConflictError):active.get_art('p-0-normal.jpg')
        self.assertFalse(active.cache_database.exists())

    def test_unsupported_atomic_destination_fails_before_retiring_original(self):
        with patch('storage_locations.os.link',side_effect=OSError('not supported')):
            self.manager.prepare(self.body);self.ready('error')
        self.assertEqual(self.storage.get_art('printing-0-normal.jpg'),JPEG)
        self.assertFalse(read_config(self.env,self.root/'home').get('pending'))
        self.storage.save_settings({'sfxVolume':.6})

    def test_external_cache_purge_compaction_and_ownership(self):
        active=Storage(self.root/'separate',self.root/'bundled',self.root/'external')
        active.save_art('crop-0-art_crop.jpg',JPEG,{'kind':'art_crop'})
        active.save_settings({'sfxVolume':.7})
        before=active.cache_database.stat().st_size
        result=active.purge_storage(['art_crops']);self.assertEqual(result['deletedImages'],1)
        result=active.compact_storage();self.assertTrue(result['cacheCompacted'])
        self.assertLess(active.cache_database.stat().st_size,before)
        self.assertEqual(active.settings()['sfxVolume'],.7)
        with self.assertRaises(ValueError):Storage(self.root/'unrelated',self.root/'bundled',self.root/'external')

if __name__=='__main__':unittest.main()
