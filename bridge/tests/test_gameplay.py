#!/usr/bin/env python3
"""Play a simple mono-red 1v1 through real XMage prompts on an isolated bridge.
This policy is a test driver, not a replacement game engine or product bot.
"""
import argparse, json, re, time, urllib.error, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://127.0.0.1:17372')
    parser.add_argument('--timeout',type=float,default=180)
    parser.add_argument('--recording-port',type=int,default=0,help='Catalog API v3 port; zero disables recording only for this test')
    parser.add_argument('--output',type=Path,default=ROOT/'bridge/tests/gameplay-report.json')
    args=parser.parse_args()
    def call(path,body=None):
        request=urllib.request.Request(args.url+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
        except urllib.error.HTTPError as error:raise RuntimeError(f'{path}: {error.code}: {error.read().decode()}') from error
    health=call('/health')
    assert health.get('engine')=='XMage' and health.get('ok')
    cards=[('Mountain',24),('Goblin Guide',4),('Monastery Swiftspear',4),('Ghitu Lavarunner',4),('Lightning Bolt',4),('Lava Spike',4),('Shock',4),('Lightning Strike',4),('Searing Spear',4),('Skewer the Critics',4)]
    deck={'name':'Engine smoke - Mono Red','format':'Modern','main':[{'name':name,'count':count} for name,count in cards],'sideboard':[],'commander':[]}
    assert sum(x['count'] for x in deck['main'])==60
    state=call('/session/start',{'format':'Modern','recordingPort':args.recording_port,'playerName':'Smoke Human','botName':'XMage Smoke Bot','deck':deck,'botDeck':deck,'settings':{'manualTriggers':False,'autoMana':True}})
    evidence={'humanPlayedLand':False,'botPlayedLand':False,'humanCastSpell':False,'botCastSpell':False,'humanSpellResolved':False,'botSpellResolved':False,'lifeChanged':False,'completedGame':False}
    actions=[];logs=[];observed=set();last_id=None;land_turn=None;tried=set();deadline=time.monotonic()+args.timeout;failure=None;turn=0
    def cmc(card):
        parts=re.findall(r'\{([^}]+)\}',card.get('manaCost',''))
        return sum(int(x) if x.isdigit() else 1 for x in parts)
    try:
        while time.monotonic()<deadline:
            if 'revision' in state:observed.add(state['revision'])
            if state.get('error'):raise RuntimeError(state['error'])
            turn=max(turn,state.get('turn',0))
            for entry in state.get('log',[]):
                line=entry.get('text','') if isinstance(entry,dict) else str(entry)
                if line not in logs:logs.append(line)
            critical=next((line for line in logs if 'critical error' in line.lower() or 'game error occurred' in line.lower()),None)
            if critical:raise RuntimeError(critical)
            players=state.get('players',[])
            if len(players)!=2:
                time.sleep(.02);state=call('/session/state');continue
            human=next(p for p in players if p['human']);bot=next(p for p in players if not p['human'])
            for who,player in (('human',human),('bot',bot)):
                if any('Land' in c.get('type','') for c in player.get('battlefield',[])):evidence[who+'PlayedLand']=True
                if any('Instant' in c.get('type','') or 'Sorcery' in c.get('type','') for c in player.get('graveyard',[])):evidence[who+'SpellResolved']=True
            for who,name in (('human',human['name']),('bot',bot['name'])):
                if any(name in line and (' casts ' in line.lower() or 'cast ' in line.lower()) for line in logs):evidence[who+'CastSpell']=True
            evidence['lifeChanged'] |= all(p.get('handCount',0)>0 for p in players) and any(p['life']!=20 for p in players)
            if state.get('running') is False:
                evidence['completedGame']=any(p.get('won') for p in players) and any(p.get('lost') for p in players)
                break
            prompt=state.get('prompt')
            if not prompt or prompt['id']==last_id:
                time.sleep(.02);state=call('/session/state');continue
            choices=prompt.get('choices',[]);ptype=prompt['type'];message=prompt.get('message','').lower();chosen=None;response=None
            indexed={c['id']:c for c in choices};own_turn=state.get('activePlayerId')==human['id'];turn_key=state.get('turn',0)
            if ptype=='select':
                if 'select attackers' in message and 'special' in indexed:chosen=indexed['special']
                elif 'select blockers' in message or 'select attackers' in message:chosen=indexed.get('done')
                elif own_turn and ('main' in state.get('phase','').lower() or 'main' in state.get('step','').lower()) and not state.get('stack'):
                    if land_turn!=turn_key:
                        land=next((c for c in human['hand'] if 'Land' in c.get('type','') and c['id'] in indexed),None)
                        if land:
                            chosen=indexed[land['id']];land_turn=turn_key
                    if chosen is None:
                        available=sum(1 for c in human.get('battlefield',[]) if 'Land' in c.get('type','') and not c.get('tapped'))+sum(human.get('mana',{}).values())
                        candidates=sorted((c for c in human['hand'] if 'Land' not in c.get('type','') and c['id'] in indexed and cmc(c)<=available and (c['id'],turn_key) not in tried),key=cmc)
                        if candidates:
                            chosen=indexed[candidates[0]['id']];tried.add((candidates[0]['id'],turn_key))
                if chosen is None:chosen=indexed.get('done')
            elif ptype=='play_mana':
                chosen=next((c for c in choices if c.get('responseType')=='mana'),None)
                if chosen is None:
                    land=next((c for c in human.get('battlefield',[]) if 'Land' in c.get('type','') and not c.get('tapped') and c['id'] in indexed),None)
                    if land:chosen=indexed[land['id']]
                if chosen is None:chosen=indexed.get('done')
            elif ptype=='ask':
                desired=False if 'mulligan' in message else True
                chosen=next((c for c in choices if c.get('value') is desired),None)
            elif ptype in ('pick_target','target','choose_target'):
                chosen=indexed.get(human['id'] if 'starting player' in message else bot['id'])
                if chosen is None:chosen=next((c for c in choices if c.get('responseType')=='uuid'),None)
                if chosen is None:chosen=indexed.get('done')
            elif ptype=='order':response={'type':'order','value':[c['id'] for c in choices]}
            elif ptype in ('get_amount','amount'):
                response={'type':'integer','value':prompt.get('min',0)}
            if response is None:
                if chosen is None and choices:chosen=choices[0]
                if chosen:response={'type':chosen['responseType'],'value':chosen.get('value',chosen['id'])}
            if response is None:raise RuntimeError('Unhandled prompt '+json.dumps(prompt))
            response['promptId']=prompt['id'];last_id=prompt['id']
            actions.append({'turn':state.get('turn'),'step':state.get('step'),'message':prompt.get('message'),'choice':chosen.get('label') if chosen else response['value'],'type':response['type']})
            if len(actions)<=12:print(str(state.get('turn'))+' '+prompt.get('message','')+' -> '+str(chosen.get('label') if chosen else response['value']),flush=True)
            state=call('/session/action',response)
            if len(actions)%50==0:print(f"{len(actions)} actions; turn {turn}; life {human['life']} / {bot['life']}",flush=True)
            if len(actions)>1500:raise RuntimeError('Exceeded action budget')
        if not evidence['completedGame'] and time.monotonic()>=deadline:failure='Timed out before game completion'
    except Exception as error:failure=str(error)
    finally:
        call('/session/stop',{})
    passed=all(evidence.values()) and failure is None
    report={'passed':passed,'engine':health,'evidence':evidence,'failure':failure,'turns':turn,'actionCount':len(actions),'observedFrameCount':len(observed),'replayId':state.get('replayId'),'replayStatus':state.get('replayStatus'),'recordingError':state.get('recordingError'),'finalPlayers':[{k:p.get(k) for k in ('name','life','won','lost','handCount','libraryCount')} for p in state.get('players',[])],'log':logs,'actions':actions}
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'passed':passed,'evidence':evidence,'failure':failure,'turns':turn,'actions':len(actions)},indent=2))
    return not passed
if __name__=='__main__':raise SystemExit(main())
