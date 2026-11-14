#!/usr/bin/env python3
"""Local catalog/deck API. Rules and games belong exclusively to XMage."""
from __future__ import annotations
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
from urllib.parse import parse_qs, unquote, urlsplit
from urllib.request import Request, urlopen
from urllib.error import URLError

from catalog import Catalog, SCHEMA_VERSION
from storage import Storage, ConflictError
from validation import validate
from artwork import prefer_cached_card
from deck_import import preview as import_preview

PROJECT = Path(__file__).resolve().parent.parent


def make_handler(catalog, storage):
    art_locks = {}
    art_guard = threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        server_version = "Love2Gathering/1"

        def log_message(self, *args):
            pass

        def respond(self, status, body):
            data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def read_json(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise ValueError("Invalid body size")
            if not 0 < length <= 8 * 1024 * 1024:
                raise ValueError("Body must contain JSON up to 8 MB")
            try:
                return json.loads(self.rfile.read(length))
            except (json.JSONDecodeError, UnicodeDecodeError):
                raise ValueError("Invalid JSON body")

        def run_request(self, method):
            try:
                self.route(method)
            except ConflictError as exc:
                self.respond(409, {"error": str(exc)})
            except KeyError as exc:
                self.respond(404, {"error": str(exc).strip("'")})
            except ValueError as exc:
                self.respond(400, {"error": str(exc)})
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as exc:
                self.respond(500, {"error": str(exc)})

        def do_GET(self): self.run_request("GET")
        def do_POST(self): self.run_request("POST")
        def do_PUT(self): self.run_request("PUT")
        def do_DELETE(self): self.run_request("DELETE")

        def route(self, method):
            url = urlsplit(self.path)
            path = unquote(url.path).rstrip("/") or "/"
            query = parse_qs(url.query)
            param = lambda key, default="": query.get(key, [default])[0]
            if method == "GET" and path == "/health":
                progress = catalog.status()
                storage_status = storage.health()
                self.respond(200, {"status": "ok", "ready": progress["state"] == "ready",
                                   "index": progress, "source": catalog.source.name,
                                   "catalogSource": str(catalog.source.resolve()), "version": 3,
                                   "apiVersion": 6, "schemaVersion": int(SCHEMA_VERSION),
                                   "storage": storage_status, "userStore": storage_status})
                return
            if path == "/ui-layout":
                if method == "GET": self.respond(200, storage.ui_layout())
                elif method == "PUT": self.respond(200, storage.save_ui_layout(self.read_json()))
                else: self.respond(405, {"error": "Method not allowed"})
                return
            if path == "/replays":
                if method == "GET":
                    self.respond(200, storage.list_replays(min(200, max(1, int(param("limit", "50")))), max(0, int(param("offset", "0")))))
                elif method == "POST": self.respond(201, storage.create_replay(self.read_json()))
                else: self.respond(405, {"error": "Method not allowed"})
                return
            if path == '/history' and method == 'GET':
                self.respond(200, storage.history(min(60, max(1, int(param('limit', '30')))), max(0, int(param('offset', '0')))))
                return
            if path.startswith("/replays/"):
                parts = path.split("/")
                identifier = Storage.check_id(parts[2])
                operation = parts[3] if len(parts) == 4 else None
                if len(parts) == 3 and method == "GET":
                    replay = storage.get_replay(identifier)
                    self.respond(200 if replay else 404, replay or {"error": "Replay not found"})
                elif len(parts) == 3 and method == "DELETE":
                    deleted = storage.delete_replay(identifier)
                    self.respond(200 if deleted else 404, {"deleted": deleted})
                elif operation == "events" and method == "POST":
                    body = self.read_json()
                    if not isinstance(body, dict): raise ValueError("Event batch must be an object")
                    self.respond(200, storage.append_replay_events(identifier, body.get("events")))
                elif operation in ("events", "frames") and method == "GET":
                    self.respond(200, storage.replay_events(identifier, min(500, max(1, int(param("limit", "100")))), max(0, int(param("offset", "0"))), operation == "frames"))
                elif operation == "finish" and method == "POST":
                    self.respond(200, storage.finish_replay(identifier, self.read_json()))
                else: self.respond(404, {"error": "Replay endpoint not found"})
                return
            if path == "/settings":
                if method == "GET": self.respond(200, storage.settings())
                elif method == "PUT": self.respond(200, storage.save_settings(self.read_json()))
                else: self.respond(405, {"error": "Method not allowed"})
                return
            if path == '/profile':
                if method == 'GET':self.respond(200,storage.profile())
                elif method == 'PUT':self.respond(200,storage.save_profile(self.read_json(),catalog))
                else:self.respond(405,{'error':'Method not allowed'})
                return
            if path == '/precons/stats' and method == 'GET':
                self.respond(200,storage.precon_stats());return
            if path == '/precons' and method == 'GET':
                self.respond(200,storage.precons(param('q'),param('format'),param('set'),param('type'),param('category','deck'),min(60,max(1,int(param('limit','24')))),max(0,int(param('offset','0')))));return
            if path.startswith('/precons/') and method == 'GET':
                deck=storage.get_precon(path[len('/precons/'):]);self.respond(200 if deck else 404,deck or {'error':'Preconstructed deck not found'});return
            if path == "/decks":
                if method == "GET":
                    decks = storage.list_decks(param('origin') or None)
                    if catalog.status()['state'] == 'ready':
                        for deck in decks: deck['colorIdentity'] = catalog.deck_colors(deck)
                    self.respond(200, {"decks": decks})
                elif method == "POST": self.save_deck(self.read_json(), status=201)
                else: self.respond(405, {"error": "Method not allowed"})
                return
            if path.startswith('/decks/') and path.endswith('/fork') and method == 'POST':
                if catalog.status()['state']!='ready':self.respond(503,{'error':'Card index is not ready'});return
                identifier=path[len('/decks/'):-len('/fork')];body=self.read_json()
                if not isinstance(body,dict):raise ValueError('Deck copy options must be an object')
                deck=storage.copy_deck(identifier,body.get('name'),body.get('format'))
                result=validate(deck,catalog)
                if not result['saveAllowed']:
                    self.respond(422,{'error':result['errors'][0]['message'],'deck':deck,'validation':result,'saved':False});return
                self.respond(201,{'deck':storage.save_deck(deck,validation=result),'validation':result,'saved':True});return
            if path == '/imports/preview' and method == 'POST':
                if catalog.status()['state'] != 'ready':
                    self.respond(503, {'error': 'Card index is not ready'});return
                self.respond(200, import_preview(self.read_json(), catalog, storage))
                return
            if path.startswith('/decks/') and path.endswith('/token-art'):
                identifier = path[len('/decks/'):-len('/token-art')]
                if not storage.get_deck(identifier): raise KeyError('Deck not found')
                if method == 'GET': self.respond(200, storage.token_preferences(identifier))
                elif method == 'PUT': self.respond(200, storage.save_token_preferences(identifier, self.read_json(), catalog))
                else: self.respond(405, {'error': 'Method not allowed'})
                return
            if path == "/decks/validate" and method == "POST":
                if catalog.status()["state"] != "ready":
                    self.respond(503, {"error": "Card index is not ready"})
                    return
                deck = storage.validate_deck(self.read_json())
                self.respond(200, validate(deck, catalog))
                return
            if path.startswith("/decks/"):
                identifier = path[len("/decks/"):]
                Storage.check_id(identifier)
                if method == "GET":
                    deck = storage.get_deck(identifier)
                    self.respond(200 if deck else 404, deck or {"error": "Deck not found"})
                elif method == "PUT": self.save_deck(self.read_json(), identifier=identifier)
                elif method == "DELETE":
                    deleted = storage.delete_deck(identifier)
                    self.respond(200 if deleted else 404, {"deleted": deleted})
                else: self.respond(405, {"error": "Method not allowed"})
                return
            if path.startswith(("/cards", "/art", "/sets", "/gallery/art", "/tokens")) and catalog.status()["state"] != "ready":
                self.respond(503, {"error": "Card index is not ready", "index": catalog.status()})
                return
            if method == "GET" and path == "/cards":
                limit = min(200, max(1, int(param("limit", "50"))))
                offset = max(0, int(param("offset", "0")))
                self.respond(200, catalog.search(param("q"), param("format").lower(), param("color"), param("type"), limit, offset, param("sort", "name").lower(), param("set")))
                return
            if method == "GET" and path == "/sets":
                self.respond(200, {"sets": catalog.sets(param("format").lower())})
                return
            if method == "GET" and path.startswith("/cards/"):
                card = catalog.get(name=param("name"), printing_id=param("printing") or None) if path == "/cards/by-name" else catalog.get(identifier=path[len("/cards/"):], printing_id=param("printing") or None)
                if card and not param('printing'): card = prefer_cached_card(catalog, storage, card)
                self.respond(200 if card else 404, card or {"error": "Card not found"})
                return
            if path == '/tokens' and method == 'GET':
                deck = storage.get_deck(param('deckId')) if param('deckId') else None
                if param('deckId') and not deck: raise KeyError('Deck not found')
                result = catalog.tokens(param('q'), deck, min(60, max(1, int(param('limit', '24')))), max(0, int(param('offset', '0'))))
                result['preferences'] = storage.token_preferences(param('deckId')) if deck else {'mode': 'default', 'selected': []}
                self.respond(200, result);return
            if path == '/tokens/resolve' and method == 'POST':
                body = self.read_json();deck_id = body.get('deckId');deck = storage.get_deck(deck_id) if deck_id else None
                preferences = storage.token_preferences(deck_id) if deck else {'mode': 'default', 'selected': []}
                card = catalog.resolve_token(body.get('token'), preferences, body.get('seed', ''), deck)
                self.respond(200, {'card': card, 'mode': preferences['mode']});return
            if method == "GET" and path == "/gallery":
                if catalog.status()["state"] != "ready":
                    self.respond(503, {"error": "Artwork index is not ready. Configure a local JSONL source or explicitly download Scryfall bulk metadata.", "index": catalog.status()})
                    return
                self.respond(200, catalog.gallery(param("q"), param("artist"), param("set"), param("variant", "all"), param("lang", "en"), min(60, max(1, int(param("limit", "24")))), max(0, int(param("offset", "0")))))
                return
            if method == "GET" and (path.startswith("/art/") or path.startswith("/gallery/art/")):
                gallery = path.startswith("/gallery/art/")
                identifier = path[len("/gallery/art/"):] if gallery else path[len("/art/"):]
                face = int(param("face", "0"))
                if not 0 <= face <= 9: raise ValueError("Face must be 0 to 9")
                card = catalog.gallery_item(identifier, face) if gallery else catalog.get(identifier=identifier, printing_id=param("printing") or None)
                if not card:
                    self.respond(404, {"error": "Card not found"})
                    return
                images = card["image_uris"]
                if face and not gallery:
                    faces = card.get("card_faces", [])
                    face_images = faces[face].get("image_uris", {}) if len(faces) > face else {}
                    images = face_images or (images if card.get("layout") in ("adventure", "split", "flip") else {})
                kind = param("kind", "normal")
                if kind not in ("normal", "large", "art_crop"):
                    raise ValueError("Image kind must be normal, large or art_crop")
                art_url = images.get(kind)
                cache_key = card["printing_id"] + f"-{face}-{kind}.jpg"
                legacy_keys = (card["printing_id"] + f"-{face}.jpg", (card.get("oracle_id") or card["id"]) + f"-{face}.jpg") if kind == "normal" else ()
                with art_guard:
                    lock = art_locks.setdefault(cache_key, threading.Lock())
                with lock:
                    local = storage.local_art(card['printing_id'], card.get('oracle_id') or card['id'], face, kind, aliases=not gallery and param('exact') != '1')
                    data = local[0] if local else None
                    if data is None:
                        allow_network = param('network') == '1' or (param('network') != '0' and storage.settings().get('localArtworkOnly') is False)
                        if not allow_network:
                            self.respond(404, {'error': 'Artwork is not cached locally. The background image downloader can fill this cache.', 'cachedMiss': True})
                            return
                        if not art_url or urlsplit(art_url).hostname != "cards.scryfall.io":
                            self.respond(404, {"error": "No card image"})
                            return
                        data = self.download_art(art_url)
                        storage.save_art(cache_key, data, {"oracleId": card.get("oracle_id") or card["id"], "printingId": card["printing_id"], "face": face, "kind": kind, "source": art_url})
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "public, max-age=31536000, immutable")
                if local: self.send_header('X-Love2Gathering-Art-Key', local[1])
                self.end_headers()
                self.wfile.write(data)
                return
            self.respond(404, {"error": "Endpoint not found"})

        def download_art(self, art_url):
            try:
                request = Request(art_url, headers={"User-Agent": "Love2Gathering/1.0 (local personal MTG client)", "Accept": "image/jpeg"})
                with urlopen(request, timeout=6) as response:
                    if urlsplit(response.geturl()).hostname != "cards.scryfall.io":
                        raise ValueError("Card image redirected outside Scryfall")
                    data = response.read(3 * 1024 * 1024 + 1)
                    if len(data) > 3 * 1024 * 1024 or not data.startswith(b"\xff\xd8"):
                        raise ValueError("Invalid card image response")
                return data
            except (URLError, OSError) as exc:
                raise ValueError("Card art download unavailable: " + str(exc)) from exc

        def save_deck(self, value, identifier=None, status=200):
            if catalog.status()["state"] != "ready":
                self.respond(503, {"error": "Card index is not ready"})
                return
            deck = storage.validate_deck(value, identifier)
            result = validate(deck, catalog)
            if not result["saveAllowed"]:
                self.respond(422, {"error": result["errors"][0]["message"], "validation": result})
                return
            self.respond(status, storage.save_deck(deck, identifier, result))

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=17370)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--source", type=Path, default=Path(os.environ["LOVE2GATHERING_CATALOG_SOURCE"]) if os.environ.get("LOVE2GATHERING_CATALOG_SOURCE") else next((PROJECT / "assets").glob("all-cards*.jsonl"), PROJECT / "assets" / "all-cards.jsonl"))
    parser.add_argument("--database", type=Path, default=PROJECT / "service" / "data" / "catalog.sqlite")
    parser.add_argument("--data-dir", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "love2gathering")
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    catalog = Catalog(args.source, args.database)
    if args.build_only:
        catalog.ensure()
        print(json.dumps(catalog.status()))
        return 0 if catalog.status()["state"] == "ready" else 1
    storage = Storage(args.data_dir, PROJECT / "decks")
    thread = threading.Thread(target=catalog.ensure, name="catalog-index", daemon=True)
    thread.start()
    server = ThreadingHTTPServer((args.host, args.port), make_handler(catalog, storage))
    server.daemon_threads = True
    print(f"Catalog API listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
