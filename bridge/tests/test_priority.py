#!/usr/bin/env python3
"""Exercise priority controls through a real native game on an owned isolated bridge.
All-Plains test decks use ordinary production loading/format validation; no zones are injected.
"""
import argparse
import json
import time
import threading
import urllib.error
import urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17402')
    parser.add_argument('--recording-port', type=int, default=0)
    parser.add_argument('--output', type=Path, default=ROOT/'bridge/tests/priority-http-report.json')
    args = parser.parse_args()
    coherence_reads = [0]
    coherence_failures = []
    def validate_state(state):
        prompt = state.get('prompt')
        if prompt and prompt.get('priority'):
            controls = state.get('priority', {})
            assert controls.get('canEndTurn') is True and not controls.get('pending'), 'Consumed or refreshing priority prompt was exposed: ' + json.dumps(state.get('priority'))
        return state
    def call(path, value=None):
        request = urllib.request.Request(args.url+path, data=None if value is None else json.dumps(value).encode(), headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response: return validate_state(json.load(response))
        except urllib.error.HTTPError as error: raise RuntimeError(error.read().decode()) from error
    def wait(predicate, text):
        deadline = time.monotonic()+25
        while time.monotonic()<deadline:
            state=call('/session/state')
            assert not state.get('error'), state.get('error')
            if predicate(state): return state
            time.sleep(.01)
        raise AssertionError(text+': '+json.dumps(state.get('prompt'))+'; '+json.dumps(state.get('priority')))
    def answer(state, choice):
        p=state['prompt']
        return call('/session/action', {'promptId':p['id'], 'type':choice['responseType'], 'value':choice.get('value',choice['id'])})
    def done(state): return answer(state,next(c for c in state['prompt']['choices'] if c['id']=='done'))
    def reject(path, value):
        try: call(path,value)
        except RuntimeError: return True
        raise AssertionError('Invalid priority request accepted')
    checks={}; failure=None; samples=[]; replay_id=None
    stop_reading = threading.Event()
    def reader():
        while not stop_reading.is_set():
            try:
                call('/session/state'); coherence_reads[0] += 1
            except Exception as error:
                coherence_failures.append(str(error))
            stop_reading.wait(.002)
    readers = [threading.Thread(target=reader, daemon=True) for _ in range(3)]
    for worker in readers: worker.start()
    try:
        deck={'name':'Priority production test','format':'Modern','main':[{'name':'Plains','count':60}], 'sideboard':[], 'commander':[]}
        call('/session/start',{'format':'Modern','recordingPort':args.recording_port,'startingSeatId':'local','playerName':'Priority Human','botName':'Priority Bot','deck':deck,'botDeck':deck,
                               'priority':{'autoPass':True,'stops':{'own':['PRECOMBAT_MAIN'],'opponent':['END_TURN']}}})
        state=wait(lambda s: s.get('prompt'), 'No native pregame prompt')
        human=next(p for p in state['players'] if p['human'])
        checks['endTurnRejectedDuringPregame']=reject('/session/priority',{'command':'end_turn','promptId':state['prompt']['id']})
        while not state['prompt'].get('priority'):
            p=state['prompt'];choices=p['choices']
            if p.get('mulligan'): choice=p['mulligan']['keepChoice']
            else: choice=next((c for c in choices if c['id']==human['id']),choices[0])
            old=p['id'];answer(state,choice)
            state=wait(lambda s: s.get('prompt') and s['prompt']['id']!=old,'Pregame did not progress')
        policy=state['priority'];replay_id=state.get('replayId')
        checks['persistedStopsAppliedBeforeStart']=policy['stops']=={'own':['PRECOMBAT_MAIN'],'opponent':['END_TURN']} and policy['stopStep']=='PRECOMBAT_MAIN'
        checks['emptyInitialUpkeepAutoPassed']=policy['autoPassCount']>=1  # Native duel first player skips the first draw step.
        checks['visibleOwnMainStop']=policy['paused'] and policy['reason']=='stop' and policy['stopPlayerId']==human['id']
        checks['manaOnlyPolicyExposed']=policy.get('manaOnlyPolicySupported') is True and policy.get('passWithOnlyMana') is False
        old=state['prompt']['id'];call('/session/priority',{'command':'configure','passWithOnlyMana':True})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'Mana-only policy did not wake native priority')
        checks['manaOnlyPreferenceAcknowledged']=state['priority'].get('passWithOnlyMana') is True and state['priority']['reason']=='stop'
        old=state['prompt']['id'];call('/session/priority',{'command':'configure','passWithOnlyMana':False})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'Restoring mana-only policy did not wake native priority')
        checks['manaOnlyDoesNotBypassStops']=state['priority'].get('passWithOnlyMana') is False and state['priority']['stopStep']=='PRECOMBAT_MAIN'
        checks['staleEndTurnRejected']=reject('/session/priority',{'command':'end_turn','promptId':state['prompt']['id']-1})
        checks['staleActionRejected']=reject('/session/action',{'type':'boolean','value':True,'promptId':-999999})
        checks['malformedActionRejected']=reject('/session/action',{'type':'uuid','value':'not-a-uuid','promptId':state['prompt']['id']})
        old=state['prompt']['id'];call('/session/priority',{'command':'end_turn','promptId':old})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'End Turn did not advance')
        checks['endTurnCancelledAtNewTurnWithoutEmptyQuestion']=state['priority']['reason']=='stop' and state['priority']['stopStep']=='END_TURN' and state['priority']['stopPlayerId']!=human['id'] and not state['priority']['yielding']
        checks['endTurnDidNotPlayLand']=not next(p for p in state['players'] if p['human'])['battlefield']
        checks['emptyOpponentEndStepBluffStop']=state['priority']['reason']=='stop' and state['priority']['stopStep']=='END_TURN' and state['priority']['stopPlayerId']!=human['id'] and state['priority']['meaningfulActionCount']==0
        samples.append(state['priority']);old=state['prompt']['id']
        call('/session/priority',{'command':'configure','autoPass':False,'stops':{'own':[],'opponent':[]}})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'Full control did not wake priority')
        checks['fullControlHoldsEmptyPriority']=state['priority']['reason']=='manual' and state['priority']['paused']
        checks['invalidStopRejected']=reject('/session/priority',{'command':'configure','stops':{'opponent':['NOT_A_STEP']}})
        old=state['prompt']['id'];call('/session/priority',{'command':'configure','autoPass':True})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'Automatic priority did not resume')
        checks['nativeLandActionHeld']=state['priority']['reason']=='action' and state['priority']['meaningfulActionCount']>0
        old=state['prompt']['id'];call('/session/priority',{'command':'cancel'})
        state=wait(lambda s:s.get('prompt') and s['prompt']['id']!=old,'Cancel did not safely refresh priority')
        checks['cancelPreservesAvailableAction']=state['priority']['reason']=='action' and not state['priority']['yielding']
        samples.append(state['priority'])
        if args.recording_port:
            assert call('/session/replay/save',{}).get('saved')
            base=f'http://127.0.0.1:{args.recording_port}/replays/{replay_id}'
            with urllib.request.urlopen(base+'/events?limit=500') as response: events=json.load(response)['events']
            actions=[e['data'].get('input',{}) for e in events if e['type']=='action']
            checks['automaticAndExplicitPriorityRecorded']=any(a.get('type')=='auto_priority' for a in actions) and any(a.get('type')=='priority' for a in actions)
            checks['rejectedAttemptsNotRecorded']=not any(a.get('promptId')==-999999 or a.get('value')=='not-a-uuid' for a in actions)
        assert all(checks.values()), [k for k,v in checks.items() if not v]
    except Exception as error: failure=f'{type(error).__name__}: {error}'
    finally:
        call('/session/stop',{})
        stop_reading.set()
        for worker in readers: worker.join(35)
    checks['coherentPrioritySnapshots']=not coherence_failures and coherence_reads[0]>0
    if coherence_failures: failure='Snapshot coherence: '+coherence_failures[0]
    report={'passed':failure is None and all(checks.values()),'kind':'Real native production game, HTTP controls and ordinary validated all-Plains decks; no injected game state or frontend UI', 'checks':checks,'concurrentSnapshotReads':coherence_reads[0],'snapshotFailures':coherence_failures,'failure':failure,'replayId':replay_id,'prioritySamples':samples}
    args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return not report['passed']
if __name__=='__main__':raise SystemExit(main())
