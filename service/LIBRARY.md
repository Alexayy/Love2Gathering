# Local images, imports, tokens and history

These features use catalog API **11**; artwork choices reuse existing deck JSON and token-preference storage. A future launch must choose a compatible service rather than reusing an old handler. Index rebuilding streams the configured JSONL, preserving the source, user SQLite saves and running matches.

## Local image identity

Configured SQL image storage remains authoritative: `images.sqlite` for a split cache, or `app.sqlite` for an existing combined store. Requests first try the exact printing/face/kind BLOB, then the same printing's `large` scan for a missing `normal` image. Runtime `/art/<id>` may reuse the same oracle/face/kind from another printing; `/cards/by-name` prefers an available cached catalog printing and returns its **actual printing metadata**. Explicit `printing=` card lookups retain their selection; `exact=1` disables cross-printing aliases on `/art`. See [independent database/cache locations](STORAGE.md).

`/gallery/art/<printing>` always stays on that printing/face, including legacy keys. A different printing's image cannot satisfy a Gallery credit. Full-card scans and art crops never substitute for each other. Aliases are served without rewriting the original cache key/source metadata. `X-Love2Gathering-Art-Key` identifies the served cache entry.

After SQL lookup fails, configured mirrors are checked: old `art/` and `image-library/full-cards/` or `image-library/art-crops/`. `LOVE2GATHERING_IMAGE_LIBRARY` selects another mirror root. Mirrors are imported with `INSERT OR IGNORE`, preserving an image another writer committed meanwhile. Request parameters cannot select filesystem paths. **Use local artwork only** defaults to true: a miss returns HTTP 404 with `cachedMiss:true`, allowing the authorized background downloader to fill the cache without foreground Scryfall/API/CDN requests. The user's explicit opt-in can allow downloading missing images; `network=0` always blocks it and `network=1` explicitly permits a bounded request. Existing entitled cache hits never require network access.

API7 adds `GET /art/cache-info` and exact gallery `art_cached` flags. The UI distinguishes pending, unavailable metadata, missing cache entries, errors and ready images; a failed local lookup is not a permanent Loading label. Runtime aliases preserve Oracle/face/kind. Gallery and Profile remain exact, preserving their displayed artist credits even when another printing is locally available. `app/artwork.lua` implements shared transport/status handling; the base Model loader delegates to it before Library installs its native-token wrapper.

**Download avatar**, **Download playmat** and Gallery's **Download artwork** are explicit selected-image actions. `POST /art/download` accepts one exact `{printingId,face,kind}` from the local catalog. It checks SQL first, downloads at most one bounded JPEG and retains a 64 MiB reserve plus SQLite write headroom. It does not change the local-only preference. The bulk downloader's separate 3 GiB pause guard does not prevent these small deliberate downloads when enough space remains. Full-card and crop entries stay separate; exported mirror folders are not deleted or relabelled.

## Import preview and save

`POST /imports/preview` accepts `{text,format,name?}` or `{url,format,name?}` and returns `{deck,validation,warnings,excluded,source,printingSelections,saved:false}`. It never saves. Only explicit Save invokes existing `POST /decks`. Snapshot checks still distinguish allowed unfinished drafts from illegal cards/copies/commanders/identities; XMage performs final validation at match startup.

Supported exports include quantity/plain lists, `1x`, Arena headers, `SB:`/commander prefixes, Archidekt category/foil markers, set/collector suffixes, common CSV columns, Cockatrice `.cod`, and JSON deck/Archidekt/Moxfield boards. Main/sideboard/commander quantities are retained. Maybeboard/token categories are shown separately with a warning. `printingSelections` persists independently of card quantities. Numeric-only MTGO XML needs a named text export; names are not invented from unknown numeric IDs.

Exports are bounded to **1 MiB and 4,000 lines**, with existing 300 entries per zone and 250 copies per stored entry. Dropped TXT/DEC/COD/CSV/JSON files are read within those bounds by LÖVE; the service accepts content, never arbitrary local paths.

URL retrieval accepts HTTPS Archidekt, Moxfield and MTGGoldfish public deck URLs only, canonicalizes to their export/API host, rejects credentials/unexpected ports/query data/private-address resolution, and bounds redirects, time and bytes. It sends an identifying User-Agent and accepts no authentication cookies. A provider's login/challenge/access refusal produces a visible text-export fallback; there is no bypass or promise that third-party endpoints remain available.

Primary sources reviewed **2026-11-14**: [Archidekt FAQ](https://archidekt.com/faq), its [official curated precons](https://archidekt.com/commander-precons), [Moxfield Help](https://moxfield.com/help) and its served frontend's API host, and [MTGGoldfish's own Arena export](https://www.mtggoldfish.com/deck/arena_download/7502486). The live test fetched Archidekt's own `/api/decks/27859380/` and retained all 100 cards/categories. Goldfish refused this session's automated request; its text export remains supported. No third-party scraping/authentication service is used.

## Card editions and alternate artwork

Classic deck rows and the card preview offer an artwork icon; Simplified deck cards expose the same icon. The modal is limited to that card's English, same-Oracle printings. Search accepts edition names/codes, collector numbers, release years and artists; the set dropdown and extended-art/borderless/showcase filters narrow the paged grid. The highlighted tile is the staged edition. **Apply edition** changes every copy of that named card in the chosen deck zone, including basic lands and commanders; **Default art** removes the override. Cancel/Escape does not modify the deck. Save uses the ordinary deck save/fork operation.

`GET /printings?name=&q=&set=&variant=all&limit=12&offset=0` returns `{name,oracleId,items,sets,total,limit,offset}`. Pages allow 1–60 items. Variants are `all`, `extended`, `borderless`, `showcase`; the All/Set views include other treatments and full-art lands without guessing their treatment from a name. Metadata reads use the existing streamed catalog index and never load the complete JSONL into Lua.

`deck.printingSelections` persists `{name,zone,count,printingId,set?,collectorNumber?}` alongside the unchanged named card entries. Before saving, the service validates that the exact printing belongs to that card's Oracle identity, the zone contains it and artwork counts do not exceed card counts. Saved template forks, imports and commanders preserve the same field; unresolved imported set/collector references remain import notes. Catalog validation is separate from XMage's final construction validation.

Explicit thumbnails and selected runtime scans request `exact=1`; a missing selected printing remains a placeholder rather than displaying another illustrator's cached art. The frontend has separate exact cache identities, four concurrent bounded metadata lookups and stale opening/search/editor/revision guards. Picker browsing does not download images.

The bridge adds only `selectedPrintingId` to each entitled visible card. Opposing humans see a revealed card owner's selected art, and recorded projections retain it. Hidden cards never expose this field or a complete deck artwork list. Rendering overlays image metadata while preserving native object IDs, current P/T, counters, rules and engine legality. The normal picker applies one edition to all copies in a zone. Imported mixed-edition lists retain their quantities in storage, but runtime matching uses stable per-object weighted artwork selection by card name across the source deck; it does not guarantee an exact physical distribution or distinguish sideboard copies of the same name.

`service/tests/test_card_printings.py` covers bounded exact pages, validation, persistence and exact-cache misses. Its headless LÖVE queue test runs actual API workers against its own temporary HTTP/SQL service: printing quantities are synchronized on the staged validation candidate before adding/removing copies, with no mutation of the live editor until acceptance. `tests/card_printings_model.lua` covers staging, stale requests, editor routing, format/revision fences and native-value preservation. `tests/card_printings_ui.sh` requires an explicit API11 catalog with real Forest THB and Rin and Seri cached scans under `/tmp`; it creates/removes only its named fixture deck and exercises actual main/Slab input, set filtering, modal cancellation, saves and reopened image identities. `scripts/test-card-printings-native.sh` checks visible/hidden two-human native projections against the packaged bridge, separately from GUI presentation fixtures.

## Token artwork

Streaming indexing retains real token/emblem printing faces and `all_parts` relationships from the [official Scryfall card schema](https://scryfall.com/docs/api/cards). The token page shows one tile per token family actually referenced by the saved deck, with its current mode, active image and selected count. It does not show the entire token catalog as an undifferentiated list. Distinct rules, base P/T, colors and types remain separate families even when they share a name such as Rat. Artwork variants can share a family across Oracle IDs or double-faced pairings; edition and artist do not define the family.

Open a tile to stage choices in a paged image grid. **Default** uses a linked printing, **Manual** picks one exact illustration, **Random selected** samples only the outlined selected cards, and **Random all** samples every matching illustration in the catalog. Popup Apply adopts the staged choice; Cancel/Escape preserves it. **Save token artwork** persists the deck's family overrides. The main tile shows the active illustration/mode, and the popup marks eligible images with an outline and Active label. Missing local scans remain placeholders; the picker does not trigger image downloads or substitute another illustrator's printing.

Removing a token maker from a saved deck hides its token family. On the next artwork save, an unchanged previously saved override for that removed family is pruned. A newly added or modified unrelated override is rejected. The client adopts the normalized save response only when no newer artwork edits have been made.

| Route | Contract |
| --- | --- |
| `GET /tokens?deckId=&q=&offset=&limit=` | Up to 60 matching printing/face items; existing flat API remains supported. |
| `GET /tokens?groups=1&deckId=` | Paged related family tiles: `tokenIdentity`, default/active card, active IDs, mode, active count and complete variant count. |
| `GET /tokens?deckId=&identity=&q=&offset=&limit=` | Paged variants of one related family; search accepts name, set and artist. |
| `GET /decks/<id>/token-art` | Legacy `{mode,selected}` plus optional `overrides` keyed by token family. |
| `PUT /decks/<id>/token-art` | `{mode,selected,overrides?:{tokenIdentity:{mode,selected}}}`. Modes are `default`, `selected` (Manual), `randomSelected`, `randomAll`. At most 100 related families and 500 selected exact token-image IDs across overrides. |
| `POST /tokens/resolve` | `{deckId?,token:{name,type_line?,power?,toughness?,colors?,printing?},seed?}` returns `{card,mode}`; null card means unknown. |

The existing `token_preferences` SQL payload stores overrides, so older preferences remain readable without a destructive migration. Manual mode requires exactly one illustration; random-selected requires at least one. An override must belong to a token actually referenced by the deck, and every selected image must match that family's identity. Different token families never join a random pool. The source deck's quantities, commanders, cover and printing selections are not changed. If a later deck edit removes a token maker, the next artwork Save prunes only its unchanged stored family override; new or edited unrelated family overrides remain validation errors.

Resolution matches the native original name/type/base P/T/colors; `token.printing` supplies that identity when live values have changed. A stable native object ID seeds random choice to avoid art flicker. A legacy preference without a matching selected variant falls back to a matching default instead of blanking the token. Artwork never changes native IDs, live stats, abilities or legality. The frontend retains four concurrent resolutions, a bounded 128-entry cache, retry bounds and opening/search/save-revision fences. Practice uses its active deck; constructed rooms use the seat's actual deck; drafts do not inherit unrelated practice choices.

`GET /decks` also appends presentation-only `colorIdentity:[W,U,B,R,G]` in canonical order, computed from the main/commander catalog union when the index is ready. It does not persist derived colors or modify quantities.

## Match history

`GET /history?limit=&offset=` derives up to 60 summaries from SQLite recording metadata and latest frames: names, format, per-seat deck summaries, timestamps, recording ID and `win/loss/draw/running/aborted/failed/unknown`. Native terminal results/flags establish completed outcomes. Interrupted recordings never become wins/losses; old records without evidence remain unknown. There is **no history winner-write endpoint**.

Native metadata provides truthful `{id,name,format}` deck summaries. Empty original IDs stay empty. Room recording retains only the host perspective and excludes opponent compositions. History opens existing read-only playback.

## Frontend hooks and verification

Install `require('app.library').install(Model)`, call `updateLibrary(dt)` and delegate pages to `LibraryUI.import/history/tokens`. Entry methods are `showImport(text?)`, `showHistory()`, `showTokenSettings(deckId)` and `importDeckFile(loveFile)`. Reopening/edited input/refresh identities fence stale callbacks.

`tests/library_model.lua` verifies mocked transport contracts. `tests/library_ui.sh` exercises actual themed Slab, multiline paste/readable pixels and explicit preview/save/token/history controls with synthetic service results. `service/tests/test_library.py` uses isolated synthetic metadata and SQLite for alias/face/kind safety, strict Gallery credits, mirrors, parser/URL bounds, preferences and history. `tests/library_live.py` requires explicit `/tmp` storage and checks real public Archidekt import, genuine token JPEGs, network-disabled HTTP reuse in its own ephemeral service, and history from actual completed engine recordings. It never injects a winner.

## Explicit cleanup and managed downloads

Settings Storage separates **Cleanup** and **Downloads**. Managed image plans stream the configured source into SQL, estimate missing bytes from cached samples/fallback ranges and request explicit Start/Resume. They default to SQL-only images; optional exports and the standalone CLI can retain separate JPEG mirrors. The navbar shows bounded background progress without covering native choices.

Image purges clear only selected full-card/art categories and managed mirror files; retained legacy backups cannot silently reimport a purged category. Replay purge preserves native match-history summaries and protects active/pending delivery. Duplicate-export cleanup verifies equality against SQL before deleting a file. SQL page reuse and actual disk compaction are separate. See [STORAGE.md](STORAGE.md) for limits and recovery.
