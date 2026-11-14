"""Local image identity and mirrors. SQL BLOBs always precede filesystem/network."""
import json
from pathlib import Path
import os
import sqlite3
from replays import encode, now


class ArtworkStore:
    def artwork_summary(self):
        with self.connection()as c:
            counts={row[0]:row[1]for row in c.execute("SELECT CASE WHEN cache_key LIKE '%-art_crop.jpg' THEN 'artCrops' WHEN cache_key LIKE '%-normal.jpg' OR cache_key LIKE '%-large.jpg' THEN 'fullCards' ELSE 'legacy' END,count(*)FROM art_cache INDEXED BY sqlite_autoindex_art_cache_1 GROUP BY 1")}
        return {'cachedImages':sum(counts.values()),'fullCards':counts.get('fullCards',0),'artCrops':counts.get('artCrops',0),'legacy':counts.get('legacy',0)}
    def artwork_statuses(self,items,kind='art_crop'):
        keys={item['printing_id']+'-'+str(item.get('face',0))+'-'+kind+'.jpg'for item in items}
        with self.connection()as c:
            cached={row[0]for row in c.execute('SELECT cache_key FROM art_cache WHERE cache_key IN ('+','.join('?'for _ in keys)+')',tuple(keys))}if keys else set()
        for item in items:item['art_cached']=item['printing_id']+'-'+str(item.get('face',0))+'-'+kind+'.jpg'in cached
        return items
    def art_candidates(self, oracle_id, face=0, kind='normal', limit=40):
        kinds = ('normal', 'large') if kind == 'normal' else (kind,)
        with self.connection() as c:
            rows = c.execute("SELECT cache_key,metadata FROM art_cache WHERE json_extract(metadata,'$.oracleId')=? AND CAST(json_extract(metadata,'$.face') AS INTEGER)=? AND json_extract(metadata,'$.kind') IN (" + ','.join('?' for _ in kinds) + ") ORDER BY CASE json_extract(metadata,'$.kind') WHEN ? THEN 0 ELSE 1 END,cache_key LIMIT ?", (oracle_id, face, *kinds, kind, limit))
            return [dict(key=r['cache_key'], **json.loads(r['metadata'])) for r in rows]

    def local_art(self, printing_id, oracle_id, face=0, kind='normal', aliases=True):
        """Return bytes plus the actual SQL identity without relabeling an alias."""
        key = f'{printing_id}-{face}-{kind}.jpg'
        keys = [key]
        if kind == 'normal':
            keys += [f'{printing_id}-{face}-large.jpg', f'{printing_id}-{face}.jpg']
            if aliases: keys.append(f'{oracle_id}-{face}.jpg')
        with self.connection() as c:
            for candidate in keys:
                self._check_art_key(candidate)
                row = c.execute('SELECT content,metadata FROM art_cache WHERE cache_key=?', (candidate,)).fetchone()
                if row: return bytes(row['content']), candidate, json.loads(row['metadata'])
            if aliases and oracle_id:
                kinds = ('normal', 'large') if kind == 'normal' else (kind,)
                row = c.execute("SELECT cache_key,content,metadata FROM art_cache WHERE json_extract(metadata,'$.oracleId')=? AND CAST(json_extract(metadata,'$.face') AS INTEGER)=? AND json_extract(metadata,'$.kind') IN (" + ','.join('?' for _ in kinds) + ") ORDER BY CASE json_extract(metadata,'$.kind') WHEN ? THEN 0 ELSE 1 END,cache_key LIMIT 1", (oracle_id, face, *kinds, kind)).fetchone()
                if row: return bytes(row['content']), row['cache_key'], json.loads(row['metadata'])
        # Mirrors are only imported when no entitled SQL image is available.
        # They never overwrite a newer SQL image or masquerade as another kind.
        library = Path(os.environ.get('LOVE2GATHERING_IMAGE_LIBRARY', str(self.root / 'image-library')))
        for candidate in keys:
            if not self.art_mirror_import_allowed(candidate):continue
            folder = 'art-crops' if candidate.endswith('-art_crop.jpg') else 'full-cards'
            for path in (self.root / 'art' / candidate, library / folder / candidate):
                if not path.is_file() or not 2 <= path.stat().st_size <= 3 * 1024 * 1024: continue
                data = path.read_bytes()
                if not data.startswith(b'\xff\xd8'): continue
                actual_kind = 'large' if candidate.endswith('-large.jpg') else kind
                metadata = {'oracleId': oracle_id, 'face': face, 'kind': actual_kind, 'mirrorSource': str(path)}
                if candidate == f'{oracle_id}-{face}.jpg' and oracle_id != printing_id: metadata['legacyOracleAlias'] = True
                else: metadata['printingId'] = printing_id
                with self.connection(write=True) as c:
                    if not self.art_mirror_import_allowed(candidate,connection=c):continue
                    c.execute("INSERT OR IGNORE INTO art_cache VALUES (?,?,'image/jpeg',?,?)", (candidate, sqlite3.Binary(data), encode(metadata), now()))
                    row = c.execute('SELECT content,metadata FROM art_cache WHERE cache_key=?', (candidate,)).fetchone()
                    return bytes(row['content']), candidate, json.loads(row['metadata'])
        return None


def prefer_cached_card(catalog, storage, card):
    if not card: return card
    for candidate in storage.art_candidates(card['id'], card.get('requested_face', 0)):
        printing = candidate.get('printingId')
        if not printing or printing == card.get('printing_id'): return card
        try:
            cached = catalog.get(identifier=card['id'], printing_id=printing)
            if cached:
                if 'requested_face' in card: cached['requested_face'] = card['requested_face']
                cached['art_cached'] = True
                return cached
        except ValueError: continue
    return card
