#!/usr/bin/env python3
"""Actual NSIS/Win32 transactions in a fresh owned Wine prefix.

Fixtures contain the real pinned embedded Python and labeled small component
files. This establishes replacement/rollback/registration, not Windows gameplay.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import time
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',type=Path);p.add_argument('--report',type=Path,default=HERE/'transaction-test-report.json');a=p.parse_args()
    work=a.work.resolve()if a.work else ROOT/'.runtime'/('windows-transaction-'+uuid.uuid4().hex[:10])
    if not work.is_relative_to(ROOT/'.runtime')or work.exists():p.error('Use a fresh explicit directory under this checkout .runtime')
    work.mkdir(parents=True);prefix=work/'wine';target=work/'Chosen Game Folder';checks=[];failure=None
    python_lock=json.loads((HERE/'runtimes.lock.json').read_text())['python']
    python_archive=ROOT/'.tools/packaging-platform/downloads'/python_lock['filename']
    env=dict(os.environ,WINEPREFIX=str(prefix),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
    tool=ROOT/'.tools/packaging-platform/nsis/usr/bin/makensis';nsisenv=dict(os.environ,NSISDIR=str(tool.parent.parent/'share/nsis'))
    def win(path):return'Z:'+str(path).replace('/','\\')
    def check(value,label):
        assert value,label;checks.append(label);print('WINDOWS TRANSACTION PASS '+label,flush=True)
    def run(command,label,expected=0,timeout=180):
        with(work/(label+'.log')).open('w')as log:r=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        if expected is not None:assert r.returncode==expected,(label,r.returncode,(work/(label+'.log')).read_text(errors='replace')[-1200:])
        return r.returncode
    def until(predicate,label,timeout=30):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            if predicate():return
            time.sleep(.1)
        raise AssertionError(label+' timed out')
    def compile(arguments,label):
        with(work/(label+'.log')).open('w')as log:r=subprocess.run([str(tool),'-V2',*arguments],env=nsisenv,stdout=log,stderr=subprocess.STDOUT)
        assert r.returncode==0,(label,(work/(label+'.log')).read_text())
    def seal(path):
        records={f.relative_to(path).as_posix():sha(f)for f in sorted(path.rglob('*'))if f.is_file()and f.name!='payload-manifest.json'}
        (path/'payload-manifest.json').write_text(json.dumps({'version':1,'files':records})+'\n')
    def fixture(version):
        path=work/('payload-'+version);path.mkdir();runtime=path/'runtime/python';runtime.mkdir(parents=True)
        assert sha(python_archive)==python_lock['sha256'],'Pinned embedded Python archive checksum differs'
        with zipfile.ZipFile(python_archive)as z:z.extractall(runtime)
        shutil.copy2(HERE/'install_support.py',path/'install_support.py')
        (path/'launcher.py').write_text("from pathlib import Path\nimport time\nr=Path(__file__).resolve().parent\n(r/'RUNNING').write_text('ready')\nwhile not(r/'STOP').exists():time.sleep(.1)\n(r/'RUNNING').unlink()\n(r/'STOP').unlink()\n")
        (path/'release.json').write_text(json.dumps({'applicationId':'io.github.Alexayy.Love2Gathering','version':'2026.11.18.'+version,'tag':'DEV-2026.11.18.'+version+'-1-'+version*12,'channel':'development','sourceRevision':version*40,'builtAtUTC':'2026-11-18T00:00:00Z'}))
        for name in('app.love','runtime/java/bin/java.exe','runtime/love/love.exe','bridge/target/xmage-bridge-1.0.0.jar','assets/owned-note.txt',
                     'runtime/java/'+('obsolete-runtime.dll'if version=='1'else'new-runtime.dll'),
                     'bridge/target/lib/'+('obsolete.jar'if version=='1'else'new.jar')):
            f=path/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('Labeled transaction fixture '+version+' '+name)
        compile(['-DOUTPUT='+str(path/'Love2Gathering.exe'),str(HERE/'launcher.nsi')],'launcher-'+version)
        seal(path);installer=work/('setup-'+version+'.exe')
        compile(['-DPAYLOAD='+str(path),'-DOUTPUT='+str(installer),'-DVERSION=2026.11.18.'+version,str(HERE/'installer.nsi')],'installer-'+version)
        return path,installer
    def setup(installer,label,expected=0):return run(['wine','cmd','/c',win(installer)+' /S /D='+win(target)],label,expected)
    def query_registry(label):
        code=run(['wine','reg','query',r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering'],label,None)
        return code,(work/(label+'.log')).read_text(errors='replace')
    def snapshot():return{f.relative_to(target).as_posix():sha(f)for f in target.rglob('*')if f.is_file()}
    try:
        old,first=fixture('1');new,second=fixture('2')
        setup(first,'install-first');check((target/'.love2gathering-install.json').is_file()and(target/'Uninstall.exe').is_file(),'Actual NSIS installs the complete sealed fixture into the chosen folder')
        _,reg=query_registry('registry-first');check('QuietUninstallString'in reg and'/S'in reg,'Windows Apps registers an explicit quiet uninstall command')
        inside=target/'keep-user-save.sqlite';outside=work/'outside-user-save.sqlite'
        for f in(inside,outside):
            with sqlite3.connect(f)as db:db.execute('CREATE TABLE saved(value TEXT)');db.execute("INSERT INTO saved VALUES('keep me')")
        saved={str(f):sha(f)for f in(inside,outside)}
        # Run the actual installed launcher/Python. No process is terminated by
        # the installer or uninstaller; the fixture exits through its own STOP.
        run(['wine',win(target/'Love2Gathering.exe')],'start-installed')
        until(lambda:(target/'RUNNING').exists(),'Installed Python start')
        before=snapshot();code=setup(second,'upgrade-while-active',None)
        check(code!=0 and snapshot()==before,'An active installed runtime refuses upgrade without changing any payload/user file')
        run(['wine',win(target/'Uninstall.exe'),'/S'],'uninstall-while-active',None)
        time.sleep(.5);_,reg=query_registry('registry-busy')
        check((target/'Love2Gathering.exe').is_file()and'2026.11.18.1'in reg,'A refused active uninstall retains the application and its Windows registration')
        (target/'STOP').write_text('stop');until(lambda:not(target/'RUNNING').exists(),'Installed Python clean exit');time.sleep(.4)
        lock_ready=work/'FILE-LOCKED';unlock=work/'RELEASE-FILE';lock_script=work/'external-file-lock.py'
        lock_script.write_text('import ctypes,time\nfrom pathlib import Path\nk=ctypes.WinDLL("kernel32",use_last_error=True)\n'
                               +'k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p];k.CreateFileW.restype=ctypes.c_void_p\n'
                               +'h=k.CreateFileW('+repr(win(target/'bridge/target/xmage-bridge-1.0.0.jar'))+',0x80000000,0,None,3,0,None);assert h!=ctypes.c_void_p(-1).value\n'
                               +'Path('+repr(win(lock_ready))+').write_text("locked")\n'
                               +'while not Path('+repr(win(unlock))+').exists():time.sleep(.05)\n'
                               +'k.CloseHandle.argtypes=[ctypes.c_void_p];k.CloseHandle(h)\n')
        lock_log=(work/'external-file-lock.log').open('w')
        locker=subprocess.Popen(['wine',win(new/'runtime/python/python.exe'),'-B',win(lock_script)],env=env,stdout=lock_log,stderr=subprocess.STDOUT)
        until(lambda:lock_ready.exists()or locker.poll()is not None,'External exclusive file lock');assert lock_ready.is_file()
        before=snapshot();code=setup(second,'upgrade-file-locked',None)
        check(code!=0 and locker.poll()is None and snapshot()==before,'An externally locked owned JAR refuses replacement without changing files or killing the locking process')
        unlock.write_text('release');assert locker.wait(timeout=20)==0;lock_log.close()
        (target/'assets/owned-note.txt').write_text('User-modified owned file')
        before=snapshot();code=setup(second,'upgrade-modified-owned',None)
        check(code!=0 and snapshot()==before,'A modified owned file is preserved by refusing its update')
        shutil.copy2(old/'assets/owned-note.txt',target/'assets/owned-note.txt')
        # Force a failure after the new tree was published by omitting staged
        # shortcuts; verify the old payload and registration really roll back.
        shutil.copy2(target/'Uninstall.exe',new/'Uninstall.exe');before=snapshot();result=work/'rollback.json'
        code=run(['wine',win(new/'runtime/python/python.exe'),'-B',win(new/'install_support.py'),'install','--prefix',win(target),'--source',win(new),'--links',win(work/'missing-links'),'--version','2026.11.18.2','--result',win(result)],'rollback-post-publish',None)
        check(code!=0 and snapshot()==before and not json.loads(result.read_text())['passed'],'A post-publication integration failure restores the exact old file tree')
        _,reg=query_registry('registry-rollback');check('2026.11.18.1'in reg,'A failed upgrade restores the prior Windows Apps registration')
        # A sealed old installation predates the stronger per-install record.
        # Migration must still recognize only old manifest-owned files.
        (target/'.love2gathering-install.json').unlink()
        handoff=work/'update_handoff.py';shutil.copy2(ROOT/'packaging/runtime/update_handoff.py',handoff)
        session=work/'update session';session.mkdir();release_parent=work/'RELEASE-PARENT';parent_ready=work/'PARENT-READY'
        parent_script=work/'installed-supervisor-fixture.py'
        parent_script.write_text('import hashlib,json,shutil,sys,time\nfrom pathlib import Path\nsys.path.insert(0,'+repr(win(work))+')\nimport update_handoff as u\n'
                                 +'root=Path('+repr(win(target))+');session=Path('+repr(win(session))+')\n'
                                 +'context_path=u.create_context(root,session);c=u.document(context_path)\n'
                                 +'work=Path(c["workDirectory"]);work.mkdir();installer=work/"Love2Gathering-2026.11.18.2-windows-x64-setup.exe"\n'
                                 +'shutil.copyfile('+repr(win(second))+',installer)\n'
                                 +'job={k:c[k]for k in("token","root","method","channel")}\n'
                                 +'job.update(schema=1,version="2026.11.18.2",revision="2"*40,tag="DEV-2026.11.18.2-1-"+"2"*12,installerPath=str(installer),expectedSize=installer.stat().st_size,checksum=hashlib.sha256(installer.read_bytes()).hexdigest())\n'
                                 +'job["candidateId"]=hashlib.sha256((job["tag"]+"\\n"+installer.name+"\\n"+str(job["expectedSize"])+"\\n"+job["checksum"]).encode()).hexdigest()\n'
                                 +'u.atomic_json(Path(c["requestPath"]),job);assert u.prepare_handoff(context_path)\n'
                                 +'Path('+repr(win(parent_ready))+').write_text("prepared")\n'
                                 +'while not Path('+repr(win(release_parent))+').exists():time.sleep(.05)\n')
        parent_log=(work/'deferred-parent.log').open('w')
        parent=subprocess.Popen(['wine',win(target/'runtime/python/python.exe'),'-B',win(parent_script)],env=env,stdout=parent_log,stderr=subprocess.STDOUT)
        until(lambda:parent_ready.exists()or parent.poll()is not None,'Installed supervisor handoff preparation')
        check(parent_ready.is_file()and parent.poll()is None and(session/'update-python/python.exe').is_file(),'The deferred updater copies the real interpreter outside the installed tree while its parent is alive')
        time.sleep(1)
        check(not(session/'update-result.json').exists()and json.loads((target/'release.json').read_text())['version']=='2026.11.18.1','The real copied helper waits for the exact active installed parent before invoking NSIS')
        release_parent.write_text('exit');assert parent.wait(timeout=30)==0;parent_log.close()
        until(lambda:(session/'update-result.json').is_file(),'Deferred complete package update',90)
        outcome=json.loads((session/'update-result.json').read_text())
        check(outcome.get('state')=='installed'and outcome.get('version')=='2026.11.18.2'and(target/'.love2gathering-install.json').is_file(),'After parent exit, the helper rehashes and installs the complete selected release through direct Win32 CreateProcess')
        until(lambda:(target/'RUNNING').is_file(),'Updated installed application restart')
        check((session/'update-request.accepted.json').is_file(),'A successful deferred update restarts the installed launcher without replaying its accepted request')
        (target/'STOP').write_text('stop');until(lambda:not(target/'RUNNING').exists(),'Updated Python clean exit');time.sleep(.4)
        check((target/'app.love').read_bytes()==(new/'app.love').read_bytes()and(target/'bridge/target/xmage-bridge-1.0.0.jar').read_bytes()==(new/'bridge/target/xmage-bridge-1.0.0.jar').read_bytes(),'A successful update replaces both client and compiled bridge components')
        check(not(target/'runtime/java/obsolete-runtime.dll').exists()and not(target/'bridge/target/lib/obsolete.jar').exists()and(target/'runtime/java/new-runtime.dll').is_file()and(target/'bridge/target/lib/new.jar').is_file(),'A complete update removes obsolete owned runtime/JAR files and installs their replacements')
        check(all(sha(Path(name))==value for name,value in saved.items()),'Upgrade preserves genuine SQLite saves inside and outside the install folder')
        _,reg=query_registry('registry-upgraded');check('2026.11.18.2'in reg,'Successful upgrade publishes only the new registered version')
        modified=target/'assets/owned-note.txt';modified.write_text('Preserved personal modification');modified_hash=sha(modified)
        run(['wine',win(target/'Uninstall.exe'),'/S'],'uninstall-success')
        until(lambda:not(target/'Love2Gathering.exe').exists()and not(target/'Uninstall.exe').exists(),'Transactional uninstall')
        check(all(sha(Path(name))==value for name,value in saved.items())and sha(modified)==modified_hash,'Uninstall preserves untracked SQLite data and modified owned files')
        code,_=query_registry('registry-removed');check(code!=0,'Successful uninstall removes its Windows Apps registration')
        links=list(prefix.glob('drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Love2Gathering/*.lnk'))
        check(not links,'Successful uninstall removes only its still-owned Start Menu shortcuts')
    except BaseException as exc:failure=str(exc)
    finally:
        if(target/'RUNNING').exists():(target/'STOP').write_text('stop')
        # The entire Wine prefix belongs to this run, never the user’s prefix.
        subprocess.run(['wineserver','-k'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['wineserver','-w'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
    report={'passed':failure is None,'failure':failure,'checks':checks,'work':str(work),'wineVersion':subprocess.check_output(['wine','--version'],text=True).strip(),
            'scope':'Actual NSIS install/update/uninstall, Win32 process/file checks, registry/shortcut rollback and real deferred helper with copied CPython, exact-parent wait, verified installer and installed-launcher restart under a fresh isolated Wine prefix. Client/Java/LÖVE/bridge files are labeled small transaction fixtures; no native Windows VM, graphics or gameplay claim. Genuine SQLite saves are preserved. No arbitrary process kills or user stores.',
            'ownedWinePrefixStopped':True,'pythonArchiveSha256':sha(python_archive),'handoffSourceSha256':sha(work/'update_handoff.py')if(work/'update_handoff.py').exists()else None,
            'sourceHashes':{str(f.relative_to(ROOT)):sha(f)for f in(HERE/'installer.nsi',HERE/'install_support.py',Path(__file__))}}
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'failure':failure,'checks':len(checks),'report':str(a.report)}),flush=True)
    return 0 if report['passed']else 1


if __name__=='__main__':raise SystemExit(main())
