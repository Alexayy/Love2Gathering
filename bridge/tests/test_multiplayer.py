#!/usr/bin/env python3
"""Native Commander 4/5/6-player starts and a full priority/turn round on an isolated bridge.
The human passes priority; every opponent is the real XMage MAD bot. No zones are injected.
Use only an owned test engine: this script replaces its current match.
"""
import argparse
import json
import time
import traceback
import threading
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:17402')
    parser.add_argument('--recording-port', type=int, default=0)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--output', type=Path, default=ROOT / 'bridge/tests/multiplayer-report.json')
    args = parser.parse_args()

    def call(path, body=None):
        request = urllib.request.Request(args.url + path, data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'{path}: {error.code}: {error.read().decode()}') from error

    def reject(body, expected):
        try:
            call('/session/start', body)
        except RuntimeError as error:
            assert expected in str(error), str(error)
            return True
        raise AssertionError('Invalid start unexpectedly accepted')

    decks = [json.loads((ROOT / 'decks' / f'commander-{name}.json').read_text()) for name in ('krenko-goblins', 'goreclaw-stompy', 'ayara-devotion', 'giada-angels', 'talrand-spells')]
    health = call('/health')
    assert health.get('engine') == 'XMage' and health.get('ok')
    results = []
    failure = None
    poll_stop = threading.Event()
    poll_count = [0]
    poll_errors = []
    def poll_snapshots():
        while not poll_stop.is_set():
            try:
                call('/session/state')
                poll_count[0] += 1
            except Exception as error:
                poll_errors.append(str(error))
            poll_stop.wait(.005)
    readers = [threading.Thread(target=poll_snapshots, daemon=True) for _ in range(3)]
    for reader in readers:
        reader.start()
    current = None
    try:
        for count in (4, 5, 6):
            body = {'format': 'Commander', 'recordingPort': args.recording_port, 'playerName': 'Commander Human', 'deck': decks[0],
                    'bots': [{'name': f'Commander Bot {i + 1}', 'deck': decks[(i + 1) % len(decks)]} for i in range(count - 1)],
                    'settings': {'manualTriggers': False, 'autoMana': True}}
            state = call('/session/start', body)
            deadline = time.monotonic() + args.timeout
            actions = []
            active = set()
            log_seen = {}
            last_id = None
            free_mulligan = False
            starting_targets = set()
            opening = None
            players = []
            target_turns = count + 1
            while time.monotonic() < deadline:
                if state.get('error') or state.get('projectionError'):
                    raise AssertionError(state.get('error') or state.get('projectionError'))
                players = state.get('players', [])
                if players:
                    assert len(players) == count, f'Expected {count} players, got {len(players)}'
                    assert [p['seat'] for p in players] == list(range(count))
                    assert sum(p['human'] for p in players) == 1
                    assert state['playerCount'] == count and state['format'] == 'Commander'
                    for player in players:
                        assert player['human'] or player['hand'] == [], 'Bot hand leaked'
                    if all(len(p.get('command', [])) == 1 and p['handCount'] >= 7 for p in players) and opening is None:
                        opening = [{'name': p['name'], 'life': p['life'], 'handCount': p['handCount'], 'libraryCount': p['libraryCount'], 'commander': p['command'][0]['name']} for p in players]
                        assert all(p['life'] == 40 for p in players)
                        assert all(p['libraryCount'] + p['handCount'] == 99 for p in players)
                if state.get('activePlayerId'):
                    active.add(state['activePlayerId'])
                for entry in state.get('log', []):
                    if isinstance(entry, dict):
                        log_seen[entry['id']] = entry
                        assert 'critical error' not in entry['text'].lower()
                        if entry.get('category') == 'turn' and entry.get('actorId'):
                            active.add(entry['actorId'])
                if opening and free_mulligan and len(starting_targets) == count and state.get('turn', 0) >= target_turns and len(active) == count:
                    break
                assert state.get('running') is not False, 'Game stopped unexpectedly'
                prompt = state.get('prompt')
                if not prompt or prompt['id'] == last_id:
                    time.sleep(.02)
                    state = call('/session/state')
                    continue
                choices = prompt.get('choices', [])
                indexed = {choice['id']: choice for choice in choices}
                if 'mulligan' in prompt:
                    free_mulligan |= prompt['mulligan']['free'] and prompt['mulligan']['downTo'] == 7
                    chosen = prompt['mulligan']['keepChoice']
                elif 'starting player' in prompt.get('message', '').lower():
                    starting_targets = set(indexed)
                    assert {p['id'] for p in players}.issubset(starting_targets), 'Missing player target choices'
                    chosen = next(c for c in choices if c['id'] == next(p['id'] for p in players if p['human']))
                elif prompt['type'] in ('select', 'play_mana') and 'done' in indexed:
                    chosen = indexed['done']
                elif prompt['type'] == 'ask':
                    chosen = next((c for c in choices if c.get('value') is False), choices[0])
                else:
                    chosen = indexed.get('done') or (choices[0] if choices else None)
                assert chosen, f'Unhandled prompt: {prompt}'
                answer = {'promptId': prompt['id'], 'type': chosen['responseType'], 'value': chosen.get('value', chosen['id'])}
                actions.append({'turn': state.get('turn'), 'type': prompt['type'], 'message': prompt.get('message'), 'choice': chosen.get('label')})
                last_id = prompt['id']
                state = call('/session/action', answer)
            else:
                raise AssertionError(f'{count}-player match timed out')
            assert opening and free_mulligan and len(starting_targets) == count
            assert len(active) == count
            bot_lands = {e['actorId'] for e in log_seen.values() if e.get('category') == 'land' and e.get('actor') == 'bot'}
            assert len(bot_lands) == count - 1, 'Every bot must actually take a turn and play a land'
            assert all(e['actor'] == 'bot' for e in log_seen.values() if e.get('actorId') in {p['id'] for p in players if not p['human']}), 'Multiplayer bot logs attributed incorrectly'
            if args.recording_port:
                saved = call('/session/replay/save', {})
                assert saved.get('saved') and state.get('running'), saved
            current = state
            result = {'playerCount': count, 'passed': True, 'opening': opening, 'freeMulligan': free_mulligan, 'allStartingPlayerTargets': len(starting_targets), 'activePlayersObserved': len(active), 'turn': state.get('turn'), 'actionCount': len(actions), 'replayId': state.get('replayId'), 'actions': actions}
            call('/session/stop', {})
            if args.recording_port:
                catalog = f'http://127.0.0.1:{args.recording_port}'
                with urllib.request.urlopen(catalog + '/replays/' + state['replayId'], timeout=30) as response:
                    metadata = json.load(response)
                assert metadata['status'] == 'aborted', 'Stopped game must finish recording instead of leaving bots running'
                assert metadata['playerCount'] == count and len(metadata['bots']) == count - 1
                assert len(metadata['metadata']['players']) == count
                frames_checked = 0
                while True:
                    with urllib.request.urlopen(catalog + '/replays/' + state['replayId'] + f'/frames?limit=100&offset={frames_checked}', timeout=30) as response:
                        page = json.load(response)
                    for event in page['frames']:
                        frame = event['data']
                        assert len(frame['players']) == count
                        assert all(p['human'] or p['hand'] == [] for p in frame['players']), 'Saved replay leaked bot hand'
                    frames_checked += len(page['frames'])
                    if frames_checked >= page['total']:
                        break
                assert frames_checked > 0
                result['recordingFramesChecked'] = frames_checked
                result['recordingParticipantCount'] = len(metadata['metadata']['players'])
            results.append(result)
            print(f'PASS: {count} players; {len(actions)} actual prompt answers; turn {state.get("turn")}', flush=True)
        invalid = {'format': 'Commander', 'recordingPort': 0, 'deck': decks[0], 'bots': []}
        bounds = reject(invalid, '1 to 5 bots')
        invalid['bots'] = [{'deck': decks[1]}] * 6
        bounds &= reject(invalid, '1 to 5 bots')
        invalid['bots'] = [{'deck': decks[1]}] * 3
        invalid['format'] = 'Modern'
        bounds &= reject(invalid, 'Multiple bots require Commander')
        invalid['format'] = 'Commander'
        invalid['bots'][-1] = {'deck': {'main': [{'name': 'Forest', 'count': 99}], 'commander': []}}
        validation = reject(invalid, 'Bot 3 deck:')
        # Invalid construction must leave the previous stopped session intact.
        assert call('/session/state').get('gameId') == current.get('gameId')
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
        traceback.print_exc()
        bounds = validation = False
    finally:
        call('/session/stop', {})
        poll_stop.set()
        for reader in readers:
            reader.join(35)
    if poll_errors:
        failure = 'Concurrent snapshot reads failed: ' + '; '.join(poll_errors[:3])
    report = {'passed': failure is None and len(results) == 3 and bounds and validation, 'kind': 'Real XMage production deck startup, human HTTP choices and MAD bot turns; no injected state or frontend UI', 'health': health, 'concurrentSnapshotReads': poll_count[0], 'snapshotReadErrors': poll_errors, 'failure': failure, 'bounds': bounds, 'nativeBotDeckValidation': validation, 'tests': results}
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ('passed', 'failure', 'bounds', 'nativeBotDeckValidation')}, indent=2))
    return not report['passed']


if __name__ == '__main__':
    raise SystemExit(main())
