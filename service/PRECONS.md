# Starter, owned and historical product decks

The catalog reports API **6**. My Decks contains saved `origin:user` lists. Starter contains the twenty curated JSON lists shipped directly in `decks/`. Preconstructed is a separately indexed, immutable product archive; it does not add thousands of full lists to the lobby's `/decks` response.

## Acquired source and coverage

The packaged `decks/preconstructed/catalog.jsonl.gz` was prepared from the official [MTGJSON AllDeckFiles archive](https://mtgjson.com/downloads/all-files/), [DeckList](https://mtgjson.com/data-models/deck-list/) and SetList snapshot dated **2026-11-14**, version `5.3.0+20261114`. The official archive SHA256 was verified before preparation:

```text
ce2ccbb53ebbbe9e1ed56540e3e229c60e6f9b252e274789ddf378948555ca6f
```

All **3,154** entries in that DeckList snapshot were found and retained. The archive contains **1,183 deck products**, **611 packets** and **1,360 other collections**. Default browsing returns only deck products. Jumpstart, halfdecks and similar packets have their own category. Ordinary Secret Lair drops, redemption sets, land packs, toolkits and similar non-deck records stay out of both categories. Actual 100-card Secret Lair Commander decks remain deck products. This is complete coverage of the acquired provider index, rather than a guarantee that upstream contains every historical Wizards product. Announced future releases can be present in the source snapshot.

Products retain their expansion, original quantities, main/sideboard/commander zones, printing references, face commander when supplied, and color identity from source card metadata. Plane and scheme zones remain available in archived details; the current constructed editor and engine formats do not implement those product-specific auxiliary formats. Product types include historical Theme/Intro/Event/Challenger decks, Commander, Duel Decks, Planechase, Archenemy, starter products and others. [`manifest.json`](../decks/preconstructed/manifest.json) records all type totals, dates, source URLs and provenance.

When an input supplies an actual string `description`, normalization preserves it verbatim, including Unicode and line breaks, up to the editor's 20,000-character limit. Oversized or non-string values fail preparation instead of being silently discarded. Missing/null descriptions keep the existing generic fallback, which the interface can omit. Descriptions or strategy guides are not promised for every product; the documented MTGJSON deck schema supplies no strategy field, and no strategy text is guessed from names or unrelated fields.

The provider's deck schema defines the product zones and release metadata. Source provenance is retained for each product; it is not inferred from its name. For example, [Wizards' Foundations Commander decklists](https://magic.wizards.com/en/news/announcements/foundations-commander-decklists) identifies **Calling All Angels** as a Commander deck with **Giada, Font of Hope**, 99 main-deck cards plus the commander, including 32 Plains. The packaged record preserves those quantities. [Wizards' Commander 2017 lists](https://magic.wizards.com/en/news/feature/commander-2017-edition-decklists-2017-08-11) likewise provides Feline Ferocity and Arahbo.

MTGJSON data is distributed under its [MIT license](https://mtgjson.com/license/); the complete notice is packaged beside the generated source. Wizards owns Magic and its card/game content. No card images are bundled into the preconstructed metadata source.

## Bounded API

| Route | Result |
| --- | --- |
| `GET /decks` | Existing lobby-compatible visible user/bundled lists; preconstructed products are excluded. |
| `GET /decks?origin=user` | Only owned lists, including older user overrides of bundled IDs. |
| `GET /decks?origin=starter` | Original twenty bundled lists, with immutable `starter-<legacy-id>` aliases. |
| `GET /precons?category=deck&q=&format=&set=&type=&limit=24&offset=0` | Summaries and total; page size is capped at 60. |
| `GET /precons/stats` | Deck/packet/withheld totals, expansion/type/historical-format selectors and source manifest. |
| `GET /precons/<id>` | One complete immutable archived product. |
| `POST /decks/<id>/fork` | Make an independently validated owned copy, optionally choosing `name` and supported target `format`. |

`category` accepts `deck` (default), `packet`, `collection` or `all`. Collection/all are for explicit inspection and auditing. Selector statistics include deck and packet products; hidden collections do not inflate those selectors. Summaries contain no complete card lists. They include `expansion`, `set`, `productType`, `historicalFormat`, `faceCommander`, `colorIdentity`, `counts`, `coverCard`, `source`, and immutable/archive flags. IDs are stable `precon-` plus a digest of the upstream filename. Query filters and page bounds are applied in SQLite.

Historical format labels describe the release-era product. A historical Standard product has `format:"Archive"`, `historicalFormat:"Standard"`, `playable:false`; filtering by Standard matches that historical label. All source products are unvalidated archives, including those labelled Commander, Modern or Pioneer. A source label never certifies current snapshot or installed-engine legality.

## Editing and preservation

Saving an edited bundled, Starter-alias or preconstructed list automatically assigns a new `deck-...` user ID. The response contains the actual new ID; clients must adopt it. Existing legacy user overrides keep their current IDs. Neither the bundled source file nor its independent Starter alias is overwritten, and old hidden bundled selections remain compatible with the legacy lobby route.

Explicit forking uses `POST /decks/<id>/fork` with an object, for example `{"format":"Modern","name":"My repaired list"}`. An Archive product needs a supported target: Commander, Modern, Standard or Pioneer. The normal construction validator checks the complete editable main/sideboard/commander list and printing references. A valid result returns HTTP 201 `{deck,validation,saved:true}`. A list with construction errors returns HTTP 422 `{deck,validation,saved:false,error}` containing the **complete unsaved copy** and a new ID for repair. Illegal cards are named and retained; no invalid list is silently persisted or reduced. Valid unfinished lists follow the existing draft-save rules. XMage still performs final validation when a game starts.

The generated product table lives in `app.sqlite` alongside, but separately from, user decks. Seeding/reseeding is transactional. A changed normalized source updates only product records; failed preparation or indexing leaves the previous valid source/database entries and user decks intact. Old product records remain addressable by ID after an update, while browsing shows the current active snapshot. The original Scryfall JSONL and image caches are never opened or changed by acquisition.

## Explicit refresh

No network acquisition happens at application startup. To refresh from official MTGJSON sources:

```sh
python3 scripts/sync-precons.py
```

The command uses `.runtime/precons/` for the compressed archive, official SHA256, DeckList and SetList. Interrupted transfers resume committed bytes, reject invalid ranges/checksums, and can restart stale partial transfers. Archive members are streamed individually without extracting paths; compressed input is capped at 512 MiB, each member at 32 MiB, and expanded content at 2 GiB. The full provider index must be present with a coherent snapshot date before atomic source replacement. New metadata and the archive require roughly 160 MiB cache space for this snapshot, plus temporary normalized output. The packaged source itself is about 5.4 MB.

To prepare again without contacting any server:

```sh
python3 scripts/sync-precons.py --offline --output /tmp/l2g-precons/catalog.jsonl.gz
```

`--cache` and `--output` select other owned destinations. `LOVE2GATHERING_PRECON_SOURCE` selects a prepared local JSONL/JSONL.gz for a catalog process. The normalized source is distribution input; `app.sqlite` remains authoritative for user changes. See [LIBRARY.md](LIBRARY.md) for deck import previews, tokens, artwork cache aliases and native match history; [README.md](README.md) documents the rest of the service.

## Verification

```sh
python3 -m unittest discover -s service/tests -p test_precons.py -v
python3 -m unittest discover -s service/tests -v
```

Coverage includes actual packaged provider counts and named Wizards lists, bounded/filterable pages, historical-format honesty, immutable Starter/preconstructed sources, legacy user override preservation, new IDs on edits, complete unsaved invalid-copy repair, transactional reseed failure, presentation setting types, offline SHA256 resume, interrupted range continuation and stale-range restart. These are storage/service/acquisition checks, separate from native final deck legality and real frontend interaction tests.
