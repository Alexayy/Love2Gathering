"""Bounded, per-printing/face artwork index over the original streaming source."""
import json
import re
from artists import artist_links
from search_text import words, register_search

IMAGE_KINDS = ("normal", "large", "art_crop")
GALLERY_INDEXES = (
    "CREATE INDEX gallery_name ON gallery(name COLLATE NOCASE,id)",
    "CREATE INDEX gallery_artist ON gallery(artist COLLATE NOCASE,name COLLATE NOCASE,id)",
    "CREATE INDEX gallery_set ON gallery(set_code,lang,name COLLATE NOCASE,id)",
    "CREATE INDEX gallery_variant ON gallery(variant,lang,name COLLATE NOCASE,id)",
)


def images(value):
    return {key: url for key, url in (value or {}).items() if key in IMAGE_KINDS and isinstance(url, str)}


class GalleryCatalog:
    @staticmethod
    def create_gallery(connection, *, indexes=True):
        connection.executescript("""
            CREATE TABLE gallery(id TEXT PRIMARY KEY,printing_id TEXT NOT NULL,
                face INTEGER NOT NULL,oracle_id TEXT NOT NULL,name TEXT NOT NULL,
                artist TEXT NOT NULL,set_code TEXT NOT NULL,lang TEXT NOT NULL,
                year TEXT NOT NULL,variant TEXT NOT NULL,search TEXT NOT NULL,payload TEXT NOT NULL);
            CREATE UNIQUE INDEX gallery_printing_face ON gallery(printing_id,face);
        """)
        if indexes:
            for statement in GALLERY_INDEXES:
                connection.execute(statement)

    @staticmethod
    def index_gallery(connection, raw):
        if raw.get("object") != "card" or not raw.get("id") or not raw.get("name"):
            return
        printing = str(raw["id"])
        base_images = images(raw.get("image_uris"))
        faces = raw.get("card_faces") or []
        # A transform/modal card supplies separate images per face. Split/adventure
        # layouts share a single card image, and therefore a single gallery entry.
        art_faces = [(index, face, images(face.get("image_uris"))) for index, face in enumerate(faces) if images(face.get("image_uris")).get("art_crop")]
        if not art_faces and base_images.get("art_crop"):
            art_faces = [(0, raw, base_images)]
        effects = raw.get("frame_effects") or []
        variants = []
        if "extendedart" in effects: variants.append("extended")
        if raw.get("border_color") == "borderless": variants.append("borderless")
        if "showcase" in effects: variants.append("showcase")
        for face_index, face, face_images in art_faces:
            name = face.get("name") or raw["name"]
            artist = face.get("artist") or raw.get("artist") or ""
            released = raw.get("released_at") or ""
            item = {"id": printing + "-" + str(face_index), "printing_id": printing,
                    "oracle_id": raw.get("oracle_id") or printing, "face": face_index,
                    "name": name, "card_name": raw["name"], "set": raw.get("set") or "",
                    "set_name": raw.get("set_name") or raw.get("set") or "",
                    "artist": artist, "artist_ids": face.get("artist_ids") or ([face["artist_id"]] if face.get("artist_id") else raw.get("artist_ids") or []),
                    "released_at": released, "year": released[:4] if re.match(r"^\d{4}-", released) else "",
                    "image_uris": face_images, "lang": raw.get("lang") or "en",
                    "collector_number": raw.get("collector_number") or "",
                    "frame_effects": effects, "border_color": raw.get("border_color") or "",
                    "variants": variants, "scryfall_uri": raw.get("scryfall_uri") or ""}
            search = " ".join((name, raw["name"], artist, item["set"], item["set_name"], item["year"])).casefold()
            connection.execute("INSERT OR REPLACE INTO gallery VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", (
                item["id"], printing, face_index, item["oracle_id"], name, artist,
                item["set"], item["lang"], item["year"], " ".join(variants), search,
                json.dumps(item, ensure_ascii=False, separators=(",", ":"))))

    def gallery(self, query="", artist="", set_code="", variant="all", language="en", limit=24, offset=0):
        if variant not in ("all", "extended", "borderless", "showcase"):
            raise ValueError("Gallery variant must be all, extended, borderless or showcase")
        if not re.fullmatch(r"all|[a-z]{2,4}", language): raise ValueError("Invalid gallery language")
        if not isinstance(limit, int) or not 1 <= limit <= 60 or not isinstance(offset, int) or offset < 0:
            raise ValueError("Gallery pages require limit 1 to 60 and nonnegative offset")
        if any(len(value) > 300 for value in (query, artist, set_code)):
            raise ValueError("Gallery filters must contain at most 300 characters")
        clauses, params = [], []
        for token in words(query):
            clauses.append("(instr(search,?)>0 OR instr(search,'&')>0)"if token=='and'else"instr(search,?)>0");params.append(token)
        if words(query):clauses.append('l2g_words(search,?)=1');params.append(query)
        elif query.strip():clauses.append('instr(search,?)>0');params.append(query.casefold())
        if artist:
            clauses.append("instr(lower(artist),?)>0");params.append(artist.casefold())
        if set_code:
            clauses.append("set_code=?");params.append(set_code.casefold())
        if variant != "all":
            clauses.append("instr(variant,?)>0");params.append(variant)
        if language != "all":
            clauses.append("lang=?");params.append(language)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        with self.connect() as connection:
            register_search(connection)
            if words(query)and connection.execute('SELECT 1 FROM gallery'+where+(' AND 'if where else' WHERE ')+'l2g_words(name,?)=1 LIMIT 1',(*params,query)).fetchone():
                where+=(' AND 'if where else' WHERE ')+'l2g_words(name,?)=1';params.append(query)
            total = connection.execute("SELECT count(*) FROM gallery" + where, params).fetchone()[0]
            ordering='name COLLATE NOCASE,set_code,printing_id,face';ranking=()
            if words(query):ordering='l2g_prefix(name,?) DESC,l2g_words(name,?) DESC,'+ordering;ranking=(query,query)
            items = [json.loads(row[0]) for row in connection.execute("SELECT payload FROM gallery" + where + ' ORDER BY '+ordering+' LIMIT ? OFFSET ?', (*params,*ranking, limit, offset))]
        for item in items: item["artist_links"] = artist_links(item["artist"])
        return {"items": items, "total": total, "limit": limit, "offset": offset}

    def gallery_item(self, printing_id, face=0):
        if not isinstance(printing_id,str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", printing_id) or isinstance(face,bool) or not isinstance(face,int) or not 0 <= face <= 9:
            raise ValueError("Invalid gallery printing or face")
        with self.connect() as connection:
            row = connection.execute("SELECT payload FROM gallery WHERE printing_id=? AND face=?", (printing_id, face)).fetchone()
        return json.loads(row[0]) if row else None
