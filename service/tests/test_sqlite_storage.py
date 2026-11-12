import concurrent.futures
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from storage import Storage,ConflictError

def deck(identifier='mine'):
    return {'id':identifier,'name':'My draft','format':'Modern','description':'Preserve me','coverCard':'Lightning Bolt','draft':True,
            'main':[{'name':'Lightning Bolt','count':4}],'sideboard':[],'commander':[]}

class SQLiteStorageTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.data=self.root/'user';self.bundle=self.root/'bundle'
        self.bundle.mkdir();(self.bundle/'included.json').write_text(json.dumps(deck('included')))
    def tearDown(self):self.temp.cleanup()
    def store(self):return Storage(self.data,self.bundle)

    def test_legacy_migration_is_preserved_atomic_and_never_reimports_stale_files(self):
        (self.data/'decks').mkdir(parents=True)
        original=json.dumps(deck());(self.data/'decks/mine.json').write_text(original)
        (self.data/'decks/bad.json').write_text('{broken')
        settings=json.dumps({'manualTriggers':True,'musicVolume':0.2,'vsync':'invalid'})
        (self.data/'settings.json').write_text(settings)
        (self.data/'hidden-decks.json').write_text(json.dumps(['included','../invalid']))
        s=self.store()
        self.assertEqual([d['id'] for d in s.list_decks()],['mine'])
        self.assertEqual(s.get_deck('mine')['coverCard'],'Lightning Bolt');self.assertTrue(s.get_deck('mine')['draft'])
        self.assertTrue(s.settings()['manualTriggers']);self.assertEqual(s.settings()['musicVolume'],0.2)
        self.assertTrue(s.settings()['vsync']);self.assertGreaterEqual(len(s.health()['migrationIssues']),3)
        changed=deck();changed['name']='SQLite edit';s.save_deck(changed)
        s.save_settings({'manualTriggers':False});s.delete_deck('mine')
        again=self.store();self.assertIsNone(again.get_deck('mine'));self.assertFalse(again.settings()['manualTriggers'])
        self.assertIsNone(again.get_deck('included'))
        self.assertEqual((self.data/'decks/mine.json').read_text(),original)
        self.assertEqual((self.data/'settings.json').read_text(),settings)
        with sqlite3.connect(s.database) as c:
            self.assertEqual(c.execute('PRAGMA journal_mode').fetchone()[0],'wal')
            self.assertEqual(c.execute("SELECT count(*) FROM meta WHERE key='legacy_json_migrated'").fetchone()[0],1)

    def test_new_decks_settings_layout_and_images_write_only_sqlite(self):
        s=self.store();s.save_deck(deck(),validation={'draft':True});s.save_settings({'uiScale':1.2,'showCardArt':False})
        layout={'hand':{'x':0.2,'y':0.8,'w':0.6,'h':0.2},'replayPrefs':{'speed':2}}
        s.save_ui_layout(layout);image=b'\xff\xd8'+b'fake-jpeg-fixture'*20
        s.save_art('printing-0-normal.jpg',image,{'kind':'normal','oracleId':'oracle'})
        again=self.store()
        self.assertEqual(again.get_deck('mine')['draft'],True);self.assertFalse(again.settings()['showCardArt'])
        self.assertEqual(again.ui_layout(),layout);self.assertEqual(again.get_art('printing-0-normal.jpg'),image)
        self.assertFalse((self.data/'decks').exists());self.assertFalse((self.data/'settings.json').exists());self.assertFalse((self.data/'art').exists())
        self.assertEqual(again.database,self.data/'app.sqlite')

    def test_legacy_art_import_is_lazy_and_preserves_the_original(self):
        s=self.store();old=self.data/'art';old.mkdir();data=b'\xff\xd8'+b'legacy-jpeg'*20
        (old/'oracle-0.jpg').write_bytes(data)
        self.assertEqual(s.get_art('printing-0-normal.jpg',('oracle-0.jpg',)),data)
        with sqlite3.connect(s.database) as c:self.assertEqual(c.execute('SELECT count(*) FROM art_cache').fetchone()[0],1)
        self.assertEqual(self.store().get_art('printing-0-normal.jpg'),data);self.assertEqual((old/'oracle-0.jpg').read_bytes(),data)
        with self.assertRaises(ValueError):s.get_art('../escape.jpg')

    def test_all_legacy_jpegs_are_migrated_in_batches_and_originals_preserved(self):
        old=self.data/'art';old.mkdir(parents=True)
        data=b'\xff\xd8'+b'legacy-jpeg'*20
        for index in range(35):(old/f'printing-{index}-0-normal.jpg').write_bytes(data)
        (old/'bad-0-normal.jpg').write_bytes(b'not an image')
        s=self.store()
        with sqlite3.connect(s.database) as c:
            self.assertEqual(c.execute('SELECT count(*) FROM art_cache').fetchone()[0],35)
            self.assertTrue(c.execute("SELECT 1 FROM meta WHERE key='legacy_art_migrated'").fetchone())
        self.assertEqual(len(list(old.glob('*.jpg'))),36)
        self.assertEqual(self.store().get_art('printing-34-0-normal.jpg'),data)

    def test_transport_copy_bound_preserves_legacy_but_rejects_new_oversized_entry(self):
        (self.data/'decks').mkdir(parents=True)
        value=deck();value['main']=[{'name':'Forest','count':300}]
        (self.data/'decks/mine.json').write_text(json.dumps(value))
        s=self.store();self.assertEqual(s.get_deck('mine')['main'][0]['count'],300)
        with self.assertRaises(ValueError):s.save_deck(value)

    def test_multiple_services_migrate_once_and_commit_without_lost_changes(self):
        (self.data/'decks').mkdir(parents=True);(self.data/'decks/mine.json').write_text(json.dumps(deck()))
        def work(index):
            s=self.store();s.save_deck(dict(deck('thread-'+str(index)),name='Thread '+str(index)))
            s.save_settings({'musicVolume':index/10})
            s.save_ui_layout({'thread':index})
            return s.get_deck('thread-'+str(index))['id']
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:results=list(pool.map(work,range(6)))
        self.assertEqual(len(set(results)),6);self.assertEqual(len(self.store().list_decks()),8)
        with sqlite3.connect(self.data/'app.sqlite') as c:self.assertEqual(c.execute('PRAGMA integrity_check').fetchone()[0],'ok')

    def test_replay_events_are_atomic_immutable_idempotent_and_survive_restart(self):
        s=self.store();created=s.create_replay({'id':'recording','title':'Test match','format':'Modern','startedAt':1000})
        self.assertEqual(s.create_replay({'id':'recording','title':'Test match','format':'Modern','startedAt':1000}),created)
        events=[{'sequence':0,'type':'frame','timestamp':1000,'data':{'players':[{'human':True,'hand':[]},{'human':False,'hand':[]}],'turn':1}},
                {'sequence':1,'type':'action','timestamp':1001,'data':{'promptId':4,'type':'uuid','value':'card'}},
                {'sequence':2,'type':'log','timestamp':1002,'data':'Land played'}]
        self.assertEqual(s.append_replay_events('recording',events)['inserted'],3)
        self.assertEqual(s.append_replay_events('recording',events)['inserted'],0)
        conflict=deepcopy(events[0]);conflict['data']['turn']=99
        with self.assertRaises(ConflictError):s.append_replay_events('recording',[{'sequence':3,'type':'error','data':'must roll back'},conflict])
        again=self.store();meta=again.get_replay('recording')
        self.assertEqual((meta['eventCount'],meta['frameCount'],meta['actionCount'],meta['lastSequence']),(3,1,1,2))
        self.assertEqual(again.replay_events('recording',frames_only=True)['frames'],events[:1])
        finished=again.finish_replay('recording',{'status':'failed','error':'Connection interrupted'})
        self.assertEqual(again.finish_replay('recording',{'status':'failed','error':'Connection interrupted'}),finished)
        self.assertEqual(self.store().get_replay('recording')['status'],'failed')
        with self.assertRaises(ConflictError):again.finish_replay('recording',{'status':'completed'})
        with self.assertRaises(ConflictError):again.append_replay_events('recording',[{'sequence':3,'type':'frame','data':{}}])
        self.assertEqual(again.append_replay_events('recording',events)['inserted'],0)
        self.assertEqual(again.list_replays()['total'],1)
        self.assertTrue(again.delete_replay('recording'));self.assertEqual(again.list_replays()['total'],0)
        with sqlite3.connect(s.database) as c:self.assertEqual(c.execute('SELECT count(*) FROM replay_events').fetchone()[0],0)

if __name__=='__main__':unittest.main()
