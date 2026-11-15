#!/usr/bin/env python3
"""Fresh, owned native native-recovery projection/response/privacy acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from urllib.request import Request,urlopen

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,build_bridge,isolated_env,java_tools,sha,write_json


def replay_delivery_http(output):
    """Deliver actual JVM WAL-outbox bytes through the real catalog protocol."""
    sys.path.insert(0,str(ROOT/'service'))
    from catalog import Catalog
    from storage import Storage
    from server import make_handler
    work=output/'catalog';work.mkdir()
    source=work/'cards.jsonl';source.write_text('')
    catalog=Catalog(source,work/'catalog.sqlite');catalog.ensure()
    store=Storage(work/'saves',work/'bundled');handler=make_handler(catalog,store)
    server=ThreadingHTTPServer(('127.0.0.1',0),handler);server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        batch=json.loads((output/'native/delivery-replay.json').read_text())
        base='http://127.0.0.1:'+str(server.server_port)
        def post(path,body):
            request=Request(base+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'},method='POST')
            with urlopen(request,timeout=3)as response:return json.load(response)
        identifier=batch['metadata']['id'];post('/replays',batch['metadata'])
        result=post('/replays/'+identifier+'/events',{'events':batch['events']})
        retried=post('/replays/'+identifier+'/events',{'events':batch['events']})
        saved=store.replay_events(identifier)['events']
        assert result['inserted']==1 and retried['inserted']==0
        assert saved==batch['events'] and saved[0]['data']['status']=='failed'
        return dict(status='pass',eventCount=len(saved),inserted=result['inserted'],retryInserted=retried['inserted'],
                    eventType=saved[0]['type'],nativeLogType=saved[0]['data']['type'],
                    scope='Actual queue failure -> durable JVM SQLite outbox -> real owned catalog HTTP -> immutable replay read and idempotent retry')
    finally:
        server.shutdown();server.server_close();thread.join(3);handler.close_managers()


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--build-report',type=Path,help='Reuse an isolated bridge build only when every recorded Java source hash still matches')
    parser.add_argument('--report-file',type=Path,default=ROOT/'bridge/tests/native-recovery-report.json')
    args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-native-recovery-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output must be empty')
    def engine_identity():
        def git(*values):return subprocess.check_output(['git',*values],cwd=ROOT)
        return dict(head=git('rev-parse','HEAD:engine/mage').decode().strip(),index=git('rev-parse',':engine/mage').decode().strip(),
                    gitmodules=sha(ROOT/'.gitmodules'),status=git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all').decode(),
                    diff=hashlib.sha256(git('-C','engine/mage','diff','--binary')).hexdigest())
    before=engine_identity();build=None;result={};watch={};replay={};failure=None
    sources=[ROOT/'bridge/tests/love2gathering'/name for name in('TriggerFixture.java','ActionabilityFixture.java','GameplayPresentationFixture.java','NativeRecoveryFixture.java')]
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
                              '-cp',str(classes)+os.pathsep+build['classpath'],'love2gathering.NativeRecoveryFixture',str(ROOT),str(work)],work,env=env)
        watch=process.wait({'wallSeconds':50,'cpuSeconds':40,'rssBytes':1200*1024**2,'diskBytes':64*1024**2})
        if(work/'result.json').is_file():result=json.loads((work/'result.json').read_text())
        if watch.get('status')!='pass'or result.get('passed')is not True:raise AssertionError('Native recovery acceptance failed; see native/process.log')
        replay=replay_delivery_http(output)
    except Exception as exc:failure=str(exc)
    unchanged=engine_identity()==before
    report=dict(status='pass'if failure is None and unchanged else'fail',failure=failure,engineUnchanged=unchanged,build=build,
                fixture=result,watchdog=watch,replayDelivery=replay,sourceHashes={str(path.relative_to(ROOT)):sha(path)for path in sources},
                baseline=json.loads((ROOT/'bridge/tests/native-recovery-baseline-report.json').read_text()),output=str(output),
                scope='Real pinned XMage Greaves equip, Serenity mixed-zone targeting, native mana undo and installed capabilities. Initial zones/resources/turn cursor are deterministic fixtures. Delayed-publication and injected delivery failures test the actual loopback action handler and transport fences, not game rules. No external services, game replacement, card acquisition, user storage or engine changes.')
    write_json(output/'report.json',report);write_json(args.report_file,report)
    print('Native recovery '+report['status']+'; '+str(output/'report.json'))
    if failure:print(failure,file=sys.stderr)
    return 0 if report['status']=='pass'else 1


if __name__=='__main__':raise SystemExit(main())
