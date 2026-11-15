"""Bounded deck preview, never a save or an authentication/challenge workaround."""
import csv
import io
import json
import re
import socket
import ipaddress
from urllib.parse import urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener
from urllib.error import HTTPError, URLError
import xml.etree.ElementTree as ET

MAX_BYTES = 1024 * 1024
HOSTS = {'archidekt.com', 'www.archidekt.com', 'moxfield.com', 'www.moxfield.com', 'api2.moxfield.com', 'mtggoldfish.com', 'www.mtggoldfish.com'}
ZONES = {'deck': 'main', 'main': 'main', 'mainboard': 'main', 'maindeck': 'main', 'main deck': 'main',
         'sideboard': 'sideboard', 'side': 'sideboard', 'commander': 'commander', 'commanders': 'commander',
         'companion': 'sideboard', 'maybeboard': 'excluded', 'considering': 'excluded', 'tokens': 'excluded', 'tokens & extras': 'excluded'}


def safe_url(value):
    if not isinstance(value, str) or len(value) > 2048 or any(ord(c) < 33 for c in value): raise ValueError('Invalid deck URL')
    p = urlsplit(value)
    if p.scheme != 'https' or p.hostname not in HOSTS or p.username or p.password or p.port not in (None, 443) or p.query or p.fragment not in ('', 'paper', 'online', 'arena'):
        raise ValueError('Use an HTTPS Archidekt, Moxfield or MTGGoldfish public deck URL without credentials or query parameters')
    return p


def export_url(value):
    p = safe_url(value);host = p.hostname.removeprefix('www.')
    if host == 'archidekt.com':
        match = re.fullmatch(r'/(?:api/)?decks/(\d{1,12})(?:/[^/?]*)?/?', p.path)
        if match: return 'https://archidekt.com/api/decks/' + match[1] + '/', 'Archidekt'
    elif host in ('moxfield.com', 'api2.moxfield.com'):
        match = re.fullmatch(r'/(?:v[23]/decks/all/|decks/)([A-Za-z0-9_-]{6,100})/?', p.path)
        if match: return 'https://api2.moxfield.com/v2/decks/all/' + match[1], 'Moxfield'
    elif host == 'mtggoldfish.com':
        match = re.fullmatch(r'/deck/(?:arena_download/|download/)?(\d{1,12})(?:/)?', p.path)
        if match: return 'https://www.mtggoldfish.com/deck/arena_download/' + match[1], 'MTGGoldfish'
    raise ValueError('Paste a public deck page URL, or paste/upload its text export')


def public_host(url):
    for address in socket.getaddrinfo(urlsplit(url).hostname, 443, type=socket.SOCK_STREAM):
        if not ipaddress.ip_address(address[4][0]).is_global: raise ValueError('Deck host resolved to a non-public address')


class SafeRedirect(HTTPRedirectHandler):
    max_redirections = 3
    max_repeats = 2
    def redirect_request(self, request, fp, code, message, headers, newurl):
        # Revalidate each hop before urllib contacts it; never send credentials.
        safe_url(newurl)
        target = urlsplit(newurl)
        if target.hostname.removeprefix('www.') != urlsplit(request.full_url).hostname.removeprefix('www.'):
            raise ValueError('Deck export redirected to another host; use a text export')
        public_host(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def download(value):
    url, provider = export_url(value)
    # A whitelisted hostname must still resolve to public addresses; this also
    # rejects accidentally configured private hosts before any request is sent.
    try:
        public_host(url)
        request = Request(url, headers={'User-Agent': 'Love2Gathering/1.0 (personal deck import)', 'Accept': 'application/json,text/plain,text/html'})
        with build_opener(SafeRedirect()).open(request, timeout=12) as response:
            safe_url(response.geturl());raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES: raise ValueError('Deck export exceeds the 1 MiB import bound')
            text = raw.decode('utf-8-sig')
    except (HTTPError, URLError, OSError, UnicodeError) as exc:
        raise ValueError(provider + ' export is unavailable or requires site access. Open its Export menu and paste/upload the text list instead.') from exc
    if '<html' in text[:2000].lower() or '<!doctype html' in text[:2000].lower():
        # Goldfish publishes the Arena list in a normal textarea. Extract only
        # that element; challenge/login documents are never interpreted as decks.
        if provider == 'MTGGoldfish':
            from html import unescape
            match = re.search(r'<textarea\b[^>]*>(.*?)</textarea>', text, re.S | re.I)
            if match: text = unescape(match[1])
            else: raise ValueError('MTGGoldfish did not supply an export. Paste its text export instead.')
        else: raise ValueError(provider + ' did not supply a public deck export. Paste/upload its text export instead.')
    return text, {'provider': provider, 'url': value}


def entry(name, count, zone='main', set_code=None, collector=None):
    if isinstance(count, bool): raise ValueError('Card quantity must be an integer')
    if isinstance(count, str) and not re.fullmatch(r'\d{1,3}', count): raise ValueError('Card quantity must be an integer')
    if not isinstance(count, (str, int)): raise ValueError('Card quantity must be an integer')
    count = int(count)
    if not 1 <= count <= 250: raise ValueError('Card quantities must be from 1 to 250')
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 300: raise ValueError('Invalid imported card name')
    result = {'name': name.strip(), 'count': count, 'zone': zone}
    if set_code: result['set'] = str(set_code).lower()[:12]
    if collector: result['collectorNumber'] = str(collector)[:40]
    return result


def parse_text(text):
    entries, warnings = [], []
    zone, title = 'main', None
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line: continue
        header = line.strip('/#[] :').strip().casefold()
        if header in ZONES: zone = ZONES[header];continue
        if line.startswith(('#', '//')): continue
        if header == 'about': continue
        if line.startswith('Name '): title = line[5:];continue
        if line.startswith('Format '): continue
        current = zone
        prefix = re.match(r'^(SB|SIDEBOARD|CMDR|CMD|COMMANDER):\s*', line, re.I)
        if prefix: current = 'sideboard' if prefix[1].upper() in ('SB', 'SIDEBOARD') else 'commander';line = line[prefix.end():]
        tags = re.findall(r'\[([^\]]+)\]', line)
        for tag in tags:
            for category in tag.split(','):
                clean = re.sub(r'\{[^}]*\}', '', category).strip().casefold()
                if clean in ZONES: current = ZONES[clean]
                if '{noDeck}' in category and clean not in ('commander', 'sideboard'): current = 'excluded'
        line = re.sub(r'\s*\[[^\]]+\]', '', line)
        line = re.sub(r'\s*(?:\*[FE]\*|\+FOIL|\(FOIL\))\s*$', '', line, flags=re.I)
        quantity = re.match(r'^(\d{1,4})x?\s+(.+)$', line, re.I)
        count, card_name = (quantity[1], quantity[2]) if quantity else (1, line)
        printing = re.match(r'^(.*?)\s+\(([A-Za-z0-9]{2,12})\)(?:\s+(\S{1,40}))?$', card_name)
        set_code, collector = (printing[2], printing[3]) if printing else (None, None)
        if printing: card_name = printing[1]
        try: entries.append(entry(card_name, count, current, set_code, collector))
        except ValueError as exc: raise ValueError('Line ' + str(number) + ': ' + str(exc)) from exc
    return entries, title, warnings


def parse_json(value):
    if not isinstance(value, dict): raise ValueError('Deck JSON must be an object')
    entries = []
    if isinstance(value.get('cards'), list):  # Archidekt's public deck object.
        for item in value['cards']:
            card = item.get('card') or {};oracle = card.get('oracleCard') or card
            categories = item.get('categories') or [];zone = 'main'
            for category in categories:
                category = category.get('name', '') if isinstance(category, dict) else str(category)
                zone = ZONES.get(category.casefold(), zone)
            entries.append(entry(oracle.get('name') or card.get('name'), item.get('quantity', 1), zone,
                                 (card.get('edition') or {}).get('editioncode') or card.get('set'), card.get('collectorNumber')))
    else:
        boards = value.get('boards') or value
        for source, zone in (('main', 'main'), ('mainboard', 'main'), ('sideboard', 'sideboard'), ('commander', 'commander'), ('commanders', 'commander')):
            items = boards.get(source, [])
            if isinstance(items, dict) and 'cards' in items: items = items['cards']
            if isinstance(items, dict): items = items.values()
            for item in items:
                card = item.get('card') or item
                entries.append(entry(card.get('name'), item.get('count', item.get('quantity', 1)), zone,
                                     card.get('set'), card.get('collectorNumber') or card.get('cn')))
    return entries, value.get('name'), []


def parse(text):
    if not isinstance(text, str) or not text.strip() or len(text.encode('utf-8')) > MAX_BYTES: raise ValueError('Paste a nonempty deck export up to 1 MiB')
    if len(text.splitlines()) > 4000: raise ValueError('Deck export exceeds 4000 lines')
    text = text.lstrip('\ufeff').strip()
    if text.startswith('{'): return parse_json(json.loads(text))
    if text.startswith('<'):
        if re.search(r'<!DOCTYPE|<!ENTITY', text, re.I): raise ValueError('XML entities and document types are not supported')
        root = ET.fromstring(text)
        if root.tag != 'cockatrice_deck': raise ValueError('Use a Cockatrice .cod file or a plain-text export')
        entries = []
        for section in root.findall('zone'):
            zone = 'sideboard' if section.get('name') in ('side', 'sideboard') else 'main'
            for card in section.findall('card'): entries.append(entry(card.get('name'), card.get('number', '1'), zone))
        return entries, root.findtext('deckname'), []
    first = text.splitlines()[0]
    if ',' in first and re.search(r'\b(?:name|card)\b', first, re.I) and re.search(r'\b(?:quantity|count|qty)\b', first, re.I):
        entries = []
        for row in csv.DictReader(io.StringIO(text)):
            row = {str(k).strip().lower(): v for k, v in row.items()}
            zone = 'commander' if row.get('commander', '').lower() in ('true', '1', 'yes') else 'sideboard' if row.get('sideboard', '').lower() in ('true', '1', 'yes') else ZONES.get(row.get('board', row.get('zone', '')).casefold(), 'main')
            entries.append(entry(row.get('name') or row.get('card'), row.get('quantity') or row.get('count') or row.get('qty'), zone, row.get('set'), row.get('collector number') or row.get('collector_number')))
        return entries, None, []
    return parse_text(text)


def preview(value, catalog, storage, fetcher=download):
    if not isinstance(value, dict): raise ValueError('Import preview must be an object')
    if bool(value.get('url')) == bool(value.get('text')): raise ValueError('Supply either deck text or one public URL')
    text, source = fetcher(value['url']) if value.get('url') else (value['text'], {'provider': 'Text/file'})
    entries, title, warnings = parse(text)
    deck = {'name': value.get('name') or title or 'Imported deck', 'format': value.get('format') or 'Commander', 'main': [], 'sideboard': [], 'commander': []}
    printings, excluded = [], []
    for item in entries:
        if item['zone'] == 'excluded': excluded.append(item);continue
        card = catalog.get(name=item['name'])
        if card: item['name'] = card['name']
        deck[item['zone']].append({'name': item['name'], 'count': item['count']})
        if item.get('set'):
            choice = {key: item[key] for key in ('name', 'count', 'zone', 'set', 'collectorNumber') if key in item}
            with catalog.connect() as c:
                row = c.execute('SELECT printing_id FROM card_sets WHERE card_id=? AND set_code=? AND (? IS NULL OR collector_number=?) ORDER BY printing_id LIMIT 1', ((card or {}).get('id'), item['set'], item.get('collectorNumber'), item.get('collectorNumber'))).fetchone()
            if row: choice['printingId'] = row[0]
            else: warnings.append('Printing not found locally: ' + item['name'] + ' (' + item['set'] + ') ' + item.get('collectorNumber', ''))
            printings.append(choice)
    if not any(deck[zone] for zone in ('main', 'sideboard', 'commander')): raise ValueError('No deck cards were found in the export')
    deck['printingSelections'] = printings
    normalized = storage.validate_deck(deck)
    from validation import validate
    result = validate(normalized, catalog)
    if excluded: warnings.append(str(len(excluded)) + ' maybeboard/token entries are shown separately and are not deck cards.')
    return {'deck': normalized, 'validation': result, 'warnings': warnings, 'excluded': excluded, 'source': source, 'printingSelections': printings, 'saved': False}
