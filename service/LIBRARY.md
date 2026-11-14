# Local images, imports, tokens and history

These features use catalog API **5** and generated schema **7**. A future launch must choose a compatible service rather than reusing an old handler. Index rebuilding streams the configured JSONL, preserving the source, user SQLite saves and running matches.

## Local image identity

`app.sqlite` remains authoritative. Requests first try the exact printing/face/kind BLOB, then the same printing's `large` scan for a missing `normal` image. Runtime `/art/<id>` may reuse the same oracle/face/kind from another printing; `/cards/by-name` prefers an available cached catalog printing and returns its **actual printing metadata**. Explicit `printing=` card lookups retain their selection; `exact=1` disables cross-printing aliases on `/art`.

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

## Token artwork

Streaming indexing retains real token/emblem printing faces and `all_parts` relationships from the [official Scryfall card schema](https://scryfall.com/docs/api/cards), following its [image documentation](https://scryfall.com/docs/api/images). Deck token browsing includes variants of identities explicitly referenced by the deck's cards. Missing relationships/images remain unknown.

| Route | Contract |
| --- | --- |
| `GET /tokens?deckId=&q=&offset=&limit=` | Up to 60 printing/face items, total and preferences; omit deckId to search all tokens. |
| `GET /decks/<id>/token-art` | `{mode,selected}`, independent of cards/covers. |
| `PUT /decks/<id>/token-art` | Validated `default`, `randomSelected` or `randomAll` and up to 500 actual image IDs. |
| `POST /tokens/resolve` | `{deckId?,token:{name,type_line?,power?,toughness?,colors?,printing?},seed?}` returns `{card,mode}`; null card means unknown. |

Resolution matches native name/type/base power/toughness/colors; `token.printing` supplies original identity when live values changed. Random modes choose only matching variants. The native object ID is a stable seed, avoiding illustration flicker. Random selected falls back to a default matching image when a particular token has no selected variant. No known metadata means no guessed image. Artwork never changes native object IDs, live stats, abilities or legal actions.

The frontend resolves at most four tokens concurrently, retains at most 128 entries and bounds error retries. Practice uses its active deck; constructed rooms use their own room deck; drafts use defaults instead of unrelated practice preferences.

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
