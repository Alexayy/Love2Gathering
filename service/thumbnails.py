"""One bounded, restartable JPEG derivative per exact cached source identity."""
from collections import deque,OrderedDict
from contextlib import contextmanager
import hashlib
from io import BytesIO
import json
import sqlite3
import threading
import time
import weakref
from image_io import ImageIOCancelled
from replays import ConflictError

try:
    from PIL import Image,features
    AVAILABLE=bool(features.check('jpg'))
except ImportError:
    Image=None;AVAILABLE=False

VERSION=1
WIDTH=256
MAX_HEIGHT=512


def schema(prefix=''):
    return [
        f'CREATE TABLE IF NOT EXISTS {prefix}art_sources(cache_key TEXT PRIMARY KEY REFERENCES art_cache(cache_key) ON DELETE CASCADE,digest TEXT NOT NULL)',
        f'CREATE TABLE IF NOT EXISTS {prefix}art_thumbnails(cache_key TEXT PRIMARY KEY REFERENCES art_cache(cache_key) ON DELETE CASCADE,source_digest TEXT NOT NULL,version INTEGER NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,metadata TEXT NOT NULL,content BLOB NOT NULL)',
        # Older catalog/CLI writers do not know the digest table. Triggers live
        # beside the original cache (including the attached images database),
        # so they also protect raw writes and REPLACE with foreign keys off.
        f'CREATE TRIGGER IF NOT EXISTS {prefix}art_content_changed AFTER UPDATE OF content ON art_cache WHEN OLD.content IS NOT NEW.content BEGIN DELETE FROM art_thumbnails WHERE cache_key=NEW.cache_key; DELETE FROM art_sources WHERE cache_key=NEW.cache_key; END',
        f'CREATE TRIGGER IF NOT EXISTS {prefix}art_source_inserted AFTER INSERT ON art_cache BEGIN DELETE FROM art_thumbnails WHERE cache_key=NEW.cache_key; DELETE FROM art_sources WHERE cache_key=NEW.cache_key; END',
        f'CREATE TRIGGER IF NOT EXISTS {prefix}art_source_deleted AFTER DELETE ON art_cache BEGIN DELETE FROM art_thumbnails WHERE cache_key=OLD.cache_key; DELETE FROM art_sources WHERE cache_key=OLD.cache_key; END']


def jpeg_thumbnail(content):
    if not AVAILABLE:return None
    with Image.open(BytesIO(content))as source:
        width,height=source.size
        if source.format!='JPEG'or not 0<width<=8192 or not 0<height<=8192 or width*height>16*1024**2:raise ValueError('Image dimensions exceed thumbnail limits')
        source.draft('RGB',(WIDTH,MAX_HEIGHT))
        source.thumbnail((WIDTH,MAX_HEIGHT),Image.Resampling.LANCZOS)
        image=source.convert('RGB');output=BytesIO();image.save(output,format='JPEG',quality=82)
        data=output.getvalue()
        if len(data)>256*1024:raise ValueError('Thumbnail exceeds its byte limit')
        return data,image.width,image.height


class Thumbnails:
    def __init__(self,storage):
        self.storage=weakref.ref(storage);self.condition=threading.Condition();self.queue=deque();self.pending=set();self.dirty=set()
        self.failed=OrderedDict();self.thread=None;self.closed=threading.Event()
        self.paused=0;self.enabled=False
        self.metrics={'generated':0,'reused':0,'failed':0,'dropped':0,'inputBytes':0,'outputBytes':0}

    def request(self,key,digest=None):
        if not self.enabled or not AVAILABLE or self.closed.is_set():return 'unavailable'
        with self.condition:
            if key in self.failed:
                if digest is None or self.failed[key]==digest:return 'unavailable'
                del self.failed[key]
            if key not in self.pending:
                if len(self.pending)>=64:self.metrics['dropped']+=1;return 'pending'
                self.pending.add(key);self.queue.append(key)
            elif digest is not None:self.dirty.add(key)
            if self.thread is None or not self.thread.is_alive():
                self.thread=threading.Thread(target=self._run,name='image-thumbnails',daemon=True)
                try:self.thread.start()
                except RuntimeError:
                    self.metrics['failed']+=1;self.failed[key]=digest;self.queue.clear();self.pending.clear();self.dirty.clear();self.thread=None
                    return 'unavailable'
            self.condition.notify_all()
        return 'pending'

    @contextmanager
    def pause(self):
        with self.condition:self.paused+=1
        try:yield
        finally:
            with self.condition:self.paused-=1;self.condition.notify_all()

    def _checkpoint(self,storage):
        with self.condition:
            while self.paused and not self.closed.is_set():self.condition.wait(.025)
        storage.image_io.checkpoint()

    def _run(self):
        while not self.closed.is_set():
            with self.condition:
                if not self.queue:self.thread=None;self.condition.notify_all();return
                key=self.queue.popleft()
            storage=self.storage()
            if storage is None:return
            digest=None;retry=False
            try:
                with storage.image_io.background(self.closed):
                    self._checkpoint(storage)
                    with storage.image_io.measure('thumbnailRead'),storage.connection()as c:
                        thumbs,sources=storage.image_table('art_thumbnails'),storage.image_table('art_sources')
                        ready=c.execute('SELECT 1 FROM '+thumbs+' t JOIN '+sources+' s USING(cache_key) WHERE t.cache_key=? AND t.source_digest=s.digest AND t.version=?',(key,VERSION)).fetchone()
                        if ready:
                            self.metrics['reused']+=1;continue
                        row=c.execute('SELECT content,metadata FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                    if row is None:continue
                    content=bytes(row['content']);digest=hashlib.sha256(content).hexdigest()
                    with storage.image_io.measure('thumbnailDecode'):result=jpeg_thumbnail(content)
                    if result is None:continue
                    data,width,height=result
                    if self.closed.is_set():return
                    self._checkpoint(storage)
                    with storage.image_io.measure('thumbnailWrite'),storage.connection(write=True)as c:
                        # Legacy sources acquire a digest only if their exact
                        # original still matches. A concurrent replacement or
                        # purge can never resurrect a stale derived image.
                        c.execute('INSERT OR IGNORE INTO '+sources+' SELECT cache_key,? FROM art_cache WHERE cache_key=? AND content=?',(digest,key,sqlite3.Binary(content)))
                        current=c.execute('SELECT metadata FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                        saved=c.execute('INSERT OR REPLACE INTO '+thumbs+' SELECT cache_key,?, ?, ?, ?, ?, ? FROM '+sources+' WHERE cache_key=? AND digest=?',(digest,VERSION,width,height,current['metadata']if current else row['metadata'],sqlite3.Binary(data),key,digest)).rowcount
                    if saved:self.metrics['generated']+=1;self.metrics['inputBytes']+=len(content);self.metrics['outputBytes']+=len(data)
                    else:retry=True
            except ImageIOCancelled:return
            except ConflictError:
                if storage.relocation_active.is_set():
                    self.closed.set()
                    with self.condition:self.queue.clear();self.pending.clear();self.dirty.clear()
                    return
                retry=not self.closed.is_set()
            except sqlite3.OperationalError:
                retry=not self.closed.is_set()
            except Exception:
                with self.condition:
                    self.metrics['failed']+=1;self.failed[key]=digest
                    while len(self.failed)>256:self.failed.popitem(last=False)
            finally:
                storage=None
                with self.condition:
                    retry=(retry or key in self.dirty)and not self.closed.is_set();self.dirty.discard(key)
                    if retry:self.queue.append(key)
                    else:self.pending.discard(key)
                    self.condition.notify_all()
            if retry:self.closed.wait(.05)

    def flush(self,timeout=5):
        deadline=time.monotonic()+timeout
        with self.condition:
            while self.pending and time.monotonic()<deadline:self.condition.wait(min(.05,max(0,deadline-time.monotonic())))
            return not self.pending

    def close(self):
        self.closed.set()
        with self.condition:self.queue.clear();self.pending.clear();self.dirty.clear();self.condition.notify_all();thread=self.thread
        if thread is not None and thread is not threading.current_thread():thread.join(3)

    def status(self):
        with self.condition:return dict(self.metrics,available=AVAILABLE,enabled=self.enabled,version=VERSION,width=WIDTH,maxHeight=MAX_HEIGHT,pending=len(self.pending),queueLimit=64,workerAlive=bool(self.thread and self.thread.is_alive()))
