#!/usr/bin/env python3
"""Load each starter into the running real XMage bridge and inspect opening zones.
This deliberately replaces the active engine session. Run on a test bridge port.
"""
import argparse, json, time, urllib.error, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://127.0.0.1:17372',help='Use an isolated running bridge; active session will be replaced')
    parser.add_argument('--output',type=Path,default=ROOT/'engine-load-report.json')
    args=parser.parse_args()
    def call(path,body=None):
        request=urllib.request.Request(args.url+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'{path}: {error.code}: {error.read().decode()}') from error
    health=call('/health')
    if not health.get('ok') or health.get('engine')!='XMage':raise RuntimeError('Expected a real XMage bridge')
    manifest=json.loads((ROOT/'library.json').read_text())
    results=[]
    for item in manifest:
        deck=json.loads((ROOT/(item['id']+'.json')).read_text())
        result={'id':deck['id'],'format':deck['format'],'passed':False}
        try:
            state=call('/session/start',{'format':deck['format'],'recordingPort':0,'playerName':'Load test','botName':'Load test bot','deck':deck,'botDeck':deck,'settings':{'manualTriggers':False,'autoMana':True}})
            deadline=time.monotonic()+25
            answered=set()
            while time.monotonic()<deadline:
                if state.get('error'):raise RuntimeError(state['error'])
                if state.get('running') is False:raise RuntimeError('Game ended during setup: '+'; '.join(str(e.get('text','')) if isinstance(e,dict) else str(e) for e in state.get('log',[])[-4:]))
                players=state.get('players',[])
                ready=len(players)==2 and all(p.get('handCount',0)>0 for p in players)
                if deck['format']=='Commander':ready=ready and all(len(p.get('command',[]))==1 for p in players)
                if ready:
                    expected=99 if deck['format']=='Commander' else 60
                    for player in players:
                        actual=player['libraryCount']+player['handCount']+len(player.get('graveyard',[]))+len(player.get('battlefield',[]))
                        if actual!=expected:raise AssertionError(f"{player['name']}: expected {expected} cards outside command zone, got {actual}")
                    human=next(p for p in players if p['human'])
                    bot=next(p for p in players if not p['human'])
                    if len(human['hand'])!=human['handCount']:raise AssertionError('Human hand is not fully visible')
                    if bot['hand']:raise AssertionError('Bot hidden hand exposed')
                    result.update(passed=True,opening_hand=human['handCount'],library=human['libraryCount'],commanders=len(human.get('command',[])),prompt=state.get('prompt',{}).get('type') if state.get('prompt') else None)
                    break
                prompt=state.get('prompt')
                if prompt and prompt['id'] not in answered:
                    choices=prompt.get('choices',[])
                    if choices:
                        # Only pregame prompts are answered. Prefer keeping a hand.
                        preferred=next((c for c in choices if c.get('value') is False),choices[0]) if 'mulligan' in prompt.get('message','').lower() else next((c for c in choices if c.get('label','').lower() in ('yes','keep','keep hand')),choices[0])
                        call('/session/action',{'promptId':prompt['id'],'type':preferred['responseType'],'value':preferred.get('value',preferred['id'])})
                        answered.add(prompt['id'])
                time.sleep(.05)
                state=call('/session/state')
            if not result['passed']:raise TimeoutError('No initialized opening hand and command zone before timeout')
        except Exception as error:
            result['error']=str(error)
        finally:
            call('/session/stop',{})
        results.append(result)
        print(deck['id']+': '+('PASS' if result['passed'] else result['error']),flush=True)
    report={'engine':health,'decks':results,'passed':all(x['passed'] for x in results),'tested':'real XMage card instantiation, 1v1 bot startup, opening zones and hidden information; no full-game or AI-strategy claim'}
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(str(sum(x['passed'] for x in results))+'/'+str(len(results))+' real engine loads passed')
    return not report['passed']
if __name__=='__main__':raise SystemExit(main())
