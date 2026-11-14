#!/usr/bin/env python3
"""Real temporary filesystem/desktop integration; the app launcher is a fixture."""
from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('linux_installer', HERE / 'installer.py')
installer = importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='love2gathering-installer-test-')
        self.base = Path(self.tmp.name);self.home = self.base / 'home';self.home.mkdir()
        self.env = patch.dict(os.environ, {'HOME': str(self.home), 'XDG_DATA_HOME': str(self.home / 'data'), 'XDG_CONFIG_HOME': str(self.home / 'config')})
        self.env.start()
        self.payload = self.base / 'payload';self.payload.mkdir()
        (self.payload / 'runtime/java/bin').mkdir(parents=True)
        java = self.payload / 'runtime/java/bin/java';java.write_text('#!/bin/sh\nprintf \'openjdk version "21.0.1"\\n\'\n');java.chmod(0o755)
        self.launcher = self.payload / 'love2gathering'
        self.launcher.write_text('#!/bin/sh\nif [ "${1:-}" = "--help" ]; then printf "fixture launcher help\\n"; exit 0; fi\nprintf "%s" "$0" > "$LOVE2GATHERING_INSTALLER_PROBE"\n');self.launcher.chmod(0o755)
        (self.payload / 'share/icons').mkdir(parents=True)
        (self.payload / 'share/icons/love2gathering.png').write_bytes(b'fixture-icon')
        (self.payload / 'version.txt').write_text('one')
        self.prefix = self.base / 'Games with spaces 100% "Arcane" $value' / 'Love2Gathering'
        self.out = io.StringIO()
    def tearDown(self):
        self.env.stop();self.tmp.cleanup()
    def call(self, *args):
        with redirect_stdout(self.out), redirect_stderr(self.out):
            return installer.main(['--prefix', str(self.prefix), '--yes', *args])
    def install(self, *args):
        result = self.call('--payload', str(self.payload), *args)
        self.assertEqual(result, 0, self.out.getvalue())
    def test_selected_path_symlink_menu_and_actual_desktop_launch(self):
        self.install('--desktop-shortcut')
        command = self.home / '.local/bin/love2gathering'
        self.assertTrue(command.is_symlink());self.assertEqual(command.resolve(), self.prefix / 'love2gathering')
        result = subprocess.run([str(command), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0);self.assertIn('fixture launcher help', result.stdout)
        menu = self.home / 'data/applications' / installer.DESKTOP_NAME
        self.assertTrue(menu.is_file());self.assertTrue((self.home / 'Desktop' / installer.DESKTOP_NAME).is_file())
        validate = shutil.which('desktop-file-validate')
        if validate:
            result = subprocess.run([validate, str(menu)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        gio = shutil.which('gio')
        if gio:
            probe = self.base / 'desktop-launched'
            env = dict(os.environ, LOVE2GATHERING_INSTALLER_PROBE=str(probe))
            result = subprocess.run([gio, 'launch', str(menu)], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            import time
            deadline = time.monotonic() + 3
            while not probe.exists() and time.monotonic() < deadline:time.sleep(.01)
            self.assertEqual(probe.read_text(), str(self.prefix / 'love2gathering'))
    def test_update_keeps_user_files_and_replaces_owned_files(self):
        self.install();(self.prefix / 'my-decks').mkdir();saved = self.prefix / 'my-decks/app.sqlite';saved.write_bytes(b'keep all user data')
        (self.payload / 'version.txt').write_text('two');self.install()
        self.assertEqual((self.prefix / 'version.txt').read_text(), 'two');self.assertEqual(saved.read_bytes(), b'keep all user data')
    def test_update_refuses_to_overwrite_changed_app_file(self):
        self.install();(self.prefix / 'version.txt').write_text('user changed this')
        self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertEqual((self.prefix / 'version.txt').read_text(), 'user changed this')
        self.assertTrue((self.prefix / installer.MARKER).is_file())
    def test_uninstall_preserves_all_saves_and_changed_files(self):
        self.install('--desktop-shortcut');(self.prefix / 'custom-note.txt').write_text('keep')
        (self.prefix / 'empty-user-folder').mkdir()
        (self.prefix / 'version.txt').write_text('modified')
        external = self.home / 'data/love2gathering';external.mkdir();(external / 'app.sqlite').write_bytes(b'saves')
        process = subprocess.run([str(self.prefix / 'uninstall.sh'), '--yes'], capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertFalse((self.prefix / 'love2gathering').exists())
        self.assertEqual((self.prefix / 'version.txt').read_text(), 'modified')
        self.assertEqual((self.prefix / 'custom-note.txt').read_text(), 'keep')
        self.assertTrue((self.prefix / 'empty-user-folder').is_dir())
        self.assertEqual((external / 'app.sqlite').read_bytes(), b'saves')
        self.assertFalse((self.home / '.local/bin/love2gathering').is_symlink())
        self.assertFalse((self.home / 'data/applications' / installer.DESKTOP_NAME).exists())
    def test_foreign_folder_command_and_symlink_are_not_replaced(self):
        self.prefix.mkdir(parents=True);foreign = self.prefix / 'keep.txt';foreign.write_text('foreign')
        self.assertEqual(self.call('--payload', str(self.payload)), 1);self.assertEqual(foreign.read_text(), 'foreign')
        shutil.rmtree(self.prefix);target = self.base / 'target';target.mkdir();(target / 'keep').write_text('target')
        self.prefix.symlink_to(target, target_is_directory=True)
        self.assertEqual(self.call('--payload', str(self.payload)), 1);self.assertEqual((target / 'keep').read_text(), 'target')
        self.prefix.unlink();command = self.home / '.local/bin/love2gathering';command.parent.mkdir(parents=True);command.write_text('unrelated')
        self.assertEqual(self.call('--payload', str(self.payload)), 1);self.assertEqual(command.read_text(), 'unrelated')
    def test_archive_payload_installs_without_following_unsafe_members(self):
        archive = self.base / 'release.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:stream.add(self.payload, arcname='Love2Gathering')
        self.assertEqual(self.call('--archive', str(archive)), 0, self.out.getvalue())
        self.assertEqual((self.prefix / 'version.txt').read_text(), 'one')
        bad = self.base / 'unsafe.tar'
        with tarfile.open(bad, 'w') as stream:
            item = tarfile.TarInfo('../outside');item.size = 4;stream.addfile(item, io.BytesIO(b'evil'))
        target = self.base / 'unpack';target.mkdir()
        with self.assertRaises(ValueError):installer.unpack(bad, target)
        self.assertFalse((self.base / 'outside').exists())
    def test_package_symlink_cannot_escape_release(self):
        (self.payload / 'escape').symlink_to('/tmp')
        self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertFalse(self.prefix.exists())
    def test_safe_archive_hard_links_and_installer_lock(self):
        archive = self.base / 'hard-link.tar'
        with tarfile.open(archive, 'w') as stream:
            item = tarfile.TarInfo('original');item.size = 4;stream.addfile(item, io.BytesIO(b'safe'))
            item = tarfile.TarInfo('copy');item.type = tarfile.LNKTYPE;item.linkname = 'original';stream.addfile(item)
        target = self.base / 'hard-links';target.mkdir();installer.unpack(archive, target)
        self.assertEqual((target / 'copy').read_bytes(), b'safe')
        with installer.operation_lock():
            self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertFalse(self.prefix.exists())
    def test_partial_shortcut_failure_rolls_back_app_and_integrations(self):
        self.install();menu = self.home / 'data/applications' / installer.DESKTOP_NAME;original = menu.read_bytes()
        (self.payload / 'version.txt').write_text('two')
        write = installer.write_integrations
        def fail(prefix, paths):
            write(prefix, paths);raise OSError('fixture integration error')
        with patch.object(installer, 'write_integrations', fail):
            self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertEqual(menu.read_bytes(), original);self.assertEqual((self.prefix / 'version.txt').read_text(), 'one')
    def test_shortcut_changed_during_copy_is_preserved(self):
        original = installer.tree_files
        menu = self.home / 'data/applications' / installer.DESKTOP_NAME
        def changed(payload):
            files = original(payload);menu.parent.mkdir(parents=True);menu.write_text('foreign shortcut appeared');return files
        with patch.object(installer, 'tree_files', changed):
            self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertEqual(menu.read_text(), 'foreign shortcut appeared');self.assertFalse(self.prefix.exists())
    def test_tampered_manifest_cannot_delete_files_outside_install(self):
        self.install();outside = self.base / 'outside';outside.write_text('keep')
        marker = self.prefix / installer.MARKER;data = json.loads(marker.read_text());data['files'].append({'path':'../outside','kind':'file','sha256':installer.digest(outside)});marker.write_text(json.dumps(data))
        self.assertEqual(self.call('--uninstall'), 1);self.assertEqual(outside.read_text(), 'keep')
        self.assertTrue((self.prefix / 'love2gathering').exists())
    def test_modified_installer_helper_blocks_update(self):
        self.install();helper = self.prefix / '.installer/installer.py';helper.write_text('custom helper')
        self.assertEqual(self.call('--payload', str(self.payload)), 1)
        self.assertEqual(helper.read_text(), 'custom helper')


if __name__ == '__main__':
    unittest.main(verbosity=2)
