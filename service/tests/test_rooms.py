"""Real HTTP gateways with a synthetic native adapter; native rules tested separately."""
import copy
import json
from pathlib import Path
import sys
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rooms import Gateway, Registry, RoomError, decode_invite, handler, invite, MAX_BODY
from http.server import ThreadingHTTPServer


class NativeFixture:
    def __init__(self):
        self.calls = []
        self.games = {}
        self.game_sequence = 0
        self.drafts = {}
        self.retries = {}

    def remember(self, path, body, result):
        if body.get('idempotencyKey'):
            self.retries[(path, body['idempotencyKey'])] = (copy.deepcopy(body), copy.deepcopy(result))
        return result

    def call(self, method, path, body=None, timeout=None):
        self.calls.append((method, path, copy.deepcopy(body)))
        from urllib.parse import parse_qs, urlsplit
        query = parse_qs(urlsplit(path).query);path = urlsplit(path).path
        get = lambda key: query[key][0]
        key = body.get('idempotencyKey') if body else None
        if key and path in ('/multiplayer/start', '/draft/start', '/draft/next-round'):
            saved = self.retries.get((path, key))
            if saved:
                if saved[1] is None: raise RoomError('This start has been closed')
                if saved[0] != body: raise RoomError('Idempotency key conflicts with previous request')
                return copy.deepcopy(saved[1])
        if path == '/multiplayer/capabilities':
            return {'formats': ['Modern', 'Commander', 'Legacy', 'Limited'], 'games': [
                {'format': 'Constructed', 'minPlayers': 2, 'maxPlayers': 2},
                {'format': 'Commander', 'minPlayers': 2, 'maxPlayers': 10},
                {'format': 'Limited', 'minPlayers': 2, 'maxPlayers': 10}],
                'draft': {'profiles': [{'id': p, 'label': p, 'minPlayers': 4, 'maxPlayers': 16, 'packCount': 3}
                                       for p in ('booster', 'random', 'cube')],
                          'deckProfiles': [{'id': 'Limited', 'minDeckSize': 40}],
                          'pairings': [{'id': 'swiss'}, {'id': 'elimination'}],
                          'sets': [{'code': 'M14', 'name': 'Magic 2014'}, {'code': 'M20', 'name': 'Core Set 2020'},
                                   {'code': 'M21', 'name': 'Core Set 2021'}], 'cubes': [{'code': 'VintageCube', 'name': 'Vintage cube'}]}}
        if path == '/multiplayer/start':
            self.game_sequence += 1
            key = 'game-' + str(self.game_sequence)
            self.games[key] = {'seats': copy.deepcopy(body['seats']), 'running': True, 'winnerSeatIds': []}
            return self.remember(path, body, {'gameId': key, 'seats': [{'seatId': s['seatId'], 'playerId': 'p-' + s['seatId'], 'human': s['type'] == 'human'} for s in body['seats']]})
        if path == '/multiplayer/state':
            game = self.games[get('gameId')]
            return {'gameId': get('gameId'), 'running': game['running'], 'players': [
                {'id': 'p-' + s['seatId'], 'name': s['name'], 'human': 'p-' + s['seatId'] == get('playerId'),
                 'hand': [{'id': 'private-' + s['seatId']}] if 'p-' + s['seatId'] == get('playerId') else []}
                for s in game['seats']]}
        if path == '/multiplayer/result':
            return {k: v for k, v in self.games[get('gameId')].items() if k != 'seats'}
        if path == '/multiplayer/stop':
            if key:
                prior = self.retries.get(('/multiplayer/start', key))
                if prior and prior[1]: self.games.pop(prior[1]['gameId'], None)
                self.retries[('/multiplayer/start', key)] = (None, None)
            self.games.pop(body.get('gameId'), None);return {'running': False}
        if path in ('/multiplayer/action', '/multiplayer/priority'):
            return {'gameId': body['gameId'], 'revision': 3}
        if path == '/draft/start':
            key = 'draft-' + str(len(self.drafts) + 1)
            self.drafts[key] = {'status': 'drafting', 'seats': body['seats'], 'ready': set(), 'round': 0}
            return self.remember(path, body, {'draftId': key})
        if path == '/draft/state':
            draft = self.drafts[get('draftId')];seat = get('seatId')
            return {'id': get('draftId'), 'status': draft['status'], 'pack': [{'id': 'pack-' + seat}],
                    'pool': [{'id': 'pool-' + seat}], 'players': [{'seatId': s['seatId'], 'ready': s['seatId'] in draft['ready'] or s['type'] == 'bot'} for s in draft['seats']]}
        if path == '/draft/pick': return {'accepted': True}
        if path == '/draft/forfeit':
            draft = self.drafts[body['draftId']]
            next(s for s in draft['seats'] if s['seatId'] == body['seatId'])['type'] = 'bot'
            draft['ready'].add(body['seatId']);return {'accepted': True}
        if path == '/draft/deck':
            if 'forged' in body['main']: return {'accepted': False, 'errors': ['Card is outside your pool: forged']}
            self.drafts[body['draftId']]['ready'].add(body['seatId'])
            return {'accepted': True, 'deck': {'name': 'Draft deck', 'format': 'Limited', 'main': [], 'sideboard': []}}
        if path == '/draft/pairings':
            return {'round': self.drafts[get('draftId')]['round'], 'standings': []}
        if path == '/draft/next-round':
            draft = self.drafts[body['draftId']];draft['round'] += 1
            ids = [s['seatId'] for s in draft['seats']]
            return self.remember(path, body, {'round': draft['round'], 'matches': [{'id': 'pair-' + str(draft['round']) + '-' + str(i), 'seatIds': ids[i:i+2]} for i in range(0, len(ids), 2)]})
        if path == '/draft/result':
            draft = self.drafts[body['draftId']]
            if draft.get('elimination') and not self.games[body['gameId']]['winnerSeatIds']:
                raise RoomError('A drawn elimination game requires a rematch')
            return {'accepted': True}
        if path == '/draft/stop':
            if key:
                prior = self.retries.get(('/draft/start', key))
                if prior and prior[1]: self.drafts.pop(prior[1]['draftId'], None)
                self.retries[('/draft/start', key)] = (None, None)
            self.drafts.pop(body.get('draftId'), None);return {'ok': True}
        raise AssertionError((method, path, body))


class RunningGateway:
    def __init__(self):
        self.engine = NativeFixture()
        self.registry = Registry(self.engine, 'http://127.0.0.1:1')
        self.gateway = Gateway(self.registry)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), handler(self.gateway))
        self.server.daemon_threads = True
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)
        self.registry.public_origin = self.url
        self.gateway.local_origin = self.gateway.upstream = self.url
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True);self.thread.start()

    def request(self, path, body=None, token=None, headers=None):
        h = {'Content-Type': 'application/json'}
        if token: h['Authorization'] = 'Bearer ' + token
        h.update(headers or {})
        request = Request(self.url + path, data=None if body is None else json.dumps(body).encode(), headers=h)
        with urlopen(request, timeout=5) as response: return json.load(response)

    def close(self):
        self.server.shutdown();self.server.server_close();self.thread.join()


class RoomTests(unittest.TestCase):
    def setUp(self): self.a = RunningGateway();self.b = RunningGateway()
    def tearDown(self): self.a.close();self.b.close()

    def create(self, draft=False, maximum=2):
        config = {'name': 'Test room', 'playerName': 'Host', 'kind': 'draft' if draft else 'constructed',
                  'format': 'Commander', 'maxPlayers': maximum,
                  'draft': {'mode': 'booster', 'profile': 'Limited', 'pairing': 'swiss', 'sets': ['M14'] * 3}}
        return self.a.request('/client/rooms', config)

    def join(self, created): return self.b.request('/client/join', {'code': created['room']['inviteCode'], 'name': 'Guest'})
    def client(self, server, connection, suffix='', body=None): return server.request('/client/rooms/' + connection['connectionId'] + suffix, body)
    def wait_phase(self, created, phase):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            value = self.client(self.a, created)
            if value['room']['phase'] == phase: return value
            time.sleep(.01)
        self.fail('Room did not reach ' + phase)

    def ready_game(self):
        created = self.create();joined = self.join(created)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/deck', {'deck': {'name': 'Private deck', 'format': 'Commander', 'main': [{'name': 'Private card', 'count': 99}]}})
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {})
        return created, joined, self.wait_phase(created, 'playing')

    def test_code_carries_origin_and_secret_without_public_list(self):
        created = self.create();code = decode_invite(created['room']['inviteCode'])
        self.assertEqual(code['server'], self.a.url)
        self.assertNotIn('memberToken', created)
        with self.assertRaises(HTTPError) as error: self.a.request('/rooms')
        self.assertEqual(error.exception.code, 404)
        for code in ('bad', 'L2G1-####', invite(self.a.url, 'room12345', 'secret12345') + 'x'):
            with self.assertRaises(RoomError): decode_invite(code)

    def test_two_gateways_join_only_by_code_and_keep_decks_private(self):
        created = self.create();joined = self.join(created)
        self.assertEqual(created['room']['id'], joined['room']['id'])
        self.client(self.b, joined, '/deck', {'deck': {'name': 'Guest private', 'format': 'Commander', 'main': [{'name': 'Secret', 'count': 1}]}})
        state = self.client(self.a, created)
        self.assertNotIn('Secret', json.dumps(state));self.assertNotIn('memberToken', json.dumps(state))
        self.assertEqual(len(state['room']['members']), 2)
        self.assertEqual(self.b.engine.games, {})

    def test_bad_codes_and_seat_tokens_cannot_claim_other_players(self):
        created = self.create();code = decode_invite(created['room']['inviteCode'])
        with self.assertRaises(HTTPError) as error: self.a.request('/rooms/' + code['room'], token=code['key'])
        self.assertEqual(error.exception.code, 403)
        with self.assertRaises(HTTPError): self.a.request('/rooms/' + code['room'] + '/join', {'key': 'wrong', 'name': 'Host'})
        joined = self.join(created)
        with self.assertRaises(HTTPError) as error: self.client(self.b, joined, '/bots', {'count': 0})
        self.assertEqual(error.exception.code, 403)

    def test_perspective_and_action_identity_cannot_be_forged(self):
        created, joined, state = self.ready_game()
        other = self.client(self.b, joined)
        self.assertEqual(sum(bool(p['hand']) for p in state['game']['players']), 1)
        self.assertEqual(sum(bool(p['hand']) for p in other['game']['players']), 1)
        self.assertNotEqual(next(p['id'] for p in state['game']['players'] if p['human']), next(p['id'] for p in other['game']['players'] if p['human']))
        self.client(self.b, joined, '/game/action', {'gameId': 'forged-game', 'playerId': 'forged-player', 'promptId': 8, 'type': 'boolean', 'value': False})
        sent = self.a.engine.calls[-1][2]
        self.assertEqual(sent['playerId'], 'p-' + joined['participantId']);self.assertNotEqual(sent['gameId'], 'forged-game')

    def test_host_only_start_ready_gate_and_locked_setup(self):
        created = self.create();joined = self.join(created)
        with self.assertRaises(HTTPError): self.client(self.b, joined, '/start', {})
        with self.assertRaises(HTTPError): self.client(self.a, created, '/start', {})
        with self.assertRaises(HTTPError): self.client(self.a, created, '/ready', {'ready': True})
        with self.assertRaises(HTTPError): self.client(self.a, created, '/bots', {'count': 100})
        self.assertEqual(self.a.engine.games, {})

    def test_commander_damage_option_defaults_validates_and_reaches_native_start(self):
        self.assertTrue(self.create()['room']['config']['commanderDamage'])
        for value in ('false', 0, None, {}):
            with self.subTest(value=value), self.assertRaises(HTTPError):
                self.a.request('/client/rooms', {'format': 'Commander', 'commanderDamage': value})
        created = self.a.request('/client/rooms', {'format': 'Commander', 'maxPlayers': 2, 'commanderDamage': False})
        self.assertFalse(created['room']['config']['commanderDamage'])
        self.client(self.a, created, '/bots', {'count': 1})
        self.client(self.a, created, '/deck', {'deck': {'name': 'House rule deck', 'format': 'Commander', 'main': [{'name': 'Forest', 'count': 99}]}})
        self.client(self.a, created, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {})
        state = self.wait_phase(created, 'playing')
        sent = [body for _, path, body in self.a.engine.calls if path == '/multiplayer/start'][-1]
        self.assertFalse(sent['commanderDamage'])
        self.a.engine.games[state['game']['gameId']]['running'] = False
        self.client(self.a, created, '/rematch', {})
        self.wait_phase(created, 'playing')
        self.assertFalse([body for _, path, body in self.a.engine.calls if path == '/multiplayer/start'][-1]['commanderDamage'])

    def test_constructed_bots_keep_their_selected_decks_and_seats(self):
        created = self.create(maximum=4)
        joined = self.join(created)
        with patch('rooms.default_bot_deck', side_effect=[{'name': 'First'}, RoomError('Unavailable starter')]):
            with self.assertRaises(HTTPError):
                self.client(self.a, created, '/bots', {'count': 2})
        self.assertFalse(any(p['bot'] for p in self.client(self.a, created)['room']['members']))
        state = self.client(self.a, created, '/bots', {'count': 1})
        bot = next(p for p in state['room']['members'] if p['bot'])
        self.assertTrue(bot['deckId'].startswith('starter-commander-'))
        selected = {'id': 'local-bot-list', 'name': 'Goblin partners', 'format': 'Commander',
                    'commander': ['Rograkh, Son of Rohgahh', 'Kediss, Emberclaw Familiar'],
                    'main': [{'name': 'Mountain', 'count': 98}]}
        request = {'botSeatId': bot['id'], 'deck': selected}
        with self.assertRaises(HTTPError) as denied:
            self.client(self.b, joined, '/deck', request)
        self.assertEqual(denied.exception.code, 403)
        for invalid in (joined['participantId'], 'gone', None):
            with self.subTest(seat=invalid), self.assertRaises(HTTPError):
                self.client(self.a, created, '/deck', dict(request, botSeatId=invalid))
        with self.assertRaises(HTTPError):
            self.client(self.a, created, '/deck', dict(request, deck=dict(selected, format='Modern')))
        self.client(self.a, created, '/deck', request)
        for count in (2, 1, 2):
            state = self.client(self.a, created, '/bots', {'count': count})
            bots = [p for p in state['room']['members'] if p['bot']]
            self.assertEqual((bots[0]['id'], bots[0]['deckId'], bots[0]['deckName'], bots[0]['ready']),
                             (bot['id'], selected['id'], selected['name'], True))
        guest = self.client(self.b, joined)
        self.assertNotIn('local-bot-list', json.dumps(guest))
        self.assertNotIn('Rograkh', json.dumps(guest))
        for gateway, connection in ((self.a, created), (self.b, joined)):
            self.client(gateway, connection, '/deck', {'deck': {'name': 'Human deck', 'format': 'Commander'}})
            self.client(gateway, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {})
        self.wait_phase(created, 'playing')
        seats = [body['seats'] for _, path, body in self.a.engine.calls if path == '/multiplayer/start'][-1]
        submitted = {p['seatId']: p['deck'] for p in seats}
        self.assertEqual(submitted[bot['id']], selected)
        starter = submitted[bots[1]['id']]
        self.assertTrue(starter['id'].startswith('starter-commander-'))
        self.assertEqual(sum(card['count'] for card in starter['main'] + starter['commander']), 100)
        self.assertNotEqual(starter['commander'], selected['commander'])

    def test_constructed_bot_without_a_starter_needs_its_own_deck(self):
        created = self.a.request('/client/rooms', {'format': 'Legacy', 'maxPlayers': 2})
        host_deck = {'name': 'Host deck', 'format': 'Legacy'}
        self.client(self.a, created, '/deck', {'deck': host_deck})
        self.client(self.a, created, '/ready', {'ready': True})
        state = self.client(self.a, created, '/bots', {'count': 1})
        bot = next(p for p in state['room']['members'] if p['bot'])
        self.assertFalse(bot['ready'])
        self.assertIsNone(bot['deckName'])
        with self.assertRaises(HTTPError) as unassigned:
            self.client(self.a, created, '/start', {})
        self.assertEqual(unassigned.exception.code, 409)
        self.assertFalse(self.a.engine.games)
        bot_deck = dict(host_deck, name='Bot deck')
        self.client(self.a, created, '/deck', {'botSeatId': bot['id'], 'deck': bot_deck})
        self.client(self.a, created, '/start', {})
        self.wait_phase(created, 'playing')
        seats = [body['seats'] for _, path, body in self.a.engine.calls if path == '/multiplayer/start'][-1]
        self.assertEqual([p['deck'] for p in seats], [host_deck, bot_deck])

    def test_constructed_rematch_requires_finished_game_and_other_human_consent(self):
        created, joined, state = self.ready_game()
        old_game = state['game']['gameId']
        with self.assertRaises(HTTPError): self.client(self.a, created, '/rematch', {})
        self.a.engine.games[old_game]['running'] = False
        self.assertTrue(self.client(self.a, created)['room']['canRematch'])
        requested = self.client(self.b, joined, '/rematch', {})
        request = requested['room']['rematchRequest']
        self.assertEqual(request['requesterId'], joined['participantId'])
        self.assertEqual(self.client(self.a, created)['game']['gameId'], old_game)
        self.assertEqual(self.client(self.a, created)['room']['rematchRequest']['id'], request['id'])
        self.client(self.a, created, '/rematch-response', {'requestId': request['id'], 'accept': True})
        after = self.wait_phase(created, 'playing')
        self.assertNotEqual(old_game, after['game']['gameId'])
        self.assertNotIn(old_game, self.a.engine.games)
        self.assertEqual(len(after['room']['members']), 2)
        with self.assertRaises(HTTPError): self.client(self.b, joined, '/game/action', {'expectedGameId': old_game, 'type': 'concede'})

    def test_rematch_decline_cancel_and_stale_response_do_not_replace_a_game(self):
        created, joined, state = self.ready_game();old = state['game']['gameId']
        self.a.engine.games[old]['running'] = False
        requested = self.client(self.a, created, '/rematch', {})['room']['rematchRequest']
        with self.assertRaises(HTTPError): self.client(self.a, created, '/rematch-response', {'requestId': requested['id'], 'accept': True})
        with self.assertRaises(HTTPError): self.client(self.b, joined, '/rematch-response', {'requestId': 'old-request', 'accept': True})
        with self.assertRaises(HTTPError): self.client(self.b, joined, '/rematch-response', {'requestId': requested['id'], 'accept': 'true'})
        self.client(self.b, joined, '/rematch-response', {'requestId': requested['id'], 'accept': False})
        self.assertIsNone(self.client(self.a, created)['room']['rematchRequest'])
        self.assertIn(old, self.a.engine.games)
        fresh = self.client(self.b, joined, '/rematch', {})['room']['rematchRequest']
        self.assertNotEqual(fresh['id'], requested['id'])
        with self.assertRaises(HTTPError): self.client(self.a, created, '/rematch-response', {'requestId': requested['id'], 'accept': True})
        with self.assertRaises(HTTPError): self.client(self.a, created, '/rematch-cancel', {'requestId': fresh['id']})
        self.client(self.b, joined, '/rematch-cancel', {'requestId': fresh['id']})
        self.assertIn(old, self.a.engine.games)

    def test_rematch_requires_every_human_and_expired_request_never_restarts(self):
        created = self.create(maximum=3);first = self.join(created);second = self.join(created)
        for gateway, connection in ((self.a, created), (self.b, first), (self.b, second)):
            self.client(gateway, connection, '/deck', {'deck': {'name': 'Consent fixture', 'format': 'Commander', 'main': [{'name': 'Forest', 'count': 99}]}})
            self.client(gateway, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {})
        old = self.wait_phase(created, 'playing')['game']['gameId'];self.a.engine.games[old]['running'] = False
        requested = self.client(self.a, created, '/rematch', {})['room']['rematchRequest']
        partial = self.client(self.b, first, '/rematch-response', {'requestId': requested['id'], 'accept': True})
        self.assertEqual(partial['room']['phase'], 'playing');self.assertIn(old, self.a.engine.games)
        self.assertEqual(set(partial['room']['rematchRequest']['approvedSeatIds']), {created['participantId'], first['participantId']})
        room = self.a.registry.rooms[created['room']['id']]
        with room.lock: room.rematch_request['deadline'] = time.monotonic() - 1
        self.assertIsNone(self.client(self.b, second)['room']['rematchRequest'])
        with self.assertRaises(HTTPError): self.client(self.b, second, '/rematch-response', {'requestId': requested['id'], 'accept': True})
        self.assertIn(old, self.a.engine.games)
        fresh = self.client(self.a, created, '/rematch', {})['room']['rematchRequest']
        for connection in (first, second): self.client(self.b, connection, '/rematch-response', {'requestId': fresh['id'], 'accept': True})
        self.assertNotEqual(self.wait_phase(created, 'playing')['game']['gameId'], old)

    def test_native_capacities_and_draft_profile_validation(self):
        caps = self.a.request('/client/capabilities')
        self.assertEqual(next(p for p in caps['game']['formats'] if p['id'] == 'Commander')['maxPlayers'], 10)
        self.assertEqual(caps['draft']['maxPlayers'], 16)
        created = self.create(draft=True, maximum=16)
        self.assertEqual(created['room']['config']['maxPlayers'], 16)
        with self.assertRaises(HTTPError): self.create(draft=True, maximum=17)

    def test_random_pool_is_independent_of_hidden_traditional_pack_slots(self):
        for selected in (None, [], ['M20', 'M21'], ['M20', 'M20']):
            with self.subTest(selected=selected):
                draft = {'mode': 'random', 'profile': 'Limited', 'pairing': 'elimination', 'sets': ['M14'] * 3}
                if selected is not None: draft['randomSets'] = selected
                created = self.a.request('/client/rooms', {'kind': 'draft', 'name': 'Random pool', 'maxPlayers': 4, 'draft': draft})
                self.client(self.a, created, '/bots', {'count': 3})
                self.client(self.a, created, '/ready', {'ready': True})
                self.client(self.a, created, '/start', {});self.wait_phase(created, 'drafting')
                sent = [body['config'] for _, path, body in self.a.engine.calls if path == '/draft/start'][-1]
                self.assertNotIn('sets', sent)
                self.assertEqual(sent['randomSets'], list(dict.fromkeys(selected or [])))
                self.assertEqual(sent['pairing'], 'elimination')
                self.assertEqual(sent['profile'], 'random')
                self.client(self.a, created, '/leave', {})

    def test_random_pool_rejects_unoffered_sets_and_non_array_values(self):
        for selected in ({}, 'M20', None, ['not-a-supported-set'], [True]):
            with self.subTest(selected=selected):
                with self.assertRaises(HTTPError) as error:
                    self.a.request('/client/rooms', {'kind': 'draft', 'name': 'Invalid pool', 'maxPlayers': 4,
                        'draft': {'mode': 'random', 'profile': 'Limited', 'randomSets': selected}})
                self.assertEqual(error.exception.code, 400)
        self.assertFalse(self.a.engine.drafts)

    def test_draft_private_packs_and_rejected_deck_never_becomes_ready(self):
        created = self.create(draft=True, maximum=4);joined = self.join(created)
        self.client(self.a, created, '/bots', {'count': 2})
        self.client(self.a, created, '/ready', {'ready': True});self.client(self.b, joined, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});state = self.wait_phase(created, 'drafting')
        other = self.client(self.b, joined)
        self.assertNotEqual(state['draft']['pack'], other['draft']['pack'])
        self.assertNotIn(other['draft']['pack'][0]['id'], json.dumps(state))
        native = next(iter(self.a.engine.drafts.values()));native['status'] = 'building'
        self.client(self.a, created);self.client(self.b, joined)
        with self.assertRaises(HTTPError) as error: self.client(self.b, joined, '/draft/deck', {'main': ['forged'], 'basics': {}})
        self.assertEqual(error.exception.code, 422)
        state = self.client(self.a, created)
        self.assertFalse(next(p for p in state['room']['members'] if p['id'] == joined['participantId'])['ready'])

    def test_host_close_and_guest_leave_are_scoped(self):
        created, joined, _ = self.ready_game()
        self.client(self.b, joined, '/leave', {})
        self.assertEqual(self.a.engine.calls[-1][1], '/multiplayer/action')
        self.assertEqual(self.a.engine.calls[-1][2]['type'], 'concede')
        self.assertEqual(len(self.a.engine.games), 1)
        self.client(self.a, created, '/leave', {})
        self.assertEqual(self.a.engine.games, {})

    def test_old_round_action_is_rejected_without_forwarding(self):
        created, joined, _ = self.ready_game()
        count = len(self.a.engine.calls)
        with self.assertRaises(HTTPError) as error:
            self.client(self.b, joined, '/game/action', {'expectedGameId': 'previous-round', 'type': 'boolean', 'value': True})
        self.assertEqual(error.exception.code, 409)
        self.assertEqual(count, len(self.a.engine.calls))

    def test_explicit_draft_leave_surrenders_only_departed_native_seat(self):
        created = self.create(draft=True, maximum=4);joined = self.join(created)
        self.client(self.a, created, '/bots', {'count': 2})
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'drafting')
        self.client(self.b, joined, '/leave', {})
        state = self.client(self.a, created)
        self.assertTrue(next(p for p in state['room']['members'] if p['id'] == joined['participantId'])['bot'])
        forfeits = [body for method, path, body in self.a.engine.calls if path == '/draft/forfeit']
        self.assertEqual(forfeits[0]['seatId'], joined['participantId'])
        self.assertFalse(next(p for p in state['room']['members'] if p['id'] == created['participantId'])['bot'])

    def test_close_during_native_start_reclaims_late_game(self):
        engine = self.a.engine;original = engine.call;entered = threading.Event();release = threading.Event()
        def delayed(method, path, body=None, timeout=None):
            if path == '/multiplayer/start': entered.set();release.wait(2)
            return original(method, path, body, timeout=timeout)
        engine.call = delayed
        created = self.create();joined = self.join(created)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/deck', {'deck': {'name': 'Deck', 'format': 'Commander'}})
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});self.assertTrue(entered.wait(2))
        self.client(self.a, created, '/leave', {});release.set()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if any(path == '/multiplayer/stop' for _, path, _ in engine.calls): break
            time.sleep(.01)
        self.assertEqual(engine.games, {})
        self.assertEqual(self.a.registry.get(created['room']['id']).phase, 'closed')

    def test_native_draw_requests_same_pairing_rematch(self):
        created = self.create(draft=True, maximum=4);joined = self.join(created)
        self.client(self.a, created, '/bots', {'count': 2})
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'drafting')
        native = next(iter(self.a.engine.drafts.values()));native['status'] = 'building';native['elimination'] = True
        self.client(self.a, created);self.client(self.b, joined)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/draft/deck', {'main': [], 'basics': {}})
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'playing')
        room = self.a.registry.get(created['room']['id']);first = next(iter(room.games.values()));old_game = first['gameId']
        self.a.engine.games[old_game]['running'] = False
        self.a.registry.collect_results(room)
        rematch = room.games[first['id']]
        self.assertNotEqual(rematch['gameId'], old_game)
        self.assertEqual(rematch['seatIds'], first['seatIds'])
        self.assertFalse(rematch['finished'])

    def test_host_close_cleans_native_draft_with_bye(self):
        created = self.create(draft=True, maximum=5)
        room = self.a.registry.get(created['room']['id'])
        room.draft_id = 'bye-draft';self.a.engine.drafts['bye-draft'] = {}
        room.games['bye-1'] = {'id': 'bye-1', 'seatIds': [created['participantId']], 'finished': True}
        self.client(self.a, created, '/leave', {})
        self.assertNotIn('bye-draft', self.a.engine.drafts)

    def test_departure_while_paired_game_starts_wakes_captured_human(self):
        created = self.create(draft=True, maximum=4);joined = self.join(created)
        self.client(self.a, created, '/bots', {'count': 2})
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'drafting')
        native = next(iter(self.a.engine.drafts.values()));native['status'] = 'building'
        self.client(self.a, created);self.client(self.b, joined)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/draft/deck', {'main': [], 'basics': {}})
        entered = threading.Event();release = threading.Event();original = self.a.engine.call
        def delayed(method, path, body=None, timeout=None):
            if path == '/multiplayer/start' and any(s['seatId'] == joined['participantId'] for s in body['seats']):
                body = copy.deepcopy(body);entered.set();release.wait(2)
            return original(method, path, body, timeout=timeout)
        self.a.engine.call = delayed
        self.client(self.a, created, '/start', {});self.assertTrue(entered.wait(2))
        self.client(self.b, joined, '/leave', {});release.set();self.wait_phase(created, 'playing')
        concessions = [body for _, path, body in self.a.engine.calls if path == '/multiplayer/action']
        self.assertTrue(any(body['playerId'] == 'p-' + joined['participantId'] and body['type'] == 'concede' for body in concessions))
        room = self.a.registry.get(created['room']['id'])
        self.assertNotIn(joined['participantId'], room.assignments)

    def test_lost_native_start_response_retries_exact_accepted_game(self):
        created = self.create();joined = self.join(created)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/deck', {'deck': {'name': 'Deck', 'format': 'Commander'}})
            self.client(server, connection, '/ready', {'ready': True})
        original = self.a.engine.call;lost = [False]
        def lose_once(method, path, body=None, timeout=None):
            result = original(method, path, body, timeout=timeout)
            if path == '/multiplayer/start' and not lost[0]:
                lost[0] = True;raise RoomError('Simulated response loss after accepted start', 503)
            return result
        self.a.engine.call = lose_once
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'lobby')
        self.assertEqual(len(self.a.engine.games), 1)
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'playing')
        self.assertEqual(len(self.a.engine.games), 1)
        starts = [body for _, path, body in self.a.engine.calls if path == '/multiplayer/start']
        self.assertEqual(starts[0], starts[1])

    def test_lost_round_response_does_not_advance_native_twice(self):
        created = self.create(draft=True, maximum=4);joined = self.join(created)
        self.client(self.a, created, '/bots', {'count': 2})
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/ready', {'ready': True})
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'drafting')
        native = next(iter(self.a.engine.drafts.values()));native['status'] = 'building'
        self.client(self.a, created);self.client(self.b, joined)
        for server, connection in ((self.a, created), (self.b, joined)):
            self.client(server, connection, '/draft/deck', {'main': [], 'basics': {}})
        original = self.a.engine.call;lost = [False]
        def lose_once(method, path, body=None, timeout=None):
            result = original(method, path, body, timeout=timeout)
            if path == '/draft/next-round' and not lost[0]:
                lost[0] = True;raise RoomError('Simulated response loss after accepted round', 503)
            return result
        self.a.engine.call = lose_once
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'building')
        self.assertEqual(native['round'], 1)
        self.client(self.a, created, '/start', {});self.wait_phase(created, 'playing')
        self.assertEqual(native['round'], 1)
        self.assertEqual(len(self.a.engine.games), 2)

    def test_public_host_disables_proxy_client_endpoints(self):
        self.a.gateway.client_api = False
        with self.assertRaises(HTTPError) as error: self.a.request('/client/capabilities')
        self.assertEqual(error.exception.code, 403)
        self.assertTrue(self.a.request('/capabilities')['network']['codeOnly'])

    def test_guest_can_leave_after_host_closed_or_room_expired(self):
        created = self.create();joined = self.join(created)
        self.client(self.a, created, '/leave', {})
        self.assertEqual(self.client(self.b, joined)['room']['phase'], 'closed')
        self.assertTrue(self.client(self.b, joined, '/leave', {})['left'])
        created = self.create();joined = self.join(created)
        self.a.registry.rooms.pop(created['room']['id'])
        self.assertTrue(self.client(self.b, joined, '/leave', {})['left'])
        self.assertNotIn(joined['connectionId'], self.b.gateway.connections)

    def test_browser_origins_and_non_json_commands_are_rejected(self):
        with self.assertRaises(HTTPError) as error: self.a.request('/client/rooms', {}, headers={'Origin': 'https://unrelated.example'})
        self.assertEqual(error.exception.code, 403)
        with self.assertRaises(HTTPError) as error: self.a.request('/client/rooms', {}, headers={'Content-Type': 'text/plain'})
        self.assertEqual(error.exception.code, 415)

    def test_invite_decoder_rejects_non_http_and_embedded_credentials(self):
        for url in ('file:///tmp/test', 'http://user:secret@example.com', 'http://host:99999', 'https://example.com/?key=x'):
            with self.assertRaises(RoomError): invite(url, 'room12345', 'secret12345')


if __name__ == '__main__': unittest.main()
