"""Streaming, local Scryfall catalog. No rules are implemented here."""
from __future__ import annotations

import json
import gzip
import filelocks
import os
from pathlib import Path
import re
import sqlite3
import threading
import time
from gallery_catalog import GalleryCatalog
from tokens import TokenCatalog
from query_cache import QueryCache, cached_query
from formats import FORMATS, INDEXED_FORMATS, profile as format_profile, clause as format_clause

SCHEMA_VERSION = "7"


class CatalogConnection(sqlite3.Connection):
    """Read scopes own their connection, including failed queries.

    sqlite3's ordinary context manager only finishes a transaction. Leaving
    metadata connections open also retains their page caches/file descriptors
    until cyclic garbage collection runs during an active image download.
    """
    def __exit__(self,*args):
        try:return super().__exit__(*args)
        finally:self.close()


class Catalog(GalleryCatalog,TokenCatalog):
    def __init__(self, source: Path, database: Path):
        self.source = Path(source)
        self.database = Path(database)
        self.lock = threading.Lock()
        self.progress = {"state": "pending", "lines": 0, "cards": 0, "error": None}
        self.query_cache = QueryCache(self.database)

    def status(self):
        with self.lock:
            return dict(self.progress)

    def _status(self, **fields):
        with self.lock:
            self.progress.update(fields)

    def connect(self):
        connection = sqlite3.connect(f"file:{self.database}?mode=ro", uri=True, timeout=20, factory=CatalogConnection)
        connection.row_factory = sqlite3.Row
        return connection

    def current(self):
        if not self.database.exists() or not self.source.exists():
            return False
        try:
            with self.connect() as connection:
                meta = dict(connection.execute("SELECT key, value FROM metadata"))
                stat = self.source.stat()
                return (meta.get("schema") == SCHEMA_VERSION
                        and meta.get("source_size") == str(stat.st_size)
                        and meta.get("source_mtime") == str(stat.st_mtime_ns))
        except sqlite3.Error:
            return False

    def ensure(self):
        try:
            self.database.parent.mkdir(parents=True, exist_ok=True)
            # Installed desktop instances can share an index while owning
            # separate services. Serialize its temporary build across processes,
            # then recheck the complete index before doing expensive work.
            with (self.database.parent / (self.database.name + '.build.lock')).open('a+b') as lock:
                self._status(state='waiting', error=None)
                filelocks.flock(lock, filelocks.LOCK_EX)
                if self.current():
                    with self.connect() as connection:
                        count = connection.execute("SELECT count(*) FROM cards").fetchone()[0]
                    self._status(state="ready", cards=count)
                    return
                self.build()
        except Exception as exc:
            self._status(state="error", error=str(exc))

    @staticmethod
    def normalize(raw):
        faces = raw.get("card_faces", [])
        name = raw.get("name", "").strip()
        if not name or raw.get("object") != "card":
            return None
        fields = ("name", "mana_cost", "cmc", "type_line", "oracle_text", "colors",
                  "color_identity", "legalities", "image_uris", "set", "collector_number",
                  "power", "toughness", "loyalty", "defense", "layout", "released_at", "set_name",
                  "artist", "artist_ids", "frame_effects", "border_color", "illustration_id", "lang", "scryfall_uri", "all_parts")
        card = {key: raw.get(key) for key in fields}
        card.update(id=raw.get("oracle_id") or raw.get("id"),
                    printing_id=raw.get("id"), card_faces=faces)
        card["oracle_text"] = card["oracle_text"] or "\n\n".join(f.get("oracle_text", "") for f in faces)
        card["mana_cost"] = card["mana_cost"] or " // ".join(f.get("mana_cost", "") for f in faces)
        card["image_uris"] = card["image_uris"] or (faces[0].get("image_uris", {}) if faces else {})
        card["colors"] = card["colors"] or sorted({c for face in faces for c in face.get("colors", [])})
        card["color_identity"] = card["color_identity"] or []
        card["legalities"] = card["legalities"] or {}
        for field in ("power", "toughness", "loyalty", "defense"):
            if card[field] is None and faces:
                card[field] = faces[0].get(field)
        return card

    def build(self):
        self.database.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.database.with_suffix(".building.sqlite")
        temporary.unlink(missing_ok=True)
        self._status(state="indexing", lines=0, cards=0, error=None)
        started = time.monotonic()
        connection = sqlite3.connect(temporary)
        try:
            connection.execute("PRAGMA journal_mode=OFF")
            connection.execute("PRAGMA synchronous=OFF")
            connection.executescript("""
                CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE cards(id TEXT PRIMARY KEY, name TEXT UNIQUE COLLATE NOCASE,
                    search TEXT NOT NULL, type_line TEXT NOT NULL, colors TEXT NOT NULL,
                    modern TEXT, standard TEXT, pioneer TEXT, commander TEXT,
                    rank INTEGER NOT NULL, payload TEXT NOT NULL);
                CREATE INDEX cards_name ON cards(name COLLATE NOCASE);
                CREATE TABLE card_sets(card_id TEXT, set_code TEXT, set_name TEXT,
                    printing_id TEXT PRIMARY KEY, collector_number TEXT, image_url TEXT, face_images TEXT,payload TEXT);
                CREATE INDEX card_sets_card ON card_sets(card_id);
                CREATE INDEX card_sets_set ON card_sets(set_code, card_id);
                CREATE TABLE aliases(name TEXT PRIMARY KEY COLLATE NOCASE, card_id TEXT, face INTEGER);
            """)
            self.create_gallery(connection)
            self.create_tokens(connection)
            statement = """INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(name) DO UPDATE SET
                    id=excluded.id, search=excluded.search, type_line=excluded.type_line,
                    colors=excluded.colors, modern=excluded.modern, standard=excluded.standard,
                    pioneer=excluded.pioneer, commander=excluded.commander,
                    rank=excluded.rank, payload=excluded.payload WHERE excluded.rank > cards.rank"""
            lines = 0
            with (gzip.open(self.source, "rt", encoding="utf-8") if self.source.suffix == ".gz" else self.source.open("r", encoding="utf-8")) as stream:
                for lines, line in enumerate(stream, 1):
                    if not line.strip():
                        continue
                    try:
                        raw = json.loads(line)
                    except json.JSONDecodeError as exc:
                        raise ValueError(f"Invalid JSONL at line {lines}: {exc.msg}") from exc
                    self.index_gallery(connection, raw)
                    self.index_tokens(connection, raw)
                    # This local bulk file includes translations and printings. Keep one
                    # English oracle entry, preferring paper cards with usable card art.
                    if raw.get("lang", "en") != "en":
                        continue
                    card = self.normalize(raw)
                    if card is None:
                        continue
                    rank = (10 if not raw.get("digital", False) else 0) + (2 if card["image_uris"].get("normal") else 0)
                    rank += 1 if raw.get("highres_image") else 0
                    legalities = card["legalities"]
                    search = " ".join((card["name"], card["type_line"] or "", card["oracle_text"] or "")).casefold()
                    connection.execute(statement, (card["id"], card["name"], search,
                        (card["type_line"] or "").casefold(), "".join(card["color_identity"]),
                        *(legalities.get(fmt, "not_legal") for fmt in ("modern", "standard", "pioneer", "commander")),
                        rank, json.dumps(card, ensure_ascii=False, separators=(",", ":"))))
                    connection.execute("INSERT OR IGNORE INTO card_sets VALUES (?,?,?,?,?,?,?,?)", (
                        card["id"], card["set"], raw.get("set_name", card["set"]), card["printing_id"],
                        card["collector_number"], json.dumps({key: value for key, value in card["image_uris"].items() if key in ("normal", "large", "art_crop")}),
                        json.dumps([{key: value for key, value in f.get("image_uris", {}).items() if key in ("normal", "large", "art_crop")} for f in card["card_faces"]]),
                        json.dumps(card, ensure_ascii=False, separators=(",", ":"))))
                    for face, data in enumerate(card["card_faces"]):
                        if data.get("name"):
                            connection.execute("INSERT OR IGNORE INTO aliases VALUES (?,?,?)", (data["name"], card["id"], face))
                    if lines % 10000 == 0:
                        connection.commit()
                        count = connection.execute("SELECT count(*) FROM cards").fetchone()[0]
                        self._status(lines=lines, cards=count, seconds=round(time.monotonic() - started, 1))
            stat = self.source.stat()
            metadata = {"schema": SCHEMA_VERSION, "source_size": str(stat.st_size),
                        "source_mtime": str(stat.st_mtime_ns), "source_name": self.source.name}
            connection.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
            for fmt in INDEXED_FORMATS:
                connection.execute(f"CREATE INDEX cards_{fmt} ON cards({fmt})")
            connection.commit()
            count = connection.execute("SELECT count(*) FROM cards").fetchone()[0]
            connection.close()
            os.replace(temporary, self.database)
            self._status(state="ready", lines=lines, cards=count, seconds=round(time.monotonic() - started, 1))
        except Exception:
            connection.close()
            temporary.unlink(missing_ok=True)
            raise

    @cached_query
    def search(self, query="", format_name="", color="", type_name="", limit=50, offset=0, sort="name", set_code="", color_mode="legacy"):
        clauses, params = [], []
        for token in query.casefold().split():
            clauses.append("search LIKE ? ESCAPE '\\'")
            params.append("%" + token.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%")
        if format_name:
            condition=format_clause(format_name)
            if condition:clauses.append(condition)
        if color_mode not in ("legacy", "any", "exact"):
            raise ValueError("Color mode must be legacy, any or exact")
        if color:
            if not re.fullmatch("[WUBRGCwubrgc]+", color):
                raise ValueError("Colors must be W, U, B, R, G or C")
            selected = set(color.upper())
            if color_mode != "legacy" and "C" in selected and len(selected) > 1:
                raise ValueError("Colorless identity cannot be combined with colored identities")
            if color_mode == "any":
                if selected == {"C"}:
                    clauses.append("colors = ''")
                else:
                    clauses.append("(" + " OR ".join("instr(colors, ?) > 0" for _ in selected) + ")")
                    params.extend(sorted(selected))
            else:
                if color_mode == "exact":
                    # The indexed colors field stores identity, including mana
                    # symbols in rules/lands. Do not depend on snapshot order.
                    clauses.append("length(colors) = ?")
                    params.append(0 if selected == {"C"} else len(selected))
                for value in sorted(selected):
                    if value == "C":
                        clauses.append("colors = ''")
                    else:
                        clauses.append("instr(colors, ?) > 0")
                        params.append(value)
        if type_name:
            clauses.append("instr(type_line, ?) > 0")
            params.append(type_name.casefold())
        if set_code:
            clauses.append("EXISTS (SELECT 1 FROM card_sets s WHERE s.card_id=cards.id AND s.set_code=?)")
            params.append(set_code.casefold())
        orders = {"name": "name COLLATE NOCASE", "color": "CASE WHEN colors='' THEN 0 WHEN length(colors)>1 THEN 6 ELSE instr('WUBRG',colors) END, colors, name COLLATE NOCASE",
                  "set": "json_extract(payload,'$.set') COLLATE NOCASE, name COLLATE NOCASE"}
        if sort not in orders:
            raise ValueError("Sort must be name, color or set")
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        with self.connect() as connection:
            total = connection.execute("SELECT count(*) FROM cards" + where, params).fetchone()[0]
            # A broad opening page can stop after a few name-index entries.
            # A filtered page must retain SQLite's selective legality/index
            # plan: forcing alphabetical random row reads can inspect thousands
            # of cold payload pages before finding twenty matching cards.
            # Sort only identities/names, then fetch JSON for the chosen page.
            broad = not (query.strip() or color or type_name or set_code)
            source = "cards INDEXED BY cards_name" if sort == "name" and total > limit and broad else "cards"
            ids = [row[0] for row in connection.execute("SELECT id FROM " + source + where + " ORDER BY " + orders[sort] + " LIMIT ? OFFSET ?", (*params, limit, offset))] if total > offset else []
            payloads = {row[0]:row[1] for row in connection.execute("SELECT id,payload FROM cards WHERE id IN (" + ','.join('?' for _ in ids) + ")", ids)} if ids else {}
            cards = [json.loads(payloads[identifier]) for identifier in ids]
            if set_code:
                for card in cards:
                    printing = connection.execute("SELECT * FROM card_sets WHERE card_id=? AND set_code=? ORDER BY collector_number LIMIT 1", (card["id"], set_code.casefold())).fetchone()
                    self._printing(card, printing)
        result={"cards": cards, "total": total, "limit": limit, "offset": offset}
        if format_name:
            selected=format_profile(format_name);result.update(formatId=selected['id'],snapshotLegalityChecked=selected['snapshotKey']is not None,snapshotFilterAvailable=selected['snapshotKey']is not None,nativeValidationRequired=True)
        return result

    @staticmethod
    def _printing(card, printing):
        if not printing:
            return card
        if printing["payload"]:
            requested = card.get("requested_face")
            card.update(json.loads(printing["payload"]))
            if requested is not None: card["requested_face"] = requested
        card.update(set=printing["set_code"], set_name=printing["set_name"], printing_id=printing["printing_id"], collector_number=printing["collector_number"])
        if printing["image_url"]:
            card["image_uris"] = json.loads(printing["image_url"])
        for face, images in enumerate(json.loads(printing["face_images"])):
            if images and face < len(card.get("card_faces", [])):
                card["card_faces"][face]["image_uris"] = images
        return card

    @cached_query
    def sets(self, format_name=""):
        condition=format_clause(format_name,'cards.')if format_name else None
        where = ' WHERE '+condition if condition else ''
        with self.connect() as connection:
            rows = connection.execute("SELECT s.set_code AS code, s.set_name AS name, count(DISTINCT s.card_id) AS count FROM card_sets s JOIN cards ON cards.id=s.card_id" + where + " GROUP BY s.set_code ORDER BY s.set_name COLLATE NOCASE")
            return [dict(row) for row in rows]

    def deck_colors(self, deck):
        names = sorted({entry['name'] for zone in ('main', 'commander') for entry in deck.get(zone, [])})
        return self._deck_colors(names)

    @cached_query
    def _deck_colors(self, names):
        if not names: return []
        with self.connect() as connection:
            rows = connection.execute('SELECT payload FROM cards WHERE name COLLATE NOCASE IN (' + ','.join('?' for _ in names) + ')', names)
            colors = {color for row in rows for color in (json.loads(row[0]).get('color_identity') or [])}
        return [color for color in 'WUBRG' if color in colors]

    @cached_query
    def get(self, identifier=None, name=None, printing_id=None):
        with self.connect() as connection:
            row = connection.execute("SELECT payload FROM cards WHERE " + ("name = ? COLLATE NOCASE" if name is not None else "id = ?"),
                                     (name if name is not None else identifier,)).fetchone()
            face = None
            if not row and name is not None:
                alias = connection.execute("SELECT card_id,face FROM aliases WHERE name=? COLLATE NOCASE", (name,)).fetchone()
                if alias:
                    row = connection.execute("SELECT payload FROM cards WHERE id=?", (alias["card_id"],)).fetchone()
                    face = alias["face"]
            if not row:
                # Token printings and names shared by different oracle objects
                # still have exact per-printing records even when not selected
                # as the builder's representative name row.
                printing = connection.execute('SELECT * FROM card_sets WHERE printing_id=? OR (card_id=? AND printing_id=?) LIMIT 1', (identifier, identifier, printing_id)).fetchone() if identifier else None
                if not printing: return None
                card = json.loads(printing['payload'])
                return self._printing(card, printing)
            card = json.loads(row[0])
            if face is not None:
                card["requested_face"] = face
            if printing_id:
                printing = connection.execute("SELECT * FROM card_sets WHERE card_id=? AND printing_id=?", (card["id"], printing_id)).fetchone()
                if not printing:
                    raise ValueError("Printing does not belong to this card")
                self._printing(card, printing)
            return card

    @cached_query
    def gallery(self, *args, **kwargs):
        return super().gallery(*args, **kwargs)

    @cached_query
    def gallery_item(self, *args, **kwargs):
        return super().gallery_item(*args, **kwargs)
