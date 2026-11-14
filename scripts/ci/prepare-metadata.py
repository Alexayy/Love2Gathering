#!/usr/bin/env python3
"""Explicit CI bulk metadata acquisition; never fetch images or open user storage."""
from __future__ import annotations
import argparse
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('l2g_metadata_downloader', ROOT / 'scripts/download-card-images.py')
DOWNLOADER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DOWNLOADER)
MAX_BYTES = 8 * 1024 ** 3
MAX_CARDS = 2_000_000


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
            max_bytes=MAX_BYTES, max_cards=MAX_CARDS):
    path = Path(path)
    report_path = Path(report_path) if report_path else path.with_suffix('.provenance.json')
    if path.resolve() == report_path.resolve():
        raise ValueError('Metadata and provenance need separate output paths')
    if bulk_type not in ('default_cards', 'all_cards'):
        raise ValueError('Choose default_cards or all_cards metadata')
    if path.suffix != '.jsonl' or min_cards < 1 or max_bytes < 1 or max_cards < min_cards:
        raise ValueError('Choose a .jsonl output and positive metadata limits')
    if path.exists() or path.is_symlink() or report_path.exists() or report_path.is_symlink():
        return validate_cache(path, report_path, bulk_type, min_cards)
    fetcher = fetcher or DOWNLOADER.Fetcher(.15, 3)
    with fetcher.open('https://api.scryfall.com/bulk-data/' + bulk_type) as response:
        raw = response.read(DOWNLOADER.MAX_RECORD + 1)
        if len(raw) > DOWNLOADER.MAX_RECORD:
            raise ValueError('Bulk metadata descriptor exceeds its bound')
        descriptor = json.loads(raw)
    if not isinstance(descriptor, dict) or descriptor.get('type') != bulk_type:
        raise ValueError('Unexpected Scryfall bulk metadata descriptor')
    uri = descriptor.get('jsonl_download_uri') or descriptor.get('download_uri')
    if not uri:
        raise ValueError('Bulk metadata descriptor has no download URL')
    DOWNLOADER.check_url(uri)
    count, size, digest = 0, 0, hashlib.sha256()
    with fetcher.open(uri, 'application/gzip, application/json;q=.9, */*;q=.5') as response:
        if descriptor.get('jsonl_download_uri'):
            stream = gzip.GzipFile(fileobj=response)
            records = DOWNLOADER.jsonl_records(stream)
        else:
            stream = io.TextIOWrapper(response, encoding='utf-8')
            records = DOWNLOADER.array_records(stream)
        with stream, DOWNLOADER.atomic_output(path, binary=True) as output:
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
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
