"""Cold metadata indexing reports all input, then publishes a complete index."""
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
import filelocks


def card(number, language='en'):
    return {'object': 'card', 'id': f'printing-{number}', 'oracle_id': f'oracle-{number}',
            'name': f'Card {number}', 'lang': language, 'type_line': 'Creature',
            'image_uris': {'normal': f'https://example.invalid/{number}.jpg',
                           'art_crop': f'https://example.invalid/{number}-art.jpg'},
            'colors': [], 'color_identity': [], 'legalities': {'modern': 'legal'}}


class CatalogIndexingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='love2gathering-index-test-')
        self.root = Path(self.temporary.name)
        self.source = self.root / 'cards.jsonl'
        self.database = self.root / 'catalog.sqlite'

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, records, compressed=False):
        self.source = self.root / ('cards.jsonl.gz' if compressed else 'cards.jsonl')
        content = '\n'.join(json.dumps(item, ensure_ascii=False) for item in records) + '\n'
        if compressed:
            with gzip.open(self.source, 'wt', encoding='utf-8') as stream:
                stream.write(content)
        else:
            self.source.write_text(content, encoding='utf-8')

    def observed(self):
        catalog = Catalog(self.source, self.database)
        updates, original = [], catalog._status

        def status(**fields):
            original(**fields)
            updates.append(catalog.status())

        catalog._status = status
        return catalog, updates

    def test_translations_and_non_cards_advance_progress_before_first_english_card(self):
        self.write([card(number, 'fr') for number in range(1, 80)]
                   + [{'object': 'set', 'name': 'Non-card metadata'}] * 20 + [card(100)])
        catalog, updates = self.observed()
        ticks = itertools.count()
        with patch('catalog.time.monotonic', side_effect=lambda: next(ticks) * .1):
            catalog.ensure()
        self.assertEqual(catalog.status()['state'], 'ready', catalog.status())
        reading = [item for item in updates if item['phase'] == 'reading' and 1 < item['lines'] < 100]
        self.assertGreater(len(reading), 5)
        self.assertTrue(all(item['cards'] == 0 for item in reading))
        self.assertGreater(reading[-1]['lines'], 90)
        self.assertGreater(reading[-1]['bytesRead'], 0)
        self.assertEqual(catalog.status()['lines'], 100)
        self.assertEqual(catalog.status()['cards'], 1)

    def test_gzip_progress_uses_bounded_compressed_bytes_and_retains_every_printing(self):
        self.write([card(number, 'fr' if number % 2 else 'en') for number in range(3000)], compressed=True)
        source_hash = hashlib.sha256(self.source.read_bytes()).hexdigest()
        catalog, updates = self.observed()
        ticks = itertools.count()
        with patch('catalog.time.monotonic', side_effect=lambda: next(ticks) * .1):
            catalog.ensure()
        self.assertEqual(catalog.status()['state'], 'ready', catalog.status())
        reading = [item for item in updates if item['phase'] == 'reading']
        values = [item['bytesRead'] for item in reading]
        self.assertEqual(values, sorted(values))
        self.assertTrue(all(0 <= value <= self.source.stat().st_size for value in values))
        self.assertGreater(len(set(values)), 1)
        self.assertEqual(catalog.status()['bytesRead'], self.source.stat().st_size)
        self.assertEqual(catalog.search()['total'], 1500)
        self.assertEqual(catalog.gallery(language='all')['total'], 3000)
        self.assertEqual(hashlib.sha256(self.source.read_bytes()).hexdigest(), source_hash)

    def test_every_search_index_is_complete_before_ready_and_reopen_reuses_it(self):
        self.write([card(1), card(2)])
        catalog, updates = self.observed()
        catalog.ensure()
        phases = [item['phase'] for item in updates]
        self.assertIn('indexes', phases)
        indexing = [item for item in updates if item['phase'] == 'indexes']
        self.assertEqual(indexing[-1]['indexesDone'], indexing[-1]['indexesTotal'])
        with catalog.connect() as connection:
            names = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='index'")}
        self.assertTrue({'cards_name', 'card_sets_card', 'card_sets_set', 'gallery_artist',
                         'gallery_name', 'gallery_variant', 'gallery_set', 'token_names',
                         'token_printings', 'token_oracles', 'cards_modern', 'cards_standard',
                         'cards_pioneer', 'cards_commander'} <= names)
        digest = hashlib.sha256(self.database.read_bytes()).hexdigest()
        reopened = Catalog(self.source, self.database)
        with patch.object(reopened, 'build', side_effect=AssertionError('Fresh index was rebuilt')):
            reopened.ensure()
        self.assertEqual(reopened.status()['state'], 'ready')
        self.assertEqual(reopened.status()['cards'], 2)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).hexdigest(), digest)

    def test_source_changed_during_import_preserves_previous_complete_index(self):
        self.write([card(1)])
        previous = Catalog(self.source, self.database)
        previous.ensure()
        digest = hashlib.sha256(self.database.read_bytes()).hexdigest()
        self.write([card(2)])
        catalog, _ = self.observed()
        original = catalog.index_gallery
        changed = False

        def change_source(connection, raw):
            nonlocal changed
            original(connection, raw)
            if not changed:
                with self.source.open('a', encoding='utf-8') as stream:
                    stream.write('\n')
                changed = True

        catalog.index_gallery = change_source
        catalog.ensure()
        self.assertEqual(catalog.status()['state'], 'error')
        self.assertIn('source changed', catalog.status()['error'])
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).hexdigest(), digest)
        self.assertFalse(self.database.with_suffix('.building.sqlite').exists())
        self.assertEqual(previous.get(name='Card 1')['name'], 'Card 1')

    def test_failed_index_creation_preserves_previous_complete_index(self):
        self.write([card(1)])
        catalog = Catalog(self.source, self.database)
        catalog.ensure()
        digest = hashlib.sha256(self.database.read_bytes()).hexdigest()
        self.write([card(2)])
        with patch.object(catalog, '_build_indexes', side_effect=sqlite3.OperationalError('disk full fixture')):
            catalog.ensure()
        self.assertEqual(catalog.status()['state'], 'error')
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).hexdigest(), digest)
        self.assertFalse(self.database.with_suffix('.building.sqlite').exists())
        self.assertEqual(catalog.get(name='Card 1')['name'], 'Card 1')

    def test_another_instance_build_lock_reports_waiting_with_elapsed_time(self):
        self.write([card(1)])
        catalog = Catalog(self.source, self.database)
        lock_path = self.database.parent / (self.database.name + '.build.lock')
        worker = threading.Thread(target=catalog.ensure, daemon=True)
        with lock_path.open('a+b') as lock:
            filelocks.flock(lock, filelocks.LOCK_EX)
            worker.start()
            try:
                until = time.monotonic() + 3
                while catalog.status()['phase'] != 'waiting' and time.monotonic() < until:
                    time.sleep(.005)
                self.assertEqual(catalog.status()['phase'], 'waiting')
                self.assertIn('another local card index', catalog.status()['message'])
                time.sleep(.15)
                self.assertGreaterEqual(catalog.status()['seconds'], .1)
                self.assertFalse(self.database.exists())
            finally:
                filelocks.flock(lock, filelocks.LOCK_UN)
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(catalog.status()['state'], 'ready', catalog.status())


if __name__ == '__main__':
    unittest.main()
