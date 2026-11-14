"""Public presentation identity; native game life never belongs to a profile."""
import json
import uuid
from replays import encode, now

DEFAULT_PROFILE = {'name': 'Planeswalker', 'avatar': None, 'playmat': None}


def bounded_name(value, fallback='Planeswalker', maximum=80):
    value = fallback if value is None else value
    if not isinstance(value, str) or not value.strip() or len(value.strip()) > maximum or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Choose a name between 1 and ' + str(maximum) + ' characters')
    return value.strip()


def art_reference(value):
    if value is None: return None
    if not isinstance(value, dict) or set(value) - {'oracleId', 'printingId', 'face', 'name'}:
        raise ValueError('Artwork must contain card identities, not URLs or extra fields')
    result = {}
    for key in ('oracleId', 'printingId'):
        raw = value.get(key)
        if not isinstance(raw, str) or len(raw) != 36:
            raise ValueError('Artwork requires an exact printing and Oracle UUID')
        try: result[key] = str(uuid.UUID(raw))
        except ValueError: raise ValueError('Artwork requires an exact printing and Oracle UUID') from None
    face = value.get('face', 0)
    if not isinstance(face, int) or isinstance(face, bool) or not 0 <= face <= 9:
        raise ValueError('Artwork face must be between 0 and 9')
    result['face'] = face
    if value.get('name') is not None:
        result['name'] = bounded_name(value['name'], maximum=300)
    return result


def normalize_profile(value, fallback_name='Planeswalker'):
    if value is None: value = {}
    if not isinstance(value, dict) or set(value) - {'name', 'avatar', 'playmat'}:
        raise ValueError('Profile supports only name, avatar and playmat')
    if len(json.dumps(value, ensure_ascii=False)) > 4096:
        raise ValueError('Profile exceeds the presentation resource bound')
    return {'name': bounded_name(value.get('name'), fallback_name),
            'avatar': art_reference(value.get('avatar')), 'playmat': art_reference(value.get('playmat'))}


class ProfileStore:
    def _init_profile_storage(self):
        with self.connection(write=True) as c:
            c.execute('CREATE TABLE IF NOT EXISTS player_profile(singleton INTEGER PRIMARY KEY CHECK(singleton=1),payload TEXT NOT NULL,updated_at INTEGER NOT NULL)')

    def profile(self):
        with self.connection() as c:
            row = c.execute('SELECT payload FROM player_profile WHERE singleton=1').fetchone()
        return normalize_profile(json.loads(row[0])) if row else dict(DEFAULT_PROFILE)

    def save_profile(self, value, catalog):
        normalized = normalize_profile(value)
        previous = self.profile()
        for slot in ('avatar', 'playmat'):
            reference = normalized[slot]
            if reference is None: continue
            old = previous.get(slot)
            if old and all(old.get(key) == reference.get(key) for key in ('oracleId', 'printingId', 'face')):
                normalized[slot] = old
                continue
            if catalog is None or catalog.status().get('state') != 'ready':
                raise ValueError('Card index must be ready before choosing new artwork')
            item = catalog.gallery_item(reference['printingId'], reference['face'])
            if not item or item.get('oracle_id') != reference['oracleId'] or not item.get('image_uris', {}).get('art_crop'):
                raise ValueError('Selected card printing and face have no matching catalog illustration')
            reference['name'] = item['name']
        with self.connection(write=True) as c:
            c.execute('INSERT INTO player_profile VALUES(1,?,?) ON CONFLICT(singleton) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at', (encode(normalized), now()))
        return normalized
