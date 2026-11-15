"""Choose cached cover media without substituting an exact printing/artist."""
from contextlib import closing
import json


def cover(catalog, storage, name, printing_id='', deck_id=''):
    if not isinstance(name, str) or not 1 <= len(name) <= 300 or not isinstance(printing_id, str) or len(printing_id) > 100:
        raise ValueError('Choose one card and optional exact printing for the cover')
    if deck_id:
        storage.check_id(deck_id)
        deck = storage.get_deck(deck_id)
        if deck and not printing_id:
            selections = [entry for entry in deck.get('printingSelections', []) if entry.get('name') == name and entry.get('printingId')]
            total = sum(entry.get('count', 1) for entry in selections)
            if total:
                seed = 0
                for value in name.encode('utf-8'):seed = (seed * 31 + value) % 2147483647
                selected = seed % total
                for choice in selections:
                    selected -= choice.get('count', 1)
                    if selected < 0:printing_id = choice['printingId'];break
    card = catalog.get(name=name, printing_id=printing_id or None)
    if not card:raise KeyError('Cover card not found')
    face = card.get('requested_face', 0)
    for kind in ('art_crop', 'normal'):
        if printing_id:
            # Exact identities must not be hidden beyond a bounded alias page.
            kinds=('normal','large')if kind=='normal'else(kind,)
            with storage.connection()as connection:
                for stored_kind in kinds:
                    key=f'{printing_id}-{face}-{stored_kind}.jpg'
                    row=connection.execute('SELECT metadata FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                    if row:
                        metadata=json.loads(row['metadata'])
                        if metadata.get('oracleId')!=card['id']or int(metadata.get('face',0))!=face:continue
                        chosen=dict(card,requested_face=face,printingExact=True,printingResolved=True)
                        return{'card':chosen,'kind':kind,'cached':True}
            continue
        with closing(storage.iter_art_candidates(card['id'], face, kind)) as candidates:
            for candidate in candidates:
                printing = candidate.get('printingId')
                if not printing or printing_id and printing != printing_id:continue
                chosen = catalog.get(identifier=card['id'], printing_id=printing)
                if chosen:
                    chosen['requested_face'] = face;chosen['printingExact'] = True;chosen['printingResolved'] = True
                    return {'card': chosen, 'kind': kind, 'cached': True}
    # A missing exact choice remains exact. On-demand artwork policy may fetch
    # it later, while Cache only keeps the honest unavailable placeholder.
    card['printingExact'] = True;card['printingResolved'] = True
    return {'card': card, 'kind': 'art_crop', 'cached': False}
