"""Artwork identity only: tokens and references come from local card metadata."""
import hashlib
import json
import re
import secrets
from replays import encode, now

MODES = ('default', 'randomSelected', 'randomAll')


def token_name(value):
    return re.sub(r'\s+(?:creature\s+)?token$', '', str(value or ''), flags=re.I).strip().casefold()


class TokenCatalog:
    @staticmethod
    def create_tokens(c):
        c.executescript('''CREATE TABLE token_images(id TEXT PRIMARY KEY,printing_id TEXT NOT NULL,oracle_id TEXT NOT NULL,face INTEGER NOT NULL,name TEXT NOT NULL,type_line TEXT NOT NULL,power TEXT,toughness TEXT,colors TEXT NOT NULL,payload TEXT NOT NULL);
            CREATE INDEX token_names ON token_images(name COLLATE NOCASE,id);
            CREATE INDEX token_printings ON token_images(printing_id);
            CREATE INDEX token_oracles ON token_images(oracle_id);
            CREATE TABLE token_links(parent_name TEXT NOT NULL COLLATE NOCASE,printing_id TEXT NOT NULL,PRIMARY KEY(parent_name,printing_id));''')

    @staticmethod
    def index_tokens(c, raw):
        if raw.get('object') != 'card': return
        for part in raw.get('all_parts') or []:
            if part.get('component') == 'token' and part.get('id'):
                c.execute('INSERT OR IGNORE INTO token_links VALUES (?,?)', (raw.get('name', ''), part['id']))
        layout = raw.get('layout') or ''
        if layout not in ('token', 'double_faced_token', 'emblem') and 'Token' not in (raw.get('type_line') or ''): return
        if raw.get('lang', 'en') != 'en' or not raw.get('id'): return
        faces = raw.get('card_faces') or [raw]
        for face_number, face in enumerate(faces):
            images = face.get('image_uris') or (raw.get('image_uris') if face_number == 0 else {}) or {}
            if not images.get('normal') and not images.get('large'): continue
            printing = raw['id'];oracle = raw.get('oracle_id') or printing
            item = {'id': oracle, 'tokenImageId': printing + '-' + str(face_number), 'printing_id': printing,
                    'oracle_id': oracle, 'requested_face': face_number, 'token': True,
                    'name': face.get('name') or raw['name'], 'type_line': face.get('type_line') or raw.get('type_line') or '',
                    'power': face.get('power'), 'toughness': face.get('toughness'), 'colors': face.get('colors') or [],
                    'oracle_text': face.get('oracle_text') or '', 'image_uris': images, 'card_faces': raw.get('card_faces') or [],
                    'set': raw.get('set'), 'set_name': raw.get('set_name'), 'collector_number': raw.get('collector_number'),
                    'artist': face.get('artist') or raw.get('artist') or '', 'layout': layout}
            c.execute('INSERT OR REPLACE INTO token_images VALUES (?,?,?,?,?,?,?,?,?,?)',
                      (item['tokenImageId'], printing, oracle, face_number, item['name'], item['type_line'], item['power'], item['toughness'], ''.join(sorted(item['colors'])), encode(item)))

    def token_item(self, identifier):
        if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,110}', identifier): raise ValueError('Invalid token artwork ID')
        with self.connect() as c:
            row = c.execute('SELECT payload FROM token_images WHERE id=?', (identifier,)).fetchone()
        return json.loads(row[0]) if row else None

    def tokens(self, query='', deck=None, limit=24, offset=0):
        if len(query) > 300: raise ValueError('Token search exceeds 300 characters')
        where, params = [], []
        for word in query.casefold().split(): where.append("instr(lower(name||' '||type_line),?)>0");params.append(word)
        names = [e['name'] for zone in ('main', 'sideboard', 'commander') for e in (deck or {}).get(zone, [])]
        if deck is not None:
            # Include all art variants for token identities explicitly linked to
            # this deck. Missing relationships remain unknown rather than guessed.
            if not names: return {'items': [], 'total': 0, 'limit': limit, 'offset': offset}
            where.append('oracle_id IN (SELECT DISTINCT t.oracle_id FROM token_images t JOIN token_links l ON l.printing_id=t.printing_id WHERE l.parent_name IN (' + ','.join('?' for _ in names) + '))');params += names
        clause = ' WHERE ' + ' AND '.join(where) if where else ''
        with self.connect() as c:
            total = c.execute('SELECT count(*) FROM token_images' + clause, params).fetchone()[0]
            rows = c.execute('SELECT payload FROM token_images' + clause + ' ORDER BY name COLLATE NOCASE,printing_id,face LIMIT ? OFFSET ?', (*params, limit, offset))
            items = [json.loads(r[0]) for r in rows]
        return {'items': items, 'total': total, 'limit': limit, 'offset': offset}

    def resolve_token(self, descriptor, preferences, seed='', deck=None):
        if not isinstance(descriptor, dict): raise ValueError('Token descriptor must be an object')
        name = token_name(descriptor.get('name'))
        if not name or len(name) > 300: raise ValueError('Token needs a bounded native name')
        source = descriptor.get('printing') if isinstance(descriptor.get('printing'), dict) else descriptor
        power, toughness = source.get('power'), source.get('toughness')
        colors = source.get('colors')
        if colors is not None and (not isinstance(colors, list) or any(not isinstance(c, str) or len(c) != 1 or c not in 'WUBRG' for c in colors)): raise ValueError('Token colors must be native W/U/B/R/G values')
        with self.connect() as c:
            rows = c.execute('SELECT payload FROM token_images WHERE name=? COLLATE NOCASE ORDER BY printing_id,face LIMIT 2000', (name,))
            candidates = [json.loads(r[0]) for r in rows]
        for field, value in (('power', power), ('toughness', toughness)):
            if value is not None: candidates = [i for i in candidates if str(i.get(field)) == str(value)]
        if colors is not None: candidates = [i for i in candidates if sorted(i['colors']) == sorted(colors)]
        type_line = str(source.get('type_line') or source.get('type') or '').casefold()
        if type_line:
            subtypes = type_line.split('—')[-1].strip().split() if '—' in type_line else []
            if subtypes: candidates = [i for i in candidates if all(word in i['type_line'].casefold().split() for word in subtypes)]
        mode = preferences.get('mode', 'default')
        if mode == 'randomSelected':
            chosen = [i for i in candidates if i['tokenImageId'] in preferences.get('selected', [])]
            if chosen: candidates = chosen
            else: mode = 'default'  # A preference for another token never blanks this one.
        if not candidates: return None
        if mode == 'default' and deck:
            linked = {i['tokenImageId'] for i in self.tokens(deck=deck, limit=2000)['items']}
            related = [i for i in candidates if i['tokenImageId'] in linked]
            if related: candidates = related
        if mode == 'default': return candidates[0]
        if not isinstance(seed, str) or len(seed) > 300: raise ValueError('Token artwork seed exceeds its bound')
        index = int.from_bytes(hashlib.sha256(seed.encode()).digest()[:8], 'big') % len(candidates) if seed else secrets.randbelow(len(candidates))
        return candidates[index]


class TokenPreferences:
    def token_preferences(self, deck_id):
        self.check_id(deck_id)
        with self.connection() as c: row = c.execute('SELECT payload FROM token_preferences WHERE deck_id=?', (deck_id,)).fetchone()
        return json.loads(row[0]) if row else {'mode': 'default', 'selected': []}

    def save_token_preferences(self, deck_id, value, catalog):
        if not self.get_deck(deck_id): raise KeyError('Save the deck before choosing token artwork')
        if not isinstance(value, dict) or value.get('mode') not in MODES: raise ValueError('Choose default, randomSelected or randomAll token artwork')
        selected = value.get('selected', [])
        if not isinstance(selected, list) or len(selected) > 500: raise ValueError('Choose at most 500 token artworks')
        if any(not isinstance(identifier, str) for identifier in selected): raise ValueError('Token artwork IDs must be strings')
        selected = list(dict.fromkeys(selected))
        if any(not catalog.token_item(identifier) for identifier in selected): raise ValueError('Selected token artwork is not in the local metadata')
        if value['mode'] == 'randomSelected' and not selected: raise ValueError('Choose token artwork before using randomSelected')
        normalized = {'mode': value['mode'], 'selected': selected}
        with self.connection(write=True) as c: c.execute('INSERT INTO token_preferences VALUES (?,?,?) ON CONFLICT(deck_id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at', (deck_id, encode(normalized), now()))
        return normalized
