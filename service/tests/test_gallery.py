import json
import gzip
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from server import make_handler
from artists import artist_links


class GalleryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory();self.root = Path(self.temporary.name)
        self.source = self.root / "cards.jsonl"
        base = {"object": "card", "id": "printing-a", "oracle_id": "oracle-one", "name": "Example Card",
                "lang": "en", "type_line": "Creature", "oracle_text": "Rules", "mana_cost": "{R}",
                "colors": ["R"], "color_identity": ["R"], "legalities": {"commander": "legal"},
                "set": "eld", "set_name": "Throne of Eldraine", "collector_number": "1", "released_at": "2019-10-04",
                "artist": "Ryan Pancoast", "artist_ids": ["ryan-id"], "border_color": "black",
                "image_uris": {kind: "https://cards.scryfall.io/" + kind + "/a.jpg" for kind in ("normal", "large", "art_crop")}}
        extended = dict(base, id="printing-b", set="cmm", set_name="Commander Masters", released_at="2023-08-04",
                        artist="Karl Kopinski", frame_effects=["extendedart"])
        borderless = dict(base, id="printing-c", artist="Unknown Illustrator", border_color="borderless")
        french = dict(base, id="printing-fr", lang="fr", name="Carte Exemple", artist="Kai Carpenter")
        transform = dict(base, id="printing-dfc", oracle_id="oracle-two", name="Day // Night", layout="transform", image_uris={},
                         card_faces=[{"name": "Day", "artist": "Ryan Pancoast", "artist_id": "ryan-id", "image_uris": base["image_uris"]},
                                     {"name": "Night", "artist": "Kai Carpenter", "artist_id": "kai-id", "image_uris": {kind: url.replace("a.jpg", "back.jpg") for kind, url in base["image_uris"].items()}}])
        self.source.write_text("\n".join(json.dumps(card) for card in (base, extended, borderless, french, transform)))
        self.catalog = Catalog(self.source, self.root / "catalog.sqlite");self.catalog.ensure()
        self.assertEqual(self.catalog.status()["state"], "ready")
        self.storage = Storage(self.root / "data", self.root / "bundled")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.catalog, self.storage))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True);self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.temporary.cleanup()

    def read(self, path):
        with urlopen(self.base + path, timeout=5) as response:return json.load(response)

    def test_every_printing_and_image_face_has_its_own_credit(self):
        items = self.read("/gallery?lang=all")["items"]
        self.assertEqual(len(items), 6)
        credits = {item["id"]: item for item in items}
        self.assertEqual(credits["printing-a-0"]["artist"], "Ryan Pancoast")
        self.assertEqual(credits["printing-b-0"]["artist"], "Karl Kopinski")
        self.assertEqual(credits["printing-b-0"]["year"], "2023")
        self.assertEqual(credits["printing-dfc-1"]["name"], "Night")
        self.assertEqual(credits["printing-dfc-1"]["artist_ids"], ["kai-id"])
        self.assertIn("back.jpg", credits["printing-dfc-1"]["image_uris"]["art_crop"])
        self.assertEqual(self.catalog.search()["total"], 2, "Gallery indexing changed English oracle-card deduplication")

    def test_variant_artist_set_language_and_page_filters(self):
        self.assertEqual(self.read("/gallery")["total"], 5)
        self.assertEqual(self.read("/gallery?variant=extended")["items"][0]["printing_id"], "printing-b")
        self.assertEqual(self.read("/gallery?variant=borderless")["items"][0]["printing_id"], "printing-c")
        self.assertEqual(self.read("/gallery?artist=Ryan&set=eld")["total"], 2)
        self.assertEqual(self.read("/gallery?q=2019&lang=fr")["items"][0]["name"], "Carte Exemple")
        page = self.read("/gallery?lang=all&limit=2&offset=2")
        self.assertEqual((page["total"], page["limit"], page["offset"], len(page["items"])), (6, 2, 2, 2))
        self.assertEqual(self.read("/gallery?q=%25")["total"], 0, "Search punctuation became a wildcard")
        with self.assertRaises(HTTPError) as error:self.read("/gallery?variant=guessed")
        self.assertEqual(error.exception.code, 400)

    def test_links_are_reviewed_and_unknown_artist_is_explicitly_empty(self):
        item = self.read("/gallery?artist=Ryan")["items"][0]
        self.assertTrue(item["artist_links"])
        self.assertTrue(all(link["source"].startswith("https://www.ryanpancoast.com/") and link["verifiedAt"] == "2026-11-13" for link in item["artist_links"]))
        self.assertEqual(self.read("/gallery?artist=Unknown")["items"][0]["artist_links"], [])
        self.assertEqual(artist_links("Invented Name"), [])
        for name in ("Karl Kopinski", "Ryan Pancoast", "Eric Deschamps", "Svetlin Velinov", "Lie Setiawan"):
            self.assertTrue(artist_links(name), "Core Commander illustrator missing a reviewed destination: " + name)

    def test_selected_printing_card_details_keep_the_correct_artist(self):
        printing = self.catalog.get(identifier="oracle-one", printing_id="printing-b")
        self.assertEqual((printing["artist"], printing["released_at"], printing["frame_effects"]), ("Karl Kopinski", "2023-08-04", ["extendedart"]))

    def test_gallery_art_reads_authoritative_blob_for_nonenglish_and_reverse_face(self):
        data = b"\xff\xd8" + b"gallery-test-jpeg" * 50
        for printing, face, kind in (("printing-fr", 0, "art_crop"), ("printing-dfc", 1, "art_crop"), ("printing-a", 0, "large")):
            self.storage.save_art(f"{printing}-{face}-{kind}.jpg", data)
            with urlopen(self.base + f"/gallery/art/{printing}?face={face}&kind={kind}") as response:
                self.assertEqual(response.headers["Content-Type"], "image/jpeg");self.assertEqual(response.read(), data)
        self.assertFalse((self.storage.root / "art").exists())
        with self.assertRaises(HTTPError) as error:self.read("/gallery/art/printing-dfc?face=2")
        self.assertEqual(error.exception.code, 404)

    def test_normal_requests_reuse_same_printing_face_large_blob_without_network_or_copying(self):
        large = b"\xff\xd8" + b"large-full-card" * 40
        reverse = b"\xff\xd8" + b"reverse-large-scan" * 40
        cropped = b"\xff\xd8" + b"art-only-crop" * 40
        metadata = {"kind": "large", "source": "https://cards.scryfall.io/large/a.jpg"}
        self.storage.save_art("printing-a-0-large.jpg", large, metadata)
        self.storage.save_art("printing-dfc-1-large.jpg", reverse, metadata)
        self.storage.save_art("printing-a-0-art_crop.jpg", cropped, {"kind": "art_crop"})
        with patch.object(self.server.RequestHandlerClass, "download_art", side_effect=AssertionError("Cached scans must work offline")) as download:
            for path, expected in (("/art/oracle-one?printing=printing-a", large),
                                   ("/gallery/art/printing-a?kind=normal", large),
                                   ("/art/oracle-two?printing=printing-dfc&face=1", reverse),
                                   ("/gallery/art/printing-dfc?face=1&kind=normal", reverse),
                                   ("/gallery/art/printing-a?kind=art_crop", cropped)):
                with urlopen(self.base + path) as response:self.assertEqual(response.read(), expected)
            download.assert_not_called()
        with self.storage.connection() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM art_cache WHERE cache_key LIKE '%-normal.jpg'").fetchone()[0], 0)
            saved = connection.execute("SELECT metadata FROM art_cache WHERE cache_key='printing-a-0-large.jpg'").fetchone()[0]
            self.assertEqual(json.loads(saved), metadata)

    def test_failed_rebuild_preserves_previous_gallery_and_user_sql_data(self):
        original = self.source.read_bytes();self.storage.save_settings({"manualTriggers": True})
        self.source.write_text("{bad json\n");self.catalog.ensure()
        self.assertEqual(self.catalog.status()["state"], "error")
        self.assertEqual(self.catalog.gallery(language="all")["total"], 6)
        self.assertTrue(self.storage.settings()["manualTriggers"])
        self.source.write_bytes(original);self.catalog.ensure()
        self.assertEqual(self.catalog.status()["state"], "ready")

    def test_explicit_compressed_metadata_source_streams_without_replacing_original(self):
        original = self.source.read_bytes();compressed = self.root / "chosen-source.jsonl.gz"
        with gzip.open(compressed, "wb") as output: output.write(original)
        catalog = Catalog(compressed, self.root / "compressed.sqlite");catalog.ensure()
        self.assertEqual(catalog.status()["state"], "ready")
        self.assertEqual(catalog.gallery(language="all")["total"], 6)
        self.assertEqual(self.source.read_bytes(), original)


if __name__ == "__main__":unittest.main()
