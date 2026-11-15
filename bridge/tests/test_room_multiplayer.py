#!/usr/bin/env python3
"""Real two/four-human room games, isolated native registry, privacy and authoritative results.
Use an owned loopback test engine; this also replaces its ordinary practice session.
"""
import argparse
import json
import time
import uuid
import copy
import urllib.error
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://127.0.0.1:17402')
    parser.add_argument('--token-file',type=Path,default=ROOT/'.runtime/rooms-coordinator.token')
    parser.add_argument('--recording-port',type=int,default=17400)
    parser.add_argument('--output',type=Path,default=ROOT/'bridge/tests/room-multiplayer-http-report.json')
    args=parser.parse_args();token=args.token_file.read_text().strip();checks={};games=[];details=[];failure=None;start_bodies={}
    def call(path,value=None,authorized=True):
        headers={'Content-Type':'application/json'}
        if authorized:headers['Authorization']='Bearer '+token
        request=urllib.request.Request(args.url+path,data=None if value is None else json.dumps(value).encode(),headers=headers)
        try:
            with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
        except urllib.error.HTTPError as error:raise RuntimeError(str(error.code)+': '+error.read().decode()) from error
    def reject(path,value=None,authorized=True):
        try:call(path,value,authorized)
        except RuntimeError:return True
        raise AssertionError('Unauthorized/stale request accepted: '+path)
    def state(game,player):return call(f'/multiplayer/state?gameId={game}&playerId={player}')
    def wait(predicate,game,player,text):
        deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            current=state(game,player)
            assert not current.get('error'),current.get('error')
            if predicate(current):return current
            time.sleep(.01)
        raise AssertionError(text+': '+json.dumps(current.get('prompt')))
    def start(count,format='Commander',humans=None,record=True):
        humans=count if humans is None else humans
        main_count=99 if format=='Commander' else 40
        deck={'name':'Native room acceptance','main':[{'name':'Plains','count':main_count}],'sideboard':[],'commander':[{'name':'Giada, Font of Hope','count':1}] if format=='Commander' else []}
        seats=[]
        for i in range(count):
            seats.append({'seatId':f'seat-{i}','name':f'Room Player {i+1}','type':'human' if i<humans else 'bot','deck':deck,
                          'priority':{'autoPass':True,'stops':{'own':['END_TURN'] if i==0 else ['DRAW'] if i==1 else [],'opponent':[]}}})
        body={'format':format,'seats':seats,'recordingPort':args.recording_port if record and humans else 0,'recordingSeatId':'seat-0','idempotencyKey':'room-acceptance-'+str(uuid.uuid4())}
        result=call('/multiplayer/start',body)
        retried=call('/multiplayer/start',dict(reversed(list(body.items()))))
        checks['startRetryReturnsSameNativeGame']=retried['gameId']==result['gameId'] and retried['seats']==result['seats']
        conflict=copy.deepcopy(body);conflict['seats'][0]['name']+=' changed'
        checks['startRetryDifferentBodyRejected']=reject('/multiplayer/start',conflict)
        games.append(result['gameId']);start_bodies[result['gameId']]=body;return result
    def answer(game,player,prompt,choice):
        return call('/multiplayer/action',{'gameId':game,'playerId':player,'promptId':prompt['id'],'type':choice['responseType'],'value':choice.get('value',choice['id'])})
    try:
        checks['coordinatorAuthenticationRequired']=reject('/multiplayer/capabilities',authorized=False)
        capabilities=call('/multiplayer/capabilities')
        checks['actualNativeLimits']=next(g['maxPlayers'] for g in capabilities['games'] if g['format']=='Commander')==10 and next(g['maxPlayers'] for g in capabilities['games'] if g['format']=='Limited')==10
        practice={'main':[{'name':'Plains','count':60}],'sideboard':[],'commander':[]}
        call('/session/start',{'format':'Modern','recordingPort':0,'deck':practice,'botDeck':practice})
        practice_id=call('/session/state').get('gameId')
        if not practice_id:
            time.sleep(.1);practice_id=call('/session/state').get('gameId')
        for count,format,humans in ((2,'Limited',2),(4,'Limited',4),(4,'Commander',4),(4,'Commander',2)):
            opened=start(count,format,humans);game=opened['gameId'];members=[p for p in opened['seats'] if p['human']];ids=[p['playerId'] for p in members]
            last={};land_turns=set();asked=set();stops=set();actions=0;privacy_frames=0;cross=False;deadline=time.monotonic()+90
            while time.monotonic()<deadline:
                states=[state(game,player) for player in ids]
                for viewer,current in zip(ids,states):
                    assert not current.get('error'),current.get('error')
                    assert not current.get('projectionError'),current.get('projectionError')
                    players=current.get('players',[])
                    if players:
                        assert len(players)==count
                        assert sum(bool(p['human']) for p in players)==1
                        assert sum(bool(p['isHuman']) for p in players)==humans
                        assert all(p['isLocal']==p['human'] for p in players)
                        assert all(p['human'] or p['hand']==[] for p in players)
                        assert next(p for p in players if p['human'])['id']==viewer
                        serialized=json.dumps(current)
                        for other in states:
                            for player in other.get('players',[]):
                                if player['human'] and player['id']!=viewer:
                                    for card in player.get('hand',[]):assert card['id'] not in serialized,'Another human hand ID leaked'
                        privacy_frames+=1
                if states[0].get('turn',0)>=count+1 and len({p for p,t in land_turns})==humans:
                    break
                acted=False
                for player,current in zip(ids,states):
                    p=current.get('prompt')
                    if not p or p['id']==last.get(player):continue
                    choices=p.get('choices',[]);index={c['id']:c for c in choices};chosen=None
                    if p.get('priority'):
                        assert current['priority']['canEndTurn'] and not current['priority']['pending']
                        if p.get('priorityReason')=='stop':stops.add((player,current['priority']['stopStep']))
                    if not cross and len(ids)>1:
                        other=next(value for value in ids if value!=player)
                        cross=reject('/multiplayer/action',{'gameId':game,'playerId':other,'promptId':p['id'],'type':'boolean','value':True})
                    if 'starting player' in p.get('message','').lower():chosen=index.get(ids[0])
                    elif p.get('mulligan'):chosen=p['mulligan']['keepChoice'];asked.add(player)
                    elif p['type']=='select':
                        local=next(value for value in current['players'] if value['human']);turn=current.get('turn',0)
                        if current.get('activePlayerId')==player and (player,turn) not in land_turns:
                            land=next((c for c in local['hand'] if 'Land' in c.get('type','') and c['id'] in index),None)
                            if land:chosen=index[land['id']];land_turns.add((player,turn))
                        chosen=chosen or index.get('done')
                    elif p['type']=='ask':chosen=next((c for c in choices if c.get('value') is False),None)
                    chosen=chosen or index.get('done') or (choices[0] if choices else None)
                    assert chosen,'Unhandled native prompt '+str(p)
                    last[player]=p['id'];answer(game,player,p,chosen);actions+=1;acted=True
                if not acted:time.sleep(.01)
            else:raise AssertionError('Native room turn cycle timed out')
            assert len(asked)==humans and cross
            checks[f'{humans}humans_{count}seats_{format}_nativeRound']=True
            checks[f'{humans}humans_{count}seats_{format}_privateHands']=privacy_frames>0
            checks[f'{humans}humans_{count}seats_{format}_distinctPrompts']=len(set(last.values()))==len(last)
            checks['perHumanStops']=any(step=='END_TURN' for _,step in stops) and any(step=='DRAW' for _,step in stops)
            checks['ordinaryPracticeUnchanged']=call('/session/state').get('gameId')==practice_id
            checks['botCannotReadHumanPerspective']=reject(f'/multiplayer/state?gameId={game}&playerId=00000000-0000-0000-0000-000000000000')
            for member,current in zip(members,states):
                assert current['replayAvailable']==(member['seatId']=='seat-0')
                if member['seatId']!='seat-0':checks['guestReplaySaveRejected']=reject('/multiplayer/replay/save',{'gameId':game,'playerId':member['playerId']})
            saved=call('/multiplayer/replay/save',{'gameId':game,'playerId':ids[0]});assert saved['saved']
            replay_id=saved['replayId'];base=f'http://127.0.0.1:{args.recording_port}/replays/{replay_id}'
            with urllib.request.urlopen(base,timeout=30) as response:metadata=json.load(response)
            assert 'bots' not in metadata and 'botDeck' not in metadata,'Room replay metadata exposed an opponent deck'
            frames=0
            while True:
                with urllib.request.urlopen(base+f'/frames?limit=100&offset={frames}',timeout=30) as response:page=json.load(response)
                for event in page['frames']:
                    assert all(p['human'] or not p['hand'] for p in event['data']['players'])
                    assert sum(bool(p['human']) for p in event['data']['players'])==1
                frames+=len(page['frames'])
                if frames>=page['total']:break
            checks['designatedReplayPrivacy']=frames>0
            details.append({'humanPlayers':humans,'totalPlayers':count,'format':format,'nativeAnswers':actions,'privacyProjectionsChecked':privacy_frames,'replayFramesChecked':frames,'turn':states[0]['turn'],'replayId':replay_id})
            if humans==2 and count==2:
                other=start(2,'Limited',2,False)
                checks['parallelNativeGamesIndependent']=state(game,ids[0]).get('gameId')==game and reject('/multiplayer/action',{'gameId':other['gameId'],'playerId':ids[0],'type':'concede'})
                call('/multiplayer/stop',{'idempotencyKey':start_bodies[other['gameId']]['idempotencyKey']})
                checks['keyOnlyCleanupStopsAcceptedStart']=reject(f'/multiplayer/state?gameId={other["gameId"]}&playerId={other["seats"][0]["playerId"]}')
                checks['closedStartKeyCannotRecreate']=reject('/multiplayer/start',start_bodies[other['gameId']])
                # Concede the nonactive player while the other real human waits.
                active=next((player for player,current in zip(ids,states) if current.get('prompt')),ids[0]);conceding=next(player for player in ids if player!=active)
                call('/multiplayer/action',{'gameId':game,'playerId':conceding,'type':'concede'})
                deadline=time.monotonic()+15
                while time.monotonic()<deadline:
                    result=call(f'/multiplayer/result?gameId={game}')
                    if result['running'] is False:break
                    time.sleep(.02)
                assert result['running'] is False and len(result['winnerSeatIds'])==1,result
                checks['nonactiveHumanConcedeEndsNativeDuel']=True
            call('/multiplayer/stop',{'gameId':game})
            checks['stoppedGameCleanupRetryAccepted']=call('/multiplayer/stop',{'gameId':game})['alreadyStopped']
            checks['stoppedStartKeyCleanupRetryAccepted']=call('/multiplayer/stop',{'idempotencyKey':start_bodies[game]['idempotencyKey']})['alreadyStopped']
        cancelled=copy.deepcopy(next(iter(start_bodies.values())));cancelled['idempotencyKey']='cancel-before-start-'+str(uuid.uuid4())
        call('/multiplayer/stop',{'idempotencyKey':cancelled['idempotencyKey']})
        checks['closeBeforeStartBlocksLateRequest']=reject('/multiplayer/start',cancelled)
        botgame=start(2,'Limited',0,False);game=botgame['gameId'];deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            result=call(f'/multiplayer/result?gameId={game}')
            assert not result.get('error'),result
            if result['running'] is False:break
            time.sleep(.02)
        assert result['running'] is False and len(result['players'])==2 and len(result['winnerSeatIds'])==1,result
        checks['botOnlyNativePairingCompletes']=True
        checks['publicResultHasNoPrivateCards']=all('hand' not in p and 'battlefield' not in p for p in result['players'])
        assert all(checks.values()),[key for key,value in checks.items() if not value]
    except Exception as error:failure=f'{type(error).__name__}: {error}'
    finally:
        for game in games:
            try:call('/multiplayer/stop',{'gameId':game})
            except RuntimeError:pass
        call('/session/stop',{})
    report={'passed':failure is None and all(checks.values()),'kind':'Real native production room games and separate authenticated human projections; ordinary validated decks, no injected zones, UI or remote-network claim','checks':checks,'failure':failure,'games':details}
    args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return not report['passed']
if __name__=='__main__':raise SystemExit(main())
