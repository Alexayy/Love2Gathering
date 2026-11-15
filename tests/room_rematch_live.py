#!/usr/bin/env python3
"""Two real human native room games, rematch fences and recorded history.

Requires an already running isolated room gateway, native engine and catalog.
Uses only desktop room routes and read-only catalog endpoints; no coordinator
credentials are read. Closes only the room/connections created by this test.
Invitation codes and connection/seat credentials never enter the report.
"""
import argparse
import json
from pathlib import Path
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


class RequestError(ValueError):
    def __init__(self, status, message):
        super().__init__(str(status) + ': ' + message)
        self.status = status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17463')
    parser.add_argument('--catalog-url', default='http://127.0.0.1:17460')
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--output', type=Path, default=ROOT / 'tests/room-rematch-live-report.json')
    args = parser.parse_args()
    for address in (args.url, args.catalog_url):
        origin = urllib.parse.urlsplit(address)
        assert origin.hostname in ('127.0.0.1', 'localhost') and origin.port and origin.port >= 17400, 'Use explicitly isolated loopback services'
    deadline = time.monotonic() + args.timeout
    checks, clients, games, summaries = [], [], [], []
    report = {'passed': False, 'scope': 'Real native Modern room games with two humans through the desktop gateway: native opening choices/private hands, opposite native concessions, rematch request/other-human consent with the same connections/seats/decks, authorization/stale-game fences, and actual completed host win/loss history from SQLite recordings. No fixture game state, direct native access, or coordinator credentials.'}

    def check(value, label):
        assert value, label
        checks.append(label)
        print('ROOM REMATCH PASS', label, flush=True)

    def call(server, path, body=None, cleanup=False):
        while True:
            assert cleanup or time.monotonic() < deadline, 'Room rematch acceptance timed out'
            request = urllib.request.Request(server + path, data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
            try:
                with urllib.request.urlopen(request, timeout=15 if cleanup else min(30, max(1, deadline - time.monotonic()))) as response:
                    return json.load(response)
            except urllib.error.HTTPError as exc:
                try: message = json.load(exc).get('error', 'Room request failed')
                except (ValueError, AttributeError): message = 'Room request failed'
                raise RequestError(exc.code, str(message)) from None
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                # A root-owned catalog can restart while the native recorder
                # retains its durable outbox. Never blindly retry an action.
                if body is not None or cleanup or time.monotonic() >= deadline:
                    raise
                time.sleep(.1)

    def command(client, operation='', body=None, cleanup=False):
        return call(args.url, '/client/rooms/' + client['connection'] + ('/' + operation if operation else ''), body, cleanup)

    def rejected(client, operation, body, status):
        try: command(client, operation, body)
        except RequestError as exc:
            assert exc.status == status, 'Wrong authorization/stale rejection status: ' + str(exc)
            return True
        return False

    def poll(client, predicate, message):
        while time.monotonic() < deadline:
            state = command(client)
            assert not state['room'].get('error'), state['room'].get('error')
            if predicate(state): return state
            time.sleep(.02)
        raise AssertionError(message)

    def catalog_ready():
        while time.monotonic() < deadline:
            health = call(args.catalog_url, '/health')
            if health.get('storage'): return health
            time.sleep(.1)
        raise AssertionError('Isolated recording catalog did not become available')

    def reach_main(expected_id):
        seen, states = set(), {}
        while time.monotonic() < deadline:
            for client in clients:
                game = command(client, 'game/state')
                assert game.get('gameId') == expected_id and not game.get('error'), 'Seat routed to a different or failed native game'
                if game.get('phase') == 'Precombat Main':
                    states[client['seat']] = game
                    continue
                prompt = game.get('prompt')
                identity = client['seat'], prompt and prompt['id']
                if not prompt or identity in seen: continue
                choices = prompt.get('choices', [])
                if prompt.get('mulligan'): choice = prompt['mulligan']['keepChoice']
                elif 'starting player' in prompt.get('message', '').lower():
                    host = next(player for player in game['players'] if player['seatId'] == clients[0]['seat'])
                    choice = next(choice for choice in choices if choice['id'] == host['id'])
                else: choice = next((choice for choice in choices if choice['id'] == 'done'), choices[0] if choices else None)
                assert choice, 'Native opening prompt has no supported offered answer'
                seen.add(identity)
                command(client, 'game/action', {'expectedGameId': expected_id, 'promptId': prompt['id'], 'type': choice['responseType'], 'value': choice.get('value', choice['id'])})
            if len(states) == 2:
                for client in clients:
                    game = states[client['seat']]
                    own = next(player for player in game['players'] if player['human'])
                    assert own['seatId'] == client['seat'] and len(own['hand']) == own['handCount'] == 7 and own['libraryCount'] + own['handCount'] == 60
                    assert all(player['isHuman'] and (player['human'] or player['hand'] == []) for player in game['players'])
                return states
            time.sleep(.01)
        raise AssertionError('Both human native perspectives did not reach main')

    def finish(conceding, expected_id, winner):
        command(conceding, 'game/action', {'expectedGameId': expected_id, 'type': 'concede', 'value': True})
        ended = poll(clients[0], lambda state: state.get('game', {}).get('gameId') == expected_id and state['game'].get('running') is False and any(player['won'] for player in state['game']['players']), 'Native concession did not finish')
        players = ended['game']['players']
        assert next(player for player in players if player['seatId'] == winner['seat'])['won'] is True
        return ended

    def history(replay_id, outcome):
        while time.monotonic() < deadline:
            rows = call(args.catalog_url, '/history?limit=60')['matches']
            item = next((item for item in rows if item['id'] == replay_id), None)
            if item and item['completed'] and item['outcome'] == outcome:
                summaries.append({key: item[key] for key in ('id', 'format', 'status', 'outcome', 'completed', 'players')})
                return item
            time.sleep(.1)
        raise AssertionError('Native completed recording did not reach host history')

    started = time.monotonic()
    try:
        catalog_ready()
        health = call(args.url, '/health')
        check(health.get('service') == 'love2gathering-rooms', 'Isolated gateway serves the current room transport')
        priority = {'autoPass': True, 'stops': {'own': ['PRECOMBAT_MAIN'], 'opponent': ['PRECOMBAT_MAIN']}}
        created = call(args.url, '/client/rooms', {'kind': 'constructed', 'name': 'Native rematch acceptance', 'format': 'Modern', 'maxPlayers': 2, 'playerName': 'Rematch Host', 'priority': priority})
        clients.append({'connection': created['connectionId'], 'seat': created['participantId'], 'closed': False})
        joined = call(args.url, '/client/join', {'name': 'Rematch Guest', 'code': created['room']['inviteCode'], 'priority': priority})
        clients.append({'connection': joined['connectionId'], 'seat': joined['participantId'], 'closed': False})
        check(joined['room']['id'] == created['room']['id'] and clients[0]['seat'] != clients[1]['seat'], 'Two distinct human connections join by invitation code')
        decks = [json.loads((ROOT / 'decks' / file).read_text()) for file in ('modern-boros-burn.json', 'modern-merfolk.json')]
        for client, deck in zip(clients, decks):
            command(client, 'deck', {'deck': deck});command(client, 'ready', {'ready': True})
        check(command(clients[0])['room']['canStart'], 'Both native-valid constructed decks are selected and ready')
        command(clients[0], 'start', {})
        first = poll(clients[0], lambda state: state['room']['phase'] == 'playing' and bool((state.get('game') or {}).get('gameId')), 'First native room game did not start')
        first_id = first['game']['gameId']; games.append(first_id)
        first_states = reach_main(first_id)
        check(True, 'First real two-human native game reaches main with private seven-card hands and full decks')
        check(not command(clients[0])['room']['canRematch'] and rejected(clients[0], 'rematch', {}, 409), 'Running native game cannot be rematched')
        check(rejected(clients[1], 'rematch', {}, 409), 'A guest cannot rematch a running native game')
        ended = finish(clients[1], first_id, clients[0])
        check(ended['room']['canRematch'], 'Nonactive human concession produces an authoritative winner and enables host rematch')
        check(command(clients[1])['room']['canRematch'], 'Both completed native human perspectives can request a rematch')
        first_replay = ended['game']['replayId']
        first_history = history(first_replay, 'win')
        check({player['name'] for player in first_history['players']} == {'Rematch Host', 'Rematch Guest'} and all(player['deck']['name'] == deck['name'] and player['deck']['format'] == 'Modern' for player, deck in zip(sorted(first_history['players'], key=lambda player: not player['local']), decks)), 'Host win history preserves both native participant names and their exact deck summaries')
        catalog_ready();request=command(clients[0], 'rematch', {})['room']['rematchRequest']
        offered=command(clients[1]);check(offered['room']['rematchRequest']['requesterName']=='Rematch Host' and offered['game']['gameId']==first_id,'The opponent sees a rematch request before the game is replaced')
        command(clients[1], 'rematch-response', {'requestId':request['id'],'accept':True})
        second = poll(clients[0], lambda state: state['room']['phase'] == 'playing' and (state.get('game') or {}).get('gameId') and state['game']['gameId'] != first_id, 'Native rematch did not create a different game')
        second_id = second['game']['gameId'];games.append(second_id)
        check(second['participantId'] == clients[0]['seat'] and command(clients[1])['participantId'] == clients[1]['seat'], 'Rematch retains both original human connections and stable seat identities')
        check(rejected(clients[0], 'game/action', {'expectedGameId': first_id, 'type': 'concede', 'value': True}, 409), 'Old native game action is rejected before it can concede the rematch')
        second_states = reach_main(second_id)
        check(True, 'Rematch loads the same submitted native decks and preserves separate hidden hands')
        check(first_states[clients[0]['seat']]['players'][0]['id'] != second_states[clients[0]['seat']]['players'][0]['id'], 'Rematch uses new native player instances in a new native game')
        check(not command(clients[0])['room']['canRematch'] and rejected(clients[0], 'rematch', {}, 409), 'A running rematch cannot be started again prematurely')
        ended = finish(clients[0], second_id, clients[1])
        check(ended['game']['replayId'] != first_replay and ended['room']['canRematch'], 'Second real native game completes independently and remains eligible for a later host rematch')
        second_history = history(ended['game']['replayId'], 'loss')
        check(all(player['won'] is True if player['name'] == 'Rematch Guest' else player['lost'] is True for player in second_history['players']), 'Opposite native concession produces a distinct host-loss history entry with correct winner flags')
        check(first_history['id'] != second_history['id'] and first_history['outcome'] == 'win' and second_history['outcome'] == 'loss', 'Both completed recordings remain distinct in genuine match history')
        report['passed'] = True
    except Exception as exc:
        report['error'] = str(exc)
        report['traceback'] = traceback.format_exc()
    finally:
        cleanup_errors = []
        for client in clients[1:] + clients[:1]:
            try:
                command(client, 'leave', {}, cleanup=True);client['closed'] = True
            except Exception as exc: cleanup_errors.append(str(exc))
        if cleanup_errors:
            report['cleanupErrors'] = cleanup_errors;report['passed'] = False
        report.update(checks=checks, games=games, history=summaries, allCreatedConnectionsClosed=all(client['closed'] for client in clients), seconds=round(time.monotonic() - started, 3))
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': len(checks), 'error': report.get('error'), 'allCreatedConnectionsClosed': report['allCreatedConnectionsClosed']}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
