"""Local image identity and mirrors. SQL BLOBs always precede filesystem/network."""
import json
from contextlib import closing
from pathlib import Path
import os
import sqlite3
from replays import encode, now
from thumbnails import VERSION as THUMBNAIL_VERSION


class ArtworkStore:
    @staticmethod
    def _art_candidate_keys(connection, oracle_id, face, kind, limit):
        """Select identity before touching image-overflow metadata pages.

        SQLite cannot substitute the expression-index value into an ORDER BY
        CASE(json_extract(metadata, ...)). That sort rereads metadata after
        every matching image BLOB. Query each indexed kind in preference order
        instead, reading only the key column until a candidate is examined.
        """
        keys = []
        for selected_kind in ('normal', 'large') if kind == 'normal' else (kind,):
            remaining = limit - len(keys)
            if remaining <= 0: break
            keys.extend(row[0] for row in connection.execute(
                "SELECT cache_key FROM art_cache WHERE json_extract(metadata,'$.oracleId')=? "
                "AND CAST(json_extract(metadata,'$.face') AS INTEGER)=? "
                "AND json_extract(metadata,'$.kind')=? ORDER BY cache_key LIMIT ?",
                (oracle_id, face, selected_kind, remaining)))
        return keys

    def artwork_summary(self):
        with self.connection()as c:
            counts={row[0]:row[1]for row in c.execute("SELECT CASE WHEN cache_key LIKE '%-art_crop.jpg' THEN 'artCrops' WHEN cache_key LIKE '%-normal.jpg' OR cache_key LIKE '%-large.jpg' THEN 'fullCards' ELSE 'legacy' END,count(*)FROM art_cache INDEXED BY sqlite_autoindex_art_cache_1 GROUP BY 1")}
            derived=c.execute('SELECT count(*),COALESCE(sum(length(content)),0)FROM '+self.image_table('art_thumbnails')).fetchone()
        return {'cachedImages':sum(counts.values()),'fullCards':counts.get('fullCards',0),'artCrops':counts.get('artCrops',0),'legacy':counts.get('legacy',0),'thumbnailImages':derived[0],'thumbnailBytes':derived[1]}
    def artwork_statuses(self,items,kind='art_crop'):
        keys={item['printing_id']+'-'+str(item.get('face',0))+'-'+kind+'.jpg'for item in items}
        with self.connection()as c:
            cached={row[0]for row in c.execute('SELECT cache_key FROM art_cache WHERE cache_key IN ('+','.join('?'for _ in keys)+')',tuple(keys))}if keys else set()
        for item in items:item['art_cached']=item['printing_id']+'-'+str(item.get('face',0))+'-'+kind+'.jpg'in cached
        return items
    def art_candidates(self, oracle_id, face=0, kind='normal', limit=40):
        return list(self.iter_art_candidates(oracle_id,face,kind,limit))

    def iter_art_candidates(self, oracle_id, face=0, kind='normal', limit=40):
        """Read metadata only for candidates the caller actually examines.

        Metadata follows the image BLOB in legacy SQLite rows. A caller that
        accepts the first cached printing should not read/decode forty rows of
        cold image-overflow pages first. Keep SQL identity authoritative.
        """
        with self.connection() as c:
            keys = self._art_candidate_keys(c, oracle_id, face, kind, limit)
            for key in keys:
                row=c.execute('SELECT metadata FROM art_cache WHERE cache_key=?',(key,)).fetchone()
                if row:yield dict(key=key,**json.loads(row['metadata']))

    def _art_row(self,connection,key,variant):
        if variant=='thumb':
            row=connection.execute('SELECT t.content,t.metadata FROM '+self.image_table('art_thumbnails')+' t JOIN '+self.image_table('art_sources')+' s USING(cache_key) WHERE t.cache_key=? AND t.source_digest=s.digest AND t.version=?',(key,THUMBNAIL_VERSION)).fetchone()
            if row:return bytes(row['content']),key,dict(json.loads(row['metadata']),_imageVariant='thumb')
        row=connection.execute('SELECT content,metadata FROM art_cache WHERE cache_key=?',(key,)).fetchone()
        if not row:return None
        metadata=json.loads(row['metadata'])
        if variant=='thumb':
            status=self.queue_thumbnail(key)
            metadata=dict(metadata,_imageVariant='original',_thumbPending=status=='pending',_thumbUnavailable=status=='unavailable')
        return bytes(row['content']),key,metadata

    def local_art(self, printing_id, oracle_id, face=0, kind='normal', aliases=True, variant='original'):
        """Return bytes plus the actual SQL identity without relabeling an alias."""
        if variant not in('original','thumb'):raise ValueError('Image variant must be original or thumb')
        if variant=='thumb':self.enable_thumbnails()
        key = f'{printing_id}-{face}-{kind}.jpg'
        keys = [key]
        if kind == 'normal':
            keys += [f'{printing_id}-{face}-large.jpg', f'{printing_id}-{face}.jpg']
            if aliases: keys.append(f'{oracle_id}-{face}.jpg')
        with self.connection(image=True) as c:
            for candidate in keys:
                self._check_art_key(candidate)
                row=self._art_row(c,candidate,variant)
                if row:return row
            if aliases and oracle_id:
                # Choose identity without carrying BLOBs through the sort. Only
                # the winning exact row is loaded, with its matching metadata.
                identities = self._art_candidate_keys(c, oracle_id, face, kind, 1)
                if identities:
                    row=self._art_row(c,identities[0],variant)
                    if row:return row
        # Mirrors are only imported when no entitled SQL image is available.
        # They never overwrite a newer SQL image or masquerade as another kind.
        library = Path(os.environ.get('LOVE2GATHERING_IMAGE_LIBRARY', str(self.image_library)))
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
                with self.connection(write=True,image=True) as c:
                    if not self.art_mirror_import_allowed(candidate,connection=c):continue
                    c.execute("INSERT OR IGNORE INTO art_cache VALUES (?,?,'image/jpeg',?,?)", (candidate, sqlite3.Binary(data), encode(metadata), now()))
                    row = c.execute('SELECT content,metadata FROM art_cache WHERE cache_key=?', (candidate,)).fetchone()
                    if row:self._art_source(c,candidate,bytes(row['content']))
                if row:
                    self.queue_thumbnail(candidate)
                    metadata=json.loads(row['metadata'])
                    if variant=='thumb':metadata=dict(metadata,_imageVariant='original',_thumbPending=self.queue_thumbnail(candidate)=='pending')
                    return bytes(row['content']),candidate,metadata
        return None


def prefer_cached_card(catalog, storage, card):
    if not card: return card
    with closing(storage.iter_art_candidates(card['id'],card.get('requested_face',0)))as candidates:
        for candidate in candidates:
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
