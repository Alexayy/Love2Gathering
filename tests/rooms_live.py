#!/usr/bin/env python3
"""Real two-gateway acceptance, using only the desktop public/client HTTP API.

Requires two already running, isolated room gateways and their native engine.
Creates private rooms of its own and leaves/closes those rooms in finally. Never
restarts services, reads a coordinator token or calls a global/native stop route.
Invitations and connection credentials are deliberately omitted from the report.
"""
import argparse
import concurrent.futures
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
    parser.add_argument('--host-url', default='http://127.0.0.1:17420')
    parser.add_argument('--guest-url', default='http://127.0.0.1:17421')
    parser.add_argument('--timeout', type=float, default=240)
    parser.add_argument('--skip-forfeit', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'tests/rooms-live-report.json')
    args = parser.parse_args()
    for address in (args.host_url, args.guest_url):
        parsed = urllib.parse.urlsplit(address)
        assert parsed.hostname in ('127.0.0.1', 'localhost') and parsed.port and parsed.port >= 17400, 'Use explicitly isolated loopback gateways'
    assert args.host_url != args.guest_url, 'Two independent gateways are required'
    checks, rooms, completed = [], [], []
    deadline = time.monotonic() + args.timeout
    report = {'scope': 'Real two desktop gateways, code-only human joins, native constructed game, four private native draft seats, 180 picks, native Limited decks and paired games, native concession/scoring/Swiss advancement, and deliberate draft departure. Only public/client HTTP routes; no injected game state or coordinator token.',
              'gateways': [args.host_url, args.guest_url], 'passed': False}

    def check(condition, label):
        assert condition, label
        checks.append(label)
        print('ROOMS LIVE PASS', label, flush=True)

    def call(server, path, body=None):
        assert time.monotonic() < deadline, 'End-to-end room acceptance timed out'
        request = urllib.request.Request(server + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=min(30, max(1, deadline - time.monotonic()))) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            try: message = json.load(exc).get('error', 'Room request failed')
            except (ValueError, AttributeError): message = 'Room request failed'
            raise RequestError(exc.code, str(message)) from None

    def reject(server, path, body=None, statuses=(400, 403, 404, 409, 410, 422)):
        try: call(server, path, body)
        except RequestError as exc:
            assert exc.status in statuses, 'Unexpected rejection: ' + str(exc)
            return True
        return False

    def command(client, operation='', body=None):
        return call(client['server'], '/client/rooms/' + client['connection'] + ('/' + operation if operation else ''), body)

    def create(config, count):
        started = call(args.host_url, '/client/rooms', dict(config, playerName='Live Host'))
        clients = [{'server': args.host_url, 'connection': started['connectionId'], 'seat': started['participantId'], 'closed': False}]
        rooms.append(clients)
        code = started['room']['inviteCode']
        for number in range(1, count):
            server = args.guest_url if number % 2 else args.host_url
            joined = call(server, '/client/join', {'name': 'Live Guest ' + str(number), 'code': code})
            assert joined['room']['id'] == started['room']['id'], 'Code join reached a different room'
            clients.append({'server': server, 'connection': joined['connectionId'], 'seat': joined['participantId'], 'closed': False})
        return clients

    def close(clients):
        # Release guest gateway connections before the host closes native state.
        for client in clients[1:] + clients[:1]:
            if client['closed']: continue
            try: command(client, 'leave', {});client['closed'] = True
            except Exception: pass

    def poll(client, phases, timeout=45):
        until = min(deadline, time.monotonic() + timeout)
        while time.monotonic() < until:
            current = command(client)
            assert not current['room'].get('error'), current['room'].get('error')
            if current['room']['phase'] in phases: return current
            time.sleep(.02)
        raise AssertionError('Room did not reach ' + '/'.join(phases))

    def answer(client, game, prompt, choice):
        return command(client, 'game/action', {'expectedGameId': game['gameId'], 'promptId': prompt['id'],
            'type': choice['responseType'], 'value': choice.get('value', choice['id'])})

    def reach_main(clients, deck_size):
        answered, mains = set(), {}
        until = min(deadline, time.monotonic() + 45)
        while time.monotonic() < until:
            for client in clients:
                current = command(client, 'game/state')
                assert not current.get('error'), current.get('error')
                if current.get('phase') == 'Precombat Main':
                    mains[client['seat']] = current
                    continue
                prompt = current.get('prompt')
                identity = client['seat'], prompt and prompt['id']
                if not prompt or identity in answered: continue
                choices = prompt.get('choices', [])
                if prompt.get('mulligan'): choice = prompt['mulligan']['keepChoice']
                elif 'starting player' in prompt.get('message', '').lower():
                    player = next(p for p in current['players'] if p['seatId'] == clients[0]['seat'])
                    choice = next(c for c in choices if c['id'] == player['id'])
                else: choice = next((c for c in choices if c['id'] == 'done'), choices[0] if choices else None)
                assert choice, 'Unsupported native opening prompt: ' + prompt.get('message', '')
                answered.add(identity)
                answer(client, current, prompt, choice)
            if len(mains) == len(clients): break
            time.sleep(.01)
        assert len(mains) == len(clients), 'Both native human views did not reach main phase'
        for client in clients:
            current = mains[client['seat']]
            own = next(p for p in current['players'] if p['human'])
            assert own['seatId'] == client['seat'] and len(own['hand']) == own['handCount'] == 7, 'Authenticated perspective did not retain its private hand'
            assert own['libraryCount'] + own['handCount'] == deck_size, 'Native game loaded a different submitted deck size'
            assert all(p['hand'] == [] and p['handCount'] == 7 for p in current['players'] if not p['human']), 'Another human hand leaked through the gateway'
        return mains

    def draft_to_build(clients, forfeit=False):
        for client in clients: command(client, 'ready', {'ready': True})
        command(clients[0], 'start', {})
        poll(clients[0], ('drafting',))
        seen, accepted, stale_tested, privacy_tested, departed = set(), 0, False, False, None
        active = clients[:]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
            while time.monotonic() < deadline:
                states = list(workers.map(lambda c: command(c), active))
                assert all(not state['room'].get('error') for state in states), 'Native draft reported an error'
                if all(state['room']['phase'] == 'building' for state in states): break
                pending = []
                for client, current in zip(active, states):
                    own = current.get('draft')
                    if not own: continue
                    if not privacy_tested:
                        assert all(not any(key in p for key in ('pack', 'pool', 'deck', 'selection')) for p in own['players']), 'A public draft seat leaked its private cards'
                        privacy_tested = True
                    token = own.get('pickToken')
                    identity = client['seat'], token
                    if own['status'] == 'drafting' and token and own['pack'] and identity not in seen:
                        seen.add(identity)
                        pending.append((client, {'pickToken': token, 'cardId': own['pack'][0]['id']}))
                if pending:
                    list(workers.map(lambda item: command(item[0], 'draft/pick', item[1]), pending))
                    accepted += len(pending)
                    if not stale_tested:
                        assert reject(pending[0][0]['server'], '/client/rooms/' + pending[0][0]['connection'] + '/draft/pick', pending[0][1]), 'Repeated pick token was accepted'
                        stale_tested = True
                if forfeit and not departed and accepted >= 4:
                    departed = active.pop()
                    command(departed, 'leave', {});departed['closed'] = True
                    assert reject(departed['server'], '/client/rooms/' + departed['connection']), 'Departed connection could still read private draft state'
                time.sleep(.005)
            else: raise AssertionError('Gateway draft did not finish')
        check(privacy_tested and stale_tested, 'Gateway draft exposes only own cards and rejects repeated native pick tokens')
        if not forfeit: check(accepted == 180, 'Four human gateway connections complete all 180 native picks')
        else: check(departed is not None and accepted < 180, 'Explicit guest departure removes its local connection while native auto-picking continues')
        states = [command(client) for client in active]
        for client, current in zip(active, states):
            own = current['draft']
            assert len(own['pool']) == 45, 'Three native packs did not produce 45 owned card instances'
            assert own['minDeckSize'] == 40 and any(b['name'] == 'Forest' for b in own['basicLands']), 'Limited setup did not preserve native basic-land options'
            selected = [card['id'] for card in own['pool'][:23]]
            result = command(client, 'draft/deck', {'main': selected, 'basics': {'Forest': 17}})
            assert sum(entry['count'] for entry in result['draft']['deck']['main']) == 40, 'Native Limited rejected a pool-valid 40-card deck'
            assert set(result['draft']['selection']['main']) == set(selected), 'Validated native selection was not retained for reconnection'
        ready = command(clients[0])
        check(ready['room']['canStart'] and all(p['ready'] for p in ready['room']['members']), 'Every active pool builds a native-valid 40-card deck and restores exact selected instance IDs')
        if departed:
            native_left = next(p for p in ready['draft']['players'] if p['seatId'] == departed['seat'])
            public_left = next(p for p in ready['room']['members'] if p['id'] == departed['seat'])
            check(native_left['forfeited'] and native_left['poolCount'] == 45 and native_left['ready'] and public_left['bot'], 'Departed seat retains its complete native pool and receives a valid native bot deck')
        return accepted, ready

    try:
        for server in (args.host_url, args.guest_url):
            health = call(server, '/health')
            check(health.get('service') == 'love2gathering-rooms' and health.get('apiVersion') == 1, 'Independent isolated room gateway answers its health endpoint')
        check(reject(args.host_url, '/rooms') and reject(args.guest_url, '/rooms'), 'Public room discovery is unavailable on both gateways')
        caps = call(args.host_url, '/client/capabilities')
        check({p['id'] for p in caps['draft']['modes']} == {'booster', 'random', 'cube'} and caps['draft']['maxPlayers'] == 16, 'Desktop capabilities preserve native draft procedures and seat bounds')

        constructed = create({'kind': 'constructed', 'name': 'Live constructed acceptance', 'format': 'Modern', 'maxPlayers': 2}, 2)
        check(len({c['seat'] for c in constructed}) == 2 and constructed[0]['server'] != constructed[1]['server'], 'Two independent gateways join one constructed room using only its invitation code')
        check(reject(args.guest_url, '/client/rooms/' + constructed[0]['connection']), 'A host connection credential is not a local guest connection')
        for client, file in zip(constructed, ('modern-boros-burn.json', 'modern-merfolk.json')):
            command(client, 'deck', {'deck': json.loads((ROOT / 'decks' / file).read_text())})
            command(client, 'ready', {'ready': True})
        command(constructed[0], 'start', {})
        poll(constructed[0], ('playing',))
        constructed_states = reach_main(constructed, 60)
        check(True, 'Real two-human constructed game reaches main with each private opening hand through its own gateway')
        check(reject(constructed[1]['server'], '/client/rooms/' + constructed[1]['connection'] + '/game/replay/save', {}), 'Guest cannot export the host-perspective native recording')
        close(constructed)
        check(all(c['closed'] for c in constructed), 'Constructed room releases both created connections and closes only its own native game')

        config = {'kind': 'draft', 'name': 'Live four-human draft acceptance', 'maxPlayers': 4,
                  'draft': {'mode': 'booster', 'profile': 'Limited', 'pairing': 'swiss', 'sets': ['M21', 'M20', 'M19'], 'timing': 'PROFESSIONAL'}}
        clients = create(config, 4)
        check(len({c['seat'] for c in clients}) == 4 and sum(c['server'] == args.host_url for c in clients) == 2, 'Four human seats span two independent local gateways')
        picks, building = draft_to_build(clients)
        check(reject(clients[0]['server'], '/client/rooms/' + clients[0]['connection'] + '/draft/result', {'winnerSeatId': clients[0]['seat']}), 'Public clients cannot forge a tournament winner or native result')
        check(all(s['points'] == 0 for s in command(clients[0])['draft']['tournament']['standings']), 'Rejected public result leaves native standings unchanged')
        command(clients[0], 'start', {})
        playing = poll(clients[0], ('playing',))
        pairs = playing['draft']['tournament']['matches']
        check(playing['draft']['tournament']['round'] == 1 and len(pairs) == 2, 'Host starts two actual native Limited games from first-round Swiss pairings')
        by_seat = {client['seat']: client for client in clients}
        first_game_ids = {}
        for pair in pairs:
            paired = [by_seat[seat] for seat in pair['seatIds']]
            mains = reach_main(paired, 40)
            check(True, 'Paired native Limited game reaches main with exact 40-card decks and private seven-card hands')
            game = mains[paired[1]['seat']]
            for client in paired: first_game_ids[client['seat']] = game['gameId']
            command(paired[1], 'game/action', {'expectedGameId': game['gameId'], 'type': 'concede', 'value': True,
                'playerId': next(p['id'] for p in game['players'] if p['seatId'] == paired[0]['seat']), 'seatId': paired[0]['seat']})
            until = min(deadline, time.monotonic() + 30)
            while time.monotonic() < until:
                current = command(clients[0])
                result = next(match for match in current['room']['matches'] if match['id'] == pair['id'])
                if result['finished']: break
                time.sleep(.02)
            else: raise AssertionError('Native paired concession did not reach gateway scoring')
            check(result['winnerSeatId'] == paired[0]['seat'], 'Authenticated loser concession ignores forged seat identity and records the authoritative native winner')
            standings = current['draft']['tournament']['standings']
            check(next(s['points'] for s in standings if s['seatId'] == paired[0]['seat']) == 3, 'Completed native game awards the correct native Swiss points through the gateway')
            completed.append({'pairingId': pair['id'], 'gameId': game['gameId'], 'winnerSeatId': result['winnerSeatId']})
        current = command(clients[0])
        check(current['room']['canNextRound'], 'Host can advance only after every native paired game has finished')
        command(clients[0], 'next-round', {})
        second = poll(clients[0], ('playing',))
        check(second['draft']['tournament']['round'] == 2 and len(second['room']['matches']) == 2, 'Host next-round starts the second native Swiss round through the public gateway')
        check(reject(clients[0]['server'], '/client/rooms/' + clients[0]['connection'] + '/game/action',
                     {'expectedGameId': first_game_ids[clients[0]['seat']], 'type': 'concede', 'value': True}, (409,)),
              'A queued action from the old native round cannot affect the new match')
        close(clients)
        check(all(c['closed'] for c in clients), 'Draft room departure closes only created connections and its own paired native games')
        if not args.skip_forfeit:
            forfeiting = create(dict(config, name='Live explicit draft departure'), 4)
            forfeit_picks, _ = draft_to_build(forfeiting, forfeit=True)
            close(forfeiting)
            report['forfeitHumanPicks'] = forfeit_picks
        report.update(passed=True, acceptedHumanPicks=picks, nativeFirstRoundGames=completed, secondRound=2,
                      constructedGameIds=sorted({state['gameId'] for state in constructed_states.values()}))
    except BaseException as exc:
        report['failure'] = str(exc)
        traceback.print_exc()
    finally:
        # Cleanup has a separate bounded allowance if acceptance exhausted its time.
        deadline = max(deadline, time.monotonic() + 30)
        for clients in reversed(rooms): close(clients)
        report['checks'] = checks
        report['closedCreatedConnections'] = all(c['closed'] for clients in rooms for c in clients)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('ROOMS LIVE COMPLETE', len(checks), 'checks; passed =', report['passed'], flush=True)
    return 0 if report['passed'] and report['closedCreatedConnections'] else 1


if __name__ == '__main__': raise SystemExit(main())
