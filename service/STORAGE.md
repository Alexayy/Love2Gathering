# Storage, cleanup and image downloads

## Database and image-cache locations

`service/paths.py` resolves the data directory in this order:

1. `LOVE2GATHERING_DATA_DIR`, when explicitly set.
2. The active database directory saved by Settings.
3. `XDG_DATA_HOME/love2gathering`, when explicitly set.
4. An existing `.local/share/love2gathering/app.sqlite` at the nearest mounted-drive ancestor of the project.
5. `$HOME/.local/share/love2gathering`.

The launcher exports that result for the catalog, native replay recorder and room host. Standalone catalog/downloader commands use the same resolver; their explicit `--data-dir` takes precedence. Merely launching does not copy, remove or merge an older home store. Settings Storage and `/health.storage.dataDirectory` show the actual destination. The copied home directory remains a separate backup.

`app.sqlite` is authoritative for saves and replay metadata/events. A separate cache stores authoritative image BLOBs in **`images.sqlite`**, with JPEG folders as optional export mirrors. New installations use `DATA/cache/images.sqlite`. An existing combined `app.sqlite` stays combined until an explicit location change; it is never silently split at startup. The cache resolver uses `LOVE2GATHERING_CACHE_DIR`, a matching saved cache location, then the database's persisted cache reference. Missing persisted database/cache files stop startup with a reconnect-drive explanation rather than creating an empty replacement.

The generated card index in `service/data/catalog.sqlite` is separate. `replay-outbox.sqlite` contains native delivery work and is never purged as a cache. Source JSONL, bundled decks and external image-library paths are outside cleanup scope.

### Prepare a location change

Open **Settings → Storage → Locations**. Type or browse the database and image-cache folders, then **Check locations**. The review shows copies, temporary space and free space on each affected drive. **Prepare and use after restart** opens a confirmation before any copies begin. Image BLOBs are copied in bounded batches into the selected `images.sqlite`; decks, profiles, layouts, history and recordings remain in `app.sqlite`. Both databases retain WAL, busy-timeout and full-synchronous behavior. Image-cache ownership is tied to the saves database, preventing accidental use of another library's cache.

Preparation pauses writes and new matches. Active/pending native recordings, a downloader or maintenance job must finish first. Other catalog writers are fenced, and native outbox writes use a coordinated retirement marker. The current store, native delivery state and staged copies are checked again at activation. A changed source or a foreign file that appeared at the destination causes activation to fail without replacing it.

When copies are ready, close the client and launch it again with **`run.sh`**. The launcher activates verified copies before starting any writers. **Cancel location change** works during preparation or while awaiting restart. It restores the current store and removes only this operation's staged copies. Originals are retained as backups, including `.before-…` backups for files replaced in the same folder. Consequently, changing locations alone does **not** reclaim the original copy's disk space.

`storage-paths.json` under `${XDG_CONFIG_HOME:-$HOME/.config}/love2gathering` records the active/prepared locations; `LOVE2GATHERING_CONFIG_DIR` overrides that directory for tests. Explicit data/cache environment overrides take precedence and are reported in Settings. Do not point a second catalog at another installation's pending location change. Standalone services should be stopped before activation; use the launcher to finish a prepared change.

## Cleanup

Settings → Storage → Cleanup asynchronously scans counts and sizes. Successful totals stay cached until **Refresh usage**, completed maintenance or a relevant download update; navbar polling does not repeatedly rescan a large HDD cache. Purge buttons open a confirmation with the selected category's consequences. No cleanup runs on startup.

| Category | Removes | Preserves |
| --- | --- | --- |
| Full-card scans | Cached full-card JPEG BLOBs, including normal/large scans, and managed full-card exports | Cropped art, decks, profiles, settings and source metadata |
| Cropped artwork | Cached `art_crop` BLOBs and managed cropped-art exports | Full-card scans and saved avatar/playmat references; those references may show a missing-image placeholder |
| Replays | Finished playback timelines and their events | Match-history summaries, active recordings and native outbox work |
| Duplicate exports | Managed `image-library` JPEG copies whose bytes match an authoritative cached SQL image | SQL images, unique/changed exports, legacy backup directories and external mirrors |

The displayed duplicate estimate is an upper bound based on matching keys/sizes. Actual deletion compares bytes. Symlinks and unrecognized filenames are not followed. Original legacy backups remain untouched. Import barriers prevent retained legacy/external files from silently repopulating an explicitly purged image category. A deliberate later download can cache that category again.

Replay purge tombstones prevent delayed retries from recreating a deleted timeline. History keeps participants, decks and native outcomes, but a purged match no longer has a playback recording. A replay with pending native events, unfinished delivery or active recording is protected. A fully acknowledged terminal outbox row is safe even when its engine process remains alive.

Deleting SQL rows makes pages **reusable inside the database**; it does not promise an immediate smaller file. Duplicate-export cleanup returns filesystem space directly. **Compact database** is a separate explicit VACUUM operation after cleanup, covering both saves and a separate image database. It needs temporary free space on each affected drive (the interface displays the conservative requirement), and refuses active/pending recording. During exclusive maintenance ordinary storage access may briefly report busy; health and progress remain available. Duplicate-export-only cleanup permits ordinary SQL readers.

Purges and compaction exclude image jobs through cross-process locks. Compaction uses a bounded owned child process and a temporary directory on the data drive. Closing the catalog cancels owned maintenance and stops that child. A cancelled purge may already have removed some selected items; other categories remain intact. Do not use cleanup tests against a user's real store.

## Scan before downloading

Settings → Storage → Downloads selects full cards, art crops or both, and normal/large full scans. **Scan download size** streams the configured local JSONL/JSONL.GZ into a persistent SQL work plan. It does not make Scryfall/CDN requests. The plan retains exact printing/face/kind identity, including extended-art printings and multi-face cards. An existing large scan can satisfy the same printing/face's normal scan.

The result distinguishes total image identities, cached identities, missing identities and unique network requests. Identical source URLs can be fetched once while retaining each printing's cache entry. Byte estimates use a bounded sample of up to 512 existing cached images for each kind, with labeled conservative defaults when there is no sample. A range communicates uncertainty: remote image sizes are unknown until fetched. Extra SQL/mirror storage and reusable SQL pages are shown separately from network bytes. No mass HEAD requests are used to estimate a library. Sampling and final sizing use read-only transactions after short plan writes, allowing replay/deck/settings writes to continue during an estimate.

**Start download** is explicit. Progress, downloaded count/bytes and transfer speed appear in a small clickable navbar ribbon; during gameplay a thin toolbar indicator opens the same controls. **Pause**, **Resume** and **Cancel** keep committed images. Restarting the catalog pauses interrupted work and does not automatically resume network access. A second client can inspect/control the shared job. A source change requires a new scan; purging images invalidates an older plan.

Managed downloads default to **SQLite only**, avoiding a second JPEG copy. Optional mirror export writes separate `full-cards` and `art-crops` files after SQL commits. The standalone `scripts/download-card-images.py` retains its export default; use `--sql-only` to avoid duplication. Existing mirrors can repair SQL without another request when explicitly included in a plan.

Requests retain the downloader's pacing, bounded JPEG/provenance checks and retries. Bulk work checks both database and cache drives and pauses before crossing the 3 GiB free-space reserve. A few explicit selected-image downloads use their smaller separately documented reserve. A download failure or pause does not invalidate already committed images. The app still uses local-only foreground image reads by default.

## Local API

Catalog API 11 includes these controls, the six current card-back styles, exact card editions and grouped per-token artwork choices. All mutation bodies require a direct local JSON request without browser-origin headers. Only the location routes accept validated absolute directory paths; cleanup/download routes cannot choose arbitrary filesystem paths.

| Request | Body / behavior |
| --- | --- |
| `GET /storage/status?refresh=1` | Start/refresh asynchronous usage statistics; return current operation and cached statistics promptly |
| `POST /storage/purge` | `{ "categories": ["full_cards", "art_crops", "replays", "export_duplicates"] }`; select only desired categories |
| `POST /storage/compact` | `{}` |
| `GET /downloads/status` | Durable job state, plan estimates, validity, progress, speed and free space |
| `POST /downloads/scan` | `{ "fullSize": "normal", "kinds": ["normal", "art_crop"], "mirrors": false }` |
| `POST /downloads/control` | `{ "command": "start" }`; also `pause`, `resume`, `cancel` |
| `GET /storage/locations` | Active/configured paths, explicit overrides and operation/restart state |
| `POST /storage/locations/validate` | `{ "databaseDirectory": "/…", "cacheDirectory": "/…" }`; validate and estimate without copying |
| `POST /storage/locations` | The same two fields; prepare verified copies and require launcher restart |
| `POST /storage/locations/cancel` | `{}`; cancel this installation's running or prepared change |

The frontend fences stale status responses and clears affected decoded images/replay views after confirmed purge. A fast operation that completes before the next poll still triggers invalidation. New image commits retry missing artwork without needlessly discarding ready decoded textures.

## Verification scope

`service/tests/test_paths.py` covers destination precedence without home writes. `test_maintenance.py` covers scoped purges, preserved history/outboxes, mirror barriers, lock exclusions and real temporary SQLite shrink/reopen. `test_downloads.py` covers streamed plans, estimates, pacing/control recovery, URL/face identity, reserve protection and plan invalidation. `test_storage_http.py` exercises the actual local routes against isolated SQL and a bounded fake image fetcher. These tests never purge or bulk-download into the user's cache.

`tests/storage_model.lua` checks async request fencing and UI invalidation. `tests/storage_ui.sh` drives actual LÖVE/Slab controls against an explicitly synthetic async service ledger; its captures verify layout and input, not Internet transfer or native gameplay. Broader service/model checks cover existing migration, deck/profile and replay behavior independently.

`test_storage_locations.py` and `test_storage_locations_http.py` use temporary real SQLite stores for preparation, split-image reads, cancellation, atomic activation/recovery, cross-writer fences and destination ownership. `tests/storage_locations_ui.sh` drives actual text input, folder picker, validation and confirmations against an isolated real catalog. `ReplayRelocationFixture` separately verifies native JDBC retirement and crash recovery. None relocates the user's actual library.
