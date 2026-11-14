"""Explicit, durable image-library plans and paced background downloads.

The source is the already configured local JSONL. A scan performs no network
requests and retains only bounded batches in memory; the plan lives in SQL.
"""
from __future__ import annotations

from contextlib import contextmanager
import filelocks as fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import threading
import time
import uuid

from replays import ConflictError, encode, now

PROJECT = Path(__file__).resolve().parents[1]
RESERVE_BYTES = 3 * 1024**3
SIZE_SAMPLE_LIMIT = 512
_spec = importlib.util.spec_from_file_location('love2gathering_image_downloader', PROJECT / 'scripts/download-card-images.py')
_cli = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cli)


@contextmanager
def image_job_lock(root, blocking=False):
    """One managed/CLI image operation per data directory, across processes."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    fd=os.open(root/'.image-download.lock',os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)
    with os.fdopen(fd,'a+b') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError as exc:
            raise ConflictError('Another image scan, download or storage operation is active') from exc
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def _options(value):
    if value is None:
        value = {}
    if not isinstance(value, dict) or set(value) - {'fullSize', 'kinds', 'mirrors'}:
        raise ValueError('Choose image size, image kinds and whether to export mirrors')
    full_size = value.get('fullSize', 'normal')
    if full_size not in ('normal', 'large'):
        raise ValueError('Full-card size must be normal or large')
    mirrors = value.get('mirrors', False)
    if not isinstance(mirrors, bool):
        raise ValueError('Mirrors must be true or false')
    kinds = value.get('kinds', ['normal', 'art_crop'])
    if not isinstance(kinds, list) or not 1 <= len(kinds) <= 2 or any(not isinstance(k, str) for k in kinds):
        raise ValueError('Choose full cards, art crops, or both')
    selected = []
    for kind in kinds:
        if kind in ('normal', full_size):
            kind = full_size
        elif kind != 'art_crop':
            raise ValueError('Image kinds must match the selected full-card size or art_crop')
        if kind not in selected:
            selected.append(kind)
    return {'fullSize': full_size, 'kinds': selected, 'mirrors': mirrors}


class DownloadManager:
    def __init__(self, catalog, storage, *, fetcher_factory=None, disk_usage=shutil.disk_usage):
        self.catalog, self.storage = catalog, storage
        self.fetcher_factory = fetcher_factory or (lambda: _cli.Fetcher(.15, 3))
        self.disk_usage = disk_usage
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.thread = None
        self.stop_kind = 'paused'
        self._job_guard = None
        self.last_snapshot = self._idle()
        self._init_sql()
        self._recover()

    def _init_sql(self):
        with self.storage.connection(write=True) as c:
            c.execute('CREATE TABLE IF NOT EXISTS image_download_state(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL)')
            c.execute('CREATE TABLE IF NOT EXISTS image_download_items(job_id TEXT NOT NULL,cache_key TEXT NOT NULL,ordinal INTEGER NOT NULL,url TEXT NOT NULL,kind TEXT NOT NULL,metadata TEXT NOT NULL,existing_key TEXT,mirror TEXT,mirror_bytes INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT \'pending\',PRIMARY KEY(job_id,cache_key))')
            c.execute('CREATE INDEX IF NOT EXISTS image_download_pending ON image_download_items(job_id,status,ordinal)')
            c.execute('CREATE INDEX IF NOT EXISTS image_download_url ON image_download_items(job_id,url,status)')
            c.execute('CREATE TABLE IF NOT EXISTS image_download_mirrors(cache_key TEXT PRIMARY KEY,path TEXT NOT NULL,bytes INTEGER NOT NULL)')

    def _state(self, c=None):
        if c is None:
            with self.storage.connection() as connection:
                return self._state(connection)
        row = c.execute('SELECT payload FROM image_download_state WHERE id=1').fetchone()
        return json.loads(row[0]) if row else self._idle()

    def _idle(self):
        return {'state': 'idle', 'jobId': None, 'scan': None, 'scanComplete': False, 'processed': 0,
                'downloaded': 0, 'cached': 0, 'failed': 0, 'bytesDownloaded': 0,
                'imagesAdded':0,'imported':0,
                'networkRequests': 0, 'rateBytesPerSecond': 0, 'progress': 0, 'error': None,
                'reserveBytes': RESERVE_BYTES, 'dataDirectory': str(self.storage.root.resolve())}

    def _save(self, state, c=None):
        state['updatedAt'] = now()
        if c is None:
            with self.storage.connection(write=True) as connection:
                return self._save(state, connection)
        current = self._state(c)
        request = current.get('controlRequest') if current.get('jobId') == state.get('jobId') else None
        if request and not state.get('controlRequest') and state['state'] not in ('paused','cancelled','error'):
            if state['state'] in ('ready','completed'):
                state.update(state=request,rateBytesPerSecond=0)
            else:
                state.update(state='pausing',controlRequest=request)
        c.execute('INSERT INTO image_download_state VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload', (encode(state),))
        self.last_snapshot=json.loads(encode(state))

    def _recover(self):
        # Another desktop may own the worker. Never pause its durable state.
        try:
            with image_job_lock(self.storage.root):
                with self.storage.connection(write=True) as c:
                    state = self._state(c)
                    if state['state'] in ('scanning', 'downloading', 'pausing'):
                        state.pop('controlRequest',None)
                        state.update(state='paused', rateBytesPerSecond=0,
                                     error='Interrupted operation. Resume to continue; committed images are retained.')
                        self._save(state, c)
        except ConflictError:
            pass

    def status(self):
        try:
            state = self._state()
            generation=self._purge_generation()
            self.last_snapshot=json.loads(encode(state))
            busy=False
        except ConflictError:
            state=json.loads(encode(self.last_snapshot));generation=None;busy=True
        state['freeBytes'] = self.disk_usage(self.storage.cache_root).free
        state['databaseFreeBytes'] = self.disk_usage(self.storage.root).free
        state['cacheDirectory'] = str(self.storage.cache_root.resolve())
        state['maintenanceBusy']=busy
        state['scanValid'] = not busy and bool(state.get('scanComplete')) and state.get('artPurgeGeneration') == generation
        state['scanInvalidReason'] = ('Storage maintenance is in progress.'if busy else None if not state.get('scanComplete') or state['scanValid'] else 'Image cache was purged after this scan. Scan again before downloading.')
        state['canStart'] = state['scanValid'] and state['state'] in ('ready', 'paused', 'cancelled', 'error', 'completed')
        state['canResume'] = not busy and bool(state.get('jobId'))and state['state'] in ('paused', 'cancelled', 'error') and (state['scanValid'] or not state.get('scanComplete'))
        return state

    def _purge_generation(self,c=None):
        if c is None:
            with self.storage.connection()as connection:return self._purge_generation(connection)
        row=c.execute("SELECT value FROM meta WHERE key='art_purge_generation'").fetchone()
        return int(row[0])if row else 0

    def _claim(self):
        if self.thread is not None and self.thread.is_alive():
            raise ConflictError('An image operation is already active')
        guard = image_job_lock(self.storage.root)
        guard.__enter__()
        self._job_guard = guard
        self.stop.clear()

    def _launch(self, target, state):
        def run():
            try:
                target(state)
            except Exception as exc:
                state.update(state='error', rateBytesPerSecond=0, error=str(exc),failed=state.get('failed',0)+1)
                self._save(state)
            finally:
                guard = self._job_guard
                self._job_guard = None
                if guard is not None:
                    guard.__exit__(None, None, None)
        self.thread = threading.Thread(target=run, name='ImageLibraryDownload', daemon=True)
        self.thread.start()

    def scan(self, options=None):
        options = _options(options)
        if not self.catalog.source.is_file():
            raise ValueError('The configured local card metadata file is missing')
        with self.lock:
            self._claim()
            try:
                state = self._idle()
                state.update(state='scanning', phase='scan', jobId=str(uuid.uuid4()), options=options, scannedRecords=0)
                self._save(state)
                self._launch(self._scan_worker, state)
            except BaseException:
                self._job_guard.__exit__(None, None, None)
                self._job_guard = None
                raise
        return self.status()

    def control(self, command):
        if not isinstance(command, str) or command not in ('start', 'resume', 'pause', 'cancel'):
            raise ValueError('Image command must be start, resume, pause or cancel')
        with self.lock:
            state = self._state()
            if command in ('pause', 'cancel'):
                # Only the owning manager can signal its thread. A second
                # desktop stores a control request for that worker to observe.
                if state['state'] in ('scanning', 'downloading', 'pausing'):
                    state['controlRequest'] = 'cancelled' if command == 'cancel' else 'paused'
                    state['state'] = 'pausing'
                    self._save(state)
                    self.stop_kind = state['controlRequest']
                    self.stop.set()
                else:
                    state.update(state='cancelled' if command == 'cancel' else 'paused', rateBytesPerSecond=0)
                    self._save(state)
                return self.status()
            if not state.get('jobId'):
                raise ConflictError('Scan the local metadata before starting a download')
            if command == 'start' and not state.get('scanComplete'):
                raise ConflictError('Wait for a complete image scan before starting')
            self._claim()
            try:
                state.pop('controlRequest', None)
                state['error'] = None
                state['rateBytesPerSecond'] = 0
                if state.get('scanComplete'):
                    if self._fingerprint() != state.get('sourceFingerprint'):
                        raise ConflictError('Local metadata changed; scan again before downloading')
                    if state.get('artPurgeGeneration') != self._purge_generation():
                        raise ConflictError('Image cache was purged after this scan; scan again before downloading')
                    state.update(state='downloading', phase='download')
                    self._save(state)
                    self._launch(self._download_worker, state)
                else:
                    state.update(state='scanning', phase='scan', scannedRecords=0)
                    self._save(state)
                    self._launch(self._scan_worker, state)
            except BaseException:
                self._job_guard.__exit__(None, None, None)
                self._job_guard = None
                raise
        return self.status()

    def _fingerprint(self):
        source = self.catalog.source
        st = source.stat()
        return {'path': str(source.resolve()), 'bytes': st.st_size, 'mtimeNs': st.st_mtime_ns}

    def _requested_stop(self, state):
        current = self._state()
        requested = current.get('controlRequest')
        if self.stop.is_set() or requested:
            state.pop('controlRequest', None)
            state.update(state=requested or self.stop_kind, rateBytesPerSecond=0)
            self._save(state)
            return True
        return False

    def _mirror_inventory(self,state=None):
        prepared = []
        with self.storage.connection(write=True) as c:
            c.execute('DELETE FROM image_download_mirrors')
        if (self.storage.image_library).is_symlink():return True
        for folder in ('full-cards', 'art-crops'):
            path = self.storage.image_library / folder
            if not path.is_dir() or path.is_symlink():
                continue
            for entry in os.scandir(path):
                if not entry.is_file(follow_symlinks=False):
                    continue
                try:
                    self.storage._check_art_key(entry.name)
                    size = entry.stat(follow_symlinks=False).st_size
                    if not 4 <= size <= _cli.MAX_IMAGE:
                        continue
                except (OSError, ValueError):
                    continue
                prepared.append((entry.name, str(Path('image-library') / folder / entry.name), size))
                if len(prepared) >= 512:
                    with self.storage.connection(write=True) as c:
                        c.executemany('INSERT OR IGNORE INTO image_download_mirrors VALUES(?,?,?)', prepared)
                    prepared.clear()
                    if state is not None and self._requested_stop(state):return False
        if prepared:
            with self.storage.connection(write=True) as c:
                c.executemany('INSERT OR IGNORE INTO image_download_mirrors VALUES(?,?,?)', prepared)
        return True

    def _scan_worker(self, state):
        fingerprint = self._fingerprint()
        with self.storage.connection(write=True) as c:
            c.execute('DELETE FROM image_download_items')
        if not self._mirror_inventory(state):return
        options = state['options']
        batch = []
        ordinal = 0
        last = time.monotonic()
        for index, record in enumerate(_cli.read_metadata(self.catalog.source), 1):
            for job in _cli.image_jobs(record, options['fullSize']):
                kind = job['metadata']['kind']
                if kind not in options['kinds']:
                    continue
                batch.append((state['jobId'], job['key'], ordinal, job['url'], kind, encode(job['metadata'])))
                ordinal += 1
            if len(batch) >= 512:
                with self.storage.connection(write=True) as c:
                    c.executemany('INSERT OR IGNORE INTO image_download_items(job_id,cache_key,ordinal,url,kind,metadata) VALUES(?,?,?,?,?,?)', batch)
                batch.clear()
            state['scannedRecords'] = index
            if time.monotonic() - last >= .5:
                last = time.monotonic()
                if self._requested_stop(state):
                    return
                self._save(state)
        if batch:
            with self.storage.connection(write=True) as c:
                c.executemany('INSERT OR IGNORE INTO image_download_items(job_id,cache_key,ordinal,url,kind,metadata) VALUES(?,?,?,?,?,?)', batch)
        if self._requested_stop(state):
            return
        if self._fingerprint() != fingerprint:
            raise ValueError('Local metadata changed while scanning; scan again')
        with self.storage.connection(write=True) as c:
            self._refresh_mirrors(c,state['jobId'])
            self._refresh_cached(c,state['jobId'],options['mirrors'])
        # Sizing can touch cold BLOB-header pages. Commit plan changes first:
        # a WAL reader must never reserve the sole writer during that work.
        with self.storage.connection() as c:
            scan = self._estimate(c, state)
            processed=c.execute("SELECT count(*)FROM image_download_items WHERE job_id=? AND status='cached'",(state['jobId'],)).fetchone()[0]
            generation=self._purge_generation(c)
        if self._requested_stop(state):return
        state.update(state='ready', phase='download', scanComplete=True, scan=scan,
                     sourceFingerprint=fingerprint,artPurgeGeneration=generation,cached=scan['cached'],processed=processed,
                     progress=processed/scan['total'] if scan['total'] else 1)
        self._save(state)

    @staticmethod
    def _refresh_cached(c, job_id, mirrors=False):
        c.execute("UPDATE image_download_items SET existing_key=COALESCE((SELECT cache_key FROM art_cache a WHERE a.cache_key=image_download_items.cache_key),(SELECT cache_key FROM art_cache a WHERE a.cache_key=CASE WHEN image_download_items.kind='normal' THEN substr(image_download_items.cache_key,1,length(image_download_items.cache_key)-length('-normal.jpg'))||'-large.jpg' END)) WHERE job_id=?", (job_id,))
        c.execute("UPDATE image_download_items SET status=CASE WHEN existing_key IS NOT NULL AND ?=0 THEN 'cached' WHEN existing_key IS NOT NULL AND status='done' AND mirror IS NOT NULL THEN 'done' ELSE 'pending' END WHERE job_id=?", (int(mirrors),job_id))

    @staticmethod
    def _refresh_mirrors(c,job_id):
        c.execute("UPDATE image_download_items SET mirror=(SELECT path FROM image_download_mirrors m WHERE m.cache_key=image_download_items.cache_key),mirror_bytes=COALESCE((SELECT bytes FROM image_download_mirrors m WHERE m.cache_key=image_download_items.cache_key),0) WHERE job_id=?",(job_id,))

    def _estimate(self, c, state):
        job_id = state['jobId']
        by_kind = {}
        means = {}
        bases = []
        for kind in state['options']['kinds']:
            # Walk only the covering key index to choose a bounded UUID-key
            # sample, then read those BLOB headers rather than the whole cache.
            cached = c.execute('SELECT count(*),COALESCE(sum(length(a.content)),0) FROM (SELECT cache_key FROM art_cache WHERE cache_key GLOB ? ORDER BY cache_key LIMIT ?)sample JOIN art_cache a ON a.cache_key=sample.cache_key', ('*-'+kind+'.jpg',SIZE_SAMPLE_LIMIT)).fetchone()
            sample_count, sample_bytes = cached
            mean = sample_bytes/sample_count if sample_count else {'normal': 100*1024, 'large': 210*1024, 'art_crop': 80*1024}[kind]
            means[kind] = mean
            row = c.execute("SELECT count(*),COALESCE(sum(existing_key IS NOT NULL),0),COALESCE(sum(existing_key IS NULL AND mirror IS NOT NULL),0),COALESCE(sum(mirror IS NULL),0) FROM image_download_items WHERE job_id=? AND kind=?", (job_id,kind)).fetchone()
            total, sql_cached, mirrors, mirror_exports = row
            missing = total-sql_cached-mirrors
            by_kind[kind] = {'total':total,'cached':sql_cached,'mirrorCandidates':mirrors,'missing':missing,
                             'estimatedBytes':round(missing*mean),'meanBytes':round(mean),'sampleCount':sample_count,'mirrorExports':mirror_exports}
            bases.append(kind+(': sample mean of '+str(sample_count)+' SQL images (at most '+str(SIZE_SAMPLE_LIMIT)+')' if sample_count else ': conservative default; no cached sample'))
        total = sum(v['total'] for v in by_kind.values())
        cached = sum(v['cached'] for v in by_kind.values())
        mirrors = sum(v['mirrorCandidates'] for v in by_kind.values())
        missing = total-cached-mirrors
        # URL grouping prevents duplicate HTTP requests for shared scans. The
        # identity count still includes every exact catalog printing/face.
        network = c.execute('SELECT kind,count(*) FROM (SELECT url,min(kind)kind FROM image_download_items i WHERE job_id=? AND existing_key IS NULL AND mirror IS NULL AND NOT EXISTS(SELECT 1 FROM image_download_items other WHERE other.job_id=i.job_id AND other.url=i.url AND (other.existing_key IS NOT NULL OR other.mirror IS NOT NULL)) GROUP BY url) GROUP BY kind', (job_id,)).fetchall()
        estimated_download = round(sum(means[row[0]]*row[1] for row in network))
        sql_bytes = round(sum((v['total']-v['cached'])*means[k] for k,v in by_kind.items()))
        mirror_bytes = round(sum(v['mirrorExports']*means[k]for k,v in by_kind.items()))if state['options']['mirrors']else 0
        page_size = c.execute('PRAGMA '+('images.'if self.storage.separate_cache else'')+'page_size').fetchone()[0]
        reusable = c.execute('PRAGMA '+('images.'if self.storage.separate_cache else'')+'freelist_count').fetchone()[0]*page_size
        return {'total':total,'cached':cached,'missing':missing,'mirrorCandidates':mirrors,'byKind':by_kind,
                'uniqueUrls':c.execute('SELECT count(DISTINCT url)FROM image_download_items WHERE job_id=?',(job_id,)).fetchone()[0],
                'networkRequests':sum(row[1]for row in network),'estimatedDownloadBytes':estimated_download,
                'estimatedMinBytes':round(estimated_download*.5),'estimatedMaxBytes':round(estimated_download*1.75),
                'estimatedSqliteBytes':sql_bytes,'estimatedMirrorBytes':mirror_bytes,'reusableSqliteBytes':reusable,
                'estimatedStorageBytes':max(0,sql_bytes-reusable)+mirror_bytes,'estimateBasis':'; '.join(bases)+'. Size is an estimate, not remote Content-Length; mirrors are validated when imported.',
                **state['options']}

    def _local(self, row):
        with self.storage.connection() as c:
            keys = [row['cache_key']]
            if row['kind'] == 'normal':
                keys.append(row['cache_key'][:-len('-normal.jpg')]+'-large.jpg')
            for key in keys:
                result = c.execute('SELECT content FROM art_cache WHERE cache_key=?', (key,)).fetchone()
                if result:
                    return bytes(result[0]), key, False
            # Another identity sharing this actual URL can supply its bytes.
            candidate = c.execute('SELECT a.content,a.cache_key FROM image_download_items i JOIN art_cache a ON a.cache_key=i.existing_key WHERE i.job_id=? AND i.url=? LIMIT 1', (row['job_id'],row['url'])).fetchone()
            if candidate:
                return bytes(candidate[0]),candidate[1],True
        if row['mirror']:
            path = self.storage.cache_root / row['mirror']
            try:
                if (self.storage.image_library).is_symlink()or path.parent.is_symlink():return None,None,False
                if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode) or path.stat().st_size>_cli.MAX_IMAGE:
                    return None,None,False
                data = path.read_bytes()
                _cli.validate_image(data)
                return data,None,True
            except (OSError,ValueError):
                pass
        return None,None,False

    def _download_worker(self, state):
        job_id = state['jobId']
        if not self._mirror_inventory(state):return
        with self.storage.connection(write=True) as c:
            self._refresh_mirrors(c,job_id)
            self._refresh_cached(c,job_id,state['options']['mirrors'])
        with self.storage.connection() as c:
            state['scan']=self._estimate(c,state)
            state['processed']=c.execute("SELECT count(*)FROM image_download_items WHERE job_id=? AND status IN('cached','done')",(job_id,)).fetchone()[0]
            state['progress']=state['processed']/state['scan']['total']if state['scan']['total']else 1
        if self._requested_stop(state):return
        self._save(state)
        fetcher = self.fetcher_factory()
        started = time.monotonic()
        initial_bytes = state.get('bytesDownloaded',0)
        while True:
            if self._requested_stop(state):
                return
            with self.storage.connection() as c:
                row = c.execute("SELECT * FROM image_download_items WHERE job_id=? AND status='pending' ORDER BY ordinal LIMIT 1",(job_id,)).fetchone()
                if row is None:
                    total = state['scan']['total']
                    done = c.execute("SELECT count(*)FROM image_download_items WHERE job_id=? AND status IN('cached','done')",(job_id,)).fetchone()[0]
                    state.update(processed=done,cached=max(0,done-state.get('downloaded',0)),progress=done/total if total else 1)
                    state.update(state='completed',rateBytesPerSecond=0,error=None)
                    self._save(state)
                    return
            row = dict(row)
            data, existing, needs_save = self._local(row)
            network = data is None
            if network:
                if min(self.disk_usage(self.storage.root).free,self.disk_usage(self.storage.cache_root).free) < RESERVE_BYTES + _cli.MAX_IMAGE*3:
                    state.update(state='paused',rateBytesPerSecond=0,error='Paused to retain at least 3 GiB free. Free space and resume to continue.')
                    self._save(state)
                    return
                data = fetcher.image(row['url'])
                _cli.validate_image(data)
                state['bytesDownloaded'] += len(data)
                state['networkRequests'] += 1
                needs_save = True
            if self._requested_stop(state):
                return
            mirror_path=None;mirror_write=False
            if state['options']['mirrors']:
                mirror_path=self.storage.image_library/('art-crops'if row['kind']=='art_crop'else'full-cards')/row['cache_key']
                if (self.storage.image_library).is_symlink()or mirror_path.parent.is_symlink()or mirror_path.is_symlink():
                    raise ValueError('Image mirror exports must remain inside the application data directory')
                mirror_write=not mirror_path.is_file()or mirror_path.stat().st_size!=len(data)or mirror_path.read_bytes()!=data
            if (needs_save or mirror_write)and min(self.disk_usage(self.storage.root).free,self.disk_usage(self.storage.cache_root).free) < RESERVE_BYTES+_cli.MAX_IMAGE*3:
                state.update(state='paused',rateBytesPerSecond=0,error='Paused to retain at least 3 GiB free. Free space and resume to continue.')
                self._save(state)
                return
            if needs_save:
                mirror_import = not network and existing is None
                self.storage.save_art(row['cache_key'],data,json.loads(row['metadata']))
                existing = row['cache_key']
                state['imagesAdded']=state.get('imagesAdded',0)+1
                if mirror_import:state['imported']=state.get('imported',0)+1
            if mirror_write:_cli.write_mirror(mirror_path,data)
            with self.storage.connection(write=True) as c:
                c.execute("UPDATE image_download_items SET status='done',existing_key=? WHERE job_id=? AND cache_key=?",(existing or row['cache_key'],job_id,row['cache_key']))
                done=state['processed']+1
                if network:
                    state['downloaded'] += 1
                state.update(processed=done,progress=done/state['scan']['total'] if state['scan']['total'] else 1,
                             rateBytesPerSecond=round((state['bytesDownloaded']-initial_bytes)/max(.1,time.monotonic()-started)))
                self._save(state,c)

    def close(self):
        with self.lock:
            if self.thread is not None and self.thread.is_alive():
                state = self._state()
                state.update(state='pausing',controlRequest='paused',rateBytesPerSecond=0)
                self._save(state)
                self.stop_kind='paused'
                self.stop.set()
        if self.thread is not None:
            self.thread.join(timeout=1)
