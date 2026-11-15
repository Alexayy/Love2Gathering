"""Immutable MTGJSON product/deck source and bounded SQLite browsing.

This is product metadata, never a statement of current engine legality. User
copies use the normal construction validator and never update source templates.
"""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit
from replays import encode
from search_text import words, register_search

READY_TYPES = {'Theme Deck','Commander Deck','Intro Pack','Arena Starter Deck','Welcome Deck','Duel Deck','Sample Deck',
               'Planeswalker Deck','World Championship Deck','Event Deck','Challenger Deck','Starter Deck','Enhanced Deck',
               'MTGO Theme Deck','Game Night Deck','Starter Kit','Advanced Deck','Planechase Deck','Guild Kit','Clash Pack',
               'Advanced Pack','Demo Deck','Arena Starter Kit','Archenemy Deck','Pro Tour Deck','Pioneer Challenger Deck',
               'Duel Of The Planeswalkers Deck','Historic Brawl Precon Deck','Arena Promotional Deck','Brawl Deck',
               'Spellslinger Starter Kit','Premium Deck','Challenge Deck','MTGO Commander Deck','MTGO Duel Deck',
               'Modern Event Deck','Dandan Deck'}
PACKET_TYPES = {'Jumpstart','Halfdeck','Booster Battle Pack Packet','Welcome Booster'}


def product_id(filename):
    return 'precon-' + hashlib.sha256(filename.encode('utf-8')).hexdigest()[:20]


def entries(cards):
    result = {}
    for card in cards or []:
        name, count = card.get('name'), card.get('count', 1)
        if not isinstance(name, str) or not name or isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 10000:
            raise ValueError('Invalid MTGJSON product card/name/count')
        result[name] = result.get(name, 0) + count
    return [{'name': name, 'count': count} for name, count in result.items()]


def normalize_deck(raw, filename, set_names, source_meta):
    kind = raw.get('type') or 'Unknown product'
    zones = {dest: entries(raw.get(source)) for source,dest in [('mainBoard','main'),('sideBoard','sideboard'),('commander','commander'),('planes','planes'),('schemes','schemes')]}
    counts = {zone: sum(card['count'] for card in cards) for zone,cards in zones.items()}
    total = counts['main'] + counts['sideboard'] + counts['commander']
    category = 'deck' if kind in READY_TYPES else 'packet' if kind in PACKET_TYPES else 'collection'
    # Ordinary Secret Lair drops and complete-set collections are not ready decks.
    # Full Commander products within Secret Lair are actual 100-card decks.
    if kind == 'Secret Lair Drop' and counts['commander'] > 0 and counts['main'] + counts['commander'] == 100: category = 'deck'
    if kind == 'Box Set' and 40 <= counts['main'] <= 100 and total <= 120: category = 'deck'
    commander_product = category == 'deck' and ('Commander' in kind or (kind == 'Secret Lair Drop' and counts['commander']))
    fmt = 'Commander' if commander_product else 'Pioneer' if kind == 'Pioneer Challenger Deck' else 'Modern' if kind == 'Modern Event Deck' else 'Archive'
    historical = 'Commander' if commander_product else 'Pioneer' if kind == 'Pioneer Challenger Deck' else 'Modern' if kind == 'Modern Event Deck' else 'Brawl' if 'Brawl' in kind else 'Planechase' if 'Planechase' in kind else 'Archenemy' if 'Archenemy' in kind else 'Jumpstart' if category == 'packet' else 'Standard' if kind in ('Challenger Deck','Event Deck','Planeswalker Deck') else 'Constructed (release-era)' if category == 'deck' else 'Product collection'
    face_cards = raw.get('displayCommander') or raw.get('commander') or []
    face = face_cards[0].get('name') if face_cards else None
    cover = face or ((raw.get('mainBoard') or [{}])[0].get('name'))
    colors = {color for zone in ('mainBoard','sideBoard','commander') for card in raw.get(zone, []) for color in card.get('colorIdentity', [])}
    code = str(raw.get('code') or '').lower()
    description = raw.get('description')
    if description is None:
        description = kind+' — '+set_names.get(code.upper(),code.upper())+'; original product list, current legality unverified.'
    elif not isinstance(description,str) or len(description)>20000:
        raise ValueError('Product description must be a string up to 20000 characters')
    original = raw.get('source') or ''
    host = (urlsplit(original).hostname or '').lower()
    source = {'provider':'MTGJSON','fileName':filename,'url':'https://mtgjson.com/api/v5/decks/'+filename+'.json',
              'originalURL':original,'officialOriginal':host == 'wizards.com' or host.endswith('.wizards.com') or host.endswith('.wizards.co.jp'),
              'date':source_meta.get('date'),'version':source_meta.get('version'),'license':'MIT','licenseURL':'https://mtgjson.com/license/'}
    deck = {'id':product_id(filename),'name':raw.get('name') or filename,'format':fmt,'historicalFormat':historical,
            'origin':'preconstructed','collection':'preconstructed','readOnly':True,'archived':True,'playable':False,
            'validationStatus':'Archive: not validated for the current snapshot or installed engine',
            'productType':kind,'category':category,'set':code,'expansion':set_names.get(code.upper(),code.upper()),
            'releaseDate':raw.get('releaseDate'),'faceCommander':face,'faceCommanders':[card.get('name') for card in face_cards if card.get('name')],
            'coverCard':cover,'colorIdentity':[color for color in 'WUBRG' if color in colors],'counts':counts,
            'source':source,'description':description,**zones}
    printings = []
    for source_zone,zone in [('mainBoard','main'),('sideBoard','sideboard'),('commander','commander')]:
        for card in raw.get(source_zone, []):
            choice = {'name':card['name'],'count':card.get('count',1),'zone':zone}
            if card.get('setCode'): choice['set'] = card['setCode'].lower()
            if card.get('number'): choice['collectorNumber'] = str(card['number'])
            printing = (card.get('identifiers') or {}).get('scryfallId')
            if printing: choice['printingId'] = printing
            printings.append(choice)
    deck['printingSelections'] = printings
    return deck


def summary(deck):
    return {key:deck.get(key) for key in ('id','name','format','historicalFormat','origin','collection','readOnly','archived','playable','validationStatus','productType','category','set','expansion','releaseDate','faceCommander','faceCommanders','coverCard','colorIdentity','counts','source')}


class PreconStore:
    def _init_precons(self):
        self._precon_signature = None
        self.precon_source = Path(os.environ.get('LOVE2GATHERING_PRECON_SOURCE', str(self.bundled/'preconstructed/catalog.jsonl.gz')))
        with self.connection() as c:
            c.executescript('''CREATE TABLE IF NOT EXISTS preconstructed(id TEXT PRIMARY KEY,name TEXT NOT NULL,format TEXT NOT NULL,historical_format TEXT NOT NULL,category TEXT NOT NULL,set_code TEXT NOT NULL,expansion TEXT NOT NULL,product_type TEXT NOT NULL,release_date TEXT,summary TEXT NOT NULL,payload TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1);
                CREATE INDEX IF NOT EXISTS precon_browse ON preconstructed(active,category,format,release_date DESC,name);
                CREATE INDEX IF NOT EXISTS precon_set ON preconstructed(active,set_code,name);''')
        self._seed_precons()

    def _seed_precons(self):
        source = self.precon_source
        if not source.is_file(): return
        stat = source.stat();signature = (str(source.resolve()),stat.st_size,stat.st_mtime_ns)
        if signature == self._precon_signature: return
        with self.lock:
            marker = encode(signature)
            with self.connection() as c:
                row = c.execute("SELECT value FROM meta WHERE key='precons_source'").fetchone()
            if row and row[0] == marker: self._precon_signature = signature;return
            opener = gzip.open if source.suffix == '.gz' else open
            with self.connection(write=True) as c:
                c.execute('UPDATE preconstructed SET active=0')
                with opener(source,'rt',encoding='utf-8') as stream:
                    for number,line in enumerate(stream,1):
                        if len(line) > 2*1024*1024: raise ValueError('Normalized precon record exceeds 2 MiB')
                        record = json.loads(line)
                        if '_meta' in record:
                            c.execute("INSERT INTO meta VALUES('precons_metadata',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(encode(record['_meta']),));continue
                        self.check_id(record['id'])
                        if not str(record['id']).startswith('precon-'): raise ValueError('Invalid normalized precon ID')
                        c.execute('INSERT INTO preconstructed VALUES (?,?,?,?,?,?,?,?,?,?,?,1) ON CONFLICT(id) DO UPDATE SET name=excluded.name,format=excluded.format,historical_format=excluded.historical_format,category=excluded.category,set_code=excluded.set_code,expansion=excluded.expansion,product_type=excluded.product_type,release_date=excluded.release_date,summary=excluded.summary,payload=excluded.payload,active=1',
                                  (record['id'],record['name'],record['format'],record['historicalFormat'],record['category'],record['set'],record['expansion'],record['productType'],record.get('releaseDate'),encode(summary(record)),encode(record)))
                c.execute("INSERT INTO meta VALUES('precons_source',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(marker,))
            self._precon_signature = signature

    def precons(self, query='', format_name='', set_code='', product_type='', category='deck', limit=24, offset=0):
        self._seed_precons()
        if category not in ('deck','packet','collection','all'): raise ValueError('Precon category must be deck, packet, collection or all')
        if any(not isinstance(v,str) or len(v)>300 for v in (query,format_name,set_code,product_type)): raise ValueError('Precon filter exceeds 300 characters')
        if not isinstance(limit,int) or not 1<=limit<=60 or not isinstance(offset,int) or offset<0: raise ValueError('Invalid precon page bounds')
        clauses,params=['active=1'],[]
        if category!='all':clauses.append('category=?');params.append(category)
        if format_name:clauses.append('(format=? COLLATE NOCASE OR historical_format=? COLLATE NOCASE)');params.extend((format_name,format_name))
        if set_code:clauses.append('set_code=?');params.append(set_code.lower())
        if product_type:clauses.append('product_type=? COLLATE NOCASE');params.append(product_type)
        if words(query):
            clauses.append("l2g_words(name||' '||expansion||' '||product_type||' '||COALESCE(json_extract(summary,'$.faceCommander'),''),?)=1");params.append(query)
        elif query.strip():clauses.append('instr(lower(name),?)>0');params.append(query.casefold())
        where=' WHERE '+' AND '.join(clauses)
        with self.connection() as c:
            register_search(c)
            total=c.execute('SELECT count(*) FROM preconstructed'+where,params).fetchone()[0]
            rows=c.execute("SELECT summary FROM preconstructed"+where+" ORDER BY COALESCE(release_date,'') DESC,expansion COLLATE NOCASE,name COLLATE NOCASE,id LIMIT ? OFFSET ?",(*params,limit,offset))
            decks=[json.loads(row[0]) for row in rows]
        return {'decks':decks,'items':decks,'total':total,'limit':limit,'offset':offset,'category':category}

    def get_precon(self,identifier):
        self.check_id(identifier);self._seed_precons()
        with self.connection() as c:row=c.execute('SELECT payload FROM preconstructed WHERE id=?',(identifier,)).fetchone()
        return json.loads(row[0]) if row else None

    def precon_stats(self):
        self._seed_precons()
        with self.connection() as c:
            totals={row[0]:row[1] for row in c.execute('SELECT category,count(*) FROM preconstructed WHERE active=1 GROUP BY category')}
            metadata=c.execute("SELECT value FROM meta WHERE key='precons_metadata'").fetchone()
            sets=[{'code':row[0],'name':row[1],'count':row[2]} for row in c.execute("SELECT set_code,expansion,count(*) FROM preconstructed WHERE active=1 AND category IN ('deck','packet') GROUP BY set_code,expansion ORDER BY expansion COLLATE NOCASE")]
            types=[{'id':row[0],'count':row[1]} for row in c.execute("SELECT product_type,count(*) FROM preconstructed WHERE active=1 AND category IN ('deck','packet') GROUP BY product_type ORDER BY product_type")]
            formats=[{'id':row[0],'count':row[1]} for row in c.execute("SELECT historical_format,count(*) FROM preconstructed WHERE active=1 AND category IN ('deck','packet') GROUP BY historical_format ORDER BY historical_format")]
        return {'ready':bool(metadata),'totalSourceRecords':sum(totals.values()),'deckCount':totals.get('deck',0),'packetCount':totals.get('packet',0),'withheldCollectionCount':totals.get('collection',0),'sets':sets,'types':types,'formats':formats,'source':json.loads(metadata[0]) if metadata else None}
