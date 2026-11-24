#!/usr/bin/env python3
"""Private room-code gateway. XMage owns games, packs, picks and pairings.

Each desktop has a local client gateway. Its public room API can be advertised
on a LAN, or served through a configured HTTPS origin. Invitations contain the
origin and a random room secret; there is deliberately no room-list endpoint.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
from profiles import normalize_profile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid

MAX_BODY = 8 * 1024 * 1024
MAX_RESPONSE = 16 * 1024 * 1024
API_VERSION = 1
PUBLIC_REQUEST_TIMEOUT = 6
NATIVE_READ_TIMEOUT = 2.5
ENVELOPE_READ_BUDGET = 5
MEMBERSHIP_REQUEST_LIMIT = 1024
MEMBERSHIP_REQUEST_TTL = 3600


class RoomError(ValueError):
    def __init__(self, message, status=400, *, retryable=False, kind=None):
        super().__init__(message)
        self.status = status
        self.retryable = retryable
        self.kind = kind


class MembershipRequests:
    """Bounded private identities for explicit retry of one create/join intent.

    This does not replay gameplay mutations. Requests currently completing are
    fenced, and a key may never be reused for another operation or payload.
    """
    def __init__(self):
        self.lock = threading.RLock()
        self.entries = {}

    def run(self, scope, request_id, value, action):
        if request_id is None:
            return action(None)  # Existing clients remain usable without retry guarantees.
        if not isinstance(request_id, str) or not 16 <= len(request_id) <= 160 or any(ord(c) < 33 or ord(c) > 126 for c in request_id):
            raise RoomError('Invalid connection request identity')
        fingerprint = hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode()).hexdigest()
        now = time.monotonic()
        with self.lock:
            for key, record in list(self.entries.items()):
                if not record['busy'] and now - record['touched'] > MEMBERSHIP_REQUEST_TTL:
                    self.entries.pop(key, None)
            record = self.entries.get(request_id)
            if record is not None and (record['scope'] != scope or record['fingerprint'] != fingerprint):
                raise RoomError('Connection request identity conflicts with another operation or payload', 409)
            if record is not None:
                record['touched'] = now
                if record.get('result') is not None:
                    return copy.deepcopy(record['result'])
                if record.get('error'):
                    raise RoomError(record['error'], 503, kind='outcome_unknown')
                if record['busy']:
                    raise RoomError('This connection request is still completing. Retry the same request.', 503, kind='connection_pending')
            else:
                if len(self.entries) >= MEMBERSHIP_REQUEST_LIMIT:
                    raise RoomError('Too many pending connection requests; retry later', 503)
                record = {'scope': scope, 'fingerprint': fingerprint, 'busy': False, 'touched': now}
                self.entries[request_id] = record
            record['busy'] = True
            # A remote create/join key stays stable even when its reply is lost.
            record.setdefault('upstreamId', secrets.token_urlsafe(32))
        try:
            result = action(record['upstreamId'])
        except RoomError as exc:
            with self.lock:
                record['busy'] = False;record['touched'] = time.monotonic()
                if exc.kind == 'legacy_outcome_unknown':
                    record['error'] = 'The room host did not confirm this connection and does not support safe membership retries. Check the existing seat with the host before a new connection.'
            raise
        except Exception:
            with self.lock:
                record['busy'] = False
                record['error'] = 'Connection outcome is unknown. The same request cannot safely create another seat.'
            raise
        with self.lock:
            record['result'] = copy.deepcopy(result);record['busy'] = False;record['touched'] = time.monotonic()
        return result


def origin(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 1024:
        raise RoomError('Invalid room server address')
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise RoomError('Invalid room server address') from exc
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise RoomError('Room server must use HTTP or HTTPS without credentials or query parameters')
    if port is not None and not 1 <= port <= 65535:
        raise RoomError('Invalid room server port')
    if any(ord(char) < 33 or ord(char) == 127 for char in value):
        raise RoomError('Invalid room server address')
    return value.rstrip('/')


def invite(server, room_id, secret):
    payload = json.dumps({'v': 1, 'server': origin(server), 'room': room_id, 'key': secret}, separators=(',', ':')).encode()
    return 'L2G1-' + base64.urlsafe_b64encode(payload).decode().rstrip('=')


def decode_invite(code):
    if not isinstance(code, str) or len(code) > 2048:
        raise RoomError('Paste a complete room code')
    code = ''.join(code.split())
    if not code.startswith('L2G1-'):
        raise RoomError('This is not a Love: 2 Gathering room code')
    encoded = code[5:]
    try:
        value = json.loads(base64.b64decode(encoded + '=' * (-len(encoded) % 4), altchars=b'-_', validate=True))
    except (ValueError, UnicodeError) as exc:
        raise RoomError('Invalid room code') from exc
    if not isinstance(value, dict) or value.get('v') != 1:
        raise RoomError('Unsupported room code version')
    value['server'] = origin(value.get('server'))
    for key in ('room', 'key'):
        if not isinstance(value.get(key), str) or not 8 <= len(value[key]) <= 100 or not all(c.isalnum() or c in '-_' for c in value[key]):
            raise RoomError('Invalid room code')
    return value


def name(value, label='Player name', maximum=120):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum or any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise RoomError(f'{label} must contain 1 to {maximum} printable characters')
    return value.strip()


def integer(value, low, high, label):
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise RoomError(f'{label} must be an integer from {low} to {high}')
    return value


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # Never forward room credentials to a different origin.


class JSONClient:
    def __init__(self, server, token=None, timeout=PUBLIC_REQUEST_TIMEOUT, read_timeout=PUBLIC_REQUEST_TIMEOUT):
        self.server = origin(server)
        self.token = token
        self.timeout = timeout
        self.read_timeout = read_timeout
        self.opener = build_opener(NoRedirects())

    def call(self, method, path, body=None, token=None, timeout=None):
        headers = {'Accept': 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'Love2Gathering-Rooms/1.0'}
        credential = self.token if token is None else token
        if credential:
            headers['Authorization'] = 'Bearer ' + credential
        payload = None if body is None else json.dumps(body, ensure_ascii=False, allow_nan=False).encode()
        if payload is not None and len(payload) > MAX_BODY:
            raise RoomError('Room request exceeds 8 MiB')
        request = Request(self.server + path, data=payload, headers=headers, method=method)
        try:
            budget = min(self.timeout, self.read_timeout) if method == 'GET' else self.timeout
            with self.opener.open(request, timeout=budget if timeout is None else min(budget, timeout)) as response:
                raw = response.read(MAX_RESPONSE + 1)
                if len(raw) > MAX_RESPONSE:
                    raise RoomError('Room response exceeds its resource limit', 502)
                return json.loads(raw)
        except HTTPError as exc:
            problem = {}
            try:
                problem = json.loads(exc.read(MAX_BODY))
                message = str(problem.get('error', 'Room request failed'))
            except (ValueError, AttributeError):
                message = 'Room request failed: HTTP ' + str(exc.code)
            raise RoomError(message, exc.code, retryable=bool(problem.get('retryable')) if isinstance(problem, dict) else False,
                            kind=problem.get('kind') if isinstance(problem, dict) else None) from exc
        except (URLError, TimeoutError, OSError, ValueError) as exc:
            if isinstance(exc, RoomError):
                raise
            # Reads are safe to retry. A timed-out mutation may already have
            # reached XMage, so it must be reconciled by reading the same seat.
            raise RoomError('Room response is unavailable: ' + str(exc), 503,
                            retryable=method == 'GET', kind='transport' if method == 'GET' else 'outcome_unknown') from exc


class Member:
    def __init__(self, player_name, bot=False, options=None):
        self.id = str(uuid.uuid4())
        self.name = name(player_name, maximum=80)
        self.bot = bot
        self.token = secrets.token_urlsafe(32)
        self.ready = bot
        self.deck = None
        self.last_seen = time.monotonic()
        self.left = False
        options = options or {}
        try: self.profile = normalize_profile(options.get('profile'), self.name)
        except ValueError as exc: raise RoomError(str(exc)) from exc
        self.name = self.profile['name']
        settings = options.get('settings', {})
        self.settings = {key: settings[key] for key in ('manualTriggers', 'autoMana')
                         if isinstance(settings, dict) and isinstance(settings.get(key), bool)}
        priority = options.get('priority', {})
        if not isinstance(priority, dict) or len(json.dumps(priority)) > 65536:
            raise RoomError('Invalid priority preferences')
        self.priority = copy.deepcopy(priority)


def default_bot_deck(fmt, seats):
    """Prefer a bundled list that the fewest seats at this table already use."""
    directory = Path(__file__).resolve().parents[1] / 'decks'
    catalog = json.loads((directory / 'library.json').read_text(encoding='utf-8'))
    candidates = [item for item in catalog if item['format'] == fmt]
    if not candidates:
        return None
    used = [seat.deck.get('name') for seat in seats if seat.deck]
    selected = min(candidates, key=lambda item: used.count(item['name']))
    deck = json.loads((directory / (selected['id'] + '.json')).read_text(encoding='utf-8'))
    # This is the immutable Starter entry, even if a host has an edited original.
    deck['id'] = 'starter-' + selected['id']
    return deck


class Room:
    def __init__(self, config, owner, public_origin):
        self.id = secrets.token_urlsafe(12)
        self.secret = secrets.token_urlsafe(24)
        self.code = invite(public_origin, self.id, self.secret)
        self.config = config
        self.host_id = owner.id
        self.members = {owner.id: owner}
        self.revision = 1
        self.phase = 'lobby'
        self.error = None
        self.draft_id = None
        self.draft_public = None
        self.games = {}
        self.assignments = {}
        self.pending_round = None
        self.next_round_payload = None
        self.round_index = 0
        self.rematch_index = 0
        self.rematch_request = None
        self.start_payload = None
        self.pair_payloads = {}
        self.pair_attempts = {}
        self.closed = False
        self.touched = time.monotonic()
        self.lock = threading.RLock()
        self.result_lock = threading.Lock()

    def changed(self):
        self.revision += 1
        self.touched = time.monotonic()

    def public(self, viewer):
        now = time.monotonic()
        if self.rematch_request and self.rematch_request['deadline'] <= now:
            self.rematch_request = None
            self.changed()
        return {'id': self.id, 'revision': self.revision, 'hostId': self.host_id,
                'name': self.config['name'], 'phase': self.phase, 'inviteCode': self.code,
                'config': copy.deepcopy(self.config), 'error': self.error,
                'rematchRequest': ({key: copy.deepcopy(value) for key, value in self.rematch_request.items()
                                    if key != 'deadline'} | {'remainingSeconds': max(0, int(self.rematch_request['deadline'] - now))}) if self.rematch_request else None,
                'members': [{'id': p.id, 'name': p.name, 'bot': p.bot, 'ready': p.ready,
                             'profile': copy.deepcopy(p.profile),
                             'connected': p.bot or (not p.left and now - p.last_seen < 20),
                             'deckName': p.deck.get('name') if p.deck else None,
                             **({'deckId': p.deck['id']} if viewer.id == self.host_id and p.bot and p.deck
                                and isinstance(p.deck.get('id'), str) else {})}
                            for p in self.members.values()],
                'draft': self.draft_public,
                'matches': [{key: value for key, value in match.items() if key in ('id', 'seatIds', 'finished', 'winnerSeatId', 'error')}
                            for match in self.games.values()]}


class Registry:
    def __init__(self, engine, public_origin, recording_port=0, max_rooms=32):
        self.engine = engine
        self.public_origin = origin(public_origin)
        self.recording_port = recording_port
        self.max_rooms = max_rooms
        self.rooms = {}
        self.lock = threading.RLock()
        self.cap_cache = None
        self.cap_stamp = 0
        self.membership_requests = MembershipRequests()

    def capabilities(self):
        now = time.monotonic()
        if self.cap_cache is not None and now - self.cap_stamp < 30:
            return copy.deepcopy(self.cap_cache)
        offered = self.engine.call('GET', '/multiplayer/capabilities')
        game = offered.get('game', offered)
        if isinstance(game, list): game = {'formats': game}
        if game is offered:
            bounds = {item.get('format') or item.get('id'): item for item in offered.get('games', [])}
            details = [item for item in offered.get('formatDetails', []) if isinstance(item, dict) and item.get('supported') is True and item.get('id') != 'Limited']
            game = {'formats': details or [dict(bounds.get(item, bounds.get('Constructed', {})), id=item, label=item)
                                for item in offered.get('formats', []) if item != 'Limited'],
                    'maxPlayers': max((item.get('maxPlayers', 2) for item in bounds.values()), default=10)}
        draft = offered.get('draft') or self.engine.call('GET', '/draft/options')
        # The native adapter distinguishes draft procedure, deck rules and pairing.
        native = copy.deepcopy(draft)
        native['modes'] = draft.get('modes') or draft.get('profiles', [])
        native['profiles'] = draft.get('deckProfiles', ['Limited'])
        native['pairings'] = draft.get('pairings', ['swiss', 'elimination'])
        if 'minPlayers' not in native:
            native['minPlayers'] = min((item.get('minPlayers', 4) for item in native['modes'] if isinstance(item, dict)), default=4)
        if 'maxPlayers' not in native:
            native['maxPlayers'] = max((item.get('maxPlayers', 16) for item in native['modes'] if isinstance(item, dict)), default=16)
        result = {'game': game, 'draft': native,
                  'network': {'codeOnly': True, 'server': self.public_origin,
                              'internet': self.public_origin.startswith('https://')}}
        self.cap_cache, self.cap_stamp = result, now
        return copy.deepcopy(result)

    def validate_config(self, value):
        if not isinstance(value, dict):
            raise RoomError('Room settings must be an object')
        caps = self.capabilities()
        kind = value.get('kind', 'constructed')
        if kind not in ('constructed', 'draft'):
            raise RoomError('Choose a multiplayer game or draft')
        config = {'kind': kind, 'name': name(value.get('name', 'Private room'), 'Room name')}
        if kind == 'draft':
            draft = value.get('draft', {})
            if not isinstance(draft, dict):
                raise RoomError('Choose draft settings')
            modes = [item.get('id') if isinstance(item, dict) else item for item in caps['draft']['modes']]
            mode = draft.get('mode', 'booster')
            if mode not in modes:
                raise RoomError('This draft mode is not supported by the installed engine')
            profile = draft.get('profile', 'Limited')
            profiles = [item.get('id') if isinstance(item, dict) else item for item in caps['draft']['profiles']]
            if profile not in profiles:
                raise RoomError('This deck profile is not supported by the installed engine')
            pairing = draft.get('pairing', 'swiss')
            offered_pairings = [item.get('id') if isinstance(item, dict) else item for item in caps['draft']['pairings']]
            if pairing not in offered_pairings:
                raise RoomError('Choose Swiss or single elimination')
            procedure = next((item for item in caps['draft']['modes'] if isinstance(item, dict) and item.get('id') == mode), {})
            minimum = procedure.get('minPlayers', caps['draft'].get('minPlayers', 4))
            maximum = procedure.get('maxPlayers', caps['draft'].get('maxPlayers', 16))
            config['maxPlayers'] = integer(value.get('maxPlayers', 8), minimum, maximum, 'Draft seats')
            config['format'] = profile
            config['draft'] = copy.deepcopy(draft)
            config['draft'].update(mode=mode, profile=profile, pairing=pairing)
            if mode == 'random':
                # Traditional pack slots persist in the desktop's setup form;
                # they must never silently restrict the random booster pool.
                config['draft'].pop('sets', None)
                eligible = draft.get('randomSets', [])
                if not isinstance(eligible, list):
                    raise RoomError('Choose a list of supported random booster sets')
                offered = {item.get('code') or item.get('id') if isinstance(item, dict) else item
                           for item in caps['draft'].get('sets', [])}
                if len(eligible) > len(offered):
                    raise RoomError('Random booster pool exceeds the supported set list')
                if any(not isinstance(code, str) or code not in offered for code in eligible):
                    raise RoomError('Choose supported booster sets for the random pool')
                config['draft']['randomSets'] = list(dict.fromkeys(eligible))
        else:
            fmt = value.get('format', 'Commander')
            formats = caps['game'].get('formats', [])
            offered = [item.get('id') if isinstance(item, dict) else item for item in formats]
            if fmt not in offered:
                raise RoomError('This format is not supported by the installed engine')
            selected = next((item for item in formats if isinstance(item, dict) and item.get('id') == fmt), {})
            minimum = selected.get('minPlayers', 2)
            maximum = selected.get('maxPlayers', caps['game'].get('maxPlayers', 10) if fmt == 'Commander' else 2)
            config['maxPlayers'] = integer(value.get('maxPlayers', 4 if fmt == 'Commander' else 2), minimum, maximum, 'Game seats')
            config['format'] = fmt
            commander_damage = value.get('commanderDamage', True)
            if not isinstance(commander_damage, bool):
                raise RoomError('Commander damage must be enabled or disabled')
            config['commanderDamage'] = commander_damage if fmt == 'Commander' else True
        return config

    def create(self, value):
        identity = self.membership_requests.run('create', value.get('membershipRequestId'), value,
                                               lambda _key=None: self._create(value))
        return self.membership_result(identity)

    def _create(self, value):
        config = self.validate_config(value)
        owner = Member(value.get('playerName', 'Host'), options=value)
        with self.lock:
            self.reap()
            if len(self.rooms) >= self.max_rooms:
                raise RoomError('This room server is full', 503)
            room = Room(config, owner, self.public_origin)
            self.rooms[room.id] = room
        return {'roomId': room.id, 'memberId': owner.id}

    def membership_result(self, identity):
        room = self.get(identity['roomId'])
        with room.lock:
            member = room.members.get(identity['memberId'])
            if room.closed or member is None or member.left:
                raise RoomError('This connection request belongs to a closed or departed seat', 410)
            member.last_seen = time.monotonic()
            return self.envelope(room, member, private=False) | {'memberToken': member.token}

    def get(self, room_id):
        with self.lock:
            room = self.rooms.get(room_id)
        if room is None:
            raise RoomError('Room not found or the host has closed it', 404)
        return room

    def authorize(self, room_id, token):
        room = self.get(room_id)
        with room.lock:
            member = next((p for p in room.members.values() if not p.bot and secrets.compare_digest(p.token, token)), None)
            if member is None or member.left:
                raise RoomError('This seat is not authorized for the room', 403)
            member.last_seen = time.monotonic()
        return room, member

    def join(self, room_id, value):
        identity = self.membership_requests.run('join:' + room_id, value.get('membershipRequestId'), value,
                                               lambda _key=None: self._join(room_id, value))
        return self.membership_result(identity)

    def _join(self, room_id, value):
        room = self.get(room_id)
        with room.lock:
            if not isinstance(value.get('key'), str) or not secrets.compare_digest(room.secret, value['key']):
                raise RoomError('Room code is incorrect', 403)
            if room.phase != 'lobby':
                raise RoomError('This room has already started', 409)
            if len(room.members) >= room.config['maxPlayers']:
                raise RoomError('This room has no empty seats', 409)
            member = Member(value.get('name', 'Player'), options=value)
            room.members[member.id] = member
            room.changed()
            return {'roomId': room.id, 'memberId': member.id}

    @staticmethod
    def owner(room, member):
        if room.host_id != member.id:
            raise RoomError('Only the host can change this room', 403)

    def envelope(self, room, member, private=True):
        draft, game = None, None
        deadline = time.monotonic() + ENVELOPE_READ_BUDGET
        def read(path):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RoomError('The native room update is still pending. Your seat is retained.', 503,
                                retryable=True, kind='engine_wait')
            return self.engine.call('GET', path, timeout=min(NATIVE_READ_TIMEOUT, remaining))
        if room.closed: private = False
        if private and room.draft_id:
            draft = read('/draft/state?draftId=' + quote(room.draft_id) + '&seatId=' + quote(member.id))
            phase = draft.get('phase') or draft.get('status')
            with room.lock:
                if phase in ('building', 'ready') and room.phase == 'drafting':
                    room.phase = 'building'
                    for player in room.members.values():
                        if not player.bot:
                            player.ready = False
                    room.changed()
                if phase == 'failed':
                    room.error = draft.get('error') or 'The engine could not finish the draft';room.phase = 'failed';room.changed()
                for item in draft.get('players', []):
                    player = room.members.get(item.get('seatId') or item.get('id'))
                    if player and room.phase == 'building' and player.ready != bool(item.get('ready')):
                        player.ready = bool(item.get('ready'));room.changed()
                room.draft_public = {key: draft[key] for key in ('round', 'pick', 'packNumber', 'pickNumber', 'waiting', 'status') if key in draft}
        assignment = room.assignments.get(member.id)
        if private and assignment and room.phase == 'playing':
            game = read('/multiplayer/state?gameId=' + quote(assignment['gameId']) + '&playerId=' + quote(assignment['playerId']))
        if draft is not None and room.phase in ('building', 'playing', 'completed'):
            draft['tournament'] = read('/draft/pairings?draftId=' + quote(room.draft_id))
        with room.lock:
            public = room.public(member)
            public['canStart'] = member.id == room.host_id and room.phase in ('lobby', 'building') and len(room.members) == room.config['maxPlayers'] and all(p.ready for p in room.members.values())
            public['canNextRound'] = member.id == room.host_id and room.phase == 'playing' and room.config['kind'] == 'draft' and bool(room.games) and all(p.get('finished') for p in room.games.values())
            public['canRematch'] = room.phase == 'playing' and room.config['kind'] == 'constructed' and bool(game) and game.get('running') is False and not game.get('error') and all(not p.left and p.ready for p in room.members.values())
            return {'room': public, 'participantId': member.id, 'draft': draft, 'game': game}

    def mutate(self, room, member, command, value):
        if room.closed:
            if command == 'leave': return {'left': True}
            raise RoomError('The host has closed this room', 410)
        if command in ('rematch', 'rematch-response', 'rematch-cancel'):
            with room.lock:
                if room.config['kind'] != 'constructed' or room.phase != 'playing' or any(p.left or not p.ready for p in room.members.values()):
                    raise RoomError('Rematch requires the original ready players in a completed constructed room', 409)
                assignment = room.assignments.get(member.id)
                if not assignment: raise RoomError('No completed match to replay', 409)
                result = self.engine.call('GET', '/multiplayer/result?gameId=' + quote(assignment['gameId']))
                if result.get('running') is not False or result.get('error'):
                    raise RoomError('Wait for the native match to finish before a rematch', 409)
                request = room.rematch_request
                if request and request['deadline'] <= time.monotonic():
                    room.rematch_request = request = None;room.changed()
                if command == 'rematch':
                    if request:
                        if request['requesterId'] != member.id:
                            raise RoomError('A player already requested a rematch. Accept or decline that request.', 409)
                        return self.envelope(room, member, private=False)
                    humans = [p.id for p in room.members.values() if not p.bot and not p.left]
                    if len(humans) > 1:
                        room.rematch_request = {'id': secrets.token_urlsafe(12), 'gameId': assignment['gameId'],
                            'requesterId': member.id, 'requesterName': member.name,
                            'approvedSeatIds': [member.id], 'deadline': time.monotonic() + 90}
                        room.changed()
                        return self.envelope(room, member, private=False)
                else:
                    if not request or value.get('requestId') != request['id'] or request['gameId'] != assignment['gameId']:
                        raise RoomError('This rematch request is no longer active', 409)
                    if command == 'rematch-cancel':
                        if request['requesterId'] != member.id: raise RoomError('Only the requester can cancel this request', 403)
                        room.rematch_request = None;room.changed()
                        return self.envelope(room, member, private=False)
                    if not isinstance(value.get('accept'), bool): raise RoomError('Accept must be true or false')
                    if request['requesterId'] == member.id: raise RoomError('Waiting for the other players to respond', 409)
                    if not value['accept']:
                        room.rematch_request = None;room.changed()
                        return self.envelope(room, member, private=False)
                    if member.id not in request['approvedSeatIds']: request['approvedSeatIds'].append(member.id)
                    humans = [p.id for p in room.members.values() if not p.bot and not p.left]
                    if not all(seat in request['approvedSeatIds'] for seat in humans):
                        room.changed();return self.envelope(room, member, private=False)
                room.rematch_request = None
                room.phase = 'starting';room.rematch_index += 1;room.changed()
            def restart(target):
                for match in list(target.games.values()):
                    self.engine.call('POST', '/multiplayer/stop', {'gameId': match['gameId']})
                with target.lock: target.games = {};target.assignments = {};target.start_payload = None
                self.start_room(target)
            threading.Thread(target=self.task, args=(room, restart), daemon=True).start()
            return self.envelope(room, member, private=False)
        if command == 'start':
            self.owner(room, member)
            with room.lock:
                if room.phase == 'building':
                    if any(not p.ready for p in room.members.values()):
                        raise RoomError('Every drafted deck must be submitted first', 409)
                    room.phase = 'starting'
                    task = self.start_round
                elif room.phase == 'lobby':
                    if len(room.members) != room.config['maxPlayers']:
                        raise RoomError('Fill the empty seats or choose fewer seats before creating the room', 409)
                    if room.config['kind'] == 'constructed' and any(not p.deck for p in room.members.values()):
                        raise RoomError('Choose a deck for every constructed seat before starting', 409)
                    if any(not p.ready for p in room.members.values()):
                        raise RoomError('Every player must be ready', 409)
                    room.phase = 'starting'
                    task = self.start_room
                else:
                    raise RoomError('This room has already started', 409)
                room.error = None
                room.changed()
            threading.Thread(target=self.task, args=(room, task), daemon=True).start()
            return self.envelope(room, member, private=False)
        if command == 'next-round':
            self.owner(room, member)
            with room.lock:
                if room.config['kind'] != 'draft' or room.phase != 'playing':
                    raise RoomError('There is no completed draft round to advance', 409)
            self.collect_results(room)
            with room.lock:
                if room.config['kind'] != 'draft' or room.phase != 'playing':
                    raise RoomError('There is no completed draft round to advance', 409)
                if any(not match.get('finished') for match in room.games.values()):
                    raise RoomError('Wait for every match in this round', 409)
                room.phase = 'starting';room.changed()
            threading.Thread(target=self.task, args=(room, self.start_round), daemon=True).start()
            return self.envelope(room, member, private=False)
        if command == 'leave':
            if room.host_id == member.id:
                self.close(room)
            else:
                # A deliberate departure surrenders only this native draft seat.
                # Transient disconnections do not change its human ownership.
                if room.draft_id:
                    self.engine.call('POST', '/draft/forfeit', {'draftId': room.draft_id, 'seatId': member.id})
                with room.lock:
                    room.rematch_request = None
                    if room.phase == 'lobby':
                        room.members.pop(member.id)
                    else:
                        member.left = True
                        if room.config['kind'] == 'draft': member.bot = True
                    room.changed()
                assignment = room.assignments.get(member.id)
                if assignment:
                    self.engine.call('POST', '/multiplayer/action', dict(assignment, type='concede', value=True))
            return {'left': True}
        if command in ('ready', 'deck', 'bots'):
            with room.lock:
                if room.phase != 'lobby':
                    raise RoomError('Room setup is locked after starting', 409)
                if command == 'ready':
                    if not isinstance(value.get('ready'), bool):
                        raise RoomError('Ready must be true or false')
                    if value['ready'] and room.config['kind'] == 'constructed' and not member.deck:
                        raise RoomError('Choose your deck before becoming ready')
                    member.ready = value['ready']
                elif command == 'deck':
                    target = member
                    if 'botSeatId' in value:
                        self.owner(room, member)
                        seat_id = value['botSeatId']
                        target = room.members.get(seat_id) if isinstance(seat_id, str) else None
                        if room.config['kind'] != 'constructed' or not target or not target.bot:
                            raise RoomError('Choose an existing constructed bot seat')
                    deck = value.get('deck')
                    if not isinstance(deck, dict) or str(deck.get('format', '')).casefold() != room.config['format'].casefold():
                        raise RoomError('Choose a deck in the room format')
                    # Native validation still happens when XMage starts the match.
                    target.deck = copy.deepcopy(deck)
                    target.ready = target.bot
                else:
                    self.owner(room, member)
                    humans = sum(not p.bot for p in room.members.values())
                    count = integer(value.get('count'), 0, room.config['maxPlayers'] - humans, 'Bot seats')
                    existing = [p for p in room.members.values() if p.bot]
                    seats = dict(room.members)
                    for bot in existing[count:]:
                        del seats[bot.id]
                    for index in range(len(existing), count):
                        bot = Member('XMage Bot ' + str(index + 1), bot=True)
                        if room.config['kind'] == 'constructed':
                            bot.deck = default_bot_deck(room.config['format'], seats.values())
                            bot.ready = bot.deck is not None
                        seats[bot.id] = bot
                    room.members = seats
                room.changed()
            return self.envelope(room, member, private=False)
        if command == 'draft/pick':
            if room.phase != 'drafting' or not room.draft_id:
                raise RoomError('No pack is waiting for a pick', 409)
            self.engine.call('POST', '/draft/pick', {'draftId': room.draft_id, 'seatId': member.id,
                                                   'pickToken': value.get('pickToken'), 'cardId': value.get('cardId')})
            with room.lock: room.changed()
            return self.envelope(room, member)
        if command == 'draft/deck':
            if room.phase != 'building' or not room.draft_id:
                raise RoomError('Deck construction has not started', 409)
            result = self.engine.call('POST', '/draft/deck', {'draftId': room.draft_id, 'seatId': member.id,
                                                          'main': value.get('main', []), 'basics': value.get('basics', {})})
            if result.get('accepted') is False:
                raise RoomError('; '.join(map(str, result.get('errors', ['The drafted deck is not valid']))), 422)
            with room.lock:
                member.deck = result.get('deck', result);member.ready = True;room.changed()
            return self.envelope(room, member)
        if command.startswith('game/'):
            assignment = room.assignments.get(member.id)
            if not assignment:
                raise RoomError('You do not have a match in this round', 409)
            if value.get('expectedGameId') is not None and value['expectedGameId'] != assignment['gameId']:
                raise RoomError('This action belongs to a previous match', 409)
            operation = command[5:]
            if operation not in ('action', 'priority', 'replay/save'):
                raise RoomError('Unknown game command', 404)
            forwarded = copy.deepcopy(value)
            # Client-supplied seat/game identities never select a perspective.
            forwarded.update(assignment)
            result = self.engine.call('POST', '/multiplayer/' + operation, forwarded)
            if operation == 'priority' and isinstance(result.get('priority'), dict):
                priority = result['priority']
                member.priority = copy.deepcopy({key: priority[key] for key in ('autoPass', 'passWithOnlyMana', 'stops') if key in priority})
            if operation == 'replay/save':
                return result
            return result
        raise RoomError('Unknown room command', 404)

    def task(self, room, action):
        try:
            action(room)
        except Exception as exc:
            with room.lock:
                if not room.closed:
                    if isinstance(exc, RoomError) and exc.status == 400 and not room.draft_id:
                        room.start_payload = None  # Native setup rejected; no game was accepted.
                    room.error = str(exc);room.phase = 'building' if room.draft_id else 'lobby';room.changed()

    def start_room(self, room):
        seats = [{'seatId': p.id, 'name': p.name, 'profile': copy.deepcopy(p.profile), 'type': 'bot' if p.bot else 'human',
                  'deck': p.deck, 'settings': p.settings, 'priority': p.priority}
                 for p in room.members.values()]
        if room.config['kind'] == 'draft':
            draft = copy.deepcopy(room.config['draft'])
            draft['profile'] = draft.pop('mode')
            draft['deckProfile'] = room.config['draft'].get('profile', 'Limited')
            if 'cubeId' in draft: draft['cubeCode'] = draft.pop('cubeId')
            if 'cubeCards' in draft: draft['customCube'] = draft.pop('cubeCards')
            if draft['profile'] == 'random': draft.pop('sets', None)
            with room.lock:
                if room.closed: return
                if room.start_payload is None:
                    room.start_payload = {'config': draft, 'seats': seats, 'idempotencyKey': room.id + ':draft'}
            result = self.engine.call('POST', '/draft/start', room.start_payload)
            with room.lock:
                room.draft_id = result.get('draftId') or result.get('id')
                if not room.draft_id:
                    raise RoomError('The engine did not return a draft identity', 502)
                closed = room.closed
                if not closed: room.phase = 'drafting';room.changed()
            if closed:
                self.engine.call('POST', '/draft/stop', {'draftId': room.draft_id})
            else:
                for player in list(room.members.values()):
                    if player.left: self.engine.call('POST', '/draft/forfeit', {'draftId': room.draft_id, 'seatId': player.id})
        else:
            with room.lock:
                if room.closed: return
                if room.start_payload is None:
                    room.start_payload = {'format': room.config['format'], 'seats': seats,
                        'commanderDamage': room.config.get('commanderDamage', True),
                        'recordingPort': self.recording_port, 'recordingSeatId': room.host_id,
                        'idempotencyKey': room.id + ':constructed:' + str(room.rematch_index)}
            result = self.engine.call('POST', '/multiplayer/start', room.start_payload)
            if self.assign_game(room, result, [p.id for p in room.members.values()]):
                with room.lock:
                    if not room.closed: room.phase = 'playing';room.changed()
                for item in result.get('seats', []):
                    if room.members[item['seatId']].left:
                        self.engine.call('POST', '/multiplayer/action', {'gameId': result['gameId'], 'playerId': item['playerId'], 'type': 'concede', 'value': True})

    def assign_game(self, room, result, seat_ids, pair_id=None):
        game_id = result.get('gameId')
        if not game_id:
            raise RoomError('The engine did not return a game identity', 502)
        match = {'id': pair_id or game_id, 'gameId': game_id, 'seatIds': seat_ids, 'finished': False}
        mapping = result.get('players') or result.get('seats') or result.get('participants') or []
        with room.lock:
            closed = room.closed
            if not closed:
                room.games[match['id']] = match
                for item in mapping:
                    seat_id = item.get('seatId')
                    if seat_id in room.members and not room.members[seat_id].bot:
                        room.assignments[seat_id] = {'gameId': game_id, 'playerId': item.get('playerId') or item.get('id')}
                room.changed()
        if closed: self.engine.call('POST', '/multiplayer/stop', {'gameId': game_id})
        return not closed

    def start_pair(self, room, seat_ids, pair_id):
        seats = [{'seatId': key, 'name': room.members[key].name,
                  'profile': copy.deepcopy(room.members[key].profile),
                  'type': 'bot' if room.members[key].bot else 'human',
                  'settings': room.members[key].settings, 'priority': room.members[key].priority} for key in seat_ids]
        with room.lock:
            if room.closed: return False
            key = pair_id + ':' + str(room.pair_attempts.get(pair_id, 0))
            if key not in room.pair_payloads:
                room.pair_payloads[key] = {'format': 'Limited', 'seats': seats,
                    'draftId': room.draft_id, 'pairingId': pair_id,
                    'recordingPort': self.recording_port if room.host_id in seat_ids else 0,
                    'recordingSeatId': room.host_id if room.host_id in seat_ids else None,
                    'idempotencyKey': room.draft_id + ':' + key}
        started = self.engine.call('POST', '/multiplayer/start', room.pair_payloads[key])
        assigned = self.assign_game(room, started, seat_ids, pair_id)
        if assigned:
            for item in started.get('seats', []):
                if item.get('human') and room.members[item['seatId']].left:
                    self.engine.call('POST', '/multiplayer/action', {'gameId': started['gameId'], 'playerId': item['playerId'], 'type': 'concede', 'value': True})
        return assigned

    def collect_results(self, room):
        if not room.result_lock.acquire(blocking=False): return
        try:
            self._collect_results(room)
        finally: room.result_lock.release()

    def repeat_pair(self, room, match):
        if not match.get('rematchReleased'):
            self.engine.call('POST', '/multiplayer/stop', {'gameId': match['gameId']})
            room.pair_attempts[match['id']] = room.pair_attempts.get(match['id'], 0) + 1
            match['rematchReleased'] = True
        self.start_pair(room, match['seatIds'], match['id'])

    def _collect_results(self, room):
        for match in list(room.games.values()):
            if room.closed: return
            if match.get('finished'):
                continue
            if match.get('rematch'):
                self.repeat_pair(room, match);continue
            result = self.engine.call('GET', '/multiplayer/result?gameId=' + quote(match['gameId']))
            if result.get('running') is not False:
                continue
            winner = result.get('winnerSeatId')
            if winner is None:
                winners = result.get('winnerSeatIds', [])
                winner = winners[0] if len(winners) == 1 else None
            try:
                self.engine.call('POST', '/draft/result', {'draftId': room.draft_id, 'pairingId': match['id'], 'gameId': match['gameId']})
            except RoomError as exc:
                if str(exc) != 'A drawn elimination game requires a rematch': raise
                # Native validation confirms an actual completed draw. Replay the
                # same native pairing rather than selecting an invented winner.
                match['rematch'] = True
                self.repeat_pair(room, match);continue
            with room.lock:
                match.update(finished=True, winnerSeatId=winner);room.changed()

    def start_round(self, room):
        if room.closed: return
        if room.pending_round is None:
            for match in list(room.games.values()):
                if match.get('gameId'):
                    self.engine.call('POST', '/multiplayer/stop', {'gameId': match['gameId']})
            if room.next_round_payload is None:
                room.next_round_payload = {'draftId': room.draft_id,
                    'idempotencyKey': room.id + ':round-' + str(room.round_index + 1)}
            result = self.engine.call('POST', '/draft/next-round', room.next_round_payload)
            with room.lock:
                room.pending_round = result
                room.round_index = result.get('round', room.round_index)
                room.games = {};room.assignments = {}
        result = room.pending_round
        if result.get('status') == 'completed':
            with room.lock:
                if not room.closed: room.phase = 'completed';room.pending_round = None;room.next_round_payload = None;room.changed()
            return
        matches = result.get('matches')
        if matches is None:
            rounds = result.get('rounds', [])
            matches = rounds[-1].get('pairs', []) if rounds else []
        if not matches:
            raise RoomError('The engine has not provided pairings for this round', 409)
        for pair in matches:
            if room.closed: return
            pair_id = pair.get('matchId') or pair.get('id')
            if pair_id in room.games: continue
            ids = pair.get('seatIds') or [pair.get('seat1'), pair.get('seat2')]
            if pair.get('bye'):
                with room.lock: room.games[pair['id']] = {'id': pair['id'], 'seatIds': ids, 'finished': True, 'winnerSeatId': ids[0]}
                continue
            if len(ids) != 2 or not all(item in room.members for item in ids):
                raise RoomError('Invalid native draft pairing', 502)
            if not self.start_pair(room, ids, pair_id): return
        with room.lock:
            if not room.closed: room.phase = 'playing';room.pending_round = None;room.next_round_payload = None;room.changed()

    def close(self, room):
        with room.lock:
            room.closed = True;room.phase = 'closed';room.changed()
        for match in list(room.games.values()):
            if not match.get('gameId'): continue  # Native Swiss byes have no game.
            try: self.engine.call('POST', '/multiplayer/stop', {'gameId': match['gameId']})
            except RoomError: pass
        # Also fence starts whose native response was lost or still in flight.
        # Native key tombstones prevent a late start from recreating the room.
        for payload in list(room.pair_payloads.values()):
            try: self.engine.call('POST', '/multiplayer/stop', {'idempotencyKey': payload['idempotencyKey']})
            except RoomError: pass
        if room.start_payload:
            path = '/draft/stop' if room.config['kind'] == 'draft' else '/multiplayer/stop'
            try: self.engine.call('POST', path, {'idempotencyKey': room.start_payload['idempotencyKey']})
            except RoomError: pass
        if room.draft_id:
            try: self.engine.call('POST', '/draft/stop', {'draftId': room.draft_id})
            except RoomError: pass

    def reap(self):
        now = time.monotonic()
        for key, room in list(self.rooms.items()):
            if (room.closed and now - room.touched > 60) or (room.phase == 'lobby' and now - room.touched > 3600):
                self.rooms.pop(key, None)

    def maintain(self):
        with self.lock: rooms = list(self.rooms.values())
        for room in rooms:
            if not room.closed and room.phase == 'playing' and room.draft_id:
                try: self.collect_results(room)
                except RoomError as exc:
                    with room.lock:
                        if room.error != str(exc): room.error = str(exc);room.changed()
        with self.lock: self.reap()


class Gateway:
    def __init__(self, registry, upstream=None, local_origin=None, client_api=True):
        self.registry = registry
        self.local_origin = origin(local_origin) if local_origin else registry.public_origin
        self.upstream = origin(upstream) if upstream else self.local_origin
        self.connections = {}
        self.lock = threading.RLock()
        self.client_api = client_api
        self.membership_requests = MembershipRequests()
        self.membership_hosts = {}

    def connect(self, method, value):
        value = copy.deepcopy(value)
        request_id = value.pop('connectionRequestId', None)
        snapshot = {}
        supported = [False]
        def connect_once(upstream_id=None):
            result = self._connect(method, value, upstream_id, supported)
            snapshot.update(result)
            return {'connectionId': result['connectionId']}
        # Unknown replies from legacy hosts cannot be replayed safely. New
        # hosts advertise membership idempotency before the first mutation.
        def operation(upstream_id=None):
            try: return connect_once(upstream_id)
            except RoomError as exc:
                if not supported[0] and exc.kind == 'outcome_unknown':
                    # Cache this terminal uncertainty instead of sending a
                    # second blind join to a server lacking the new contract.
                    raise RoomError('The host did not confirm the connection. A legacy host cannot safely retry this membership.',
                                    503, kind='legacy_outcome_unknown') from exc
                raise
        identity = self.membership_requests.run(method, request_id, value, operation)
        if snapshot:
            return snapshot
        # A locally lost reply already has a credential-bearing connection.
        # Refresh that exact seat instead of creating a second membership.
        return self.call(identity['connectionId'], 'GET') | identity

    def _connect(self, method, value, request_id=None, supported=None):
        if method == 'create':
            server = self.upstream
            path = '/rooms';body = copy.deepcopy(value)
        else:
            code = decode_invite(value.get('code'))
            server = self.local_origin if code['server'] == self.registry.public_origin else code['server']
            path = '/rooms/' + quote(code['room']) + '/join'
            body = {'key': code['key'], 'name': value.get('name'), 'profile': value.get('profile'), 'settings': value.get('settings', {}), 'priority': value.get('priority', {})}
        client = JSONClient(server)
        deadline = time.monotonic() + PUBLIC_REQUEST_TIMEOUT
        if request_id:
            with self.lock: feature = self.membership_hosts.get(server)
            if feature is None:
                health = client.call('GET', '/health')
                if not isinstance(health, dict): raise RoomError('The room host returned invalid health information', 502)
                feature = health.get('membershipIdempotency') is True
                with self.lock:
                    if len(self.membership_hosts) >= 128: self.membership_hosts.pop(next(iter(self.membership_hosts)))
                    self.membership_hosts[server] = feature
            if supported is not None: supported[0] = feature
            if feature: body['membershipRequestId'] = request_id
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise RoomError('Room connection is waiting for the host. Retry the same request.', 503, retryable=True, kind='transport')
        try:
            result = client.call('POST', path, body, timeout=remaining)
        except RoomError as exc:
            if exc.status >= 500:
                # A server may fail while serializing an already accepted
                # membership. Only an advertised idempotency key makes a
                # repeated POST safe, even for malformed/oversized replies.
                raise RoomError(str(exc), exc.status, kind='outcome_unknown') from exc
            raise
        if not isinstance(result, dict):
            raise RoomError('Room server returned an invalid connection', 502, kind='outcome_unknown')
        token = result.pop('memberToken', None)
        room = result.get('room')
        room_id = room.get('id') if isinstance(room, dict) else None
        if (not isinstance(token, str) or not 8 <= len(token) <= 512 or any(ord(c) < 33 or ord(c) > 126 for c in token)
                or not isinstance(room_id, str) or not 1 <= len(room_id) <= 128):
            raise RoomError('Room server returned an incomplete connection', 502, kind='outcome_unknown')
        connection = secrets.token_urlsafe(24)
        with self.lock:
            self.connections[connection] = {'client': JSONClient(server, token), 'roomId': result['room']['id']}
        return result | {'connectionId': connection}

    def call(self, connection_id, method, operation='', body=None):
        with self.lock:
            connection = self.connections.get(connection_id)
        if connection is None:
            raise RoomError('This room connection has expired; join with its code again', 404)
        path = '/rooms/' + quote(connection['roomId']) + ('/' + operation if operation else '')
        try:
            result = connection['client'].call(method, path, body)
        except RoomError as exc:
            if operation != 'leave' or exc.status not in (403, 404, 410): raise
            result = {'left': True}  # Already closed/expired seats can be forgotten locally.
        if operation == 'leave':
            with self.lock: self.connections.pop(connection_id, None)
        return result


def handler(gateway):
    registry = gateway.registry

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Invitations and seat credentials never enter an access log.

        def respond(self, status, value):
            body = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            try: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError): pass

        def body(self):
            try: length = int(self.headers.get('Content-Length', '0'))
            except ValueError as exc: raise RoomError('Invalid request length') from exc
            if not 0 <= length <= MAX_BODY:
                raise RoomError('Room request exceeds 8 MiB', 413)
            if self.headers.get_content_type() != 'application/json':
                raise RoomError('Room commands require JSON', 415)
            try: value = json.loads(self.rfile.read(length))
            except (ValueError, UnicodeError) as exc: raise RoomError('Invalid JSON request') from exc
            if not isinstance(value, dict): raise RoomError('Room commands require an object')
            return value

        def route(self):
            if self.headers.get('Origin'):
                raise RoomError('Browser-origin room commands are not accepted', 403)
            path = urlsplit(self.path).path.rstrip('/') or '/'
            parts = path.strip('/').split('/')
            method = self.command
            value = self.body() if method == 'POST' else {}
            if path == '/health' and method == 'GET':
                return {'status': 'ok', 'apiVersion': API_VERSION, 'service': 'love2gathering-rooms', 'membershipIdempotency': True}
            if path.startswith('/client/'):
                if not gateway.client_api:
                    raise RoomError('Desktop-client endpoints are disabled on this room host', 403)
                if not ipaddress.ip_address(self.client_address[0]).is_loopback:
                    raise RoomError('This endpoint is local to its desktop client', 403)
                if path == '/client/capabilities' and method == 'GET':
                    return JSONClient(gateway.upstream).call('GET', '/capabilities')
                if path == '/client/rooms' and method == 'POST':
                    return gateway.connect('create', value)
                if path == '/client/join' and method == 'POST':
                    return gateway.connect('join', value)
                if len(parts) >= 3 and parts[:2] == ['client', 'rooms']:
                    operation = '/'.join(parts[3:])
                    return gateway.call(parts[2], method, operation, value if method == 'POST' else None)
                raise RoomError('Unknown client command', 404)
            if path == '/capabilities' and method == 'GET':
                return registry.capabilities()
            if path == '/rooms' and method == 'POST':
                return registry.create(value)
            if len(parts) >= 2 and parts[0] == 'rooms':
                room_id = parts[1]
                operation = '/'.join(parts[2:])
                if operation == 'join' and method == 'POST':
                    return registry.join(room_id, value)
                authorization = self.headers.get('Authorization', '')
                token = authorization[7:] if authorization.startswith('Bearer ') else ''
                room, member = registry.authorize(room_id, token)
                if not operation and method == 'GET':
                    return registry.envelope(room, member)
                if operation == 'game/state' and method == 'GET':
                    assignment = room.assignments.get(member.id)
                    if not assignment: raise RoomError('Your match is not running', 409)
                    return registry.engine.call('GET', '/multiplayer/state?gameId=' + quote(assignment['gameId']) + '&playerId=' + quote(assignment['playerId']))
                if method == 'POST':
                    return registry.mutate(room, member, operation, value)
            raise RoomError('No public room list is available; join with a room code', 404)

        def handle_request(self):
            try: self.respond(200, self.route())
            except RoomError as exc: self.respond(exc.status, {'error': str(exc), 'status': exc.status, 'retryable': exc.retryable, 'kind': exc.kind})
            except Exception:
                self.respond(500, {'error': 'Room server could not complete the request'})

        do_GET = handle_request
        do_POST = handle_request

    return Handler


def lan_host():
    # UDP connect selects the outbound interface without sending a datagram.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(('192.0.2.1', 9))
            return probe.getsockname()[0]
        except OSError:
            return '127.0.0.1'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=17380)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--public-url', default=os.environ.get('LOVE2GATHERING_ROOM_PUBLIC_URL'))
    parser.add_argument('--upstream', default=os.environ.get('LOVE2GATHERING_ROOM_SERVER_URL'))
    parser.add_argument('--engine-port', type=int, default=int(os.environ.get('LOVE2GATHERING_ENGINE_PORT', '17371')))
    parser.add_argument('--catalog-port', type=int, default=int(os.environ.get('LOVE2GATHERING_CATALOG_PORT', '17370')))
    parser.add_argument('--max-rooms', type=int, default=32)
    parser.add_argument('--no-client-api', action='store_true', help='Disable desktop-only proxy endpoints on a headless/public host')
    parser.add_argument('--coordinator-token-file', type=Path)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or not 1 <= args.max_rooms <= 64:
        parser.error('Invalid room-server port or room count')
    token = args.coordinator_token_file.read_text().strip() if args.coordinator_token_file else os.environ.get('LOVE2GATHERING_COORDINATOR_TOKEN')
    if not token:
        parser.error('Set LOVE2GATHERING_COORDINATOR_TOKEN for the local XMage coordinator')
    advertised = args.public_url or f'http://{lan_host()}:{args.port}'
    engine = JSONClient(f'http://127.0.0.1:{args.engine_port}', token, timeout=180, read_timeout=NATIVE_READ_TIMEOUT)
    registry = Registry(engine, advertised, args.catalog_port, args.max_rooms)
    gateway = Gateway(registry, args.upstream, f'http://127.0.0.1:{args.port}', not args.no_client_api)
    server = ThreadingHTTPServer((args.bind, args.port), handler(gateway))
    server.daemon_threads = True
    stopped = threading.Event()
    def maintain():
        while not stopped.wait(.6): registry.maintain()
    threading.Thread(target=maintain, daemon=True).start()
    print(f'Room-code gateway listening on port {args.port}', flush=True)
    def stop_signal(*_): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop_signal)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        stopped.set()
        for room in list(registry.rooms.values()): registry.close(room)
        server.server_close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
