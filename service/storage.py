"""SQLite is authoritative for user data; legacy files remain untouched backups."""
from contextlib import contextmanager
import json
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
USER_SCHEMA_VERSION=1

class Storage(StorageSchema,ReplayStore,ArtworkStore,TokenPreferences,HistoryStore,PreconStore,ProfileStore):
    def __init__(self,data_dir,bundled_decks):
        self.root=Path(data_dir);self.bundled=Path(bundled_decks)
        self.root.mkdir(parents=True,exist_ok=True)
        self.database=self.root/'app.sqlite';self.lock=threading.RLock();self._bundle_signature=None
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
            c.executescript('''BEGIN IMMEDIATE;
                CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS decks(id TEXT NOT NULL,origin TEXT NOT NULL,payload TEXT NOT NULL,updated_at INTEGER NOT NULL,PRIMARY KEY(id,origin));
                CREATE TABLE IF NOT EXISTS hidden_decks(id TEXT PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS ui_layout(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS migration_issues(source TEXT PRIMARY KEY,error TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS art_cache(cache_key TEXT PRIMARY KEY,content BLOB NOT NULL,mime TEXT NOT NULL,metadata TEXT NOT NULL,updated_at INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS art_oracle_face_kind ON art_cache(json_extract(metadata,'$.oracleId'),CAST(json_extract(metadata,'$.face') AS INTEGER),json_extract(metadata,'$.kind'));
                CREATE TABLE IF NOT EXISTS token_preferences(deck_id TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS replays(id TEXT PRIMARY KEY,payload TEXT NOT NULL,status TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,finished_at INTEGER);
                CREATE TABLE IF NOT EXISTS replay_events(replay_id TEXT NOT NULL REFERENCES replays(id) ON DELETE CASCADE,sequence INTEGER NOT NULL,type TEXT NOT NULL,timestamp TEXT,payload TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(replay_id,sequence));
                CREATE INDEX IF NOT EXISTS replays_created ON replays(created_at DESC);
                CREATE INDEX IF NOT EXISTS replay_frames ON replay_events(replay_id,type,sequence);
                INSERT OR IGNORE INTO meta VALUES('schema_version','1');COMMIT;''')
        finally:c.close()
        self._migrate_legacy();self._migrate_legacy_art();self._seed_bundled();self._init_precons();self._init_profile_storage()

    @contextmanager
    def connection(self,write=False):
        c=sqlite3.connect(self.database,timeout=30,isolation_level=None);c.row_factory=sqlite3.Row
        c.execute('PRAGMA busy_timeout=30000');c.execute('PRAGMA foreign_keys=ON');c.execute('PRAGMA synchronous=FULL')
        try:
            if write:c.execute('BEGIN IMMEDIATE')
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
                c.executemany("INSERT OR IGNORE INTO art_cache VALUES (?,?,'image/jpeg',?,?)",prepared)
                for source,error in issues:self._issue(c,source,error)
        with self.connection(write=True) as c:c.execute("INSERT OR IGNORE INTO meta VALUES('legacy_art_migrated',?)",(str(now()),))

    def health(self):
        with self.connection() as c:issues=[dict(r) for r in c.execute('SELECT source,error FROM migration_issues ORDER BY source')]
        return {'database':'app.sqlite','dataDirectory':str(self.root.resolve()),'schemaVersion':USER_SCHEMA_VERSION,'journalMode':'wal','legacyFilesPreserved':True,'migrationIssues':issues}

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
        with self.connection() as c:
            for key in (cache_key,*legacy_keys):
                self._check_art_key(key)
                row=c.execute('SELECT content FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                if row:return bytes(row[0])
        for key in (cache_key,*legacy_keys):
            self._check_art_key(key);path=self.root/'art'/key
            if path.is_file() and path.stat().st_size<=3*1024*1024:
                data=path.read_bytes()
                if data.startswith(b'\xff\xd8'):
                    self.save_art(cache_key,data,{'legacySource':'art/'+key});return data
        return None

    def save_art(self,cache_key,data,metadata=None):
        self._check_art_key(cache_key)
        if not isinstance(data,bytes) or not 2<=len(data)<=3*1024*1024 or not data.startswith(b'\xff\xd8'):raise ValueError('Invalid JPEG artwork')
        with self.connection(write=True) as c:c.execute("INSERT INTO art_cache VALUES (?,?,'image/jpeg',?,?) ON CONFLICT(cache_key) DO UPDATE SET content=excluded.content,metadata=excluded.metadata,updated_at=excluded.updated_at",(cache_key,sqlite3.Binary(data),encode(metadata or {}),now()))
