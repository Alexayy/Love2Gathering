# Local data service

Run `python3 service/server.py --port 17370 --data-dir PATH`. The launcher and standalone catalog use the same resolver in `paths.py`: explicit application override, XDG override, an existing store on the project's mounted drive, then the home fallback. The service listens on loopback by default and reports **API version 8** at `/health`. Version 8 adds guarded storage maintenance, streamed image-download planning and persistent background progress. Exact artwork cache status, normalized gallery search and explicit selected-image downloads remain available. Starter/preconstructed browsing, owned copies, profiles, imports, token preferences and history remain available. The generated card index stays at schema 7, so this API change needs no metadata rebuild.

## Local card indexing

The first launch streams the bundled JSONL or JSONL.GZ into a separate generated SQLite index. Installed packages keep this index under the configured data directory's `catalog/` folder; later launches reuse a complete index when the source size, modification time and schema still match. Metadata and user saves remain untouched.

`GET /health` reports `index.phase`: `waiting` for another instance's build lock, `checking` for an existing index, `reading` for source import, `indexes` for search preparation, then `ready` or `error`. Reading reports source `lines`, deduplicated English `cards`, `bytesRead`, `totalBytes` and elapsed `seconds` at approximately half-second intervals, including translations and non-card records. Byte counts refer to the compressed file for gzip sources, so the displayed read percentage is separate from final search preparation. That phase reports `indexesDone` / `indexesTotal` and continues its elapsed-time heartbeat. A zero English-card count therefore does not hide input progress.

Search indexes are bulk-built after import using a bounded 32 MiB SQLite cache. Uniqueness constraints remain active throughout import, and the completed schema remains version 7, preserving existing indexes without a forced rebuild. Failed imports, changed sources and failed search preparation leave the previous complete catalog in place; only a fully prepared replacement is published.

The startup screen shows elapsed seconds while waiting for another instance or preparing search, so a slow single-index operation remains visibly active. [The indexing report](../tests/catalog-indexing-report.json) records a full local compressed-source HTTP run, previous-code comparison, source preservation and all 34 added XMage names resolving through the ready catalog, including a front-face alias. Its host timings are separate from Fedora VM or Flatpak runtime acceptance.

## SQLite storage and migration

The user database is **`PATH/app.sqlite`**. It contains decks, bundled-deck seeds, deletion tombstones, settings, UI layout, token artwork preferences, artwork JPEG blobs and metadata, replay metadata, and immutable replay events. WAL mode, a 30-second busy timeout and `synchronous=FULL` support concurrent local services. Writes use transactions. The generated card index remains separate in `service/data/catalog.sqlite`; the configured source JSONL remains unchanged.

On first use of a user directory, valid `decks/*.json`, `settings.json` and `hidden-decks.json` are imported in one transaction. Malformed entries are isolated and reported in `health.storage.migrationIssues`. A committed migration marker prevents stale JSON from being imported after a later SQLite edit or deletion. Existing JPG caches are imported eagerly in committed batches of 16, with a completion marker and safe restart behavior. Legacy artwork keys are also resolved from SQLite; old files added later can be imported on first access.

**Original JSON and JPG files remain untouched as migration backups.** New user state and artwork are written to SQLite. Bundled deck JSON remains distribution input: its records are seeded into SQLite, while user overrides and hidden-deck selections survive reseeding. Legacy decks above the current 250-copy transport limit are preserved during import; new editor writes retain that limit independently of printed card copy rules.

`GET /health` includes `storage.dataDirectory`, the resolved absolute data directory, plus the database name, schema version and migration report. `catalogSource` is the resolved absolute configured metadata path, including when that file is missing. The launcher uses the directory and any explicit source override to avoid reusing a service belonging to different storage or metadata. `userStore` aliases the same health object for compatibility.

## API

| Endpoint | Behavior |
| --- | --- |
| `GET /cards?q=&format=&color=&type=&set=&sort=&limit=&offset=` | Paginated catalog search; sort is `name`, `color` or `set`. |
| `GET /cards/<oracle-id>` or `/cards/by-name?name=` | Card details; face names resolve to their full oracle card and requested face. |
| `GET /sets?format=` | Set names, codes and distinct-card counts across printings. |
| `GET /art/<oracle-id>?printing=&face=&kind=&exact=&network=` | Local JPEG; kind is `normal`, `large` or `art_crop`. Missing images stay offline by default; `exact=1` prevents cross-printing aliases and `network=0` always prevents downloads. |
| `GET /gallery?q=&artist=&set=&variant=&lang=&limit=&offset=` | Per-printing, per-image-face art/credits; variants `all`, `extended`, `borderless`, `showcase`; default English, `lang=all` includes other languages; maximum page size 60. |
| `GET /gallery/art/<printing-id>?face=&kind=art_crop` | Correct face's JPEG, including non-English printings, using the same authoritative SQLite artwork cache. |
| `GET /storage/status?refresh=1` | Asynchronous cache/replay/disk usage and maintenance progress; no destructive side effects. |
| `POST /storage/purge`, `POST /storage/compact` | Explicit local JSON controls; category preview/confirmation belongs to the client. No caller-selected paths. |
| `GET /downloads/status`, `POST /downloads/scan`, `POST /downloads/control` | Persisted scan/start/pause/resume/cancel controls and navbar progress. A scan does not fetch images. |
| `GET /art/cache-info` | Cache image-kind counts and the matching data directory's bulk downloader status; reads covering keys, without scanning image BLOBs. |
| `POST /art/download` | Explicitly fetch one exact `{printingId,face,kind}`; reuse its cache first, preserve local-only preferences and retain a small disk-space reserve. |
| `GET /decks?origin=`, `POST /decks` | List or save decks; `origin=user` selects My Decks, `origin=starter` selects original bundled aliases. Default listing remains lobby-compatible. A ready catalog appends presentation-only `colorIdentity`. |
| `GET`, `PUT`, `DELETE /decks/<id>` | Read, save or hide/delete a deck. |
| `GET /precons?category=&q=&format=&set=&type=&limit=&offset=`, `GET /precons/stats` | Bounded immutable historical product summaries, selector data and provenance; default deck products exclude standalone collections. |
| `GET /precons/<id>`, `POST /decks/<id>/fork` | Inspect an archived list or validate an independent owned copy; invalid copies return complete unsaved repair data. |
| `GET`, `PUT /profile` | Persist a bounded player name and exact catalog avatar/playmat references, without arbitrary image URLs or life settings. |
| `POST /decks/validate` | Construction checks; returns `saveAllowed`, `playable`, `draft`, named errors, warnings and counts. |
| `POST /imports/preview` | Bounded text/file-content or public-URL preview; no save. Explicit saving still uses `POST /decks`. |
| `GET /tokens?deckId=&q=&limit=&offset=` | Actual indexed token printing/face images related to a deck, or all token images when deckId is omitted. |
| `GET`, `PUT /decks/<id>/token-art` | Independent validated default/random-selected/random-all artwork preferences. |
| `POST /tokens/resolve` | Match native token descriptors to known printing/face images, preserving native identity and live stats. |
| `GET`, `PUT /settings` | Typed preferences; partial writes update the supplied keys transactionally. |
| `GET`, `PUT /ui-layout` | Read or atomically replace layout, including panel/replay preferences and `matchPrefs.logVerbose`. |
| `GET /history?limit=&offset=` | Read-only match/deck/outcome summaries from saved native recording metadata and terminal frames. |
| `POST /replays` | Create recording metadata; a supplied ID and identical metadata make retries idempotent. |
| `GET /replays?offset=&limit=` | Recording list and total; maximum page size 200. |
| `GET /replays/<id>` | Metadata, status, frame/action/log/error counts and last durable sequence. |
| `POST /replays/<id>/events` | Atomically append `{ "events": [...] }`, up to 2,000 events. |
| `GET /replays/<id>/events?offset=&limit=` | All events ordered by sequence. |
| `GET /replays/<id>/frames?offset=&limit=` | Frame events only; maximum page size 500. |
| `POST /replays/<id>/finish` | Finish as `completed`, `failed` or `aborted`, optionally including result/error details. |
| `DELETE /replays/<id>` | Delete a recording and its events transactionally. |

Request bodies are capped at 8 MiB. Replay metadata is capped at 1 MiB and UI layout at 256 KiB. IDs are constrained identifiers, not filesystem paths.

See [PRECONS.md](PRECONS.md) for the acquired 3,154-record MTGJSON snapshot, 1,183 deck products, 611 packets, preserved source licenses, historical-format labels and explicit resumable refresh. Editing an original Starter or preconstructed template forks a new user ID; clients must adopt the returned ID. Historical products are never presented as already validated against the current card snapshot or installed XMage.

[Player profile documentation](../docs/PROFILES.md) covers exact avatar/playmat references, public room propagation and the native-life boundary.

## Artwork metadata and offline images

Generated catalog schema 7 retains a separately indexed gallery row for every printing and face with an `art_crop` image. Oracle-card search retains its existing English deduplication. Transform/modal faces carry their own image and illustrator credits; split/adventure cards with one shared scan produce one gallery image. Selected printing details retain that printing's artist, release date and frame effects. Extended art comes from Scryfall's `extendedart` frame effect; borderless comes from its `border_color`, without inferring variants from card names.

Gallery responses contain `items`, `total`, `limit` and `offset`. Items include `id`, `printing_id`, `oracle_id`, `face`, `name`, `set`, `set_name`, `artist`, `artist_ids`, `year`, `released_at`, `lang`, `image_uris`, `frame_effects`, `border_color`, `variants` and `artist_links`. The displayed year is the printing's release year, rather than a guessed painting date. Artwork is fetched in bounded pages; the frontend retains at most 60 decoded gallery images.

Each item also has `art_cached` for that exact printing/face's cropped illustration. Search normalizes `&` to `and`, requires word-prefix matches for every query word and prefers card-name results over broader credits/set matches. A query such as `Rin & Seri` returns the actual Rin and Seri illustrations, rather than matching `rin` inside Meandering River and `seri` inside Series. No full-index migration is needed. Profile/Gallery clear outdated results immediately when a query changes.

`service/artists.py` is a small reviewed registry, checked on **2026-11-13**, rather than a claim that every illustrator has been researched. Its initial entries cover the original five bundled Commander illustrations: Karl Kopinski (Krenko, M13), Ryan Pancoast (Ayara, ELD), Eric Deschamps (Giada, SNC), and Svetlin Velinov (Goreclaw, M19; Talrand, M13). Other reviewed entries cover Kai Carpenter, Lie Setiawan, Jason Felix, Scott M. Fischer and Chase Stone. Each link has its exact official destination, source and check date; unknown artists return an empty array. Shop/service links are included only where published by the artist. Gallery opens a destination only when clicked.

Credit and image fields follow the official [Scryfall card schema](https://scryfall.com/docs/api/cards), [image documentation](https://scryfall.com/docs/api/images) and [bulk data documentation](https://scryfall.com/docs/api/bulk-data). Artist provenance is retained with each registry entry, for example [Ryan Pancoast's links](https://www.ryanpancoast.com/about), [Eric Deschamps's shop](https://www.ericdeschamps.com/purchase), and [Svetlin Velinov's profile](https://www.behance.net/velinov).

Settings Storage uses SQL-only managed downloads by default; optional managed mirrors and the CLI retain separate exports. See [STORAGE.md](STORAGE.md) for download estimates, maintenance scopes, locks and recovery.

Use `scripts/download-card-images.py --help` for explicit, resumable full-card and cropped-art downloads. The CLI downloader commits JPEG BLOBs into `app.sqlite` before writing separate `full-cards/` and `art-crops/` mirrors. Pass `--sql-only` to omit those copies. An interrupted export can rebuild missing mirrors from SQLite without another download. Existing original metadata is never overwritten; `--bootstrap-metadata` requires a new destination and is the explicit way to obtain a missing bulk source. A local `.jsonl` or `.jsonl.gz` source can be selected with `--source PATH` or `LOVE2GATHERING_CATALOG_SOURCE=PATH` when starting the service. The catalog streams either format. Missing metadata leaves decks/settings/replays available and returns a clear gallery indexing error.

`--full-size large` caches high-resolution full-card scans instead of the normal-size scans. A frontend `kind=normal` request reuses an existing large JPEG for the **same printing and face** when its normal image is absent, so those downloads also work offline. The service serves that BLOB directly and preserves its large-image key/source metadata; it does not create a misleading normal-cache copy. Cropped artwork remains a separate `art_crop` entry.

**Use local artwork only** (`localArtworkOnly:true`) is the default saved setting. Cache/mirror misses return HTTP 404 with `cachedMiss:true` before any foreground download; the explicit background downloader fills those entries. A user can opt in to downloading missing images, and `network=1` explicitly permits such a request. Existing cache hits require no external request regardless of that preference. Runtime by-name lookups prefer an actual cached catalog printing and return its metadata; ordinary artwork may reuse same-oracle/face/kind cache entries. `exact=1` and Gallery requests retain exact printing/face identity and credits. Full scans never substitute for cropped art. See [LIBRARY.md](LIBRARY.md) for aliases, atomic mirror import, import preview bounds, token modes and match-history evidence.

Missing images have an explicit **not cached** state after the request finishes. Profile/Gallery let the user download the selected missing illustration, keeping its exact printing and face. This action writes its bounded JPEG to SQL, without enabling automatic foreground downloads. Existing cache hits need neither network nor extra download space. A new selected download reserves 64 MiB plus bounded SQLite/JPEG headroom; HTTP 409 with `reserveBlocked:true` explains insufficient space. This differs from the bulk supervisor's 3 GiB pause guard. Export mirrors remain intact; the downloader can later repair a missing mirror from the authoritative SQL image without fetching again.

Presentation defaults use Beleren, a Kenney pointer, Desktop resolution and Borderless mode. The version-2 preference migration changes the historical Windowed/1440×900 pair, preserving explicitly different display choices. It applies the requested Beleren defaults once; subsequent saved choices are not repeatedly reset. Typed settings also include panel opacity, theme/accent colors, automatic active-turn camera following and Classic/Simplified builder presentation. These settings do not change Magic rules.

Replay events have this shape:

```json
{"sequence":0,"type":"frame","timestamp":1770000000000,"data":{"gameId":"...","players":[]}}
```

Types are `frame`, `action`, `log` and `error`. The bridge supplies projected player-visible snapshots; this service does not read raw XMage internals. Recording happens at the engine producer rather than through frontend polling. Events are immutable: an identical sequence/content retry is accepted, while conflicting content returns HTTP 409 and rolls back the whole batch. After finishing, new events are rejected, while exact old-event retries remain safe. Partial and failed recordings retain their frames for reopening.

Frame reads return `{ "frames": [{ "sequence": 0, "type": "frame", "timestamp": 1770000000000, "data": {} }], "total": 1, "limit": 250, "offset": 0 }`. `data` is the playback snapshot. Replay metadata exposes `eventCount`, `frameCount`, `actionCount`, `logCount`, `errorCount` and `lastSequence`.

## Room-code multiplayer service

The network-facing room gateway is separate from the loopback catalog: `service/rooms.py`, preferred port **17380**. The normal launcher starts one per desktop; `scripts/run-room-server.sh` runs an owned headless host. It provides code-only private joining, independent human perspectives, completed constructed-game host rematches, native traditional/random/cube drafting and native tournament progression. See [ROOMS.md](ROOMS.md) for hosting, authenticated seat boundaries, routes and acceptance scope. Keep the catalog and engine loopback-only when exposing that gateway.

## Verification

```sh
python3 -m unittest discover -s service/tests -v
lua tests/replay_model.lua
lua tests/gallery_model.lua
lua tests/library_model.lua
tests/library_ui.sh
tests/quit_storage.sh
```

The backend suite covers migration preservation and idempotence, concurrent startup/writes, eager and lazy artwork import, deck/settings validation, replay conflict rollback and restart reopening, pagination, and HTTP responses. The quit test starts its own ephemeral-port catalog in a temporary user directory, runs the real LÖVE request workers, and verifies that a callback-generated write survives immediate quit and SQLite reopening. It does not use the running user's catalog or data directory.

Gallery tests cover printing/face credits, variants, language/artist/set filters, bounded pagination, reviewed/unknown artist links, compressed metadata, correct cached image selection and failed-rebuild preservation. `LOVE2GATHERING_CATALOG_PORT=TEST_PORT tests/gallery_ui.sh` requires a ready catalog in temporary storage and verifies actual LÖVE/Slab browsing, art-only enlargement, artist-link clicks and variant/page controls. Its URL launcher is intercepted to avoid opening a browser during acceptance; the selected verified URL is asserted. Downloader tests separately exercise retries, rate-limit handling, restart, mirror repair and source preservation without network.

The API-5 [local image, deck import, token artwork and match history guide](LIBRARY.md) documents the complete route contracts and provider limitations. `tests/library-live-report.json` separates real public Archidekt import, genuine token JPEG cache reuse and existing native outcomes from synthetic model/UI fixtures; its final offline checks instrument a separate temporary HTTP service rather than interrupting another running service.
