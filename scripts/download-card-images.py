#!/usr/bin/env python3
"""Stream printing/face metadata into restartable SQLite and separate JPEG mirrors.

No metadata or artwork is downloaded merely by starting the application. This
utility requires a local source or an explicit --bootstrap-metadata request.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import gzip
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'service'))
from storage import Storage
from paths import default_data_dir

MAX_IMAGE = 3 * 1024 * 1024
MAX_RECORD = 2 * 1024 * 1024
USER_AGENT = 'Love2Gathering/1.0 (offline artwork downloader; https://github.com/Alexayy/Love2Gathering)'
PRINTING_ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$')


class DownloadPaused(OSError):
    pass


@contextmanager
def cli_image_lock(root):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    fd=os.open(root/'.image-download.lock',os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)
    try:
        try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError as exc:raise ValueError('Another image download, scan or storage operation is active')from exc
        yield
    finally:os.close(fd)


@contextmanager
def null_lock():
    yield


def check_url(url, image=False):
    parsed = urlsplit(url)
    allowed = parsed.hostname == 'cards.scryfall.io' if image else (
        parsed.hostname == 'api.scryfall.com' or (parsed.hostname or '').endswith('.scryfall.io'))
    if parsed.scheme != 'https' or not allowed or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('Only HTTPS Scryfall image/metadata URLs are supported')
    return url


class ScryfallRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        check_url(new_url, image=urlsplit(request.full_url).hostname == 'cards.scryfall.io')
        return super().redirect_request(request, fp, code, message, headers, new_url)


class Fetcher:
    def __init__(self, interval=.15, retries=3, opener=None, sleep=time.sleep, monotonic=time.monotonic):
        self.interval = interval
        self.retries = retries
        self.sleep, self.monotonic = sleep, monotonic
        self.next_request = 0
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.opener = opener or build_opener(ScryfallRedirects(), HTTPSHandler(context=context))

    def open(self, url, accept='application/json', image=False):
        check_url(url, image=image)
        limited = False
        for attempt in range(self.retries + 1):
            self.sleep(max(0, self.next_request - self.monotonic()))
            self.next_request = self.monotonic() + self.interval
            try:
                response = self.opener.open(Request(url, headers={'User-Agent': USER_AGENT, 'Accept': accept}), timeout=30)
                check_url(response.geturl(), image=image)
                return response
            except HTTPError as exc:
                if exc.code == 429:
                    # Respect a rate-limit signal. A second signal stops rather
                    # than repeatedly trying to power through a server block.
                    if limited or attempt == self.retries:
                        raise
                    limited = True
                    try:
                        delay = max(10, min(120, float(exc.headers.get('Retry-After', '10'))))
                    except ValueError:
                        delay = 10
                    self.sleep(delay)
                elif exc.code not in (500, 502, 503, 504) or attempt == self.retries:
                    raise
                else:
                    self.sleep(min(8, 2 ** attempt))
            except (URLError, TimeoutError, OSError):
                if attempt == self.retries:
                    raise
                self.sleep(min(8, 2 ** attempt))
        raise RuntimeError('Request retry budget exhausted')

    def image(self, url):
        for attempt in range(self.retries + 1):
            response = self.open(url, 'image/jpeg', image=True)
            try:
                with response:
                    data = response.read(MAX_IMAGE + 1)
            except (HTTPException, OSError) as exc:
                if attempt == self.retries:
                    raise
                self.sleep(min(8, 2 ** attempt))
                continue
            validate_image(data)
            return data
        raise RuntimeError('Image transfer retry budget exhausted')


def validate_image(data):
    if not isinstance(data, bytes) or not 4 <= len(data) <= MAX_IMAGE or not data.startswith(b'\xff\xd8') or not data.endswith(b'\xff\xd9'):
        raise ValueError('Image must be a complete JPEG within the 3 MiB application bound')


@contextmanager
def atomic_output(path, binary=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = 'wb' if binary else 'w'
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode=mode, dir=path.parent, prefix=path.name + '.', suffix='.part', delete=False,
                                         **({} if binary else {'encoding': 'utf-8'})) as stream:
            temporary = Path(stream.name)
            yield stream
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def jsonl_records(stream):
    line_number = 0
    while True:
        line = stream.readline(MAX_RECORD + 1)
        if not line:
            return
        line_number += 1
        if len(line) > MAX_RECORD:
            raise ValueError(f'Metadata record {line_number} exceeds the 2 MiB streaming bound')
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except (ValueError, UnicodeDecodeError) as exc:
            raise ValueError(f'Invalid JSONL metadata on line {line_number}: {exc}') from exc
        if isinstance(record, dict):
            yield record


def array_records(stream):
    """Incremental fallback for older bulk descriptors containing a JSON array."""
    decoder = json.JSONDecoder()
    buffer = ''
    ended = False
    begun = False
    while True:
        buffer = buffer.lstrip()
        if not begun:
            if not buffer:
                chunk = stream.read(65536)
                if not chunk:
                    raise ValueError('Empty bulk metadata')
                buffer += chunk
                continue
            if buffer[0] != '[':
                raise ValueError('Bulk metadata must be a JSON array')
            buffer, begun = buffer[1:], True
            continue
        if buffer.startswith(','):
            buffer = buffer[1:]
            continue
        if buffer.startswith(']'):
            return
        try:
            record, position = decoder.raw_decode(buffer)
        except ValueError:
            if ended:
                raise ValueError('Incomplete or invalid bulk metadata')
            if len(buffer) > MAX_RECORD:
                raise ValueError('Bulk metadata record exceeds the 2 MiB streaming bound')
            chunk = stream.read(65536)
            ended = not chunk
            buffer += chunk
            continue
        if position > MAX_RECORD:
            raise ValueError('Bulk metadata record exceeds the 2 MiB streaming bound')
        if isinstance(record, dict):
            yield record
        buffer = buffer[position:]


def bootstrap_metadata(path, bulk_type, fetcher):
    path = Path(path)
    if path.exists():
        raise ValueError('Metadata destination already exists; choose a new path to preserve the original')
    with fetcher.open('https://api.scryfall.com/bulk-data/' + bulk_type) as response:
        descriptor = json.loads(response.read(MAX_RECORD + 1))
    uri = descriptor.get('jsonl_download_uri') or descriptor.get('download_uri')
    if not uri:
        raise ValueError('Scryfall did not provide a bulk download URI')
    check_url(uri)
    import io
    with fetcher.open(uri, 'application/gzip, application/json;q=.9, */*;q=.5') as response:
        with atomic_output(path) as output:
            if descriptor.get('jsonl_download_uri'):
                with gzip.GzipFile(fileobj=response) as uncompressed:
                    for card in jsonl_records(uncompressed):
                        output.write(json.dumps(card, ensure_ascii=False, separators=(',', ':')) + '\n')
            else:
                text = io.TextIOWrapper(response, encoding='utf-8')
                for card in array_records(text):
                    output.write(json.dumps(card, ensure_ascii=False, separators=(',', ':')) + '\n')
    return descriptor


def image_jobs(record, full_size='normal'):
    if record.get('object') != 'card':
        return
    printing = record.get('id', '')
    if not isinstance(printing, str) or not PRINTING_ID.fullmatch(printing):
        return
    faces = record.get('card_faces')
    # Split/adventure/flip cards share one printed scan. True image faces (for
    # example transform cards) carry their own image_uris and retain face IDs.
    image_faces = [(index, face) for index, face in enumerate(faces[:10])
                   if isinstance(face, dict) and face.get('image_uris')] if isinstance(faces, list) else []
    if not image_faces:
        image_faces = [(0, record)]
    for face, card in image_faces:
        if not isinstance(card, dict):
            continue
        images = card.get('image_uris') or record.get('image_uris') or {}
        if not isinstance(images, dict):
            continue
        for kind in (full_size, 'art_crop'):
            url = images.get(kind)
            if not url:
                continue
            check_url(url, image=True)
            key = f'{printing}-{face}-{kind}.jpg'
            yield {'key': key, 'url': url, 'directory': 'art-crops' if kind == 'art_crop' else 'full-cards',
                   'metadata': {'printingId': printing, 'oracleId': record.get('oracle_id') or printing,
                                'face': face, 'kind': kind, 'source': url, 'name': card.get('name') or record.get('name'),
                                'artist': card.get('artist') or record.get('artist')}}


def read_metadata(path):
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rb') as stream:
        yield from jsonl_records(stream)


def write_mirror(path, data):
    with atomic_output(path, binary=True) as output:
        output.write(data)


def download(metadata, output, store, fetcher, limit=0, dry_run=False, full_size='normal',reserve_bytes=0):
    stats = {'examined': 0, 'downloaded': 0, 'cached': 0, 'imported': 0, 'mirrored': 0, 'failed': 0,
             'bytesDownloaded': 0, 'dryRun': dry_run, 'errors': []}
    for record in read_metadata(metadata):
        for job in image_jobs(record, full_size):
            if limit and stats['examined'] >= limit:
                return stats
            stats['examined'] += 1
            if dry_run:
                continue
            path = Path(output) / job['directory'] / job['key']if output is not None else None
            try:
                data = store.get_art(job['key'])
                if data is not None:
                    stats['cached'] += 1
                elif path is not None and path.is_file() and path.stat().st_size <= MAX_IMAGE:
                    try:
                        data = path.read_bytes()
                        validate_image(data)
                    except ValueError:
                        data = None
                    if data is not None:
                        if reserve_bytes and shutil.disk_usage(store.root).free<reserve_bytes+MAX_IMAGE*3:
                            raise DownloadPaused('Paused to retain the configured free-space reserve; restart to import mirrors')
                        store.save_art(job['key'], data, job['metadata'])
                        stats['imported'] += 1
                if data is None:
                    if reserve_bytes and shutil.disk_usage(store.root).free<reserve_bytes+MAX_IMAGE*3:
                        raise DownloadPaused('Paused to retain the configured free-space reserve; restart to resume committed images')
                    data = fetcher.image(job['url'])
                    # Commit the authoritative copy first. A restart repairs a
                    # missing mirror without repeating the network request.
                    store.save_art(job['key'], data, job['metadata'])
                    stats['downloaded'] += 1
                    stats['bytesDownloaded'] += len(data)
                if path is not None and(not path.exists() or path.stat().st_size != len(data) or path.read_bytes() != data):
                    if reserve_bytes and shutil.disk_usage(store.root).free<reserve_bytes+MAX_IMAGE*3:
                        raise DownloadPaused('Paused to retain the configured free-space reserve; restart to repair mirrors')
                    write_mirror(path, data)
                    stats['mirrored'] += 1
            except DownloadPaused as exc:
                stats.update(paused=True,reason=str(exc));return stats
            except (ValueError, OSError, URLError, HTTPException) as exc:
                stats['failed'] += 1
                if len(stats['errors']) < 100:
                    stats['errors'].append({'key': job['key'], 'error': str(exc)})
    return stats


def parser():
    user_data = default_data_dir()
    p = argparse.ArgumentParser(description=__doc__)
    default_source = os.environ.get('LOVE2GATHERING_CATALOG_SOURCE') or next((PROJECT / 'assets').glob('all-cards*.jsonl'), PROJECT / 'assets/all-cards.jsonl')
    p.add_argument('--metadata', type=Path, default=Path(default_source), help='Local JSONL or JSONL.GZ printing metadata; never modified')
    p.add_argument('--bootstrap-metadata', choices=['default_cards', 'all_cards'], help='Explicitly download bulk metadata to a NEW --metadata path (can be several GB)')
    p.add_argument('--output', type=Path, default=user_data / 'image-library', help='Separate full-cards/ and art-crops/ JPEG mirrors')
    p.add_argument('--sql-only',action='store_true',help='Cache only in app.sqlite, without creating duplicate export JPEGs')
    p.add_argument('--reserve-gib',type=float,default=3,help='Pause image work before free space falls below this reserve (default 3 GiB)')
    p.add_argument('--data-dir', type=Path, default=user_data, help='Application data directory containing authoritative app.sqlite')
    p.add_argument('--full-size', choices=['normal', 'large'], default='normal', help='Full-card JPEG size (normal=488×680; large=672×936)')
    p.add_argument('--limit', type=int, default=0, help='Maximum image entries examined from the start; 0 means all')
    p.add_argument('--dry-run', action='store_true', help='Stream/count the selected entries without network or storage writes')
    p.add_argument('--interval', type=float, default=.15, help='Minimum seconds between requests; at least 0.11')
    p.add_argument('--retries', type=int, default=3, help='Bounded retries for transient failures, from 0 to 5')
    return p


def main(argv=None):
    p = parser();args = p.parse_args(argv)
    if args.limit < 0 or not .11 <= args.interval <= 60 or not 0 <= args.retries <= 5 or not 0<=args.reserve_gib<=1024:
        p.error('limit must be nonnegative, interval 0.11..60 seconds, retries 0..5 and reserve 0..1024 GiB')
    if args.dry_run and args.bootstrap_metadata:
        p.error('--dry-run cannot download metadata; supply an existing local source')
    if args.bootstrap_metadata and args.metadata.name.endswith('.gz'):
        p.error('Bootstrap produces plain JSONL for the catalog; choose a .jsonl metadata destination')
    try:
        fetcher = Fetcher(args.interval, args.retries)
        if args.bootstrap_metadata:
            bootstrap_metadata(args.metadata, args.bootstrap_metadata, fetcher)
        if not args.metadata.is_file():
            p.error('Metadata source is missing. Supply --metadata PATH or explicitly use --bootstrap-metadata TYPE with a new path.')
        store = None if args.dry_run else Storage(args.data_dir, PROJECT / 'decks')
        with cli_image_lock(args.data_dir)if store is not None else null_lock():
            stats = download(args.metadata, None if args.sql_only else args.output, store, fetcher, args.limit, args.dry_run, args.full_size,int(args.reserve_gib*1024**3))
        print(json.dumps(stats, ensure_ascii=False, indent=2))
        return 2 if stats.get('paused')else 1 if stats['failed'] else 0
    except KeyboardInterrupt:
        print('Interrupted; committed SQLite images and completed mirrors are retained for restart.', file=sys.stderr)
        return 130
    except (ValueError, OSError, URLError, HTTPException, EOFError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
