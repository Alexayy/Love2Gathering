#!/usr/bin/env python3
"""Actual one-human/seven-bot draft through an explicitly isolated desktop gateway.

Creates and closes only its own room. No coordinator credentials or synthetic
cards/state; native packs, bot picks/decks, Limited validation and pairing.
"""
import argparse,json,time,traceback,urllib.request,urllib.error,urllib.parse
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',required=True);p.add_argument('--timeout',type=float,default=300);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 u=urllib.parse.urlsplit(a.url);assert u.hostname in('localhost','127.0.0.1')and u.port and u.port>=17400,'Use owned isolated gateway'
 deadline=time.monotonic()+a.timeout;started=time.monotonic();checks=[];connection=None;closed=False;seen=set();accepted=0;stale=False;report={'passed':False,'scope':'Real desktop gateway, one human plus seven native bot draft seats, real packs/picks, native bot Limited deck builds, submitted human pool instances, actual first-round paired games. No synthetic state, rules, direct coordinator access, or acquired assets.'}
 def check(ok,label):
  assert ok,label;checks.append(label);print('BOT DRAFT LIVE PASS',label,flush=True)
 def call(path,body=None,cleanup=False):
  assert cleanup or time.monotonic()<deadline,'Bot draft acceptance timed out'
  req=urllib.request.Request(a.url+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json','Accept':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=20)as r:return json.load(r)
  except urllib.error.HTTPError as e:
   try:message=json.load(e).get('error','Gateway request rejected')
   except Exception:message='Gateway request rejected'
   raise ValueError(str(e.code)+': '+message)from None
 def cmd(op='',body=None,cleanup=False):return call('/client/rooms/'+connection+('/'+op if op else''),body,cleanup)
 def current():
  v=cmd();assert not v['room'].get('error'),v['room'].get('error');return v
 try:
  caps=call('/client/capabilities');native=caps['draft']
  check(native.get('botSupport')is True and native['minPlayers']<=8<=native['maxPlayers'],'Installed gateway advertises native bot support and eight-seat capacity')
  modes={i['id']for i in native['modes']};check('booster'in modes,'Booster procedure is actually offered by installed engine')
  available={i['code'].upper()for i in native['sets']};assert{'M21','M20','M19'}<=available
  config={'kind':'draft','name':'Owned bot draft acceptance','maxPlayers':8,'playerName':'Bot Draft Tester','draft':{'mode':'booster','profile':'Limited','pairing':'swiss','sets':['M21','M20','M19'],'timing':'PROFESSIONAL'}}
  initial=call('/client/rooms',config);connection=initial['connectionId'];seat=initial['participantId']
  cmd('bots',{'count':7});cmd('ready',{'ready':True});before=current()
  check(len(before['room']['members'])==8 and sum(i['bot']for i in before['room']['members'])==7 and before['room']['canStart'],'One human plus seven native bots fill and ready the actual private room')
  cmd('start',{});last_phase=None;first=None
  while time.monotonic()<deadline:
   v=current();phase=v['room']['phase']
   if phase!=last_phase:print('BOT DRAFT PHASE',phase,'after',round(time.monotonic()-started,2),'s',flush=True);last_phase=phase
   own=v.get('draft')
   if own:
    assert not own.get('error'),own.get('error')
    assert all(not any(k in row for k in('pack','pool','deck','selection'))for row in own['players']),'Private bot packs/pools/decks leaked'
    if own.get('status')in('building','ready')and phase=='building':break
    token=own.get('pickToken')
    if own.get('status')=='drafting'and token and own['pack']and token not in seen:
     seen.add(token);pick={'pickToken':token,'cardId':own['pack'][0]['id']};cmd('draft/pick',pick);accepted+=1
     if first is None:first={'packSize':len(own['pack']),'packNumber':own.get('packNumber'),'pickNumber':own.get('pickNumber')}
     if not stale:
      try:cmd('draft/pick',pick)
      except ValueError:stale=True
      assert stale,'Already used native pick token was accepted'
     if accepted%15==0:print('BOT DRAFT HUMAN PICKS',accepted,flush=True)
   time.sleep(.01)
  else:raise AssertionError('Actual native bot draft did not reach building')
  own=v['draft'];check(accepted==45 and len(own['pool'])==45,'The human completes45 actual offered picks across three native packs')
  check(stale,'A used pick token cannot select from another pack')
  bots=[i for i in own['players']if i.get('seatId',i.get('id'))!=seat]
  check(len(bots)==7 and all(not i['human']and i['poolCount']==45 and i['ready']for i in bots),'All seven native bots finish45-card pools and submit native-validated Limited decks')
  check(all(not any(k in i for k in('pack','pool','deck','selection'))for i in bots),'Bot public status never reveals their private pack, pool, deck or selection')
  check(own['minDeckSize']==40 and any(i['name']=='Forest'for i in own['basicLands']),'Human builder receives native40-card minimum and offered basic lands')
  selected=[i['id']for i in own['pool'][:23]];submitted=cmd('draft/deck',{'main':selected,'basics':{'Forest':17}});deck=submitted['draft']['deck']
  check(sum(i['count']for i in deck['main'])==40 and set(submitted['draft']['selection']['main'])==set(selected),'Native Limited accepts exact drafted instances plus offered basics and retains selection')
  ready=current();check(ready['room']['canStart']and all(i['ready']for i in ready['draft']['players']),'All eight validated decks enable actual native pairing')
  cmd('start',{});answered=set();game=None
  while time.monotonic()<deadline:
   v=current()
   if v['room']['phase']=='playing'and v.get('game'):
    game=cmd('game/state');assert not game.get('error'),game.get('error')
    if game.get('phase')=='Precombat Main':break
    prompt=game.get('prompt')
    if prompt and prompt['id']not in answered:
     choices=prompt.get('choices',[])
     if prompt.get('mulligan'):choice=prompt['mulligan']['keepChoice']
     elif'starting player'in prompt.get('message','').lower():
      player=next(i for i in game['players']if i['human']);choice=next(i for i in choices if i['id']==player['id'])
     else:choice=next((i for i in choices if i['id']=='done'),choices[0]if choices else None)
     assert choice,'Uncovered native opening choice';answered.add(prompt['id']);cmd('game/action',{'expectedGameId':game['gameId'],'promptId':prompt['id'],'type':choice['responseType'],'value':choice.get('value',choice['id'])})
   time.sleep(.02)
  else:raise AssertionError('Native human/bot paired game did not reach first main phase')
  human=next(i for i in game['players']if i['human']);opponent=next(i for i in game['players']if not i['human'])
  check(len(game['players'])==2 and human['libraryCount']+human['handCount']==40 and len(human['hand'])==human['handCount']==7,'Actual paired Limited game loads the submitted human40-card deck and full private hand')
  check(opponent['hand']==[]and opponent['libraryCount']+opponent['handCount']>=40,'The actual native bot deck is playable and its hand remains hidden')
  check(len(v['room']['matches'])==4 and v['draft']['tournament']['round']==1,'Eight-seat native Swiss produces four actual first-round game pairings')
  report.update(passed=True,acceptedHumanPicks=accepted,botCount=7,poolSizes=[i['poolCount']for i in own['players']],firstOfferedPack=first,nativeGameCount=len(v['room']['matches']),nativeGameId=game['gameId'],botDeckSize=opponent['libraryCount']+opponent['handCount'])
 except Exception as e:report.update(error=str(e),traceback=traceback.format_exc())
 finally:
  if connection:
   try:cmd('leave',{},True);closed=True
   except Exception as e:report['cleanupError']=str(e)
  report.update(allCreatedConnectionsClosed=closed,seconds=round(time.monotonic()-started,3),checks=checks);report['passed']=report['passed']and closed;a.output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':report.get('error'),'allCreatedConnectionsClosed':closed},indent=2),flush=True);return 0 if report['passed']else 1
if __name__=='__main__':raise SystemExit(main())
