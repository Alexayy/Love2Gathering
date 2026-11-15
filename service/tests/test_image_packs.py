"""Optional image packs use only isolated caches and synthetic local JPEGs."""
from contextlib import closing
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from downloads import image_job_lock
from image_packs import EmptyImages, FORMAT, ImagePacks, ReadonlyImages, RESERVE_BYTES, build_starter_pack, export_starter_pack, starter_plan
from maintenance import operation_lock
from replays import ConflictError
from storage import Storage

JPEG = b'\xff\xd8isolated-complete-image-pack-fixture\xff\xd9'
PROJECT = Path(__file__).resolve().parents[2]


class ImagePackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='love2gathering-image-pack-')
        self.root = Path(self.temporary.name)
        self.source = self.root / 'cards.jsonl'
        cards = []
        for name in ('first', 'second'):
            cards.append({'object': 'card', 'id': name, 'oracle_id': 'oracle-' + name, 'name': name,
                          'lang': 'en', 'type_line': 'Creature', 'set': 'tst', 'legalities': {'modern': 'legal'},
                          'image_uris': {kind: f'https://cards.scryfall.io/{kind}/{name}.jpg' for kind in ('normal', 'large', 'art_crop')}})
        self.source.write_text('\n'.join(json.dumps(v) for v in cards) + '\n')
        self.catalog = Catalog(self.source, self.root / 'catalog.sqlite');self.catalog.ensure()
        self.store = Storage(self.root / 'data', self.root / 'empty-bundled')
        self.manager = ImagePacks(self.catalog, self.store)
        self.decks = self.root / 'starters';self.decks.mkdir()
        (self.decks / 'fixture.json').write_text(json.dumps({'id': 'fixture', 'name': 'Fixture Starter', 'main': [{'name': 'first', 'count': 4}, {'name': 'second', 'count': 1}]}))
        self.number = 0

    def tearDown(self):
        self.manager.close();self.store.close_images();self.temporary.cleanup()

    @staticmethod
    def entry(printing='first', kind='normal', face=0, data=JPEG):
        return {'printingId': printing, 'oracleId': 'oracle-' + printing, 'face': face, 'kind': kind,
                'source': f'https://cards.scryfall.io/{kind}/{printing}.jpg', 'name': printing,
                'path': ('art-crops/' if kind == 'art_crop' else 'full-cards/') + f'{printing}-{face}-{kind}.jpg',
                'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

    def pack(self, entries=None, mutate=None, extra=None):
        self.number += 1;path = self.root / f'pack-{self.number}.zip'
        entries = entries if entries is not None else [self.entry(), self.entry('second', 'art_crop')]
        manifest = {'format': FORMAT, 'version': 1, 'complete': True, 'decks': [{'id': 'fixture', 'name': 'Fixture Starter'}], 'images': deepcopy(entries), 'missing': []}
        if mutate: mutate(manifest)
        with zipfile.ZipFile(path, 'w') as archive:
            for entry in entries: archive.writestr(entry['path'], JPEG)
            archive.writestr('manifest.json', json.dumps(manifest))
            if extra: extra(archive)
        return path

    def wait(self):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if not self.manager.thread.is_alive(): return self.manager.status()
            time.sleep(.005)
        self.fail('Image pack operation did not finish: ' + repr(self.manager.status()))

    def inspect(self, path):
        self.manager.inspect(str(path));return self.wait()

    def test_preview_is_read_only_then_explicit_install_is_idempotent_and_preserves_existing(self):
        old = JPEG + b'newer-user-copy'
        self.store.save_art('first-0-normal.jpg', old, {'preserve': True})
        self.store.save_settings({'theme': 'Ocean'})
        status = self.inspect(self.pack())
        self.assertEqual((status['state'], status['images'], status['cached'], status['missing']), ('ready', 2, 1, 1))
        self.assertIsNone(self.store.get_art('second-0-art_crop.jpg'))
        with self.assertRaises(ConflictError): self.manager.install('stale-job')
        self.manager.install(status['jobId']);status = self.wait()
        self.assertEqual((status['state'], status['installed'], status['skipped']), ('completed', 1, 1))
        self.assertEqual(self.store.get_art('first-0-normal.jpg'), old)
        self.assertEqual(self.store.get_art('second-0-art_crop.jpg'), JPEG)
        self.assertEqual(self.store.settings()['theme'], 'Ocean')
        with self.store.connection() as connection:
            metadata = json.loads(connection.execute("SELECT metadata FROM art_cache WHERE cache_key='second-0-art_crop.jpg'").fetchone()[0])
        self.assertEqual(metadata['source'], 'https://cards.scryfall.io/art_crop/second.jpg')
        self.assertIn('manifestSha256', metadata['imagePack'])
        status = self.inspect(self.root / 'pack-1.zip');self.manager.install(status['jobId']);status = self.wait()
        self.assertEqual((status['installed'], status['skipped']), (0, 2))

    def test_incomplete_pack_reports_missing_source_images_honestly(self):
        def incomplete(manifest):
            missing = self.entry('second')
            for key in ('path', 'size', 'sha256'): missing.pop(key)
            missing['reason'] = 'Not cached in pack build source'
            manifest.update(complete=False, missing=[missing])
        status = self.inspect(self.pack([self.entry()], mutate=incomplete))
        self.assertEqual((status['state'], status['complete'], status['missingEntries'], status['missing']), ('ready', False, 1, 1))

    def test_foreign_identity_face_kind_url_hash_and_oversize_are_rejected_before_writes(self):
        mutations = [lambda m: m['images'][-1].update(oracleId='foreign'),
                     lambda m: m['images'][-1].update(printingId='absent'),
                     lambda m: m['images'][-1].update(face=1),
                     lambda m: m['images'][-1].update(kind='thumbnail'),
                     lambda m: m['images'][-1].update(source='https://untrusted.example/art.jpg'),
                     lambda m: m['images'][-1].update(sha256='0'*64),
                     lambda m: m['images'][-1].update(size=3*1024**2+1)]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                status = self.inspect(self.pack(mutate=mutate))
                self.assertEqual(status['state'], 'error', status)
                with self.assertRaises(ConflictError): self.manager.install(status['jobId'])
                self.assertEqual(self.store.artwork_summary()['cachedImages'], 0)

    def test_traversal_undeclared_symlinks_and_duplicate_zip_entries_are_rejected(self):
        def link(archive):
            item = zipfile.ZipInfo('full-cards/linked.jpg');item.create_system=3;item.external_attr=(stat.S_IFLNK | 0o777)<<16
            archive.writestr(item, '/etc/passwd')
        extras = [lambda a: a.writestr('../outside.jpg', JPEG), lambda a: a.writestr('extra.jpg', JPEG), link]
        for extra in extras:
            with self.subTest(extra=extra): self.assertEqual(self.inspect(self.pack(extra=extra))['state'], 'error')
        with patch('warnings.warn'):
            path = self.pack(extra=lambda a: a.writestr('full-cards/first-0-normal.jpg', JPEG))
        self.assertEqual(self.inspect(path)['state'], 'error')
        self.assertFalse((self.root / 'outside.jpg').exists())
        self.assertEqual(self.store.artwork_summary()['cachedImages'], 0)

    def test_manifest_and_archive_bounds_are_checked(self):
        path = self.pack()
        with patch('image_packs.MAX_MANIFEST', 8):
            self.assertEqual(self.inspect(path)['state'], 'error')
        with patch('image_packs.MAX_ARCHIVE', 32):
            self.assertEqual(self.inspect(path)['state'], 'error')
        with patch('image_packs.MAX_IMAGES', 0):
            self.assertEqual(self.inspect(path)['state'], 'error')

    def test_active_download_and_purge_locks_reject_install_with_pause_message(self):
        status = self.inspect(self.pack())
        with image_job_lock(self.store.root):
            with self.assertRaisesRegex(ConflictError, 'Pause'): self.manager.install(status['jobId'])
        with operation_lock(self.store.root, exclusive=True):
            with self.assertRaisesRegex(ConflictError, 'Pause'): self.manager.install(status['jobId'])
        self.assertEqual(self.manager.status()['state'], 'ready')

    def test_changed_archive_requires_a_new_preview(self):
        path = self.pack();status = self.inspect(path)
        with path.open('ab') as stream: stream.write(b'changed')
        with self.assertRaisesRegex(ConflictError, 'changed'): self.manager.install(status['jobId'])
        self.assertEqual(self.store.artwork_summary()['cachedImages'], 0)

    def test_low_space_keeps_committed_images_and_can_resume_after_new_preview(self):
        calls = []
        def space(_):
            calls.append(True)
            return SimpleNamespace(free=RESERVE_BYTES+len(JPEG)*4 if len(calls)<=2 else 0)
        self.manager.disk_usage = space
        path = self.pack();status = self.inspect(path);self.manager.install(status['jobId']);status = self.wait()
        self.assertEqual((status['state'], status['installed'], status['processed']), ('error', 1, 1))
        self.assertIn('64 MiB', status['error'])
        self.assertEqual(self.store.artwork_summary()['cachedImages'], 1)
        self.manager.disk_usage = lambda _: SimpleNamespace(free=1024**3)
        status = self.inspect(path);self.assertEqual(status['cached'], 1)
        self.manager.install(status['jobId']);status = self.wait()
        self.assertEqual((status['state'], status['installed'], status['skipped']), ('completed', 1, 1))

    def test_readonly_plan_export_and_cli_keep_sources_unchanged(self):
        self.store.save_art('first-0-normal.jpg', JPEG, {k: v for k, v in self.entry().items() if k not in ('path', 'size', 'sha256')})
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in (self.source, self.store.database, self.catalog.database, self.decks / 'fixture.json')}
        with closing(ReadonlyImages(self.store.database)) as source:
            plan = starter_plan(self.catalog, source, self.decks)
            self.assertEqual((len(plan['images']), len(plan['missing']), plan['complete']), (1, 3, False))
            target = self.root / 'export.zip'
            manifest = export_starter_pack(self.catalog, source, self.decks, target)
            self.assertEqual((len(manifest['images']), len(manifest['missing'])), (1, 3))
            with self.assertRaises(ValueError): export_starter_pack(self.catalog, source, self.decks, target)
        self.assertEqual(self.inspect(target)['state'], 'ready')
        run = subprocess.run([sys.executable, str(PROJECT / 'scripts/starter-image-pack.py'), 'plan', '--catalog', str(self.catalog.database), '--database', str(self.store.database), '--decks', str(self.decks)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout)['missingEntries'], 3)
        for path, digest in before.items(): self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)

    def test_explicit_build_fetches_only_missing_images_and_never_writes_sql(self):
        self.store.save_art('first-0-normal.jpg', JPEG, {k: v for k, v in self.entry().items() if k not in ('path', 'size', 'sha256')})
        before = hashlib.sha256(self.store.database.read_bytes()).hexdigest()
        class Fetcher:
            def __init__(self): self.urls=[];self.closed=False
            def image(self, url): self.urls.append(url);return JPEG
            def close(self): self.closed=True
        fetcher = Fetcher();progress=[];target=self.root/'complete.zip'
        with closing(ReadonlyImages(self.store.database)) as source:
            manifest = build_starter_pack(self.catalog, source, self.decks, target,
                                          fetcher=fetcher, progress=lambda *value:progress.append(value))
        self.assertTrue(manifest['complete']);self.assertEqual(len(manifest['images']),4)
        self.assertEqual(fetcher.urls, ['https://cards.scryfall.io/art_crop/first.jpg', 'https://cards.scryfall.io/normal/second.jpg', 'https://cards.scryfall.io/art_crop/second.jpg'])
        self.assertTrue(fetcher.closed);self.assertTrue(progress)
        self.assertEqual(hashlib.sha256(self.store.database.read_bytes()).hexdigest(), before)
        self.assertEqual(self.store.artwork_summary()['cachedImages'],1)
        self.assertEqual(self.inspect(target)['state'],'ready')

    def test_failed_build_publishes_nothing_and_existing_output_prevents_acquisition(self):
        class Fetcher:
            def __init__(self): self.urls=[];self.closed=False
            def image(self, url): self.urls.append(url);raise OSError('Synthetic provider refusal')
            def close(self): self.closed=True
        target=self.root/'refused.zip';fetcher=Fetcher()
        with self.assertRaisesRegex(OSError,'refusal'):
            build_starter_pack(self.catalog, EmptyImages(), self.decks, target, fetcher=fetcher)
        self.assertTrue(fetcher.closed);self.assertEqual(len(fetcher.urls),1)
        self.assertFalse(target.exists());self.assertEqual(list(self.root.glob('.refused.zip.*.tmp')),[])
        target.write_bytes(b'existing-user-output');fetcher=Fetcher()
        with self.assertRaises(ValueError):
            build_starter_pack(self.catalog, EmptyImages(), self.decks, target, fetcher=fetcher)
        self.assertEqual(fetcher.urls,[]);self.assertEqual(target.read_bytes(),b'existing-user-output')

    def test_explicit_build_reuses_shared_urls_without_collapsing_exact_identities(self):
        raw=[json.loads(line)for line in self.source.read_text().splitlines()]
        raw[1]['image_uris']=dict(raw[0]['image_uris'])
        self.source.write_text('\n'.join(json.dumps(card)for card in raw)+'\n');self.catalog.ensure()
        class Fetcher:
            def __init__(self):self.urls=[]
            def image(self,url):self.urls.append(url);return JPEG
            def close(self):pass
        fetcher=Fetcher();target=self.root/'shared.zip'
        manifest=build_starter_pack(self.catalog, EmptyImages(), self.decks,target,fetcher=fetcher)
        self.assertEqual(len(fetcher.urls),2);self.assertEqual(len(manifest['images']),4)
        self.assertEqual({entry['printingId']for entry in manifest['images']},{'first','second'})
        self.assertEqual(self.inspect(target)['state'],'ready')


if __name__ == '__main__': unittest.main()
