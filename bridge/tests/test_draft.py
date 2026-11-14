#!/usr/bin/env python3
"""Owned-engine HTTP acceptance: real draft -> pool-valid Limited decks -> native paired games.

Never use a user's engine. All created native sessions are stopped in finally.
Native bot/max-capacity/cube cases are separately covered by DraftFixture.java.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17412')
    parser.add_argument('--token-file', type=Path, default=ROOT / '.runtime/rooms-coordinator.token')
    parser.add_argument('--timeout', type=float, default=240)
    parser.add_argument('--output', type=Path, default=ROOT / 'bridge/tests/draft-http-report.json')
    args = parser.parse_args()
    parsed = urllib.parse.urlsplit(args.url)
    assert parsed.hostname in ('127.0.0.1', 'localhost') and parsed.port not in (None, 17371), 'Use an explicitly owned isolated loopback engine'
    token = args.token_file.read_text().strip()
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
    checks = []
    drafts, games, draft_keys, game_keys = [], [], [], []
    report = {'scope': 'Actual authenticated native HTTP drafts, private projections, native Limited validation, stored-pool deck handoff, native game completion, native Swiss pairing/result progression and start/round/result/stop retry identity; no injected zones', 'passed': False}

    def check(condition, label):
        assert condition, label
        checks.append(label)
        print('DRAFT HTTP PASS', label, flush=True)

    def call(path, body=None, auth=True):
        request = urllib.request.Request(args.url + path, data=None if body is None else json.dumps(body).encode(), headers=headers if auth else {})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:return json.load(response)
        except urllib.error.HTTPError as error:
            raise ValueError(str(error.code) + ': ' + error.read().decode()) from error

    def reject(path, body=None, auth=True):
        try:call(path, body, auth)
        except ValueError:return True
        return False

    def state(draft, seat):return call('/draft/state?' + urllib.parse.urlencode({'draftId': draft, 'seatId': seat}))
    def game_state(game, player):return call('/multiplayer/state?' + urllib.parse.urlencode({'gameId': game, 'playerId': player}))
    def answer(game, player, prompt, choice):
        return call('/multiplayer/action', {'gameId': game, 'playerId': player, 'promptId': prompt['id'], 'type': choice['responseType'], 'value': choice.get('value', choice['id'])})

    try:
        check(reject('/draft/options', auth=False), 'Native draft operations reject unauthenticated requests')
        capabilities = call('/draft/options')
        check({p['id'] for p in capabilities['profiles']} == {'booster', 'random', 'cube'}, 'Only native draft procedures are offered')
        check(all(p['minPlayers'] == 4 and p['maxPlayers'] == 16 for p in capabilities['profiles']), 'Draft capacity comes from native tournament profiles')
        seats = [{'seatId': 'http-draft-' + str(i), 'name': 'HTTP drafter ' + str(i), 'type': 'human'} for i in range(4)]
        config = {'profile': 'booster', 'pairing': 'swiss', 'sets': ['M21', 'M20', 'M19'], 'timing': 'PROFESSIONAL'}
        closed_draft_key = 'draft-http-close-first-' + str(uuid.uuid4());draft_keys.append(closed_draft_key)
        call('/draft/stop', {'idempotencyKey': closed_draft_key})
        check(reject('/draft/start', {'idempotencyKey': closed_draft_key, 'config': config, 'seats': seats}), 'A draft close arriving before its start prevents that late start')
        draft_key = 'draft-http-' + str(uuid.uuid4());draft_keys.append(draft_key)
        draft_body = {'idempotencyKey': draft_key, 'config': config, 'seats': seats}
        started = call('/draft/start', draft_body);draft = started['draftId'];drafts.append(draft)
        check(call('/draft/start', json.loads(json.dumps(draft_body, sort_keys=True))) == started,
              'Equivalent draft start retries with reordered object keys return the same native draft identity')
        changed_start = json.loads(json.dumps(draft_body));changed_start['config']['timing'] = 'BEGINNER'
        check(reject('/draft/start', changed_start), 'A reused draft start key rejects changed configuration')
        seen = set();accepted = 0;stale = False;private_checked = False
        deadline = time.monotonic() + args.timeout
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            while time.monotonic() < deadline:
                states = list(pool.map(lambda seat: state(draft, seat['seatId']), seats))
                assert all(not s.get('error') for s in states), states
                if all(s['status'] in ('building', 'ready') for s in states):break
                pending = []
                for seat, current in zip(seats, states):
                    if not private_checked:
                        check(all(not any(key in p for key in ('pack', 'pool', 'deck')) for p in current['players']), 'Public draft seats contain counts without private packs or pools')
                        private_checked = True
                    pick_token = current.get('pickToken')
                    identity = seat['seatId'], pick_token
                    if current['status'] == 'drafting' and pick_token and current['pack'] and identity not in seen:
                        seen.add(identity)
                        body = {'draftId': draft, 'seatId': seat['seatId'], 'pickToken': pick_token, 'cardId': current['pack'][0]['id']}
                        pending.append(body)
                for body, result in zip(pending, pool.map(lambda body: call('/draft/pick', body), pending)):
                    accepted += 1
                    if not stale:
                        check(reject('/draft/pick', body), 'Repeated HTTP pick cannot select another card from a later pack')
                        stale = True
                time.sleep(.005)
            else:raise AssertionError('Native HTTP draft timed out')
        check(accepted == 180, 'Four independent humans complete 180 native pick submissions')
        pools = {}
        for seat in seats:
            own = state(draft, seat['seatId']);pools[seat['seatId']] = own['pool']
            check(len(own['pool']) == 45, 'Three real native packs give ' + seat['seatId'] + ' 45 cards')
            forged = call('/draft/deck', {'draftId': draft, 'seatId': seat['seatId'], 'main': ['00000000-0000-0000-0000-000000000001']})
            check(not forged['accepted'] and forged['errors'], 'Undrafted card instance cannot enter the submitted Limited deck')
            selected = [card['id'] for card in own['pool'][:23]]
            submitted = call('/draft/deck', {'draftId': draft, 'seatId': seat['seatId'], 'main': selected, 'basics': {'Forest': 17}})
            check(submitted['accepted'] and sum(entry['count'] for entry in submitted['deck']['main']) == 40, 'Native Limited validates a deck built from the private pool plus offered basics')
        check(state(draft, seats[0]['seatId'])['status'] == 'ready', 'Draft waits until every human has a valid deck')
        round_body = {'draftId': draft, 'idempotencyKey': 'round-http-' + str(uuid.uuid4())}
        first_round = call('/draft/next-round', round_body)
        check(len(first_round['matches']) == 2 and first_round['round'] == 1, 'Native Swiss produces two actual Limited game pairings')
        check(call('/draft/next-round', round_body) == first_round, 'A first-round retry returns the same native pairings without advancing')
        check(reject('/draft/next-round', dict(round_body, differentInput=True)), 'A round idempotency key rejects changed input')
        completed = []
        by_seat = {seat['seatId']: seat for seat in seats}
        for pair in first_round['matches']:
            paired = [dict(by_seat[seat], deck={'main': [{'name': 'Untrusted nonexistent card', 'count': 40}]}) for seat in pair['seatIds']]
            game_key = 'draft-http-game-' + str(uuid.uuid4());game_keys.append(game_key)
            game_body = {'idempotencyKey': game_key, 'draftId': draft, 'pairingId': pair['id'], 'seats': paired, 'recordingPort': 0}
            if not completed:
                closed_game_key = 'draft-http-game-close-first-' + str(uuid.uuid4());game_keys.append(closed_game_key)
                call('/multiplayer/stop', {'idempotencyKey': closed_game_key})
                check(reject('/multiplayer/start', dict(game_body, idempotencyKey=closed_game_key)), 'A game close arriving before its start prevents that late paired game')
            game_start = call('/multiplayer/start', game_body)
            game = game_start['gameId'];games.append(game)
            check(call('/multiplayer/start', json.loads(json.dumps(game_body, sort_keys=True))) == game_start,
                  'Equivalent paired-game start retries retain the same native game and player identities')
            check(reject('/multiplayer/start', dict(game_body, recordingPort=1)), 'A reused game start key rejects changed input')
            players = {seat['seatId']: seat['playerId'] for seat in game_start['seats']}
            answered = set();main_seen = False
            game_deadline = time.monotonic() + 45
            while time.monotonic() < game_deadline:
                for seat in pair['seatIds']:
                    current = game_state(game, players[seat]);assert not current.get('error'), current.get('error')
                    if current.get('phase') == 'Precombat Main':
                        own = next(p for p in current['players'] if p.get('human'))
                        check(len(current['players']) == 2 and len(own['hand']) == own['handCount'] == 7 and own['libraryCount'] + own['handCount'] == 40,
                              'Native Limited loads the 40-card submitted deck and full private opening hand')
                        check(all(p['hand'] == [] and p['handCount'] == 7 for p in current['players'] if not p.get('human')),
                              'Paired native game keeps the other drafter hand private')
                        main_seen = True;break
                    prompt = current.get('prompt')
                    if not prompt or prompt['id'] in answered:continue
                    choices = prompt.get('choices', [])
                    if prompt.get('mulligan'):choice = prompt['mulligan']['keepChoice']
                    elif 'starting player' in prompt.get('message', '').lower():choice = next(c for c in choices if c['id'] == players[pair['seatIds'][0]])
                    else:choice = next((c for c in choices if c['id'] == 'done'), choices[0] if choices else None)
                    assert choice, prompt
                    answered.add(prompt['id']);answer(game, players[seat], prompt, choice)
                if main_seen:break
                time.sleep(.01)
            check(main_seen, 'Native paired Limited game reaches its real main phase using stored validated decks')
            loser = pair['seatIds'][1]
            call('/multiplayer/action', {'gameId': game, 'playerId': players[loser], 'type': 'concede', 'value': True})
            result = None
            while time.monotonic() < game_deadline:
                result = call('/multiplayer/result?' + urllib.parse.urlencode({'gameId': game}))
                if result.get('running') is False:break
                time.sleep(.01)
            check(result and result['running'] is False and result['winnerSeatIds'] == [pair['seatIds'][0]], 'Actual native concession finishes the Limited game with its authoritative winner')
            result_body = {'draftId': draft, 'pairingId': pair['id'], 'gameId': game}
            scored = call('/draft/result', result_body)
            check(any(s['seatId'] == pair['seatIds'][0] and s['points'] == 3 for s in scored['standings']), 'Completed native game result awards native Swiss points')
            check(call('/draft/result', result_body) == scored, 'Retrying the same bound native result does not award points twice')
            call('/multiplayer/stop', {'idempotencyKey': game_key})
            stopped = call('/multiplayer/stop', {'gameId': game})
            check(stopped.get('running') is False and stopped.get('alreadyStopped'), 'Key-only game stop and repeated stop by identity reclaim the same game')
            check(call('/multiplayer/stop', {'idempotencyKey': game_key}).get('alreadyStopped'), 'Repeated key-only game cleanup is accepted')
            check(reject('/multiplayer/start', game_body), 'A closed paired-game start key cannot create a replacement game')
            check(call('/draft/result', result_body) == scored, 'A lost result response remains recoverable after its native game has been reclaimed')
            completed.append({'pairingId': pair['id'], 'gameId': game, 'winnerSeatId': pair['seatIds'][0], 'mainPhaseReached': True})
        check(call('/draft/pairings?' + urllib.parse.urlencode({'draftId': draft}))['finished'], 'Every first-round native game finishes before advancement')
        check(reject('/draft/result', {'draftId': draft, 'pairingId': completed[0]['pairingId'], 'gameId': completed[1]['gameId']}),
              'An already scored pairing cannot be rebound to a different actual native game')
        check(call('/draft/next-round', round_body) == first_round, 'A delayed first-round retry remains its original snapshot after both games finish')
        second_body = {'draftId': draft, 'idempotencyKey': 'round-http-' + str(uuid.uuid4())}
        second = call('/draft/next-round', second_body)
        check(second['round'] == 2 and len(second['matches']) == 2, 'Actual completed games advance the native Swiss pairing algorithm')
        check(call('/draft/next-round', second_body) == second, 'Second-round retry keeps the exact native round and pairing identities')
        call('/draft/stop', {'idempotencyKey': draft_key})
        check(call('/draft/stop', {'draftId': draft}).get('alreadyStopped'), 'Key-only draft close and repeated identity close are accepted')
        check(call('/draft/stop', {'idempotencyKey': draft_key}).get('alreadyStopped'), 'Repeated key-only draft cleanup is accepted')
        check(reject('/draft/start', draft_body), 'A closed draft start key cannot recreate the stopped draft')
        report.update(passed=True, draftId=draft, acceptedHumanPicks=accepted, poolSizes=[len(p) for p in pools.values()], nativeGames=completed, secondRound=second['round'])
    except BaseException as error:
        report['failure'] = str(error);traceback.print_exc()
    finally:
        for game in games:
            try:call('/multiplayer/stop', {'gameId': game})
            except Exception:pass
        for draft in drafts:
            try:call('/draft/stop', {'draftId': draft})
            except Exception:pass
        # Key-only cleanup also covers a start whose successful response was lost.
        for key in game_keys:
            try:call('/multiplayer/stop', {'idempotencyKey': key})
            except Exception:pass
        for key in draft_keys:
            try:call('/draft/stop', {'idempotencyKey': key})
            except Exception:pass
        report['checks'] = checks
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('DRAFT HTTP COMPLETE', len(checks), 'checks; passed =', report['passed'], flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':raise SystemExit(main())
