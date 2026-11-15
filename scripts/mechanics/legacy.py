"""Run existing native regressions in relocated, isolated evidence directories.

Only two temporary Java copies change: their exact fixed /tmp path-literal
prefixes. Original source, engine files, build payloads and user data stay read only.
"""
from __future__ import annotations
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import sys
import uuid
from .runtime import ROOT,OwnedProcess,isolated_env,java_tools,sha,write_json

FIXTURES=(
    ('TriggerFixture','trigger-report.json'),
    ('ActionabilityFixture','actionability-report.json'),
    ('PriorityFixture','priority-report.json'),
    ('NativeViewFixture','native-view-report.json'),
    ('CombatTimingFixture','combat-timing-report.json'),
    ('ProfileFixture','profile-native-report.json'),
    ('CardPrintingFixture','card-printings-native-report.json'),
)
RELOCATED=('NativeViewFixture','CombatTimingFixture')
PREFIXES=('/tmp/love2gathering-native-','/tmp/love2gathering-combat-')


def owned_directory(path):
    path=Path(path).resolve()
    if not str(path).startswith('/tmp/love2gathering-mechanics-'):raise ValueError('An owned mechanics /tmp directory is required')
    return path


def run_legacy(execution,output):
    execution=owned_directory(execution);output=owned_directory(output)
    output.mkdir(parents=True,exist_ok=False)
    build=json.loads((execution/'build/build.json').read_text())
    if sha(build['jar'])!=build['jarSha256']:raise ValueError('Compiled bridge payload changed')
    fixture_classes=execution/'fixture-classes'
    if not fixture_classes.is_dir():raise ValueError('Fresh compiled native fixtures required')
    prior=json.loads((execution/'results.json').read_text())
    original_sources={name:ROOT/'bridge/tests/love2gathering'/(name+'.java')for name,_ in FIXTURES}
    sources={name:sha(path)for name,path in original_sources.items()}
    for name,path in original_sources.items():
        if prior.get('fixtureSources',{}).get(str(path.relative_to(ROOT)))!=sources[name]:raise ValueError('Legacy fixture source differs from the compiled full-run source: '+name)
    work=output/'compile';classes=output/'relocated-classes';classes.mkdir();copies=output/'relocated-src/love2gathering';copies.mkdir(parents=True)
    fixed=output/'relocated-fixed-output';fixed.mkdir()
    relocation={}
    for name in RELOCATED:
        original=original_sources[name].read_text();relocated=original;replacements=[]
        for prefix in PREFIXES:
            literal='"'+prefix;count=relocated.count(literal)
            if count:
                replacement='"'+str(fixed/Path(prefix).name)
                relocated=relocated.replace(literal,replacement)
                replacements.append({'originalLiteralPrefix':literal,'relocatedLiteralPrefix':replacement,'occurrences':count})
        if not replacements or any('"'+prefix in relocated for prefix in PREFIXES):raise ValueError('Unreviewed absolute fixture output path in '+name)
        target=copies/(name+'.java');target.write_text(relocated)
        relocation[name]={'originalSource':str(original_sources[name]),'originalSha256':sources[name],
                          'relocatedSource':str(target),'relocatedSha256':sha(target),'onlyChanges':'exact path-literal prefix relocation','replacements':replacements}
    classpath=str(fixture_classes)+os.pathsep+build['classpath'];tools=java_tools()
    compile_command=[str(tools['javac']),'-J-XX:ActiveProcessorCount=2','-J-Xmx512m','--release','21','-encoding','UTF-8','-cp',classpath,'-d',str(classes),*[str(copies/(name+'.java'))for name in RELOCATED]]
    compiler=OwnedProcess(compile_command,work,env=isolated_env(work));compiled=compiler.wait({'wallSeconds':45,'rssBytes':1024*1024*1024,'cpuSeconds':40},jcmd=None)
    write_json(output/'relocation.json',{'sources':relocation,'compiler':compiled})
    if compiled['status']!='pass':raise RuntimeError('Relocated native fixture compilation failed')
    classpath=str(classes)+os.pathsep+classpath
    results=[]
    for name,report_name in FIXTURES:
        directory=output/name;shadow=directory/'shadow-root';(shadow/'bridge/tests').mkdir(parents=True)
        shutil.copyfile(ROOT/'bridge/card-map.json',shadow/'bridge/card-map.json')
        required=set(re.findall(r'root\.resolve\("(decks/[^"\\]+)"',original_sources[name].read_text()))
        for relative in required:
            target=shadow/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,target)
        env=isolated_env(directory)
        for key in('LOVE2GATHERING_CATALOG_PORT','LOVE2GATHERING_ENGINE_PORT','LOVE2GATHERING_ROOM_PORT','LOVE2GATHERING_COORDINATOR_TOKEN'):env.pop(key,None)
        command=[str(tools['java']),'-XX:ActiveProcessorCount=2','-Xmx768m','-Djava.awt.headless=true','-Duser.home='+env['HOME'],'-Dlove2gathering.root='+str(shadow),'-Xlog:gc:file='+str(directory/'gc.log')+':uptime,level,tags','-cp',classpath,'love2gathering.'+name,str(shadow)]
        budgets={'wallSeconds':60,'rssBytes':1536*1024*1024,'cpuSeconds':60,'diskBytes':256*1024*1024,'logBytes':16*1024*1024}
        process=OwnedProcess(command,directory,env=env);watchdog=process.wait(budgets,jcmd=tools['jcmd'])
        path=shadow/'bridge/tests'/report_name
        try:native=json.loads(path.read_text())if path.is_file()else None
        except ValueError:native=None
        status=watchdog['status']if watchdog['status']!='pass'else'pass'if native and native.get('passed')is True else'fail'
        result={'scenarioId':'legacy-'+name,'status':status,'evidenceType':'existing_native_regression',
                'nativeScope':native.get('scope',native.get('kind'))if native else'No complete native report; inspect process log',
                'nativeCheckCount':native.get('checks')if native else None,'nativeReport':native,
                'bridgeJarSha256':build['jarSha256'],'originalSourceSha256':sources[name],
                'originalClassSha256':sha(fixture_classes/'love2gathering'/(name+'.class')),
                'executedClassSha256':sha((classes if name in RELOCATED else fixture_classes)/'love2gathering'/(name+'.class')),
                'relocated':name in RELOCATED,'shadowRoot':str(shadow),
                'shadowInputHashes':{str(p.relative_to(shadow)):sha(p)for p in [shadow/'bridge/card-map.json',*[shadow/path for path in sorted(required)]]},
                'nativeReportPath':str(path),'budgets':budgets,'watchdog':watchdog,
                'interpretation':'Existing actual native assertions; initialized/cheat positions, normal mulligan starts or seat projections as specified by nativeScope. No complete production match or frontend/UI proof.',
                'deterministicProductionShuffle':False}
        write_json(directory/'result.json',result);results.append(result)
        print(name+': '+status,flush=True)
    unchanged=all(sha(original_sources[name])==value for name,value in sources.items())
    report={'startedFromExecution':str(execution),'bridgeJarSha256':build['jarSha256'],
            'sourceSha256':sha(__file__),'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'results':results,'passed':len(results)==len(FIXTURES)and all(r['status']=='pass'for r in results)and unchanged,
            'originalFixtureSourcesUnchanged':unchanged,'fixedOutputRelocation':str(output/'relocation.json'),
            'executionPolicy':'Sequential JVMs; only exact absolute-output path literals changed in temporary NativeView/CombatTiming source copies; no catalog/image acquisition/user storage'}
    write_json(output/'legacy-summary.json',report);return report


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--execution',type=Path,required=True);parser.add_argument('--output',type=Path)
    args=parser.parse_args(argv)
    output=args.output or owned_directory(args.execution).parents[1]/('legacy-'+uuid.uuid4().hex[:8])
    report=run_legacy(args.execution,output)
    print(json.dumps({'passed':report['passed'],'cases':len(report['results']),'output':str(output)}),flush=True)
    return 0 if report['passed']else 1

if __name__=='__main__':raise SystemExit(main())
