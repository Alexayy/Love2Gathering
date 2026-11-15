"""Offline downloader contracts: per-printing faces, durable resume and bounds."""
import gzip
from http.client import IncompleteRead
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('image_downloader', PROJECT / 'scripts/download-card-images.py')
downloader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloader)
JPEG = b'\xff\xd8' + b'complete-fixture-jpeg' * 10 + b'\xff\xd9'


def card(identifier='printing-one', oracle='same-oracle'):
    return {'object': 'card', 'id': identifier, 'oracle_id': oracle, 'name': 'Shared card name',
            'artist': 'Illustrator', 'image_uris': {kind: f'https://cards.scryfall.io/{kind}/{identifier}.jpg'
                                                  for kind in ('normal', 'large', 'art_crop')}}


class FakeFetcher:
    def __init__(self):
        self.urls = []

    def image(self, url):
        self.urls.append(url)
        return JPEG


class Response(io.BytesIO):
    def __init__(self, data, url='https://api.scryfall.com/bulk-data/default_cards'):
        super().__init__(data)
        self.url = url

    def geturl(self):
        return self.url


class ImageDownloaderTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'cards.jsonl'
        self.output = self.root / 'images'
        self.store = downloader.Storage(self.root / 'user', self.root / 'no-bundled-seeds')
        self.fetcher = FakeFetcher()

    def tearDown(self):
        self.temp.cleanup()

    def write_source(self, cards):
        self.source.write_text('\n'.join(json.dumps(item) for item in cards) + '\n', encoding='utf-8')

    def run_download(self, **options):
        return downloader.download(self.source, self.output, self.store, self.fetcher, **options)

    def test_every_printing_and_double_face_is_retained(self):
        first = card('printing-one')
        second = card('printing-two')
        double = card('double-face')
        double.pop('image_uris')
        double['card_faces'] = [dict(card('front'), name='Front'), dict(card('back'), name='Back')]
        self.write_source([first, second, double])
        result = self.run_download()
        self.assertEqual(result['downloaded'], 8)
        self.assertEqual(len(list((self.output / 'full-cards').glob('*.jpg'))), 4)
        self.assertEqual(len(list((self.output / 'art-crops').glob('*.jpg'))), 4)
        for face in (0, 1):
            self.assertEqual(self.store.get_art(f'double-face-{face}-art_crop.jpg'), JPEG)
        with self.store.connection() as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM art_cache').fetchone()[0], 8)

    def test_restart_reuses_sqlite_and_repairs_missing_or_changed_mirror_without_network(self):
        self.write_source([card()])
        self.run_download()
        self.fetcher.urls.clear()
        (self.output / 'full-cards/printing-one-0-normal.jpg').unlink()
        (self.output / 'art-crops/printing-one-0-art_crop.jpg').write_bytes(b'incomplete mirror')
        reopened = downloader.Storage(self.root / 'user', self.root / 'no-bundled-seeds')
        result = downloader.download(self.source, self.output, reopened, self.fetcher)
        self.assertEqual(result['cached'], 2)
        self.assertEqual(result['mirrored'], 2)
        self.assertEqual(self.fetcher.urls, [])
        self.assertEqual((self.output / 'art-crops/printing-one-0-art_crop.jpg').read_bytes(), JPEG)

    def test_split_and_adventure_faces_share_one_scan_without_duplicate_image_entries(self):
        shared = card()
        shared['card_faces'] = [{'name': 'Left half'}, {'name': 'Right half'}]
        self.write_source([shared])
        result = self.run_download()
        self.assertEqual(result['downloaded'], 2)
        self.assertEqual(len(list(self.output.rglob('*.jpg'))), 2)
        self.assertIsNone(self.store.get_art('printing-one-1-normal.jpg'))

    def test_sqlite_commit_survives_mirror_write_failure_and_restart(self):
        self.write_source([card()])
        with patch.object(downloader, 'write_mirror', side_effect=OSError('test disk interruption')):
            result = self.run_download(limit=1)
        self.assertEqual(result['failed'], 1)
        self.assertEqual(self.store.get_art('printing-one-0-normal.jpg'), JPEG)
        self.fetcher.urls.clear()
        result = self.run_download(limit=1)
        self.assertEqual(result['cached'], 1)
        self.assertEqual(result['mirrored'], 1)
        self.assertEqual(self.fetcher.urls, [])

    def test_existing_complete_mirror_is_imported_and_truncated_jpeg_is_redownloaded(self):
        self.write_source([card()])
        folder = self.output / 'full-cards'
        folder.mkdir(parents=True)
        (folder / 'printing-one-0-normal.jpg').write_bytes(JPEG)
        crop = self.output / 'art-crops/printing-one-0-art_crop.jpg'
        crop.parent.mkdir()
        crop.write_bytes(JPEG[:-2])
        result = self.run_download()
        self.assertEqual(result['imported'], 1)
        self.assertEqual(result['downloaded'], 1)
        self.assertEqual(self.fetcher.urls, [card()['image_uris']['art_crop']])
        self.assertEqual(crop.read_bytes(), JPEG)

    def test_gzipped_source_limit_high_resolution_and_dry_run_make_no_writes(self):
        self.write_source([card(), card('second')])
        source = self.root / 'cards.jsonl.gz'
        with gzip.open(source, 'wb') as stream:
            stream.write(self.source.read_bytes())
        result = downloader.download(source, self.output, None, self.fetcher, limit=1, dry_run=True, full_size='large')
        self.assertEqual(result['examined'], 1)
        self.assertEqual(result['downloaded'], 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.fetcher.urls, [])
        result = self.run_download(limit=1, full_size='large')
        self.assertEqual(result['examined'], 1)
        self.assertTrue((self.output / 'full-cards/printing-one-0-large.jpg').is_file())
        self.assertIsNone(self.store.get_art('printing-one-0-normal.jpg'))

    def test_unsafe_hosts_paths_and_unbounded_or_incomplete_images_are_rejected(self):
        for url in ('http://cards.scryfall.io/x.jpg', 'https://cards.scryfall.io.evil.test/x.jpg',
                    'https://example.com/a.jpg', 'https://user:password@cards.scryfall.io/x.jpg'):
            with self.assertRaises(ValueError):downloader.check_url(url, image=True)
        for bad in (b'html', JPEG[:-2], JPEG * (downloader.MAX_IMAGE // len(JPEG) + 1)):
            with self.assertRaises(ValueError):downloader.validate_image(bad)
        self.assertEqual(list(downloader.image_jobs(card('../escape'))), [])
        self.assertEqual(list(downloader.image_jobs({'object': 'not-card'})), [])

    def test_streaming_metadata_bounds_and_old_array_fallback(self):
        with self.assertRaises(ValueError):list(downloader.jsonl_records(io.BytesIO(b'x' * (downloader.MAX_RECORD + 1))))
        with self.assertRaises(ValueError):list(downloader.jsonl_records(io.BytesIO(b'{broken}\n')))
        records = [card(), card('other')]
        self.assertEqual(list(downloader.array_records(io.StringIO(json.dumps(records)))), records)
        with self.assertRaises(ValueError):list(downloader.array_records(io.StringIO('[{')))

    def test_metadata_bootstrap_is_explicit_atomic_and_preserves_existing_source(self):
        raw = (json.dumps(card()) + '\n').encode()
        descriptor = {'jsonl_download_uri': 'https://data.scryfall.io/cards.jsonl.gz'}
        responses = [Response(json.dumps(descriptor).encode()), Response(gzip.compress(raw), descriptor['jsonl_download_uri'])]
        fake = type('Fetcher', (), {'open': lambda self, *args, **kwargs: responses.pop(0)})()
        downloader.bootstrap_metadata(self.source, 'default_cards', fake)
        self.assertEqual(list(downloader.read_metadata(self.source)), [card()])
        original = self.source.read_bytes()
        with self.assertRaises(ValueError):downloader.bootstrap_metadata(self.source, 'default_cards', fake)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertFalse(list(self.root.glob('*.part')))

    def test_http_headers_pacing_transient_retry_and_repeated_rate_limit_stop(self):
        requests = []
        responses = [HTTPError('https://cards.scryfall.io/a.jpg', 503, 'temporary', {}, None),
                     Response(JPEG, 'https://cards.scryfall.io/a.jpg')]
        def opened(request, **kwargs):
            requests.append(request)
            result = responses.pop(0)
            if isinstance(result, Exception):raise result
            return result
        sleeps = []
        opener = type('Opener', (), {'open': lambda self, *a, **kw: opened(*a, **kw)})()
        fetcher = downloader.Fetcher(opener=opener, sleep=sleeps.append, monotonic=lambda: 10)
        self.assertEqual(fetcher.image('https://cards.scryfall.io/a.jpg'), JPEG)
        self.assertEqual(len(requests), 2)
        self.assertTrue(requests[0].get_header('User-agent').startswith('Love2Gathering/'))
        self.assertEqual(requests[0].get_header('Accept'), 'image/jpeg')
        self.assertIn(1, sleeps)
        self.assertTrue(any(delay >= .14 for delay in sleeps))
        responses.extend([HTTPError('https://cards.scryfall.io/a.jpg', 429, 'rate limit', {'Retry-After': '11'}, None)] * 2)
        with self.assertRaises(HTTPError):fetcher.image('https://cards.scryfall.io/a.jpg')
        self.assertEqual(len(requests), 4)
        self.assertIn(11, sleeps)

    def test_interrupted_image_transfer_retries_without_accepting_partial_content(self):
        class Interrupted(Response):
            def read(self, *args):raise IncompleteRead(b'partial JPEG', 10)
        responses = [Interrupted(b'', 'https://cards.scryfall.io/a.jpg'), Response(JPEG, 'https://cards.scryfall.io/a.jpg')]
        opener = type('Opener', (), {'open': lambda self, *args, **kwargs: responses.pop(0)})()
        fetcher = downloader.Fetcher(opener=opener, sleep=lambda _: None)
        self.assertEqual(fetcher.image('https://cards.scryfall.io/a.jpg'), JPEG)
        self.assertFalse(responses)


if __name__ == '__main__':
    unittest.main()
