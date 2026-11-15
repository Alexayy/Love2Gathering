import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from maintenance import StorageMaintenance, operation_lock
from storage import Storage, ConflictError


class MaintenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        self.data=self.root/'data'
        self.bundle=self.root/'bundled'
        self.bundle.mkdir()
        self.store=Storage(self.data,self.bundle)
        self.image=b'\xff\xd8'+b'cached-jpeg'*100+b'\xff\xd9'
        self.store.save_deck({'id':'mine','name':'Preserved deck','format':'Modern','main':[{'name':'Forest','count':20}],'commander':[],'sideboard':[]})
        self.store.save_settings({'musicVolume':.2})
        self.store.save_ui_layout({'keep':'layout'})

    def tearDown(self):
        self.temp.cleanup()

    def mirror(self,key,data=None):
        folder='art-crops'if key.endswith('-art_crop.jpg')else'full-cards'
        path=self.data/'image-library'/folder/key
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(self.image if data is None else data)
        return path

    def art(self,key,data=None):
        self.store.save_art(key,self.image if data is None else data,{'printingId':'printing','oracleId':'oracle','face':0,'kind':'art_crop'if key.endswith('-art_crop.jpg')else'normal'})

    def replay(self,identifier,status='completed'):
        metadata={'id':identifier,'title':'Native match','format':'Modern','metadata':{'perspectivePlayerId':'human','players':[{'id':'human','name':'You','deck':{'name':'Forest deck'}},{'id':'bot','name':'Bot','deck':{'name':'Bot deck'}}]}}
        self.store.create_replay(metadata)
        frame={'gameId':identifier,'running':False,'players':[{'id':'human','name':'You','human':True,'won':True,'lost':False,'hand':[{'name':'PRIVATE'}]},{'id':'bot','name':'Bot','won':False,'lost':True}]}
        self.store.append_replay_events(identifier,[{'sequence':0,'type':'frame','data':frame}])
        if status!='recording':self.store.finish_replay(identifier,{'status':status,'result':{'completed':True,'perspectivePlayerId':'human','players':frame['players']}})
        return metadata

    def outbox(self,rows):
        with sqlite3.connect(self.data/'replay-outbox.sqlite')as c:
            c.execute('CREATE TABLE replay_outbox(id TEXT PRIMARY KEY,status TEXT,owner_pid INTEGER,finish TEXT)')
            c.execute('CREATE TABLE replay_outbox_events(replay_id TEXT,sequence INTEGER,payload TEXT)')
            for identifier,status,pid,pending in rows:
                c.execute('INSERT INTO replay_outbox VALUES (?,?,?,?)',(identifier,status,pid,json.dumps({'status':status})))
                if pending:c.execute('INSERT INTO replay_outbox_events VALUES (?,0,?)',(identifier,'pending'))

    def test_stats_count_images_exports_and_estimated_duplicate_candidates(self):
        self.art('printing-0-normal.jpg');self.art('printing-0-art_crop.jpg')
        self.mirror('printing-0-normal.jpg')
        self.mirror('printing-0-art_crop.jpg',b'x'*len(self.image))
        self.mirror('uncached-0-normal.jpg')
        self.replay('closed');self.replay('running','recording')
        stats=self.store.maintenance_stats()
        self.assertEqual(stats['full_cards']['count'],1)
        self.assertEqual(stats['art_crops']['count'],1)
        self.assertEqual(stats['full_cards']['mirrorCount'],2)
        self.assertEqual(stats['export_duplicates'],{'count':2,'bytes':len(self.image)*2,'estimated':True})
        self.assertEqual((stats['replays']['count'],stats['replays']['protectedCount']),(1,1))
        self.assertGreater(stats['database']['bytes'],0)

    def test_duplicate_purge_verifies_bytes_keeps_sql_and_unmatched_exports(self):
        self.art('printing-0-normal.jpg');good=self.mirror('printing-0-normal.jpg')
        self.art('different-0-normal.jpg');different=self.mirror('different-0-normal.jpg',b'x'*len(self.image))
        unmatched=self.mirror('unmatched-0-art_crop.jpg')
        result=self.store.purge_storage(['export_duplicates'])
        self.assertFalse(good.exists());self.assertTrue(different.exists());self.assertTrue(unmatched.exists())
        self.assertEqual((result['deletedImages'],result['deletedMirrors'],result['retainedMirrors']),(0,1,2))
        self.assertEqual(self.store.get_art('printing-0-normal.jpg'),self.image)
        with self.store.connection()as c:self.assertEqual(c.execute("SELECT value FROM meta WHERE key='art_purge_generation'").fetchone()[0],'0')

    def test_scoped_image_purge_keeps_user_data_other_kind_and_legacy_backups(self):
        self.art('printing-0-normal.jpg');self.art('printing-0-art_crop.jpg')
        scan=self.mirror('printing-0-normal.jpg');crop=self.mirror('printing-0-art_crop.jpg')
        legacy=self.data/'art'/'old-0-normal.jpg';legacy.parent.mkdir();legacy.write_bytes(self.image)
        result=self.store.purge_storage(['full_cards'])
        self.assertEqual(result['deletedImages'],1);self.assertFalse(scan.exists());self.assertTrue(crop.exists());self.assertTrue(legacy.exists())
        self.assertIsNone(self.store.get_art('printing-0-normal.jpg'))
        self.assertIsNone(self.store.get_art('old-0-normal.jpg'))
        self.assertEqual(self.store.get_art('printing-0-art_crop.jpg'),self.image)
        restarted=Storage(self.data,self.bundle)
        self.assertIsNone(restarted.get_art('old-0-normal.jpg'))
        self.assertEqual(restarted.get_deck('mine')['name'],'Preserved deck')
        self.assertEqual(restarted.settings()['musicVolume'],.2);self.assertEqual(restarted.ui_layout(),{'keep':'layout'})
        with restarted.connection()as c:self.assertEqual(c.execute("SELECT value FROM meta WHERE key='art_purge_generation'").fetchone()[0],'1')
        # A deliberate later download can refill SQL even after old mirror import is disabled.
        restarted.save_art('printing-0-normal.jpg',self.image)
        self.assertEqual(restarted.get_art('printing-0-normal.jpg'),self.image)

    def test_both_image_categories_increment_generation_once_and_rollback_is_atomic(self):
        self.art('printing-0-normal.jpg');self.art('printing-0-art_crop.jpg');self.replay('closed')
        with patch.object(self.store,'_archive_and_delete_replays',side_effect=RuntimeError('fixture failure')):
            with self.assertRaises(RuntimeError):self.store.purge_storage(['full_cards','replays'])
        self.assertEqual(self.store.get_art('printing-0-normal.jpg'),self.image)
        self.assertIsNotNone(self.store.get_replay('closed'))
        self.store.purge_storage(['full_cards','art_crops'])
        with self.store.connection()as c:self.assertEqual(c.execute("SELECT value FROM meta WHERE key='art_purge_generation'").fetchone()[0],'1')

    def test_art_crop_purge_uses_literal_kind_suffix(self):
        self.art('printing-0-art_crop.jpg');self.art('printing-0-artXcrop.jpg')
        result=self.store.purge_storage(['art_crops'])
        self.assertEqual(result['deletedImages'],1)
        self.assertIsNone(self.store.get_art('printing-0-art_crop.jpg'))
        self.assertEqual(self.store.get_art('printing-0-artXcrop.jpg'),self.image)

    def test_replay_purge_preserves_native_history_and_blocks_stale_recreation(self):
        metadata=self.replay('closed');self.replay('aborted','aborted');self.replay('running','recording')
        original=self.store.history()['matches'];own=next(x for x in original if x['id']=='closed')
        result=self.store.purge_storage(['replays'])
        self.assertEqual(result['deletedReplays'],2);self.assertEqual(self.store.list_replays()['total'],1)
        history={x['id']:x for x in self.store.history()['matches']}
        self.assertEqual(history['closed']['outcome'],'win');self.assertEqual(history['closed']['deck'],own['deck'])
        self.assertFalse(history['closed']['replayAvailable']);self.assertNotIn('PRIVATE',json.dumps(history))
        self.assertEqual(history['aborted']['outcome'],'aborted');self.assertTrue(history['running']['replayAvailable'])
        with self.assertRaises(ConflictError):self.store.create_replay(metadata)
        restarted=Storage(self.data,self.bundle)
        self.assertEqual(restarted.history()['total'],3)
        with self.assertRaises(ConflictError):restarted.delete_replay('running')

    def test_native_outbox_pending_unfinished_are_preserved_even_for_terminal_rows(self):
        for identifier in ('safe','pending','unfinished','owned'):self.replay(identifier)
        self.outbox([('safe','completed',0,False),('pending','completed',0,True),('unfinished','recording',0,False),('owned','completed',os.getpid(),False)])
        result=self.store.purge_storage(['replays'])
        self.assertEqual(result['deletedReplays'],2)
        self.assertEqual({x['id']for x in self.store.list_replays()['replays']},{'pending','unfinished'})
        with self.assertRaises(ConflictError):self.store.delete_replay('pending')
        with self.assertRaises(ConflictError):self.store.compact_storage()

    def test_fully_acknowledged_outbox_row_allows_purge_and_compaction_with_live_engine_pid(self):
        self.replay('complete');self.outbox([('complete','completed',os.getpid(),False)])
        self.assertTrue(self.store.maintenance_stats()['database']['canCompact'])
        self.assertEqual(self.store.purge_storage(['replays'])['deletedReplays'],1)
        self.assertTrue(self.store.compact_storage()['databaseCompacted'])

    def test_active_download_and_cross_process_maintenance_locks_refuse_purge(self):
        self.art('printing-0-normal.jpg')
        with operation_lock(self.data,exclusive=True,blocking=False,filename='.image-download.lock'):
            with self.assertRaises(ConflictError):self.store.purge_storage(['full_cards'])
        with operation_lock(self.data,exclusive=True,blocking=False):
            with self.assertRaises(ConflictError):self.store.get_art('printing-0-normal.jpg')
        self.assertEqual(self.store.get_art('printing-0-normal.jpg'),self.image)

    def test_duplicate_cleanup_allows_sql_readers_and_excludes_destructive_operation(self):
        self.art('printing-0-normal.jpg');self.mirror('printing-0-normal.jpg')
        seen=[]
        def progress(_):
            seen.append(self.store.get_art('printing-0-normal.jpg'))
            with self.assertRaises(ConflictError):
                with operation_lock(self.data,exclusive=True,blocking=False):pass
        self.store.purge_storage(['export_duplicates'],progress)
        self.assertTrue(seen);self.assertEqual(seen[0],self.image)

    def test_regular_sql_connections_keep_concurrent_reader_support(self):
        entered=threading.Event();release=threading.Event();second=threading.Event()
        def first():
            with self.store.connection()as c:
                c.execute('SELECT count(*)FROM settings').fetchone();entered.set();release.wait(2)
        def other():
            self.store.settings();second.set()
        a=threading.Thread(target=first);a.start();self.assertTrue(entered.wait(1))
        b=threading.Thread(target=other);b.start()
        try:self.assertTrue(second.wait(.5),'A reader must not wait for another reader\'s Python lock')
        finally:release.set();a.join();b.join()

    def test_symlinks_and_files_outside_managed_exports_are_never_removed(self):
        outside=self.root/'outside.jpg';outside.write_bytes(self.image)
        folder=self.data/'image-library'/'full-cards';folder.mkdir(parents=True)
        (folder/'link-0-normal.jpg').symlink_to(outside)
        (folder/'notes.txt').write_text('preserve')
        self.art('link-0-normal.jpg')
        result=self.store.purge_storage(['full_cards'])
        self.assertEqual(result['deletedMirrors'],0)
        self.assertEqual(outside.read_bytes(),self.image);self.assertTrue((folder/'link-0-normal.jpg').is_symlink())
        self.assertEqual((folder/'notes.txt').read_text(),'preserve')

    def test_compact_reclaims_actual_sqlite_file_space_and_keeps_remaining_data(self):
        payload=b'\xff\xd8'+b'x'*(1024*1024)+b'\xff\xd9'
        for index in range(4):self.art(f'large-{index}-0-normal.jpg',payload)
        self.art('keep-0-art_crop.jpg');self.replay('closed')
        self.store.purge_storage(['full_cards'])
        stats=self.store.maintenance_stats()['database']
        self.assertGreater(stats['reusableBytes'],2*1024*1024)
        result=self.store.compact_storage()
        self.assertGreater(result['bytesFreed'],2*1024*1024)
        self.assertEqual(self.store.get_art('keep-0-art_crop.jpg'),self.image)
        self.assertEqual(self.store.get_deck('mine')['name'],'Preserved deck')
        self.assertEqual(self.store.history()['total'],1)
        with self.store.connection()as c:self.assertEqual(c.execute('PRAGMA integrity_check').fetchone()[0],'ok')

    def test_compact_reserve_validation_and_background_status_remain_nonblocking(self):
        with patch('maintenance.shutil.disk_usage',return_value=type('Usage',(),{'free':1})()):
            with self.assertRaises(ConflictError):self.store.compact_storage()
        manager=StorageMaintenance(self.store);entered=threading.Event();release=threading.Event()
        def slow(progress):
            entered.set();release.wait(3);return {'bytesFreed':0,'message':'done'}
        with patch.object(self.store,'compact_storage',side_effect=slow):
            initial=manager.start_compact();self.assertTrue(entered.wait(1))
            started=time.monotonic();state=manager.status();self.assertLess(time.monotonic()-started,.1)
            self.assertEqual(state['operation']['state'],'running')
            with self.assertRaises(ConflictError):manager.start_compact()
            release.set()
            for _ in range(100):
                if manager.status()['operation']['state']=='completed':break
                time.sleep(.01)
            self.assertEqual(manager.status()['operation']['state'],'completed')
        manager.close()
        with self.assertRaises(ConflictError):manager.start_compact()

    def test_cached_usage_never_rescans_from_navbar_time_or_polling(self):
        manager=StorageMaintenance(self.store)
        cached=self.store.maintenance_stats()
        manager.stats=cached;manager.stats_at=1
        with patch('maintenance.time.monotonic',return_value=10**9),patch.object(self.store,'maintenance_stats',return_value=cached)as scan:
            for _ in range(10):
                state=manager.status()
                self.assertEqual(state['stats'],cached)
                self.assertFalse(state['scanning'])
            scan.assert_not_called()
            manager.status(refresh=True)
            deadline=time.time()+2
            while manager.status()['scanning']and time.time()<deadline:time.sleep(.005)
            self.assertFalse(manager.status()['scanning'])
            scan.assert_called_once()
        manager.close()

    def test_invalid_categories_never_delete_any_data(self):
        self.art('printing-0-normal.jpg');manager=StorageMaintenance(self.store)
        for invalid in (None,[],['unknown'],['full_cards','full_cards'],[{}],['full_cards',True]):
            with self.subTest(value=invalid),self.assertRaises(ValueError):self.store.purge_storage(invalid)
            with self.subTest(manager=invalid),self.assertRaises(ValueError):manager.start_purge(invalid)
        self.assertEqual(self.store.get_art('printing-0-normal.jpg'),self.image)
        manager.close()

    def test_shutdown_terminates_owned_vacuum_child_and_leaves_database_usable(self):
        manager=StorageMaintenance(self.store);original=subprocess.Popen;processes=[]
        def sleeping_child(*args,**kwargs):
            child=original([sys.executable,'-c','import time;time.sleep(30)'],**kwargs);processes.append(child);return child
        with patch('maintenance.subprocess.Popen',side_effect=sleeping_child):
            manager.start_compact()
            for _ in range(100):
                if processes:break
                time.sleep(.01)
            self.assertTrue(processes)
            started=time.monotonic();manager.close();self.assertLess(time.monotonic()-started,3)
        self.assertIsNotNone(processes[0].poll())
        self.assertEqual(self.store.get_deck('mine')['name'],'Preserved deck')
        with self.store.connection()as c:self.assertEqual(c.execute('PRAGMA integrity_check').fetchone()[0],'ok')


if __name__=='__main__':unittest.main()
