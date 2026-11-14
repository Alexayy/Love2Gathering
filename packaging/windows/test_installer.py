#!/usr/bin/env python3
"""Actual NSIS install/uninstall in an explicitly isolated Wine prefix."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time

PROJECT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--installer',type=Path,required=True)
    p.add_argument('--wine-prefix',type=Path,required=True)
    p.add_argument('--work',type=Path,required=True)
    args=p.parse_args();work=args.work.resolve();prefix=args.wine_prefix.resolve();installer=args.installer.resolve()
    if not work.is_relative_to(PROJECT/'.runtime')or not prefix.is_relative_to(PROJECT/'.runtime'):
        p.error('Wine prefix and work must be explicit directories under this checkout .runtime')
    work.mkdir(parents=True,exist_ok=True);target=work/'Chosen Game Folder'
    if target.exists():p.error('Choose a fresh work directory for this acceptance run')
    env=dict(os.environ,WINEPREFIX=str(prefix),WINEDEBUG='-all',PYTHONLEGACYWINDOWSSTDIO='1')
    win=lambda path:'Z:'+str(path).replace('/','\\')
    def run(command,label,timeout=180):
        with(work/(label+'.log')).open('w')as log:
            result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        assert result.returncode==0,(label,result.returncode)
    def wait(predicate,label):
        until=time.monotonic()+180
        while time.monotonic()<until:
            if predicate():return
            time.sleep(.2)
        raise AssertionError(label+' timed out')
    run(['wine','cmd','/c',win(installer)+' /S /D='+win(target)],'install')
    wait(lambda:(target/'.love2gathering-owned').is_file()and(target/'Uninstall.exe').is_file(),'installation')
    assert(target/'Love2Gathering.exe').is_file()
    links=list(prefix.glob('drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Love2Gathering/Love2Gathering.lnk'))
    assert links,'Start Menu shortcut missing'
    expected=win(target/'Love2Gathering.exe').lower()
    assert any(expected.encode('ascii')in link.read_bytes().lower()or expected.encode('utf-16-le')in link.read_bytes().lower()for link in links),'Shortcut target mismatch'
    inside=target/'keep-user-save.sqlite';outside=work/'outside-user-save.sqlite'
    for path in(inside,outside):
        with sqlite3.connect(path)as c:c.execute('CREATE TABLE user_save(value TEXT)');c.execute("INSERT INTO user_save VALUES('preserve me')")
    before={str(path):hashlib.sha256(path.read_bytes()).hexdigest()for path in(inside,outside)}
    run(['wine',str(target/'Uninstall.exe'),'/S'],'uninstall')
    wait(lambda:not(target/'Love2Gathering.exe').exists()and not(target/'Uninstall.exe').exists(),'uninstallation')
    assert all(path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==before[str(path)]for path in(inside,outside))
    report={'passed':True,'scope':'Actual generated NSIS x64 installer/uninstaller under isolated Wine9; chosen path includes spaces, Start Menu target checked, unlisted real SQLite saves inside/outside installation preserved. Bundled runtime version checks are separate; not native Windows gameplay acceptance.','checks':{'chosenFolder':True,'startMenuTarget':True,'applicationRemoved':True,'unlistedSQLitePreserved':True,'outsideSQLitePreserved':True},'installerSha256':hashlib.sha256(installer.read_bytes()).hexdigest(),'sourceSha256':{str(path.relative_to(PROJECT)):hashlib.sha256(path.read_bytes()).hexdigest()for path in(Path(__file__).resolve(),PROJECT/'packaging/windows/installer.nsi',PROJECT/'packaging/runtime/launcher.py')}}
    (PROJECT/'packaging/windows/installer-test-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report));return 0


if __name__=='__main__':raise SystemExit(main())
