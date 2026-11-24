#!/usr/bin/env python3
"""Actual owned helper subprocesses with synthetic native Flatpak commands."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path); value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
host = module('flatpak_update_host_fixture', HERE / 'update-host.py')
fixtures = module('flatpak_installer_fixture_source', HERE / 'test_installer.py')


class HostUpdateTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.FlatpakInstallerTest('test_verified_local_commit_updates_without_uninstall_and_rejects_wrong_bundle')
        self.fixture.setUp(); self.base = self.fixture.base; self.prefix = self.fixture.prefix
        binary = self.fixture.binary / 'flatpak'
        code = binary.read_text().replace(
            "if action=='info':print(origin if '--show-origin'in args else(root/'fixture-app-installed').read_text())",
            "if action=='info':\n current=(root/'fixture-app-installed').read_text()\n print(str(root/'app'/'io.github.Alexayy.Love2Gathering'/'x86_64'/'stable'/current)if'--show-location'in args else ref if'--show-ref'in args else origin if'--show-origin'in args else current)")
        binary.write_text(code); self.fixture.installed()
        self.old = dict(applicationId=host.APP_ID, version='2026.11.17.10', channel='stable', sourceRevision='a' * 40,
                        tag='v2026.11.17.10', builtAtUTC='2026-11-17T12:00:00Z')
        self.new = dict(self.old, version='2026.11.18.11', sourceRevision='b' * 40, tag='v2026.11.18.11')
        self.deploy('a' * 64, self.old); self.deploy('b' * 64, self.new)
        self.fixture.reset(); self.launches = []; self.contexts = []; self.mutation = None
        self.sessions = self.base / 'host-sessions'
        self.saves = self.fixture.home / '.var/app' / host.APP_ID / 'data/app.sqlite'
        self.saves.parent.mkdir(parents=True); self.saves.write_bytes(b'preserved real saved-data fixture')

    def tearDown(self): self.fixture.tearDown()

    def deploy(self, commit, release):
        root = self.prefix / 'app' / host.APP_ID / 'x86_64/stable' / commit / 'files/share/Love2Gathering'
        root.mkdir(parents=True); (root / 'release.json').write_text(json.dumps(release))
        tools = root / 'host-tools'; tools.mkdir()
        for name in (host.HELPER, host.UPDATER):
            (tools / name).write_bytes((HERE / name).read_bytes() + (b'\n# Updated verified native bundle helper\n' if commit.startswith('b') else b''))

    def spawn(self, command, env):
        self.launches.append((command, env.copy()))
        index = len(self.launches)
        context = Path(next(value.split('=', 2)[2] for value in command if value.startswith('--env=LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT=')))
        value = json.loads(context.read_text()); self.contexts.append(value)
        test = self
        class Child:
            def wait(self):
                if index == 1:
                    test.assertEqual((test.prefix / 'fixture-app-installed').read_text(), 'a' * 64)
                    folder = Path(value['workDirectory']); folder.mkdir(); name = 'Love2Gathering-' + test.new['version'] + '-x86_64.flatpak'
                    installer = folder / name; installer.write_bytes(test.fixture.bundle.read_bytes())
                    job = dict(schema=1, token=value['token'], root=value['root'], method='flatpak', channel=test.new['channel'],
                               version=test.new['version'], revision=test.new['sourceRevision'], tag=test.new['tag'], installerPath=str(installer),
                               expectedSize=installer.stat().st_size, checksum=host.digest(installer))
                    job['candidateId'] = hashlib.sha256((job['tag'] + '\n' + name + '\n' + str(job['expectedSize']) + '\n' + job['checksum']).encode()).hexdigest()
                    if test.mutation: test.mutation(job, value)
                    Path(value['requestPath']).write_text(json.dumps(job))
                return 0
        return Child()

    def coordinate(self):
        with patch.dict(os.environ, {'FLATPAK_TEST_COMMIT': 'b' * 64}):
            return host.coordinate(self.prefix, ('--kept-argument',), spawn=self.spawn, session_base=self.sessions)

    def test_actual_installed_helper_updates_exact_prefix_then_restarts_owned_app(self):
        before = (self.prefix / host.UPDATER).read_bytes()
        self.assertEqual(self.coordinate(), 0)
        self.assertEqual((self.prefix / 'fixture-app-installed').read_text(), 'b' * 64)
        self.assertEqual(len(self.launches), 2)
        self.assertEqual([value['version'] for value in self.contexts], [self.old['version'], self.new['version']])
        self.assertNotEqual(self.contexts[0]['token'], self.contexts[1]['token'])
        for command, env in self.launches:
            self.assertEqual(env['FLATPAK_USER_DIR'], str(self.prefix)); self.assertEqual(command[-2:], [host.APP_ID, '--kept-argument'])
        self.assertNotEqual((self.prefix / host.UPDATER).read_bytes(), before)
        state = json.loads((self.prefix / host.MARKER).read_text())
        self.assertEqual(state['files'][host.UPDATER], host.digest(self.prefix / host.UPDATER))
        self.assertEqual(self.saves.read_bytes(), b'preserved real saved-data fixture')
        self.assertTrue(any(json.loads(path.read_text())['state'] == 'installed' for path in self.sessions.glob('*/update-result.json')))
        calls = self.fixture.commands(); self.assertTrue(all(row['root'] == str(self.prefix) for row in calls))
        self.assertFalse(any('uninstall' in row['args'] or '--delete-data' in row['args'] for row in calls))

    def test_wrong_token_channel_revision_tag_id_and_path_cannot_invoke_installer(self):
        mutations = [('token', 'forged'), ('root', '/tmp/foreign'), ('method', 'linux-run'), ('channel', 'development'),
                     ('revision', 'z' * 40), ('tag', 'v2026.11.18.999'), ('candidateId', 'f' * 64), ('installerPath', '/tmp/foreign.flatpak')]
        for key, value in mutations:
            with self.subTest(key=key):
                self.launches = []; self.mutation = lambda job, context, key=key, value=value: job.update({key: value})
                with self.assertRaises((ValueError, OSError)): self.coordinate()
                self.assertEqual((self.prefix / 'fixture-app-installed').read_text(), 'a' * 64)
                self.assertEqual(self.saves.read_bytes(), b'preserved real saved-data fixture')
        self.assertFalse(any('update' in row['args'] for row in self.fixture.commands()))

    def test_development_channel_retains_exact_commit_bound_tags_across_update(self):
        for commit, release in (('a' * 64, self.old), ('b' * 64, self.new)):
            release['channel'] = 'development'; release['tag'] = 'DEV-' + release['version'] + '-1-' + release['sourceRevision'][:12]
            path = self.prefix / 'app' / host.APP_ID / 'x86_64/stable' / commit / 'files/share/Love2Gathering/release.json'
            path.write_text(json.dumps(release))
        self.assertEqual(self.coordinate(), 0)
        self.assertEqual([value['channel'] for value in self.contexts], ['development', 'development'])
        self.assertEqual(self.contexts[-1]['tag'], self.new['tag'])

    def test_corrupt_staged_bundle_and_changed_installation_do_not_update(self):
        self.mutation = lambda job, context: Path(job['installerPath']).write_bytes(b'changed after verification')
        with self.assertRaisesRegex(ValueError, 'bundle changed'): self.coordinate()
        self.assertEqual((self.prefix / 'fixture-app-installed').read_text(), 'a' * 64)
        self.launches = []
        self.mutation = lambda job, context: (self.prefix / 'fixture-app-installed').write_text('b' * 64)
        with self.assertRaisesRegex(ValueError, 'changed while'): self.coordinate()
        self.assertFalse(any('update' in row['args'] for row in self.fixture.commands()))

    def test_unchanged_native_deployment_cannot_claim_success_or_restart(self):
        with patch.dict(os.environ, {'FLATPAK_TEST_IGNORE_UPDATE': '1'}):
            with self.assertRaises(subprocess.CalledProcessError): self.coordinate()
        self.assertEqual(len(self.launches), 1)
        self.assertEqual((self.prefix / 'fixture-app-installed').read_text(), 'a' * 64)
        self.assertFalse(any(json.loads(path.read_text()).get('state') == 'installed' for path in self.sessions.glob('*/update-result.json')))

    def test_modified_helpers_and_symbolic_prefix_are_preserved(self):
        path = self.prefix / host.UPDATER; path.write_text('modified coordinator')
        with self.assertRaisesRegex(ValueError, 'changed'): self.coordinate()
        self.assertEqual(path.read_text(), 'modified coordinator')
        link = self.base / 'alias'; link.symlink_to(self.prefix, target_is_directory=True)
        with self.assertRaises(ValueError): host.coordinate(link, session_base=self.sessions)
        self.assertFalse(self.launches)


if __name__ == '__main__': unittest.main(verbosity=2)
