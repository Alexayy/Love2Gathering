#!/usr/bin/env python3
"""Explicit CI bulk metadata acquisition; never fetch images or open user storage."""
from __future__ import annotations
import argparse
import gzip
from http.client import HTTPException
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import time
from urllib.error import URLError
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('l2g_metadata_downloader', ROOT / 'scripts/download-card-images.py')
DOWNLOADER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DOWNLOADER)
MAX_BYTES = 8 * 1024 ** 3
MAX_CARDS = 2_000_000


class TransferReadError(Exception):
    """Only input I/O failures are retryable, never output writes or JSON rules."""
    def __init__(self, error):
        self.error = error
        super().__init__('Metadata response body was interrupted')


class TransferInput(io.BufferedIOBase):
    def __init__(self, response):
        self.response = response
    def readable(self):
        return True
    def read(self, size=-1):
        try:
            return self.response.read(size)
        except (HTTPException, URLError, OSError, EOFError) as error:
            raise TransferReadError(error) from error
    def read1(self, size=-1):
        return self.read(size)


def complete_get(fetcher, url, accept, consume, retries, pause):
    for attempt in range(retries + 1):
        # Fetcher already applies its bounded open/status/rate-limit retries.
        # Do not multiply that budget by retrying an exhausted open operation.
        response = fetcher.open(url, accept)
        try:
            return consume(response)
        except (EOFError, TransferReadError) as error:
            if attempt == retries:
                if isinstance(error, TransferReadError):
                    raise error.error from error
                raise
            print('Metadata body interrupted; retrying the complete GET (' + str(attempt + 1) + '/' + str(retries) + ')', file=sys.stderr)
            pause(min(8, 2 ** attempt))


def file_digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_cache(path, report_path, bulk_type, min_cards):
    if path.is_symlink() or report_path.is_symlink():
        raise ValueError('Metadata/cache provenance cannot be symbolic links')
    if not path.is_file() or not report_path.is_file():
        raise ValueError('Existing metadata has no complete provenance; preserve it and choose a new CI output path')
    if report_path.stat().st_size > 65536:
        raise ValueError('Metadata provenance exceeds its bound')
    report = json.loads(report_path.read_text(encoding='utf-8'))
    if (not isinstance(report, dict) or report.get('version') != 1 or report.get('bulkType') != bulk_type
            or report.get('metadataOnly') is not True or type(report.get('cards')) is not int
            or not min_cards <= report['cards'] <= MAX_CARDS
            or path.stat().st_size != report.get('bytes') or path.stat().st_size > MAX_BYTES
            or file_digest(path) != report.get('sha256')):
        raise ValueError('Cached metadata does not match its verified provenance; choose a new CI cache key/output')
    report = dict(report, reused=True)
    return report


def prepare(path, report_path=None, bulk_type='default_cards', min_cards=10000, fetcher=None,
            max_bytes=MAX_BYTES, max_cards=MAX_CARDS, stream_retries=3, pause=None):
    path = Path(path)
    report_path = Path(report_path) if report_path else path.with_suffix('.provenance.json')
    if path.resolve() == report_path.resolve():
        raise ValueError('Metadata and provenance need separate output paths')
    if bulk_type not in ('default_cards', 'all_cards'):
        raise ValueError('Choose default_cards or all_cards metadata')
    if path.suffix != '.jsonl' or min_cards < 1 or max_bytes < 1 or max_cards < min_cards or type(stream_retries) is not int or not 0 <= stream_retries <= 5:
        raise ValueError('Choose a .jsonl output and positive metadata limits')
    if path.exists() or path.is_symlink() or report_path.exists() or report_path.is_symlink():
        return validate_cache(path, report_path, bulk_type, min_cards)
    fetcher = fetcher or DOWNLOADER.Fetcher(.15, 3)
    pause = pause or getattr(fetcher, 'sleep', time.sleep)
    def read_descriptor(response):
        with response:
            raw = TransferInput(response).read(DOWNLOADER.MAX_RECORD + 1)
            if len(raw) > DOWNLOADER.MAX_RECORD:
                raise ValueError('Bulk metadata descriptor exceeds its bound')
            return json.loads(raw)
    descriptor = complete_get(fetcher, 'https://api.scryfall.com/bulk-data/' + bulk_type,
                              'application/json', read_descriptor, stream_retries, pause)
    if not isinstance(descriptor, dict) or descriptor.get('type') != bulk_type:
        raise ValueError('Unexpected Scryfall bulk metadata descriptor')
    uri = descriptor.get('jsonl_download_uri') or descriptor.get('download_uri')
    if not uri:
        raise ValueError('Bulk metadata descriptor has no download URL')
    DOWNLOADER.check_url(uri)
    def read_bulk(response):
        # Each body attempt owns a fresh digest/count and temporary output. The
        # connection and decompressor finish before atomic publication occurs.
        count, size, digest = 0, 0, hashlib.sha256()
        with DOWNLOADER.atomic_output(path, binary=True) as output:
            with response:
                raw = TransferInput(response)
                if descriptor.get('jsonl_download_uri'):
                    stream = gzip.GzipFile(fileobj=raw)
                    records = DOWNLOADER.jsonl_records(stream)
                else:
                    stream = io.TextIOWrapper(raw, encoding='utf-8')
                    records = DOWNLOADER.array_records(stream)
                with stream:
                    for record in records:
                        if record.get('object') != 'card' or not record.get('id') or not record.get('name'):
                            raise ValueError('The selected bulk contains a malformed/non-card record')
                        data = (json.dumps(record, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
                        count += 1;size += len(data)
                        if count > max_cards or size > max_bytes:
                            raise ValueError('Bulk metadata exceeds the configured CI resource bound')
                        output.write(data);digest.update(data)
                    if count < min_cards:
                        raise ValueError('Bulk metadata is unexpectedly small; no release source was installed')
        return count, size, digest
    count, size, digest = complete_get(fetcher, uri, 'application/gzip, application/json;q=.9, */*;q=.5',
                                     read_bulk, stream_retries, pause)
    report = {
        'version': 1, 'bulkType': bulk_type, 'metadataOnly': True, 'cards': count,
        'bytes': size, 'sha256': digest.hexdigest(), 'sourceUrl': uri,
        'providerId': descriptor.get('id'), 'sourceUpdatedAt': descriptor.get('updated_at'),
        'preparedAt': datetime.now(timezone.utc).isoformat(), 'reused': False,
    }
    with DOWNLOADER.atomic_output(report_path) as output:
        json.dump(report, output, indent=2);output.write('\n')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--bulk-type', choices=('default_cards', 'all_cards'), default='default_cards')
    parser.add_argument('--min-cards', type=int, default=10000)
    args = parser.parse_args(argv)
    result = prepare(args.output, args.report, args.bulk_type, args.min_cards)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    try:raise SystemExit(main())
    except (OSError, ValueError, EOFError, HTTPException, URLError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
