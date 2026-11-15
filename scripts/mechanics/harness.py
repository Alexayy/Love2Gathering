"""Repeatable native, production, transport and client diagnostic orchestration."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse
import collections
import datetime
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import time
import uuid
from .generate import generate
from .runtime import (ROOT, OwnedProcess, Services, baseline, build_bridge, git,
                      isolated_env, java_tools, machine, new_run, sha, verify_engine, write_json)
from .runtime import probe_projection, RUN_CANCELLED


class RunInterrupted(Exception):pass


def manifests():
    result=[]
    for path in sorted((ROOT/'bridge/tests/mechanics').glob('*.json')):
        data=json.loads(path.read_text());items=data if isinstance(data,list)else data['scenarios']
        for item in items:
            item=dict(item);item['manifest']=str(path.relative_to(ROOT));item['manifestSha256']=sha(path)
            item.setdefault('evidenceType',item.get('evidenceKind','deterministic_native'));result.append(item)
    ids=[item['id']for item in result]
    if len(ids)!=len(set(ids)):raise ValueError('Duplicate scenario IDs')
    if len(ids)<50:raise ValueError('At least50 directed native scenarios required')
    if sum(bool(s.get('combined'))for s in result)<15:raise ValueError('At least15 combined scenarios required')
    return result


def compile_fixtures(directory,build):
    directory.mkdir(parents=True,exist_ok=False)
    sources=sorted((ROOT/'bridge/tests/love2gathering').glob('*.java'))
    command=[str(java_tools()['javac']),'-encoding','UTF-8','-cp',build['classpath'],'-d',str(directory),*map(str,sources)]
    with(directory.parent/'fixture-compile.log').open('wb')as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
    return {'classpath':str(directory)+os.pathsep+build['classpath'],
            'sourceHashes':{str(p.relative_to(ROOT)):sha(p)for p in sources}}


def run_case(spec,repeat,directory,build,fixtures,common,env_extra=None):
    if RUN_CANCELLED.is_set():return {**common,'scenarioId':spec['id'],'repeat':repeat,'status':'not_run','reason':'Runner interrupted before child launch'}
    work=directory/(spec['id']+'-r'+str(repeat));work.mkdir(parents=True,exist_ok=False)
    budgets={'wallSeconds':45,'rssBytes':1536*1024*1024,'logBytes':32*1024*1024,
             **spec.get('budgets',{})}
    tools=java_tools();heap=budgets.get('heapMb',budgets.get('heapMiB',768))
    command=[str(tools['java']),'-XX:ActiveProcessorCount=2','-Xmx'+str(heap)+'m',
             '-Djava.awt.headless=true','-Duser.home='+str(work/'home'),
             '-Xlog:gc:file='+str(work/'gc.log')+':uptime,level,tags',
             '-cp',fixtures['classpath'],spec['fixtureClass'],str(ROOT),spec['id'],str(work)]
    configurable={'stepSeconds':'stepSeconds','nativeEvents':'nativeEvents','acceptedActions':'acceptedActions','attempts':'attempts','nativeObjects':'objects','nativeResolutions':'nativeResolutions','stackResolutions':'stackResolutions','flushMillis':'flushMillis'}
    command[1:1]=['-Dlove2gathering.test.'+prop+'='+str(budgets[key])for key,prop in configurable.items()if key in budgets]
    write_json(work/'scenario.json',spec)
    process=OwnedProcess(command,work,env=isolated_env(work,env_extra))
    watch=process.wait(budgets,jcmd=tools['jcmd'])
    result_path=work/'result.json'
    try:native=json.loads(result_path.read_text())if result_path.exists()else{}
    except ValueError:native={'status':'fail','error':'Malformed fixture result; raw evidence retained'}
    status=watch['status']if watch['status']!='pass'else native.get('status','fail')
    if native.get('status')=='budget_exceeded'and watch.get('status')=='fail'and not watch.get('watchdogReason')and watch.get('exitCode')==1 and watch.get('ownedProcessTerminated'):
        status='budget_exceeded'
    classification=native.get('classification')
    # A suspected native discrepancy remains a failed assertion. Classification
    # is a separate research field, never a way to turn a failure into a pass.
    if spec['id']=='adv-prevent-unpreventable-banefire' and native.get('status')=='fail':
        classification='suspected_upstream'
    metrics={}
    frames=list(dict.fromkeys(p for p in [work/'projection.json',work/'visible-merged-frame.json',work/'final-frame.json',work/'checkpoint-frame.json',*sorted(work.glob('last-session-*.json')),*sorted(work.glob('stack-before-*.json'))]if p.exists()))
    projection=frames[0]if frames else work/'projection.json'
    if projection.exists():
        try:
            metrics['frameSizes']={p.name:p.stat().st_size for p in frames}
            if max(metrics['frameSizes'].values(),default=0)>budgets.get('projectionBytes',16*1024*1024):
                status='budget_exceeded';raise ValueError('Frame exceeds projection byte budget; not decoded or transported')
            data=projection.read_bytes();started=time.perf_counter();frame=json.loads(data);decode=(time.perf_counter()-started)*1000
            metrics={'pythonJsonDecodeMs':decode,'projectionBytes':len(data),'projectionFile':projection.name,'nativeProjectedObjects':sum(len(p.get('battlefield',[]))for p in frame.get('players',[])),
                     'frameSizes':{p.name:p.stat().st_size for p in frames}}
            metrics['loopbackTransport']=probe_projection(projection)
        except Exception as ex:
            metrics['projectionInspectionError']=str(ex)
            if status in('pass','native_limit_observed'):status='fail'
    over=[]
    for field,limit in(('acceptedActions','acceptedActions'),('attemptedActions','attempts'),('nativeEvents','nativeEvents'),('nativeEventCount','nativeEvents'),('nativeResolutions','nativeResolutions'),('resolutions','nativeResolutions')):
        value=native.get(field,native.get('metrics',{}).get(field))
        if isinstance(value,(int,float))and limit in budgets and value>budgets[limit]:over.append(field)
    if metrics.get('nativeProjectedObjects',0)>budgets.get('nativeObjects',float('inf')):over.append('nativeObjects')
    if native.get('metrics',{}).get('outboxAndSqlBytesAfter',0)>budgets.get('outboxBytes',float('inf')):over.append('outboxBytes')
    if max(metrics.get('frameSizes',{}).values(),default=0)>budgets.get('projectionBytes',16*1024*1024):over.append('projectionBytes')
    if over:status='budget_exceeded';metrics['postOperationBudgetExceeded']=over
    if native.get('gameThreadAlive')or any(t.get('alive')for t in native.get('gameThreads',[])):
        status='hang_suspected';metrics['cleanupIssue']='Fixture GAME executor remained alive after bounded native stop'
    cleanup=work/'cleanup.json'
    if cleanup.exists():
        metrics['cleanup']=json.loads(cleanup.read_text())
        if any(metrics['cleanup'].get(k)for k in('gameThreadAlive','sessionGameThreadAlive'))or metrics['cleanup'].get('decisionExecutorTerminated')is False:
            status='hang_suspected';metrics['cleanupIssue']='Native decision worker did not terminate after bounded cleanup'
    result={**common,'scenarioId':spec['id'],'repeat':repeat,'status':status,
            'evidenceType':spec.get('evidenceType','deterministic_native'),
            'expected':spec.get('expected'),'cards':spec.get('cards',[]),'findingClassification':classification,
            'manifestSha256':spec.get('manifestSha256'),'budgets':budgets,
            'watchdog':watch,'actual':native,'metrics':metrics,
            'fixtureClass':spec['fixtureClass'],'fixtureSourceSha256':fixtures['sourceHashes'].get('bridge/tests/love2gathering/'+spec['fixtureClass'].split('.')[-1]+'.java'),
            'configurationSha256':sha(work/'scenario.json'),'evidenceDirectory':str(work)}
    write_json(work/'combined-result.json',result)
    print(spec['id']+' #'+str(repeat)+': '+status,flush=True)
    return result


def outbox_recovery(directory,fixtures,port):
    directory.mkdir(parents=True);tools=java_tools();env=isolated_env(directory);marker=directory/'marker.json'
    outcomes=[]
    for phase,args in [('write',['write',str(port),str(marker),'1']),('recover',['recover',str(port),str(marker)])]:
        work=directory/phase
        command=[str(tools['java']),'-XX:ActiveProcessorCount=2','-Xmx256m','-Duser.home='+env['HOME'],'-cp',fixtures['classpath'],'love2gathering.ReplayOutboxFixture',*args]
        p=OwnedProcess(command,work,env=env);status=p.wait({'wallSeconds':30,'rssBytes':768*1024*1024},jcmd=tools['jcmd']);outcomes.append(status)
        if status['status']!='pass':raise RuntimeError('Outbox '+phase+' fault/recovery failed; evidence retained')
    crash=json.loads(marker.read_text())
    from .runtime import http_json
    meta=http_json(f'http://127.0.0.1:{port}/replays/'+crash['id'])
    result={'status':'pass','evidenceType':'recording_transport_crash_fixture','durableBeforeAbruptExit':crash['durablePending'],
            'recoveredStatus':meta['status'],'eventCount':meta['eventCount'],'lastSequence':meta['lastSequence'],'processes':outcomes}
    if meta['status']!='aborted'or meta['eventCount']!=3 or meta['lastSequence']!=2:raise AssertionError('Outbox recovery lost/conflicted events')
    write_json(directory/'result.json',result);return result


def watchdog_selftest(directory,fixtures=None):
    results=[]
    for name,code,limit in [('busy','while True: pass',.4),('waiting','import time;time.sleep(60)',.4),('next','print("next scenario runs")',5)]:
        work=directory/name;work.mkdir(parents=True)
        p=OwnedProcess([sys.executable,'-c',code],work,env=isolated_env(work))
        result=p.wait({'wallSeconds':limit,'rssBytes':128*1024*1024});result['scenarioId']='watchdog-'+name
        results.append(result)
    if fixtures:
        for mode,repeat in((mode,repeat)for mode in('busy','deadlock')for repeat in range(1,4)):
            work=directory/('java-'+mode+'-r'+str(repeat));work.mkdir(parents=True)
            command=[str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xmx96m','-cp',fixtures['classpath'],'love2gathering.MechanicsHangFixture',mode,str(work)]
            p=OwnedProcess(command,work,env=isolated_env(work))
            result=p.wait({'wallSeconds':2,'cpuSeconds':10,'rssBytes':384*1024*1024},jcmd=java_tools()['jcmd']);result['scenarioId']='watchdog-java-'+mode+'-r'+str(repeat)
            result['faultWasInitialized']=(work/'fault.json').exists()
            result['threadDumpCount']=len(list(work.glob('threads-*.txt')))
            results.append(result)
    passed=all(r['ownedProcessTerminated']for r in results)and results[0]['status']==results[1]['status']=='budget_exceeded'and results[2]['status']=='pass'
    if fixtures:
        passed=passed and all(r['status']=='budget_exceeded'and r['faultWasInitialized']and r['threadDumpCount']==3 for r in results[3:])
        work=directory/'next-after-java';work.mkdir(parents=True)
        following=OwnedProcess([sys.executable,'-c','print("next scenario after Java faults")'],work,env=isolated_env(work)).wait({'wallSeconds':5})
        following['scenarioId']='watchdog-next-after-java';results.append(following)
        passed=passed and following['status']=='pass'and following['ownedProcessTerminated']
    write_json(directory/'result.json',{'passed':passed,'evidenceType':'diagnostic_process_fault_fixture','cases':results,'gameOutcome':None})
    if not passed:raise RuntimeError('External watchdog self-test failed')
    return results


def report(directory,data):
    write_json(directory/'results.json',data)
    counts=collections.Counter(row['status']for row in data.get('scenarios',[]))
    lines=['# Mechanics and stability run','', 'Run: `'+data['runId']+'`',
           'Source: `'+data['sourceRevision']+'`; native pin: `'+data['enginePin']+'`.','',
           'These statuses are test evidence, not synthetic game outcomes. A watchdog budget never awards a draw, win or loss.','',
           '| Status | Invocations |','| --- | ---: |']
    lines += ['| '+key+' | '+str(value)+' |'for key,value in sorted(counts.items())]
    lines += ['','| Scenario | Repeat | Status | Evidence |','| --- | ---: | --- | --- |']
    for row in data.get('scenarios',[]):lines.append('| '+row['scenarioId']+' | '+str(row.get('repeat',1))+' | '+row['status']+' | '+str(row.get('evidenceType',''))+' |')
    lines += ['','## Production / client scopes','',
              'Production status: **'+data.get('productionStatus','pending')+'**; native completions: '+str(data.get('production',{}).get('completedNativeGames','pending'))+'.',
              'Client status: **'+data.get('clientStatus','pending')+'**.',
              'Harness error: '+str(data.get('harnessError','none'))+'. Cleanup error: '+str(data.get('cleanupError','none'))+'.',
              'Production outcomes are recorded separately in `production/`; initialized fixture zones do not prove production reachability.',
              'Client synthetic boards and actual-native-projection rendering retain their own evidence labels in `client/`.',
              'Detailed expected/actual values, traces, resource samples, GC logs and failure thread dumps remain beside each scenario.',
              '', '## Engine preservation','',json.dumps(data.get('engineVerification',{}),indent=2),'']
    (directory/'REPORT.md').write_text('\n'.join(lines))


def scope_status(report_value,watchdog=None,*,production=False):
    """All required child scopes affect the parent result, including watchdogs."""
    if watchdog and watchdog.get('status')not in('pass','not_run'):
        ordinary_failure=watchdog.get('status')=='fail'and watchdog.get('exitCode')==1 and not watchdog.get('watchdogReason')and watchdog.get('ownedProcessTerminated')
        if not ordinary_failure:return watchdog['status']
        if not production:return 'budget_exceeded'if report_value and report_value.get('status')=='budget_exceeded'else'fail'
    if not report_value:return 'fail'
    if report_value.get('status')=='not_run':return 'not_run'
    if production:
        rows=report_value.get('results',[])
        from .production import CASES
        if len(rows)!=len(CASES)or not report_value.get('minimumCompletedMet'):return 'fail'
        states={row.get('status')for row in rows}
        return 'pass'if states=={'pass'}else'budget_exceeded'if states<={'pass','budget_exceeded'}else'fail'
    return report_value.get('status','fail')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=('smoke','full','stress'),default='smoke')
    parser.add_argument('--run-dir',type=Path)
    parser.add_argument('--jobs',type=int,default=2)
    parser.add_argument('--scenario',action='append',help='Repeat one exact native scenario; other scopes are explicitly not_run')
    parser.add_argument('--skip-production',action='store_true',help='Diagnostic partial run; marks production not_run')
    parser.add_argument('--skip-client',action='store_true',help='Diagnostic partial run; marks client not_run')
    args=parser.parse_args(argv)
    if not 1<=args.jobs<=3:parser.error('Choose1–3 independent fixture JVMs')
    run=args.run_dir.resolve()if args.run_dir else new_run()
    if run.parent!=Path('/tmp')or not run.name.startswith('love2gathering-mechanics-'):parser.error('run-dir must be an owned /tmp/love2gathering-mechanics-* directory')
    run.mkdir(mode=0o700,exist_ok=True)
    if not(run/'baseline.json').exists():baseline(run)
    old=json.loads((run/'baseline.json').read_text());identifier=run.name.removeprefix('love2gathering-mechanics-')
    execution=run/'executions'/(args.mode+'-'+uuid.uuid4().hex[:8]);execution.mkdir(parents=True)
    data={'runId':identifier,'executionDirectory':str(execution),'sourceRevision':git('rev-parse','HEAD'),
          'dirtyState':git('status','--porcelain=v1','--untracked-files=all'),'enginePin':git('rev-parse','HEAD:engine/mage'),
          'mode':args.mode,'machine':machine(),'scenarios':[],'startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    data['runnerSources']={str(p.relative_to(ROOT)):sha(p)for p in sorted((ROOT/'scripts/mechanics').glob('*.py'))}
    services=None;jobs=[];old_handlers={};RUN_CANCELLED.clear()
    def interrupted(signum,frame):
        RUN_CANCELLED.set();raise RunInterrupted('Runner interrupted by signal '+str(signum)+'; owned children are being stopped')
    for sig in(signal.SIGINT,signal.SIGTERM):old_handlers[sig]=signal.signal(sig,interrupted)
    try:
        all_specs=manifests();spec_by_id={s['id']:s for s in all_specs}
        specs=[s for s in all_specs if not s.get('stage')]
        generation=generate(execution/'generated',[ROOT/path for path in sorted({s['manifest']for s in all_specs})])
        if generation['missingMetadata']or generation['missingNativeMap']:raise RuntimeError('Missing local/native card identities: '+str(generation['missingMetadata']+generation['missingNativeMap']))
        data['generation']=generation
        build=build_bridge(execution/'build');data['build']=build
        fixtures=compile_fixtures(execution/'fixture-classes',build);data['fixtureSources']=fixtures['sourceHashes']
        common={key:data[key]for key in('runId','sourceRevision','enginePin','dirtyState')};common['bridgeJarSha256']=build['jarSha256'];common['listHashes']={d['id']:d['sha256']for d in generation['decks']}
        validation=execution/'deck-validation';validation.mkdir()
        command=[str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xmx768m','-Djava.awt.headless=true','-Duser.home='+str(validation/'home'),'-cp',fixtures['classpath'],'love2gathering.MechanicsDeckValidation',str(ROOT),str(execution/'generated/generation.json'),str(validation)]
        p=OwnedProcess(command,validation,env=isolated_env(validation));data['deckValidationWatchdog']=p.wait({'wallSeconds':90,'rssBytes':1800*1024*1024},jcmd=java_tools()['jcmd'])
        if data['deckValidationWatchdog']['status']!='pass':raise RuntimeError('Native generated-list validation did not complete')
        checked=json.loads((validation/'result.json').read_text());by_id={d['id']:d for d in checked['decks']}
        for deck in generation['decks']:deck.update(by_id[deck['id']])
        write_json(execution/'generated/generation.json',generation)
        watchdog_selftest(execution/'watchdog-selftest',fixtures)
        services=Services(execution/'services',generation['metadata'],build)
        services.start()
        port=services.ports['catalog'];extra={'LOVE2GATHERING_CATALOG_PORT':str(port),'LOVE2GATHERING_TEST_CATALOG_DIRECTORY':str(execution/'services/catalog')}
        data['outboxRecovery']=outbox_recovery(execution/'outbox-recovery',fixtures,port)
        if args.scenario:
            selected=set(args.scenario);missing=selected-set(spec_by_id)
            if missing:raise ValueError('Unknown scenario IDs: '+str(sorted(missing)))
            specs=[spec_by_id[key]for key in sorted(selected)]
        elif args.mode=='smoke':
            wanted={'C01','C07','C14','C21','C26','C27','C28','adv-mutate-top','adv-copy-spell','adv-mutate-projection-token'}
            specs=[s for s in specs if s['id']in wanted]
        data['manifestScenarioCount']=len(all_specs);data['directedMechanicsScenarioCount']=sum(not s.get('stage')for s in all_specs);data['combinedScenarioCount']=sum(bool(s.get('combined'))for s in all_specs if not s.get('stage'))
        jobs=[(s,r)for s in specs for r in range(1,(s.get('repeats',s.get('repetitions',1))if args.mode!='smoke'else 1)+1)]
        with ThreadPoolExecutor(max_workers=args.jobs)as pool:
            futures=[pool.submit(run_case,s,r,execution/'native',build,fixtures,common,extra)for s,r in jobs]
            for future in as_completed(futures):data['scenarios'].append(future.result());report(execution,data)
        for identifier in(()if args.scenario else('life-stop-held','life-stale-game','life-concede-held-answer','life-concurrent-answer','life-unoffered-uuid','life-typed-boolean','life-amount-bounds','life-empty-actionable','life-stale-answer')):
            spec=spec_by_id[identifier]
            for repeat in range(1,(spec.get('repeats',1)if args.mode!='smoke'else 1)+1):data['scenarios'].append(run_case(spec,repeat,execution/'lifecycle',build,fixtures,common,extra))
        levels=[]if args.scenario else[1,10,100]if args.mode=='smoke'else[1,10,100,500,1000]
        native_frames=[]
        stop_escalation=False
        for count in levels:
            variants=['tokens-'+str(count)]
            if count==1000:variants+=['tokens-split1000','tokens-varied-split1000']
            if stop_escalation:
                for skipped in variants:data['scenarios'].append({**common,'scenarioId':skipped,'repeat':1,'status':'not_run','evidenceType':'deterministic_native','reason':'Prior native stress level failed/exceeded its budget'})
                continue
            for index,identifier in enumerate(variants):
                spec=spec_by_id[identifier]
                spec=dict(spec);spec['budgets']={**spec['budgets'],'sharedDiskDirectories':[str(execution/'services/catalog')],'sharedDiskBytes':8*1024*1024*1024}
                result=run_case(spec,1,execution/'stress',build,fixtures,common,extra);data['scenarios'].append(result)
                if result['status']in('pass','native_limit_observed'):native_frames.append(Path(result['evidenceDirectory'])/'projection.json')
                if result['status']not in('pass','native_limit_observed'):
                    stop_escalation=True
                    for skipped in variants[index+1:]:data['scenarios'].append({**common,'scenarioId':skipped,'repeat':1,'status':'not_run','evidenceType':'deterministic_native','reason':'Prior native stress variant failed/exceeded its budget'})
                    break
        if not args.skip_production and not args.scenario:
            command=[sys.executable,'-m','mechanics.production','--engine-url',f'http://127.0.0.1:{services.ports["engine"]}','--catalog-url',f'http://127.0.0.1:{port}','--generation',str(execution/'generated/generation.json'),'--output',str(execution/'production'),'--budget-seconds','120']
            production=OwnedProcess(command,execution/'production-runner',env=isolated_env(execution/'production-runner',{'PYTHONPATH':str(ROOT/'scripts')}))
            data['productionWatchdog']=production.wait({'wallSeconds':1100,'rssBytes':2300*1024*1024,'cpuSeconds':600,'diskBytes':256*1024*1024,'diskDirectories':[str(execution/'production')],'sharedDiskDirectories':[str(execution/'services/catalog'),str(execution/'services/engine')],'sharedDiskBytes':8*1024*1024*1024,'externalOwnedPids':[p.identity for name,p in services.processes.items()if name in('engine','catalog')]})
            summary=execution/'production/production-summary.json';data['production']=json.loads(summary.read_text())if summary.exists()else{'status':'fail','reason':'Production watchdog/driver did not finish'}
        else:data['production']={'status':'not_run','reason':'Explicit --skip-production'}
        data['productionStatus']=scope_status(data['production'],data.get('productionWatchdog'),production=True)
        if not args.skip_client and not args.scenario:
            data['clientSourceAtLaunch']={str(p.relative_to(ROOT)):sha(p)for pattern in('app/*.lua','tests/mechanics_client*')for p in sorted(ROOT.glob(pattern))if p.is_file()}
            command=[sys.executable,str(ROOT/'tests/mechanics_client.py'),'--mode',args.mode,'--output',str(execution/'client')]
            if native_frames:command+=['--native',str(native_frames[-1])]
            client=OwnedProcess(command,execution/'client-runner',env=isolated_env(execution/'client-runner'))
            data['clientRunner']=client.wait({'wallSeconds':240,'rssBytes':1800*1024*1024})
            client_report=execution/'client/report.json'
            if client_report.exists():data['client']=json.loads(client_report.read_text())
        else:data['clientRunner']={'status':'not_run','reason':'Explicit --skip-client'};data['client']={'status':'not_run'}
        data['clientStatus']=scope_status(data.get('client'),data.get('clientRunner'))
    except Exception as ex:
        data['harnessError']=str(ex);print('HARNESS ERROR '+str(ex),file=sys.stderr)
        if isinstance(ex,RunInterrupted):
            data['interrupted']=True;recorded={(row['scenarioId'],row.get('repeat',1))for row in data['scenarios']}
            for spec,repeat in jobs:
                if(spec['id'],repeat)in recorded:continue
                child=execution/'native'/(spec['id']+'-r'+str(repeat))/'combined-result.json'
                data['scenarios'].append(json.loads(child.read_text())if child.exists()else{'scenarioId':spec['id'],'repeat':repeat,'status':'not_run','reason':'Runner interrupted; no completed child result'})
    finally:
        try:
            if services:services.close()
        except Exception as ex:data['cleanupError']=str(ex)
        finally:
            data['finishedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
            try:data['engineVerification']=verify_engine(run)
            except Exception as ex:data['engineVerification']={'passed':False,'error':str(ex)}
            report(execution,data);write_json(run/'latest.json',{'executionDirectory':str(execution),'report':str(execution/'REPORT.md')})
            print('Report: '+str(execution/'REPORT.md'),flush=True)
            for sig,handler in old_handlers.items():signal.signal(sig,handler)
    findings=any(r['status']not in('pass','native_limit_observed')for r in data['scenarios'])
    scope_failure=any(data.get(key,'fail')not in('pass','not_run')for key in('productionStatus','clientStatus'))
    return 1 if data.get('harnessError')or data.get('cleanupError')or not data['engineVerification']['passed']or findings or scope_failure else 0
