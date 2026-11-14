"""Explicit restart-bound relocation with separate durable image-cache SQLite."""
from contextlib import contextmanager
from copy import deepcopy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import uuid

from paths import config_file, read_config, explicit_override
from replays import ConflictError, now

RESERVE = 64 * 1024 * 1024
ART_SCHEMA = "CREATE TABLE art_cache(cache_key TEXT PRIMARY KEY,content BLOB NOT NULL,mime TEXT NOT NULL,metadata TEXT NOT NULL,updated_at INTEGER NOT NULL)"
ART_INDEX = "CREATE INDEX art_oracle_face_kind ON art_cache(json_extract(metadata,'$.oracleId'),CAST(json_extract(metadata,'$.face') AS INTEGER),json_extract(metadata,'$.kind'))"


@contextmanager
def _connection(*args,**kwargs):
    connection=sqlite3.connect(*args,**kwargs)
    try:
        yield connection
        connection.commit()
    except BaseException:
        connection.rollback()
        raise
    finally:connection.close()


def _atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(',', ':'))
            stream.flush();os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
        try:os.fsync(directory)
        finally:os.close(directory)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)


@contextmanager
def _config_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path.with_suffix('.lock'), os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        try:fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:raise ConflictError('Another storage location change is active') from exc
        yield
    finally:os.close(fd)


def _directory(value, label):
    if not isinstance(value, str) or not value.strip() or len(value) > 4096 or '\x00' in value:
        raise ValueError(label + ' must be an absolute directory path')
    path = Path(value.strip()).expanduser()
    if not path.is_absolute():raise ValueError(label + ' must be an absolute directory path')
    path = path.resolve()
    if path.exists() and not path.is_dir():raise ValueError(label + ' is not a directory')
    parent = path
    while not parent.exists():parent=parent.parent
    if not os.access(parent, os.W_OK | os.X_OK):raise ValueError(label + ' is not writable')
    return path


def _nearest_existing(path):
    while not path.exists():path=path.parent
    return path


def _backup(source_path, destination_path, check=None, update=None):
    source = sqlite3.connect(source_path.resolve().as_uri() + '?mode=ro', uri=True, timeout=5)
    destination = sqlite3.connect(destination_path, timeout=5)
    last = 0
    try:
        def progress(status, remaining, total):
            nonlocal last
            if check:check()
            if update and time.monotonic() - last > .2:
                last=time.monotonic();update(total - remaining,total)
        source.backup(destination, pages=256, progress=progress, sleep=.01)
        destination.commit()
        if destination.execute('PRAGMA quick_check').fetchone()[0] != 'ok':raise ValueError('Copied SQLite database failed its integrity check')
    finally:source.close();destination.close()


def _process_started_ms(pid):
    """Linux process birth time; proof checks tolerate coarse boot-time seconds."""
    try:
        fields=Path('/proc/'+str(pid)+'/stat').read_text().rsplit(')',1)[1].split()
        ticks=int(fields[19]);boot=next(int(line.split()[1])for line in Path('/proc/stat').read_text().splitlines()if line.startswith('btime '))
        return round(boot*1000+ticks*1000/os.sysconf('SC_CLK_TCK'))
    except (OSError,ValueError,IndexError,StopIteration):return None


def _assert_cooperative_owners(path,connection=None):
    if not Path(path).exists():return
    if connection is None:
        with _connection(Path(path).resolve().as_uri()+'?mode=ro',uri=True,timeout=2)as current:return _assert_cooperative_owners(path,current)
    tables={row[0]for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'replay_outbox'not in tables:return
    controls=dict(connection.execute('SELECT key,value FROM replay_outbox_control'))if'replay_outbox_control'in tables else{}
    for row in connection.execute('SELECT DISTINCT owner_pid FROM replay_outbox'):
        pid=row[0]
        if not isinstance(pid,int)or pid<=0:continue
        try:os.kill(pid,0)
        except ProcessLookupError:continue
        except PermissionError:pass
        try:stamp=int(controls.get('owner_started:'+str(pid),'0'))
        except ValueError:stamp=0
        actual=_process_started_ms(pid)
        # /proc/stat boot time is rounded to seconds on some kernels/JDKs.
        if controls.get('owner_protocol:'+str(pid))!='1'or stamp<=0 or actual is None or abs(stamp-actual)>2000:
            raise ConflictError('Close older running Love2Gathering clients before moving storage; their game engine cannot safely follow this location change')


def _outbox_signature(path,connection=None):
    digest=hashlib.sha256(b'love2gathering-outbox-v1')
    if not Path(path).exists():return digest.hexdigest()
    if connection is None:
        with _connection(Path(path).resolve().as_uri()+'?mode=ro',uri=True,timeout=2)as current:
            return _outbox_signature(path,current)
    tables={row[0]for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'replay_outbox'not in tables:return digest.hexdigest()
    for table,order in(('replay_outbox','id'),('replay_outbox_events','replay_id,sequence')):
        if table not in tables:continue
        for row in connection.execute('SELECT * FROM '+table+' ORDER BY '+order):
            data=json.dumps(tuple(row),separators=(',',':')).encode()
            digest.update(table.encode()+str(len(data)).encode()+b':'+data)
    return digest.hexdigest()


def _restore_original(pending):
    main=Path(pending['sourceDirectory'])/'app.sqlite'
    with _connection(main)as source:
        marker=source.execute("SELECT value FROM meta WHERE key='storage_relocation_job'").fetchone()
        if marker and marker[0]==pending['id']:source.execute("DELETE FROM meta WHERE key IN('storage_relocated_to','storage_relocation_job')")
    outbox=main.with_name('replay-outbox.sqlite')
    if outbox.exists():
        with _connection(outbox)as source:
            if source.execute("SELECT 1 FROM sqlite_master WHERE type='table'AND name='replay_outbox_control'").fetchone():source.execute("DELETE FROM replay_outbox_control WHERE key='relocated'AND value=?",(pending['databaseDirectory'],))


def _installed_job(database,job_id):
    metadata={
        'app.sqlite':('meta','storage_activation_job'),
        'images.sqlite':('image_store_meta','activation_job'),
        'replay-outbox.sqlite':('replay_outbox_control','activation_job')}
    if Path(database).name not in metadata or Path(database).is_symlink():return False
    table,key=metadata[Path(database).name]
    try:
        with _connection(Path(database).resolve().as_uri()+'?mode=ro',uri=True,timeout=2)as connection:
            row=connection.execute('SELECT value FROM '+table+' WHERE key=?',(key,)).fetchone()
            return bool(row and row[0]==job_id)
    except sqlite3.Error:return False


def _sync_directory(directory):
    handle=os.open(directory,os.O_RDONLY|getattr(os,'O_DIRECTORY',0))
    try:os.fsync(handle)
    finally:os.close(handle)


def _staging_directory(destination):
    stage=Path(tempfile.mkdtemp(prefix='.love2gathering-relocate-',dir=destination))
    probe=stage/'.activation-probe';linked=stage/'.activation-probe-link'
    try:
        probe.write_bytes(b'safe activation')
        os.link(probe,linked,follow_symlinks=False)
    except OSError as exc:
        shutil.rmtree(stage,ignore_errors=True)
        raise ValueError('The selected drive does not support safe atomic storage activation; choose another directory')from exc
    finally:
        if probe.exists():probe.unlink()
        if linked.exists():linked.unlink()
    return stage


def _move_preserving_original(prepared,destination,job_id,allow_existing=False):
    prepared,destination=Path(prepared),Path(destination)
    if not prepared.exists():
        if destination.exists()and _installed_job(destination,job_id):return
        raise ConflictError('Prepared copy is unavailable or its installed destination changed; originals were preserved')
    if not _installed_job(prepared,job_id):raise ConflictError('Prepared copy identity changed; originals were preserved')
    if destination.is_file()and not destination.is_symlink()and _installed_job(destination,job_id):
        if not os.path.samefile(prepared,destination):raise ConflictError('Installed destination changed; originals were preserved')
        prepared.unlink();_sync_directory(prepared.parent);return
    destination.parent.mkdir(parents=True,exist_ok=True)
    if destination.exists()or destination.is_symlink():
        if not allow_existing or destination.is_symlink():raise ConflictError('Destination appeared after validation; it was preserved: '+str(destination))
        backup=destination.with_name(destination.name+'.before-'+job_id)
        with _connection(destination,isolation_level=None)as connection:
            row=connection.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
            if row[0]:raise ConflictError('A previous storage process is still reading; close it before restarting')
        # A no-replace hard link is atomic and stays on the same volume. A
        # restart between link/unlink recognizes the same preserved original.
        if not backup.exists():
            try:os.link(destination,backup,follow_symlinks=False)
            except FileExistsError:pass
        if not backup.is_file()or not os.path.samefile(destination,backup):raise ConflictError('A different relocation backup already exists; files were preserved')
        destination.unlink();_sync_directory(destination.parent)
    try:os.link(prepared,destination,follow_symlinks=False)
    except FileExistsError as exc:raise ConflictError('Destination appeared during activation; it was preserved: '+str(destination))from exc
    _sync_directory(destination.parent)
    prepared.unlink();_sync_directory(prepared.parent)


def activate_pending(environ=None, home=None):
    """Launcher-only activation before any catalog/engine writer is started."""
    env = os.environ if environ is None else environ
    path = config_file(env,home)
    config = read_config(env,home)
    pending = config.get('pending')
    if not pending:return False
    if explicit_override(env,'LOVE2GATHERING_DATA_DIR') and Path(env['LOVE2GATHERING_DATA_DIR']).resolve()!=Path(pending['databaseDirectory']):
        raise ConflictError('Remove LOVE2GATHERING_DATA_DIR before applying the saved storage location')
    if explicit_override(env,'LOVE2GATHERING_CACHE_DIR') and Path(env['LOVE2GATHERING_CACHE_DIR']).resolve()!=Path(pending['cacheDirectory']):
        raise ConflictError('Remove LOVE2GATHERING_CACHE_DIR before applying the saved cache location')
    from maintenance import operation_lock
    with _config_lock(path),operation_lock(pending['sourceDirectory'],exclusive=True,blocking=False,filename='.image-download.lock'),operation_lock(pending['sourceDirectory'],exclusive=True,blocking=False):
        if not pending.get('activationStarted'):
            with _connection(Path(pending['sourceDirectory'])/'app.sqlite')as source:
                marker=source.execute("SELECT value FROM meta WHERE key='storage_relocation_job'").fetchone()
            signature_ok=not pending.get('outboxSignature')or _outbox_signature(Path(pending['sourceDirectory'])/'replay-outbox.sqlite')==pending['outboxSignature']
            try:_assert_cooperative_owners(Path(pending['sourceDirectory'])/'replay-outbox.sqlite')
            except ConflictError:signature_ok=False
            if not marker or marker[0]!=pending['id']or not signature_ok:
                # An interrupted pre-retirement or uncooperative old engine
                # cannot make us activate a stale recording snapshot.
                _restore_original(pending)
                config.pop('pending',None);config['lastError']='A recording changed before activation; the original storage remains active. Prepare the location change again.';_atomic_json(path,config)
                for folder in pending.get('stagingDirectories',[]):
                    if Path(folder).name.startswith('.love2gathering-relocate-'):shutil.rmtree(folder,ignore_errors=True)
                return False
            with _connection(Path(pending['sourceDirectory'])/'replay-outbox.sqlite')as outbox:
                outbox.execute('CREATE TABLE IF NOT EXISTS replay_outbox_control(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
                outbox.execute("INSERT INTO replay_outbox_control VALUES('relocated',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(pending['databaseDirectory'],))
            destinations=[(pending.get('preparedCache'),Path(pending['cacheDirectory'])/'images.sqlite',False),
                          (pending['preparedDatabase'],Path(pending['databaseDirectory'])/'app.sqlite',Path(pending['databaseDirectory'])==Path(pending['sourceDirectory'])),
                          (pending.get('preparedOutbox'),Path(pending['databaseDirectory'])/'replay-outbox.sqlite',Path(pending['databaseDirectory'])==Path(pending['sourceDirectory']))]
            foreign=next((target for prepared,target,original in destinations if prepared and(target.exists()or target.is_symlink())and not original and not _installed_job(target,pending['id'])),None)
            if foreign is not None:
                _restore_original(pending);config.pop('pending',None);config['lastError']='A destination appeared after validation and was preserved: '+str(foreign);_atomic_json(path,config)
                for folder in pending.get('stagingDirectories',[]):
                    if Path(folder).name.startswith('.love2gathering-relocate-'):shutil.rmtree(folder,ignore_errors=True)
                return False
            pending['activationStarted']=True;config['pending']=pending;_atomic_json(path,config)
        # Cache is installed first; the app copy contains no legacy art table.
        if pending.get('preparedCache'):
            _move_preserving_original(pending['preparedCache'],Path(pending['cacheDirectory'])/'images.sqlite',pending['id'])
        _move_preserving_original(pending['preparedDatabase'],Path(pending['databaseDirectory'])/'app.sqlite',pending['id'],allow_existing=Path(pending['databaseDirectory'])==Path(pending['sourceDirectory']))
        if pending.get('preparedOutbox'):
            _move_preserving_original(pending['preparedOutbox'],Path(pending['databaseDirectory'])/'replay-outbox.sqlite',pending['id'],allow_existing=Path(pending['databaseDirectory'])==Path(pending['sourceDirectory']))
        config['active']={key:pending[key]for key in('databaseDirectory','cacheDirectory')}
        config.pop('pending',None)
        config['lastAppliedAt']=now()
        _atomic_json(path,config)
    for folder in pending.get('stagingDirectories',[]):
        target=Path(folder)
        if target.name.startswith('.love2gathering-relocate-'):
            try:target.rmdir()
            except OSError:pass
    return True


class StorageLocations:
    def __init__(self,storage,*,environ=None,home=None):
        self.storage=storage;self.env=os.environ if environ is None else environ;self.home=home
        self.path=config_file(self.env,home);self.lock=threading.RLock();self.worker=None;self.cancelled=threading.Event();self.operation=None;self.process=None

    def _active(self):
        s=self.storage
        return {'databaseDirectory':str(s.root.resolve()),'cacheDirectory':str(s.cache_root.resolve()),
                'databaseFile':str(s.database.resolve()),'cacheDatabaseFile':str(s.cache_database.resolve()),'separateCache':s.separate_cache}

    def status(self):
        with self.lock:
            config=read_config(self.env,self.home);pending=config.get('pending')
            foreign=bool(pending and Path(pending['sourceDirectory']).resolve()!=self.storage.root.resolve())
            local_pending=pending if not foreign else None
            configured=config.get('active')
            if configured and Path(configured['databaseDirectory']).resolve()!=self.storage.root.resolve():configured=None
            operation=self.operation
            if operation and operation.get('state')=='prepared'and not local_pending:operation=dict(operation,state='cancelled',message='Location change is no longer pending for this store')
            return deepcopy({'active':self._active(),'configured':local_pending and{key:local_pending[key]for key in('databaseDirectory','cacheDirectory')}or configured,
                    'restartRequired':bool(local_pending),'foreignPending':foreign,'operation':operation,'configFile':str(self.path),'error':config.get('lastError'),
                    'overridden':{'database':explicit_override(self.env,'LOVE2GATHERING_DATA_DIR'),
                                  'cache':explicit_override(self.env,'LOVE2GATHERING_CACHE_DIR')}})

    def validate(self,body):
        if not isinstance(body,dict)or set(body)!={'databaseDirectory','cacheDirectory'}:raise ValueError('Choose databaseDirectory and cacheDirectory')
        database=_directory(body['databaseDirectory'],'Database folder');cache=_directory(body['cacheDirectory'],'Image cache folder')
        source=self.storage
        if database/'app.sqlite'!=source.database.resolve()and(database/'app.sqlite').exists():raise ValueError('The destination already contains app.sqlite; choose an empty application folder')
        if cache/'images.sqlite'!=source.cache_database.resolve()and(cache/'images.sqlite').exists():raise ValueError('The destination already contains images.sqlite; choose an empty image-cache folder')
        if database==source.root.resolve()and cache==source.cache_root.resolve()and source.separate_cache:raise ValueError('These locations are already active')
        overrides=self.status()['overridden']
        if overrides['database']and database!=source.root.resolve():raise ValueError('LOVE2GATHERING_DATA_DIR overrides Settings; remove it before changing the database folder')
        if overrides['cache']and cache!=source.cache_root.resolve():raise ValueError('LOVE2GATHERING_CACHE_DIR overrides Settings; remove it before changing the image cache folder')
        data_bytes=source.database.stat().st_size
        cache_bytes=source.cache_database.stat().st_size
        # Existing combined SQL requires a temporary main copy, cache extraction
        # and a new compact main file. Estimate a safe upper bound without an
        # expensive BLOB-size scan on the user's HDD.
        requirements={}
        for folder,amount in((database,data_bytes*2+RESERVE),(cache,(0 if source.separate_cache and cache/'images.sqlite'==source.cache_database.resolve()else cache_bytes*2)+RESERVE)):
            existing=_nearest_existing(folder);device=existing.stat().st_dev
            entry=requirements.setdefault(device,{'directory':str(existing),'requiredBytes':0,'freeBytes':shutil.disk_usage(existing).free})
            entry['requiredBytes']+=amount
        volumes=list(requirements.values())
        errors=['Not enough temporary free space on '+entry['directory']for entry in volumes if entry['freeBytes']<entry['requiredBytes']]
        return {'valid':not errors,'errors':errors,'databaseDirectory':str(database),'cacheDirectory':str(cache),
                'copyBytes':data_bytes+(0 if source.separate_cache and cache/'images.sqlite'==source.cache_database.resolve()else cache_bytes),
                'requiredBytes':sum(entry['requiredBytes']for entry in volumes),'freeBytes':min(entry['freeBytes']for entry in volumes),
                'volumes':volumes,'restartRequired':True,'originalsPreserved':True,
                'message':'Prepare a consistent copy, separate image BLOBs from saves, then restart. Originals remain as backups. The current store is paused after preparation.'}

    def prepare(self,body):
        plan=self.validate(body)
        if not plan['valid']:raise ValueError('; '.join(plan['errors']))
        with self.lock:
            if self.worker and self.worker.is_alive()or read_config(self.env,self.home).get('pending'):raise ConflictError('A location change is already preparing or awaiting restart')
            if self.storage._outbox_protected():raise ConflictError('Finish active games and flush native recordings before moving storage')
            _assert_cooperative_owners(self.storage.root/'replay-outbox.sqlite')
            with self.storage.connection()as c:
                if c.execute("SELECT 1 FROM replays WHERE status='recording'LIMIT 1").fetchone():raise ConflictError('Finish the current game before moving storage')
            self.cancelled.clear();job_id=uuid.uuid4().hex
            self.operation={'id':job_id,'state':'preparing','phase':'prepare','message':'Preparing storage copies','done':0,'total':0,'startedAt':now()}
            self.worker=threading.Thread(target=self._prepare_worker,args=(plan,job_id),name='Storage location preparation',daemon=True);self.worker.start()
        return self.status()

    def _check(self):
        if self.cancelled.is_set():raise ConflictError('Storage location preparation cancelled; originals remain active')

    def _update(self,**values):
        with self.lock:
            if self.operation is None:self.operation={'id':'location-control'}
            self.operation.update(values)

    def _prepare_worker(self,plan,job_id):
        s=self.storage;staging=[];success=False
        try:
            with _config_lock(self.path),s._exclusive_maintenance():
                self._check()
                if s._outbox_protected():raise ConflictError('Native recording became active; storage was preserved')
                _assert_cooperative_owners(s.root/'replay-outbox.sqlite')
                with _connection(s.database)as active:
                    if active.execute("SELECT 1 FROM replays WHERE status='recording'LIMIT 1").fetchone():raise ConflictError('A recording became active; storage was preserved')
                outbox_signature=_outbox_signature(s.root/'replay-outbox.sqlite')
                s.relocation_active.set()
                database=Path(plan['databaseDirectory']);cache=Path(plan['cacheDirectory'])
                database.mkdir(parents=True,exist_ok=True);cache.mkdir(parents=True,exist_ok=True)
                main_stage=_staging_directory(database);staging.append(main_stage)
                prepared_main=main_stage/'app.sqlite'
                self._update(phase='database',message='Copying database; original remains intact')
                _backup(s.database,prepared_main,self._check,lambda done,total:self._update(done=done,total=total))
                prepared_cache=None
                reuse_cache=s.separate_cache and cache/'images.sqlite'==s.cache_database.resolve()
                if not reuse_cache:
                    cache_stage=_staging_directory(cache);staging.append(cache_stage);prepared_cache=cache_stage/'images.sqlite'
                    self._update(phase='cache',message='Separating cached images from application saves',done=0,total=0)
                    if s.separate_cache:
                        _backup(s.cache_database,prepared_cache,self._check,lambda done,total:self._update(done=done,total=total))
                    else:
                        with _connection(prepared_main)as old,_connection(prepared_cache)as images:
                            images.execute('PRAGMA synchronous=FULL');images.execute(ART_SCHEMA)
                            images.execute('CREATE TABLE image_store_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
                            identity=old.execute("SELECT value FROM meta WHERE key='storage_identity'").fetchone()[0]
                            images.execute("INSERT INTO image_store_meta VALUES('owner',?)",(identity,));images.commit()
                            count=old.execute('SELECT count(*)FROM art_cache').fetchone()[0];done=0;rows=old.execute('SELECT cache_key,content,mime,metadata,updated_at FROM art_cache')
                            while True:
                                self._check();batch=rows.fetchmany(16)
                                if not batch:break
                                images.executemany('INSERT INTO art_cache VALUES(?,?,?,?,?)',batch);images.commit();done+=len(batch)
                                if done%256==0:self._update(done=done,total=count)
                            images.execute(ART_INDEX);images.commit()
                if prepared_cache:
                    with _connection(prepared_cache)as identified_cache:identified_cache.execute("INSERT INTO image_store_meta VALUES('activation_job',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(job_id,))
                self._check()
                with _connection(prepared_main,isolation_level=None)as copied:
                    copied.execute("INSERT INTO meta VALUES('image_cache_directory',?) ON CONFLICT(key)DO UPDATE SET value=excluded.value",(str(cache),))
                    copied.execute('DROP TABLE IF EXISTS art_cache');copied.execute("DELETE FROM meta WHERE key IN('storage_relocated_to','storage_relocation_job')")
                    copied.execute("INSERT INTO meta VALUES('storage_activation_job',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(job_id,))
                    copied.execute('PRAGMA journal_mode=DELETE')
                self._update(phase='compact',message='Compacting the new saves database; original remains intact',done=0,total=0)
                code="import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute('PRAGMA synchronous=FULL');c.execute('VACUUM');assert c.execute('PRAGMA quick_check').fetchone()[0]=='ok';c.close()"
                temporary_env=dict(os.environ,SQLITETMPDIR=str(main_stage.resolve()),TMPDIR=str(main_stage.resolve()))
                with self.lock:
                    self._check();self.process=subprocess.Popen([sys.executable,'-c',code,str(prepared_main)],env=temporary_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                    process=self.process
                try:
                    _,error=process.communicate()
                    self._check()
                    if process.returncode:raise ValueError('Prepared database compaction failed: '+error[-1000:].strip())
                finally:
                    with self.lock:self.process=None
                self._check()
                source_outbox=s.root/'replay-outbox.sqlite'
                with _connection(source_outbox,isolation_level=None)as outbox:
                    outbox.execute('CREATE TABLE IF NOT EXISTS replay_outbox_control(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
                    outbox.execute('BEGIN IMMEDIATE')
                    # Native recorder creation checks this table in the same
                    # writer transaction, so it cannot slip past retirement.
                    _assert_cooperative_owners(source_outbox,outbox)
                    if _outbox_signature(source_outbox,outbox)!=outbox_signature or s._outbox_protected():raise ConflictError('Native recordings changed during preparation; the original storage was preserved')
                    with _connection(s.database)as original:
                        if original.execute("SELECT 1 FROM replays WHERE status='recording'LIMIT 1").fetchone():raise ConflictError('A game became active; the original storage was preserved')
                    prepared_outbox=main_stage/'replay-outbox.sqlite'
                    _backup(source_outbox,prepared_outbox,self._check)
                    with _connection(prepared_outbox)as copied_outbox:
                        copied_outbox.execute("DELETE FROM replay_outbox_control WHERE key='relocated'")
                        copied_outbox.execute("INSERT INTO replay_outbox_control VALUES('activation_job',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(job_id,))
                    self._check()
                    pending={'id':job_id,'sourceDirectory':str(s.root.resolve()),'databaseDirectory':str(database),'cacheDirectory':str(cache),
                             'preparedDatabase':str(prepared_main),'preparedCache':str(prepared_cache)if prepared_cache else None,
                             'preparedOutbox':str(prepared_outbox),'outboxSignature':outbox_signature,'stagingDirectories':[str(path)for path in staging]}
                    config=read_config(self.env,self.home);config.update(version=1,pending=pending);config.pop('lastError',None)
                    _atomic_json(self.path,config)
                    try:
                        with _connection(s.database)as original:
                            original.execute("INSERT INTO meta VALUES('storage_relocated_to',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(str(database),))
                            original.execute("INSERT INTO meta VALUES('storage_relocation_job',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(job_id,))
                        outbox.execute("INSERT INTO replay_outbox_control VALUES('relocated',?)ON CONFLICT(key)DO UPDATE SET value=excluded.value",(str(database),))
                        outbox.execute('COMMIT')
                    except BaseException:
                        if outbox.in_transaction:outbox.execute('ROLLBACK')
                        _restore_original(pending)
                        config.pop('pending',None);_atomic_json(self.path,config)
                        raise
                success=True
                self._update(state='prepared',phase='restart',message='Copies are ready. Restart the application to activate the new database and image cache.',finishedAt=now())
        except BaseException as exc:
            self._update(state='cancelled'if self.cancelled.is_set()else'error',error=str(exc),message=str(exc),finishedAt=now())
        finally:
            # The durable retirement marker now fences all catalog instances.
            # Clearing the transient flag permits another same-store client to
            # cancel a prepared change and resume every instance consistently.
            s.relocation_active.clear()
            if not success:
                for path in staging:shutil.rmtree(path,ignore_errors=True)

    def cancel(self):
        with self.lock:
            worker=self.worker
            if worker and worker.is_alive()and(self.operation or{}).get('state')=='preparing':
                self.cancelled.set()
                if self.process is not None and self.process.poll()is None:self.process.terminate()
                self.operation['message']='Cancelling preparation; original storage will remain active'
                return self.status()
        with _config_lock(self.path):
            config=read_config(self.env,self.home);pending=config.get('pending')
            if pending:
                if Path(pending['sourceDirectory']).resolve()!=self.storage.root.resolve():raise ConflictError('This location change belongs to another data store; cancel it from that client')
                if pending.get('activationStarted'):raise ConflictError('Storage activation has started; finish restarting')
                from maintenance import operation_lock
                with operation_lock(self.storage.root,exclusive=True,blocking=False,filename='.image-download.lock'),operation_lock(self.storage.root,exclusive=True,blocking=False):_restore_original(pending)
                config.pop('pending',None);_atomic_json(self.path,config)
                for folder in pending.get('stagingDirectories',[]):
                    if Path(folder).name.startswith('.love2gathering-relocate-'):shutil.rmtree(folder,ignore_errors=True)
                self.storage.relocation_active.clear()
                self._update(state='cancelled',message='Location change cancelled; original storage remains active',finishedAt=now())
        return self.status()

    def close(self):
        with self.lock:worker=self.worker
        if worker and worker.is_alive():
            self.cancelled.set()
            with self.lock:
                if self.process is not None and self.process.poll()is None:self.process.terminate()
            worker.join(timeout=10)
            with self.lock:
                if self.process is not None and self.process.poll()is None:self.process.kill();self.process.wait(timeout=3)
