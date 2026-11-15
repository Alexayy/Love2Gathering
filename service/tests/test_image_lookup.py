"""Exact local images and bounded alias lookup against isolated SQLite stores."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from artwork import prefer_cached_card
from storage import Storage


JPEG = b'\xff\xd8' + b'isolated-image-overflow-fixture' * 4096 + b'\xff\xd9'


class ImageLookupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='love2gathering-image-lookup-')
        self.root = Path(self.temporary.name)
        self.store = Storage(self.root / 'data', self.root / 'bundled')

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def save(store, printing, kind='normal', face=0, oracle='oracle', data=JPEG):
        key = f'{printing}-{face}-{kind}.jpg'
        store.save_art(key, data, {'printingId': printing, 'oracleId': oracle, 'face': face, 'kind': kind})
        return key

    def test_selection_vm_never_reads_image_or_metadata_overflow_columns(self):
        for separate in (False, True):
            with self.subTest(separate=separate):
                store = Storage(self.root / ('split' if separate else 'combined'),
                                self.root / 'bundled', self.root / 'images' if separate else None)
                self.save(store, 'a-large', 'large')
                self.save(store, 'z-normal')
                statements = []
                with store.connection() as connection:
                    connection.set_trace_callback(statements.append)
                    keys = store._art_candidate_keys(connection, 'oracle', 0, 'normal', 40)
                    connection.set_trace_callback(None)
                    self.assertEqual(keys, ['z-normal-0-normal.jpg', 'a-large-0-large.jpg'])
                    schema = 'images' if separate else 'main'
                    root = connection.execute(f"SELECT rootpage FROM {schema}.sqlite_master WHERE name='art_cache'").fetchone()[0]
                    database = next(row[0] for row in connection.execute('PRAGMA database_list') if row[1] == schema)
                    for statement in statements:
                        instructions = list(connection.execute('EXPLAIN ' + statement))
                        table_cursors = {row[2] for row in instructions
                                         if row[1] == 'OpenRead' and row[3] == root and row[4] == database}
                        self.assertTrue(table_cursors, 'The regression inspects actual SQLite table-read instructions')
                        self.assertFalse(any(row[1] == 'Column' and row[2] in table_cursors and row[3] in (1, 3)
                                             for row in instructions),
                                         'Identity selection must not read content or metadata after the BLOB')
                        self.assertFalse(any(row[1] == 'Function' and 'json_extract' in str(row[5])
                                             for row in instructions),
                                         'The existing expression index must supply every filter value')

    def test_kind_preference_and_limit_apply_across_both_indexed_queries(self):
        self.save(self.store, 'a-large', 'large')
        for printing in ('z-normal', 'm-normal', 'n-normal'):
            self.save(self.store, printing)
        with self.store.connection() as connection:
            self.assertEqual(self.store._art_candidate_keys(connection, 'oracle', 0, 'normal', 2),
                             ['m-normal-0-normal.jpg', 'n-normal-0-normal.jpg'])
            self.assertEqual(self.store._art_candidate_keys(connection, 'oracle', 0, 'normal', 4),
                             ['m-normal-0-normal.jpg', 'n-normal-0-normal.jpg', 'z-normal-0-normal.jpg', 'a-large-0-large.jpg'])
            self.assertEqual(self.store._art_candidate_keys(connection, 'oracle', 0, 'normal', 0), [])

    def test_local_alias_keeps_actual_printing_face_and_kind(self):
        self.save(self.store, 'front')
        expected = JPEG + b'back'
        key = self.save(self.store, 'back', 'large', face=1, data=expected)
        self.save(self.store, 'crop', 'art_crop', face=1)
        self.save(self.store, 'other', face=1, oracle='another-oracle')
        data, actual_key, metadata = self.store.local_art('requested', 'oracle', face=1)
        self.assertEqual((data, actual_key, metadata['printingId'], metadata['face'], metadata['kind']),
                         (expected, key, 'back', 1, 'large'))
        self.assertIsNone(self.store.local_art('requested', 'missing-oracle', face=1))

    def test_exact_printing_lookup_never_uses_an_oracle_alias(self):
        key = self.save(self.store, 'chosen')
        self.save(self.store, 'another')
        with patch.object(self.store, '_art_candidate_keys', side_effect=AssertionError('Exact lookup searched aliases')):
            self.assertEqual(self.store.local_art('chosen', 'oracle', aliases=False)[1], key)
            self.assertIsNone(self.store.local_art('missing', 'oracle', aliases=False))

    def test_preferred_cached_card_decodes_only_examined_metadata_and_skips_invalid_printing(self):
        for printing in ('a-invalid', 'b-valid', 'c-unexamined'):
            self.save(self.store, printing)
        calls = []
        class Catalog:
            def get(self, identifier, printing_id):
                calls.append(printing_id)
                if printing_id == 'a-invalid': raise ValueError('Printing not in this snapshot')
                return {'id': identifier, 'printing_id': printing_id}
        decoded = []
        original = json.loads
        def tracked(value, *args, **kwargs):
            if isinstance(value, str) and 'printingId' in value: decoded.append(value)
            return original(value, *args, **kwargs)
        with patch('artwork.json.loads', side_effect=tracked):
            result = prefer_cached_card(Catalog(), self.store, {'id': 'oracle', 'printing_id': 'missing'})
        self.assertEqual(result['printing_id'], 'b-valid')
        self.assertEqual(calls, ['a-invalid', 'b-valid'])
        self.assertEqual(len(decoded), 2)

    def test_purge_and_replacement_never_serve_a_stale_in_memory_result(self):
        self.save(self.store, 'chosen')
        self.assertEqual(self.store.local_art('chosen', 'oracle')[0], JPEG)
        replacement = JPEG + b'replaced'
        self.save(self.store, 'chosen', data=replacement)
        self.assertEqual(self.store.local_art('chosen', 'oracle')[0], replacement)
        self.store.purge_storage(['full_cards'])
        self.assertIsNone(self.store.local_art('chosen', 'oracle'))
        self.assertEqual(self.store.art_candidates('oracle'), [])


if __name__ == '__main__':
    unittest.main()
