#!/usr/bin/env python3
"""Real random-pool acceptance through an already running isolated room gateway.

Uses only desktop client routes, creates one human plus three native bot seats,
and closes only its own rooms. Does not read coordinator credentials, restart
services, inject packs, or submit tournament outcomes.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17451')
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--output', type=Path, default=ROOT / 'tests/rooms-random-live-report.json')
    args = parser.parse_args()
    parsed = urllib.parse.urlsplit(args.url)
    assert parsed.hostname in ('127.0.0.1', 'localhost') and parsed.port and parsed.port >= 17400, 'Use an explicitly isolated loopback gateway'
    deadline = time.monotonic() + args.timeout
    started = time.monotonic()
    checks, clients, cases = [], [], []
    report = {
        'scope': 'Real room gateway and native random booster drafts: one human plus three XMage bots per room, explicit eligible sets versus unrestricted sets, stale traditional pack slots, native pick clocks and all offered human picks, complete pools and native Limited deck validation. Swiss and elimination are selected independently; this test does not play tournament games or prove external LAN/WAN connectivity.',
        'gateway': args.url, 'passed': False,
    }

    def check(condition, label):
        assert condition, label
        checks.append(label)
        print('RANDOM ROOM PASS', label, flush=True)

    def call(path, body=None, cleanup=False):
        assert cleanup or time.monotonic() < deadline, 'Random-room acceptance timed out'
        request = urllib.request.Request(args.url + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=15 if cleanup else min(30, max(1, deadline - time.monotonic()))) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            try: message = json.load(exc).get('error', 'Room request failed')
            except (ValueError, AttributeError): message = 'Room request failed'
            raise AssertionError(str(exc.code) + ': ' + str(message)) from None

    def command(client, operation='', body=None, cleanup=False):
        return call('/client/rooms/' + client['connection'] + ('/' + operation if operation else ''), body, cleanup)

    def run_case(label, eligible, pairing):
        current = call('/client/rooms', {
            'kind': 'draft', 'name': 'Random pool acceptance ' + label,
            'playerName': 'Random pool test host', 'maxPlayers': 4,
            'draft': {'mode': 'random', 'profile': 'Limited', 'pairing': pairing,
                      'randomSets': eligible, 'sets': ['M14', 'M14', 'M14'], 'timing': 'PROFESSIONAL'},
        })
        client = {'connection': current['connectionId'], 'closed': False}
        clients.append(client)
        normalized = current['room']['config']['draft']
        check('sets' not in normalized and normalized['randomSets'] == eligible,
              label + ': normalized random config ignores stale traditional pack slots')
        check(normalized['pairing'] == pairing, label + ': requested tournament pairing remains independent of random card pool')
        command(client, 'bots', {'count': 3})
        current = command(client, 'ready', {'ready': True})
        check(len(current['room']['members']) == 4 and sum(bool(p['bot']) for p in current['room']['members']) == 3,
              label + ': four native seats contain one human and three bots')
        command(client, 'start', {})
        seen, picked, observed_sets, generations, pack_sizes = set(), [], set(), set(), {}
        clock_seen, privacy_seen = False, False
        while time.monotonic() < deadline:
            current = command(client)
            assert not current['room'].get('error'), current['room'].get('error')
            assert current['room']['phase'] not in ('failed', 'closed'), 'Draft failed before building'
            own = current.get('draft')
            if current['room']['phase'] == 'building':
                break
            if not own:
                time.sleep(.02)
                continue
            assert not own.get('error'), own.get('error')
            assert own['profile'] == 'random' and own['pairing'] == pairing, 'Native procedure/pairing differs from requested configuration'
            assert all(not any(key in player for key in ('pack', 'pool', 'deck', 'selection')) for player in own['players']), 'Public draft seats leaked private cards'
            privacy_seen = True
            token, pack = own.get('pickToken'), own.get('pack', [])
            if own['status'] == 'drafting' and token and pack and token not in seen:
                seen.add(token)
                sets = {card['set'] for card in pack}
                if eligible:
                    assert sets <= set(eligible), 'Native pack includes a card from outside the selected eligible set pool'
                observed_sets.update(sets)
                generation = own['packNumber']
                generations.add(generation)
                pack_sizes.setdefault(str(generation), len(pack))
                clock_seen |= own.get('secondsRemaining', 0) > 0 and own.get('deadline', 0) > 0
                picked.append(pack[0]['id'])
                command(client, 'draft/pick', {'pickToken': token, 'cardId': pack[0]['id']})
            time.sleep(.005)
        else:
            raise AssertionError(label + ': native random draft did not finish')
        own = current['draft']
        pool = own['pool']
        check(generations == {1, 2, 3} and own['packCount'] == 3,
              label + ': human completes all three native-generated random packs')
        check(clock_seen and privacy_seen, label + ': native pick deadlines are present and other seats keep their cards private')
        check(len(pool) == len(picked) and {card['id'] for card in pool} == set(picked),
              label + ': every accepted human pick is retained exactly once in the completed native pool')
        if eligible:
            check(len(pool) == 45 and {card['set'] for card in pool} <= set(eligible),
                  label + ': all 45 drafted cards come from M20/M21 despite stale M14 slots')
        else:
            check(normalized['randomSets'] == [] and len(pool) >= 23,
                  label + ': unrestricted native selection completes without a hidden traditional-set restriction')
        assert len(pool) >= 23, 'Native pool is too small for this test deck selection'
        selected = [card['id'] for card in pool[:23]]
        built = command(client, 'draft/deck', {'main': selected, 'basics': {'Forest': 17}})
        check(sum(entry['count'] for entry in built['draft']['deck']['main']) == 40
              and set(built['draft']['selection']['main']) == set(selected),
              label + ': native Limited accepts a 40-card deck from this pool and offered basics')
        check(built['room']['canStart'] and all(player['ready'] for player in built['room']['members']),
              label + ': all three native bot decks and the human deck are ready')
        cases.append({'case': label, 'randomSets': eligible, 'pairing': pairing,
                      'humanPicks': len(picked), 'humanPoolCount': len(pool),
                      'observedSetCodes': sorted(observed_sets), 'packInitialSizes': pack_sizes,
                      'nativePackGenerations': sorted(generations), 'nativeDeckSize': 40})
        command(client, 'leave', {}, cleanup=True)
        client['closed'] = True
        check(True, label + ': host closes only its own native draft room')

    try:
        health = call('/health')
        check(health.get('service') == 'love2gathering-rooms' and health.get('apiVersion') == 1,
              'Isolated gateway serves the desktop room API')
        caps = call('/client/capabilities')
        offered = {entry['code'] for entry in caps['draft']['sets']}
        pairings = {entry['id'] if isinstance(entry, dict) else entry for entry in caps['draft']['pairings']}
        check({'M14', 'M20', 'M21'} <= offered and {'swiss', 'elimination'} <= pairings,
              'Native capabilities offer the selected booster pools and both tournament procedures')
        run_case('restricted', ['M20', 'M21'], 'swiss')
        run_case('unrestricted', [], 'elimination')
        report['passed'] = True
    except Exception as exc:
        report['error'] = str(exc)
        report['traceback'] = traceback.format_exc()
    finally:
        cleanup_errors = []
        for client in clients:
            if not client['closed']:
                try:
                    command(client, 'leave', {}, cleanup=True)
                    client['closed'] = True
                except Exception as exc:
                    cleanup_errors.append(str(exc))
        if cleanup_errors:
            report['cleanupErrors'] = cleanup_errors
            report['passed'] = False
        report.update(checks=checks, cases=cases, seconds=round(time.monotonic() - started, 3),
                      allCreatedRoomsClosed=all(client['closed'] for client in clients))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
