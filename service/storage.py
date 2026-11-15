"""SQLite is authoritative for user data; legacy files remain untouched backups."""
from contextlib import contextmanager
import json
import math
from pathlib import Path
import re
import sqlite3
import threading
import time
import uuid
from replays import ReplayStore, ConflictError, encode, now
from storage_schema import StorageSchema, DEFAULT_SETTINGS, FORMATS
from artwork import ArtworkStore
from tokens import TokenPreferences
from history import HistoryStore
from precons import PreconStore
from profiles import ProfileStore
from maintenance import MaintenanceStore, operation_lock
from paths import default_cache_dir
from image_io import ImageIO
from thumbnails import Thumbnails, schema as thumbnail_schema
USER_SCHEMA_VERSION=1

class Storage(StorageSchema,ReplayStore,ArtworkStore,TokenPreferences,HistoryStore,PreconStore,ProfileStore,MaintenanceStore):
    def __init__(self,data_dir,bundled_decks,cache_dir=None):
        self.root=Path(data_dir);self.bundled=Path(bundled_decks)
        self.root.mkdir(parents=True,exist_ok=True)
        self.database=self.root/'app.sqlite';self.lock=threading.RLock();self._bundle_signature=None
        self.image_io=ImageIO(self.root);self.thumbnails=Thumbnails(self)
        self._access_context=threading.local()
        selected_cache=cache_dir if cache_dir is not None else default_cache_dir(self.root)
        self.cache_root=Path(selected_cache).resolve()if selected_cache is not None else self.root
        self.separate_cache=selected_cache is not None
        self.cache_database=self.cache_root/'images.sqlite'if self.separate_cache else self.database
        self.image_library=self.cache_root/'image-library'
        self.relocation_active=threading.Event()
        self.cache_root.mkdir(parents=True,exist_ok=True)
        self.maintenance_lock=threading.RLock();self.maintenance_active=threading.Event()
        self.maintenance_cancel=threading.Event();self.maintenance_process_lock=threading.Lock();self.maintenance_process=None
        with operation_lock(self.root, blocking=False):
            c=sqlite3.connect(self.database,timeout=30)
            try:
                c.execute('PRAGMA busy_timeout=30000')
                deadline=time.monotonic()+30
                while True:
                    try:
                        c.execute('PRAGMA journal_mode=WAL');break
                    except sqlite3.OperationalError as exc:
                        # Initial conversion to WAL can return SQLITE_BUSY without
                        # honoring busy_timeout when services start concurrently.
                        if 'locked' not in str(exc).lower() or time.monotonic()>=deadline:raise
                        time.sleep(.025)
                c.execute('PRAGMA synchronous=FULL')
                art_schema=''if self.separate_cache else '''CREATE TABLE IF NOT EXISTS art_cache(cache_key TEXT PRIMARY KEY,content BLOB NOT NULL,mime TEXT NOT NULL,metadata TEXT NOT NULL,updated_at INTEGER NOT NULL);
                    CREATE INDEX IF NOT EXISTS art_oracle_face_kind ON art_cache(json_extract(metadata,'$.oracleId'),CAST(json_extract(metadata,'$.face') AS INTEGER),json_extract(metadata,'$.kind'));'''
                c.executescript('''BEGIN IMMEDIATE;
                    CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS decks(id TEXT NOT NULL,origin TEXT NOT NULL,payload TEXT NOT NULL,updated_at INTEGER NOT NULL,PRIMARY KEY(id,origin));
                    CREATE TABLE IF NOT EXISTS hidden_decks(id TEXT PRIMARY KEY);
                    CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS ui_layout(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS migration_issues(source TEXT PRIMARY KEY,error TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS token_preferences(deck_id TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL);
                    CREATE TABLE IF NOT EXISTS replays(id TEXT PRIMARY KEY,payload TEXT NOT NULL,status TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,finished_at INTEGER);
                    CREATE TABLE IF NOT EXISTS replay_events(replay_id TEXT NOT NULL REFERENCES replays(id) ON DELETE CASCADE,sequence INTEGER NOT NULL,type TEXT NOT NULL,timestamp TEXT,payload TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(replay_id,sequence));
                    CREATE INDEX IF NOT EXISTS replays_created ON replays(created_at DESC);
                    CREATE INDEX IF NOT EXISTS replay_frames ON replay_events(replay_id,type,sequence);
                    INSERT OR IGNORE INTO meta VALUES('schema_version','1');'''+art_schema+(';'.join(thumbnail_schema())+';'if not self.separate_cache else '')+'COMMIT;')
                c.execute("INSERT OR IGNORE INTO meta VALUES('storage_identity',?)",(str(uuid.uuid4()),));c.commit()
                if self.separate_cache:
                    if c.execute("SELECT 1 FROM sqlite_master WHERE type='table'AND name='art_cache'").fetchone():
                        raise ValueError('The database still contains legacy image BLOBs; prepare the location change before selecting a separate cache')
                    self._attach_cache(c,initialize=True)
            finally:c.close()
        initial_stat=self.database.stat();self._database_identity=(initial_stat.st_dev,initial_stat.st_ino)
        self._init_maintenance();self._migrate_legacy();self._migrate_presentation_preferences();self._migrate_legacy_art();self._seed_bundled();self._init_precons();self._init_profile_storage()

    def _migrate_presentation_preferences(self):
        with self.connection(write=True)as c:
            previous={row['key']:json.loads(row['value'])for row in c.execute('SELECT key,value FROM settings')}
            if previous.get('presentationVersion')==2:return
            changed={'fontFamily':'Beleren','titleFontFamily':'Beleren','presentationVersion':2}
            if(previous.get('windowMode')=='Windowed'and previous.get('resolution')=='1440x900')or not('windowMode'in previous or'resolution'in previous):
                changed.update(windowMode='Borderless',resolution='Desktop')
            if previous.get('cursorStyle','System')=='System':changed['cursorStyle']='Kenney'
            for key,value in changed.items():c.execute('INSERT INTO settings VALUES (?,?) ON CONFLICT(key)DO UPDATE SET value=excluded.value',(key,encode(value)))

    @contextmanager
    def interactive_access(self,timeout=3):
        """Bound SQLite writer waits for one foreground request, not workers.

        A native outbox/background job may still wait the ordinary thirty
        seconds. HTTP callers must respond before the client's socket timeout;
        a busy response must never pretend an uncommitted save succeeded.
        """
        if isinstance(timeout,bool)or not isinstance(timeout,(int,float))or not math.isfinite(timeout)or timeout<=0:
            raise ValueError('Interactive storage timeout must be positive')
        previous=getattr(self._access_context,'deadline',None)
        deadline=self._access_time()+timeout
        self._access_context.deadline=min(previous,deadline)if previous is not None else deadline
        try:yield
        finally:
            if previous is None:del self._access_context.deadline
            else:self._access_context.deadline=previous

    def _access_time(self):
        paused=getattr(self._access_context,'external_started',None)
        current=time.monotonic()if paused is None else paused
        return current-getattr(self._access_context,'external_elapsed',0)

    @contextmanager
    def external_io(self):
        """Exclude an external wait from this thread's foreground SQL budget.

        Network time has its own timeout. It must not consume the remaining
        writer-lock allowance before the downloaded image can be committed.
        A logical clock preserves time already spent, including across nested
        scopes and exceptions, without changing background SQLite waits.
        """
        if getattr(self._access_context,'deadline',None)is None or getattr(self._access_context,'external_started',None)is not None:
            yield;return
        started=time.monotonic();self._access_context.external_started=started
        try:yield
        finally:
            self._access_context.external_elapsed=getattr(self._access_context,'external_elapsed',0)+max(0,time.monotonic()-started)
            del self._access_context.external_started

    def _busy_timeout_ms(self):
        deadline=getattr(self._access_context,'deadline',None)
        if deadline is None:return 30000
        remaining=deadline-self._access_time()
        if remaining<=0:raise sqlite3.OperationalError('Database is busy; foreground storage wait budget expired')
        return max(1,min(30000,int(remaining*1000)))

    def _attach_cache(self,c,initialize=False):
        if not self.separate_cache:return
        if not self.cache_database.is_file():
            persisted=c.execute("SELECT value FROM main.meta WHERE key='image_cache_directory'").fetchone()
            if not initialize or persisted:raise ConflictError('Image cache is unavailable; reconnect its drive or prepare a verified location change before continuing')
        c.execute('ATTACH DATABASE ? AS images',(str(self.cache_database),))
        c.execute('PRAGMA images.busy_timeout='+str(self._busy_timeout_ms()))
        c.execute('PRAGMA images.synchronous=FULL')
        if initialize:
            c.execute('PRAGMA images.journal_mode=WAL')
            c.execute('CREATE TABLE IF NOT EXISTS images.image_store_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
            identity=c.execute("SELECT value FROM main.meta WHERE key='storage_identity'").fetchone()[0]
            owner=c.execute("SELECT value FROM images.image_store_meta WHERE key='owner'").fetchone()
            if owner and owner[0]!=identity:raise ValueError('Image cache belongs to another application database')
            c.execute("INSERT OR IGNORE INTO images.image_store_meta VALUES('owner',?)",(identity,))
            c.commit()
            c.execute("CREATE TABLE IF NOT EXISTS images.art_cache(cache_key TEXT PRIMARY KEY,content BLOB NOT NULL,mime TEXT NOT NULL,metadata TEXT NOT NULL,updated_at INTEGER NOT NULL)")
            c.execute("CREATE INDEX IF NOT EXISTS images.art_oracle_face_kind ON art_cache(json_extract(metadata,'$.oracleId'),CAST(json_extract(metadata,'$.face') AS INTEGER),json_extract(metadata,'$.kind'))")
            for statement in thumbnail_schema('images.'):c.execute(statement)
            c.execute("INSERT INTO main.meta VALUES('image_cache_directory',?) ON CONFLICT(key)DO UPDATE SET value=excluded.value",(str(self.cache_root.resolve()),));c.commit()

    @contextmanager
    def connection(self,write=False,image=False):
        if self.relocation_active.is_set():raise ConflictError('Storage relocation is prepared or in progress; restart the application')
        try:current_stat=self.database.stat()
        except FileNotFoundError as exc:raise ConflictError('Storage is being activated; restart the application')from exc
        if hasattr(self,'_database_identity')and self._database_identity!=(current_stat.st_dev,current_stat.st_ino):raise ConflictError('Storage was replaced by a prepared copy; restart the application')
        if self.maintenance_active.is_set():
            raise ConflictError('Storage maintenance is in progress; try again when it finishes')
        # Metadata keeps WAL's concurrent reader/writer behavior. Only actual
        # image operations and explicitly marked bulk work share the HDD lane.
        lane=self.image_io.operation(timeout=self._busy_timeout_ms()/1000,label='sql')if image or self.image_io.is_background()else self.image_io.measure('sql')
        with lane,operation_lock(self.root, blocking=False):
            if self.maintenance_active.is_set():
                raise ConflictError('Storage maintenance is in progress; try again when it finishes')
            timeout=self._busy_timeout_ms()
            c=sqlite3.connect(self.database,timeout=timeout/1000,isolation_level=None);c.row_factory=sqlite3.Row
            try:
                c.execute('PRAGMA busy_timeout='+str(timeout));c.execute('PRAGMA foreign_keys=ON');c.execute('PRAGMA synchronous=FULL')
                retired=c.execute("SELECT value FROM meta WHERE key='storage_relocated_to'").fetchone()
                if retired:raise ConflictError('This storage was relocated; restart the application to use '+retired[0])
                self._attach_cache(c)
                if write:
                    c.execute('PRAGMA busy_timeout='+str(self._busy_timeout_ms()))
                    c.execute('BEGIN IMMEDIATE')
                yield c
                if write:c.execute('COMMIT')
            except BaseException:
                if write and c.in_transaction:c.execute('ROLLBACK')
                raise
            finally:c.close()

    def _issue(self,c,source,error):
        c.execute('INSERT OR REPLACE INTO migration_issues VALUES (?,?)',(source,str(error)))

    def _migrate_legacy(self):
        # One writer lock makes the entire migration atomic across services.
        with self.connection(write=True) as c:
            if c.execute("SELECT 1 FROM meta WHERE key='legacy_json_migrated'").fetchone():return
            for path in sorted((self.root/'decks').glob('*.json')):
                try:
                    raw=json.loads(path.read_text(encoding='utf-8'));deck=self.validate_deck(raw,legacy=True)
                    if isinstance(raw.get('draft'),bool):deck['draft']=raw['draft']
                    c.execute("INSERT OR IGNORE INTO decks VALUES (?,'user',?,?)",(deck['id'],encode(deck),now()))
                except (OSError,ValueError,TypeError) as exc:self._issue(c,'decks/'+path.name,exc)
            path=self.root/'settings.json'
            if path.exists():
                try:
                    values=json.loads(path.read_text(encoding='utf-8'))
                    if not isinstance(values,dict):raise ValueError('Settings must be an object')
                    for key,value in values.items():
                        try:
                            self.validate_settings({key:value});c.execute('INSERT OR IGNORE INTO settings VALUES (?,?)',(key,encode(value)))
                        except ValueError as exc:self._issue(c,'settings.json:'+key,exc)
                except (OSError,ValueError,TypeError) as exc:self._issue(c,'settings.json',exc)
            path=self.root/'hidden-decks.json'
            if path.exists():
                try:
                    values=json.loads(path.read_text(encoding='utf-8'))
                    if not isinstance(values,list):raise ValueError('Hidden decks must be a list')
                    for i,identifier in enumerate(values):
                        try:
                            self.check_id(identifier);c.execute('INSERT OR IGNORE INTO hidden_decks VALUES (?)',(identifier,))
                        except ValueError as exc:self._issue(c,'hidden-decks.json:'+str(i),exc)
                except (OSError,ValueError,TypeError) as exc:self._issue(c,'hidden-decks.json',exc)
            c.execute("INSERT INTO meta VALUES('legacy_json_migrated',?)",(str(now()),))

    def _seed_bundled(self):
        with self.lock:
            paths=sorted(self.bundled.glob('*.json')) if self.bundled.exists() else []
            signature=tuple((p.name,p.stat().st_mtime_ns,p.stat().st_size) for p in paths)
            if signature==self._bundle_signature:return
            with self.connection(write=True) as c:
                for path in paths:
                    try:
                        value=json.loads(path.read_text(encoding='utf-8'))
                        if not isinstance(value,dict) or 'id' not in value:continue
                        deck=self.validate_deck(value)
                        c.execute("INSERT INTO decks VALUES (?,'bundled',?,?) ON CONFLICT(id,origin) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at WHERE decks.payload<>excluded.payload",(deck['id'],encode(deck),now()))
                    except (OSError,ValueError,TypeError) as exc:self._issue(c,'bundled/'+path.name,exc)
            self._bundle_signature=signature

    def _migrate_legacy_art(self,batch_size=16):
        with self.connection() as c:
            if c.execute("SELECT 1 FROM meta WHERE key='legacy_art_migrated'").fetchone():return
        paths=sorted((self.root/'art').glob('*.jpg'))
        # Small committed batches bound memory and permit restart after a crash.
        # INSERT OR IGNORE protects artwork a running service already cached.
        for start in range(0,len(paths),batch_size):
            prepared=[];issues=[]
            for path in paths[start:start+batch_size]:
                try:
                    self._check_art_key(path.name)
                    if not 2<=path.stat().st_size<=3*1024*1024:raise ValueError('Artwork is outside the 3 MB cache limit')
                    data=path.read_bytes()
                    if not data.startswith(b'\xff\xd8'):raise ValueError('Not a JPEG cache entry')
                    prepared.append((path.name,sqlite3.Binary(data),encode({'legacySource':'art/'+path.name}),now()))
                except (OSError,ValueError) as exc:issues.append(('art/'+path.name,exc))
            with self.connection(write=True) as c:
                if c.execute("SELECT 1 FROM meta WHERE key='legacy_art_migrated'").fetchone():return
                prepared=[row for row in prepared if self.art_mirror_import_allowed(row[0],c)]
                c.executemany("INSERT OR IGNORE INTO art_cache VALUES (?,?,'image/jpeg',?,?)",prepared)
                for source,error in issues:self._issue(c,source,error)
        with self.connection(write=True) as c:c.execute("INSERT OR IGNORE INTO meta VALUES('legacy_art_migrated',?)",(str(now()),))

    def health(self):
        with self.connection() as c:issues=[dict(r) for r in c.execute('SELECT source,error FROM migration_issues ORDER BY source')]
        return {'database':'app.sqlite','dataDirectory':str(self.root.resolve()),'cacheDirectory':str(self.cache_root.resolve()),'cacheDatabase':str(self.cache_database.resolve()),'separateCache':self.separate_cache,'schemaVersion':USER_SCHEMA_VERSION,'journalMode':'wal','legacyFilesPreserved':True,'migrationIssues':issues}

    def list_decks(self,origin=None):
        self._seed_bundled()
        if origin not in (None,'','all','user','starter','bundled'):raise ValueError('Deck origin must be user, starter or all')
        with self.connection() as c:
            if origin in ('starter','bundled'):
                rows=c.execute("SELECT payload,origin FROM decks WHERE origin='bundled'")
            elif origin=='user':
                rows=c.execute("SELECT payload,origin FROM decks WHERE origin='user' AND NOT EXISTS(SELECT 1 FROM hidden_decks h WHERE h.id=decks.id)")
            else:
                rows=c.execute("SELECT d.payload,d.origin FROM decks d WHERE NOT EXISTS(SELECT 1 FROM hidden_decks h WHERE h.id=d.id) AND (d.origin='user' OR NOT EXISTS(SELECT 1 FROM decks u WHERE u.id=d.id AND u.origin='user'))")
            decks=[dict(json.loads(r['payload']),origin=r['origin']) for r in rows]
        for deck in decks:
            deck['collection']='mine' if deck['origin']=='user' else 'starter'
            if origin in ('starter','bundled'):
                deck['sourceId']=deck['id'];deck['id']='starter-'+deck['id'];deck['readOnly']=True
        return sorted(decks,key=lambda d:(d['format'],d['name'].casefold()))

    def get_deck(self,identifier):
        self.check_id(identifier)
        if identifier.startswith('starter-'):
            self._seed_bundled()
            with self.connection() as c:
                # Preserve a pre-existing owned identifier if it predates these
                # aliases; normal new templates never write into this namespace.
                user=c.execute("SELECT payload FROM decks WHERE id=? AND origin='user'",(identifier,)).fetchone()
                if user:return dict(json.loads(user[0]),origin='user',collection='mine')
                row=c.execute("SELECT payload FROM decks WHERE id=? AND origin='bundled'",(identifier[len('starter-'):],)).fetchone()
            if row:
                deck=json.loads(row[0]);return dict(deck,id=identifier,sourceId=deck['id'],origin='bundled',collection='starter',readOnly=True)
        if identifier.startswith('precon-'):
            with self.connection() as c: user=c.execute("SELECT payload FROM decks WHERE id=? AND origin='user'",(identifier,)).fetchone()
            if user:return dict(json.loads(user[0]),origin='user',collection='mine')
            return self.get_precon(identifier)
        return next((d for d in self.list_decks() if d['id']==identifier),None)

    def copy_deck(self,identifier,name=None,format_name=None):
        source=self.get_deck(identifier)
        if source is None:raise KeyError('Deck not found')
        value=dict(source)
        value['id']='deck-'+uuid.uuid4().hex[:16]
        if name is not None:value['name']=name
        if format_name is not None:value['format']=format_name
        if str(value.get('format','')).lower() not in FORMATS:raise ValueError('Choose Commander, Modern, Standard or Pioneer for the editable copy; the original product is an unvalidated archive')
        value['sourceDeck']={'id':source['id'],'name':source['name'],'origin':source.get('origin','user')}
        return self.validate_deck(value)

    def _owned_save(self,value,identifier=None):
        requested=identifier or value.get('id')
        if requested:
            self.check_id(requested)
            with self.connection() as c:
                owned=c.execute("SELECT 1 FROM decks WHERE id=? AND origin='user'",(requested,)).fetchone()
                bundled=c.execute("SELECT 1 FROM decks WHERE id=? AND origin='bundled'",(requested,)).fetchone()
            template=None if owned else self.get_deck(requested) if bundled or requested.startswith(('starter-','precon-')) else None
            if template and template.get('origin')!='user':
                copied=dict(value,id='deck-'+uuid.uuid4().hex[:16],sourceDeck={'id':template['id'],'name':template['name'],'origin':template['origin']})
                return self.validate_deck(copied)
        return self.validate_deck(value,identifier)

    def save_deck(self,value,identifier=None,validation=None):
        deck=self._owned_save(value,identifier)
        if validation is not None:deck['draft']=bool(validation['draft'])
        elif isinstance(value.get('draft'),bool):deck['draft']=value['draft']
        with self.connection(write=True) as c:
            c.execute("INSERT INTO decks VALUES (?,'user',?,?) ON CONFLICT(id,origin) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at",(deck['id'],encode(deck),now()))
            c.execute('DELETE FROM hidden_decks WHERE id=?',(deck['id'],))
        result=dict(deck,origin='user',collection='mine')
        if validation is not None:result['validation']=validation
        return result

    def delete_deck(self,identifier):
        self.check_id(identifier)
        with self.connection(write=True) as c:
            if not c.execute('SELECT 1 FROM decks WHERE id=? AND NOT EXISTS(SELECT 1 FROM hidden_decks WHERE id=?)',(identifier,identifier)).fetchone():return False
            c.execute("DELETE FROM decks WHERE id=? AND origin='user'",(identifier,));c.execute('INSERT OR IGNORE INTO hidden_decks VALUES (?)',(identifier,))
        return True

    def settings(self):
        with self.connection() as c:values={r['key']:json.loads(r['value']) for r in c.execute('SELECT * FROM settings')}
        return {**DEFAULT_SETTINGS,**values}

    def save_settings(self,value):
        self.validate_settings(value)
        with self.connection(write=True) as c:
            for key,item in value.items():c.execute('INSERT INTO settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',(key,encode(item)))
        return self.settings()

    def ui_layout(self):
        with self.connection() as c:row=c.execute("SELECT value FROM ui_layout WHERE key='main'").fetchone()
        return json.loads(row[0]) if row else {}

    def save_ui_layout(self,value):
        if not isinstance(value,dict) or len(encode(value))>256*1024:raise ValueError('UI layout must be an object up to 256 KB')
        with self.connection(write=True) as c:c.execute("INSERT INTO ui_layout VALUES('main',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(encode(value),))
        return value

    @staticmethod
    def _check_art_key(key):
        if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,180}\.jpg',key):raise ValueError('Invalid artwork cache key')

    def get_art(self,cache_key,legacy_keys=()):
        self._check_art_key(cache_key)
        with self.connection(image=True) as c:
            for key in (cache_key,*legacy_keys):
                self._check_art_key(key)
                row=c.execute('SELECT content FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                if row:return bytes(row[0])
        for key in (cache_key,*legacy_keys):
            self._check_art_key(key);path=self.root/'art'/key
            if self.art_mirror_import_allowed(key) and path.is_file() and path.stat().st_size<=3*1024*1024:
                data=path.read_bytes()
                if data.startswith(b'\xff\xd8'):
                    with self.connection(write=True,image=True)as c:
                        if not self.art_mirror_import_allowed(key,c):continue
                        c.execute("INSERT INTO art_cache VALUES (?,?,'image/jpeg',?,?) ON CONFLICT(cache_key)DO NOTHING",(cache_key,sqlite3.Binary(data),encode({'legacySource':'art/'+key}),now()))
                        row=c.execute('SELECT content FROM art_cache WHERE cache_key=?',(cache_key,)).fetchone()
                        if row:self._art_source(c,cache_key,bytes(row[0]))
                    if row:self.queue_thumbnail(cache_key)
                    return bytes(row[0]) if row else None
        return None

    def save_art(self,cache_key,data,metadata=None):
        self._check_art_key(cache_key)
        if not isinstance(data,bytes) or not 2<=len(data)<=3*1024*1024 or not data.startswith(b'\xff\xd8'):raise ValueError('Invalid JPEG artwork')
        with self.connection(write=True,image=True) as c:
            c.execute("INSERT INTO art_cache VALUES (?,?,'image/jpeg',?,?) ON CONFLICT(cache_key) DO UPDATE SET content=excluded.content,metadata=excluded.metadata,updated_at=excluded.updated_at",(cache_key,sqlite3.Binary(data),encode(metadata or {}),now()))
            digest=self._art_source(c,cache_key,data)
            c.execute('UPDATE '+self.image_table('art_thumbnails')+' SET metadata=? WHERE cache_key=? AND source_digest=?',(encode(metadata or {}),cache_key,digest))
        self.thumbnails.request(cache_key,digest)

    def image_table(self,name):
        if name not in('art_sources','art_thumbnails'):raise ValueError('Unknown derived image table')
        return ('images.'if self.separate_cache else'main.')+name

    def _art_source(self,connection,key,data):
        import hashlib
        digest=hashlib.sha256(data).hexdigest()
        connection.execute('INSERT INTO '+self.image_table('art_sources')+' VALUES(?,?) ON CONFLICT(cache_key)DO UPDATE SET digest=excluded.digest',(key,digest))
        return digest

    def flush_thumbnails(self,timeout=5):return self.thumbnails.flush(timeout)
    def close_images(self):self.thumbnails.close()
    def enable_thumbnails(self):
        if self.thumbnails.closed.is_set():self.thumbnails=Thumbnails(self)
        self.thumbnails.enabled=True
        return self.thumbnails.status()['available']
    @contextmanager
    def quiesce_images(self):
        with self.thumbnails.pause(),self.image_io.operation(timeout=3):yield
    @contextmanager
    def _exclusive_maintenance(self,readonly=False):
        # Retire only the derivative worker's brief disk section. CPU decoding
        # need not finish before purge, and all original cross-process locks
        # and generation fences remain owned by MaintenanceStore.
        with self.quiesce_images(),super()._exclusive_maintenance(readonly):yield
    def queue_thumbnail(self,cache_key):
        self._check_art_key(cache_key)
        return self.thumbnails.request(cache_key)
