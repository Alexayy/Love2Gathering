"""Bounded same-card printing choices. Presentation never changes deck legality."""
import json
import re
from query_cache import cached_query


@cached_query
def printings(catalog, name, query='', set_code='', variant='all', limit=12, offset=0):
    if not isinstance(name, str) or not 1 <= len(name) <= 300:
        raise ValueError('Choose one card name')
    if any(not isinstance(value, str) or len(value) > 300 for value in (query, set_code)):
        raise ValueError('Printing filters exceed 300 characters')
    if variant not in ('all', 'extended', 'borderless', 'showcase'):
        raise ValueError('Unknown printing treatment')
    if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 60 or isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise ValueError('Printing pages require limit 1 to 60 and nonnegative offset')
    card = catalog.get(name=name)
    if not card:
        raise KeyError('Card not found')
    clauses, params = ['card_id=?'], [card['id']]
    # card_sets contains only the catalog's English, same-Oracle printings.
    # Never search names across the whole gallery and accidentally include tokens.
    if set_code:
        clauses.append('set_code=?');params.append(set_code.casefold())
    if query.strip():
        for word in query.casefold().split():
            clauses.append("instr(lower(set_name||' '||set_code||' '||COALESCE(collector_number,'')||' '||COALESCE(json_extract(payload,'$.artist'),'')||' '||COALESCE(json_extract(payload,'$.released_at'),'')),?)>0")
            params.append(word)
    treatment = {'extended': "instr(COALESCE(json_extract(payload,'$.frame_effects'),''),'extendedart')>0",
                 'showcase': "instr(COALESCE(json_extract(payload,'$.frame_effects'),''),'showcase')>0",
                 'borderless': "json_extract(payload,'$.border_color')='borderless'"}
    if variant != 'all':clauses.append(treatment[variant])
    where = ' WHERE ' + ' AND '.join(clauses)
    with catalog.connect() as connection:
        total = connection.execute('SELECT count(*) FROM card_sets'+where, params).fetchone()[0]
        rows = connection.execute('SELECT payload FROM card_sets'+where+" ORDER BY COALESCE(json_extract(payload,'$.released_at'),'') DESC,set_code,collector_number,printing_id LIMIT ? OFFSET ?", (*params, limit, offset))
        items = [json.loads(row[0]) for row in rows]
        sets = [{'code': row[0], 'name': row[1], 'count': row[2]} for row in connection.execute('SELECT set_code,MAX(set_name),COUNT(*) FROM card_sets WHERE card_id=? GROUP BY set_code ORDER BY MAX(set_name) COLLATE NOCASE LIMIT 400', (card['id'],))]
    for item in items:
        item['printingExact'] = True;item['printingResolved'] = True
    return {'name': card['name'], 'oracleId': card['id'], 'items': items, 'sets': sets,
            'total': total, 'limit': limit, 'offset': offset}


def validate_printings(deck, catalog, problem):
    """Validate saved exact choices against their original card and quantities."""
    totals = {}
    counts = {(zone, entry['name']): entry['count'] for zone in ('main','sideboard','commander') for entry in deck[zone]}
    for selection in deck.get('printingSelections', []):
        name = selection['name'];card = catalog.get(name=name)
        canonical = card['name'] if card else name
        key = (selection['zone'], canonical)
        if key not in counts:
            problem('printing_card', 'Artwork selection is not in this deck zone: '+name, [name]);continue
        totals[key] = totals.get(key, 0) + selection['count']
        if totals[key] > counts[key]:
            problem('printing_count', 'Artwork selections exceed the number of '+canonical+' in '+selection['zone']+'.', [canonical])
        selection['name'] = canonical
        printing_id = selection.get('printingId')
        # An unresolved imported set/collector reference remains an import note.
        # A chosen exact printing must always prove the same Oracle identity.
        if not printing_id:continue
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', printing_id):
            problem('printing_identity', 'Invalid artwork printing for '+canonical+'.', [canonical]);continue
        try:chosen = catalog.get(identifier=card['id'], printing_id=printing_id) if card else None
        except ValueError:chosen = None
        if not chosen:
            problem('printing_identity', 'The selected printing is not a printing of '+canonical+' in the local catalog.', [canonical]);continue
        if chosen.get('set'):selection['set'] = chosen['set']
        if chosen.get('collector_number'):selection['collectorNumber'] = str(chosen['collector_number'])
