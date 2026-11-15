#!/usr/bin/env python3
"""Native choice HTTP checks against the explicit test-only NativeViewServer.

Initial zones are deterministic fixtures. Answers use the production Session
action implementation; this is not production deck-start or GUI evidence.
"""
import argparse
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17464')
    parser.add_argument('--output', type=Path, default=ROOT / 'bridge/tests/native-view-facade-http-report.json')
    args = parser.parse_args()
    origin = urllib.parse.urlsplit(args.url)
    assert origin.hostname in ('127.0.0.1', 'localhost') and origin.port and origin.port >= 17400, 'Use an explicit isolated native fixture server'
    checks, cases = {}, []

    def call(path, body=None):
        request = urllib.request.Request(args.url + path, data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def wait(predicate, path='/session/state'):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            state = call(path)
            assert not state.get('error'), state.get('error')
            if predicate(state):
                return state
            time.sleep(.01)
        raise AssertionError('Native fixture did not reach the expected decision')

    def answer(state, choice):
        return call('/session/action', {'promptId': state['prompt']['id'], 'type': choice['responseType'], 'value': choice.get('value', choice['id'])})

    def choose(state, identity):
        return next(choice for choice in state['prompt']['choices'] if choice['id'] == identity)

    def finished():
        result = wait(lambda value: value['nativeResult']['done'], '/fixture/result')
        assert not result['nativeResult'].get('error'), result['nativeResult'].get('error')
        cases.append(result)
        return result

    report = {'passed': False, 'scope': __doc__}
    try:
        call('/fixture/angel', {})
        angel = wait(lambda state: any(card['name'] == 'Angel of Vitality' and card.get('power') == '5' for player in state.get('players', []) for card in player['battlefield']))
        card = next(card for player in angel['players'] for card in player['battlefield'] if card['name'] == 'Angel of Vitality')
        assert card['power'] == card['toughness'] == '5' and card['printing']['power'] == '2' and card['counters']['+1/+1'] == 1
        checks['nativeAngel5WithPrinted2AndCounter'] = True
        assert angel['capabilities']['automaticManaPoolPayment'] and not angel['capabilities']['automaticSourceTapping'] and not angel['clock']['enabled']
        checks['unsupportedAutotappingAndClockAreTruthful'] = True
        finished()
        for kind, destination in (('scry', 'bottom'), ('surveil', 'graveyard')):
            call('/fixture/' + kind, {})
            state = wait(lambda state: (state.get('prompt') or {}).get('cardPanel', {}).get('kind') == kind)
            first = state['prompt']; panel = first['cardPanel']; interaction = panel['interactionId']
            assert panel['selectionDestination'] == destination and panel['remainingDestination'] == 'top'
            moved = panel['cards'][0]['id']
            answer(state, choose(state, moved))
            state = wait(lambda state: state.get('prompt') and state['prompt']['id'] != first['id'])
            assert any(card['id'] == moved and card['selected'] for card in state['prompt']['cardPanel']['cards'])
            checks[kind + 'NativeSelectionAcknowledged'] = True
            try:
                call('/session/action', {'promptId': first['id'], 'type': 'uuid', 'value': moved})
                raise AssertionError('Consumed fixture prompt was accepted')
            except urllib.error.HTTPError as exc:
                assert exc.code == 400
            previous = state['prompt']['id']; answer(state, choose(state, 'done'))
            state = wait(lambda state: state.get('prompt') and state['prompt']['id'] != previous)
            order = state['prompt']['cardPanel']
            assert order['interactionId'] == interaction and order['stage'] == 'order' and order['orderDirection'] == 'last_chosen_topmost'
            checks[kind + 'NativeOrderingMetadata'] = True
            answer(state, choose(state, order['cards'][0]['choiceId']))
            result = finished(); native = result['nativeResult']
            assert (native['libraryTopToBottom'][-1]['id'] == moved if kind == 'scry' else any(card['id'] == moved for card in native['graveyard']))
            assert native['libraryTopToBottom'][0]['id'] == order['cards'][1]['id']
            checks[kind + 'NativeZonesAndOrderCorrect'] = True
            assert len(result['acceptedActions']) == 3 and len({action['promptId'] for action in result['acceptedActions']}) == 3
            checks[kind + 'OnlyAcceptedDistinctNativeInputsRecorded'] = True
        call('/fixture/cancel', {})
        state = wait(lambda state: (state.get('prompt') or {}).get('cancelScope') == 'pending_action')
        assert state['prompt']['pendingAction']['kind'] == 'activation'
        answer(state, state['prompt']['cancelChoice']); result = finished()['nativeResult']
        assert not result['activationAccepted'] and result['sacrificeStillPresent'] and result['striderStillPresent'] and result['stackSize'] == 0
        checks['nativeWoeStriderCancelRestoresUncommittedAction'] = True
        call('/fixture/combat', {})
        state = wait(lambda state: (state.get('prompt') or {}).get('combat', {}).get('role') == 'blockers')
        groups = state['combat']['groups']; own = next(player for player in state['players'] if player['human'])
        bear = next(card for card in own['battlefield'] if card['name'] == 'Grizzly Bears')
        native = next(blocker for blocker in state['prompt']['combat']['blockers'] if blocker['blockerId'] == bear['id'])
        assert len(native['legalAttackerIds']) == 1
        menace = next(group for group in groups if group['attackerId'] == native['legalAttackerIds'][0])
        assert menace['minBlockers'] == 2 and len(native['unavailable']) == 3
        checks['nativeFlyingLandwalkUnblockableAndMenaceHints'] = True
        previous = state['prompt']['id']; answer(state, choose(state, bear['id']))
        state = wait(lambda state: state.get('prompt') and state['prompt']['id'] != previous)
        assert any(bear['id'] in group['blockerIds'] for group in state['combat']['groups'])
        checks['nativeBlockAssignmentRelationships'] = True
        previous = state['prompt']['id']; answer(state, choose(state, 'done'))
        state = wait(lambda state: state.get('prompt') and state['prompt']['id'] != previous)
        assert all(bear['id'] not in group['blockerIds'] for group in state['combat']['groups'])
        checks['nativeMenaceRejectsLoneBlockerAndReasks'] = True
        answer(state, choose(state, 'done')); finished()
        call('/fixture/look', {})
        state = wait(lambda state: bool(state.get('lookedAt')))
        result = finished()
        assert result['nativeResult']['nativeTransientListCleared'] and any(card['id'] == result['nativeResult']['lookedAtCardId'] and card['name'] == 'Mountain' for group in state['lookedAt'] for card in group['cards'])
        checks['nativeLookAtRetainedAfterTransientCallbackClears'] = True
        assert all(group.get('id') for group in state['lookedAt']) and result['acceptedActions'] == []
        checks['nativeLookAtHasDismissalIdentityWithoutGameAnswer'] = True
        assert all(player['hand'] == [] for player in state['players'] if not player['human'])
        checks['nativeLookAtDoesNotExposeOtherHandContents'] = True
        report['passed'] = True
    except Exception as exc:
        report['error'] = str(exc)
    report.update(checks=checks, cases=cases)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': len(checks), 'error': report.get('error')}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
