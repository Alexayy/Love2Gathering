"""Explicit, bounded Starter image packs. No network or automatic installation."""
from collections import OrderedDict
from contextlib import ExitStack, closing, nullcontext
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import struct
import threading
import time
from urllib.parse import urlsplit
import uuid
import zipfile

from artwork import ArtworkStore
from maintenance import operation_lock
from replays import ConflictError, encode, now

FORMAT = 'love2gathering-starter-images'
MAX_IMAGES = 4000
MAX_IMAGE = 3 * 1024**2
MAX_MANIFEST = 1024**2
MAX_ARCHIVE = 2 * 1024**3
RESERVE_BYTES = 64 * 1024**2
IDENTITY = re.compile(r'[A-Za-z0-9_-]{1,100}\Z')
SHA256 = re.compile(r'[a-f0-9]{64}\Z')
KINDS = ('normal', 'large', 'art_crop')


def _source(value):
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError('Image source must be one catalog Scryfall image URL')
    parsed = urlsplit(value)
    if parsed.scheme != 'https' or parsed.hostname != 'cards.scryfall.io' or parsed.username or parsed.password or parsed.port not in (None, 443) or parsed.fragment:
        raise ValueError('Image packs accept only HTTPS cards.scryfall.io image sources')
    return value


def _identity(path):
    info = path.stat()
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def _entry(value, catalog, image=True):
    required = {'printingId', 'oracleId', 'face', 'kind', 'source', 'name'}
    required |= {'path', 'size', 'sha256'} if image else {'reason'}
    if not isinstance(value, dict) or set(value) != required:
        raise ValueError('Image pack entry has missing or unknown identity fields')
    if any(not isinstance(value[key], str) or not IDENTITY.fullmatch(value[key]) for key in ('printingId', 'oracleId')):
        raise ValueError('Invalid image printing or Oracle identity')
    face, kind = value['face'], value['kind']
    if isinstance(face, bool) or not isinstance(face, int) or not 0 <= face <= 9 or kind not in KINDS:
        raise ValueError('Invalid image face or image kind')
    if not isinstance(value['name'], str) or not 1 <= len(value['name']) <= 300:
        raise ValueError('Image pack card names must be bounded')
    _source(value['source'])
    item = catalog.gallery_item(value['printingId'], face)
    if not item or item['oracle_id'] != value['oracleId'] or item['image_uris'].get(kind) != value['source'] or value['name'] not in (item['name'], item.get('card_name')):
        raise ValueError('Image pack printing, Oracle, face or source does not match the local catalog')
    if image:
        expected = ('art-crops/' if kind == 'art_crop' else 'full-cards/') + f"{value['printingId']}-{face}-{kind}.jpg"
        if value['path'] != expected:
            raise ValueError('Image pack path must match its exact printing, face and kind')
        if isinstance(value['size'], bool) or not isinstance(value['size'], int) or not 2 <= value['size'] <= MAX_IMAGE:
            raise ValueError('Image pack JPEG exceeds the 3 MiB limit')
        if not isinstance(value['sha256'], str) or not SHA256.fullmatch(value['sha256']):
            raise ValueError('Image pack requires a SHA256 checksum for every JPEG')
    elif not isinstance(value['reason'], str) or not 1 <= len(value['reason']) <= 300:
        raise ValueError('Missing image entries need a bounded explanation')
    return value


def _bounded_zip(stream):
    """Reject oversized central directories before ZipFile allocates entries."""
    stream.seek(0, 2)
    size = stream.tell()
    if not 22 <= size <= MAX_ARCHIVE:
        raise ValueError('Image pack archive must be at most 2 GiB')
    stream.seek(max(0, size - 65557))
    tail = stream.read(65557)
    offset = tail.rfind(b'PK\x05\x06')
    if offset < 0 or len(tail) - offset < 22:
        raise ValueError('Image pack is not a complete ZIP archive')
    _, disk, directory_disk, disk_count, count, directory_size, directory_offset, comment = struct.unpack('<4s4H2LH', tail[offset:offset+22])
    if disk or directory_disk or disk_count != count or count > MAX_IMAGES + 1 or directory_size > 2 * MAX_MANIFEST or directory_offset + directory_size > size or len(tail) - offset != 22 + comment:
        raise ValueError('Image pack ZIP directory exceeds its bounded single-volume format')
    stream.seek(0)
    return zipfile.ZipFile(stream)


def _read_image(archive, entry, stopped=lambda: False, checkpoint=lambda: None):
    data = bytearray()
    digest = hashlib.sha256()
    with archive.open(entry['path']) as source:
        while True:
            checkpoint()
            if stopped(): raise ConflictError('Image pack operation stopped; committed images are retained')
            part = source.read(min(65536, MAX_IMAGE + 1 - len(data)))
            if not part: break
            data.extend(part);digest.update(part)
            if len(data) > MAX_IMAGE: raise ValueError('Image pack JPEG exceeds the 3 MiB limit')
    if len(data) != entry['size'] or digest.hexdigest() != entry['sha256'] or not data.startswith(b'\xff\xd8'):
        raise ValueError('Image pack JPEG size, signature or SHA256 checksum does not match')
    return bytes(data)


def validate_archive(stream, catalog, stopped=lambda: False, progress=None, checkpoint=lambda: None):
    with _bounded_zip(stream) as archive:
        infos = archive.infolist();seen = set();total = 0
        for info in infos:
            mode = info.external_attr >> 16
            if info.filename.casefold() in seen or '\\' in info.filename or '\x00' in info.filename or info.is_dir() or stat.S_IFMT(mode) not in (0, stat.S_IFREG) or info.flag_bits & 1 or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise ValueError('Image pack contains duplicate, encrypted, linked or unsafe ZIP entries')
            seen.add(info.filename.casefold());total += info.file_size
            if info.file_size < 0 or info.file_size > (MAX_MANIFEST if info.filename == 'manifest.json' else MAX_IMAGE) or total > MAX_ARCHIVE:
                raise ValueError('Image pack uncompressed contents exceed their size limits')
        try:
            raw = archive.read('manifest.json')
        except KeyError as exc: raise ValueError('Image pack is missing manifest.json') from exc
        if len(raw) > MAX_MANIFEST: raise ValueError('Image pack manifest exceeds 1 MiB')
        try: manifest = json.loads(raw)
        except (ValueError, UnicodeDecodeError) as exc: raise ValueError('Image pack manifest is not valid JSON') from exc
        if not isinstance(manifest, dict) or set(manifest) != {'format', 'version', 'complete', 'decks', 'images', 'missing'} or manifest.get('format') != FORMAT or type(manifest.get('version')) is not int or manifest['version'] != 1 or type(manifest.get('complete')) is not bool:
            raise ValueError('Image pack requires the supported version 1 manifest')
        images, missing, decks = manifest['images'], manifest['missing'], manifest['decks']
        if not isinstance(images, list) or not isinstance(missing, list) or len(images) + len(missing) > MAX_IMAGES or not isinstance(decks, list) or not 1 <= len(decks) <= 100 or manifest['complete'] != (not missing):
            raise ValueError('Image pack counts or completeness declaration are invalid')
        for deck in decks:
            if not isinstance(deck, dict) or set(deck) != {'id', 'name'} or any(not isinstance(deck[k], str) or not 1 <= len(deck[k]) <= 300 for k in ('id', 'name')):
                raise ValueError('Image pack deck labels are invalid')
        identities = set();expected = {'manifest.json'}
        for image in images:
            checkpoint()
            _entry(image, catalog)
            identity = (image['printingId'], image['face'], image['kind'])
            if identity in identities: raise ValueError('Image pack repeats an image identity')
            identities.add(identity);expected.add(image['path'])
            try: info = archive.getinfo(image['path'])
            except KeyError as exc: raise ValueError('Image pack is missing a declared JPEG') from exc
            if info.file_size != image['size']: raise ValueError('Image pack declared JPEG size differs from its ZIP entry')
        for image in missing:
            checkpoint()
            _entry(image, catalog, image=False)
            identity = (image['printingId'], image['face'], image['kind'])
            if identity in identities: raise ValueError('Image pack repeats an available or missing identity')
            identities.add(identity)
        if {info.filename for info in infos} != expected:
            raise ValueError('Image pack contains undeclared files or unsafe paths')
        for index, image in enumerate(images):
            _read_image(archive, image, stopped, checkpoint)
            if progress: progress(index + 1, len(images))
        return manifest, hashlib.sha256(raw).hexdigest()


class ImagePacks:
    def __init__(self, catalog, storage, *, disk_usage=shutil.disk_usage):
        self.catalog, self.storage, self.disk_usage = catalog, storage, disk_usage
        enable=getattr(storage,'enable_thumbnails',None)
        if enable is not None:enable()
        self.lock = threading.RLock();self.stop = threading.Event();self.thread = None;self.preview = None
        self.state = {'state': 'idle', 'progress': 0, 'reserveBytes': RESERVE_BYTES}

    def _background(self):
        coordinator=getattr(self.storage,'image_io',None)
        return coordinator.background(self.stop)if coordinator is not None else nullcontext()

    def _checkpoint(self):
        coordinator=getattr(self.storage,'image_io',None)
        if coordinator is not None:coordinator.checkpoint()

    def status(self):
        with self.lock: return deepcopy(self.state)

    def _update(self, **values):
        with self.lock: self.state.update(values)

    def _idle(self):
        if self.thread and self.thread.is_alive(): raise ConflictError('An image pack operation is already running')
        self.stop.clear()

    def inspect(self, path):
        with self.lock:
            self._idle()
            if not isinstance(path, str) or not path or len(path) > 4096: raise ValueError('Choose one local image pack ZIP file')
            selected = Path(path).expanduser().absolute()
            if selected.is_symlink() or not selected.is_file(): raise ValueError('Choose a regular local image pack ZIP file')
            self.preview = None
            self.state = {'state': 'inspecting', 'jobId': uuid.uuid4().hex, 'path': str(selected), 'progress': 0, 'reserveBytes': RESERVE_BYTES}
            self.thread = threading.Thread(target=self._inspect, args=(selected,), daemon=True);self.thread.start()
            return self.status()

    def _cached(self, images):
        keys = [Path(image['path']).name for image in images];cached = set()
        for start in range(0, len(keys), 256):
            selected = keys[start:start+256]
            with self.storage.connection() as connection:
                cached.update(row[0] for row in connection.execute('SELECT cache_key FROM art_cache WHERE cache_key IN (' + ','.join('?' for _ in selected) + ')', selected))
        return cached

    def _inspect(self, path):
        try:
            with self._background(), operation_lock(self.storage.root, blocking=False), path.open('rb') as stream:
                identity = _identity(path)
                manifest, digest = validate_archive(stream, self.catalog, self.stop.is_set, lambda done, total: self._update(progress=done/max(1, total)), self._checkpoint)
                if identity != _identity(path): raise ConflictError('Image pack changed during inspection; inspect it again')
                cached = self._cached(manifest['images'])
                with self.lock: self.preview = (identity, manifest, digest)
                self._update(state='ready', images=len(manifest['images']), totalBytes=sum(v['size'] for v in manifest['images']), cached=len(cached), missing=len(manifest['images'])-len(cached), missingEntries=len(manifest['missing']), complete=manifest['complete'], decks=len(manifest['decks']), progress=1, processed=0, installed=0, skipped=0, error=None)
        except Exception as exc: self._update(state='error', error=str(exc))

    def install(self, job_id):
        from downloads import image_job_lock
        with self.lock:
            self._idle()
            if self.state.get('state') != 'ready' or job_id != self.state.get('jobId') or self.preview is None:
                raise ConflictError('Inspect this image pack before choosing Install')
            if _identity(Path(self.state['path'])) != self.preview[0]: raise ConflictError('Image pack changed; inspect it again before installing')
            guards = ExitStack()
            try:
                guards.enter_context(image_job_lock(self.storage.root, blocking=False))
                guards.enter_context(operation_lock(self.storage.root, blocking=False))
            except ConflictError as exc:
                guards.close()
                raise ConflictError('Pause the active image download or scan and finish storage maintenance before installing an image pack') from exc
            self._update(state='importing', progress=0, processed=0, installed=0, skipped=0, error=None)
            self.thread = threading.Thread(target=self._install, args=(guards,), daemon=True)
            try: self.thread.start()
            except BaseException: guards.close();raise
            return self.status()

    def _install(self, guards):
        try:
            with guards, self._background(), Path(self.state['path']).open('rb') as stream:
                identity, preview, expected_digest = self.preview
                manifest, digest = validate_archive(stream, self.catalog, self.stop.is_set, checkpoint=self._checkpoint)
                if digest != expected_digest or _identity(Path(self.state['path'])) != identity:
                    raise ConflictError('Image pack changed; inspect it again before installing')
                stream.seek(0)
                with _bounded_zip(stream) as archive:
                    installed = skipped = 0
                    for index, image in enumerate(manifest['images']):
                        self._checkpoint()
                        if self.stop.is_set(): raise ConflictError('Image pack import stopped; committed images are retained')
                        key = Path(image['path']).name
                        with self.storage.connection() as connection:
                            exists = connection.execute('SELECT 1 FROM art_cache WHERE cache_key=?', (key,)).fetchone()
                        if exists: skipped += 1
                        else:
                            if min(self.disk_usage(self.storage.root).free, self.disk_usage(self.storage.cache_root).free) < RESERVE_BYTES + image['size'] * 3:
                                raise ConflictError('Free disk space before installing this image pack; at least 64 MiB plus room for the next image is retained. Already installed images are safe; inspect and install again to resume.')
                            data = _read_image(archive, image, self.stop.is_set, self._checkpoint)
                            metadata = {key: image[key] for key in ('printingId', 'oracleId', 'face', 'kind', 'source', 'name')}
                            metadata['imagePack'] = {'version': 1, 'manifestSha256': digest}
                            with self.storage.connection(write=True) as connection:
                                changed = connection.execute("INSERT OR IGNORE INTO art_cache VALUES (?,?,'image/jpeg',?,?)", (key, sqlite3.Binary(data), encode(metadata), now())).rowcount
                            installed += changed;skipped += not changed
                            queue=getattr(self.storage,'queue_thumbnail',None)
                            if changed and queue is not None:queue(key)
                            flush=getattr(self.storage,'flush_thumbnails',None)
                            if changed and installed%32==0 and flush is not None:flush(timeout=.25)
                        self._update(processed=index+1, installed=installed, skipped=skipped, progress=(index+1)/max(1, len(manifest['images'])))
                        self.stop.wait(.005)
                self._update(state='completed', progress=1, cached=len(manifest['images']), missing=0)
        except Exception as exc: self._update(state='error', error=str(exc))

    def close(self):
        self.stop.set()
        thread = self.thread
        if thread and thread is not threading.current_thread(): thread.join(2)


class ReadonlyImages:
    """The exporter never constructs Storage or runs source migrations."""
    def __init__(self, database, cache=None):
        self.database = Path(database).resolve();self.connection = None
        if not self.database.is_file(): raise ValueError('Existing application database is missing')
        with closing(sqlite3.connect(self.database.as_uri() + '?mode=ro', uri=True)) as main:
            if cache is None:
                row = main.execute("SELECT value FROM meta WHERE key='image_cache_directory'").fetchone()
                cache = Path(row[0]) / 'images.sqlite' if row else self.database
            self.path = Path(cache).resolve()
        if not self.path.is_file(): raise ValueError('Existing image cache database is missing')
        self.connection = sqlite3.connect(self.path.as_uri() + '?mode=ro', uri=True, isolation_level=None)
        self.connection.row_factory = sqlite3.Row

    def close(self):
        if self.connection is not None: self.connection.close();self.connection = None

    def read(self, key, content=False):
        columns = 'content,metadata' if content else 'length(content) AS size,metadata'
        row = self.connection.execute('SELECT ' + columns + ' FROM art_cache WHERE cache_key=? AND length(content) BETWEEN 2 AND ?', (key, MAX_IMAGE)).fetchone()
        return dict(row) if row else None

    def printing(self, oracle):
        keys = ArtworkStore._art_candidate_keys(self.connection, oracle, 0, 'normal', 1)
        if not keys: keys = ArtworkStore._art_candidate_keys(self.connection, oracle, 0, 'art_crop', 1)
        if not keys: return None
        # The indexed predicates already prove Oracle/face/kind. The exact
        # per-image metadata is checked later; choosing a printing must not
        # visit another cold post-BLOB metadata page for every Starter card.
        for kind in ('normal', 'large', 'art_crop'):
            suffix = '-0-' + kind + '.jpg'
            if keys[0].endswith(suffix): return keys[0][:-len(suffix)]
        return None


class EmptyImages:
    """An explicit CI build can acquire a pack without opening user storage."""
    def printing(self, oracle): return None
    def read(self, key, content=False): return None
    def close(self): pass


def starter_plan(catalog, source, decks_dir, deck_ids=None, full_size='normal', progress=None):
    if full_size not in ('normal', 'large'): raise ValueError('Choose normal or large full-card scans')
    selected = set(deck_ids or []);decks = [];names = {};exact = []
    if len(selected) > 100: raise ValueError('Choose at most 100 Starter decks')
    for path in sorted(Path(decks_dir).glob('*.json')):
        if path.stat().st_size > MAX_MANIFEST: continue
        deck = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(deck, dict) or not deck.get('id') or not isinstance(deck.get('main'), list) or selected and deck['id'] not in selected: continue
        if len(decks) >= 100: raise ValueError('Starter deck selection exceeds 100 lists')
        decks.append({'id': deck['id'], 'name': deck['name']})
        for zone in ('main', 'commander', 'sideboard'):
            for item in deck.get(zone, []): names[item['name']] = True
        exact.extend(v['printingId'] for v in deck.get('printingSelections', []) if v.get('printingId'))
    if not decks or selected - {deck['id'] for deck in decks}: raise ValueError('Selected Starter deck list is missing')
    if len(names) > 2000 or len(exact) > 2000: raise ValueError('Selected Starter deck cards exceed the bounded pack size')
    cards = {}
    for index, name in enumerate(names):
        if progress: progress('Selecting Starter cards', index, len(names))
        card = catalog.get(name=name)
        if not card: raise ValueError('Starter card is absent from the local catalog: ' + name)
        printing = source.printing(card['id'])
        if printing:
            try: card = catalog.get(identifier=card['id'], printing_id=printing) or card
            except ValueError: pass
        cards[card['printing_id']] = card
    for printing in exact:
        item = catalog.gallery_item(printing, 0)
        if not item: raise ValueError('Selected Starter printing is absent from the local catalog')
        cards[printing] = catalog.get(identifier=item['oracle_id'], printing_id=printing)
    available = [];missing = []
    for index, card in enumerate(cards.values()):
        if progress: progress('Checking cached Starter images', index, len(cards))
        faces = [(i, face) for i, face in enumerate((card.get('card_faces') or [])[:10]) if face.get('image_uris')]
        if not faces: faces = [(0, card)]
        for face, value in faces:
            images = value.get('image_uris') or card.get('image_uris') or {}
            for kind in (full_size, 'art_crop'):
                url = images.get(kind)
                if not url: continue
                entry = {'printingId': card['printing_id'], 'oracleId': card['id'], 'face': face, 'kind': kind, 'source': _source(url), 'name': value.get('name') or card['name']}
                key = f"{card['printing_id']}-{face}-{kind}.jpg"
                row = source.read(key)
                if not row and kind == 'normal':
                    large_key = f"{card['printing_id']}-{face}-large.jpg"
                    row = source.read(large_key)
                    if row and images.get('large'): kind = 'large';key = large_key;entry.update(kind=kind, source=_source(images['large']))
                    else: row = None
                if row:
                    metadata = json.loads(row['metadata'])
                    if metadata.get('printingId', card['printing_id']) != card['printing_id'] or metadata.get('oracleId', card['id']) != card['id'] or metadata.get('face', face) != face or metadata.get('kind', kind) != kind: row = None
                if row:
                    entry.update(path=('art-crops/' if kind == 'art_crop' else 'full-cards/') + key, size=row['size'])
                    available.append(entry)
                else: entry['reason'] = 'Not present in the selected local SQL image cache';missing.append(entry)
                if len(available) + len(missing) > MAX_IMAGES: raise ValueError('Starter image pack exceeds 4000 entries')
    if progress: progress('Starter image plan ready', len(available), len(available) + len(missing))
    return {'format': FORMAT, 'version': 1, 'complete': not missing, 'decks': decks, 'images': available, 'missing': missing}


def export_starter_pack(catalog, source, decks_dir, output, deck_ids=None, full_size='normal', progress=None):
    return _write_pack(catalog, source, decks_dir, output, deck_ids, full_size, progress)


def build_starter_pack(catalog, source, decks_dir, output, deck_ids=None, full_size='normal', progress=None, fetcher=None):
    """Explicit acquisition writes only a NEW ZIP staging file, never SQL."""
    if Path(output).expanduser().absolute().exists(): raise ValueError('Choose a new image pack output file; existing files are preserved')
    if fetcher is None:
        from downloads import _cli
        fetcher = _cli.Fetcher(.15, 3)
    try: return _write_pack(catalog, source, decks_dir, output, deck_ids, full_size, progress, fetcher)
    finally:
        if hasattr(fetcher, 'close'): fetcher.close()


def _write_pack(catalog, source, decks_dir, output, deck_ids, full_size, progress, fetcher=None):
    manifest = starter_plan(catalog, source, decks_dir, deck_ids, full_size, progress)
    output = Path(output).expanduser().absolute()
    if output.exists(): raise ValueError('Choose a new image pack output file; existing files are preserved')
    output.parent.mkdir(parents=True, exist_ok=True)
    required = sum(entry['size'] for entry in manifest['images'])
    if required + MAX_MANIFEST > MAX_ARCHIVE: raise ValueError('Starter image pack exceeds 2 GiB')
    if shutil.disk_usage(output.parent).free < required + RESERVE_BYTES: raise ValueError('Retain at least 64 MiB free space after exporting this pack')
    temporary = output.with_name('.' + output.name + '.' + uuid.uuid4().hex + '.tmp')
    complete = [];shared = OrderedDict();shared_bytes = 0
    entries = manifest['images'] + manifest['missing'] if fetcher is not None else manifest['images']
    if fetcher is not None: manifest['missing'] = []
    try:
        with zipfile.ZipFile(temporary, 'x', compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            for index, entry in enumerate(entries):
                entry = dict(entry)
                if progress: progress('Building Starter image pack' if fetcher is not None else 'Exporting cached Starter images', index, len(entries))
                if 'path' not in entry:
                    entry.pop('reason', None)
                    entry['path'] = ('art-crops/' if entry['kind'] == 'art_crop' else 'full-cards/') + f"{entry['printingId']}-{entry['face']}-{entry['kind']}.jpg"
                row = source.read(Path(entry['path']).name, content=True)
                data = bytes(row['content']) if row else shared.get(entry['source'])
                if data is None and fetcher is not None:
                    if shutil.disk_usage(output.parent).free < RESERVE_BYTES + MAX_IMAGE * 3:
                        raise ValueError('Image pack build stopped to retain 64 MiB free space; no incomplete output was published')
                    data = fetcher.image(entry['source'])
                if not data or not data.startswith(b'\xff\xd8'):
                    if fetcher is not None: raise ValueError('Image pack build received an invalid JPEG; no incomplete output was published')
                    missing = {key: entry[key] for key in ('printingId', 'oracleId', 'face', 'kind', 'source', 'name')}
                    missing['reason'] = 'Image became unavailable during the read-only export';manifest['missing'].append(missing);continue
                if not isinstance(data, bytes) or not 4 <= len(data) <= MAX_IMAGE or not data.endswith(b'\xff\xd9'):
                    raise ValueError('Image pack requires complete JPEGs within the 3 MiB limit')
                if temporary.stat().st_size + len(data) + MAX_MANIFEST > MAX_ARCHIVE:
                    raise ValueError('Starter image pack exceeds 2 GiB')
                old = shared.pop(entry['source'], None)
                if old is not None: shared_bytes -= len(old)
                shared[entry['source']] = data;shared_bytes += len(data)
                while len(shared) > 64 or shared_bytes > 8 * 1024**2:
                    _, removed = shared.popitem(last=False);shared_bytes -= len(removed)
                entry.update(size=len(data), sha256=hashlib.sha256(data).hexdigest())
                _entry(entry, catalog)
                archive.writestr(entry['path'], data);complete.append(entry)
            manifest['images'] = complete;manifest['complete'] = not manifest['missing']
            raw = encode(manifest).encode('utf-8')
            if len(raw) > MAX_MANIFEST: raise ValueError('Starter image pack manifest exceeds 1 MiB')
            archive.writestr('manifest.json', raw)
        # Same-directory hard linking publishes the completed file atomically
        # without overwriting an intervening destination or doubling disk use.
        os.link(temporary, output)
        if progress: progress('Starter image pack complete', len(complete), len(entries))
        return manifest
    finally: temporary.unlink(missing_ok=True)
