#!/usr/bin/env python3
"""Real SQLite profile and two-human-plus-bot native room propagation.

Requires explicitly isolated catalog/gateway services. Uses public client room
routes, restores its temporary saved profile, closes only its created room, and
never reads a coordinator token or writes to default user storage.
"""
import argparse
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--catalog-url',default='http://127.0.0.1:17460');parser.add_argument('--room-url',default='http://127.0.0.1:17463');parser.add_argument('--output',type=Path,default=ROOT/'tests/profile-live-report.json');args=parser.parse_args()
    for url in(args.catalog_url,args.room_url):
        origin=urllib.parse.urlsplit(url);assert origin.hostname in('127.0.0.1','localhost')and origin.port and origin.port>=17400,'Use explicitly isolated services'
    checks,clients=[],[];saved=None;report={'passed':False,'scope':__doc__};deadline=time.monotonic()+120
    def check(value,label):assert value,label;checks.append(label);print('PROFILE LIVE PASS',label,flush=True)
    def call(url,path,body=None,method=None):
        request=urllib.request.Request(url+path,data=None if body is None else json.dumps(body).encode(),method=method,headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=30)as response:return json.load(response)
    def command(client,operation='',body=None):return call(args.room_url,'/client/rooms/'+client['connection']+('/'+operation if operation else''),body)
    def wait(fn):
        while time.monotonic()<deadline:
            result=fn()
            if result:return result
            time.sleep(.02)
        raise AssertionError('Native profile acceptance timed out')
    def reference(item):return{'oracleId':item['oracle_id'],'printingId':item['printing_id'],'face':item['face'],'name':item['name']}
    try:
        health=call(args.catalog_url,'/health');assert health['apiVersion']>=6 and health['ready']and health['storage']['dataDirectory'].startswith('/tmp/'),'Temporary ready profile catalog required'
        saved=call(args.catalog_url,'/profile')
        avatar=reference(call(args.catalog_url,'/gallery?q=Angel%20of%20Vitality&limit=1')['items'][0]);mat=reference(call(args.catalog_url,'/gallery?q=Krenko&limit=1')['items'][0])
        profile=call(args.catalog_url,'/profile',{'name':'Profile Host','avatar':avatar,'playmat':mat},'PUT');check(call(args.catalog_url,'/profile')==profile,'Exact real catalog avatar/playmat identities persist through actual SQLite HTTP')
        malformed=dict(profile,life=999)
        try:call(args.catalog_url,'/profile',malformed,'PUT');raise AssertionError('Profile life override was accepted')
        except urllib.error.HTTPError as exc:check(exc.code==400,'Profile cannot override native HP')
        created=call(args.room_url,'/client/rooms',{'kind':'constructed','name':'Profile room acceptance','format':'Commander','maxPlayers':3,'playerName':'Legacy host','profile':profile,'priority':{'autoPass':True,'stops':{'own':['PRECOMBAT_MAIN'],'opponent':['PRECOMBAT_MAIN']}}})
        clients.append({'connection':created['connectionId'],'seat':created['participantId']})
        guest_profile={'name':'Profile Guest','avatar':mat,'playmat':avatar}
        joined=call(args.room_url,'/client/join',{'name':'Legacy guest','code':created['room']['inviteCode'],'profile':guest_profile,'priority':{'autoPass':True,'stops':{'own':['PRECOMBAT_MAIN'],'opponent':['PRECOMBAT_MAIN']}}})
        clients.append({'connection':joined['connectionId'],'seat':joined['participantId']})
        check(all(member['profile']['name']==member['name']for member in joined['room']['members']),'Code-only room join preserves public per-seat profile names')
        command(clients[0],'bots',{'count':1})
        deck=json.loads((ROOT/'decks/commander-krenko-goblins.json').read_text())
        for client in clients:command(client,'deck',{'deck':deck});command(client,'ready',{'ready':True})
        command(clients[0],'start',{})
        wait(lambda:(lambda r:r if r['room']['phase']=='playing'and(r.get('game')or{}).get('gameId')else None)(command(clients[0])))
        answered=set();states={}
        while len(states)<2 and time.monotonic()<deadline:
            for client in clients:
                state=command(client,'game/state');assert not state.get('error'),state.get('error')
                if state.get('phase')=='Precombat Main':states[client['seat']]=state;continue
                p=state.get('prompt');key=(client['seat'],p and p['id'])
                if not p or key in answered:continue
                if p.get('mulligan'):choice=p['mulligan']['keepChoice']
                else:
                    host=next(player for player in state['players']if player['seatId']==clients[0]['seat']);choice=next((c for c in p['choices']if c['id']==host['id']),next((c for c in p['choices']if c['id']=='done'),p['choices'][0]))
                answered.add(key);command(client,'game/action',{'expectedGameId':state['gameId'],'promptId':p['id'],'type':choice['responseType'],'value':choice.get('value',choice['id'])})
            time.sleep(.01)
        assert len(states)==2,'Both real human perspectives must reach native main'
        for client in clients:
            state=states[client['seat']];profiles={p['name']:p['profile']for p in state['players']}
            check(profiles['Profile Host']==profile and profiles['Profile Guest']==guest_profile,'Native human perspective sees both exact public avatar/playmat references')
            check(all(p['life']==40 for p in state['players']),'Native Commander owns all three40-life totals')
            check(all(p['hand']==[]for p in state['players']if not p['human']),'Public profile does not reveal another human/bot hand')
        state=states[clients[0]['seat']];bot=next(p for p in state['players']if not p['isHuman'])
        check(bot['avatarCard']['name']==deck['commander'][0]['name']and not bot['avatarCard'].get('id'),'Bot portrait uses its native commander without a hidden card instance ID')
        replay_id=state['replayId'];game_id=state['gameId']
        for client in clients:command(client,'game/action',{'expectedGameId':game_id,'type':'concede','value':True})
        wait(lambda:(lambda r:r if(r.get('game')or{}).get('running')is False else None)(command(clients[0])))
        recording=wait(lambda:(lambda r:r if r['status']=='completed'else None)(call(args.catalog_url,'/replays/'+replay_id)))
        participants=recording['metadata']['players'];by_name={p['name']:p for p in participants}
        check(by_name['Profile Host']['profile']==profile and by_name['Profile Guest']['profile']==guest_profile,'Completed authoritative recording preserves public profiles of both human participants')
        check(recording['result']['completed']and len(recording['result']['winnerIds'])==1,'Native completion remains authoritative with presentation profiles')
        report['passed']=True;report['replayId']=replay_id;report['profileIdentity']={'avatar':avatar,'playmat':mat}
    except Exception as exc:report['error']=str(exc)
    finally:
        cleanup=[]
        for client in clients[1:]+clients[:1]:
            try:command(client,'leave',{})
            except Exception as exc:cleanup.append(type(exc).__name__)
        if saved is not None:
            try:call(args.catalog_url,'/profile',saved,'PUT')
            except Exception as exc:cleanup.append(type(exc).__name__)
        report['checks']=checks;report['cleanupErrors']=cleanup
        if cleanup:report['passed']=False
        args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':report.get('error'),'cleanupErrors':report['cleanupErrors']},indent=2));return 0 if report['passed']else 1


if __name__=='__main__':raise SystemExit(main())
