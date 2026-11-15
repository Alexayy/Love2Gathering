from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from paths import default_data_dir, default_cache_dir


class DataPathsTests(unittest.TestCase):
    def test_saved_locations_require_their_existing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);config=root/'config';config.mkdir();database=root/'drive/saves';cache=root/'drive/cache'
            env={'LOVE2GATHERING_CONFIG_DIR':str(config)}
            (config/'storage-paths.json').write_text(json.dumps({'version':1,'active':{'databaseDirectory':str(database),'cacheDirectory':str(cache)}}))
            with self.assertRaisesRegex(ValueError,'Saved database is unavailable'):
                default_data_dir(environ=env)
            self.assertFalse(database.exists())
            database.mkdir(parents=True);(database/'app.sqlite').write_bytes(b'unchanged')
            self.assertEqual(default_data_dir(environ=env),database)
            with self.assertRaisesRegex(ValueError,'Image cache is unavailable'):
                default_cache_dir(database,environ=env)
            self.assertFalse(cache.exists())
            cache.mkdir();(cache/'images.sqlite').write_bytes(b'unchanged')
            self.assertEqual(default_cache_dir(database,environ=env),cache)
            # Explicit new-install overrides remain usable despite an unavailable saved drive.
            explicit={'LOVE2GATHERING_CONFIG_DIR':str(config),'LOVE2GATHERING_DATA_DIR':str(root/'new'),'LOVE2GATHERING_CACHE_DIR':str(root/'new-cache')}
            self.assertEqual(default_data_dir(environ=explicit),root/'new')
            self.assertEqual(default_cache_dir(root/'new',environ=explicit),root/'new-cache')

    def test_missing_persisted_image_store_is_not_recreated(self):
        from storage import Storage
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'saves';cache=Path(tmp)/'cache'
            store=Storage(root,Path(tmp)/'decks',cache_dir=cache)
            (cache/'images.sqlite').unlink()
            with self.assertRaisesRegex(ValueError,'Image cache is unavailable'):
                default_cache_dir(root,{},Path(tmp)/'home',fresh_default=True)
            self.assertFalse((cache/'images.sqlite').exists())

    def test_existing_mounted_copy_is_adopted_without_touching_home(self):
        with tempfile.TemporaryDirectory()as tmp:
            volume=Path(tmp)/'drive';project=volume/'Projects/Love2Gathering';project.mkdir(parents=True)
            copied=volume/'.local/share/love2gathering';copied.mkdir(parents=True);(copied/'app.sqlite').write_bytes(b'unchanged-copy')
            home=Path(tmp)/'home'
            with patch.object(Path,'is_mount',lambda path:path==volume):
                self.assertEqual(default_data_dir(project,{},home),copied)
                self.assertEqual(default_data_dir(project,{'LOVE2GATHERING_DATA_DIR':str(home/'explicit')},home),home/'explicit')
                self.assertEqual(default_data_dir(project,{'XDG_DATA_HOME':str(home/'xdg')},home),home/'xdg/love2gathering')
            self.assertFalse(home.exists());self.assertEqual((copied/'app.sqlite').read_bytes(),b'unchanged-copy')

    def test_incomplete_or_unmounted_copy_does_not_shadow_standard_saves(self):
        with tempfile.TemporaryDirectory()as tmp:
            volume=Path(tmp)/'drive';project=volume/'Projects/Love2Gathering';project.mkdir(parents=True);home=Path(tmp)/'home'
            copied=volume/'.local/share/love2gathering';copied.mkdir(parents=True)
            with patch.object(Path,'is_mount',lambda path:path==volume):
                self.assertEqual(default_data_dir(project,{},home),home/'.local/share/love2gathering')
            (copied/'app.sqlite').write_bytes(b'copy')
            with patch.object(Path,'is_mount',lambda path:False):
                self.assertEqual(default_data_dir(project,{},home),home/'.local/share/love2gathering')

    def test_fresh_launcher_cache_stays_separate_after_reopening(self):
        from storage import Storage
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp)/'saves';home=Path(tmp)/'home'
            selected=default_cache_dir(root,{},home,fresh_default=True)
            self.assertEqual(selected,root/'cache')
            store=Storage(root,Path(tmp)/'decks',cache_dir=selected)
            store.save_art('fresh-0-art_crop.jpg',b'\xff\xd8image\xff\xd9',{'kind':'art_crop'})
            self.assertEqual(default_cache_dir(root,{},home,fresh_default=True),selected)
            reopened=Storage(root,Path(tmp)/'decks')
            self.assertTrue(reopened.separate_cache);self.assertEqual(reopened.get_art('fresh-0-art_crop.jpg'),b'\xff\xd8image\xff\xd9')
            with reopened.connection()as c:self.assertIsNone(c.execute("SELECT 1 FROM main.sqlite_master WHERE name='art_cache'").fetchone())
            self.assertFalse(home.exists())
