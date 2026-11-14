"""No-network release acceptance: partial or foreign releases cannot be published."""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('publish_release', Path(__file__).with_name('publish-release.py'))
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
VERSION = '2026.11.15.123'
COMMIT = '1a' * 20
TAG = 'development-123-1-' + COMMIT[:12]


class FakeGitHub:
    def __init__(self, *, existing=False, fail_upload=0, corrupt=None):
        self.release = self.make_release() if existing else None
        self.tag = {'type': 'commit', 'sha': COMMIT} if existing else None
        self.assets = []
        self.commands = []
        self.fail_upload = fail_upload
        self.uploaded = 0
        self.corrupt = corrupt
        self.annotated = None

    @staticmethod
    def make_release():
        return {'id': 77, 'tag_name': TAG, 'target_commitish': COMMIT,
                'draft': True, 'prerelease': True,
                'html_url': f'https://github.com/{publisher.REPOSITORY}/releases/tag/{TAG}'}

    def api(self, endpoint, *arguments):
        prefix = 'repos/' + publisher.REPOSITORY
        if endpoint == prefix + '/releases/tags/' + TAG:
            if self.release is None or self.release['draft']:
                raise publisher.NotFound('404')
            return deepcopy(self.release)
        if endpoint == 'graphql':
            assert 'tag=' + TAG in arguments
            return {'data': {'repository': {'release': {'databaseId': 77} if self.release else None}}}
        if endpoint == prefix + '/releases/77':
            return deepcopy(self.release)
        if endpoint == prefix + '/git/ref/tags/' + TAG:
            if self.tag is None:
                raise publisher.NotFound('404')
            return {'object': deepcopy(self.tag)}
        if endpoint == prefix + '/releases/77/assets?per_page=100':
            return deepcopy(self.assets)
        if self.annotated and endpoint == prefix + '/git/tags/' + self.annotated:
            return {'object': {'type': 'commit', 'sha': COMMIT}}
        raise AssertionError('Unexpected API request: ' + endpoint)

    def command(self, *args):
        self.commands.append(args)
        assert args[:1] == ('release',)
        assert args[args.index('--repo') + 1] == publisher.REPOSITORY
        if args[1] == 'create':
            assert '--draft' in args and '--prerelease' in args
            assert args[args.index('--target') + 1] == COMMIT
            self.release = self.make_release()
        elif args[1] == 'upload':
            self.uploaded += 1
            if self.uploaded == self.fail_upload:
                raise publisher.ReleaseError('simulated interrupted upload')
            assert self.release['draft'] is True
            path = Path(args[3])
            value = {'name': path.name, 'size': path.stat().st_size, 'state': 'uploaded',
                     'digest': 'sha256:' + publisher.digest(path)}
            if self.uploaded == 1:
                if self.corrupt == 'size':
                    value['size'] += 1
                if self.corrupt == 'state':
                    value['state'] = 'starter'
                if self.corrupt == 'digest':
                    value['digest'] = 'sha256:' + '0' * 64
                if self.corrupt == 'missing':
                    return ''
            self.assets = [a for a in self.assets if a['name'] != path.name] + [value]
        elif args[1] == 'edit':
            assert '--draft=false' in args and '--latest=false' in args
            self.release['draft'] = False
            if self.tag is None:
                self.tag = {'type': 'commit', 'sha': COMMIT}
        else:
            raise AssertionError('Unexpected gh invocation: ' + repr(args))
        return ''


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='love2gathering-publish-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        self.metadata = self.root / 'cards.provenance.json'
        self.metadata.write_text(json.dumps({'version': 1, 'metadataOnly': True,
            'bulkType': 'default_cards', 'cards': 10000, 'bytes': 123456, 'sha256': 'a' * 64}))
        self.release_path = self.dist / 'stage/common/Love2Gathering/release.json'
        self.release_path.parent.mkdir(parents=True)
        self.release_path.write_text(json.dumps({'applicationId': publisher.APP_ID,
            'version': VERSION, 'sourceRevision': COMMIT, 'engineRevision': publisher.ENGINE_REVISION,
            'includesUserData': False}))
        self.names = publisher.package_names(VERSION)
        archive = b'\xfd7zXZ\x00' + b'not a real package: transport fixture' * 10
        pe = bytearray(256)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 0x3c, 128)
        pe[128:132] = b'PE\x00\x00'
        content = [b'!<arch>\nfixture', b'\xed\xab\xee\xdbfixture',
                   b'#!/bin/sh\nexit 0\n' + publisher.MARKER + archive,
                   archive, bytes(pe), b'flatpak\x00fixture' + publisher.APP_ID.encode()]
        for name, value in zip(self.names, content):
            (self.dist / name).write_bytes(value)
        (self.dist / 'install-flatpak.py').write_text('import argparse\nAPP_ID = ' + repr(publisher.APP_ID))
        (self.dist / 'windows-runtime-provenance.json').write_text(json.dumps(
            {component: {'sha256': 'a' * 64} for component in ('love', 'python', 'java')}))
        (self.dist / 'flatpak-native-provenance.json').write_text(json.dumps(
            {'love': {'sha256': 'b' * 64}, 'libraries': {'libsample.so': {'sha256': 'c' * 64}}}))

    def prepare(self):
        return publisher.prepare(self.dist, VERSION, TAG, COMMIT, self.metadata)

    def test_prepare_has_exact_allowlist_and_checksums_ignore_extra_files(self):
        (self.dist / 'old-version.exe').write_bytes(b'do not upload')
        files = self.prepare()
        self.assertEqual(len(files), 13)
        self.assertNotIn('old-version.exe', [p.name for p in files])
        sums = dict(line.split('  ')[::-1] for line in (self.dist / 'SHA256SUMS').read_text().splitlines())
        for path in files[:-1]:
            self.assertEqual(sums[path.name], publisher.digest(path))
        manifest = json.loads((self.dist / 'release-manifest.json').read_text())
        self.assertEqual(manifest['commit'], COMMIT)
        self.assertEqual(manifest['engineRevision'], publisher.ENGINE_REVISION)
        self.assertEqual(len(manifest['assets']), 11)
        guide = (self.dist / 'INSTALL.md').read_text()
        self.assertIn(self.names[0], guide)
        self.assertIn(f'install-flatpak.py {self.names[-1]} --prefix ', guide)

    def test_prepare_only_never_authenticates_or_contacts_github(self):
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': publisher.REPOSITORY}, clear=True), \
                patch.object(publisher, 'GitHub', side_effect=AssertionError('must not contact GitHub')):
            self.assertEqual(publisher.main(['--dist', str(self.dist), '--version', VERSION,
                '--tag', TAG, '--commit', COMMIT, '--metadata-report', str(self.metadata), '--prepare-only']), 0)

    def test_success_creates_private_draft_then_publishes_after_exact_assets_verified(self):
        files = self.prepare()
        gh = FakeGitHub()
        url = publisher.publish(gh, files, VERSION, TAG, COMMIT)
        self.assertIn(publisher.REPOSITORY, url)
        self.assertFalse(gh.release['draft'])
        self.assertTrue(gh.release['prerelease'])
        self.assertEqual([c[1] for c in gh.commands], ['create'] + ['upload'] * 13 + ['edit'])
        self.assertEqual({a['name'] for a in gh.assets}, {p.name for p in files})

    def test_partial_upload_never_publishes(self):
        gh = FakeGitHub(fail_upload=5)
        with self.assertRaisesRegex(publisher.ReleaseError, 'interrupted'):
            publisher.publish(gh, self.prepare(), VERSION, TAG, COMMIT)
        self.assertTrue(gh.release['draft'])
        self.assertNotIn('edit', [c[1] for c in gh.commands])

    def test_asset_size_state_digest_or_missing_never_publishes(self):
        files = self.prepare()
        for corruption in ('size', 'state', 'digest', 'missing'):
            with self.subTest(corruption=corruption):
                gh = FakeGitHub(corrupt=corruption)
                with self.assertRaises(publisher.ReleaseError):
                    publisher.publish(gh, files, VERSION, TAG, COMMIT)
                self.assertTrue(gh.release['draft'])
                self.assertNotIn('edit', [c[1] for c in gh.commands])

    def test_foreign_or_published_releases_are_untouched(self):
        files = self.prepare()
        for changes in ({'draft': False}, {'target_commitish': 'main'},
                        {'target_commitish': 'f' * 40}, {'prerelease': False}, {'tag_name': 'other'}):
            with self.subTest(changes=changes):
                gh = FakeGitHub(existing=True)
                gh.release.update(changes)
                before = deepcopy(gh.release)
                with self.assertRaisesRegex(publisher.ReleaseError, 'unrelated'):
                    publisher.publish(gh, files, VERSION, TAG, COMMIT)
                self.assertEqual(gh.commands, [])
                self.assertEqual(gh.release, before)

    def test_existing_foreign_tag_is_untouched_even_without_release(self):
        gh = FakeGitHub()
        gh.tag = {'type': 'commit', 'sha': 'f' * 40}
        with self.assertRaisesRegex(publisher.ReleaseError, 'exact commit'):
            publisher.publish(gh, self.prepare(), VERSION, TAG, COMMIT)
        self.assertEqual(gh.commands, [])

    def test_owned_matching_draft_can_resume_but_unknown_assets_abort_untouched(self):
        files = self.prepare()
        gh = FakeGitHub(existing=True)
        gh.assets = [{'name': files[0].name, 'size': 1, 'state': 'starter'}]
        publisher.publish(gh, files, VERSION, TAG, COMMIT)
        self.assertNotIn('create', [c[1] for c in gh.commands])
        self.assertTrue(all('--clobber' in c for c in gh.commands if c[1] == 'upload'))
        gh = FakeGitHub(existing=True)
        gh.assets = [{'name': 'foreign.exe', 'size': 10, 'state': 'uploaded'}]
        with self.assertRaisesRegex(publisher.ReleaseError, 'Unexpected'):
            publisher.publish(gh, files, VERSION, TAG, COMMIT)
        self.assertEqual(gh.commands, [])

    def test_same_commit_annotated_tag_is_allowed(self):
        gh = FakeGitHub(existing=True)
        gh.annotated = 'f' * 40
        gh.tag = {'type': 'tag', 'sha': gh.annotated}
        publisher.publish(gh, self.prepare(), VERSION, TAG, COMMIT)
        self.assertFalse(gh.release['draft'])

    def test_resuming_draft_with_only_pending_tag_uses_graphql_identity(self):
        gh = FakeGitHub(existing=True)
        gh.tag = None
        publisher.publish(gh, self.prepare(), VERSION, TAG, COMMIT)
        self.assertNotIn('create', [c[1] for c in gh.commands])
        self.assertFalse(gh.release['draft'])
        self.assertEqual(gh.tag, {'type': 'commit', 'sha': COMMIT})

    def test_draft_lookup_graphql_failure_does_not_create_duplicate_release(self):
        class UnavailableGraphQL(FakeGitHub):
            def api(self, endpoint, *arguments):
                if endpoint == 'graphql':
                    return {'errors': [{'message': 'temporarily unavailable'}]}
                return super().api(endpoint, *arguments)
        gh = UnavailableGraphQL(existing=True)
        with self.assertRaisesRegex(publisher.ReleaseError, 'look up a draft'):
            publisher.publish(gh, self.prepare(), VERSION, TAG, COMMIT)
        self.assertEqual(gh.commands, [])

    def test_mismatched_payload_provenance_stops_before_github(self):
        source = json.loads(self.release_path.read_text())
        for key, wrong in (('version', '2026.11.14'), ('sourceRevision', 'f' * 40),
                           ('engineRevision', '0' * 40), ('includesUserData', True)):
            with self.subTest(key=key):
                self.release_path.write_text(json.dumps(source | {key: wrong}))
                with self.assertRaisesRegex(publisher.ReleaseError, 'provenance'):
                    self.prepare()
        self.release_path.write_text(json.dumps(source))

    def test_missing_package_bad_magic_and_mismatched_run_archive_abort(self):
        path = self.dist / self.names[0]
        value = path.read_bytes()
        path.unlink()
        with self.assertRaises(publisher.ReleaseError):
            self.prepare()
        path.write_bytes(b'<!doctype html>upstream error page')
        with self.assertRaisesRegex(publisher.ReleaseError, 'signature'):
            self.prepare()
        path.write_bytes(value)
        with (self.dist / self.names[2]).open('ab') as stream:
            stream.write(b'extra data')
        with self.assertRaisesRegex(publisher.ReleaseError, 'exactly this tar'):
            self.prepare()

    def test_symlink_and_invalid_identity_are_rejected(self):
        output = self.dist / 'INSTALL.md'
        output.symlink_to(self.root / 'external.txt')
        with self.assertRaisesRegex(publisher.ReleaseError, 'symlink'):
            self.prepare()
        output.unlink()
        with self.assertRaisesRegex(publisher.ReleaseError, 'Tag must'):
            publisher.prepare(self.dist, VERSION, TAG + 'oops', COMMIT, self.metadata)
        with self.assertRaisesRegex(publisher.ReleaseError, 'invalid date'):
            publisher.prepare(self.dist, '2026.02.31.123', TAG, COMMIT, self.metadata)

    def test_auth_failure_is_not_treated_as_missing_release(self):
        gh = publisher.GitHub()
        failed = type('Result', (), {'returncode': 1, 'stdout': '', 'stderr': 'gh: Bad credentials (HTTP 401)'})()
        with patch.object(publisher.subprocess, 'run', return_value=failed), \
                self.assertRaisesRegex(publisher.ReleaseError, 'Bad credentials'):
            publisher.get_release(gh, TAG)


if __name__ == '__main__':
    unittest.main()
