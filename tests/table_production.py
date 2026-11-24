#!/usr/bin/env python3
"""Fresh owned production duel completion and Commander turn-round acceptance.

Uses real native deck initialization and MAD bots, an isolated recording catalog
with one local metadata record, and the existing production HTTP test drivers.
No user storage/services, native zone injection or engine-source writes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,Services,build_bridge,http_json,isolated_env,sha,write_json


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--report-file',type=Path,default=ROOT/'tests/table-production-report.json')
    parser.add_argument('--previous-attempt',type=Path,help='Retain the summary of an earlier owned attempt')
    args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-table-production-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output must be empty')

    def engine_identity():
        def git(*values):return subprocess.check_output(['git',*values],cwd=ROOT)
        return{'headGitlink':git('rev-parse','HEAD:engine/mage').decode().strip(),
               'indexGitlink':git('rev-parse',':engine/mage').decode().strip(),
               'engineHead':git('-C','engine/mage','rev-parse','HEAD').decode().strip(),
               'gitmodulesSha256':sha(ROOT/'.gitmodules'),
               'sourceStatus':git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all').decode(),
               'sourceDiffSha256':hashlib.sha256(git('-C','engine/mage','diff','--binary')).hexdigest(),
               'indexDiffSha256':hashlib.sha256(git('-C','engine/mage','diff','--cached','--binary')).hexdigest()}

    before=engine_identity();build=None;services=None;failure=None;results={};watchdogs={};children=[];started=time.monotonic()
    source_paths=sorted((ROOT/'bridge/src').rglob('*.java'))
    frozen={str(path.relative_to(ROOT)):sha(path)for path in source_paths}
    report={'passed':False,'scope':'Fresh bridge-only Java21 compile, real pinned XMage production-deck HTTP games and native MAD bots, real isolated SQLite recording catalog with one metadata record. Full native duel result and 4/5/6-player Commander openings/turn rounds; no native zone injection, GUI, external acquisition or user data/services. Manual priority remains the product default; the drivers answer actual offered choices.',
            'output':str(output),'engineBefore':before,'userStoreModified':False}
    if args.previous_attempt:
        prior_path=args.previous_attempt.resolve()
        if not str(prior_path).startswith('/tmp/love2gathering-mechanics-'):parser.error('Prior attempt must be an owned mechanics report')
        prior=json.loads(prior_path.read_text())
        report['previousAttempt']={'artifact':str(prior_path),'artifactSha256':sha(prior_path),'passed':prior.get('passed'),'failure':prior.get('failure'),'watchdogs':prior.get('watchdogs'),
                                   'previousAttempt':prior.get('previousAttempt'),'scope':'Earlier owned attempt retained separately; the first aggregate RSS ceiling and the legacy manual starting-player prompt expectation were acceptance-driver defects.'}
    def checkpoint(stage):
        write_json(output/'progress.json',{'stage':stage,'elapsedSeconds':round(time.monotonic()-started,3)})
        print('TABLE PRODUCTION '+stage,flush=True)
    try:
        checkpoint('compiling current bridge sources')
        build=build_bridge(output/'build')
        if build['sources']!=frozen:raise AssertionError('Bridge sources changed during the fresh build')
        source=output/'cards.jsonl'
        source.write_text(json.dumps({'object':'card','id':'production-plains','oracle_id':'production-plains-oracle','name':'Plains','lang':'en','set':'tst','type_line':'Basic Land — Plains','legalities':{'modern':'legal','commander':'legal'},'image_uris':{}})+'\n')
        services=Services(output/'services',source,build)
        checkpoint('starting owned catalog and native engine')
        services.start(gateway=False)
        engine='http://127.0.0.1:'+str(services.ports['engine'])
        for key,driver in(('duel','bridge/tests/test_gameplay.py'),('multiplayer','bridge/tests/test_multiplayer.py')):
            checkpoint('running '+key+' production games')
            directory=output/key;child_report=directory/'result.json'
            command=[sys.executable,str(ROOT/driver),'--url',engine,'--recording-port',str(services.ports['catalog']),'--timeout','240','--output',str(child_report)]
            child=OwnedProcess(command,directory,env=isolated_env(directory));children.append(child)
            # Commander has three independently bounded 240-second cases.
            watch=child.wait({'wallSeconds':780 if key=='multiplayer'else 275,'cpuSeconds':1800 if key=='multiplayer'else 550,
                              'rssBytes':2560*1024**2,'diskBytes':2048*1024**2,'diskDirectories':[output/'services'],
                              'externalOwnedPids':[process.identity for process in services.processes.values()]})
            watchdogs[key]=watch
            if not child_report.is_file():raise AssertionError(key+' driver did not publish a result')
            result=json.loads(child_report.read_text());results[key]=result
            if watch['status']!='pass'or result.get('passed')is not True:raise AssertionError(key+' production game failed: '+str(result.get('failure')))
            if key=='duel':
                deadline=time.monotonic()+20;metadata=None
                while time.monotonic()<deadline:
                    metadata=http_json('http://127.0.0.1:'+str(services.ports['catalog'])+'/replays/'+result['replayId'])
                    if metadata.get('status')=='completed':break
                    time.sleep(.05)
                if not metadata or metadata.get('status')!='completed'or not(metadata.get('result')or{}).get('completed'):raise AssertionError('Completed production duel recording did not finalize in the owned catalog')
                report['duelRecording']={name:metadata.get(name)for name in('status','completed','outcome','frameCount','eventCount','actionCount')}
                report['duelRecording'].update(completed=metadata['result']['completed'],outcome=metadata['result'].get('outcome'))
                if not metadata.get('frameCount'):raise AssertionError('Owned duel recording has no frames')
            checkpoint(key+' passed')
    except BaseException as exc:
        failure=str(exc);print('TABLE PRODUCTION FAILED '+failure,flush=True)
    finally:
        for child in children:
            try:child.stop()
            except Exception as exc:failure=failure or str(exc)
        if services:
            try:services.close()
            except Exception as exc:failure=failure or str(exc)
    unchanged=engine_identity()==before
    still_frozen={str(path.relative_to(ROOT)):sha(path)for path in sorted((ROOT/'bridge/src').rglob('*.java'))}==frozen
    cleanup=json.loads((output/'services/cleanup.json').read_text())if(output/'services/cleanup.json').is_file()else{}
    summaries={}
    for key,result in results.items():
        child_path=output/key/'result.json'
        if key=='duel':
            keep=('passed','evidence','failure','turns','actionCount','observedFrameCount','replayId','replayStatus','recordingError','finalPlayers')
            summary={name:result.get(name)for name in keep}
        else:
            summary={name:result.get(name)for name in('passed','kind','concurrentSnapshotReads','snapshotReadErrors','failure','bounds','nativeBotDeckValidation')}
            summary['tests']=[{name:case.get(name)for name in('playerCount','passed','opening','freeMulligan','nativeStartingOrderParticipants','nativeFirstActiveValidated','openingRollMode','openingRollRounds','activePlayersObserved','turn','actionCount','replayId','recordingFramesChecked','recordingParticipantCount')}for case in result.get('tests',[])]
        summary.update(artifact=str(child_path),artifactSha256=sha(child_path));summaries[key]=summary
    report.update(passed=failure is None and unchanged and still_frozen and len(results)==2,
                  failure=failure,engineUnchanged=unchanged,bridgeSourcesStillMatch=still_frozen,build=build,results=summaries,
                  watchdogs=watchdogs,cleanup=cleanup,ownedChildrenTerminated=all(not child.owns()for child in children),
                  elapsedSeconds=round(time.monotonic()-started,3),
                  runnerSources={name:sha(ROOT/name)for name in('tests/table_production.py','bridge/tests/test_gameplay.py','bridge/tests/test_multiplayer.py','scripts/mechanics/runtime.py')})
    if not cleanup or not all(value.get('terminated')for value in cleanup.values()):report['passed']=False;report['failure']=report['failure']or'Owned service termination is unconfirmed'
    write_json(output/'report.json',report);write_json(args.report_file,report)
    checkpoint('passed'if report['passed']else'failed')
    print(str(output/'report.json'),flush=True)
    return 0 if report['passed']else 1


if __name__=='__main__':raise SystemExit(main())
