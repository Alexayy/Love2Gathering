from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from paths import default_data_dir


class DataPathsTests(unittest.TestCase):
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
