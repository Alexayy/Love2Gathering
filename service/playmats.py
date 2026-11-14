"""Bot art uses exact full-art metadata and cache keys, never guessed sets."""
from functools import lru_cache
import hashlib
import json
from pathlib import Path

@lru_cache(maxsize=1)
def _lands():
    path=Path(__file__).resolve().parents[1]/'assets/card-art/full-art-basics.json'
    try:return json.loads(path.read_text())['lands']
    except (OSError,ValueError,KeyError):return{}

def lookup_playmat(catalog,storage,name,seed=''):
    options=_lands().get(name)
    if not options:raise ValueError('Choose a basic-land art descriptor supplied by the native game')
    if not isinstance(seed,str)or len(seed)>200:raise ValueError('Invalid playmat seed')
    with storage.connection()as c:
        cached=[]
        for entry in options:
            if c.execute('SELECT 1 FROM art_cache WHERE cache_key=?',(entry['printingId']+'-0-art_crop.jpg',)).fetchone():cached.append(entry)
    pool=cached or options
    start=int.from_bytes(hashlib.sha256(seed.encode()).digest()[:4],'big')%len(pool)
    for choice in pool[start:]+pool[:start]:
        try:card=catalog.get(identifier=choice['printingId'])
        except ValueError:card=None
        if card:return {'reference':choice,'card':card,'cached':bool(cached),'fullArt':True}
    raise KeyError('No known full-art basic printing is present in this configured snapshot')
