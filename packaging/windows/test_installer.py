#!/usr/bin/env python3
"""Actual NSIS install/uninstall in an explicitly isolated Wine prefix."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

PROJECT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--installer',type=Path,required=True)
    p.add_argument('--wine-prefix',type=Path,required=True)
    p.add_argument('--work',type=Path,required=True)
    p.add_argument('--check-graphics',action='store_true',help='Exercise real bundled Mesa fallback and LÖVE before uninstalling')
    p.add_argument('--upgrade-installer',type=Path,help='Optionally replace the whole installed payload before uninstalling')
    p.add_argument('--check-health',action='store_true',help='Check real bundled runtime versions and owned catalog/engine/room readiness before uninstalling')
    p.add_argument('--check-health-timeout',type=int,default=300,help='Bounded full metadata readiness wait in seconds')
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
    assert(target/'.love2gathering-install.json').is_file(),'Transactional installed-file ownership record is missing'
    run(['wine','reg','query',r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering','/v','QuietUninstallString'],'quiet-uninstall-registration')
    links=list(prefix.glob('drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Love2Gathering/Love2Gathering.lnk'))
    assert links,'Start Menu shortcut missing'
    expected=win(target/'Love2Gathering.exe').lower()
    assert any(expected.encode('ascii')in link.read_bytes().lower()or expected.encode('utf-16-le')in link.read_bytes().lower()for link in links),'Shortcut target mismatch'
    readiness=None;readiness_error=None
    if args.check_health:
        for name in('data','cache','config'):
            folder=work/('owned-'+name);folder.mkdir(exist_ok=True);env['LOVE2GATHERING_'+name.upper()+'_DIR']=win(folder)
        python=win(target/'runtime/python/python.exe');launcher=win(target/'launcher.py')
        try:
            run(['wine',python,'-B',launcher,'--check'],'installed-check',timeout=60)
            run(['wine',python,'-B',launcher,'--checkhealth','--startup-timeout',str(args.check_health_timeout)],'installed-checkhealth',timeout=args.check_health_timeout+150)
            lines=(work/'installed-checkhealth.log').read_text(errors='replace').splitlines()
            readiness=next(json.loads(line)for line in reversed(lines)if line.startswith('{'))
            assert readiness.get('passed')is True,'Installed services did not publish successful readiness'
        except(AssertionError,subprocess.TimeoutExpired,ValueError,StopIteration)as exc:readiness_error=str(exc)
    if args.check_graphics:
        run([sys.executable,str(PROJECT/'packaging/windows/test_graphics_runtime.py'),'--payload',str(target),'--wine-prefix',str(prefix),'--report',str(PROJECT/'packaging/windows/graphics-runtime-report.json')],'graphics-runtime')
    inside=target/'keep-user-save.sqlite';outside=work/'outside-user-save.sqlite'
    for path in(inside,outside):
        with sqlite3.connect(path)as c:c.execute('CREATE TABLE user_save(value TEXT)');c.execute("INSERT INTO user_save VALUES('preserve me')")
    before={str(path):hashlib.sha256(path.read_bytes()).hexdigest()for path in(inside,outside)}
    if args.upgrade_installer:
        previous=json.loads((target/'.love2gathering-install.json').read_text())
        run(['wine','cmd','/c',win(args.upgrade_installer.resolve())+' /S /D='+win(target)],'upgrade')
        current=json.loads((target/'.love2gathering-install.json').read_text())
        for name,expected_hash in current['files'].items():assert hashlib.sha256((target/name).read_bytes()).hexdigest()==expected_hash,'Upgraded payload differs: '+name
        for name in set(previous['files'])-set(current['files']):assert not(target/name).exists(),'Obsolete owned payload survived: '+name
        assert all(hashlib.sha256(path.read_bytes()).hexdigest()==before[str(path)]for path in(inside,outside))
    run(['wine',str(target/'Uninstall.exe'),'/S'],'uninstall')
    wait(lambda:not(target/'Love2Gathering.exe').exists()and not(target/'Uninstall.exe').exists(),'uninstallation')
    assert all(path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==before[str(path)]for path in(inside,outside))
    report={'passed':readiness_error is None,'scope':'Actual generated NSIS x64 installer/uninstaller under isolated Wine; chosen path includes spaces, Start Menu and quiet uninstall registration checked, optional complete payload upgrade/runtime/service readiness, unlisted real SQLite saves inside/outside installation preserved. Not native Windows gameplay acceptance.','wineVersion':subprocess.check_output(['wine','--version'],text=True).strip(),'checks':{'chosenFolder':True,'startMenuTarget':True,'quietUninstallRegistered':True,'completePayloadUpgrade':bool(args.upgrade_installer),'applicationRemoved':True,'unlistedSQLitePreserved':True,'outsideSQLitePreserved':True,'installedSoftwareGraphics':args.check_graphics,'installedServiceReadiness':bool(readiness and readiness.get('passed'))if args.check_health else None},'serviceReadiness':readiness,'serviceReadinessError':readiness_error,'installerSha256':hashlib.sha256(installer.read_bytes()).hexdigest(),'sourceSha256':{str(path.relative_to(PROJECT)):hashlib.sha256(path.read_bytes()).hexdigest()for path in(Path(__file__).resolve(),PROJECT/'packaging/windows/installer.nsi',PROJECT/'packaging/windows/install_support.py',PROJECT/'packaging/runtime/launcher.py')}}
    (PROJECT/'packaging/windows/installer-test-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report));return 0 if report['passed']else 1


if __name__=='__main__':raise SystemExit(main())
