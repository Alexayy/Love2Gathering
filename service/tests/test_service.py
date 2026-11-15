import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from server import make_handler
from storage import Storage


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "cards.jsonl"
        card = {"object": "card", "id": "printing-one", "oracle_id": "oracle-one", "name": "Lightning Bolt",
                "lang": "en", "type_line": "Instant", "oracle_text": "Lightning Bolt deals 3 damage to any target.",
                "mana_cost": "{R}", "cmc": 1, "colors": ["R"], "color_identity": ["R"],
                "set": "lea", "set_name": "Limited Edition Alpha", "collector_number": "161",
                "image_uris": {"normal": "https://cards.scryfall.io/normal/front/test.jpg"},
                "legalities": {"modern": "legal", "standard": "not_legal", "pioneer": "not_legal", "commander": "legal"}}
        copies = [card, dict(card, id="printing-two", set="m10", set_name="Magic 2010"), dict(card, name="Éclair", lang="fr"),
                  dict(card, name="Forest", oracle_id="oracle-two", id="forest", type_line="Basic Land — Forest",
                       oracle_text="{T}: Add {G}.", colors=[], color_identity=["G"], legalities={"modern": "legal", "standard": "legal"})]
        self.source.write_text("\n".join(json.dumps(item) for item in copies))
        self.catalog = Catalog(self.source, self.root / "catalog.sqlite")
        self.catalog.ensure()
        self.assertEqual(self.catalog.status()["state"], "ready")
        self.storage = Storage(self.root / "data", self.root / "bundled")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.catalog, self.storage))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def request(self, path, method="GET", body=None):
        data = json.dumps(body).encode() if body is not None else None
        request = Request(self.base + path, data=data, method=method, headers={"Content-Type": "application/json"})
        with urlopen(request) as response:
            return response.status, json.load(response)

    def deck(self):
        return {"id": "test-deck", "name": "Test", "format": "modern", "main": [{"name": "Lightning Bolt", "count": 4}]}

    def test_english_printing_dedup_search_and_filters(self):
        self.assertEqual(self.catalog.status()["cards"], 2)
        self.assertEqual(self.request("/cards?q=damage&format=modern")[1]["total"], 1)
        self.assertEqual(self.request("/cards?q=damage&format=standard")[1]["total"], 0)
        self.assertEqual(self.request("/cards?color=G&type=land")[1]["cards"][0]["name"], "Forest")
        self.assertEqual(self.request("/cards/by-name?name=LIGHTNING%20BOLT")[1]["id"], "oracle-one")
        self.assertTrue(self.request("/health")[1]["ready"])
        sets = self.request("/sets?format=modern")[1]["sets"]
        self.assertEqual({entry["code"] for entry in sets}, {"lea", "m10"})
        printing = self.request("/cards?set=m10&sort=set")[1]["cards"][0]
        self.assertEqual(printing["set"], "m10")
        self.assertEqual(printing["printing_id"], "printing-two")

    def test_round_trip_preserves_bundled_and_user_decks(self):
        self.storage.bundled.mkdir()
        (self.storage.bundled / "example.json").write_text(json.dumps(dict(self.deck(), id="bundled")))
        self.assertEqual(self.request("/decks")[1]["decks"][0]["origin"], "bundled")
        self.assertEqual(self.request("/decks", "POST", self.deck())[0], 201)
        update = dict(self.deck(), name="Changed")
        self.assertEqual(self.request("/decks/test-deck", "PUT", update)[1]["name"], "Changed")
        self.assertEqual(self.request("/decks/test-deck")[1]["name"], "Changed")
        self.request("/decks/bundled", "DELETE")
        self.assertTrue((self.storage.bundled / "example.json").exists())
        self.assertEqual(len(self.request("/decks")[1]["decks"]), 1)
        self.request("/decks/test-deck", "DELETE")
        self.assertEqual(self.request("/decks")[1]["decks"], [])

    def test_bad_input_does_not_damage_saved_deck(self):
        self.request("/decks", "POST", self.deck())
        for path, value in (("/decks/../escape", self.deck()), ("/decks/test-deck", dict(self.deck(), main=[{"name": "Bolt", "count": -1}]))):
            with self.assertRaises(HTTPError) as error:
                self.request(path, "PUT", value)
            self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.request("/decks/test-deck")[1]["main"][0]["count"], 4)

    def test_settings_persist_and_failed_rebuild_keeps_valid_database(self):
        self.request("/settings", "PUT", {"manualTriggers": True})
        again = Storage(self.root / "data", self.root / "bundled")
        self.assertTrue(again.settings()["manualTriggers"])
        self.source.write_text('{"broken":\n')
        self.catalog.ensure()
        self.assertEqual(self.catalog.status()["state"], "error")
        self.assertEqual(self.catalog.get(name="Lightning Bolt")["id"], "oracle-one")

    def test_illegal_format_and_copy_changes_never_overwrite_saved_deck(self):
        result = self.request("/decks", "POST", self.deck())[1]
        self.assertTrue(result["draft"])
        self.assertTrue(result["validation"]["saveAllowed"])
        for changed, expected in ((dict(self.deck(), format="Standard"), "format_legality"),
                                  (dict(self.deck(), sideboard=[{"name": "Lightning Bolt", "count": 1}]), "copy_limit")):
            with self.assertRaises(HTTPError) as error:
                self.request("/decks/test-deck", "PUT", changed)
            self.assertEqual(error.exception.code, 422)
            response = json.loads(error.exception.read())
            self.assertEqual(response["validation"]["errors"][0]["code"], expected)
        saved = self.request("/decks/test-deck")[1]
        self.assertEqual(saved["format"], "Modern")
        self.assertEqual(saved["sideboard"], [])

    def test_typed_settings_reject_invalid_values_without_writes(self):
        for value in ({"musicVolume": 2}, {"vsync": "false"}, {"windowMode": "Invalid"}, {"uiScale": 0.2}, {"msaa": True}, {"resolution": "100x100"}):
            with self.assertRaises(HTTPError) as error:
                self.request("/settings", "PUT", value)
            self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.request("/settings")[1]["musicVolume"], 0.25)

    def test_replay_api_atomic_batches_pagination_and_failure_reopen(self):
        status, replay = self.request('/replays','POST',{'id':'http-replay','title':'HTTP recording','format':'Modern'})
        self.assertEqual(status,201)
        events=[{'sequence':0,'type':'frame','timestamp':10,'data':{'turn':1}},
                {'sequence':1,'type':'action','timestamp':11,'data':{'type':'boolean','value':True}},
                {'sequence':2,'type':'frame','timestamp':12,'data':{'turn':2}}]
        self.assertEqual(self.request('/replays/http-replay/events','POST',{'events':events})[1]['inserted'],3)
        self.assertEqual(self.request('/replays/http-replay/events','POST',{'events':events})[1]['inserted'],0)
        page=self.request('/replays/http-replay/frames?offset=1&limit=250')[1]
        self.assertEqual((page['total'],page['limit'],page['frames'][0]['sequence']),(2,250,2))
        with self.assertRaises(HTTPError) as error:
            self.request('/replays/http-replay/events','POST',{'events':[{'sequence':0,'type':'frame','data':{'turn':99}}]})
        self.assertEqual(error.exception.code,409)
        self.request('/replays/http-replay/finish','POST',{'status':'failed','error':'Interrupted'})
        meta=self.request('/replays/http-replay')[1]
        self.assertEqual((meta['status'],meta['eventCount'],meta['actionCount'],meta['lastSequence']),('failed',3,1,2))
        self.assertEqual(self.request('/replays')[1]['total'],1)
        with self.assertRaises(HTTPError) as error:self.request('/replays/missing')
        self.assertEqual(error.exception.code,404)
        self.assertTrue(self.request('/replays/http-replay','DELETE')[1]['deleted'])

    def test_sqlite_layout_and_artwork_are_served_without_file_writes(self):
        layout={'hand':{'x':0.2,'y':0.8,'w':0.6,'h':0.2},'replayPrefs':{'speed':1.5}}
        self.assertEqual(self.request('/ui-layout','PUT',layout)[1],layout)
        self.assertEqual(self.request('/ui-layout')[1],layout)
        data=b'\xff\xd8'+b'test-jpeg'*30
        self.storage.save_art('printing-one-0-normal.jpg',data,{'oracleId':'oracle-one'})
        with urlopen(self.base+'/art/oracle-one') as response:
            self.assertEqual(response.headers['Content-Type'],'image/jpeg')
            self.assertEqual(response.read(),data)
        health=self.request('/health')[1]
        self.assertEqual(health['apiVersion'],14)
        self.assertEqual(health['catalogSource'],str(self.source.resolve()))
        self.assertEqual(health['userStore']['database'],'app.sqlite')
        self.assertEqual(health['storage']['dataDirectory'],str(self.storage.root.resolve()))
        self.assertFalse((self.storage.root/'art').exists())


if __name__ == "__main__":
    unittest.main()
