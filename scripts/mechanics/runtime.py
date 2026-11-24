"""Owned subprocesses and diagnostic budgets; never decides a Magic outcome."""
from __future__ import annotations

import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import socket
import subprocess
import time
import threading
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
PIN = '2a96b0ac129dfd77946eaad536184d3b35fb5e64'
# The runner owns signal policy; worker watchdogs observe this shared fence.
RUN_CANCELLED = threading.Event()


def write_json(path, value):
    path = Path(path);path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix+'.pending')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')
    temporary.replace(path)


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024*1024), b''): result.update(block)
    return result.hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def engine_manifest():
    entries = []
    for directory, dirs, files in os.walk(ROOT/'engine', followlinks=False):
        dirs.sort();files.sort()
        for name in dirs+files:
            path=Path(directory)/name;stat=path.lstat()
            entry={'path':str(path.relative_to(ROOT/'engine')), 'mode':stat.st_mode}
            if path.is_symlink(): entry['link']=os.readlink(path)
            elif path.is_file(): entry.update(size=stat.st_size, sha256=sha(path))
            entries.append(entry)
    return entries


def baseline(directory):
    result={'sourceRevision':git('rev-parse','HEAD'),
            'dirty':git('status','--porcelain=v1','--untracked-files=all'),
            'engineGitlink':git('rev-parse','HEAD:engine/mage'),
            'indexGitlink':git('rev-parse',':engine/mage'),
            'gitmodulesSha256':sha(ROOT/'.gitmodules'),
            'engineDirty':git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all'),
            'engineDiff':git('-C','engine/mage','diff','--binary'),
            'engineCachedDiff':git('-C','engine/mage','diff','--cached','--binary'),
            'startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    write_json(directory/'baseline.json',result)
    write_json(directory/'engine-before.json',engine_manifest())
    return result


def verify_engine(directory):
    before=json.loads((directory/'baseline.json').read_text())
    after=engine_manifest();old=json.loads((directory/'engine-before.json').read_text())
    checks={'contentAndModes':old==after,
            'headGitlink':before['engineGitlink']==git('rev-parse','HEAD:engine/mage'),
            'indexGitlink':before['indexGitlink']==git('rev-parse',':engine/mage'),
            'gitmodules':before['gitmodulesSha256']==sha(ROOT/'.gitmodules'),
            'existingDirty':before['engineDirty']==git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all'),
            'existingDiff':before['engineDiff']==git('-C','engine/mage','diff','--binary'),
            'existingCachedDiff':before['engineCachedDiff']==git('-C','engine/mage','diff','--cached','--binary')}
    result={'passed':all(checks.values()), 'checks':checks,'entries':len(after),
            'beforeSha256':sha(directory/'engine-before.json')}
    write_json(directory/'engine-verification.json',result)
    return result


def isolated_env(directory, extra=None):
    directory=Path(directory).resolve()
    if not str(directory).startswith('/tmp/love2gathering-mechanics-'):
        raise ValueError('Mechanics storage must be inside its owned /tmp run')
    values={'LOVE2GATHERING_DATA_DIR':str(directory/'data'),
            'LOVE2GATHERING_CACHE_DIR':str(directory/'cache'),
            'LOVE2GATHERING_CONFIG_DIR':str(directory/'config'),
            'XDG_DATA_HOME':str(directory/'xdg/data'),
            'XDG_CONFIG_HOME':str(directory/'xdg/config'),
            'XDG_CACHE_HOME':str(directory/'xdg/cache'),
            'LOVE2GATHERING_STORAGE_RESOLVED':'',
            'LOVE2GATHERING_DATA_DIR_EXPLICIT':'1',
            'LOVE2GATHERING_CACHE_DIR_EXPLICIT':'1',
            'HOME':str(directory/'home'),
            'PYTHONDONTWRITEBYTECODE':'1'}
    for key,value in values.items():
        if key.endswith('_DIR') or key.startswith('XDG_') or key=='HOME':Path(value).mkdir(parents=True,exist_ok=True)
    # HOME is passed only to owned children; the caller's HOME is never changed.
    env=dict(os.environ);env.update(values);env.update(extra or {})
    return env


def proc_identity(pid):
    try:
        text=Path(f'/proc/{pid}/stat').read_text();fields=text[text.rfind(')')+2:].split()
        return {'pid':pid,'birthTicks':int(fields[19]),'state':fields[0],
                'ppid':int(fields[1]),'processGroup':int(fields[2]),
                'cpuTicks':int(fields[11])+int(fields[12]),'rssBytes':int(fields[21])*os.sysconf('SC_PAGE_SIZE'),
                'threads':int(fields[17])}
    except (OSError,ValueError,IndexError): return None


class OwnedProcess:
    def __init__(self, command, directory, *, env=None):
        self.directory=Path(directory);self.directory.mkdir(parents=True,exist_ok=True)
        self.log=(self.directory/'process.log').open('wb')
        self.started=time.monotonic()
        self.owner_token=uuid.uuid4().hex;self.members={}
        child_env=dict(env or isolated_env(self.directory))
        ancestors=child_env.get('LOVE2GATHERING_TEST_ANCESTORS','').split(',')
        if child_env.get('LOVE2GATHERING_TEST_OWNER'):ancestors.append(child_env['LOVE2GATHERING_TEST_OWNER'])
        child_env['LOVE2GATHERING_TEST_ANCESTORS']=','.join(filter(None,ancestors))
        child_env['LOVE2GATHERING_TEST_OWNER']=self.owner_token
        try:
            self.process=subprocess.Popen(command,cwd=self.directory,env=child_env,
                                          stdout=self.log,stderr=subprocess.STDOUT,start_new_session=True)
        except BaseException:
            self.log.close();raise
        self.identity=proc_identity(self.process.pid)
        if self.identity is None:self.identity={'pid':self.process.pid,'birthTicks':None}
        self.members[self.process.pid]=self.identity
        write_json(self.directory/'process.json',{'command':command,'identity':self.identity,
                   'cwd':str(self.directory),'owner':'mechanics runner','createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat()})

    def alive_members(self,scan=False):
        # The random marker survives ordinary exec, new sessions and reparenting.
        # Remembered birth ticks still protect a discovered child after exec
        # removes its marker; no process is selected by a name or a port.
        if scan:
            marker=('LOVE2GATHERING_TEST_OWNER='+self.owner_token).encode()
            for path in Path('/proc').iterdir():
                if not path.name.isdigit():continue
                try:
                    if path.stat().st_uid!=os.geteuid():continue
                    environment=(path/'environ').read_bytes().split(b'\0')
                    inherited=next((entry.split(b'=',1)[1]for entry in environment if entry.startswith(b'LOVE2GATHERING_TEST_ANCESTORS=')),b'').split(b',')
                    if marker not in environment and self.owner_token.encode()not in inherited:continue
                    current=proc_identity(int(path.name))
                    if current:self.members[current['pid']]=current
                except OSError:continue
        live=[]
        for pid,identity in list(self.members.items()):
            current=proc_identity(pid)
            if current and current['birthTicks']==identity['birthTicks']and current['state']!='Z':live.append(current)
        return live

    def owns(self):return bool(self.alive_members(scan=True))

    @staticmethod
    def _signal_identity(identity,sig):
        descriptor=None
        try:
            if hasattr(os,'pidfd_open')and hasattr(signal,'pidfd_send_signal'):
                descriptor=os.pidfd_open(identity['pid'])
            current=proc_identity(identity['pid'])
            if not current or current['birthTicks']!=identity['birthTicks']:return False
            if descriptor is not None:signal.pidfd_send_signal(descriptor,sig)
            else:os.kill(identity['pid'],sig)
            return True
        except ProcessLookupError:return False
        finally:
            if descriptor is not None:os.close(descriptor)

    def send(self,sig):
        sent=False
        for identity in self.alive_members(scan=True):sent=self._signal_identity(identity,sig)or sent
        return sent

    def stop(self):
        try:
            if self.alive_members(scan=True):
                self.send(signal.SIGTERM)
                deadline=time.monotonic()+2
                while self.alive_members(scan=True)and time.monotonic()<deadline:time.sleep(.05)
                deadline=time.monotonic()+3
                while self.alive_members(scan=True)and time.monotonic()<deadline:
                    self.send(signal.SIGKILL);time.sleep(.05)
                if self.alive_members(scan=True):raise RuntimeError('Owned descendants survived scoped SIGKILL')
            try:self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:raise RuntimeError('Owned parent did not terminate after scoped kill')
        finally:
            if not self.log.closed:self.log.close()

    def diagnostics(self,jcmd=None):
        dumps=[]
        if jcmd and self.owns():
            for index in range(3):
                path=self.directory/f'threads-{index}.txt'
                try:
                    with path.open('wb')as out:
                        subprocess.run([str(jcmd),str(self.process.pid),'Thread.print','-l'],stdout=out,stderr=subprocess.STDOUT,timeout=3)
                    dumps.append(str(path))
                except(OSError,subprocess.TimeoutExpired):pass
                time.sleep(.2)
            for command in('GC.heap_info','VM.flags'):
                try:
                    with(self.directory/(command+'.txt')).open('wb')as out:
                        subprocess.run([str(jcmd),str(self.process.pid),command],stdout=out,stderr=subprocess.STDOUT,timeout=3)
                except(OSError,subprocess.TimeoutExpired):pass
        write_json(self.directory/'diagnostic-process.json',proc_identity(self.process.pid))
        return dumps

    @staticmethod
    def _disk_size(roots):
        # Files can disappear while a WAL rotates or the client cleans a frame.
        # Overlapping roots/hard links must not double charge the same inode.
        seen=set();total=0
        for root in roots:
            root=Path(root)
            paths=[root]if root.is_file()else root.rglob('*')
            for path in paths:
                try:
                    info=path.lstat();identity=(info.st_dev,info.st_ino)
                    if path.is_symlink()or not path.is_file()or identity in seen:continue
                    seen.add(identity);total+=info.st_size
                except OSError:continue
        return total

    def wait(self,budgets,*,jcmd=None,recover=None):
        samples=[];peak=0;reason=None;disk=0;shared_disk=0;last_disk_check=-float('inf');last_member_check=-float('inf');cpu=0
        cpu_starts={};cpu_max={};external=budgets.get('externalOwnedPids',[])
        for identity in external:
            current=proc_identity(identity['pid'])
            if current and current['birthTicks']==identity['birthTicks']:
                cpu_starts[(current['pid'],current['birthTicks'])]=current['cpuTicks']
        def measure(final=False):
            nonlocal peak,disk,shared_disk,last_disk_check,last_member_check,cpu
            if RUN_CANCELLED.is_set():return'runner_cancelled'
            elapsed=time.monotonic()-self.started
            scan=final or elapsed-last_member_check>.5
            members=self.alive_members(scan=scan)
            if scan:last_member_check=elapsed
            for identity in external:
                current=proc_identity(identity['pid'])
                if current and current['birthTicks']==identity['birthTicks']and current['state']!='Z':members.append(current)
            unique={(m['pid'],m['birthTicks']):m for m in members}
            for key,member in unique.items():cpu_max[key]=max(cpu_max.get(key,0),member['cpuTicks']-cpu_starts.get(key,0))
            cpu=sum(cpu_max.values())/os.sysconf('SC_CLK_TCK');rss=sum(m['rssBytes']for m in unique.values());peak=max(peak,rss)
            sample=proc_identity(self.process.pid)or{}
            sample.update({'elapsedSeconds':round(elapsed,3),'treeRssBytes':rss,'treeCpuSeconds':cpu,'members':list(unique.values())});samples.append(sample)
            if final or elapsed-last_disk_check>.5:
                disk=self._disk_size([self.directory,*budgets.get('diskDirectories',[])])
                shared_disk=self._disk_size(budgets.get('sharedDiskDirectories',[]));last_disk_check=elapsed
            if elapsed>budgets.get('wallSeconds',45):return'wall_time'
            if peak>budgets.get('rssBytes',2300*1024*1024):return'rss'
            if cpu>budgets.get('cpuSeconds',120):return'cpu_time'
            if disk>budgets.get('diskBytes',256*1024*1024):return'disk_bytes'
            if shared_disk>budgets.get('sharedDiskBytes',8*1024*1024*1024):return'shared_service_disk_bytes'
            if self.log.tell()>budgets.get('logBytes',32*1024*1024):return'log_bytes'
            return None
        try:
            while self.process.poll()is None:
                reason=measure()
                if reason:break
                time.sleep(.05)
            if not reason:reason=measure(final=True)
            if not reason and self.alive_members(scan=True):reason='descendants_survived_parent'
            dumps=self.diagnostics(jcmd)if reason else[]
            recovery=recover()if reason and recover else None
            if reason:self.stop()
            else:self.process.wait();self.log.close()
            write_json(self.directory/'resource-samples.json',samples)
            return {'exitCode':self.process.returncode,'wallSeconds':round(time.monotonic()-self.started,3),
                    'peakRssBytes':peak,'status':'budget_exceeded'if reason else'pass'if self.process.returncode==0 else'fail',
                    'cpuSeconds':round(cpu,3),'diskBytes':disk,'sharedServiceDiskBytes':shared_disk,
                    'watchdogReason':reason,'threadDumps':dumps,'recovery':recovery,
                    'ownedProcessTerminated':not self.alive_members(scan=True),'ownedProcessIdentities':list(self.members.values()),'log':str(self.directory/'process.log')}
        finally:
            if self.alive_members(scan=True):self.stop()
            elif not self.log.closed:self.log.close()


def java_tools():
    candidates=[Path(os.environ['JAVA_HOME'])]if os.environ.get('JAVA_HOME')else []
    candidates+=sorted((ROOT/'.tools').glob('jdk-*'))
    for candidate in candidates:
        if(candidate/'bin/javac').is_file():return {name:candidate/'bin'/name for name in ('java','javac','jar','jcmd')}
    import shutil
    return {name:Path(shutil.which(name)or name)for name in ('java','javac','jar','jcmd')}


def build_bridge(directory):
    directory=Path(directory)
    if directory.exists()and any(directory.iterdir()):raise ValueError('Refusing to overwrite a prior bridge payload; use a fresh build directory')
    directory.mkdir(parents=True,exist_ok=True)
    classes=directory/'classes';classes.mkdir(exist_ok=True);tools=java_tools()
    libraries=sorted((ROOT/'bridge/target/lib').glob('*.jar'))
    if not libraries:raise RuntimeError('Pinned runtime dependencies missing; engine/ is read-only')
    sources=sorted((ROOT/'bridge/src').rglob('*.java'));cp=str(ROOT/'bridge/target/lib/*')
    with(directory/'compile.log').open('wb')as log:
        subprocess.run([str(tools['javac']),'--release','21','-encoding','UTF-8','-cp',cp,'-d',str(classes),*map(str,sources)],stdout=log,stderr=subprocess.STDOUT,check=True)
    jar=directory/'xmage-bridge.jar'
    subprocess.run([str(tools['jar']),'--create','--file',str(jar),'-C',str(classes),'.'],check=True)
    result={'jar':str(jar),'jarSha256':sha(jar),'classpath':str(jar)+os.pathsep+cp,
            'sources':{str(p.relative_to(ROOT)):sha(p)for p in sources},
            'dependencies':{p.name:sha(p)for p in libraries},'enginePin':git('-C','engine/mage','rev-parse','HEAD'),
            'parentEnginePin':git('rev-parse','HEAD:engine/mage'),
            'indexEnginePin':git('rev-parse',':engine/mage'),
            'kind':'bridge-only javac/jar; original engine and targets read-only'}
    write_json(directory/'build.json',result);return result


def machine():
    return {'platform':platform.platform(),'python':platform.python_version(),
            'cpuCount':os.cpu_count(),'memoryBytes':os.sysconf('SC_PAGE_SIZE')*os.sysconf('SC_PHYS_PAGES'),
            'clockTicks':os.sysconf('SC_CLK_TCK')}


def http_json(url,body=None,timeout=10):
    request=urllib.request.Request(url,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=timeout)as response:return json.load(response)


def probe_projection(path):
    """Loopback transport of an actual frame; not a production game endpoint."""
    from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
    data=Path(path).read_bytes();times=[];decode=[]
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        for _ in range(5):
            started=time.perf_counter()
            with urllib.request.urlopen(f'http://127.0.0.1:{server.server_port}/state',timeout=3)as response:body=response.read()
            times.append((time.perf_counter()-started)*1000);started=time.perf_counter();frame=json.loads(body);decode.append((time.perf_counter()-started)*1000)
            if body!=data:raise AssertionError('Native frame changed in transport')
    finally:server.shutdown();server.server_close();thread.join(timeout=2)
    return {'evidenceType':'native_projection_transport_fixture','requests':5,'bodyBytes':len(data),
            'httpRoundTripMs':times,'pythonDecodeMs':decode,'frameSha256':sha(path),
            'objectCount':sum(len(p.get('battlefield',[]))for p in frame.get('players',[])),'ownedServerStopped':not thread.is_alive()}


def free_port():
    with socket.socket()as listener:
        listener.bind(('127.0.0.1',0));return listener.getsockname()[1]


def owns_listener(identity,port):
    current=proc_identity(identity['pid'])
    if not current or current['birthTicks']!=identity['birthTicks']:return False
    sockets=set();root=Path('/proc')/str(identity['pid'])
    try:
        for descriptor in(root/'fd').iterdir():
            try:
                link=os.readlink(descriptor)
                if link.startswith('socket:['):sockets.add(link[8:-1])
            except OSError:pass
        for name in('tcp','tcp6'):
            for line in(root/'net'/name).read_text().splitlines()[1:]:
                fields=line.split()
                if len(fields)>9 and fields[3]=='0A'and int(fields[1].split(':')[1],16)==port and fields[9]in sockets:return True
    except OSError:return False
    return False


class Services:
    """Direct owned services: bypass every launcher/storage-activation path."""
    def __init__(self,directory,metadata,build=None):
        self.directory=Path(directory);self.metadata=Path(metadata);self.build=build;self.processes={};self.ports={}

    def launch(self,name,command,env,port,health='/health'):
        process=OwnedProcess(command,self.directory/name,env=env);self.processes[name]=process;self.ports[name]=port
        deadline=time.monotonic()+45;last=None
        while time.monotonic()<deadline:
            if process.process.poll()is not None:raise RuntimeError(name+' failed; inspect '+str(process.directory/'process.log'))
            if not owns_listener(process.identity,port):time.sleep(.05);continue
            try:
                value=http_json(f'http://127.0.0.1:{port}'+health,timeout=1)
                if name=='catalog':
                    actual=value.get('storage',{})
                    if actual.get('dataDirectory')!=env['LOVE2GATHERING_DATA_DIR']or actual.get('cacheDirectory')!=env['LOVE2GATHERING_CACHE_DIR']:
                        raise ValueError('Owned catalog storage identity does not match test directories')
                if name!='catalog'or value.get('ready'):return value
            except Exception as ex:last=ex
            time.sleep(.08)
        raise RuntimeError(name+' readiness timed out: '+str(last))

    def start(self,*,engine=True,gateway=True):
        try:return self._start(engine=engine,gateway=gateway)
        except BaseException as failure:
            try:self.close()
            except Exception as cleanup:failure.add_note('Owned service cleanup also failed: '+str(cleanup))
            raise

    def _start(self,*,engine=True,gateway=True):
        import secrets,sys
        cat=self.directory/'catalog';port=free_port();env=isolated_env(cat)
        self.launch('catalog',[sys.executable,str(ROOT/'service/server.py'),'--port',str(port),'--source',str(self.metadata),'--database',str(cat/'catalog.sqlite'),'--data-dir',env['LOVE2GATHERING_DATA_DIR']],env,port)
        if engine:
            if not self.build:raise ValueError('Fresh isolated bridge build required')
            work=self.directory/'engine';engine_port=free_port();token=secrets.token_urlsafe(40)
            env=isolated_env(work,{'LOVE2GATHERING_CATALOG_PORT':str(port),'LOVE2GATHERING_COORDINATOR_TOKEN':token})
            java=java_tools()['java']
            self.launch('engine',[str(java),'-XX:ActiveProcessorCount=2','-Xms128m','-Xmx1024m','-Djava.awt.headless=true','-Duser.home='+env['HOME'],'-Dlove2gathering.root='+str(ROOT),'-cp',self.build['classpath'],'love2gathering.EngineBridge',str(engine_port)],env,engine_port)
            if gateway:
                room=self.directory/'gateway';room_port=free_port();room_env=isolated_env(room,{'LOVE2GATHERING_COORDINATOR_TOKEN':token})
                self.launch('gateway',[sys.executable,str(ROOT/'service/rooms.py'),'--bind','127.0.0.1','--port',str(room_port),'--engine-port',str(engine_port),'--catalog-port',str(port),'--public-url',f'http://127.0.0.1:{room_port}'],room_env,room_port)
        write_json(self.directory/'services.json',{'ports':self.ports,'processes':{name:p.identity for name,p in self.processes.items()},'dataDirectory':str(cat/'data'),'cacheDirectory':str(cat/'cache'),'source':str(self.metadata),'secrets':'memory only; not recorded'})
        return self

    def close(self):
        result={};errors=[]
        for name,process in reversed(list(self.processes.items())):
            error=None
            try:process.stop()
            except Exception as ex:error=str(ex);errors.append(name+': '+error)
            result[name]={'terminated':not process.owns(),'identity':process.identity,'error':error}
        write_json(self.directory/'cleanup.json',result)
        if errors:raise RuntimeError('Owned service cleanup incomplete: '+'; '.join(errors))


def new_run():
    identifier=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
    path=Path('/tmp')/('love2gathering-mechanics-'+identifier);path.mkdir(mode=0o700)
    return path
