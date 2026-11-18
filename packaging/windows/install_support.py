#!/usr/bin/env python3
"""Transactional per-user Windows payload installation/removal; never kills apps.

Run from NSIS's private temporary directory with its staged embedded Python.
The source payload and destination are explicit installer inputs. User storage
is never discovered, migrated or removed by this helper.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
from pathlib import Path,PurePosixPath
import shutil
import sys
import uuid

APP_ID='io.github.Alexayy.Love2Gathering'
OWNER='.love2gathering-install.json'
LEGACY='.love2gathering-owned'
MANIFEST='payload-manifest.json'
APP_KEY=r'Software\Love2Gathering'
UNINSTALL_KEY=r'Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering'
RESERVED={OWNER,LEGACY}
MAX_FILES=50000
MAX_BYTES=8*1024**3


def digest(path):
    value=hashlib.sha256()
    with path.open('rb')as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):value.update(block)
    return value.hexdigest()


def relative(value):
    if not isinstance(value,str)or not value or '\\'in value or any(ord(c)<32 for c in value):raise ValueError('Unsafe manifest path')
    p=PurePosixPath(value)
    if p.is_absolute()or str(p)!=value or any(part in('','..','.')for part in p.parts):raise ValueError('Unsafe manifest path: '+value)
    devices={'CON','PRN','AUX','NUL',*(f'COM{i}'for i in range(1,10)),*(f'LPT{i}'for i in range(1,10))}
    for part in p.parts:
        if any(c in part for c in '<>:"|?*')or part.rstrip(' .')!=part or part.split('.')[0].upper()in devices:raise ValueError('Unsafe Windows manifest path: '+value)
    return Path(*p.parts)


def reparse(path):
    return path.is_symlink()or bool(getattr(path.lstat(),'st_file_attributes',0)&0x400)


def tree(root):
    result={};total=0
    if reparse(root):raise ValueError('The installation cannot be a link or junction')
    for p in sorted(root.rglob('*')):
        if reparse(p):raise ValueError('A link/junction was preserved; update requires an ordinary installation tree: '+str(p))
        if p.is_file():
            name=p.relative_to(root).as_posix();relative(name);total+=p.stat().st_size
            if len(result)>=MAX_FILES or total>MAX_BYTES:raise ValueError('Installation exceeds its bounded file/size limit')
            result[name]=p
        elif not p.is_dir():raise ValueError('Unsupported installed file: '+str(p))
    return result


def read_json(path,limit=16*1024**2):
    if not path.is_file()or reparse(path)or path.stat().st_size>limit:raise ValueError('Missing/invalid installation manifest: '+str(path))
    return json.loads(path.read_text(encoding='utf-8'))


def hashes(value):
    if not isinstance(value,dict)or not value or len(value)>MAX_FILES:raise ValueError('Invalid payload file manifest')
    seen=set()
    for name,checksum in value.items():
        relative(name)
        if name.casefold()in seen or name in RESERVED or not isinstance(checksum,str)or len(checksum)!=64 or any(c not in'0123456789abcdef'for c in checksum):raise ValueError('Invalid or colliding payload entry: '+name)
        seen.add(name.casefold())
    return value


def ownership(prefix):
    if not prefix.exists():return None
    if not prefix.is_dir()or reparse(prefix):raise ValueError('Choose an ordinary dedicated installation directory')
    if not any(prefix.iterdir()):return None
    marker=prefix/LEGACY
    if not marker.is_file()or reparse(marker)or marker.stat().st_size>1024 or not marker.read_text(encoding='utf-8').startswith(APP_ID+' '):raise ValueError('The nonempty destination is not an owned Love2Gathering installation')
    if(prefix/OWNER).exists():
        record=read_json(prefix/OWNER)
        if record.get('schema')!=1 or record.get('appId')!=APP_ID or record.get('prefix','').casefold()!=str(prefix).casefold():raise ValueError('Installation ownership differs from its current path')
        hashes(record.get('files'))
        return record
    # Migrate only a sealed legacy installer payload, including its generated
    # uninstaller. Unknown old files remain untracked and are preserved.
    manifest=read_json(prefix/MANIFEST)
    if manifest.get('version')!=1:raise ValueError('Unsupported legacy payload manifest')
    files=dict(hashes(manifest.get('files')));files[MANIFEST]=digest(prefix/MANIFEST)
    if(prefix/'Uninstall.exe').is_file():files['Uninstall.exe']=digest(prefix/'Uninstall.exe')
    return{'schema':1,'appId':APP_ID,'prefix':str(prefix),'files':files,'integrations':{},'legacy':True}


def validate_source(source):
    manifest=read_json(source/MANIFEST)
    if manifest.get('version')!=1:raise ValueError('Unsupported new payload manifest')
    files=dict(hashes(manifest.get('files')));actual=tree(source)
    for name,expected in files.items():
        if name not in actual or digest(actual[name])!=expected:raise ValueError('New package checksum failed: '+name)
    extras=set(actual)-set(files)-{MANIFEST,'Uninstall.exe'}
    if extras:raise ValueError('Unsealed files in the new payload: '+sorted(extras)[0])
    required=('Love2Gathering.exe','Uninstall.exe','launcher.py','app.love','install_support.py','runtime/python/python.exe','runtime/python/pythonw.exe',
              'runtime/java/bin/java.exe','runtime/love/love.exe','bridge/target/xmage-bridge-1.0.0.jar')
    if any(name not in actual for name in required):raise ValueError('The complete Windows application/runtime payload is required')
    files[MANIFEST]=digest(source/MANIFEST);files['Uninstall.exe']=digest(source/'Uninstall.exe')
    return files


def kernel():
    api=ctypes.WinDLL('kernel32',use_last_error=True)
    api.CloseHandle.argtypes=[ctypes.c_void_p];api.CloseHandle.restype=ctypes.c_int
    return api


@contextmanager
def transaction_lock(prefix):
    api=kernel();api.CreateMutexW.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_wchar_p];api.CreateMutexW.restype=ctypes.c_void_p
    name='Local\\Love2GatheringInstall-'+hashlib.sha256(str(prefix).casefold().encode()).hexdigest()
    handle=api.CreateMutexW(None,False,name)
    if not handle:raise ctypes.WinError(ctypes.get_last_error())
    api.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32];api.WaitForSingleObject.restype=ctypes.c_uint32
    api.ReleaseMutex.argtypes=[ctypes.c_void_p]
    try:
        if api.WaitForSingleObject(handle,0)not in(0,0x80):raise ValueError('Another install or uninstall is already in progress')
        try:yield
        finally:api.ReleaseMutex(handle)
    finally:api.CloseHandle(handle)


def active_processes(prefix):
    from ctypes import wintypes as w
    class Entry(ctypes.Structure):
        _fields_=[('dwSize',w.DWORD),('cntUsage',w.DWORD),('th32ProcessID',w.DWORD),('th32DefaultHeapID',ctypes.c_size_t),('th32ModuleID',w.DWORD),('cntThreads',w.DWORD),('th32ParentProcessID',w.DWORD),('pcPriClassBase',w.LONG),('dwFlags',w.DWORD),('szExeFile',w.WCHAR*260)]
    api=kernel();api.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD];api.CreateToolhelp32Snapshot.restype=ctypes.c_void_p
    api.Process32FirstW.argtypes=[ctypes.c_void_p,ctypes.POINTER(Entry)];api.Process32NextW.argtypes=api.Process32FirstW.argtypes
    api.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];api.OpenProcess.restype=ctypes.c_void_p
    api.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,w.DWORD,w.LPWSTR,ctypes.POINTER(w.DWORD)]
    snapshot=api.CreateToolhelp32Snapshot(2,0)
    if snapshot==ctypes.c_void_p(-1).value:raise ctypes.WinError(ctypes.get_last_error())
    found=[];entry=Entry();entry.dwSize=ctypes.sizeof(entry);root=str(prefix).casefold().rstrip('\\')+'\\'
    try:
        present=api.Process32FirstW(snapshot,ctypes.byref(entry))
        while present:
            process=api.OpenProcess(0x1000,False,entry.th32ProcessID)
            if process:
                try:
                    buffer=ctypes.create_unicode_buffer(32768);size=w.DWORD(len(buffer))
                    if api.QueryFullProcessImageNameW(process,0,buffer,ctypes.byref(size)):
                        image=buffer.value.casefold()
                        if image.startswith(root)and Path(image).name!='uninstall.exe':found.append((entry.th32ProcessID,Path(image).name))
                finally:api.CloseHandle(process)
            present=api.Process32NextW(snapshot,ctypes.byref(entry))
    finally:api.CloseHandle(snapshot)
    return found


def inactive(prefix,files):
    processes=active_processes(prefix)
    if processes:raise ValueError('Close Love: 2 Gathering and its installed runtimes before continuing: '+', '.join(name+' (PID '+str(pid)+')'for pid,name in processes))
    api=kernel();api.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p];api.CreateFileW.restype=ctypes.c_void_p
    for name,path in files.items():
        if name=='Uninstall.exe':continue
        handle=api.CreateFileW(str(path),0x80010000,0,None,3,0,None)
        if handle==ctypes.c_void_p(-1).value:raise ValueError('An installed file is in use or cannot be replaced; no files were changed: '+name)
        api.CloseHandle(handle)


def shell_folder(number):
    buffer=ctypes.create_unicode_buffer(32768)
    if ctypes.WinDLL('shell32').SHGetFolderPathW(None,number,None,0,buffer):raise ValueError('Could not locate the current user’s Windows shortcuts')
    return Path(buffer.value)


def integration_paths():
    menu=shell_folder(2)/'Love2Gathering'
    return{'application':menu/'Love2Gathering.lnk','uninstall':menu/'Uninstall.lnk','desktop':shell_folder(0x10)/'Love2Gathering.lnk'}


def registry_values(path):
    import winreg as reg
    try:
        with reg.OpenKey(reg.HKEY_CURRENT_USER,path)as key:
            values={};index=0
            while True:
                try:name,value,kind=reg.EnumValue(key,index)
                except OSError:break
                values[name]=(value,kind);index+=1
            return values
    except FileNotFoundError:return None


def registry_restore(path,values):
    import winreg as reg
    with reg.CreateKey(reg.HKEY_CURRENT_USER,path)as key:
        names=[];index=0
        while True:
            try:names.append(reg.EnumValue(key,index)[0]);index+=1
            except OSError:break
        for name in names:reg.DeleteValue(key,name)
        for name,(value,kind)in(values or{}).items():reg.SetValueEx(key,name,0,kind,value)
    if values is None:
        try:reg.DeleteKey(reg.HKEY_CURRENT_USER,path)
        except OSError:pass  # Unknown subkeys are never recursively erased.


def integration_snapshot():
    paths=integration_paths();files={}
    for name,path in paths.items():
        if path.exists():
            if reparse(path)or not path.is_file()or path.stat().st_size>1024*1024:raise ValueError('An unrelated shortcut was preserved: '+str(path))
            files[name]=path.read_bytes()
        else:files[name]=None
    return{'paths':paths,'files':files,'registry':{key:registry_values(key)for key in(APP_KEY,UNINSTALL_KEY)}}


def atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True);temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex)
    try:temporary.write_bytes(data);os.replace(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()


def restore_integrations(snapshot):
    for name,path in snapshot['paths'].items():
        previous=snapshot['files'][name]
        if previous is None:
            if path.exists():path.unlink()
        else:atomic(path,previous)
    for key,values in snapshot['registry'].items():registry_restore(key,values)


def legacy_link_matches(data,prefix,name):
    if not prefix:return False
    target=str(Path(prefix)/('Uninstall.exe'if name=='uninstall'else'Love2Gathering.exe')).casefold()
    return target.encode('utf-16-le')in data.lower()or target.encode('utf-8')in data.lower()


def register(prefix,version,links,desktop,previous,snapshot):
    import winreg as reg
    installed={};old_reg=(snapshot['registry'][APP_KEY]or{}).get('InstallDir',('',0))[0]
    expected=(previous or{}).get('integrations',{})
    for name,path in snapshot['paths'].items():
        if name=='desktop'and not desktop:continue
        before=snapshot['files'][name]
        if before is not None and hashlib.sha256(before).hexdigest()!=expected.get(name)and previous and not previous.get('legacy',False):raise ValueError('A modified shortcut was preserved: '+str(path))
        if before is not None and not expected.get(name)and not legacy_link_matches(before,old_reg,name):raise ValueError('An unrelated shortcut was preserved: '+str(path))
        source=links/(name+'.lnk')
        if not source.is_file()or reparse(source)or source.stat().st_size>1024*1024:raise ValueError('Staged Windows shortcut is missing: '+name)
        atomic(path,source.read_bytes());installed[name]=digest(path)
    if not desktop and previous and expected.get('desktop')and snapshot['files']['desktop']is not None:
        # Retain an existing explicitly chosen desktop shortcut across updates.
        installed['desktop']=expected['desktop']
    with reg.CreateKey(reg.HKEY_CURRENT_USER,APP_KEY)as key:reg.SetValueEx(key,'InstallDir',0,reg.REG_SZ,str(prefix))
    values={'DisplayName':'Love: 2 Gathering','DisplayVersion':version,'InstallLocation':str(prefix),'UninstallString':'"'+str(prefix/'Uninstall.exe')+'"',
            'QuietUninstallString':'"'+str(prefix/'Uninstall.exe')+'" /S','DisplayIcon':str(prefix/'Love2Gathering.exe'),'NoModify':1,'NoRepair':1}
    with reg.CreateKey(reg.HKEY_CURRENT_USER,UNINSTALL_KEY)as key:
        for name,value in values.items():reg.SetValueEx(key,name,0,reg.REG_DWORD if isinstance(value,int)else reg.REG_SZ,value)
    return installed


def unregister(prefix,record,snapshot):
    configured=(snapshot['registry'][APP_KEY]or{}).get('InstallDir',('',0))[0]
    if configured.casefold()!=str(prefix).casefold():return
    for name,path in snapshot['paths'].items():
        content=snapshot['files'][name]
        if content is not None and(hashlib.sha256(content).hexdigest()==record.get('integrations',{}).get(name)or record.get('legacy')and legacy_link_matches(content,configured,name)):path.unlink()
    registry_restore(UNINSTALL_KEY,None)
    app=dict(snapshot['registry'][APP_KEY]or{});app.pop('InstallDir',None);registry_restore(APP_KEY,app or None)


def copy_checked(source,target):
    target.parent.mkdir(parents=True,exist_ok=True);before=digest(source);shutil.copy2(source,target)
    if digest(target)!=before or digest(source)!=before:raise ValueError('A file changed while staging; original installation retained: '+str(source))


def install(prefix,source,version,links,desktop):
    files=validate_source(source);previous=ownership(prefix);old=tree(prefix)if prefix.exists()else{}
    inactive(prefix,old);snapshot=integration_snapshot()
    if previous:
        for name,expected in previous['files'].items():
            if name in old and digest(old[name])!=expected:raise ValueError('A modified installed file was preserved; restore or move it before updating: '+name)
    token=uuid.uuid4().hex;stage=prefix.with_name('.'+prefix.name+'.install-'+token);backup=prefix.with_name('.'+prefix.name+'.backup-'+token)
    stage.mkdir();moved=False;published=False
    try:
        for name,path in tree(source).items():copy_checked(path,stage/relative(name))
        tracked=set((previous or{}).get('files',{}))|RESERVED
        for name,path in old.items():
            if name in tracked:continue
            if name in files or name.casefold()in{key.casefold()for key in files}:raise ValueError('An untracked file conflicts with the new package and was preserved: '+name)
            copy_checked(path,stage/relative(name))
        record={'schema':1,'appId':APP_ID,'prefix':str(prefix),'version':version,'files':files,'integrations':{}}
        atomic(stage/LEGACY,(APP_ID+' '+version+'\r\n').encode());atomic(stage/OWNER,(json.dumps(record,indent=2)+'\n').encode())
        if prefix.exists():os.replace(prefix,backup);moved=True
        os.replace(stage,prefix);published=True
        record['integrations']=register(prefix,version,links,desktop,previous,snapshot)
        atomic(prefix/OWNER,(json.dumps(record,indent=2)+'\n').encode())
    except BaseException as failure:
        try:restore_integrations(snapshot)
        except BaseException as exc:failure.add_note('Shortcut/registry restoration also failed: '+str(exc))
        finally:
            if published:shutil.rmtree(prefix)
            if moved:os.replace(backup,prefix)
        raise
    finally:
        if stage.exists():shutil.rmtree(stage)
    warning=None
    if moved:
        try:shutil.rmtree(backup)
        except OSError:warning='The complete new version is installed; an old backup remains at '+str(backup)
    return{'installed':True,'preservedUntrackedFiles':len(set(old)-tracked),'cleanupWarning':warning}


def uninstall(prefix):
    record=ownership(prefix)
    if not record:raise ValueError('No owned installation was found; registration was retained')
    old=tree(prefix);inactive(prefix,old);snapshot=integration_snapshot()
    keep={name:path for name,path in old.items()if name not in RESERVED and(name not in record['files']or digest(path)!=record['files'][name])}
    token=uuid.uuid4().hex;stage=prefix.with_name('.'+prefix.name+'.preserved-'+token);backup=prefix.with_name('.'+prefix.name+'.remove-'+token)
    stage.mkdir();moved=False;published=False
    try:
        for name,path in keep.items():copy_checked(path,stage/relative(name))
        os.replace(prefix,backup);moved=True
        if keep:os.replace(stage,prefix);published=True
        unregister(prefix,record,snapshot)
    except BaseException as failure:
        try:restore_integrations(snapshot)
        except BaseException as exc:failure.add_note('Shortcut/registry restoration also failed: '+str(exc))
        finally:
            if published:shutil.rmtree(prefix)
            if moved:os.replace(backup,prefix)
        raise
    finally:
        if stage.exists():shutil.rmtree(stage)
    warning=None
    try:shutil.rmtree(backup)
    except OSError:warning='Application removed; closed-runtime files remain in '+str(backup)
    return{'uninstalled':True,'preservedFiles':len(keep),'cleanupWarning':warning}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('install','uninstall'));p.add_argument('--prefix',type=Path,required=True)
    p.add_argument('--source',type=Path);p.add_argument('--links',type=Path);p.add_argument('--version');p.add_argument('--desktop-shortcut',action='store_true');p.add_argument('--result',type=Path,required=True)
    args=p.parse_args(argv);result={'passed':False,'action':args.action};code=2
    try:
        if os.name!='nt':raise ValueError('This helper requires Windows')
        raw=args.prefix
        if not raw.is_absolute()or raw==Path(raw.anchor)or any(ord(c)<32 for c in str(raw)):raise ValueError('Choose a dedicated absolute installation directory')
        prefix=raw.parent.resolve()/raw.name
        if prefix in{Path.home().resolve(),Path(os.environ['WINDIR']).resolve(),Path(os.environ.get('LOCALAPPDATA',str(Path.home()))).resolve()}:raise ValueError('Choose a dedicated application folder')
        prefix.parent.mkdir(parents=True,exist_ok=True)
        with transaction_lock(prefix):
            if args.action=='install':
                if not(args.source and args.links and args.version):raise ValueError('Complete staged package/shortcut/version inputs are required')
                if args.source.resolve()==prefix:raise ValueError('The updater must run from a separate staged payload')
                result.update(install(prefix,args.source.resolve(),args.version,args.links.resolve(),args.desktop_shortcut))
            else:result.update(uninstall(prefix))
        result['passed']=True;code=0
    except BaseException as exc:result['error']=str(exc)
    args.result.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    args.result.with_suffix('.txt').write_text(str(result.get('error')or result.get('cleanupWarning')or'Completed'),encoding='ascii',errors='replace')
    return code


if __name__=='__main__':raise SystemExit(main())
