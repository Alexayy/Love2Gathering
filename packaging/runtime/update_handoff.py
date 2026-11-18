#!/usr/bin/env python3
"""Deferred whole-package updates, after this supervisor's processes stop.

The catalog downloads but never executes an installer. This helper is copied
outside the installation, rechecks the approved artifact, waits for its exact
parent process, and delegates replacement to the existing platform installer.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time
from datetime import date

APP_ID='io.github.Alexayy.Love2Gathering'
METHODS={'windows-setup','linux-run','deb','rpm','flatpak'}

def document(path,maximum=128*1024):
    path=Path(path)
    if path.is_symlink()or not path.is_file()or path.stat().st_size>maximum:raise ValueError('Invalid update document')
    value=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value,dict):raise ValueError('Invalid update document')
    return value

def atomic_json(path,value):
    path=Path(path);temporary=path.with_name(path.name+'.'+secrets.token_hex(6)+'.tmp')
    try:
        with temporary.open('x',encoding='utf-8')as stream:json.dump(value,stream,indent=2)
        temporary.chmod(0o600);os.replace(temporary,path)
    finally:
        temporary.unlink(missing_ok=True)

def process_identity(pid):
    if os.name=='nt':
        import ctypes
        from ctypes import wintypes
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
        handle=kernel.OpenProcess(0x1000,False,pid)
        if not handle:return None
        try:
            creation,exit_time,kernel_time,user_time=(wintypes.FILETIME()for _ in range(4))
            kernel.GetProcessTimes.argtypes=[wintypes.HANDLE,*([ctypes.POINTER(wintypes.FILETIME)]*4)]
            if not kernel.GetProcessTimes(handle,*map(ctypes.byref,(creation,exit_time,kernel_time,user_time))):return None
            if exit_time.dwHighDateTime or exit_time.dwLowDateTime:return None
            return str((creation.dwHighDateTime<<32)|creation.dwLowDateTime)
        finally:
            kernel.CloseHandle.argtypes=[wintypes.HANDLE];kernel.CloseHandle(handle)
    try:
        fields=Path('/proc',str(pid),'stat').read_text().rsplit(')',1)[1].split()
        return None if fields[0]=='Z'else fields[19]
    except (OSError,IndexError):return None

def installation_method(root,environ=None):
    root=Path(root);env=os.environ if environ is None else environ
    if env.get('FLATPAK_ID')==APP_ID:return'flatpak'
    if os.name=='nt'and(root/'.love2gathering-owned').is_file():return'windows-setup'
    if(root/'.love2gathering-install.json').is_file():
        owned=document(root/'.love2gathering-install.json',16*1024*1024)
        if owned.get('appId')==APP_ID and Path(owned.get('prefix','')).resolve()==root.resolve():return'linux-run'
    info=root/'update-installation.json'
    if info.is_file():
        method=document(info).get('method')
        if method in METHODS:return method
    return None

def create_context(root,session,environ=None):
    root=Path(root).resolve();session=Path(session).resolve()
    if session==root or root in session.parents:raise ValueError('Update staging must be outside application files')
    env=os.environ if environ is None else environ
    release=document(root/'release.json');method=installation_method(root,env)
    if not method or release.get('channel')not in{'stable','development'}:return None
    if release.get('applicationId')!=APP_ID:raise ValueError('This is not a packaged Love2Gathering installation')
    outer=env.get('LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT')
    if method=='flatpak'and outer:
        path=Path(outer).resolve();value=document(path)
        if value.get('externalHost')is not True or value.get('schema')!=1 or value.get('method')!='flatpak'or value.get('root')!=str(root):raise ValueError('Invalid Flatpak host update context')
        if any(value.get(key)!=release.get(key)for key in('version','tag','channel','builtAtUTC'))or value.get('revision')!=release.get('sourceRevision'):raise ValueError('Flatpak host update identity does not match this deployment')
        if not re.fullmatch('[A-Za-z0-9_-]{32,256}',str(value.get('token',''))):raise ValueError('Invalid Flatpak update authorization')
        if value.get('requestPath')!=str(path.parent/'update-request.json')or value.get('workDirectory')!=str(path.parent/'updates')or root in path.parents:raise ValueError('Invalid Flatpak update staging directory')
        return path
    value=dict(schema=1,token=secrets.token_urlsafe(40),root=str(root),method=method,
               channel=release['channel'],version=release['version'],revision=release['sourceRevision'],tag=release['tag'],
               builtAtUTC=release['builtAtUTC'],requestPath=str(session/'update-request.json'),workDirectory=str(session/'updates'))
    path=session/'update-context.json';atomic_json(path,value);return path

def validate_job(context,job,*,rehash=True):
    if context.get('schema')!=1 or job.get('schema')!=1:raise ValueError('Unsupported update request')
    for key in('token','root','method','channel'):
        if not isinstance(job.get(key),str)or job[key]!=context.get(key):raise ValueError('Update request does not belong to this installation')
    if job['method']not in METHODS:raise ValueError('Unsupported installation method')
    if not re.fullmatch('[a-f0-9]{64}',str(job.get('candidateId',''))):raise ValueError('Invalid update candidate')
    version=job.get('version','')
    def parts(value):
        if not isinstance(value,str)or not re.fullmatch(r'\d{4}\.\d{2}\.\d{2}\.[0-9]{1,5}',value):raise ValueError('Invalid update version')
        result=tuple(map(int,value.split('.')));date(*result[:3])
        if not 1<=result[3]<=65535:raise ValueError('Invalid release build number')
        return result
    if parts(version)<=parts(context['version']):raise ValueError('The selected release is not newer than this installation')
    revision=job.get('revision','')
    if not re.fullmatch('[a-f0-9]{40}',revision):raise ValueError('Invalid selected release revision')
    tag=job.get('tag','');pattern='v'+re.escape(version)if context['channel']=='stable'else'DEV-'+re.escape(version)+r'-[1-9][0-9]{0,4}-'+revision[:12]
    if not isinstance(tag,str)or not re.fullmatch(pattern,tag):raise ValueError('Selected release tag does not match its channel/version/revision')
    current=document(Path(context['root'])/'release.json')
    if any(current.get(key)!=context.get(key)for key in('channel','version','tag'))or current.get('sourceRevision')!=context.get('revision'):raise ValueError('This installation changed after the update was prepared; check again')
    suffix={'windows-setup':'windows-x64-setup.exe','linux-run':'linux-x86_64.run','deb':'linux-amd64.deb','rpm':'linux-x86_64.rpm','flatpak':'x86_64.flatpak'}[job['method']]
    installer=Path(job.get('installerPath',''));work_path=Path(context['workDirectory']);work=work_path.resolve()
    if work_path.is_symlink():raise ValueError('Update staging must not redirect through a symbolic link')
    if not installer.is_absolute()or installer.is_symlink()or installer.parent.resolve()!=work or installer.name!='Love2Gathering-'+version+'-'+suffix:raise ValueError('Invalid staged installer path')
    if not re.fullmatch('[a-f0-9]{64}',str(job.get('checksum',''))):raise ValueError('Invalid update checksum')
    size=job.get('expectedSize')
    if type(size)is not int or not 0<size<=8*1024**3 or not installer.is_file()or installer.stat().st_size!=size:raise ValueError('Update installer size changed')
    identity=hashlib.sha256((tag+'\n'+installer.name+'\n'+str(size)+'\n'+job['checksum']).encode()).hexdigest()
    if identity!=job['candidateId']:raise ValueError('Update candidate identity changed')
    if rehash:
        digest=hashlib.sha256()
        with installer.open('rb')as stream:
            for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
        actual=digest.hexdigest()
        if actual!=job['checksum']:raise ValueError('Update installer checksum changed; download it again')
    return installer

def install_command(context,job,*,windows=None,which=shutil.which):
    method=job['method'];root=str(Path(context['root']));installer=str(Path(job['installerPath']))
    windows=os.name=='nt'if windows is None else windows
    if method=='windows-setup':
        if not windows:raise ValueError('This installer requires Windows')
        if any(c in root for c in'\r\n\x00"'):raise ValueError('Invalid Windows installation folder')
        # NSIS requires /D to be the final, unquoted remainder. This is passed
        # directly to CreateProcess, never through cmd.exe or a command shell.
        return subprocess.list2cmdline([installer,'/S'])+' /D='+root
    if method=='linux-run':return[installer,'--prefix',root,'--yes']
    if method in{'deb','rpm'}:
        pkexec=which('pkexec')
        tool=which('apt-get'if method=='deb'else'rpm')
        if not pkexec or not tool:raise ValueError('The system package installer is unavailable; install the downloaded package with your package manager')
        return[pkexec,tool,*(['install','--assume-yes',installer]if method=='deb'else['--upgrade','--prefix',root,'--',installer])]
    if method=='flatpak':
        # A portal-backed system installer owns Flatpak installation/location
        # and any authentication. No host-execution permission is introduced.
        opener=which('xdg-open')or which('gio')
        if not opener:raise ValueError('The desktop file-opening portal is unavailable')
        return[opener,*(['open']if Path(opener).name=='gio'else[]),installer]
    raise ValueError('Unsupported installation method')

def prepare_handoff(context_path,*,spawn=subprocess.Popen):
    context_path=Path(context_path);context=document(context_path)
    request=Path(context['requestPath'])
    if not request.exists():return False
    job=document(request);validate_job(context,job)
    if context.get('externalHost')is True:
        if context.get('method')!='flatpak'or os.environ.get('FLATPAK_ID')!=APP_ID or os.environ.get('LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT')!=str(context_path):raise ValueError('Missing owned Flatpak host coordinator')
        # The outer, installation-aware host launcher waits for the complete
        # Flatpak process, updates its exact original prefix, then restarts it.
        return True
    parent=os.getpid();identity=process_identity(parent)
    if identity is None:raise ValueError('Cannot identify the update supervisor')
    session=context_path.parent;helper=session/'update-helper.py'
    shutil.copyfile(Path(__file__),helper)
    python=sys.executable
    if os.name=='nt':
        source=Path(context['root'])/'runtime/python';target=session/'update-python'
        if source.resolve()!=Path(sys.executable).parent.resolve():raise ValueError('Updater requires the packaged Windows interpreter')
        shutil.copytree(source,target,symlinks=False)
        python=str(target/Path(sys.executable).name)
    plan=dict(context=context,job=job,parentPid=parent,parentIdentity=identity)
    plan_path=session/'update-plan.json';atomic_json(plan_path,plan)
    env=os.environ.copy();env.pop('LOVE2GATHERING_UPDATE_CONTEXT',None);env['PYTHONDONTWRITEBYTECODE']='1'
    log=(session/'update.log').open('ab')
    options={'cwd':str(session),'env':env,'stdin':subprocess.DEVNULL,'stdout':log,'stderr':subprocess.STDOUT}
    if os.name=='nt':options['creationflags']=subprocess.CREATE_NEW_PROCESS_GROUP|subprocess.CREATE_NO_WINDOW
    else:options['start_new_session']=True
    try:spawn([python,str(helper),'--plan',str(plan_path)],**options)
    finally:log.close()
    request.rename(request.with_name('update-request.accepted.json'))
    return True

def apply_plan(plan_path,*,run=subprocess.run,spawn=subprocess.Popen,timeout=120):
    path=Path(plan_path);plan=document(path);context,job=plan['context'],plan['job']
    deadline=time.monotonic()+timeout
    while process_identity(plan['parentPid'])==plan['parentIdentity']:
        if time.monotonic()>=deadline:raise ValueError('Application has not finished closing; update was not installed')
        time.sleep(.1)
    installer=validate_job(context,job)
    if job['method']=='linux-run':installer.chmod(0o700)
    command=install_command(context,job)
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt'else 0
    result=run(command,cwd=str(path.parent),stdin=subprocess.DEVNULL,check=False,creationflags=flags)
    if result.returncode:raise ValueError('Installer did not complete (exit '+str(result.returncode)+'); see update.log')
    if job['method']=='flatpak':
        outcome=dict(state='system_installer_opened',version=job['version'],message='Complete the update in the system installer, then reopen Love2Gathering.')
    else:
        # A successful child process alone is not proof of replacement.
        installed=document(Path(context['root'])/'release.json')
        if installed.get('version')!=job['version']or installed.get('tag')!=job['tag']or installed.get('sourceRevision')!=job['revision']:raise ValueError('Installer exited without installing the selected release')
        outcome=dict(state='installed',version=job['version'])
        executable=Path(context['root'])/('Love2Gathering.exe'if os.name=='nt'else'love2gathering')
        if not executable.is_file():raise ValueError('Updated application launcher is missing')
        spawn([str(executable)],cwd=str(executable.parent),stdin=subprocess.DEVNULL)
    atomic_json(path.parent/'update-result.json',outcome);return outcome

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plan',type=Path,required=True);args=parser.parse_args()
    try:apply_plan(args.plan)
    except Exception as error:
        atomic_json(args.plan.parent/'update-result.json',dict(state='error',message=str(error)))
        print(str(error),file=sys.stderr,flush=True);return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
