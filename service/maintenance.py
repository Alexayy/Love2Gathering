"""Explicit, scoped storage maintenance. No destructive work runs at startup."""
from contextlib import contextmanager
from copy import deepcopy
import errno
import filelocks as fcntl
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import uuid

from replays import ConflictError, encode, now

RESERVE = 64 * 1024 * 1024
CATEGORIES = frozenset(('full_cards', 'art_crops', 'replays', 'export_duplicates'))
ART_KEY = re.compile(r'[A-Za-z0-9_-]{1,180}\.jpg\Z')


@contextmanager
def operation_lock(root, exclusive=False, blocking=True, filename='.maintenance.lock'):
    """Shared around bounded data access; exclusive during purge/compaction.

    Independent CLI processes participate too. A caller holding exclusive must
    use a raw SQLite connection instead of nesting Storage.connection().
    """
    if filename not in ('.maintenance.lock', '.image-download.lock'):
        raise ValueError('Unknown maintenance lock')
    path = Path(root) / filename
    fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        mode = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        try:
            fcntl.flock(fd, mode | (0 if blocking else fcntl.LOCK_NB))
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EACCES):
                raise ConflictError('Storage is busy with an image download or maintenance operation; try again when it finishes') from exc
            raise
        yield
    finally:
        os.close(fd)


def _file_size(path):
    try:
        return path.stat().st_size
    except FileNotFoundError:
        return 0


def _raw_connection(database):
    connection = sqlite3.connect(database, timeout=5, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA busy_timeout=5000')
    connection.execute('PRAGMA foreign_keys=ON')
    connection.execute('PRAGMA synchronous=FULL')
    return connection


class MaintenanceStore:
    def _init_maintenance(self):
        with self.connection(write=True) as c:
            c.execute('CREATE TABLE IF NOT EXISTS replay_tombstones(id TEXT PRIMARY KEY,deleted_at INTEGER NOT NULL)')
            c.execute('CREATE TABLE IF NOT EXISTS match_history(id TEXT PRIMARY KEY,payload TEXT NOT NULL,created_at INTEGER NOT NULL)')
            c.execute('CREATE INDEX IF NOT EXISTS match_history_created ON match_history(created_at DESC,id DESC)')
            c.execute('CREATE TABLE IF NOT EXISTS art_purge_barriers(kind TEXT PRIMARY KEY,purged_at INTEGER NOT NULL)')
            c.execute("INSERT OR IGNORE INTO meta VALUES ('art_purge_generation','0')")

    def art_mirror_import_allowed(self, key, connection=None):
        kind = 'art_crops' if key.endswith('-art_crop.jpg') else 'full_cards'
        if connection is not None:
            return connection.execute('SELECT 1 FROM art_purge_barriers WHERE kind=?', (kind,)).fetchone() is None
        with self.connection() as c:
            return c.execute('SELECT 1 FROM art_purge_barriers WHERE kind=?', (kind,)).fetchone() is None

    def _outbox_protected(self):
        """Inspect the actual local outbox without creating/migrating it."""
        path = self.root / 'replay-outbox.sqlite'
        if not path.exists():
            return set()
        if path.is_symlink():
            raise ConflictError('Replay outbox is a symbolic link; recordings were preserved')
        try:
            c = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=2)
            try:
                c.row_factory = sqlite3.Row
                if not c.execute("SELECT 1 FROM sqlite_master WHERE type='table'AND name='replay_outbox'").fetchone():
                    if c.execute("SELECT 1 FROM sqlite_master WHERE type='table'AND name='replay_outbox_control'").fetchone():return set()
                    raise ConflictError('Replay outbox schema is unavailable; recordings were preserved')
                rows = c.execute("SELECT id,status,owner_pid,finish,EXISTS(SELECT 1 FROM replay_outbox_events e WHERE e.replay_id=r.id) AS pending FROM replay_outbox r")
                # A terminal outbox status is written only after the catalog
                # acknowledges /finish. Its engine PID may safely remain alive.
                return {row['id'] for row in rows if row['pending'] or row['finish'] is None or row['status'] not in ('completed', 'failed', 'aborted')}
            finally:
                c.close()
        except sqlite3.Error as exc:
            raise ConflictError('Replay outbox could not be inspected; recordings were preserved') from exc

    def _mirror_files(self):
        library = self.image_library
        if library.is_symlink():
            return
        for kind, name in (('full_cards', 'full-cards'), ('art_crops', 'art-crops')):
            folder = library / name
            if not folder.is_dir() or folder.is_symlink():
                continue
            with os.scandir(folder) as entries:
                for entry in entries:
                    if ART_KEY.fullmatch(entry.name) and entry.is_file(follow_symlinks=False):
                        yield kind, Path(entry.path), entry.stat(follow_symlinks=False)

    def _database_stats(self, c):
        page_size = c.execute('PRAGMA page_size').fetchone()[0]
        reusable = c.execute('PRAGMA freelist_count').fetchone()[0] * page_size
        size = _file_size(self.database)
        free = shutil.disk_usage(self.root).free
        required = size * 2 + RESERVE
        cache_size = _file_size(self.cache_database) if self.separate_cache else 0
        cache_free = shutil.disk_usage(self.cache_root).free
        cache_reusable = c.execute('PRAGMA images.freelist_count').fetchone()[0] * c.execute('PRAGMA images.page_size').fetchone()[0] if self.separate_cache else 0
        cache_required = cache_size * 2 + RESERVE if self.separate_cache else 0
        return {'bytes': size, 'walBytes': _file_size(Path(str(self.database) + '-wal')),
                'reusableBytes': reusable, 'freeBytes': free, 'compactRequiredBytes': required,
                'cacheBytes': cache_size, 'cacheWalBytes': _file_size(Path(str(self.cache_database)+'-wal')) if self.separate_cache else 0,
                'cacheReusableBytes': cache_reusable, 'cacheFreeBytes': cache_free, 'cacheCompactRequiredBytes': cache_required,
                'totalBytes': size + cache_size, 'cacheDirectory': str(self.cache_root.resolve()),
                'cacheDatabaseFile': str(self.cache_database.resolve()), 'separateCache': self.separate_cache,
                'canCompact': free >= required and cache_free >= cache_required, 'outboxBytes': _file_size(self.root / 'replay-outbox.sqlite')}

    def maintenance_stats(self):
        result = {kind: {'count': 0, 'bytes': 0, 'mirrorCount': 0, 'mirrorBytes': 0}
                  for kind in ('full_cards', 'art_crops')}
        protected_error = None
        try:
            outbox_ids = self._outbox_protected()
        except ConflictError as exc:
            outbox_ids = None
            protected_error = str(exc)
        with self.connection() as c:
            # length(BLOB) reads SQLite's stored size, not the image content.
            # Kind is determined by cache key; no per-row JSON/BLOB decoding.
            sizes = {}
            for row in c.execute('SELECT cache_key,length(content) AS bytes FROM art_cache'):
                kind = 'art_crops' if row['cache_key'].endswith('-art_crop.jpg') else 'full_cards'
                result[kind]['count'] += 1
                result[kind]['bytes'] += row['bytes']
                sizes[row['cache_key']] = row['bytes']
            ids = []
            protected = 0
            for row in c.execute('SELECT id,status FROM replays'):
                if row['status'] == 'recording' or outbox_ids is None or row['id'] in outbox_ids:
                    protected += 1
                else:
                    ids.append(row['id'])
            replay_bytes = 0
            # Bounded bindings handle a long history without SQLite's variable limit.
            for offset in range(0, len(ids), 400):
                part = ids[offset:offset + 400]
                query = ','.join('?' for _ in part)
                replay_bytes += c.execute('SELECT COALESCE(sum(length(payload)),0) FROM replays WHERE id IN (' + query + ')', part).fetchone()[0]
                replay_bytes += c.execute('SELECT COALESCE(sum(length(payload)),0) FROM replay_events WHERE replay_id IN (' + query + ')', part).fetchone()[0]
            result['replays'] = {'count': len(ids), 'bytes': replay_bytes, 'protectedCount': protected}
            if protected_error:
                result['replays']['error'] = protected_error
            result['database'] = self._database_stats(c)
            result['replays']['protectedOutboxCount']=len(outbox_ids)if outbox_ids is not None else None
            if protected_error or protected or outbox_ids:
                result['database']['canCompact']=False
                result['database']['compactionBlockedReason']=protected_error or'Finish active games and flush pending recordings before compacting the database.'
            elif not result['database']['canCompact']:
                result['database']['compactionBlockedReason']='Not enough temporary free space on the data drive.'
        duplicates = {'count': 0, 'bytes': 0, 'estimated': True}
        mirrors = {'count': 0, 'bytes': 0}
        for kind, path, info in self._mirror_files():
            result[kind]['mirrorCount'] += 1
            result[kind]['mirrorBytes'] += info.st_size
            mirrors['count'] += 1
            mirrors['bytes'] += info.st_size
            if sizes.get(path.name) == info.st_size:
                duplicates['count'] += 1
                duplicates['bytes'] += info.st_size
        result['export_duplicates'] = duplicates
        result['export_mirrors'] = mirrors
        result['retainedLegacyBackups'] = True
        result['cacheDirectory']=str(self.cache_root.resolve())
        result['externalMirrorsExcluded'] = bool(os.environ.get('LOVE2GATHERING_IMAGE_LIBRARY') and Path(os.environ['LOVE2GATHERING_IMAGE_LIBRARY']).resolve() != self.image_library.resolve())
        return result

    @contextmanager
    def _exclusive_maintenance(self, readonly=False):
        if self.relocation_active.is_set():raise ConflictError('Storage is awaiting restart after relocation')
        # Acquire the download lifetime lock first: a download never resumes
        # into freshly purged data after a network request finishes.
        with operation_lock(self.root, exclusive=True, blocking=False, filename='.image-download.lock'):
            with self.maintenance_lock:
                retired=_raw_connection(self.database)
                try:
                    if retired.execute("SELECT 1 FROM meta WHERE key='storage_relocated_to'").fetchone():raise ConflictError('Storage was relocated; restart the application')
                finally:retired.close()
                if readonly:
                    # Duplicate exports only: keep ordinary SQL readers usable
                    # while excluding another destructive operation/download.
                    with operation_lock(self.root,blocking=False):yield
                    return
                self.maintenance_active.set()
                try:
                    with operation_lock(self.root, exclusive=True, blocking=False):
                        yield
                finally:
                    self.maintenance_active.clear()

    def cancel_maintenance(self):
        self.maintenance_cancel.set()
        with self.maintenance_process_lock:
            process=self.maintenance_process
            if process is not None and process.poll() is None:
                process.terminate()

    def _maintenance_check_cancelled(self):
        if self.maintenance_cancel.is_set():
            raise ConflictError('Storage maintenance was stopped; uncommitted SQLite changes were rolled back')

    def _archive_and_delete_replays(self, c, identifiers):
        for identifier in identifiers:
            row = c.execute('SELECT id,payload,status,created_at,finished_at FROM replays WHERE id=?', (identifier,)).fetchone()
            if not row:
                continue
            if row['status'] == 'recording':
                raise ConflictError('An active recording cannot be purged')
            summary = self._match_history_item(c, row)
            summary['replayAvailable'] = False
            c.execute('INSERT INTO match_history VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,created_at=excluded.created_at', (identifier, encode(summary), row['created_at']))
            c.execute('INSERT OR IGNORE INTO replay_tombstones VALUES (?,?)', (identifier, now()))
            c.execute('DELETE FROM replays WHERE id=?', (identifier,))

    def purge_storage(self, categories, progress=None, replay_id=None):
        if not isinstance(categories, list) or not categories or len(categories) > 4 or any(not isinstance(x, str) or x not in CATEGORIES for x in categories) or len(set(categories)) != len(categories):
            raise ValueError('Choose replays, full_cards, art_crops or export_duplicates once each')
        if replay_id is not None:
            self.check_id(replay_id)
        result = {'categories': categories, 'deletedImages': 0, 'deletedReplays': 0, 'deletedMirrors': 0,
                  'mirrorBytesFreed': 0, 'retainedMirrors': 0, 'historyPreserved': True, 'databaseCompacted': False}
        def update(message, done=0, total=0):
            if progress:
                progress({'message': message, 'done': done, 'total': total})
        with self._exclusive_maintenance(readonly=categories==['export_duplicates']):
            self._maintenance_check_cancelled()
            protected = self._outbox_protected() if 'replays' in categories else set()
            c = _raw_connection(self.database)
            self._attach_cache(c)
            try:
                c.set_progress_handler(lambda:1 if self.maintenance_cancel.is_set() else 0,10000)
                c.execute('BEGIN IMMEDIATE')
                if 'replays' in categories:
                    rows = c.execute("SELECT id FROM replays WHERE status<>'recording'")
                    identifiers = [row['id'] for row in rows if row['id'] not in protected and (replay_id is None or row['id'] == replay_id)]
                    if replay_id is not None:
                        exists = c.execute('SELECT status FROM replays WHERE id=?', (replay_id,)).fetchone()
                        if exists and (exists['status'] == 'recording' or replay_id in protected):
                            raise ConflictError('This recording is active or still owned/pending in the native outbox')
                    update('Removing finished replay timelines; keeping match history')
                    self._archive_and_delete_replays(c, identifiers)
                    result['deletedReplays'] = len(identifiers)
                    result['protectedReplays'] = c.execute('SELECT count(*) FROM replays').fetchone()[0]
                for kind in ('full_cards', 'art_crops'):
                    if kind not in categories:
                        continue
                    update('Removing cached full-card images' if kind == 'full_cards' else 'Removing cached artwork crops')
                    # GLOB treats '_' literally, matching the exact kind suffix
                    # used by cache lookup and stats (LIKE would wildcard it).
                    where = "cache_key GLOB '*-art_crop.jpg'" if kind == 'art_crops' else "cache_key NOT GLOB '*-art_crop.jpg'"
                    result['deletedImages'] += c.execute('DELETE FROM art_cache WHERE ' + where).rowcount
                    c.execute('INSERT INTO art_purge_barriers VALUES (?,?) ON CONFLICT(kind) DO UPDATE SET purged_at=excluded.purged_at', (kind, now()))
                if any(kind in categories for kind in ('full_cards','art_crops')):
                    c.execute("INSERT INTO meta VALUES ('art_purge_generation','1') ON CONFLICT(key)DO UPDATE SET value=CAST(COALESCE(CAST(meta.value AS INTEGER),0)+1 AS TEXT)")
                self._maintenance_check_cancelled()
                c.execute('COMMIT')
                c.set_progress_handler(None,0)
                mirrors = list(self._mirror_files())
                for index, (kind, path, info) in enumerate(mirrors):
                    if self.maintenance_cancel.is_set():
                        result['cancelled']=True
                        result['retainedMirrors']+=len(mirrors)-index
                        break
                    remove = kind in categories
                    try:
                        if not remove and 'export_duplicates' in categories:
                            row = c.execute('SELECT content FROM art_cache WHERE cache_key=? AND length(content)=?', (path.name, info.st_size)).fetchone()
                            if row:
                                # A same-sized filename alone never proves a duplicate.
                                data = path.read_bytes()
                                remove = data == bytes(row['content'])
                            if not remove:
                                result['retainedMirrors'] += 1
                        if remove:
                            current = path.lstat()
                            if path.is_symlink() or (current.st_ino, current.st_size, current.st_mtime_ns) != (info.st_ino, info.st_size, info.st_mtime_ns):
                                result['retainedMirrors'] += 1
                                continue
                            path.unlink()
                            result['deletedMirrors'] += 1
                            result['mirrorBytesFreed'] += info.st_size
                    except OSError as exc:
                        result['retainedMirrors']+=1
                        warnings=result.setdefault('warnings',[])
                        if len(warnings)<10:warnings.append('Kept export '+path.name+': '+str(exc))
                    if index % 100 == 0:
                        update('Checking managed export copies' if categories == ['export_duplicates'] else 'Removing selected managed image exports', index, len(mirrors))
                remaining=self._database_stats(c)
                result['reusableBytes'] = remaining['reusableBytes']
                result['cacheReusableBytes'] = remaining['cacheReusableBytes']
                result['message'] = 'Selected data removed. SQLite pages are reusable; Compact database separately releases unused pages to the disk.'
                if result.get('cancelled'):result['message']='SQLite purge committed; remaining export removal was stopped. Remaining exports cannot automatically restore purged images. Repeat purge to remove them.'
                return result
            except BaseException:
                if c.in_transaction:
                    c.execute('ROLLBACK')
                raise
            finally:
                c.close()

    def compact_storage(self, progress=None):
        with self._exclusive_maintenance():
            self._maintenance_check_cancelled()
            protected = self._outbox_protected()
            c = _raw_connection(self.database)
            self._attach_cache(c)
            try:
                if c.execute("SELECT 1 FROM replays WHERE status='recording' LIMIT 1").fetchone() or protected:
                    raise ConflictError('Finish the current game and flush pending recordings before compacting the database')
                before = self._database_stats(c)
                if not before['canCompact']:
                    raise ConflictError('Compaction needs up to twice the database size plus 64 MiB free on the data drive; deleted pages remain reusable meanwhile')
                checkpoint = c.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
                cache_checkpoint=c.execute('PRAGMA images.wal_checkpoint(TRUNCATE)').fetchone()if self.separate_cache else(0,)
                if checkpoint[0]or cache_checkpoint[0]:
                    raise ConflictError('A database reader is active; try compaction again when it finishes')
            finally:
                c.close()
            code = "import sqlite3,sys;c=sqlite3.connect(sys.argv[1],timeout=5,isolation_level=None);c.execute('PRAGMA busy_timeout=5000');c.execute('PRAGMA synchronous=FULL');c.execute('VACUUM');c.execute('PRAGMA wal_checkpoint(TRUNCATE)');c.close()"
            databases=[self.database]+([self.cache_database]if self.separate_cache else[])
            before_size=sum(_file_size(path)for path in databases)
            for index,database in enumerate(databases):
                self._maintenance_check_cancelled()
                if progress:progress({'message':'Compacting '+('image cache'if index else'application database')+' on its selected drive','done':index,'total':len(databases)})
                # Each SQLite temporary file stays beside the DB being compacted.
                temporary=database.parent/'.maintenance-temp';temporary.mkdir(mode=0o700,exist_ok=True)
                if temporary.is_symlink():raise ValueError('Maintenance temporary directory must not be a symbolic link')
                env=dict(os.environ,SQLITETMPDIR=str(temporary.resolve()),TMPDIR=str(temporary.resolve()))
                with self.maintenance_process_lock:
                    self._maintenance_check_cancelled()
                    process=subprocess.Popen([sys.executable,'-c',code,str(database)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                    self.maintenance_process=process
                try:_,stderr=process.communicate()
                finally:
                    with self.maintenance_process_lock:self.maintenance_process=None
                if process.returncode:raise ConflictError('Database compaction did not complete: '+stderr[-1200:].strip())
            after_size=sum(_file_size(path)for path in databases)
            return {'databaseBytesBefore':before_size,'databaseBytesAfter':after_size,
                    'bytesFreed':max(0,before_size-after_size),'databaseCompacted':True,
                    'cacheCompacted':self.separate_cache,
                    'message':'Unused SQLite pages were released on their selected drives; saved decks, history and remaining images were retained.'}



class StorageMaintenance:
    """A lightweight status endpoint while bounded/background work is active."""
    def __init__(self, storage):
        self.storage = storage
        self.lock = threading.RLock()
        self.stats = None
        self.scanning = False
        self.operation = None
        self.error = None
        self.stats_at = 0
        self.closing=False
        self.workers=[]

    def _scan(self):
        try:
            result = self.storage.maintenance_stats()
            with self.lock:
                self.stats, self.error, self.stats_at = result, None, time.monotonic()
        except Exception as exc:
            with self.lock:
                self.error,self.stats_at=str(exc),time.monotonic()
        finally:
            with self.lock:
                self.scanning = False

    def status(self, refresh=False):
        with self.lock:
            running = self.operation and self.operation['state'] == 'running'
            # Image record headers and mirror stats can still be expensive on
            # HDDs. Navbar polling must reuse usage totals indefinitely; only
            # explicit refresh or completed maintenance triggers another scan.
            initial = self.stats is None and (not self.stats_at or time.monotonic()-self.stats_at>5)
            if not self.closing and not running and not self.scanning and (initial or refresh):
                self.scanning = True
                self.workers=[worker for worker in self.workers if worker.is_alive()]
                worker=threading.Thread(target=self._scan,name='Storage usage scan',daemon=True);self.workers.append(worker);worker.start()
            return deepcopy({'dataDirectory': str(self.storage.root.resolve()), 'scanning': self.scanning,
                             'stats': self.stats, 'operation': self.operation, 'error': self.error})

    def _start(self, kind, categories=None):
        if kind == 'purge' and (not isinstance(categories, list) or not categories or len(categories) > 4 or any(not isinstance(x, str) or x not in CATEGORIES for x in categories) or len(set(categories)) != len(categories)):
            raise ValueError('Choose one or more storage categories')
        with self.lock:
            if self.closing:raise ConflictError('Storage service is closing')
            if self.scanning or self.operation and self.operation['state'] == 'running':
                raise ConflictError('A storage scan or maintenance operation is already running')
            # Fail fast instead of queueing a destructive action behind a job.
            with operation_lock(self.storage.root, exclusive=True, blocking=False, filename='.image-download.lock'):
                pass
            operation = {'id': uuid.uuid4().hex, 'kind': kind, 'categories': categories or [], 'state': 'running',
                         'message': 'Preparing storage maintenance', 'done': 0, 'total': 0, 'startedAt': now()}
            self.operation = operation
            self.storage.maintenance_cancel.clear()
            self.workers=[worker for worker in self.workers if worker.is_alive()]
            def update(value):
                with self.lock:
                    operation.update(value)
            def work():
                try:
                    value = self.storage.purge_storage(categories, update) if kind == 'purge' else self.storage.compact_storage(update)
                    with self.lock:
                        update({'state': 'completed', 'result': value, 'message': value.get('message', 'Storage maintenance completed'), 'finishedAt': now()})
                        self.scanning=True
                    self._scan()
                except Exception as exc:
                    update({'state': 'failed', 'error': str(exc), 'message': str(exc), 'finishedAt': now()})
            worker=threading.Thread(target=work,name='Storage '+kind,daemon=True);self.workers.append(worker);worker.start()
            return self.status()

    def start_purge(self, categories):
        return self._start('purge', categories)

    def start_compact(self):
        return self._start('compact')

    def close(self):
        with self.lock:self.closing=True;workers=list(self.workers)
        self.storage.cancel_maintenance()
        deadline=time.monotonic()+8
        for worker in workers:
            if worker is not threading.current_thread():worker.join(max(0,deadline-time.monotonic()))
        with self.storage.maintenance_process_lock:
            process=self.storage.maintenance_process
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=3)
