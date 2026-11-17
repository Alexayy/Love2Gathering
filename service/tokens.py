"""Artwork identity only: tokens and references come from local card metadata."""
import hashlib
import json
import re
import secrets
from replays import encode, now

MODES = ('default', 'selected', 'randomSelected', 'randomAll')
TOKEN_INDEXES = (
    'CREATE INDEX token_names ON token_images(name COLLATE NOCASE,id)',
    'CREATE INDEX token_printings ON token_images(printing_id)',
    'CREATE INDEX token_oracles ON token_images(oracle_id)',
)


def token_name(value):
    return re.sub(r'\s+(?:creature\s+)?token$', '', str(value or ''), flags=re.I).strip().casefold()


def token_identity(item):
    """An artwork family, independent of set/illustrator and double-face pairing."""
    fields = [token_name(item.get('name')),
              re.sub(r'\btoken\b', '', str(item.get('type_line') or ''), flags=re.I),
              str(item.get('power') or ''), str(item.get('toughness') or ''),
              ''.join(sorted(item.get('colors') or [])), str(item.get('oracle_text') or '')]
    fields = [' '.join(value.casefold().split()) for value in fields]
    return 'token-' + hashlib.sha256(encode(fields).encode()).hexdigest()[:32]


def token_preference(preferences, identity):
    override = (preferences.get('overrides') or {}).get(identity)
    return override if isinstance(override, dict) else preferences


def public_token(item):
    value = dict(item)
    value['tokenIdentity'] = token_identity(value)
    value['printingExact'] = True
    return value


class TokenCatalog:
    @staticmethod
    def create_tokens(c, *, indexes=True):
        c.executescript('''CREATE TABLE token_images(id TEXT PRIMARY KEY,printing_id TEXT NOT NULL,oracle_id TEXT NOT NULL,face INTEGER NOT NULL,name TEXT NOT NULL,type_line TEXT NOT NULL,power TEXT,toughness TEXT,colors TEXT NOT NULL,payload TEXT NOT NULL);
            CREATE TABLE token_links(parent_name TEXT NOT NULL COLLATE NOCASE,printing_id TEXT NOT NULL,PRIMARY KEY(parent_name,printing_id));''')
        if indexes:
            for statement in TOKEN_INDEXES:
                c.execute(statement)

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
        return public_token(json.loads(row[0])) if row else None

    def _related_token_families(self, deck):
        names = sorted({e['name'] for zone in ('main', 'sideboard', 'commander') for e in (deck or {}).get(zone, [])})
        if not names: return {}
        families = {}
        with self.connect() as c:
            rows = c.execute('SELECT t.payload FROM token_images t JOIN token_links l ON l.printing_id=t.printing_id WHERE l.parent_name IN (' + ','.join('?' for _ in names) + ')', names)
            for row in rows:
                item = public_token(json.loads(row[0]));key = item['tokenIdentity']
                family = families.setdefault(key, {'name': item['name'], 'linked': set()})
                family['linked'].add(item['tokenImageId'])
        return families

    def tokens(self, query='', deck=None, limit=24, offset=0, *, groups=False, identity='', preferences=None):
        if not isinstance(query, str) or len(query) > 300: raise ValueError('Token search exceeds 300 characters')
        if not isinstance(limit, int) or not 1 <= limit <= 2000 or not isinstance(offset, int) or offset < 0: raise ValueError('Invalid token page bounds')
        if identity and not re.fullmatch(r'token-[0-9a-f]{32}', identity): raise ValueError('Invalid token family')
        preferences = preferences or {'mode': 'default', 'selected': []}
        families = self._related_token_families(deck) if deck is not None else None
        where, params = [], []
        search = "name||' '||type_line" if groups else "name||' '||type_line||' '||coalesce(json_extract(payload,'$.set_name'),'')||' '||coalesce(json_extract(payload,'$.set'),'')||' '||coalesce(json_extract(payload,'$.artist'),'')"
        for word in query.casefold().split(): where.append('instr(lower(' + search + '),?)>0');params.append(word)
        if families is not None:
            if not families: return {'items': [], 'total': 0, 'limit': limit, 'offset': offset, 'grouped': groups}
            names = sorted({family['name'] for family in families.values()})
            where.append('name COLLATE NOCASE IN (' + ','.join('?' for _ in names) + ')');params += names
        clause = ' WHERE ' + ' AND '.join(where) if where else ''
        result, total, summaries = [], 0, {}
        with self.connect() as c:
            rows = c.execute('SELECT payload FROM token_images' + clause + ' ORDER BY name COLLATE NOCASE,printing_id,face', params)
            for row in rows:
                item = public_token(json.loads(row[0]));key = item['tokenIdentity']
                if (families is not None and key not in families) or (identity and identity != key): continue
                if not groups:
                    if offset <= total < offset + limit: result.append(item)
                    total += 1
                    continue
                pref = token_preference(preferences, key)
                group = summaries.setdefault(key, {'tokenIdentity': key, 'name': item['name'], 'type_line': item['type_line'],
                    'power': item.get('power'), 'toughness': item.get('toughness'), 'colors': item['colors'],
                    'variantCount': 0, 'mode': pref.get('mode', 'default'), 'activeImageIds': [], 'activeCard': item,
                    'defaultCard': item, '_linked': False})
                group['variantCount'] += 1
                linked = families is not None and item['tokenImageId'] in families[key]['linked']
                if linked and not group['_linked']:
                    group['defaultCard'] = item;group['_linked'] = True
                if item['tokenImageId'] in pref.get('selected', []):
                    group['activeImageIds'].append(item['tokenImageId'])
                    if len(group['activeImageIds']) == 1: group['activeCard'] = item
        if groups:
            values = sorted(summaries.values(), key=lambda item: (item['name'].casefold(), item['tokenIdentity']))
            total = len(values)
            for group in values:
                group.pop('_linked')
                if group['mode'] in ('default', 'randomAll') or not group['activeImageIds']:
                    group['activeCard'] = group['defaultCard']
                group['activeCount'] = group['variantCount'] if group['mode'] == 'randomAll' else len(group['activeImageIds']) if group['mode'] in ('selected', 'randomSelected') and group['activeImageIds'] else 1
            result = values[offset:offset + limit]
        return {'items': result, 'total': total, 'limit': limit, 'offset': offset, 'grouped': groups}

    def resolve_token(self, descriptor, preferences, seed='', deck=None):
        if not isinstance(descriptor, dict): raise ValueError('Token descriptor must be an object')
        name = token_name(descriptor.get('name'))
        if not name or len(name) > 300: raise ValueError('Token needs a bounded native name')
        source = descriptor.get('printing') if isinstance(descriptor.get('printing'), dict) else descriptor
        power, toughness = source.get('power'), source.get('toughness')
        colors = source.get('colors')
        if colors is not None and (not isinstance(colors, list) or any(not isinstance(c, str) or len(c) != 1 or c not in 'WUBRG' for c in colors)): raise ValueError('Token colors must be native W/U/B/R/G values')
        with self.connect() as c:
            rows = c.execute('SELECT payload FROM token_images WHERE name=? COLLATE NOCASE ORDER BY printing_id,face', (name,))
            candidates = [public_token(json.loads(r[0])) for r in rows]
        for field, value in (('power', power), ('toughness', toughness)):
            if value is not None: candidates = [i for i in candidates if str(i.get(field)) == str(value)]
        if colors is not None: candidates = [i for i in candidates if sorted(i['colors']) == sorted(colors)]
        type_line = str(source.get('type_line') or source.get('type') or '').casefold()
        if type_line:
            subtypes = type_line.split('—')[-1].strip().split() if '—' in type_line else []
            if subtypes: candidates = [i for i in candidates if all(word in i['type_line'].casefold().split() for word in subtypes)]
        if not candidates: return None
        if deck:
            families = self._related_token_families(deck)
            related = [i for i in candidates if i['tokenIdentity'] in families]
            if related: candidates = related
        # Native descriptors can lack ability text. Resolve a related family
        # first, then apply only that family's overrides; different rules/PT/
        # colors never join a random-all art pool.
        key = candidates[0]['tokenIdentity'];candidates = [i for i in candidates if i['tokenIdentity'] == key]
        pref = token_preference(preferences, key);mode = pref.get('mode', 'default')
        if mode in ('selected', 'randomSelected'):
            chosen = [i for i in candidates if i['tokenImageId'] in pref.get('selected', [])]
            if chosen: candidates = chosen
            else: mode = 'default'  # A preference for another token never blanks this one.
        if not candidates: return None
        if mode == 'default' and deck:
            linked = self._related_token_families(deck).get(key, {}).get('linked', set())
            related = [i for i in candidates if i['tokenImageId'] in linked]
            if related: candidates = related
        if mode in ('default', 'selected'): return candidates[0]
        if not isinstance(seed, str) or len(seed) > 300: raise ValueError('Token artwork seed exceeds its bound')
        index = int.from_bytes(hashlib.sha256(seed.encode()).digest()[:8], 'big') % len(candidates) if seed else secrets.randbelow(len(candidates))
        return candidates[index]


class TokenPreferences:
    def token_preferences(self, deck_id):
        self.check_id(deck_id)
        with self.connection() as c: row = c.execute('SELECT payload FROM token_preferences WHERE deck_id=?', (deck_id,)).fetchone()
        return json.loads(row[0]) if row else {'mode': 'default', 'selected': []}

    def save_token_preferences(self, deck_id, value, catalog):
        deck = self.get_deck(deck_id)
        if not deck: raise KeyError('Save the deck before choosing token artwork')
        if not isinstance(value, dict) or value.get('mode') not in MODES: raise ValueError('Choose default, selected, randomSelected or randomAll token artwork')
        selected = value.get('selected', [])
        if not isinstance(selected, list) or len(selected) > 500: raise ValueError('Choose at most 500 token artworks')
        if any(not isinstance(identifier, str) for identifier in selected): raise ValueError('Token artwork IDs must be strings')
        selected = list(dict.fromkeys(selected))
        if any(not catalog.token_item(identifier) for identifier in selected): raise ValueError('Selected token artwork is not in the local metadata')
        if value['mode'] in ('selected', 'randomSelected') and not selected: raise ValueError('Choose token artwork before using a selected mode')
        if value['mode'] == 'selected' and len(selected) != 1: raise ValueError('Choose exactly one manual token artwork')
        normalized = {'mode': value['mode'], 'selected': selected}
        if 'overrides' in value:
            overrides = value['overrides']
            # A deck edit can remove a token maker while its previously saved
            # artwork is still in an open client's preferences. Drop only an
            # unchanged persisted override; a new/edited unrelated family must
            # still fail validation. Bound both the old and current families.
            if not isinstance(overrides, dict) or len(overrides) > 200: raise ValueError('Choose at most 100 token families')
            previous = self.token_preferences(deck_id).get('overrides') or {}
            allowed = catalog._related_token_families(deck);result = {}
            total = 0
            for key, pref in overrides.items():
                if key not in allowed:
                    if key in previous and pref == previous[key]: continue
                    raise ValueError('Token artwork must belong to a token made by this deck')
                if not isinstance(pref, dict) or pref.get('mode') not in MODES: raise ValueError('Token artwork must belong to a token made by this deck')
                if len(result) >= 100: raise ValueError('Choose at most 100 token families')
                ids = pref.get('selected', [])
                if not isinstance(ids, list) or len(ids) > 500 or any(not isinstance(i, str) for i in ids): raise ValueError('Invalid selected token artwork list')
                ids = list(dict.fromkeys(ids));total += len(ids)
                if total > 500: raise ValueError('Choose at most 500 token artworks across this deck')
                for identifier in ids:
                    item = catalog.token_item(identifier)
                    if not item or item['tokenIdentity'] != key: raise ValueError('Selected illustration does not match this token identity')
                if pref['mode'] == 'selected' and len(ids) != 1: raise ValueError('Manual token artwork needs exactly one illustration')
                if pref['mode'] == 'randomSelected' and not ids: raise ValueError('Choose illustrations before using Random selected')
                result[key] = {'mode': pref['mode'], 'selected': ids}
            normalized['overrides'] = result
        with self.connection(write=True) as c: c.execute('INSERT INTO token_preferences VALUES (?,?,?) ON CONFLICT(deck_id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at', (deck_id, encode(normalized), now()))
        return normalized
