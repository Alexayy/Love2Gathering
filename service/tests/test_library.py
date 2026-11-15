"""Isolated synthetic metadata/recordings: cache identity, import, token art, history."""
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from storage import Storage
from server import make_handler
from deck_import import parse, preview, export_url, download, SafeRedirect


class LibraryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.root = Path(self.temp.name)
        card = {'object': 'card', 'id': 'bolt-a', 'oracle_id': 'bolt', 'name': 'Lightning Bolt', 'lang': 'en',
                'type_line': 'Instant', 'oracle_text': 'Lightning Bolt deals 3 damage to any target.', 'mana_cost': '{R}',
                'colors': ['R'], 'color_identity': ['R'], 'set': 'lea', 'set_name': 'Alpha', 'collector_number': '161',
                'artist': 'Example A', 'legalities': {'modern': 'legal', 'commander': 'legal'},
                'image_uris': {kind: 'https://cards.scryfall.io/' + kind + '/bolt-a.jpg' for kind in ('normal', 'large', 'art_crop')}}
        second = dict(card, id='bolt-b', set='m10', artist='Example B')
        forest = dict(card, id='forest', oracle_id='forest', name='Forest', type_line='Basic Land — Forest', colors=[], color_identity=['G'])
        maker = dict(card, id='maker', oracle_id='maker', name='Goblin Maker', type_line='Creature — Goblin', power='1', toughness='1',
                     all_parts=[{'id': 'goblin-a', 'component': 'token', 'name': 'Goblin', 'type_line': 'Token Creature — Goblin'}])
        other_maker = dict(maker, id='other-maker', oracle_id='other-maker', name='Other Goblin Maker',
                           all_parts=[{'id': 'goblin-c', 'component': 'token', 'name': 'Goblin', 'type_line': 'Token Creature — Goblin'}])
        token = dict(card, id='goblin-a', oracle_id='goblin', name='Goblin', type_line='Token Creature — Goblin', layout='token',
                     power='1', toughness='1', legalities={}, image_uris={kind: 'https://cards.scryfall.io/' + kind + '/goblin.jpg' for kind in ('normal', 'large', 'art_crop')})
        # Identical token faces can have different Oracle IDs when paired on
        # different double-faced token printings. Artwork families still match.
        token_b = dict(token, id='goblin-b', oracle_id='goblin-alternate-pair', set='tbro')
        other = dict(token, id='goblin-c', oracle_id='goblin-other', colors=['G'], power='2', toughness='2')
        self.source = self.root / 'cards.jsonl';self.source.write_text('\n'.join(json.dumps(item) for item in (card, second, forest, maker, other_maker, token, token_b, other)))
        self.catalog = Catalog(self.source, self.root / 'catalog.sqlite');self.catalog.ensure();self.assertEqual(self.catalog.status()['state'], 'ready')
        self.storage = Storage(self.root / 'data', self.root / 'bundled')
        self.storage.save_deck({'id': 'my-deck', 'name': 'Token deck', 'format': 'Modern', 'coverCard': 'Goblin Maker', 'main': [{'name': 'Goblin Maker', 'count': 4}]})
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.catalog, self.storage))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True);self.thread.start()
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.temp.cleanup()

    def request(self, path, body=None, method=None, binary=False):
        request = Request(self.url + path, data=None if body is None else json.dumps(body).encode(), method=method,
                          headers={'Content-Type': 'application/json'})
        with urlopen(request, timeout=5) as response: return response.read() if binary else json.load(response)

    def test_sqlite_oracle_alias_is_offline_face_and_kind_safe_and_returns_real_printing(self):
        scan, crop, back = b'\xff\xd8scan', b'\xff\xd8crop', b'\xff\xd8back'
        self.storage.save_art('bolt-b-0-large.jpg', scan, {'printingId': 'bolt-b', 'oracleId': 'bolt', 'face': 0, 'kind': 'large'})
        self.storage.save_art('bolt-b-0-art_crop.jpg', crop, {'printingId': 'bolt-b', 'oracleId': 'bolt', 'face': 0, 'kind': 'art_crop'})
        self.storage.save_art('bolt-b-1-large.jpg', back, {'printingId': 'bolt-b', 'oracleId': 'bolt', 'face': 1, 'kind': 'large'})
        with patch.object(self.server.RequestHandlerClass, 'download_art', side_effect=AssertionError('Offline cache must not touch network')) as network:
            self.assertEqual(self.request('/art/bolt?printing=bolt-a', binary=True), scan)
            self.assertEqual(self.request('/art/bolt?printing=bolt-a&kind=art_crop', binary=True), crop)
            resolved = self.request('/cards/by-name?name=Lightning%20Bolt')
            self.assertEqual((resolved['printing_id'], resolved['artist']), ('bolt-b', 'Example B'))
            network.assert_not_called()
        self.assertEqual(self.storage.local_art('uncached', 'bolt', 1)[0], back)
        self.assertIsNone(self.storage.local_art('uncached', 'bolt', 2))
        with self.storage.connection() as c: self.assertEqual(c.execute("SELECT count(*) FROM art_cache WHERE cache_key='bolt-a-0-normal.jpg'").fetchone()[0], 0)

    def test_gallery_and_explicit_exact_image_never_substitute_other_printing(self):
        alias, actual = b'\xff\xd8other-printing', b'\xff\xd8exact-printing'
        self.storage.save_art('bolt-b-0-normal.jpg', alias, {'printingId': 'bolt-b', 'oracleId': 'bolt', 'face': 0, 'kind': 'normal'})
        self.storage.save_art('bolt-0.jpg', alias, {'legacySource': 'other-printing'})
        with patch.object(self.server.RequestHandlerClass, 'download_art', return_value=actual) as network:
            self.assertEqual(self.request('/gallery/art/bolt-a?kind=normal&network=1', binary=True), actual)
            self.assertEqual(network.call_args.args[0], 'https://cards.scryfall.io/normal/bolt-a.jpg')
        self.assertEqual(self.request('/cards/by-name?name=Lightning%20Bolt&printing=bolt-a')['printing_id'], 'bolt-a')

    def test_cache_miss_is_offline_by_default_with_explicit_opt_in(self):
        with patch.object(self.server.RequestHandlerClass, 'download_art', return_value=b'\xff\xd8explicit') as network:
            with self.assertRaises(HTTPError) as error: self.request('/art/bolt?printing=bolt-a', binary=True)
            self.assertEqual(error.exception.code, 404);self.assertTrue(json.load(error.exception)['cachedMiss']);network.assert_not_called()
            self.assertEqual(self.request('/art/bolt?printing=bolt-a&network=1', binary=True), b'\xff\xd8explicit')
            self.assertEqual(network.call_count, 1)

    def test_mirrors_import_without_overwriting_sqlite_or_relabeling_large(self):
        mirror = self.storage.root / 'image-library/full-cards';mirror.mkdir(parents=True)
        (mirror / 'bolt-a-0-large.jpg').write_bytes(b'\xff\xd8mirror')
        self.assertEqual(self.storage.local_art('bolt-a', 'bolt')[0], b'\xff\xd8mirror')
        with self.storage.connection() as c:
            row = c.execute("SELECT metadata FROM art_cache WHERE cache_key='bolt-a-0-large.jpg'").fetchone()
            self.assertEqual(json.loads(row[0])['kind'], 'large')
        self.storage.save_art('bolt-a-0-normal.jpg', b'\xff\xd8new-sql')
        self.assertEqual(self.storage.local_art('bolt-a', 'bolt')[0], b'\xff\xd8new-sql')

    def test_token_relationship_variants_preferences_persist_without_changing_deck(self):
        original = self.storage.get_deck('my-deck')
        tokens = self.request('/tokens?deckId=my-deck')
        self.assertEqual({i['tokenImageId'] for i in tokens['items']}, {'goblin-a-0', 'goblin-b-0'})
        prefs = {'mode': 'randomSelected', 'selected': ['goblin-b-0']}
        self.assertEqual(self.request('/decks/my-deck/token-art', prefs, 'PUT'), prefs)
        self.assertEqual(Storage(self.storage.root, self.root / 'bundled').token_preferences('my-deck'), prefs)
        self.assertEqual(self.storage.get_deck('my-deck'), original)
        resolved = self.request('/tokens/resolve', {'deckId': 'my-deck', 'token': {'name': 'Goblin Token', 'power': '1', 'toughness': '1', 'colors': ['R']}, 'seed': 'native-instance'})['card']
        self.assertEqual(resolved['tokenImageId'], 'goblin-b-0')
        # Exact token printing stays loadable despite another oracle sharing the name.
        self.assertEqual(self.catalog.get(identifier=resolved['id'], printing_id=resolved['printing_id'])['printing_id'], 'goblin-b')

    def test_token_resolution_uses_original_descriptor_and_never_guesses_unknown_image(self):
        descriptor = {'name': 'Goblin', 'power': '8', 'toughness': '8', 'colors': ['G'], 'printing': {'power': '1', 'toughness': '1', 'colors': ['R']}}
        resolved = self.request('/tokens/resolve', {'token': descriptor, 'seed': 'x'})['card']
        self.assertEqual((resolved['power'], resolved['colors']), ('1', ['R']))
        self.assertIsNone(self.request('/tokens/resolve', {'token': {'name': 'Invented Token'}})['card'])
        for prefs in ({'mode': 'guess'}, {'mode': 'randomSelected', 'selected': []}, {'mode': 'default', 'selected': ['bolt-a-0']}):
            with self.assertRaises(HTTPError): self.request('/decks/my-deck/token-art', prefs, 'PUT')

    def test_token_groups_show_only_related_families_and_saved_active_manual_art(self):
        groups = self.request('/tokens?deckId=my-deck&groups=1')
        self.assertTrue(groups['grouped']);self.assertEqual(groups['total'], 1)
        group = groups['items'][0];key = group['tokenIdentity']
        self.assertEqual((group['name'], group['variantCount'], group['activeCard']['tokenImageId']), ('Goblin', 2, 'goblin-a-0'))
        prefs = {'mode': 'default', 'selected': [], 'overrides': {key: {'mode': 'selected', 'selected': ['goblin-b-0']}}}
        self.assertEqual(self.request('/decks/my-deck/token-art', prefs, 'PUT'), prefs)
        current = self.request('/tokens?deckId=my-deck&groups=1')['items'][0]
        self.assertEqual((current['mode'], current['activeCount'], current['activeCard']['tokenImageId']), ('selected', 1, 'goblin-b-0'))
        variants = self.request('/tokens?deckId=my-deck&identity=' + key + '&limit=1&offset=1')
        self.assertEqual((variants['total'], len(variants['items']), variants['items'][0]['tokenImageId']), (2, 1, 'goblin-b-0'))
        result = self.request('/tokens/resolve', {'deckId': 'my-deck', 'token': {'name': 'Goblin', 'power': '1', 'toughness': '1', 'colors': ['R']}, 'seed': 'another-instance'})['card']
        self.assertEqual(result['tokenImageId'], 'goblin-b-0');self.assertTrue(result['printingExact'])
        self.assertEqual(Storage(self.storage.root, self.root / 'bundled').token_preferences('my-deck'), prefs)

    def test_token_family_random_all_and_selected_do_not_cross_native_identity(self):
        key = self.request('/tokens?deckId=my-deck&groups=1')['items'][0]['tokenIdentity']
        for mode,selected in [('randomSelected',['goblin-b-0']),('randomAll',[])]:
            prefs={'mode':'default','selected':[],'overrides':{key:{'mode':mode,'selected':selected}}}
            self.request('/decks/my-deck/token-art',prefs,'PUT')
            found=set()
            for n in range(12):
                card=self.request('/tokens/resolve',{'deckId':'my-deck','token':{'name':'Goblin','power':'1','toughness':'1','colors':['R']},'seed':str(n)})['card']
                found.add(card['tokenImageId']);self.assertEqual(card['tokenIdentity'],key)
            self.assertEqual(found,{'goblin-b-0'}if mode=='randomSelected'else{'goblin-a-0','goblin-b-0'})
        for mode,selected in [('selected',[]),('selected',['goblin-a-0','goblin-b-0']),('randomSelected',[]),('selected',['goblin-c-0'])]:
            with self.assertRaises(HTTPError):self.request('/decks/my-deck/token-art',{'mode':'default','selected':[],'overrides':{key:{'mode':mode,'selected':selected}}},'PUT')
        other=self.catalog.token_item('goblin-c-0')['tokenIdentity']
        with self.assertRaises(HTTPError):self.request('/decks/my-deck/token-art',{'mode':'default','selected':[],'overrides':{other:{'mode':'randomAll','selected':[]}}},'PUT')

    def test_token_save_prunes_unchanged_removed_family_without_admitting_unrelated_edits(self):
        deck = self.storage.get_deck('my-deck')
        self.storage.save_deck(dict(deck, main=[{'name': 'Goblin Maker', 'count': 4}, {'name': 'Other Goblin Maker', 'count': 4}]))
        removed = self.catalog.token_item('goblin-a-0')['tokenIdentity']
        remaining = self.catalog.token_item('goblin-c-0')['tokenIdentity']
        prefs = {'mode': 'default', 'selected': [], 'overrides': {
            removed: {'mode': 'selected', 'selected': ['goblin-b-0']},
            remaining: {'mode': 'selected', 'selected': ['goblin-c-0']}}}
        self.request('/decks/my-deck/token-art', prefs, 'PUT')
        self.storage.save_deck(dict(deck, main=[{'name': 'Other Goblin Maker', 'count': 4}]))
        reopened = self.request('/tokens?deckId=my-deck&groups=1')
        self.assertEqual([item['tokenIdentity'] for item in reopened['items']], [remaining])
        # Preferences may originate before the deck edit. A changed unrelated
        # override is rejected, even when that family used to be in this deck.
        edited = json.loads(json.dumps(reopened['preferences']))
        edited['overrides'][removed] = {'mode': 'randomAll', 'selected': []}
        with self.assertRaises(HTTPError): self.request('/decks/my-deck/token-art', edited, 'PUT')
        edited['overrides'][removed] = prefs['overrides'][removed]
        edited['overrides'][remaining] = {'mode': 'randomAll', 'selected': []}
        expected = {'mode': 'default', 'selected': [], 'overrides': {remaining: edited['overrides'][remaining]}}
        self.assertEqual(self.request('/decks/my-deck/token-art', edited, 'PUT'), expected)
        self.assertEqual(Storage(self.storage.root, self.root / 'bundled').token_preferences('my-deck'), expected)
        self.assertEqual(self.request('/tokens?deckId=my-deck&groups=1')['preferences'], expected)
        # Once pruned, even the former saved value is a new unrelated override.
        with self.assertRaises(HTTPError): self.request('/decks/my-deck/token-art', prefs, 'PUT')

    def test_import_preview_preserves_zones_printings_extras_and_never_saves(self):
        text = 'About\nName Imported example\nCommander\n1 Goblin Maker\nDeck\n4x Lightning Bolt (M10) 161 *F* [Burn]\nSB: 1 Forest\n1 Goblin (tbro) 1 [Tokens & Extras{noDeck}]'
        before = len(self.storage.list_decks())
        result = self.request('/imports/preview', {'text': text, 'format': 'Modern'})
        self.assertFalse(result['saved']);self.assertEqual(len(self.storage.list_decks()), before)
        self.assertEqual(result['deck']['name'], 'Imported example')
        self.assertEqual(result['deck']['commander'], [{'name': 'Goblin Maker', 'count': 1}])
        self.assertEqual(result['deck']['sideboard'], [{'name': 'Forest', 'count': 1}])
        self.assertEqual(result['printingSelections'][0]['printingId'], 'bolt-b')
        self.assertEqual(len(result['excluded']), 1)
        self.assertFalse(result['validation']['saveAllowed'], 'Illegal commander zone in Modern was silently removed')
        good = self.request('/imports/preview', {'text': '4 Lightning Bolt (M10) 161\n56 Forest', 'format': 'Modern'})
        self.assertTrue(good['validation']['playable']);self.assertEqual(good['deck']['printingSelections'][0]['set'], 'm10')
        saved = self.request('/decks', good['deck'])
        self.assertEqual(saved['printingSelections'], good['deck']['printingSelections'])

    def test_import_common_json_xml_csv_and_unknown_cards_remain_named_errors(self):
        json_deck = {'name': 'Moxfield export', 'mainboard': {'uuid': {'quantity': 4, 'card': {'name': 'Lightning Bolt', 'set': 'm10', 'cn': '161'}}}, 'sideboard': {}}
        self.assertEqual(parse(json.dumps(json_deck))[0][0]['count'], 4)
        archidekt = {'cards': [{'quantity': 1, 'card': {'oracleCard': {'name': 'Goblin Maker'}, 'edition': {'editioncode': 'lea'}}, 'categories': ['Commander']}]}
        self.assertEqual(parse(json.dumps(archidekt))[0][0]['zone'], 'commander')
        self.assertEqual(parse('<cockatrice_deck><deckname>COD</deckname><zone name="main"><card number="4" name="Lightning Bolt"/></zone><zone name="side"><card number="1" name="Forest"/></zone></cockatrice_deck>')[0][1]['zone'], 'sideboard')
        self.assertEqual(parse('Quantity,Name,Set,Collector Number\n4,Lightning Bolt,m10,161')[0][0]['collectorNumber'], '161')
        result = self.request('/imports/preview', {'text': '1 Unknown Card\n59 Forest', 'format': 'Modern'})
        self.assertIn('Unknown Card', result['validation']['errors'][0]['message'])
        with self.assertRaises(ValueError): parse('251 Forest')
        with self.assertRaises(ValueError): parse('<!DOCTYPE a><cockatrice_deck/>')

    def test_url_whitelist_private_targets_and_site_access_failure_have_no_bypass(self):
        self.assertEqual(export_url('https://archidekt.com/decks/1234/example')[0], 'https://archidekt.com/api/decks/1234/')
        self.assertEqual(export_url('https://moxfield.com/decks/abcdef')[1], 'Moxfield')
        self.assertIn('/arena_download/1234', export_url('https://www.mtggoldfish.com/deck/1234')[0])
        self.assertIn('/arena_download/1234', export_url('https://www.mtggoldfish.com/deck/1234#paper')[0])
        for url in ('http://archidekt.com/decks/1', 'https://127.0.0.1/deck/1', 'https://moxfield.com.evil.test/decks/abcdef', 'https://user:pw@moxfield.com/decks/abcdef', 'https://moxfield.com/decks/abcdef?cookie=secret', 'file:///etc/passwd'):
            with self.assertRaises(ValueError): export_url(url)
        with patch('deck_import.socket.getaddrinfo', return_value=[(2, 1, 6, '', ('127.0.0.1', 443))]):
            with self.assertRaisesRegex(ValueError, 'non-public'): download('https://archidekt.com/decks/1234')
        with self.assertRaises(ValueError): SafeRedirect().redirect_request(Request('https://archidekt.com/api/decks/1234/'), None, 302, '', {}, 'https://evil.test/steal')

    def test_history_uses_terminal_native_frames_and_decks_not_supplied_winner_claims(self):
        players = [{'id': 'me', 'name': 'Alice', 'deck': {'id': 'my-deck', 'name': 'Actual deck', 'format': 'Modern'}}, {'id': 'other', 'name': 'Bot', 'deck': {'name': 'Bot deck'}}]
        for identifier, status, won in (('native-win', 'completed', True), ('native-loss', 'completed', False), ('interrupted', 'aborted', True)):
            self.storage.create_replay({'id': identifier, 'format': 'Modern', 'metadata': {'players': players, 'perspectivePlayerId': 'me'}})
            self.storage.append_replay_events(identifier, [{'sequence': 0, 'type': 'frame', 'data': {'running': False, 'players': [{'id': 'me', 'name': 'Alice', 'human': True, 'won': won, 'lost': not won}, {'id': 'other', 'name': 'Bot', 'won': not won, 'lost': won}]}}])
            self.storage.finish_replay(identifier, {'status': status, 'winnerSeatId': 'forged-ignored'})
        history = self.request('/history');by_id = {item['id']: item for item in history['matches']}
        self.assertEqual(by_id['native-win']['outcome'], 'win');self.assertEqual(by_id['native-loss']['outcome'], 'loss')
        self.assertEqual(by_id['interrupted']['outcome'], 'aborted');self.assertEqual(by_id['native-win']['deck']['name'], 'Actual deck')
        self.assertEqual(self.request('/history?limit=1&offset=1')['total'], 3)
        with self.assertRaises(HTTPError): self.request('/history', {'winnerSeatId': 'me'})


if __name__ == '__main__': unittest.main()
