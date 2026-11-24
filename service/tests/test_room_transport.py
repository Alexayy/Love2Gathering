"""Real room HTTP timeout budgets; lost replies never duplicate membership or commands."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rooms import JSONClient, Member, MembershipRequests, Registry, Room, RoomError
from test_rooms import RunningGateway


@contextmanager
def delayed_server(delay=.2):
    calls = []
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def send(self, value):
            raw = json.dumps(value).encode()
            self.send_response(200);self.send_header('Content-Length', str(len(raw)));self.end_headers()
            try: self.wfile.write(raw)
            except (BrokenPipeError, ConnectionResetError): pass
        def do_GET(self):
            calls.append(('GET', self.path))
            time.sleep(delay)
            self.send({'status': 'competing', 'players': [], 'gameId': 'native-game', 'running': True})
        def do_POST(self):
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
            calls.append(('POST', self.path))
            if self.path == '/lost-ack': time.sleep(delay)
            self.send({'accepted': True})
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler);server.daemon_threads = True
    worker = threading.Thread(target=server.serve_forever, daemon=True);worker.start()
    try: yield f'http://127.0.0.1:{server.server_port}', calls
    finally: server.shutdown();server.server_close();worker.join()


class RoomTransportTests(unittest.TestCase):
    def test_each_seats_mana_only_preference_survives_a_confirmed_rematch(self):
        host, guest = RunningGateway(), RunningGateway()
        try:
            created = host.request('/client/rooms', {'name': 'Priority preferences', 'playerName': 'Host',
                                   'kind': 'constructed', 'format': 'Commander', 'maxPlayers': 2,
                                   'priority': {'autoPass': False, 'passWithOnlyMana': False}})
            joined = guest.request('/client/join', {'code': created['room']['inviteCode'], 'name': 'Guest'})
            for server, connection in ((host, created), (guest, joined)):
                base = '/client/rooms/' + connection['connectionId']
                server.request(base + '/deck', {'deck': {'name': 'Private deck', 'format': 'Commander'}})
                server.request(base + '/ready', {'ready': True})
            host_base = '/client/rooms/' + created['connectionId'];guest_base = '/client/rooms/' + joined['connectionId']
            host.request(host_base + '/start', {})
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                state = host.request(host_base)
                if state['room']['phase'] == 'playing': break
                time.sleep(.01)
            self.assertEqual(state['room']['phase'], 'playing')
            original = host.engine.call
            def priority(method, path, body=None, timeout=None):
                if path == '/multiplayer/priority':
                    return {'gameId': body['gameId'], 'priority': {'autoPass': True, 'passWithOnlyMana': True,
                            'stops': {'own': ['END_TURN'], 'opponent': []}}}
                return original(method, path, body, timeout=timeout)
            host.engine.call = priority
            guest.request(guest_base + '/game/priority', {'command': 'configure', 'autoPass': True, 'passWithOnlyMana': True})
            room = host.registry.get(created['room']['id'])
            self.assertTrue(room.members[joined['participantId']].priority['passWithOnlyMana'])
            self.assertFalse(room.members[created['participantId']].priority['passWithOnlyMana'])
            old = state['game']['gameId'];host.engine.games[old]['running'] = False
            requested = host.request(host_base + '/rematch', {})
            guest.request(guest_base + '/rematch-response', {'requestId': requested['room']['rematchRequest']['id'], 'accept': True})
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                state = host.request(host_base)
                if state['room']['phase'] == 'playing' and state.get('game', {}).get('gameId') != old: break
                time.sleep(.01)
            seats = host.engine.games[state['game']['gameId']]['seats']
            by_seat = {seat['seatId']: seat['priority'] for seat in seats}
            self.assertTrue(by_seat[joined['participantId']]['passWithOnlyMana'])
            self.assertFalse(by_seat[created['participantId']]['autoPass'])
        finally: guest.close();host.close()

    def test_create_and_join_retries_reuse_exact_room_and_authenticated_seat(self):
        host, guest = RunningGateway(), RunningGateway()
        try:
            config = {'name': 'Idempotent room', 'playerName': 'Host', 'kind': 'constructed',
                      'format': 'Commander', 'maxPlayers': 2, 'connectionRequestId': 'desktop-create-intent-0001'}
            original = host.registry.membership_result;lost = [False]
            def lose_create(identity):
                result = original(identity)
                if not lost[0]:
                    lost[0] = True
                    raise RoomError('Simulated response loss after room creation', 503, kind='outcome_unknown')
                return result
            host.registry.membership_result = lose_create
            with self.assertRaises(HTTPError): host.request('/client/rooms', config)
            self.assertEqual(len(host.registry.rooms), 1)
            created = host.request('/client/rooms', config)
            repeated = host.request('/client/rooms', config)
            self.assertEqual(created['connectionId'], repeated['connectionId'])
            self.assertEqual(created['room']['id'], repeated['room']['id'])
            self.assertEqual(len(host.registry.rooms), 1)
            join = {'code': created['room']['inviteCode'], 'name': 'Guest', 'connectionRequestId': 'desktop-join-intent-0001'}
            lost[0] = False
            with self.assertRaises(HTTPError): guest.request('/client/join', join)
            room = host.registry.get(created['room']['id'])
            self.assertEqual(len(room.members), 2)
            joined = guest.request('/client/join', join)
            same = guest.request('/client/join', join)
            self.assertEqual(joined['participantId'], same['participantId'])
            self.assertEqual(joined['connectionId'], same['connectionId'])
            self.assertEqual(len(room.members), 2)
            self.assertNotIn('memberToken', joined)
            with self.assertRaises(HTTPError) as conflict:
                guest.request('/client/join', dict(join, name='Another player'))
            self.assertEqual(conflict.exception.code, 409)
            self.assertEqual(len(room.members), 2)
        finally: guest.close();host.close()

    def test_legacy_unknown_join_outcome_is_fenced_instead_of_creating_another_seat(self):
        host, guest = RunningGateway(), RunningGateway()
        try:
            created = host.request('/client/rooms', {'name': 'Legacy room', 'playerName': 'Host',
                                   'kind': 'constructed', 'format': 'Commander', 'maxPlayers': 2})
            guest.gateway.membership_hosts[host.url] = False
            original = host.registry.membership_result
            def lose_reply(identity):
                original(identity)
                raise RoomError('Simulated legacy lost reply', 503, kind='outcome_unknown')
            host.registry.membership_result = lose_reply
            payload = {'code': created['room']['inviteCode'], 'name': 'Guest', 'connectionRequestId': 'desktop-legacy-intent-0001'}
            with self.assertRaises(HTTPError): guest.request('/client/join', payload)
            with self.assertRaises(HTTPError) as retry: guest.request('/client/join', payload)
            self.assertEqual(retry.exception.code, 503)
            self.assertEqual(len(host.registry.get(created['room']['id']).members), 2)
        finally: guest.close();host.close()

    def test_legacy_incomplete_or_failed_reply_after_allocation_never_reposts_join(self):
        for malformed in (True, False):
            with self.subTest(malformed=malformed):
                host, guest = RunningGateway(), RunningGateway()
                try:
                    created = host.request('/client/rooms', {'name': 'Legacy partial reply', 'playerName': 'Host',
                                           'kind': 'constructed', 'format': 'Commander', 'maxPlayers': 3})
                    guest.gateway.membership_hosts[host.url] = False
                    original = host.registry.membership_result
                    def incomplete(identity):
                        result = original(identity)
                        if malformed:
                            result.pop('memberToken');return result
                        raise RoomError('Server failed after allocation', 500)
                    host.registry.membership_result = incomplete
                    payload = {'code': created['room']['inviteCode'], 'name': 'Guest', 'connectionRequestId': 'desktop-partial-intent-0001'}
                    with self.assertRaises(HTTPError): guest.request('/client/join', payload)
                    with self.assertRaises(HTTPError): guest.request('/client/join', payload)
                    self.assertEqual(len(host.registry.get(created['room']['id']).members), 2)
                finally: guest.close();host.close()

    def test_membership_cache_fences_inflight_requests_scopes_payloads_and_expiry(self):
        memo = MembershipRequests();entered, release = threading.Event(), threading.Event();results = []
        def work(key=None):
            entered.set();release.wait(1);return {'identity': key}
        key = 'one-stable-desktop-intent';thread = threading.Thread(target=lambda: results.append(memo.run('join:a', key, {'name': 'Player'}, work)))
        thread.start();self.assertTrue(entered.wait(1))
        try:
            with self.assertRaises(RoomError) as pending: memo.run('join:a', key, {'name': 'Player'}, work)
            self.assertEqual(pending.exception.kind, 'connection_pending')
            with self.assertRaises(RoomError): memo.run('join:b', key, {'name': 'Player'}, work)
            with self.assertRaises(RoomError): memo.run('join:a', key, {'name': 'Changed'}, work)
        finally: release.set();thread.join(2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(memo.run('join:a', key, {'name': 'Player'}, lambda _: self.fail('Repeated membership operation')), results[0])
        with patch('rooms.MEMBERSHIP_REQUEST_LIMIT', 1):
            with self.assertRaises(RoomError): memo.run('create', 'another-desktop-intent', {}, lambda _: {})
        with patch('rooms.MEMBERSHIP_REQUEST_TTL', -1), patch('rooms.MEMBERSHIP_REQUEST_LIMIT', 1):
            self.assertEqual(memo.run('create', 'another-desktop-intent', {}, lambda _: {'new': True}), {'new': True})

    def test_native_reads_have_shorter_budget_than_mutations_and_no_implicit_retry(self):
        with delayed_server() as (url, calls):
            client = JSONClient(url, timeout=1, read_timeout=.04)
            started = time.monotonic()
            with self.assertRaises(RoomError) as failure: client.call('GET', '/slow-state')
            self.assertLess(time.monotonic() - started, .5)
            self.assertEqual(failure.exception.status, 503)
            self.assertTrue(failure.exception.retryable)
            self.assertEqual(failure.exception.kind, 'transport')
            self.assertEqual(client.call('POST', '/action', {'promptId': 19}), {'accepted': True})
            self.assertEqual(calls.count(('GET', '/slow-state')), 1)
            self.assertEqual(calls.count(('POST', '/action')), 1)

    def test_lost_mutation_acknowledgement_is_unknown_not_safely_retryable(self):
        with delayed_server() as (url, calls):
            client = JSONClient(url, timeout=.04)
            with self.assertRaises(RoomError) as failure: client.call('POST', '/lost-ack', {'promptId': 17})
            self.assertFalse(failure.exception.retryable)
            self.assertEqual(failure.exception.kind, 'outcome_unknown')
            self.assertEqual(calls, [('POST', '/lost-ack')])

    def test_composed_private_state_reads_share_one_total_deadline(self):
        with delayed_server(.1) as (url, calls):
            owner = Member('Budget fixture')
            room = Room({'kind': 'draft', 'name': 'Budget', 'maxPlayers': 2}, owner, url)
            room.phase = 'playing';room.draft_id = 'native-draft'
            room.assignments[owner.id] = {'gameId': 'native-game', 'playerId': 'native-player'}
            registry = Registry(JSONClient(url), url)
            started = time.monotonic()
            with patch('rooms.ENVELOPE_READ_BUDGET', .17), self.assertRaises(RoomError):
                registry.envelope(room, owner)
            self.assertLess(time.monotonic() - started, .5)
            self.assertEqual(len(calls), 2)  # Pairings cannot add another timeout window.
            self.assertEqual(room.assignments[owner.id]['gameId'], 'native-game')
            self.assertFalse(owner.left)

    def test_real_gateway_recovers_same_authenticated_seat_after_delayed_read(self):
        gateway = RunningGateway()
        try:
            created = gateway.request('/client/rooms', {'name': 'Timeout fixture', 'playerName': 'Host',
                                      'kind': 'constructed', 'format': 'Commander', 'maxPlayers': 2})
            connection_id = created['connectionId'];path = '/client/rooms/' + connection_id
            member_id = created['participantId'];original = gateway.registry.envelope
            gate, entered = threading.Event(), threading.Event()
            def held(*args, **kwargs):
                entered.set();gate.wait(1);return original(*args, **kwargs)
            gateway.registry.envelope = held
            gateway.gateway.connections[connection_id]['client'].read_timeout = .05
            try:
                with self.assertRaises(HTTPError) as failure: gateway.request(path)
                self.assertTrue(entered.is_set())
                self.assertEqual(failure.exception.code, 503)
                problem = json.loads(failure.exception.read())
                self.assertTrue(problem['retryable'])
                self.assertEqual(problem['kind'], 'transport')
                self.assertIn(connection_id, gateway.gateway.connections)
            finally:
                gate.set();gateway.registry.envelope = original
            recovered = gateway.request(path)
            self.assertEqual(recovered['participantId'], member_id)
            self.assertEqual(len(recovered['room']['members']), 1)
            room = gateway.registry.get(created['room']['id'])
            self.assertFalse(room.members[member_id].left)
        finally: gateway.close()


if __name__ == '__main__': unittest.main()
