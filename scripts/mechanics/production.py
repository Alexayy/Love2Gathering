"""Normal validated XMage games driven only by explicitly supported offered choices.
No shuffled-game determinism or native-rules replacement is claimed.
"""
from __future__ import annotations
import argparse
import hashlib
import gzip
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request
from .runtime import write_json

BURN=('Lightning Bolt','Lava Spike','Shock','Lightning Strike','Searing Spear')
CASES=(
    ('P01','burn','burn','burn',2),
    ('P02','burn','control','burn',2),
    ('P03','control','control','pass',2),
    ('P06','control','burn','pass',2),
    ('P04','commander-krenko-goblins','commander-giada-angels','pass',4),
    ('P05','commander-krenko-goblins','commander-giada-angels','pass',6),
)
DISCARD=('Mountain','Goblin Guide','Monastery Swiftspear','Ghitu Lavarunner','Skewer the Critics',*BURN)

class BudgetExceeded(RuntimeError):pass

class HTTPFailure(RuntimeError):
    def __init__(self,status,value):super().__init__(str(status)+': '+str(value));self.status=status;self.value=value

class Client:
    def __init__(self,base):
        parts=urllib.parse.urlsplit(base)
        if parts.scheme!='http' or parts.hostname not in('127.0.0.1','localhost') or not parts.port:raise ValueError('Explicit loopback test URL required')
        self.base=base.rstrip('/');self.deadline=None
    def call(self,path,body=None,*,drop_body=False,timeout=8):
        if self.deadline is not None:
            remaining=self.deadline-time.monotonic()
            if remaining<=0:raise BudgetExceeded('overall_http_phase')
            timeout=min(timeout,remaining)
        req=urllib.request.Request(self.base+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req,timeout=timeout)as response:
                if drop_body:return {'acceptedHttpStatus':response.status,'responseBodyIntentionallyDiscarded':True}
                return json.load(response)
        except urllib.error.HTTPError as error:
            try:value=json.loads(error.read())
            except Exception:value={'error':str(error)}
            raise HTTPFailure(error.code,value)from error

def local_player(state):
    local=state.get('localPlayerId')
    if local:return next(p for p in state.get('players',[])if p['id']==local)
    players=[p for p in state.get('players',[])if p.get('human')]
    if len(players)!=1:raise AssertionError('Production practice must expose one local human')
    return players[0]

def semantic(state):
    return json.dumps({'turn':state.get('turn'),'step':state.get('step'),'active':state.get('activePlayerId'),
        'players':[{k:p.get(k)for k in('id','life','handCount','libraryCount','battlefield','graveyard','exile','lost','won')}for p in state.get('players',[])],
        'stack':state.get('stack'),'prompt':state.get('prompt')and state['prompt'].get('id')},sort_keys=True,separators=(',',':'))

def supported_answer(state,policy):
    p=state.get('prompt')
    if not p:return None
    choices={str(c['id']):c for c in p.get('choices',[])};kind=p.get('type');human=local_player(state)
    opponents=[x for x in state['players']if x['id']!=human['id']and not x.get('lost')]
    target=opponents[0]['id']if len(opponents)==1 else None
    def offered(key):
        c=choices.get(str(key))
        if c is None:raise AssertionError('Expected offered choice missing: '+str(key))
        return {'type':c['responseType'],'value':c.get('value',c['id'])}
    if p.get('mulligan'):
        # Keep is the actual offered native false answer, not a message heuristic.
        keep=[c for c in choices.values()if c.get('responseType')=='boolean'and c.get('value')is False]
        if len(keep)!=1:raise AssertionError('Native opening lacks unique offered Keep response')
        return offered(keep[0]['id'])
    role=(p.get('combat')or{}).get('role')
    if role in('attackers','blockers'):
        return offered('done')
    if p.get('priority'):
        actionable=p.get('actionable')
        if not isinstance(actionable,list):raise AssertionError('Native priority must explicitly export actionable array')
        allowed=set(actionable)
        if policy=='burn':
            for name in ('Mountain',*BURN):
                matching=[c for c in human.get('hand',[])if c.get('name')==name and c.get('id')in allowed and c['id']in choices]
                if matching:return offered(min(matching,key=lambda c:c['id'])['id'])
        return offered('done')
    if kind=='play_mana'and policy=='burn':
        # Payment chooses only sources/types which XMage explicitly offers now.
        if 'mana-R'in choices:return offered('mana-R')
        allowed=set(p.get('actionable',[]))
        matching=[c for c in human.get('battlefield',[])if c.get('name')=='Mountain'and c.get('id')in allowed and c['id']in choices]
        if matching:return offered(min(matching,key=lambda c:c['id'])['id'])
        raise AssertionError('Known burn cost has no offered red payment/source; never force Cancel')
    if kind in('pick_target','target','choose_target'):
        message=str(p.get('message','')).casefold()
        if 'starting player'in message:return offered(human['id'])
        if 'discard'in message:
            offered_cards={c['id']:c for c in human.get('hand',[])if c['id']in choices}
            for name in DISCARD:
                matching=[c for c in offered_cards.values()if c.get('name')==name]
                if matching:return offered(min(matching,key=lambda c:c['id'])['id'])
            raise AssertionError('Known hand-size discard contains no predeclared policy card')
        if policy=='burn'and target in choices:return offered(target)
    raise AssertionError('Unknown production prompt; no fallback chosen: '+json.dumps(p))

def reject(client,path,body):
    try:client.call(path,body)
    except HTTPFailure as error:
        if not 400<=error.status<500:raise
        return {'status':error.status,'error':error.value}
    raise AssertionError('Rejected action unexpectedly accepted')

def replay_checks(catalog,identifier,accepted,folder,*,completed,verification_seconds=30):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    deadline=time.monotonic()+verification_seconds;metadata_deadline=time.monotonic()+min(10,verification_seconds)
    def call(path):
        remaining=deadline-time.monotonic()
        if remaining<=0:raise BudgetExceeded('replay_verification_wall_time')
        return catalog.call(path,timeout=min(8,remaining))
    while True:
        meta=call('/replays/'+identifier)
        if(meta.get('status')=='completed'if completed else meta.get('status')in('aborted','completed'))and meta.get('eventCount',0)>0:break
        if time.monotonic()>metadata_deadline:raise BudgetExceeded('replay_finish_wait')
        time.sleep(.05)
    expected={(a['promptId'],a['type'],json.dumps(a.get('value'),sort_keys=True))for a in accepted}
    actual=[];native_events={};frame_count=0;maxbytes=0;last_frame=None;offset=0;raw_bytes=0
    archive=folder/'replay-events.jsonl.gz'
    # Preserve every row losslessly, without accumulating an entire long game
    # or serializing repeated full projections into a multi-gigabyte pretty JSON.
    with gzip.open(archive,'wt',encoding='utf-8',compresslevel=1)as output:
        while True:
            page=call(f'/replays/{identifier}/events?offset={offset}&limit=50');chunk=page['events']
            for event in chunk:
                if time.monotonic()>deadline:raise BudgetExceeded('replay_verification_wall_time')
                if event['sequence']!=offset:raise AssertionError('Recording sequence is not contiguous')
                encoded=json.dumps(event,ensure_ascii=False,separators=(',',':'));raw_bytes+=len(encoded.encode('utf-8'))+1
                output.write(encoded+'\n');offset+=1
                if event['type']=='action'and isinstance(event.get('data'),dict):
                    value=event['data'].get('input',event['data'])
                    if isinstance(value,dict)and value.get('promptId')is not None:actual.append((value['promptId'],value['type'],json.dumps(value.get('value'),sort_keys=True)))
                if event['type']!='frame':continue
                state=event['data'];frame_count+=1;last_frame=state
                for player in state.get('players',[]):
                    if not player.get('human')and player.get('hand'):raise AssertionError('Replay exposes opponent hand')
                for native in state.get('animationEvents',[]):
                    old=native_events.get(native['id'])
                    if old is not None and old!=native:raise AssertionError('Native event identity changed in replay')
                    native_events[native['id']]=native
                maxbytes=max(maxbytes,len(json.dumps(state,separators=(',',':')).encode('utf-8')))
            if offset>=page['total']:break
            if not chunk:raise AssertionError('Replay pagination stopped before its declared total')
    if offset!=meta.get('eventCount')or offset!=meta.get('lastSequence',-1)+1:raise AssertionError('Replay totals disagree with immutable SQL metadata')
    if completed and not meta.get('result',{}).get('completed'):raise AssertionError('Saved result lacks native completion acknowledgement')
    if len(actual)!=len(expected)or set(actual)!=expected:raise AssertionError('Replay includes missing/duplicated/rejected prompt actions')
    if completed and(last_frame is None or last_frame.get('running')is not False):raise AssertionError('Terminal native frame missing from completed replay')
    write_json(folder/'replay-metadata.json',meta)
    result={'status':'pass','eventCount':offset,'frameCount':frame_count,'acceptedPromptActions':len(actual),'rejectedAttemptsAbsent':True,'nativeEventCount':len(native_events),'eventCountScope':'Unique public projected native animation event IDs retained across saved frames; not the complete fired GameEvent stream','maxFrameBytes':maxbytes,'rawExportBytes':raw_bytes,'compressedExportBytes':archive.stat().st_size,'archive':str(archive),'verificationBudgetSeconds':verification_seconds,'nativeFinal':last_frame}
    write_json(folder/'replay-verification.json',result);return result

def one_game(engine,catalog,deck,botdeck,folder,*,identifier,policy,players=2,budget_seconds=120,old_action=None):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True);started=time.monotonic();overall_budget=budget_seconds+50;engine.deadline=started+overall_budget;accepted=[];rejected=[];observed=[];active=set();seen=set();lastbody=old_action;status='fail';failure=None;recording=None;state={};first=True;native_complete=False;game_id=None;native_event_ids=set();last_semantic=None;last_progress=time.monotonic();max_projection=0;transport_times=[]
    port=urllib.parse.urlsplit(catalog.base).port
    body={'format':deck['format'],'recordingPort':port,'playerName':'Mechanics production human','deck':deck,'settings':{'manualTriggers':False,'autoMana':True}}
    if players==2:body['botDeck']=botdeck
    else:body['bots']=[{'name':f'Mechanics bot{i+1}','deck':botdeck}for i in range(players-1)]
    write_json(folder/'start-payload.json',body)
    try:
        before=engine.call('/session/state')
        if before.get('running'):raise AssertionError('Refusing to replace an already running session')
        state=engine.call('/session/start',body)
        identity_deadline=time.monotonic()+12
        while not state.get('gameId')and time.monotonic()<identity_deadline:
            time.sleep(.01);state=engine.call('/session/state')
        game_id=state.get('gameId');recording=state.get('replayId')
        if not game_id:raise AssertionError('No native game identity after ordinary start')
        while time.monotonic()-started<budget_seconds:
            if state.get('error')or state.get('projectionError'):raise AssertionError(state.get('error')or state.get('projectionError'))
            if state.get('gameId')!=game_id:raise AssertionError('Production game identity changed unexpectedly')
            max_projection=max(max_projection,len(json.dumps(state)))
            if max_projection>16*1024*1024:status='budget_exceeded';failure='projection_bytes';break
            if len(accepted)>1200:status='budget_exceeded';failure='accepted_action_budget';break
            sig=semantic(state)
            changed=sig!=last_semantic
            if changed:last_semantic=sig;last_progress=time.monotonic()
            if state.get('activePlayerId'):active.add(state['activePlayerId'])
            for p in state.get('players',[]):
                if not p.get('human')and p.get('hand'):raise AssertionError('Live projection exposes bot hand')
            for event in state.get('animationEvents',[]):native_event_ids.add(event['id'])
            if len(observed)<200:observed.append({'turn':state.get('turn'),'step':state.get('step'),'promptId':state.get('prompt')and state['prompt']['id'],'active':state.get('activePlayerId'),'life':[p.get('life')for p in state.get('players',[])],'semanticChange':changed})
            if state.get('running')is False:
                native_complete=any(p.get('won')for p in state.get('players',[]))and any(p.get('lost')for p in state.get('players',[]))
                if not native_complete:raise AssertionError('Execution stopped without a native winner/loser result')
                status='pass';break
            if players>2 and len(active)==players and state.get('turn',0)>=players+1:
                status='pass';break
            p=state.get('prompt')
            if not p or p['id']in seen:
                time.sleep(.01);state=engine.call('/session/state');continue
            if first:
                if old_action:rejected.append({'kind':'prior_game','result':reject(engine,'/session/action',old_action)})
                malformed={'expectedGameId':game_id,'promptId':p['id'],'type':'uuid','value':'invalid-uuid'}
                rejected.append({'kind':'malformed','result':reject(engine,'/session/action',malformed)})
                current=engine.call('/session/state')
                if current.get('prompt',{}).get('id')!=p['id']:raise AssertionError('Rejected malformed input consumed current prompt')
            response=supported_answer(state,policy);response.update(promptId=p['id'],expectedGameId=game_id);seen.add(p['id']);lastbody=response
            stamp=time.monotonic()
            if first:
                engine.call('/session/action',response,drop_body=True);accepted.append(response)
                rejected.append({'kind':'duplicate_after_lost_body','result':reject(engine,'/session/action',response)})
                first=False;state=engine.call('/session/state')
            else:state=engine.call('/session/action',response);accepted.append(response)
            transport_times.append(time.monotonic()-stamp)
        else:status='budget_exceeded';failure='wall_time'
        if status=='pass'and native_complete:
            if not recording:raise AssertionError('Normal production game has no recording ID')
            engine.call('/session/replay/save',{'expectedGameId':game_id})
            replay=replay_checks(catalog,recording,accepted,folder,completed=True)
        else:replay=None
    except Exception as error:failure=str(error);status='budget_exceeded'if isinstance(error,BudgetExceeded)else'not_covered'if'Unknown production prompt'in failure else'fail';replay=None
    finally:
        write_json(folder/'last-state.json',state);write_json(folder/'actions.json',accepted);write_json(folder/'rejected.json',rejected);write_json(folder/'observations.json',observed)
        stopped=None;engine.deadline=max(engine.deadline or 0,time.monotonic()+8)
        if state.get('gameId')and state.get('running'):
            try:stopped=engine.call('/session/stop',{'expectedGameId':state['gameId']})
            except Exception as error:stopped={'error':str(error)}
            if stopped.get('execution',{}).get('threadAlive'):
                failure='Native stop requested without confirmed GAME termination';status='hang_suspected'
        if recording and replay is None and status=='pass':
            try:replay=replay_checks(catalog,recording,accepted,folder,completed=False)
            except Exception as error:failure='Aborted replay verification: '+str(error);status='budget_exceeded'if isinstance(error,BudgetExceeded)else'fail'
        if time.monotonic()-started>overall_budget:status='budget_exceeded';failure='overall_phase_wall_time'
        engine.deadline=None
        result={'budgets':{'nativeDriveSeconds':budget_seconds,'replayVerificationSeconds':30,'overallSeconds':overall_budget,'singleRequestSeconds':8},'scenarioId':identifier,'evidenceType':'production_game','status':status,'error':failure,'nativeCompleted':native_complete,'runId':next((p.name for p in folder.parents if p.name.startswith('love2gathering-mechanics-')),None),'normalStart':bool(game_id),'deterministic':False,'shuffleSeed':None,'gameId':state.get('gameId'),'replayId':recording,'turn':state.get('turn'),'players':players,'activePlayerIds':sorted(active),'expectedSeatRotation':players>2,'acceptedActions':len(accepted),'attemptedActions':len(accepted)+len(rejected),'nativeEventCount':len(native_event_ids),'eventCountScope':'Unique public projected native animation event IDs observed while polling; bounded projection windows may omit events','rejectedAttempts':rejected,'durationSeconds':round(time.monotonic()-started,3),'maxProjectionBytes':max_projection,'maxTransportSeconds':max(transport_times,default=0),'secondsSinceSemanticChange':round(time.monotonic()-last_progress,3),'finalPlayers':[{k:p.get(k)for k in('id','name','life','won','lost','handCount','libraryCount')}for p in state.get('players',[])],'replay':replay,'stopAcknowledgement':stopped,'lastAcceptedAction':lastbody,'sourceDeckSha256':hashlib.sha256(json.dumps(deck,sort_keys=True).encode()).hexdigest(),'deckValidation':'Native Session constructor performed format validation; normal Game.start, no zone injection'if game_id else'Native startup/validation not confirmed'}
        write_json(folder/'result.json',result)
    return result,lastbody

def run_production(engine_url,catalog_url,generation,outputdir,budget_seconds=120):
    source_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    outputdir=Path(outputdir).resolve()
    if not str(outputdir).startswith('/tmp/love2gathering-mechanics-'):raise ValueError('Only owned mechanics temporary output is accepted')
    engine=Client(engine_url);catalog=Client(catalog_url);health=catalog.call('/health')
    if not health.get('ready')or not str(health.get('storage',{}).get('dataDirectory','')).startswith('/tmp/love2gathering-mechanics-'):raise ValueError('Ready isolated mechanics catalog required')
    if not engine.call('/health').get('ok'):raise ValueError('Owned XMage bridge not ready')
    if isinstance(generation,(str,Path)):generation=json.loads(Path(generation).read_text())
    decks={d['id']:json.loads(Path(d['path']).read_text())for d in generation['decks']}
    results=[];old=None
    for identifier,own,opponent,policy,count in CASES:
        result,old=one_game(engine,catalog,decks[own],decks[opponent],outputdir/identifier,identifier=identifier,policy=policy,players=count,budget_seconds=budget_seconds,old_action=old)
        result['humanDeck']=own;result['opponentDeck']=opponent;result['driverPolicy']=policy
        result['expectedCompletion']='partial seat rotation'if count>2 else'native deckout'if identifier=='P03'else'native damage result'
        write_json(outputdir/identifier/'result.json',result);results.append(result)
        execution=engine.call('/session/state').get('execution',{})
        if execution.get('threadAlive')and execution.get('stopRequested'):
            break
    report={'sourceSha256':source_hash,'evidenceType':'production_game','results':results,'completedNativeGames':sum(r['nativeCompleted']for r in results),'statuses':{s:sum(r['status']==s for r in results)for s in set(r['status']for r in results)},'seedSupport':'No production shuffle seed asserted; concrete normal-start deck/action/native/replay traces retained','minimumCompletedMet':sum(r['nativeCompleted']for r in results)>=3}
    write_json(outputdir/'production-summary.json',report);return report

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-url',required=True)
    parser.add_argument('--catalog-url',required=True)
    parser.add_argument('--generation',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--budget-seconds',type=float,default=120,help='Native drive budget per game; replay is separately bounded to 30s and total to drive+50s')
    args=parser.parse_args(argv)
    if args.budget_seconds<=0:parser.error('The native drive budget must be positive')
    report=run_production(args.engine_url,args.catalog_url,args.generation,args.output,args.budget_seconds)
    print(json.dumps({key:report[key]for key in('completedNativeGames','statuses','minimumCompletedMet')}),flush=True)
    return 0 if len(report['results'])==len(CASES) and report['minimumCompletedMet']and all(r['status']=='pass'for r in report['results'])else 1

if __name__=='__main__':raise SystemExit(main())
