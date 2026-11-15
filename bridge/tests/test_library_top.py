#!/usr/bin/env python3
"""Fresh, owned native library-top projection/response/privacy acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,build_bridge,isolated_env,java_tools,sha,write_json


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--build-report',type=Path,help='Reuse an isolated bridge build only when every recorded Java source hash still matches')
    parser.add_argument('--report-file',type=Path,default=ROOT/'bridge/tests/library-top-report.json')
    args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-library-top-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output must be empty')
    def engine_identity():
        def git(*values):return subprocess.check_output(['git',*values],cwd=ROOT)
        return dict(head=git('rev-parse','HEAD:engine/mage').decode().strip(),index=git('rev-parse',':engine/mage').decode().strip(),
                    gitmodules=sha(ROOT/'.gitmodules'),status=git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all').decode(),
                    diff=hashlib.sha256(git('-C','engine/mage','diff','--binary')).hexdigest())
    before=engine_identity();build=None;result={};watch={};failure=None
    sources=[ROOT/'bridge/tests/love2gathering'/name for name in('TriggerFixture.java','ActionabilityFixture.java','LibraryTopFixture.java')]
    try:
        if args.build_report:
            document=json.loads(args.build_report.read_text());build=document.get('build',document)
            recorded=build.get('sources')or build.get('sourceHashes')
            if not recorded or any(sha(ROOT/name)!=digest for name,digest in recorded.items()):raise ValueError('Bridge source changed since this build')
            if sha(Path(build['jar']))!=build['jarSha256']:raise ValueError('Bridge JAR changed since this build')
        else:build=build_bridge(output/'build')
        classes=output/'fixture-classes';classes.mkdir()
        command=[str(java_tools()['javac']),'--release','21','-encoding','UTF-8','-cp',build['classpath'],'-d',str(classes),*map(str,sources)]
        compiled=subprocess.run(command,capture_output=True,text=True,timeout=30)
        (output/'fixture-compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:raise RuntimeError('Fixture compilation failed; see fixture-compile.log')
        work=output/'native';env=isolated_env(work)
        process=OwnedProcess([str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xmx768m','-Djava.awt.headless=true','-Duser.home='+env['HOME'],
                              '-cp',str(classes)+os.pathsep+build['classpath'],'love2gathering.LibraryTopFixture',str(ROOT),str(work)],work,env=env)
        watch=process.wait({'wallSeconds':50,'cpuSeconds':40,'rssBytes':1200*1024**2,'diskBytes':64*1024**2})
        if(work/'result.json').is_file():result=json.loads((work/'result.json').read_text())
        if watch.get('status')!='pass'or result.get('passed')is not True:raise AssertionError('Native library-top acceptance failed; see native/process.log')
    except Exception as exc:failure=str(exc)
    unchanged=engine_identity()==before
    report=dict(status='pass'if failure is None and unchanged else'fail',failure=failure,engineUnchanged=unchanged,build=build,
                fixture=result,watchdog=watch,sourceHashes={str(path.relative_to(ROOT)):sha(path)for path in sources},
                baseline=json.loads((ROOT/'bridge/tests/library-top-baseline-report.json').read_text()),output=str(output),
                scope='Real pinned XMage decisions and UUID responses on GAME threads; only initial zones/resources and targeted ability setup are deterministic fixtures. No external services, game replacement, card acquisition, user storage or engine changes.')
    write_json(output/'report.json',report);write_json(args.report_file,report)
    print('Library top '+report['status']+'; '+str(output/'report.json'))
    if failure:print(failure,file=sys.stderr)
    return 0 if report['status']=='pass'else 1


if __name__=='__main__':raise SystemExit(main())
