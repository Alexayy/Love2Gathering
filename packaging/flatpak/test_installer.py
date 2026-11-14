#!/usr/bin/env python3
"""Temporary helper integration; fake Flatpak commands, actual desktop launcher."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('flatpak_installer', HERE / 'install-flatpak.py')
installer = importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)


class FlatpakInstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='love2gathering-flatpak-helper-')
        self.base = Path(self.tmp.name);self.home = self.base / 'home';self.home.mkdir()
        self.binary = self.base / 'bin';self.binary.mkdir();self.ledger = self.base / 'commands.jsonl'
        fake = self.binary / 'flatpak'
        fake.write_text('#!' + sys.executable + '\n' + '''import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['FLATPAK_TEST_LEDGER'],'a')as out:out.write(json.dumps({'args':args,'root':os.environ.get('FLATPAK_USER_DIR')})+'\\n')
action=args[1] if args and args[0]=='--user' and len(args)>1 else args[0] if args else ''
if action==os.environ.get('FLATPAK_TEST_FAIL'):raise SystemExit(2)
root=pathlib.Path(os.environ['FLATPAK_USER_DIR'])
commit=os.environ.get('FLATPAK_TEST_COMMIT','a'*64)
ref=os.environ.get('FLATPAK_TEST_REF','app/io.github.Alexayy.Love2Gathering/x86_64/stable')
origin=os.environ.get('FLATPAK_TEST_ORIGIN','love2gathering-origin')
if action in('remote-add','install'):
 (root/'repo').mkdir(parents=True,exist_ok=True);(root/'repo/config').write_text('fixture repository')
if action=='build-import-bundle':print('Importing '+ref+' ('+commit+')')
if action=='list' and(root/'fixture-app-installed').exists():
 display=ref[4:] if ref.startswith('app/') else ref
 print(display+'\\t'+origin if '--columns=ref,origin'in args else display)
 if os.environ.get('FLATPAK_TEST_SHARED')and'--columns=ref,origin'in args:print('org.example.Other/x86_64/stable\\t'+origin)
if action=='info':print(origin if '--show-origin'in args else(root/'fixture-app-installed').read_text())
if action=='remotes':print(origin+'\\t'+((root/'fixture-origin-url').read_text()if(root/'fixture-origin-url').exists()else os.environ.get('FLATPAK_TEST_ORIGIN_URL','')))
if action=='remote-modify':(root/'fixture-origin-url').write_text(next(value.split('=',1)[1]for value in args if value.startswith('--url=')))
if action in('install','update'):
 if not(action=='update'and os.environ.get('FLATPAK_TEST_IGNORE_UPDATE')):(root/'fixture-app-installed').write_text(commit)
 if os.environ.get('FLATPAK_TEST_LATE_DESKTOP'):
  target=pathlib.Path(os.environ['FLATPAK_TEST_LATE_DESKTOP']);target.parent.mkdir(parents=True,exist_ok=True);target.write_text('foreign appeared')
if action=='run':pathlib.Path(os.environ['FLATPAK_TEST_PROBE']).write_text(json.dumps({'root':str(root),'args':args}))
''');fake.chmod(0o755)
        self.env = patch.dict(os.environ, {'HOME':str(self.home),'XDG_DATA_HOME':str(self.base/'data'),'PATH':str(self.binary)+os.pathsep+os.environ['PATH'],'FLATPAK_TEST_LEDGER':str(self.ledger)})
        self.env.start()
        self.prefix = self.base / 'Games with space 100% "Eye" $name `literal` = slash\\'
        self.bundle = self.base / 'fixture.flatpak';self.bundle.write_bytes(b'fixture')
        self.out = io.StringIO()
    def tearDown(self):self.env.stop();self.tmp.cleanup()
    def call(self, *args):
        with redirect_stdout(self.out):return installer.main([str(self.bundle),'--prefix',str(self.prefix),*args])
    def installed(self):self.assertEqual(self.call(),0);return installer.resources(self.prefix)
    def commands(self):return [json.loads(line)for line in self.ledger.read_text().splitlines()]if self.ledger.exists()else[]
    def reset(self):self.ledger.unlink(missing_ok=True)
    def test_actual_desktop_escaping_and_flatpak_environment(self):
        paths=self.installed();self.assertTrue(paths['link'].is_symlink())
        result=subprocess.run(['desktop-file-validate',str(paths['desktop'])],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        probe=self.base/'launched.json';env=dict(os.environ,FLATPAK_TEST_PROBE=str(probe))
        result=subprocess.run(['gio','launch',str(paths['desktop'])],env=env,capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        import time
        until=time.monotonic()+3
        while not probe.exists()and time.monotonic()<until:time.sleep(.01)
        result=json.loads(probe.read_text());self.assertEqual(result['root'],str(self.prefix));self.assertEqual(result['args'],['--user','run',installer.APP_ID])
    def test_existing_repository_does_not_authorize_overwriting_files(self):
        (self.prefix/'repo').mkdir(parents=True);(self.prefix/'repo/config').write_text('repo')
        for name in('love2gathering','install-flatpak.py'):
            with self.subTest(name=name):
                foreign=self.prefix/name;foreign.write_text('foreign')
                with self.assertRaisesRegex(ValueError,'Refusing to replace'):self.call()
                self.assertEqual(foreign.read_text(),'foreign');foreign.unlink()
        self.assertFalse(self.commands())
    def test_dangling_command_and_desktop_symlink_are_preserved(self):
        paths=installer.resources(self.prefix);paths['link'].parent.mkdir(parents=True);paths['link'].symlink_to(self.base/'missing')
        with self.assertRaisesRegex(ValueError,'dangling'):self.call()
        self.assertTrue(paths['link'].is_symlink());paths['link'].unlink()
        external=self.base/'external';external.write_text('keep');paths['desktop'].parent.mkdir(parents=True);paths['desktop'].symlink_to(external)
        with self.assertRaisesRegex(ValueError,'shortcut'):self.call()
        self.assertEqual(external.read_text(),'keep');self.assertFalse(self.commands())
    def test_selected_prefix_and_marker_cannot_redirect(self):
        target=self.base/'foreign';target.mkdir();self.prefix.symlink_to(target,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'symbolic link'):self.call()
        self.prefix.unlink();self.prefix.mkdir();(self.prefix/installer.MARKER).write_text(json.dumps({'appId':installer.APP_ID,'prefix':str(target),'desktopText':''}))
        with self.assertRaisesRegex(ValueError,'ownership'):self.call('--uninstall')
        self.assertFalse(self.commands())
    def test_owned_missing_wrapper_repairs_dangling_owned_command(self):
        paths=self.installed();paths['wrapper'].unlink();self.assertTrue(paths['link'].is_symlink());self.assertFalse(paths['link'].exists())
        self.assertEqual(self.call(),0);self.assertTrue(paths['wrapper'].is_file());self.assertTrue(paths['link'].exists())
        updates=[row['args']for row in self.commands()if len(row['args'])>1 and row['args'][1]=='update']
        self.assertEqual(len(updates),0)
    def test_modified_helper_blocks_update_and_survives_uninstall(self):
        paths=self.installed();paths['helper'].write_text('custom helper');self.reset()
        with self.assertRaisesRegex(ValueError,'modified'):self.call()
        self.assertFalse(self.commands());self.assertEqual(self.call('--uninstall'),0)
        self.assertEqual(paths['helper'].read_text(),'custom helper');self.assertTrue((self.prefix/'repo/config').is_file())
    def test_uninstall_keeps_data_and_modified_wrapper_shortcuts(self):
        paths=self.installed();paths['wrapper'].write_text('custom wrapper');paths['desktop'].write_text('custom desktop')
        saves=self.home/'.var/app'/installer.APP_ID/'data';saves.mkdir(parents=True);(saves/'app.sqlite').write_bytes(b'saved data')
        (self.prefix/'unrelated.txt').write_text('keep');paths['link'].unlink();paths['link'].symlink_to(self.base/'foreign-command')
        self.assertEqual(self.call('--uninstall'),0)
        self.assertEqual((saves/'app.sqlite').read_bytes(),b'saved data');self.assertEqual((self.prefix/'unrelated.txt').read_text(),'keep')
        self.assertEqual(paths['wrapper'].read_text(),'custom wrapper');self.assertEqual(paths['desktop'].read_text(),'custom desktop');self.assertTrue(paths['link'].is_symlink())
        self.assertTrue((self.prefix/'repo/config').is_file())
        self.assertFalse(any('--delete-data'in row['args']for row in self.commands()))
    def test_flatpak_failure_does_not_change_existing_helpers(self):
        paths=self.installed();before={path:installer.snapshot(path)for path in paths.values()}
        with patch.dict(os.environ,{'FLATPAK_TEST_FAIL':'update','FLATPAK_TEST_COMMIT':'b'*64}):
            with self.assertRaises(subprocess.CalledProcessError):self.call()
        self.assertEqual(before,{path:installer.snapshot(path)for path in paths.values()})
    def test_verified_local_commit_updates_without_uninstall_and_rejects_wrong_bundle(self):
        paths=self.installed();self.reset()
        with patch.dict(os.environ,{'FLATPAK_TEST_COMMIT':'b'*64}):self.assertEqual(self.call(),0)
        self.assertEqual((self.prefix/'fixture-app-installed').read_text(),'b'*64)
        calls=[row['args']for row in self.commands()]
        self.assertTrue(any(args[0]=='build-import-bundle'for args in calls));self.assertTrue(any(len(args)>1 and args[1]=='update'for args in calls))
        self.assertFalse(any('uninstall'in args for args in calls))
        update=next(args for args in calls if len(args)>1 and args[1]=='update')
        self.assertNotIn('--no-pull',update);self.assertIn('--commit='+'b'*64,update)
        self.assertEqual((self.prefix/'fixture-origin-url').read_text(),(self.prefix/'repo').as_uri())
        before={path:installer.snapshot(path)for path in paths.values()}
        with patch.dict(os.environ,{'FLATPAK_TEST_REF':'app/org.example.Other/x86_64/stable'}):
            with self.assertRaisesRegex(ValueError,'not a Love2Gathering'):self.call()
        self.assertEqual(before,{path:installer.snapshot(path)for path in paths.values()})
        self.assertEqual((self.prefix/'fixture-app-installed').read_text(),'b'*64)
    def test_shared_or_changed_remote_is_never_rewritten(self):
        paths=self.installed();before={path:installer.snapshot(path)for path in paths.values()}
        for setting in({'FLATPAK_TEST_ORIGIN':'flathub'},{'FLATPAK_TEST_SHARED':'1'},{'FLATPAK_TEST_ORIGIN_URL':'https://other.example/repo'}):
            with self.subTest(setting=setting):
                self.reset()
                with patch.dict(os.environ,dict(setting,FLATPAK_TEST_COMMIT='b'*64)):
                    with self.assertRaises(ValueError):self.call()
                self.assertFalse(any('remote-modify'in row['args']for row in self.commands()))
                self.assertEqual((self.prefix/'fixture-app-installed').read_text(),'a'*64)
                self.assertEqual(before,{path:installer.snapshot(path)for path in paths.values()})
    def test_native_noop_cannot_claim_a_new_deployed_commit(self):
        paths=self.installed();before={path:installer.snapshot(path)for path in paths.values()}
        with patch.dict(os.environ,{'FLATPAK_TEST_COMMIT':'b'*64,'FLATPAK_TEST_IGNORE_UPDATE':'1'}):
            with self.assertRaisesRegex(ValueError,'does not match'):self.call()
        self.assertEqual(before,{path:installer.snapshot(path)for path in paths.values()})
        self.assertEqual((self.prefix/'fixture-app-installed').read_text(),'a'*64)
    def test_folder_chooser_cancel_runs_no_command_or_file_changes(self):
        with patch.object(installer,'choose_prefix',return_value=None):
            with redirect_stdout(self.out):self.assertEqual(installer.main([str(self.bundle)]),1)
        self.assertFalse(self.prefix.exists());self.assertFalse(self.commands())
    def test_late_foreign_shortcut_survives_native_install(self):
        paths=installer.resources(self.prefix)
        with patch.dict(os.environ,{'FLATPAK_TEST_LATE_DESKTOP':str(paths['desktop'])}):
            with self.assertRaisesRegex(ValueError,'changed during Flatpak'):self.call()
        self.assertEqual(paths['desktop'].read_text(),'foreign appeared');self.assertFalse(paths['wrapper'].exists());self.assertFalse(paths['marker'].exists())
    def test_registration_failure_rolls_back_earlier_owned_writes(self):
        paths=self.installed();before={path:installer.snapshot(path)for path in paths.values()};atomic=installer.atomic_file
        def fail(path,*args):
            if path==paths['helper']:raise OSError('fixture write failed')
            return atomic(path,*args)
        with patch.object(installer,'atomic_file',fail):
            with self.assertRaises(OSError):self.call()
        self.assertEqual(before,{path:installer.snapshot(path)for path in paths.values()})
    def test_legacy_owned_files_upgrade_only_with_known_checksums(self):
        self.prefix.mkdir();paths=installer.resources(self.prefix)
        paths['wrapper'].write_text(installer.wrapper_text(self.prefix));paths['helper'].write_bytes(b'known legacy helper')
        state={'appId':installer.APP_ID,'prefix':str(self.prefix),'desktopText':'old desktop'};paths['marker'].write_text(json.dumps(state))
        with patch.object(installer,'LEGACY_HELPER_SHA256',installer.digest(b'known legacy helper')):
            self.assertEqual(self.call(),0)
        state=json.loads(paths['marker'].read_text());self.assertEqual(state['schema'],2);self.assertEqual(state['files']['install-flatpak.py'],installer.digest(paths['helper'].read_bytes()))
    def test_lock_rejects_parallel_helpers_before_mutation(self):
        with installer.operation_lock():
            with self.assertRaisesRegex(ValueError,'Another Flatpak installer'):self.call()
        self.assertFalse(self.prefix.exists());self.assertFalse(self.commands())


if __name__=='__main__':unittest.main(verbosity=2)
