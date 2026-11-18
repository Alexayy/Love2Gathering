#!/usr/bin/env python3
"""Accepted native Evoke, Extort and Convoke presentation-cause acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,build_bridge,isolated_env,java_tools,sha,write_json


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-report',type=Path)
    parser.add_argument('--report-file',type=Path,default=ROOT/'bridge/tests/mechanic-causes-report.json')
    args=parser.parse_args()
    output=Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-causes-'))
    sources=[ROOT/'bridge/tests/love2gathering'/name for name in ('TriggerFixture.java','ActionabilityFixture.java','GameplayPresentationFixture.java','ZoneActionsFixture.java','MechanicCauseFixture.java')]
    def identity():
        def git(*values):return subprocess.check_output(['git',*values],cwd=ROOT)
        return dict(pin=git('rev-parse','HEAD:engine/mage').decode().strip(),index=git('rev-parse',':engine/mage').decode().strip(),status=git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all').decode(),diff=hashlib.sha256(git('-C','engine/mage','diff','--binary')).hexdigest())
    before=identity();failure=None;build=None;watch={};result={}
    try:
        if args.build_report:
            document=json.loads(args.build_report.read_text());build=document.get('build',document)
            recorded=build.get('sources')or build.get('sourceHashes')
            if not recorded or any(sha(ROOT/name)!=digest for name,digest in recorded.items()):raise ValueError('Bridge sources changed since supplied build')
            if sha(Path(build['jar']))!=build['jarSha256']:raise ValueError('Bridge JAR changed since supplied build')
        else:build=build_bridge(output/'build')
        classes=output/'fixture-classes';classes.mkdir()
        compiled=subprocess.run([str(java_tools()['javac']),'--release','21','-encoding','UTF-8','-cp',build['classpath'],'-d',str(classes),*map(str,sources)],capture_output=True,text=True,timeout=30)
        (output/'fixture-compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:raise RuntimeError('Native fixture compilation failed')
        work=output/'native';env=isolated_env(work)
        process=OwnedProcess([str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xmx768m','-Djava.awt.headless=true','-Duser.home='+env['HOME'],'-cp',str(classes)+os.pathsep+build['classpath'],'love2gathering.MechanicCauseFixture',str(ROOT),str(work)],work,env=env)
        watch=process.wait(dict(wallSeconds=60,cpuSeconds=45,rssBytes=1200*1024**2,diskBytes=64*1024**2))
        if(work/'result.json').is_file():result=json.loads((work/'result.json').read_text())
        if watch.get('status')!='pass'or not result.get('passed'):raise AssertionError('Native mechanic-cause acceptance failed; inspect native/process.log')
    except Exception as error:failure=str(error)
    unchanged=identity()==before
    report=dict(status='pass'if failure is None and unchanged else'fail',failure=failure,engineUnchanged=unchanged,build=build,fixture=result,watchdog=watch,output=str(output),sourceHashes={str(p.relative_to(ROOT)):sha(p)for p in sources},scope='Actual native accepted casts/costs and material/life outcomes with exact cause identities. Prepared initial zones/resources; no shuffled match or GUI claim.')
    write_json(output/'report.json',report);write_json(args.report_file,report)
    print(report['status'],output/'report.json')
    if failure:print(failure,file=sys.stderr)
    return 0 if report['status']=='pass'else 1


if __name__=='__main__':raise SystemExit(main())
