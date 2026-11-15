#!/usr/bin/env python3
"""Owned real bridge/catalog: local concession ends practice, rooms keep seats."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request,urlopen

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,Services,build_bridge,free_port,isolated_env,java_tools,sha,write_json


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path);parser.add_argument('--report-file',type=Path,default=ROOT/'bridge/tests/practice-concession-report.json');args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-concession-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output directory must be empty')
    def engine_identity():
        git=lambda *a:subprocess.check_output(['git',*a],cwd=ROOT)
        return{'headPin':git('rev-parse','HEAD:engine/mage').decode().strip(),'indexPin':git('rev-parse',':engine/mage').decode().strip(),'gitmodules':sha(ROOT/'.gitmodules'),'engineStatus':git('-C','engine/mage','status','--porcelain=v1','--untracked-files=all').decode(),'engineDiff':hashlib.sha256(git('-C','engine/mage','diff','--binary')).hexdigest()}
    before=engine_identity();build=build_bridge(output/'build')
    source=output/'cards.jsonl';source.write_text(json.dumps({'object':'card','id':'fixture-plains','oracle_id':'fixture-plains-oracle','name':'Plains','lang':'en','set':'tst','type_line':'Basic Land — Plains','legalities':{'modern':'legal','commander':'legal'},'image_uris':{}})+'\n')
    services=Services(output/'services',source,build);checks=[];details=[];failure=None;token=secrets.token_urlsafe(40);games=[];trigger_fixture=None
    def check(value,label):
        checks.append({'passed':bool(value),'message':label})
        if not value:raise AssertionError(label)
    def call(path,body=None,*,catalog=False):
        port=services.ports['catalog'if catalog else'engine'];headers={'Content-Type':'application/json'}
        if path.startswith('/multiplayer/'):headers['Authorization']='Bearer '+token
        request=Request('http://127.0.0.1:'+str(port)+path,data=None if body is None else json.dumps(body).encode(),headers=headers)
        try:
            with urlopen(request,timeout=8)as reply:return json.load(reply)
        except HTTPError as error:raise RuntimeError(str(error.code)+': '+error.read().decode())from error
    def wait(read,predicate,label,seconds=15):
        until=time.monotonic()+seconds;current=None
        while time.monotonic()<until:
            current=read()
            if current.get('error'):raise AssertionError(label+': '+str(current['error']))
            if predicate(current):return current
            time.sleep(.015)
        raise AssertionError(label+': '+json.dumps(current))
    def choice(state):
        p=state.get('prompt');choices=p.get('choices',[])if p else[]
        if not p:return None
        if p.get('mulligan'):return p['mulligan']['keepChoice']
        if 'starting player'in p.get('message','').lower():
            human=next(v for v in state['players']if v['human']);return next(v for v in choices if v['id']==human['id'])
        return next((v for v in choices if v.get('id')=='done'),None)or next((v for v in choices if v.get('value')is False),None)or(choices[0]if choices else None)
    def deck(commander):
        return{'id':'concession-fixture','name':'Concession fixture','format':'Commander'if commander else'Modern','main':[{'name':'Plains','count':99 if commander else 60}],'sideboard':[],'commander':[{'name':'Giada, Font of Hope','count':1}]if commander else[]}
    def replay_loss(state,count):
        replay_id=state['replayId']
        metadata=wait(lambda:call('/replays/'+replay_id,catalog=True),lambda v:v.get('status')=='completed','Practice replay did not finalize')
        result=metadata['result'];own=next(v for v in result['players']if v['id']==result['perspectivePlayerId'])
        check(result['completed']and result['outcome']=='loss'and own['lost']and not own['won'],'Replay retains the native human loss as a completed practice result')
        check(result['terminationReason']=='practice_conceded','Replay identifies the deliberate practice termination')
        if count>2:check(not result['winnerIds']and not any(v['won']or v['lost']for v in result['players']if v['id']!=own['id']),'Ending practice invents no winner or losses in the unfinished bot contest')
        history=call('/history?limit=60',catalog=True);saved=next(v for v in history['matches']if v['id']==replay_id)
        check(saved['completed']and saved['outcome']=='loss','Actual SQLite match history records the conceded practice as a loss')
        frames=call('/replays/'+replay_id+'/frames?limit=1&offset='+str(max(0,metadata['frameCount']-1)),catalog=True)
        if frames['frames']:
            frame=frames['frames'][-1]['data'];check(frame['running']is False and next(v for v in frame['players']if v['human'])['lost'],'Saved terminal native frame retains the human defeat')
        return{'replayId':replay_id,'outcome':saved['outcome'],'result':result}
    try:
        services.start(engine=False,gateway=False)
        port=free_port();env=isolated_env(output/'services/engine',{'LOVE2GATHERING_CATALOG_PORT':str(services.ports['catalog']),'LOVE2GATHERING_COORDINATOR_TOKEN':token})
        services.launch('engine',[str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xms128m','-Xmx1024m','-Djava.awt.headless=true','-Duser.home='+env['HOME'],'-Dlove2gathering.root='+str(ROOT),'-cp',build['classpath'],'love2gathering.EngineBridge',str(port)],env,port)
        for count,after_opening in((2,False),(4,False),(6,True)):
            selected=deck(count>2);body={'format':selected['format'],'playerName':'Concession fixture','deck':selected,'recordingPort':services.ports['catalog'],'startingSeatId':'bot-1'if after_opening else'local','priority':{'autoPass':True,'stops':{'own':[],'opponent':['DRAW']}}}
            if count==2:body['botDeck']=selected
            else:body['bots']=[{'name':'Fixture Bot '+str(index),'deck':selected}for index in range(1,count)]
            call('/session/start',body);state=wait(lambda:call('/session/state'),lambda v:bool(v.get('prompt')),'Practice opening prompt missing')
            if after_opening:
                deadline=time.monotonic()+20
                while time.monotonic()<deadline:
                    p=state.get('prompt');human=next(v for v in state['players']if v['human'])
                    if p and p.get('priority')and state.get('activePlayerId')!=human['id']:break
                    answer=choice(state)
                    if answer:call('/session/action',{'expectedGameId':state['gameId'],'promptId':p['id'],'type':answer['responseType'],'value':answer.get('value',answer['id'])})
                    time.sleep(.01);state=call('/session/state')
                else:raise AssertionError('Inactive human priority was not reached')
                check(True,'Six-player practice reaches a real bot turn before concession')
            game_id=state['gameId'];began=time.monotonic()
            call('/session/action',{'expectedGameId':game_id,'type':'concede','value':True})
            state=wait(lambda:call('/session/state'),lambda v:v.get('running')is False and v.get('execution',{}).get('terminationConfirmed')is True,'Practice GAME thread did not end')
            check(state['execution']['threadAlive']is False and not state['execution']['stopRequested'],'Concession terminates native GAME without relabeling it an aborted Stop')
            check(state['prompt']is None and next(v for v in state['players']if v['human'])['lost'],'Practice stops with no obsolete prompt and an authentic native human loss')
            summary=replay_loss(state,count);summary.update(players=count,afterOpening=after_opening,seconds=time.monotonic()-began);details.append(summary)
            turn=state['turn'];time.sleep(.1);check(call('/session/state')['turn']==turn,'Bots do not continue taking turns after local practice termination')
        practice_id=state['gameId']
        for humans in(4,2):
            selected=deck(True);seats=[{'seatId':'seat-'+str(index),'name':'Room fixture '+str(index),'type':'human'if index<humans else'bot','deck':selected,'priority':{'autoPass':False,'stops':{'own':[],'opponent':[]}}}for index in range(4)]
            opened=call('/multiplayer/start',{'format':'Commander','seats':seats,'recordingPort':0,'startingSeatId':'dice'})
            game_id=opened['gameId'];games.append(game_id);members=[v for v in opened['seats']if v['human']];viewer=members[0]['playerId'];conceding=members[-1]['playerId']
            read=lambda player=viewer:call('/multiplayer/state?'+urlencode({'gameId':game_id,'playerId':player}))
            wait(read,lambda v:bool(v.get('players')),'Room players missing')
            call('/multiplayer/action',{'gameId':game_id,'playerId':conceding,'type':'concede'})
            room=wait(read,lambda v:any(p['id']==conceding and p['lost']for p in v['players']),'Room concession was not processed')
            check(room['running']and room['execution']['threadAlive']and not room['execution']['concedeRequested'],'Room concession leaves the other human and bot seats executing')
            check(not any(p['lost']or p['won']for p in room['players']if p['id']!=conceding),'Room seat concession does not assign other player results')
            answered=0;deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                for member in members[:-1]:
                    current=read(member['playerId']);p=current.get('prompt')
                    if p and p.get('priority'):room=current;break
                    answer=choice(current)
                    if answer:call('/multiplayer/action',{'gameId':game_id,'playerId':member['playerId'],'promptId':p['id'],'type':answer['responseType'],'value':answer.get('value',answer['id'])});answered+=1
                else:time.sleep(.01);continue
                break
            else:raise AssertionError('Surviving human could not advance native room play')
            check(room['running']and answered>0,'Surviving humans keep answering real opening choices after another seat concedes')
            check(call('/session/state')['gameId']==practice_id,'Room concession never alters the independent local practice session')
            details.append({'roomHumans':humans,'players':4,'survivingOpeningAnswers':answered,'turn':room['turn'],'stillRunning':room['running']})
            call('/multiplayer/stop',{'gameId':game_id});games.remove(game_id)
        fixture_classes=output/'fixture-classes';fixture_classes.mkdir()
        sources=[ROOT/'bridge/tests/love2gathering'/name for name in('TriggerFixture.java','ConcessionFixture.java')]
        subprocess.run([str(java_tools()['javac']),'--release','21','-encoding','UTF-8','-cp',build['classpath'],'-d',str(fixture_classes),*map(str,sources)],check=True,capture_output=True)
        fixture_output=output/'trigger-fixture';fixture_env=isolated_env(fixture_output)
        fixture_process=OwnedProcess([str(java_tools()['java']),'-XX:ActiveProcessorCount=2','-Xmx512m','-Djava.awt.headless=true','-Duser.home='+fixture_env['HOME'],'-cp',str(fixture_classes)+os.pathsep+build['classpath'],'love2gathering.ConcessionFixture',str(ROOT),str(fixture_output)],fixture_output,env=fixture_env)
        watch=fixture_process.wait({'wallSeconds':20,'cpuSeconds':15,'rssBytes':768*1024**2,'diskBytes':32*1024**2})
        trigger_fixture=json.loads((fixture_output/'result.json').read_text())if(fixture_output/'result.json').is_file()else{}
        trigger_fixture.update(watchdog=watch,sourceHashes={str(path.relative_to(ROOT)):sha(path)for path in sources})
        check(watch['status']=='pass'and trigger_fixture.get('passed'),'Native manual-trigger concession wakes practice and preserves another human seat ordering')
    except BaseException as exc:failure=str(exc)
    finally:
        for game in games:
            try:call('/multiplayer/stop',{'gameId':game})
            except Exception:pass
        services.close()
    unchanged=engine_identity()==before
    result={'status':'pass'if failure is None and unchanged else'fail','checks':checks,'failure':failure,'details':details,'triggerOrderFixture':trigger_fixture,'engineUnchanged':unchanged,'build':build,'cleanup':json.loads((output/'services/cleanup.json').read_text()),'output':str(output),'sourceHashes':{'app/model.lua':sha(ROOT/'app/model.lua')},'scope':'Fresh bridge-only Java21 build; real owned XMage games and temporary catalog/SQLite replay/history. Production Plains/Giada deck initialization; the separately labeled trigger-order fixture alone injects native initial zones. No external acquisition, user services or engine edits.'}
    write_json(output/'report.json',result);write_json(args.report_file,result)
    print('Practice concession '+result['status']+'; '+str(output/'report.json'))
    if failure:print(failure,file=sys.stderr)
    return 0 if result['status']=='pass'else 1


if __name__=='__main__':raise SystemExit(main())
